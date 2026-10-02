package com.zarz.spotiflac.missingtracks

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
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
import java.security.MessageDigest
import java.util.Locale

// SAF/MediaStore URI IO helpers: temp copies, writes, sidecars, and the
// SAF post-processing pipeline.

internal fun MainActivity.errorJson(message: String): String {
        val obj = JSONObject()
        obj.put("success", false)
        obj.put("error", message)
        obj.put("message", message)
        return obj.toString()
    }

    /**
     * Detect whether a content URI belongs to the MediaStore provider.
     * Samsung One UI may return MediaStore URIs from SAF tree traversal,
     * which require READ_MEDIA_AUDIO / READ_EXTERNAL_STORAGE permission
     * instead of SAF tree permission.
     */
internal fun MainActivity.isMediaStoreUri(uri: Uri): Boolean {
        val authority = uri.authority ?: return false
        return authority == "media" ||
               authority.startsWith("media.") ||
               authority.contains("media")
    }

    /**
     * Resolve extension from a MediaStore URI by querying DISPLAY_NAME or MIME_TYPE.
     */
internal fun MainActivity.resolveMediaStoreExt(uri: Uri, fallbackExt: String?): String {
        try {
            contentResolver.query(uri, arrayOf(android.provider.MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val name = cursor.getString(0)?.lowercase(Locale.ROOT) ?: ""
                    val ext = extFromFileName(name)
                    if (ext.isNotBlank()) return ext
                }
            }
        } catch (_: Exception) {}

        try {
            val mime = contentResolver.getType(uri)
            val ext = extFromMimeType(mime)
            if (ext.isNotBlank()) return ext
        } catch (_: Exception) {}

        return fallbackExt ?: ""
    }

internal fun MainActivity.extFromFileName(name: String): String {
        return when {
            name.endsWith(".m4a") -> ".m4a"
            name.endsWith(".mp4") -> ".mp4"
            name.endsWith(".aac") -> ".aac"
            name.endsWith(".mp3") -> ".mp3"
            name.endsWith(".opus") -> ".opus"
            name.endsWith(".flac") -> ".flac"
            name.endsWith(".ogg") -> ".ogg"
            name.endsWith(".wave") -> ".wav"
            name.endsWith(".wav") -> ".wav"
            name.endsWith(".aiff") -> ".aiff"
            name.endsWith(".aifc") -> ".aifc"
            name.endsWith(".aif") -> ".aif"
            name.endsWith(".dsf") -> ".dsf"
            name.endsWith(".dff") -> ".dff"
            else -> ""
        }
    }

internal fun MainActivity.extFromMimeType(mime: String?): String {
        return when (mime) {
            "audio/mp4" -> ".m4a"
            "audio/aac" -> ".aac"
            "audio/eac3" -> ".m4a"
            "audio/ac3" -> ".m4a"
            "audio/ac4" -> ".m4a"
            "audio/mpeg" -> ".mp3"
            "audio/ogg" -> ".opus"
            "audio/flac" -> ".flac"
            "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave" -> ".wav"
            "audio/aiff", "audio/x-aiff" -> ".aiff"
            else -> ""
        }
    }

/** [displayName] skips a provider name query when the caller already listed it. */
internal fun MainActivity.copyUriToTemp(
    uri: Uri,
    fallbackExt: String? = null,
    displayName: String? = null,
): String? {
        var tempFile: File? = null
        var success = false

        try {
            val nameHint = (
                displayName
                    ?: try { DocumentFile.fromSingleUri(this, uri)?.name } catch (_: Exception) { null }
                    ?: uri.lastPathSegment
                    ?: ""
            ).lowercase(Locale.ROOT)
            val extFromName = extFromFileName(nameHint)
            // The MIME type only matters when the name has no extension.
            val extFromMime = if (extFromName.isNotBlank()) "" else extFromMimeType(
                try { contentResolver.getType(uri) } catch (_: Exception) { null },
            )
            val ext = if (extFromName.isNotBlank()) extFromName else if (extFromMime.isNotBlank()) extFromMime else (fallbackExt ?: "")
            val suffix = ext.ifBlank { ".tmp" }
            tempFile = coreBackend.createTemporaryMediaFile(this, "saf_", suffix)

            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output, bufferSize = 256 * 1024)
                }
            } ?: return null

            success = true
            return tempFile.absolutePath
        } catch (e: SecurityException) {
            // SAF permission denied - try MediaStore fallback for Samsung One UI
            // which may return MediaStore URIs from SAF tree traversal
            if (isMediaStoreUri(uri)) {
                android.util.Log.d(
                    "SpotiFLAC",
                    "SAF denied for MediaStore URI, trying MediaStore fallback: $uri",
                )
                val result = copyMediaStoreUriToTemp(uri, fallbackExt)
                if (result != null) {
                    return result
                }
            }
            android.util.Log.w(
                "SpotiFLAC",
                "SAF read denied for $uri: ${e.message}",
            )
            return null
        } catch (e: Exception) {
            android.util.Log.w(
                "SpotiFLAC",
                "Failed copying SAF uri $uri to temp: ${e.message}",
            )
            return null
        } finally {
            if (!success) {
                try {
                    tempFile?.delete()
                } catch (_: Exception) {}
            }
        }
    }

    /**
     * Fallback for Samsung One UI: read a MediaStore content URI using
     * READ_MEDIA_AUDIO / READ_EXTERNAL_STORAGE permission instead of SAF.
     * This handles the case where SAF tree traversal returns MediaStore URIs
     * that the SAF document provider cannot access.
     */
internal fun MainActivity.copyMediaStoreUriToTemp(uri: Uri, fallbackExt: String?): String? {
        var tempFile: File? = null
        try {
            val ext = resolveMediaStoreExt(uri, fallbackExt)
            val suffix = ext.ifBlank { ".tmp" }
            tempFile = coreBackend.createTemporaryMediaFile(this, "ms_", suffix)

            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output, bufferSize = 256 * 1024)
                }
            } ?: run {
                tempFile.delete()
                return null
            }

            android.util.Log.d(
                "SpotiFLAC",
                "MediaStore fallback succeeded for $uri",
            )
            return tempFile.absolutePath
        } catch (e: Exception) {
            android.util.Log.w(
                "SpotiFLAC",
                "MediaStore fallback also failed for $uri: ${e.message}",
            )
            try { tempFile?.delete() } catch (_: Exception) {}
            return null
        }
    }

internal fun MainActivity.buildUriDisplayName(
        uri: Uri,
        displayNameHint: String? = null,
        fallbackExt: String? = null,
    ): String {
        val explicitName = displayNameHint?.trim().orEmpty()
        if (explicitName.isNotEmpty()) return explicitName

        val docName = try { DocumentFile.fromSingleUri(this, uri)?.name } catch (_: Exception) { null }
        val uriName = uri.lastPathSegment
        val resolvedName = (docName ?: uriName ?: "").trim()
        if (resolvedName.isNotEmpty()) return resolvedName

        val ext = when {
            fallbackExt.isNullOrBlank().not() -> fallbackExt
            isMediaStoreUri(uri) -> resolveMediaStoreExt(uri, fallbackExt)
            else -> ""
        }
        return if (ext.isNullOrBlank()) "audio" else "audio$ext"
    }

internal fun MainActivity.buildLibraryCoverCacheKey(stablePath: String, lastModified: Long): String {
        val normalizedPath = stablePath.trim()
        if (normalizedPath.isEmpty()) return ""
        return if (lastModified > 0L) "$normalizedPath|$lastModified" else normalizedPath
    }

private fun isSeekableSafDescriptor(descriptor: ParcelFileDescriptor): Boolean {
    return try {
        val position = Os.lseek(
            descriptor.fileDescriptor,
            0L,
            OsConstants.SEEK_CUR,
        )
        Os.lseek(descriptor.fileDescriptor, position, OsConstants.SEEK_SET)
        true
    } catch (_: Exception) {
        false
    }
}

/** Read-only metadata uses a seekable descriptor first. Capability belongs to
 * this descriptor: a pipe or revoked URI must not disable other providers. */
private fun MainActivity.readMetadataFromUri(
    uri: Uri,
    displayNameHint: String? = null,
    fallbackExt: String? = null,
    acceptDirect: (JSONObject) -> Boolean = { true },
    read: (String, String) -> JSONObject?,
): JSONObject? {
    val displayName = buildUriDisplayName(uri, displayNameHint, fallbackExt)
    return readSafMetadataWithFallback(
        directRead = {
            contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
                if (!isSeekableSafDescriptor(descriptor)) return@use null
                read("/proc/self/fd/${descriptor.fd}", displayName)?.takeIf(acceptDirect)
            }
        },
        fallbackRead = {
            val tempPath = copyUriToTemp(uri, fallbackExt)
            if (tempPath == null) null else try {
                read(tempPath, displayName)
            } finally {
                try { File(tempPath).delete() } catch (_: Exception) {}
            }
        },
    )
}

internal fun MainActivity.readAudioMetadataFromUri(
    uri: Uri,
    displayNameHint: String? = null,
    fallbackExt: String? = null,
    coverCacheKey: String = "",
): JSONObject? = readMetadataFromUri(
    uri, displayNameHint, fallbackExt,
    acceptDirect = { !it.optBoolean("metadataFromFilename", false) },
) { path, name ->
    if (name.endsWith(".dsf", true) || name.endsWith(".dff", true) || name.endsWith(".wv", true)) {
        DsdSource.open(path)?.use { source ->
            return@readMetadataFromUri JSONObject().apply {
                put("trackName", name.substringBeforeLast('.'))
                put("artistName", "Unknown Artist")
                put("albumName", "Unknown Album")
                put("filePath", uri.toString())
                put("format", name.substringAfterLast('.').lowercase(Locale.ROOT))
                put("sampleRate", source.rate)
                put("bitDepth", 1)
                put("duration", source.durationUs / 1000000)
                put("hasLyrics", false)
            }
        }
    }
    val obj = JSONObject(coreBackend.readAudioMetadata(
        path, name, coverCacheKey,
    ))
    obj.takeUnless { it.has("error") }
}

/** The Hi-Res check reads only a window from the middle of the file, so a
 * seekable descriptor avoids copying the whole track out of SAF. */
internal fun MainActivity.checkHiResAuthenticityFromUri(
    uri: Uri,
    optionsJson: String,
): JSONObject? = readMetadataFromUri(uri) { path, _ ->
    JSONObject(coreBackend.checkHiResAuthenticity(path, optionsJson))
}?.put("file_path", uri.toString())

internal fun MainActivity.readCompleteMetadataFromUri(
    uri: Uri,
    displayNameHint: String? = null,
): JSONObject? = readMetadataFromUri(uri, displayNameHint) { path, name ->
    JSONObject(coreBackend.readFileMetadata(path, name)).takeUnless { it.has("error") }
}

internal fun MainActivity.writeUriFromPath(uri: Uri, srcPath: String): Boolean {
        val srcFile = File(srcPath)
        if (!srcFile.exists()) return false
        contentResolver.openOutputStream(uri, "wt")?.use { output ->
            FileInputStream(srcFile).use { input ->
                input.copyTo(output, bufferSize = 256 * 1024)
            }
        } ?: return false
        return true
    }

    /**
     * Get the parent DocumentFile directory for a SAF document URI.
     * The child URI must be a tree-based document URI (e.g. from SAF tree scan).
     * Returns a DocumentFile that supports findFile() for sibling lookup.
     */
internal fun MainActivity.safParentDir(childUri: Uri): DocumentFile? {
        try {
            val docId = android.provider.DocumentsContract.getDocumentId(childUri)
            if (docId.isNullOrEmpty()) return null
            val lastSlash = docId.lastIndexOf('/')
            if (lastSlash <= 0) return null

            val parentDocId = docId.substring(0, lastSlash)
            val treeDocId = android.provider.DocumentsContract.getTreeDocumentId(childUri)
            if (treeDocId.isNullOrEmpty()) return null

            val parentUri = android.provider.DocumentsContract.buildDocumentUriUsingTree(
                childUri, parentDocId
            )
            return DocumentFile.fromTreeUri(this, parentUri)
                ?: DocumentFile.fromSingleUri(this, parentUri)
        } catch (e: Exception) {
            android.util.Log.w("SpotiFLAC", "Failed to get SAF parent dir: ${e.message}")
            return null
        }
    }

    /**
     * Write a ".lrc" sidecar next to a SAF audio document. The sidecar reuses
     * the audio file's base name (e.g. "Song.flac" -> "Song.lrc") and is created
     * in the same parent directory. Used by re-enrich when the user's lyrics
     * mode requests an external/both sidecar. Best-effort: failures are logged
     * and swallowed so they never abort the metadata enrichment itself.
     */
internal fun MainActivity.writeSafSidecarLrc(audioUri: Uri, lrcContent: String): Boolean {
        if (lrcContent.isBlank()) return false
        try {
            val parent = safParentDir(audioUri) ?: run {
                android.util.Log.w("SpotiFLAC", "LRC sidecar: no SAF parent dir")
                return false
            }
            val audioName = try {
                DocumentFile.fromSingleUri(this, audioUri)?.name
            } catch (_: Exception) {
                null
            } ?: return false
            val baseName = audioName.substringBeforeLast('.', audioName)
            val lrcName = "$baseName.lrc"

            val target = SafDownloadHandler.createOrReuseDocumentFile(
                this,
                parent,
                "application/octet-stream",
                lrcName
            ) ?: run {
                android.util.Log.w("SpotiFLAC", "LRC sidecar: failed to create $lrcName")
                return false
            }

            contentResolver.openOutputStream(target.uri, "wt")?.use { output ->
                output.write(lrcContent.toByteArray(Charsets.UTF_8))
            } ?: return false
            android.util.Log.d("SpotiFLAC", "LRC sidecar written: $lrcName")
            return true
        } catch (e: Exception) {
            android.util.Log.w("SpotiFLAC", "LRC sidecar write failed: ${e.message}")
            return false
        }
    }

internal fun MainActivity.runPostProcessingSafV2(fileUriStr: String, metadataJson: String, itemId: String): String {
        val uri = Uri.parse(fileUriStr)
        val doc = DocumentFile.fromSingleUri(this, uri)
            ?: return errorJson("SAF file not found")

        val tempInput = copyUriToTemp(uri) ?: return errorJson("Failed to copy SAF file to temp")
        val inputObj = JSONObject()
        inputObj.put("item_id", itemId)
        inputObj.put("path", tempInput)
        inputObj.put("uri", fileUriStr)
        inputObj.put("name", doc.name ?: File(tempInput).name)
        inputObj.put("mime_type", doc.type ?: contentResolver.getType(uri) ?: "")
        inputObj.put("size", doc.length())
        inputObj.put("is_saf", true)

        val response = coreBackend.runPostProcessing(inputObj.toString(), metadataJson)
        val respObj = JSONObject(response)
        if (!respObj.optBoolean("success", false)) {
            try {
                File(tempInput).delete()
            } catch (_: Exception) {}
            return response
        }

        val newPath = respObj.optString("new_file_path", "")
        val outputPath = if (newPath.isNotBlank()) newPath else tempInput
        val outputFile = File(outputPath)
        if (!outputFile.exists()) {
            try {
                File(tempInput).delete()
            } catch (_: Exception) {}
            respObj.put("success", false)
            respObj.put("error", "postProcess output not found")
            return respObj.toString()
        }

        val newName = outputFile.name
        if (!newName.isNullOrBlank() && doc.name != null && doc.name != newName) {
            try {
                doc.renameTo(newName)
            } catch (_: Exception) {}
        }

        val writeOk = writeUriFromPath(uri, outputFile.absolutePath)
        if (!writeOk) {
            respObj.put("success", false)
            respObj.put("error", "failed to write postProcess output to SAF")
            return respObj.toString()
        }

        try {
            if (outputPath != tempInput) {
                outputFile.delete()
            }
            File(tempInput).delete()
        } catch (_: Exception) {}

        respObj.put("new_file_path", uri.toString())
        respObj.put("file_path", uri.toString())
        return respObj.toString()
    }
