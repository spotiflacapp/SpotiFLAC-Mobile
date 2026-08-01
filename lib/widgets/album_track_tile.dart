import 'package:flutter/material.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/widgets/track_card.dart';

/// Album-style track row: track number, title/subtitle, and a trailing play
/// button that's hidden once selection mode is active.
///
/// A thin arrangement over [TrackCard]; the container, selection tick, padding
/// and typography all come from there.
class AlbumTrackTile extends StatelessWidget {
  const AlbumTrackTile({
    super.key,
    required this.trackNumber,
    required this.trackName,
    required this.subtitle,
    required this.isSelectionMode,
    required this.isSelected,
    required this.colorScheme,
    required this.onToggleSelection,
    required this.onOpen,
    required this.onEnterSelectionMode,
    required this.onPlay,
  });

  final int? trackNumber;
  final String trackName;
  final Widget subtitle;
  final bool isSelectionMode;
  final bool isSelected;
  final ColorScheme colorScheme;
  final VoidCallback onToggleSelection;
  final VoidCallback onOpen;
  final VoidCallback onEnterSelectionMode;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return TrackCard(
      style: TrackCardStyle.flat,
      isSelectionMode: isSelectionMode,
      isSelected: isSelected,
      onTap: isSelectionMode ? onToggleSelection : onOpen,
      onLongPress: isSelectionMode ? null : onEnterSelectionMode,
      leading: SizedBox(
        width: 24,
        child: Text(
          trackNumber?.toString() ?? '-',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
      title: trackName,
      subtitle: subtitle,
      trailing: IconButton(
        tooltip: context.l10n.tooltipPlay,
        onPressed: onPlay,
        icon: Icon(Icons.play_arrow, color: colorScheme.primary),
        style: IconButton.styleFrom(
          minimumSize: Size.square(context.tokens.minTouchTarget),
          backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
