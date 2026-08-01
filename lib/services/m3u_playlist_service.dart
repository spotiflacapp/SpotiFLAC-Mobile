import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('M3uPlaylist');

class M3uExportEntry {
  final Track track;
  final String path;

  const M3uExportEntry({required this.track, required this.path});
}

class M3uPlaylistService {
  /// Parses M3U/M3U8 content into tracks for the import pipeline. EXTINF
  /// display text is split on the first " - " into artist and title; path
  /// lines without EXTINF fall back to the file name stem.
  static List<Track> parseM3u(String content) {
    final tracks = <Track>[];
    final lines = content.split(RegExp(r'\r\n|\r|\n'));
    final baseId = DateTime.now().millisecondsSinceEpoch;

    int? pendingDuration;
    String? pendingDisplay;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        final body = line.substring('#EXTINF:'.length);
        final commaIdx = body.indexOf(',');
        if (commaIdx >= 0) {
          final durationRaw = body.substring(0, commaIdx).split(' ').first;
          pendingDuration = double.tryParse(durationRaw)?.round();
          pendingDisplay = body.substring(commaIdx + 1).trim();
        }
        continue;
      }
      if (line.startsWith('#')) continue;

      var display = pendingDisplay;
      if (display == null || display.isEmpty) {
        display = p.basenameWithoutExtension(line).trim();
      }

      String artist = '';
      String title = display;
      final splitIdx = display.indexOf(' - ');
      if (splitIdx > 0) {
        artist = display.substring(0, splitIdx).trim();
        title = display.substring(splitIdx + 3).trim();
      }

      if (title.isNotEmpty) {
        final duration = pendingDuration ?? 0;
        tracks.add(
          Track(
            id: 'm3u_${baseId}_${tracks.length}',
            name: title,
            artistName: artist.isEmpty ? 'Unknown Artist' : artist,
            albumName: 'Unknown Album',
            duration: duration > 0 ? duration : 0,
            coverUrl: null,
          ),
        );
      }
      pendingDuration = null;
      pendingDisplay = null;
    }

    _log.i('Parsed ${tracks.length} tracks from M3U');
    return tracks;
  }

  /// Builds `#EXTM3U` content with one EXTINF line per entry.
  static String buildM3u8Content(List<M3uExportEntry> entries) {
    final buffer = StringBuffer('#EXTM3U\n');
    for (final entry in entries) {
      final track = entry.track;
      final duration = track.duration > 0 ? track.duration : -1;
      final artist = track.artistName.trim();
      final display = artist.isEmpty ? track.name : '$artist - ${track.name}';
      buffer
        ..write('#EXTINF:')
        ..write(duration)
        ..write(',')
        ..writeln(display)
        ..writeln(entry.path);
    }
    return buffer.toString();
  }

  /// Converts a resolved library file path into an M3U entry path. Plain
  /// paths pass through unchanged; SAF document URIs become paths relative
  /// to their tree root (so the .m3u8 resolves when placed in the download
  /// folder). Returns null when a content URI carries no usable path.
  static String? exportPathFor(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('content://')) return trimmed;

    try {
      // Uri.pathSegments already percent-decodes each segment once.
      final segments = Uri.parse(trimmed).pathSegments;
      final docIdx = segments.indexOf('document');
      if (docIdx < 0 || docIdx + 1 >= segments.length) return null;
      final docPath = segments[docIdx + 1];

      final treeIdx = segments.indexOf('tree');
      if (treeIdx >= 0 && treeIdx + 1 < segments.length) {
        final treeId = segments[treeIdx + 1];
        if (treeId.isNotEmpty && docPath.startsWith(treeId)) {
          var relative = docPath.substring(treeId.length);
          if (relative.startsWith('/')) relative = relative.substring(1);
          if (relative.isNotEmpty) return relative;
        }
      }

      // No tree context: strip the storage prefix
      // ("primary:Music/A/b.flac" -> "Music/A/b.flac").
      final colonIdx = docPath.indexOf(':');
      if (colonIdx >= 0 && colonIdx + 1 < docPath.length) {
        return docPath.substring(colonIdx + 1);
      }
      return docPath.isEmpty ? null : docPath;
    } catch (_) {
      return null;
    }
  }

  /// Writes the playlist to a shareable temp file named after the playlist.
  static Future<File> writeExportFile(
    String playlistName,
    String content,
  ) async {
    final dir = await getTemporaryDirectory();
    final safeName = playlistName
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    final file = File(
      p.join(dir.path, '${safeName.isEmpty ? 'playlist' : safeName}.m3u8'),
    );
    await file.writeAsString(content);
    return file;
  }
}
