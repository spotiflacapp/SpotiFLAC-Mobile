import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_session.dart';

/// Describes an extension-requested decryption step without coupling callers
/// to the FFmpeg execution service.
class DownloadDecryptionDescriptor {
  final String strategy;
  final String key;
  final String? inputFormat;
  final String? outputExtension;

  const DownloadDecryptionDescriptor({
    required this.strategy,
    required this.key,
    this.inputFormat,
    this.outputExtension,
  });

  factory DownloadDecryptionDescriptor.fromJson(Map<String, dynamic> json) {
    return DownloadDecryptionDescriptor(
      strategy: (json['strategy'] as String? ?? '').trim(),
      key: (json['key'] as String? ?? '').trim(),
      inputFormat: (json['input_format'] as String?)?.trim(),
      outputExtension: (json['output_extension'] as String?)?.trim(),
    );
  }

  static DownloadDecryptionDescriptor? fromDownloadResult(
    Map<String, dynamic> result,
  ) {
    final rawDecryption = result['decryption'];
    if (rawDecryption is Map) {
      final descriptorJson = Map<String, dynamic>.from(rawDecryption);
      descriptorJson['output_extension'] ??= result['output_extension'];
      final descriptor = DownloadDecryptionDescriptor.fromJson(descriptorJson);
      if (descriptor.normalizedStrategy == 'ffmpeg.mov_key' &&
          descriptor.key.isNotEmpty) {
        return descriptor;
      }
    }

    final legacyKey = (result['decryption_key'] as String?)?.trim() ?? '';
    if (legacyKey.isEmpty) {
      return null;
    }

    return DownloadDecryptionDescriptor(
      strategy: 'ffmpeg.mov_key',
      key: legacyKey,
      inputFormat: 'mov',
      outputExtension: (result['output_extension'] as String?)?.trim(),
    );
  }

  String get normalizedStrategy {
    switch (strategy.trim().toLowerCase()) {
      case '':
      case 'ffmpeg.mov_key':
      case 'ffmpeg_mov_key':
      case 'mov_decryption_key':
      case 'mp4_decryption_key':
      case 'ffmpeg.mp4_decryption_key':
        return 'ffmpeg.mov_key';
      default:
        return strategy.trim();
    }
  }

  String? get normalizedOutputExtension {
    final trimmed = (outputExtension ?? '').trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    return trimmed.startsWith('.') ? trimmed : '.$trimmed';
  }
}

class CueSplitTrackInfo {
  final int number;
  final String title;
  final String artist;
  final String isrc;
  final String composer;
  final double startSec;
  final double endSec;

  CueSplitTrackInfo({
    required this.number,
    required this.title,
    required this.artist,
    this.isrc = '',
    this.composer = '',
    required this.startSec,
    required this.endSec,
  });

  factory CueSplitTrackInfo.fromJson(Map<String, dynamic> json) {
    return CueSplitTrackInfo(
      number: json['number'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      isrc: json['isrc'] as String? ?? '',
      composer: json['composer'] as String? ?? '',
      startSec: (json['start_sec'] as num?)?.toDouble() ?? 0.0,
      endSec: (json['end_sec'] as num?)?.toDouble() ?? -1.0,
    );
  }
}

class FFmpegResult {
  final bool success;
  final int returnCode;
  final String output;

  FFmpegResult({
    required this.success,
    required this.returnCode,
    required this.output,
  });
}

class LiveDecryptedStreamResult {
  final String localUrl;
  final String format;
  final FFmpegSession session;

  LiveDecryptedStreamResult({
    required this.localUrl,
    required this.format,
    required this.session,
  });
}

/// Result of an EBU R128 loudness scan, used to compute ReplayGain tags.
class ReplayGainResult {
  /// Track gain in dB, e.g. "-6.50 dB".
  final String trackGain;

  /// Track peak as a linear ratio, e.g. "0.988831".
  final String trackPeak;

  /// Raw integrated loudness in LUFS (needed for album gain computation).
  final double integratedLufs;

  /// Raw true peak as linear ratio (needed for album peak computation).
  final double truePeakLinear;

  const ReplayGainResult({
    required this.trackGain,
    required this.trackPeak,
    required this.integratedLufs,
    required this.truePeakLinear,
  });

  @override
  String toString() =>
      'ReplayGainResult(trackGain: $trackGain, trackPeak: $trackPeak)';
}
