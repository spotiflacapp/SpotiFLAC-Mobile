package com.zarz.spotiflac

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteException
import android.net.Uri
import android.util.Base64
import android.util.Log
import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.FFmpegKitConfig
import com.antonkarpenko.ffmpegkit.FFmpegSession
import com.antonkarpenko.ffmpegkit.FFmpegSessionCompleteCallback
import com.antonkarpenko.ffmpegkit.LogRedirectionStrategy
import com.antonkarpenko.ffmpegkit.ReturnCode
import com.zarz.spotiflac.SafDownloadHandler.mimeTypeForExt
import com.zarz.spotiflac.SafDownloadHandler.normalizeExt
import com.zarz.spotiflac.NativeFinalizationPolicy.applyQualityVariantFilenameLabel
import com.zarz.spotiflac.NativeFinalizationPolicy.displayAudioQuality
import com.zarz.spotiflac.NativeFinalizationPolicy.formatIndexTag
import com.zarz.spotiflac.NativeFinalizationPolicy.isLosslessAudioCodec
import com.zarz.spotiflac.NativeFinalizationPolicy.isLossyAudioCodec
import com.zarz.spotiflac.NativeFinalizationPolicy.normalizeAudioCodec
import com.zarz.spotiflac.NativeFinalizationPolicy.removeQualityVariantStagingLabel
import com.zarz.spotiflac.NativeFinalizationPolicy.resolvePreferredDecryptionExtension
import gobackend.Gobackend
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.util.Locale
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.pow


// Deferred SAF publish helpers for NativeDownloadFinalizer.

internal fun NativeDownloadFinalizer.promoteStagedSafOutputIfNeeded(
    context: Context,
    input: NativeDownloadFinalizer.FinalizeInput,
    state: NativeDownloadFinalizer.FinalizeState,
) {
    if (!state.filePath.startsWith("content://")) return
    if (!input.result.optBoolean("saf_staged_output", false)) return
    val stagedName = input.result.optString("saf_staged_file_name", "").trim()
    if (stagedName.isNotEmpty() && state.fileName != stagedName) return

    val localInput = materializeForFFmpeg(context, input, state)
    try {
        replaceStatePath(context, input, state, localInput, deleteOld = true)
    } finally {
        File(localInput).delete()
    }
}

internal fun NativeDownloadFinalizer.isDeferredSafPublish(input: NativeDownloadFinalizer.FinalizeInput): Boolean {
    return input.request.optBoolean("defer_saf_publish", false) &&
        input.result.optBoolean("saf_deferred_publish", false)
}

internal fun NativeDownloadFinalizer.isDeferredSafRequest(input: NativeDownloadFinalizer.FinalizeInput): Boolean {
    return input.request.optString("storage_mode", "") == "saf" &&
        input.request.optBoolean("defer_saf_publish", false)
}

internal fun NativeDownloadFinalizer.publishDeferredSafOutput(
    context: Context,
    input: NativeDownloadFinalizer.FinalizeInput,
    state: NativeDownloadFinalizer.FinalizeState,
) {
    if (!isDeferredSafPublish(input)) return
    if (state.filePath.startsWith("content://")) return

    val outputFile = File(state.filePath)
    if (!outputFile.exists() || outputFile.length() <= 0L) {
        throw IllegalStateException("deferred SAF output missing or empty")
    }

    val finalName = desiredFileName(input, state, outputFile.extension)
    val treeUri = input.result.optString("saf_tree_uri", "")
        .ifBlank { input.request.optString("saf_tree_uri", "") }
    val relativeDir = input.result.optString("saf_relative_dir", "")
        .ifBlank { input.request.optString("saf_relative_dir", "") }
    val mimeType = mimeTypeForExt(outputFile.extension)
    val preserveQualityVariant = input.request.optBoolean("allow_quality_variant", false)
    val qualityLabel = qualityVariantFilenameLabel(state).orEmpty()
    val collisionOnly = preserveQualityVariant &&
        input.request.optBoolean("quality_variant_collision_only", false)
    val stagingLabel = input.request.optString("quality_variant", "").trim()
    val logicalVariantName = input.request.optString("saf_file_name", "")
        .ifBlank { finalName }
    val cleanName = removeQualityVariantStagingLabel(logicalVariantName, stagingLabel)
    val variantName = if (qualityLabel.isNotEmpty()) {
        applyQualityVariantFilenameLabel(logicalVariantName, stagingLabel, qualityLabel)
    } else {
        finalName
    }

    var alreadyExists = false
    val published = when {
        collisionOnly -> SafDownloadHandler.writeFileToSafCollisionAware(
            context = context,
            treeUriStr = treeUri,
            relativeDir = relativeDir,
            cleanFileName = cleanName,
            variantFileName = variantName,
            mimeType = mimeType,
            srcPath = outputFile.absolutePath,
            preservedSuffix = qualityLabel,
        )
        preserveQualityVariant -> SafDownloadHandler.writeFileToSafUnique(
            context = context,
            treeUriStr = treeUri,
            relativeDir = relativeDir,
            fileName = finalName,
            mimeType = mimeType,
            srcPath = outputFile.absolutePath,
            preservedSuffix = qualityLabel,
        )
        else -> SafDownloadHandler.writeFileToSafIfAbsent(
            context = context,
            treeUriStr = treeUri,
            relativeDir = relativeDir,
            fileName = finalName,
            mimeType = mimeType,
            srcPath = outputFile.absolutePath,
        )?.let { result ->
            alreadyExists = result.alreadyExists
            SafDownloadHandler.UniqueWriteResult(result.uri, result.fileName)
        }
    } ?: throw IllegalStateException("failed to publish deferred SAF output")
    val newUri = published.uri
    val publishedName = published.fileName

    Log.i(TAG, "Published deferred SAF output once: file=$publishedName bytes=${outputFile.length()}")
    outputFile.delete()
    state.filePath = newUri
    state.fileName = publishedName
    input.result.put("file_path", newUri)
    input.result.put("file_name", publishedName)
    if (alreadyExists) {
        input.result.put("already_exists", true)
        input.result.put("message", "File already exists")
        input.result.put("publish_collision_existing", true)
    }
    input.result.optJSONObject("replaygain")?.let { replayGain ->
        replayGain.put("file_path", newUri)
        replayGain.put("file_name", publishedName)
    }
    if (state.pendingExternalLrc != null) {
        state.pendingExternalLrcFileName = "${publishedName.replace(Regex("\\.[^.]+$"), "")}.lrc"
    }
    input.result.put("saf_deferred_published", true)
    publishPendingDeferredExternalLrc(context, input, state)
}

internal fun NativeDownloadFinalizer.publishPendingDeferredExternalLrc(
    context: Context,
    input: NativeDownloadFinalizer.FinalizeInput,
    state: NativeDownloadFinalizer.FinalizeState,
) {
    val lrc = state.pendingExternalLrc ?: return
    val fileName = state.pendingExternalLrcFileName ?: return
    val treeUri = input.result.optString("saf_tree_uri", "")
        .ifBlank { input.request.optString("saf_tree_uri", "") }
    val relativeDir = input.result.optString("saf_relative_dir", "")
        .ifBlank { input.request.optString("saf_relative_dir", "") }
    val temp = File(context.cacheDir, "native_lrc_${System.nanoTime()}.lrc")
    try {
        temp.writeText(lrc)
        val newUri = SafDownloadHandler.writeFileToSaf(
            context = context,
            treeUriStr = treeUri,
            relativeDir = relativeDir,
            fileName = fileName,
            mimeType = "application/octet-stream",
            srcPath = temp.absolutePath,
        )
        if (newUri == null) {
            Log.w(TAG, "Failed to publish deferred external LRC: $fileName")
        }
    } catch (e: Exception) {
        Log.w(TAG, "Failed to publish deferred external LRC: ${e.message}")
    } finally {
        temp.delete()
        state.pendingExternalLrc = null
        state.pendingExternalLrcFileName = null
    }
}
