package com.zarz.spotiflac

/**
 * Pure album ReplayGain completion policy used by DownloadService.
 */
internal object NativeReplayGainPolicy {
    private val blockingStatuses = setOf(
        "failed",
        "skipped",
        "queued",
        "downloading",
        "finalizing",
    )
    private val pendingStatuses = setOf("queued", "downloading", "finalizing")

    fun eligibleEntryIndexes(
        entryAlbumKeys: List<String>,
        statuses: Map<String, String>,
        requestAlbumKeys: Map<String, String>,
    ): List<Int> {
        val blockedKeys = mutableSetOf<String>()
        val expectedCompletedByKey = mutableMapOf<String, Int>()
        for ((itemId, albumKey) in requestAlbumKeys) {
            when (statuses[itemId]) {
                "completed" -> {
                    expectedCompletedByKey[albumKey] =
                        (expectedCompletedByKey[albumKey] ?: 0) + 1
                }
                in blockingStatuses -> blockedKeys.add(albumKey)
            }
        }

        val indexesByKey = entryAlbumKeys.indices.groupBy { entryAlbumKeys[it] }
        val eligible = mutableListOf<Int>()
        for ((albumKey, indexes) in indexesByKey) {
            if (
                albumKey.isBlank() ||
                albumKey in blockedKeys ||
                indexes.size <= 1
            ) {
                continue
            }
            val expected = expectedCompletedByKey[albumKey] ?: continue
            if (indexes.size == expected) {
                eligible.addAll(indexes)
            }
        }
        return eligible
    }

    fun hasPendingWork(statuses: Map<String, String>): Boolean =
        statuses.values.any { it in pendingStatuses }
}
