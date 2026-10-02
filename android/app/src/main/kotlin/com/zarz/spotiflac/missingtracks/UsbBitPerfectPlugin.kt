package com.zarz.spotiflac.missingtracks

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioMixerAttributes
import android.media.AudioRouting
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream
import java.nio.ByteBuffer

/** Engine-owned (not Activity-owned), so playback survives backgrounding. */
class UsbBitPerfectPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var engine: UsbPcmPlayback? = null
    private var direct: UsbDirectPlayback? = null
    private var useDirect = false
    private var hiRes: HiResPlayback? = null
    private var useHiRes = false
    private lateinit var appContext: Context
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods = MethodChannel(binding.binaryMessenger, "com.zarz.spotiflac.missingtracks/usb_pcm")
        events = EventChannel(binding.binaryMessenger, "com.zarz.spotiflac.missingtracks/usb_pcm/events")
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        appContext = binding.applicationContext
        if (Build.VERSION.SDK_INT >= 34) {
            engine = UsbPcmPlayback(binding.applicationContext) { event ->
                main.post { sink?.success(event) }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "prepare") {
            if (useHiRes) hiRes?.command(MethodCall("stop", null)) { _, _ -> }
            else if (useDirect) direct?.command(MethodCall("stop", null)) { _, _ -> }
            else if (Build.VERSION.SDK_INT >= 34) engine?.command(MethodCall("stop", null)) { _, _ -> }
            useDirect = call.argument<Boolean>("direct") == true
            useHiRes = !useDirect && call.argument<Boolean>("dapExclusive") == true
            if (useHiRes && hiRes == null) {
                hiRes = HiResPlayback(appContext) { event -> main.post { sink?.success(event) } }
            }
            if (useDirect && direct == null) {
                direct = UsbDirectPlayback(appContext) { event ->
                    main.post { sink?.success(event) }
                }
            }
        }
        if (useHiRes) {
            hiRes?.command(call) { value, error ->
                main.post {
                    if (error == null) result.success(value)
                    else result.error("aaudio_exclusive", error, null)
                }
            }
            return
        }
        if (useDirect) {
            direct?.command(call) { value, error ->
                main.post {
                    if (error == null) result.success(value)
                    else result.error("usb_direct", error, null)
                }
            }
            return
        }
        val playback = engine
        if (Build.VERSION.SDK_INT < 34 || playback == null) {
            result.success(if (call.method == "prepare") mapOf("reason" to "android_version") else null)
            return
        }
        playback.command(call) { value, error ->
            main.post {
                if (error == null) result.success(value)
                else result.error("usb_pcm", error, null)
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
        direct?.dispose()
        direct = null
        hiRes?.dispose()
        hiRes = null
        if (Build.VERSION.SDK_INT >= 34) engine?.dispose()
        engine = null
    }
}

@RequiresApi(34)
private class UsbPcmPlayback(context: Context, private val emit: (Map<String, Any>) -> Unit) {
    private val manager = context.getSystemService(AudioManager::class.java)
    private val thread = HandlerThread("SpotiFLAC-USB-PCM").apply { start() }
    private val worker = Handler(thread.looper)
    private val wakeLock = context.getSystemService(PowerManager::class.java)
        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SpotiFLAC:UsbPcm")
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
    private var extractor: MediaExtractor? = null
    private var decoder: MediaCodec? = null
    private var track: AudioTrack? = null
    private var device: AudioDeviceInfo? = null
    private var mixer: AudioMixerAttributes? = null
    private var token = 0
    private var rate = 0
    private var channels = 0
    private var sourceBits = 0
    private var inputBits = 0
    private var floatInput = false
    private var outputBits = 0
    private var durationUs = 0L
    private var positionBaseUs = 0L
    private var seekTargetUs = 0L
    private var needTimestamp = true
    private var framesWritten = 0L
    private var previousHead = 0L
    private var headWrap = 0L
    private var inputEnded = false
    private var outputEnded = false
    private var playing = false
    private var invalidRoute = false
    private var nextRouteCheck = 0L
    private var pending: ByteBuffer? = null
    private val info = MediaCodec.BufferInfo()
    private val rawBuffer = ByteBuffer.allocateDirect(256 * 1024)
    @Volatile private var revision = 0
    private val routing = AudioRouting.OnRoutingChangedListener {
        if (playing && track?.routedDevice?.id != device?.id) suspendRoute()
    }
    private val mixerListener = AudioManager.OnPreferredMixerAttributesChangedListener { attr, changedDevice, value ->
        if (attr.usage == AudioAttributes.USAGE_MEDIA && changedDevice.id == device?.id && value != mixer) {
            suspendRoute()
        }
    }

    init {
        manager.addOnPreferredMixerAttributesChangedListener({ runnable -> worker.post(runnable) }, mixerListener)
    }

    fun command(call: MethodCall, done: (Any?, String?) -> Unit) {
        val commandRevision = if (call.method == "prepare" || call.method == "stop") ++revision else revision
        worker.post {
            try {
                val value: Any? = when (call.method) {
                    "prepare" -> {
                        closeSource()
                        token = call.argument<Int>("token") ?: 0
                        try {
                            prepare(requireNotNull(call.argument<String>("path")), commandRevision)
                        } catch (error: Exception) {
                            closeSource()
                            android.util.Log.i("UsbPcm", "Using normal output: ${error.message}")
                            mapOf("reason" to (error as? Unavailable)?.reason.orEmpty().ifEmpty { "format" })
                        }
                    }
                    "resume" -> { resume(); null }
                    "pause" -> { pause(); null }
                    "seek" -> { seek((call.argument<Number>("position")?.toLong() ?: 0) * 1000); null }
                    "stop" -> { closeSource(); null }
                    "position" -> positionUs() / 1000
                    else -> error("Unknown USB PCM command")
                }
                done(value, null)
            } catch (error: Exception) { done(null, error.message ?: "USB playback failed") }
        }
    }

    private class Unavailable(val reason: String) : Exception(reason)

    private fun prepare(path: String, expectedRevision: Int): Map<String, Any> {
        val usb = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull {
            it.type == AudioDeviceInfo.TYPE_USB_DEVICE || it.type == AudioDeviceInfo.TYPE_USB_HEADSET
        } ?: throw Unavailable("no_usb")
        val supported = manager.getSupportedMixerAttributes(usb).filter {
            it.mixerBehavior == AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT
        }
        if (supported.isEmpty()) throw Unavailable("unsupported")
        // The owned descriptor is duplicated by MediaExtractor; a SAF lease may
        // close as soon as prepare returns without keeping a full-file copy.
        val media = MediaExtractor().also { extractor = it }
        FileInputStream(path).use { media.setDataSource(it.fd) }
        val index = (0 until media.trackCount).firstOrNull {
            media.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
        } ?: throw Unavailable("format")
        media.selectTrack(index)
        val format = media.getTrackFormat(index)
        val mime = format.getString(MediaFormat.KEY_MIME)
        rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        if (channels !in 1..2) throw Unavailable("format")
        val mask = if (channels == 1) AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO
        durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0
        if (mime == "audio/flac") {
            val header = ByteArray(42)
            FileInputStream(path).use { input ->
                var offset = 0
                while (offset < header.size) {
                    val read = input.read(header, offset, header.size - offset)
                    if (read <= 0) break
                    offset += read
                }
            }
            val source = BitPerfectPcm.flacFormat(header) ?: throw Unavailable("format")
            if (source.first != rate || source.second != channels) throw Unavailable("format")
            sourceBits = source.third
        } else if (mime == "audio/raw" && format.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
            sourceBits = bits(format.getInteger(MediaFormat.KEY_PCM_ENCODING))
        } else throw Unavailable("format")
        if (sourceBits !in listOf(16, 24, 32)) throw Unavailable("format")
        val matching = supported.filter { it.format.sampleRate == rate && it.format.channelMask == mask }
        outputBits = BitPerfectPcm.outputBits(sourceBits, matching.map { bits(it.format.encoding) })
            ?: throw Unavailable("format")
        val selected = matching.first { bits(it.format.encoding) == outputBits }
        device = usb
        mixer = selected
        if (!manager.setPreferredMixerAttributes(attributes, usb, selected)) throw Unavailable("unsupported")
        val minimum = AudioTrack.getMinBufferSize(rate, mask, selected.format.encoding)
        if (minimum <= 0) throw Unavailable("format")
        val audio = AudioTrack.Builder().setAudioAttributes(attributes).setAudioFormat(selected.format)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(maxOf(minimum * 2, rate / 5 * channels * (outputBits / 8)))
            .build().also { track = it }
        if (audio.state != AudioTrack.STATE_INITIALIZED || !audio.setPreferredDevice(usb) ||
            audio.sampleRate != rate || audio.audioFormat != selected.format.encoding ||
            audio.channelCount != channels) throw Unavailable("format")
        audio.addOnRoutingChangedListener(routing, worker)
        // Never change STREAM_MUSIC volume: the DAC owns volume in this mode.
        audio.setVolume(1f)
        if (mime == "audio/raw") {
            inputBits = sourceBits
            floatInput = false
        } else {
            // 24-bit integers are represented exactly by IEEE float. Converting
            // them back is checked sample-by-sample, with no rounding allowed.
            format.setInteger(MediaFormat.KEY_PCM_ENCODING, when (sourceBits) {
                16 -> AudioFormat.ENCODING_PCM_16BIT
                24 -> AudioFormat.ENCODING_PCM_FLOAT
                else -> AudioFormat.ENCODING_PCM_32BIT
            })
            val codec = MediaCodec.createDecoderByType(requireNotNull(mime)).also { decoder = it }
            codec.configure(format, null, null, 0)
            codec.start()
            inputBits = 0
            val deadline = android.os.SystemClock.elapsedRealtime() + 5000
            while (pending == null && !outputEnded) {
                if (revision != expectedRevision) throw Unavailable("cancelled")
                if (android.os.SystemClock.elapsedRealtime() > deadline) throw Unavailable("format")
                decode()
                if (pending == null) Thread.sleep(2)
            }
        }
        return mapOf("ready" to true, "device" to usb.productName.toString(), "sampleRate" to rate,
            "bitDepth" to outputBits, "sourceBitDepth" to sourceBits, "duration" to durationUs / 1000)
    }

    private fun bits(encoding: Int): Int = when (encoding) {
        AudioFormat.ENCODING_PCM_16BIT -> 16
        AudioFormat.ENCODING_PCM_24BIT_PACKED -> 24
        AudioFormat.ENCODING_PCM_32BIT -> 32
        else -> 0
    }

    private fun acceptFormat(format: MediaFormat) {
        if (format.getInteger(MediaFormat.KEY_SAMPLE_RATE) != rate ||
            format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) != channels) throw Unavailable("format")
        val encoding = if (format.containsKey(MediaFormat.KEY_PCM_ENCODING))
            format.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
        floatInput = encoding == AudioFormat.ENCODING_PCM_FLOAT
        inputBits = if (floatInput) 32 else bits(encoding)
        if (inputBits < sourceBits || (floatInput && sourceBits > 24)) throw Unavailable("format")
    }

    private fun pcm(input: ByteBuffer, timeUs: Long) {
        val frameBytes = channels * (inputBits / 8)
        require(frameBytes > 0 && input.remaining() % frameBytes == 0)
        val skipFrames = if (timeUs < seekTargetUs)
            ((seekTargetUs - timeUs) * rate + 999999) / 1000000 else 0
        val skipped = minOf(skipFrames, (input.remaining() / frameBytes).toLong())
        input.position(input.position() + skipped.toInt() * frameBytes)
        if (!input.hasRemaining()) return
        if (needTimestamp) {
            positionBaseUs = timeUs + skipped * 1000000 / rate
            needTimestamp = false
        }
        pending = BitPerfectPcm.convert(input, inputBits, sourceBits, outputBits, floatInput)
    }

    private fun decode() {
        val media = extractor ?: return
        if (pending != null || outputEnded) return
        val codec = decoder
        if (codec == null) {
            rawBuffer.clear()
            val size = media.readSampleData(rawBuffer, 0)
            if (size < 0) { outputEnded = true; return }
            rawBuffer.position(0)
            rawBuffer.limit(size)
            pcm(rawBuffer, media.sampleTime)
            media.advance()
            return
        }
        // Keep the codec fed independently of FLAC block size. Processing only
        // one tiny frame per pump would starve a high-rate DAC.
        for (attempt in 0 until 8) {
            if (inputEnded) break
            val slot = codec.dequeueInputBuffer(0)
            if (slot < 0) break
            val buffer = requireNotNull(codec.getInputBuffer(slot))
            val size = media.readSampleData(buffer, 0)
            if (size < 0) {
                codec.queueInputBuffer(slot, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                inputEnded = true
            } else {
                codec.queueInputBuffer(slot, 0, size, media.sampleTime, 0)
                media.advance()
            }
        }
        val slot = codec.dequeueOutputBuffer(info, 0)
        if (slot == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) acceptFormat(codec.outputFormat)
        if (slot >= 0) {
            try {
                if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                    if (inputBits == 0) acceptFormat(codec.outputFormat)
                    val buffer = requireNotNull(codec.getOutputBuffer(slot))
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    pcm(buffer, info.presentationTimeUs)
                }
                outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
            } finally { codec.releaseOutputBuffer(slot, false) }
        }
    }

    private fun verifiedRoute(): Boolean = track?.routedDevice?.id == device?.id &&
        device?.let { manager.getPreferredMixerAttributes(attributes, it) == mixer } == true

    private fun resume() {
        val audio = track ?: error("No USB source")
        check(!invalidRoute) { "USB route changed; reopen the track" }
        audio.play()
        // Do not write any samples until the route actually resolves to our DAC.
        if (!verifiedRoute()) {
            audio.pause()
            invalidRoute = true
            emit(mapOf("token" to token, "event" to "paused", "reason" to "route_changed"))
            error("USB route could not be verified")
        }
        playing = true
        if (!wakeLock.isHeld) wakeLock.acquire()
        emit(mapOf("token" to token, "event" to "active"))
        worker.removeCallbacks(pump)
        worker.post(pump)
    }

    private val pump = object : Runnable {
        override fun run() {
            if (!playing) return
            try {
                val now = android.os.SystemClock.elapsedRealtime()
                if (now >= nextRouteCheck) {
                    if (!verifiedRoute()) { suspendRoute(); return }
                    nextRouteCheck = now + 250
                }
                // Bounded nonblocking writes keep transport commands responsive
                // even when a DAC stops consuming samples.
                for (attempt in 0 until 8) {
                    decode()
                    val buffer = pending ?: break
                    val written = requireNotNull(track).write(buffer, buffer.remaining(), AudioTrack.WRITE_NON_BLOCKING)
                    check(written >= 0) { "USB write failed: $written" }
                    framesWritten += written / (channels * (outputBits / 8))
                    if (buffer.hasRemaining()) break
                    pending = null
                }
                if (outputEnded && pending == null && headFrames() >= framesWritten) {
                    pause()
                    emit(mapOf("token" to token, "event" to "complete"))
                } else worker.postDelayed(this, 5)
            } catch (error: Exception) {
                android.util.Log.w("UsbPcm", "PCM playback stopped", error)
                suspendRoute()
            }
        }
    }

    private fun pause() {
        playing = false
        worker.removeCallbacks(pump)
        if (wakeLock.isHeld) wakeLock.release()
        runCatching {
            if (track?.playState == AudioTrack.PLAYSTATE_PLAYING) track?.pause()
        }
    }

    private fun suspendRoute() {
        pause()
        invalidRoute = true
        emit(mapOf("token" to token, "event" to "paused", "reason" to "route_changed"))
    }

    private fun headFrames(): Long {
        val head = (track?.playbackHeadPosition?.toLong() ?: 0) and 0xffffffffL
        if (head < previousHead) headWrap += 1L shl 32
        previousHead = head
        return headWrap + head
    }
    private fun positionUs(): Long = positionBaseUs + if (rate > 0) headFrames() * 1000000 / rate else 0

    private fun seek(positionUs: Long) {
        val wasPlaying = playing
        pause()
        track?.flush()
        decoder?.flush()
        seekTargetUs = if (durationUs > 0) positionUs.coerceIn(0, durationUs - 1)
            else positionUs.coerceAtLeast(0)
        extractor?.seekTo(seekTargetUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        positionBaseUs = seekTargetUs
        framesWritten = 0
        previousHead = 0
        headWrap = 0
        needTimestamp = true
        pending = null
        inputEnded = false
        outputEnded = false
        if (wasPlaying) resume()
    }

    private fun closeSource() {
        pause()
        track?.let { audio ->
            runCatching { audio.removeOnRoutingChangedListener(routing) }
            runCatching { audio.release() }
        }
        track = null
        runCatching { decoder?.release() }
        decoder = null
        runCatching { extractor?.release() }
        extractor = null
        device?.let { runCatching { manager.clearPreferredMixerAttributes(attributes, it) } }
        device = null
        mixer = null
        pending = null
        framesWritten = 0
        previousHead = 0
        headWrap = 0
        positionBaseUs = 0
        seekTargetUs = 0
        durationUs = 0
        inputEnded = false
        outputEnded = false
        needTimestamp = true
        invalidRoute = false
    }

    fun dispose() {
        revision++
        worker.post {
            closeSource()
            manager.removeOnPreferredMixerAttributesChangedListener(mixerListener)
            thread.quitSafely()
        }
    }
}
