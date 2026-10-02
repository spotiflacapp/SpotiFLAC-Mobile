package com.zarz.spotiflac.missingtracks

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.spotiflac.backend.JsExtension
import com.spotiflac.backend.JsExtensionException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ExtensionInputValidationTest {
    @Test
    fun invalidArgumentsDoNotReachJavaScriptAndValidObjectsKeepTheirValues() {
        val source = "let calls=0; registerExtension({echo(value){return {calls:++calls,value}}});"
        JsExtension(source, "{}", 2000uL).use { runtime ->
            for (input in listOf("{}", "[1e400]", "[\"\\uD800\"]", "[] true")) {
                val failure = runCatching { runtime.call("echo", input, null, 2000uL) }.exceptionOrNull()
                assertTrue(failure is JsExtensionException.InvalidInput)
            }
            val result = JSONObject(runtime.call("echo", "[{\"title\":\"音楽 🎵\",\"options\":[true,null,42]}]", null, 2000uL))
            assertEquals(1, result.getInt("calls"))
            assertEquals("音楽 🎵", result.getJSONObject("value").getString("title"))
            assertEquals(42, result.getJSONObject("value").getJSONArray("options").getInt(2))
        }
    }
}
