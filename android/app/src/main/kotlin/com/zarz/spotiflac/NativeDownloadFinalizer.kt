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

object NativeDownloadFinalizer {
    internal const val TAG = "NativeFinalizer"
    const val NATIVE_WORKER_CONTRACT_VERSION = 1
    // Native finalizer owns background-safe history writes while Flutter may be suspended.
    // Keep this schema contract in sync with Dart HistoryDatabase before bumping either side.
    const val HISTORY_SCHEMA_VERSION = 10
    internal val activeFFmpegSessionIds = mutableSetOf<Long>()
    internal val nativeFFmpegSessionIds = mutableSetOf<Long>()
    internal val activeFFmpegSessionLock = Any()
    internal val ffmpegCompleteCallbackLock = Any()
    internal val qualityVariantNameLocks = java.util.concurrent.ConcurrentHashMap<String, Any>()
    internal var forwardedFFmpegCompleteCallback: FFmpegSessionCompleteCallback? = null
    internal val nativeFilteringFFmpegCompleteCallback = FFmpegSessionCompleteCallback { session ->
        val isNativeSession = synchronized(activeFFmpegSessionLock) {
            nativeFFmpegSessionIds.contains(session.sessionId)
        }
        if (!isNativeSession) {
            val delegate = synchronized(ffmpegCompleteCallbackLock) {
                forwardedFFmpegCompleteCallback
            }
            delegate?.apply(session)
        }
    }
    private val requiredHistoryColumns = setOf(
        "id",
        "track_name",
        "artist_name",
        "album_name",
        "album_artist",
        "cover_url",
        "file_path",
        "storage_mode",
        "download_tree_uri",
        "saf_relative_dir",
        "saf_file_name",
        "saf_repaired",
        "service",
        "downloaded_at",
        "isrc",
        "spotify_id",
        "track_number",
        "total_tracks",
        "disc_number",
        "total_discs",
        "duration",
        "release_date",
        "quality",
        "bit_depth",
        "sample_rate",
        "bitrate",
        "format",
        "genre",
        "composer",
        "label",
        "copyright",
        "spotify_id_norm",
        "isrc_norm",
        "match_key",
        "album_key",
        "search_text",
    )
    private val androidStoragePathAliases = listOf(
        "/storage/emulated/0",
        "/storage/emulated/legacy",
        "/storage/self/primary",
        "/sdcard",
        "/mnt/sdcard",
    )
    private val audioExtensions = listOf(
        ".flac",
        ".m4a",
        ".mp3",
        ".opus",
        ".ogg",
        ".wav",
        ".aac",
        ".mp4",
    )

    internal data class FinalizeInput(
        val itemId: String,
        val request: JSONObject,
        val item: JSONObject,
        val track: JSONObject,
        val result: JSONObject,
    )

    internal data class FinalizeState(
        var filePath: String,
        var fileName: String,
        var quality: String,
        var bitDepth: Int?,
        var sampleRate: Int?,
        var bitrateKbps: Int? = null,
        var audioCodec: String? = null,
        var pendingExternalLrc: String? = null,
        var pendingExternalLrcFileName: String? = null,
    )

    internal data class ReplayGainScan(
        val trackGain: String,
        val trackPeak: String,
        val integratedLufs: Double,
        val truePeakLinear: Double,
    )

    fun cancelActiveWork() {
        val sessionIds = synchronized(activeFFmpegSessionLock) {
            activeFFmpegSessionIds.toList()
        }
        for (sessionId in sessionIds) {
            try {
                FFmpegKit.cancel(sessionId)
            } catch (_: Exception) {
            }
        }
    }

    fun finalize(
        context: Context,
        itemId: String,
        requestJson: String,
        itemJson: String,
        result: JSONObject,
        settingsJson: String = "{}",
        shouldCancel: () -> Boolean = { false },
    ): JSONObject {
        if (!result.optBoolean("success", false)) return result

        val itemObject = parseObject(itemJson)
        val requestObject = parseObject(requestJson)
        validateRequestContract(requestObject)
        val input = FinalizeInput(
            itemId = itemId,
            request = requestObject,
            item = itemObject,
            track = itemObject.optJSONObject("track") ?: JSONObject(),
            result = result,
        )
        val track = if (input.track.length() > 0) input.track else input.item.optJSONObject("track") ?: JSONObject()
        val effectiveInput = input.copy(track = track)

        val initialPath = result.optString("file_path", "").trim()
        if (initialPath.isEmpty()) {
            result.put("success", false)
            result.put("error", "Native finalizer received empty file path")
            result.put("error_type", "unknown")
            return result
        }

        val state = FinalizeState(
            filePath = initialPath,
            fileName = result.optString("file_name", "").ifBlank { File(initialPath).name },
            quality = requestQuality(effectiveInput),
            bitDepth = optPositiveInt(result, "actual_bit_depth"),
            sampleRate = optPositiveInt(result, "actual_sample_rate"),
            bitrateKbps = optPositiveBitrateKbps(result, "bitrate")
                ?: optPositiveBitrateKbps(result, "actual_bitrate"),
            audioCodec = normalizeAudioCodec(
                result.optString("audio_codec", "").ifBlank { result.optString("format", "") },
            ),
        )

        // Once the output has been published to its final destination the audio
        // is complete; failures past that point are bookkeeping and must never
        // trigger the destructive cleanup below.
        var outputPublished = result.optBoolean("already_exists", false)
        try {
            var qualityMetadataRefreshed = false
            if (!result.optBoolean("already_exists", false)) {
                checkCancelled(shouldCancel)
                currentStatus("finalizing")
                finalizeDecryption(context, effectiveInput, state, shouldCancel)
                checkCancelled(shouldCancel)
                finalizeHighConversion(context, effectiveInput, state, shouldCancel)
                checkCancelled(shouldCancel)
                finalizeContainerConversion(context, effectiveInput, state, shouldCancel)
                checkCancelled(shouldCancel)
                finalizeMetadata(context, effectiveInput, state)
                checkCancelled(shouldCancel)
                runPostProcessing(context, effectiveInput, state, shouldCancel)
                checkCancelled(shouldCancel)
                val replayGain = writeReplayGain(context, effectiveInput, state, shouldCancel)
                if (replayGain != null) result.put("replaygain", replayGain)
                checkCancelled(shouldCancel)
                try {
                    refreshFinalAudioQualityMetadata(context, result, state)
                } catch (e: Exception) {
                    android.util.Log.w(TAG, "Quality metadata refresh failed (non-fatal): ${e.message}")
                }
                qualityMetadataRefreshed = true
                try {
                    finalizeQualityVariantFilename(context, effectiveInput, state)
                } catch (e: Exception) {
                    android.util.Log.w(TAG, "Quality variant rename failed (non-fatal): ${e.message}")
                }
                checkCancelled(shouldCancel)
                try {
                    writeExternalLrc(context, effectiveInput, state)
                } catch (e: Exception) {
                    android.util.Log.w(TAG, "External LRC write failed (non-fatal): ${e.message}")
                }
                checkCancelled(shouldCancel)
                if (isDeferredSafPublish(effectiveInput)) {
                    publishDeferredSafOutput(context, effectiveInput, state)
                } else {
                    promoteStagedSafOutputIfNeeded(context, effectiveInput, state)
                }
                outputPublished = true
            }
            if (!qualityMetadataRefreshed) {
                try {
                    refreshFinalAudioQualityMetadata(context, result, state)
                } catch (e: Exception) {
                    android.util.Log.w(TAG, "Quality metadata refresh failed (non-fatal): ${e.message}")
                }
            }

            val saveDownloadHistory = parseObject(settingsJson)
                .optBoolean("save_download_history", true)
            val preserveQualityVariant = input.request
                .optBoolean("allow_quality_variant", false)
            val history = if (
                saveDownloadHistory &&
                !result.optBoolean("publish_collision_existing", false) &&
                !(preserveQualityVariant && result.optBoolean("already_exists", false))
            ) {
                try {
                    buildHistoryRow(effectiveInput, state).also {
                        upsertHistory(
                            context,
                            it,
                            deduplicateTrack = !preserveQualityVariant,
                        )
                    }
                } catch (e: Exception) {
                    // History is bookkeeping; never fail (and never delete) a
                    // finished download because the insert failed.
                    android.util.Log.w(TAG, "History write failed (non-fatal): ${e.message}")
                    null
                }
            } else {
                null
            }

            result.put("file_path", state.filePath)
            if (state.fileName.isNotBlank()) result.put("file_name", state.fileName)
            if (state.quality.isNotBlank()) result.put("quality", state.quality)
            result.put("native_finalized", true)
            result.put("history_written", history != null)
            if (history != null) result.put("history_item", historyToJson(history))
        } catch (e: CancellationException) {
            if (!outputPublished) {
                cleanupFailedFinalizationOutput(context, result, initialPath, state.filePath)
            }
            result.put("success", false)
            result.put("error", "Native finalization cancelled")
            result.put("error_type", "cancelled")
            result.put("native_finalized", false)
        } catch (e: Exception) {
            if (!outputPublished) {
                cleanupFailedFinalizationOutput(context, result, initialPath, state.filePath)
            }
            result.put("success", false)
            result.put("error", "Native finalization failed: ${e.message}")
            result.put("error_type", "unknown")
            result.put("native_finalized", false)
        }

        return result
    }

    internal fun checkCancelled(shouldCancel: () -> Boolean) {
        if (shouldCancel()) {
            throw CancellationException("Native finalization cancelled")
        }
    }

    fun replayGainAlbumKey(requestJson: String, itemJson: String): String {
        val item = parseObject(itemJson)
        val input = FinalizeInput(
            itemId = item.optString("id", ""),
            request = parseObject(requestJson),
            item = item,
            track = item.optJSONObject("track") ?: JSONObject(),
            result = JSONObject(),
        )
        return albumKey(input)
    }

    fun writeAlbumReplayGain(context: Context, entriesJson: String): String {
        val entries = org.json.JSONArray(entriesJson)
        val grouped = linkedMapOf<String, MutableList<JSONObject>>()
        for (index in 0 until entries.length()) {
            val entry = entries.optJSONObject(index) ?: continue
            val key = entry.optString("album_key", "")
            if (key.isBlank()) continue
            grouped.getOrPut(key) { mutableListOf() }.add(entry)
        }

        var albumsWritten = 0
        var filesWritten = 0
        for ((_, group) in grouped) {
            if (group.size <= 1) continue
            var sumWeightedPower = 0.0
            var sumDuration = 0.0
            var maxPeak = 0.0
            for (entry in group) {
                val integrated = entry.optDouble("integrated_lufs", Double.NaN)
                if (integrated.isNaN()) continue
                val duration = entry.optDouble("duration_secs", 1.0).let { if (it > 0) it else 1.0 }
                val peak = entry.optDouble("true_peak_linear", 1.0)
                sumWeightedPower += 10.0.pow(integrated / 10.0) * duration
                sumDuration += duration
                if (peak > maxPeak) maxPeak = peak
            }
            if (sumDuration <= 0) continue
            val albumLufs = 10.0 * kotlin.math.log10(sumWeightedPower / sumDuration)
            val albumGainDb = -18.0 - albumLufs
            val albumGain = "${if (albumGainDb >= 0) "+" else ""}${"%.2f".format(Locale.US, albumGainDb)} dB"
            val albumPeak = "%.6f".format(Locale.US, if (maxPeak > 0) maxPeak else 1.0)
            val fields = JSONObject()
                .put("replaygain_album_gain", albumGain)
                .put("replaygain_album_peak", albumPeak)
            var wroteForAlbum = false
            for (entry in group) {
                val path = entry.optString("file_path", "")
                if (path.isBlank()) continue
                try {
                    writeReplayGainFields(context, path, fields)
                    filesWritten++
                    wroteForAlbum = true
                } catch (e: Exception) {
                    android.util.Log.w("SpotiFLAC", "Failed to write native album ReplayGain: ${e.message}")
                }
            }
            if (wroteForAlbum) albumsWritten++
        }

        return JSONObject()
            .put("success", true)
            .put("albums_written", albumsWritten)
            .put("files_written", filesWritten)
            .toString()
    }

    private fun parseObject(raw: String): JSONObject {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return JSONObject()
        return try {
            JSONObject(trimmed)
        } catch (_: Exception) {
            JSONObject()
        }
    }

    private fun currentStatus(@Suppress("UNUSED_PARAMETER") status: String) {
    }

    private fun cleanupFailedFinalizationOutput(
        context: Context,
        result: JSONObject,
        initialPath: String,
        currentPath: String,
    ) {
        if (result.optBoolean("already_exists", false)) return

        val paths = linkedSetOf<String>()
        if (initialPath.isNotBlank()) paths.add(initialPath)
        if (currentPath.isNotBlank()) paths.add(currentPath)
        val resultPath = result.optString("file_path", "").trim()
        if (resultPath.isNotBlank()) paths.add(resultPath)

        var cleanedAny = false
        for (path in paths) {
            cleanedAny = deleteFinalizerOwnedOutput(context, path) || cleanedAny
        }
        if (cleanedAny) {
            result.put("native_finalizer_cleaned_output", true)
        }
    }

    private fun deleteFinalizerOwnedOutput(context: Context, path: String): Boolean {
        if (path.startsWith("content://")) {
            return SafDownloadHandler.deleteContentUri(context, path)
        }

        return try {
            val file = File(path)
            if (!file.exists()) return false

            val canonicalPath = file.canonicalPath
            val appDataPath = File(context.applicationInfo.dataDir).canonicalPath
            val cachePath = context.cacheDir.canonicalPath
            if (!canonicalPath.startsWith("$appDataPath/") && !canonicalPath.startsWith("$cachePath/")) {
                return false
            }
            file.delete()
        } catch (_: Exception) {
            false
        }
    }

    private fun requestQuality(input: FinalizeInput): String {
        return input.request.optString("quality", "").ifBlank {
            input.item.optString("qualityOverride", "").ifBlank { "LOSSLESS" }
        }
    }

    private fun outputExt(input: FinalizeInput): String {
        val safExt = input.request.optString("saf_output_ext", "")
        val ext = safExt.ifBlank { input.request.optString("output_ext", "") }
        return normalizeExt(ext.ifBlank {
            when (requestQuality(input)) {
                "HIGH" -> ".mp3"
                else -> ".flac"
            }
        })
    }

    private fun finalizeDecryption(
        context: Context,
        input: FinalizeInput,
        state: FinalizeState,
        shouldCancel: () -> Boolean,
    ) {
        val descriptor = input.result.optJSONObject("decryption")
        val key = descriptor?.optString("key", "")?.trim().orEmpty()
            .ifBlank { input.result.optString("decryption_key", "").trim() }
        if (key.isEmpty()) return

        val inputFormat = descriptor?.optString("input_format", "")?.trim().orEmpty().ifBlank { "mov" }
        val requestedOutputExt = descriptor?.optString("output_extension", "")?.trim().orEmpty()
        val preferredExt = resolvePreferredDecryptionExtension(state.filePath, requestedOutputExt)
        val localInput = materializeForFFmpeg(context, input, state)
        val originalPath = localInput

        var outputPath = buildOutputPath(localInput, preferredExt)
        var successPath: String? = null
        var lastOutput = ""

        try {
            for (candidate in decryptionKeyCandidates(key)) {
                checkCancelled(shouldCancel)
                val attempts = mutableListOf<Triple<String, Boolean, Boolean>>()
                attempts.add(Triple(outputPath, preferredExt == ".flac", false))
                if (preferredExt == ".flac") {
                    attempts.add(Triple(buildOutputPath(localInput, ".m4a"), false, false))
                }
                if (preferredExt == ".flac" || preferredExt == ".m4a") {
                    attempts.add(Triple(buildOutputPath(localInput, ".mp4"), false, false))
                }
                // MOV muxer fallback for codecs the MP4 muxer rejects (e.g. AC-4):
                // keeps the .mp4 filename but stores the codec params.
                attempts.add(Triple(buildOutputPath(localInput, ".mp4"), false, true))

                for ((candidateOutput, mapAudioOnly, forceMov) in attempts) {
                    val stagedOutput = stagedConversionPath(candidateOutput)
                    try {
                        val audioMap = if (mapAudioOnly) "-map 0:a " else ""
                        // Force the flac muxer when the target extension is
                        // .flac. Without this override FFmpeg keeps the ISO-BMFF
                        // stream layout, producing FLAC-in-MP4 under a .flac
                        // filename which downstream native FLAC tag writers
                        // cannot read.
                        val muxerOverride = when {
                            forceMov -> "-f mov "
                            candidateOutput.lowercase(Locale.ROOT).endsWith(".flac") -> "-f flac "
                            else -> ""
                        }
                        val command = "-v error -decryption_key ${q(candidate)} -f $inputFormat -i ${q(localInput)} ${audioMap}-c copy ${muxerOverride}${q(stagedOutput)} -y"
                        val result = runFFmpeg(command, shouldCancel)
                        lastOutput = result.second
                        if (result.first && File(stagedOutput).exists() &&
                            promoteStagedConversion(stagedOutput, candidateOutput)
                        ) {
                            successPath = candidateOutput
                            outputPath = candidateOutput
                            break
                        }
                        File(stagedOutput).delete()
                    } catch (e: CancellationException) {
                        File(stagedOutput).delete()
                        throw e
                    } catch (e: Exception) {
                        File(stagedOutput).delete()
                        throw e
                    }
                }
                if (successPath != null) break
            }

            val decryptedPath = successPath ?: throw IllegalStateException("decrypt failed: $lastOutput")
            replaceStatePath(context, input, state, decryptedPath, deleteOld = true)
        } finally {
            if (successPath == null) {
                File(outputPath).delete()
            }
            if (originalPath != successPath && originalPath.startsWith(context.cacheDir.absolutePath)) {
                File(originalPath).delete()
            }
        }
    }

    private fun finalizeHighConversion(
        context: Context,
        input: FinalizeInput,
        state: FinalizeState,
        shouldCancel: () -> Boolean,
    ) {
        if (requestQuality(input) != "HIGH") return
        if (!looksLikeM4a(state.filePath, state.fileName)) return

        val tidalHighFormat = input.request.optString("tidal_high_format", "").ifBlank { "mp3_320" }
        val format = when {
            tidalHighFormat.startsWith("opus") -> "opus"
            tidalHighFormat.startsWith("aac") || tidalHighFormat.startsWith("m4a") -> "aac"
            else -> "mp3"
        }
        val metadataFormat = if (format == "aac") "m4a" else format
        val displayFormat = if (format == "aac") "AAC" else format.uppercase(Locale.ROOT)
        val bitrate = if (tidalHighFormat.contains("_")) {
            "${tidalHighFormat.substringAfterLast("_")}k"
        } else {
            if (format == "opus") "128k" else "320k"
        }
        val ext = when (format) {
            "opus" -> ".opus"
            "aac" -> ".m4a"
            else -> ".mp3"
        }
        val localInput = materializeForFFmpeg(context, input, state)
        val deleteLocalInput = state.filePath.startsWith("content://")
        val output = buildOutputPath(localInput, ext)
        val stagedOutput = stagedConversionPath(output)
        var adoptedOutput = false
        try {
            val command = if (format == "opus") {
                "-v error -hide_banner -i ${q(localInput)} -codec:a libopus -b:a $bitrate -vbr on -compression_level 10 -map 0:a ${q(stagedOutput)} -y"
            } else if (format == "aac") {
                "-v error -hide_banner -i ${q(localInput)} -codec:a aac -b:a $bitrate -map 0:a -f mp4 ${q(stagedOutput)} -y"
            } else {
                "-v error -hide_banner -i ${q(localInput)} -codec:a libmp3lame -b:a $bitrate -map 0:a -id3v2_version 3 ${q(stagedOutput)} -y"
            }
            val result = runFFmpeg(command, shouldCancel)
            if (!result.first || !File(stagedOutput).exists()) {
                throw IllegalStateException("HIGH conversion failed: ${result.second}")
            }
            if (!promoteStagedConversion(stagedOutput, output)) {
                throw IllegalStateException("failed to publish HIGH conversion output")
            }
            embedBasicMetadata(context, output, input, metadataFormat)
            replaceStatePath(context, input, state, output, deleteOld = true)
            adoptedOutput = true
        } finally {
            if (!adoptedOutput) {
                File(stagedOutput).delete()
                File(output).delete()
            }
            if (deleteLocalInput) File(localInput).delete()
        }
        state.quality = "$displayFormat ${bitrate.removeSuffix("k")}kbps"
        state.bitDepth = null
        state.sampleRate = null
    }

    private fun finalizeContainerConversion(
        context: Context,
        input: FinalizeInput,
        state: FinalizeState,
        shouldCancel: () -> Boolean,
    ) {
        if (requestQuality(input) == "HIGH" || outputExt(input) != ".flac") return
        val requestedDecryptionExt = requestedDecryptionOutputExt(input)
        val forceContainerConversion = shouldForceContainerConversion(input, state)
        if (!forceContainerConversion && requestedDecryptionExt.isNotBlank() && requestedDecryptionExt != ".flac") return
        val mayNeedContainerConversion = forceContainerConversion ||
            looksLikeM4a(state.filePath, state.fileName) ||
            state.filePath.startsWith("content://")
        if (!mayNeedContainerConversion) return

        val localInput = materializeForFFmpeg(context, input, state)
        val deleteLocalInput = state.filePath.startsWith("content://")
        val output = buildOutputPath(localInput, ".flac")
        val stagedOutput = stagedConversionPath(output)
        var adoptedOutput = false
        try {
            val codec = probePrimaryAudioCodec(localInput, shouldCancel)
            val isAlreadyNativeFlac = codec == "flac" && isNativeFlacFile(localInput)
            if (!isLosslessAudioCodec(codec)) {
                Log.d(TAG, "Preserving native container; audio codec is ${codec.ifBlank { "unknown" }}")
                // The preserved stream is not FLAC but still carries the
                // requested .flac name. Rename to the real container so the
                // metadata/ReplayGain writers pick the right format — an
                // MP4 stream under a .flac name fails "fLaC head incorrect"
                // on every subsequent write and the file is never repaired.
                adoptPreservedContainerExtension(state, localInput, codec)
                return
            }
            if (isAlreadyNativeFlac) {
                Log.d(TAG, "Native FLAC payload detected; publishing as FLAC and embedding metadata")
                val nativeFlacOutput = if (localInput.lowercase(Locale.ROOT).endsWith(".flac")) {
                    localInput
                } else {
                    File(localInput).copyTo(File(stagedOutput), overwrite = true)
                    if (!promoteStagedConversion(stagedOutput, output)) {
                        throw IllegalStateException("failed to publish native FLAC output")
                    }
                    output
                }
                embedBasicMetadata(context, nativeFlacOutput, input, "flac")
                replaceStatePath(context, input, state, nativeFlacOutput, deleteOld = true)
                adoptedOutput = true
                return
            }
            val result = runFFmpeg(
                "-v error -xerror -i ${q(localInput)} -c:a flac -compression_level 8 ${q(stagedOutput)} -y",
                shouldCancel,
            )
            if (!result.first || !File(stagedOutput).exists()) {
                throw IllegalStateException("container conversion failed: ${result.second}")
            }
            if (!promoteStagedConversion(stagedOutput, output)) {
                throw IllegalStateException("failed to publish container conversion output")
            }
            embedBasicMetadata(context, output, input, "flac")
            replaceStatePath(context, input, state, output, deleteOld = true)
            adoptedOutput = true
        } finally {
            if (!adoptedOutput) {
                File(stagedOutput).delete()
                File(output).delete()
            }
            if (deleteLocalInput) File(localInput).delete()
        }
    }

    /// Renames a preserved lossy/unknown stream away from its requested .flac
    /// name to match its actual container (mirrors the Dart pipeline's
    /// post-download rename). Local files only: legacy content:// outputs are
    /// left untouched. No-op when the container cannot be identified.
    private fun adoptPreservedContainerExtension(
        state: FinalizeState,
        localInput: String,
        codec: String,
    ) {
        if (state.filePath.startsWith("content://")) return
        val currentFile = File(state.filePath)
        if (!currentFile.exists()) return
        if (!currentFile.name.lowercase(Locale.ROOT).endsWith(".flac")) return

        val newExt = when {
            codec == "aac" && isMP4ContainerFile(localInput) -> ".m4a"
            codec == "mp3" -> ".mp3"
            codec == "opus" -> ".opus"
            isMP4ContainerFile(localInput) -> ".m4a"
            else -> return
        }
        val renamed = File(
            currentFile.parentFile,
            currentFile.name.dropLast(".flac".length) + newExt,
        )
        if (renamed.exists() && !renamed.delete()) {
            Log.w(TAG, "Cannot adopt container extension; ${renamed.name} already exists")
            return
        }
        if (!currentFile.renameTo(renamed)) {
            Log.w(TAG, "Failed to rename preserved container to ${renamed.name}")
            return
        }
        Log.i(TAG, "Preserved container renamed: ${currentFile.name} -> ${renamed.name}")
        state.filePath = renamed.absolutePath
        if (state.fileName.isNotBlank()) {
            state.fileName = renamed.name
        }
        state.audioCodec = normalizeAudioCodec(codec)
    }

    private fun finalizeMetadata(context: Context, input: FinalizeInput, state: FinalizeState) {
        if (!input.request.optBoolean("embed_metadata", false)) return
        if (!state.filePath.startsWith("content://")) {
            embedBasicMetadata(context, state.filePath, input, formatForPath(state.filePath))
            return
        }

        val tempPath = SafDownloadHandler.copyContentUriToTemp(context, state.filePath)
            ?: throw IllegalStateException("failed to copy SAF file for metadata")
        try {
            embedBasicMetadata(context, tempPath, input, formatForPath(state.fileName.ifBlank { tempPath }))
            val tempFile = File(tempPath)
            val finalName = desiredFileName(input, state, normalizeExt(state.fileName.substringAfterLast('.', "")))
            val newUri = SafDownloadHandler.writeFileToSaf(
                context = context,
                treeUriStr = input.request.optString("saf_tree_uri", ""),
                relativeDir = input.request.optString("saf_relative_dir", ""),
                fileName = finalName,
                mimeType = mimeTypeForExt(finalName.substringAfterLast('.', "")),
                srcPath = tempFile.absolutePath,
            ) ?: throw IllegalStateException("failed to write metadata-updated SAF file")
            if (newUri != state.filePath) SafDownloadHandler.deleteContentUri(context, state.filePath)
            state.filePath = newUri
            state.fileName = finalName
        } finally {
            File(tempPath).delete()
        }
    }

    private fun writeReplayGain(
        context: Context,
        input: FinalizeInput,
        state: FinalizeState,
        shouldCancel: () -> Boolean,
    ): JSONObject? {
        if (!input.request.optBoolean("embed_replaygain", false)) return null
        val ext = normalizeExt(File(state.filePath).extension)
        val fileExt = if (state.filePath.startsWith("content://")) {
            normalizeExt(state.fileName.substringAfterLast('.', ""))
        } else {
            ext
        }
        if (fileExt != ".flac" && fileExt != ".m4a" && fileExt != ".mp4") return null

        val scanPath = if (state.filePath.startsWith("content://")) {
            SafDownloadHandler.copyContentUriToTemp(context, state.filePath)
                ?: throw IllegalStateException("failed to copy SAF file for ReplayGain")
        } else {
            state.filePath
        }
        val deleteScanPath = scanPath != state.filePath
        val scan = try {
            scanReplayGain(scanPath, shouldCancel) ?: return null
        } finally {
            if (deleteScanPath) File(scanPath).delete()
        }
        checkCancelled(shouldCancel)
        val fields = JSONObject()
            .put("replaygain_track_gain", scan.trackGain)
            .put("replaygain_track_peak", scan.trackPeak)
        writeReplayGainFields(context, state.filePath, fields)

        return JSONObject()
            .put("album_key", albumKey(input))
            .put("file_path", state.filePath)
            .put("file_name", state.fileName)
            .put("track_id", trackString(input, "id", input.request.optString("spotify_id", input.itemId)))
            .put("integrated_lufs", scan.integratedLufs)
            .put("true_peak_linear", scan.truePeakLinear)
            .put("duration_secs", replayGainDurationSeconds(input))
            .put("track_gain", scan.trackGain)
            .put("track_peak", scan.trackPeak)
    }

    private fun writeReplayGainFields(context: Context, path: String, fields: JSONObject) {
        if (!path.startsWith("content://")) {
            Gobackend.editFileMetadata(path, fields.toString())
            return
        }

        val tempPath = SafDownloadHandler.copyContentUriToTemp(context, path)
            ?: throw IllegalStateException("failed to copy SAF file for ReplayGain write")
        try {
            Gobackend.editFileMetadata(tempPath, fields.toString())
            val uri = Uri.parse(path)
            context.contentResolver.openOutputStream(uri, "wt")?.use { output ->
                File(tempPath).inputStream().use { input -> input.copyTo(output) }
                SafDownloadHandler.syncOutputStream(output)
            } ?: throw IllegalStateException("failed to write ReplayGain back to SAF")
        } finally {
            File(tempPath).delete()
        }
    }

    private fun refreshFinalAudioQualityMetadata(context: Context, result: JSONObject, state: FinalizeState) {
        if (!supportsAudioMetadataProbe(state.filePath, state.fileName)) return

        val probePath = if (state.filePath.startsWith("content://")) {
            SafDownloadHandler.copyContentUriToTemp(context, state.filePath) ?: return
        } else {
            state.filePath
        }
        val deleteProbePath = probePath != state.filePath

        try {
            val metadata = parseObject(Gobackend.readFileMetadata(probePath))
            if (metadata.has("error")) return

            val bitDepth = optPositiveInt(metadata, "bit_depth")
            val sampleRate = optPositiveInt(metadata, "sample_rate")
            val probedCodec = normalizeAudioCodec(
                metadata.optString("audio_codec", "").ifBlank {
                    metadata.optString("codec", "").ifBlank {
                        metadata.optString("format", "")
                    }
                }
            )
            if (probedCodec != null) {
                state.audioCodec = probedCodec
                result.put("audio_codec", probedCodec)
            }
            if (bitDepth != null) {
                state.bitDepth = bitDepth
                result.put("actual_bit_depth", bitDepth)
            }
            if (sampleRate != null) {
                state.sampleRate = sampleRate
                result.put("actual_sample_rate", sampleRate)
            }
            val bitrateKbps = optPositiveBitrateKbps(metadata, "bitrate")
                ?: optPositiveBitrateKbps(metadata, "bit_rate")
            if (bitrateKbps != null) {
                state.bitrateKbps = bitrateKbps
                result.put("bitrate", bitrateKbps)
            }

            val displayQuality = displayAudioQuality(
                filePath = state.filePath,
                fileName = state.fileName,
                bitDepth = state.bitDepth,
                sampleRate = state.sampleRate,
                bitrateKbps = state.bitrateKbps,
                audioCodec = state.audioCodec,
                storedQuality = state.quality,
            )
            if (displayQuality != null) {
                state.quality = displayQuality
            }
        } catch (_: Exception) {
        } finally {
            if (deleteProbePath) File(probePath).delete()
        }
    }

    private fun supportsAudioMetadataProbe(filePath: String, fileName: String): Boolean {
        val lowerPath = filePath.trim().lowercase(Locale.ROOT)
        val lowerName = fileName.trim().lowercase(Locale.ROOT)
        if (lowerPath.startsWith("content://")) return true
        return lowerPath.endsWith(".flac") ||
            lowerPath.endsWith(".m4a") ||
            lowerPath.endsWith(".mp4") ||
            lowerPath.endsWith(".aac") ||
            lowerPath.endsWith(".mp3") ||
            lowerPath.endsWith(".opus") ||
            lowerPath.endsWith(".ogg") ||
            lowerName.endsWith(".flac") ||
            lowerName.endsWith(".m4a") ||
            lowerName.endsWith(".mp4") ||
            lowerName.endsWith(".aac") ||
            lowerName.endsWith(".mp3") ||
            lowerName.endsWith(".opus") ||
            lowerName.endsWith(".ogg")
    }

    private fun runPostProcessing(
        context: Context,
        input: FinalizeInput,
        state: FinalizeState,
        shouldCancel: () -> Boolean,
    ) {
        if (!input.request.optBoolean("post_processing_enabled", false)) return
        val metadata = JSONObject()
            .put("title", trackString(input, "name", input.request.optString("track_name", "")))
            .put("artist", trackString(input, "artistName", input.request.optString("artist_name", "")))
            .put("album", trackString(input, "albumName", input.request.optString("album_name", "")))
            .put("album_artist", trackString(input, "albumArtist", input.request.optString("album_artist", "")))
            .put("track_number", trackInt(input, "trackNumber", input.request.optInt("track_number", 0)))
            .put("disc_number", trackInt(input, "discNumber", input.request.optInt("disc_number", 0)))
            .put("isrc", trackString(input, "isrc", input.request.optString("isrc", "")))
            .put("release_date", trackString(input, "releaseDate", input.request.optString("release_date", "")))
            .put("duration_ms", trackInt(input, "duration", 0) * 1000)
            .put("cover_url", metadataCoverUrl(input))

        if (state.filePath.startsWith("content://")) {
            val uri = state.filePath
            val tempInput = SafDownloadHandler.copyContentUriToTemp(context, uri)
                ?: throw IllegalStateException("failed to copy SAF file for post-processing")
            try {
                val inputObj = JSONObject()
                    .put("path", tempInput)
                    .put("uri", uri)
                    .put("name", state.fileName)
                    .put("mime_type", mimeTypeForExt(state.fileName.substringAfterLast('.', "")))
                    .put("size", File(tempInput).length())
                    .put("is_saf", true)
                val response = JSONObject(
                    withFFmpegCommandPump(shouldCancel) {
                        checkCancelled(shouldCancel)
                        Gobackend.runPostProcessingV2JSON(inputObj.toString(), metadata.toString())
                    }
                )
                checkCancelled(shouldCancel)
                if (!response.optBoolean("success", false)) return
                val newPath = response.optString("new_file_path", "")
                val outputPath = newPath.ifBlank { tempInput }
                val outputFile = File(outputPath)
                if (!outputFile.exists()) return
                val outputName = if (newPath.isBlank()) state.fileName else outputFile.name
                val newUri = SafDownloadHandler.writeFileToSaf(
                    context = context,
                    treeUriStr = input.request.optString("saf_tree_uri", ""),
                    relativeDir = input.request.optString("saf_relative_dir", ""),
                    fileName = outputName,
                    mimeType = mimeTypeForExt(outputFile.extension),
                    srcPath = outputFile.absolutePath,
                ) ?: return
                if (newUri != uri) SafDownloadHandler.deleteContentUri(context, uri)
                state.filePath = newUri
                state.fileName = outputName
                if (outputPath != tempInput) outputFile.delete()
            } finally {
                File(tempInput).delete()
            }
            return
        }

        val inputObj = JSONObject()
            .put("path", state.filePath)
            .put("name", state.fileName)
            .put("is_saf", false)
        val response = JSONObject(
            withFFmpegCommandPump(shouldCancel) {
                checkCancelled(shouldCancel)
                Gobackend.runPostProcessingV2JSON(inputObj.toString(), metadata.toString())
            }
        )
        checkCancelled(shouldCancel)
        if (response.optBoolean("success", false)) {
            val newPath = response.optString("new_file_path", "")
            if (newPath.isNotBlank() && newPath != state.filePath) {
                state.filePath = newPath
                state.fileName = File(newPath).name
            }
        }
    }

    internal fun materializeForFFmpeg(context: Context, input: FinalizeInput, state: FinalizeState): String {
        if (!state.filePath.startsWith("content://")) return state.filePath
        return SafDownloadHandler.copyContentUriToTemp(context, state.filePath)
            ?: throw IllegalStateException("failed to copy SAF file")
    }

    internal fun replaceStatePath(
        context: Context,
        input: FinalizeInput,
        state: FinalizeState,
        localOutput: String,
        deleteOld: Boolean,
    ) {
        if (state.filePath.startsWith("content://")) {
            val outputFile = File(localOutput)
            val finalName = desiredFileName(input, state, outputFile.extension)
            val newUri = SafDownloadHandler.writeFileToSaf(
                context = context,
                treeUriStr = input.request.optString("saf_tree_uri", ""),
                relativeDir = input.request.optString("saf_relative_dir", ""),
                fileName = finalName,
                mimeType = mimeTypeForExt(outputFile.extension),
                srcPath = outputFile.absolutePath,
            ) ?: throw IllegalStateException("failed to write finalized file to SAF")
            SafDownloadHandler.deleteContentUri(context, state.filePath)
            state.filePath = newUri
            state.fileName = finalName
            outputFile.delete()
            return
        }

        val oldPath = state.filePath
        state.filePath = localOutput
        state.fileName = File(localOutput).name
        if (deleteOld && oldPath != localOutput) File(oldPath).delete()
    }

    private fun validateRequestContract(request: JSONObject) {
        val version = request.optInt("contract_version", -1)
        if (version != NATIVE_WORKER_CONTRACT_VERSION) {
            throw IllegalArgumentException(
                "unsupported native worker request contract v$version"
            )
        }

        val required = listOf("item_id", "service", "track_name", "quality", "storage_mode")
        val missing = required.filter { request.optString(it, "").trim().isEmpty() }
        if (missing.isNotEmpty()) {
            throw IllegalArgumentException(
                "native worker request missing fields: ${missing.joinToString()}"
            )
        }
    }

    private fun decryptionKeyCandidates(raw: String): List<String> {
        val candidates = linkedSetOf<String>()
        fun add(value: String) {
            val trimmed = value.trim()
            if (trimmed.isNotEmpty()) candidates.add(trimmed)
        }
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return emptyList()
        add(trimmed)
        val noPrefix = if (trimmed.startsWith("0x", ignoreCase = true)) trimmed.substring(2) else trimmed
        add(noPrefix)
        val compactHex = noPrefix.replace(Regex("[^0-9a-fA-F]"), "")
        if (compactHex.isNotEmpty() && compactHex.length % 2 == 0) add(compactHex)
        try {
            val decoded = Base64.decode(noPrefix.replace(Regex("\\s+"), ""), Base64.DEFAULT)
            if (decoded.isNotEmpty()) {
                add(decoded.joinToString("") { "%02x".format(it) })
            }
        } catch (_: Exception) {
        }
        return candidates.toList()
    }

    private fun looksLikeM4a(path: String, fileName: String): Boolean {
        val lowerPath = path.lowercase(Locale.ROOT)
        val lowerName = fileName.lowercase(Locale.ROOT)
        return lowerPath.endsWith(".m4a") ||
            lowerPath.endsWith(".mp4") ||
            lowerName.endsWith(".m4a") ||
            lowerName.endsWith(".mp4")
    }

    private fun albumKey(input: FinalizeInput): String {
        val albumId = trackString(input, "albumId", "")
        if (albumId.isNotBlank()) return "id:$albumId"
        val albumName = trackString(input, "albumName", input.request.optString("album_name", ""))
        val albumArtist = trackString(input, "albumArtist", input.request.optString("album_artist", ""))
        return "name:$albumName|$albumArtist"
    }

    private fun replayGainDurationSeconds(input: FinalizeInput): Double {
        val duration = input.request.optInt("duration_ms", 0).let {
            if (it > 0) it else trackInt(input, "duration", 0)
        }
        if (duration <= 0) return 1.0
        return if (duration > 10000) duration / 1000.0 else duration.toDouble()
    }

    private fun buildHistoryRow(input: FinalizeInput, state: FinalizeState): ContentValues {
        val result = input.result
        val values = ContentValues()
        values.put("id", input.itemId)
        values.put("track_name", result.optString("title", "").ifBlank { trackString(input, "name", input.request.optString("track_name", "")) })
        values.put("artist_name", result.optString("artist", "").ifBlank { trackString(input, "artistName", input.request.optString("artist_name", "")) })
        values.put("album_name", result.optString("album", "").ifBlank { trackString(input, "albumName", input.request.optString("album_name", "")) })
        values.put("album_artist", normalizeOptional(resultString(input, "album_artist").ifBlank { trackString(input, "albumArtist", requestString(input, "album_artist")) }))
        values.put("cover_url", normalizeOptional(metadataCoverUrl(input).ifBlank { resultString(input, "cover_url") }))
        values.put("file_path", state.filePath)
        values.put("storage_mode", input.request.optString("storage_mode", "app"))
        values.put("download_tree_uri", normalizeOptional(input.request.optString("saf_tree_uri", "")))
        values.put("saf_relative_dir", normalizeOptional(input.request.optString("saf_relative_dir", "")))
        values.put("saf_file_name", if (state.filePath.startsWith("content://")) state.fileName else null)
        values.put("saf_repaired", 0)
        values.put("service", result.optString("service", "").ifBlank { input.item.optString("service", "") })
        values.put("downloaded_at", java.time.Instant.now().toString())
        values.put("isrc", normalizeOptional(result.optString("isrc", "").ifBlank { trackString(input, "isrc", input.request.optString("isrc", "")) }))
        values.put("spotify_id", normalizeOptional(trackString(input, "id", input.request.optString("spotify_id", ""))))
        values.put("track_number", positiveOrNull(result.optInt("track_number", 0), trackInt(input, "trackNumber", input.request.optInt("track_number", 0))))
        values.put("total_tracks", positiveOrNull(result.optInt("total_tracks", 0), trackInt(input, "totalTracks", input.request.optInt("total_tracks", 0))))
        values.put("disc_number", positiveOrNull(result.optInt("disc_number", 0), trackInt(input, "discNumber", input.request.optInt("disc_number", 0))))
        values.put("total_discs", positiveOrNull(result.optInt("total_discs", 0), trackInt(input, "totalDiscs", input.request.optInt("total_discs", 0))))
        values.put("duration", trackInt(input, "duration", input.request.optInt("duration_ms", 0) / 1000))
        values.put("release_date", normalizeOptional(resultString(input, "release_date").ifBlank { resultString(input, "date").ifBlank { trackString(input, "releaseDate", requestString(input, "release_date")) } }))
        values.put("quality", state.quality)
        state.bitDepth?.let { values.put("bit_depth", it) }
        state.sampleRate?.let { values.put("sample_rate", it) }
        state.bitrateKbps?.takeIf { it >= 16 }?.let {
            values.put("bitrate", it)
        }
        normalizeAudioCodec(state.audioCodec)?.let { values.put("format", it) }
        values.put("genre", normalizeOptional(result.optString("genre", "").ifBlank { input.request.optString("genre", "") }))
        values.put("composer", normalizeOptional(resultString(input, "composer").ifBlank { trackString(input, "composer", requestString(input, "composer")) }))
        values.put("label", normalizeOptional(result.optString("label", "").ifBlank { input.request.optString("label", "") }))
        values.put("copyright", normalizeOptional(result.optString("copyright", "").ifBlank { input.request.optString("copyright", "") }))
        putNormalizedHistoryColumns(values)
        return values
    }

    private fun upsertHistory(
        context: Context,
        values: ContentValues,
        deduplicateTrack: Boolean = true,
    ) {
        val dbFile = File(File(context.applicationInfo.dataDir, "app_flutter"), "history.db")
        dbFile.parentFile?.mkdirs()
        val db = SQLiteDatabase.openDatabase(
            dbFile.absolutePath,
            null,
            SQLiteDatabase.OPEN_READWRITE or
                SQLiteDatabase.CREATE_IF_NECESSARY or
                SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING,
        )
        try {
	            configureHistoryDatabase(db)
	            db.beginTransaction()
	            try {
	                if (db.version > HISTORY_SCHEMA_VERSION) {
	                    throw IllegalStateException(
	                        "history schema v${db.version} is newer than native finalizer contract v$HISTORY_SCHEMA_VERSION"
	                    )
	                }
	                val needsBackfill = db.version < HISTORY_SCHEMA_VERSION
	                db.execSQL(
	                    """
	                    CREATE TABLE IF NOT EXISTS history (
                      id TEXT PRIMARY KEY,
                      track_name TEXT NOT NULL,
                      artist_name TEXT NOT NULL,
                      album_name TEXT NOT NULL,
                      album_artist TEXT,
                      cover_url TEXT,
                      file_path TEXT NOT NULL,
                      storage_mode TEXT,
                      download_tree_uri TEXT,
                      saf_relative_dir TEXT,
                      saf_file_name TEXT,
                      saf_repaired INTEGER,
                      service TEXT NOT NULL,
                      downloaded_at TEXT NOT NULL,
                      isrc TEXT,
                      spotify_id TEXT,
                      track_number INTEGER,
                      total_tracks INTEGER,
                      disc_number INTEGER,
                      total_discs INTEGER,
                      duration INTEGER,
                      release_date TEXT,
                      quality TEXT,
                      bit_depth INTEGER,
                      sample_rate INTEGER,
                      bitrate INTEGER,
                      format TEXT,
                      genre TEXT,
                      composer TEXT,
                      label TEXT,
                      copyright TEXT,
                      spotify_id_norm TEXT,
                      isrc_norm TEXT,
                      match_key TEXT,
                      album_key TEXT,
                      search_text TEXT
                    )
                    """.trimIndent()
                )
                ensureHistoryColumn(db, "storage_mode", "ALTER TABLE history ADD COLUMN storage_mode TEXT")
                ensureHistoryColumn(db, "download_tree_uri", "ALTER TABLE history ADD COLUMN download_tree_uri TEXT")
                ensureHistoryColumn(db, "saf_relative_dir", "ALTER TABLE history ADD COLUMN saf_relative_dir TEXT")
                ensureHistoryColumn(db, "saf_file_name", "ALTER TABLE history ADD COLUMN saf_file_name TEXT")
                ensureHistoryColumn(db, "saf_repaired", "ALTER TABLE history ADD COLUMN saf_repaired INTEGER")
	                ensureHistoryColumn(db, "composer", "ALTER TABLE history ADD COLUMN composer TEXT")
	                ensureHistoryColumn(db, "total_tracks", "ALTER TABLE history ADD COLUMN total_tracks INTEGER")
	                ensureHistoryColumn(db, "total_discs", "ALTER TABLE history ADD COLUMN total_discs INTEGER")
	                ensureHistoryColumn(db, "bitrate", "ALTER TABLE history ADD COLUMN bitrate INTEGER")
	                ensureHistoryColumn(db, "format", "ALTER TABLE history ADD COLUMN format TEXT")
	                ensureHistoryColumn(db, "spotify_id_norm", "ALTER TABLE history ADD COLUMN spotify_id_norm TEXT")
	                ensureHistoryColumn(db, "isrc_norm", "ALTER TABLE history ADD COLUMN isrc_norm TEXT")
	                ensureHistoryColumn(db, "match_key", "ALTER TABLE history ADD COLUMN match_key TEXT")
	                ensureHistoryColumn(db, "album_key", "ALTER TABLE history ADD COLUMN album_key TEXT")
	                ensureHistoryColumn(db, "search_text", "ALTER TABLE history ADD COLUMN search_text TEXT")
	                ensureHistoryPathKeyTable(db)
	                if (needsBackfill) {
	                    backfillNormalizedHistoryColumns(db)
	                    backfillHistoryPathKeys(db)
	                }
	                validateHistorySchema(db)
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_spotify_id ON history(spotify_id)")
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_isrc ON history(isrc)")
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_downloaded_at ON history(downloaded_at DESC)")
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_album ON history(album_name, album_artist)")
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_history_track_artist ON history(track_name, artist_name)")
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_history_spotify_id_norm ON history(spotify_id_norm)")
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_history_isrc_norm ON history(isrc_norm)")
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_history_match_key ON history(match_key)")
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_history_album_key ON history(album_key)")
	                if (db.version < HISTORY_SCHEMA_VERSION) db.version = HISTORY_SCHEMA_VERSION
	                if (deduplicateTrack) deleteDuplicateHistoryRows(db, values)
	                db.insertWithOnConflict("history", null, values, SQLiteDatabase.CONFLICT_REPLACE)
	                replaceHistoryPathKeys(db, values.getAsString("id"), values.getAsString("file_path"))
	                db.setTransactionSuccessful()
	            } finally {
	                db.endTransaction()
            }
        } finally {
            db.close()
        }
    }

    private fun configureHistoryDatabase(db: SQLiteDatabase) {
        runHistoryPragma(db, "PRAGMA busy_timeout = 5000", required = false)
        runHistoryPragma(db, "PRAGMA synchronous = NORMAL", required = false)
        runHistoryPragma(db, "PRAGMA journal_mode = WAL", required = false)
    }

    private fun runHistoryPragma(db: SQLiteDatabase, sql: String, required: Boolean) {
        try {
            db.rawQuery(sql, null).use { cursor ->
                while (cursor.moveToNext()) {
                    // PRAGMA setters may return a row; consume it so Android closes the cursor cleanly.
                }
            }
        } catch (e: SQLiteException) {
            if (required) throw e
            Log.w(TAG, "Unable to apply history database setting: $sql", e)
        }
    }

    private fun validateHistorySchema(db: SQLiteDatabase) {
        val columns = mutableSetOf<String>()
        db.rawQuery("PRAGMA table_info(history)", null).use { cursor ->
            val nameIndex = cursor.getColumnIndex("name")
            while (cursor.moveToNext()) {
                if (nameIndex >= 0) {
                    columns.add(cursor.getString(nameIndex).lowercase(Locale.ROOT))
                }
            }
        }
        val missing = requiredHistoryColumns.filterNot { columns.contains(it) }
        if (missing.isNotEmpty()) {
            throw IllegalStateException("history schema missing columns for native finalizer: ${missing.joinToString()}")
        }
    }

	    private fun deleteDuplicateHistoryRows(db: SQLiteDatabase, values: ContentValues) {
	        val id = values.getAsString("id") ?: return
	        val duplicateIds = linkedSetOf<String>()
	        val spotifyId = values.getAsString("spotify_id")?.trim().orEmpty()
	        val spotifyIdNorm = values.getAsString("spotify_id_norm")?.trim().orEmpty()
	        if (spotifyId.isNotEmpty() || spotifyIdNorm.isNotEmpty()) {
	            duplicateIds.addAll(
	                historyIdsForWhere(
	                    db,
	                    "(spotify_id = ? OR spotify_id_norm = ?) AND id <> ?",
	                    arrayOf(spotifyId, spotifyIdNorm, id),
	                )
	            )
	        }

	        val isrc = values.getAsString("isrc")?.trim().orEmpty()
	        val isrcNorm = values.getAsString("isrc_norm")?.trim().orEmpty()
	        if (isrc.isNotEmpty() || isrcNorm.isNotEmpty()) {
	            duplicateIds.addAll(
	                historyIdsForWhere(
	                    db,
	                    "(isrc = ? OR isrc_norm = ?) AND id <> ?",
	                    arrayOf(isrc, isrcNorm, id),
	                )
	            )
	        }

	        if (spotifyIdNorm.isEmpty() && isrcNorm.isEmpty()) {
	            val matchKey = values.getAsString("match_key")?.trim().orEmpty()
	            if (matchKey.isNotEmpty()) {
	                duplicateIds.addAll(
	                    historyIdsForWhere(
	                        db,
	                        "match_key = ? AND id <> ?",
	                        arrayOf(matchKey, id),
	                    )
	                )
	            }
	        }
	        if (duplicateIds.isEmpty()) return
	        deleteHistoryPathKeys(db, duplicateIds)
	        val placeholders = duplicateIds.joinToString(",") { "?" }
	        db.delete("history", "id IN ($placeholders)", duplicateIds.toTypedArray())
	    }

	    private fun historyIdsForWhere(db: SQLiteDatabase, where: String, args: Array<String>): List<String> {
	        val ids = mutableListOf<String>()
	        db.query("history", arrayOf("id"), where, args, null, null, null).use { cursor ->
	            val idIndex = cursor.getColumnIndex("id")
	            while (cursor.moveToNext()) {
	                if (idIndex >= 0) ids.add(cursor.getString(idIndex))
	            }
	        }
	        return ids
	    }

	    private fun deleteHistoryPathKeys(db: SQLiteDatabase, ids: Collection<String>) {
	        if (ids.isEmpty()) return
	        val placeholders = ids.joinToString(",") { "?" }
	        db.delete("history_path_keys", "item_id IN ($placeholders)", ids.toTypedArray())
	    }

	    private fun ensureHistoryPathKeyTable(db: SQLiteDatabase) {
	        db.execSQL(
	            """
	            CREATE TABLE IF NOT EXISTS history_path_keys (
	              item_id TEXT NOT NULL,
	              path_key TEXT NOT NULL,
	              PRIMARY KEY (item_id, path_key)
	            )
	            """.trimIndent()
	        )
	        db.execSQL("CREATE INDEX IF NOT EXISTS idx_history_path_keys_key ON history_path_keys(path_key)")
	    }

	    private fun backfillNormalizedHistoryColumns(db: SQLiteDatabase) {
	        db.query(
	            "history",
	            arrayOf("id", "spotify_id", "isrc", "track_name", "artist_name", "album_name", "album_artist"),
	            "spotify_id_norm IS NULL OR isrc_norm IS NULL OR match_key IS NULL OR album_key IS NULL OR search_text IS NULL",
	            null,
	            null,
	            null,
	            null,
	        ).use { cursor ->
	            val idIndex = cursor.getColumnIndex("id")
	            val spotifyIndex = cursor.getColumnIndex("spotify_id")
	            val isrcIndex = cursor.getColumnIndex("isrc")
	            val trackIndex = cursor.getColumnIndex("track_name")
	            val artistIndex = cursor.getColumnIndex("artist_name")
	            val albumIndex = cursor.getColumnIndex("album_name")
	            val albumArtistIndex = cursor.getColumnIndex("album_artist")
	            while (cursor.moveToNext()) {
	                if (idIndex < 0) continue
	                val values = ContentValues()
	                val spotifyId = cursor.getNullableString(spotifyIndex)
	                val isrc = cursor.getNullableString(isrcIndex)
	                val trackName = cursor.getNullableString(trackIndex)
	                val artistName = cursor.getNullableString(artistIndex)
	                val albumName = cursor.getNullableString(albumIndex)
	                val albumArtist = cursor.getNullableString(albumArtistIndex)
	                values.put("spotify_id_norm", normalizeSpotifyId(spotifyId))
	                values.put("isrc_norm", normalizeIsrc(isrc))
	                values.put("match_key", matchKeyFor(trackName, artistName))
	                putAlbumSearchHistoryColumns(
	                    values,
	                    trackName = trackName,
	                    artistName = artistName,
	                    albumName = albumName,
	                    albumArtist = albumArtist,
	                )
	                db.update("history", values, "id = ?", arrayOf(cursor.getString(idIndex)))
	            }
	        }
	    }

	    private fun backfillHistoryPathKeys(db: SQLiteDatabase) {
	        db.query("history", arrayOf("id", "file_path"), null, null, null, null, null).use { cursor ->
	            val idIndex = cursor.getColumnIndex("id")
	            val pathIndex = cursor.getColumnIndex("file_path")
	            while (cursor.moveToNext()) {
	                if (idIndex >= 0) {
	                    replaceHistoryPathKeys(db, cursor.getString(idIndex), cursor.getNullableString(pathIndex))
	                }
	            }
	        }
	    }

	    private fun replaceHistoryPathKeys(db: SQLiteDatabase, itemId: String?, filePath: String?) {
	        val id = itemId?.trim().orEmpty()
	        if (id.isEmpty()) return
	        db.delete("history_path_keys", "item_id = ?", arrayOf(id))
	        for (key in buildPathMatchKeys(filePath)) {
	            val values = ContentValues()
	            values.put("item_id", id)
	            values.put("path_key", key)
	            db.insertWithOnConflict("history_path_keys", null, values, SQLiteDatabase.CONFLICT_IGNORE)
	        }
	    }

	    private fun putNormalizedHistoryColumns(values: ContentValues) {
	        values.put("spotify_id_norm", normalizeSpotifyId(values.getAsString("spotify_id")))
	        values.put("isrc_norm", normalizeIsrc(values.getAsString("isrc")))
	        values.put(
	            "match_key",
	            matchKeyFor(values.getAsString("track_name"), values.getAsString("artist_name")),
	        )
	        putAlbumSearchHistoryColumns(
	            values,
	            trackName = values.getAsString("track_name"),
	            artistName = values.getAsString("artist_name"),
	            albumName = values.getAsString("album_name"),
	            albumArtist = values.getAsString("album_artist"),
	        )
	    }

	    private fun putAlbumSearchHistoryColumns(
	        values: ContentValues,
	        trackName: String?,
	        artistName: String?,
	        albumName: String?,
	        albumArtist: String?,
	    ) {
	        val track = normalizeLookupText(trackName)
	        val artist = normalizeLookupText(artistName)
	        val album = normalizeLookupText(albumName)
	        val resolvedAlbumArtist = normalizeLookupText(
	            albumArtist?.takeIf { it.trim().isNotEmpty() } ?: artistName,
	        )
	        values.put("album_key", "$album|$resolvedAlbumArtist")
	        values.put(
	            "search_text",
	            listOf(track, artist, album, resolvedAlbumArtist)
	                .filter { it.isNotEmpty() }
	                .joinToString(" "),
	        )
	    }

	    private fun normalizeLookupText(value: String?): String =
	        cleanMetadataString(value).lowercase(Locale.ROOT)

	    private fun normalizeSpotifyId(value: String?): String =
	        cleanMetadataString(value).lowercase(Locale.ROOT)

	    private fun normalizeIsrc(value: String?): String =
	        cleanMetadataString(value)
	            .uppercase(Locale.ROOT)
	            .replace(Regex("[-\\s]"), "")

	    private fun matchKeyFor(trackName: String?, artistName: String?): String {
	        val track = normalizeLookupText(trackName)
	        if (track.isEmpty()) return ""
	        return "$track|${normalizeLookupText(artistName)}"
	    }

	    private fun buildPathMatchKeys(filePath: String?): Set<String> {
	        val raw = filePath?.trim().orEmpty()
	        if (raw.isEmpty()) return emptySet()
	        val cleaned = if (raw.startsWith("EXISTS:")) raw.substring(7).trim() else raw
	        if (cleaned.isEmpty()) return emptySet()

	        val keys = linkedSetOf<String>()
	        val visited = linkedSetOf<String>()

	        fun addNormalized(value: String) {
	            val trimmed = value.trim()
	            if (trimmed.isEmpty()) return
	            if (!visited.add(trimmed)) return

	            keys.add(trimmed)
	            keys.add(trimmed.lowercase(Locale.ROOT))

	            if (trimmed.contains('\\')) {
	                val slash = trimmed.replace('\\', '/')
	                if (slash != trimmed) addNormalized(slash)
	            }

	            if (trimmed.contains('%')) {
	                try {
	                    val decoded = Uri.decode(trimmed)
	                    if (decoded != trimmed) addNormalized(decoded)
	                } catch (_: Throwable) {
	                }
	            }

	            val parsed = try {
	                Uri.parse(trimmed)
	            } catch (_: Throwable) {
	                null
	            }
	            if (parsed != null && !parsed.scheme.isNullOrEmpty()) {
	                val stripped = stripUriQueryAndFragment(trimmed)
	                keys.add(stripped)
	                keys.add(stripped.lowercase(Locale.ROOT))
	                if (parsed.scheme.equals("file", ignoreCase = true)) {
	                    parsed.path?.let { addNormalized(it) }
	                }
	            } else if (trimmed.startsWith("/")) {
	                try {
	                    val asFileUri = Uri.fromFile(File(trimmed)).toString()
	                    keys.add(asFileUri)
	                    keys.add(asFileUri.lowercase(Locale.ROOT))
	                } catch (_: Throwable) {
	                }
	            }

	            for (alias in androidEquivalentPaths(trimmed)) {
	                if (alias != trimmed) addNormalized(alias)
	            }
	        }

	        addNormalized(cleaned)

	        val extensionStripped = linkedSetOf<String>()
	        for (key in keys) {
	            stripAudioExtension(key)?.let {
	                if (it.isNotEmpty()) extensionStripped.add(it)
	            }
	        }
	        keys.addAll(extensionStripped)
	        return keys
	    }

	    private fun stripUriQueryAndFragment(value: String): String {
	        val queryIndex = value.indexOf('?').let { if (it >= 0) it else value.length }
	        val fragmentIndex = value.indexOf('#').let { if (it >= 0) it else value.length }
	        val cut = minOf(queryIndex, fragmentIndex)
	        return value.substring(0, cut)
	    }

	    private fun stripAudioExtension(path: String): String? {
	        val lower = path.lowercase(Locale.ROOT)
	        for (ext in audioExtensions) {
	            if (lower.endsWith(ext)) {
	                return path.substring(0, path.length - ext.length)
	            }
	        }
	        return null
	    }

	    private fun androidEquivalentPaths(path: String): List<String> {
	        val normalized = path.replace('\\', '/')
	        val lower = normalized.lowercase(Locale.ROOT)
	        var suffix: String? = null
	        for (prefix in androidStoragePathAliases) {
	            if (lower == prefix) {
	                suffix = ""
	                break
	            }
	            val withSlash = "$prefix/"
	            if (lower.startsWith(withSlash)) {
	                suffix = normalized.substring(prefix.length)
	                break
	            }
	        }
	        val resolvedSuffix = suffix ?: return emptyList()
	        return androidStoragePathAliases.map { "$it$resolvedSuffix" }
	    }

	    private fun android.database.Cursor.getNullableString(index: Int): String? {
	        if (index < 0 || isNull(index)) return null
	        return getString(index)
	    }

    private fun ensureHistoryColumn(db: SQLiteDatabase, column: String, alterSql: String) {
        db.rawQuery("PRAGMA table_info(history)", null).use { cursor ->
            val nameIndex = cursor.getColumnIndex("name")
            while (cursor.moveToNext()) {
                if (nameIndex >= 0 && cursor.getString(nameIndex).equals(column, ignoreCase = true)) {
                    return
                }
            }
        }
        db.execSQL(alterSql)
    }

    private fun historyToJson(values: ContentValues): JSONObject {
        val json = JSONObject()
        fun putCamel(column: String, key: String) {
            if (values.containsKey(column)) json.put(key, values.get(column))
        }
        putCamel("id", "id")
        putCamel("track_name", "trackName")
        putCamel("artist_name", "artistName")
        putCamel("album_name", "albumName")
        putCamel("album_artist", "albumArtist")
        putCamel("cover_url", "coverUrl")
        putCamel("file_path", "filePath")
        putCamel("storage_mode", "storageMode")
        putCamel("download_tree_uri", "downloadTreeUri")
        putCamel("saf_relative_dir", "safRelativeDir")
        putCamel("saf_file_name", "safFileName")
        json.put("safRepaired", values.getAsInteger("saf_repaired") == 1)
        putCamel("service", "service")
        putCamel("downloaded_at", "downloadedAt")
        putCamel("isrc", "isrc")
        putCamel("spotify_id", "spotifyId")
        putCamel("track_number", "trackNumber")
        putCamel("total_tracks", "totalTracks")
        putCamel("disc_number", "discNumber")
        putCamel("total_discs", "totalDiscs")
        putCamel("duration", "duration")
        putCamel("release_date", "releaseDate")
        putCamel("quality", "quality")
        putCamel("bit_depth", "bitDepth")
        putCamel("sample_rate", "sampleRate")
        putCamel("bitrate", "bitrate")
        putCamel("format", "format")
        putCamel("genre", "genre")
        putCamel("composer", "composer")
        putCamel("label", "label")
        putCamel("copyright", "copyright")
        return json
    }

    internal fun trackString(input: FinalizeInput, key: String, fallback: String): String =
        cleanMetadataString(input.track.optString(key, "")).ifBlank { cleanMetadataString(fallback) }

    internal fun requestString(input: FinalizeInput, key: String): String =
        cleanMetadataString(input.request.optString(key, ""))

    internal fun resultString(input: FinalizeInput, key: String): String =
        cleanMetadataString(input.result.optString(key, ""))

    internal fun metadataCoverUrl(input: FinalizeInput): String =
        trackString(input, "coverUrl", requestString(input, "cover_url"))

    internal fun trackInt(input: FinalizeInput, key: String, fallback: Int): Int {
        val value = input.track.optInt(key, 0)
        return if (value > 0) value else fallback
    }

    private fun optPositiveInt(obj: JSONObject, key: String): Int? {
        val value = obj.optInt(key, 0)
        return if (value > 0) value else null
    }

    private fun optPositiveBitrateKbps(obj: JSONObject, key: String): Int? {
        val value = optPositiveInt(obj, key) ?: return null
        val kbps = if (value >= 10000) {
            Math.round(value / 1000.0).toInt()
        } else {
            value
        }
        return if (kbps >= 16) kbps else null
    }

    internal fun positiveOrNull(primary: Int, fallback: Int): Int? {
        val value = if (primary > 0) primary else fallback
        return if (value > 0) value else null
    }

    private fun normalizeOptional(value: String?): String? {
        val trimmed = cleanMetadataString(value)
        return trimmed.ifBlank { null }
    }

    private fun cleanMetadataString(value: String?): String {
        val trimmed = value?.trim().orEmpty()
        return if (trimmed.equals("null", ignoreCase = true)) "" else trimmed
    }

    internal fun q(value: String): String = "\"${value.replace("\"", "\\\"")}\""
}
