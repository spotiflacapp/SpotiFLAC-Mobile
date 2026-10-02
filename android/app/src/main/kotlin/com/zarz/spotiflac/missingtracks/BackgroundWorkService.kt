package com.zarz.spotiflac.missingtracks

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Keeps user-started, non-download work (library scans, app update
 * downloads) running with the screen off. Without a foreground service the
 * process becomes cached when the activity stops, and Android freezes it.
 *
 * Work is reference-counted by kind; the service stops itself when the last
 * kind ends. Its notification shows the most recently updated work, using the
 * localized title and text supplied by Dart.
 */
class BackgroundWorkService : Service() {
    private data class Work(val title: String, val text: String, val progress: Int)

    companion object {
        private const val CHANNEL_ID = "background_work"
        private const val NOTIFICATION_ID = 1002
        private const val WAKELOCK_TAG = "SpotiFLAC:BackgroundWorkWakeLock"
        private const val WAKELOCK_TIMEOUT_MS = 30 * 60 * 1000L
        private const val WAKELOCK_RENEW_INTERVAL_MS = 15 * 60 * 1000L

        private val works = LinkedHashMap<String, Work>()
        private val mainHandler = Handler(Looper.getMainLooper())

        @Volatile
        private var instance: BackgroundWorkService? = null

        /**
         * Returns false when Android refuses a foreground service (for example
         * when started from the background); the work then runs as before.
         */
        fun start(context: Context, kind: String, title: String, text: String): Boolean {
            synchronized(works) {
                works.remove(kind)
                works[kind] = Work(title, text, -1)
            }
            return try {
                val intent = Intent(context, BackgroundWorkService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (e: Exception) {
                synchronized(works) { works.remove(kind) }
                android.util.Log.w("BackgroundWorkService", "Cannot start $kind: ${e.message}")
                false
            }
        }

        /** [progress] is a percentage, or negative for indeterminate. */
        fun update(kind: String, title: String, text: String, progress: Int) {
            synchronized(works) {
                if (!works.containsKey(kind)) return
                works.remove(kind)
                works[kind] = Work(title, text, progress.coerceAtMost(100))
            }
            mainHandler.post { instance?.refresh() }
        }

        fun stop(kind: String) {
            synchronized(works) {
                if (works.remove(kind) == null) return
            }
            mainHandler.post { instance?.refresh() }
        }

        fun isActive(kind: String): Boolean = synchronized(works) { works.containsKey(kind) }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var inForeground = false
    private val renewWakeLock = object : Runnable {
        override fun run() {
            if (!inForeground) return
            wakeLock?.acquire(WAKELOCK_TIMEOUT_MS)
            mainHandler.postDelayed(this, WAKELOCK_RENEW_INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Background tasks",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Library scans and app updates in progress"
                    setShowBadge(false)
                },
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // startForegroundService requires startForeground even when the work
        // already ended before this command arrived; refresh() then stops.
        val current = latestWork() ?: Work("SpotiFLAC", "", -1)
        if (!inForeground) {
            val notification = buildNotification(current)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            inForeground = true
            acquireWakeLock()
        }
        refresh()
        return START_NOT_STICKY
    }

    // Android 15 limits dataSync services; give the time back and stop.
    override fun onTimeout(startId: Int, fgsType: Int) {
        synchronized(works) { works.clear() }
        refresh()
    }

    override fun onDestroy() {
        stopWork()
        instance = null
        super.onDestroy()
    }

    private fun latestWork(): Work? = synchronized(works) { works.values.lastOrNull() }

    private fun refresh() {
        if (!inForeground) return
        val work = latestWork()
        if (work == null) {
            stopWork()
            stopSelf()
            return
        }
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(work))
    }

    private fun stopWork() {
        mainHandler.removeCallbacks(renewWakeLock)
        wakeLock?.let {
            if (it.isHeld) {
                try {
                    it.release()
                } catch (e: RuntimeException) {
                    android.util.Log.w("BackgroundWorkService", "WakeLock release failed: ${e.message}")
                }
            }
        }
        wakeLock = null
        if (inForeground) {
            inForeground = false
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG).apply {
            setReferenceCounted(false)
            acquire(WAKELOCK_TIMEOUT_MS)
        }
        mainHandler.postDelayed(renewWakeLock, WAKELOCK_RENEW_INTERVAL_MS)
    }

    private fun buildNotification(work: Work): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(work.title)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        if (work.text.isNotEmpty()) {
            builder.setContentText(work.text.lineSequence().first())
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(work.text))
        }
        if (work.progress >= 0) {
            builder.setProgress(100, work.progress, false)
        } else {
            builder.setProgress(0, 0, true)
        }
        return builder.build()
    }
}
