import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';
import 'package:spotiflac_android/utils/local_playback.dart';
import 'package:spotiflac_android/widgets/audio_quality_badges.dart';
import 'package:spotiflac_android/widgets/track_card.dart';
import 'package:spotiflac_android/widgets/in_library_badge.dart';
import 'package:spotiflac_android/widgets/preview_button.dart';
import 'package:spotiflac_android/widgets/track_collection_quick_actions.dart';

/// Track row shared by the album and playlist screens. Tap offers another
/// download when quality variants are enabled, otherwise it plays the local
/// copy when one exists and falls back to [onDownload]. Long-press opens the
/// track options sheet. Callers supply [leading] (track number, cover art,
/// ...) and choose whether the artist name links to the artist screen.
class TrackListTile extends ConsumerWidget {
  final Track track;
  final bool isInHistory;
  final void Function({bool forceQualityPicker}) onDownload;
  final Widget leading;
  final bool clickableArtist;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelection;
  final VoidCallback? onEnterSelectionMode;

  const TrackListTile({
    super.key,
    required this.track,
    required this.isInHistory,
    required this.onDownload,
    required this.leading,
    this.clickableArtist = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onToggleSelection,
    this.onEnterSelectionMode,
  }) : assert(!isSelectionMode || onToggleSelection != null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    final queueItem = ref.watch(
      downloadQueueLookupProvider.select(
        (lookup) => lookup.byTrackId[track.id],
      ),
    );

    final showLocalLibraryIndicator = ref.watch(
      settingsProvider.select(
        (s) => s.localLibraryEnabled && s.localLibraryShowDuplicates,
      ),
    );
    final isInLocalLibrary = showLocalLibraryIndicator
        ? ref.watch(
            localLibraryProvider.select(
              (state) => state.existsInLibrary(
                isrc: track.isrc,
                trackName: track.name,
                artistName: track.artistName,
              ),
            ),
          )
        : false;

    final isQueued = queueItem != null;

    return TrackCard(
      style: TrackCardStyle.flat,
      isSelectionMode: isSelectionMode,
      isSelected: isSelected,
      leading: leading,
      title: track.name,
      subtitle: Row(
        children: [
          Flexible(
            child: clickableArtist && !isSelectionMode
                ? ClickableArtistName(
                    artistName: track.artistName,
                    artistId: track.artistId,
                    coverUrl: track.coverUrl,
                    extensionId: track.source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  )
                : Text(
                    track.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
          ),
          ...buildQualityBadges(
            audioQuality: track.audioQuality,
            audioModes: track.audioModes,
            colorScheme: colorScheme,
            explicit: track.isExplicit,
          ),
          if (isInLocalLibrary || isInHistory) ...[
            const SizedBox(width: 6),
            const InLibraryBadge(),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PreviewButton(track: track),
          TrackCollectionQuickActions(
            track: track,
            hasLocalPlaybackCandidate: isInHistory || isInLocalLibrary,
          ),
        ],
      ),
      onTap: isSelectionMode
          ? onToggleSelection
          : () => _handleTap(
              context,
              ref,
              isQueued: isQueued,
              isInLocalLibrary: isInLocalLibrary,
            ),
      onLongPress: isSelectionMode
          ? null
          : onEnterSelectionMode ??
                () => TrackCollectionQuickActions.showTrackOptionsSheet(
                  context,
                  ref,
                  track,
                  hasLocalPlaybackCandidate: isInHistory || isInLocalLibrary,
                ),
    );
  }

  void _handleTap(
    BuildContext context,
    WidgetRef ref, {
    required bool isQueued,
    required bool isInLocalLibrary,
  }) async {
    if (isQueued) return;

    final settings = ref.read(settingsProvider);
    if (settings.allowQualityVariants && (isInHistory || isInLocalLibrary)) {
      onDownload(forceQualityPicker: true);
      return;
    }

    final playedLocal = await playLocalIfAvailable(context, ref, track);
    if (playedLocal) {
      return;
    }

    onDownload();
  }
}
