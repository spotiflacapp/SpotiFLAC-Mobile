part of 'audio_analysis_widget.dart';

// Analysis result models and per-run parameter records.

class AudioAnalysisData {
  static const cacheVersion = 8;

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

class _GeneratedSpectrogram {
  final ui.Image image;
  final Uint8List rgba;
  final Uint8List? cutoffIntensity;

  const _GeneratedSpectrogram({
    required this.image,
    required this.rgba,
    this.cutoffIntensity,
  });
}

class _AudioAnalysisRunResult {
  final AudioAnalysisData data;
  final ui.Image spectrogramImage;

  const _AudioAnalysisRunResult({
    required this.data,
    required this.spectrogramImage,
  });
}

class _SpectralCutoffParams {
  final Uint8List intensity;
  final int width;
  final int height;
  final double maxFrequencyHz;

  const _SpectralCutoffParams({
    required this.intensity,
    required this.width,
    required this.height,
    required this.maxFrequencyHz,
  });
}

double? _estimateEffectiveSpectralCutoffInIsolate(
  _SpectralCutoffParams params,
) {
  return estimateEffectiveSpectralCutoffHz(
    intensity: params.intensity,
    width: params.width,
    height: params.height,
    maxFrequencyHz: params.maxFrequencyHz,
  );
}

class _MediaInfo {
  final int fileSize;
  final String codecName;
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
    required this.codecName,
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
  final double? integratedLufs;
  final double? truePeakDb;
  final int clippingSamples;
  final List<ChannelAnalysisStats> channelStats;

  const _LevelMetrics({
    required this.peakDb,
    required this.rmsDb,
    this.integratedLufs,
    this.truePeakDb,
    this.clippingSamples = 0,
    this.channelStats = const [],
  });
}
