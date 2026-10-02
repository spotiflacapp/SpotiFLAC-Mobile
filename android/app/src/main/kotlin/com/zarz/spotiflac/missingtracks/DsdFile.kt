package com.zarz.spotiflac.missingtracks

import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Bounded DSF/uncompressed DSDIFF reader. Samples are normalized to MSB first. */
internal class DsdFile private constructor(private val file: RandomAccessFile) : DsdSource {
    override var rate = 0
        private set
    override var channels = 0
        private set
    private var dataOffset = 0L
    private var bytesPerChannel = 0L
    private var blockSize = 0
    private var reverseBits = false
    private var cursor = 0L
    private var cachedBlock = -1L
    private var block = ByteArray(0)
    override val durationUs: Long get() = bytesPerChannel * 8_000_000 / rate

    companion object {
        fun open(path: String): DsdFile? {
            val file = RandomAccessFile(path, "r")
            try {
                val magic = ByteArray(4)
                if (file.read(magic) != 4 || (!magic.contentEquals("DSD ".toByteArray()) &&
                    !magic.contentEquals("FRM8".toByteArray()))) { file.close(); return null }
                file.seek(0)
                return DsdFile(file).apply {
                    if (String(magic, Charsets.US_ASCII) == "DSD ") readDsf() else readDff()
                    require(channels in 1..2 && rate in listOf(2822400, 5644800, 11289600, 22579200)) {
                        "Unsupported DSD channels or rate"
                    }
                    require(bytesPerChannel > 0 && dataOffset > 0) { "Missing DSD audio" }
                }
            } catch (error: Exception) { file.close(); throw error }
        }
    }

    private fun read(length: Int): ByteArray = ByteArray(length).also { file.readFully(it) }
    private fun le64(): Long = ByteBuffer.wrap(read(8)).order(ByteOrder.LITTLE_ENDIAN).long
    private fun be64(): Long = ByteBuffer.wrap(read(8)).order(ByteOrder.BIG_ENDIAN).long
    private fun id(): String = String(read(4), Charsets.US_ASCII)
    private fun end(start: Long, size: Long, limit: Long): Long {
        require(size >= 0 && start <= limit && size <= limit - start) { "Truncated DSD chunk" }
        return start + size
    }

    private fun readDsf() {
        require(id() == "DSD " && le64() == 28L)
        val length = le64()
        le64() // Optional ID3 pointer; never needed to play samples.
        require(length in 28..file.length())
        while (file.filePointer + 12 <= length) {
            val name = id()
            val size = le64()
            require(size >= 12)
            val next = end(file.filePointer, size - 12, length)
            when (name) {
                "fmt " -> {
                    require(size >= 52)
                    val f = ByteBuffer.wrap(read(40)).order(ByteOrder.LITTLE_ENDIAN)
                    require(f.int == 1 && f.int == 0) { "Unsupported DSF format" }
                    f.int // Channel type.
                    channels = f.int
                    rate = f.int
                    val order = f.int
                    require(order == 1 || order == 8)
                    reverseBits = order == 1
                    val samples = f.long
                    require(samples > 0 && samples <= Long.MAX_VALUE - 7)
                    bytesPerChannel = (samples + 7) / 8
                    blockSize = f.int
                    require(blockSize in 1..65536 && channels in 1..2)
                }
                "data" -> {
                    require(blockSize > 0 && bytesPerChannel > 0)
                    val blocks = (bytesPerChannel + blockSize - 1) / blockSize
                    require(blocks <= (size - 12) / blockSize / channels) { "Truncated DSF data" }
                    dataOffset = file.filePointer
                    block = ByteArray(blockSize * channels)
                    return
                }
            }
            file.seek(next)
        }
    }

    private fun readDff() {
        require(id() == "FRM8")
        val limit = end(12, be64(), file.length())
        require(id() == "DSD ")
        var compression = ""
        while (file.filePointer + 12 <= limit) {
            val name = id()
            val size = be64()
            val next = end(file.filePointer, size, limit)
            when (name) {
                "PROP" -> {
                    require(size >= 4 && id() == "SND ")
                    while (file.filePointer + 12 <= next) {
                        val field = id()
                        val fieldSize = be64()
                        val fieldEnd = end(file.filePointer, fieldSize, next)
                        when (field) {
                            "FS  " -> { require(fieldSize >= 4); rate = file.readInt() }
                            "CHNL" -> { require(fieldSize >= 2); channels = file.readUnsignedShort() }
                            "CMPR" -> { require(fieldSize >= 4); compression = id() }
                        }
                        file.seek(fieldEnd + (fieldSize and 1))
                    }
                }
                "DSD " -> {
                    require(channels in 1..2 && compression == "DSD ") { "Compressed DST is not supported" }
                    require(size % channels == 0L)
                    dataOffset = file.filePointer
                    bytesPerChannel = size / channels
                    return
                }
                "DST " -> error("Compressed DST is not supported")
            }
            file.seek(next + (size and 1))
        }
    }

    override fun seek(positionUs: Long, encoding: String): Long {
        val group = if (encoding == "dop") 2 else 4
        cursor = (positionUs.coerceIn(0, durationUs) * rate / 8_000_000 / group * group)
            .coerceAtMost(bytesPerChannel)
        return cursor * 8_000_000 / rate
    }

    override fun readFrames(encoding: String, subslot: Int, maxFrames: Int): ByteArray? {
        require(maxFrames in 1..4096)
        if (cursor >= bytesPerChannel) return null
        require(encoding in listOf("dop", "dsd_be", "dsd_le"))
        require(subslot in 3..4)
        val group = if (encoding == "dop") 2 else 4
        val frames = minOf(maxFrames.toLong(), (bytesPerChannel - cursor + group - 1) / group).toInt()
        val output = ByteArray(frames * channels * subslot)
        // DFF is interleaved; read a bounded batch instead of seeking per byte.
        val interleaved = if (blockSize == 0) {
            file.seek(dataOffset + cursor * channels)
            read(minOf(frames.toLong() * group, bytesPerChannel - cursor).toInt() * channels)
        } else null
        var out = 0
        val dsd = ByteArray(group)
        for (frame in 0 until frames) {
            for (channel in 0 until channels) {
                for (index in 0 until group) {
                    val sample = cursor + frame * group + index
                    var value = 0x69
                    if (sample < bytesPerChannel) {
                        value = if (interleaved != null) {
                            interleaved[(frame * group + index) * channels + channel].toInt() and 255
                        } else {
                            val blockIndex = sample / blockSize
                            if (cachedBlock != blockIndex) {
                                file.seek(dataOffset + blockIndex * block.size)
                                file.readFully(block)
                                cachedBlock = blockIndex
                            }
                            block[channel * blockSize + (sample % blockSize).toInt()].toInt() and 255
                        }
                        if (reverseBits) value = Integer.reverse(value) ushr 24
                    }
                    dsd[index] = value.toByte()
                }
                if (encoding == "dop") {
                    if (subslot == 4) output[out++] = 0
                    output[out++] = dsd[1]
                    output[out++] = dsd[0]
                    output[out++] = 5 // Transport assigns continuous 05/FA markers.
                } else {
                    for (index in 0 until 4) output[out++] = dsd[if (encoding == "dsd_le") 3 - index else index]
                }
            }
        }
        cursor = minOf(bytesPerChannel, cursor + frames * group)
        return output
    }

    override fun close() { file.close() }
}
