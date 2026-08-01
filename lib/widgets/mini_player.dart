import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/screens/now_playing_screen.dart';
import 'package:spotiflac_android/widgets/player_artwork.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  // Hides the bar in the frames between a swipe-dismiss and the stopped
  // service clearing the media item (a dismissed Dismissible must leave the
  // tree immediately). Playing the same track again shows the bar normally.
  String? _dismissedItemId;

  @override
  Widget build(BuildContext context) {
    final mediaItem = ref.watch(currentMediaItemProvider).value;
    if (mediaItem == null) return const SizedBox.shrink();

    final isPlaying = ref.watch(playbackPlayingProvider);
    final isLoading = ref.watch(playbackLoadingProvider);
    if (mediaItem.id == _dismissedItemId && !isPlaying) {
      return const SizedBox.shrink();
    }

    final controller = ref.read(musicPlayerControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey('mini-player-${mediaItem.id}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        setState(() => _dismissedItemId = mediaItem.id);
        controller.stop();
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Material(
          color: settingsGroupColor(context).withValues(alpha: 0.72),
          child: InkWell(
            onTap: () {
              Navigator.of(
                context,
                rootNavigator: true,
              ).push(NowPlayingRoute());
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MiniPlayerProgress(
                  duration: mediaItem.duration ?? Duration.zero,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Hero(
                        tag: kNowPlayingArtworkHeroTag,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: PlayerArtwork(
                              artUri: mediaItem.artUri?.toString(),
                              colorScheme: colorScheme,
                              cacheWidth: 132,
                              iconSize: 22,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              mediaItem.title,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              mediaItem.artist ?? '',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: isLoading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                        onPressed: isLoading
                            ? null
                            : () => controller.togglePlayPause(isPlaying),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        onPressed: controller.next,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerProgress extends ConsumerWidget {
  final Duration duration;
  final Color backgroundColor;

  const _MiniPlayerProgress({
    required this.duration,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durationMs = duration.inMilliseconds;
    final positionMs = ref.watch(playbackPositionProvider).inMilliseconds;
    final progress = durationMs > 0
        ? (positionMs / durationMs).clamp(0.0, 1.0)
        : 0.0;
    return LinearProgressIndicator(
      value: progress,
      minHeight: 2,
      backgroundColor: backgroundColor,
    );
  }
}
