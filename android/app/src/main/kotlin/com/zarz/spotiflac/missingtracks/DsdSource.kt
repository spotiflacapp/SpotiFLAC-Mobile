package com.zarz.spotiflac.missingtracks

import java.io.Closeable
import java.io.FileInputStream

internal interface DsdSource : Closeable {
    val rate: Int
    val channels: Int
    val durationUs: Long
    fun seek(positionUs: Long, encoding: String): Long
    fun readFrames(encoding: String, subslot: Int, maxFrames: Int = 4096): ByteArray?

    companion object {
        fun isDsd(path: String): Boolean {
            val header = ByteArray(32)
            val count = FileInputStream(path).use { it.read(header) }
            if (count < 4) return false
            return when (String(header, 0, 4, Charsets.US_ASCII)) {
                "DSD ", "FRM8" -> true
                "wvpk" -> count >= 28 && header[27].toInt() and 0x80 != 0
                else -> false
            }
        }
        fun open(path: String): DsdSource? {
            val magic = ByteArray(4)
            FileInputStream(path).use { if (it.read(magic) != 4) return null }
            return if (magic.contentEquals("wvpk".toByteArray())) WavPackDsdSource.open(path)
                else DsdFile.open(path)
        }
    }
}

internal class WavPackDsdSource private constructor(private var handle: Long) : DsdSource {
    private val info = NativeAudio.infoWavPack(handle)
    override val rate = info[0].toInt()
    override val channels = info[1].toInt()
    private val bytesPerChannel = info[2]
    override val durationUs = bytesPerChannel * 8_000_000 / rate
    private var cursor = 0L

    companion object {
        fun open(path: String): WavPackDsdSource? {
            val handle = NativeAudio.openWavPack(path)
            if (handle == 0L) return null
            try { return WavPackDsdSource(handle) }
            catch (error: Exception) { NativeAudio.closeWavPack(handle); throw error }
        }
    }

    override fun seek(positionUs: Long, encoding: String): Long {
        val group = if (encoding == "dop") 2 else 4
        cursor = (positionUs.coerceIn(0, durationUs) * rate / 8_000_000 / group * group).coerceAtMost(bytesPerChannel)
        if (cursor < bytesPerChannel) NativeAudio.seekWavPack(handle, cursor)
        return cursor * 8_000_000 / rate
    }

    override fun readFrames(encoding: String, subslot: Int, maxFrames: Int): ByteArray? {
        if (cursor >= bytesPerChannel) return null
        require(maxFrames in 1..4096 && encoding in listOf("dop", "dsd_be", "dsd_le"))
        require(if (encoding == "dop") subslot in 3..4 else subslot == 4)
        val group = if (encoding == "dop") 2 else 4
        val count = minOf(bytesPerChannel - cursor, maxFrames.toLong() * group).toInt()
        val data = NativeAudio.readWavPack(handle, count)
        require(data.size == count * channels) { "Truncated WavPack DSD" }
        val frames = (count + group - 1) / group
        val output = ByteArray(frames * channels * subslot)
        var out = 0
        for (frame in 0 until frames) {
            for (channel in 0 until channels) {
                fun sample(index: Int): Byte {
                    val pos = frame * group + index
                    return if (pos < count) data[pos * channels + channel] else 0x69.toByte()
                }
                if (encoding == "dop") {
                    if (subslot == 4) output[out++] = 0
                    output[out++] = sample(1)
                    output[out++] = sample(0)
                    output[out++] = 5
                } else for (index in 0 until 4) output[out++] = sample(if (encoding == "dsd_le") 3 - index else index)
            }
        }
        cursor += count
        return output
    }

    override fun close() {
        if (handle != 0L) { NativeAudio.closeWavPack(handle); handle = 0 }
    }
}
