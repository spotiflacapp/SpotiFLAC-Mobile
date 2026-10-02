package com.zarz.spotiflac.missingtracks

import java.nio.ByteBuffer

/** All calls are serialized on the owning playback worker. */
internal object NativeAudio {
    init { System.loadLibrary("spotiflac_audio") }
    external fun openOboe(rate: Int, channels: Int, bits: Int, device: Int): Long
    external fun writeOboe(handle: Long, data: ByteBuffer, offset: Int, count: Int): Int
    external fun bitsOboe(handle: Long): Int
    external fun deviceOboe(handle: Long): Int
    external fun startOboe(handle: Long)
    external fun flushOboe(handle: Long)
    external fun framesOboe(handle: Long): Long
    external fun closeOboe(handle: Long)
    external fun openWavPack(path: String): Long
    external fun infoWavPack(handle: Long): LongArray
    external fun readWavPack(handle: Long, frames: Int): ByteArray
    external fun seekWavPack(handle: Long, sample: Long)
    external fun closeWavPack(handle: Long)
}
