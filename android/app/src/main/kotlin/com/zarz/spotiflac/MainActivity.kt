package com.zarz.spotiflac

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServicePlugin
import gobackend.Gobackend
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.Locale

class MainActivity: FlutterFragmentActivity() {
    // Mirrors audio_service's AudioServiceFragmentActivity: the shared engine
    // is owned by AudioServicePlugin's FlutterEngineCache. Without the
    // cached-engine-id + shouldDestroyEngineWithHost overrides, the activity
    // (via createFlutterFragment's destroyEngineWithFragment) destroys the
    // provided engine on exit while it stays registered in the cache; when
    // AudioService later stops, disposeFlutterEngine() destroys it a second
    // time and crashes with "FlutterJNI is not attached to native".
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        return AudioServicePlugin.getFlutterEngine(context)
    }

    override fun getCachedEngineId(): String {
        AudioServicePlugin.getFlutterEngine(this)
        return AudioServicePlugin.getFlutterEngineId()
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    private val CHANNEL = "com.zarz.spotiflac/backend"
    private val DOWNLOAD_PROGRESS_STREAM_CHANNEL =
        "com.zarz.spotiflac/download_progress_stream"
    private val LIBRARY_SCAN_PROGRESS_STREAM_CHANNEL =
        "com.zarz.spotiflac/library_scan_progress_stream"
    private val DOWNLOAD_PROGRESS_STREAM_POLLING_INTERVAL_MS = 1200L
    // A progress bar can't show sub-second granularity; 400ms halves the
    // disk-read wakeups during a scan vs the previous 200ms.
    private val LIBRARY_SCAN_PROGRESS_STREAM_POLLING_INTERVAL_MS = 400L
    private val LARGE_JSON_RESULT_FILE_KEY = "__json_file"
    private val LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES = 256 * 1024
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var backendChannel: MethodChannel? = null
    private val pendingSessionGrantEvents = mutableListOf<Map<String, Any>>()
    private var pendingSafTreeResult: MethodChannel.Result? = null
    internal val safScanLock = Any()
    internal var safScanProgress = SafScanProgress()
    private var downloadProgressStreamJob: Job? = null
    private var downloadProgressEventSink: EventChannel.EventSink? = null
    private var lastDownloadProgressPayload: String? = null
    private var lastDownloadProgressSeq = 0L
    private var libraryScanProgressStreamJob: Job? = null
    private var libraryScanProgressEventSink: EventChannel.EventSink? = null
    private var lastLibraryScanProgressPayload: String? = null
    private var flutterBackCallback: OnBackPressedCallback? = null
    @Volatile internal var safScanCancel = false
    @Volatile internal var safScanActive = false
    /** Tri-state: null = untested, true = works, false = fails (Samsung SELinux). */
    @Volatile internal var procSelfFdReadable: Boolean? = null
    private val safTreeLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val result = pendingSafTreeResult ?: return@registerForActivityResult
        pendingSafTreeResult = null

        if (activityResult.resultCode != Activity.RESULT_OK) {
            result.success(null)
            return@registerForActivityResult
        }

        val data = activityResult.data
        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return@registerForActivityResult
        }

        val takeFlags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try {
            contentResolver.takePersistableUriPermission(uri, takeFlags)
        } catch (e: Exception) {
            android.util.Log.w("SpotiFLAC", "Failed to persist SAF permission: ${e.message}")
        }

        val payload = JSONObject()
        payload.put("tree_uri", uri.toString())
        payload.put("display_name", resolveSafDisplayPath(uri))
        result.success(payload.toString())
    }

    /**
     * Resolve a SAF tree URI to a human-readable path.
     * e.g. "content://...tree/primary%3AMusic" -> "/storage/emulated/0/Music"
     *      "content://...tree/1234-5678%3AMusic" -> "SD Card/Music"
     */
    private fun resolveSafDisplayPath(treeUri: Uri): String {
        try {
            val docId = android.provider.DocumentsContract.getTreeDocumentId(treeUri)
            if (docId.isNullOrEmpty()) return treeUri.toString()

            val parts = docId.split(":", limit = 2)
            val storageId = parts.getOrNull(0) ?: return docId
            val subPath = parts.getOrNull(1) ?: ""

            val prefix = if (storageId == "primary") {
                "/storage/emulated/0"
            } else {
                "SD Card"
            }

            return if (subPath.isEmpty()) prefix else "$prefix/$subPath"
        } catch (e: Exception) {
            android.util.Log.w("SpotiFLAC", "Failed to resolve SAF display path: ${e.message}")
            return treeUri.toString()
        }
    }


    data class SafScanProgress(
        var totalFiles: Int = 0,
        var scannedFiles: Int = 0,
        var currentFile: String = "",
        var errorCount: Int = 0,
        var progressPct: Double = 0.0,
        var isComplete: Boolean = false,
    )

    companion object {
        private const val SAFE_API_FOR_IMPELLER = 29

        private val PROBLEMATIC_GPU_PATTERNS = listOf(
            "adreno (tm) 3",
            "adreno (tm) 4",
            "mali-4",
            "mali-t6",
            "mali-t7",
            "powervr sgx",
            "powervr ge8320",
            "vivante",
            "gc1000",
            "gc2000",
            "gc4000",
            "gc5000",
            "gc7000",
            "gc8000",
            "gc820",
            "gc880",
        )

        private val PROBLEMATIC_CHIPSETS = listOf(
            "mt6762",
            "mt6765",
            "mt8768",
            "mp0873",
            "msm8974",
            "msm8226",
            "msm8926",
            "apq8084",
        )

        // Sony Walkman / audio players report MANUFACTURER "SonyAudio" (distinct
        // from Xperia phones, which use "Sony"). They ship legacy Vivante GPUs
        // whose drivers crash in glLinkProgram with Impeller shaders, and the GL
        // renderer string is unavailable when shell args are built, so match on
        // the manufacturer instead.
        private val PROBLEMATIC_MANUFACTURERS = listOf(
            "sonyaudio",
        )

        private val PROBLEMATIC_MODELS = listOf(
            "sm-t220",
            "sm-t225",
            "hammerhead",
        )
        private fun shouldDisableImpeller(): Boolean {
            val hardware = Build.HARDWARE.lowercase(Locale.ROOT)
            val board = Build.BOARD.lowercase(Locale.ROOT)
            val model = Build.MODEL.lowercase(Locale.ROOT)
            val device = Build.DEVICE.lowercase(Locale.ROOT)
            val manufacturer = Build.MANUFACTURER.lowercase(Locale.ROOT)

            for (problematicManufacturer in PROBLEMATIC_MANUFACTURERS) {
                if (manufacturer.contains(problematicManufacturer)) {
                    android.util.Log.i("SpotiFLAC", "Matched problematic manufacturer: $problematicManufacturer")
                    return true
                }
            }

            for (problematicModel in PROBLEMATIC_MODELS) {
                if (model.contains(problematicModel) || device.contains(problematicModel)) {
                    android.util.Log.i("SpotiFLAC", "Matched problematic model: $problematicModel")
                    return true
                }
            }

            for (chipset in PROBLEMATIC_CHIPSETS) {
                if (hardware.contains(chipset) || board.contains(chipset)) {
                    android.util.Log.i("SpotiFLAC", "Matched problematic chipset: $chipset")
                    return true
                }
            }

            if (Build.VERSION.SDK_INT < SAFE_API_FOR_IMPELLER) {
                val gpuRenderer = getGpuRenderer().lowercase(Locale.ROOT)

                for (pattern in PROBLEMATIC_GPU_PATTERNS) {
                    if (gpuRenderer.contains(pattern)) {
                        android.util.Log.i("SpotiFLAC", "Matched problematic GPU on old Android: $pattern")
                        return true
                    }
                }

                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    android.util.Log.i("SpotiFLAC", "Android < 8.0, using Skia for safety")
                    return true
                }
            }

            val gpuRenderer = getGpuRenderer().lowercase(Locale.ROOT)
            for (pattern in PROBLEMATIC_GPU_PATTERNS) {
                if (gpuRenderer.contains(pattern)) {
                    android.util.Log.i("SpotiFLAC", "Matched problematic GPU: $pattern")
                    return true
                }
            }

            return false
        }

    /**
     * Note: This may return empty on some devices before OpenGL context is created.
     */
        private fun getGpuRenderer(): String {
            return try {
                android.opengl.GLES20.glGetString(android.opengl.GLES20.GL_RENDERER) ?: ""
            } catch (e: Exception) {
                ""
            }
        }
    }

    class ImpellerAwareFlutterFragment : FlutterFragment() {
        override fun getFlutterShellArgs(): FlutterShellArgs {
            val args = super.getFlutterShellArgs()
            if (shouldDisableImpeller()) {
                android.util.Log.w("SpotiFLAC", "Legacy/problematic GPU detected for ${Build.MODEL}")
                android.util.Log.w("SpotiFLAC", "Device: ${Build.MANUFACTURER} ${Build.MODEL}, SDK: ${Build.VERSION.SDK_INT}")
                android.util.Log.w("SpotiFLAC", "Hardware: ${Build.HARDWARE}, Board: ${Build.BOARD}")
                args.add("--enable-impeller=false")
            } else {
                android.util.Log.i("SpotiFLAC", "Using Impeller renderer for ${Build.MODEL}")
            }
            return args
        }
    }

    override fun createFlutterFragment(): FlutterFragment {
        val backgroundMode = getBackgroundMode()
        val renderMode = getRenderMode()
        val transparencyMode =
            if (backgroundMode == BackgroundMode.opaque) TransparencyMode.opaque else TransparencyMode.transparent
        val shouldDelayFirstAndroidViewDraw = renderMode == RenderMode.surface

        getCachedEngineId()?.let { cachedEngineId ->
            return FlutterFragment.CachedEngineFragmentBuilder(
                ImpellerAwareFlutterFragment::class.java,
                cachedEngineId
            )
                .renderMode(renderMode)
                .transparencyMode(transparencyMode)
                .handleDeeplinking(shouldHandleDeeplinking())
                .shouldAttachEngineToActivity(shouldAttachEngineToActivity())
                .destroyEngineWithFragment(shouldDestroyEngineWithHost())
                .shouldDelayFirstAndroidViewDraw(shouldDelayFirstAndroidViewDraw)
                .shouldAutomaticallyHandleOnBackPressed(true)
                .build()
        }

        getCachedEngineGroupId()?.let { cachedEngineGroupId ->
            return FlutterFragment.NewEngineInGroupFragmentBuilder(
                ImpellerAwareFlutterFragment::class.java,
                cachedEngineGroupId
            )
                .dartEntrypoint(getDartEntrypointFunctionName())
                .initialRoute(getInitialRoute())
                .handleDeeplinking(shouldHandleDeeplinking())
                .renderMode(renderMode)
                .transparencyMode(transparencyMode)
                .shouldAttachEngineToActivity(shouldAttachEngineToActivity())
                .shouldDelayFirstAndroidViewDraw(shouldDelayFirstAndroidViewDraw)
                .shouldAutomaticallyHandleOnBackPressed(true)
                .build()
        }

        return FlutterFragment.NewEngineFragmentBuilder(ImpellerAwareFlutterFragment::class.java)
            .dartEntrypoint(getDartEntrypointFunctionName())
            .dartLibraryUri(getDartEntrypointLibraryUri() ?: "")
            .dartEntrypointArgs(getDartEntrypointArgs() ?: emptyList())
            .initialRoute(getInitialRoute())
            .appBundlePath(getAppBundlePath())
            .flutterShellArgs(FlutterShellArgs.fromIntent(intent))
            .handleDeeplinking(shouldHandleDeeplinking())
            .renderMode(renderMode)
            .transparencyMode(transparencyMode)
            .shouldAttachEngineToActivity(shouldAttachEngineToActivity())
            .shouldDelayFirstAndroidViewDraw(shouldDelayFirstAndroidViewDraw)
            .shouldAutomaticallyHandleOnBackPressed(true)
            .build()
    }

    private fun parseJsonValue(value: Any?): Any? {
        return when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> {
                val map = LinkedHashMap<String, Any?>()
                val keys = value.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    map[key] = parseJsonValue(value.opt(key))
                }
                map
            }
            is JSONArray -> {
                val list = ArrayList<Any?>()
                for (i in 0 until value.length()) {
                    list.add(parseJsonValue(value.opt(i)))
                }
                list
            }
            is Number, is Boolean, is String -> value
            else -> value.toString()
        }
    }

    private fun parseJsonPayload(payload: String): Any {
        return try {
            parseJsonValue(JSONTokener(payload).nextValue()) ?: payload
        } catch (_: Exception) {
            payload
        }
    }

    private fun bridgeJsonResult(payload: String): Any {
        // Decide on char count where possible: UTF-8 size is >= length and
        // <= 3*length, so only the ambiguous band needs the full encode —
        // avoids duplicating multi-MB payloads just to measure them.
        val definitelySmall = payload.length * 3 < LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES
        val definitelyLarge = payload.length >= LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES
        if (definitelySmall ||
            (!definitelyLarge &&
                payload.toByteArray(Charsets.UTF_8).size < LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES)
        ) {
            return payload
        }

        return try {
            val file = File(cacheDir, "bridge_json_${System.nanoTime()}.json")
            file.writeText(payload, Charsets.UTF_8)
            mapOf(LARGE_JSON_RESULT_FILE_KEY to file.absolutePath)
        } catch (e: Exception) {
            android.util.Log.w(
                "SpotiFLAC",
                "Failed to spill large bridge JSON result to file: ${e.message}",
            )
            payload
        }
    }

    /**
     * Streams a JSON payload piecewise to a cache spill file so large scan
     * results never materialize on the Java heap. [result] hands back the
     * payload inline when it is small (same contract as [bridgeJsonResult]),
     * otherwise the spill-file map.
     */
    internal inner class SpillJsonWriter {
        val file = File(cacheDir, "bridge_json_${System.nanoTime()}.json")
        private val writer = file.bufferedWriter(Charsets.UTF_8)

        fun raw(fragment: String) = writer.write(fragment)

        fun result(): Any {
            writer.close()
            if (file.length() < LARGE_JSON_RESULT_FILE_THRESHOLD_BYTES) {
                val payload = file.readText(Charsets.UTF_8)
                file.delete()
                return payload
            }
            return mapOf(LARGE_JSON_RESULT_FILE_KEY to file.absolutePath)
        }

        fun abandon() {
            try { writer.close() } catch (_: Exception) {}
            try { file.delete() } catch (_: Exception) {}
        }
    }

    private fun updateDownloadProgressSeq(payload: String) {
        try {
            val seq = JSONObject(payload).optLong("seq", lastDownloadProgressSeq)
            if (seq > lastDownloadProgressSeq) {
                lastDownloadProgressSeq = seq
            }
        } catch (_: Exception) {}
    }

    private fun startDownloadProgressStream(sink: EventChannel.EventSink) {
        stopDownloadProgressStream()
        downloadProgressEventSink = sink
        lastDownloadProgressPayload = null
        lastDownloadProgressSeq = 0L
        downloadProgressStreamJob = scope.launch {
            while (isActive && downloadProgressEventSink === sink) {
                try {
                    val payload = withContext(Dispatchers.IO) {
                        Gobackend.getAllDownloadProgressDelta(lastDownloadProgressSeq)
                    }
                    if (payload.isNotEmpty() && payload != lastDownloadProgressPayload) {
                        updateDownloadProgressSeq(payload)
                        lastDownloadProgressPayload = payload
                        sink.success(parseJsonPayload(payload))
                    }
                } catch (e: Exception) {
                    android.util.Log.w(
                        "SpotiFLAC",
                        "Download progress stream poll failed: ${e.message}",
                    )
                }
                delay(DOWNLOAD_PROGRESS_STREAM_POLLING_INTERVAL_MS)
            }
        }
    }

    private fun stopDownloadProgressStream() {
        downloadProgressStreamJob?.cancel()
        downloadProgressStreamJob = null
        downloadProgressEventSink = null
        lastDownloadProgressPayload = null
        lastDownloadProgressSeq = 0L
    }

    private fun startLibraryScanProgressStream(sink: EventChannel.EventSink) {
        stopLibraryScanProgressStream()
        libraryScanProgressEventSink = sink
        lastLibraryScanProgressPayload = null
        libraryScanProgressStreamJob = scope.launch {
            try {
                val initialPayload = withContext(Dispatchers.IO) {
                    readLibraryScanProgressJsonForStream()
                }
                lastLibraryScanProgressPayload = initialPayload
                sink.success(parseJsonPayload(initialPayload))
            } catch (e: Exception) {
                android.util.Log.w(
                    "SpotiFLAC",
                    "Library scan progress initial poll failed: ${e.message}",
                )
            }
            while (isActive && libraryScanProgressEventSink === sink) {
                try {
                    val payload = withContext(Dispatchers.IO) {
                        readLibraryScanProgressJsonForStream()
                    }
                    if (payload != lastLibraryScanProgressPayload) {
                        lastLibraryScanProgressPayload = payload
                        sink.success(parseJsonPayload(payload))
                    }
                } catch (e: Exception) {
                    android.util.Log.w(
                        "SpotiFLAC",
                        "Library scan progress stream poll failed: ${e.message}",
                    )
                }
                delay(LIBRARY_SCAN_PROGRESS_STREAM_POLLING_INTERVAL_MS)
            }
        }
    }

    private fun stopLibraryScanProgressStream() {
        libraryScanProgressStreamJob?.cancel()
        libraryScanProgressStreamJob = null
        libraryScanProgressEventSink = null
        lastLibraryScanProgressPayload = null
    }

    // Disable Flutter's built-in deep linking so that incoming ACTION_VIEW URLs
    // (Spotify, Deezer, Tidal, YouTube Music) are NOT forwarded to GoRouter.
    // We handle these URLs ourselves via receive_sharing_intent + ShareIntentService.
    override fun shouldHandleDeeplinking(): Boolean = false

    // Bridge spill files and SAF temp copies are deleted after use on the
    // normal path, but a process kill mid-operation orphans them in cacheDir
    // forever (names embed nanoTime, so nothing overwrites them). Sweep
    // leftovers from previous sessions; the 1h age guard protects in-flight
    // files from concurrent work in this session.
    private fun sweepStaleCacheFiles() {
        scope.launch(Dispatchers.IO) {
            try {
                val cutoff = System.currentTimeMillis() - 60 * 60 * 1000L
                cacheDir.listFiles()?.forEach { file ->
                    val stale = file.isFile &&
                        file.lastModified() < cutoff &&
                        (file.name.startsWith("bridge_json_") ||
                            file.name.startsWith("saf_") ||
                            file.name.startsWith("ms_"))
                    if (stale) file.delete()
                }
            } catch (_: Exception) {}
        }
    }

    /**
     * Creates an install-scoped marker in noBackupFilesDir. A platform restore
     * can bring SharedPreferences back after reinstall, but this marker is never
     * backed up. Package timestamps distinguish that case from the first app
     * update after this marker was introduced, so existing users are not sent
     * through onboarding again.
     */
    private fun ensureInstallMarker(): Map<String, Any> {
        val marker = File(noBackupFilesDir, "installation_state_v1")
        val markerExisted = marker.isFile
        val packageInfo = @Suppress("DEPRECATION")
        packageManager.getPackageInfo(packageName, 0)
        val installTimestampDelta = kotlin.math.abs(
            packageInfo.lastUpdateTime - packageInfo.firstInstallTime
        )
        val looksLikeFreshPackageInstall = installTimestampDelta <= 10_000L

        var markerCreated = markerExisted
        if (!markerExisted) {
            markerCreated = try {
                marker.parentFile?.mkdirs()
                marker.writeText(
                    "created_at=${System.currentTimeMillis()}\n" +
                        "version_code=${BuildConfig.VERSION_CODE}\n"
                )
                true
            } catch (e: Exception) {
                android.util.Log.w(
                    "SpotiFLAC",
                    "Failed to create installation marker: ${e.message}"
                )
                false
            }
        }

        return mapOf(
            "marker_existed" to markerExisted,
            "marker_created" to markerCreated,
            "fresh_package_install" to looksLikeFreshPackageInstall,
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Ensure the shared audio_service engine exists before the activity
        // delegate looks it up by cached id (see getCachedEngineId above).
        AudioServicePlugin.getFlutterEngine(this)
        super.onCreate(savedInstanceState)
        handleExtensionOAuthIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleExtensionOAuthIntent(intent)
    }

    /**
     * Deliver Spotify (or other) OAuth authorization code to the extension runtime
     * and run its token exchange (e.g. completeSpotifyLogin). State must be the extension id.
     */
    private fun handleExtensionOAuthIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        if (!uri.scheme.equals("spotiflac", ignoreCase = true)) {
            return
        }
        val host = (uri.host ?: "").lowercase(Locale.US)
        val path = (uri.path ?: "").lowercase(Locale.US)
        val isSessionGrant = host == "session-grant"
        val isCallback =
            isSessionGrant ||
                host == "callback" ||
                host == "spotify-callback" ||
                path.contains("callback")
        if (!isCallback) {
            return
        }
        val code = (
            if (isSessionGrant) {
                uri.getQueryParameter("grant") ?: uri.getQueryParameter("code")
            } else {
                uri.getQueryParameter("code")
            }
        )?.trim().orEmpty()
        if (code.isEmpty()) {
            return
        }
        val extId = uri.getQueryParameter("state")?.trim().orEmpty()
        if (extId.isEmpty()) {
            android.util.Log.w("SpotiFLAC", "Extension OAuth redirect missing state (extension id)")
            return
        }
        intent.data = null
        scope.launch(Dispatchers.IO) {
            try {
                val json = if (isSessionGrant) {
                    Gobackend.setExtensionSessionGrantByID(extId, code)
                    Gobackend.invokeExtensionActionJSON(extId, "completeGrant")
                } else {
                    Gobackend.setExtensionAuthCodeByID(extId, code)
                    Gobackend.invokeExtensionActionJSON(extId, "completeSpotifyLogin")
                }
                if (isSessionGrant) {
                    requireSuccessfulExtensionAction(extId, "completeGrant", json)
                }
                android.util.Log.i("SpotiFLAC", "Extension callback complete for $extId: $json")
                if (isSessionGrant) {
                    withContext(Dispatchers.Main) {
                        notifySessionGrantCompleted(extId, true)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.w("SpotiFLAC", "Extension callback failed: ${e.message}")
                if (isSessionGrant) {
                    withContext(Dispatchers.Main) {
                        notifySessionGrantCompleted(extId, false)
                    }
                }
            }
        }
    }

    private fun requireSuccessfulExtensionAction(extensionId: String, actionName: String, response: String) {
        val obj = try {
            JSONObject(response)
        } catch (e: Exception) {
            throw IllegalStateException(
                "Extension $actionName for $extensionId returned invalid JSON: ${response.take(240)}"
            )
        }
        if (obj.optBoolean("success", false)) {
            return
        }
        val error = obj.optString("error")
            .ifBlank { obj.optString("message") }
            .ifBlank { response.take(240) }
        throw IllegalStateException("Extension $actionName failed for $extensionId: $error")
    }

    private fun notifySessionGrantCompleted(extensionId: String, success: Boolean) {
        val payload = mapOf(
            "extension_id" to extensionId,
            "success" to success,
        )
        val channel = backendChannel
        if (channel == null) {
            pendingSessionGrantEvents.add(payload)
            return
        }
        channel.invokeMethod("extensionSessionGrantCompleted", payload)
    }

    override fun onDestroy() {
        try {
            Gobackend.cleanupExtensions()
        } catch (e: Exception) {
            android.util.Log.w("SpotiFLAC", "Failed to cleanup extensions on destroy: ${e.message}")
        }
        stopDownloadProgressStream()
        stopLibraryScanProgressStream()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Gobackend.setAppVersion(BuildConfig.VERSION_NAME)
        sweepStaleCacheFiles()

        // Always-enabled back callback to ensure back presses reach Flutter.
        // Nested tab navigators can incorrectly set frameworkHandlesBack(false),
        // which disables Flutter's own OnBackPressedCallback and causes the
        // system default (finish activity) to run. This callback guarantees
        // popRoute is always forwarded to Flutter, where PopScope handles it.
        flutterBackCallback = object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                flutterEngine.navigationChannel.popRoute()
            }
        }
        onBackPressedDispatcher.addCallback(this, flutterBackCallback!!)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(
            messenger,
            DOWNLOAD_PROGRESS_STREAM_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events != null) {
                        startDownloadProgressStream(events)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    stopDownloadProgressStream()
                }
            },
        )

        EventChannel(
            messenger,
            LIBRARY_SCAN_PROGRESS_STREAM_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events != null) {
                        startLibraryScanProgressStream(events)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    stopLibraryScanProgressStream()
                }
            },
        )

        val channel = MethodChannel(messenger, CHANNEL)
        backendChannel = channel
        if (pendingSessionGrantEvents.isNotEmpty()) {
            val events = pendingSessionGrantEvents.toList()
            pendingSessionGrantEvents.clear()
            for (event in events) {
                channel.invokeMethod("extensionSessionGrantCompleted", event)
            }
        }

        channel.setMethodCallHandler { call, result ->
            scope.launch {
                try {
                    when (call.method) {
                        "ensureInstallMarker" -> {
                            val installState = withContext(Dispatchers.IO) {
                                ensureInstallMarker()
                            }
                            result.success(installState)
                        }
                        "exitApp" -> {
                            flutterBackCallback?.isEnabled = false
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                finishAndRemoveTask()
                            } else {
                                finish()
                            }
                            result.success(null)
                        }
                        "downloadByStrategy" -> {
                            val requestJson = call.arguments as String
                            val response = withContext(Dispatchers.IO) {
                                SafDownloadHandler.handle(this@MainActivity, requestJson) { json ->
                                    Gobackend.downloadByStrategy(json)
                                }
                            }
                            result.success(response)
                        }
                        "getAllDownloadProgress" -> {
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getAllDownloadProgress()
                            }
                            result.success(parseJsonPayload(response))
                        }
                        "clearItemProgress" -> {
                            val itemId = call.argument<String>("item_id") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.clearItemProgress(itemId)
                            }
                            result.success(null)
                        }
                        "cancelDownload" -> {
                            val itemId = call.argument<String>("item_id") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.cancelDownload(itemId)
                            }
                            result.success(null)
                        }
                        "resetDownloadCancel" -> {
                            val itemId = call.argument<String>("item_id") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.resetDownloadCancel(itemId)
                            }
                            result.success(null)
                        }
                        "setDownloadDirectory" -> {
                            val path = call.argument<String>("path") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.setDownloadDirectory(path)
                            }
                            result.success(null)
                        }
                        "setNetworkCompatibilityOptions", "setSongLinkNetworkOptions" -> {
                            val allowHttp = call.argument<Boolean>("allow_http") ?: false
                            val insecureTls = call.argument<Boolean>("insecure_tls") ?: false
                            withContext(Dispatchers.IO) {
                                Gobackend.setNetworkCompatibilityOptions(allowHttp, insecureTls)
                            }
                            result.success(null)
                        }
                        "setAllowPrivateNetwork" -> {
                            val allowed = call.argument<Boolean>("allowed") ?: false
                            withContext(Dispatchers.IO) {
                                Gobackend.setAllowPrivateNetwork(allowed)
                            }
                            result.success(null)
                        }
                        "checkDuplicatesBatch" -> {
                            val outputDir = call.argument<String>("output_dir") ?: ""
                            val tracksJson = call.argument<String>("tracks") ?: "[]"
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.checkDuplicatesBatch(outputDir, tracksJson)
                            }
                            result.success(response)
                        }
                        "preBuildDuplicateIndex" -> {
                            val outputDir = call.argument<String>("output_dir") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.preBuildDuplicateIndex(outputDir)
                            }
                            result.success(null)
                        }
                        "invalidateDuplicateIndex" -> {
                            val outputDir = call.argument<String>("output_dir") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.invalidateDuplicateIndex(outputDir)
                            }
                            result.success(null)
                        }
                        "buildFilename" -> {
                            val template = call.argument<String>("template") ?: ""
                            val metadata = call.argument<String>("metadata") ?: "{}"
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.buildFilename(template, metadata)
                            }
                            result.success(response)
                        }
                        "sanitizeFilename" -> {
                            val filename = call.argument<String>("filename") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.sanitizeFilename(filename)
                            }
                            result.success(response)
                        }
                        "pickSafTree" -> {
                            if (pendingSafTreeResult != null) {
                                result.error("saf_pending", "SAF picker already active", null)
                                return@launch
                            }
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                            intent.addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                            )
                            val resolver = intent.resolveActivity(packageManager)
                            if (resolver == null) {
                                result.error("saf_unavailable", "No folder picker available on this device", null)
                                return@launch
                            }
                            pendingSafTreeResult = result
                            try {
                                android.util.Log.i("SpotiFLAC", "Launching SAF picker via $resolver")
                                safTreeLauncher.launch(intent)
                            } catch (e: Exception) {
                                pendingSafTreeResult = null
                                android.util.Log.e("SpotiFLAC", "Failed to launch SAF picker: ${e.message}", e)
                                result.error(
                                    "saf_launch_failed",
                                    e.message ?: "Failed to launch folder picker",
                                    null
                                )
                            }
                        }
                        "safExists" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val exists = withContext(Dispatchers.IO) {
                                val uri = Uri.parse(uriStr)
                                DocumentFile.fromSingleUri(this@MainActivity, uri)?.exists() == true
                            }
                            result.success(exists)
                        }
                        "isSafTreeAccessible" -> {
                            val uriStr = call.argument<String>("tree_uri") ?: ""
                            val accessible = withContext(Dispatchers.IO) {
                                try {
                                    val uri = Uri.parse(uriStr)
                                    val persisted = contentResolver.persistedUriPermissions.any {
                                        it.uri == uri && it.isReadPermission && it.isWritePermission
                                    }
                                    if (!persisted) {
                                        false
                                    } else {
                                        val doc = DocumentFile.fromTreeUri(this@MainActivity, uri)
                                        doc != null && doc.exists() && doc.canWrite()
                                    }
                                } catch (e: Exception) {
                                    android.util.Log.w("SpotiFLAC", "SAF tree access check failed: ${e.message}")
                                    false
                                }
                            }
                            result.success(accessible)
                        }
                        "safDelete" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val deleted = withContext(Dispatchers.IO) {
                                val uri = Uri.parse(uriStr)
                                DocumentFile.fromSingleUri(this@MainActivity, uri)?.delete() == true
                            }
                            result.success(deleted)
                        }
                        "safStat" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                val uri = Uri.parse(uriStr)
                                val doc = DocumentFile.fromSingleUri(this@MainActivity, uri)
                                val obj = JSONObject()
                                if (doc != null && doc.exists()) {
                                    obj.put("exists", true)
                                    obj.put("size", doc.length())
                                    obj.put("modified", doc.lastModified())
                                    obj.put("mime_type", doc.type ?: contentResolver.getType(uri) ?: "")
                                } else {
                                    obj.put("exists", false)
                                    obj.put("size", 0)
                                    obj.put("modified", 0)
                                    obj.put("mime_type", "")
                                }
                                obj.toString()
                            }
                            result.success(response)
                        }
                        "resolveSafFile" -> {
                            val treeUriStr = call.argument<String>("tree_uri") ?: ""
                            val relativeDir = call.argument<String>("relative_dir") ?: ""
                            val fileName = call.argument<String>("file_name") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                resolveSafFile(treeUriStr, relativeDir, fileName)
                            }
                            result.success(response)
                        }
                        "safCopyToTemp" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val tempPath = withContext(Dispatchers.IO) {
                                copyUriToTemp(Uri.parse(uriStr))
                            }
                            result.success(tempPath)
                        }
                        "safCreateFromPath" -> {
                            val treeUriStr = call.argument<String>("tree_uri") ?: ""
                            val relativeDir = call.argument<String>("relative_dir") ?: ""
                            val fileName = SafDownloadHandler.sanitizeFilename(call.argument<String>("file_name") ?: "")
                            val mimeType = call.argument<String>("mime_type") ?: "application/octet-stream"
                            val srcPath = call.argument<String>("src_path") ?: ""
                            val createdUri = withContext(Dispatchers.IO) {
                                if (treeUriStr.isBlank()) return@withContext null
                                if (fileName.isBlank()) return@withContext null
                                val dir = SafDownloadHandler.ensureDocumentDir(this@MainActivity, Uri.parse(treeUriStr), relativeDir) ?: return@withContext null
                                val existing = dir.findFile(fileName)
                                val createdNew = existing == null
                                val doc = SafDownloadHandler.createOrReuseDocumentFile(dir, mimeType, fileName)
                                    ?: return@withContext null
                                if (!writeUriFromPath(doc.uri, srcPath)) {
                                    if (createdNew) {
                                        doc.delete()
                                    }
                                    return@withContext null
                                }
                                doc.uri.toString()
                            }
                            result.success(createdUri)
                        }
                        "safCreateUniqueFromPath" -> {
                            val treeUriStr = call.argument<String>("tree_uri") ?: ""
                            val relativeDir = call.argument<String>("relative_dir") ?: ""
                            val fileName = call.argument<String>("file_name") ?: ""
                            val mimeType = call.argument<String>("mime_type") ?: "application/octet-stream"
                            val srcPath = call.argument<String>("src_path") ?: ""
                            val preservedSuffix = call.argument<String>("preserved_suffix") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                if (treeUriStr.isBlank() || fileName.isBlank()) return@withContext null
                                SafDownloadHandler.writeFileToSafUnique(
                                    context = this@MainActivity,
                                    treeUriStr = treeUriStr,
                                    relativeDir = relativeDir,
                                    fileName = fileName,
                                    mimeType = mimeType,
                                    srcPath = srcPath,
                                    preservedSuffix = preservedSuffix,
                                )?.let { writeResult ->
                                    JSONObject()
                                        .put("uri", writeResult.uri)
                                        .put("file_name", writeResult.fileName)
                                        .toString()
                                }
                            }
                            result.success(response)
                        }
                        "safCreateCollisionAwareFromPath" -> {
                            val treeUriStr = call.argument<String>("tree_uri") ?: ""
                            val relativeDir = call.argument<String>("relative_dir") ?: ""
                            val cleanFileName = call.argument<String>("clean_file_name") ?: ""
                            val variantFileName = call.argument<String>("variant_file_name") ?: ""
                            val mimeType = call.argument<String>("mime_type") ?: "application/octet-stream"
                            val srcPath = call.argument<String>("src_path") ?: ""
                            val preservedSuffix = call.argument<String>("preserved_suffix") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                if (
                                    treeUriStr.isBlank() ||
                                    cleanFileName.isBlank() ||
                                    variantFileName.isBlank()
                                ) return@withContext null
                                SafDownloadHandler.writeFileToSafCollisionAware(
                                    context = this@MainActivity,
                                    treeUriStr = treeUriStr,
                                    relativeDir = relativeDir,
                                    cleanFileName = cleanFileName,
                                    variantFileName = variantFileName,
                                    mimeType = mimeType,
                                    srcPath = srcPath,
                                    preservedSuffix = preservedSuffix,
                                )?.let { writeResult ->
                                    JSONObject()
                                        .put("uri", writeResult.uri)
                                        .put("file_name", writeResult.fileName)
                                        .toString()
                                }
                            }
                            result.success(response)
                        }
                        "openContentUri" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val mimeType = call.argument<String>("mime_type") ?: ""
                            try {
                                val uri = Uri.parse(uriStr)
                                val type = if (mimeType.isNotBlank()) mimeType else contentResolver.getType(uri) ?: "*/*"
                                val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, type)
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                startActivity(intent)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("open_failed", e.message, null)
                            }
                        }
                        "shareContentUri" -> {
                            val uriStr = call.argument<String>("uri") ?: ""
                            val title = call.argument<String>("title") ?: ""
                            try {
                                val uri = Uri.parse(uriStr)
                                val type = contentResolver.getType(uri) ?: "audio/*"
                                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    setType(type)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    if (title.isNotBlank()) {
                                        putExtra(Intent.EXTRA_SUBJECT, title)
                                    }
                                }
                                startActivity(Intent.createChooser(shareIntent, title.ifBlank { "Share" }))
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("share_failed", e.message, null)
                            }
                        }
                        "shareMultipleContentUris" -> {
                            val uriStrings = call.argument<List<String>>("uris") ?: emptyList()
                            val title = call.argument<String>("title") ?: ""
                            try {
                                val uris = ArrayList<Uri>(uriStrings.size)
                                for (s in uriStrings) {
                                    uris.add(Uri.parse(s))
                                }
                                val shareIntent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                                    setType("audio/*")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    if (title.isNotBlank()) {
                                        putExtra(Intent.EXTRA_SUBJECT, title)
                                    }
                                }
                                startActivity(Intent.createChooser(shareIntent, title.ifBlank { "Share" }))
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("share_failed", e.message, null)
                            }
                        }
                        "getLyricsLRC" -> {
                            val spotifyId = call.argument<String>("spotify_id") ?: ""
                            val trackName = call.argument<String>("track_name") ?: ""
                            val artistName = call.argument<String>("artist_name") ?: ""
                            val filePath = call.argument<String>("file_path") ?: ""
                            val durationMs = call.argument<Int>("duration_ms")?.toLong() ?: 0L
                            val response = withContext(Dispatchers.IO) {
                                if (filePath.startsWith("content://")) {
                                    val tempPath = copyUriToTemp(Uri.parse(filePath))
                                    if (tempPath == null) {
                                        ""
                                    } else {
                                        try {
                                            Gobackend.getLyricsLRC(spotifyId, trackName, artistName, tempPath, durationMs)
                                        } finally {
                                            try {
                                                File(tempPath).delete()
                                            } catch (_: Exception) {}
                                        }
                                    }
                                } else {
                                    Gobackend.getLyricsLRC(spotifyId, trackName, artistName, filePath, durationMs)
                                }
                            }
                            result.success(response)
                        }
                        "getLyricsLRCWithSource" -> {
                            val spotifyId = call.argument<String>("spotify_id") ?: ""
                            val trackName = call.argument<String>("track_name") ?: ""
                            val artistName = call.argument<String>("artist_name") ?: ""
                            val filePath = call.argument<String>("file_path") ?: ""
                            val durationMs = call.argument<Int>("duration_ms")?.toLong() ?: 0L
                            val response = withContext(Dispatchers.IO) {
                                if (filePath.startsWith("content://")) {
                                    val tempPath = copyUriToTemp(Uri.parse(filePath))
                                    if (tempPath == null) {
                                        """{"lyrics":"","source":"","sync_type":"","instrumental":false}"""
                                    } else {
                                        try {
                                            Gobackend.getLyricsLRCWithSource(spotifyId, trackName, artistName, tempPath, durationMs)
                                        } finally {
                                            try {
                                                File(tempPath).delete()
                                            } catch (_: Exception) {}
                                        }
                                    }
                                } else {
                                    Gobackend.getLyricsLRCWithSource(spotifyId, trackName, artistName, filePath, durationMs)
                                }
                            }
                            result.success(response)
                        }
                        "embedLyricsToFile" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val lyrics = call.argument<String>("lyrics") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                if (filePath.startsWith("content://")) {
                                    val uri = Uri.parse(filePath)
                                    val tempPath = copyUriToTemp(uri, ".flac")
                                        ?: return@withContext errorJson("Failed to copy SAF file to temp")
                                    try {
                                        val raw = Gobackend.embedLyricsToFile(tempPath, lyrics)
                                        val obj = JSONObject(raw)
                                        if (!obj.optBoolean("success", false)) {
                                            return@withContext raw
                                        }

                                        if (!writeUriFromPath(uri, tempPath)) {
                                            return@withContext errorJson("Failed to write embedded lyrics back to SAF file")
                                        }

                                        obj.put("file_path", filePath)
                                        obj.toString()
                                    } catch (e: Exception) {
                                        errorJson("Failed to embed lyrics to SAF file: ${e.message}")
                                    } finally {
                                        try {
                                            File(tempPath).delete()
                                        } catch (_: Exception) {}
                                    }
                                } else {
                                    Gobackend.embedLyricsToFile(filePath, lyrics)
                                }
                            }
                            result.success(response)
                        }
                        "rewriteSplitArtistTags" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val artist = call.argument<String>("artist") ?: ""
                            val albumArtist = call.argument<String>("album_artist") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                if (filePath.startsWith("content://")) {
                                    val uri = Uri.parse(filePath)
                                    val tempPath = copyUriToTemp(uri, ".flac")
                                        ?: return@withContext errorJson("Failed to copy SAF file to temp")
                                    try {
                                        val raw = Gobackend.rewriteSplitArtistTagsExport(tempPath, artist, albumArtist)
                                        val obj = JSONObject(raw)
                                        if (!obj.optBoolean("success", false)) {
                                            return@withContext raw
                                        }

                                        if (!writeUriFromPath(uri, tempPath)) {
                                            return@withContext errorJson("Failed to write rewritten tags back to SAF file")
                                        }

                                        obj.put("file_path", filePath)
                                        obj.toString()
                                    } catch (e: Exception) {
                                        errorJson("Failed to rewrite split artist tags in SAF file: ${e.message}")
                                    } finally {
                                        try {
                                            File(tempPath).delete()
                                        } catch (_: Exception) {}
                                    }
                                } else {
                                    Gobackend.rewriteSplitArtistTagsExport(filePath, artist, albumArtist)
                                }
                            }
                            result.success(response)
                        }
                        "cleanupConnections" -> {
                            withContext(Dispatchers.IO) {
                                Gobackend.cleanupConnections()
                            }
                            result.success(null)
                        }
                        "readFileMetadata" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (filePath.startsWith("content://")) {
                                        val uri = Uri.parse(filePath)
                                        val tempPath = copyUriToTemp(uri)
                                            ?: return@withContext """{"error":"Failed to copy SAF file to temp"}"""
                                        try {
                                            Gobackend.readFileMetadata(tempPath)
                                        } finally {
                                            try { File(tempPath).delete() } catch (_: Exception) {}
                                        }
                                    } else {
                                        Gobackend.readFileMetadata(filePath)
                                    }
                                } catch (e: Exception) {
                                    android.util.Log.e("SpotiFLAC", "readFileMetadata failed: ${e.message}", e)
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        "editFileMetadata" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val metadataJson = call.argument<String>("metadata_json") ?: "{}"
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (filePath.startsWith("content://")) {
                                        val uri = Uri.parse(filePath)
                                        val tempPath = copyUriToTemp(uri)
                                            ?: return@withContext """{"error":"Failed to copy SAF file to temp"}"""
                                        try {
                                            val raw = Gobackend.editFileMetadata(tempPath, metadataJson)
                                            val obj = JSONObject(raw)
                                            val method = obj.optString("method", "")
                                            if (method == "ffmpeg") {
                                                // MP3/Opus: Dart needs to FFmpeg the temp file, then call writeTempToSaf
                                                obj.put("temp_path", tempPath)
                                                obj.put("saf_uri", filePath)
                                                return@withContext obj.toString()
                                                // Note: temp file NOT deleted here - Dart will clean up after FFmpeg + writeTempToSaf
                                            }
                            // FLAC: Go wrote directly to temp, copy back now
                            if (!writeUriFromPath(uri, tempPath)) {
                                try { File(tempPath).delete() } catch (_: Exception) {}
                                return@withContext """{"error":"Failed to write metadata back to SAF file"}"""
                            }
                            try { File(tempPath).delete() } catch (_: Exception) {}
                            raw
                                        } catch (e: Exception) {
                                            try { File(tempPath).delete() } catch (_: Exception) {}
                                            throw e
                                        }
                                    } else {
                                        Gobackend.editFileMetadata(filePath, metadataJson)
                                    }
                                } catch (e: Exception) {
                                    android.util.Log.e("SpotiFLAC", "editFileMetadata failed: ${e.message}", e)
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        "writeM4AFreeformTags" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val metadataJson = call.argument<String>("metadata_json") ?: "{}"
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    Gobackend.writeM4AFreeformTags(filePath, metadataJson)
                                } catch (e: Exception) {
                                    android.util.Log.e("SpotiFLAC", "writeM4AFreeformTags failed: ${e.message}", e)
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        "ensureAC4Config" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val sourcePath = call.argument<String>("source_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    Gobackend.ensureAC4Config(filePath, sourcePath)
                                } catch (e: Exception) {
                                    android.util.Log.e("SpotiFLAC", "ensureAC4Config failed: ${e.message}", e)
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        "writeAC4Metadata" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val metadataJson = call.argument<String>("metadata_json") ?: "{}"
                            val coverPath = call.argument<String>("cover_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    Gobackend.writeAC4Metadata(filePath, metadataJson, coverPath)
                                } catch (e: Exception) {
                                    android.util.Log.e("SpotiFLAC", "writeAC4Metadata failed: ${e.message}", e)
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        "writeTempToSaf" -> {
                            val tempPath = call.argument<String>("temp_path") ?: ""
                            val safUri = call.argument<String>("saf_uri") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    val uri = Uri.parse(safUri)
                                    if (writeUriFromPath(uri, tempPath)) {
                                        """{"success":true}"""
                                    } else {
                                        """{"success":false,"error":"Failed to write back to SAF"}"""
                                    }
                                } finally {
                                    try { File(tempPath).delete() } catch (_: Exception) {}
                                }
                            }
                            result.success(response)
                        }
                        "writeSafSidecarLrc" -> {
                            val safUri = call.argument<String>("saf_uri") ?: ""
                            val lyrics = call.argument<String>("lyrics") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    val uri = Uri.parse(safUri)
                                    if (writeSafSidecarLrc(uri, lyrics)) {
                                        """{"success":true}"""
                                    } else {
                                        """{"success":false,"error":"Failed to write LRC sidecar"}"""
                                    }
                                } catch (e: Exception) {
                                    """{"success":false,"error":"${e.message?.replace("\"", "'")}"}"""
                                }
                            }
                            result.success(response)
                        }
                        "downloadCoverToFile" -> {
                            val coverUrl = call.argument<String>("cover_url") ?: ""
                            val outputPath = call.argument<String>("output_path") ?: ""
                            val maxQuality = call.argument<Boolean>("max_quality") ?: true
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    Gobackend.downloadCoverToFile(coverUrl, outputPath, maxQuality)
                                    """{"success":true}"""
                                } catch (e: Exception) {
                                    """{"success":false,"error":"${e.message?.replace("\"", "'")}"}"""
                                }
                            }
                            result.success(response)
                        }
                        "extractCoverToFile" -> {
                            val audioPath = call.argument<String>("audio_path") ?: ""
                            val outputPath = call.argument<String>("output_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (audioPath.startsWith("content://")) {
                                        val uri = Uri.parse(audioPath)
                                        val tempPath = copyUriToTemp(uri)
                                            ?: return@withContext """{"success":false,"error":"Failed to copy SAF file to temp"}"""
                                        try {
                                            Gobackend.extractCoverToFile(tempPath, outputPath)
                                            """{"success":true}"""
                                        } finally {
                                            try { File(tempPath).delete() } catch (_: Exception) {}
                                        }
                                    } else {
                                        Gobackend.extractCoverToFile(audioPath, outputPath)
                                        """{"success":true}"""
                                    }
                                } catch (e: Exception) {
                                    """{"success":false,"error":"${e.message?.replace("\"", "'")}"}"""
                                }
                            }
                            result.success(response)
                        }
                        "fetchAndSaveLyrics" -> {
                            val trackName = call.argument<String>("track_name") ?: ""
                            val artistName = call.argument<String>("artist_name") ?: ""
                            val spotifyId = call.argument<String>("spotify_id") ?: ""
                            val durationMs = call.argument<Number>("duration_ms")?.toLong() ?: 0L
                            val outputPath = call.argument<String>("output_path") ?: ""
                            val rawAudioFilePath = call.argument<String>("audio_file_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                var safAudioTemp: String? = null
                                try {
                                    // Resolve SAF content:// URI to a temp file the Go backend can read
                                    val audioFilePath = if (rawAudioFilePath.startsWith("content://")) {
                                        val uri = Uri.parse(rawAudioFilePath)
                                        val tempPath = copyUriToTemp(uri)
                                        safAudioTemp = tempPath
                                        tempPath ?: ""
                                    } else {
                                        rawAudioFilePath
                                    }
                                    Gobackend.fetchAndSaveLyrics(trackName, artistName, spotifyId, durationMs, outputPath, audioFilePath)
                                    """{"success":true}"""
                                } catch (e: Exception) {
                                    """{"success":false,"error":"${e.message?.replace("\"", "'")}"}"""
                                } finally {
                                    if (safAudioTemp != null) {
                                        try { File(safAudioTemp).delete() } catch (_: Exception) {}
                                    }
                                }
                            }
                            result.success(response)
                        }
                        "setLyricsProviders" -> {
                            val providersJson = call.argument<String>("providers_json") ?: "[]"
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    Gobackend.setLyricsProvidersJSON(providersJson)
                                    """{"success":true}"""
                                } catch (e: Exception) {
                                    """{"success":false,"error":"${e.message?.replace("\"", "'")}"}"""
                                }
                            }
                            result.success(response)
                        }
                        "getLyricsProviders" -> {
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    Gobackend.getLyricsProvidersJSON()
                                } catch (e: Exception) {
                                    "[]"
                                }
                            }
                            result.success(response)
                        }
                        "getAvailableLyricsProviders" -> {
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    Gobackend.getAvailableLyricsProvidersJSON()
                                } catch (e: Exception) {
                                    "[]"
                                }
                            }
                            result.success(response)
                        }
                        "setLyricsFetchOptions" -> {
                            val optionsJson = call.argument<String>("options_json") ?: "{}"
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    Gobackend.setLyricsFetchOptionsJSON(optionsJson)
                                    """{"success":true}"""
                                } catch (e: Exception) {
                                    """{"success":false,"error":"${e.message?.replace("\"", "'")}"}"""
                                }
                            }
                            result.success(response)
                        }
                        "getLyricsFetchOptions" -> {
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    Gobackend.getLyricsFetchOptionsJSON()
                                } catch (e: Exception) {
                                    "{}"
                                }
                            }
                            result.success(response)
                        }
                        "reEnrichFile" -> {
                            val requestJson = call.argument<String>("request_json") ?: "{}"
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    val reqObj = JSONObject(requestJson)
                                    val filePath = reqObj.optString("file_path", "")

                                    if (filePath.startsWith("content://")) {
                                        val uri = Uri.parse(filePath)
                                        val tempPath = copyUriToTemp(uri)
                                            ?: return@withContext """{"error":"Failed to copy SAF file to temp"}"""
                                        try {
                                            reqObj.put("file_path", tempPath)
                                            val raw = Gobackend.reEnrichFile(reqObj.toString())
                                            val obj = JSONObject(raw)

                                            if (obj.has("error")) {
                                                return@withContext raw
                                            }

                                            val method = obj.optString("method", "")
                                            if (method == "ffmpeg") {
                                                // MP3/Opus: Dart handles FFmpeg on temp file, then writes back
                                                obj.put("temp_path", tempPath)
                                                obj.put("saf_uri", filePath)
                                                return@withContext obj.toString()
                                                // temp file NOT deleted - Dart cleans up after FFmpeg + writeTempToSaf
                                            }

                                            // FLAC: Go wrote directly to temp, copy back now
                                            if (!writeUriFromPath(uri, tempPath)) {
                                                return@withContext """{"error":"Failed to write enriched metadata back to SAF file"}"""
                                            }
                                            if (obj.optBoolean("write_external_lrc", false)) {
                                                writeSafSidecarLrc(uri, obj.optString("lyrics", ""))
                                            }
                                            raw
                                        } catch (e: Exception) {
                                            try { File(tempPath).delete() } catch (_: Exception) {}
                                            throw e
                                        }
                                    } else {
                                        Gobackend.reEnrichFile(requestJson)
                                    }
                                } catch (e: Exception) {
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        "startDownloadService" -> {
                            val trackName = call.argument<String>("track_name") ?: ""
                            val artistName = call.argument<String>("artist_name") ?: ""
                            val queueCount = call.argument<Int>("queue_count") ?: 0
                            DownloadService.start(this@MainActivity, trackName, artistName, queueCount)
                            result.success(null)
                        }
                        "stopDownloadService" -> {
                            DownloadService.stop(this@MainActivity)
                            result.success(null)
                        }
                        "updateDownloadServiceProgress" -> {
                            val trackName = call.argument<String>("track_name") ?: ""
                            val artistName = call.argument<String>("artist_name") ?: ""
                            val progress = (call.argument<Number>("progress") ?: 0).toLong()
                            val total = (call.argument<Number>("total") ?: 0).toLong()
                            val queueCount = (call.argument<Number>("queue_count") ?: 0).toInt()
                            val status = call.argument<String>("status") ?: "downloading"
                            DownloadService.updateProgress(this@MainActivity, trackName, artistName, progress, total, queueCount, status)
                            result.success(null)
                        }
                        "isDownloadServiceRunning" -> {
                            result.success(DownloadService.isServiceRunning())
                        }
                        "startNativeDownloadWorker" -> {
                            val requestsJson = call.argument<String>("requests_json") ?: "[]"
                            val settingsJson = call.argument<String>("settings_json") ?: "{}"
                            val requestsPath = call.argument<String>("requests_path") ?: ""
                            val settingsPath = call.argument<String>("settings_path") ?: ""
                            if (requestsPath.isNotBlank()) {
                                DownloadService.startNativeQueueFromFiles(
                                    this@MainActivity,
                                    requestsPath,
                                    settingsPath
                                )
                            } else {
                                DownloadService.startNativeQueue(this@MainActivity, requestsJson, settingsJson)
                            }
                            result.success(null)
                        }
                        "pauseNativeDownloadWorker" -> {
                            DownloadService.pauseNativeQueue(this@MainActivity)
                            result.success(null)
                        }
                        "resumeNativeDownloadWorker" -> {
                            DownloadService.resumeNativeQueue(this@MainActivity)
                            result.success(null)
                        }
                        "cancelNativeDownloadWorker" -> {
                            DownloadService.cancelNativeQueue(this@MainActivity)
                            result.success(null)
                        }
                        "getNativeDownloadWorkerSnapshot" -> {
                            val sinceStateSerial =
                                (call.argument<Number>("since_state_serial") ?: 0L).toLong()
                            // The snapshot can be megabytes late in a large
                            // batch; read and parse it off the main thread.
                            val payload = withContext(Dispatchers.IO) {
                                parseJsonPayload(
                                    DownloadService.getNativeWorkerSnapshot(
                                        this@MainActivity,
                                        sinceStateSerial
                                    )
                                )
                            }
                            result.success(payload)
                        }
                        "getTrackCacheSize" -> {
                            val size = withContext(Dispatchers.IO) {
                                Gobackend.getTrackCacheSize()
                            }
                            result.success(size.toInt())
                        }
                        "clearTrackCache" -> {
                            withContext(Dispatchers.IO) {
                                Gobackend.clearTrackIDCache()
                            }
                            result.success(null)
                        }
                        "getProviderMetadata" -> {
                            val providerId = call.argument<String>("provider_id") ?: ""
                            val resourceType = call.argument<String>("resource_type") ?: ""
                            val resourceId = call.argument<String>("resource_id") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getProviderMetadataJSON(providerId, resourceType, resourceId)
                            }
                            result.success(response)
                        }
                        "searchDeezerByISRC" -> {
                            val isrc = call.argument<String>("isrc") ?: ""
                            val itemId = call.argument<String>("item_id") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.searchDeezerByISRCForItemID(isrc, itemId)
                            }
                            result.success(response)
                        }
                        "getDeezerExtendedMetadata" -> {
                            val trackId = call.argument<String>("track_id") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getDeezerExtendedMetadata(trackId)
                            }
                            result.success(response)
                        }
                        "convertSpotifyToDeezer" -> {
                            val resourceType = call.argument<String>("resource_type") ?: ""
                            val spotifyId = call.argument<String>("spotify_id") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.convertSpotifyToDeezer(resourceType, spotifyId)
                            }
                            result.success(response)
                        }
                        "getSpotifyIDFromDeezerTrack" -> {
                            val deezerTrackId = call.argument<String>("deezer_track_id") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getSpotifyIDFromDeezerTrack(deezerTrackId)
                            }
                            result.success(response)
                        }
                        "getTidalURLFromDeezerTrack" -> {
                            val deezerTrackId = call.argument<String>("deezer_track_id") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getTidalURLFromDeezerTrack(deezerTrackId)
                            }
                            result.success(response)
                        }
                        "getLogsSince" -> {
                            val index = call.argument<Int>("index") ?: 0
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getLogsSince(index.toLong())
                            }
                            result.success(response)
                        }
                        "clearLogs" -> {
                            withContext(Dispatchers.IO) {
                                Gobackend.clearLogs()
                            }
                            result.success(null)
                        }
                        "releaseMemory" -> {
                            withContext(Dispatchers.IO) {
                                Gobackend.releaseMemory()
                            }
                            result.success(null)
                        }
                        "releaseMemoryUnderPressure" -> {
                            withContext(Dispatchers.IO) {
                                Gobackend.releaseMemoryUnderPressure()
                            }
                            result.success(null)
                        }
                        "getGoRuntimeMetrics" -> {
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getRuntimeMetricsJSON()
                            }
                            result.success(response)
                        }
                        "setMetadataLanguage" -> {
                            val tag = call.argument<String>("tag") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.setMetadataLanguage(tag)
                            }
                            result.success(null)
                        }
                        "setLoggingEnabled" -> {
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            withContext(Dispatchers.IO) {
                                Gobackend.setLoggingEnabled(enabled)
                            }
                            result.success(null)
                        }
                        "initExtensionSystem" -> {
                            val extensionsDir = call.argument<String>("extensions_dir") ?: ""
                            val dataDir = call.argument<String>("data_dir") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.initExtensionSystem(extensionsDir, dataDir)
                            }
                            result.success(null)
                        }
                        "loadExtensionsFromDir" -> {
                            val dirPath = call.argument<String>("dir_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.loadExtensionsFromDir(dirPath)
                            }
                            result.success(response)
                        }
                        "loadExtensionFromPath" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.loadExtensionFromPath(filePath)
                            }
                            result.success(response)
                        }
                        "unloadExtension" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.unloadExtensionByID(extensionId)
                            }
                            result.success(null)
                        }
                        "removeExtension" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.removeExtensionByID(extensionId)
                            }
                            result.success(null)
                        }
                        "upgradeExtension" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.upgradeExtensionFromPath(filePath)
                            }
                            result.success(response)
                        }
                        "checkExtensionUpgrade" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.checkExtensionUpgradeFromPath(filePath)
                            }
                            result.success(response)
                        }
                        "getInstalledExtensions" -> {
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getInstalledExtensions()
                            }
                            result.success(response)
                        }
                        "setExtensionEnabled" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            withContext(Dispatchers.IO) {
                                Gobackend.setExtensionEnabledByID(extensionId, enabled)
                            }
                            result.success(null)
                        }
                        "setProviderPriority" -> {
                            val priorityJson = call.argument<String>("priority") ?: "[]"
                            withContext(Dispatchers.IO) {
                                Gobackend.setProviderPriorityJSON(priorityJson)
                            }
                            result.success(null)
                        }
                        "getProviderPriority" -> {
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getProviderPriorityJSON()
                            }
                            result.success(response)
                        }
                        "setDownloadFallbackExtensionIds" -> {
                            val extensionIdsJson = call.argument<String>("extension_ids") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.setExtensionFallbackProviderIDsJSON(extensionIdsJson)
                            }
                            result.success(null)
                        }
                        "setMetadataProviderPriority" -> {
                            val priorityJson = call.argument<String>("priority") ?: "[]"
                            withContext(Dispatchers.IO) {
                                Gobackend.setMetadataProviderPriorityJSON(priorityJson)
                            }
                            result.success(null)
                        }
                        "getMetadataProviderPriority" -> {
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getMetadataProviderPriorityJSON()
                            }
                            result.success(response)
                        }
                        "getExtensionSettings" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getExtensionSettingsJSON(extensionId)
                            }
                            result.success(response)
                        }
                        "checkExtensionHealth" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.checkExtensionHealthJSON(extensionId)
                            }
                            result.success(response)
                        }
                        "setExtensionSettings" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val settingsJson = call.argument<String>("settings") ?: "{}"
                            withContext(Dispatchers.IO) {
                                Gobackend.setExtensionSettingsJSON(extensionId, settingsJson)
                            }
                            result.success(null)
                        }
                        "invokeExtensionAction" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val actionName = call.argument<String>("action") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.invokeExtensionActionJSON(extensionId, actionName)
                            }
                            result.success(response)
                        }
                        "searchTracksWithMetadataProviders" -> {
                            val query = call.argument<String>("query") ?: ""
                            val limit = call.argument<Int>("limit") ?: 20
                            val includeExtensions = call.argument<Boolean>("include_extensions") ?: true
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.searchTracksWithMetadataProvidersJSON(query, limit.toLong(), includeExtensions)
                            }
                            result.success(response)
                        }
                        "searchTracksWithMetadataProvider" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val query = call.argument<String>("query") ?: ""
                            val limit = call.argument<Int>("limit") ?: 20
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.searchTracksWithMetadataProviderJSON(
                                    extensionId,
                                    query,
                                    limit.toLong()
                                )
                            }
                            result.success(response)
                        }
                        "findCollectionAcrossExtensions" -> {
                            val requestJson = call.arguments as? String ?: "{}"
                            val response: String = withContext(Dispatchers.IO) {
                                val method = Gobackend::class.java.getMethod(
                                    "findCollectionAcrossExtensionsJSON",
                                    String::class.java
                                )
                                method.invoke(null, requestJson) as? String ?: "[]"
                            }
                            result.success(response)
                        }
                        "enrichTrackWithExtension" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val trackJson = call.argument<String>("track") ?: "{}"
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.enrichTrackWithExtensionJSON(extensionId, trackJson)
                            }
                            result.success(response)
                        }
                        "cleanupExtensions" -> {
                            withContext(Dispatchers.IO) {
                                Gobackend.cleanupExtensions()
                            }
                            result.success(null)
                        }
                        "getExtensionPendingAuth" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getExtensionPendingAuthJSON(extensionId)
                            }
                            if (response.isNullOrEmpty()) {
                                result.success(null)
                            } else {
                                result.success(response)
                            }
                        }
                        "setExtensionAuthCode" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val authCode = call.argument<String>("auth_code") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.setExtensionAuthCodeByID(extensionId, authCode)
                            }
                            result.success(null)
                        }
                        "completeExtensionSessionGrant" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val grant = call.argument<String>("grant") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.setExtensionSessionGrantByID(extensionId, grant)
                                val json = Gobackend.invokeExtensionActionJSON(extensionId, "completeGrant")
                                requireSuccessfulExtensionAction(extensionId, "completeGrant", json)
                            }
                            result.success(true)
                        }
                        "setExtensionTokens" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val accessToken = call.argument<String>("access_token") ?: ""
                            val refreshToken = call.argument<String>("refresh_token") ?: ""
                            val expiresIn = call.argument<Int>("expires_in") ?: 0
                            withContext(Dispatchers.IO) {
                                Gobackend.setExtensionTokensByID(extensionId, accessToken, refreshToken, expiresIn.toLong())
                            }
                            result.success(null)
                        }
                        "clearExtensionPendingAuth" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.clearExtensionPendingAuthByID(extensionId)
                            }
                            result.success(null)
                        }
                        "isExtensionAuthenticated" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val isAuth = withContext(Dispatchers.IO) {
                                Gobackend.isExtensionAuthenticatedByID(extensionId)
                            }
                            result.success(isAuth)
                        }
                        "getAllPendingAuthRequests" -> {
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getAllPendingAuthRequestsJSON()
                            }
                            result.success(response)
                        }
                        "getPendingFFmpegCommand" -> {
                            val commandId = call.argument<String>("command_id") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getPendingFFmpegCommandJSON(commandId)
                            }
                            if (response.isNullOrEmpty()) {
                                result.success(null)
                            } else {
                                result.success(response)
                            }
                        }
                        "setFFmpegCommandResult" -> {
                            val commandId = call.argument<String>("command_id") ?: ""
                            val success = call.argument<Boolean>("success") ?: false
                            val output = call.argument<String>("output") ?: ""
                            val error = call.argument<String>("error") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.setFFmpegCommandResultByID(commandId, success, output, error)
                            }
                            result.success(null)
                        }
                        "getAllPendingFFmpegCommands" -> {
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getAllPendingFFmpegCommandsJSON()
                            }
                            result.success(response)
                        }
                        "customSearchWithExtension" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val query = call.argument<String>("query") ?: ""
                            val optionsJson = call.argument<String>("options") ?: ""
                            val requestId = call.argument<String>("request_id") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.customSearchWithExtensionJSONWithRequestID(extensionId, query, optionsJson, requestId)
                            }
                            result.success(response)
                        }
                        "cancelExtensionRequest" -> {
                            val requestId = call.argument<String>("request_id") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.cancelExtensionRequestJSON(requestId)
                            }
                            result.success(null)
                        }
                        "handleURLWithExtension" -> {
                            val url = call.argument<String>("url") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.handleURLWithExtensionJSON(url)
                            }
                            result.success(response)
                        }
                        "findURLHandler" -> {
                            val url = call.argument<String>("url") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.findURLHandlerJSON(url)
                            }
                            result.success(response)
                        }
                        "getTrackPlatformLinks" -> {
                            val spotifyId = call.argument<String>("spotify_id") ?: ""
                            val isrc = call.argument<String>("isrc") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getTrackPlatformLinksJSON(spotifyId, isrc)
                            }
                            result.success(response)
                        }
                        "fetchMusicBrainzTags" -> {
                            val isrc = call.argument<String>("isrc") ?: ""
                            val albumName = call.argument<String>("album_name") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                val genre = try {
                                    Gobackend.fetchMusicBrainzGenreByISRC(isrc)
                                } catch (_: Exception) {
                                    ""
                                }
                                val albumArtist = try {
                                    Gobackend.fetchMusicBrainzAlbumArtistByISRC(isrc, albumName)
                                } catch (_: Exception) {
                                    ""
                                }
                                JSONObject()
                                    .put("genre", genre)
                                    .put("album_artist", albumArtist)
                                    .toString()
                            }
                            result.success(response)
                        }
                        "runPostProcessingV2" -> {
                            val inputJson = call.argument<String>("input") ?: ""
                            val metadataJson = call.argument<String>("metadata") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                val inputObj = if (inputJson.isNotBlank()) JSONObject(inputJson) else JSONObject()
                                val uriStr = inputObj.optString("uri", "")
                                val pathStr = inputObj.optString("path", "")
                                val effectiveUri = when {
                                    uriStr.startsWith("content://") -> uriStr
                                    pathStr.startsWith("content://") -> pathStr
                                    else -> ""
                                }

                                if (effectiveUri.isNotBlank()) {
                                    runPostProcessingSafV2(effectiveUri, metadataJson)
                                } else {
                                    if (pathStr.isNotBlank()) {
                                        inputObj.put("name", File(pathStr).name)
                                        inputObj.put("is_saf", false)
                                    }
                                    Gobackend.runPostProcessingV2JSON(inputObj.toString(), metadataJson)
                                }
                            }
                            result.success(response)
                        }
                        "initExtensionRepo" -> {
                            val cacheDir = call.argument<String>("cache_dir") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.initExtensionRepoJSON(cacheDir)
                            }
                            result.success(null)
                        }
                        "setRepoRegistryUrl" -> {
                            val registryUrl = call.argument<String>("registry_url") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.setRepoRegistryURLJSON(registryUrl)
                            }
                            result.success(null)
                        }
                        "getRepoRegistryUrl" -> {
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getRepoRegistryURLJSON()
                            }
                            result.success(response)
                        }
                        "clearRepoRegistryUrl" -> {
                            withContext(Dispatchers.IO) {
                                Gobackend.clearRepoRegistryURLJSON()
                            }
                            result.success(null)
                        }
                        "getRepoExtensions" -> {
                            val forceRefresh = call.argument<Boolean>("force_refresh") ?: false
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getRepoExtensionsJSON(forceRefresh)
                            }
                            result.success(response)
                        }
                        "searchRepoExtensions" -> {
                            val query = call.argument<String>("query") ?: ""
                            val category = call.argument<String>("category") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.searchRepoExtensionsJSON(query, category)
                            }
                            result.success(response)
                        }
                        "getRepoCategories" -> {
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getRepoCategoriesJSON()
                            }
                            result.success(response)
                        }
                        "downloadRepoExtension" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val destDir = call.argument<String>("dest_dir") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.downloadRepoExtensionJSON(extensionId, destDir)
                            }
                            result.success(response)
                        }
                        "clearRepoCache" -> {
                            withContext(Dispatchers.IO) {
                                Gobackend.clearRepoCacheJSON()
                            }
                            result.success(null)
                        }
                        "getExtensionHomeFeed" -> {
                            val extensionId = call.argument<String>("extension_id") ?: ""
                            val requestId = call.argument<String>("request_id") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                Gobackend.getExtensionHomeFeedJSONWithRequestID(extensionId, requestId)
                            }
                            result.success(response)
                        }
                        "setLibraryCoverCacheDir" -> {
                            val cacheDir = call.argument<String>("cache_dir") ?: ""
                            withContext(Dispatchers.IO) {
                                Gobackend.setLibraryCoverCacheDirJSON(cacheDir)
                            }
                            result.success(null)
                        }
                        "scanLibraryFolder" -> {
                            val folderPath = call.argument<String>("folder_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                safScanActive = false
                                bridgeJsonResult(Gobackend.scanLibraryFolderJSON(folderPath))
                            }
                            result.success(response)
                        }
                        "scanLibraryFolderIncremental" -> {
                            val folderPath = call.argument<String>("folder_path") ?: ""
                            val existingFiles = call.argument<String>("existing_files") ?: "{}"
                            val response = withContext(Dispatchers.IO) {
                                safScanActive = false
                                bridgeJsonResult(
                                    Gobackend.scanLibraryFolderIncrementalJSON(folderPath, existingFiles)
                                )
                            }
                            result.success(response)
                        }
                        "scanLibraryFolderIncrementalFromSnapshot" -> {
                            val folderPath = call.argument<String>("folder_path") ?: ""
                            val snapshotPath = call.argument<String>("snapshot_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                safScanActive = false
                                bridgeJsonResult(
                                    Gobackend.scanLibraryFolderIncrementalFromSnapshotJSON(
                                        folderPath,
                                        snapshotPath,
                                    )
                                )
                            }
                            result.success(response)
                        }
                        "scanSafTree" -> {
                            val treeUri = call.argument<String>("tree_uri") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                scanSafTree(treeUri)
                            }
                            result.success(response)
                        }
                        "scanSafTreeIncremental" -> {
                            val treeUri = call.argument<String>("tree_uri") ?: ""
                            val existingFiles = call.argument<String>("existing_files") ?: "{}"
                            val response = withContext(Dispatchers.IO) {
                                scanSafTreeIncremental(treeUri, existingFiles)
                            }
                            result.success(response)
                        }
                        "scanSafTreeIncrementalFromSnapshot" -> {
                            val treeUri = call.argument<String>("tree_uri") ?: ""
                            val snapshotPath = call.argument<String>("snapshot_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                val existingFiles =
                                    loadExistingFilesFromSnapshot(snapshotPath)
                                scanSafTreeIncremental(treeUri, existingFiles)
                            }
                            result.success(response)
                        }
                        "getSafFileModTimes" -> {
                            val uris = call.argument<String>("uris") ?: "[]"
                            val response = withContext(Dispatchers.IO) {
                                getSafFileModTimes(uris)
                            }
                            result.success(response)
                        }
                        "getLibraryScanProgress" -> {
                            val response = withContext(Dispatchers.IO) {
                                if (safScanActive) {
                                    safProgressToJson()
                                } else {
                                    Gobackend.getLibraryScanProgressJSON()
                                }
                            }
                            result.success(parseJsonPayload(response))
                        }
                        "cancelLibraryScan" -> {
                            withContext(Dispatchers.IO) {
                                safScanCancel = true
                                Gobackend.cancelLibraryScanJSON()
                            }
                            result.success(null)
                        }
                        "readAudioMetadata" -> {
                            val filePath = call.argument<String>("file_path") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (filePath.startsWith("content://")) {
                                        val uri = Uri.parse(filePath)
                                        val metadata = readAudioMetadataFromUri(uri)
                                            ?: return@withContext """{"error":"Failed to read SAF audio metadata"}"""
                                        metadata.put("filePath", filePath)
                                        metadata.toString()
                                    } else {
                                        Gobackend.readAudioMetadataJSON(filePath)
                                    }
                                } catch (e: Exception) {
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        "parseCueSheet" -> {
                            val cuePath = call.argument<String>("cue_path") ?: ""
                            val audioDir = call.argument<String>("audio_dir") ?: ""
                            val response = withContext(Dispatchers.IO) {
                                try {
                                    if (cuePath.startsWith("content://")) {
                                        val uri = Uri.parse(cuePath)
                                        val tempCuePath = copyUriToTemp(uri, ".cue")
                                            ?: return@withContext """{"error":"Failed to copy CUE file to temp"}"""
                                        var tempAudioPath: String? = null
                                        try {
                                            val audioFileName = extractCueAudioFileName(tempCuePath)

                                            var audioDoc: DocumentFile? = null
                                            val parentDir = safParentDir(uri)
                                            if (parentDir != null && !audioFileName.isNullOrBlank()) {
                                                audioDoc = try { parentDir.findFile(audioFileName) } catch (_: Exception) { null }
                                            }

                                            if (audioDoc == null && parentDir != null) {
                                                val cueName = try {
                                                    DocumentFile.fromSingleUri(this@MainActivity, uri)?.name ?: ""
                                                } catch (_: Exception) { "" }
                                                val cueBaseName = cueName.substringBeforeLast('.')
                                                if (cueBaseName.isNotBlank()) {
                                                    val commonExts = listOf(".flac", ".wav", ".ape", ".mp3", ".ogg", ".wv", ".m4a", ".mp4", ".aac")
                                                    for (ext in commonExts) {
                                                        audioDoc = try { parentDir.findFile(cueBaseName + ext) } catch (_: Exception) { null }
                                                        if (audioDoc != null) break
                                                        audioDoc = try { parentDir.findFile(cueBaseName + ext.uppercase(Locale.ROOT)) } catch (_: Exception) { null }
                                                        if (audioDoc != null) break
                                                    }
                                                }
                                            }

                                            val tempDir = File(tempCuePath).parent ?: cacheDir.absolutePath
                                            if (audioDoc != null) {
                                                val audioName = try { audioDoc.name ?: "audio.flac" } catch (_: Exception) { "audio.flac" }
                                                val audioExt = audioName.substringAfterLast('.', "").lowercase(Locale.ROOT)
                                                val fallbackExt = if (audioExt.isNotBlank()) ".$audioExt" else null
                                                val copiedAudio = copyUriToTemp(audioDoc.uri, fallbackExt)
                                                if (copiedAudio != null) {
                                                    val renamedAudio = File(tempDir, audioName)
                                                    val copiedFile = File(copiedAudio)
                                                    if (renamedAudio.absolutePath != copiedFile.absolutePath) {
                                                        copiedFile.renameTo(renamedAudio)
                                                    }
                                                    tempAudioPath = renamedAudio.absolutePath
                                                }
                                            }

                                            val resultJson = Gobackend.parseCueSheet(tempCuePath, tempDir)

                                            if (audioDoc != null) {
                                                val resultObj = JSONObject(resultJson)
                                                resultObj.put("audio_path", audioDoc.uri.toString())
                                                resultObj.put("cue_path", cuePath)
                                                resultObj.toString()
                                            } else {
                                                resultJson
                                            }
                                        } finally {
                                            try { File(tempCuePath).delete() } catch (_: Exception) {}
                                            try { tempAudioPath?.let { File(it).delete() } } catch (_: Exception) {}
                                        }
                                    } else {
                                        Gobackend.parseCueSheet(cuePath, audioDir)
                                    }
                                } catch (e: Exception) {
                                    """{"error":${org.json.JSONObject.quote(e.message ?: "unknown")}}"""
                                }
                            }
                            result.success(response)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            }
        }
    }
}
