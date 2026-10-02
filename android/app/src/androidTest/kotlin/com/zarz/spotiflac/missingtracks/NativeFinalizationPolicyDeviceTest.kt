package com.zarz.spotiflac.missingtracks

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runs on Android's own regex engine: the JVM accepts regex flags that the
 * device rejects when NativeFinalizationPolicy initializes during finalization.
 */
@RunWith(AndroidJUnit4::class)
class NativeFinalizationPolicyDeviceTest {
    @Test
    fun primaryArtistSeparatorCompilesAndSplitsOnDevice() {
        for ((input, expected) in listOf(
            "Calle 24, Chino Pacas" to "Calle 24",
            "Artist A feat. Artist B" to "Artist A",
            "Artist A\u00A0feat.\u00A0Artist B" to "Artist A",
            "Artist A\u3000x\u3000Artist B" to "Artist A",
            "Malcolm X" to "Malcolm X",
        )) {
            assertEquals(input, expected, NativeFinalizationPolicy.artistTagValue(input, "primary"))
        }
        assertEquals(
            "Artist A, Artist B",
            NativeFinalizationPolicy.artistTagValue("Artist A, Artist B", "joined"),
        )
    }
}
