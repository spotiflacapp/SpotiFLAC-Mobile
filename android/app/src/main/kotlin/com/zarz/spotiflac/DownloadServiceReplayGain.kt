package com.zarz.spotiflac

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.AtomicFile
import androidx.core.app.NotificationCompat
import gobackend.Gobackend
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicLong

// Album ReplayGain accumulation and journal persistence for the native worker.

internal fun DownloadService.writeNativeAlbumReplayGainIfComplete(): Boolean {
    val entries = synchronized(nativeReplayGainEntries) {
        nativeReplayGainEntries.map { JSONObject(it.toString()) }
    }
    if (entries.size <= 1) return true

    val statuses = synchronized(nativeWorkerItems) {
        nativeWorkerItems.associate { it.itemId to it.status }
    }
    val requestKeys = synchronized(nativeReplayGainRequestAlbumKeys) {
        nativeReplayGainRequestAlbumKeys.toMap()
    }
    val eligible = buildEligibleNativeAlbumReplayGain(entries, statuses, requestKeys)
    if (eligible.length() <= 1) {
        return !hasPendingNativeAlbumReplayGainWork(statuses)
    }
    return writeNativeAlbumReplayGainEntries(eligible)
}

internal fun DownloadService.buildEligibleNativeAlbumReplayGain(
    entries: List<JSONObject>,
    statuses: Map<String, String>,
    requestKeys: Map<String, String>
): JSONArray {
    val eligibleIndexes = NativeReplayGainPolicy.eligibleEntryIndexes(
        entryAlbumKeys = entries.map { it.optString("album_key", "") },
        statuses = statuses,
        requestAlbumKeys = requestKeys,
    )
    val eligible = JSONArray()
    for (index in eligibleIndexes) {
        eligible.put(entries[index])
    }
    return eligible
}

internal fun DownloadService.writeNativeAlbumReplayGainEntries(eligible: JSONArray): Boolean {
    if (eligible.length() <= 1) return true
    try {
        val result = JSONObject(NativeDownloadFinalizer.writeAlbumReplayGain(this, eligible.toString()))
        return result.optBoolean("success", false)
    } catch (e: Exception) {
        android.util.Log.w("DownloadService", "Native album ReplayGain failed: ${e.message}")
        return false
    }
}

internal fun DownloadService.hasPendingNativeAlbumReplayGainWork(statuses: Map<String, String>): Boolean {
    return NativeReplayGainPolicy.hasPendingWork(statuses)
}

internal fun DownloadService.writeNativeReplayGainJournal() {
    val requestKeys = synchronized(nativeReplayGainRequestAlbumKeys) {
        nativeReplayGainRequestAlbumKeys.toMap()
    }
    if (requestKeys.isEmpty()) return

    val entries = synchronized(nativeReplayGainEntries) {
        nativeReplayGainEntries.map { JSONObject(it.toString()) }
    }
    val statuses = synchronized(nativeWorkerItems) {
        nativeWorkerItems.associate { it.itemId to it.status }
    }
    synchronized(DownloadService.NATIVE_REPLAYGAIN_JOURNAL_FILE_LOCK) {
        val file = AtomicFile(File(filesDir, DownloadService.NATIVE_REPLAYGAIN_JOURNAL_FILE))
        val existing = readNativeReplayGainJournalLocked(file)
        val mergedEntries = mergeNativeReplayGainJournalEntries(
            existing?.optJSONArray("entries"),
            entries,
        )
        val mergedRequestKeys = mergeJsonObjectStringMap(
            existing?.optJSONObject("request_album_keys"),
            requestKeys,
        )
        val mergedStatuses = mergeJsonObjectStringMap(
            existing?.optJSONObject("statuses"),
            statuses,
        )
        val root = JSONObject()
            .put("run_id", nativeWorkerRunId)
            .put("updated_at", System.currentTimeMillis())
            .put("entries", mergedEntries)
            .put("request_album_keys", JSONObject(mergedRequestKeys))
            .put("statuses", JSONObject(mergedStatuses))

        var stream: java.io.FileOutputStream? = null
        try {
            stream = file.startWrite()
            stream.write(root.toString().toByteArray(Charsets.UTF_8))
            file.finishWrite(stream)
            stream = null
        } catch (e: Exception) {
            android.util.Log.w("DownloadService", "Failed to write native ReplayGain journal: ${e.message}")
        } finally {
            if (stream != null) {
                file.failWrite(stream)
            }
        }
    }
}

internal fun DownloadService.readNativeReplayGainJournalLocked(file: AtomicFile): JSONObject? {
    return try {
        if (!file.baseFile.exists()) return null
        val text = file.openRead().bufferedReader(Charsets.UTF_8).use {
            it.readText()
        }
        JSONObject(text)
    } catch (e: Exception) {
        android.util.Log.w("DownloadService", "Failed to merge native ReplayGain journal: ${e.message}")
        null
    }
}

internal fun DownloadService.mergeNativeReplayGainJournalEntries(
    existingEntries: JSONArray?,
    currentEntries: List<JSONObject>
): JSONArray {
    val byKey = linkedMapOf<String, JSONObject>()

    fun add(entry: JSONObject) {
        val trackId = entry.optString("track_id", "")
        val path = entry.optString("file_path", "")
        val key = if (trackId.isNotBlank()) {
            "track:$trackId"
        } else {
            "path:$path"
        }
        if (key != "path:") {
            byKey[key] = JSONObject(entry.toString())
        }
    }

    if (existingEntries != null) {
        for (index in 0 until existingEntries.length()) {
            existingEntries.optJSONObject(index)?.let(::add)
        }
    }
    for (entry in currentEntries) add(entry)

    return JSONArray().apply {
        for (entry in byKey.values) put(entry)
    }
}

internal fun DownloadService.mergeJsonObjectStringMap(
    existing: JSONObject?,
    current: Map<String, String>
): Map<String, String> {
    val merged = linkedMapOf<String, String>()
    if (existing != null) {
        for (key in existing.keys()) {
            merged[key] = existing.optString(key, "")
        }
    }
    for ((key, value) in current) {
        merged[key] = value
    }
    return merged
}

internal fun DownloadService.clearNativeReplayGainJournal() {
    synchronized(DownloadService.NATIVE_REPLAYGAIN_JOURNAL_FILE_LOCK) {
        try {
            AtomicFile(File(filesDir, DownloadService.NATIVE_REPLAYGAIN_JOURNAL_FILE)).delete()
        } catch (_: Exception) {
        }
    }
}

internal fun DownloadService.flushNativeAlbumReplayGainJournalIfComplete() {
    val root = synchronized(DownloadService.NATIVE_REPLAYGAIN_JOURNAL_FILE_LOCK) {
        try {
            val file = File(filesDir, DownloadService.NATIVE_REPLAYGAIN_JOURNAL_FILE)
            if (!file.exists()) return
            val text = AtomicFile(file).openRead().bufferedReader(Charsets.UTF_8).use {
                it.readText()
            }
            JSONObject(text)
        } catch (e: Exception) {
            android.util.Log.w("DownloadService", "Failed to read native ReplayGain journal: ${e.message}")
            return
        }
    }

    val entriesArray = root.optJSONArray("entries") ?: return
    val entries = mutableListOf<JSONObject>()
    for (index in 0 until entriesArray.length()) {
        entriesArray.optJSONObject(index)?.let { entries.add(JSONObject(it.toString())) }
    }
    val statusesJson = root.optJSONObject("statuses") ?: JSONObject()
    val statuses = mutableMapOf<String, String>()
    for (key in statusesJson.keys()) {
        statuses[key] = statusesJson.optString(key, "")
    }
    val requestKeysJson = root.optJSONObject("request_album_keys") ?: JSONObject()
    val requestKeys = mutableMapOf<String, String>()
    for (key in requestKeysJson.keys()) {
        requestKeys[key] = requestKeysJson.optString(key, "")
    }

    val eligible = buildEligibleNativeAlbumReplayGain(entries, statuses, requestKeys)
    if (eligible.length() <= 1 && hasPendingNativeAlbumReplayGainWork(statuses)) {
        return
    }
    if (writeNativeAlbumReplayGainEntries(eligible)) {
        clearNativeReplayGainJournal()
    }
}
