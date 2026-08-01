package com.zarz.spotiflac

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.util.Locale

/**
 * Shared SAF download wrapper for foreground activity calls and service-owned
 * native workers.
 */
object SafDownloadHandler {
    private val safDirLock = Any()
    private const val MAX_SAF_DISPLAY_NAME_UTF8_BYTES = 180
    private const val STAGED_SAF_MIME_TYPE = "application/octet-stream"

    // Serializes the exists-check/create/write/publish sequence per target
    // file so concurrent downloads that sanitize to the same display name
    // cannot interleave writes into one document. Different names keep
    // downloading in parallel; the second same-name caller blocks, then hits
    // the exists check and reports already_exists.
    private val safNameLocks = java.util.concurrent.ConcurrentHashMap<String, Any>()

    data class UniqueWriteResult(val uri: String, val fileName: String)
    data class ExistingAwareWriteResult(
        val uri: String,
        val fileName: String,
        val alreadyExists: Boolean,
    )

    private fun <T> withSafNameLock(
        treeUriStr: String,
        relativeDir: String,
        fileName: String,
        block: () -> T
    ): T {
        val key = "$treeUriStr|$relativeDir|${fileName.lowercase(Locale.ROOT)}"
        val lock = safNameLocks.computeIfAbsent(key) { Any() }
        return synchronized(lock) { block() }
    }

    /**
     * Flushes and fsyncs a SAF output stream so the copied bytes are durable
     * before the staged document is renamed to its final name; without this a
     * power loss right after the rename can leave a truncated "complete" file.
     */
    fun syncOutputStream(output: OutputStream) {
        try {
            output.flush()
            (output as? FileOutputStream)?.fd?.sync()
        } catch (_: Exception) {
        }
    }

    fun handle(context: Context, requestJson: String, downloader: (String) -> String): String {
        val req = JSONObject(requestJson)
        val storageMode = req.optString("storage_mode", "")
        val treeUriStr = req.optString("saf_tree_uri", "")
        if (storageMode != "saf" || treeUriStr.isBlank()) {
            return downloader(requestJson)
        }

        val relativeDir = sanitizeRelativeDir(req.optString("saf_relative_dir", ""))
        val outputExt = normalizeExt(req.optString("saf_output_ext", ""))
        val fileName = buildSafFileName(req, outputExt)
        return withSafNameLock(treeUriStr, relativeDir, fileName) {
            handleSafLocked(context, req, downloader, treeUriStr, relativeDir, outputExt, fileName)
        }
    }

    private fun handleSafLocked(
        context: Context,
        req: JSONObject,
        downloader: (String) -> String,
        treeUriStr: String,
        relativeDir: String,
        outputExt: String,
        fileName: String
    ): String {
        val treeUri = Uri.parse(treeUriStr)
        val mimeType = mimeTypeForExt(outputExt)
        val deferSafPublish = req.optBoolean("defer_saf_publish", false)
        // Downloads are always written under a staged ".partial" name so a
        // killed process can never leave a half-written file under the final
        // name (which the exists check would then accept as complete forever).
        // Callers that set stage_saf_output own the promotion to the final
        // name (the native finalizer); for everyone else — the foreground
        // Dart queue — this handler promotes right after a successful write.
        val finalizerPromotesStaged = req.optBoolean("stage_saf_output", false) && !deferSafPublish
        val useStagedOutput = !deferSafPublish
        val stagedFileName = if (useStagedOutput) buildStagedSafFileName(fileName) else fileName
        val stagedMimeType = if (useStagedOutput) STAGED_SAF_MIME_TYPE else mimeType

        val existingDir = findDocumentDir(context, treeUri, relativeDir)
        if (existingDir != null) {
            val existing = existingDir.findFile(fileName)
            if (existing != null && existing.isFile && existing.length() > 0) {
                deleteStaleStagedFiles(existingDir, fileName, outputExt)
                val obj = JSONObject()
                obj.put("success", true)
                obj.put("message", "File already exists")
                obj.put("file_path", existing.uri.toString())
                obj.put("file_name", existing.name ?: fileName)
                obj.put("already_exists", true)
                return obj.toString()
            }
        }

        val targetDir = ensureDocumentDir(context, treeUri, relativeDir)
            ?: return errorJson("Failed to access SAF directory")

        if (deferSafPublish) {
            deleteStaleStagedFiles(targetDir, fileName, outputExt)
            val workingExt = outputExt.ifBlank { ".tmp" }
            val workingFile = File.createTempFile("native_saf_work_", workingExt, context.cacheDir)
            Log.i("SpotiFLAC", "SAF deferred native output: target=$fileName working=${workingFile.name}")
            return try {
                req.put("output_path", workingFile.absolutePath)
                req.put("output_ext", outputExt)
                req.remove("output_fd")
                val response = downloader(req.toString())
                val respObj = JSONObject(response)
                if (respObj.optBoolean("success", false)) {
                    val reportedPath = respObj.optString("file_path", "").trim()
                    if (reportedPath.isEmpty() || reportedPath.startsWith("/proc/self/fd/")) {
                        respObj.put("file_path", workingFile.absolutePath)
                    } else if (reportedPath != workingFile.absolutePath) {
                        workingFile.delete()
                    }
                    respObj.put("file_name", respObj.optString("file_name", "").ifBlank { fileName })
                    respObj.put("saf_deferred_publish", true)
                    respObj.put("saf_final_file_name", fileName)
                    respObj.put("saf_relative_dir", relativeDir)
                    respObj.put("saf_tree_uri", treeUriStr)
                    respObj.put("saf_output_ext", outputExt)
                    respObj.put("saf_final_mime_type", mimeType)
                } else {
                    workingFile.delete()
                }
                respObj.toString()
            } catch (e: Exception) {
                workingFile.delete()
                errorJson("SAF deferred download failed: ${e.message}")
            }
        }

        // Remove any stale partial from a previous killed attempt before
        // creating the staged document: reusing it would let a shorter new
        // write leave the old tail bytes in place (fd truncation is
        // best-effort on some providers).
        deleteStaleStagedFiles(targetDir, fileName, outputExt)
        var document = createOrReuseDocumentFile(targetDir, stagedMimeType, stagedFileName)
            ?: return errorJson("Failed to create SAF file")

        val pfd = context.contentResolver.openFileDescriptor(document.uri, "rw")
            ?: return errorJson("Failed to open SAF file")

        var detachedFd: Int? = null
        try {
            detachedFd = pfd.detachFd()
            req.put("output_path", "")
            req.put("output_fd", detachedFd)
            req.put("output_ext", outputExt)
            val response = downloader(req.toString())
            val respObj = JSONObject(response)
            if (respObj.optBoolean("success", false)) {
                var finalFileName = fileName
                val goFilePath = respObj.optString("file_path", "")
                if (goFilePath.isNotEmpty() &&
                    !goFilePath.startsWith("content://") &&
                    !goFilePath.startsWith("/proc/self/fd/")
                ) {
                    try {
                        val srcFile = File(goFilePath)
                        if (!srcFile.exists() || srcFile.length() <= 0) {
                            throw IllegalStateException("extension output missing or empty: $goFilePath")
                        }
                        val actualExt = normalizeExt(srcFile.extension)
                        if (actualExt.isNotBlank()) {
                            respObj.put("actual_extension", actualExt)
                        }
                        if (actualExt.isNotBlank() && actualExt != outputExt) {
                            val actualFileName = buildSafFileName(req, actualExt)
                            val actualStagedFileName = if (useStagedOutput) {
                                buildStagedSafFileName(actualFileName)
                            } else {
                                actualFileName
                            }
                            val actualMimeType = mimeTypeForExt(actualExt)
                            val replacement = createOrReuseDocumentFile(
                                targetDir,
                                if (useStagedOutput) STAGED_SAF_MIME_TYPE else actualMimeType,
                                actualStagedFileName
                            ) ?: throw IllegalStateException(
                                "failed to create SAF output with actual extension"
                            )
                            if (replacement.uri != document.uri) {
                                document.delete()
                                document = replacement
                            }
                            finalFileName = actualFileName
                        }
                        context.contentResolver.openOutputStream(document.uri, "wt")?.use { output ->
                            srcFile.inputStream().use { input ->
                                input.copyTo(output)
                            }
                            syncOutputStream(output)
                        } ?: throw IllegalStateException("failed to open SAF output stream")
                        srcFile.delete()
                    } catch (e: Exception) {
                        document.delete()
                        android.util.Log.w(
                            "SpotiFLAC",
                            "Failed to copy extension output to SAF: ${e.message}"
                        )
                        return errorJson("Failed to copy extension output to SAF: ${e.message}")
                    }
                }
                respObj.put("file_path", document.uri.toString())
                respObj.put("file_name", document.name ?: fileName)
                if (finalizerPromotesStaged) {
                    respObj.put("saf_staged_output", true)
                    respObj.put("saf_staged_file_name", document.name ?: stagedFileName)
                } else if (useStagedOutput) {
                    // Legacy caller (foreground Dart queue): publish here by
                    // renaming the staged file to its final name.
                    val published = replaceFinalDocument(targetDir, document, finalFileName)
                    if (published == null) {
                        document.delete()
                        return errorJson("Failed to publish SAF download")
                    }
                    respObj.put("file_path", published.uri.toString())
                    respObj.put("file_name", published.name ?: finalFileName)
                }
            } else {
                document.delete()
            }
            return respObj.toString()
        } catch (e: Exception) {
            document.delete()
            return errorJson("SAF download failed: ${e.message}")
        } finally {
            if (detachedFd == null) {
                try {
                    pfd.close()
                } catch (_: Exception) {
                }
            }
        }
    }

    /**
     * Swaps [document] into place under [finalName] without a window where the
     * previous file is gone but the new one is not yet in place. Any existing
     * file is renamed aside first and only deleted once the staged file holds
     * the final name; a failed swap restores it. Returns the published
     * document, or null when the swap failed (the caller owns [document]).
     */
    private fun replaceFinalDocument(
        targetDir: DocumentFile,
        document: DocumentFile,
        finalName: String
    ): DocumentFile? {
        val existingFinal = targetDir.findFile(finalName)
        var aside: DocumentFile? = null
        if (existingFinal != null && existingFinal.uri != document.uri) {
            val asideName = buildReplacedSafFileName(finalName)
            try {
                targetDir.findFile(asideName)?.delete()
            } catch (_: Exception) {
            }
            if (!existingFinal.renameTo(asideName)) {
                return null
            }
            aside = targetDir.findFile(asideName) ?: existingFinal
        }
        if (!document.renameTo(finalName)) {
            aside?.renameTo(finalName)
            return null
        }
        aside?.delete()
        return targetDir.findFile(finalName) ?: document
    }

    private fun buildReplacedSafFileName(fileName: String): String {
        return "${sanitizeFilename(fileName)}.replaced"
    }

    fun copyContentUriToTemp(context: Context, uriStr: String): String? {
        return try {
            val uri = Uri.parse(uriStr)
            val extension = DocumentFile.fromSingleUri(context, uri)
                ?.name
                ?.substringAfterLast('.', "")
                ?.takeIf { it.isNotBlank() }
                ?.let { ".$it" }
                ?: ".tmp"
            val temp = File.createTempFile("native_saf_", extension, context.cacheDir)
            context.contentResolver.openInputStream(uri)?.use { input ->
                temp.outputStream().use { output ->
                    input.copyTo(output)
                }
            } ?: return null
            temp.absolutePath
        } catch (e: Exception) {
            android.util.Log.w("SpotiFLAC", "Failed to copy SAF URI to temp: ${e.message}")
            null
        }
    }

    fun writeFileToSaf(
        context: Context,
        treeUriStr: String,
        relativeDir: String,
        fileName: String,
        mimeType: String,
        srcPath: String
    ): String? {
        val finalName = sanitizeFilename(fileName)
        return withSafNameLock(treeUriStr, sanitizeRelativeDir(relativeDir), finalName) {
            writeFileToSafLocked(context, treeUriStr, relativeDir, finalName, srcPath)
        }
    }

    fun writeFileToSafUnique(
        context: Context,
        treeUriStr: String,
        relativeDir: String,
        fileName: String,
        mimeType: String,
        srcPath: String,
        preservedSuffix: String = "",
    ): UniqueWriteResult? {
        val safeRelativeDir = sanitizeRelativeDir(relativeDir)
        val preferredName = sanitizeFilenamePreservingSuffix(fileName, preservedSuffix)
        return withSafNameLock(treeUriStr, safeRelativeDir, preferredName) {
            val treeUri = Uri.parse(treeUriStr)
            val targetDir = ensureDocumentDir(context, treeUri, safeRelativeDir) ?: return@withSafNameLock null
            val availableName = findAvailableFileName(
                targetDir,
                preferredName,
                preservedSuffix,
            )
            val uri = writeFileToSafLocked(
                context,
                treeUriStr,
                safeRelativeDir,
                availableName,
                srcPath,
            ) ?: return@withSafNameLock null
            UniqueWriteResult(uri = uri, fileName = availableName)
        }
    }

    fun writeFileToSafCollisionAware(
        context: Context,
        treeUriStr: String,
        relativeDir: String,
        cleanFileName: String,
        variantFileName: String,
        mimeType: String,
        srcPath: String,
        preservedSuffix: String = "",
    ): UniqueWriteResult? {
        val safeRelativeDir = sanitizeRelativeDir(relativeDir)
        val cleanName = sanitizeFilename(cleanFileName)
        val preferredVariant = sanitizeFilenamePreservingSuffix(
            variantFileName,
            preservedSuffix,
        )
        return withSafNameLock(treeUriStr, safeRelativeDir, cleanName) {
            val treeUri = Uri.parse(treeUriStr)
            val targetDir = ensureDocumentDir(context, treeUri, safeRelativeDir)
                ?: return@withSafNameLock null
            val selectedName = if (targetDir.findFile(cleanName) == null) {
                cleanName
            } else {
                findAvailableFileName(targetDir, preferredVariant, preservedSuffix)
            }
            val uri = writeFileToSafLocked(
                context,
                treeUriStr,
                safeRelativeDir,
                selectedName,
                srcPath,
            ) ?: return@withSafNameLock null
            UniqueWriteResult(uri = uri, fileName = selectedName)
        }
    }

    fun writeFileToSafIfAbsent(
        context: Context,
        treeUriStr: String,
        relativeDir: String,
        fileName: String,
        mimeType: String,
        srcPath: String,
    ): ExistingAwareWriteResult? {
        val safeRelativeDir = sanitizeRelativeDir(relativeDir)
        val finalName = sanitizeFilename(fileName)
        return withSafNameLock(treeUriStr, safeRelativeDir, finalName) {
            val treeUri = Uri.parse(treeUriStr)
            val targetDir = ensureDocumentDir(context, treeUri, safeRelativeDir)
                ?: return@withSafNameLock null
            val existing = targetDir.findFile(finalName)
            if (existing != null && existing.isFile && existing.length() > 0L) {
                return@withSafNameLock ExistingAwareWriteResult(
                    uri = existing.uri.toString(),
                    fileName = existing.name ?: finalName,
                    alreadyExists = true,
                )
            }
            val uri = writeFileToSafLocked(
                context,
                treeUriStr,
                safeRelativeDir,
                finalName,
                srcPath,
            ) ?: return@withSafNameLock null
            ExistingAwareWriteResult(
                uri = uri,
                fileName = finalName,
                alreadyExists = false,
            )
        }
    }

    private fun sanitizeFilenamePreservingSuffix(fileName: String, suffix: String): String {
        val sanitized = sanitizeFilename(fileName)
        val trimmedSuffix = suffix.trim()
        if (trimmedSuffix.isEmpty() || sanitized.contains(trimmedSuffix)) return sanitized

        val dotIndex = fileName.lastIndexOf('.')
        val hasExtension = dotIndex > 0 && dotIndex < fileName.length - 1
        val extension = if (hasExtension) fileName.substring(dotIndex) else ""
        val rawStem = if (hasExtension) fileName.substring(0, dotIndex) else fileName
        val rawPrefix = rawStem.replace(trimmedSuffix, "").trim(' ', '_', '-')
        val safeSuffix = sanitizeFilename(trimmedSuffix)
        val reserved = " - $safeSuffix$extension"
        val prefixBytes = (MAX_SAF_DISPLAY_NAME_UTF8_BYTES - reserved.toByteArray(Charsets.UTF_8).size)
            .coerceAtLeast(1)
        val safePrefix = truncateUtf8Bytes(sanitizeFilename(rawPrefix), prefixBytes)
            .trim()
            .trim('.', ' ', '_', '-')
            .ifBlank { "track" }
        return "$safePrefix$reserved"
    }

    private fun findAvailableFileName(
        parent: DocumentFile,
        preferredName: String,
        preservedSuffix: String,
    ): String {
        if (parent.findFile(preferredName) == null) return preferredName
        for (counter in 2..9999) {
            val candidate = appendFilenameCounter(
                preferredName,
                counter.toLong(),
                preservedSuffix,
            )
            if (parent.findFile(candidate) == null) return candidate
        }
        return appendFilenameCounter(
            preferredName,
            System.currentTimeMillis(),
            preservedSuffix,
        )
    }

    private fun appendFilenameCounter(
        fileName: String,
        counter: Long,
        preservedSuffix: String,
    ): String {
        val dotIndex = fileName.lastIndexOf('.')
        val hasExtension = dotIndex > 0 && dotIndex < fileName.length - 1
        val extension = if (hasExtension) fileName.substring(dotIndex) else ""
        val originalStem = if (hasExtension) fileName.substring(0, dotIndex) else fileName
        val safePreservedSuffix = preservedSuffix.trim()
        val hasPreservedSuffix = safePreservedSuffix.isNotEmpty() && originalStem.contains(safePreservedSuffix)
        val stem = if (hasPreservedSuffix) {
            originalStem.replace(safePreservedSuffix, "").trim(' ', '_', '-')
        } else {
            originalStem
        }
        val suffix = if (hasPreservedSuffix) {
            " - $safePreservedSuffix ($counter)"
        } else {
            " ($counter)"
        }
        val reservedBytes = extension.toByteArray(Charsets.UTF_8).size +
            suffix.toByteArray(Charsets.UTF_8).size
        val maxStemBytes = (MAX_SAF_DISPLAY_NAME_UTF8_BYTES - reservedBytes).coerceAtLeast(1)
        val safeStem = truncateUtf8Bytes(stem, maxStemBytes).trim().trim('.', ' ').ifBlank { "track" }
        return "$safeStem$suffix$extension"
    }

    private fun writeFileToSafLocked(
        context: Context,
        treeUriStr: String,
        relativeDir: String,
        finalName: String,
        srcPath: String
    ): String? {
        var stagedDocument: DocumentFile? = null
        return try {
            val treeUri = Uri.parse(treeUriStr)
            val targetDir = ensureDocumentDir(context, treeUri, relativeDir) ?: return null
            val ext = normalizeExt(finalName.substringAfterLast('.', ""))
            val stagedName = buildStagedSafFileName(finalName)
            deleteStaleStagedFiles(targetDir, finalName, ext)
            val document = createOrReuseDocumentFile(targetDir, STAGED_SAF_MIME_TYPE, stagedName)
                ?: return null
            stagedDocument = document
            val outputStream = context.contentResolver.openOutputStream(document.uri, "wt")
            if (outputStream == null) {
                document.delete()
                stagedDocument = null
                return null
            }
            outputStream.use { output ->
                File(srcPath).inputStream().use { input ->
                    input.copyTo(output)
                }
                syncOutputStream(output)
            }

            val published = replaceFinalDocument(targetDir, document, finalName)
            if (published == null) {
                document.delete()
                return null
            }
            stagedDocument = null
            published.uri.toString()
        } catch (e: Exception) {
            stagedDocument?.delete()
            android.util.Log.w("SpotiFLAC", "Failed to write file to SAF: ${e.message}")
            null
        }
    }

    fun deleteContentUri(context: Context, uriStr: String): Boolean {
        return try {
            DocumentFile.fromSingleUri(context, Uri.parse(uriStr))?.delete() == true
        } catch (_: Exception) {
            false
        }
    }

    internal fun normalizeExt(ext: String?): String {
        val trimmed = ext?.trim().orEmpty()
        if (trimmed.isEmpty()) return ""
        return if (trimmed.startsWith(".")) trimmed.lowercase(Locale.ROOT) else ".${trimmed.lowercase(Locale.ROOT)}"
    }

    internal fun mimeTypeForExt(ext: String?): String {
        return when (normalizeExt(ext)) {
            ".m4a", ".mp4" -> "audio/mp4"
            ".mp3" -> "audio/mpeg"
            ".opus", ".ogg" -> "audio/ogg"
            ".flac" -> "audio/flac"
            ".wav" -> "audio/wav"
            ".aiff", ".aif", ".aifc" -> "audio/aiff"
            ".lrc" -> "application/octet-stream"
            else -> "application/octet-stream"
        }
    }

    private fun forceFilenameExt(name: String, outputExt: String): String {
        val normalizedExt = normalizeExt(outputExt)
        if (normalizedExt.isBlank()) return sanitizeFilename(name)

        val safeName = sanitizeFilename(name)
        val lower = safeName.lowercase(Locale.ROOT)
        val knownExts = listOf(".flac", ".m4a", ".mp4", ".mp3", ".opus", ".lrc")
        for (knownExt in knownExts) {
            if (lower.endsWith(knownExt)) {
                return safeName.dropLast(knownExt.length) + normalizedExt
            }
        }
        return safeName + normalizedExt
    }

    private fun buildStagedSafFileName(fileName: String): String {
        val safeName = sanitizeFilename(fileName)
        return "$safeName.partial"
    }

    private fun buildLegacyStagedSafFileName(fileName: String, outputExt: String): String {
        val safeName = sanitizeFilename(fileName)
        val ext = normalizeExt(outputExt)
        if (ext.isNotBlank() && safeName.lowercase(Locale.ROOT).endsWith(ext)) {
            return safeName.dropLast(ext.length).trimEnd('.', ' ') + ".partial$ext"
        }
        val dot = safeName.lastIndexOf('.')
        if (dot > 0 && dot < safeName.lastIndex) {
            return safeName.substring(0, dot).trimEnd('.', ' ') +
                ".partial" +
                safeName.substring(dot)
        }
        return "$safeName.partial"
    }

    private fun deleteStaleStagedFiles(parent: DocumentFile, fileName: String, outputExt: String) {
        val stagedNames = linkedSetOf(
            buildStagedSafFileName(fileName),
            buildLegacyStagedSafFileName(fileName, outputExt),
            buildReplacedSafFileName(fileName)
        )
        for (stagedName in stagedNames) {
            try {
                parent.findFile(stagedName)?.delete()
            } catch (_: Exception) {
            }
        }
    }

    internal fun sanitizeFilename(name: String): String {
        var sanitized = name
            .replace("/", " ")
            .replace(Regex("[\\\\:*?\"<>|]"), " ")
            .filter { ch ->
                val code = ch.code
                !((code < 0x20 && ch != '\t' && ch != '\n' && ch != '\r') ||
                    code == 0x7F ||
                    (Character.isISOControl(ch) && ch != '\t' && ch != '\n' && ch != '\r'))
            }
            .trim()
            .trim('.', ' ')

        sanitized = sanitized
            .replace(Regex("\\s+"), " ")
            .replace(Regex("_+"), "_")
            .trim('_', ' ')

        sanitized = truncateSafDisplayName(sanitized, MAX_SAF_DISPLAY_NAME_UTF8_BYTES)
        sanitized = sanitized.trim().trim('.', ' ').trim('_', ' ')
        return if (sanitized.isBlank()) "Unknown" else sanitized
    }

    private fun truncateSafDisplayName(name: String, maxBytes: Int): String {
        if (maxBytes <= 0 || name.toByteArray(Charsets.UTF_8).size <= maxBytes) return name

        val dotIndex = name.lastIndexOf('.')
        val ext = if (
            dotIndex > 0 &&
            dotIndex < name.length - 1 &&
            name.length - dotIndex <= 10
        ) {
            name.substring(dotIndex)
        } else {
            ""
        }
        val stem = if (ext.isNotEmpty()) name.substring(0, dotIndex) else name
        val maxStemBytes = (maxBytes - ext.toByteArray(Charsets.UTF_8).size).coerceAtLeast(1)
        return truncateUtf8Bytes(stem, maxStemBytes).trim().trim('.', ' ').trim('_', ' ') + ext
    }

    private fun truncateUtf8Bytes(value: String, maxBytes: Int): String {
        if (maxBytes <= 0 || value.toByteArray(Charsets.UTF_8).size <= maxBytes) return value

        val builder = StringBuilder()
        var usedBytes = 0
        var index = 0
        while (index < value.length) {
            val codePoint = value.codePointAt(index)
            val char = String(Character.toChars(codePoint))
            val charBytes = char.toByteArray(Charsets.UTF_8).size
            if (usedBytes + charBytes > maxBytes) break
            builder.append(char)
            usedBytes += charBytes
            index += Character.charCount(codePoint)
        }
        return builder.toString()
    }

    internal fun sanitizeRelativeDir(relativeDir: String): String {
        if (relativeDir.isBlank()) return ""
        return relativeDir
            .split("/")
            .map { sanitizeFilename(it) }
            .filter { it.isNotBlank() && it != "." && it != ".." }
            .joinToString("/")
    }

    internal fun ensureDocumentDir(
        context: Context,
        treeUri: Uri,
        relativeDir: String
    ): DocumentFile? {
        val safeRelativeDir = sanitizeRelativeDir(relativeDir)
        if (safeRelativeDir.isBlank()) {
            return DocumentFile.fromTreeUri(context, treeUri)
        }

        synchronized(safDirLock) {
            var current = DocumentFile.fromTreeUri(context, treeUri) ?: return null
            val parts = safeRelativeDir.split("/").filter { it.isNotBlank() }
            for (part in parts) {
                val existing = current.findFile(part)
                current = if (existing != null && existing.isDirectory) {
                    existing
                } else {
                    val created = current.createDirectory(part) ?: return null
                    val createdName = created.name ?: part
                    if (createdName != part) {
                        created.delete()
                        current.findFile(part) ?: return null
                    } else {
                        created
                    }
                }
            }
            return current
        }
    }

    internal fun findDocumentDir(
        context: Context,
        treeUri: Uri,
        relativeDir: String
    ): DocumentFile? {
        var current = DocumentFile.fromTreeUri(context, treeUri) ?: return null
        val safeRelativeDir = sanitizeRelativeDir(relativeDir)
        if (safeRelativeDir.isBlank()) return current

        val parts = safeRelativeDir.split("/").filter { it.isNotBlank() }
        for (part in parts) {
            val existing = current.findFile(part)
            if (existing == null || !existing.isDirectory) return null
            current = existing
        }
        return current
    }

    internal fun createOrReuseDocumentFile(
        parent: DocumentFile,
        mimeType: String,
        fileName: String
    ): DocumentFile? {
        val safeFileName = sanitizeFilename(fileName)
        if (safeFileName.isBlank()) return null

        synchronized(safDirLock) {
            val existing = parent.findFile(safeFileName)
            if (existing != null && existing.isFile) {
                return existing
            }

            val created = parent.createFile(mimeType, safeFileName) ?: return null
            val createdName = created.name ?: safeFileName
            if (createdName == safeFileName) {
                return created
            }

            val winner = parent.findFile(safeFileName)
            if (winner != null && winner.isFile) {
                if (winner.uri != created.uri) {
                    try {
                        created.delete()
                    } catch (_: Exception) {
                    }
                }
                return winner
            }

            return created
        }
    }

    private fun buildSafFileName(req: JSONObject, outputExt: String): String {
        val provided = req.optString("saf_file_name", "")
        if (provided.isNotBlank()) return forceFilenameExt(provided, outputExt)

        val trackName = req.optString("track_name", "track")
        val artistName = req.optString("artist_name", "")
        val baseName = if (artistName.isNotBlank()) "$artistName - $trackName" else trackName
        return forceFilenameExt(baseName, outputExt)
    }

    private fun errorJson(message: String): String {
        val obj = JSONObject()
        obj.put("success", false)
        obj.put("error", message)
        obj.put("message", message)
        return obj.toString()
    }
}
