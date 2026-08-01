import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart'
    show AudioSession, AudioSessionConfiguration, AudioInterruptionType;
import 'package:audioplayers/audioplayers.dart';
import 'package:spotiflac_android/services/app_state_database.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/int_utils.dart';
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

bool _playbackNormalizationEnabled = false;
MusicPlayerHandler? _activeMusicPlayerHandler;

/// Enables/disables ReplayGain volume normalization and re-applies it to the
/// track currently playing.
void setPlaybackNormalizationEnabled(bool enabled) {
  if (_playbackNormalizationEnabled == enabled) return;
  _playbackNormalizationEnabled = enabled;
  _activeMusicPlayerHandler?.reapplyNormalization();
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
  final int? bitDepth;
  final int? sampleRate;
  final int? bitrate;
  final String? format;

  const PlayableMedia({
    required this.id,
    required this.source,
    required this.title,
    required this.artist,
    this.album = '',
    this.artUri,
    this.duration,
    this.bitDepth,
    this.sampleRate,
    this.bitrate,
    this.format,
  });

  bool get isContentUri => source.startsWith('content://');

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'title': title,
    'artist': artist,
    'album': album,
    if (artUri != null && artUri!.isNotEmpty) 'artUri': artUri,
    if (duration != null) 'durationMs': duration!.inMilliseconds,
    if (bitDepth != null && bitDepth! > 0) 'bitDepth': bitDepth,
    if (sampleRate != null && sampleRate! > 0) 'sampleRate': sampleRate,
    if (bitrate != null && bitrate! > 0) 'bitrate': bitrate,
    if (format != null && format!.trim().isNotEmpty) 'format': format,
  };

  static PlayableMedia? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final source = json['source'] as String?;
    if (id == null || id.isEmpty || source == null || source.isEmpty) {
      return null;
    }
    final durationMs = (json['durationMs'] as num?)?.toInt();
    return PlayableMedia(
      id: id,
      source: source,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      artUri: json['artUri'] as String?,
      duration: (durationMs != null && durationMs > 0)
          ? Duration(milliseconds: durationMs)
          : null,
      bitDepth: readPositiveInt(json['bitDepth']),
      sampleRate: readPositiveInt(json['sampleRate']),
      bitrate: readPositiveInt(json['bitrate']),
      format: json['format']?.toString(),
    );
  }

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
        if (bitDepth != null && bitDepth! > 0) 'bit_depth': bitDepth,
        if (sampleRate != null && sampleRate! > 0) 'sample_rate': sampleRate,
        if (bitrate != null && bitrate! > 0) 'bitrate': bitrate,
        if (format != null && format!.trim().isNotEmpty)
          'format': format!.trim(),
      },
    );
  }
}

/// Technical audio metadata carried with a queue item. This is available
/// immediately when tracks change, before a fresh file probe completes.
Map<String, dynamic> playbackAudioMetadataFromMediaItem(MediaItem item) {
  final extras = item.extras;
  if (extras == null || extras.isEmpty) return const {};

  final metadata = <String, dynamic>{};
  final bitDepth = readPositiveInt(extras['bit_depth']);
  final sampleRate = readPositiveInt(extras['sample_rate']);
  final bitrate = readPositiveInt(extras['bitrate']);
  final format = extras['format']?.toString().trim();
  if (bitDepth != null) metadata['bit_depth'] = bitDepth;
  if (sampleRate != null) metadata['sample_rate'] = sampleRate;
  if (bitrate != null) metadata['bitrate'] = bitrate;
  if (format != null && format.isNotEmpty) metadata['format'] = format;
  return metadata;
}

/// Combines the immediate queue metadata with the richer file probe while
/// retaining known quality fields when a decoder omits or reports them as 0.
Map<String, dynamic> mergePlaybackFileMetadata(
  Map<String, dynamic> fallback,
  Map<String, dynamic> probed,
) {
  final merged = <String, dynamic>{...fallback, ...probed};
  for (final key in const ['bit_depth', 'sample_rate', 'bitrate']) {
    if (readPositiveInt(probed[key]) == null &&
        readPositiveInt(fallback[key]) != null) {
      merged[key] = fallback[key];
    }
  }
  final probedFormat = probed['format']?.toString().trim();
  final fallbackFormat = fallback['format']?.toString().trim();
  if ((probedFormat == null || probedFormat.isEmpty) &&
      fallbackFormat != null &&
      fallbackFormat.isNotEmpty) {
    merged['format'] = fallbackFormat;
  }
  return merged;
}

typedef PlaybackMetadataReader =
    Future<Map<String, dynamic>> Function(String path);

/// Reads playback metadata with a small bounded retry window for transient
/// cold-start/native bridge failures.
///
/// The native bridge reports some read failures as an `error` field instead
/// of throwing. Treat both forms identically so Now Playing does not cache an
/// empty Lyrics view until the route is reopened. A successful response with
/// no lyrics is still final and is never retried.
Future<Map<String, dynamic>> readPlaybackFileMetadataWithRetry(
  String path, {
  PlaybackMetadataReader? reader,
  List<Duration> retryDelays = const [
    Duration.zero,
    Duration(milliseconds: 250),
    Duration(milliseconds: 750),
  ],
}) async {
  final read = reader ?? PlatformBridge.readFileMetadata;
  final delays = retryDelays.isEmpty ? const [Duration.zero] : retryDelays;
  Object? lastError;
  var lastStack = StackTrace.current;

  for (final delay in delays) {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    try {
      final metadata = await read(path);
      final reportedError = metadata['error']?.toString().trim() ?? '';
      if (reportedError.isEmpty) return metadata;
      lastError = StateError(reportedError);
      lastStack = StackTrace.current;
    } catch (error, stack) {
      lastError = error;
      lastStack = stack;
    }
  }

  Error.throwWithStackTrace(
    lastError ?? StateError('Metadata reader returned no result'),
    lastStack,
  );
}

/// Returns a safe source-start position for restored playback. A completed
/// snapshot starts over instead of immediately completing again on resume.
Duration normalizedPlaybackResumePosition(
  Duration position, {
  Duration? duration,
}) {
  if (position <= Duration.zero) return Duration.zero;
  if (duration != null && duration > Duration.zero && position >= duration) {
    return Duration.zero;
  }
  return position;
}

class MusicPlayerHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer(playerId: 'music-player');
  AudioSession? _audioSession;
  final List<PlayableMedia> _media = [];
  final List<MediaItem> _queueItems = [];
  final Map<String, String> _resolvedPathCache = {};
  final Map<String, Future<String?>> _pendingSourceResolutions = {};
  final List<String> _resolvedPathOrder = [];
  final Set<String> _pendingResolvedPathDeletes = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  int _index = -1;
  int _playRequestGeneration = 0;
  String? _activeResolvedPath;
  bool _disposed = false;
  bool _initialized = false;
  bool _sourceReady = false;
  Future<void>? _activePlayOperation;

  bool _shuffle = false;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  final Random _random = Random();
  final List<int> _recent = [];
  final List<int> _playHistory = [];

  // True when playback was paused because another app took audio focus.
  bool _pausedByInterruption = false;
  bool _interruptionActive = false;
  bool _userPaused = false;
  // Position saved with the restored session; applied on the first play().
  Duration? _pendingRestorePosition;
  bool _restoringSession = false;
  int _switchingGeneration = 0;
  Duration _lastBroadcastPosition = Duration.zero;
  DateTime? _lastPositionBroadcastAt;
  DateTime? _lastPeriodicPersistAt;
  Future<void> _sessionWriteTail = Future<void>.value();
  static const Duration _positionBroadcastInterval = Duration(
    milliseconds: 500,
  );
  static const Duration _positionPersistInterval = Duration(seconds: 10);
  static const int _maxResolvedPathCacheEntries = 64;

  MusicPlayerHandler() {
    _activeMusicPlayerHandler = this;
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
        if (_switchingGeneration != 0 &&
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
      _player.onPositionChanged.listen(_handlePositionChanged),
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
          _log.d(
            'Audio interruption ${event.begin ? 'began' : 'ended'} '
            'type=${event.type} player=${_player.state} '
            'playing=${playbackState.value.playing}',
          );
          if (event.begin) {
            if (event.type == AudioInterruptionType.duck) {
              return;
            }

            // Another app took focus or a transient interruption began.
            _interruptionActive = true;
            _pausedByInterruption =
                _player.state == PlayerState.playing ||
                playbackState.value.playing;
            unawaited(_pauseForFocusLoss(reason: 'audio interruption'));
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
          unawaited(_pauseForFocusLoss(reason: 'becoming noisy'));
        }),
      );
    } catch (e) {
      _log.w('Failed to configure audio session: $e');
    }
  }

  bool get _shouldIgnoreComplete =>
      _switchingGeneration != 0 || _interruptionActive || _userPaused;

  Future<void> _pauseForFocusLoss({required String reason}) async {
    _log.i('Pausing internal player because of $reason');
    _playRequestGeneration++;
    _switchingGeneration = 0;
    try {
      await _player.pause();
    } catch (e) {
      _log.w('Failed to pause after audio focus loss: $e');
    }
    // Force the UI/notification to reflect the pause even if the engine does
    // not emit a state-change event on focus loss.
    _broadcastState(playerState: PlayerState.paused);
    await _persistSession(position: await _currentPositionForPersist());
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
        repeatMode: _repeatMode,
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

  void _handlePositionChanged(Duration position) {
    _broadcastPosition(position);
    if (_restoringSession ||
        _player.state != PlayerState.playing ||
        _media.isEmpty ||
        _index < 0 ||
        _index >= _media.length) {
      return;
    }

    final now = DateTime.now();
    final lastPersistAt = _lastPeriodicPersistAt;
    if (lastPersistAt != null &&
        now.difference(lastPersistAt) < _positionPersistInterval) {
      return;
    }
    _lastPeriodicPersistAt = now;
    unawaited(_persistSession(position: position));
  }

  // ReplayGain normalization: resolved path -> volume multiplier.
  final Map<String, double> _normalizationVolumeCache = {};

  /// Volume multiplier from the file's ReplayGain/R128 tags (track gain,
  /// album gain fallback; Opus R128 tags are converted to ReplayGain dB by
  /// the Go reader). 1.0 when disabled, untagged, or unreadable. Positive
  /// gains clamp at 1.0 — setVolume can only attenuate.
  Future<double> _normalizationVolumeFor(String path) async {
    if (!_playbackNormalizationEnabled) return 1.0;
    final cached = _normalizationVolumeCache[path];
    if (cached != null) return cached;

    var volume = 1.0;
    try {
      final metadata = await PlatformBridge.readFileMetadata(path);
      final gainDb =
          _parseGainDb(metadata['replaygain_track_gain']) ??
          _parseGainDb(metadata['replaygain_album_gain']);
      if (gainDb != null) {
        volume = pow(10.0, gainDb / 20.0).toDouble().clamp(0.0, 1.0);
      }
    } catch (e) {
      _log.w('Failed to read gain tags for normalization: $e');
    }
    if (_normalizationVolumeCache.length > 128) {
      _normalizationVolumeCache.clear();
    }
    _normalizationVolumeCache[path] = volume;
    return volume;
  }

  static double? _parseGainDb(Object? raw) {
    final text = raw?.toString();
    if (text == null || text.isEmpty) return null;
    final match = RegExp(r'-?\d+(\.\d+)?').firstMatch(text);
    return match == null ? null : double.tryParse(match.group(0)!);
  }

  /// Re-applies normalization to the playing track when the setting flips.
  void reapplyNormalization() {
    final index = _index;
    final generation = _playRequestGeneration;
    if (index < 0 || index >= _media.length) return;
    unawaited(() async {
      final media = _media[index];
      final resolved = media.isContentUri
          ? _resolvedPathCache[media.source]
          : media.source;
      if (resolved == null) return;
      final volume = await _normalizationVolumeFor(resolved);
      if (_index != index || generation != _playRequestGeneration) return;
      try {
        await _player.setVolume(volume);
      } catch (e) {
        _log.w('Failed to apply normalization volume: $e');
      }
    }());
  }

  Future<String?> _resolveSource(PlayableMedia media) async {
    if (!media.isContentUri) return media.source;

    final cached = _resolvedPathCache[media.source];
    if (cached != null) return cached;
    final inFlight = _pendingSourceResolutions[media.source];
    if (inFlight != null) return inFlight;

    final resolution = () async {
      try {
        final tempPath = await PlatformBridge.copyContentUriToTemp(
          media.source,
        );
        if (tempPath == null || tempPath.isEmpty) return null;
        if (_disposed) {
          await _discardResolvedPath(tempPath);
          return null;
        }

        _resolvedPathCache[media.source] = tempPath;
        _resolvedPathOrder
          ..remove(media.source)
          ..add(media.source);
        while (_resolvedPathOrder.length > _maxResolvedPathCacheEntries) {
          final evictedSource = _resolvedPathOrder.removeAt(0);
          final evictedPath = _resolvedPathCache.remove(evictedSource);
          if (evictedPath != null) {
            unawaited(_discardResolvedPath(evictedPath));
          }
        }
        return tempPath;
      } catch (e) {
        _log.e('Failed to resolve content URI for playback: $e');
        return null;
      }
    }();
    _pendingSourceResolutions[media.source] = resolution;
    try {
      return await resolution;
    } finally {
      if (identical(_pendingSourceResolutions[media.source], resolution)) {
        _pendingSourceResolutions.remove(media.source);
      }
    }
  }

  Future<void> _discardResolvedPath(String path) async {
    if (path == _activeResolvedPath) {
      _pendingResolvedPathDeletes.add(path);
      return;
    }
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      _log.w('Failed to delete SAF playback temp file: $e');
    }
  }

  Future<void> _cleanupPendingResolvedPaths() async {
    final deletable = _pendingResolvedPathDeletes
        .where((path) => path != _activeResolvedPath)
        .toList(growable: false);
    for (final path in deletable) {
      _pendingResolvedPathDeletes.remove(path);
      await _discardResolvedPath(path);
    }
  }

  Future<void> _enqueueSessionWrite(Future<void> Function() operation) {
    final queued = _sessionWriteTail.then((_) async {
      try {
        await operation();
      } catch (e) {
        _log.w('Failed to update persisted playback session: $e');
      }
    });
    _sessionWriteTail = queued;
    return queued;
  }

  /// Persists queue, current index, and position so a killed process can
  /// restore the session paused on next launch. Position updates are throttled
  /// by [_handlePositionChanged], while lifecycle/pause writes flush exactly.
  Future<void> _persistSession({Duration? position}) {
    if (_restoringSession) return Future<void>.value();
    if (_media.isEmpty || _index < 0 || _index >= _media.length) {
      return _enqueueSessionWrite(
        AppStateDatabase.instance.clearPlaybackSession,
      );
    }
    final session = <String, dynamic>{
      'version': 1,
      'media': _media.map((m) => m.toJson()).toList(growable: false),
      'index': _index,
      'positionMs': (position ?? Duration.zero).inMilliseconds,
      'shuffle': _shuffle,
      'repeat': _repeatMode.name,
    };
    return _enqueueSessionWrite(
      () => AppStateDatabase.instance.savePlaybackSession(session),
    );
  }

  Future<Duration> _currentPositionForPersist() async {
    // During restore/source preparation the engine may report a stale zero (or
    // the previous source). The broadcast position already represents the
    // intended start point for the current queue item.
    if (!_sourceReady) return playbackState.value.position;
    try {
      final position = await _player.getCurrentPosition();
      if (position != null) return position;
    } catch (_) {}
    return playbackState.value.position;
  }

  /// Flushes the live engine position and every older queued session write.
  /// Called when the app leaves the foreground so a normal restart resumes at
  /// the latest audible point rather than the beginning of the track.
  Future<void> persistCurrentSession() async {
    if (_media.isEmpty || _index < 0 || _index >= _media.length) return;
    final position = await _currentPositionForPersist();
    _lastPeriodicPersistAt = DateTime.now();
    await _persistSession(position: position);
  }

  /// Restores a persisted session paused: queue and current track become
  /// visible (mini player included) without loading any source; the first
  /// play() prepares the source directly at the saved position.
  Future<void> restoreSession({
    required List<PlayableMedia> items,
    required int index,
    required Duration position,
    required bool shuffle,
    AudioServiceRepeatMode repeatMode = AudioServiceRepeatMode.none,
  }) async {
    if (items.isEmpty) return;
    // Never clobber a session the user already started this launch.
    if (_media.isNotEmpty || _index >= 0) return;
    _restoringSession = true;
    try {
      _media
        ..clear()
        ..addAll(items);
      _queueItems
        ..clear()
        ..addAll(items.map((m) => m.toMediaItem()));
      _index = index.clamp(0, items.length - 1);
      _shuffle = shuffle;
      _repeatMode = repeatMode;
      _pendingRestorePosition = position > Duration.zero ? position : null;
      _sourceReady = false;
      _lastPeriodicPersistAt = null;
      queue.add(List<MediaItem>.unmodifiable(_queueItems));
      mediaItem.add(_media[_index].toMediaItem());
      if (position > Duration.zero) {
        playbackState.add(
          playbackState.value.copyWith(updatePosition: position),
        );
      }
      _broadcastState(playerState: PlayerState.paused);
    } finally {
      _restoringSession = false;
    }
  }

  bool _isCurrentPlayRequest(int generation, PlayableMedia media) {
    return generation == _playRequestGeneration &&
        _index >= 0 &&
        _index < _media.length &&
        _media[_index].id == media.id &&
        _media[_index].source == media.source;
  }

  Future<void> setQueueAndPlay(
    List<PlayableMedia> items, {
    int initialIndex = 0,
  }) async {
    if (items.isEmpty) return;
    _playRequestGeneration++;
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
    unawaited(_persistSession(position: playbackState.value.position));
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
    unawaited(_persistSession(position: playbackState.value.position));
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
    unawaited(_persistSession(position: playbackState.value.position));
  }

  Future<void> _playIndex(
    int index, {
    bool recordHistory = true,
    Duration startPosition = Duration.zero,
  }) async {
    if (index < 0 || index >= _media.length) return;
    // A normal track change supersedes a pending restore. A restored start
    // keeps it until the source is actually ready so a transient failure can
    // be retried from the same position.
    if (startPosition <= Duration.zero) {
      _pendingRestorePosition = null;
    }
    final generation = ++_playRequestGeneration;
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
    final effectiveStartPosition = normalizedPlaybackResumePosition(
      startPosition,
      duration: media.duration,
    );
    mediaItem.add(media.toMediaItem());
    _lastBroadcastPosition = Duration.zero;
    _lastPositionBroadcastAt = null;
    _broadcastPosition(effectiveStartPosition, force: true);
    // Claim the playing state up front (while the app is still in the
    // foreground window) so audio_service can start its foreground service
    // before the async source resolve below.
    _broadcastState(playerState: PlayerState.playing, loading: true);

    final resolved = await _resolveSource(media);
    if (!_isCurrentPlayRequest(generation, media)) return;
    if (resolved == null) {
      _log.e('No playable source for ${media.title}');
      _broadcastState(playerState: PlayerState.stopped);
      return;
    }

    try {
      await musicPlayerExclusiveAudioHook?.call();
    } catch (_) {}
    if (!_isCurrentPlayRequest(generation, media)) return;

    _switchingGeneration = generation;
    try {
      // Set before play() so the track never starts at the wrong loudness;
      // always set (1.0 when disabled/untagged) so a previous track's
      // attenuation can't leak into the next one.
      final normalizationVolume = await _normalizationVolumeFor(resolved);
      if (!_isCurrentPlayRequest(generation, media)) return;
      await _player.setAudioContext(_musicAudioContext);
      if (!_isCurrentPlayRequest(generation, media)) return;
      await _activateAudioSession();
      if (!_isCurrentPlayRequest(generation, media)) return;
      await _player.stop();
      _sourceReady = false;
      if (!_isCurrentPlayRequest(generation, media)) return;
      await _player.setVolume(normalizationVolume);
      if (!_isCurrentPlayRequest(generation, media)) return;
      await _player.play(
        DeviceFileSource(resolved),
        position: effectiveStartPosition > Duration.zero
            ? effectiveStartPosition
            : null,
      );
      if (!_isCurrentPlayRequest(generation, media)) return;
      _sourceReady = true;
      _pendingRestorePosition = null;
      _activeResolvedPath = media.isContentUri ? resolved : null;
      await _cleanupPendingResolvedPaths();
      // Plain file paths were already published before loading. Re-publishing
      // them with an identical resolved path made Now Playing clear and probe
      // the same metadata twice on every Next. SAF needs this second event so
      // the UI can inspect its temporary local copy.
      if (media.isContentUri) {
        mediaItem.add(media.toMediaItem(resolvedSource: resolved));
      }
      _broadcastPosition(effectiveStartPosition, force: true);
      _broadcastState(playerState: PlayerState.playing);
      _lastPeriodicPersistAt = DateTime.now();
      unawaited(_persistSession(position: effectiveStartPosition));
      _log.i('Playing: ${media.title}');
      // Some files do not emit onDurationChanged reliably (stuck at 0:00);
      // poll the engine for the real duration as a fallback.
      unawaited(_ensureDurationKnown(index, generation));
    } catch (e) {
      if (!_isCurrentPlayRequest(generation, media)) return;
      _sourceReady = false;
      _log.e('Playback failed for ${media.title}: $e');
      _broadcastState(playerState: PlayerState.stopped);
    } finally {
      if (_switchingGeneration == generation) {
        _switchingGeneration = 0;
      }
    }
  }

  /// Resolves the real track duration when the initial metadata had none and
  /// the duration-changed event did not fire, so the seek bar and total time
  /// do not get stuck at 0:00.
  Future<void> _ensureDurationKnown(int index, int generation) async {
    for (var attempt = 0; attempt < 15; attempt++) {
      if (_index != index || generation != _playRequestGeneration) return;
      final current = mediaItem.value;
      final existing = current?.duration;
      if (existing != null && existing > Duration.zero) return;

      try {
        final d = await _player.getDuration();
        if (_index != index || generation != _playRequestGeneration) return;
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
    if (_repeatMode == AudioServiceRepeatMode.one &&
        _index >= 0 &&
        _index < _media.length) {
      await _playIndex(_index, recordHistory: false);
      return;
    }
    if (_shuffle) {
      if (_media.length > 1) {
        await _playIndex(_pickNextShuffle());
      } else if (_repeatMode == AudioServiceRepeatMode.all &&
          _media.isNotEmpty) {
        await _playIndex(_index, recordHistory: false);
      } else {
        _broadcastState(playerState: PlayerState.completed);
      }
      return;
    }
    if (_index >= 0 && _index < _media.length - 1) {
      await _playIndex(_index + 1);
    } else if (_repeatMode == AudioServiceRepeatMode.all && _media.isNotEmpty) {
      await _playIndex(0);
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
    final activeOperation = _activePlayOperation;
    if (activeOperation != null) {
      await activeOperation;
      return;
    }

    final operation = _playInternal();
    _activePlayOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_activePlayOperation, operation)) {
        _activePlayOperation = null;
      }
    }
  }

  Future<void> _playInternal() async {
    _pausedByInterruption = false;
    _interruptionActive = false;
    _userPaused = false;
    if ((!_sourceReady ||
            _player.state == PlayerState.stopped ||
            _player.state == PlayerState.completed) &&
        _index >= 0 &&
        _index < _media.length) {
      await _playIndex(
        _index,
        recordHistory: false,
        startPosition: _pendingRestorePosition ?? Duration.zero,
      );
      return;
    }
    await _activateAudioSession();
    await _player.resume();
    _broadcastState(playerState: PlayerState.playing);
  }

  @override
  Future<void> pause() async {
    _log.i('Pausing internal player by user/control request');
    _playRequestGeneration++;
    _switchingGeneration = 0;
    _userPaused = true;
    _pausedByInterruption = false;
    await _player.pause();
    _broadcastState(playerState: PlayerState.paused);
    await _persistSession(position: await _currentPositionForPersist());
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
    if (_media.isNotEmpty && _index >= 0) {
      unawaited(_persistSession(position: playbackState.value.position));
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    // Group repeat has no meaning for a flat queue; treat it as all.
    _repeatMode = repeatMode == AudioServiceRepeatMode.group
        ? AudioServiceRepeatMode.all
        : repeatMode;
    _broadcastState();
    if (_media.isNotEmpty && _index >= 0) {
      unawaited(_persistSession(position: playbackState.value.position));
    }
  }

  @override
  Future<void> stop() async {
    _playRequestGeneration++;
    _switchingGeneration = 0;
    _userPaused = true;
    await _player.stop();
    _sourceReady = false;
    _activeResolvedPath = null;
    await _cleanupPendingResolvedPaths();
    _index = -1;
    _pausedByInterruption = false;
    _interruptionActive = false;
    _userPaused = false;
    _recent.clear();
    _playHistory.clear();
    _pendingRestorePosition = null;
    // An explicit stop ends the session for good; nothing to restore later.
    await _enqueueSessionWrite(AppStateDatabase.instance.clearPlaybackSession);
    // A stopped session has no current item; this also hides the mini player.
    mediaItem.add(null);
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

    final discardedPath = _resolvedPathCache.remove(target);
    _resolvedPathOrder.remove(target);
    if (discardedPath != null) {
      await _discardResolvedPath(discardedPath);
    }

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
      unawaited(_persistSession(position: playbackState.value.position));
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _playRequestGeneration++;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _sourceReady = false;
    await _player.dispose();
    _activeResolvedPath = null;
    final tempPaths = <String>{
      ..._resolvedPathCache.values,
      ..._pendingResolvedPathDeletes,
    };
    _resolvedPathCache.clear();
    _resolvedPathOrder.clear();
    _pendingResolvedPathDeletes.clear();
    for (final path in tempPaths) {
      await _discardResolvedPath(path);
    }
  }
}

MusicPlayerHandler? _handler;
Future<MusicPlayerHandler>? _initFuture;
final StreamController<MusicPlayerHandler> _handlerReadyController =
    StreamController<MusicPlayerHandler>.broadcast();

MusicPlayerHandler? get musicPlayerHandler => _handler;

Future<void> Function()? musicPlayerExclusiveAudioHook;

/// Flushes the current playback position if the player has been initialized.
Future<void> persistCurrentPlaybackSession() async {
  final handler = _handler;
  if (handler == null) return;
  await handler.persistCurrentSession();
}

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

/// Restores the last persisted playback session (if any) into a freshly
/// initialized handler, paused. Entries whose plain file paths no longer
/// exist are dropped; content URIs are kept and fail gracefully at play time.
Future<void> restorePersistedPlaybackSession() async {
  try {
    final session = await AppStateDatabase.instance.getPlaybackSession();
    if (session == null) return;

    final rawMedia = session['media'];
    if (rawMedia is! List) {
      await AppStateDatabase.instance.clearPlaybackSession();
      return;
    }

    final items = <PlayableMedia>[];
    final keptOriginalIndices = <int>[];
    for (var i = 0; i < rawMedia.length; i++) {
      final entry = rawMedia[i];
      if (entry is! Map) continue;
      final media = PlayableMedia.fromJson(Map<String, dynamic>.from(entry));
      if (media == null) continue;
      if (!media.isContentUri && !await File(media.source).exists()) {
        continue;
      }
      items.add(media);
      keptOriginalIndices.add(i);
    }
    if (items.isEmpty) {
      await AppStateDatabase.instance.clearPlaybackSession();
      return;
    }

    // Remap the saved index onto the surviving list; if the current track
    // itself was dropped, land on the nearest earlier survivor at 0:00.
    final savedIndex = (session['index'] as num?)?.toInt() ?? 0;
    var index = 0;
    for (var i = 0; i < keptOriginalIndices.length; i++) {
      if (keptOriginalIndices[i] <= savedIndex) index = i;
    }
    var position = Duration(
      milliseconds: (session['positionMs'] as num?)?.toInt() ?? 0,
    );
    if (keptOriginalIndices[index] != savedIndex) {
      position = Duration.zero;
    }

    final handler = await initMusicPlayer();
    await handler.restoreSession(
      items: items,
      index: index,
      position: position,
      shuffle: session['shuffle'] == true,
      repeatMode: AudioServiceRepeatMode.values.firstWhere(
        (mode) => mode.name == session['repeat'],
        orElse: () => AudioServiceRepeatMode.none,
      ),
    );
    _log.i(
      'Restored playback session: ${items.length} track(s), paused at '
      '${position.inSeconds}s',
    );
  } catch (e) {
    _log.w('Failed to restore playback session: $e');
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
