import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/history_database.dart';
import 'package:spotiflac_android/services/music_player_service.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('PlaybackProvider');

class PlaybackState {
  const PlaybackState();
}

class PlaybackController extends Notifier<PlaybackState> {
  @override
  PlaybackState build() => const PlaybackState();

  Future<bool> _useInternalPlayer() async {
    final mode = ref.read(settingsProvider).playerMode;
    if (mode != 'internal') return false;
    return await ref.read(musicPlayerControllerProvider).ensureInitialized() !=
        null;
  }

  String? _normalizeArtUri(String cover) {
    final value = cover.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http') ||
        value.startsWith('content://') ||
        value.startsWith('file://')) {
      return value;
    }
    return Uri.file(value).toString();
  }

  Future<void> playLocalPath({
    required String path,
    required String title,
    required String artist,
    String album = '',
    String coverUrl = '',
    Track? track,
  }) async {
    if (isCueVirtualPath(path)) {
      throw Exception(cueVirtualTrackRequiresSplitMessage);
    }

    if (await _useInternalPlayer()) {
      _log.d('Playing "$title" in the internal player: $path');
      await ref
          .read(musicPlayerControllerProvider)
          .playSingle(
            PlayableMedia(
              id: path,
              source: path,
              title: title,
              artist: artist,
              album: album,
              artUri: _normalizeArtUri(coverUrl),
              duration: (track != null && track.duration > 0)
                  ? Duration(seconds: track.duration)
                  : null,
            ),
          );
      return;
    }

    _log.d('Opening external player for "$title" by $artist: $path');
    await openFile(path);
  }

  /// Plays a local-library album/list starting at [startItem], queuing the rest
  /// so playback continues to the next track automatically. Honors player mode.
  Future<void> playLocalLibraryQueue(
    List<LocalLibraryItem> items, {
    required LocalLibraryItem startItem,
  }) async {
    final playable = items
        .where(
          (i) => i.filePath.trim().isNotEmpty && !isCueVirtualPath(i.filePath),
        )
        .toList();
    if (playable.isEmpty) return;
    var startIndex = playable.indexWhere((i) => i.id == startItem.id);
    if (startIndex < 0) startIndex = 0;

    if (await _useInternalPlayer()) {
      await ref
          .read(musicPlayerControllerProvider)
          .playLocal(playable, initialIndex: startIndex);
    } else {
      await openFile(playable[startIndex].filePath);
    }
  }

  /// Plays a downloaded-history album/list starting at [startItem], queuing the
  /// rest. Honors player mode.
  Future<void> playHistoryQueue(
    List<DownloadHistoryItem> items, {
    required DownloadHistoryItem startItem,
  }) async {
    final playable = items
        .where(
          (i) => i.filePath.trim().isNotEmpty && !isCueVirtualPath(i.filePath),
        )
        .toList();
    if (playable.isEmpty) return;
    var startIndex = playable.indexWhere((i) => i.id == startItem.id);
    if (startIndex < 0) startIndex = 0;

    if (await _useInternalPlayer()) {
      await ref
          .read(musicPlayerControllerProvider)
          .playHistory(playable, initialIndex: startIndex);
    } else {
      await openFile(playable[startIndex].filePath);
    }
  }

  /// Plays a prebuilt media queue starting at [startIndex]. Honors player mode
  /// ([externalPath] is opened externally when the built-in player is off).
  Future<void> playMediaQueue(
    Iterable<PlayableMedia> queue, {
    required int startIndex,
    required String externalPath,
  }) async {
    if (await _useInternalPlayer()) {
      final items = queue.toList(growable: false);
      if (items.isEmpty) return;
      final i = startIndex.clamp(0, items.length - 1);
      await ref
          .read(musicPlayerControllerProvider)
          .playAll(items, initialIndex: i);
    } else {
      await openFile(externalPath);
    }
  }

  Future<void> playTrackList(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;

    final orderedTracks = _orderedTracksFromStartIndex(tracks, startIndex);
    final resolvedPaths = await _resolveTrackPaths(orderedTracks);

    if (await _useInternalPlayer()) {
      final queue = <PlayableMedia>[];
      var skippedCueVirtualTrack = false;
      for (var index = 0; index < orderedTracks.length; index++) {
        final track = orderedTracks[index];
        final resolvedPath = resolvedPaths[index];
        if (resolvedPath == null) continue;
        if (isCueVirtualPath(resolvedPath)) {
          skippedCueVirtualTrack = true;
          continue;
        }
        queue.add(
          PlayableMedia(
            id: resolvedPath,
            source: resolvedPath,
            title: track.name,
            artist: track.artistName,
            album: track.albumName,
            artUri: _normalizeArtUri(track.coverUrl ?? ''),
            duration: track.duration > 0
                ? Duration(seconds: track.duration)
                : null,
          ),
        );
      }

      if (queue.isNotEmpty) {
        _log.d('Playing ${queue.length} tracks in the internal player');
        await ref.read(musicPlayerControllerProvider).playAll(queue);
        return;
      }
      if (skippedCueVirtualTrack) {
        throw Exception(cueVirtualTrackRequiresSplitMessage);
      }
      throw Exception(
        'No local audio file is available to play. Download the track first.',
      );
    }

    var skippedCueVirtualTrack = false;
    for (var index = 0; index < orderedTracks.length; index++) {
      final track = orderedTracks[index];
      final resolvedPath = resolvedPaths[index];
      if (resolvedPath == null) {
        continue;
      }
      if (isCueVirtualPath(resolvedPath)) {
        skippedCueVirtualTrack = true;
        continue;
      }

      _log.d(
        'Opening first available external track for list playback: '
        '"${track.name}" by ${track.artistName} -> $resolvedPath',
      );
      await openFile(resolvedPath);
      return;
    }

    if (skippedCueVirtualTrack) {
      throw Exception(cueVirtualTrackRequiresSplitMessage);
    }

    throw Exception(
      'No local audio file is available to open. Download the track first.',
    );
  }

  /// Public wrapper so non-playback features (e.g. M3U export) reuse the
  /// same library+history file resolution.
  Future<List<String?>> resolveTrackFilePaths(List<Track> tracks) =>
      _resolveTrackPaths(tracks);

  List<Track> _orderedTracksFromStartIndex(List<Track> tracks, int startIndex) {
    final safeStart = startIndex.clamp(0, tracks.length - 1);
    if (safeStart == 0) {
      return List<Track>.from(tracks, growable: false);
    }

    return <Track>[
      ...tracks.sublist(safeStart),
      ...tracks.sublist(0, safeStart),
    ];
  }

  Future<List<String?>> _resolveTrackPaths(List<Track> tracks) async {
    if (tracks.isEmpty) return const [];
    final localFuture = LibraryDatabase.instance.findExistingBatch([
      for (final track in tracks)
        LocalLibraryBatchLookupRequest(
          id: (track.source ?? '').toLowerCase() == 'local' ? track.id : null,
          isrc: track.isrc,
          trackName: track.name,
          artistName: track.artistName,
        ),
    ]);
    final historyFuture = HistoryDatabase.instance.findExistingTracks([
      for (final track in tracks)
        HistoryLookupRequest(
          spotifyId: track.id,
          isrc: track.isrc,
          trackName: track.name,
          artistName: track.artistName,
        ),
    ]);
    final localMatches = await localFuture;
    final historyMatches = await historyFuture;

    final results = List<String?>.filled(tracks.length, null);
    final existsChecks = <String, Future<bool>>{};
    final invalidHistoryIds = <String>{};
    var next = 0;
    final workerCount = tracks.length < 8 ? tracks.length : 8;

    Future<bool> pathExists(String path) =>
        existsChecks.putIfAbsent(path, () => fileExists(path));

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= tracks.length) return;
        final localPath = localMatches[index]?['filePath']?.toString() ?? '';
        if (localPath.isNotEmpty && await pathExists(localPath)) {
          results[index] = localPath;
          continue;
        }

        final historyMatch = historyMatches[index];
        final historyPath = historyMatch?['filePath']?.toString() ?? '';
        if (historyPath.isNotEmpty && await pathExists(historyPath)) {
          results[index] = historyPath;
          continue;
        }
        final historyId = historyMatch?['id']?.toString() ?? '';
        if (historyId.isNotEmpty) invalidHistoryIds.add(historyId);
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
    final historyNotifier = ref.read(downloadHistoryProvider.notifier);
    for (final id in invalidHistoryIds) {
      historyNotifier.removeFromHistory(id);
    }
    return results;
  }
}

final playbackProvider = NotifierProvider<PlaybackController, PlaybackState>(
  PlaybackController.new,
);
