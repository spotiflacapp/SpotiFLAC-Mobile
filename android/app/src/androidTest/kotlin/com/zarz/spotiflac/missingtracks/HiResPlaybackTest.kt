package com.zarz.spotiflac.missingtracks

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.plugin.common.MethodCall
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HiResPlaybackTest {
    private fun fixture(): File {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val file = File.createTempFile("dsd-pattern-", ".wv", instrumentation.targetContext.cacheDir)
        instrumentation.context.assets.open("dsd-pattern.wv").use { input ->
            file.outputStream().use { input.copyTo(it) }
        }
        return file
    }

    @Test
    fun wavPackDsdDecodesOriginalBitsAndChannelOrderForNativeAndDop() {
        val file = fixture()
        try {
            for ((encoding, slot) in listOf("dsd_be" to 4, "dsd_le" to 4, "dop" to 3, "dop" to 4)) {
                requireNotNull(DsdSource.open(file.path)).use { source ->
                    assertEquals(2822400, source.rate)
                    assertEquals(2, source.channels)
                    val group = if (encoding == "dop") 2 else 4
                    var cursor = 0
                    while (true) {
                        val data = source.readFrames(encoding, slot, 37) ?: break
                        for (frame in 0 until data.size / (slot * 2)) {
                            for (channel in 0..1) {
                                val start = (frame * 2 + channel) * slot
                                if (encoding == "dop" && slot == 4) assertEquals(0, data[start].toInt())
                                if (encoding == "dop") assertEquals(5, data[start + slot - 1].toInt())
                                for (i in 0 until group) {
                                    val sampleIndex = if (encoding == "dsd_be") i else group - 1 - i
                                    val position = cursor + frame * group + sampleIndex
                                    val expected = if (position < 16384) (position * 17 + channel * 29) and 255 else 0x69
                                    val offset = if (encoding == "dop" && slot == 4) 1 else 0
                                    assertEquals(expected, data[start + offset + i].toInt() and 255)
                                }
                            }
                        }
                        cursor += data.size / (slot * 2) * group
                    }
                    assertEquals(16384, cursor)
                }
            }
        } finally { file.delete() }
    }

    @Test
    fun wavPackSeekRetainsBitAlignmentAndSurvivesClosedSafLease() {
        val file = fixture()
        try {
            val source = android.os.ParcelFileDescriptor.open(file, android.os.ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                requireNotNull(DsdSource.open("/proc/self/fd/${fd.fd}"))
            }
            source.use {
                for (time in listOf(20000L, 0L, 40000L)) {
                    val actual = it.seek(time, "dsd_be")
                    val cursor = (actual * it.rate + 7_999_999) / 8_000_000
                    val data = requireNotNull(it.readFrames("dsd_be", 4, 1))
                    for (channel in 0..1) for (index in 0..3) {
                        assertEquals(((cursor + index) * 17 + channel * 29).toInt() and 255,
                            data[channel * 4 + index].toInt() and 255)
                    }
                }
            }
        } finally { file.delete() }
    }

    @Test
    fun dsdCannotBeSentToAAudioAsPcm() {
        val file = fixture()
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val playback = HiResPlayback(context) {}
        try {
            val done = CountDownLatch(1)
            var reply: Any? = null
            var error: String? = null
            playback.command(MethodCall("prepare", mapOf("path" to file.path, "token" to 1))) { value, failure ->
                reply = value; error = failure; done.countDown()
            }
            assertTrue(done.await(10, TimeUnit.SECONDS))
            assertNull(error)
            assertEquals("dsd_unsupported", (reply as Map<*, *>)["reason"])
            assertEquals(true, (reply as Map<*, *>)["fatal"])
        } finally { playback.dispose(); file.delete() }
    }

    @Test
    fun invalidFileIsNotReportedAsExclusiveAccessFailure() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File.createTempFile("invalid-pcm-", ".wav", context.cacheDir)
        file.writeBytes(ByteArray(64))
        val playback = HiResPlayback(context) {}
        try {
            val done = CountDownLatch(1)
            var reply: Any? = null
            var error: String? = null
            playback.command(MethodCall("prepare", mapOf("path" to file.path, "token" to 1))) { value, failure ->
                reply = value; error = failure; done.countDown()
            }
            assertTrue(done.await(10, TimeUnit.SECONDS))
            assertNull(error)
            assertEquals("format", (reply as Map<*, *>)["reason"])
            assertEquals(false, (reply as Map<*, *>)["fatal"])
        } finally { playback.dispose(); file.delete() }
    }

    @Test
    fun exclusiveOutputEitherVerifiesExactFormatOrRejectsSharedFallback() {
        assertThrows(IllegalStateException::class.java) { NativeAudio.openOboe(1, 2, 24, 0) }
        val handle = try { NativeAudio.openOboe(48000, 2, 16, 0) }
        catch (error: IllegalStateException) {
            assertTrue(error.message.orEmpty().contains("exclusive output unavailable"))
            assertTrue(error.message.orEmpty().contains("requested=48000Hz/2ch/16bit"))
            assertTrue(error.message.orEmpty().contains("format="))
            return
        }
        try {
            val bits = NativeAudio.bitsOboe(handle)
            assertTrue(bits in listOf(16, 24, 32))
            val silence = ByteBuffer.allocateDirect(4800 * 2 * (bits / 8))
            assertEquals(silence.capacity(), NativeAudio.writeOboe(handle, silence, 0, silence.capacity()))
            NativeAudio.startOboe(handle)
            val deadline = android.os.SystemClock.elapsedRealtime() + 3000
            while (NativeAudio.framesOboe(handle) < 4800 && android.os.SystemClock.elapsedRealtime() < deadline) Thread.sleep(10)
            assertEquals(4800L, NativeAudio.framesOboe(handle))
            NativeAudio.flushOboe(handle)
            assertEquals(0L, NativeAudio.framesOboe(handle))
        } finally { NativeAudio.closeOboe(handle) }
        NativeAudio.closeOboe(handle)
        assertThrows(IllegalStateException::class.java) { NativeAudio.framesOboe(handle) }
    }
}
