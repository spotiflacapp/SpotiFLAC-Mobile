import 'dart:io';

import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/file_access.dart';

final RegExp _lrcDisplayTimestampPattern = RegExp(
  r'^\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]',
);
final RegExp _lrcDisplayMetadataPattern = RegExp(
  r'^\[[a-zA-Z][a-zA-Z0-9_]*:.*\]$',
);
final RegExp _lrcDisplayInlineTimestampPattern = RegExp(
  r'<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>',
);
final RegExp _lrcDisplaySpeakerPrefixPattern = RegExp(
  r'^(v1|v2):\s*',
  caseSensitive: false,
);
final RegExp _lrcDisplayBackgroundLinePattern = RegExp(
  r'^\[bg:(.*)\]$',
  caseSensitive: false,
);

bool isInstrumentalLyricsMarker(String lyrics) =>
    lyrics.trim().toLowerCase() == '[instrumental:true]';

/// Converts embedded or fetched LRC into text suitable for the metadata UI.
/// Header-only payloads intentionally produce an empty string.
String cleanLyricsForDisplay(String lyrics) {
  final cleanLines = <String>[];

  for (final line in lyrics.split('\n')) {
    var cleaned = line.trim();

    if (_lrcDisplayMetadataPattern.hasMatch(cleaned) &&
        !_lrcDisplayBackgroundLinePattern.hasMatch(cleaned)) {
      continue;
    }

    final backgroundMatch = _lrcDisplayBackgroundLinePattern.firstMatch(
      cleaned,
    );
    if (backgroundMatch != null) {
      cleaned = backgroundMatch.group(1)?.trim() ?? '';
    }

    while (_lrcDisplayTimestampPattern.hasMatch(cleaned)) {
      cleaned = cleaned.replaceFirst(_lrcDisplayTimestampPattern, '').trim();
    }
    cleaned = cleaned.replaceAll(_lrcDisplayInlineTimestampPattern, '');
    cleaned = cleaned.replaceFirst(_lrcDisplaySpeakerPrefixPattern, '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleaned.isNotEmpty) {
      cleanLines.add(cleaned);
    }
  }

  return cleanLines.join('\n');
}

bool hasUsableLyricsContent(String lyrics) =>
    isInstrumentalLyricsMarker(lyrics) ||
    cleanLyricsForDisplay(lyrics).trim().isNotEmpty;

bool hasEmbeddedLyricsMetadata(Map<String, String> metadata) {
  final lyrics = (metadata['LYRICS'] ?? '').trim();
  if (hasUsableLyricsContent(lyrics)) return true;

  final unsyncedLyrics = (metadata['UNSYNCEDLYRICS'] ?? '').trim();
  if (hasUsableLyricsContent(unsyncedLyrics)) return true;

  return false;
}

String _sidecarLrcPath(String path) {
  final slash = path.lastIndexOf(Platform.pathSeparator);
  final dot = path.lastIndexOf('.');
  if (dot > slash) {
    return '${path.substring(0, dot)}.lrc';
  }
  return '$path.lrc';
}

/// Writes a ".lrc" sidecar next to a re-enriched audio file when the Go backend
/// result requests it (`write_external_lrc`), honoring the user's lyrics mode.
///
/// This handles the filesystem case only. SAF (`content://`) files are written
/// centrally by the Kotlin `reEnrichFile` handler, which still holds the
/// original document URI, so callers should skip those here (they are detected
/// and ignored). Best-effort: returns true only when a sidecar was actually
/// written, and never throws.
Future<bool> writeReEnrichSidecarLrc({
  required String audioFilePath,
  required Map<String, dynamic> reEnrichResult,
}) async {
  if (reEnrichResult['write_external_lrc'] != true) return false;

  // SAF documents are handled natively in Kotlin; nothing to do from Dart.
  if (isContentUri(audioFilePath)) return false;

  final lrc = (reEnrichResult['lyrics'] as String?)?.trim() ?? '';
  if (lrc.isEmpty) return false;

  try {
    final lrcPath = _sidecarLrcPath(audioFilePath);
    await File(lrcPath).writeAsString(lrc);
    return true;
  } catch (_) {
    return false;
  }
}

/// Writes a SAF ".lrc" sidecar after a FFmpeg re-enrich write-back succeeds.
///
/// Native FLAC re-enrich handles SAF sidecars in Kotlin after the direct
/// write-back. This helper is for the FFmpeg path, where Dart owns the final
/// `writeTempToSaf` success/failure decision.
Future<bool> writeReEnrichSafSidecarLrc({
  required String safUri,
  required Map<String, dynamic> reEnrichResult,
}) async {
  if (reEnrichResult['write_external_lrc'] != true) return false;
  if (!isContentUri(safUri)) return false;

  final lrc = (reEnrichResult['lyrics'] as String?)?.trim() ?? '';
  if (lrc.isEmpty) return false;

  try {
    return await PlatformBridge.writeSafSidecarLrc(safUri, lrc);
  } catch (_) {
    return false;
  }
}

Future<void> ensureLyricsMetadataForConversion({
  required Map<String, String> metadata,
  required String sourcePath,
  required bool shouldEmbedLyrics,
  required String trackName,
  required String artistName,
  String spotifyId = '',
  int durationMs = 0,
}) async {
  if (!shouldEmbedLyrics || hasEmbeddedLyricsMetadata(metadata)) {
    return;
  }

  String? lyrics;

  // Prefer sidecar .lrc when available to avoid network calls.
  if (!isContentUri(sourcePath)) {
    try {
      final lrcPath = _sidecarLrcPath(sourcePath);
      final lrcFile = File(lrcPath);
      if (await lrcFile.exists()) {
        final content = (await lrcFile.readAsString()).trim();
        if (content.isNotEmpty) {
          lyrics = content;
        }
      }
    } catch (_) {}
  }

  if (lyrics == null || lyrics.isEmpty) {
    try {
      final fetched = await PlatformBridge.getLyricsLRC(
        spotifyId,
        trackName,
        artistName,
        durationMs: durationMs,
      );
      final normalized = fetched.trim();
      if (normalized.isNotEmpty &&
          normalized.toLowerCase() != '[instrumental:true]') {
        lyrics = normalized;
      }
    } catch (_) {}
  }

  if (lyrics == null || lyrics.isEmpty) {
    return;
  }

  metadata['LYRICS'] = lyrics;
  metadata['UNSYNCEDLYRICS'] = lyrics;
}

void mergePlatformMetadataForTagEmbed({
  required Map<String, String> target,
  required Map<String, dynamic> source,
}) {
  void put(String key, dynamic value) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) return;
    target[key] = normalized;
  }

  put('TITLE', source['title']);
  put('ARTIST', source['artist']);
  put('ALBUM', source['album']);
  put('ALBUMARTIST', source['album_artist']);
  put('DATE', source['date']);
  put('ISRC', source['isrc']);
  put('GENRE', source['genre']);
  put('ORGANIZATION', source['label']);
  put('COPYRIGHT', source['copyright']);
  put('COMPOSER', source['composer']);
  put('COMMENT', source['comment']);
  put('LYRICS', source['lyrics']);
  put('UNSYNCEDLYRICS', source['lyrics']);

  final trackNumber = source['track_number'];
  final totalTracks = source['total_tracks'];
  if (trackNumber != null && trackNumber.toString() != '0') {
    put(
      'TRACKNUMBER',
      totalTracks != null &&
              totalTracks.toString().isNotEmpty &&
              totalTracks.toString() != '0'
          ? '${trackNumber.toString()}/${totalTracks.toString()}'
          : trackNumber,
    );
  }

  final discNumber = source['disc_number'];
  final totalDiscs = source['total_discs'];
  if (discNumber != null && discNumber.toString() != '0') {
    put(
      'DISCNUMBER',
      totalDiscs != null &&
              totalDiscs.toString().isNotEmpty &&
              totalDiscs.toString() != '0'
          ? '${discNumber.toString()}/${totalDiscs.toString()}'
          : discNumber,
    );
  }
}
