package com.zarz.spotiflac.missingtracks

import android.content.Context
import androidx.documentfile.provider.DocumentFile
import java.util.Locale

internal fun findSafCueAudioSibling(
    context: Context,
    parent: DocumentFile,
    cueName: String,
    audioFileName: String?,
): DocumentFile? {
    val candidates = linkedSetOf<String>()
    if (!audioFileName.isNullOrBlank()) candidates.add(audioFileName)
    val baseName = cueName.substringBeforeLast('.')
    if (baseName.isNotBlank()) {
        for (extension in listOf(".flac", ".wav", ".ape", ".mp3", ".ogg", ".wv", ".m4a", ".mp4", ".aac")) {
            candidates.add(baseName + extension)
            candidates.add(baseName + extension.uppercase(Locale.ROOT))
        }
    }
    val matches = try {
        findSafChildren(context, parent, candidates)
    } catch (_: Exception) {
        // Preserve the old per-candidate recovery for unusual providers.
        return candidates.firstNotNullOfOrNull { name ->
            try { findSafChild(context, parent, name) } catch (_: Exception) { null }
        }
    }
    return candidates.firstNotNullOfOrNull(matches::get)
}
