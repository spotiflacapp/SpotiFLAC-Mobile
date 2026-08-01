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

// Wi-Fi-only download policy: network callback, pause and resume.

internal fun DownloadService.configureNativeWorkerNetworkPolicy(settingsJson: String) {
    nativeWorkerDownloadNetworkMode = try {
        JSONObject(settingsJson).optString("download_network_mode", "any")
    } catch (_: Exception) {
        "any"
    }

    unregisterNativeWorkerNetworkCallback()
    if (!NativeWorkerPolicy.requiresWifi(nativeWorkerDownloadNetworkMode)) {
        nativeWorkerNetworkPaused = false
        return
    }

    nativeWorkerNetworkPaused = !hasUsableWifiConnection()
    val connectivityManager =
        getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            synchronized(nativeWorkerWifiNetworks) {
                nativeWorkerWifiNetworks.add(network)
            }
            refreshNativeWorkerNetworkPause()
        }

        override fun onLost(network: Network) {
            synchronized(nativeWorkerWifiNetworks) {
                nativeWorkerWifiNetworks.remove(network)
            }
            refreshNativeWorkerNetworkPause()
        }

        override fun onCapabilitiesChanged(
            network: Network,
            networkCapabilities: NetworkCapabilities,
        ) {
            synchronized(nativeWorkerWifiNetworks) {
                if (networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                    networkCapabilities.hasCapability(
                        NetworkCapabilities.NET_CAPABILITY_INTERNET,
                    )
                ) {
                    nativeWorkerWifiNetworks.add(network)
                } else {
                    nativeWorkerWifiNetworks.remove(network)
                }
            }
            refreshNativeWorkerNetworkPause()
        }
    }
    try {
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        connectivityManager.registerNetworkCallback(request, callback)
        nativeWorkerNetworkCallback = callback
    } catch (e: Exception) {
        android.util.Log.w(
            "DownloadService",
            "Failed to monitor Wi-Fi for native worker: ${e.message}",
        )
    }
}

internal fun DownloadService.hasUsableWifiConnection(): Boolean {
    val connectivityManager =
        getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    if (synchronized(nativeWorkerWifiNetworks) {
            nativeWorkerWifiNetworks.isNotEmpty()
        }
    ) {
        return true
    }
    return try {
        val activeNetwork = connectivityManager.activeNetwork ?: return false
        val capabilities =
            connectivityManager.getNetworkCapabilities(activeNetwork) ?: return false
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    } catch (_: Exception) {
        false
    }
}

internal fun DownloadService.refreshNativeWorkerNetworkPause() {
    if (!NativeWorkerPolicy.requiresWifi(nativeWorkerDownloadNetworkMode)) return

    val shouldPause = NativeWorkerPolicy.shouldPauseForNetwork(
        nativeWorkerDownloadNetworkMode,
        hasUsableWifiConnection(),
    )
    if (shouldPause == nativeWorkerNetworkPaused) return

    nativeWorkerNetworkPaused = shouldPause
    if (nativeWorkerJob?.isActive != true) return

    if (shouldPause) {
        currentStatus = if (nativeWorkerVerificationPaused) {
            "verification_required"
        } else {
            "waiting_wifi"
        }
        cancelActiveNativeItemForPause()
        updateNotification(0L, 0L)
    } else {
        currentStatus = if (nativeWorkerVerificationPaused) {
            "verification_required"
        } else {
            "preparing"
        }
        updateNotification(0L, 0L)
    }
    writeNativeWorkerSnapshotAsync(
        isRunning = nativeWorkerJob?.isActive == true,
        isPaused = isNativeWorkerPaused(),
        currentItemId = "",
        message = if (isNativeWorkerPaused()) {
            nativeWorkerPauseMessage()
        } else {
            "Wi-Fi restored"
        },
        includeItems = true,
    )
}

internal fun DownloadService.unregisterNativeWorkerNetworkCallback() {
    val callback = nativeWorkerNetworkCallback
    nativeWorkerNetworkCallback = null
    synchronized(nativeWorkerWifiNetworks) {
        nativeWorkerWifiNetworks.clear()
    }
    if (callback == null) return
    try {
        val connectivityManager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        connectivityManager.unregisterNetworkCallback(callback)
    } catch (_: Exception) {
    }
}
