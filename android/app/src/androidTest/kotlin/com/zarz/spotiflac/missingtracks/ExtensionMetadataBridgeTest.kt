package com.zarz.spotiflac.missingtracks

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.spotiflac.backend.CancellationDomain
import com.spotiflac.backend.CancellationRegistry
import com.spotiflac.backend.ExtensionManager
import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ExtensionMetadataBridgeTest {
    @Test
    fun applicationMetadataRoutePreservesProviderStampingAndCancellation() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root = File(context.cacheDir, "extension-bridge-${System.nanoTime()}").apply { mkdirs() }
        val id = "example.metadata"
        try {
            val sources = File(root, "sources").apply { mkdirs() }
            val extension = File(sources, id).apply { mkdirs() }
            File(extension, "manifest.json").writeText(
                """{"name":"$id","displayName":"Example Metadata","version":"1","description":"Generic bridge fixture","type":["metadata_provider"]}""",
            )
            File(extension, "index.js").writeText("""
                function collection(id) {
                    if (id === "missing") return null;
                    return {id, name:"Album 音楽 🎵", artists:"Artist Café", total_tracks:128,
                        tracks:Array.from({length:128}, (_, i) => ({id:"track-"+i,
                            name:"歌 🎵 "+i, artists:"Artist Café", album_name:"Album 音楽 🎵",
                            provider_id:"supplied", duration_ms:123456, track_number:i+1}))};
                }
                registerExtension({getAlbum:collection,getPlaylist:collection});
            """.trimIndent())
            ExtensionManager(sources.path, File(root, "data").path, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", "1", 10000uL).use { manager ->
                manager.loadAll()
                manager.setEnabled(id, true)
                for ((kind, method) in listOf("album" to "getAlbum", "playlist" to "getPlaylist")) {
                    val legacy = JSONObject(manager.providerCall(id, method, "[\"fixture\"]", null, 10000uL))
                    val result = JSONObject(manager.getProviderMetadataJson(id, kind, "fixture", null))
                    val tracks = result.getJSONArray("track_list")
                    assertEquals(128, tracks.length())
                    assertEquals(id, tracks.getJSONObject(127).getString("provider_id"))
                    assertEquals(legacy.getJSONArray("tracks").getJSONObject(127).getString("name"), tracks.getJSONObject(127).getString("name"))
                    assertEquals("Album 音楽 🎵", result.getJSONObject("${kind}_info").getString("name"))
                    assertTrue(runCatching { manager.getProviderMetadataJson(id, kind, "missing", null) }.isFailure)
                }
                CancellationRegistry(CancellationDomain.EXTENSION_REQUEST).use { registry ->
                    registry.acquire("bridge-cancel").use { lease ->
                        registry.cancel("bridge-cancel")
                        assertTrue(runCatching { manager.getProviderMetadataJson(id, "album", "fixture", lease) }.isFailure)
                    }
                }
                assertEquals(128, JSONObject(manager.getProviderMetadataJson(id, "album", "fixture", null)).getJSONArray("track_list").length())
            }
        } finally {
            root.deleteRecursively()
        }
    }
}
