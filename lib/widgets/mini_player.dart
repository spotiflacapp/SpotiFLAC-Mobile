import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/player_state.dart';
import 'package:spotiflac_android/providers/player_provider.dart';
import 'package:spotiflac_android/screens/player_screen.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final current = playerState.current;
    if (current == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final totalSeconds = playerState.duration.inSeconds;
    final progress = totalSeconds > 0
        ? (playerState.position.inSeconds / totalSeconds).clamp(0.0, 1.0)
        : 0.0;

    return Material(
      elevation: 4,
      color: colorScheme.surfaceContainerHigh,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          PageRouteBuilder<void>(
            pageBuilder: (context, animation, secondaryAnimation) => const PlayerScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 300),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _AlbumArt(coverUrl: current.coverUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current.title,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (current.artist.isNotEmpty)
                          Text(
                            current.artist,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  _PrevButton(playerState: playerState),
                  _PlayPauseButton(playerState: playerState),
                  _NextButton(playerState: playerState),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumArt extends StatelessWidget {
  final String? coverUrl;
  const _AlbumArt({this.coverUrl});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: coverUrl != null && coverUrl!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: coverUrl!,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              memCacheWidth: 88,
              cacheManager: CoverCacheManager.instance,
              errorWidget: (context, url, error) => _placeholder(colorScheme),
            )
          : _placeholder(colorScheme),
    );
  }

  Widget _placeholder(ColorScheme colorScheme) => Container(
    width: 44,
    height: 44,
    color: colorScheme.surfaceContainerHighest,
    child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant, size: 20),
  );
}

class _PlayPauseButton extends ConsumerWidget {
  final PlayerState playerState;
  const _PlayPauseButton({required this.playerState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    if (playerState.isLoading) {
      return SizedBox(
        width: 36,
        height: 36,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
      );
    }
    return IconButton(
      icon: Icon(
        playerState.isPlaying ? Icons.pause : Icons.play_arrow,
        color: colorScheme.onSurface,
      ),
      onPressed: () => ref.read(playerProvider.notifier).togglePlayPause(),
      iconSize: 28,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

class _PrevButton extends ConsumerWidget {
  final PlayerState playerState;
  const _PrevButton({required this.playerState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: Icon(
        Icons.skip_previous,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onPressed: () => ref.read(playerProvider.notifier).skipToPrevious(),
      iconSize: 24,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

class _NextButton extends ConsumerWidget {
  final PlayerState playerState;
  const _NextButton({required this.playerState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: Icon(
        Icons.skip_next,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onPressed: () => ref.read(playerProvider.notifier).skipToNext(),
      iconSize: 24,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}
