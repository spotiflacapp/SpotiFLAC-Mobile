import 'package:spotiflac_android/utils/int_utils.dart';
import 'package:spotiflac_android/utils/string_utils.dart';

/// Parses a bitrate value that may be expressed in bps or kbps, returning
/// `null` for anything below a plausible lossy-audio floor.
int? readPositiveBitrateKbps(dynamic value) {
  final parsed = readPositiveInt(value);
  if (parsed == null) return null;
  final kbps = parsed >= 10000 ? (parsed / 1000).round() : parsed;
  return kbps >= 16 ? kbps : null;
}

/// Guesses an audio format from a file path/name extension.
String? audioFormatForPath(String? filePath, {String? fileName}) {
  final candidates = <String>[?filePath, ?fileName];
  for (final candidate in candidates) {
    final lower = candidate.trim().toLowerCase();
    if (lower.endsWith('.opus') || lower.endsWith('.ogg')) return 'OPUS';
    if (lower.endsWith('.mp3')) return 'MP3';
    if (lower.endsWith('.aac')) return 'AAC';
    if (lower.endsWith('.m4a') || lower.endsWith('.mp4')) return 'M4A';
  }
  return null;
}

/// Returns [quality] unless it's a placeholder, an implausibly low bitrate,
/// or a "requested lossless" label that doesn't describe an actual delivered
/// quality (e.g. `HI_RES_LOSSLESS` before the real quality is known).
String? nonPlaceholderQuality(String? quality) {
  final normalized = normalizeOptionalString(quality);
  if (normalized == null || isPlaceholderQualityLabel(normalized)) {
    return null;
  }
  final bitrateMatch = RegExp(
    r'\b(\d+)\s*kbps\b',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (bitrateMatch != null) {
    final bitrate = int.tryParse(bitrateMatch.group(1) ?? '');
    if (bitrate != null && bitrate < 16) return null;
  }
  final lower = normalized.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  const requestedLosslessLabels = {
    'hi_res_lossless',
    'hires_lossless',
    'hi_res',
    'hires',
    'flac_best_available',
  };
  if (requestedLosslessLabels.contains(lower)) return null;
  return normalized;
}

/// Normalizes a codec/format string to one of the lowercase canonical
/// format keys used throughout the download/conversion pipeline.
String? normalizeAudioFormatValue(String? value) {
  final normalized = normalizeOptionalString(
    value,
  )?.toLowerCase().replaceAll('-', '_');
  return switch (normalized) {
    'flac' => 'flac',
    'alac' => 'alac',
    'aac' || 'mp4a' => 'aac',
    'eac3' || 'ec_3' => 'eac3',
    'ac3' || 'ac_3' => 'ac3',
    'ac4' || 'ac_4' => 'ac4',
    'mp3' => 'mp3',
    'opus' || 'ogg' => 'opus',
    'm4a' || 'mp4' => 'm4a',
    _ => null,
  };
}

/// Whether [value] normalizes to one of the lossy (bitrate-based) formats.
bool isLossyAudioFormat(String? value) {
  return const {
    'aac',
    'eac3',
    'ac3',
    'ac4',
    'mp3',
    'opus',
    'm4a',
  }.contains(normalizeAudioFormatValue(value));
}

/// Maps a free-form lossy format setting string to a canonical format key.
String lossyFormatForSetting(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.startsWith('opus')) return 'opus';
  if (normalized.startsWith('aac') || normalized.startsWith('m4a')) {
    return 'aac';
  }
  return 'mp3';
}

/// The file extension (with leading dot) for a canonical lossy format key.
String lossyExtensionForFormat(String format) {
  return switch (format) {
    'opus' => '.opus',
    'aac' => '.m4a',
    _ => '.mp3',
  };
}

/// The metadata-tag format name for a canonical lossy format key.
String metadataFormatForLossyFormat(String format) {
  return format == 'aac' ? 'm4a' : format;
}

/// The user-facing display label for a canonical lossy format key.
String displayFormatForLossyFormat(String format) {
  return format == 'aac' ? 'AAC' : format.toUpperCase();
}

/// The user-facing display format label for a codec/format string, or
/// `null` if it doesn't map to a known display format.
String? displayFormatForCodec(String? value) {
  final normalized = normalizeOptionalString(
    value,
  )?.toLowerCase().replaceAll('-', '_');
  return switch (normalized) {
    'flac' => 'FLAC',
    'alac' => 'ALAC',
    'aac' || 'mp4a' => 'AAC',
    'eac3' || 'ec_3' => 'EAC3',
    'ac3' || 'ac_3' => 'AC3',
    'ac4' || 'ac_4' => 'AC4',
    'mp3' => 'MP3',
    'opus' => 'OPUS',
    _ => null,
  };
}

/// Resolves the best user-facing quality/format label for a track from
/// whatever combination of detected codec, bit depth/sample rate, bitrate,
/// and previously stored quality string is available.
String? resolveDisplayQuality({
  required String? filePath,
  String? fileName,
  String? detectedFormat,
  int? bitDepth,
  int? sampleRate,
  int? bitrateKbps,
  String? storedQuality,
}) {
  final format =
      displayFormatForCodec(detectedFormat) ??
      audioFormatForPath(filePath, fileName: fileName);
  if (format == 'OPUS' ||
      format == 'MP3' ||
      format == 'AAC' ||
      format == 'EAC3' ||
      format == 'AC3' ||
      format == 'AC4' ||
      (format == 'M4A' && (bitDepth == null || bitDepth <= 0))) {
    return buildDisplayAudioQuality(bitrateKbps: bitrateKbps, format: format) ??
        nonPlaceholderQuality(storedQuality) ??
        format;
  }
  return buildDisplayAudioQuality(
    bitDepth: bitDepth,
    sampleRate: sampleRate,
    storedQuality: nonPlaceholderQuality(storedQuality) ?? storedQuality,
  );
}
