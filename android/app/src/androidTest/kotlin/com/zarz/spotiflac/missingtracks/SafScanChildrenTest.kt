package com.zarz.spotiflac.missingtracks

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.IOException
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SafScanChildrenTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val authority = "com.spotiflac.test.documents.lookup"
    private val controlUri = Uri.parse("content://$authority.control")
    private val treeUri = DocumentsContract.buildTreeDocumentUri(authority, "root")
    private val grantFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION

    private fun reset(count: Int = 0, mode: String = "normal", mimeCases: Boolean = false): DocumentFile {
        context.contentResolver.call(controlUri, "lookup.reset", null, Bundle().apply {
            putInt("count", count)
            putString("mode", mode)
            putBoolean("mimeCases", mimeCases)
            putBoolean("persistable", true)
            putString("targetPackage", context.packageName)
        })
        context.contentResolver.takePersistableUriPermission(treeUri, grantFlags)
        return requireNotNull(DocumentFile.fromTreeUri(context, treeUri))
    }

    private fun stats() = requireNotNull(context.contentResolver.call(controlUri, "lookup.stats", null, null))

    @After
    fun releaseTreeGrant() {
        if (context.contentResolver.persistedUriPermissions.any { it.uri == treeUri }) {
            context.contentResolver.releasePersistableUriPermission(treeUri, grantFlags)
        }
    }

    @Test
    fun richRowsContainFileMetadataAndTraversableChildrenWithoutNameQueries() {
        val root = reset(count = 2000)
        val children = context.listSafChildrenOrThrow(root)
        assertEquals(2002, children.size)
        assertEquals(1, stats().getInt("children"))
        assertEquals(0, stats().getInt("documents"))
        assertTrue(children.all { it.lastModified == 1234L })
        val directory = children.single { it.isDirectory }
        assertFalse(directory.isFile)
        assertEquals("nested:音楽/opaque", DocumentsContract.getDocumentId(directory.doc.uri))
        val nested = context.listSafChildrenOrThrow(directory.doc, includeLastModified = false).single()
        assertEquals("歌 🎵.flac", nested.name)
        assertTrue(nested.isFile)
        assertEquals(0L, nested.lastModified)
        assertEquals(2, stats().getInt("children"))
        assertEquals(0, stats().getInt("documents"))
        assertTrue(nested.doc.renameTo("Renamed.flac"))
        assertEquals("Renamed.flac", nested.doc.name)
    }

    @Test
    fun unknownAndEmptyMimeStayNonFilesWhileGenericMimeRemainsAFile() {
        val root = reset(mimeCases = true)
        val entries = context.listSafChildrenOrThrow(root, includeLastModified = false).associateBy { it.name }
        assertFalse(requireNotNull(entries["Null.flac"]).isFile)
        assertFalse(requireNotNull(entries["Empty.flac"]).isFile)
        assertTrue(requireNotNull(entries["Generic.flac"]).isFile)
        assertEquals("", JSONObject(context.resolveSafFile(treeUri.toString(), "", "Null.flac")).getString("uri"))
        assertEquals("", JSONObject(context.resolveSafFile(treeUri.toString(), "", "Empty.flac")).getString("uri"))
        assertTrue(JSONObject(context.resolveSafFile(treeUri.toString(), "", "Generic.flac")).getString("uri").isNotBlank())
    }

    @Test
    fun rejectedRichProjectionRetainsLegacyMetadataFallback() {
        val root = reset(mode = "throw", mimeCases = true)
        val entries = context.listSafChildrenOrThrow(root).associateBy { it.name }
        assertEquals(2, stats().getInt("children"))
        assertTrue(stats().getInt("documents") > 0)
        assertTrue(requireNotNull(entries["音楽 🎵"]).isDirectory)
        assertFalse(requireNotNull(entries["Null.flac"]).isFile)
        assertFalse(requireNotNull(entries["Empty.flac"]).isFile)
        assertTrue(requireNotNull(entries["Generic.flac"]).isFile)
        assertTrue(entries.values.all { it.lastModified == 1234L })
    }

    @Test
    fun resolverWalksNestedDirectoriesWithConstantQueryCount() {
        reset(count = 2000)
        val result = JSONObject(context.resolveSafFile(treeUri.toString(), "", "歌 🎵.flac"))
        assertEquals("song:opaque/%", DocumentsContract.getDocumentId(Uri.parse(result.getString("uri"))))
        assertEquals("音楽 🎵", result.getString("relative_dir"))
        assertEquals(3, stats().getInt("children"))
        assertEquals(0, stats().getInt("documents"))
    }

    private fun inspect(vararg names: String): JSONArray {
        val requests = JSONArray()
        for ((index, name) in names.withIndex()) {
            requests.put(JSONObject().put("key", index.toString()).put("tree_uri", treeUri.toString())
                .put("relative_dir", "").put("current_uri", "").put("file_names", JSONArray().put(name)))
        }
        return JSONObject(context.inspectSafFiles(requests.toString())).getJSONArray("results")
    }

    @Test
    fun batchInspectionFindsNestedRowsAndSeparatesMissingFromUnreadable() {
        reset(count = 2000)
        val results = inspect("歌 🎵.flac", "Missing.flac")
        assertEquals("found", results.getJSONObject(0).getString("status"))
        assertEquals("音楽 🎵", results.getJSONObject(0).getString("relative_dir"))
        assertEquals("missing", results.getJSONObject(1).getString("status"))
        assertEquals(3, stats().getInt("children"))
        // Only fixed root permission/type checks; no per-child lookups.
        assertTrue(stats().getInt("documents") < 10)

        val root = reset(mode = "all-null")
        assertThrows(IOException::class.java) { context.listSafChildrenOrThrow(root) }
        assertEquals("unknown", inspect("Missing.flac").getJSONObject(0).getString("status"))
    }
}
