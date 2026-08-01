package com.zarz.spotiflac

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeFinalizationPolicyTest {
    @Test
    fun matchesSharedCrossPipelineQualityCases() {
        val stream = checkNotNull(
            javaClass.getResourceAsStream("/finalization_quality_cases.tsv"),
        )
        stream.bufferedReader().useLines { lines ->
            for (line in lines) {
                if (line.isBlank() || line.startsWith("#")) continue
                val fields = line.split('\t')
                assertEquals("invalid shared fixture: $line", 6, fields.size)
                val actual = NativeFinalizationPolicy.qualityVariantFilenameLabel(
                    measuredQuality = fields[4],
                    bitDepth = fields[1].toIntOrNull(),
                    sampleRate = fields[2].toIntOrNull(),
                    bitrateKbps = fields[3].toIntOrNull(),
                    audioCodec = fields[0],
                )
                val expected = fields[5].takeUnless { it == "<null>" }
                assertEquals("shared fixture: $line", expected, actual)
            }
        }
    }

    @Test
    fun codecAliasesDriveLossyAndLosslessDecisions() {
        assertEquals("aac", NativeFinalizationPolicy.normalizeAudioCodec("mp4a"))
        assertEquals("eac3", NativeFinalizationPolicy.normalizeAudioCodec("ec-3"))
        assertEquals("opus", NativeFinalizationPolicy.normalizeAudioCodec("ogg"))
        assertTrue(NativeFinalizationPolicy.isLossyAudioCodec("ac-4"))
        assertTrue(NativeFinalizationPolicy.isLosslessAudioCodec("pcm_s24le"))
        assertTrue(NativeFinalizationPolicy.isLosslessAudioCodec("ALAC"))
        assertFalse(NativeFinalizationPolicy.isLosslessAudioCodec("aac"))
    }

    @Test
    fun displayQualityUsesMeasuredLosslessSpecifications() {
        assertEquals(
            "24-bit/96kHz",
            NativeFinalizationPolicy.displayAudioQuality(
                filePath = "/music/track.flac",
                fileName = "track.flac",
                bitDepth = 24,
                sampleRate = 96000,
                bitrateKbps = null,
                audioCodec = "flac",
                storedQuality = "HI_RES",
            ),
        )
        assertEquals(
            "24-bit/44.1kHz",
            NativeFinalizationPolicy.displayAudioQuality(
                filePath = "/music/track.flac",
                fileName = "track.flac",
                bitDepth = 24,
                sampleRate = 44100,
                bitrateKbps = null,
                audioCodec = "flac",
                storedQuality = "LOSSLESS",
            ),
        )
    }

    @Test
    fun displayQualityPreservesUsefulLossyLabels() {
        assertEquals(
            "OPUS 192kbps",
            NativeFinalizationPolicy.displayAudioQuality(
                filePath = "/music/track.ogg",
                fileName = "track.ogg",
                bitDepth = null,
                sampleRate = 48000,
                bitrateKbps = 192,
                audioCodec = "opus",
                storedQuality = "HIGH",
            ),
        )
        assertEquals(
            "AAC",
            NativeFinalizationPolicy.displayAudioQuality(
                filePath = "/music/track.m4a",
                fileName = "track.m4a",
                bitDepth = null,
                sampleRate = 48000,
                bitrateKbps = null,
                audioCodec = "aac",
                storedQuality = "LOSSLESS",
            ),
        )
    }

    @Test
    fun qualityVariantLabelRejectsUnmeasuredPlaceholders() {
        assertNull(
            NativeFinalizationPolicy.qualityVariantFilenameLabel(
                measuredQuality = "LOSSLESS",
                bitDepth = null,
                sampleRate = null,
                bitrateKbps = null,
                audioCodec = "flac",
            ),
        )
        assertEquals(
            "24bit-96kHz",
            NativeFinalizationPolicy.qualityVariantFilenameLabel(
                measuredQuality = "24-bit/96kHz",
                bitDepth = null,
                sampleRate = null,
                bitrateKbps = null,
                audioCodec = "flac",
            ),
        )
        assertEquals(
            "320kbps",
            NativeFinalizationPolicy.qualityVariantFilenameLabel(
                measuredQuality = "MP3 320kbps",
                bitDepth = null,
                sampleRate = null,
                bitrateKbps = null,
                audioCodec = "mp3",
            ),
        )
    }

    @Test
    fun finalQualityLabelReplacesOnlyTheStagingToken() {
        assertEquals(
            "Artist - Track - 24bit-96kHz.flac",
            NativeFinalizationPolicy.applyQualityVariantFilenameLabel(
                fileName = "Artist - Track - pending.flac",
                stagingLabel = "pending",
                qualityLabel = "24bit-96kHz",
            ),
        )
        assertEquals(
            "Artist - Track - 24bit-96kHz.flac",
            NativeFinalizationPolicy.applyQualityVariantFilenameLabel(
                fileName = "Artist - Track.flac",
                stagingLabel = "",
                qualityLabel = "24bit-96kHz",
            ),
        )
    }

    @Test
    fun measuredQualityIsAddedOnlyAfterCleanNameCollision() {
        val stagedName = "Artist - Track - qv_ab12cd34.flac"
        assertEquals(
            "Artist - Track.flac",
            NativeFinalizationPolicy.removeQualityVariantStagingLabel(
                fileName = stagedName,
                stagingLabel = "qv_ab12cd34",
            ),
        )
        assertEquals(
            "Artist - Track.flac",
            NativeFinalizationPolicy.resolveQualityVariantFilename(
                fileName = stagedName,
                stagingLabel = "qv_ab12cd34",
                qualityLabel = "24bit-96kHz",
                collisionOnly = true,
                cleanNameExists = false,
            ),
        )
        assertEquals(
            "Artist - Track - 24bit-96kHz.flac",
            NativeFinalizationPolicy.resolveQualityVariantFilename(
                fileName = stagedName,
                stagingLabel = "qv_ab12cd34",
                qualityLabel = "24bit-96kHz",
                collisionOnly = true,
                cleanNameExists = true,
            ),
        )
    }

    @Test
    fun deferredSafNamingNeverPublishesTheNativeCacheName() {
        val logicalName = NativeFinalizationPolicy.logicalOutputFileName(
            deferredSafPublish = true,
            resultSafFileName = "Sunidhi Chauhan - Aisa Jadoo - qv_ab12cd34.flac",
            requestSafFileName = "fallback.flac",
            currentFileName = "native_saf_work_603020549715656640.m4a",
        )

        assertEquals(
            "Sunidhi Chauhan - Aisa Jadoo - 16bit-44.1kHz.flac",
            NativeFinalizationPolicy.applyQualityVariantFilenameLabel(
                fileName = logicalName,
                stagingLabel = "qv_ab12cd34",
                qualityLabel = "16bit-44.1kHz",
            ),
        )
    }

    @Test
    fun nonSafNamingStillFollowsTheCurrentConvertedFile() {
        assertEquals(
            "converted.flac",
            NativeFinalizationPolicy.logicalOutputFileName(
                deferredSafPublish = false,
                resultSafFileName = "ignored.flac",
                requestSafFileName = "ignored-too.flac",
                currentFileName = "converted.flac",
            ),
        )
    }

    @Test
    fun decryptionExtensionAndIndexTagsHaveStableFallbacks() {
        assertEquals(
            ".m4a",
            NativeFinalizationPolicy.resolvePreferredDecryptionExtension(
                inputPath = "/music/encrypted.bin",
                requested = "M4A",
            ),
        )
        assertEquals(
            ".flac",
            NativeFinalizationPolicy.resolvePreferredDecryptionExtension(
                inputPath = "/music/encrypted.m4a",
                requested = "",
            ),
        )
        assertEquals("3/12", NativeFinalizationPolicy.formatIndexTag(3, 12))
        assertEquals("3", NativeFinalizationPolicy.formatIndexTag(3, 0))
        assertEquals("0", NativeFinalizationPolicy.formatIndexTag(0, 12))
    }
}
