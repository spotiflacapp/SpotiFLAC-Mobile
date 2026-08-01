import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/utils/audio_format_utils.dart';
import 'package:spotiflac_android/utils/string_utils.dart';

const highQualityBadgeBitrateThresholdKbps = 900;

String normalizeLibraryQualityLabelMode(String? mode) {
  return mode == AppSettings.libraryQualityLabelBitDepth
      ? AppSettings.libraryQualityLabelBitDepth
      : AppSettings.libraryQualityLabelBitrate;
}

/// Builds a Library label from metadata already held in memory. Lossy formats
/// keep their bitrate label because bit depth is not a useful quality signal
/// for encoded MP3/AAC/Opus audio.
String? buildLibraryAudioQualityLabel({
  required String mode,
  String? format,
  int? bitrateKbps,
  int? bitDepth,
  int? sampleRate,
  String? storedQuality,
}) {
  final bitrateLabel = bitrateKbps != null && bitrateKbps > 0
      ? buildDisplayAudioQuality(bitrateKbps: bitrateKbps, format: format)
      : null;
  final bitDepthLabel =
      bitDepth != null && bitDepth > 0 && sampleRate != null && sampleRate > 0
      ? buildDisplayAudioQuality(bitDepth: bitDepth, sampleRate: sampleRate)
      : null;
  final fallback = normalizeOptionalString(storedQuality);

  final useBitDepth =
      normalizeLibraryQualityLabelMode(mode) ==
          AppSettings.libraryQualityLabelBitDepth &&
      !isLossyAudioFormat(format);
  return useBitDepth
      ? bitDepthLabel ?? bitrateLabel ?? fallback
      : bitrateLabel ?? bitDepthLabel ?? fallback;
}

/// Preserves the highlighted color used by legacy 24-bit Library badges while
/// also supporting newer labels that display a measured bitrate instead.
bool shouldHighlightAudioQualityBadge(String quality) {
  final normalized = quality.trim().toLowerCase();
  if (RegExp(r'\b24(?:\s*[- ]?\s*bit|/)').hasMatch(normalized)) {
    return true;
  }

  final kbpsMatch = RegExp(
    r'\b(\d+(?:\.\d+)?)\s*k(?:bps)?\b',
  ).firstMatch(normalized);
  final kbps = double.tryParse(kbpsMatch?.group(1) ?? '');
  if (kbps != null) {
    return kbps > highQualityBadgeBitrateThresholdKbps;
  }

  final mbpsMatch = RegExp(
    r'\b(\d+(?:\.\d+)?)\s*mbps\b',
  ).firstMatch(normalized);
  final mbps = double.tryParse(mbpsMatch?.group(1) ?? '');
  return mbps != null && mbps * 1000 > highQualityBadgeBitrateThresholdKbps;
}
