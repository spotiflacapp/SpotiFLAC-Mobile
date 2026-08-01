import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/string_utils.dart';

part 'audio_analysis_models.dart';
part 'audio_analysis_info_card.dart';
part 'audio_analysis_spectrogram.dart';

const int audioSpectrogramWidth = 1600;
const int audioSpectrogramHeight = 800;
const int audioSpectralAnalysisWidth = 400;
const double audioSpectrogramDynamicRangeDb = 120;

String formatAudioAnalysisSpectralCutoff(
  double? cutoffHz, {
  required String notDetectedLabel,
}) {
  if (cutoffHz == null || !cutoffHz.isFinite || cutoffHz <= 0) {
    return notDetectedLabel;
  }
  if (cutoffHz >= 1000) {
    return '${(cutoffHz / 1000).toStringAsFixed(1)} kHz';
  }
  return '${cutoffHz.round()} Hz';
}

final RegExp _ac4CodecTokenPattern = RegExp(
  r'(^|[^a-z0-9])ac[\s_-]?4($|[^a-z0-9])',
  caseSensitive: false,
);

/// Returns whether the bundled FFmpeg decoder can analyze this audio codec.
/// Container formats such as MP4 are intentionally not used here because the
/// same container may hold supported AAC/ALAC/E-AC-3 or unsupported AC-4.
bool isAudioAnalysisCodecSupported(String? codecName) {
  final value = codecName?.trim() ?? '';
  if (value.isEmpty) return true;
  return !_ac4CodecTokenPattern.hasMatch(value);
}

String? unsupportedAudioAnalysisCodecLabel(String? codecName) =>
    isAudioAnalysisCodecSupported(codecName) ? null : 'AC-4';

class _UnsupportedAudioAnalysisCodecException implements Exception {
  final String codecLabel;

  const _UnsupportedAudioAnalysisCodecException(this.codecLabel);
}

String _buildShowspectrumOptions({required int width, required String color}) {
  return 'showspectrumpic='
      's=${width}x$audioSpectrogramHeight:'
      'legend=0:mode=combined:color=$color:scale=log:fscale=lin:'
      'win_func=hann:drange=${audioSpectrogramDynamicRangeDb.toStringAsFixed(0)}:'
      'limit=0';
}

String buildAudioSpectrogramFilter({
  int channel = -1,
  bool includeCutoffPlane = false,
}) {
  final channelFilter = channel >= 0 ? 'pan=mono|c0=c$channel,' : '';
  final input = '[0:a:0]${channelFilter}aformat=sample_fmts=fltp';
  final display = _buildShowspectrumOptions(
    width: audioSpectrogramWidth,
    color: 'intensity',
  );
  if (!includeCutoffPlane) {
    return '$input,$display,format=rgba[spectrum]';
  }

  // The display palette encodes quiet bins as saturated blue/purple pixels,
  // so RGB brightness is not a monotonic measure of spectral magnitude. Keep
  // the colorful UI output, but generate a small fixed-hue plane whose gray
  // values can be used safely for effective-bandwidth detection.
  final cutoff = _buildShowspectrumOptions(
    width: audioSpectralAnalysisWidth,
    color: 'green',
  );
  return '$input,asplit=2[display_input][cutoff_input];'
      '[display_input]$display,format=rgba[spectrum];'
      '[cutoff_input]$cutoff,format=gray[cutoff]';
}

List<String> buildAudioSpectrogramArguments({
  required String inputPath,
  required String outputPath,
  String? cutoffOutputPath,
  int channel = -1,
}) {
  final arguments = <String>[
    '-hide_banner',
    '-y',
    '-i',
    inputPath,
    '-filter_complex',
    buildAudioSpectrogramFilter(
      channel: channel,
      includeCutoffPlane: cutoffOutputPath != null,
    ),
    '-map',
    '[spectrum]',
    '-frames:v',
    '1',
    '-f',
    'rawvideo',
    '-pix_fmt',
    'rgba',
    outputPath,
  ];
  if (cutoffOutputPath != null) {
    arguments.addAll([
      '-map',
      '[cutoff]',
      '-frames:v',
      '1',
      '-f',
      'rawvideo',
      '-pix_fmt',
      'gray',
      cutoffOutputPath,
    ]);
  }
  return arguments;
}

class AudioAstatsSummary {
  final double peakDb;
  final double rmsDb;

  const AudioAstatsSummary({required this.peakDb, required this.rmsDb});
}

class AudioAnalysisMetadataSummary extends AudioAstatsSummary {
  final double? integratedLufs;
  final double? truePeakDb;
  final List<ChannelAnalysisStats> channelStats;

  const AudioAnalysisMetadataSummary({
    required super.peakDb,
    required super.rmsDb,
    this.integratedLufs,
    this.truePeakDb,
    this.channelStats = const [],
  });
}

AudioAstatsSummary? parseAudioAstatsSummary(String logs) {
  final overallMatch = RegExp(r'Overall([\s\S]*)').firstMatch(logs);
  final section = overallMatch?.group(1) ?? logs;
  final peak = _parseLastAudioAstatsValue(section, 'Peak level dB');
  final rms = _parseLastAudioAstatsValue(section, 'RMS level dB');
  if (peak == null || rms == null) return null;
  return AudioAstatsSummary(peakDb: peak, rmsDb: rms);
}

double? _parseLastAudioAstatsValue(String text, String label) {
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

String buildAudioMetricsFilter({
  required double durationSeconds,
  required String metadataPath,
}) {
  final metadataStart = math.max(0.0, durationSeconds - 2.0);
  final escapedPath = metadataPath
      .replaceAll(r'\', r'\\')
      .replaceAll(':', r'\:')
      .replaceAll("'", r"\'");
  return 'astats=metadata=1:reset=0:'
      'measure_perchannel=Peak_level+RMS_level+Peak_count:'
      'measure_overall=Peak_level+RMS_level,'
      'ebur128=peak=true:metadata=1:framelog=quiet,'
      "aselect='gte(t,${metadataStart.toStringAsFixed(3)})',"
      "ametadata=print:file='$escapedPath'";
}

List<String> buildAudioMetricsArguments({
  required String inputPath,
  required String metadataPath,
  required double durationSeconds,
}) {
  // FFmpegKit's log level is process-global. A native download finalizer can
  // run `-v error` concurrently, so analyzer results must come from this
  // session's metadata file rather than info-level log callbacks.
  return [
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
    buildAudioMetricsFilter(
      durationSeconds: durationSeconds,
      metadataPath: metadataPath,
    ),
    '-f',
    'null',
    '-',
  ];
}

AudioAnalysisMetadataSummary? parseAudioAnalysisMetadata(String metadata) {
  final peak = _parseLastMetadataValue(
    metadata,
    'lavfi.astats.Overall.Peak_level',
  );
  final rms = _parseLastMetadataValue(
    metadata,
    'lavfi.astats.Overall.RMS_level',
  );
  if (peak == null || rms == null) return null;

  final channelNumbers = RegExp(
    r'^lavfi\.astats\.(\d+)\.',
    multiLine: true,
  ).allMatches(metadata).map((match) => int.parse(match.group(1)!)).toSet();
  final channelStats = channelNumbers.toList()..sort();

  final truePeakLinear = _parseLastMetadataValue(
    metadata,
    'lavfi.r128.true_peak',
  );
  return AudioAnalysisMetadataSummary(
    peakDb: peak,
    rmsDb: rms,
    integratedLufs: _parseLastMetadataValue(metadata, 'lavfi.r128.I'),
    truePeakDb: truePeakLinear != null && truePeakLinear > 0
        ? 20 * math.log(truePeakLinear) / math.ln10
        : null,
    channelStats: channelStats.map((channel) {
      final channelPeak = _parseLastMetadataValue(
        metadata,
        'lavfi.astats.$channel.Peak_level',
      );
      final channelRms = _parseLastMetadataValue(
        metadata,
        'lavfi.astats.$channel.RMS_level',
      );
      return ChannelAnalysisStats(
        channel: channel,
        peakDb: channelPeak,
        rmsDb: channelRms,
        dynamicRangeDb: channelPeak != null && channelRms != null
            ? channelPeak - channelRms
            : null,
        peakCount:
            _parseLastMetadataValue(
              metadata,
              'lavfi.astats.$channel.Peak_count',
            )?.round() ??
            0,
      );
    }).toList(),
  );
}

double? _parseLastMetadataValue(String metadata, String key) {
  final matches = RegExp(
    '^${RegExp.escape(key)}=([^\\r\\n]+)',
    multiLine: true,
  ).allMatches(metadata);
  double? value;
  for (final match in matches) {
    final parsed = double.tryParse(match.group(1)?.trim() ?? '');
    if (parsed != null && parsed.isFinite) value = parsed;
  }
  return value;
}

double? estimateEffectiveSpectralCutoffHz({
  required Uint8List intensity,
  required int width,
  required int height,
  required double maxFrequencyHz,
}) {
  if (width <= 0 ||
      height <= 0 ||
      maxFrequencyHz <= 0 ||
      intensity.length < width * height) {
    return null;
  }

  // Use a high temporal percentile so sustained musical bandwidth wins over
  // silence, while short ultrasonic transients do not define the cutoff.
  // These bytes come from FFmpeg's fixed-hue `color=green` output, where gray
  // value is monotonic with magnitude; display-palette RGB is deliberately not
  // accepted here because its blue noise floor has deceptively large channels.
  final profile = Float64List(height);
  final histogram = Uint32List(256);
  final percentileTarget = math.max(0, (width * 0.90).floor());
  for (var y = 0; y < height; y++) {
    histogram.fillRange(0, histogram.length, 0);
    final rowStart = y * width;
    for (var x = 0; x < width; x++) {
      histogram[intensity[rowStart + x]]++;
    }

    var cumulative = 0;
    for (var value = 0; value < histogram.length; value++) {
      cumulative += histogram[value];
      if (cumulative > percentileTarget) {
        // showspectrumpic stores Nyquist at the top. Reverse it here so array
        // indices increase with frequency, which makes edge detection clearer.
        profile[height - y - 1] = value.toDouble();
        break;
      }
    }
  }

  final hzPerRow = maxFrequencyHz / height;
  final smoothingRadius = math.max(1, (50 / hzPerRow).ceil());
  final smoothed = Float64List(height);
  var running = 0.0;
  var windowStart = 0;
  var windowEnd = -1;
  for (var index = 0; index < height; index++) {
    final desiredStart = math.max(0, index - smoothingRadius);
    final desiredEnd = math.min(height - 1, index + smoothingRadius);
    while (windowEnd < desiredEnd) {
      windowEnd++;
      running += profile[windowEnd];
    }
    while (windowStart < desiredStart) {
      running -= profile[windowStart];
      windowStart++;
    }
    smoothed[index] = running / (windowEnd - windowStart + 1);
  }

  final centralStart = math.max(0, (height * 0.05).floor());
  final centralEnd = math.min(height, (height * 0.95).ceil());
  final lowLevel = _spectralPercentile(
    smoothed,
    centralStart,
    centralEnd,
    0.10,
  );
  final highLevel = _spectralPercentile(
    smoothed,
    centralStart,
    centralEnd,
    0.95,
  );
  final dynamicSpan = highLevel - lowLevel;
  if (highLevel < 24) return null;
  if (dynamicSpan < 1) return maxFrequencyHz;

  // Locate a sharp downward edge over roughly 200 Hz, then validate it using
  // wider bands on both sides. This detects codec/low-pass bandwidth edges but
  // rejects a gradual musical roll-off or a narrow ultrasonic pilot.
  final edgeSpanRows = math.max(2, (200 / hzPerRow).ceil());
  final topGuardRows = math.max(edgeSpanRows, (500 / hzPerRow).ceil());
  final minSearchHz = math.max(1000.0, math.min(4000.0, maxFrequencyHz * 0.20));
  final searchStart = math.max(edgeSpanRows, (minSearchHz / hzPerRow).floor());
  final searchEnd = height - edgeSpanRows - topGuardRows;
  final candidateStarts = <int>[];
  for (var start = searchStart; start < searchEnd; start++) {
    final drop = smoothed[start] - smoothed[start + edgeSpanRows];
    if (drop > 0) candidateStarts.add(start);
  }
  candidateStarts.sort((a, b) {
    final aDrop = smoothed[a] - smoothed[a + edgeSpanRows];
    final bDrop = smoothed[b] - smoothed[b + edgeSpanRows];
    return bDrop.compareTo(aDrop);
  });

  final minimumDrop = math.max(12.0, dynamicSpan * 0.18);
  for (final bestStart in candidateStarts) {
    final bestLocalDrop =
        smoothed[bestStart] - smoothed[bestStart + edgeSpanRows];
    if (bestLocalDrop < minimumDrop * 0.60) break;
    final edgeIndex = (bestStart + edgeSpanRows / 2).round();
    final gapRows = math.max(1, (100 / hzPerRow).ceil());
    final supportRows = math.max(3, (1200 / hzPerRow).ceil());
    final belowEnd = edgeIndex - gapRows;
    final belowStart = math.max(0, belowEnd - supportRows);
    final aboveStart = edgeIndex + gapRows;
    final aboveEnd = math.min(height, aboveStart + supportRows);
    if (belowEnd > belowStart && aboveEnd > aboveStart) {
      final belowLevel = _spectralMedian(smoothed, belowStart, belowEnd);
      final aboveLevel = _spectralMedian(smoothed, aboveStart, aboveEnd);
      final tailLevel = _spectralMedian(smoothed, aboveStart, height);
      final baseStart = math.max(0, edgeIndex - (3000 / hzPerRow).ceil());
      final baseLevel = _spectralMedian(smoothed, baseStart, belowEnd);
      if (belowLevel - aboveLevel >= minimumDrop &&
          belowLevel - tailLevel >= minimumDrop &&
          baseLevel - tailLevel >= minimumDrop) {
        final cutoff = (edgeIndex + 0.5) * hzPerRow;
        return cutoff.clamp(0.0, maxFrequencyHz).toDouble();
      }
    }
  }

  // A genuinely broadband signal with no internal falling edge reaches the
  // analysis ceiling. Natural music has a pronounced spectral tilt, so the
  // top band does not need to be almost as loud as the baseband. It must still
  // sit clearly above the measured low-level floor; silence or an isolated
  // high-frequency line therefore continues to return null.
  final basebandLevel = _spectralMedian(
    smoothed,
    (height * 0.05).floor(),
    math.max(1, (height * 0.50).floor()),
  );
  final topBandLevel = _spectralMedian(
    smoothed,
    (height * 0.90).floor(),
    math.max(1, (height * 0.98).floor()),
  );
  final populatedTopFloor = math.max(24.0, lowLevel * 0.60);
  if (basebandLevel >= 24 && topBandLevel >= populatedTopFloor) {
    return maxFrequencyHz;
  }
  return null;
}

double _spectralMedian(Float64List values, int start, int end) {
  return _spectralPercentile(values, start, end, 0.50);
}

double _spectralPercentile(
  Float64List values,
  int start,
  int end,
  double percentile,
) {
  final safeStart = start.clamp(0, values.length).toInt();
  final safeEnd = end.clamp(safeStart, values.length).toInt();
  if (safeEnd <= safeStart) return 0;
  final sorted = values.sublist(safeStart, safeEnd)..sort();
  final index = ((sorted.length - 1) * percentile)
      .round()
      .clamp(0, sorted.length - 1)
      .toInt();
  return sorted[index];
}

class AudioAnalysisCard extends StatefulWidget {
  final String filePath;
  final String? codecHint;

  const AudioAnalysisCard({super.key, required this.filePath, this.codecHint});

  @override
  State<AudioAnalysisCard> createState() => _AudioAnalysisCardState();
}

class _AudioAnalysisCardState extends State<AudioAnalysisCard> {
  AudioAnalysisData? _data;
  bool _analyzing = false;
  bool _checkingCache = true;
  String? _error;
  ui.Image? _spectrogramImage;
  int _spectrogramChannel = -1;
  bool _spectrogramChannelLoading = false;
  int _spectrogramRequestId = 0;
  String? _unsupportedCodec;

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
    _unsupportedCodec = unsupportedAudioAnalysisCodecLabel(widget.codecHint);
    if (_isSupported) {
      if (_unsupportedCodec == null) {
        _tryLoadFromCache();
      } else {
        _checkingCache = false;
      }
    }
  }

  @override
  void didUpdateWidget(covariant AudioAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath == widget.filePath &&
        oldWidget.codecHint == widget.codecHint) {
      return;
    }

    _spectrogramRequestId++;
    _spectrogramImage?.dispose();
    _spectrogramImage = null;
    _spectrogramChannel = -1;
    _spectrogramChannelLoading = false;
    _data = null;
    _error = null;
    _analyzing = false;
    _unsupportedCodec = unsupportedAudioAnalysisCodecLabel(widget.codecHint);
    _checkingCache = _isSupported && _unsupportedCodec == null;

    if (_checkingCache) {
      unawaited(_tryLoadFromCache());
    }
  }

  @override
  void dispose() {
    _spectrogramRequestId++;
    _spectrogramImage?.dispose();
    super.dispose();
  }

  Future<void> _tryLoadFromCache() async {
    final expectedPath = widget.filePath;
    final requestId = _spectrogramRequestId;
    bool isCurrentRequest() =>
        mounted &&
        widget.filePath == expectedPath &&
        requestId == _spectrogramRequestId;

    try {
      final cached = await _loadFromCache(expectedPath);
      if (cached != null && isCurrentRequest()) {
        final unsupported = unsupportedAudioAnalysisCodecLabel(cached.codec);
        if (unsupported != null) {
          await _clearCache(expectedPath);
          if (isCurrentRequest()) {
            setState(() {
              _unsupportedCodec = unsupported;
              _checkingCache = false;
            });
          }
          return;
        }
        setState(() {
          _data = cached;
          _checkingCache = false;
        });
        var image = await _loadSpectrogramFromCache(
          expectedPath,
          channel: _spectrogramChannel,
        );
        image ??= await _generateAndCacheSpectrogram(filePath: expectedPath);
        if (isCurrentRequest()) {
          setState(() {
            _spectrogramImage?.dispose();
            _spectrogramImage = image;
          });
        } else {
          image.dispose();
        }
        return;
      }
    } catch (_) {}
    if (isCurrentRequest()) {
      setState(() => _checkingCache = false);
    }
  }

  Future<ui.Image> _generateAndCacheSpectrogram({String? filePath}) async {
    final sourcePath = filePath ?? widget.filePath;
    final artifact = await _generateSpectrogramForFile(
      sourcePath,
      channel: _spectrogramChannel,
    );
    await _saveSpectrogramToCache(
      sourcePath,
      artifact.image,
      channel: _spectrogramChannel,
    );
    return artifact.image;
  }

  Future<void> _analyze({bool forceRefresh = false}) async {
    if (_analyzing) return;
    setState(() {
      _spectrogramRequestId++;
      _analyzing = true;
      _spectrogramChannelLoading = false;
      _error = null;
      if (forceRefresh) {
        _spectrogramImage?.dispose();
        _spectrogramImage = null;
        _data = null;
        _spectrogramChannel = -1;
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
      ui.Image? image;

      if (cached != null) {
        final unsupported = unsupportedAudioAnalysisCodecLabel(cached.codec);
        if (unsupported != null) {
          throw _UnsupportedAudioAnalysisCodecException(unsupported);
        }
        data = cached;
        image = await _loadSpectrogramFromCache(
          widget.filePath,
          channel: _spectrogramChannel,
        );
      } else {
        final result = await _runAnalysis(widget.filePath);
        data = result.data;
        image = result.spectrogramImage;
        await _saveToCache(widget.filePath, data);
        await _saveSpectrogramToCache(
          widget.filePath,
          image,
          channel: _spectrogramChannel,
        );
      }

      image ??= await _generateAndCacheSpectrogram();

      if (mounted) {
        setState(() {
          _data = data;
          _spectrogramImage?.dispose();
          _spectrogramImage = image;
          _analyzing = false;
        });
      } else {
        image.dispose();
      }
    } on _UnsupportedAudioAnalysisCodecException catch (e) {
      if (mounted) {
        setState(() {
          _unsupportedCodec = e.codecLabel;
          _error = null;
          _analyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = context.friendlyError(e);
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
      if (await jsonFile.exists()) {
        await jsonFile.delete();
      }
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.replaceAll('\\', '/').split('/').last;
        final isCombined = name == '$key.png';
        final isChannel = name.startsWith('${key}_ch') && name.endsWith('.png');
        if (isCombined || isChannel) {
          await entity.delete();
        }
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
    ui.Image image, {
    required int channel,
  }) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final file = File(
          '${dir.path}/${_spectrogramCacheFileName(key, channel)}',
        );
        await file.writeAsBytes(byteData.buffer.asUint8List());
      }
    } catch (_) {}
  }

  static String _spectrogramCacheFileName(String key, int channel) =>
      channel < 0 ? '$key.png' : '${key}_ch$channel.png';

  static Future<ui.Image?> _loadSpectrogramFromCache(
    String filePath, {
    required int channel,
  }) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final file = File(
        '${dir.path}/${_spectrogramCacheFileName(key, channel)}',
      );
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, completer.complete);
      return completer.future;
    } catch (_) {
      return null;
    }
  }

  Future<_AudioAnalysisRunResult> _runAnalysis(String filePath) async {
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
      final unsupported = unsupportedAudioAnalysisCodecLabel(info.codecName);
      if (unsupported != null) {
        throw _UnsupportedAudioAnalysisCodecException(unsupported);
      }
      _GeneratedSpectrogram? spectrogram;
      try {
        spectrogram = await _generateSpectrogram(
          workingPath,
          channel: -1,
          includeCutoffPlane: true,
        );
        final cutoffIntensity = spectrogram.cutoffIntensity;
        if (cutoffIntensity == null) {
          throw Exception('FFmpeg spectral cutoff plane was not generated');
        }
        final spectralCutoffHz = await compute(
          _estimateEffectiveSpectralCutoffInIsolate,
          _SpectralCutoffParams(
            intensity: cutoffIntensity,
            width: audioSpectralAnalysisWidth,
            height: audioSpectrogramHeight,
            maxFrequencyHz: info.sampleRate / 2,
          ),
        );
        final effectiveDuration = info.totalSamples > 0 && info.sampleRate > 0
            ? info.totalSamples / info.sampleRate
            : info.duration;
        final levelMetrics = await _runFullStreamLevelAnalysis(
          workingPath,
          durationSeconds: effectiveDuration,
        );
        if (levelMetrics == null) {
          throw Exception('FFmpeg level analysis returned no usable metrics');
        }
        final peakAmplitude = levelMetrics.peakDb;
        final rmsLevel = levelMetrics.rmsDb;
        final dynamicRange = peakAmplitude - rmsLevel;

        return _AudioAnalysisRunResult(
          data: AudioAnalysisData(
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
            integratedLufs: levelMetrics.integratedLufs,
            truePeakDb: levelMetrics.truePeakDb,
            clippingSamples: levelMetrics.clippingSamples,
            spectralCutoffHz: spectralCutoffHz,
            channelStats: levelMetrics.channelStats,
            totalSamples: info.totalSamples,
          ),
          spectrogramImage: spectrogram.image,
        );
      } catch (_) {
        spectrogram?.image.dispose();
        rethrow;
      }
    } finally {
      if (tempCopy != null) {
        try {
          await File(tempCopy).delete();
        } catch (_) {}
      }
    }
  }

  Future<_GeneratedSpectrogram> _generateSpectrogramForFile(
    String filePath, {
    required int channel,
  }) async {
    String workingPath = filePath;
    String? tempCopy;
    if (filePath.startsWith('content://')) {
      tempCopy = await PlatformBridge.copyContentUriToTemp(filePath);
      if (tempCopy == null) {
        throw Exception('Failed to copy SAF file for spectrogram');
      }
      workingPath = tempCopy;
    }

    try {
      return await _generateSpectrogram(workingPath, channel: channel);
    } finally {
      if (tempCopy != null) {
        try {
          await File(tempCopy).delete();
        } catch (_) {}
      }
    }
  }

  Future<_GeneratedSpectrogram> _generateSpectrogram(
    String inputPath, {
    required int channel,
    bool includeCutoffPlane = false,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final rawPath =
        '${tempDir.path}/analysis_spectrum_'
        '${DateTime.now().microsecondsSinceEpoch}_${channel + 1}.rgba';
    final cutoffPath = includeCutoffPlane ? '$rawPath.cutoff.gray' : null;

    try {
      final session = await FFmpegKit.executeWithArguments(
        buildAudioSpectrogramArguments(
          inputPath: inputPath,
          outputPath: rawPath,
          cutoffOutputPath: cutoffPath,
          channel: channel,
        ),
      );

      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getLogsAsString();
        throw Exception('FFmpeg spectrogram failed: $logs');
      }

      final expectedLength = audioSpectrogramWidth * audioSpectrogramHeight * 4;
      final rawBytes = await File(rawPath).readAsBytes();
      if (rawBytes.length < expectedLength) {
        throw Exception(
          'Incomplete spectrogram output '
          '(${rawBytes.length}/$expectedLength bytes)',
        );
      }
      final rgba = rawBytes.length == expectedLength
          ? rawBytes
          : Uint8List.sublistView(rawBytes, 0, expectedLength);
      Uint8List? cutoffIntensity;
      if (cutoffPath != null) {
        final expectedCutoffLength =
            audioSpectralAnalysisWidth * audioSpectrogramHeight;
        final cutoffBytes = await File(cutoffPath).readAsBytes();
        if (cutoffBytes.length < expectedCutoffLength) {
          throw Exception(
            'Incomplete spectral cutoff output '
            '(${cutoffBytes.length}/$expectedCutoffLength bytes)',
          );
        }
        cutoffIntensity = cutoffBytes.length == expectedCutoffLength
            ? cutoffBytes
            : Uint8List.sublistView(cutoffBytes, 0, expectedCutoffLength);
      }
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        audioSpectrogramWidth,
        audioSpectrogramHeight,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      return _GeneratedSpectrogram(
        image: await completer.future,
        rgba: rgba,
        cutoffIntensity: cutoffIntensity,
      );
    } finally {
      try {
        await File(rawPath).delete();
      } catch (_) {}
      if (cutoffPath != null) {
        try {
          await File(cutoffPath).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _changeSpectrogramChannel(int channel) async {
    final data = _data;
    if (data == null ||
        channel == _spectrogramChannel ||
        channel < -1 ||
        channel >= data.channels) {
      return;
    }

    final previousChannel = _spectrogramChannel;
    final requestId = ++_spectrogramRequestId;
    setState(() {
      _spectrogramChannel = channel;
      _spectrogramChannelLoading = true;
    });

    ui.Image? image;
    try {
      image = await _loadSpectrogramFromCache(
        widget.filePath,
        channel: channel,
      );
      if (image == null) {
        final artifact = await _generateSpectrogramForFile(
          widget.filePath,
          channel: channel,
        );
        image = artifact.image;
        await _saveSpectrogramToCache(widget.filePath, image, channel: channel);
      }

      if (!mounted || requestId != _spectrogramRequestId) {
        image.dispose();
        return;
      }
      setState(() {
        _spectrogramImage?.dispose();
        _spectrogramImage = image;
        _spectrogramChannelLoading = false;
      });
    } catch (_) {
      image?.dispose();
      if (mounted && requestId == _spectrogramRequestId) {
        setState(() {
          _spectrogramChannel = previousChannel;
          _spectrogramChannelLoading = false;
        });
      }
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
      codecName: codecName,
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

  Future<_LevelMetrics?> _runFullStreamLevelAnalysis(
    String inputPath, {
    required double durationSeconds,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final metadataFile = File(
      '${tempDir.path}/analysis_metrics_'
      '${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    try {
      final session = await FFmpegKit.executeWithArguments(
        buildAudioMetricsArguments(
          inputPath: inputPath,
          metadataPath: metadataFile.path,
          durationSeconds: durationSeconds,
        ),
      );

      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        return null;
      }

      final metadata = await metadataFile.exists()
          ? await metadataFile.readAsString()
          : '';
      final metadataSummary = parseAudioAnalysisMetadata(metadata);
      final logs = metadataSummary == null
          ? await session.getAllLogsAsString() ?? ''
          : '';
      final summary = metadataSummary ?? parseAudioAstatsSummary(logs);
      if (summary == null) return null;
      final channelStats = metadataSummary?.channelStats.isNotEmpty == true
          ? metadataSummary!.channelStats
          : _parseChannelStats(logs);
      final clippingSamples = channelStats.fold<int>(0, (sum, stats) {
        if (stats.peakDb == null || stats.peakDb! < -0.1) return sum;
        return sum + stats.peakCount;
      });
      return _LevelMetrics(
        peakDb: summary.peakDb,
        rmsDb: summary.rmsDb,
        integratedLufs: metadataSummary?.integratedLufs,
        truePeakDb: metadataSummary?.truePeakDb,
        clippingSamples: clippingSamples,
        channelStats: channelStats,
      );
    } finally {
      try {
        if (await metadataFile.exists()) await metadataFile.delete();
      } catch (_) {}
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
    return _parseLastAudioAstatsValue(text, label);
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

  @override
  Widget build(BuildContext context) {
    if (!_isSupported) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    if (_checkingCache) return const SizedBox.shrink();

    if (_unsupportedCodec != null) {
      return Card(
        elevation: 0,
        color: settingsGroupColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: cs.primary, size: 24),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 4),
                    Text(
                      '${l10n.snackbarUnsupportedAudioFormat}: '
                      '$_unsupportedCodec',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

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
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
            maxFreq: data.sampleRate / 2,
            duration: data.duration,
            channels: data.channels,
            selectedChannel: _spectrogramChannel,
            channelLoading: _spectrogramChannelLoading,
            onChannelChanged: _changeSpectrogramChannel,
          ),
        ],
      ],
    );
  }
}
