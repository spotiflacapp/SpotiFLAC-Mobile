import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/player_state.dart';
import 'package:spotiflac_android/providers/player_provider.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final current = playerState.current;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          iconSize: 32,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          current?.album ?? '',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 16),
              _AlbumArtwork(coverUrl: current?.coverUrl),
              const SizedBox(height: 32),
              _TrackInfo(current: current, colorScheme: colorScheme),
              const SizedBox(height: 24),
              _SeekBar(playerState: playerState, colorScheme: colorScheme),
              const SizedBox(height: 24),
              _Controls(playerState: playerState),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumArtwork extends StatelessWidget {
  final String? coverUrl;
  const _AlbumArtwork({this.coverUrl});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size.width - 56;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: coverUrl != null && coverUrl!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: coverUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              memCacheWidth: (size * MediaQuery.of(context).devicePixelRatio).toInt(),
              cacheManager: CoverCacheManager.instance,
              errorWidget: (context, url, error) => _placeholder(colorScheme, size),
            )
          : _placeholder(colorScheme, size),
    );
  }

  Widget _placeholder(ColorScheme colorScheme, double size) => Container(
    width: size,
    height: size,
    color: colorScheme.surfaceContainerHighest,
    child: Icon(
      Icons.music_note,
      color: colorScheme.onSurfaceVariant,
      size: size * 0.4,
    ),
  );
}

class _TrackInfo extends StatelessWidget {
  final QueueTrack? current;
  final ColorScheme colorScheme;
  const _TrackInfo({required this.current, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                current?.title ?? '',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                current?.artist ?? '',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SeekBar extends ConsumerStatefulWidget {
  final PlayerState playerState;
  final ColorScheme colorScheme;
  const _SeekBar({required this.playerState, required this.colorScheme});

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _draggingValue;

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.playerState.duration.inMilliseconds.toDouble();
    final current = widget.playerState.position.inMilliseconds.toDouble();
    final sliderValue = _draggingValue ?? (total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0);

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: sliderValue,
            onChanged: (v) => setState(() => _draggingValue = v),
            onChangeEnd: (v) {
              final seekMs = (v * total).round();
              ref.read(playerProvider.notifier).seek(
                Duration(milliseconds: seekMs),
              );
              setState(() => _draggingValue = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _format(widget.playerState.position),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: widget.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                _format(widget.playerState.duration),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: widget.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  final PlayerState playerState;
  const _Controls({required this.playerState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = ref.read(playerProvider.notifier);

    final loopIcon = switch (playerState.loopMode) {
      PlayerLoopMode.off => Icons.repeat,
      PlayerLoopMode.all => Icons.repeat,
      PlayerLoopMode.one => Icons.repeat_one,
    };
    final loopColor = playerState.loopMode == PlayerLoopMode.off
        ? colorScheme.onSurfaceVariant
        : colorScheme.primary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: Icon(loopIcon, color: loopColor),
          iconSize: 24,
          onPressed: controller.cycleLoopMode,
          tooltip: 'Repeat',
        ),
        IconButton(
          icon: Icon(Icons.skip_previous, color: colorScheme.onSurface),
          iconSize: 36,
          onPressed: controller.skipToPrevious,
        ),
        _PlayPauseButton(playerState: playerState),
        IconButton(
          icon: Icon(Icons.skip_next, color: colorScheme.onSurface),
          iconSize: 36,
          onPressed: controller.skipToNext,
        ),
        // Placeholder so repeat icon has a symmetric counterpart
        const SizedBox(width: 48),
      ],
    );
  }
}

class _PlayPauseButton extends ConsumerWidget {
  final PlayerState playerState;
  const _PlayPauseButton({required this.playerState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: playerState.isLoading
          ? Padding(
              padding: const EdgeInsets.all(18),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onPrimary,
              ),
            )
          : IconButton(
              icon: Icon(
                playerState.isPlaying ? Icons.pause : Icons.play_arrow,
                color: colorScheme.onPrimary,
              ),
              iconSize: 32,
              onPressed: () =>
                  ref.read(playerProvider.notifier).togglePlayPause(),
            ),
    );
  }
}
