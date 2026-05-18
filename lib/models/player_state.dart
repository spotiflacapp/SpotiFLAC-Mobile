import 'package:spotiflac_android/models/track.dart';

enum PlayerLoopMode { off, one, all }

class QueueTrack {
  final String title;
  final String artist;
  final String album;
  final String? coverUrl;
  final String filePath;
  final Track? track;

  const QueueTrack({
    required this.title,
    required this.artist,
    required this.album,
    this.coverUrl,
    required this.filePath,
    this.track,
  });

  QueueTrack copyWith({String? filePath}) => QueueTrack(
    title: title,
    artist: artist,
    album: album,
    coverUrl: coverUrl,
    filePath: filePath ?? this.filePath,
    track: track,
  );
}

class PlayerState {
  final List<QueueTrack> queue;
  final int currentIndex;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;
  final PlayerLoopMode loopMode;
  final String? error;

  const PlayerState({
    this.queue = const [],
    this.currentIndex = 0,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.loopMode = PlayerLoopMode.off,
    this.error,
  });

  QueueTrack? get current =>
      queue.isEmpty ? null : queue[currentIndex.clamp(0, queue.length - 1)];

  bool get hasTrack => queue.isNotEmpty;
  bool get hasPrevious => currentIndex > 0;
  bool get hasNext => currentIndex < queue.length - 1;

  PlayerState copyWith({
    List<QueueTrack>? queue,
    int? currentIndex,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    PlayerLoopMode? loopMode,
    String? error,
    bool clearError = false,
  }) {
    return PlayerState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      loopMode: loopMode ?? this.loopMode,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
