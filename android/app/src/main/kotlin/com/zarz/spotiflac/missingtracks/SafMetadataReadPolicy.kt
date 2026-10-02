package com.zarz.spotiflac.missingtracks

import java.io.File

/** Failure belongs to this read, never to a different document or provider.
 * The direct callback owns and closes its descriptor before fallback starts. */
internal fun <T> readSafMetadataWithFallback(
    directRead: () -> T?,
    fallbackRead: () -> T?,
): T? {
    val direct = try { directRead() } catch (_: Exception) { null }
    if (direct != null) return direct
    return try { fallbackRead() } catch (_: Exception) { null }
}

internal fun <T> readLyricsWithSafCopy(
    path: String,
    copyToTemp: (String) -> File?,
    read: (String) -> T,
): T? {
    if (!path.startsWith("content://")) return read(path)
    val temporary = copyToTemp(path) ?: return null
    return try {
        read(temporary.absolutePath)
    } finally {
        temporary.delete()
    }
}
