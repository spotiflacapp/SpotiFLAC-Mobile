package com.zarz.spotiflac.missingtracks

import java.io.File

/** Creates a validated staged FLAC; publication and source ownership stay with the caller. */
internal fun convertToStagedFlac(
    input: String,
    stagedOutput: String,
    codec: String,
    execute: (Array<String>) -> Pair<Boolean, String>,
    checkCancelled: () -> Unit,
) {
    val staged = File(stagedOutput)
    var complete = false
    var diagnostic = ""
    val encoders = if (NativeFinalizationPolicy.normalizeAudioCodec(codec) == "flac") {
        listOf(arrayOf("-c:a", "copy"), arrayOf("-c:a", "flac", "-compression_level", "8"))
    } else {
        listOf(arrayOf("-c:a", "flac", "-compression_level", "8"))
    }
    try {
        for (encoder in encoders) {
            checkCancelled()
            check(!staged.exists() || staged.delete()) { "failed to remove staged FLAC output" }
            val result = execute(
                arrayOf("-v", "error", "-xerror", "-i", input) +
                    encoder + arrayOf("-f", "flac", stagedOutput, "-y"),
            )
            checkCancelled()
            diagnostic = result.second
            val hasHeader = result.first && staged.isFile && staged.length() > 42L &&
                staged.inputStream().use { stream ->
                    val header = ByteArray(4)
                    stream.read(header) == 4 && header.contentEquals(byteArrayOf(0x66, 0x4c, 0x61, 0x43))
                }
            if (!hasHeader) {
                if (result.first) diagnostic = "conversion produced no valid FLAC header"
                continue
            }
            if ("copy" !in encoder) {
                complete = true
                return
            }
            // A remux does not decode audio, so verify the whole stream to
            // reject corrupt later frames just as the encoder did previously.
            // Cancellation must never trigger an encoding retry.
            val validation = execute(
                arrayOf(
                    "-v", "error", "-xerror", "-err_detect", "crccheck+explode", "-i", stagedOutput,
                    "-map", "0:a:0", "-f", "null", "-",
                ),
            )
            checkCancelled()
            diagnostic = validation.second
            if (validation.first) {
                complete = true
                return
            }
        }
        throw IllegalStateException("container conversion failed: $diagnostic")
    } finally {
        if (!complete) staged.delete()
    }
}
