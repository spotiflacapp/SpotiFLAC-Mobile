package com.zarz.spotiflac.missingtracks

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
import com.zarz.spotiflac.missingtracks.SafDownloadHandler.mimeTypeForExt
import com.zarz.spotiflac.missingtracks.SafDownloadHandler.normalizeExt
import com.zarz.spotiflac.missingtracks.NativeFinalizationPolicy.applyQualityVariantFilenameLabel
import com.zarz.spotiflac.missingtracks.NativeFinalizationPolicy.displayAudioQuality
import com.zarz.spotiflac.missingtracks.NativeFinalizationPolicy.formatIndexTag
import com.zarz.spotiflac.missingtracks.NativeFinalizationPolicy.normalizeAudioCodec
import com.zarz.spotiflac.missingtracks.NativeFinalizationPolicy.resolvePreferredDecryptionExtension
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.util.Locale
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.pow

object NativeDownloadFinalizer {
    internal const val TAG = "NativeFinalizer"
    const val NATIVE_WORKER_CONTRACT_VERSION = 1
    // Native finalizer owns background-safe history writes while Flutter may be suspended.
    // Keep this schema contract in sync with Dart HistoryDatabase before bumping either side.
    const val HISTORY_SCHEMA_VERSION = 14
    // Keep one native connection for the process. Opening history.db and
    // probing/migrating its schema for every finalized track was expensive,
    // and a single guarded writer also prevents native finalizer calls from
    // interleaving transactions on the same connection. Flutter/sqflite uses
    // its own WAL connection, so the busy timeout remains configured once on
    // this connection for cross-connection contention.
    private val historyDatabaseLock = Any()
    private var historyDatabase: SQLiteDatabase? = null
    private var historyDatabasePath = ""
    private var historyDatabaseSchemaVersion = 0
    internal val activeFFmpegSessionIds = mutableSetOf<Long>()
    internal val nativeFFmpegSessionIds = BoundedRegistry<Long>(maxEntries = 256)
    internal val activeFFmpegSessionLock = Any()
    internal val ffmpegCompleteCallbackLock = Any()
    internal val qualityVariantNameLocks = KeyedLockPool<String>()
    internal var forwardedFFmpegCompleteCallback: FFmpegSessionCompleteCallback? = null
    internal val nativeFilteringFFmpegCompleteCallback = FFmpegSessionCompleteCallback { session ->
        val isNativeSession = nativeFFmpegSessionIds.consume(session.sessionId)
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
        "explicit",
        "has_lyrics",
        "lyrics_metadata_scan_version",
        "has_replaygain",
        "replaygain_metadata_scan_version",
        "spotify_id_norm",
        "isrc_norm",
        "match_key",
        "album_key",
        "search_text",
        "sort_track",
        "sort_artist",
        "sort_album",
        "sort_album_artist",
        "sort_genre",
        "sort_release",
        "sort_added",
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
        var lyricsMetadataScanned: Boolean = false,
        var hasEmbeddedLyrics: Boolean = false,
        var externalLrcWritten: Boolean = false,
        var replayGainMetadataScanned: Boolean = false,
        var hasReplayGain: Boolean = false,
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

    private inline fun <T> timedStage(name: String, block: () -> T): T {
        val started = System.nanoTime()
        try {
            return block()
        } finally {
            Log.d(TAG, "Finalization stage $name took ${(System.nanoTime() - started) / 1_000_000}ms")
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
        if (result.optBoolean("saf_deferred_publish", false) && result.has("saf_relative_dir")) {
            requestObject.put("saf_relative_dir", result.getString("saf_relative_dir"))
        }
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
                timedStage("container conversion") {
                    finalizeContainerConversion(context, effectiveInput, state, shouldCancel)
                }
                checkCancelled(shouldCancel)
                timedStage("metadata") {
                    finalizeMetadata(context, effectiveInput, state)
                }
                checkCancelled(shouldCancel)
                timedStage("extension post-processing") {
                    runPostProcessing(context, effectiveInput, state, shouldCancel)
                }
                checkCancelled(shouldCancel)
                try {
                    timedStage("automatic conversion") {
                        finalizeAutoConversion(
                            context,
                            effectiveInput,
                            state,
                            shouldCancel,
                        )
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // Auto-conversion is best effort: a completed source file
                    // must remain usable if FFmpeg or metadata embedding fails.
                    Log.w(TAG, "Automatic conversion failed; keeping source: ${e.message}")
                    result.put("auto_conversion_warning", e.message ?: "conversion failed")
                }
                checkCancelled(shouldCancel)
                try {
                    val replayGain = timedStage("ReplayGain") {
                        writeReplayGain(context, effectiveInput, state, shouldCancel)
                    }
                    if (replayGain != null) {
                        result.put("replaygain", replayGain)
                        state.replayGainMetadataScanned = true
                        state.hasReplayGain = true
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // Gain tagging is optional; keep the completed audio if
                    // its native editor or the verification step fails.
                    Log.w(TAG, "ReplayGain write failed: ${e.message}")
                    result.put("replaygain_warning", e.message ?: "ReplayGain write failed")
                }
                checkCancelled(shouldCancel)
                try {
                    timedStage("quality probe") {
                        refreshFinalAudioQualityMetadata(context, result, state)
                    }
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
                timedStage("publish") {
                    if (isDeferredSafPublish(effectiveInput)) {
                        publishDeferredSafOutput(context, effectiveInput, state)
                    } else {
                        promoteStagedSafOutputIfNeeded(context, effectiveInput, state)
                    }
                }
                outputPublished = true
            } else {
                // Match the Dart queue: an existing download still runs enabled
                // extension hooks. It may be the input left by an interrupted
                // finalizer, so file existence does not prove the hook finished.
                // outputPublished keeps this pre-existing input out of cleanup.
                checkCancelled(shouldCancel)
                runPostProcessing(context, effectiveInput, state, shouldCancel)
                checkCancelled(shouldCancel)
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
        return normalizeExt(ext.ifBlank { ".flac" })
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

            val rawDecryptedPath = successPath ?: throw IllegalStateException("decrypt failed: $lastOutput")
            val decryptedPath = normalizeDecryptedIsoBmffAudioPath(
                rawDecryptedPath,
                state,
                shouldCancel,
            )
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

    private fun normalizeDecryptedIsoBmffAudioPath(
        path: String,
        state: FinalizeState,
        shouldCancel: () -> Boolean,
    ): String {
        if (!isMP4ContainerFile(path)) return path

        val probedCodec = probePrimaryAudioCodec(path, shouldCancel)
        val codec = normalizeAudioCodec(probedCodec.ifBlank { state.audioCodec.orEmpty() })
        val desiredExt = NativeFinalizationPolicy.isoBmffAudioExtension(codec)
        state.audioCodec = codec
        if (path.lowercase(Locale.ROOT).endsWith(desiredExt)) return path

        val target = File(buildOutputPath(path, desiredExt))
        if (target.exists()) {
            Log.w(TAG, "Cannot normalize ISO-BMFF audio extension; ${target.name} already exists")
            return path
        }
        val source = File(path)
        if (!source.renameTo(target)) {
            Log.w(TAG, "Failed to normalize ISO-BMFF audio extension to ${target.name}")
            return path
        }
        Log.i(
            TAG,
            "ISO-BMFF audio renamed: ${source.name} -> ${target.name} " +
                "(codec=${codec.orEmpty().ifBlank { "unknown" }})",
        )
        return target.absolutePath
    }

    private fun finalizeAutoConversion(
        context: Context,
        input: FinalizeInput,
        state: FinalizeState,
        shouldCancel: () -> Boolean,
    ) {
        val target = NativeFinalizationPolicy.autoConversionTarget(
            enabled = input.request.optBoolean("auto_convert_downloads", false),
            format = input.request.optString("auto_convert_format", ""),
            bitrate = input.request.optString("auto_convert_bitrate", ""),
        ) ?: return
        if (
            NativeFinalizationPolicy.autoConversionAlreadySatisfied(
                target,
                state.audioCodec,
                state.bitrateKbps,
            )
        ) return

        val localInput = materializeForFFmpeg(context, input, state)
        val sourceWasSaf = state.filePath.startsWith("content://")
        val sameLocalExtension = !sourceWasSaf &&
            normalizeExt(File(localInput).extension) == target.extension
        val output = if (sameLocalExtension) {
            buildOutputPath(localInput, target.extension)
        } else {
            uniqueAutoConversionOutputPath(localInput, target.extension)
        }
        val stagedOutput = stagedConversionPath(output)
        val bitrate = "${target.bitrateKbps}k"
        var adoptedOutput = false
        try {
            val command = when (target.codec) {
                "opus" -> "-v error -hide_banner -i ${q(localInput)} -codec:a libopus -b:a $bitrate -vbr on -compression_level 10 -map 0:a ${q(stagedOutput)} -y"
                "aac" -> "-v error -hide_banner -i ${q(localInput)} -codec:a aac -b:a $bitrate -map 0:a -f mp4 ${q(stagedOutput)} -y"
                else -> "-v error -hide_banner -i ${q(localInput)} -codec:a libmp3lame -b:a $bitrate -map 0:a -id3v2_version 3 ${q(stagedOutput)} -y"
            }
            val conversion = runFFmpeg(command, shouldCancel)
            if (!conversion.first || !File(stagedOutput).exists()) {
                throw IllegalStateException("automatic conversion failed: ${conversion.second}")
            }
            if (!promoteStagedConversion(stagedOutput, output)) {
                throw IllegalStateException("failed to promote automatic conversion output")
            }

            val metadataFormat = if (target.codec == "aac") "m4a" else target.codec
            embedBasicMetadata(context, output, input, metadataFormat)

            if (sameLocalExtension) {
                replaceSameFormatLocalOutput(localInput, output)
                state.filePath = localInput
                state.fileName = File(localInput).name
            } else {
                replaceStatePath(context, input, state, output, deleteOld = true)
            }
            adoptedOutput = true
        } finally {
            if (!adoptedOutput) {
                File(stagedOutput).delete()
                File(output).delete()
            }
            if (sourceWasSaf) File(localInput).delete()
        }

        state.quality = "${if (target.codec == "aac") "AAC" else target.codec.uppercase(Locale.ROOT)} ${target.bitrateKbps}kbps"
        state.bitDepth = null
        state.sampleRate = null
        state.bitrateKbps = target.bitrateKbps
        state.audioCodec = target.codec
    }

    private fun replaceSameFormatLocalOutput(inputPath: String, convertedPath: String) {
        val source = File(inputPath)
        val converted = File(convertedPath)
        val backup = File("$inputPath.spotiflac-backup-${System.nanoTime()}")
        if (!source.renameTo(backup)) {
            throw IllegalStateException("failed to stage original for same-format conversion")
        }
        try {
            if (!converted.renameTo(source)) {
                throw IllegalStateException("failed to publish same-format conversion")
            }
            backup.delete()
        } catch (e: Exception) {
            if (!source.exists()) backup.renameTo(source)
            throw e
        }
    }

    private fun uniqueAutoConversionOutputPath(inputPath: String, extension: String): String {
        val source = File(inputPath)
        val requested = File(source.parentFile, "${source.nameWithoutExtension}$extension")
        if (!requested.exists()) return requested.absolutePath
        for (index in 2..Int.MAX_VALUE) {
            val candidate = File(
                source.parentFile,
                "${source.nameWithoutExtension} ($index)$extension",
            )
            if (!candidate.exists()) return candidate.absolutePath
        }
        throw IllegalStateException("could not allocate automatic conversion output")
    }

    private fun finalizeContainerConversion(
        context: Context,
        input: FinalizeInput,
        state: FinalizeState,
        shouldCancel: () -> Boolean,
    ) {
        if (outputExt(input) != ".flac") return
        val requestedDecryptionExt = requestedDecryptionOutputExt(input)
        val forceContainerConversion = shouldForceContainerConversion(input, state)
        if (!forceContainerConversion && requestedDecryptionExt.isNotBlank() && requestedDecryptionExt != ".flac") return
        val mayNeedContainerConversion = forceContainerConversion ||
            looksLikeM4a(state.filePath, state.fileName) ||
            isMP4ContainerFile(state.filePath) ||
            state.filePath.startsWith("content://")
        if (!mayNeedContainerConversion) return

        val localInput = materializeForFFmpeg(context, input, state)
        val deleteLocalInput = state.filePath.startsWith("content://")
        val output = buildOutputPath(localInput, ".flac")
        val stagedOutput = stagedConversionPath(output)
        var adoptedOutput = false
        var createdOutput = false
        try {
            val codec = probePrimaryAudioCodec(localInput, shouldCancel)
            val isAlreadyNativeFlac = codec == "flac" && isNativeFlacFile(localInput)
            if (!NativeFinalizationPolicy.shouldAttemptLosslessContainerConversion(
                    forceContainerConversion,
                    codec,
                )
            ) {
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
                    createdOutput = true
                    output
                }
                embedBasicMetadata(context, nativeFlacOutput, input, "flac")
                replaceStatePath(context, input, state, nativeFlacOutput, deleteOld = true)
                adoptedOutput = true
                return
            }
            convertToStagedFlac(
                input = localInput,
                stagedOutput = stagedOutput,
                codec = codec,
                execute = { arguments -> runFFmpegArguments(arguments, shouldCancel) },
                checkCancelled = { checkCancelled(shouldCancel) },
            )
            if (!promoteStagedConversion(stagedOutput, output)) {
                throw IllegalStateException("failed to publish container conversion output")
            }
            createdOutput = true
            // Keep metadata failures before adoption so the source survives
            // and the unsuccessful output is removed by the local cleanup.
            embedBasicMetadata(context, output, input, "flac")
            replaceStatePath(context, input, state, output, deleteOld = true)
            adoptedOutput = true
        } finally {
            if (!adoptedOutput) {
                File(stagedOutput).delete()
                if (createdOutput && output != localInput) File(output).delete()
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
            isMP4ContainerFile(localInput) ->
                NativeFinalizationPolicy.isoBmffAudioExtension(codec)
            codec == "mp3" -> ".mp3"
            codec == "opus" -> ".opus"
            else -> return
        }
        val renamed = File(uniqueAutoConversionOutputPath(currentFile.path, newExt))
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
        if (
            fileExt != ".flac" &&
            fileExt != ".m4a" &&
            fileExt != ".mp4" &&
            fileExt != ".mp3" &&
            fileExt != ".opus" &&
            fileExt != ".ogg"
        ) return null

        val scanPath = if (state.filePath.startsWith("content://")) {
            SafDownloadHandler.copyContentUriToTemp(context, state.filePath)
                ?: throw IllegalStateException("failed to copy SAF file for ReplayGain")
        } else {
            state.filePath
        }
        val deleteScanPath = scanPath != state.filePath
        val scan = try {
            scanReplayGain(scanPath, shouldCancel)
                ?: throw IllegalStateException("ReplayGain analysis produced no valid measurement")
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
            writeLocalReplayGainFields(context, path, fields)
            return
        }

        val tempPath = SafDownloadHandler.copyContentUriToTemp(context, path)
            ?: throw IllegalStateException("failed to copy SAF file for ReplayGain write")
        try {
            writeLocalReplayGainFields(context, tempPath, fields)
            val uri = Uri.parse(path)
            context.contentResolver.openOutputStream(uri, "wt")?.use { output ->
                File(tempPath).inputStream().use { input -> input.copyTo(output) }
                SafDownloadHandler.syncOutputStream(output)
            } ?: throw IllegalStateException("failed to write ReplayGain back to SAF")
        } finally {
            File(tempPath).delete()
        }
    }

    private fun writeLocalReplayGainFields(context: Context, path: String, fields: JSONObject) {
        val backend = createCoreBackend(context)
        val result = parseObject(backend.editFileMetadata(path, fields.toString()))
        val method = result.optString("method", "")
        check(
            result.optBoolean("success", false) &&
                !result.has("error") &&
                (method == "native" || method.startsWith("native_")),
        ) { "ReplayGain native write did not complete: $result" }

        val metadata = parseObject(backend.readFileMetadata(path, ""))
        check(!metadata.has("error")) { "ReplayGain verification failed: $metadata" }
        val isOpus = metadata.optString("audio_codec", "") == "opus"
        for (key in fields.keys()) {
            // Opus stores only R128 gain, exposed by the Go reader as dB.
            if (isOpus && key.endsWith("_peak")) continue
            val expected = fields.optString(key, "").trim().removeSuffix("dB").trim().toDoubleOrNull()
            val actual = metadata.optString(key, "").trim().removeSuffix("dB").trim().toDoubleOrNull()
            val tolerance = if (key.endsWith("_gain")) 0.01 else 0.000001
            check(expected != null && actual != null && abs(actual - expected) <= tolerance) {
                "ReplayGain verification failed for $key"
            }
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
            val metadata = parseObject(createCoreBackend(context).readFileMetadata(probePath, state.fileName))
            if (metadata.has("error")) return

            if (!metadata.optBoolean("metadataFromFilename", false) &&
                (metadata.has("audio_codec") || metadata.has("format") ||
                    metadata.has("replaygain_track_gain") || metadata.has("replaygain_album_gain"))
            ) {
                state.replayGainMetadataScanned = true
                state.hasReplayGain = listOf("replaygain_track_gain", "replaygain_album_gain").any { key ->
                    val value = metadata.optString(key, "").trim()
                    val gain = (if (value.endsWith("dB", ignoreCase = true)) value.dropLast(2) else value)
                        .trim().toDoubleOrNull()
                    gain != null && gain.isFinite()
                }
            }

            if (metadata.has("lyrics") || metadata.has("hasLyrics")) {
                state.lyricsMetadataScanned = true
                state.hasEmbeddedLyrics =
                    metadata.optBoolean("hasLyrics", false) ||
                    NativeFinalizationPolicy.hasUsableLyricsContent(
                        metadata.optString("lyrics", ""),
                    )
            }

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
            .put(
                "album_artist",
                NativeFinalizationPolicy.authoritativeAlbumArtist(
                    requestValue = requestString(input, "album_artist"),
                    trackValue = trackString(input, "albumArtist", ""),
                    providerResultValue = resultString(input, "album_artist"),
                ),
            )
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
                    .put("item_id", input.itemId)
                    .put("path", tempInput)
                    .put("uri", uri)
                    .put("name", state.fileName)
                    .put("mime_type", mimeTypeForExt(state.fileName.substringAfterLast('.', "")))
                    .put("size", File(tempInput).length())
                    .put("is_saf", true)
                checkCancelled(shouldCancel)
                val response = JSONObject(createCoreBackend(context).runPostProcessing(inputObj.toString(), metadata.toString()))
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
            .put("item_id", input.itemId)
            .put("path", state.filePath)
            .put("name", state.fileName)
            .put("is_saf", false)
        checkCancelled(shouldCancel)
        val response = JSONObject(createCoreBackend(context).runPostProcessing(inputObj.toString(), metadata.toString()))
        checkCancelled(shouldCancel)
        if (response.optBoolean("success", false)) {
            val newPath = response.optString("new_file_path", "")
            if (newPath.isNotBlank() && newPath != state.filePath) {
                if (isDeferredSafPublish(input)) {
                    val output = File(newPath)
                    check(output.isFile && output.length() > 0L) {
                        "post-processing output missing or empty"
                    }
                    // This input is an owned staging file; publication later
                    // removes the replacement, so retire the old stage now.
                    File(state.filePath).delete()
                }
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
        val albumArtist = NativeFinalizationPolicy.authoritativeAlbumArtist(
            requestValue = requestString(input, "album_artist"),
            trackValue = trackString(input, "albumArtist", ""),
            providerResultValue = resultString(input, "album_artist"),
        )
        return "name:$albumName|$albumArtist"
    }

    private fun replayGainDurationSeconds(input: FinalizeInput): Double {
        val duration = NativeFinalizationPolicy.durationMilliseconds(
            input.request.optLong("duration_ms", 0L),
            trackInt(input, "duration", 0).toLong(),
        )
        return if (duration > 0L) duration / 1000.0 else 1.0
    }

    private fun buildHistoryRow(input: FinalizeInput, state: FinalizeState): ContentValues {
        val result = input.result
        val values = ContentValues()
        values.put("id", input.itemId)
        values.put("track_name", result.optString("title", "").ifBlank { trackString(input, "name", input.request.optString("track_name", "")) })
        values.put("artist_name", result.optString("artist", "").ifBlank { trackString(input, "artistName", input.request.optString("artist_name", "")) })
        values.put("album_name", result.optString("album", "").ifBlank { trackString(input, "albumName", input.request.optString("album_name", "")) })
        values.put(
            "album_artist",
            normalizeOptional(
                NativeFinalizationPolicy.authoritativeAlbumArtist(
                    requestValue = requestString(input, "album_artist"),
                    trackValue = trackString(input, "albumArtist", ""),
                    providerResultValue = resultString(input, "album_artist"),
                ),
            ),
        )
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
        values.put(
            "explicit",
            if (
                result.optBoolean("explicit", false) ||
                    input.track.optBoolean("explicit", false) ||
                    input.request.optBoolean("explicit", false)
            ) 1 else 0,
        )
        values.put(
            "has_lyrics",
            if (state.hasEmbeddedLyrics || state.externalLrcWritten) 1 else 0,
        )
        values.put(
            "lyrics_metadata_scan_version",
            if (
                state.lyricsMetadataScanned ||
                state.hasEmbeddedLyrics ||
                state.externalLrcWritten
            ) 1 else 0,
        )
        putNormalizedHistoryColumns(values)
        values.put("has_replaygain", if (state.hasReplayGain) 1 else 0)
        values.put("replaygain_metadata_scan_version", if (state.replayGainMetadataScanned) 1 else 0)
        return values
    }

    private fun upsertHistory(
        context: Context,
        values: ContentValues,
        deduplicateTrack: Boolean = true,
    ) {
        withHistoryDatabase(context) { db ->
            val initializeSchema = historyDatabaseSchemaVersion != HISTORY_SCHEMA_VERSION
            db.beginTransaction()
            try {
                if (initializeSchema) {
                    if (db.version > HISTORY_SCHEMA_VERSION) {
                        throw IllegalStateException(
                            "history schema v${db.version} is newer than native finalizer contract v$HISTORY_SCHEMA_VERSION"
                        )
                    }
                    // v14 only adds gain flags; v13 already has normalized keys.
                    // Avoid walking the entire history for this additive upgrade.
                    val needsBackfill = db.version < 13
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
                      explicit INTEGER NOT NULL DEFAULT 0,
                      has_lyrics INTEGER NOT NULL DEFAULT 0,
                      lyrics_metadata_scan_version INTEGER NOT NULL DEFAULT 0,
                      has_replaygain INTEGER NOT NULL DEFAULT 0,
                      replaygain_metadata_scan_version INTEGER NOT NULL DEFAULT 0,
                      spotify_id_norm TEXT,
                      isrc_norm TEXT,
                      match_key TEXT,
                      album_key TEXT,
                      search_text TEXT,
                      sort_track TEXT,
                      sort_artist TEXT,
                      sort_album TEXT,
                      sort_album_artist TEXT,
                      sort_genre TEXT,
                      sort_release TEXT,
                      sort_added INTEGER
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
	                ensureHistoryColumn(db, "sort_track", "ALTER TABLE history ADD COLUMN sort_track TEXT")
	                ensureHistoryColumn(db, "sort_artist", "ALTER TABLE history ADD COLUMN sort_artist TEXT")
	                ensureHistoryColumn(db, "sort_album", "ALTER TABLE history ADD COLUMN sort_album TEXT")
	                ensureHistoryColumn(db, "sort_album_artist", "ALTER TABLE history ADD COLUMN sort_album_artist TEXT")
	                ensureHistoryColumn(db, "sort_genre", "ALTER TABLE history ADD COLUMN sort_genre TEXT")
	                ensureHistoryColumn(db, "sort_release", "ALTER TABLE history ADD COLUMN sort_release TEXT")
	                ensureHistoryColumn(db, "sort_added", "ALTER TABLE history ADD COLUMN sort_added INTEGER")
	                ensureHistoryColumn(db, "explicit", "ALTER TABLE history ADD COLUMN explicit INTEGER NOT NULL DEFAULT 0")
	                ensureHistoryColumn(db, "has_lyrics", "ALTER TABLE history ADD COLUMN has_lyrics INTEGER NOT NULL DEFAULT 0")
	                ensureHistoryColumn(db, "lyrics_metadata_scan_version", "ALTER TABLE history ADD COLUMN lyrics_metadata_scan_version INTEGER NOT NULL DEFAULT 0")
	                ensureHistoryColumn(db, "has_replaygain", "ALTER TABLE history ADD COLUMN has_replaygain INTEGER NOT NULL DEFAULT 0")
	                ensureHistoryColumn(db, "replaygain_metadata_scan_version", "ALTER TABLE history ADD COLUMN replaygain_metadata_scan_version INTEGER NOT NULL DEFAULT 0")
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
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_history_queue_added ON history(sort_added DESC, sort_track, id)")
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_history_queue_track ON history(sort_track, sort_artist, id)")
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_history_queue_artist ON history(sort_artist, sort_track, id)")
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_history_queue_album ON history(sort_album, sort_track, id)")
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_history_queue_genre ON history(sort_genre, sort_track, id)")
	                db.execSQL("CREATE INDEX IF NOT EXISTS idx_history_queue_release ON history(sort_release, sort_track, id)")
                    if (db.version < HISTORY_SCHEMA_VERSION) db.version = HISTORY_SCHEMA_VERSION
                }
                if (deduplicateTrack) deleteDuplicateHistoryRows(db, values)
                db.insertWithOnConflict("history", null, values, SQLiteDatabase.CONFLICT_REPLACE)
                replaceHistoryPathKeys(db, values.getAsString("id"), values.getAsString("file_path"))
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
            if (initializeSchema) {
                historyDatabaseSchemaVersion = HISTORY_SCHEMA_VERSION
            }
        }
    }

    private inline fun <T> withHistoryDatabase(
        context: Context,
        block: (SQLiteDatabase) -> T,
    ): T {
        synchronized(historyDatabaseLock) {
            val dbFile = File(File(context.applicationInfo.dataDir, "app_flutter"), "history.db")
            dbFile.parentFile?.mkdirs()
            val db = historyDatabase?.takeIf {
                it.isOpen && historyDatabasePath == dbFile.absolutePath
            } ?: run {
                historyDatabase?.close()
                val opened = SQLiteDatabase.openDatabase(
                    dbFile.absolutePath,
                    null,
                    SQLiteDatabase.OPEN_READWRITE or
                        SQLiteDatabase.CREATE_IF_NECESSARY or
                        SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING,
                )
                try {
                    configureHistoryDatabase(opened)
                } catch (e: Exception) {
                    opened.close()
                    throw e
                }
                historyDatabase = opened
                historyDatabasePath = dbFile.absolutePath
                historyDatabaseSchemaVersion = 0
                opened
            }
            historyDatabase = db
            return block(db)
        }
    }

    private fun configureHistoryDatabase(db: SQLiteDatabase) {
        runHistoryPragma(db, "PRAGMA busy_timeout = 5000", required = false)
        // CONFLICT_REPLACE must fire the history delete trigger so the
        // external-content FTS index does not retain the replaced rowid.
        runHistoryPragma(db, "PRAGMA recursive_triggers = ON", required = false)
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
	            arrayOf("id", "spotify_id", "isrc", "track_name", "artist_name", "album_name", "album_artist", "genre", "release_date", "downloaded_at"),
	            "spotify_id_norm IS NULL OR isrc_norm IS NULL OR match_key IS NULL OR album_key IS NULL OR search_text IS NULL OR sort_track IS NULL OR sort_release IS NULL OR sort_added IS NULL",
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
	            val genreIndex = cursor.getColumnIndex("genre")
	            val releaseDateIndex = cursor.getColumnIndex("release_date")
	            val downloadedAtIndex = cursor.getColumnIndex("downloaded_at")
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
	                putQueueSortHistoryColumns(
	                    values,
	                    trackName = trackName,
	                    artistName = artistName,
	                    albumName = albumName,
	                    albumArtist = albumArtist,
	                    genre = cursor.getNullableString(genreIndex),
	                    releaseDate = cursor.getNullableString(releaseDateIndex),
	                    downloadedAt = cursor.getNullableString(downloadedAtIndex),
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
	        putQueueSortHistoryColumns(
	            values,
	            trackName = values.getAsString("track_name"),
	            artistName = values.getAsString("artist_name"),
	            albumName = values.getAsString("album_name"),
	            albumArtist = values.getAsString("album_artist"),
	            genre = values.getAsString("genre"),
	            releaseDate = values.getAsString("release_date"),
	            downloadedAt = values.getAsString("downloaded_at"),
	        )
	    }

	    private fun putQueueSortHistoryColumns(
	        values: ContentValues,
	        trackName: String?,
	        artistName: String?,
	        albumName: String?,
	        albumArtist: String?,
	        genre: String?,
	        releaseDate: String?,
	        downloadedAt: String?,
	    ) {
	        values.put("sort_track", normalizeLookupText(trackName))
	        values.put("sort_artist", normalizeLookupText(artistName))
	        values.put("sort_album", normalizeLookupText(albumName))
	        values.put(
	            "sort_album_artist",
	            normalizeLookupText(albumArtist?.takeIf { it.trim().isNotEmpty() } ?: artistName),
	        )
	        values.put("sort_genre", normalizeLookupText(genre))
	        values.put("sort_release", releaseDate?.trim().orEmpty())
	        val sortAdded = parseHistoryTimestampMillis(downloadedAt)
	        values.put("sort_added", sortAdded)
	    }

	    private fun parseHistoryTimestampMillis(value: String?): Long {
	        val timestamp = value?.trim().orEmpty()
	        if (timestamp.isEmpty()) return 0L
	        return try {
	            java.time.Instant.parse(timestamp).toEpochMilli()
	        } catch (_: Exception) {
	            try {
	                java.time.OffsetDateTime.parse(timestamp).toInstant().toEpochMilli()
	            } catch (_: Exception) {
	                try {
	                    java.time.LocalDateTime.parse(timestamp)
	                        .atZone(java.time.ZoneId.systemDefault())
	                        .toInstant()
	                        .toEpochMilli()
	                } catch (_: Exception) {
	                    0L
	                }
	            }
	        }
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
	                for (alias in androidExternalStorageDocumentPaths(parsed)) {
	                    addNormalized(alias)
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

	    private fun androidExternalStorageDocumentPaths(uri: Uri): List<String> {
	        if (
	            !uri.scheme.equals("content", ignoreCase = true) ||
	            !uri.authority.equals(
	                "com.android.externalstorage.documents",
	                ignoreCase = true,
	            )
	        ) {
	            return emptyList()
	        }

	        val segments = uri.pathSegments
	        val documentIndex = segments.indexOfLast { it == "document" }
	        val treeIndex = segments.indexOfLast { it == "tree" }
	        val idIndex = if (documentIndex >= 0) documentIndex + 1 else treeIndex + 1
	        if (idIndex <= 0 || idIndex >= segments.size) return emptyList()

	        val documentId = segments.subList(idIndex, segments.size).joinToString("/")
	        val separator = documentId.indexOf(':')
	        if (
	            separator < 0 ||
	            !documentId.substring(0, separator).equals("primary", ignoreCase = true)
	        ) {
	            return emptyList()
	        }

	        val relativePath = documentId
	            .substring(separator + 1)
	            .replace('\\', '/')
	            .trimStart('/')
	        val suffix = if (relativePath.isEmpty()) "" else "/$relativePath"
	        return androidStoragePathAliases.map { "$it$suffix" }
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
        json.put("explicit", values.getAsInteger("explicit") == 1)
        json.put("hasLyrics", values.getAsInteger("has_lyrics") == 1)
        json.put("lyricsMetadataScanVersion", values.getAsInteger("lyrics_metadata_scan_version") ?: 0)
        json.put("hasReplayGain", values.getAsInteger("has_replaygain") == 1)
        json.put("replayGainMetadataScanVersion", values.getAsInteger("replaygain_metadata_scan_version") ?: 0)
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
