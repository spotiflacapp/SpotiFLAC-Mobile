package com.zarz.spotiflac.missingtracks

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.After
import org.junit.Before
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativeDownloadContainerTest {
    private lateinit var backend: CoreBackend
    private lateinit var backendRoot: File

    @Before
    fun initializeBackend() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        backendRoot = File(context.filesDir, "finalizer-test-${System.nanoTime()}").apply { mkdirs() }
        backend = createCoreBackend(context)
        backend.invokeApplication("initExtensionSystem", mapOf(
            "extensions_dir" to File(backendRoot, "sources").apply { mkdirs() }.path,
            "data_dir" to File(backendRoot, "data").apply { mkdirs() }.path,
            "master_key" to "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            "allowed_directories" to listOf(context.cacheDir.path),
        ))
    }

    @After
    fun closeBackend() {
        backend.invokeApplication("cleanupExtensions", emptyMap<String, Any>())
        backendRoot.deleteRecursively()
    }

    @Test
    fun selectedLibraryFilesCanBeEditedReenrichedAndExportArtworkOutsideDownloadRoot() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.filesDir, "selected-library-${System.nanoTime()}").apply { mkdirs() }
        try {
            val input = File(directory, "selected.flac")
            val fixture = NativeDownloadFinalizer.runFFmpegArguments(arrayOf(
                "-v", "error", "-f", "lavfi", "-i", "sine=frequency=997:sample_rate=48000",
                "-t", "0.5", "-c:a", "flac", input.path,
            ))
            assertTrue(fixture.second, fixture.first)
            val artwork = File(directory, "selected.png")
            val bitmap = android.graphics.Bitmap.createBitmap(4, 4, android.graphics.Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(android.graphics.Color.BLUE)
            artwork.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
            val edit = JSONObject(backend.editFileMetadata(input.path, JSONObject()
                .put("title", "Edited title").put("cover_path", artwork.path)
                .put("replaygain_track_gain", "-7.00 dB").put("replaygain_track_peak", "0.750000").toString()))
            assertTrue(edit.toString(), edit.getBoolean("success"))
            val request = JSONObject().put("file_path", input.path).put("search_online", false)
                .put("track_name", "Enriched title").put("artist_name", "Example artist")
                .put("update_fields", org.json.JSONArray(listOf("track_name")))
            val enriched = JSONObject(backend.reEnrichFile(request.toString()))
            assertTrue(enriched.toString(), enriched.getBoolean("success"))
            val metadata = JSONObject(backend.readFileMetadata(input.path, input.name))
            assertEquals("Enriched title", metadata.getString("title"))
            assertEquals("-7.00 dB", metadata.getString("replaygain_track_gain"))
            val output = File(directory, "export.png")
            backend.extractCoverToFile(input.path, output.path)
            assertTrue(output.readBytes().contentEquals(artwork.readBytes()))
            val library = JSONObject(backend.readAudioMetadata(input.path, input.name, ""))
            assertEquals("Enriched title", library.getString("trackName"))
        } finally { directory.deleteRecursively() }
    }

    @Test
    fun libraryMetadataReadsAnOpenDescriptorWithoutGrantingItsFilesystemPath() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val artwork = File(backendRoot, "selected-cover.png")
        val bitmap = android.graphics.Bitmap.createBitmap(4, 4, android.graphics.Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.GREEN)
        artwork.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
        val input = File(backendRoot, "selected-track.flac")
        val fixture = NativeDownloadFinalizer.runFFmpegArguments(arrayOf(
            "-v", "error", "-f", "lavfi", "-i", "sine=frequency=997:sample_rate=48000",
            "-i", artwork.path, "-t", "0.5", "-map", "0:a", "-map", "1:v",
            "-c:a", "flac", "-c:v", "copy", "-disposition:v", "attached_pic",
            "-metadata", "title=Document track", input.path,
        ))
        assertTrue(fixture.second, fixture.first)
        val covers = File(context.cacheDir, "descriptor-covers-${System.nanoTime()}").apply { mkdirs() }
        try {
            backend.setLibraryCoverCacheDirectory(covers.path)
            android.os.ParcelFileDescriptor.open(input, android.os.ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                val result = JSONObject(backend.readAudioMetadata(
                    "/proc/self/fd/${descriptor.fd}", input.name, "content://example/tree/music/selected-track.flac",
                ))
                assertEquals("Document track", result.getString("trackName"))
                assertEquals(48000, result.getInt("sampleRate"))
                assertFalse(result.optBoolean("metadataFromFilename"))
                val cachedCover = File(result.getString("coverPath"))
                assertEquals(covers.canonicalPath, cachedCover.parentFile!!.canonicalPath)
                assertTrue(cachedCover.readBytes().contentEquals(artwork.readBytes()))
                assertTrue(descriptor.statSize > 0)
            }
        } finally { covers.deleteRecursively() }
    }

    @Test
    fun nativeFormatsPreserveTagsLyricsAndReplayGain() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root = File(context.cacheDir, "finalizer-parity-${System.nanoTime()}").apply { mkdirs() }
        try {
            for ((extension, encoder) in listOf("mp3" to "libmp3lame", "opus" to "libopus", "flac" to "flac", "m4a" to "aac")) {
                val input = File(root, "track.$extension")
                val fixture = NativeDownloadFinalizer.runFFmpegArguments(arrayOf(
                    "-v", "error", "-f", "lavfi", "-i", "sine=frequency=997:sample_rate=48000",
                    "-t", "1.5", "-c:a", encoder, input.path,
                ))
                assertTrue(fixture.second, fixture.first)
                val request = JSONObject()
                    .put("contract_version", 1).put("item_id", "example-$extension")
                    .put("service", "example-provider").put("track_name", "Parity test")
                    .put("artist_name", "Example artist").put("album_name", "Example album")
                    .put("album_artist", "Album Artist").put("track_number", 2).put("total_tracks", 10)
                    .put("quality", "LOSSLESS").put("storage_mode", "app")
                    .put("output_ext", ".$extension").put("embed_metadata", true)
                    .put("embed_lyrics", true).put("lyrics_mode", "both")
                    .put("embed_replaygain", true).put("duration_ms", 1500)
                val result = NativeDownloadFinalizer.finalize(
                    context, "example-$extension", request.toString(), "{}",
                    JSONObject().put("success", true).put("file_path", input.path)
                        .put("file_name", input.name).put("lyrics_lrc", "[00:00.00]Example line"),
                    "{\"save_download_history\":false}",
                )
                assertTrue(result.toString(), result.getBoolean("success"))
                assertFalse(result.toString(), result.has("replaygain_warning"))
                assertEquals(1.5, result.getJSONObject("replaygain").getDouble("duration_secs"), 0.001)
                val output = File(result.getString("file_path"))
                assertEquals(extension, output.extension)
                assertEquals("[00:00.00]Example line", File(root, "track.lrc").readText())
                File(root, "track.lrc").delete()
                val probe = NativeDownloadFinalizer.runFFmpegArguments(arrayOf(
                    "-hide_banner", "-i", output.path, "-map", "0:a:0", "-f", "null", "-",
                ))
                assertTrue(probe.second, probe.first)
                val gainTag = if (extension == "opus") "r128_track_gain" else "replaygain_track_gain"
                for (tag in listOf("Parity test", "Album Artist", "Example line", gainTag)) {
                    assertTrue("$extension: missing $tag\n${probe.second}", probe.second.contains(tag, ignoreCase = true))
                }
            }
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun misnamedMp4IsTaggedAndPublishedAsM4aWithoutOverwritingExistingAudio() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root = File(context.cacheDir, "container-test-${System.nanoTime()}").apply { mkdirs() }
        try {
            val input = File(root, "track.flac")
            val existing = File(root, "track.m4a").apply { writeText("existing download") }
            val fixture = NativeDownloadFinalizer.runFFmpegArguments(arrayOf(
                "-v", "error", "-f", "lavfi", "-i", "sine=frequency=997:sample_rate=44100",
                "-t", "0.2", "-c:a", "aac", "-f", "mp4", input.path,
            ))
            assertTrue(fixture.second, fixture.first)
            assertTrue(isMP4ContainerFile(input.path))
            val request = JSONObject()
                .put("contract_version", 1).put("item_id", "example-track")
                .put("service", "example-provider").put("track_name", "Container test")
                .put("artist_name", "Example artist").put("album_name", "Example album")
                .put("quality", "LOSSLESS").put("storage_mode", "app")
                .put("output_ext", ".flac").put("embed_metadata", true)
            val result = NativeDownloadFinalizer.finalize(
                context, "example-track", request.toString(), "{}",
                JSONObject().put("success", true).put("file_path", input.path)
                    .put("file_name", input.name),
                "{\"save_download_history\":false}",
            )
            assertTrue(result.toString(), result.getBoolean("success"))
            assertTrue(result.getBoolean("native_finalized"))
            val output = File(result.getString("file_path"))
            assertEquals("m4a", output.extension)
            assertTrue(output.length() > 0)
            assertTrue(isMP4ContainerFile(output.path))
            assertFalse(input.exists())
            assertEquals("existing download", existing.readText())
            val probe = NativeDownloadFinalizer.runFFmpegArguments(arrayOf(
                "-hide_banner", "-i", output.path, "-map", "0:a:0", "-f", "null", "-",
            ))
            assertTrue(probe.second, probe.first)
            assertTrue(probe.second, probe.second.contains("Container test"))
            assertTrue(probe.second, probe.second.contains("Audio: aac"))
        } finally {
            root.deleteRecursively()
        }
    }
}
