import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/music_player_service.dart';

final currentMediaItemProvider = StreamProvider<MediaItem?>((ref) {
  return musicPlayerMediaItemEvents();
});

final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  return musicPlayerPlaybackStateEvents();
});

final playQueueProvider = StreamProvider<List<MediaItem>>((ref) {
  return musicPlayerQueueEvents();
});

class MusicPlayerController {
  const MusicPlayerController();

  MusicPlayerHandler? get _handler => musicPlayerHandler;

  bool get isAvailable => _handler != null;

  Future<MusicPlayerHandler?> ensureInitialized() async {
    try {
      return await initMusicPlayer();
    } catch (_) {
      return null;
    }
  }

  Future<void> playAll(
    List<PlayableMedia> items, {
    int initialIndex = 0,
  }) async {
    final handler = await ensureInitialized();
    await handler?.setQueueAndPlay(items, initialIndex: initialIndex);
  }

  Future<void> playSingle(PlayableMedia item) => playAll([item]);

  Future<void> playHistory(
    List<DownloadHistoryItem> items, {
    int initialIndex = 0,
  }) async {
    final media = items
        .where((i) => i.filePath.trim().isNotEmpty)
        .map(playableFromHistory)
        .toList();
    if (media.isEmpty) return;
    await playAll(media, initialIndex: initialIndex.clamp(0, media.length - 1));
  }

  Future<void> playLocal(
    List<LocalLibraryItem> items, {
    int initialIndex = 0,
  }) async {
    final media = items
        .where((i) => i.filePath.trim().isNotEmpty)
        .map(playableFromLocal)
        .toList();
    if (media.isEmpty) return;
    await playAll(media, initialIndex: initialIndex.clamp(0, media.length - 1));
  }

  Future<void> play() async => _handler?.play();
  Future<void> pause() async => _handler?.pause();
  Future<void> stop() async => _handler?.stop();
  Future<void> seek(Duration position) async => _handler?.seek(position);
  Future<void> next() async => _handler?.skipToNext();
  Future<void> previous() async => _handler?.skipToPrevious();

  Future<void> togglePlayPause(bool isPlaying) async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> setShuffle(bool enabled) async {
    await _handler?.setShuffleMode(
      enabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
  }

  Future<void> playNext(PlayableMedia item) async =>
      (await ensureInitialized())?.enqueue(item, playNext: true);

  Future<void> addToQueue(PlayableMedia item) async =>
      (await ensureInitialized())?.enqueue(item);

  Future<void> playNextHistory(DownloadHistoryItem item) async =>
      playNext(playableFromHistory(item));

  Future<void> addToQueueHistory(DownloadHistoryItem item) async =>
      addToQueue(playableFromHistory(item));

  Future<void> playNextLocal(LocalLibraryItem item) async =>
      playNext(playableFromLocal(item));

  Future<void> addToQueueLocal(LocalLibraryItem item) async =>
      addToQueue(playableFromLocal(item));

  Future<void> jumpTo(int index) async => _handler?.skipToQueueItem(index);

  void moveQueueItem(int oldIndex, int newIndex) {
    _handler?.moveQueueItem(oldIndex, newIndex);
  }
}

final musicPlayerControllerProvider = Provider<MusicPlayerController>(
  (ref) => const MusicPlayerController(),
);

PlayableMedia playableFromHistory(DownloadHistoryItem item) {
  return PlayableMedia(
    id: item.id,
    source: item.filePath,
    title: item.trackName,
    artist: item.artistName,
    album: item.albumName,
    artUri: (item.coverUrl != null && item.coverUrl!.trim().isNotEmpty)
        ? item.coverUrl
        : null,
    duration: (item.duration != null && item.duration! > 0)
        ? Duration(seconds: item.duration!)
        : null,
  );
}

PlayableMedia playableFromLocal(LocalLibraryItem item) {
  String? art;
  final cover = item.coverPath;
  if (cover != null && cover.trim().isNotEmpty) {
    art = cover.startsWith('http') || cover.startsWith('content://')
        ? cover
        : Uri.file(cover).toString();
  }
  return PlayableMedia(
    id: item.id,
    source: item.filePath,
    title: item.trackName,
    artist: item.artistName,
    album: item.albumName,
    artUri: art,
    duration: (item.duration != null && item.duration! > 0)
        ? Duration(seconds: item.duration!)
        : null,
  );
}
