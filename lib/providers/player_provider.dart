import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:spotiflac_android/models/player_state.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('PlayerProvider');

class PlayerController extends Notifier<PlayerState> {
  late ja.AudioPlayer _player;

  @override
  PlayerState build() {
    _player = ja.AudioPlayer();
    final sub1 = _player.playerStateStream.listen(_onPlayerState);
    final sub2 = _player.positionStream.listen(_onPosition);
    final sub3 = _player.durationStream.listen(_onDuration);
    ref.onDispose(() {
      sub1.cancel();
      sub2.cancel();
      sub3.cancel();
      _player.dispose();
    });
    return const PlayerState();
  }

  void _onPlayerState(ja.PlayerState ps) {
    final isLoading = ps.processingState == ja.ProcessingState.loading ||
        ps.processingState == ja.ProcessingState.buffering;
    state = state.copyWith(isPlaying: ps.playing, isLoading: isLoading);
    if (ps.processingState == ja.ProcessingState.completed) {
      _handleTrackCompleted();
    }
  }

  void _onPosition(Duration pos) {
    state = state.copyWith(position: pos);
  }

  void _onDuration(Duration? dur) {
    if (dur != null) state = state.copyWith(duration: dur);
  }

  void _handleTrackCompleted() {
    switch (state.loopMode) {
      case PlayerLoopMode.one:
        _player.seek(Duration.zero);
        _player.play();
      case PlayerLoopMode.all:
        final nextIndex =
            state.hasNext ? state.currentIndex + 1 : 0;
        _loadQueueIndex(nextIndex);
      case PlayerLoopMode.off:
        if (state.hasNext) _loadQueueIndex(state.currentIndex + 1);
    }
  }

  Future<void> playFromPath({
    required String filePath,
    required String title,
    String artist = '',
    String album = '',
    String? coverUrl,
    Track? track,
  }) async {
    final entry = QueueTrack(
      filePath: filePath,
      title: title,
      artist: artist,
      album: album,
      coverUrl: coverUrl,
      track: track,
    );
    state = state.copyWith(
      queue: [entry],
      currentIndex: 0,
      position: Duration.zero,
      duration: Duration.zero,
      isLoading: true,
      clearError: true,
    );
    await _loadFromPath(filePath);
  }

  Future<void> playTrackList(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    final safeStart = startIndex.clamp(0, tracks.length - 1);
    final entries = tracks
        .map(
          (t) => QueueTrack(
            filePath: '',
            title: t.name,
            artist: t.artistName,
            album: t.albumName,
            coverUrl: t.coverUrl,
            track: t,
          ),
        )
        .toList(growable: false);

    state = state.copyWith(
      queue: entries,
      currentIndex: safeStart,
      position: Duration.zero,
      duration: Duration.zero,
      isLoading: true,
      clearError: true,
    );
    await _loadTrack(tracks[safeStart], safeStart);
  }

  Future<void> _loadQueueIndex(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    final entry = state.queue[index];
    state = state.copyWith(
      currentIndex: index,
      position: Duration.zero,
      duration: Duration.zero,
      isLoading: true,
    );
    if (entry.filePath.isNotEmpty) {
      await _loadFromPath(entry.filePath);
    } else if (entry.track != null) {
      await _loadTrack(entry.track!, index);
    }
  }

  Future<void> _loadTrack(Track track, int queueIndex) async {
    final path = await _resolveTrackPath(track);
    if (path == null) {
      state = state.copyWith(
        isLoading: false,
        error: 'Track not downloaded. Download it first.',
      );
      return;
    }
    // Cache resolved path back into queue entry
    if (queueIndex < state.queue.length) {
      final newQueue = List<QueueTrack>.from(state.queue);
      newQueue[queueIndex] = newQueue[queueIndex].copyWith(filePath: path);
      state = state.copyWith(queue: newQueue);
    }
    await _loadFromPath(path);
  }

  Future<void> _loadFromPath(String filePath) async {
    try {
      state = state.copyWith(isLoading: true, clearError: true);
      final uri = filePath.startsWith('content://')
          ? Uri.parse(filePath)
          : Uri.file(filePath);
      await _player.setAudioSource(ja.AudioSource.uri(uri));
      await _player.play();
    } catch (e) {
      _log.e('Playback failed for path "$filePath": $e', e);
      state = state.copyWith(isLoading: false, error: 'Playback failed: $e');
    }
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    state = state.copyWith(position: position);
  }

  Future<void> skipToNext() => _loadQueueIndex(
    state.hasNext
        ? state.currentIndex + 1
        : (state.loopMode == PlayerLoopMode.all ? 0 : state.currentIndex),
  );

  Future<void> skipToPrevious() async {
    if (state.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (state.hasPrevious) await _loadQueueIndex(state.currentIndex - 1);
  }

  void cycleLoopMode() {
    state = state.copyWith(
      loopMode: switch (state.loopMode) {
        PlayerLoopMode.off => PlayerLoopMode.all,
        PlayerLoopMode.all => PlayerLoopMode.one,
        PlayerLoopMode.one => PlayerLoopMode.off,
      },
    );
  }

  Future<void> stop() async {
    await _player.stop();
    state = const PlayerState();
  }

  Future<String?> _resolveTrackPath(Track track) async {
    final localNotifier = ref.read(localLibraryProvider.notifier);

    if ((track.source ?? '').toLowerCase() == 'local') {
      final byId = await localNotifier.getById(track.id);
      if (byId != null && await fileExists(byId.filePath)) return byId.filePath;
    }

    final existing = await localNotifier.findExistingAsync(
      isrc: track.isrc?.trim(),
      trackName: track.name,
      artistName: track.artistName,
    );
    if (existing != null && await fileExists(existing.filePath)) {
      return existing.filePath;
    }

    final historyState = ref.read(downloadHistoryProvider);
    final historyNotifier = ref.read(downloadHistoryProvider.notifier);

    for (final candidateId in _idCandidates(track.id)) {
      final item = historyState.getBySpotifyId(candidateId) ??
          await historyNotifier.getBySpotifyIdAsync(candidateId);
      if (item != null && await fileExists(item.filePath)) return item.filePath;
    }

    final isrc = track.isrc?.trim();
    if (isrc != null && isrc.isNotEmpty) {
      final item = historyState.getByIsrc(isrc) ??
          await historyNotifier.getByIsrcAsync(isrc);
      if (item != null && await fileExists(item.filePath)) return item.filePath;
    }

    final byMeta = await historyNotifier.findByTrackAndArtistAsync(
      track.name,
      track.artistName,
    );
    if (byMeta != null && await fileExists(byMeta.filePath)) {
      return byMeta.filePath;
    }

    return null;
  }

  List<String> _idCandidates(String rawId) {
    final trimmed = rawId.trim();
    if (trimmed.isEmpty) return const [];
    final candidates = <String>{trimmed};
    if (trimmed.toLowerCase().startsWith('spotify:track:')) {
      candidates.add(trimmed.split(':').last.trim());
    } else if (!trimmed.contains(':')) {
      candidates.add('spotify:track:$trimmed');
    }
    return candidates.toList(growable: false);
  }
}

final playerProvider = NotifierProvider<PlayerController, PlayerState>(
  PlayerController.new,
);
