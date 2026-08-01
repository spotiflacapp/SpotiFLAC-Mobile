import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_full/session_state.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/services/audio_metadata_mapper.dart';
import 'package:spotiflac_android/services/ffmpeg_models.dart';
import 'package:spotiflac_android/services/id3v23_lyrics.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/artist_utils.dart';
import 'package:spotiflac_android/utils/audio_conversion_utils.dart';
import 'package:spotiflac_android/utils/logger.dart';

export 'package:spotiflac_android/services/ffmpeg_models.dart';

final _log = AppLogger('FFmpeg');

class _ResolvedLosslessConversionQuality {
  final int? targetBitDepth;
  final int? targetSampleRate;

  const _ResolvedLosslessConversionQuality({
    this.targetBitDepth,
    this.targetSampleRate,
  });
}

class _ConversionOutputPlan {
  final String workingPath;
  final String finalPath;

  const _ConversionOutputPlan({
    required this.workingPath,
    required this.finalPath,
  });

  bool get requiresPromotion => workingPath != finalPath;
}

class FFmpegService {
  static const int _commandLogPreviewLength = 300;
  static const Duration _liveTunnelStartupTimeout = Duration(seconds: 8);
  static const Duration _liveTunnelStartupPollInterval = Duration(
    milliseconds: 200,
  );
  static const Duration _liveTunnelStabilizationDelay = Duration(
    milliseconds: 900,
  );
  static const String _genericMovKeyDecryptionStrategy = 'ffmpeg.mov_key';
  static int _tempEmbedCounter = 0;
  static FFmpegSession? _activeLiveDecryptSession;
  static String? _activeLiveDecryptUrl;
  static String? _activeLiveTempInputPath;
  static String? _activeNativeDashManifestPath;
  static String? _activeNativeDashManifestUrl;
  static final Set<String> _preparedNativeDashManifestPaths = <String>{};

  static String _buildOutputPath(String inputPath, String extension) {
    final normalizedExt = extension.startsWith('.') ? extension : '.$extension';
    final inputFile = File(inputPath);
    final dir = inputFile.parent.path;
    final filename = inputFile.uri.pathSegments.last;
    final dotIndex = filename.lastIndexOf('.');
    final baseName = dotIndex > 0 ? filename.substring(0, dotIndex) : filename;
    var outputPath = '$dir${Platform.pathSeparator}$baseName$normalizedExt';

    if (outputPath == inputPath) {
      outputPath =
          '$dir${Platform.pathSeparator}${baseName}_converted$normalizedExt';
    }
    return outputPath;
  }

  static bool _sameLocalPath(String first, String second) {
    final firstPath = File(first).absolute.path;
    final secondPath = File(second).absolute.path;
    return Platform.isWindows
        ? firstPath.toLowerCase() == secondPath.toLowerCase()
        : firstPath == secondPath;
  }

  static Future<String> _uniqueConversionPath(String requestedPath) async {
    if (!await File(requestedPath).exists()) return requestedPath;
    final file = File(requestedPath);
    final fileName = file.uri.pathSegments.last;
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final extension = dotIndex > 0 ? fileName.substring(dotIndex) : '';
    for (var index = 2; ; index++) {
      final candidate =
          '${file.parent.path}${Platform.pathSeparator}$baseName ($index)$extension';
      if (!await File(candidate).exists()) return candidate;
    }
  }

  static Future<_ConversionOutputPlan> _conversionOutputPlan(
    String inputPath,
    String extension, {
    required bool deleteOriginal,
  }) async {
    final normalizedExt = extension.startsWith('.') ? extension : '.$extension';
    final inputFile = File(inputPath);
    final fileName = inputFile.uri.pathSegments.last;
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final requestedPath =
        '${inputFile.parent.path}${Platform.pathSeparator}$baseName$normalizedExt';

    if (_sameLocalPath(requestedPath, inputPath) && deleteOriginal) {
      final token = DateTime.now().microsecondsSinceEpoch;
      return _ConversionOutputPlan(
        workingPath:
            '${inputFile.parent.path}${Platform.pathSeparator}.$baseName.spotiflac-$token$normalizedExt',
        finalPath: inputPath,
      );
    }

    final finalPath = await _uniqueConversionPath(requestedPath);
    return _ConversionOutputPlan(workingPath: finalPath, finalPath: finalPath);
  }

  static Future<void> _cleanupConversionOutput(
    _ConversionOutputPlan plan,
  ) async {
    try {
      final output = File(plan.workingPath);
      if (await output.exists()) await output.delete();
    } catch (e) {
      _log.w('Failed to clean conversion output: $e');
    }
  }

  static Future<String?> _finalizeConversionOutput({
    required _ConversionOutputPlan plan,
    required String inputPath,
    required bool deleteOriginal,
  }) async {
    if (!await File(plan.workingPath).exists()) {
      _log.e('Converted output is missing: ${plan.workingPath}');
      return null;
    }

    if (plan.requiresPromotion) {
      final source = File(inputPath);
      final backupPath =
          '$inputPath.spotiflac-backup-${DateTime.now().microsecondsSinceEpoch}';
      final backup = File(backupPath);
      var sourceMovedToBackup = false;
      try {
        if (await source.exists()) {
          await source.rename(backupPath);
          sourceMovedToBackup = true;
        }
        await File(plan.workingPath).rename(plan.finalPath);
      } catch (e) {
        _log.e('Failed to replace original after conversion: $e');
        try {
          if (sourceMovedToBackup &&
              !await source.exists() &&
              await backup.exists()) {
            await backup.rename(inputPath);
          }
        } catch (restoreError) {
          _log.e('Failed to restore original conversion backup: $restoreError');
        }
        await _cleanupConversionOutput(plan);
        return null;
      }
      try {
        if (await backup.exists()) await backup.delete();
      } catch (e) {
        _log.w('Converted file is ready but backup cleanup failed: $e');
      }
      return plan.finalPath;
    }

    if (deleteOriginal && !_sameLocalPath(inputPath, plan.finalPath)) {
      try {
        final source = File(inputPath);
        if (await source.exists()) await source.delete();
      } catch (e) {
        _log.w('Failed to delete original after conversion: $e');
      }
    }
    return plan.finalPath;
  }

  static String _previewCommandForLog(String command) {
    final redacted = command
        .replaceAll(
          RegExp(r'-metadata\s+lyrics="[^"]*"', caseSensitive: false),
          '-metadata lyrics="<redacted>"',
        )
        .replaceAll(
          RegExp(r'-metadata\s+unsyncedlyrics="[^"]*"', caseSensitive: false),
          '-metadata unsyncedlyrics="<redacted>"',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (redacted.length <= _commandLogPreviewLength) {
      return redacted;
    }
    return '${redacted.substring(0, _commandLogPreviewLength)}...';
  }

  static String _nextTempEmbedPath(String tempDirPath, String extension) {
    final normalizedExt = extension.startsWith('.') ? extension : '.$extension';
    _tempEmbedCounter = (_tempEmbedCounter + 1) & 0x7fffffff;
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final processId = pid;
    return '$tempDirPath${Platform.pathSeparator}temp_embed_${timestamp}_${processId}_$_tempEmbedCounter$normalizedExt';
  }

  static List<String> _buildDecryptionKeyCandidates(String rawKey) {
    final candidates = <String>[];

    void addCandidate(String key) {
      final normalized = key.trim();
      if (normalized.isEmpty) return;
      if (!candidates.contains(normalized)) {
        candidates.add(normalized);
      }
    }

    final trimmed = rawKey.trim();
    if (trimmed.isEmpty) return candidates;

    addCandidate(trimmed);

    final noPrefix = trimmed.startsWith(RegExp(r'0x', caseSensitive: false))
        ? trimmed.substring(2)
        : trimmed;
    addCandidate(noPrefix);

    final compactHex = noPrefix.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (compactHex.isNotEmpty && compactHex.length.isEven) {
      addCandidate(compactHex);
    }

    try {
      final b64 = noPrefix.replaceAll(RegExp(r'\s+'), '');
      final decoded = base64Decode(b64);
      if (decoded.isNotEmpty) {
        final hex = decoded
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        if (hex.isNotEmpty) {
          addCandidate(hex);
        }
      }
    } catch (_) {}

    return candidates;
  }

  static Future<FFmpegResult> _execute(String command) async {
    try {
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      final output = await session.getOutput() ?? '';

      return FFmpegResult(
        success: ReturnCode.isSuccess(returnCode),
        returnCode: returnCode?.getValue() ?? -1,
        output: output,
      );
    } catch (e) {
      _log.e('FFmpeg execute error: $e');
      return FFmpegResult(success: false, returnCode: -1, output: e.toString());
    }
  }

  static Future<FFmpegResult> _executeWithArguments(
    List<String> arguments,
  ) async {
    try {
      final session = await FFmpegKit.executeWithArguments(arguments);
      final returnCode = await session.getReturnCode();
      final output = await session.getOutput() ?? '';

      return FFmpegResult(
        success: ReturnCode.isSuccess(returnCode),
        returnCode: returnCode?.getValue() ?? -1,
        output: output,
      );
    } catch (e) {
      _log.e('FFmpeg executeWithArguments error: $e');
      return FFmpegResult(success: false, returnCode: -1, output: e.toString());
    }
  }

  @visibleForTesting
  static List<String> buildCoverResizeArguments({
    required String inputPath,
    required String outputPath,
    required int maxDimension,
  }) {
    if (maxDimension < 64 || maxDimension > 8192) {
      throw ArgumentError.value(
        maxDimension,
        'maxDimension',
        'Must be between 64 and 8192 pixels',
      );
    }
    return [
      '-y',
      '-i',
      inputPath,
      '-map_metadata',
      '-1',
      '-an',
      '-sn',
      '-vf',
      'scale=$maxDimension:$maxDimension:'
          'force_original_aspect_ratio=decrease:flags=lanczos',
      '-frames:v',
      '1',
      '-update',
      '1',
      '-q:v',
      '2',
      outputPath,
    ];
  }

  /// Resizes cover art so its longest edge is [maxDimension].
  ///
  /// FFmpeg is allowed to upscale smaller sources because this is an explicit
  /// user choice. Aspect ratio is preserved and the result is written as the
  /// format implied by [outputPath].
  static Future<bool> resizeCoverArt({
    required String inputPath,
    required String outputPath,
    required int maxDimension,
  }) async {
    try {
      final source = File(inputPath);
      if (!await source.exists()) return false;

      final result = await _executeWithArguments(
        buildCoverResizeArguments(
          inputPath: inputPath,
          outputPath: outputPath,
          maxDimension: maxDimension,
        ),
      );
      final output = File(outputPath);
      final hasOutput = await output.exists() && await output.length() > 0;
      if (!result.success || !hasOutput) {
        _log.w(
          'Cover resize failed (${result.returnCode}): '
          '${_previewCommandForLog(result.output)}',
        );
        try {
          if (await output.exists()) await output.delete();
        } catch (_) {}
        return false;
      }
      return true;
    } catch (e) {
      _log.w('Cover resize failed: $e');
      try {
        final output = File(outputPath);
        if (await output.exists()) await output.delete();
      } catch (_) {}
      return false;
    }
  }

  @visibleForTesting
  static ({int width, int height})? imageDimensionsFromProperties(
    Map<dynamic, dynamic> properties,
  ) {
    final width = int.tryParse(properties['width']?.toString() ?? '');
    final height = int.tryParse(properties['height']?.toString() ?? '');
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return (width: width, height: height);
  }

  /// Reads image dimensions without decoding the full bitmap into Dart memory.
  static Future<({int width, int height})?> probeImageDimensions(
    String filePath,
  ) async {
    try {
      final session = await FFprobeKit.getMediaInformation(filePath);
      final info = session.getMediaInformation();
      if (info == null) return null;
      for (final stream in info.getStreams()) {
        final properties =
            stream.getAllProperties() ?? const <String, dynamic>{};
        final dimensions = imageDimensionsFromProperties(properties);
        if (dimensions != null) return dimensions;
      }
    } catch (e) {
      _log.w('Cover dimension probe failed for $filePath: $e');
    }
    return null;
  }

  static Future<String?> probePrimaryAudioCodec(String filePath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(filePath);
      final info = session.getMediaInformation();
      if (info == null) return null;

      for (final stream in info.getStreams()) {
        final props = stream.getAllProperties() ?? const <String, dynamic>{};
        if (props['codec_type']?.toString() != 'audio') continue;
        final codec = props['codec_name']?.toString().trim().toLowerCase();
        return codec == null || codec.isEmpty ? null : codec;
      }
    } catch (e) {
      _log.w('Audio codec probe failed for $filePath: $e');
    }
    return null;
  }

  static bool isLosslessAudioCodec(String? codec) {
    final normalized = codec?.trim().toLowerCase().replaceAll('-', '_') ?? '';
    if (normalized.isEmpty) return false;
    if (normalized.startsWith('pcm_')) return true;
    return const {
      'alac',
      'flac',
      'wavpack',
      'ape',
      'tta',
      'mlp',
      'truehd',
      'shorten',
    }.contains(normalized);
  }

  /// Probes the source audio bit depth (bits_per_raw_sample, falling back to
  /// bits_per_sample). Returns null when unknown.
  static Future<int?> probeBitDepth(String filePath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(filePath);
      final info = session.getMediaInformation();
      if (info == null) return null;
      for (final stream in info.getStreams()) {
        final props = stream.getAllProperties() ?? const <String, dynamic>{};
        if (props['codec_type']?.toString() != 'audio') continue;
        final raw = props['bits_per_raw_sample']?.toString();
        final bps = props['bits_per_sample']?.toString();
        final v = int.tryParse(raw ?? '') ?? int.tryParse(bps ?? '');
        if (v != null && v > 0) return v;
        return null;
      }
    } catch (e) {
      _log.w('Bit depth probe failed for $filePath: $e');
    }
    return null;
  }

  static Future<int?> probeSampleRate(String filePath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(filePath);
      final info = session.getMediaInformation();
      if (info == null) return null;
      for (final stream in info.getStreams()) {
        final props = stream.getAllProperties() ?? const <String, dynamic>{};
        if (props['codec_type']?.toString() != 'audio') continue;
        final value = int.tryParse(props['sample_rate']?.toString() ?? '');
        if (value != null && value > 0) return value;
        return null;
      }
    } catch (e) {
      _log.w('Sample rate probe failed for $filePath: $e');
    }
    return null;
  }

  /// Returns `true` when [filePath] starts with the native FLAC magic bytes
  /// (`fLaC`). Useful to distinguish a real FLAC file from a FLAC-in-MP4
  /// container that carries a `.flac` extension or claims codec=flac.
  static Future<bool> isNativeFlacFile(String filePath) async {
    try {
      final raf = await File(filePath).open();
      try {
        final header = await raf.read(4);
        return header.length == 4 &&
            header[0] == 0x66 && // 'f'
            header[1] == 0x4C && // 'L'
            header[2] == 0x61 && // 'a'
            header[3] == 0x43; // 'C'
      } finally {
        await raf.close();
      }
    } catch (e) {
      _log.w('Native FLAC magic probe failed for $filePath: $e');
      return false;
    }
  }

  static Future<_ResolvedLosslessConversionQuality> _resolveLosslessQuality({
    required String inputPath,
    required LosslessConversionQuality quality,
    int? sourceBitDepth,
  }) async {
    final probedBitDepth =
        sourceBitDepth ??
        (quality.maxBitDepth != null ? await probeBitDepth(inputPath) : null);
    final probedSampleRate = quality.maxSampleRate != null
        ? await probeSampleRate(inputPath)
        : null;

    int? targetBitDepth;
    if (quality.maxBitDepth != null &&
        (probedBitDepth == null || probedBitDepth > quality.maxBitDepth!)) {
      targetBitDepth = quality.maxBitDepth;
    }

    int? targetSampleRate;
    if (quality.maxSampleRate != null &&
        (probedSampleRate == null ||
            probedSampleRate > quality.maxSampleRate!)) {
      targetSampleRate = quality.maxSampleRate;
    }

    return _ResolvedLosslessConversionQuality(
      targetBitDepth: targetBitDepth,
      targetSampleRate: targetSampleRate,
    );
  }

  static void _appendLosslessCodecQualityArguments(
    List<String> arguments, {
    required String codec,
    int? targetBitDepth,
    int? targetSampleRate,
    LosslessConversionProcessing processing =
        const LosslessConversionProcessing(),
  }) {
    final sampleFmt = _losslessOutputSampleFormat(
      codec: codec,
      targetBitDepth: targetBitDepth,
    );
    _appendLosslessAresampleFilter(
      arguments,
      targetSampleRate: targetSampleRate,
      outputSampleFormat: sampleFmt,
      processing: processing,
    );
    if (targetBitDepth == null || targetBitDepth <= 0) return;

    if (codec == 'flac') {
      if (targetBitDepth <= 16) {
        arguments
          ..add('-sample_fmt')
          ..add('s16');
      } else if (targetBitDepth <= 24) {
        arguments
          ..add('-sample_fmt')
          ..add('s32')
          ..add('-bits_per_raw_sample')
          ..add('24');
      }
      return;
    }

    if (codec == 'alac') {
      if (targetBitDepth <= 16) {
        arguments
          ..add('-sample_fmt')
          ..add('s16p');
      } else if (targetBitDepth <= 24) {
        arguments
          ..add('-sample_fmt')
          ..add('s32p')
          ..add('-bits_per_raw_sample')
          ..add('24');
      }
    }
  }

  static String? _losslessOutputSampleFormat({
    required String codec,
    int? targetBitDepth,
  }) {
    if (targetBitDepth == null || targetBitDepth <= 0) return null;

    if (codec == 'flac') {
      return targetBitDepth <= 16 ? 's16' : 's32';
    }
    if (codec == 'alac') {
      return targetBitDepth <= 16 ? 's16p' : 's32p';
    }
    if (codec == 'pcm') {
      return targetBitDepth <= 16 ? 's16' : 's32';
    }
    return null;
  }

  static void _appendLosslessAresampleFilter(
    List<String> arguments, {
    int? targetSampleRate,
    String? outputSampleFormat,
    LosslessConversionProcessing processing =
        const LosslessConversionProcessing(),
  }) {
    final hasSampleRate = targetSampleRate != null && targetSampleRate > 0;
    final hasSampleFormat =
        outputSampleFormat != null && outputSampleFormat.trim().isNotEmpty;
    if (!hasSampleRate && !hasSampleFormat && !processing.hasDither) return;

    final options = <String>[
      ...losslessResamplerFilterOptions(processing),
      if (hasSampleRate) 'osr=$targetSampleRate',
      if (hasSampleFormat) 'osf=${outputSampleFormat.trim()}',
      if (processing.hasDither) 'dither_method=${processing.normalizedDither}',
    ];

    arguments
      ..add('-af')
      ..add('aresample=${options.join(':')}');
  }

  static Future<String?> convertM4aToFlac(String inputPath) async {
    final outputPath = _buildOutputPath(inputPath, '.flac');

    final command =
        '-v error -xerror -i "$inputPath" -c:a flac -compression_level 8 "$outputPath" -y';

    final result = await _execute(command);

    if (result.success) {
      try {
        await File(inputPath).delete();
      } catch (_) {}
      return outputPath;
    }

    _log.e('M4A to FLAC conversion failed: ${result.output}');
    return null;
  }

  static Future<String?> convertM4aToLossy(
    String inputPath, {
    required String format,
    String? bitrate,
    bool deleteOriginal = true,
  }) async {
    final normalizedFormat = format.toLowerCase();
    String bitrateValue = normalizedFormat == 'opus' ? '128k' : '320k';
    if (bitrate != null && bitrate.contains('_')) {
      final parts = bitrate.split('_');
      if (parts.length == 2) {
        bitrateValue = '${parts[1]}k';
      }
    }

    final extension = switch (normalizedFormat) {
      'opus' => '.opus',
      'aac' || 'm4a' => '.m4a',
      _ => '.mp3',
    };
    final outputPlan = await _conversionOutputPlan(
      inputPath,
      extension,
      deleteOriginal: deleteOriginal,
    );
    final outputPath = outputPlan.workingPath;

    String command;
    if (normalizedFormat == 'opus') {
      command =
          '-v error -hide_banner -i "$inputPath" -codec:a libopus -b:a $bitrateValue -vbr on -compression_level 10 -map 0:a "$outputPath" -y';
    } else if (normalizedFormat == 'aac' || normalizedFormat == 'm4a') {
      command =
          '-v error -hide_banner -i "$inputPath" -codec:a aac -b:a $bitrateValue -map 0:a -f mp4 "$outputPath" -y';
    } else {
      command =
          '-v error -hide_banner -i "$inputPath" -codec:a libmp3lame -b:a $bitrateValue -map 0:a -id3v2_version 3 "$outputPath" -y';
    }

    final result = await _execute(command);

    if (result.success) {
      return _finalizeConversionOutput(
        plan: outputPlan,
        inputPath: inputPath,
        deleteOriginal: deleteOriginal,
      );
    }

    _log.e('M4A to $normalizedFormat conversion failed: ${result.output}');
    await _cleanupConversionOutput(outputPlan);
    return null;
  }

  static Future<String?> decryptWithDescriptor({
    required String inputPath,
    required DownloadDecryptionDescriptor descriptor,
    bool deleteOriginal = true,
  }) async {
    final key = descriptor.key.trim();

    switch (descriptor.normalizedStrategy) {
      case _genericMovKeyDecryptionStrategy:
        if (key.isEmpty) {
          return inputPath;
        }
        return _decryptMovKeyFile(
          inputPath: inputPath,
          decryptionKey: key,
          inputFormat: descriptor.inputFormat,
          outputExtension: descriptor.outputExtension,
          deleteOriginal: deleteOriginal,
        );
      default:
        _log.e(
          'Unsupported download decryption strategy: ${descriptor.strategy}',
        );
        return null;
    }
  }

  static String _resolvePreferredDecryptionExtension(
    String inputPath,
    String? requestedExtension,
  ) {
    final trimmedRequested = (requestedExtension ?? '').trim();
    if (trimmedRequested.isNotEmpty) {
      return trimmedRequested.startsWith('.')
          ? trimmedRequested
          : '.$trimmedRequested';
    }

    return inputPath.toLowerCase().endsWith('.m4a')
        ? '.flac'
        : inputPath.toLowerCase().endsWith('.flac')
        ? '.flac'
        : inputPath.toLowerCase().endsWith('.mp3')
        ? '.mp3'
        : inputPath.toLowerCase().endsWith('.opus')
        ? '.opus'
        : inputPath.toLowerCase().endsWith('.mp4')
        ? '.mp4'
        : '.flac';
  }

  static Future<String?> _decryptMovKeyFile({
    required String inputPath,
    required String decryptionKey,
    String? inputFormat,
    String? outputExtension,
    bool deleteOriginal = true,
  }) async {
    final preferredExt = _resolvePreferredDecryptionExtension(
      inputPath,
      outputExtension,
    );
    var tempOutput = _buildOutputPath(inputPath, preferredExt);
    final demuxerFormat = (inputFormat ?? '').trim().isNotEmpty
        ? inputFormat!.trim()
        : 'mov';

    String buildDecryptCommand(
      String outputPath, {
      required bool mapAudioOnly,
      required String key,
      bool forceMovMuxer = false,
    }) {
      final audioMap = mapAudioOnly ? '-map 0:a ' : '';
      // Force MOV demuxer: -decryption_key is only supported by the MOV/MP4
      // demuxer. The input may carry a .flac extension (SAF mode) while actually
      // containing an encrypted M4A stream, so we must override auto-detection.
      //
      // When the requested output is a native .flac we also force the flac
      // muxer (-f flac). Without it, FFmpeg infers the muxer from the output
      // extension AND keeps the input container's stream layout, which for
      // FLAC-in-MP4 sources would still emit an ISO-BMFF payload under a
      // .flac filename. That file fails native FLAC tag writers later on.
      //
      // forceMovMuxer routes through the MOV muxer for codecs the MP4 muxer
      // rejects (e.g. AC-4), keeping the .mp4 filename.
      final muxerOverride = forceMovMuxer
          ? '-f mov '
          : outputPath.toLowerCase().endsWith('.flac')
          ? '-f flac '
          : '';
      return '-v error -decryption_key "$key" -f $demuxerFormat -i "$inputPath" $audioMap-c copy $muxerOverride"$outputPath" -y';
    }

    final keyCandidates = _buildDecryptionKeyCandidates(decryptionKey);
    if (keyCandidates.isEmpty) {
      _log.e('No usable decryption key candidates');
      return null;
    }

    FFmpegResult? lastResult;
    var decryptSucceeded = false;

    for (final keyCandidate in keyCandidates) {
      _log.d(
        'Executing FFmpeg decrypt command (key length: ${keyCandidate.length})',
      );
      var result = await _execute(
        buildDecryptCommand(
          tempOutput,
          mapAudioOnly: preferredExt == '.flac',
          key: keyCandidate,
        ),
      );

      // Fallback for uncommon streams that cannot be remuxed into FLAC.
      if (!result.success && preferredExt == '.flac') {
        final fallbackOutput = _buildOutputPath(inputPath, '.m4a');
        final fallbackResult = await _execute(
          buildDecryptCommand(
            fallbackOutput,
            mapAudioOnly: false,
            key: keyCandidate,
          ),
        );
        if (fallbackResult.success) {
          tempOutput = fallbackOutput;
          result = fallbackResult;
        }
      }

      // Second fallback: use .mp4 (mp4 muxer) for codecs not supported by
      // the ipod muxer (e.g. eac3/Dolby Digital Plus, mha1/Dolby Atmos).
      if (!result.success &&
          (preferredExt == '.flac' || preferredExt == '.m4a')) {
        final mp4FallbackOutput = _buildOutputPath(inputPath, '.mp4');
        final mp4FallbackResult = await _execute(
          buildDecryptCommand(
            mp4FallbackOutput,
            mapAudioOnly: false,
            key: keyCandidate,
          ),
        );
        if (mp4FallbackResult.success) {
          tempOutput = mp4FallbackOutput;
          result = mp4FallbackResult;
        }
      }

      // Final fallback: force the MOV muxer for codecs the MP4 muxer rejects
      // (e.g. AC-4). MOV stores the codec params and keeps the .mp4 filename.
      if (!result.success) {
        final movFallbackOutput = _buildOutputPath(inputPath, '.mp4');
        final movFallbackResult = await _execute(
          buildDecryptCommand(
            movFallbackOutput,
            mapAudioOnly: false,
            key: keyCandidate,
            forceMovMuxer: true,
          ),
        );
        if (movFallbackResult.success) {
          tempOutput = movFallbackOutput;
          result = movFallbackResult;
        }
      }

      if (result.success) {
        decryptSucceeded = true;
        lastResult = result;
        break;
      }

      try {
        final tempFile = File(tempOutput);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      lastResult = result;
    }

    if (!decryptSucceeded) {
      _log.e('FFmpeg decrypt failed: ${lastResult?.output ?? 'unknown error'}');
      return null;
    }

    try {
      final tempFile = File(tempOutput);
      final inputFile = File(inputPath);
      if (!await tempFile.exists()) {
        _log.e('Decrypted output file not found: $tempOutput');
        return null;
      }

      if (deleteOriginal && await inputFile.exists()) {
        await inputFile.delete();
      }
      return tempOutput;
    } catch (e) {
      _log.e('Failed to finalize decrypted file: $e');
      return null;
    }
  }

  static bool isActiveLiveDecryptedUrl(String url) {
    final active = _activeLiveDecryptUrl;
    if (active == null || active.isEmpty) return false;
    return active == url.trim();
  }

  static bool isActiveNativeDashManifestUrl(String url) {
    final activeUrl = _activeNativeDashManifestUrl;
    if (activeUrl == null || activeUrl.isEmpty) return false;

    final normalized = url.trim();
    if (activeUrl == normalized) return true;

    try {
      final activePath = Uri.parse(activeUrl).toFilePath();
      final incomingPath = Uri.parse(normalized).toFilePath();
      return activePath == incomingPath;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> prepareDashManifestForNativePlayback({
    required String manifestPayload,
    bool registerAsActive = true,
  }) async {
    final rawPayload = manifestPayload.trim();
    if (rawPayload.isEmpty) return null;

    final payload = rawPayload.startsWith('MANIFEST:')
        ? rawPayload.substring('MANIFEST:'.length)
        : rawPayload;

    final manifestPath = await _writeTempManifestFile(payload);
    if (manifestPath == null) {
      _log.e('Failed to prepare DASH manifest for native playback');
      return null;
    }

    final manifestUrl = Uri.file(manifestPath).toString();
    _preparedNativeDashManifestPaths.add(manifestPath);
    if (registerAsActive) {
      await activatePreparedNativeDashManifest(manifestUrl);
    }
    return manifestUrl;
  }

  static Future<void> activatePreparedNativeDashManifest(String url) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return;

    final manifestPath = _nativeDashManifestPathFromUrl(normalized);
    if (manifestPath == null ||
        !_preparedNativeDashManifestPaths.contains(manifestPath)) {
      return;
    }

    final previousPath = _activeNativeDashManifestPath;
    _activeNativeDashManifestPath = manifestPath;
    _activeNativeDashManifestUrl = Uri.file(manifestPath).toString();

    if (previousPath != null &&
        previousPath.isNotEmpty &&
        previousPath != manifestPath) {
      _preparedNativeDashManifestPaths.remove(previousPath);
      await _deleteNativeDashManifestFile(previousPath);
    }
  }

  static Future<void> stopNativeDashManifestPlayback() async {
    final manifestPath = _activeNativeDashManifestPath;
    _activeNativeDashManifestPath = null;
    _activeNativeDashManifestUrl = null;

    if (manifestPath == null || manifestPath.isEmpty) return;
    _preparedNativeDashManifestPaths.remove(manifestPath);
    await _deleteNativeDashManifestFile(manifestPath);
  }

  static Future<void> cleanupInactivePreparedNativeDashManifests() async {
    final activePath = _activeNativeDashManifestPath;
    final stalePaths = _preparedNativeDashManifestPaths
        .where((path) => path != activePath)
        .toList(growable: false);

    for (final path in stalePaths) {
      _preparedNativeDashManifestPaths.remove(path);
      await _deleteNativeDashManifestFile(path);
    }
  }

  static String? _nativeDashManifestPathFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme.toLowerCase() != 'file') {
        return null;
      }
      final path = uri.toFilePath();
      return path.trim().isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteNativeDashManifestFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static Future<void> stopLiveDecryptedStream() async {
    final session = _activeLiveDecryptSession;
    final tempInputPath = _activeLiveTempInputPath;
    _activeLiveDecryptSession = null;
    _activeLiveDecryptUrl = null;
    _activeLiveTempInputPath = null;

    if (session != null) {
      try {
        await session.cancel();
      } catch (e) {
        final sessionId = session.getSessionId();
        if (sessionId != null) {
          try {
            await FFmpegKit.cancel(sessionId);
          } catch (_) {}
        }
        _log.w('Failed to stop live decrypt session cleanly: $e');
      }
    }

    if (tempInputPath != null && tempInputPath.isNotEmpty) {
      try {
        final file = File(tempInputPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  static Future<LiveDecryptedStreamResult?> startDashLiveStream({
    required String manifestPayload,
    String preferredFormat = 'm4a',
  }) async {
    final rawPayload = manifestPayload.trim();
    if (rawPayload.isEmpty) return null;

    final payload = rawPayload.startsWith('MANIFEST:')
        ? rawPayload.substring('MANIFEST:'.length)
        : rawPayload;

    final manifestPath = await _writeTempManifestFile(payload);
    if (manifestPath == null) {
      _log.e('Failed to prepare DASH manifest for live stream');
      return null;
    }

    await stopLiveDecryptedStream();
    await stopNativeDashManifestPlayback();

    final attempts = _buildLiveDashFormatAttempts(preferredFormat);
    for (final format in attempts) {
      final stream = await _tryStartLiveDashAttempt(
        manifestPath: manifestPath,
        format: format,
      );
      if (stream != null) {
        _activeLiveDecryptSession = stream.session;
        _activeLiveDecryptUrl = stream.localUrl;
        _activeLiveTempInputPath = manifestPath;
        return stream;
      }
    }

    try {
      final file = File(manifestPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _writeTempManifestFile(String payload) async {
    if (payload.trim().isEmpty) return null;

    Uint8List bytes;
    try {
      bytes = base64Decode(payload);
    } catch (_) {
      bytes = Uint8List.fromList(utf8.encode(payload));
    }

    final manifestText = utf8.decode(bytes, allowMalformed: true).trim();
    if (manifestText.isEmpty) return null;

    final tempDir = await getTemporaryDirectory();
    final manifestPath =
        '${tempDir.path}${Platform.pathSeparator}dash_${DateTime.now().microsecondsSinceEpoch}.mpd';
    await File(manifestPath).writeAsString(manifestText, flush: true);
    return manifestPath;
  }

  static List<_LiveDecryptFormat> _buildLiveDashFormatAttempts(
    String preferredFormat,
  ) {
    final normalized = preferredFormat.trim().toLowerCase();
    if (normalized == 'flac') {
      return const [_LiveDecryptFormat.flac, _LiveDecryptFormat.m4a];
    }
    return const [_LiveDecryptFormat.m4a, _LiveDecryptFormat.flac];
  }

  static Future<bool> _awaitLiveTunnelReady(FFmpegSession session) async {
    final deadline = DateTime.now().add(_liveTunnelStartupTimeout);
    var seenRunning = false;

    while (DateTime.now().isBefore(deadline)) {
      final state = await session.getState();
      if (state == SessionState.running) {
        seenRunning = true;
        break;
      }
      if (state != SessionState.created) {
        return false;
      }
      await Future<void>.delayed(_liveTunnelStartupPollInterval);
    }

    if (!seenRunning) {
      return false;
    }

    await Future<void>.delayed(_liveTunnelStabilizationDelay);
    return (await session.getState()) == SessionState.running;
  }

  static Future<LiveDecryptedStreamResult?> _tryStartLiveDashAttempt({
    required String manifestPath,
    required _LiveDecryptFormat format,
  }) async {
    final port = await _allocateLoopbackPort();
    final ext = format == _LiveDecryptFormat.flac ? 'flac' : 'm4a';
    final mimeType = format == _LiveDecryptFormat.flac
        ? 'audio/flac'
        : 'audio/mp4';
    final localUrl = 'http://localhost:$port/stream.$ext';

    final commandArguments = <String>[
      '-nostdin',
      '-hide_banner',
      '-loglevel',
      'error',
      '-protocol_whitelist',
      'file,http,https,tcp,tls,crypto,data',
      '-i',
      manifestPath,
      '-map',
      '0:a:0',
      '-c:a',
      'copy',
      if (format == _LiveDecryptFormat.flac) ...['-f', 'flac'],
      if (format == _LiveDecryptFormat.m4a) ...[
        '-movflags',
        '+frag_keyframe+empty_moov+default_base_moof',
        '-f',
        'mp4',
      ],
      '-content_type',
      mimeType,
      '-listen',
      '1',
      localUrl,
    ];

    _log.d(
      'Starting DASH tunnel: ${_previewCommandForLog(commandArguments.join(' '))}',
    );

    final session = await FFmpegKit.executeWithArgumentsAsync(commandArguments);
    final isReady = await _awaitLiveTunnelReady(session);
    if (isReady) {
      return LiveDecryptedStreamResult(
        localUrl: localUrl,
        format: ext,
        session: session,
      );
    }

    final state = await session.getState();
    final output = (await session.getOutput() ?? '').trim();
    if (output.isNotEmpty) {
      _log.w('DASH tunnel failed ($ext): $output');
    } else {
      _log.w('DASH tunnel failed ($ext) with session state: $state');
    }

    try {
      await session.cancel();
    } catch (_) {}
    return null;
  }

  static Future<LiveDecryptedStreamResult?> startEncryptedLiveDecryptedStream({
    required String encryptedStreamUrl,
    required String decryptionKey,
    String preferredFormat = 'flac',
  }) async {
    final inputUrl = encryptedStreamUrl.trim();
    if (inputUrl.isEmpty) return null;

    final keyCandidates = _buildDecryptionKeyCandidates(decryptionKey);
    if (keyCandidates.isEmpty) {
      _log.e('No usable decryption key candidates for live stream');
      return null;
    }

    await stopLiveDecryptedStream();

    final attempts = _buildLiveDecryptFormatAttempts(preferredFormat);
    for (final format in attempts) {
      for (final keyCandidate in keyCandidates) {
        final stream = await _tryStartLiveDecryptAttempt(
          inputUrl: inputUrl,
          decryptionKey: keyCandidate,
          format: format,
        );
        if (stream != null) {
          _activeLiveDecryptSession = stream.session;
          _activeLiveDecryptUrl = stream.localUrl;
          _activeLiveTempInputPath = null;
          return stream;
        }
      }
    }

    return null;
  }

  static List<_LiveDecryptFormat> _buildLiveDecryptFormatAttempts(
    String preferredFormat,
  ) {
    final normalized = preferredFormat.trim().toLowerCase();
    if (normalized == 'm4a' || normalized == 'mp4' || normalized == 'aac') {
      return const [_LiveDecryptFormat.m4a, _LiveDecryptFormat.flac];
    }
    return const [_LiveDecryptFormat.flac, _LiveDecryptFormat.m4a];
  }

  static Future<LiveDecryptedStreamResult?> _tryStartLiveDecryptAttempt({
    required String inputUrl,
    required String decryptionKey,
    required _LiveDecryptFormat format,
  }) async {
    final port = await _allocateLoopbackPort();
    final ext = format == _LiveDecryptFormat.flac ? 'flac' : 'm4a';
    final mimeType = format == _LiveDecryptFormat.flac
        ? 'audio/flac'
        : 'audio/mp4';
    final localUrl = 'http://localhost:$port/stream.$ext';

    final commandArguments = <String>[
      '-nostdin',
      '-hide_banner',
      '-loglevel',
      'error',
      '-decryption_key',
      decryptionKey,
      '-i',
      inputUrl,
      '-map',
      '0:a:0',
      '-c:a',
      'copy',
      if (format == _LiveDecryptFormat.flac) ...['-f', 'flac'],
      if (format == _LiveDecryptFormat.m4a) ...[
        '-movflags',
        '+frag_keyframe+empty_moov+default_base_moof',
        '-f',
        'mp4',
      ],
      '-content_type',
      mimeType,
      '-listen',
      '1',
      localUrl,
    ];

    _log.d(
      'Starting live decrypt tunnel: ${_previewCommandForLog(commandArguments.join(' '))}',
    );

    final session = await FFmpegKit.executeWithArgumentsAsync(commandArguments);
    final isReady = await _awaitLiveTunnelReady(session);
    if (isReady) {
      return LiveDecryptedStreamResult(
        localUrl: localUrl,
        format: ext,
        session: session,
      );
    }

    final state = await session.getState();
    final output = (await session.getOutput() ?? '').trim();
    if (output.isNotEmpty) {
      _log.w('Live decrypt attempt failed ($ext): $output');
    } else {
      _log.w('Live decrypt attempt failed ($ext) with session state: $state');
    }

    try {
      await session.cancel();
    } catch (_) {}
    return null;
  }

  static Future<int> _allocateLoopbackPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static Future<bool> isAvailable() async {
    try {
      final version = await FFmpegKitConfig.getFFmpegVersion();
      return version?.isNotEmpty ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Scan an audio file for EBU R128 loudness and compute ReplayGain values.
  ///
  /// Uses the FFmpeg `ebur128` audio filter to measure integrated loudness (LUFS)
  /// and true peak. ReplayGain reference level is -18 LUFS (≈ 89 dB SPL).
  ///
  static Future<ReplayGainResult?> scanReplayGain(String filePath) async {
    // -nostats suppresses the interactive progress line.
    // ebur128=peak=true prints integrated loudness + true peak.
    // framelog=quiet suppresses per-frame measurements (very verbose),
    // keeping only the final summary which we parse.
    final command =
        '-hide_banner -nostats -i "$filePath" -filter_complex ebur128=peak=true:framelog=quiet -f null -';

    _log.d(
      'Scanning ReplayGain for: ${filePath.split(Platform.pathSeparator).last}',
    );
    final result = await _execute(command);

    // FFmpeg writes ebur128 stats to stderr, which ends up in the output.
    // Even on "failure" return code, the output may contain valid data
    // because -f null always "fails" on some FFmpeg builds.
    final output = result.output;

    final integratedMatch = RegExp(
      r'I:\s+(-?\d+\.?\d*)\s+LUFS',
    ).allMatches(output);
    if (integratedMatch.isEmpty) {
      _log.w('ReplayGain scan: could not parse integrated loudness');
      return null;
    }
    // Take the last match (the summary, not per-segment values)
    final integratedLufs = double.tryParse(integratedMatch.last.group(1) ?? '');
    if (integratedLufs == null) {
      _log.w('ReplayGain scan: invalid integrated loudness value');
      return null;
    }

    // Parse true peak: "Peak:      0.9 dBFS" or "True peak:\n    Peak:    -0.3 dBFS"
    // The ebur128 filter with peak=true outputs per-channel true peak.
    // We want the highest (maximum) true peak across all channels.
    double? truePeakDbfs;
    final peakMatches = RegExp(
      r'Peak:\s+(-?\d+\.?\d*)\s+dBFS',
    ).allMatches(output);
    for (final m in peakMatches) {
      final val = double.tryParse(m.group(1) ?? '');
      if (val != null) {
        if (truePeakDbfs == null || val > truePeakDbfs) {
          truePeakDbfs = val;
        }
      }
    }

    const replayGainReferenceLufs = -18.0;
    final gainDb = replayGainReferenceLufs - integratedLufs;

    // Convert true peak from dBFS to linear ratio.
    // If no true peak was found, fall back to 1.0 (0 dBFS).
    double peakLinear;
    if (truePeakDbfs != null) {
      peakLinear = math.pow(10, truePeakDbfs / 20.0).toDouble();
    } else {
      peakLinear = 1.0;
    }

    final trackGain =
        '${gainDb >= 0 ? "+" : ""}${gainDb.toStringAsFixed(2)} dB';
    final trackPeak = peakLinear.toStringAsFixed(6);

    _log.i(
      'ReplayGain scan result: gain=$trackGain, peak=$trackPeak (integrated=${integratedLufs.toStringAsFixed(1)} LUFS)',
    );

    return ReplayGainResult(
      trackGain: trackGain,
      trackPeak: trackPeak,
      integratedLufs: integratedLufs,
      truePeakLinear: peakLinear,
    );
  }

  /// Convert a ReplayGain gain value (dB, referenced to -18 LUFS) into an Opus
  /// R128 gain tag value (Q7.8 fixed point integer, referenced to -23 LUFS).
  ///
  /// Opus players read `R128_TRACK_GAIN` / `R128_ALBUM_GAIN` per RFC 7845, not
  /// the `REPLAYGAIN_*` dB strings. The reference levels differ by exactly 5 dB
  /// (-18 vs -23 LUFS), so the R128 gain equals the ReplayGain value minus 5 dB,
  /// stored as `round(dB * 256)`.
  static String? replayGainDbToR128(String replayGainDb) {
    final match = RegExp(r'-?\d+\.?\d*').firstMatch(replayGainDb);
    if (match == null) return null;
    final rgDb = double.tryParse(match.group(0) ?? '');
    if (rgDb == null) return null;
    final r128Db = rgDb - 5.0;
    return (r128Db * 256).round().toString();
  }

  /// Write album ReplayGain tags to a file via FFmpeg.
  ///
  /// For local files, replaces the file in-place and returns `true`.
  /// When [returnTempPath] is `true` (for SAF content:// URIs), the method
  /// skips the file replacement and returns the temp output path as a String
  /// via [tempOutputPath].  The caller is responsible for writing the temp
  /// file to the SAF URI and cleaning it up.
  static Future<bool> writeAlbumReplayGainTags(
    String filePath,
    String albumGain,
    String albumPeak, {
    bool returnTempPath = false,
    void Function(String tempPath)? onTempReady,
  }) => _writeReplayGainTags(
    filePath,
    'Album',
    albumGain,
    albumPeak,
    returnTempPath: returnTempPath,
    onTempReady: onTempReady,
  );

  /// Write track ReplayGain tags to a file via FFmpeg, replacing it in place.
  ///
  /// Used for formats that are not handled by the native tag writers
  /// (MP3/Opus). All existing streams and metadata are preserved via
  /// `-map 0 -c copy -map_metadata 0`; only the REPLAYGAIN_TRACK_* fields are
  /// added/overwritten. Returns `true` when the file was rewritten in place.
  static Future<bool> writeTrackReplayGainTags(
    String filePath,
    String trackGain,
    String trackPeak,
  ) => _writeReplayGainTags(filePath, 'Track', trackGain, trackPeak);

  /// Shared implementation for album/track ReplayGain tagging.
  /// [scope] is 'Album' or 'Track'; it selects the REPLAYGAIN_*/R128_* tags.
  static Future<bool> _writeReplayGainTags(
    String filePath,
    String scope,
    String gain,
    String peak, {
    bool returnTempPath = false,
    void Function(String tempPath)? onTempReady,
  }) async {
    final ext = filePath.contains('.')
        ? '.${filePath.split('.').last}'
        : '.tmp';
    final tempDir = await getTemporaryDirectory();
    final tempOutput = _nextTempEmbedPath(tempDir.path, ext);
    final tag = scope.toUpperCase();
    final arguments = <String>[
      '-v',
      'error',
      '-hide_banner',
      '-i',
      filePath,
      '-map',
      '0',
      '-c',
      'copy',
      '-map_metadata',
      '0',
      '-metadata',
      'REPLAYGAIN_${tag}_GAIN=$gain',
      '-metadata',
      'REPLAYGAIN_${tag}_PEAK=$peak',
    ];

    if (ext.toLowerCase() == '.opus') {
      final r128 = replayGainDbToR128(gain);
      if (r128 != null) {
        arguments
          ..add('-metadata')
          ..add('R128_${tag}_GAIN=$r128');
      }
    }

    arguments
      ..add(tempOutput)
      ..add('-y');

    _log.d('Writing ${scope.toLowerCase()} ReplayGain tags via FFmpeg');
    final result = await _executeWithArguments(arguments);

    if (result.success) {
      if (returnTempPath) {
        try {
          if (await File(tempOutput).exists()) {
            onTempReady?.call(tempOutput);
            return true;
          }
        } catch (e) {
          _log.w(
            'Failed to replace file with ${scope.toLowerCase()} ReplayGain: $e',
          );
        }
      } else if (await _promoteTempOutput(
        tempOutput,
        filePath,
        onError: (e) => _log.w(
          'Failed to replace file with ${scope.toLowerCase()} ReplayGain: $e',
        ),
      )) {
        _log.d('$scope ReplayGain tags written successfully');
        return true;
      }
    }

    try {
      final tempFile = File(tempOutput);
      if (await tempFile.exists()) await tempFile.delete();
    } catch (_) {}

    return false;
  }

  /// Replace [targetPath] with the successful FFmpeg temp output at
  /// [tempOutput]. Returns `true` when the target was replaced. The temp
  /// file is always cleaned up, including when the replacement fails.
  static Future<bool> _promoteTempOutput(
    String tempOutput,
    String targetPath, {
    void Function()? onMissing,
    required void Function(Object e) onError,
  }) async {
    try {
      final tempFile = File(tempOutput);
      if (await tempFile.exists()) {
        final originalFile = File(targetPath);
        if (await originalFile.exists()) {
          await originalFile.delete();
        }
        await tempFile.copy(targetPath);
        await tempFile.delete();
        return true;
      }
      onMissing?.call();
      return false;
    } catch (e) {
      onError(e);
      return false;
    } finally {
      try {
        final tempFile = File(tempOutput);
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
    }
  }

  /// Map input #1 (the cover image) as attached picture art.
  static void _appendCoverInputArgs(
    List<String> arguments, {
    String map = '1:v',
    String disposition = '-disposition:v:0',
  }) {
    arguments
      ..add('-map')
      ..add(map)
      ..add('-c:v')
      ..add('copy')
      ..add(disposition)
      ..add('attached_pic')
      ..add('-metadata:s:v')
      ..add('title=Album cover')
      ..add('-metadata:s:v')
      ..add('comment=Cover (front)');
  }

  static Future<String?> embedMetadata({
    required String flacPath,
    String? coverPath,
    Map<String, String>? metadata,
    String artistTagMode = artistTagModeJoined,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final tempOutput = _nextTempEmbedPath(tempDir.path, '.flac');
    final arguments = <String>['-v', 'error', '-hide_banner', '-i', flacPath];

    if (coverPath != null) {
      arguments
        ..add('-i')
        ..add(coverPath);
    }

    arguments
      ..add('-map')
      ..add('0:a');

    if (coverPath != null) {
      _appendCoverInputArgs(
        arguments,
        map: '1:0',
        disposition: '-disposition:v',
      );
    }

    arguments
      ..add('-c:a')
      ..add('copy');

    if (metadata != null) {
      AudioMetadataMapper.appendVorbisMetadataArguments(
        arguments,
        metadata,
        artistTagMode: artistTagMode,
      );
    }

    arguments
      ..add(tempOutput)
      ..add('-y');

    _log.d('Executing FFmpeg FLAC embed command');
    final result = await _executeWithArguments(arguments);

    if (result.success) {
      final promoted = await _promoteTempOutput(
        tempOutput,
        flacPath,
        onMissing: () => _log.e('Temp output file not found: $tempOutput'),
        onError: (e) =>
            _log.e('Failed to replace file after metadata embed: $e'),
      );
      return promoted ? flacPath : null;
    }

    try {
      final tempFile = File(tempOutput);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      _log.w('Failed to cleanup temp file: $e');
    }

    _log.e('Metadata/Cover embed failed: ${result.output}');
    return null;
  }

  static Future<String?> embedMetadataToMp3({
    required String mp3Path,
    String? coverPath,
    Map<String, String>? metadata,
    bool preserveMetadata = false,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final tempOutput = _nextTempEmbedPath(tempDir.path, '.mp3');
    final lyrics = AudioMetadataMapper.extractLyricsForId3(metadata);

    // Try with -c:a copy first (fastest, preserves original codec)
    var result = await _runMp3Embed(
      mp3Path: mp3Path,
      tempOutput: tempOutput,
      coverPath: coverPath,
      metadata: metadata,
      preserveMetadata: preserveMetadata,
      audioCodec: 'copy',
    );

    if (result.success) {
      final embeddedPath = await _finalizeMp3Embed(mp3Path, tempOutput);
      if (embeddedPath != null && lyrics != null) {
        await _ensureMp3UnsyncedLyricsFrame(embeddedPath, lyrics);
      }
      return embeddedPath;
    }

    // If copy failed (e.g. AAC/Opus in .mp3 container), re-encode to real MP3
    final output = result.output;
    if (output.contains('Invalid audio stream') ||
        output.contains('incorrect codec parameters')) {
      _log.w('MP3 copy failed (codec mismatch), re-encoding with libmp3lame');

      try {
        final tempFile = File(tempOutput);
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}

      final reencodeOutput = _nextTempEmbedPath(tempDir.path, '.mp3');
      result = await _runMp3Embed(
        mp3Path: mp3Path,
        tempOutput: reencodeOutput,
        coverPath: coverPath,
        metadata: metadata,
        preserveMetadata: preserveMetadata,
        audioCodec: 'libmp3lame',
        audioBitrate: '192k', // AAC 128kbps ≈ MP3 192kbps equivalent
      );

      if (result.success) {
        final embeddedPath = await _finalizeMp3Embed(mp3Path, reencodeOutput);
        if (embeddedPath != null && lyrics != null) {
          await _ensureMp3UnsyncedLyricsFrame(embeddedPath, lyrics);
        }
        return embeddedPath;
      }

      try {
        final tempFile = File(reencodeOutput);
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}

      _log.e('MP3 re-encode also failed: ${result.output}');
      return null;
    }

    try {
      final tempFile = File(tempOutput);
      if (await tempFile.exists()) await tempFile.delete();
    } catch (e) {
      _log.w('Failed to cleanup temp MP3 file: $e');
    }

    _log.e('MP3 Metadata/Cover embed failed: ${result.output}');
    return null;
  }

  static Future<FFmpegResult> _runMp3Embed({
    required String mp3Path,
    required String tempOutput,
    String? coverPath,
    Map<String, String>? metadata,
    bool preserveMetadata = false,
    required String audioCodec,
    String? audioBitrate,
  }) async {
    final arguments = <String>['-v', 'error', '-hide_banner', '-i', mp3Path];

    if (coverPath != null) {
      arguments
        ..add('-i')
        ..add(coverPath);
    }

    arguments
      ..add('-map')
      ..add('0:a')
      ..add('-map_metadata')
      ..add(preserveMetadata ? '0' : '-1');

    if (coverPath != null) {
      arguments
        ..add('-map')
        ..add('1:0')
        ..add('-c:v:0')
        ..add('copy')
        ..add('-id3v2_version')
        ..add('3')
        ..add('-metadata:s:v')
        ..add('title=Album cover')
        ..add('-metadata:s:v')
        ..add('comment=Cover (front)');
    }

    arguments
      ..add('-c:a')
      ..add(audioCodec);

    if (audioBitrate != null) {
      arguments
        ..add('-b:a')
        ..add(audioBitrate);
    }

    if (metadata != null) {
      AudioMetadataMapper.appendMappedMetadataArguments(
        arguments,
        AudioMetadataMapper.convertToId3Tags(metadata),
      );
    }

    arguments
      ..add('-id3v2_version')
      ..add('3')
      ..add(tempOutput)
      ..add('-y');

    _log.d('Executing FFmpeg MP3 embed command (codec: $audioCodec)');
    return await _executeWithArguments(arguments);
  }

  /// Finalize MP3 embed by replacing the original file with the temp output.
  static Future<String?> _finalizeMp3Embed(
    String mp3Path,
    String tempOutput,
  ) async {
    final promoted = await _promoteTempOutput(
      tempOutput,
      mp3Path,
      onMissing: () => _log.e('Temp MP3 output file not found: $tempOutput'),
      onError: (e) =>
          _log.e('Failed to replace MP3 file after metadata embed: $e'),
    );
    if (!promoted) return null;
    _log.d('MP3 metadata embedded successfully');
    return mp3Path;
  }

  static Future<void> _ensureMp3UnsyncedLyricsFrame(
    String mp3Path,
    String lyrics,
  ) async {
    try {
      final file = File(mp3Path);
      if (!await file.exists()) return;

      final bytes = await file.readAsBytes();
      final updated = Id3v23Lyrics.writeUnsyncedLyrics(bytes, lyrics);
      if (updated == null) {
        _log.w('Skipping MP3 USLT lyrics frame update: unsupported ID3 tag');
        return;
      }

      await file.writeAsBytes(updated, flush: true);
      _log.d('MP3 USLT lyrics frame written (${lyrics.length} chars)');
    } catch (e) {
      _log.w('Failed to write MP3 USLT lyrics frame: $e');
    }
  }

  static Future<String?> embedMetadataToOpus({
    required String opusPath,
    String? coverPath,
    Map<String, String>? metadata,
    String artistTagMode = artistTagModeJoined,
    bool preserveMetadata = false,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final tempOutput = _nextTempEmbedPath(tempDir.path, '.opus');
    final mapMetaValue = preserveMetadata ? '0' : '-1';
    final arguments = <String>[
      '-v',
      'error',
      '-hide_banner',
      '-i',
      opusPath,
      '-map',
      '0:a',
      '-map_metadata',
      mapMetaValue,
      '-map_metadata:s:a',
      mapMetaValue,
      '-c:a',
      'copy',
    ];

    if (metadata != null) {
      AudioMetadataMapper.appendVorbisMetadataArguments(
        arguments,
        metadata,
        artistTagMode: artistTagMode,
      );
    }

    if (coverPath != null) {
      try {
        final pictureBlock = await _createMetadataBlockPicture(coverPath);
        if (pictureBlock != null) {
          arguments
            ..add('-metadata')
            ..add('METADATA_BLOCK_PICTURE=$pictureBlock');
          _log.d(
            'Created METADATA_BLOCK_PICTURE for Opus (${pictureBlock.length} chars)',
          );
        } else {
          _log.w('Failed to create METADATA_BLOCK_PICTURE, skipping cover');
        }
      } catch (e) {
        _log.e('Error creating METADATA_BLOCK_PICTURE: $e');
      }
    }

    arguments
      ..add(tempOutput)
      ..add('-y');
    _log.d('Executing FFmpeg Opus embed command');

    final result = await _executeWithArguments(arguments);

    if (result.success) {
      final promoted = await _promoteTempOutput(
        tempOutput,
        opusPath,
        onMissing: () => _log.e('Temp Opus output file not found: $tempOutput'),
        onError: (e) =>
            _log.e('Failed to replace Opus file after metadata embed: $e'),
      );
      if (!promoted) return null;
      _log.d('Opus metadata embedded successfully');
      return opusPath;
    }

    try {
      final tempFile = File(tempOutput);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      _log.w('Failed to cleanup temp Opus file: $e');
    }

    _log.e('Opus Metadata embed failed: ${result.output}');
    return null;
  }

  static Future<String?> embedMetadataToM4a({
    required String m4aPath,
    String? coverPath,
    Map<String, String>? metadata,
    bool preserveMetadata = true,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final tempOutput = _nextTempEmbedPath(tempDir.path, '.m4a');

    final normalizedCoverPath = coverPath?.trim();
    final hasCover =
        normalizedCoverPath != null &&
        normalizedCoverPath.isNotEmpty &&
        await File(normalizedCoverPath).exists();
    final preserveExistingStreams = preserveMetadata && !hasCover;

    List<String> buildArgs(bool forceMov) {
      final arguments = <String>['-v', 'error', '-hide_banner', '-i', m4aPath];
      if (hasCover) {
        arguments
          ..add('-i')
          ..add(normalizedCoverPath);
      }
      if (preserveExistingStreams) {
        // When no replacement cover is provided, preserve all input streams so
        // the existing attached artwork is not dropped during the metadata rewrite.
        arguments
          ..add('-map')
          ..add('0')
          ..add('-c')
          ..add('copy');
      } else {
        arguments
          ..add('-map')
          ..add('0:a')
          ..add('-c:a')
          ..add('copy');
      }
      arguments
        ..add('-map_metadata')
        ..add(preserveMetadata ? '0' : '-1');

      if (hasCover) {
        // Mark the image as an attached picture so the container writes a proper
        // covr atom instead of a generic MJPEG video track.
        _appendCoverInputArgs(arguments);
      }

      if (metadata != null) {
        AudioMetadataMapper.appendMappedMetadataArguments(
          arguments,
          AudioMetadataMapper.convertToM4aTags(metadata),
        );
      }

      // MOV muxer accepts codecs the MP4 muxer rejects (e.g. AC-4). The default
      // (no -f) keeps the ipod muxer for plain .m4a; cover writes force mp4.
      if (forceMov) {
        arguments
          ..add('-f')
          ..add('mov');
      } else if (hasCover) {
        arguments
          ..add('-f')
          ..add('mp4');
      }

      arguments
        ..add(tempOutput)
        ..add('-y');
      return arguments;
    }

    _log.d('Executing FFmpeg M4A embed command');
    var result = await _executeWithArguments(buildArgs(false));
    if (!result.success) {
      _log.w('M4A embed failed with default muxer, retrying with mov muxer');
      try {
        final stale = File(tempOutput);
        if (await stale.exists()) await stale.delete();
      } catch (_) {}
      result = await _executeWithArguments(buildArgs(true));
    }

    if (result.success) {
      final promoted = await _promoteTempOutput(
        tempOutput,
        m4aPath,
        onMissing: () => _log.e('Temp M4A output file not found: $tempOutput'),
        onError: (e) =>
            _log.e('Failed to replace M4A file after metadata embed: $e'),
      );
      if (!promoted) return null;

      // FFmpeg's MP4 muxer ignores ISRC and label, so write them natively
      // as iTunes freeform atoms. Only fields the caller supplied are
      // touched (an empty value clears the tag).
      if (metadata != null) {
        await _writeM4AFreeformTags(m4aPath, metadata);
      }

      _log.d('M4A metadata embedded successfully');
      return m4aPath;
    }

    try {
      final tempFile = File(tempOutput);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      _log.w('Failed to cleanup temp M4A file: $e');
    }

    _log.e('M4A Metadata embed failed: ${result.output}');
    return null;
  }

  static Future<String?> _createMetadataBlockPicture(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        _log.e('Cover image not found: $imagePath');
        return null;
      }

      final imageData = await file.readAsBytes();

      String mimeType;
      if (imagePath.toLowerCase().endsWith('.png')) {
        mimeType = 'image/png';
      } else if (imagePath.toLowerCase().endsWith('.jpg') ||
          imagePath.toLowerCase().endsWith('.jpeg')) {
        mimeType = 'image/jpeg';
      } else {
        if (imageData.length >= 8 &&
            imageData[0] == 0x89 &&
            imageData[1] == 0x50 &&
            imageData[2] == 0x4E &&
            imageData[3] == 0x47) {
          mimeType = 'image/png';
        } else if (imageData.length >= 2 &&
            imageData[0] == 0xFF &&
            imageData[1] == 0xD8) {
          mimeType = 'image/jpeg';
        } else {
          mimeType = 'image/jpeg';
        }
      }

      final mimeBytes = utf8.encode(mimeType);
      const description = '';
      final descBytes = utf8.encode(description);

      final blockSize =
          4 +
          4 +
          mimeBytes.length +
          4 +
          descBytes.length +
          4 +
          4 +
          4 +
          4 +
          4 +
          imageData.length;

      final buffer = ByteData(blockSize);
      var offset = 0;

      buffer.setUint32(offset, 3, Endian.big);
      offset += 4;

      buffer.setUint32(offset, mimeBytes.length, Endian.big);
      offset += 4;

      final blockBytes = Uint8List(blockSize);
      blockBytes.setRange(0, offset, buffer.buffer.asUint8List());
      blockBytes.setRange(offset, offset + mimeBytes.length, mimeBytes);
      offset += mimeBytes.length;

      final tempBuffer = ByteData(4);
      tempBuffer.setUint32(0, descBytes.length, Endian.big);
      blockBytes.setRange(offset, offset + 4, tempBuffer.buffer.asUint8List());
      offset += 4;

      blockBytes.setRange(offset, offset + descBytes.length, descBytes);
      offset += descBytes.length;

      tempBuffer.setUint32(0, 0, Endian.big);
      blockBytes.setRange(offset, offset + 4, tempBuffer.buffer.asUint8List());
      offset += 4;

      tempBuffer.setUint32(0, 0, Endian.big);
      blockBytes.setRange(offset, offset + 4, tempBuffer.buffer.asUint8List());
      offset += 4;

      tempBuffer.setUint32(0, 0, Endian.big);
      blockBytes.setRange(offset, offset + 4, tempBuffer.buffer.asUint8List());
      offset += 4;

      tempBuffer.setUint32(0, 0, Endian.big);
      blockBytes.setRange(offset, offset + 4, tempBuffer.buffer.asUint8List());
      offset += 4;

      tempBuffer.setUint32(0, imageData.length, Endian.big);
      blockBytes.setRange(offset, offset + 4, tempBuffer.buffer.asUint8List());
      offset += 4;

      blockBytes.setRange(offset, offset + imageData.length, imageData);

      final base64String = base64Encode(blockBytes);

      return base64String;
    } catch (e) {
      _log.e('Error creating METADATA_BLOCK_PICTURE: $e');
      return null;
    }
  }

  /// Unified audio format conversion with full metadata + cover preservation.
  /// Supports: FLAC/M4A/MP3/Opus -> AAC/M4A/MP3/Opus/ALAC/FLAC/WAV/AIFF.
  /// ALAC, FLAC, WAV and AIFF targets are lossless codecs (bitrate parameter
  /// is ignored). [losslessQuality] can cap bit depth/sample rate, and caps are
  /// only applied when they reduce the source quality.
  /// [sourceBitDepth] (when known) avoids an extra probe.
  static Future<String?> convertAudioFormat({
    required String inputPath,
    required String targetFormat,
    required String bitrate,
    required Map<String, String> metadata,
    String? coverPath,
    String artistTagMode = artistTagModeJoined,
    bool deleteOriginal = true,
    int? sourceBitDepth,
    LosslessConversionQuality losslessQuality =
        const LosslessConversionQuality(),
    LosslessConversionProcessing losslessProcessing =
        const LosslessConversionProcessing(),
  }) async {
    final format = targetFormat.toLowerCase();
    if (!const {
      'mp3',
      'opus',
      'aac',
      'alac',
      'flac',
      'wav',
      'aiff',
      'aif',
    }.contains(format)) {
      _log.e('Unsupported target format: $targetFormat');
      return null;
    }

    final resolvedLosslessQuality = isLosslessConversionTarget(format)
        ? await _resolveLosslessQuality(
            inputPath: inputPath,
            quality: losslessQuality,
            sourceBitDepth: sourceBitDepth,
          )
        : const _ResolvedLosslessConversionQuality();

    if (format == 'alac' || format == 'flac') {
      return _convertToLossless(
        inputPath: inputPath,
        metadata: metadata,
        codec: format,
        coverPath: coverPath,
        artistTagMode: artistTagMode,
        targetBitDepth: resolvedLosslessQuality.targetBitDepth,
        targetSampleRate: resolvedLosslessQuality.targetSampleRate,
        processing: losslessProcessing,
        deleteOriginal: deleteOriginal,
      );
    }
    if (format == 'wav' || format == 'aiff' || format == 'aif') {
      return _convertToPcm(
        inputPath: inputPath,
        metadata: metadata,
        coverPath: coverPath,
        container: format == 'wav' ? 'wav' : 'aiff',
        sourceBitDepth: sourceBitDepth,
        targetBitDepth: resolvedLosslessQuality.targetBitDepth,
        targetSampleRate: resolvedLosslessQuality.targetSampleRate,
        processing: losslessProcessing,
        deleteOriginal: deleteOriginal,
      );
    }

    final extension = switch (format) {
      'opus' => '.opus',
      'aac' => '.m4a',
      _ => '.mp3',
    };
    final outputPlan = await _conversionOutputPlan(
      inputPath,
      extension,
      deleteOriginal: deleteOriginal,
    );
    final outputPath = outputPlan.workingPath;

    String command;
    if (format == 'opus') {
      command =
          '-v error -hide_banner -i "$inputPath" -codec:a libopus -b:a $bitrate -vbr on -compression_level 10 -map 0:a "$outputPath" -y';
    } else if (format == 'aac') {
      command =
          '-v error -hide_banner -i "$inputPath" -codec:a aac -b:a $bitrate -map 0:a -f mp4 "$outputPath" -y';
    } else {
      command =
          '-v error -hide_banner -i "$inputPath" -codec:a libmp3lame -b:a $bitrate -map 0:a -id3v2_version 3 "$outputPath" -y';
    }

    _log.i(
      'Converting ${inputPath.split(Platform.pathSeparator).last} to $format @ $bitrate',
    );
    final result = await _execute(command);

    if (!result.success) {
      _log.e('Audio conversion failed: ${result.output}');
      await _cleanupConversionOutput(outputPlan);
      return null;
    }

    // Treat embed failure as conversion failure when metadata/cover was requested.
    final hasMetadata = metadata.values.any((v) => v.trim().isNotEmpty);
    final hasCover = coverPath != null && coverPath.trim().isNotEmpty;
    if (hasMetadata || hasCover) {
      String? embedResult;
      if (format == 'mp3') {
        embedResult = await embedMetadataToMp3(
          mp3Path: outputPath,
          coverPath: coverPath,
          metadata: metadata,
        );
      } else if (format == 'aac') {
        embedResult = await embedMetadataToM4a(
          m4aPath: outputPath,
          coverPath: coverPath,
          metadata: metadata,
          preserveMetadata: true,
        );
      } else {
        embedResult = await embedMetadataToOpus(
          opusPath: outputPath,
          coverPath: coverPath,
          metadata: metadata,
          artistTagMode: artistTagMode,
        );
      }

      if (embedResult == null) {
        _log.e(
          'Metadata/Cover preservation failed, rolling back converted file',
        );
        await _cleanupConversionOutput(outputPlan);
        return null;
      }
    }

    return _finalizeConversionOutput(
      plan: outputPlan,
      inputPath: inputPath,
      deleteOriginal: deleteOriginal,
    );
  }

  /// Convert to ALAC (.m4a) or FLAC per [codec].
  /// Metadata and cover art are embedded in a single FFmpeg pass.
  static Future<String?> _convertToLossless({
    required String inputPath,
    required Map<String, String> metadata,
    required String codec, // 'alac' or 'flac'
    String? coverPath,
    String artistTagMode = artistTagModeJoined,
    int? targetBitDepth,
    int? targetSampleRate,
    LosslessConversionProcessing processing =
        const LosslessConversionProcessing(),
    bool deleteOriginal = true,
  }) async {
    final isAlac = codec == 'alac';
    final outputPlan = await _conversionOutputPlan(
      inputPath,
      isAlac ? '.m4a' : '.flac',
      deleteOriginal: deleteOriginal,
    );
    final outputPath = outputPlan.workingPath;
    final arguments = <String>['-v', 'error', '-hide_banner', '-i', inputPath];

    final hasCover =
        coverPath != null &&
        coverPath.trim().isNotEmpty &&
        await File(coverPath).exists();
    if (hasCover) {
      arguments
        ..add('-i')
        ..add(coverPath);
    }

    arguments
      ..add('-map')
      ..add('0:a');
    if (hasCover) {
      _appendCoverInputArgs(arguments);
    }
    arguments
      ..add('-c:a')
      ..add(codec);
    if (!isAlac) {
      arguments
        ..add('-compression_level')
        ..add('8');
    }
    _appendLosslessCodecQualityArguments(
      arguments,
      codec: codec,
      targetBitDepth: targetBitDepth,
      targetSampleRate: targetSampleRate,
      processing: processing,
    );
    arguments
      ..add('-map_metadata')
      ..add(isAlac ? '-1' : '0');

    if (isAlac) {
      AudioMetadataMapper.appendMappedMetadataArguments(
        arguments,
        AudioMetadataMapper.convertToM4aTags(metadata),
      );
    } else {
      AudioMetadataMapper.appendVorbisMetadataArguments(
        arguments,
        metadata,
        artistTagMode: artistTagMode,
      );
    }

    arguments
      ..add(outputPath)
      ..add('-y');

    final label = isAlac ? 'ALAC' : 'FLAC';
    _log.i(
      'Converting ${inputPath.split(Platform.pathSeparator).last} to $label'
      '${targetBitDepth != null ? ' $targetBitDepth-bit' : ''}'
      '${targetSampleRate != null ? ' @ ${targetSampleRate}Hz' : ''}'
      '${processing.hasDither ? ' dither=${processing.normalizedDither}' : ''}'
      '${processing.normalizedResampler != 'swr' ? ' resampler=${processing.normalizedResampler}' : ''}',
    );
    final result = await _executeWithArguments(arguments);

    if (!result.success) {
      _log.e('$label conversion failed: ${result.output}');
      await _cleanupConversionOutput(outputPlan);
      return null;
    }

    return _finalizeConversionOutput(
      plan: outputPlan,
      inputPath: inputPath,
      deleteOriginal: deleteOriginal,
    );
  }

  /// Convert to uncompressed PCM (WAV or AIFF), preserving bit depth when known.
  /// Tags and cover are written natively into an embedded ID3 chunk by the Go
  /// backend (RIFF "id3 " for WAV, "ID3 " for AIFF) for full-fidelity tagging.
  static Future<String?> _convertToPcm({
    required String inputPath,
    required Map<String, String> metadata,
    required String container, // 'wav' or 'aiff'
    String? coverPath,
    int? sourceBitDepth,
    int? targetBitDepth,
    int? targetSampleRate,
    LosslessConversionProcessing processing =
        const LosslessConversionProcessing(),
    bool deleteOriginal = true,
  }) async {
    final isAiff = container == 'aiff';
    final outputPlan = await _conversionOutputPlan(
      inputPath,
      isAiff ? '.aiff' : '.wav',
      deleteOriginal: deleteOriginal,
    );
    final outputPath = outputPlan.workingPath;
    var depth = targetBitDepth ?? sourceBitDepth;
    if (depth == null || depth <= 0) {
      depth = await probeBitDepth(inputPath);
    }
    final use24 = depth != null && depth >= 24;
    final codec = isAiff
        ? (use24 ? 'pcm_s24be' : 'pcm_s16be')
        : (use24 ? 'pcm_s24le' : 'pcm_s16le');

    final arguments = <String>[
      '-v',
      'error',
      '-hide_banner',
      '-i',
      inputPath,
      '-map',
      '0:a',
    ];
    _appendLosslessAresampleFilter(
      arguments,
      targetSampleRate: targetSampleRate,
      outputSampleFormat: _losslessOutputSampleFormat(
        codec: 'pcm',
        targetBitDepth: targetBitDepth,
      ),
      processing: processing,
    );
    arguments.addAll(['-c:a', codec, '-map_metadata', '-1']);

    // Keep a container-native metadata fallback for software that does not
    // inspect WAV/AIFF ID3 chunks. FFmpeg writes common WAV fields into
    // LIST/INFO and the fields supported by AIFF into its native text chunks.
    // The native writer below remains authoritative for the complete field
    // set (including track/disc totals, lyrics, ReplayGain, and cover art).
    AudioMetadataMapper.appendMappedMetadataArguments(
      arguments,
      AudioMetadataMapper.convertToId3Tags(metadata),
    );
    arguments.addAll([outputPath, '-y']);

    _log.i(
      'Converting ${inputPath.split(Platform.pathSeparator).last} to '
      '${container.toUpperCase()} (${use24 ? 24 : 16}-bit'
      '${targetSampleRate != null ? ', ${targetSampleRate}Hz' : ''}'
      '${processing.hasDither ? ', dither=${processing.normalizedDither}' : ''}'
      '${processing.normalizedResampler != 'swr' ? ', resampler=${processing.normalizedResampler}' : ''})',
    );
    final result = await _executeWithArguments(arguments);
    if (!result.success) {
      _log.e('${container.toUpperCase()} conversion failed: ${result.output}');
      await _cleanupConversionOutput(outputPlan);
      return null;
    }

    // Write tags + cover via the native ID3-chunk writer in the Go backend.
    final hasMetadata = metadata.values.any((v) => v.trim().isNotEmpty);
    final hasCover = coverPath != null && coverPath.trim().isNotEmpty;
    if (hasMetadata || hasCover) {
      final ok = await _embedChunkTagsNative(outputPath, metadata, coverPath);
      if (!ok) {
        // Metadata/cover preservation is part of the requested conversion.
        // Publishing an apparently successful but untagged file is data loss.
        _log.e('Native tag embed failed for $container output');
        await _cleanupConversionOutput(outputPlan);
        return null;
      }
    }

    return _finalizeConversionOutput(
      plan: outputPlan,
      inputPath: inputPath,
      deleteOriginal: deleteOriginal,
    );
  }

  /// Writes tags + cover into a WAV/AIFF file via the Go native ID3-chunk
  /// writer (PlatformBridge.editFileMetadata). Maps Vorbis-style metadata keys
  /// to the lowercase field names the Go editor expects.
  static Future<bool> _embedChunkTagsNative(
    String path,
    Map<String, String> vorbisMetadata,
    String? coverPath,
  ) async {
    final fields = AudioMetadataMapper.vorbisToNativeChunkFields(
      vorbisMetadata,
    );
    if (coverPath != null && coverPath.trim().isNotEmpty) {
      fields['cover_path'] = coverPath;
    }
    if (fields.isEmpty) return true;
    try {
      final res = await PlatformBridge.editFileMetadata(path, fields);
      final error = res['error'];
      if (error != null) {
        _log.w('editFileMetadata for $path failed: $error');
        return false;
      }
      return res['success'] == true;
    } catch (e) {
      _log.w('editFileMetadata for $path failed: $e');
      return false;
    }
  }

  /// Writes ISRC and label into an M4A/MP4 file natively (iTunes freeform
  /// atoms), since FFmpeg's MP4 muxer drops these keys. Only keys present in
  /// [metadata] are written; an empty value clears the corresponding tag.
  static Future<void> _writeM4AFreeformTags(
    String m4aPath,
    Map<String, String> metadata,
  ) async {
    final fields = <String, String>{};
    for (final entry in metadata.entries) {
      final key = entry.key.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      switch (key) {
        case 'ISRC':
          fields['isrc'] = entry.value;
          break;
        case 'LABEL':
        case 'ORGANIZATION':
          fields['label'] = entry.value;
          break;
      }
    }
    if (fields.isEmpty) return;
    try {
      await PlatformBridge.writeM4AFreeformTags(m4aPath, fields);
    } catch (e) {
      _log.w('writeM4AFreeformTags failed for $m4aPath: $e');
    }
  }

  /// Split a CUE+audio file into individual track files using FFmpeg.
  /// Each track is extracted with `-c copy` (no re-encoding) and metadata is embedded.
  /// [audioPath] is the source audio file (FLAC, WAV, etc.)
  /// [outputDir] is where individual track files will be saved
  /// [tracks] is the list of track split info from the Go CUE parser
  /// [albumMetadata] contains album-level metadata (artist, album, genre, date)
  static Future<List<String>?> splitCueToTracks({
    required String audioPath,
    required String outputDir,
    required List<CueSplitTrackInfo> tracks,
    required Map<String, String> albumMetadata,
    String? coverPath,
    void Function(int current, int total)? onProgress,
  }) async {
    if (tracks.isEmpty) {
      _log.e('No tracks to split');
      return null;
    }

    final outputPaths = <String>[];
    final inputExt = audioPath.toLowerCase().split('.').last;
    final outputExt =
        (inputExt == 'flac' ||
            inputExt == 'wav' ||
            inputExt == 'ape' ||
            inputExt == 'wv')
        ? 'flac'
        : inputExt;

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      onProgress?.call(i + 1, tracks.length);

      final sanitizedTitle = track.title
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final trackNumStr = track.number.toString().padLeft(2, '0');
      final outputFileName = '$trackNumStr - $sanitizedTitle.$outputExt';
      final outputPath = '$outputDir${Platform.pathSeparator}$outputFileName';
      final arguments = <String>[
        '-v',
        'error',
        '-hide_banner',
        '-i',
        audioPath,
      ];

      final startTime = _formatSecondsForFFmpeg(track.startSec);
      arguments
        ..add('-ss')
        ..add(startTime);

      if (track.endSec > 0) {
        final endTime = _formatSecondsForFFmpeg(track.endSec);
        arguments
          ..add('-to')
          ..add(endTime);
      }

      if (outputExt == 'flac') {
        arguments
          ..add('-c:a')
          ..add('flac')
          ..add('-compression_level')
          ..add('8');
      } else {
        arguments
          ..add('-c:a')
          ..add('copy');
      }

      final artist = track.artist.isNotEmpty
          ? track.artist
          : (albumMetadata['artist'] ?? '');
      final album = albumMetadata['album'] ?? '';
      final genre = albumMetadata['genre'] ?? '';
      final date = albumMetadata['date'] ?? '';
      final cueMetadata = <String, String>{};

      void addMeta(String key, String value) {
        if (value.isNotEmpty) {
          cueMetadata[key] = value;
        }
      }

      addMeta('TITLE', track.title);
      addMeta('ARTIST', artist);
      addMeta('ALBUM', album);
      addMeta('ALBUMARTIST', albumMetadata['artist'] ?? '');
      addMeta('TRACKNUMBER', track.number.toString());
      addMeta('GENRE', genre);
      addMeta('DATE', date);
      if (track.isrc.isNotEmpty) addMeta('ISRC', track.isrc);
      if (track.composer.isNotEmpty) addMeta('COMPOSER', track.composer);

      AudioMetadataMapper.appendMappedMetadataArguments(arguments, cueMetadata);
      arguments
        ..add(outputPath)
        ..add('-y');

      _log.d('CUE split track ${track.number}');
      final result = await _executeWithArguments(arguments);
      if (!result.success) {
        _log.e('CUE split failed for track ${track.number}: ${result.output}');
        continue;
      }

      if (coverPath != null && coverPath.isNotEmpty && outputExt == 'flac') {}

      outputPaths.add(outputPath);
      _log.i('CUE split: track ${track.number} -> $outputFileName');
    }

    if (outputPaths.isEmpty) {
      _log.e('CUE split: no tracks were successfully extracted');
      return null;
    }

    _log.i('CUE split complete: ${outputPaths.length}/${tracks.length} tracks');
    return outputPaths;
  }

  static String _formatSecondsForFFmpeg(double seconds) {
    if (seconds < 0) return '0';
    final hours = seconds ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    final secs = seconds - (hours * 3600) - (mins * 60);
    return '${hours.toString().padLeft(2, '0')}:${mins.toInt().toString().padLeft(2, '0')}:${secs.toStringAsFixed(3).padLeft(6, '0')}';
  }
}

enum _LiveDecryptFormat { flac, m4a }
