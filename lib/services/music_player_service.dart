import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart'
    show AudioSession, AudioSessionConfiguration, AudioInterruptionType;
import 'package:audioplayers/audioplayers.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('MusicPlayer');

String _playbackUnknownTitle = 'Unknown title';
String _playbackUnknownArtist = 'Unknown artist';

void updateMusicPlayerStrings({
  required String unknownTitle,
  required String unknownArtist,
}) {
  _playbackUnknownTitle = unknownTitle;
  _playbackUnknownArtist = unknownArtist;
}

final AudioContext _musicAudioContext = AudioContext(
  android: const AudioContextAndroid(
    audioFocus: AndroidAudioFocus.none,
    contentType: AndroidContentType.music,
    usageType: AndroidUsageType.media,
    stayAwake: true,
  ),
);

class PlayableMedia {
  final String id;
  final String source;
  final String title;
  final String artist;
  final String album;
  final String? artUri;
  final Duration? duration;

  const PlayableMedia({
    required this.id,
    required this.source,
    required this.title,
    required this.artist,
    this.album = '',
    this.artUri,
    this.duration,
  });

  bool get isContentUri => source.startsWith('content://');

  MediaItem toMediaItem({String? resolvedSource}) {
    return MediaItem(
      id: id,
      title: title.isEmpty ? _playbackUnknownTitle : title,
      artist: artist.isEmpty ? _playbackUnknownArtist : artist,
      album: album.isEmpty ? null : album,
      duration: duration,
      artUri: (artUri != null && artUri!.isNotEmpty)
          ? Uri.tryParse(artUri!)
          : null,
      extras: {
        'source': source,
        if (resolvedSource != null && resolvedSource.isNotEmpty)
          'resolvedSource': resolvedSource,
      },
    );
  }
}

class MusicPlayerHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer(playerId: 'music-player');
  AudioSession? _audioSession;
  final List<PlayableMedia> _media = [];
  final List<MediaItem> _queueItems = [];
  final Map<String, String> _resolvedPathCache = {};
  final List<String> _resolvedPathOrder = [];
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  int _index = -1;
  bool _initialized = false;

  bool _shuffle = false;
  final Random _random = Random();
  final List<int> _recent = [];
  final List<int> _playHistory = [];

  // True when playback was paused because another app took audio focus.
  bool _pausedByInterruption = false;
  bool _interruptionActive = false;
  bool _userPaused = false;
  bool _switchingTrack = false;
  Duration _lastBroadcastPosition = Duration.zero;
  DateTime? _lastPositionBroadcastAt;
  static const Duration _positionBroadcastInterval = Duration(
    milliseconds: 500,
  );
  static const int _maxResolvedPathCacheEntries = 64;

  MusicPlayerHandler() {
    _init();
  }

  void _init() {
    if (_initialized) return;
    _initialized = true;
    _player.setReleaseMode(ReleaseMode.stop);
    unawaited(_player.setAudioContext(_musicAudioContext));
    unawaited(_configureAudioSession());

    _subscriptions.addAll([
      _player.onPlayerStateChanged.listen((state) {
        if (_switchingTrack &&
            (state == PlayerState.stopped ||
                state == PlayerState.completed ||
                state == PlayerState.disposed)) {
          _log.d('Ignoring transient $state event while switching tracks');
          return;
        }
        if (state == PlayerState.completed && _shouldIgnoreComplete) {
          if (_userPaused || _interruptionActive) {
            _broadcastState(playerState: PlayerState.paused);
          }
          return;
        }
        _broadcastState(playerState: state);
      }),
      _player.onPositionChanged.listen(_broadcastPosition),
      _player.onDurationChanged.listen((duration) {
        final current = mediaItem.value;
        if (current != null && duration > Duration.zero) {
          mediaItem.add(current.copyWith(duration: duration));
        }
      }),
      _player.onPlayerComplete.listen((_) {
        unawaited(_handlePlayerComplete());
      }),
    ]);
  }

  /// Configures the OS audio session and reacts to interruptions (e.g. another
  /// app like PowerAmp taking audio focus, or headphones unplugged) so playback
  /// pauses and the UI/notification reflect the real state instead of staying
  /// stuck on "playing".
  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      _audioSession = session;
      await session.configure(const AudioSessionConfiguration.music());

      _subscriptions.add(
        session.interruptionEventStream.listen((event) {
          if (event.begin) {
            if (event.type == AudioInterruptionType.duck) {
              return;
            }

            // Another app took focus or a transient interruption began.
            _interruptionActive = true;
            _pausedByInterruption =
                _player.state == PlayerState.playing ||
                playbackState.value.playing;
            unawaited(_pauseForFocusLoss());
          } else {
            if (event.type == AudioInterruptionType.duck) {
              return;
            }

            // Focus returned; resume only if we paused due to a transient
            // (duck/pause) interruption.
            _interruptionActive = false;
            if (_pausedByInterruption &&
                event.type == AudioInterruptionType.pause) {
              _pausedByInterruption = false;
              unawaited(play());
            } else {
              _pausedByInterruption = false;
            }
          }
        }),
      );

      _subscriptions.add(
        session.becomingNoisyEventStream.listen((_) {
          // Headphones unplugged / output route lost.
          unawaited(_pauseForFocusLoss());
        }),
      );
    } catch (e) {
      _log.w('Failed to configure audio session: $e');
    }
  }

  bool get _shouldIgnoreComplete =>
      _switchingTrack || _interruptionActive || _userPaused;

  Future<void> _pauseForFocusLoss() async {
    try {
      await _player.pause();
    } catch (e) {
      _log.w('Failed to pause after audio focus loss: $e');
    }
    // Force the UI/notification to reflect the pause even if the engine does
    // not emit a state-change event on focus loss.
    _broadcastState(playerState: PlayerState.paused);
  }

  Future<void> _activateAudioSession() async {
    try {
      final session = _audioSession ?? await AudioSession.instance;
      _audioSession = session;
      final granted = await session.setActive(true);
      if (!granted) {
        _log.w('Audio focus request was not granted');
      }
    } catch (e) {
      _log.w('Failed to activate audio session: $e');
    }
  }

  AudioProcessingState _mapProcessingState(PlayerState state) {
    switch (state) {
      case PlayerState.playing:
      case PlayerState.paused:
        return AudioProcessingState.ready;
      case PlayerState.completed:
        return AudioProcessingState.completed;
      case PlayerState.stopped:
      case PlayerState.disposed:
        return AudioProcessingState.idle;
    }
  }

  void _broadcastState({PlayerState? playerState, bool? loading}) {
    final state = playerState ?? _player.state;
    final playing = state == PlayerState.playing;

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToPrevious,
          MediaAction.skipToNext,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: (loading == true)
            ? AudioProcessingState.loading
            : _mapProcessingState(state),
        playing: playing,
        shuffleMode: _shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  void _broadcastPosition(Duration position, {bool force = false}) {
    final now = DateTime.now();
    final lastAt = _lastPositionBroadcastAt;
    final elapsed = lastAt == null ? null : now.difference(lastAt);
    final moved = (position - _lastBroadcastPosition).abs();
    if (!force &&
        elapsed != null &&
        elapsed < _positionBroadcastInterval &&
        moved < _positionBroadcastInterval) {
      return;
    }
    _lastPositionBroadcastAt = now;
    _lastBroadcastPosition = position;
    playbackState.add(playbackState.value.copyWith(updatePosition: position));
  }

  Future<String?> _resolveSource(PlayableMedia media) async {
    if (!media.isContentUri) return media.source;

    final cached = _resolvedPathCache[media.source];
    if (cached != null) return cached;
    try {
      final tempPath = await PlatformBridge.copyContentUriToTemp(media.source);
      if (tempPath != null && tempPath.isNotEmpty) {
        _resolvedPathCache[media.source] = tempPath;
        _resolvedPathOrder.remove(media.source);
        _resolvedPathOrder.add(media.source);
        while (_resolvedPathOrder.length > _maxResolvedPathCacheEntries) {
          final evicted = _resolvedPathOrder.removeAt(0);
          _resolvedPathCache.remove(evicted);
        }
        return tempPath;
      }
    } catch (e) {
      _log.e('Failed to resolve content URI for playback: $e');
    }
    return null;
  }

  Future<void> setQueueAndPlay(
    List<PlayableMedia> items, {
    int initialIndex = 0,
  }) async {
    if (items.isEmpty) return;
    _media
      ..clear()
      ..addAll(items);
    _queueItems
      ..clear()
      ..addAll(items.map((m) => m.toMediaItem()));
    _recent.clear();
    _playHistory.clear();
    queue.add(List<MediaItem>.unmodifiable(_queueItems));
    await _playIndex(initialIndex.clamp(0, items.length - 1));
  }

  Future<void> enqueue(PlayableMedia item, {bool playNext = false}) async {
    if (_media.isEmpty || _index < 0) {
      await setQueueAndPlay([item]);
      return;
    }
    final insertAt = playNext
        ? (_index + 1).clamp(0, _media.length)
        : _media.length;
    _media.insert(insertAt, item);
    _queueItems.insert(insertAt, item.toMediaItem());

    for (var i = 0; i < _recent.length; i++) {
      if (_recent[i] >= insertAt) _recent[i]++;
    }
    for (var i = 0; i < _playHistory.length; i++) {
      if (_playHistory[i] >= insertAt) _playHistory[i]++;
    }

    queue.add(List<MediaItem>.unmodifiable(_queueItems));
    _broadcastState();
  }

  Future<void> enqueueAll(
    List<PlayableMedia> items, {
    bool playNext = false,
  }) async {
    if (items.isEmpty) return;
    if (_media.isEmpty || _index < 0) {
      await setQueueAndPlay(items);
      return;
    }
    var at = playNext ? (_index + 1).clamp(0, _media.length) : _media.length;
    for (final item in items) {
      _media.insert(at, item);
      _queueItems.insert(at, item.toMediaItem());
      for (var i = 0; i < _recent.length; i++) {
        if (_recent[i] >= at) _recent[i]++;
      }
      for (var i = 0; i < _playHistory.length; i++) {
        if (_playHistory[i] >= at) _playHistory[i]++;
      }
      at++;
    }
    queue.add(List<MediaItem>.unmodifiable(_queueItems));
    _broadcastState();
  }

  void moveQueueItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _media.length ||
        newIndex < 0 ||
        newIndex >= _media.length ||
        oldIndex == newIndex) {
      return;
    }
    final media = _media.removeAt(oldIndex);
    final qi = _queueItems.removeAt(oldIndex);
    _media.insert(newIndex, media);
    _queueItems.insert(newIndex, qi);

    if (_index == oldIndex) {
      _index = newIndex;
    } else {
      if (oldIndex < _index && newIndex >= _index) {
        _index--;
      } else if (oldIndex > _index && newIndex <= _index) {
        _index++;
      }
    }

    _recent.clear();
    _playHistory.clear();

    queue.add(List<MediaItem>.unmodifiable(_queueItems));
    _broadcastState();
  }

  Future<void> _playIndex(int index, {bool recordHistory = true}) async {
    if (index < 0 || index >= _media.length) return;
    _index = index;
    _pausedByInterruption = false;
    _interruptionActive = false;
    _userPaused = false;

    if (recordHistory) {
      _playHistory.add(index);
      if (_playHistory.length > 200) _playHistory.removeAt(0);
      _recent.add(index);
      final maxRecent = ((_media.length - 1) * 0.6).floor().clamp(
        1,
        _media.length > 1 ? _media.length - 1 : 1,
      );
      while (_recent.length > maxRecent) {
        _recent.removeAt(0);
      }
    }

    final media = _media[index];
    mediaItem.add(media.toMediaItem());
    _lastBroadcastPosition = Duration.zero;
    _lastPositionBroadcastAt = null;
    // Claim the playing state up front (while the app is still in the
    // foreground window) so audio_service can start its foreground service
    // before the async source resolve below.
    _broadcastState(playerState: PlayerState.playing, loading: true);

    final resolved = await _resolveSource(media);
    if (resolved == null) {
      _log.e('No playable source for ${media.title}');
      _broadcastState(playerState: PlayerState.stopped);
      return;
    }

    try {
      await musicPlayerExclusiveAudioHook?.call();
    } catch (_) {}

    _switchingTrack = true;
    try {
      await _player.setAudioContext(_musicAudioContext);
      await _activateAudioSession();
      await _player.stop();
      await _player.play(DeviceFileSource(resolved));
      mediaItem.add(media.toMediaItem(resolvedSource: resolved));
      _broadcastPosition(Duration.zero, force: true);
      _broadcastState(playerState: PlayerState.playing);
      _log.i('Playing: ${media.title}');
      // Some files do not emit onDurationChanged reliably (stuck at 0:00);
      // poll the engine for the real duration as a fallback.
      unawaited(_ensureDurationKnown(index));
    } catch (e) {
      _log.e('Playback failed for ${media.title}: $e');
      _broadcastState(playerState: PlayerState.stopped);
    } finally {
      _switchingTrack = false;
    }
  }

  /// Resolves the real track duration when the initial metadata had none and
  /// the duration-changed event did not fire, so the seek bar and total time
  /// do not get stuck at 0:00.
  Future<void> _ensureDurationKnown(int index) async {
    for (var attempt = 0; attempt < 15; attempt++) {
      if (_index != index) return; // track changed; stop polling
      final current = mediaItem.value;
      final existing = current?.duration;
      if (existing != null && existing > Duration.zero) return;

      try {
        final d = await _player.getDuration();
        if (_index != index) return;
        if (d != null && d > Duration.zero) {
          final item = mediaItem.value;
          if (item != null) {
            mediaItem.add(item.copyWith(duration: d));
          }
          return;
        }
      } catch (_) {
        // ignore and retry
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  int _pickNextShuffle() {
    if (_media.length <= 1) return _index;
    final pool = <int>[];
    for (var i = 0; i < _media.length; i++) {
      if (i != _index && !_recent.contains(i)) pool.add(i);
    }
    if (pool.isEmpty) {
      for (var i = 0; i < _media.length; i++) {
        if (i != _index) pool.add(i);
      }
    }
    return pool[_random.nextInt(pool.length)];
  }

  Future<void> _onComplete() async {
    if (_shuffle) {
      if (_media.length > 1) {
        await _playIndex(_pickNextShuffle());
      } else {
        _broadcastState(playerState: PlayerState.completed);
      }
      return;
    }
    if (_index >= 0 && _index < _media.length - 1) {
      await _playIndex(_index + 1);
    } else {
      _broadcastState(playerState: PlayerState.completed);
    }
  }

  Future<void> _handlePlayerComplete() async {
    if (_shouldIgnoreComplete) {
      _log.d('Ignoring non-terminal player complete event');
      if (_userPaused || _interruptionActive) {
        _broadcastState(playerState: PlayerState.paused);
      }
      return;
    }

    await _onComplete();
  }

  @override
  Future<void> play() async {
    _pausedByInterruption = false;
    _interruptionActive = false;
    _userPaused = false;
    if ((_player.state == PlayerState.stopped ||
            _player.state == PlayerState.completed) &&
        _index >= 0 &&
        _index < _media.length) {
      await _playIndex(_index, recordHistory: false);
      return;
    }
    await _activateAudioSession();
    await _player.resume();
    _broadcastState(playerState: PlayerState.playing);
  }

  @override
  Future<void> pause() async {
    _userPaused = true;
    _pausedByInterruption = false;
    await _player.pause();
    _broadcastState(playerState: PlayerState.paused);
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _broadcastPosition(position, force: true);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffle = shuffleMode == AudioServiceShuffleMode.all;
    _broadcastState();
  }

  @override
  Future<void> stop() async {
    _userPaused = true;
    await _player.stop();
    _index = -1;
    _pausedByInterruption = false;
    _interruptionActive = false;
    _userPaused = false;
    _recent.clear();
    _playHistory.clear();
    _broadcastState(playerState: PlayerState.stopped);
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (_shuffle) {
      if (_media.length > 1) await _playIndex(_pickNextShuffle());
      return;
    }
    if (_index < _media.length - 1) await _playIndex(_index + 1);
  }

  @override
  Future<void> skipToPrevious() async {
    if (playbackState.value.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      _broadcastPosition(Duration.zero, force: true);
      return;
    }
    if (_shuffle) {
      if (_playHistory.length >= 2) {
        _playHistory.removeLast();
        final prev = _playHistory.last;
        await _playIndex(prev, recordHistory: false);
      } else {
        await _player.seek(Duration.zero);
        _broadcastPosition(Duration.zero, force: true);
      }
      return;
    }
    if (_index > 0) await _playIndex(_index - 1);
  }

  @override
  Future<void> skipToQueueItem(int index) => _playIndex(index);

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    if (parentMediaId == AudioService.browsableRootId ||
        parentMediaId == AudioService.recentRootId) {
      return List<MediaItem>.unmodifiable(_queueItems);
    }
    return const [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final index = _media.indexWhere((m) => m.id == mediaId);
    if (index < 0) return null;
    return _queueItems[index];
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final index = _media.indexWhere((m) => m.id == mediaId);
    if (index >= 0) await _playIndex(index);
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) =>
      playFromMediaId(mediaItem.id);

  /// Called when a file is deleted from disk. Removes it from the queue and, if
  /// it is the track currently playing, stops or advances so a deleted song can
  /// no longer be played.
  Future<void> onSourceDeleted(String source) async {
    final target = source.trim();
    if (target.isEmpty || _media.isEmpty) return;

    _resolvedPathCache.remove(target);
    _resolvedPathOrder.remove(target);

    final wasCurrent =
        _index >= 0 &&
        _index < _media.length &&
        _media[_index].source == target;

    var removedBeforeCurrent = 0;
    final kept = <PlayableMedia>[];
    for (var i = 0; i < _media.length; i++) {
      if (_media[i].source == target) {
        if (i < _index) removedBeforeCurrent++;
        continue;
      }
      kept.add(_media[i]);
    }

    if (kept.length == _media.length) return; // nothing matched

    _media
      ..clear()
      ..addAll(kept);
    _queueItems
      ..clear()
      ..addAll(kept.map((m) => m.toMediaItem()));
    _recent.clear();
    _playHistory.clear();
    queue.add(List<MediaItem>.unmodifiable(_queueItems));

    if (_media.isEmpty) {
      await stop();
      return;
    }

    if (wasCurrent) {
      final nextIndex = _index.clamp(0, _media.length - 1);
      await _playIndex(nextIndex);
    } else {
      _index = (_index - removedBeforeCurrent).clamp(0, _media.length - 1);
      _broadcastState();
    }
  }

  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _player.dispose();
  }
}

MusicPlayerHandler? _handler;
Future<MusicPlayerHandler>? _initFuture;
final StreamController<MusicPlayerHandler> _handlerReadyController =
    StreamController<MusicPlayerHandler>.broadcast();

MusicPlayerHandler? get musicPlayerHandler => _handler;

Future<void> Function()? musicPlayerExclusiveAudioHook;

Future<MusicPlayerHandler> initMusicPlayer() async {
  if (_handler != null) return _handler!;
  final existingFuture = _initFuture;
  if (existingFuture != null) return existingFuture;

  final future = _doInitMusicPlayer();
  _initFuture = future;
  return future;
}

Future<MusicPlayerHandler> _doInitMusicPlayer() async {
  try {
    final handler = await AudioService.init(
      builder: () => MusicPlayerHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.zarz.spotiflac.playback',
        androidNotificationChannelName: 'Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    _handler = handler;
    _handlerReadyController.add(handler);
    return handler;
  } catch (_) {
    _initFuture = null;
    rethrow;
  }
}

Stream<MediaItem?> musicPlayerMediaItemEvents() async* {
  final existing = _handler;
  if (existing != null) {
    yield existing.mediaItem.value;
    yield* existing.mediaItem;
    return;
  }
  yield null;
  await for (final handler in _handlerReadyController.stream) {
    yield handler.mediaItem.value;
    yield* handler.mediaItem;
    return;
  }
}

Stream<PlaybackState> musicPlayerPlaybackStateEvents() async* {
  final existing = _handler;
  if (existing != null) {
    yield existing.playbackState.value;
    yield* existing.playbackState;
    return;
  }
  await for (final handler in _handlerReadyController.stream) {
    yield handler.playbackState.value;
    yield* handler.playbackState;
    return;
  }
}

Stream<List<MediaItem>> musicPlayerQueueEvents() async* {
  final existing = _handler;
  if (existing != null) {
    yield existing.queue.value;
    yield* existing.queue;
    return;
  }
  yield const [];
  await for (final handler in _handlerReadyController.stream) {
    yield handler.queue.value;
    yield* handler.queue;
    return;
  }
}
