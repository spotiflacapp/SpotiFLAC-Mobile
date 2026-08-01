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


// FFmpeg execution, probing, and container helpers for NativeDownloadFinalizer.

internal fun NativeDownloadFinalizer.isMP4ContainerFile(path: String): Boolean {
    return try {
        File(path).inputStream().use { stream ->
            val header = ByteArray(12)
            val read = stream.read(header)
            read >= 8 &&
                header[4] == 'f'.code.toByte() &&
                header[5] == 't'.code.toByte() &&
                header[6] == 'y'.code.toByte() &&
                header[7] == 'p'.code.toByte()
        }
    } catch (_: Exception) {
        false
    }
}

internal fun NativeDownloadFinalizer.formatForPath(path: String): String {
    return when (normalizeExt(File(path).extension)) {
        ".mp3" -> "mp3"
        ".opus", ".ogg" -> "opus"
        ".m4a", ".mp4", ".aac" -> "m4a"
        else -> "flac"
    }
}

internal fun NativeDownloadFinalizer.scanReplayGain(path: String, shouldCancel: () -> Boolean = { false }): NativeDownloadFinalizer.ReplayGainScan? {
    val command = "-hide_banner -nostats -i ${q(path)} -filter_complex ebur128=peak=true:framelog=quiet -f null -"
    val result = runFFmpeg(command, shouldCancel)
    val output = result.second
    val integrated = Regex("I:\\s+(-?\\d+\\.?\\d*)\\s+LUFS")
        .findAll(output)
        .lastOrNull()
        ?.groupValues
        ?.getOrNull(1)
        ?.toDoubleOrNull() ?: return null
    val truePeak = Regex("Peak:\\s+(-?\\d+\\.?\\d*)\\s+dBFS")
        .findAll(output)
        .mapNotNull { it.groupValues.getOrNull(1)?.toDoubleOrNull() }
        .maxOrNull()
    val gain = -18.0 - integrated
    val peak = if (truePeak != null) 10.0.pow(truePeak / 20.0) else 1.0
    return NativeDownloadFinalizer.ReplayGainScan(
        trackGain = "${if (gain >= 0) "+" else ""}${"%.2f".format(Locale.US, gain)} dB",
        trackPeak = "%.6f".format(Locale.US, peak),
        integratedLufs = integrated,
        truePeakLinear = peak,
    )
}

internal fun NativeDownloadFinalizer.runFFmpeg(command: String, shouldCancel: () -> Boolean = { false }): Pair<Boolean, String> {
    checkCancelled(shouldCancel)
    installNativeFFmpegCallbackFilter()
    val latch = CountDownLatch(1)
    var completedSession: FFmpegSession? = null
    val session = FFmpegSession.create(
        FFmpegKitConfig.parseArguments(command),
        { finishedSession ->
            completedSession = finishedSession
            latch.countDown()
        },
        null,
        null,
        LogRedirectionStrategy.NEVER_PRINT_LOGS,
    )
    val sessionId = session.sessionId
    synchronized(activeFFmpegSessionLock) {
        activeFFmpegSessionIds.add(sessionId)
        nativeFFmpegSessionIds.add(sessionId)
    }
    FFmpegKitConfig.asyncFFmpegExecute(session)
    try {
        var cancelRequested = false
        while (!latch.await(200, TimeUnit.MILLISECONDS)) {
            if (shouldCancel()) {
                cancelRequested = true
                try {
                    FFmpegKit.cancel(sessionId)
                } catch (_: Exception) {
                }
                break
            }
        }
        if (cancelRequested) {
            latch.await(5, TimeUnit.SECONDS)
            throw CancellationException("Native FFmpeg session cancelled")
        }
        val finalSession = completedSession ?: session
        val output = finalSession.getAllLogsAsString(1000) ?: ""
        checkCancelled(shouldCancel)
        return ReturnCode.isSuccess(finalSession.returnCode) to output
    } finally {
        synchronized(activeFFmpegSessionLock) {
            activeFFmpegSessionIds.remove(sessionId)
        }
    }
}

internal fun NativeDownloadFinalizer.installNativeFFmpegCallbackFilter() {
    synchronized(ffmpegCompleteCallbackLock) {
        val current = FFmpegKitConfig.getFFmpegSessionCompleteCallback()
        if (current !== nativeFilteringFFmpegCompleteCallback) {
            forwardedFFmpegCompleteCallback = current
            FFmpegKitConfig.enableFFmpegSessionCompleteCallback(nativeFilteringFFmpegCompleteCallback)
        }
    }
}

internal fun NativeDownloadFinalizer.withFFmpegCommandPump(
    shouldCancel: () -> Boolean = { false },
    block: () -> String,
): String {
    val running = AtomicBoolean(true)
    val handled = mutableSetOf<String>()
    val pump = Thread {
        while (running.get()) {
            try {
                val raw = Gobackend.getAllPendingFFmpegCommandsJSON()
                val commands = org.json.JSONArray(raw)
                for (index in 0 until commands.length()) {
                    val command = commands.optJSONObject(index) ?: continue
                    val id = command.optString("command_id", "")
                    val commandLine = command.optString("command", "")
                    if (id.isBlank() || commandLine.isBlank() || handled.contains(id)) {
                        continue
                    }
                    handled.add(id)
                    // Every claimed command must get a result delivered to
                    // the Go side, even on failure or cancellation: the
                    // backend blocks until one arrives and never retries a
                    // claimed id, so bailing out here would strand the
                    // gomobile call the main thread is sitting in forever.
                    val result = try {
                        if (shouldCancel()) {
                            Pair(false, "cancelled")
                        } else {
                            runFFmpeg(commandLine, shouldCancel)
                        }
                    } catch (e: Exception) {
                        Pair(false, e.message ?: "FFmpeg execution failed")
                    }
                    try {
                        Gobackend.setFFmpegCommandResultByID(
                            id,
                            result.first,
                            result.second,
                            if (result.first) "" else result.second,
                        )
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to deliver FFmpeg result for $id: ${e.message}")
                    }
                }
            } catch (_: Exception) {
            }
            try {
                Thread.sleep(100)
            } catch (_: InterruptedException) {
                // Keep pumping until `running` flips: on cancel the Go call
                // may still be waiting for a result for an in-flight
                // command, and it is delivered as failed above.
            }
        }
    }
    pump.isDaemon = true
    pump.start()
    return try {
        block()
    } finally {
        running.set(false)
        pump.interrupt()
    }
}

/**
 * Staged sibling name for conversion outputs: "song.flac" -> "song.partial.flac".
 * The ".partial<ext>" shape is ignored by library scans and duplicate checks,
 * while the real trailing extension still lets FFmpeg infer the muxer. A
 * process kill mid-conversion therefore never leaves a partial file under a
 * real audio name in the user's music folder.
 */
internal fun NativeDownloadFinalizer.stagedConversionPath(finalPath: String): String {
    val file = File(finalPath)
    val ext = file.extension
    val name = if (ext.isBlank()) "${file.name}.partial" else "${file.nameWithoutExtension}.partial.$ext"
    return File(file.parentFile, name).absolutePath
}

internal fun NativeDownloadFinalizer.promoteStagedConversion(stagedPath: String, finalPath: String): Boolean {
    val staged = File(stagedPath)
    fsyncQuietly(staged)
    val final = File(finalPath)
    if (staged.renameTo(final)) return true
    return final.delete() && staged.renameTo(final)
}

internal fun NativeDownloadFinalizer.buildOutputPath(inputPath: String, extension: String): String {
    val ext = normalizeExt(extension).ifBlank { ".tmp" }
    val file = File(inputPath)
    val base = file.nameWithoutExtension.ifBlank { "track" }
    val candidate = File(file.parentFile, "$base$ext").absolutePath
    if (candidate != inputPath) return candidate
    return File(file.parentFile, "${base}_converted$ext").absolutePath
}

internal fun NativeDownloadFinalizer.desiredFileName(input: NativeDownloadFinalizer.FinalizeInput, state: NativeDownloadFinalizer.FinalizeState, extension: String): String {
    val ext = normalizeExt(extension).ifBlank { normalizeExt(File(state.fileName).extension).ifBlank { ".flac" } }
    val rawName = input.result.optString("quality_variant_file_name", "")
        .ifBlank { input.request.optString("saf_file_name", "") }
        .ifBlank { state.fileName }
        .ifBlank { "${trackString(input, "artistName", input.request.optString("artist_name", "Artist"))} - ${trackString(input, "name", input.request.optString("track_name", "Track"))}" }
    val knownExts = listOf(".flac", ".m4a", ".mp4", ".aac", ".mp3", ".opus", ".ogg", ".lrc")
    var base = rawName.trim()
    val lower = base.lowercase(Locale.ROOT)
    for (knownExt in knownExts) {
        if (lower.endsWith(knownExt)) {
            base = base.dropLast(knownExt.length)
            break
        }
    }
    base = base
        .replace("/", " ")
        .replace(Regex("[\\\\:*?\"<>|]"), " ")
        .trim()
        .trim('.', ' ')
        .ifBlank { "track" }
    return "$base$ext"
}

internal fun NativeDownloadFinalizer.shouldForceContainerConversion(input: NativeDownloadFinalizer.FinalizeInput, state: NativeDownloadFinalizer.FinalizeState): Boolean {
    if (input.result.optBoolean("requires_container_conversion", false)) return true
    if (input.request.optBoolean("requires_container_conversion", false)) return true
    return false
}

internal fun NativeDownloadFinalizer.probePrimaryAudioCodec(path: String, shouldCancel: () -> Boolean = { false }): String {
    val result = runFFmpeg("-hide_banner -nostdin -i ${q(path)} -map 0:a:0 -frames:a 1 -f null -", shouldCancel)
    val output = result.second
    val match = Regex("Audio:\\s*([^,\\s]+)", RegexOption.IGNORE_CASE).find(output)
    return match?.groupValues?.getOrNull(1)
        ?.trim()
        ?.lowercase(Locale.ROOT)
        ?.replace('-', '_')
        .orEmpty()
}

/**
 * Returns true when the file on [path] starts with the native FLAC magic
 * bytes (`fLaC`). A file may contain a FLAC audio stream yet live inside
 * an MP4/fMP4 container (e.g. some Amazon Music downloads); native FLAC
 * tag writers require the raw fLaC header, so we must detect that mismatch
 * before skipping the container conversion step.
 */
internal fun NativeDownloadFinalizer.isNativeFlacFile(path: String): Boolean {
    return try {
        RandomAccessFile(path, "r").use { raf ->
            if (raf.length() < 4L) return false
            val header = ByteArray(4)
            raf.readFully(header)
            header[0] == 0x66.toByte() && // 'f'
                header[1] == 0x4C.toByte() && // 'L'
                header[2] == 0x61.toByte() && // 'a'
                header[3] == 0x43.toByte() // 'C'
        }
    } catch (e: Exception) {
        Log.w(TAG, "Native FLAC magic probe failed for $path: ${e.message}")
        false
    }
}

internal fun NativeDownloadFinalizer.requestedDecryptionOutputExt(input: NativeDownloadFinalizer.FinalizeInput): String {
    val descriptor = input.result.optJSONObject("decryption")
    return normalizeExt(
        descriptor?.optString("output_extension", "")
            ?.ifBlank { input.result.optString("output_extension", "") }
    )
}
