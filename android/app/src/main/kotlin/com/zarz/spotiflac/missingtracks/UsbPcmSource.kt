package com.zarz.spotiflac.missingtracks

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.Closeable
import java.io.FileInputStream
import java.nio.ByteBuffer

/** A source for the direct driver; decoding never passes through AudioTrack. */
internal class UsbPcmSource(path: String) : Closeable {
    private val extractor = MediaExtractor()
    private var codec: MediaCodec? = null
    private val info = MediaCodec.BufferInfo()
    private val raw = ByteBuffer.allocateDirect(256 * 1024)
    private var inputEnded = false
    var ended = false
        private set
    private var inputBits = 0
    private var floating = false
    private var targetUs = 0L
    val rate: Int
    val channels: Int
    val bits: Int
    val durationUs: Long

    init {
        try {
            FileInputStream(path).use { extractor.setDataSource(it.fd) }
            val index = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: error("No audio stream")
            extractor.selectTrack(index)
            val format = extractor.getTrackFormat(index)
            rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0
            when (val mime = format.getString(MediaFormat.KEY_MIME)) {
                "audio/flac" -> {
                    val header = ByteArray(42)
                    FileInputStream(path).use { input ->
                        var n = 0
                        while (n < header.size) {
                            val count = input.read(header, n, header.size - n)
                            if (count <= 0) break
                            n += count
                        }
                    }
                    val source = requireNotNull(BitPerfectPcm.flacFormat(header))
                    require(source.first == rate && source.second == channels)
                    bits = source.third
                    format.setInteger(MediaFormat.KEY_PCM_ENCODING, when (bits) {
                        16 -> AudioFormat.ENCODING_PCM_16BIT
                        24 -> AudioFormat.ENCODING_PCM_FLOAT
                        32 -> AudioFormat.ENCODING_PCM_32BIT
                        else -> error("Unsupported precision")
                    })
                    codec = MediaCodec.createDecoderByType(mime).also {
                        it.configure(format, null, null, 0)
                        it.start()
                    }
                }
                "audio/raw" -> {
                    bits = precision(format.getInteger(MediaFormat.KEY_PCM_ENCODING))
                    inputBits = bits
                }
                else -> error("Direct USB supports integer FLAC/WAV and DSF/DFF")
            }
            require(channels in 1..2 && bits in listOf(16, 24, 32))
        } catch (error: Exception) { close(); throw error }
    }

    private fun precision(encoding: Int) = when (encoding) {
        AudioFormat.ENCODING_PCM_16BIT -> 16
        AudioFormat.ENCODING_PCM_24BIT_PACKED -> 24
        AudioFormat.ENCODING_PCM_32BIT -> 32
        else -> 0
    }

    private fun accept(format: MediaFormat) {
        require(format.getInteger(MediaFormat.KEY_SAMPLE_RATE) == rate && format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) == channels)
        val encoding = if (format.containsKey(MediaFormat.KEY_PCM_ENCODING)) format.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
        floating = encoding == AudioFormat.ENCODING_PCM_FLOAT
        inputBits = if (floating) 32 else precision(encoding)
        require(inputBits >= bits && !(floating && bits > 24)) { "Decoder reduced precision" }
    }

    private fun convert(buffer: ByteBuffer, timeUs: Long, outputBits: Int): ByteBuffer {
        val frame = channels * (inputBits / 8)
        require(frame > 0 && buffer.remaining() % frame == 0)
        val skip = if (timeUs < targetUs) ((targetUs - timeUs) * rate + 999999) / 1000000 else 0
        buffer.position(buffer.position() + minOf(skip, (buffer.remaining() / frame).toLong()).toInt() * frame)
        return BitPerfectPcm.convert(buffer, inputBits, bits, outputBits, floating)
    }

    fun read(outputBits: Int): ByteBuffer? {
        if (ended) return null
        val decoder = codec
        if (decoder == null) {
            raw.clear()
            val size = extractor.readSampleData(raw, 0)
            if (size < 0) { ended = true; return null }
            raw.limit(size)
            raw.position(0)
            val output = convert(raw, extractor.sampleTime, outputBits)
            extractor.advance()
            return output
        }
        repeat(8) {
            if (!inputEnded) {
                val slot = decoder.dequeueInputBuffer(0)
                if (slot >= 0) {
                    val size = extractor.readSampleData(requireNotNull(decoder.getInputBuffer(slot)), 0)
                    if (size < 0) {
                        decoder.queueInputBuffer(slot, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputEnded = true
                    } else {
                        decoder.queueInputBuffer(slot, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
        }
        val slot = decoder.dequeueOutputBuffer(info, 0)
        if (slot == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) accept(decoder.outputFormat)
        if (slot < 0) return null
        try {
            ended = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
            if (info.size == 0 || info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) return null
            if (inputBits == 0) accept(decoder.outputFormat)
            val buffer = requireNotNull(decoder.getOutputBuffer(slot))
            buffer.position(info.offset)
            buffer.limit(info.offset + info.size)
            return convert(buffer, info.presentationTimeUs, outputBits)
        } finally { decoder.releaseOutputBuffer(slot, false) }
    }

    fun seek(positionUs: Long) {
        targetUs = positionUs.coerceAtLeast(0)
        codec?.flush()
        extractor.seekTo(targetUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        inputEnded = false
        ended = false
    }

    override fun close() {
        runCatching { codec?.release() }
        codec = null
        runCatching { extractor.release() }
    }
}
