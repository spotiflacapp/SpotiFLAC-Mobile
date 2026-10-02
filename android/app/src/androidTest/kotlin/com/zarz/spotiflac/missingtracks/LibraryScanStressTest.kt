package com.zarz.spotiflac.missingtracks

import android.graphics.Bitmap
import android.graphics.Color
import android.os.Debug
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.concurrent.thread
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LibraryScanStressTest {
    @Test
    fun scansTwoThousandTracksWithLargeEmbeddedArtwork() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("library_stress") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root = File(context.cacheDir, "scan-stress-${System.nanoTime()}").apply { mkdirs() }
        val backend = createCoreBackend(context)
        val running = AtomicBoolean(true)
        val peakNative = AtomicLong(0)
        val peakPss = AtomicLong(0)
        val sampler = thread(name = "scan-memory-sampler") {
            while (running.get()) {
                peakNative.updateAndGet { maxOf(it, Debug.getNativeHeapAllocatedSize()) }
                peakPss.updateAndGet { maxOf(it, Debug.getPss()) }
                Thread.sleep(100)
            }
        }
        try {
            backend.invokeApplication("initExtensionSystem", mapOf(
                "extensions_dir" to File(root, "sources").apply { mkdirs() }.path,
                "data_dir" to File(root, "data").apply { mkdirs() }.path,
                "master_key" to "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            ))
            val tracks = File(root, "tracks").apply { mkdirs() }
            val covers = File(root, "covers").apply { mkdirs() }
            backend.setLibraryCoverCacheDirectory(covers.path)
            val image = File(root, "cover.png")
            val bitmap = Bitmap.createBitmap(2400, 2400, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(Color.rgb(45, 100, 160))
            image.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 90, it) }
            bitmap.recycle()
            val template = File(root, "template.flac")
            val fixture = NativeDownloadFinalizer.runFFmpegArguments(arrayOf(
                "-v", "error", "-f", "lavfi", "-i", "sine=frequency=997:sample_rate=48000",
                "-i", image.path, "-t", "0.25", "-map", "0:a", "-map", "1:v",
                "-c:a", "flac", "-c:v", "copy", "-disposition:v", "attached_pic", template.path,
            ))
            assertTrue(fixture.second, fixture.first)
            val snapshot = JSONObject()
            repeat(2000) { index ->
                val album = File(tracks, "album-${index / 20}").apply { mkdirs() }
                val file = template.copyTo(File(album, "track-$index.flac"))
                snapshot.put(file.canonicalPath, file.lastModified())
            }
            val beforeNative = Debug.getNativeHeapAllocatedSize()
            peakNative.set(beforeNative)
            peakPss.set(Debug.getPss())
            val output = File(root, "scan.ndjson")
            val start = SystemClock.elapsedRealtime()
            assertEquals(2000L, backend.scanLibraryFolderToNdjsonFile(tracks.path, output.path))
            val fullMs = SystemClock.elapsedRealtime() - start
            assertEquals(2000, output.useLines { it.count() })
            assertEquals(0, JSONObject(backend.getLibraryScanProgress()).getInt("error_count"))
            val firstNative = Debug.getNativeHeapAllocatedSize()
            val repeatStart = SystemClock.elapsedRealtime()
            assertEquals(2000L, backend.scanLibraryFolderToNdjsonFile(tracks.path, output.path))
            val repeatMs = SystemClock.elapsedRealtime() - repeatStart
            val incrementalStart = SystemClock.elapsedRealtime()
            val incremental = JSONObject(backend.scanLibraryFolderIncremental(tracks.path, snapshot.toString()))
            val incrementalMs = SystemClock.elapsedRealtime() - incrementalStart
            assertEquals(2000, incremental.getInt("skippedCount"))
            assertEquals(0, incremental.getJSONArray("scanned").length())
            Log.i("LibraryScanStress", JSONObject()
                .put("tracks", 2000).put("full_ms", fullMs).put("repeat_ms", repeatMs)
                .put("incremental_ms", incrementalMs).put("before_native_bytes", beforeNative)
                .put("after_first_native_bytes", firstNative)
                .put("after_repeat_native_bytes", Debug.getNativeHeapAllocatedSize())
                .put("peak_native_bytes", peakNative.get()).put("peak_pss_kib", peakPss.get())
                .put("cover_files", covers.listFiles()?.size ?: 0).toString())
        } finally {
            running.set(false)
            sampler.join()
            backend.invokeApplication("cleanupExtensions", emptyMap<String, Any>())
            root.deleteRecursively()
        }
    }
}
