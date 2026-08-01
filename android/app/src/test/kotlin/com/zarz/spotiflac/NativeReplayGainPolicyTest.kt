package com.zarz.spotiflac

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeReplayGainPolicyTest {
    @Test
    fun completeAlbumRequiresEveryCompletedRequestEntry() {
        val eligible = NativeReplayGainPolicy.eligibleEntryIndexes(
            entryAlbumKeys = listOf("album:a", "album:a"),
            statuses = mapOf("one" to "completed", "two" to "completed"),
            requestAlbumKeys = mapOf("one" to "album:a", "two" to "album:a"),
        )

        assertEquals(listOf(0, 1), eligible)
    }

    @Test
    fun incompleteOrFailedAlbumIsBlocked() {
        assertTrue(
            NativeReplayGainPolicy.eligibleEntryIndexes(
                entryAlbumKeys = listOf("album:a"),
                statuses = mapOf("one" to "completed", "two" to "downloading"),
                requestAlbumKeys = mapOf("one" to "album:a", "two" to "album:a"),
            ).isEmpty(),
        )
        assertTrue(
            NativeReplayGainPolicy.eligibleEntryIndexes(
                entryAlbumKeys = listOf("album:a", "album:a"),
                statuses = mapOf("one" to "completed", "two" to "failed"),
                requestAlbumKeys = mapOf("one" to "album:a", "two" to "album:a"),
            ).isEmpty(),
        )
    }

    @Test
    fun singleTrackAndBlankAlbumKeysAreNeverWrittenAsAlbumGain() {
        val eligible = NativeReplayGainPolicy.eligibleEntryIndexes(
            entryAlbumKeys = listOf("album:single", "", ""),
            statuses = mapOf(
                "single" to "completed",
                "blank-one" to "completed",
                "blank-two" to "completed",
            ),
            requestAlbumKeys = mapOf(
                "single" to "album:single",
                "blank-one" to "",
                "blank-two" to "",
            ),
        )

        assertTrue(eligible.isEmpty())
    }

    @Test
    fun albumsAreEvaluatedIndependently() {
        val eligible = NativeReplayGainPolicy.eligibleEntryIndexes(
            entryAlbumKeys = listOf("album:a", "album:a", "album:b", "album:b"),
            statuses = mapOf(
                "a1" to "completed",
                "a2" to "completed",
                "b1" to "completed",
                "b2" to "queued",
            ),
            requestAlbumKeys = mapOf(
                "a1" to "album:a",
                "a2" to "album:a",
                "b1" to "album:b",
                "b2" to "album:b",
            ),
        )

        assertEquals(listOf(0, 1), eligible)
    }

    @Test
    fun pendingWorkOnlyIncludesRunnableStatuses() {
        assertTrue(
            NativeReplayGainPolicy.hasPendingWork(
                mapOf("one" to "completed", "two" to "finalizing"),
            ),
        )
        assertFalse(
            NativeReplayGainPolicy.hasPendingWork(
                mapOf("one" to "completed", "two" to "failed"),
            ),
        )
    }
}
