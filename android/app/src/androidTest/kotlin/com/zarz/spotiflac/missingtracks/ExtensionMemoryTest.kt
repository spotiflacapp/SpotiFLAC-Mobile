package com.zarz.spotiflac.missingtracks

import android.os.Debug
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.spotiflac.backend.JsExtension
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ExtensionMemoryTest {
    @Test
    fun liveStateAndTextDecodingSurviveIdleCollection() {
        val source = """
            let calls = 0;
            const keep = {value: "Music 音楽 🎵"};
            registerExtension({
                allocate() {
                    const cycle = {bytes: new Uint8Array(16 * 1024 * 1024)};
                    cycle.self = cycle;
                    return ++calls;
                },
                state() {
                    return {calls, value: keep.value,
                        decoded: new TextDecoder().decode(new Uint8Array([97, 226, 130, 98])),
                        text: utils.base64Decode(utils.base64Encode(keep.value))};
                }
            });
        """.trimIndent()
        JsExtension(source, "{}", 5000uL).use { runtime ->
            val before = Debug.getNativeHeapAllocatedSize()
            assertEquals("1", runtime.call("allocate", "[]", null, 5000uL))
            val retained = Debug.getNativeHeapAllocatedSize()
            Thread.sleep(2500)
            val afterIdle = Debug.getNativeHeapAllocatedSize()
            // Process-wide allocator samples are diagnostic, not a flaky
            // assertion about unrelated platform allocations or Android PSS.
            Log.i("ExtensionMemoryTest", "native heap bytes: before=$before retained=$retained afterIdle=$afterIdle")
            val state = JSONObject(runtime.call("state", "[]", null, 5000uL))
            assertEquals(1, state.getInt("calls"))
            assertEquals("Music 音楽 🎵", state.getString("value"))
            assertEquals("Music 音楽 🎵", state.getString("text"))
            assertEquals("a\uFFFD\uFFFDb", state.getString("decoded"))
            assertEquals("2", runtime.call("allocate", "[]", null, 5000uL))
        }
    }
}
