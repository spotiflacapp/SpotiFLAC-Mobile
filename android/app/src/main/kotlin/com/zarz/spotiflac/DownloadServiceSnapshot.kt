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

// Native-worker item state snapshots for the Flutter side.

internal fun DownloadService.writeNativeWorkerSnapshot(
    isRunning: Boolean,
    isPaused: Boolean,
    currentItemId: String,
    message: String,
    lastResult: JSONObject? = null,
    settingsJson: String = "",
    includeItems: Boolean = false,
    snapshotSerial: Long = snapshotWriteSerial.incrementAndGet()
) {
    try {
        synchronized(snapshotWriteLock) {
            if (includeItems) {
                if (snapshotSerial < latestCommittedStateSnapshotSerial) return
            } else {
                if (snapshotSerial < latestCommittedProgressSnapshotSerial) return
            }

            val counts = nativeWorkerCounts()
            val snapshot = JSONObject()
                .put("contract_version", DownloadService.NATIVE_WORKER_CONTRACT_VERSION)
                .put("run_id", nativeWorkerRunId.ifBlank { readNativeWorkerRunIdFromSnapshotFile() })
                .put("is_running", isRunning)
                .put("is_paused", isPaused)
                .put("total", counts.total)
                .put("completed", counts.completed)
                .put("failed", counts.failed)
                .put("skipped", counts.skipped)
                .put("current_item_id", currentItemId)
                .put("message", message)
                .put("updated_at", System.currentTimeMillis())
                .put("snapshot_serial", snapshotSerial)
                .put("state_serial", if (includeItems) snapshotSerial else latestCommittedStateSnapshotSerial)
                .put("snapshot_mode", if (includeItems) "compact_items" else "delta")
            // Snapshot of the header before the per-item payload is
            // attached; served to pollers that already consumed this
            // items payload (see getNativeWorkerSnapshot).
            val headerCandidate = if (includeItems) snapshot.toString() else null
            snapshot.put("item_ids", nativeWorkerItemIds())
            if (includeItems) {
                snapshot.put("items", nativeWorkerItemsSnapshot(includeStatic = false))
            } else {
                nativeWorkerItemSnapshot(currentItemId, includeStatic = false)?.let {
                    snapshot.put("item_delta", it)
                }
            }
            if (settingsJson.isNotBlank() && includeItems) {
                snapshot.put("settings_json", settingsJson)
            }
            if (lastResult != null) {
                snapshot.put("last_result", lastResult)
            }

            synchronized(DownloadService.NATIVE_WORKER_STATE_FILE_LOCK) {
                val targetFileName = if (includeItems) {
                    DownloadService.NATIVE_WORKER_STATE_FILE
                } else {
                    DownloadService.NATIVE_WORKER_PROGRESS_FILE
                }
                val file = AtomicFile(File(filesDir, targetFileName))
                var stream: java.io.FileOutputStream? = null
                try {
                    stream = file.startWrite()
                    stream.write(snapshot.toString().toByteArray(Charsets.UTF_8))
                    file.finishWrite(stream)
                    stream = null
                    if (includeItems) {
                        latestCommittedStateSnapshotSerial = snapshotSerial
                        if (headerCandidate != null) {
                            DownloadService.lastStateHeaderJson = headerCandidate
                            DownloadService.lastStateHeaderSerial = snapshotSerial
                        }
                    } else {
                        latestCommittedProgressSnapshotSerial = snapshotSerial
                    }
                } finally {
                    if (stream != null) {
                        file.failWrite(stream)
                    }
                }
            }
        }
    } catch (e: Exception) {
        android.util.Log.w("DownloadService", "Failed to write native worker snapshot: ${e.message}")
    }
}

internal fun DownloadService.writeNativeWorkerSnapshotAsync(
    isRunning: Boolean,
    isPaused: Boolean,
    currentItemId: String,
    message: String,
    lastResult: JSONObject? = null,
    settingsJson: String = "",
    includeItems: Boolean = false
) {
    val snapshotSerial = snapshotWriteSerial.incrementAndGet()
    serviceScope.launch {
        writeNativeWorkerSnapshot(
            isRunning = isRunning,
            isPaused = isPaused,
            currentItemId = currentItemId,
            message = message,
            lastResult = lastResult,
            settingsJson = settingsJson,
            includeItems = includeItems,
            snapshotSerial = snapshotSerial
        )
    }
}

internal fun DownloadService.readNativeWorkerRunIdFromSnapshotFile(): String {
    return try {
        synchronized(DownloadService.NATIVE_WORKER_STATE_FILE_LOCK) {
            val file = File(filesDir, DownloadService.NATIVE_WORKER_STATE_FILE)
            if (!file.exists()) {
                ""
            } else {
                val text = AtomicFile(file).openRead().bufferedReader(Charsets.UTF_8).use {
                    it.readText()
                }
                JSONObject(text).optString("run_id", "")
            }
        }
    } catch (_: Exception) {
        ""
    }
}

internal fun DownloadService.updateNativeWorkerItem(itemId: String, updater: (DownloadService.NativeWorkerItem) -> Unit) {
    synchronized(nativeWorkerItems) {
        nativeWorkerItems.firstOrNull { it.itemId == itemId }?.let(updater)
    }
}

internal fun DownloadService.updateNativeWorkerItemProgress(itemId: String) {
    try {
        val raw = Gobackend.getAllDownloadProgress()
        val root = JSONObject(raw)
        val items = root.optJSONObject("items") ?: return
        val progress = items.optJSONObject(itemId) ?: return
        val backendStatus = progress.optString("status", "downloading")
        val bytesReceived = progress.optLong("bytes_received", 0L)
        val bytesTotal = progress.optLong("bytes_total", 0L)
        if (backendStatus == "preparing") {
            currentStatus = "preparing"
            updateNativeWorkerItem(itemId) {
                it.status = "preparing"
                it.progress = 0.0
                it.bytesReceived = 0L
                it.bytesTotal = 0L
            }
            lastProgress = 0L
            lastTotal = 0L
            updateNotification(0L, 0L)
            return
        }
        val progressValue = if (bytesTotal > 0L) {
            bytesReceived.toDouble() / bytesTotal.toDouble()
        } else {
            progress.optDouble("progress", 0.0)
        }.coerceIn(0.0, 1.0)
        currentStatus = if (backendStatus == "finalizing") {
            "finalizing"
        } else {
            "downloading"
        }
        updateNativeWorkerItem(itemId) {
            it.status = currentStatus
            it.progress = progressValue
            it.bytesReceived = bytesReceived
            it.bytesTotal = bytesTotal
        }
        if (bytesTotal > 0L) {
            lastProgress = bytesReceived
            lastTotal = bytesTotal
            updateNotification(bytesReceived, bytesTotal)
        } else if (progressValue > 0.0) {
            val percentProgress = (progressValue * DownloadService.NOTIFICATION_PERCENT_TOTAL).toLong()
                .coerceIn(0L, DownloadService.NOTIFICATION_PERCENT_TOTAL)
            lastProgress = percentProgress
            lastTotal = DownloadService.NOTIFICATION_PERCENT_TOTAL
            updateNotification(percentProgress, DownloadService.NOTIFICATION_PERCENT_TOTAL)
        } else {
            lastProgress = 0L
            lastTotal = 0L
            updateNotification(0L, 0L)
        }
    } catch (_: Exception) {
    }
}

internal fun DownloadService.nativeWorkerCounts(): DownloadService.NativeWorkerCounts {
    var total = 0
    var completed = 0
    var failed = 0
    var skipped = 0
    synchronized(nativeWorkerItems) {
        total = nativeWorkerItems.size
        for (item in nativeWorkerItems) {
            when (item.status) {
                "completed" -> completed++
                "failed" -> failed++
                "skipped" -> skipped++
            }
        }
    }
    return DownloadService.NativeWorkerCounts(
        total = total,
        completed = completed,
        failed = failed,
        skipped = skipped
    )
}

internal fun DownloadService.nativeWorkerItemSnapshot(itemId: String, includeStatic: Boolean): JSONObject? {
    if (itemId.isBlank()) return null
    synchronized(nativeWorkerItems) {
        val item = nativeWorkerItems.firstOrNull { it.itemId == itemId } ?: return null
        return nativeWorkerItemSnapshotLocked(item, includeStatic)
    }
}

internal fun DownloadService.nativeWorkerItemIds(): JSONArray {
    val array = JSONArray()
    synchronized(nativeWorkerItems) {
        for (item in nativeWorkerItems) {
            array.put(item.itemId)
        }
    }
    return array
}

internal fun DownloadService.nativeWorkerItemsSnapshot(includeStatic: Boolean): JSONArray {
    val array = JSONArray()
    synchronized(nativeWorkerItems) {
        for (item in nativeWorkerItems) {
            array.put(nativeWorkerItemSnapshotLocked(item, includeStatic))
        }
    }
    return array
}

internal fun DownloadService.nativeWorkerItemSnapshotLocked(item: DownloadService.NativeWorkerItem, includeStatic: Boolean): JSONObject {
    val json = JSONObject()
        .put("item_id", item.itemId)
        .put("status", item.status)
        .put("progress", item.progress)
        .put("bytes_received", item.bytesReceived)
        .put("bytes_total", item.bytesTotal)
    if (includeStatic) {
        json.put("track_name", item.trackName)
            .put("artist_name", item.artistName)
            .put("item_json", item.itemJson)
    }
    if (item.error.isNotBlank()) {
        json.put("error", item.error)
    }
    item.resultJson?.let { json.put("result", it) }
    return json
}

