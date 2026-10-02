package com.zarz.spotiflac.missingtracks

import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.ParcelFileDescriptor
import com.spotiflac.backend.UsbDirectOutput
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class UsbBitPerfectPluginTest {
    @Test
    fun directNativeBridgeRejectsNonUsbFdWithoutClosingItsOwner() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File.createTempFile("usb-bridge-", ".bin", context.cacheDir)
        try {
            file.writeBytes(ByteArray(64))
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                val descriptors = byteArrayOf(
                    9, 4, 0, 0, 0, 1, 1, 0, 0,
                    9, 4, 1, 1, 1, 1, 2, 0, 0,
                    7, 0x24, 1, 1, 1, 1, 0,
                    11, 0x24, 2, 1, 2, 2, 16, 1, 0x80.toByte(), 0xbb.toByte(), 0,
                    9, 5, 1, 0x0d, 0xc0.toByte(), 0, 1, 0, 0,
                )
                assertThrows(Exception::class.java) {
                    UsbDirectOutput.open(fd.fd, descriptors, 48000u, 2u, 16u, false, false)
                }
                assertEquals(64L, fd.statSize)
            }
        } finally { file.delete() }
    }

    @Test
    fun pcmSourceRetainsSafDescriptorAndSeeksWithoutChangingSamples() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File.createTempFile("usb-pcm-", ".wav", context.cacheDir)
        val audioSize = 4800 * 4
        val wav = ByteBuffer.allocate(44 + audioSize).order(ByteOrder.LITTLE_ENDIAN)
        wav.put("RIFF".toByteArray()).putInt(36 + audioSize).put("WAVEfmt ".toByteArray())
            .putInt(16).putShort(1).putShort(2).putInt(48000).putInt(192000).putShort(4).putShort(16)
            .put("data".toByteArray()).putInt(audioSize)
        repeat(4800) { wav.putShort(1234).putShort(-1234) }
        try {
            file.writeBytes(wav.array())
            val source = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                UsbPcmSource("/proc/self/fd/${fd.fd}")
            }
            source.use {
                assertEquals(48000, it.rate)
                assertEquals(16, it.bits)
                for (target in listOf(0L, 50000L)) {
                    it.seek(target)
                    val decoded = requireNotNull(it.read(32)).order(ByteOrder.LITTLE_ENDIAN)
                    assertTrue(decoded.remaining() > 0)
                    while (decoded.hasRemaining()) {
                        assertEquals(1234 shl 16, decoded.int)
                        assertEquals(-1234 shl 16, decoded.int)
                    }
                }
            }
        } finally { file.delete() }
    }

    @Test
    fun unsupportedRouteReturnsFallbackAndEngineDetachesCleanly() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val manager = context.getSystemService(AudioManager::class.java)
        assumeTrue(manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).none {
            it.type == AudioDeviceInfo.TYPE_USB_DEVICE || it.type == AudioDeviceInfo.TYPE_USB_HEADSET
        })
        lateinit var engine: FlutterEngine
        lateinit var plugin: UsbBitPerfectPlugin
        instrumentation.runOnMainSync {
            engine = FlutterEngine(context)
            plugin = UsbBitPerfectPlugin()
            engine.plugins.add(plugin)
        }
        try {
            fun invoke(method: String, arguments: Map<String, Any>? = null): Any? {
                val done = CountDownLatch(1)
                var value: Any? = null
                var failure: String? = null
                instrumentation.runOnMainSync {
                    plugin.onMethodCall(MethodCall(method, arguments), object : MethodChannel.Result {
                        override fun success(result: Any?) { value = result; done.countDown() }
                        override fun error(code: String, message: String?, details: Any?) {
                            failure = "$code: $message"
                            done.countDown()
                        }
                        override fun notImplemented() { failure = "not implemented"; done.countDown() }
                    })
                }
                assertTrue("Native method timed out", done.await(10, TimeUnit.SECONDS))
                assertNull(failure)
                return value
            }
            val result = invoke("prepare", mapOf("path" to "/unopened.flac", "token" to 1)) as Map<*, *>
            assertEquals(if (android.os.Build.VERSION.SDK_INT >= 34) "no_usb" else "android_version", result["reason"])
            assertNull(result["ready"])
            invoke("stop")
            val direct = invoke("prepare", mapOf("path" to "/unopened.dsf", "token" to 2, "direct" to true)) as Map<*, *>
            assertEquals("no_usb", direct["reason"])
            assertNull(direct["ready"])
            invoke("stop")
        } finally {
            instrumentation.runOnMainSync { engine.destroy() }
        }
    }
}
