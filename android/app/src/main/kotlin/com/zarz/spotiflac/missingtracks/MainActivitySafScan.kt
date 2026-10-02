package com.zarz.spotiflac.missingtracks

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document.MIME_TYPE_DIR
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
import java.io.IOException
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

// SAF library-scan subsystem: tree walking, incremental diff, CUE resolution,
// and scan-progress state shared with the progress stream in MainActivity.

internal fun MainActivity.buildStableLibraryId(filePath: String): String {
        val digest = MessageDigest.getInstance("SHA-1")
        val bytes = digest.digest(filePath.toByteArray(Charsets.UTF_8))
        val hex = bytes.joinToString("") { "%02x".format(it) }
        return "lib_$hex"
    }

internal fun MainActivity.resetSafScanProgress() {
        synchronized(safScanLock) {
            safScanProgress = MainActivity.SafScanProgress()
        }
    }

internal fun MainActivity.updateSafScanProgress(block: (MainActivity.SafScanProgress) -> Unit) {
        synchronized(safScanLock) {
            block(safScanProgress)
        }
    }

internal fun MainActivity.safProgressToJson(): String {
        val snapshot = synchronized(safScanLock) { safScanProgress.copy() }
        val obj = JSONObject()
        obj.put("total_files", snapshot.totalFiles)
        obj.put("scanned_files", snapshot.scannedFiles)
        obj.put("current_file", snapshot.currentFile)
        obj.put("error_count", snapshot.errorCount)
        obj.put("progress_pct", snapshot.progressPct)
        obj.put("is_complete", snapshot.isComplete)
        return obj.toString()
    }

internal fun MainActivity.readLibraryScanProgressJsonForStream(): String {
        return if (safScanActive) {
            safProgressToJson()
        } else {
            coreBackend.getLibraryScanProgress()
        }
    }


internal fun MainActivity.loadExistingFilesFromSnapshot(snapshotPath: String): MutableMap<String, Long> {
        val result = mutableMapOf<String, Long>()
        if (snapshotPath.isBlank()) {
            return result
        }

        val snapshotFile = File(snapshotPath)
        if (!snapshotFile.exists()) {
            return result
        }

        snapshotFile.forEachLine { line ->
            if (line.isBlank()) return@forEachLine
            val separatorIndex = line.indexOf('\t')
            if (separatorIndex <= 0 || separatorIndex >= line.length - 1) {
                return@forEachLine
            }
            val modTime = line.substring(0, separatorIndex).toLongOrNull() ?: 0L
            val filePath = line.substring(separatorIndex + 1)
            if (filePath.isNotEmpty()) {
                result[filePath] = modTime
            }
        }
        return result
    }

internal fun Context.resolveSafFile(treeUriStr: String, relativeDir: String, fileName: String): String {
        val obj = JSONObject()
        if (treeUriStr.isBlank() || fileName.isBlank()) {
            obj.put("uri", "")
            obj.put("relative_dir", "")
            return obj.toString()
        }
        val safeRelativeDir = SafDownloadHandler.sanitizeRelativeDir(relativeDir)
        val safeFileName = SafDownloadHandler.sanitizeFilename(fileName)
        if (safeFileName.isBlank()) {
            obj.put("uri", "")
            obj.put("relative_dir", "")
            return obj.toString()
        }

        val treeUri = Uri.parse(treeUriStr)
        val targetDir = SafDownloadHandler.findDocumentDir(this, treeUri, safeRelativeDir)
        if (targetDir != null) {
            val direct = findSafChild(this, targetDir, safeFileName)
            if (direct != null && direct.isFile) {
                obj.put("uri", direct.uri.toString())
                obj.put("relative_dir", safeRelativeDir)
                return obj.toString()
            }
        }

        val root = DocumentFile.fromTreeUri(this, treeUri) ?: run {
            obj.put("uri", "")
            obj.put("relative_dir", "")
            return obj.toString()
        }

        val queue: ArrayDeque<Pair<DocumentFile, String>> = ArrayDeque()
        queue.add(root to "")
        var visited = 0
        val maxVisited = 20000

        while (queue.isNotEmpty()) {
            if (visited > maxVisited) break
            val (dir, path) = queue.removeFirst()
            val children = try {
                listSafChildrenOrThrow(dir, includeLastModified = false)
            } catch (_: Exception) {
                continue
            }
            for (child in children) {
                visited++
                if (child.isDirectory) {
                    val childName = child.name ?: continue
                    val childPath = if (path.isBlank()) childName else "$path/$childName"
                    queue.add(child.doc to childPath)
                } else if (child.isFile) {
                    if (child.name == safeFileName) {
                        obj.put("uri", child.doc.uri.toString())
                        obj.put("relative_dir", path)
                        return obj.toString()
                    }
                }
            }
        }

        obj.put("uri", "")
        obj.put("relative_dir", "")
        return obj.toString()
    }

private data class SafFileInspectionRequest(
    val key: String,
    val treeUri: String,
    val relativeDir: String,
    val currentUri: String,
    val fileNames: List<String>,
)

/**
 * Inspects many SAF history entries while walking each document tree at most
 * once. The old per-file resolver could repeat a 20k-document breadth-first
 * search for every missing history row and every conversion filename variant.
 */
internal fun Context.inspectSafFiles(requestsJson: String): String {
    val output = JSONObject()
    val resultsByKey = linkedMapOf<String, JSONObject>()
    val requests = mutableListOf<SafFileInspectionRequest>()

    fun result(
        key: String,
        status: String,
        uri: String = "",
        fileName: String = "",
        relativeDir: String = "",
    ) = JSONObject().apply {
        put("key", key)
        put("status", status)
        put("uri", uri)
        put("file_name", fileName)
        put("relative_dir", relativeDir)
    }

    try {
        val rawRequests = JSONArray(requestsJson)
        for (index in 0 until rawRequests.length()) {
            val raw = rawRequests.optJSONObject(index) ?: continue
            val key = raw.optString("key").trim()
            if (key.isBlank()) continue
            val names = mutableListOf<String>()
            val rawNames = raw.optJSONArray("file_names")
            if (rawNames != null) {
                for (nameIndex in 0 until rawNames.length()) {
                    val sanitized = SafDownloadHandler.sanitizeFilename(
                        rawNames.optString(nameIndex).trim(),
                    )
                    if (sanitized.isNotBlank() && sanitized !in names) {
                        names.add(sanitized)
                    }
                }
            }
            requests.add(
                SafFileInspectionRequest(
                    key = key,
                    treeUri = raw.optString("tree_uri").trim(),
                    relativeDir = SafDownloadHandler.sanitizeRelativeDir(
                        raw.optString("relative_dir"),
                    ),
                    currentUri = raw.optString("current_uri").trim(),
                    fileNames = names,
                ),
            )
        }

        val pendingByTree = linkedMapOf<String, MutableList<SafFileInspectionRequest>>()
        for (request in requests) {
            if (request.currentUri.startsWith("content://")) {
                try {
                    val current = DocumentFile.fromSingleUri(this, Uri.parse(request.currentUri))
                    if (current != null && current.exists() && current.isFile) {
                        resultsByKey[request.key] = result(
                            key = request.key,
                            status = "found",
                            uri = request.currentUri,
                            fileName = current.name.orEmpty(),
                            relativeDir = request.relativeDir,
                        )
                        continue
                    }
                } catch (_: Exception) {
                    // Fall through to the persisted tree lookup.
                }
            }
            if (request.treeUri.isBlank() || request.fileNames.isEmpty()) {
                resultsByKey[request.key] = result(request.key, "unknown")
                continue
            }
            pendingByTree.getOrPut(request.treeUri) { mutableListOf() }.add(request)
        }

        for ((treeUriString, treeRequests) in pendingByTree) {
            val treeUri = try {
                Uri.parse(treeUriString)
            } catch (_: Exception) {
                null
            }
            val hasPermission = treeUri != null && contentResolver.persistedUriPermissions.any {
                it.uri == treeUri && it.isReadPermission && it.isWritePermission
            }
            val root = if (hasPermission) {
                try {
                    DocumentFile.fromTreeUri(this, treeUri)
                } catch (_: Exception) {
                    null
                }
            } else {
                null
            }
            if (root == null || !root.exists() || !root.canWrite()) {
                for (request in treeRequests) {
                    resultsByKey[request.key] = result(request.key, "unknown")
                }
                continue
            }

            val unresolved = mutableListOf<SafFileInspectionRequest>()
            val directoryCache = mutableMapOf<String, Map<String, SafChildEntry>>()
            val resolvedDirectoryCache = mutableMapOf<String, DocumentFile?>()
            for (request in treeRequests) {
                val directDir = if (resolvedDirectoryCache.containsKey(request.relativeDir)) {
                    resolvedDirectoryCache[request.relativeDir]
                } else {
                    val resolved = try {
                        SafDownloadHandler.findDocumentDir(this, treeUri!!, request.relativeDir)
                    } catch (_: Exception) {
                        null
                    }
                    resolvedDirectoryCache[request.relativeDir] = resolved
                    resolved
                }
                val lookup = if (directDir == null) {
                    emptyMap()
                } else {
                    directoryCache.getOrPut(directDir.uri.toString()) {
                        buildMap {
                            for (child in listSafChildrenOrThrow(directDir, includeLastModified = false)) {
                                if (child.isDirectory) continue
                                val name = child.name?.trim().orEmpty()
                                if (name.isNotBlank()) put(name.lowercase(Locale.ROOT), child)
                            }
                        }
                    }
                }
                val directName = request.fileNames.firstOrNull {
                    lookup.containsKey(it.lowercase(Locale.ROOT))
                }
                val direct = directName?.let { lookup[it.lowercase(Locale.ROOT)] }
                if (direct != null && direct.isFile) {
                    resultsByKey[request.key] = result(
                        key = request.key,
                        status = "found",
                        uri = direct.doc.uri.toString(),
                        fileName = direct.name ?: directName,
                        relativeDir = request.relativeDir,
                    )
                } else {
                    unresolved.add(request)
                }
            }
            if (unresolved.isEmpty()) continue

            val wantedNames = unresolved
                .flatMap { it.fileNames }
                .map { it.lowercase(Locale.ROOT) }
                .toSet()
            val requestKeysByName = mutableMapOf<String, MutableSet<String>>()
            for (request in unresolved) {
                for (fileName in request.fileNames) {
                    requestKeysByName
                        .getOrPut(fileName.lowercase(Locale.ROOT)) { mutableSetOf() }
                        .add(request.key)
                }
            }
            val matches = mutableMapOf<String, Pair<SafChildEntry, String>>()
            val matchedRequestKeys = mutableSetOf<String>()
            val queue: ArrayDeque<Pair<DocumentFile, String>> = ArrayDeque()
            queue.add(root to "")
            var visited = 0
            val maxVisited = 50000
            var scanComplete = true

            while (queue.isNotEmpty() && matchedRequestKeys.size < unresolved.size) {
                if (visited >= maxVisited) {
                    scanComplete = false
                    break
                }
                val (directory, path) = queue.removeFirst()
                val children = try {
                    listSafChildrenOrThrow(directory, includeLastModified = false)
                } catch (_: Exception) {
                    scanComplete = false
                    break
                }
                for (child in children) {
                    visited++
                    if (visited >= maxVisited) {
                        scanComplete = false
                        break
                    }
                    if (child.isDirectory) {
                        val childName = child.name ?: continue
                        val childPath = if (path.isBlank()) childName else "$path/$childName"
                        queue.add(child.doc to childPath)
                    } else if (child.isFile) {
                        val childName = child.name ?: continue
                        val normalized = childName.lowercase(Locale.ROOT)
                        if (normalized in wantedNames && normalized !in matches) {
                            matches[normalized] = child to path
                            matchedRequestKeys.addAll(
                                requestKeysByName[normalized].orEmpty(),
                            )
                        }
                    }
                }
            }

            for (request in unresolved) {
                val matchedName = request.fileNames.firstOrNull {
                    matches.containsKey(it.lowercase(Locale.ROOT))
                }
                val match = matchedName?.let { matches[it.lowercase(Locale.ROOT)] }
                resultsByKey[request.key] = if (match != null) {
                    result(
                        key = request.key,
                        status = "found",
                        uri = match.first.doc.uri.toString(),
                        fileName = match.first.name ?: matchedName,
                        relativeDir = match.second,
                    )
                } else {
                    result(request.key, if (scanComplete) "missing" else "unknown")
                }
            }
        }
    } catch (error: Exception) {
        android.util.Log.w("SpotiFLAC", "Batch SAF inspection failed: ${error.message}")
        for (request in requests) {
            resultsByKey.putIfAbsent(request.key, result(request.key, "unknown"))
        }
    }

    val results = JSONArray()
    for (request in requests) {
        results.put(resultsByKey[request.key] ?: result(request.key, "unknown"))
    }
    output.put("results", results)
    return output.toString()
}

private fun safScanCheckpointPath(outputPath: String): String = "$outputPath.state"

private fun loadSafScanCheckpoint(path: String): MutableMap<String, Long> {
    val checkpoint = File(path)
    if (!checkpoint.exists()) return mutableMapOf()
    val entries = mutableMapOf<String, Long>()
    try {
        checkpoint.forEachLine(Charsets.UTF_8) { line ->
            val separator = line.indexOf('\t')
            if (separator <= 0) return@forEachLine
            val uri = line.substring(0, separator)
            val modified = line.substring(separator + 1).toLongOrNull() ?: return@forEachLine
            entries[uri] = modified
        }
    } catch (e: Exception) {
        android.util.Log.w("SpotiFLAC", "SAF scan: failed reading checkpoint: ${e.message}")
    }
    return entries
}

private fun reconcileSafScanCheckpoint(
    outputPath: String,
    loaded: MutableMap<String, Long>,
): MutableMap<String, Long> {
    val output = File(outputPath)
    if (!output.exists()) return loaded

    val outputEntries = mutableMapOf<String, Long>()
    try {
        output.forEachLine(Charsets.UTF_8) { line ->
            if (line.isBlank()) return@forEachLine
            try {
                val obj = JSONObject(line)
                val filePath = obj.optString("filePath", "").trim()
                if (filePath.isNotBlank()) {
                    val modified = obj.optLong("fileModTime", 0L)
                    val cueMarker = filePath.indexOf("#track")
                    val key = if (cueMarker > 0) filePath.substring(0, cueMarker) else filePath
                    outputEntries[key] = modified
                }
            } catch (_: Exception) {}
        }
    } catch (e: Exception) {
        android.util.Log.w("SpotiFLAC", "SAF scan: failed reconciling checkpoint: ${e.message}")
        return loaded
    }

    loaded.clear()
    loaded.putAll(outputEntries)
    return loaded
}

private fun countSafScanRows(path: String): Int {
    val output = File(path)
    if (!output.exists()) return 0
    return try {
        output.useLines(Charsets.UTF_8) { lines -> lines.count { it.isNotBlank() } }
    } catch (e: Exception) {
        android.util.Log.w("SpotiFLAC", "SAF scan: failed counting existing rows: ${e.message}")
        0
    }
}

private fun repairSafScanOutput(path: String) {
    val output = File(path)
    if (!output.exists()) return
    try {
        RandomAccessFile(output, "rw").use { file ->
            var position = file.length() - 1
            while (position >= 0) {
                file.seek(position)
                if (file.readByte().toInt() == '\n'.code) {
                    file.setLength(position + 1)
                    return
                }
                position--
            }
            // No complete line survived the interruption.
            file.setLength(0)
        }
    } catch (e: Exception) {
        android.util.Log.w("SpotiFLAC", "SAF scan: failed repairing output: ${e.message}")
    }
}


    /**
     * Extract the audio filename referenced by a CUE sheet file.
     * Reads the FILE "name" TYPE line from the .cue text.
     * Returns just the filename (no path), or null if not found.
     */
internal fun MainActivity.extractCueAudioFileName(cueTempPath: String): String? {
        try {
            val lines = File(cueTempPath).readLines()
            for (line in lines) {
                val trimmed = line.trim().let { l ->
                    if (l.startsWith("\uFEFF")) l.removePrefix("\uFEFF").trim() else l
                }
                if (trimmed.uppercase(Locale.ROOT).startsWith("FILE ")) {
                    val rest = trimmed.substring(5).trim()
                    val filename = if (rest.startsWith("\"")) {
                        val endQuote = rest.indexOf('"', 1)
                        if (endQuote > 0) rest.substring(1, endQuote) else rest
                    } else {
                        val parts = rest.split("\\s+".toRegex())
                        if (parts.size >= 2) parts.dropLast(1).joinToString(" ") else rest
                    }
                    return filename.substringAfterLast("/").substringAfterLast("\\")
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("SpotiFLAC", "Failed to extract audio filename from CUE: ${e.message}")
        }
        return null
    }

    private val cueSiblingAudioExtensions = listOf(
        ".flac", ".wav", ".ape", ".mp3", ".ogg", ".wv", ".m4a", ".mp4", ".aac"
    )

    // Keep the SAF folder walk aligned with the backend's supported audio formats.
    // CUE files are handled separately.
    private val libraryScanAudioExtensions = setOf(
        ".flac", ".m4a", ".mp4", ".aac", ".mp3", ".opus", ".ogg",
        ".ape", ".wv", ".mpc", ".wav", ".aiff", ".aif", ".dsf", ".dff"
    )

internal fun MainActivity.getSafChildFileLookup(
        dir: DocumentFile,
        cache: MutableMap<String, Map<String, DocumentFile>>,
    ): Map<String, DocumentFile> {
        val dirKey = dir.uri.toString()
        return cache.getOrPut(dirKey) { safChildFileLookup(listSafChildrenOrThrow(dir)) }
    }

private fun safChildFileLookup(children: List<SafChildEntry>): Map<String, DocumentFile> =
    buildMap {
        for (child in children) {
            if (child.isDirectory) continue
            val childName = child.name?.trim().orEmpty()
            if (childName.isBlank()) continue
            put(childName.lowercase(Locale.ROOT), child.doc)
        }
    }

/** Keeps a traversal listing for CUE sibling lookup so the directory is not
 * queried again; on network providers every listing is a round trip. */
private fun rememberCueDirectoryListing(
    dir: DocumentFile,
    children: List<SafChildEntry>,
    cache: MutableMap<String, Map<String, DocumentFile>>,
) {
    if (children.any { !it.isDirectory && it.name?.endsWith(".cue", ignoreCase = true) == true }) {
        cache[dir.uri.toString()] = safChildFileLookup(children)
    }
}

// Provider round trips dominate on SD cards, USB drives and network shares.
private const val SAF_LIST_CONCURRENCY = 4
private const val SAF_READ_WORKERS = 6
private const val SAF_SCAN_PAUSE_POLL_MS = 100L

/**
 * Holds a SAF scan at its checkpoint while paused, keeping its position in
 * memory. Returns true when the scan should stop because it was cancelled.
 */
internal fun MainActivity.safScanStopRequested(): Boolean {
    while (safScanPaused && !safScanCancel) {
        Thread.sleep(SAF_SCAN_PAUSE_POLL_MS)
    }
    return safScanCancel
}

/**
 * Prefetches the listings of directories already waiting in a breadth-first
 * queue. The caller still dequeues, deduplicates and records errors serially,
 * so traversal order and results match a one-directory-at-a-time walk.
 * Idle daemon threads exit on their own, so abandoned walks leak nothing.
 */
private class SafTreeLister(private val context: Context) {
    private val executor = ThreadPoolExecutor(
        SAF_LIST_CONCURRENCY,
        SAF_LIST_CONCURRENCY,
        1,
        TimeUnit.SECONDS,
        LinkedBlockingQueue(),
    ) { runnable -> Thread(runnable, "saf-scan-list").apply { isDaemon = true } }
        .apply { allowCoreThreadTimeOut(true) }
    private val prefetched = mutableMapOf<String, Future<Result<List<SafChildEntry>>>>()

    private fun submit(dir: DocumentFile) = executor.submit<Result<List<SafChildEntry>>> {
        try {
            Result.success(context.listSafChildrenOrThrow(dir))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    fun list(
        dir: DocumentFile,
        queue: Collection<Pair<DocumentFile, String>>,
        visited: Set<String>,
    ): Result<List<SafChildEntry>> {
        val uri = dir.uri.toString()
        val current = prefetched.remove(uri) ?: submit(dir)
        for ((next, _) in queue) {
            if (prefetched.size >= SAF_LIST_CONCURRENCY * 2) break
            val nextUri = next.uri.toString()
            if (nextUri == uri || nextUri in visited || nextUri in prefetched) continue
            prefetched[nextUri] = submit(next)
        }
        return try {
            current.get()
        } catch (e: ExecutionException) {
            throw e.cause ?: e
        }
    }
}

/**
 * Runs [task] on a bounded pool and passes each result to [consume] in input
 * order. A sliding window keeps workers busy past one slow file. Returns
 * false when cancelled.
 */
private fun <T, R> runSafReadsInOrder(
    items: List<T>,
    cancelled: () -> Boolean,
    task: (T) -> R,
    consume: (T, Result<R>) -> Unit,
): Boolean {
    if (items.isEmpty()) return true
    val workers = minOf(SAF_READ_WORKERS, items.size)
    val executor = Executors.newFixedThreadPool(workers)
    try {
        val window = workers * 4
        val inFlight = ArrayDeque<Pair<T, Future<R>>>(window)
        var next = 0
        while (next < items.size || inFlight.isNotEmpty()) {
            if (cancelled()) {
                inFlight.forEach { it.second.cancel(true) }
                return false
            }
            while (inFlight.size < window && next < items.size) {
                val item = items[next++]
                inFlight.addLast(item to executor.submit<R> { task(item) })
            }
            val (item, future) = inFlight.removeFirst()
            val result = try {
                Result.success(future.get())
            } catch (e: ExecutionException) {
                Result.failure(e.cause ?: e)
            } catch (e: Exception) {
                Result.failure(e)
            }
            consume(item, result)
        }
        return true
    } finally {
        executor.shutdownNow()
    }
}

internal fun MainActivity.resolveCueAudioSibling(
        parentDir: DocumentFile,
        cueName: String,
        audioFileName: String?,
        childLookupCache: MutableMap<String, Map<String, DocumentFile>>,
    ): DocumentFile? {
        val childLookup = getSafChildFileLookup(parentDir, childLookupCache)

        val directMatch = audioFileName
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.substringAfterLast("/")
            ?.substringAfterLast("\\")
            ?.lowercase(Locale.ROOT)
            ?.let(childLookup::get)
        if (directMatch != null) {
            return directMatch
        }

        val cueBaseName = cueName.substringBeforeLast('.').trim()
        if (cueBaseName.isBlank()) {
            return null
        }

        val cueBaseKey = cueBaseName.lowercase(Locale.ROOT)
        for (ext in cueSiblingAudioExtensions) {
            childLookup["$cueBaseKey$ext"]?.let { return it }
        }
        return null
    }

internal data class SafChildEntry(
    val doc: DocumentFile,
    val name: String?,
    val isDirectory: Boolean,
    val lastModified: Long,
    val isFile: Boolean,
)

internal fun Context.listSafChildrenOrThrow(
    dir: DocumentFile,
    includeLastModified: Boolean = true,
): List<SafChildEntry> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            dir.uri,
            DocumentsContract.getDocumentId(dir.uri),
        )
        val projection = mutableListOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        if (includeLastModified) projection.add(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
        val cursor = try {
            contentResolver.query(childrenUri, projection.toTypedArray(), null, null, null)
        } catch (_: Exception) {
            // A few older providers reject the richer projection; retry with IDs.
            contentResolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
                null,
                null,
                null,
            )
        } ?: throw IOException("SAF provider returned no cursor for ${dir.uri}")
        return cursor.use {
            val documentIdIndex = it.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            )
            val displayNameIndex = it.getColumnIndex(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            val mimeTypeIndex = it.getColumnIndex(
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            val lastModifiedIndex = it.getColumnIndex(
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            )
            buildList {
                while (it.moveToNext()) {
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(
                        dir.uri,
                        it.getString(documentIdIndex),
                    )
                    val child = DocumentFile.fromTreeUri(this@listSafChildrenOrThrow, childUri)
                        ?: throw IOException("Invalid SAF child URI: $childUri")
                    val name = if (displayNameIndex >= 0 && !it.isNull(displayNameIndex)) {
                        it.getString(displayNameIndex)
                    } else {
                        try { child.name } catch (_: Exception) { null }
                    }
                    val mimeType = if (mimeTypeIndex >= 0 && !it.isNull(mimeTypeIndex)) {
                        it.getString(mimeTypeIndex)
                    } else {
                        null
                    }
                    val isDirectory = if (mimeType != null) {
                        mimeType == MIME_TYPE_DIR
                    } else {
                        try { child.isDirectory } catch (_: Exception) { false }
                    }
                    val isFile = if (mimeType != null) {
                        mimeType.isNotEmpty() && !isDirectory
                    } else {
                        !isDirectory && try { child.isFile } catch (_: Exception) { false }
                    }
                    val lastModified = if (!includeLastModified) {
                        0L
                    } else if (
                        lastModifiedIndex >= 0 && !it.isNull(lastModifiedIndex)
                    ) {
                        it.getLong(lastModifiedIndex)
                    } else {
                        try { child.lastModified() } catch (_: Exception) { 0L }
                    }
                    add(SafChildEntry(child, name, isDirectory, lastModified, isFile))
                }
            }
        }
    }

internal fun MainActivity.resolveReadableSafTreeOrThrow(
        treeUriStr: String,
    ): Pair<Uri, DocumentFile> {
        if (treeUriStr.isBlank()) {
            throw IllegalArgumentException("SAF tree URI is empty")
        }
        val treeUri = Uri.parse(treeUriStr)
        val hasReadPermission = contentResolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isReadPermission
        } || checkUriPermission(
            treeUri,
            android.os.Process.myPid(),
            android.os.Process.myUid(),
            Intent.FLAG_GRANT_READ_URI_PERMISSION,
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasReadPermission) {
            throw SecurityException("Read access to the SAF tree has been revoked")
        }
        val root = DocumentFile.fromTreeUri(this, treeUri)
            ?: throw IOException("Unable to resolve SAF tree")
        if (!root.exists() || !root.canRead()) {
            throw IOException("SAF tree is unavailable or unreadable")
        }
        return treeUri to root
    }

internal fun MainActivity.scanSafTree(
        treeUriStr: String,
        ndjsonOutputPath: String? = null,
    ): Any {
        val earlyCheckpoint = ndjsonOutputPath
            ?.takeIf {
                File(it).exists() && File(safScanCheckpointPath(it)).exists()
            }
            ?.let { loadSafScanCheckpoint(safScanCheckpointPath(it)) }
            ?: mutableMapOf()

        fun emptyResult(): Any {
            if (ndjsonOutputPath == null) return "[]"
            if (earlyCheckpoint.isNotEmpty() && File(ndjsonOutputPath).exists()) {
                throw IOException("SAF scan returned no files while a resumable scan exists")
            }
            File(ndjsonOutputPath).writeText("", Charsets.UTF_8)
            try { File(safScanCheckpointPath(ndjsonOutputPath)).delete() } catch (_: Exception) {}
            return mapOf("path" to ndjsonOutputPath, "count" to 0, "error_count" to 0)
        }

        fun cancelledResult(): Any {
            updateSafScanProgress { it.isComplete = true }
            if (ndjsonOutputPath == null) return "[]"
            // Preserve partial output so the next scan can resume.
            throw java.util.concurrent.CancellationException("SAF library scan cancelled")
        }

        val (_, root) = resolveReadableSafTreeOrThrow(treeUriStr)

        resetSafScanProgress()
        safScanCancel = false
        safScanActive = true
        updateSafScanProgress {
            it.scannedFiles = earlyCheckpoint.size
            it.currentFile = if (earlyCheckpoint.isEmpty()) {
                "Scanning folders..."
            } else {
                "Resuming scan..."
            }
        }

        val supportedAudioExt = libraryScanAudioExtensions
        data class SafAudioEntry(
            val doc: DocumentFile,
            val name: String,
            val lastModified: Long,
        )
        data class SafCueEntry(
            val doc: DocumentFile,
            val parentDir: DocumentFile,
            val name: String,
            val lastModified: Long,
        )
        val audioFiles = mutableListOf<SafAudioEntry>()
        val cueFiles = mutableListOf<SafCueEntry>()
        val visitedDirUris = mutableSetOf<String>()
        val safChildLookupCache = mutableMapOf<String, Map<String, DocumentFile>>()
        var traversalErrors = 0

        val queue: ArrayDeque<Pair<DocumentFile, String>> = ArrayDeque()
        queue.add(root to "")
        val lister = SafTreeLister(this)

        while (queue.isNotEmpty()) {
            if (safScanStopRequested()) {
                return cancelledResult()
            }

            val (dir, path) = queue.removeFirst()
            val dirUri = dir.uri.toString()
            if (!visitedDirUris.add(dirUri)) {
                continue
            }

            val listing = lister.list(dir, queue, visitedDirUris)
            val children = listing.getOrNull()
            if (children == null) {
                traversalErrors++
                updateSafScanProgress { it.errorCount = traversalErrors }
                android.util.Log.w(
                    "SpotiFLAC",
                    "SAF scan: failed listing directory $dirUri: ${listing.exceptionOrNull()?.message}",
                )
                continue
            }
            rememberCueDirectoryListing(dir, children, safChildLookupCache)

            for (child in children) {
                if (safScanStopRequested()) {
                    return cancelledResult()
                }

                try {
                    if (child.isDirectory) {
                        val childName = child.name ?: continue
                        val childPath = if (path.isBlank()) childName else "$path/$childName"
                        val childUri = child.doc.uri.toString()
                        if (childUri == dirUri || visitedDirUris.contains(childUri)) {
                            continue
                        }
                        queue.add(child.doc to childPath)
                    } else {
                        val name = child.name ?: continue
                        val lastModified = child.lastModified
                        val ext = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
                        if (ext == "cue") {
                            cueFiles.add(SafCueEntry(child.doc, dir, name, lastModified))
                        } else if (ext.isNotBlank() && supportedAudioExt.contains(".$ext")) {
                            audioFiles.add(SafAudioEntry(child.doc, name, lastModified))
                        }
                    }
                } catch (e: Exception) {
                    traversalErrors++
                    updateSafScanProgress { it.errorCount = traversalErrors }
                    android.util.Log.w(
                        "SpotiFLAC",
                        "SAF scan: skipped child under $dirUri: ${e.message}",
                    )
                }
            }
        }

        if (traversalErrors > 0) {
            throw IOException("SAF traversal failed for $traversalErrors entries")
        }

        val totalItems = audioFiles.size + cueFiles.size
        updateSafScanProgress {
            it.totalFiles = totalItems
            if (totalItems > 0 && earlyCheckpoint.isNotEmpty()) {
                it.scannedFiles = earlyCheckpoint.size.coerceAtMost(totalItems)
                it.progressPct = it.scannedFiles.toDouble() / totalItems.toDouble() * 100.0
            }
        }

        if (audioFiles.isEmpty() && cueFiles.isEmpty()) {
            updateSafScanProgress {
                it.isComplete = true
                it.progressPct = 100.0
            }
            return emptyResult()
        }

        // Stream results to a spill file: a full-library scan's JSONArray plus
        // its serialized string would otherwise hold the whole payload on the
        // Java heap several times over.
        val spill = if (ndjsonOutputPath == null) this.SpillJsonWriter() else null
        val outputPath = ndjsonOutputPath
        val checkpointPath = outputPath?.let(::safScanCheckpointPath)
        val checkpoint = if (checkpointPath != null) {
            val outputFile = File(requireNotNull(outputPath))
            val checkpointFile = File(checkpointPath)
            outputFile.parentFile?.mkdirs()
            // Discard stale output that has no checkpoint.
            if (outputFile.exists() && !checkpointFile.exists()) {
                try { outputFile.delete() } catch (_: Exception) {}
            } else if (!outputFile.exists() && checkpointFile.exists()) {
                try { checkpointFile.delete() } catch (_: Exception) {}
            }
            repairSafScanOutput(outputFile.absolutePath)
            reconcileSafScanCheckpoint(
                outputFile.absolutePath,
                loadSafScanCheckpoint(checkpointPath),
            )
        } else {
            mutableMapOf()
        }
        val checkpointWriter = checkpointPath?.let {
            FileOutputStream(File(it), true).bufferedWriter(Charsets.UTF_8)
        }
        val ndjsonWriter = outputPath?.let {
            FileOutputStream(File(it), true).bufferedWriter(Charsets.UTF_8)
        }
        var resultCount = outputPath?.let(::countSafScanRows) ?: 0
        fun checkpointed(uri: String, lastModified: Long): Boolean =
            checkpoint[uri] == lastModified

        fun recordCheckpoint(uri: String, lastModified: Long) {
            if (checkpointWriter == null || uri.isBlank()) return
            checkpoint[uri] = lastModified
            checkpointWriter.write(uri)
            checkpointWriter.write('\t'.code)
            checkpointWriter.write(lastModified.toString())
            checkpointWriter.newLine()
            checkpointWriter.flush()
        }

        fun putResult(obj: JSONObject) {
            if (ndjsonWriter != null) {
                ndjsonWriter.write(obj.toString())
                ndjsonWriter.newLine()
            } else {
                spill!!.raw(if (resultCount == 0) "[" else ",")
                spill.raw(obj.toString())
            }
            resultCount++
        }
        try {
        var scanned = checkpoint.size.coerceAtMost(totalItems)
        var errors = traversalErrors

        val cueReferencedAudioUris = mutableSetOf<String>()

        for (cue in cueFiles) {
            val cueDoc = cue.doc
            val parentDir = cue.parentDir
            val cueUri = cueDoc.uri.toString()
            val cueAlreadyIndexed = checkpointed(cueUri, cue.lastModified)
            if (safScanStopRequested()) {
                ndjsonWriter?.close()
                spill?.abandon()
                return cancelledResult()
            }

            val cueName = cue.name
            updateSafScanProgress { it.currentFile = cueName }

            var tempCuePath: String? = null
            var tempAudioPath: String? = null
            try {
                tempCuePath = copyUriToTemp(cueDoc.uri, ".cue", cueName)
                if (tempCuePath == null) {
                    errors++
                    android.util.Log.w("SpotiFLAC", "SAF scan: failed to copy CUE ${cueDoc.uri}")
                    scanned++
                    continue
                }

                val audioFileName = extractCueAudioFileName(tempCuePath)

                val audioDoc = resolveCueAudioSibling(
                    parentDir = parentDir,
                    cueName = cueName,
                    audioFileName = audioFileName,
                    childLookupCache = safChildLookupCache,
                )

                if (audioDoc == null) {
                    android.util.Log.w("SpotiFLAC", "SAF scan: no audio file found for CUE $cueName")
                    errors++
                    scanned++
                    continue
                }

                cueReferencedAudioUris.add(audioDoc.uri.toString())

                if (cueAlreadyIndexed) {
                    continue
                }

                val tempDir = File(tempCuePath).parent ?: cacheDir.absolutePath
                val audioName = try { audioDoc.name ?: "audio.flac" } catch (_: Exception) { "audio.flac" }
                val audioExt = audioName.substringAfterLast('.', "").lowercase(Locale.ROOT)
                val fallbackAudioExt = if (audioExt.isNotBlank()) ".$audioExt" else null
                val audioLastModified = try { audioDoc.lastModified() } catch (_: Exception) { cueDoc.lastModified() }
                val coverCacheKey = buildLibraryCoverCacheKey(
                    audioDoc.uri.toString(),
                    audioLastModified,
                )

                tempAudioPath = copyUriToTemp(audioDoc.uri, fallbackAudioExt)
                if (tempAudioPath == null) {
                    android.util.Log.w("SpotiFLAC", "SAF scan: failed to copy audio for CUE $cueName")
                    errors++
                    scanned++
                    continue
                }

                val renamedAudio = File(tempDir, audioName)
                val tempAudioFile = File(tempAudioPath)
                if (renamedAudio.absolutePath != tempAudioFile.absolutePath) {
                    tempAudioFile.renameTo(renamedAudio)
                    tempAudioPath = renamedAudio.absolutePath
                }

                val cueLastModified = cue.lastModified

                val cueResultsJson = coreBackend.scanCueForLibrary(
                    tempCuePath,
                    tempDir,
                    cueDoc.uri.toString(),
                    cueLastModified,
                    coverCacheKey,
                )

                val cueArray = JSONArray(cueResultsJson)
                for (j in 0 until cueArray.length()) {
                    putResult(cueArray.getJSONObject(j))
                }
                ndjsonWriter?.flush()
                recordCheckpoint(cueUri, cue.lastModified)

            } catch (e: Exception) {
                errors++
                android.util.Log.w("SpotiFLAC", "SAF scan: error processing CUE $cueName: ${e.message}")
            } finally {
                try { tempCuePath?.let { File(it).delete() } } catch (_: Exception) {}
                try { tempAudioPath?.let { File(it).delete() } } catch (_: Exception) {}
            }

            scanned++
            val pct = scanned.toDouble() / totalItems.toDouble() * 100.0
            updateSafScanProgress {
                it.scannedFiles = scanned
                it.errorCount = errors
                it.progressPct = pct
            }
        }

        data class SafAudioScanOutcome(
            val uri: String,
            val name: String,
            val lastModified: Long,
            val metadata: JSONObject?,
        )

        val pendingAudio = mutableListOf<SafAudioEntry>()
        // Skip resumable and CUE entries before parallel reads.
        for (audio in audioFiles) {
            val doc = audio.doc
            if (safScanStopRequested()) {
                ndjsonWriter?.close()
                spill?.abandon()
                return cancelledResult()
            }

            val stableUri = doc.uri.toString()
            val lastModified = audio.lastModified
            if (checkpointed(stableUri, lastModified)) {
                continue
            }
            if (cueReferencedAudioUris.contains(stableUri)) {
                recordCheckpoint(stableUri, lastModified)
                scanned++
                val pct = scanned.toDouble() / totalItems.toDouble() * 100.0
                updateSafScanProgress {
                    it.scannedFiles = scanned
                    it.progressPct = pct
                }
                continue
            }
            pendingAudio.add(audio)
        }

        // Descriptor reads stream from the provider without copying, so the
        // pool is bounded by provider round trips rather than copy memory.
        val completed = runSafReadsInOrder(
            pendingAudio,
            cancelled = { safScanStopRequested() },
            task = { audio ->
                val doc = audio.doc
                val stableUri = doc.uri.toString()
                val name = audio.name
                val lastModified = audio.lastModified
                val ext = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
                val fallbackExt = if (ext.isNotBlank()) ".${ext}" else null
                val coverCacheKey = buildLibraryCoverCacheKey(stableUri, lastModified)
                val metadata = try {
                    readAudioMetadataFromUri(
                        doc.uri,
                        name,
                        fallbackExt,
                        coverCacheKey,
                    )
                } catch (e: Exception) {
                    android.util.Log.w(
                        "SpotiFLAC",
                        "SAF scan: metadata read failed for $stableUri: ${e.message}",
                    )
                    null
                }
                SafAudioScanOutcome(stableUri, name, lastModified, metadata)
            },
        ) { _, result ->
            val outcome = result.getOrNull()
            if (outcome == null) {
                errors++
            } else {
                updateSafScanProgress { it.currentFile = outcome.name }
                val metadataObj = outcome.metadata
                if (metadataObj == null) {
                    errors++
                } else {
                    try {
                        metadataObj.put("id", buildStableLibraryId(outcome.uri))
                        metadataObj.put("filePath", outcome.uri)
                        metadataObj.put("fileModTime", outcome.lastModified)
                        putResult(metadataObj)
                        // Flush before recording the checkpoint to avoid losing the row.
                        ndjsonWriter?.flush()
                        recordCheckpoint(outcome.uri, outcome.lastModified)
                    } catch (_: Exception) {
                        errors++
                    }
                }
            }

            scanned++
            val pct = scanned.toDouble() / totalItems.toDouble() * 100.0
            updateSafScanProgress {
                it.scannedFiles = scanned
                it.errorCount = errors
                it.progressPct = pct
            }
        }
        if (!completed) {
            ndjsonWriter?.close()
            spill?.abandon()
            return cancelledResult()
        }

        updateSafScanProgress {
            it.isComplete = true
            it.progressPct = 100.0
        }

        if (ndjsonWriter != null) {
            ndjsonWriter.close()
            checkpointWriter?.close()
            return mapOf("path" to outputPath, "count" to resultCount, "error_count" to errors)
        }
        spill!!.raw(if (resultCount == 0) "[]" else "]")
        return spill.result()
        } catch (e: Exception) {
            try { ndjsonWriter?.close() } catch (_: Exception) {}
            try { checkpointWriter?.close() } catch (_: Exception) {}
            spill?.abandon()
            // Preserve partial output for resume.
            throw e
        }
    }

    /**
     * Incremental SAF tree scan - only scans new or modified files.
     * Supports .cue sheets: expands them into virtual track entries and
     * deduplicates audio files referenced by CUE sheets.
     * @param treeUriStr The SAF tree URI to scan
     * @param existingFilesJson JSON object mapping file URI -> lastModified timestamp
     * @return JSON object with new/changed files and removed URIs
     */
internal fun MainActivity.scanSafTreeIncremental(treeUriStr: String, existingFilesJson: String): Any {
        val existingFiles = mutableMapOf<String, Long>()
        try {
            val obj = JSONObject(existingFilesJson)
            val keys = obj.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                existingFiles[key] = obj.optLong(key, 0)
            }
        } catch (_: Exception) {}
        return scanSafTreeIncremental(treeUriStr, existingFiles)
    }

internal fun MainActivity.scanSafTreeIncremental(
        treeUriStr: String,
        existingFiles: Map<String, Long>,
    ): Any {
        val (_, root) = resolveReadableSafTreeOrThrow(treeUriStr)

        resetSafScanProgress()
        safScanCancel = false
        safScanActive = true
        updateSafScanProgress {
            it.currentFile = "Scanning folders..."
        }

        val supportedAudioExt = libraryScanAudioExtensions
        // Names and timestamps come from the directory listing; querying each
        // document again costs a provider round trip per changed file.
        data class ChangedAudio(val doc: DocumentFile, val name: String, val lastModified: Long)
        data class CueEntry(
            val doc: DocumentFile,
            val parentDir: DocumentFile,
            val name: String,
            val lastModified: Long,
        )
        val audioFiles = mutableListOf<ChangedAudio>()
        val cueFilesToScan = mutableListOf<CueEntry>()
        val unchangedCueFiles = mutableListOf<CueEntry>()
        val currentUris = mutableSetOf<String>()
        val visitedDirUris = mutableSetOf<String>()
        val safChildLookupCache = mutableMapOf<String, Map<String, DocumentFile>>()
        var traversalErrors = 0

        val existingCueVirtualPaths = mutableMapOf<String, MutableList<String>>()
        for (key in existingFiles.keys) {
            val hashIdx = key.indexOf("#track")
            if (hashIdx > 0) {
                val baseCueUri = key.substring(0, hashIdx)
                existingCueVirtualPaths.getOrPut(baseCueUri) { mutableListOf() }.add(key)
            }
        }

        val queue: ArrayDeque<Pair<DocumentFile, String>> = ArrayDeque()
        queue.add(root to "")
        val lister = SafTreeLister(this)

        while (queue.isNotEmpty()) {
            if (safScanStopRequested()) {
                updateSafScanProgress { it.isComplete = true }
                val result = JSONObject()
                result.put("files", JSONArray())
                result.put("removedUris", JSONArray())
                result.put("skippedCount", 0)
                result.put("totalFiles", 0)
                result.put("cancelled", true)
                return result.toString()
            }

            val (dir, path) = queue.removeFirst()
            val dirUri = dir.uri.toString()
            if (!visitedDirUris.add(dirUri)) {
                continue
            }

            val listing = lister.list(dir, queue, visitedDirUris)
            val children = listing.getOrNull()
            if (children == null) {
                traversalErrors++
                updateSafScanProgress { it.errorCount = traversalErrors }
                android.util.Log.w(
                    "SpotiFLAC",
                    "SAF incremental scan: failed listing directory $dirUri: ${listing.exceptionOrNull()?.message}",
                )
                continue
            }
            rememberCueDirectoryListing(dir, children, safChildLookupCache)

            for (child in children) {
                if (safScanStopRequested()) {
                    updateSafScanProgress { it.isComplete = true }
                    val result = JSONObject()
                    result.put("files", JSONArray())
                    result.put("removedUris", JSONArray())
                    result.put("skippedCount", 0)
                    result.put("totalFiles", 0)
                    result.put("cancelled", true)
                    return result.toString()
                }

                try {
                    if (child.isDirectory) {
                        val childName = child.name ?: continue
                        val childPath = if (path.isBlank()) childName else "$path/$childName"
                        val childUri = child.doc.uri.toString()
                        if (childUri == dirUri || visitedDirUris.contains(childUri)) {
                            continue
                        }
                        queue.add(child.doc to childPath)
                    } else {
                        val uriStr = child.doc.uri.toString()
                        currentUris.add(uriStr)

                        val name = child.name ?: continue
                        val ext = name.substringAfterLast('.', "").lowercase(Locale.ROOT)

                        if (ext == "cue") {
                            val lastModified = child.lastModified

                            val virtualPaths = existingCueVirtualPaths[uriStr]
                            val existingModified = virtualPaths?.firstOrNull()?.let { existingFiles[it] }

                            if (existingModified != null && existingModified == lastModified) {
                                unchangedCueFiles.add(CueEntry(child.doc, dir, name, lastModified))
                                for (vp in virtualPaths) {
                                    currentUris.add(vp)
                                }
                            } else {
                                cueFilesToScan.add(CueEntry(child.doc, dir, name, lastModified))
                            }
                        } else if (ext.isNotBlank() && supportedAudioExt.contains(".$ext")) {
                            val existingModified = existingFiles[uriStr]
                            val lastModified = child.lastModified

                            if (existingModified == null || existingModified != lastModified) {
                                audioFiles.add(ChangedAudio(child.doc, name, lastModified))
                            }
                        }
                    }
                } catch (e: Exception) {
                    traversalErrors++
                    updateSafScanProgress { it.errorCount = traversalErrors }
                    android.util.Log.w(
                        "SpotiFLAC",
                        "SAF incremental scan: skipped child under $dirUri: ${e.message}",
                    )
                }
            }
        }

        if (traversalErrors > 0) {
            throw IOException("SAF traversal failed for $traversalErrors entries")
        }

        val removedUris = existingFiles.keys.filter { !currentUris.contains(it) }
        val totalFiles = currentUris.size
        val filesToProcess = audioFiles.size + cueFilesToScan.size
        val skippedCount = (totalFiles - filesToProcess).coerceAtLeast(0)

        updateSafScanProgress {
            it.totalFiles = totalFiles
        }

        if (audioFiles.isEmpty() && cueFilesToScan.isEmpty()) {
            updateSafScanProgress {
                it.isComplete = true
                it.scannedFiles = totalFiles
                it.progressPct = 100.0
            }
            val result = JSONObject()
            result.put("files", JSONArray())
            result.put("removedUris", JSONArray(removedUris))
            result.put("skippedCount", skippedCount)
            result.put("totalFiles", totalFiles)
            return result.toString()
        }

        // Stream changed-file entries to a spill file — after a cache loss an
        // incremental scan can be as large as a full scan.
        val spill = this.SpillJsonWriter()
        spill.raw("{\"files\":[")
        var fileCount = 0
        fun putFile(obj: JSONObject) {
            if (fileCount > 0) spill.raw(",")
            spill.raw(obj.toString())
            fileCount++
        }
        var scanned = 0
        var errors = traversalErrors

        val cueReferencedAudioUris = mutableSetOf<String>()

        for ((cueDoc, parentDir, cueName, cueLastModified) in cueFilesToScan) {
            if (safScanStopRequested()) {
                updateSafScanProgress { it.isComplete = true }
                spill.abandon()
                val result = JSONObject()
                result.put("files", JSONArray())
                result.put("removedUris", JSONArray())
                result.put("skippedCount", skippedCount)
                result.put("totalFiles", totalFiles)
                result.put("cancelled", true)
                return result.toString()
            }

            updateSafScanProgress { it.currentFile = cueName }

            var tempCuePath: String? = null
            var tempAudioPath: String? = null
            try {
                tempCuePath = copyUriToTemp(cueDoc.uri, ".cue", cueName)
                if (tempCuePath == null) {
                    errors++
                    android.util.Log.w("SpotiFLAC", "SAF incremental scan: failed to copy CUE ${cueDoc.uri}")
                    scanned++
                    continue
                }

                val audioFileName = extractCueAudioFileName(tempCuePath)

                val audioDoc = resolveCueAudioSibling(
                    parentDir = parentDir,
                    cueName = cueName,
                    audioFileName = audioFileName,
                    childLookupCache = safChildLookupCache,
                )

                if (audioDoc == null) {
                    android.util.Log.w("SpotiFLAC", "SAF incremental scan: no audio file found for CUE $cueName")
                    errors++
                    scanned++
                    continue
                }

                cueReferencedAudioUris.add(audioDoc.uri.toString())

                val tempDir = File(tempCuePath).parent ?: cacheDir.absolutePath
                val audioName = try { audioDoc.name ?: "audio.flac" } catch (_: Exception) { "audio.flac" }
                val audioExt = audioName.substringAfterLast('.', "").lowercase(Locale.ROOT)
                val fallbackAudioExt = if (audioExt.isNotBlank()) ".$audioExt" else null
                val audioLastModified = try { audioDoc.lastModified() } catch (_: Exception) { cueLastModified }
                val coverCacheKey = buildLibraryCoverCacheKey(
                    audioDoc.uri.toString(),
                    audioLastModified,
                )

                tempAudioPath = copyUriToTemp(audioDoc.uri, fallbackAudioExt)
                if (tempAudioPath == null) {
                    android.util.Log.w("SpotiFLAC", "SAF incremental scan: failed to copy audio for CUE $cueName")
                    errors++
                    scanned++
                    continue
                }

                val renamedAudio = File(tempDir, audioName)
                val tempAudioFile = File(tempAudioPath)
                if (renamedAudio.absolutePath != tempAudioFile.absolutePath) {
                    tempAudioFile.renameTo(renamedAudio)
                    tempAudioPath = renamedAudio.absolutePath
                }

                val cueResultsJson = coreBackend.scanCueForLibrary(
                    tempCuePath,
                    tempDir,
                    cueDoc.uri.toString(),
                    cueLastModified,
                    coverCacheKey,
                )

                val cueArray = JSONArray(cueResultsJson)
                for (j in 0 until cueArray.length()) {
                    val trackObj = cueArray.getJSONObject(j)
                    putFile(trackObj)
                    val virtualPath = trackObj.optString("filePath", "")
                    if (virtualPath.isNotBlank()) {
                        currentUris.add(virtualPath)
                    }
                }

            } catch (e: Exception) {
                errors++
                android.util.Log.w("SpotiFLAC", "SAF incremental scan: error processing CUE $cueName: ${e.message}")
            } finally {
                try { tempCuePath?.let { File(it).delete() } } catch (_: Exception) {}
                try { tempAudioPath?.let { File(it).delete() } } catch (_: Exception) {}
            }

            scanned++
            val processed = skippedCount + scanned
            val pct = if (totalFiles > 0) {
                processed.toDouble() / totalFiles.toDouble() * 100.0
            } else {
                100.0
            }
            updateSafScanProgress {
                it.scannedFiles = processed
                it.errorCount = errors
                it.progressPct = pct
            }
        }

        for ((cueDoc, parentDir, cueName) in unchangedCueFiles) {
            var tempCue: String? = null
            try {
                tempCue = copyUriToTemp(cueDoc.uri, ".cue", cueName)
                if (tempCue != null) {
                    val audioFileName = extractCueAudioFileName(tempCue)
                    val audioDoc = resolveCueAudioSibling(
                        parentDir = parentDir,
                        cueName = cueName,
                        audioFileName = audioFileName,
                        childLookupCache = safChildLookupCache,
                    )
                    if (audioDoc != null) {
                        cueReferencedAudioUris.add(audioDoc.uri.toString())
                    }
                }
            } catch (e: Exception) {
                android.util.Log.w("SpotiFLAC", "SAF incremental scan: failed to resolve audio for unchanged CUE: ${e.message}")
            } finally {
                try { tempCue?.let { File(it).delete() } } catch (_: Exception) {}
            }
        }

        fun cancelledIncrementalResult(): String {
            updateSafScanProgress { it.isComplete = true }
            spill.abandon()
            val result = JSONObject()
            result.put("files", JSONArray())
            result.put("removedUris", JSONArray())
            result.put("skippedCount", skippedCount)
            result.put("totalFiles", totalFiles)
            result.put("cancelled", true)
            return result.toString()
        }

        fun reportProcessed() {
            val processed = skippedCount + scanned
            val pct = if (totalFiles > 0) {
                processed.toDouble() / totalFiles.toDouble() * 100.0
            } else {
                100.0
            }
            updateSafScanProgress {
                it.scannedFiles = processed
                it.errorCount = errors
                it.progressPct = pct
            }
        }

        val pendingAudio = mutableListOf<ChangedAudio>()
        for (audio in audioFiles) {
            if (safScanStopRequested()) return cancelledIncrementalResult()
            if (cueReferencedAudioUris.contains(audio.doc.uri.toString())) {
                scanned++
                reportProcessed()
            } else {
                pendingAudio.add(audio)
            }
        }

        val completed = runSafReadsInOrder(
            pendingAudio,
            cancelled = { safScanStopRequested() },
            task = { audio ->
                val ext = audio.name.substringAfterLast('.', "").lowercase(Locale.ROOT)
                val fallbackExt = if (ext.isNotBlank()) ".${ext}" else null
                readAudioMetadataFromUri(
                    audio.doc.uri,
                    audio.name,
                    fallbackExt,
                    buildLibraryCoverCacheKey(audio.doc.uri.toString(), audio.lastModified),
                )
            },
        ) { audio, result ->
            updateSafScanProgress { it.currentFile = audio.name }
            // A failed read aborts the incremental scan, as it did when serial.
            val metadataObj = result.getOrThrow()
            if (metadataObj == null) {
                errors++
            } else {
                try {
                    val stableUri = audio.doc.uri.toString()
                    metadataObj.put("id", buildStableLibraryId(stableUri))
                    metadataObj.put("filePath", stableUri)
                    metadataObj.put("fileModTime", audio.lastModified)
                    metadataObj.put("lastModified", audio.lastModified)
                    putFile(metadataObj)
                } catch (_: Exception) {
                    errors++
                }
            }
            scanned++
            reportProcessed()
        }
        if (!completed) return cancelledIncrementalResult()

        val finalRemovedUris = existingFiles.keys.filter { !currentUris.contains(it) }

        updateSafScanProgress {
            it.isComplete = true
            it.progressPct = 100.0
        }

        spill.raw("],\"removedUris\":")
        spill.raw(JSONArray(finalRemovedUris).toString())
        spill.raw(",\"skippedCount\":$skippedCount,\"totalFiles\":$totalFiles}")
        return spill.result()
    }

// A failed DocumentsProvider query must never be mistaken for a missing file.
// Unlike DocumentFile.exists(), this keeps null cursors/exceptions inconclusive.
internal fun MainActivity.safExistsBatch(urisJson: String): String {
    val result = JSONObject()
    val uris = JSONArray(urisJson)
    val accessibleTrees = mutableMapOf<String, Boolean>()
    val permissions = contentResolver.persistedUriPermissions
    val projection = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
    for (index in 0 until uris.length()) {
        val path = uris.optString(index)
        if (path.isBlank()) continue
        var status = "unknown"
        try {
            val uri = Uri.parse(path)
            val treeAccessible = if (DocumentsContract.isTreeUri(uri)) {
                val treeId = DocumentsContract.getTreeDocumentId(uri)
                val tree = DocumentsContract.buildTreeDocumentUri(uri.authority, treeId)
                accessibleTrees.getOrPut(tree.toString()) {
                    val granted = permissions.any { it.uri == tree && it.isReadPermission }
                    if (!granted) false else {
                        val root = DocumentsContract.buildDocumentUriUsingTree(tree, treeId)
                        contentResolver.query(root, projection, null, null, null)?.use {
                            it.moveToFirst()
                        } == true
                    }
                }
            } else false
            contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                status = if (cursor.moveToFirst()) "found"
                    else if (treeAccessible &&
                        !cursor.extras.getBoolean(DocumentsContract.EXTRA_LOADING, false))
                        "missing" else "unknown"
            }
        } catch (_: Exception) {
            // Revoked permission, offline storage and provider errors: retain row.
        }
        result.put(path, status)
    }
    return result.toString()
}

/**
 * Resolve SAF file last-modified values for a list of content URIs.
 * Returns JSON object mapping uri -> lastModified (unix millis).
 */
internal fun MainActivity.getSafFileModTimes(urisJson: String): String {
        val result = JSONObject()
        val uris = try {
            JSONArray(urisJson)
        } catch (_: Exception) {
            JSONArray()
        }

        for (i in 0 until uris.length()) {
            val uriStr = uris.optString(i, "")
            if (uriStr.isBlank()) continue
            try {
                val uri = Uri.parse(uriStr)
                val doc = DocumentFile.fromSingleUri(this, uri)
                if (doc != null && doc.exists()) {
                    result.put(uriStr, doc.lastModified())
                }
            } catch (_: Exception) {}
        }

        return result.toString()
    }
