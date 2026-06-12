import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/level.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';

class AudioAnalysisData {
  static const cacheVersion = 4;

  final String filePath;
  final int fileSize;
  final String codec;
  final String container;
  final String decodedSampleFormat;
  final int sampleRate;
  final int channels;
  final String channelLayout;
  final int bitsPerSample;
  final double duration;
  final int bitrate;
  final String bitDepth;
  final double dynamicRange;
  final double peakAmplitude;
  final double rmsLevel;
  final double? integratedLufs;
  final double? truePeakDb;
  final int clippingSamples;
  final double? spectralCutoffHz;
  final List<ChannelAnalysisStats> channelStats;
  final int totalSamples;
  final SpectrogramData? spectrum;

  const AudioAnalysisData({
    required this.filePath,
    required this.fileSize,
    this.codec = '',
    this.container = '',
    this.decodedSampleFormat = '',
    required this.sampleRate,
    required this.channels,
    this.channelLayout = '',
    required this.bitsPerSample,
    required this.duration,
    required this.bitrate,
    required this.bitDepth,
    required this.dynamicRange,
    required this.peakAmplitude,
    required this.rmsLevel,
    this.integratedLufs,
    this.truePeakDb,
    this.clippingSamples = 0,
    this.spectralCutoffHz,
    this.channelStats = const [],
    required this.totalSamples,
    this.spectrum,
  });

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'cacheVersion': cacheVersion,
    'fileSize': fileSize,
    'codec': codec,
    'container': container,
    'decodedSampleFormat': decodedSampleFormat,
    'sampleRate': sampleRate,
    'channels': channels,
    'channelLayout': channelLayout,
    'bitsPerSample': bitsPerSample,
    'duration': duration,
    'bitrate': bitrate,
    'bitDepth': bitDepth,
    'dynamicRange': dynamicRange,
    'peakAmplitude': peakAmplitude,
    'rmsLevel': rmsLevel,
    'integratedLufs': integratedLufs,
    'truePeakDb': truePeakDb,
    'clippingSamples': clippingSamples,
    'spectralCutoffHz': spectralCutoffHz,
    'channelStats': channelStats.map((stats) => stats.toJson()).toList(),
    'totalSamples': totalSamples,
  };

  factory AudioAnalysisData.fromJson(Map<String, dynamic> json) {
    return AudioAnalysisData(
      filePath: json['filePath'] as String,
      fileSize: json['fileSize'] as int,
      codec: json['codec']?.toString() ?? '',
      container: json['container']?.toString() ?? '',
      decodedSampleFormat: json['decodedSampleFormat']?.toString() ?? '',
      sampleRate: json['sampleRate'] as int,
      channels: json['channels'] as int,
      channelLayout: json['channelLayout']?.toString() ?? '',
      bitsPerSample: json['bitsPerSample'] as int,
      duration: (json['duration'] as num).toDouble(),
      bitrate: json['bitrate'] as int,
      bitDepth: json['bitDepth'] as String,
      dynamicRange: (json['dynamicRange'] as num).toDouble(),
      peakAmplitude: (json['peakAmplitude'] as num).toDouble(),
      rmsLevel: (json['rmsLevel'] as num).toDouble(),
      integratedLufs: (json['integratedLufs'] as num?)?.toDouble(),
      truePeakDb: (json['truePeakDb'] as num?)?.toDouble(),
      clippingSamples: (json['clippingSamples'] as num?)?.toInt() ?? 0,
      spectralCutoffHz: (json['spectralCutoffHz'] as num?)?.toDouble(),
      channelStats:
          (json['channelStats'] as List?)
              ?.whereType<Map<dynamic, dynamic>>()
              .map((item) => ChannelAnalysisStats.fromJson(item))
              .toList() ??
          const [],
      totalSamples: json['totalSamples'] as int,
    );
  }
}

class ChannelAnalysisStats {
  final int channel;
  final double? peakDb;
  final double? rmsDb;
  final double? dynamicRangeDb;
  final int peakCount;

  const ChannelAnalysisStats({
    required this.channel,
    this.peakDb,
    this.rmsDb,
    this.dynamicRangeDb,
    this.peakCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'channel': channel,
    'peakDb': peakDb,
    'rmsDb': rmsDb,
    'dynamicRangeDb': dynamicRangeDb,
    'peakCount': peakCount,
  };

  factory ChannelAnalysisStats.fromJson(Map<dynamic, dynamic> json) {
    return ChannelAnalysisStats(
      channel: (json['channel'] as num?)?.toInt() ?? 0,
      peakDb: (json['peakDb'] as num?)?.toDouble(),
      rmsDb: (json['rmsDb'] as num?)?.toDouble(),
      dynamicRangeDb: (json['dynamicRangeDb'] as num?)?.toDouble(),
      peakCount: (json['peakCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class SpectrogramData {
  final List<Float64List> magnitudes;
  final int sampleRate;
  final int freqBins;
  final double duration;
  final double maxFreq;
  final int sliceCount;

  const SpectrogramData({
    required this.magnitudes,
    required this.sampleRate,
    required this.freqBins,
    required this.duration,
    required this.maxFreq,
    required this.sliceCount,
  });
}

class AudioAnalysisCard extends StatefulWidget {
  final String filePath;

  const AudioAnalysisCard({super.key, required this.filePath});

  @override
  State<AudioAnalysisCard> createState() => _AudioAnalysisCardState();
}

class _AudioAnalysisCardState extends State<AudioAnalysisCard> {
  AudioAnalysisData? _data;
  bool _analyzing = false;
  bool _checkingCache = true;
  String? _error;
  ui.Image? _spectrogramImage;

  static const _supportedExtensions = {
    '.flac',
    '.mp3',
    '.m4a',
    '.mp4',
    '.aac',
    '.ac3',
    '.eac3',
    '.opus',
    '.ogg',
    '.wav',
    '.wma',
    '.mka',
    '.wv',
    '.ape',
    '.tta',
    '.aif',
    '.aiff',
  };

  bool get _isSupported {
    final lower = widget.filePath.toLowerCase();
    return _supportedExtensions.any((ext) => lower.endsWith(ext));
  }

  @override
  void initState() {
    super.initState();
    if (_isSupported) {
      _tryLoadFromCache();
    }
  }

  @override
  void dispose() {
    _spectrogramImage?.dispose();
    super.dispose();
  }

  Future<void> _tryLoadFromCache() async {
    try {
      final cached = await _loadFromCache(widget.filePath);
      if (cached != null && mounted) {
        setState(() {
          _data = cached;
          _checkingCache = false;
        });
        final image = await _loadSpectrogramFromCache(widget.filePath);
        if (image != null && mounted) {
          setState(() {
            _spectrogramImage?.dispose();
            _spectrogramImage = image;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _checkingCache = false);
    }
  }

  Future<void> _analyze({bool forceRefresh = false}) async {
    if (_analyzing) return;
    setState(() {
      _analyzing = true;
      _error = null;
      if (forceRefresh) {
        _spectrogramImage?.dispose();
        _spectrogramImage = null;
        _data = null;
      }
    });

    try {
      if (forceRefresh) {
        await _clearCache(widget.filePath);
      }

      final cached = forceRefresh
          ? null
          : await _loadFromCache(widget.filePath);
      AudioAnalysisData data;
      bool fromCache = false;

      if (cached != null) {
        data = cached;
        fromCache = true;
      } else {
        data = await _runAnalysis(widget.filePath);
        _saveToCache(widget.filePath, data);
      }

      ui.Image? image;
      if (fromCache) {
        image = await _loadSpectrogramFromCache(widget.filePath);
      }
      if (image == null &&
          data.spectrum != null &&
          data.spectrum!.sliceCount > 0) {
        image = await _renderSpectrogramToImage(data.spectrum!);
        _saveSpectrogramToCache(widget.filePath, image);
      }

      if (mounted) {
        setState(() {
          _data = data;
          _spectrogramImage?.dispose();
          _spectrogramImage = image;
          _analyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _analyzing = false;
        });
      }
    }
  }

  static Future<void> _clearCache(String filePath) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final jsonFile = File('${dir.path}/$key.json');
      final imageFile = File('${dir.path}/$key.png');
      if (await jsonFile.exists()) {
        await jsonFile.delete();
      }
      if (await imageFile.exists()) {
        await imageFile.delete();
      }
    } catch (_) {}
  }

  static String _cacheKey(String filePath) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(filePath)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  static Future<Directory> _cacheDir() async {
    final appSupport = await getApplicationSupportDirectory();
    final dir = Directory('${appSupport.path}/audio_analysis_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<AudioAnalysisData?> _loadFromCache(String filePath) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final file = File('${dir.path}/$key.json');
      if (!await file.exists()) return null;

      final json = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      if (json['cacheVersion'] != AudioAnalysisData.cacheVersion) {
        return null;
      }
      final cachedSize = json['fileSize'] as int;

      if (!filePath.startsWith('content://')) {
        final currentSize = await File(filePath).length();
        if (currentSize != cachedSize) return null;
      } else {
        final stat = await PlatformBridge.safStat(filePath);
        final currentSize = (stat['size'] as num?)?.toInt() ?? 0;
        if (currentSize > 0 && currentSize != cachedSize) return null;
      }

      return AudioAnalysisData.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveToCache(
    String filePath,
    AudioAnalysisData data,
  ) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final file = File('${dir.path}/$key.json');
      await file.writeAsString(jsonEncode(data.toJson()));
    } catch (_) {}
  }

  static Future<void> _saveSpectrogramToCache(
    String filePath,
    ui.Image image,
  ) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final file = File('${dir.path}/$key.png');
        await file.writeAsBytes(byteData.buffer.asUint8List());
      }
    } catch (_) {}
  }

  static Future<ui.Image?> _loadSpectrogramFromCache(String filePath) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final file = File('${dir.path}/$key.png');
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, completer.complete);
      return completer.future;
    } catch (_) {
      return null;
    }
  }

  Future<AudioAnalysisData> _runAnalysis(String filePath) async {
    await FFmpegKitConfig.setLogLevel(Level.avLogError);

    String workingPath = filePath;
    String? tempCopy;
    if (filePath.startsWith('content://')) {
      tempCopy = await PlatformBridge.copyContentUriToTemp(filePath);
      if (tempCopy == null) {
        throw Exception('Failed to copy SAF file for analysis');
      }
      workingPath = tempCopy;
    }

    try {
      final info = await _getMediaInfo(workingPath);

      final tempDir = await getTemporaryDirectory();
      final pcmPath =
          '${tempDir.path}/analysis_pcm_${DateTime.now().millisecondsSinceEpoch}.raw';

      try {
        await _decodeToPCM(workingPath, pcmPath, info.sampleRate);

        final pcmBytes = await File(pcmPath).readAsBytes();
        final spectrumResult = await compute(
          _analyzeInIsolate,
          _AnalysisParams(
            pcmBytes: pcmBytes,
            sampleRate: info.sampleRate,
            bitsPerSample: info.bitsPerSample,
          ),
        );
        final levelMetrics = await _runFullStreamLevelAnalysis(workingPath);
        final loudnessMetrics = await _runLoudnessAnalysis(workingPath);
        final peakAmplitude =
            levelMetrics?.peakDb ?? spectrumResult.peakAmplitude;
        final rmsLevel = levelMetrics?.rmsDb ?? spectrumResult.rmsLevel;
        final dynamicRange = peakAmplitude - rmsLevel;
        final spectralCutoffHz = spectrumResult.spectrum == null
            ? null
            : await compute(
                _estimateSpectralCutoffHz,
                spectrumResult.spectrum!,
              );

        return AudioAnalysisData(
          filePath: filePath,
          fileSize: info.fileSize,
          codec: info.codec,
          container: info.container,
          decodedSampleFormat: info.decodedSampleFormat,
          sampleRate: info.sampleRate,
          channels: info.channels,
          channelLayout: info.channelLayout,
          bitsPerSample: info.bitsPerSample,
          duration: info.duration,
          bitrate: info.bitrate,
          bitDepth: info.bitsPerSample > 0
              ? '${info.bitsPerSample}-bit'
              : 'N/A',
          dynamicRange: dynamicRange,
          peakAmplitude: peakAmplitude,
          rmsLevel: rmsLevel,
          integratedLufs: loudnessMetrics?.integratedLufs,
          truePeakDb: loudnessMetrics?.truePeakDb,
          clippingSamples: levelMetrics?.clippingSamples ?? 0,
          spectralCutoffHz: spectralCutoffHz,
          channelStats: levelMetrics?.channelStats ?? const [],
          totalSamples: info.totalSamples,
          spectrum: spectrumResult.spectrum,
        );
      } finally {
        try {
          await File(pcmPath).delete();
        } catch (_) {}
      }
    } finally {
      if (tempCopy != null) {
        try {
          await File(tempCopy).delete();
        } catch (_) {}
      }
      await FFmpegKitConfig.setLogLevel(Level.avLogInfo);
    }
  }

  Future<_MediaInfo> _getMediaInfo(String filePath) async {
    final session = await FFprobeKit.getMediaInformation(filePath);
    final info = session.getMediaInformation();

    if (info == null) {
      throw Exception('Failed to get media information');
    }

    int fileSize = 0;
    try {
      fileSize = await File(filePath).length();
    } catch (_) {}

    final streams = info.getStreams();
    final audioStream = streams.firstWhere(
      (s) => s.getAllProperties()?['codec_type'] == 'audio',
      orElse: () => throw Exception('No audio stream found'),
    );

    final props = audioStream.getAllProperties() ?? {};
    final infoProps = info.getAllProperties() ?? {};
    final codecName = props['codec_name']?.toString().toLowerCase() ?? '';
    final codecLongName = props['codec_long_name']?.toString() ?? '';
    final decodedSampleFormat = props['sample_fmt']?.toString() ?? '';
    final formatName = infoProps['format_name']?.toString() ?? '';
    final formatLongName = infoProps['format_long_name']?.toString() ?? '';
    final sampleRate =
        int.tryParse(props['sample_rate']?.toString() ?? '') ?? 0;
    final channels = int.tryParse(props['channels']?.toString() ?? '') ?? 0;
    final channelLayout =
        props['channel_layout']?.toString() ??
        props['ch_layout']?.toString() ??
        '';
    final streamDuration = double.tryParse(props['duration']?.toString() ?? '');
    final containerDuration = double.tryParse(info.getDuration() ?? '');
    final duration =
        (streamDuration != null && streamDuration > 0
            ? streamDuration
            : containerDuration) ??
        0;
    final streamBitrate = int.tryParse(props['bit_rate']?.toString() ?? '');
    final containerBitrate = int.tryParse(info.getBitrate() ?? '');
    final bitrate =
        streamBitrate ??
        containerBitrate ??
        (duration > 0 && fileSize > 0 ? (fileSize * 8 / duration).round() : 0);

    final canReportStoredBitDepth = _codecHasStoredBitDepth(codecName);

    int bitsPerSample = 0;
    if (canReportStoredBitDepth) {
      bitsPerSample =
          int.tryParse(props['bits_per_raw_sample']?.toString() ?? '') ?? 0;
      if (bitsPerSample == 0) {
        bitsPerSample =
            int.tryParse(props['bits_per_sample']?.toString() ?? '') ?? 0;
      }
    }

    if (bitsPerSample == 0 && canReportStoredBitDepth) {
      final sampleFmt = props['sample_fmt']?.toString() ?? '';
      if (sampleFmt.contains('16') ||
          sampleFmt == 's16' ||
          sampleFmt == 's16p') {
        bitsPerSample = 16;
      } else if (sampleFmt.contains('32') ||
          sampleFmt == 'flt' ||
          sampleFmt == 'fltp') {
        bitsPerSample = 32;
      } else if (sampleFmt.contains('24') || sampleFmt == 's24') {
        bitsPerSample = 24;
      }
    }

    return _MediaInfo(
      fileSize: fileSize,
      codec: _formatCodecLabel(codecName, codecLongName),
      container: _formatContainerLabel(formatName, formatLongName),
      decodedSampleFormat: decodedSampleFormat,
      sampleRate: sampleRate,
      channels: channels,
      channelLayout: channelLayout,
      bitsPerSample: bitsPerSample,
      duration: duration,
      bitrate: bitrate,
      totalSamples: _estimateTotalSamples(
        props: props,
        duration: duration,
        sampleRate: sampleRate,
        channels: channels,
      ),
    );
  }

  String _formatCodecLabel(String codecName, String codecLongName) {
    final name = codecName.trim();
    final longName = _normalizeAnalysisLabel(codecLongName);
    if (name.isEmpty) return longName;
    if (longName.isEmpty || longName.toLowerCase() == name.toLowerCase()) {
      return name.toUpperCase();
    }
    return '${name.toUpperCase()} ($longName)';
  }

  String _formatContainerLabel(String formatName, String formatLongName) {
    final longName = _normalizeAnalysisLabel(formatLongName);
    if (longName.isNotEmpty) return longName;
    final name = formatName.trim();
    return name.isEmpty ? '' : name.toUpperCase();
  }

  String _normalizeAnalysisLabel(String value) {
    final trimmed = value.trim();
    final lower = trimmed.toLowerCase();
    if (lower.isEmpty || lower == 'unknown' || lower == 'n/a') return '';
    return trimmed;
  }

  int _estimateTotalSamples({
    required Map<dynamic, dynamic> props,
    required double duration,
    required int sampleRate,
    required int channels,
  }) {
    final nbSamples = int.tryParse(props['nb_samples']?.toString() ?? '');
    if (nbSamples != null && nbSamples > 0) {
      return nbSamples;
    }

    final durationTs = int.tryParse(props['duration_ts']?.toString() ?? '');
    final timeBase = props['time_base']?.toString() ?? '';
    if (durationTs != null && durationTs > 0 && timeBase.contains('/')) {
      final parts = timeBase.split('/');
      final numerator = double.tryParse(parts[0]);
      final denominator = double.tryParse(parts[1]);
      if (numerator != null &&
          numerator > 0 &&
          denominator != null &&
          denominator > 0 &&
          sampleRate > 0) {
        final seconds = durationTs * numerator / denominator;
        return (seconds * sampleRate).round();
      }
    }

    if (duration > 0 && sampleRate > 0) {
      return (duration * sampleRate).round();
    }
    return 0;
  }

  bool _codecHasStoredBitDepth(String codecName) {
    if (codecName.isEmpty) return false;
    return codecName == 'flac' ||
        codecName == 'alac' ||
        codecName == 'wavpack' ||
        codecName == 'ape' ||
        codecName == 'tta' ||
        codecName.startsWith('pcm_');
  }

  Future<_LevelMetrics?> _runFullStreamLevelAnalysis(String inputPath) async {
    await FFmpegKitConfig.setLogLevel(Level.avLogInfo);
    try {
      final session = await FFmpegKit.executeWithArguments([
        '-v',
        'info',
        '-hide_banner',
        '-nostats',
        '-i',
        inputPath,
        '-map',
        '0:a:0',
        '-vn',
        '-sn',
        '-dn',
        '-af',
        'astats=metadata=1:reset=0',
        '-f',
        'null',
        '-',
      ]);

      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        return null;
      }

      final logs = await session.getLogsAsString();
      final overallMatch = RegExp(r'Overall([\s\S]*)').firstMatch(logs);
      final section = overallMatch?.group(1) ?? logs;
      final peak = _parseLastAstatsValue(section, 'Peak level dB');
      final rms = _parseLastAstatsValue(section, 'RMS level dB');
      if (peak == null || rms == null) return null;
      final channelStats = _parseChannelStats(logs);
      final clippingSamples = channelStats.fold<int>(0, (sum, stats) {
        if (stats.peakDb == null || stats.peakDb! < -0.1) return sum;
        return sum + stats.peakCount;
      });
      return _LevelMetrics(
        peakDb: peak,
        rmsDb: rms,
        clippingSamples: clippingSamples,
        channelStats: channelStats,
      );
    } finally {
      await FFmpegKitConfig.setLogLevel(Level.avLogError);
    }
  }

  Future<_LoudnessMetrics?> _runLoudnessAnalysis(String inputPath) async {
    await FFmpegKitConfig.setLogLevel(Level.avLogInfo);
    try {
      final session = await FFmpegKit.executeWithArguments([
        '-hide_banner',
        '-nostats',
        '-i',
        inputPath,
        '-map',
        '0:a:0',
        '-vn',
        '-sn',
        '-dn',
        '-af',
        'ebur128=peak=true:framelog=quiet',
        '-f',
        'null',
        '-',
      ]);

      final logs = await session.getLogsAsString();
      final integratedMatches = RegExp(
        r'I:\s+(-?\d+\.?\d*)\s+LUFS',
      ).allMatches(logs);
      final integrated = integratedMatches.isEmpty
          ? null
          : double.tryParse(integratedMatches.last.group(1) ?? '');

      double? truePeak;
      for (final match in RegExp(
        r'Peak:\s+(-?\d+\.?\d*)\s+dBFS',
      ).allMatches(logs)) {
        final value = double.tryParse(match.group(1) ?? '');
        if (value != null && (truePeak == null || value > truePeak)) {
          truePeak = value;
        }
      }

      if (integrated == null && truePeak == null) return null;
      return _LoudnessMetrics(integratedLufs: integrated, truePeakDb: truePeak);
    } finally {
      await FFmpegKitConfig.setLogLevel(Level.avLogError);
    }
  }

  List<ChannelAnalysisStats> _parseChannelStats(String logs) {
    final stats = <ChannelAnalysisStats>[];
    final channelMatches = RegExp(
      r'Channel:\s*(\d+)([\s\S]*?)(?=Channel:\s*\d+|Overall|$)',
      caseSensitive: false,
    ).allMatches(logs);

    for (final match in channelMatches) {
      final channel = int.tryParse(match.group(1) ?? '') ?? 0;
      final section = match.group(2) ?? '';
      if (channel <= 0 || section.trim().isEmpty) continue;
      final peakDb = _parseLastAstatsValue(section, 'Peak level dB');
      final rmsDb = _parseLastAstatsValue(section, 'RMS level dB');
      stats.add(
        ChannelAnalysisStats(
          channel: channel,
          peakDb: peakDb,
          rmsDb: rmsDb,
          dynamicRangeDb: peakDb != null && rmsDb != null
              ? peakDb - rmsDb
              : null,
          peakCount:
              _parseLastAstatsInt(section, 'Peak count') ??
              _parseLastAstatsInt(section, 'Peak count ch') ??
              0,
        ),
      );
    }

    return stats;
  }

  double? _parseLastAstatsValue(String text, String label) {
    final matches = RegExp(
      '${RegExp.escape(label)}:\\s*([-+]?\\d+(?:\\.\\d+)?)',
      caseSensitive: false,
    ).allMatches(text);
    double? value;
    for (final match in matches) {
      final parsed = double.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed.isFinite) {
        value = parsed;
      }
    }
    return value;
  }

  int? _parseLastAstatsInt(String text, String label) {
    final matches = RegExp(
      '${RegExp.escape(label)}:\\s*(\\d+)',
      caseSensitive: false,
    ).allMatches(text);
    int? value;
    for (final match in matches) {
      value = int.tryParse(match.group(1) ?? '') ?? value;
    }
    return value;
  }

  Future<void> _decodeToPCM(
    String inputPath,
    String outputPath,
    int sampleRate,
  ) async {
    final maxDuration = sampleRate > 0 ? (10000000 / sampleRate) : 300;

    final session = await FFmpegKit.executeWithArguments([
      '-loglevel',
      'error',
      '-i',
      inputPath,
      '-t',
      maxDuration.toStringAsFixed(1),
      '-ac',
      '1',
      '-ar',
      sampleRate.toString(),
      '-f',
      's16le',
      '-acodec',
      'pcm_s16le',
      '-y',
      outputPath,
    ]);

    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getLogsAsString();
      throw Exception('FFmpeg decode failed: $logs');
    }
  }

  Future<ui.Image> _renderSpectrogramToImage(SpectrogramData spectrum) async {
    const imgWidth = 800;
    const imgHeight = 400;

    final pixels = await compute(
      _renderSpectrogramPixels,
      _SpectrogramRenderParams(
        spectrum: spectrum,
        width: imgWidth,
        height: imgHeight,
      ),
    );

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      imgWidth,
      imgHeight,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupported) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    if (_checkingCache) return const SizedBox.shrink();

    if (_analyzing) {
      final isRescan = _data != null || _spectrogramImage != null;
      return Card(
        elevation: 0,
        color: settingsGroupColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(height: 12),
                Text(
                  isRescan
                      ? l10n.audioAnalysisRescanning
                      : l10n.audioAnalysisAnalyzing,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Card(
        color: cs.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: cs.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: l10n.audioAnalysisRescan,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                color: cs.onErrorContainer,
                onPressed: () => _analyze(forceRefresh: true),
              ),
            ],
          ),
        ),
      );
    }

    if (_data == null) {
      return Card(
        elevation: 0,
        color: settingsGroupColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          onTap: _analyze,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.analytics_outlined, color: cs.primary, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.audioAnalysisTitle,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.audioAnalysisDescription,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      );
    }

    final data = _data!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AudioInfoCard(
          data: data,
          onRescan: () => _analyze(forceRefresh: true),
        ),
        if (_spectrogramImage != null) ...[
          const SizedBox(height: 12),
          _SpectrogramView(
            image: _spectrogramImage!,
            sampleRate: data.sampleRate,
            maxFreq: data.spectrum?.maxFreq ?? data.sampleRate / 2,
            duration: data.spectrum?.duration ?? data.duration,
          ),
        ],
      ],
    );
  }
}

class _MediaInfo {
  final int fileSize;
  final String codec;
  final String container;
  final String decodedSampleFormat;
  final int sampleRate;
  final int channels;
  final String channelLayout;
  final int bitsPerSample;
  final double duration;
  final int bitrate;
  final int totalSamples;

  const _MediaInfo({
    required this.fileSize,
    required this.codec,
    required this.container,
    required this.decodedSampleFormat,
    required this.sampleRate,
    required this.channels,
    required this.channelLayout,
    required this.bitsPerSample,
    required this.duration,
    required this.bitrate,
    required this.totalSamples,
  });
}

class _LevelMetrics {
  final double peakDb;
  final double rmsDb;
  final int clippingSamples;
  final List<ChannelAnalysisStats> channelStats;

  const _LevelMetrics({
    required this.peakDb,
    required this.rmsDb,
    this.clippingSamples = 0,
    this.channelStats = const [],
  });
}

class _LoudnessMetrics {
  final double? integratedLufs;
  final double? truePeakDb;

  const _LoudnessMetrics({this.integratedLufs, this.truePeakDb});
}

class _AnalysisParams {
  final Uint8List pcmBytes;
  final int sampleRate;
  final int bitsPerSample;

  const _AnalysisParams({
    required this.pcmBytes,
    required this.sampleRate,
    required this.bitsPerSample,
  });
}

class _AnalysisResult {
  final double dynamicRange;
  final double peakAmplitude;
  final double rmsLevel;
  final int totalSamples;
  final SpectrogramData? spectrum;

  const _AnalysisResult({
    required this.dynamicRange,
    required this.peakAmplitude,
    required this.rmsLevel,
    required this.totalSamples,
    this.spectrum,
  });
}

_AnalysisResult _analyzeInIsolate(_AnalysisParams params) {
  final byteData = ByteData.sublistView(params.pcmBytes);
  final sampleCount = params.pcmBytes.length ~/ 2;
  final samples = Float64List(sampleCount);

  for (int i = 0; i < sampleCount; i++) {
    final raw = byteData.getInt16(i * 2, Endian.little);
    samples[i] = raw / 32768.0;
  }

  double peak = 0;
  double sumSquares = 0;
  for (int i = 0; i < samples.length; i++) {
    final abs = samples[i].abs();
    if (abs > peak) peak = abs;
    sumSquares += samples[i] * samples[i];
  }

  final peakDB = peak > 0 ? 20.0 * math.log(peak) / math.ln10 : -100.0;
  final rms = math.sqrt(sumSquares / samples.length);
  final rmsDB = rms > 0 ? 20.0 * math.log(rms) / math.ln10 : -100.0;

  SpectrogramData? spectrum;
  if (samples.length >= 8192) {
    spectrum = _computeSpectrum(samples, params.sampleRate);
  }

  return _AnalysisResult(
    dynamicRange: peakDB - rmsDB,
    peakAmplitude: peakDB,
    rmsLevel: rmsDB,
    totalSamples: sampleCount,
    spectrum: spectrum,
  );
}

SpectrogramData _computeSpectrum(Float64List samples, int sampleRate) {
  const fftSize = 8192;
  const numSlices = 300;
  const freqBins = fftSize ~/ 2;

  final duration = samples.length / sampleRate;
  var samplesPerSlice = samples.length ~/ numSlices;
  var actualSlices = numSlices;
  if (samplesPerSlice < fftSize) {
    samplesPerSlice = fftSize;
    actualSlices = samples.length ~/ fftSize;
  }

  final magnitudes = <Float64List>[];

  for (int i = 0; i < actualSlices; i++) {
    final start = i * samplesPerSlice;
    if (start + fftSize > samples.length) break;

    final windowed = Float64List(fftSize);
    for (int j = 0; j < fftSize; j++) {
      final w = 0.5 * (1.0 - math.cos(2.0 * math.pi * j / (fftSize - 1)));
      windowed[j] = samples[start + j] * w;
    }

    final spectrum = _fft(windowed);

    final mags = Float64List(freqBins);
    for (int j = 0; j < freqBins; j++) {
      final re = spectrum[j * 2];
      final im = spectrum[j * 2 + 1];
      var mag = math.sqrt(re * re + im * im);
      if (mag < 1e-10) mag = 1e-10;
      mags[j] = 20.0 * math.log(mag) / math.ln10;
    }
    magnitudes.add(mags);
  }

  return SpectrogramData(
    magnitudes: magnitudes,
    sampleRate: sampleRate,
    freqBins: freqBins,
    duration: duration,
    maxFreq: sampleRate / 2.0,
    sliceCount: magnitudes.length,
  );
}

double? _estimateSpectralCutoffHz(SpectrogramData spectrum) {
  if (spectrum.magnitudes.isEmpty || spectrum.freqBins <= 0) return null;

  final averages = Float64List(spectrum.freqBins);
  for (final slice in spectrum.magnitudes) {
    final limit = math.min(slice.length, spectrum.freqBins);
    for (int i = 0; i < limit; i++) {
      averages[i] += slice[i];
    }
  }

  var peak = -double.infinity;
  final startBin = math.max(
    1,
    (20 / spectrum.maxFreq * spectrum.freqBins).floor(),
  );
  for (int i = startBin; i < averages.length; i++) {
    averages[i] /= spectrum.magnitudes.length;
    if (averages[i] > peak) peak = averages[i];
  }
  if (!peak.isFinite) return null;

  final threshold = peak - 60.0;
  var cutoffBin = 0;
  for (int i = averages.length - 1; i >= startBin; i--) {
    if (averages[i] >= threshold) {
      cutoffBin = i;
      break;
    }
  }
  if (cutoffBin <= 0) return null;
  return cutoffBin / spectrum.freqBins * spectrum.maxFreq;
}

/// Cooley-Tukey radix-2 FFT. Returns interleaved [re, im, re, im, ...].
Float64List _fft(Float64List realInput) {
  final n = realInput.length;
  final data = Float64List(n * 2);
  for (int i = 0; i < n; i++) {
    data[i * 2] = realInput[i];
  }

  int j = 0;
  for (int i = 0; i < n; i++) {
    if (i < j) {
      final tr = data[i * 2];
      final ti = data[i * 2 + 1];
      data[i * 2] = data[j * 2];
      data[i * 2 + 1] = data[j * 2 + 1];
      data[j * 2] = tr;
      data[j * 2 + 1] = ti;
    }
    int m = n >> 1;
    while (m >= 1 && j >= m) {
      j -= m;
      m >>= 1;
    }
    j += m;
  }

  for (int size = 2; size <= n; size <<= 1) {
    final halfSize = size >> 1;
    final angle = -2.0 * math.pi / size;
    final wRe = math.cos(angle);
    final wIm = math.sin(angle);

    for (int i = 0; i < n; i += size) {
      double curRe = 1.0;
      double curIm = 0.0;

      for (int k = 0; k < halfSize; k++) {
        final evenIdx = (i + k) * 2;
        final oddIdx = (i + k + halfSize) * 2;

        final tRe = curRe * data[oddIdx] - curIm * data[oddIdx + 1];
        final tIm = curRe * data[oddIdx + 1] + curIm * data[oddIdx];

        data[oddIdx] = data[evenIdx] - tRe;
        data[oddIdx + 1] = data[evenIdx + 1] - tIm;
        data[evenIdx] += tRe;
        data[evenIdx + 1] += tIm;

        final newRe = curRe * wRe - curIm * wIm;
        curIm = curRe * wIm + curIm * wRe;
        curRe = newRe;
      }
    }
  }

  return data;
}

class _AudioInfoCard extends StatelessWidget {
  final AudioAnalysisData data;
  final VoidCallback? onRescan;

  const _AudioInfoCard({required this.data, this.onRescan});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nyquist = data.sampleRate / 2;

    return Card(
      elevation: 0,
      color: settingsGroupColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.audioAnalysisTitle,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (onRescan != null)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: context.l10n.audioAnalysisRescan,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    color: cs.onSurfaceVariant,
                    onPressed: onRescan,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (data.codec.isNotEmpty)
                  _MetricChip(
                    icon: Icons.memory,
                    label: context.l10n.audioAnalysisCodec,
                    value: data.codec,
                    cs: cs,
                  ),
                if (data.container.isNotEmpty)
                  _MetricChip(
                    icon: Icons.inventory_2_outlined,
                    label: context.l10n.audioAnalysisContainer,
                    value: data.container,
                    cs: cs,
                  ),
                _MetricChip(
                  icon: Icons.graphic_eq,
                  label: context.l10n.audioAnalysisSampleRate,
                  value: '${(data.sampleRate / 1000).toStringAsFixed(1)} kHz',
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.audio_file,
                  label: context.l10n.audioAnalysisBitDepth,
                  value: data.bitDepth,
                  cs: cs,
                ),
                if (data.decodedSampleFormat.isNotEmpty)
                  _MetricChip(
                    icon: Icons.data_object,
                    label: context.l10n.audioAnalysisDecodedFormat,
                    value: data.decodedSampleFormat,
                    cs: cs,
                  ),
                if (data.bitrate > 0)
                  _MetricChip(
                    icon: Icons.speed,
                    label: context.l10n.trackConvertBitrate,
                    value: _formatBitrate(data.bitrate),
                    cs: cs,
                  ),
                _MetricChip(
                  icon: Icons.surround_sound,
                  label: context.l10n.audioAnalysisChannels,
                  value: _formatChannels(context, data),
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.timer_outlined,
                  label: context.l10n.audioAnalysisDuration,
                  value: _formatDuration(data.duration),
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.multiline_chart,
                  label: context.l10n.audioAnalysisNyquist,
                  value: '${(nyquist / 1000).toStringAsFixed(1)} kHz',
                  cs: cs,
                ),
                if (data.fileSize > 0)
                  _MetricChip(
                    icon: Icons.storage,
                    label: context.l10n.audioAnalysisFileSize,
                    value: _formatFileSize(data.fileSize),
                    cs: cs,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _MetricChip(
                  icon: Icons.trending_up,
                  label: context.l10n.audioAnalysisDynamicRange,
                  value: '${data.dynamicRange.toStringAsFixed(2)} dB',
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.show_chart,
                  label: context.l10n.audioAnalysisPeak,
                  value: '${data.peakAmplitude.toStringAsFixed(2)} dB',
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.equalizer,
                  label: context.l10n.audioAnalysisRms,
                  value: '${data.rmsLevel.toStringAsFixed(2)} dB',
                  cs: cs,
                ),
                if (data.integratedLufs != null)
                  _MetricChip(
                    icon: Icons.volume_up_outlined,
                    label: context.l10n.audioAnalysisLufs,
                    value: '${data.integratedLufs!.toStringAsFixed(1)} LUFS',
                    cs: cs,
                  ),
                if (data.truePeakDb != null)
                  _MetricChip(
                    icon: Icons.warning_amber_outlined,
                    label: context.l10n.audioAnalysisTruePeak,
                    value: '${data.truePeakDb!.toStringAsFixed(2)} dBTP',
                    cs: cs,
                  ),
                _MetricChip(
                  icon: Icons.report_gmailerrorred_outlined,
                  label: context.l10n.audioAnalysisClipping,
                  value: _formatClipping(context, data.clippingSamples),
                  cs: cs,
                ),
                if (data.spectralCutoffHz != null)
                  _MetricChip(
                    icon: Icons.filter_alt_outlined,
                    label: context.l10n.audioAnalysisSpectralCutoff,
                    value: _formatFrequency(data.spectralCutoffHz!),
                    cs: cs,
                  ),
                _MetricChip(
                  icon: Icons.numbers,
                  label: context.l10n.audioAnalysisSamples,
                  value: _formatNumber(data.totalSamples),
                  cs: cs,
                ),
              ],
            ),
            if (data.channelStats.length > 1) ...[
              const SizedBox(height: 8),
              Divider(color: cs.outlineVariant),
              const SizedBox(height: 8),
              Text(
                context.l10n.audioAnalysisChannelStats,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: data.channelStats.map((stats) {
                  return _MetricChip(
                    icon: Icons.surround_sound,
                    label: 'Ch ${stats.channel}',
                    value: _formatChannelStats(stats),
                    cs: cs,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(double seconds) {
    final mins = seconds ~/ 60;
    final secs = (seconds % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String _formatChannels(BuildContext context, AudioAnalysisData data) {
    final layout = data.channelLayout.trim();
    if (layout.isNotEmpty && layout != 'unknown') {
      return data.channels > 0 ? '${data.channels} ($layout)' : layout;
    }
    if (data.channels == 2) return context.l10n.audioAnalysisStereo;
    if (data.channels == 1) return context.l10n.audioAnalysisMono;
    return data.channels > 0 ? '${data.channels}' : 'N/A';
  }

  String _formatFileSize(int bytes) {
    if (bytes == 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    final i = (math.log(bytes) / math.log(1024)).floor();
    final size = bytes / math.pow(1024, i);
    return '${size.toStringAsFixed(1)} ${units[i]}';
  }

  String _formatFrequency(double hz) {
    if (hz >= 1000) return '${(hz / 1000).toStringAsFixed(1)} kHz';
    return '${hz.round()} Hz';
  }

  String _formatBitrate(int bitsPerSecond) {
    if (bitsPerSecond >= 1000000) {
      return '${(bitsPerSecond / 1000000).toStringAsFixed(2)} Mbps';
    }
    return '${(bitsPerSecond / 1000).round()} kbps';
  }

  String _formatClipping(BuildContext context, int samples) {
    if (samples <= 0) return context.l10n.audioAnalysisNoClipping;
    return _formatNumber(samples);
  }

  String _formatChannelStats(ChannelAnalysisStats stats) {
    final parts = <String>[];
    if (stats.peakDb != null) {
      parts.add('P ${stats.peakDb!.toStringAsFixed(1)}');
    }
    if (stats.rmsDb != null) {
      parts.add('R ${stats.rmsDb!.toStringAsFixed(1)}');
    }
    if (stats.dynamicRangeDb != null) {
      parts.add('DR ${stats.dynamicRangeDb!.toStringAsFixed(1)}');
    }
    if (stats.peakCount > 0 && (stats.peakDb ?? -100) >= -0.1) {
      parts.add('Clip ${_formatNumber(stats.peakCount)}');
    }
    return parts.isEmpty ? 'N/A' : parts.join(' / ');
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpectrogramView extends StatelessWidget {
  final ui.Image image;
  final int sampleRate;
  final double maxFreq;
  final double duration;

  const _SpectrogramView({
    required this.image,
    required this.sampleRate,
    required this.maxFreq,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const labelColor = Color(0xFFB5B5B5);

    return Card(
      color: Colors.black,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 10, 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const leftGutter = 34.0;
                const bottomGutter = 18.0;
                final plotWidth = constraints.maxWidth - leftGutter;
                final plotHeight = plotWidth / 2.0;
                final totalHeight = plotHeight + bottomGutter;
                return SizedBox(
                  width: constraints.maxWidth,
                  height: totalHeight,
                  child: CustomPaint(
                    painter: _SpectrogramPainter(
                      image: image,
                      maxFreqHz: maxFreq,
                      durationSec: duration,
                      labelColor: labelColor,
                      gridColor: Colors.white.withValues(alpha: 0.10),
                    ),
                    size: Size(constraints.maxWidth, totalHeight),
                  ),
                );
              },
            ),
          ),
          // Intensity color legend (matches the spectrogram colormap).
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 10, 8),
            child: Row(
              children: [
                const Text(
                  'Quiet',
                  style: TextStyle(color: labelColor, fontSize: 10),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: LinearGradient(colors: _legendColors()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Loud',
                  style: TextStyle(color: labelColor, fontSize: 10),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${context.l10n.audioAnalysisSampleRate}: $sampleRate Hz',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
                const Spacer(),
                Text(
                  '${context.l10n.audioAnalysisNyquist}: ${(maxFreq / 1000).toStringAsFixed(1)} kHz',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<Color> _legendColors() {
    return List.generate(20, (i) {
      final c = _spekColorRGB(i / 19.0);
      return Color.fromARGB(255, c[0], c[1], c[2]);
    });
  }
}

class _SpectrogramPainter extends CustomPainter {
  final ui.Image image;
  final double maxFreqHz;
  final double durationSec;
  final Color labelColor;
  final Color gridColor;

  static const double leftGutter = 34;
  static const double bottomGutter = 18;

  _SpectrogramPainter({
    required this.image,
    required this.maxFreqHz,
    required this.durationSec,
    required this.labelColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(
      leftGutter,
      0,
      size.width - leftGutter,
      size.height - bottomGutter,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    // Spectrogram image.
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      plot,
      Paint()..filterQuality = FilterQuality.medium,
    );

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // Frequency axis (Y): 0 Hz at the bottom, maxFreq at the top.
    final maxKHz = maxFreqHz / 1000.0;
    if (maxKHz > 0) {
      final stepKHz = _niceStepKHz(maxKHz);
      for (double fk = 0; fk <= maxKHz + 0.001; fk += stepKHz) {
        final ratio = (fk * 1000) / maxFreqHz;
        final y = plot.bottom - ratio * plot.height;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
        _drawText(
          canvas,
          fk == 0 ? '0' : '${fk.toStringAsFixed(0)}k',
          Offset(plot.left - 5, y),
          align: _TextAlignV.rightCenter,
        );
      }
    }

    // Time axis (X): 0 at the left, duration at the right.
    if (durationSec > 0) {
      final stepSec = _niceStepSec(durationSec);
      for (double ts = 0; ts <= durationSec + 0.001; ts += stepSec) {
        final ratio = ts / durationSec;
        final x = plot.left + ratio * plot.width;
        canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
        _drawText(
          canvas,
          _fmtTime(ts),
          Offset(x, plot.bottom + 3),
          align: _TextAlignV.topCenter,
        );
      }
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset anchor, {
    required _TextAlignV align,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    double dx = anchor.dx;
    double dy = anchor.dy;
    switch (align) {
      case _TextAlignV.rightCenter:
        dx = anchor.dx - tp.width;
        dy = anchor.dy - tp.height / 2;
        break;
      case _TextAlignV.topCenter:
        dx = anchor.dx - tp.width / 2;
        dy = anchor.dy;
        break;
    }
    tp.paint(canvas, Offset(dx, dy));
  }

  static double _niceStepKHz(double maxKHz) {
    const candidates = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0];
    for (final c in candidates) {
      if (maxKHz / c <= 6) return c;
    }
    return 100.0;
  }

  static double _niceStepSec(double dur) {
    const candidates = [5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0, 600.0];
    for (final c in candidates) {
      if (dur / c <= 6) return c;
    }
    return 1200.0;
  }

  static String _fmtTime(double sec) {
    final s = sec.round();
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(covariant _SpectrogramPainter old) =>
      old.image != image ||
      old.maxFreqHz != maxFreqHz ||
      old.durationSec != durationSec;
}

enum _TextAlignV { rightCenter, topCenter }

class _SpectrogramRenderParams {
  final SpectrogramData spectrum;
  final int width;
  final int height;

  const _SpectrogramRenderParams({
    required this.spectrum,
    required this.width,
    required this.height,
  });
}

Uint8List _renderSpectrogramPixels(_SpectrogramRenderParams params) {
  final w = params.width;
  final h = params.height;
  final spectrum = params.spectrum;
  final pixels = Uint8List(w * h * 4);

  for (int i = 3; i < pixels.length; i += 4) {
    pixels[i] = 255;
  }

  final slices = spectrum.magnitudes;
  if (slices.isEmpty) return pixels;

  final freqBins = spectrum.freqBins;

  double minDB = 0;
  double maxDB = -200;
  for (final slice in slices) {
    for (int i = 0; i < slice.length; i++) {
      final db = slice[i];
      if (db > maxDB) maxDB = db;
      if (db < minDB && db > -200) minDB = db;
    }
  }
  minDB = math.max(minDB, maxDB - 90);
  final dbRange = maxDB - minDB;
  if (dbRange <= 0) return pixels;

  for (int px = 0; px < w; px++) {
    final t = (px / w * slices.length).floor().clamp(0, slices.length - 1);
    final slice = slices[t];

    for (int py = 0; py < h; py++) {
      final freqRatio = 1.0 - (py / h);
      final f = (freqRatio * freqBins).floor().clamp(0, freqBins - 1);
      if (f >= slice.length) continue;

      final db = slice[f];
      final intensity = ((db - minDB) / dbRange).clamp(0.0, 1.0);
      final color = _spekColorRGB(intensity);

      final offset = (py * w + px) * 4;
      pixels[offset] = color[0];
      pixels[offset + 1] = color[1];
      pixels[offset + 2] = color[2];
      pixels[offset + 3] = 255;
    }
  }

  return pixels;
}

List<int> _spekColorRGB(double intensity) {
  int r, g, b;
  if (intensity < 0.08) {
    final t = intensity / 0.08;
    r = 0;
    g = 0;
    b = (t * 80).floor();
  } else if (intensity < 0.18) {
    final t = (intensity - 0.08) / 0.10;
    r = (t * 50).floor();
    g = (t * 30).floor();
    b = (80 + t * 175).floor();
  } else if (intensity < 0.28) {
    final t = (intensity - 0.18) / 0.10;
    r = (50 + t * 150).floor();
    g = (30 - t * 30).floor();
    b = (255 - t * 55).floor();
  } else if (intensity < 0.40) {
    final t = (intensity - 0.28) / 0.12;
    r = (200 + t * 55).floor();
    g = 0;
    b = (200 - t * 200).floor();
  } else if (intensity < 0.52) {
    final t = (intensity - 0.40) / 0.12;
    r = 255;
    g = (t * 100).floor();
    b = 0;
  } else if (intensity < 0.65) {
    final t = (intensity - 0.52) / 0.13;
    r = 255;
    g = (100 + t * 80).floor();
    b = 0;
  } else if (intensity < 0.78) {
    final t = (intensity - 0.65) / 0.13;
    r = 255;
    g = (180 + t * 55).floor();
    b = (t * 30).floor();
  } else if (intensity < 0.90) {
    final t = (intensity - 0.78) / 0.12;
    r = 255;
    g = (235 + t * 20).floor();
    b = (30 + t * 100).floor();
  } else {
    final t = (intensity - 0.90) / 0.10;
    r = 255;
    g = 255;
    b = (130 + t * 125).floor();
  }
  return [r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255)];
}
