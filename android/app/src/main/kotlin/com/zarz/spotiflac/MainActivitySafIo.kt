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

internal fun MainActivity.copyUriToTemp(uri: Uri, fallbackExt: String? = null): String? {
        var tempFile: File? = null
        var success = false

        try {
            val mime = try { contentResolver.getType(uri) } catch (_: Exception) { null }
            val nameHint = (
                try { DocumentFile.fromSingleUri(this, uri)?.name } catch (_: Exception) { null }
                    ?: uri.lastPathSegment
                    ?: ""
            ).lowercase(Locale.ROOT)
            val extFromName = extFromFileName(nameHint)
            val extFromMime = extFromMimeType(mime)
            val ext = if (extFromName.isNotBlank()) extFromName else if (extFromMime.isNotBlank()) extFromMime else (fallbackExt ?: "")
            val suffix: String? = if (ext.isNotBlank()) ext else null
            tempFile = File.createTempFile("saf_", suffix, cacheDir)

            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
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
                    success = true
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
            val suffix: String? = if (ext.isNotBlank()) ext else null
            tempFile = File.createTempFile("ms_", suffix, cacheDir)

            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
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

internal fun MainActivity.readAudioMetadataFromUri(
        uri: Uri,
        displayNameHint: String? = null,
        fallbackExt: String? = null,
        coverCacheKey: String = "",
    ): JSONObject? {
        val displayName = buildUriDisplayName(uri, displayNameHint, fallbackExt)

        // Skip /proc/self/fd/ attempt when known to fail (e.g. Samsung SELinux).
        if (procSelfFdReadable != false) {
            try {
                contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                    val directPath = "/proc/self/fd/${pfd.fd}"
                    val metadataJson = Gobackend.readAudioMetadataWithHintAndCoverCacheKeyJSON(
                        directPath,
                        displayName,
                        coverCacheKey,
                    )
                    if (metadataJson.isNotBlank()) {
                        val obj = JSONObject(metadataJson)
                        val filenameFallback = obj.optBoolean("metadataFromFilename", false)
                        if (!obj.has("error") && !filenameFallback) {
                            procSelfFdReadable = true
                            return obj
                        }
                        // Go could not read real metadata from the fd path –
                        // remember so we skip the attempt for remaining files.
                        if (procSelfFdReadable == null) {
                            procSelfFdReadable = false
                            android.util.Log.d(
                                "SpotiFLAC",
                                "Direct /proc/self/fd read not usable on this device, " +
                                    "using temp-file fallback for remaining files",
                            )
                        }
                    }
                }
            } catch (e: Exception) {
                if (procSelfFdReadable == null) {
                    procSelfFdReadable = false
                    android.util.Log.d(
                        "SpotiFLAC",
                        "Direct /proc/self/fd read not usable on this device, " +
                            "using temp-file fallback for remaining files",
                    )
                }
            }
        }

        val tempPath = try {
            copyUriToTemp(uri, fallbackExt)
        } catch (e: Exception) {
            android.util.Log.w(
                "SpotiFLAC",
                "SAF metadata fallback copy failed for $uri: ${e.message}",
            )
            null
        } ?: return null

        try {
            val metadataJson = Gobackend.readAudioMetadataWithHintAndCoverCacheKeyJSON(
                tempPath,
                displayName,
                coverCacheKey,
            )
            if (metadataJson.isBlank()) return null
            val obj = JSONObject(metadataJson)
            return if (obj.has("error")) null else obj
        } catch (e: Exception) {
            android.util.Log.w(
                "SpotiFLAC",
                "SAF metadata temp read failed for $uri: ${e.message}",
            )
            return null
        } finally {
            try {
                File(tempPath).delete()
            } catch (_: Exception) {}
        }
    }

internal fun MainActivity.writeUriFromPath(uri: Uri, srcPath: String): Boolean {
        val srcFile = File(srcPath)
        if (!srcFile.exists()) return false
        contentResolver.openOutputStream(uri, "wt")?.use { output ->
            FileInputStream(srcFile).use { input ->
                input.copyTo(output)
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

internal fun MainActivity.runPostProcessingSafV2(fileUriStr: String, metadataJson: String): String {
        val uri = Uri.parse(fileUriStr)
        val doc = DocumentFile.fromSingleUri(this, uri)
            ?: return errorJson("SAF file not found")

        val tempInput = copyUriToTemp(uri) ?: return errorJson("Failed to copy SAF file to temp")
        val tempDir = File(tempInput).parentFile?.absolutePath ?: ""
        if (tempDir.isNotBlank()) {
            try {
                Gobackend.allowDownloadDir(tempDir)
            } catch (_: Exception) {}
        }

        val inputObj = JSONObject()
        inputObj.put("path", tempInput)
        inputObj.put("uri", fileUriStr)
        inputObj.put("name", doc.name ?: File(tempInput).name)
        inputObj.put("mime_type", doc.type ?: contentResolver.getType(uri) ?: "")
        inputObj.put("size", doc.length())
        inputObj.put("is_saf", true)

        val response = Gobackend.runPostProcessingV2JSON(inputObj.toString(), metadataJson)
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
