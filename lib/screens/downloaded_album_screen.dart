import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/cover_palette.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/services/batch_track_actions.dart';
import 'package:spotiflac_android/models/unified_library_item.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';
import 'package:spotiflac_android/utils/audio_quality_badge_policy.dart';
import 'package:spotiflac_android/utils/confirm_and_delete_tracks.dart';
import 'package:spotiflac_android/utils/cover_art_utils.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/image_cache_utils.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/screens/collapsing_header_scroll_mixin.dart';
import 'package:spotiflac_android/screens/selection_mode_mixin.dart';
import 'package:spotiflac_android/screens/track_metadata_screen.dart';
import 'package:spotiflac_android/services/downloaded_embedded_cover_resolver.dart';
import 'package:spotiflac_android/widgets/collection_scaffold.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';
import 'package:spotiflac_android/widgets/album_track_tile.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/widgets/destructive_selection_button.dart';
import 'package:spotiflac_android/widgets/selection_action_button.dart';
import 'package:spotiflac_android/widgets/selection_bottom_bar.dart';
import 'package:spotiflac_android/widgets/disc_separator_chip.dart';
import 'package:spotiflac_android/widgets/album_detail_header.dart';

class DownloadedAlbumScreen extends ConsumerStatefulWidget {
  final String albumName;
  final String artistName;
  final String? coverUrl;

  const DownloadedAlbumScreen({
    super.key,
    required this.albumName,
    required this.artistName,
    this.coverUrl,
  });

  @override
  ConsumerState<DownloadedAlbumScreen> createState() =>
      _DownloadedAlbumScreenState();
}

class _DownloadedAlbumScreenState extends ConsumerState<DownloadedAlbumScreen>
    with
        SelectionModeMixin<DownloadedAlbumScreen>,
        CollapsingHeaderScrollMixin<DownloadedAlbumScreen> {
  bool _embeddedCoverRefreshScheduled = false;
  List<DownloadHistoryItem>? _albumTracksSourceCache;
  List<DownloadHistoryItem>? _albumTracksCache;
  List<DownloadHistoryItem>? _discGroupingSourceCache;
  Map<int, List<DownloadHistoryItem>>? _discGroupingCache;
  List<int>? _sortedDiscNumbersCache;
  List<DownloadHistoryItem>? _commonQualitySourceCache;
  String? _commonQualityCache;
  String? _commonQualityModeCache;
  List<DownloadHistoryItem>? _embeddedCoverSourceCache;
  String? _embeddedCoverPathCache;
  bool _embeddedCoverPathResolved = false;

  String get _albumLookupKey =>
      '${widget.albumName.toLowerCase()}|${widget.artistName.toLowerCase()}';

  @override
  void didUpdateWidget(covariant DownloadedAlbumScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumName != widget.albumName ||
        oldWidget.artistName != widget.artistName) {
      _albumTracksSourceCache = null;
      _albumTracksCache = null;
      _invalidateDerivedTrackCaches();
    }
  }

  List<DownloadHistoryItem> _getAlbumTracks(
    List<DownloadHistoryItem> allItems,
  ) {
    final cached = _albumTracksCache;
    if (cached != null && identical(allItems, _albumTracksSourceCache)) {
      return cached;
    }

    final tracks =
        allItems.where((item) {
          final itemArtist =
              (item.albumArtist != null && item.albumArtist!.isNotEmpty)
              ? item.albumArtist!
              : item.artistName;
          final itemKey =
              '${item.albumName.toLowerCase()}|${itemArtist.toLowerCase()}';
          return itemKey == _albumLookupKey;
        }).toList()..sort((a, b) {
          final aDisc = a.discNumber ?? 1;
          final bDisc = b.discNumber ?? 1;
          if (aDisc != bDisc) return aDisc.compareTo(bDisc);
          final aNum = a.trackNumber ?? 999;
          final bNum = b.trackNumber ?? 999;
          if (aNum != bNum) return aNum.compareTo(bNum);
          return a.trackName.compareTo(b.trackName);
        });

    _albumTracksSourceCache = allItems;
    _albumTracksCache = tracks;
    _invalidateDerivedTrackCaches();
    return tracks;
  }

  void _invalidateDerivedTrackCaches() {
    _discGroupingSourceCache = null;
    _discGroupingCache = null;
    _sortedDiscNumbersCache = null;
    _commonQualitySourceCache = null;
    _commonQualityCache = null;
    _commonQualityModeCache = null;
    _embeddedCoverSourceCache = null;
    _embeddedCoverPathCache = null;
    _embeddedCoverPathResolved = false;
  }

  Map<int, List<DownloadHistoryItem>> _getDiscGroups(
    List<DownloadHistoryItem> tracks,
  ) {
    final cached = _discGroupingCache;
    if (cached != null && identical(tracks, _discGroupingSourceCache)) {
      return cached;
    }

    final discMap = <int, List<DownloadHistoryItem>>{};
    for (final track in tracks) {
      final discNumber = track.discNumber ?? 1;
      discMap.putIfAbsent(discNumber, () => []).add(track);
    }
    _discGroupingSourceCache = tracks;
    _discGroupingCache = discMap;
    _sortedDiscNumbersCache = discMap.keys.toList()..sort();
    return discMap;
  }

  List<int> _getSortedDiscNumbers(List<DownloadHistoryItem> tracks) {
    _getDiscGroups(tracks);
    return _sortedDiscNumbersCache ?? const [];
  }

  Future<void> _deleteSelected(List<DownloadHistoryItem> currentTracks) async {
    final historyNotifier = ref.read(downloadHistoryProvider.notifier);
    final tracksById = {for (final track in currentTracks) track.id: track};

    await confirmAndDeleteTracks(
      context: context,
      ids: selectedIds.toList(),
      deleteItem: (id) async {
        final item = tracksById[id];
        if (item == null) return false;
        final deleted = await deleteFile(item.filePath);
        if (!deleted) return false;
        historyNotifier.removeFromHistory(id);
        return true;
      },
      onExitSelectionMode: exitSelectionMode,
    );
  }

  Future<void> _openFile(
    DownloadHistoryItem track, {
    List<DownloadHistoryItem> queueItems = const [],
  }) async {
    try {
      await ref
          .read(playbackProvider.notifier)
          .playHistoryQueue(
            queueItems.isNotEmpty ? queueItems : [track],
            startItem: track,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.snackbarCannotOpenFile(context.friendlyError(e)),
            ),
          ),
        );
      }
    }
  }

  void _onEmbeddedCoverChanged() {
    if (!mounted || _embeddedCoverRefreshScheduled) return;
    _embeddedCoverRefreshScheduled = true;
    _embeddedCoverPathResolved = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _embeddedCoverRefreshScheduled = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _navigateToMetadataScreen(
    DownloadHistoryItem item, {
    required List<DownloadHistoryItem> navigationItems,
    required int navigationIndex,
  }) async {
    final navigator = Navigator.of(context);
    precacheCoverImage(context, item.coverUrl);
    final beforeModTime =
        await DownloadedEmbeddedCoverResolver.readFileModTimeMillis(
          item.filePath,
        );
    if (!mounted) return;

    final result = await navigator.push(
      slidePageRoute<bool>(
        page: TrackMetadataScreen(
          item: item,
          historyNavigationItems: navigationItems,
          navigationIndex: navigationIndex,
        ),
      ),
    );
    await DownloadedEmbeddedCoverResolver.scheduleRefreshForPath(
      item.filePath,
      beforeModTime: beforeModTime,
      force: result == true,
      onChanged: _onEmbeddedCoverChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final qualityLabelMode = ref.watch(
      settingsProvider.select((s) => s.libraryQualityLabelMode),
    );
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final bottomInset = context.navBarBottomInset;

    final tracksValue = ref.watch(
      downloadedAlbumTracksProvider(
        DownloadedAlbumTracksRequest(
          albumName: widget.albumName,
          artistName: widget.artistName,
        ),
      ),
    );
    final tracks = tracksValue.maybeWhen(
      data: (items) => _getAlbumTracks(items),
      orElse: () => const <DownloadHistoryItem>[],
    );

    if (tracks.isEmpty && tracksValue.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.albumName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (tracks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.albumName)),
        body: Center(child: Text(context.l10n.noTracksFoundForAlbum)),
      );
    }

    pruneSelection(tracks.map((t) => t.id).toSet());

    return CollectionScaffold(
      scrollController: scrollController,
      isSelectionMode: isSelectionMode,
      onExitSelectionMode: exitSelectionMode,
      appBar: _buildAppBar(context, colorScheme, tracks, qualityLabelMode),
      slivers: [_buildTrackList(context, colorScheme, tracks)],
      selectionBar: _buildSelectionBottomBar(
        context,
        colorScheme,
        tracks,
        bottomPadding,
      ),
      bottomInset: bottomInset,
    );
  }

  String? _resolveAlbumEmbeddedCoverPath(List<DownloadHistoryItem> tracks) {
    if (_embeddedCoverPathResolved &&
        identical(tracks, _embeddedCoverSourceCache)) {
      return _embeddedCoverPathCache;
    }

    _embeddedCoverSourceCache = tracks;
    _embeddedCoverPathResolved = true;

    if (tracks.isEmpty) {
      _embeddedCoverPathCache = null;
      return null;
    }

    _embeddedCoverPathCache = DownloadedEmbeddedCoverResolver.resolve(
      tracks.first.filePath,
      onChanged: _onEmbeddedCoverChanged,
    );
    return _embeddedCoverPathCache;
  }

  Widget _buildAppBar(
    BuildContext context,
    ColorScheme colorScheme,
    List<DownloadHistoryItem> tracks,
    String qualityLabelMode,
  ) {
    final expandedHeight = calculateExpandedHeight(context);
    final embeddedCoverPath = _resolveAlbumEmbeddedCoverPath(tracks);
    final commonQuality = _getCommonQuality(tracks, qualityLabelMode);

    final cacheWidth = coverCacheWidthForViewport(context);
    final Widget background = embeddedCoverPath != null
        ? Image.file(
            File(embeddedCoverPath),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => Container(color: colorScheme.surface),
          )
        : widget.coverUrl != null
        ? CachedNetworkImage(
            imageUrl: highResCoverUrl(widget.coverUrl) ?? widget.coverUrl!,
            fit: BoxFit.cover,
            memCacheWidth: cacheWidth,
            cacheManager: CoverCacheManager.instance,
            placeholder: (_, _) => Container(color: colorScheme.surface),
            errorWidget: (_, _, _) => Container(color: colorScheme.surface),
          )
        : Container(
            color: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.album,
              size: 80,
              color: colorScheme.onSurfaceVariant,
            ),
          );

    return AlbumDetailHeader(
      title: widget.albumName,
      expandedHeight: expandedHeight,
      showTitleInAppBar: showTitleInAppBar,
      background: background,
      paletteSource: embeddedCoverPath ?? widget.coverUrl,
      blurAndScrimBackground:
          embeddedCoverPath != null || widget.coverUrl != null,
      coverBuilder: (context, coverSize) => _buildSquareCover(
        context,
        colorScheme,
        embeddedCoverPath,
        coverSize,
        cacheWidth,
      ),
      subtitle: Text(
        widget.artistName,
        style: TextStyle(
          color: HeaderPalette.of(context).onSurfaceVariant,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      meta: tracks.isNotEmpty
          ? _buildDownloadedHeaderMeta(context, tracks, commonQuality)
          : null,
      actions: tracks.isNotEmpty
          ? AlbumPlayActions(
              playLabel: context.l10n.tooltipPlay,
              shuffleTooltip: context.l10n.actionShuffle,
              onPlay: () => _playAll(tracks),
              onShuffle: () => _shuffleAll(tracks),
            )
          : null,
    );
  }

  Widget _buildSquareCover(
    BuildContext context,
    ColorScheme colorScheme,
    String? embeddedCoverPath,
    double coverSize,
    int cacheWidth,
  ) {
    Widget placeholder() => Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.album, size: 48, color: colorScheme.onSurfaceVariant),
    );

    if (embeddedCoverPath != null) {
      return Image.file(
        File(embeddedCoverPath),
        fit: BoxFit.cover,
        width: coverSize,
        height: coverSize,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder(),
      );
    }

    final coverUrl = widget.coverUrl;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: highResCoverUrl(coverUrl) ?? coverUrl,
        fit: BoxFit.cover,
        width: coverSize,
        height: coverSize,
        memCacheWidth: cacheWidth,
        cacheManager: CoverCacheManager.instance,
        placeholder: (_, _) => placeholder(),
        errorWidget: (_, _, _) => placeholder(),
      );
    }

    return placeholder();
  }

  Widget _buildDownloadedHeaderMeta(
    BuildContext context,
    List<DownloadHistoryItem> tracks,
    String? commonQuality,
  ) {
    final totalSeconds = tracks.fold<int>(
      0,
      (sum, t) => sum + ((t.duration ?? 0) > 0 ? t.duration! : 0),
    );
    final totalMinutes = (totalSeconds / 60).round();

    return HeaderMetaRow(
      items: [
        HeaderMetaItem(
          context.l10n.downloadedAlbumDownloadedCount(tracks.length),
        ),
        if (totalMinutes > 0) HeaderMetaItem('$totalMinutes min'),
        if (commonQuality != null && commonQuality.isNotEmpty)
          HeaderMetaItem(commonQuality, icon: Icons.graphic_eq),
      ],
    );
  }

  Future<void> _playAll(List<DownloadHistoryItem> tracks) async {
    if (tracks.isEmpty) return;
    await ref.read(musicPlayerControllerProvider).setShuffle(false);
    await _openFile(tracks.first, queueItems: tracks);
  }

  Future<void> _shuffleAll(List<DownloadHistoryItem> tracks) async {
    if (tracks.isEmpty) return;
    await ref.read(musicPlayerControllerProvider).setShuffle(true);
    await _openFile(
      tracks[Random().nextInt(tracks.length)],
      queueItems: tracks,
    );
  }

  String? _getCommonQuality(List<DownloadHistoryItem> tracks, String mode) {
    if (identical(tracks, _commonQualitySourceCache) &&
        mode == _commonQualityModeCache) {
      return _commonQualityCache;
    }

    if (tracks.isEmpty) {
      _commonQualitySourceCache = tracks;
      _commonQualityModeCache = mode;
      _commonQualityCache = null;
      return null;
    }
    String? label(DownloadHistoryItem track) => buildLibraryAudioQualityLabel(
      mode: mode,
      format: track.format,
      bitrateKbps: track.bitrate,
      bitDepth: track.bitDepth,
      sampleRate: track.sampleRate,
      storedQuality: track.quality,
    );

    final firstQuality = label(tracks.first);
    if (firstQuality == null) {
      _commonQualitySourceCache = tracks;
      _commonQualityModeCache = mode;
      _commonQualityCache = null;
      return null;
    }
    for (final track in tracks) {
      if (label(track) != firstQuality) {
        _commonQualitySourceCache = tracks;
        _commonQualityModeCache = mode;
        _commonQualityCache = null;
        return null;
      }
    }
    _commonQualitySourceCache = tracks;
    _commonQualityModeCache = mode;
    _commonQualityCache = firstQuality;
    return firstQuality;
  }

  Widget _buildTrackList(
    BuildContext context,
    ColorScheme colorScheme,
    List<DownloadHistoryItem> tracks,
  ) {
    final discMap = _getDiscGroups(tracks);

    if (discMap.length <= 1) {
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: wideListInset(context)),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final track = tracks[index];
            return KeyedSubtree(
              key: ValueKey(track.id),
              child: StaggeredListItem(
                index: index,
                child: _buildTrackItem(
                  context,
                  colorScheme,
                  track,
                  tracks,
                  index,
                ),
              ),
            );
          }, childCount: tracks.length),
        ),
      );
    }

    final discNumbers = _getSortedDiscNumbers(tracks);
    final List<Widget> children = [];
    var revealIndex = 0;

    for (final discNumber in discNumbers) {
      final discTracks = discMap[discNumber];
      if (discTracks == null || discTracks.isEmpty) continue;

      children.add(DiscSeparatorChip(discNumber: discNumber));

      for (final track in discTracks) {
        final navigationIndex = tracks.indexOf(track);
        children.add(
          KeyedSubtree(
            key: ValueKey(track.id),
            child: StaggeredListItem(
              index: revealIndex++,
              child: _buildTrackItem(
                context,
                colorScheme,
                track,
                tracks,
                navigationIndex,
              ),
            ),
          ),
        );
      }
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: wideListInset(context)),
      sliver: SliverList(delegate: SliverChildListDelegate(children)),
    );
  }

  Widget _buildTrackItem(
    BuildContext context,
    ColorScheme colorScheme,
    DownloadHistoryItem track,
    List<DownloadHistoryItem> navigationItems,
    int navigationIndex,
  ) {
    return AlbumTrackTile(
      trackNumber: track.trackNumber,
      trackName: track.trackName,
      subtitle: Text(
        track.artistName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      isSelectionMode: isSelectionMode,
      isSelected: selectedIds.contains(track.id),
      colorScheme: colorScheme,
      onToggleSelection: () => toggleSelection(track.id),
      onOpen: () => _navigateToMetadataScreen(
        track,
        navigationItems: navigationItems,
        navigationIndex: navigationIndex,
      ),
      onEnterSelectionMode: () => enterSelectionMode(track.id),
      onPlay: () => _openFile(track, queueItems: navigationItems),
    );
  }

  Future<void> _shareSelected(List<DownloadHistoryItem> allTracks) async {
    final tracksById = {for (final t in allTracks) t.id: t};
    final safUris = <String>[];
    final filesToShare = <XFile>[];

    for (final id in selectedIds) {
      final item = tracksById[id];
      if (item == null) continue;
      final path = item.filePath;
      if (isContentUri(path)) {
        if (await fileExists(path)) safUris.add(path);
      } else if (await fileExists(path)) {
        filesToShare.add(XFile(path));
      }
    }

    if (safUris.isEmpty && filesToShare.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.selectionShareNoFiles)),
        );
      }
      return;
    }

    if (safUris.isNotEmpty) {
      try {
        if (safUris.length == 1) {
          await PlatformBridge.shareContentUri(safUris.first);
        } else {
          await PlatformBridge.shareMultipleContentUris(safUris);
        }
      } catch (_) {}
    }

    if (filesToShare.isNotEmpty) {
      await SharePlus.instance.share(ShareParams(files: filesToShare));
    }
  }

  List<UnifiedLibraryItem> _selectedUnifiedItems(
    List<DownloadHistoryItem> tracks,
  ) {
    final tracksById = {for (final t in tracks) t.id: t};
    return [
      for (final t in selectedIds.map((id) => tracksById[id]))
        if (t != null) UnifiedLibraryItem.fromDownloadHistory(t),
    ];
  }

  Widget _buildSelectionBottomBar(
    BuildContext context,
    ColorScheme colorScheme,
    List<DownloadHistoryItem> tracks,
    double bottomPadding,
  ) {
    final selectedCount = selectedIds.length;
    final allSelected = selectedCount == tracks.length && tracks.isNotEmpty;

    return SelectionBottomBar(
      selectedCount: selectedCount,
      allSelected: allSelected,
      onClose: exitSelectionMode,
      onToggleSelectAll: () {
        if (allSelected) {
          exitSelectionMode();
        } else {
          selectAll(tracks.map((e) => e.id));
        }
      },
      bottomPadding: bottomPadding,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final columns = (constraints.maxWidth / 320).floor().clamp(2, 4);
            final itemWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final actions = <Widget>[
              SelectionActionButton(
                icon: Icons.share_outlined,
                label: context.l10n.selectionShareCount(selectedCount),
                onPressed: selectedCount > 0
                    ? () => _shareSelected(tracks)
                    : null,
                colorScheme: colorScheme,
              ),
              SelectionActionButton(
                icon: Icons.swap_horiz,
                label: context.l10n.selectionConvertCount(selectedCount),
                onPressed: selectedCount > 0
                    ? () => showBatchConvertSheet(
                        context,
                        ref,
                        _selectedUnifiedItems(tracks),
                        onExitSelectionMode: exitSelectionMode,
                      )
                    : null,
                colorScheme: colorScheme,
              ),
              SelectionActionButton(
                icon: Icons.graphic_eq,
                label: context.l10n.selectionReplayGainCount(selectedCount),
                onPressed: selectedCount > 0
                    ? () => runBatchReplayGain(
                        context,
                        _selectedUnifiedItems(tracks),
                        onExitSelectionMode: exitSelectionMode,
                      )
                    : null,
                colorScheme: colorScheme,
              ),
            ];

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final action in actions)
                  SizedBox(width: itemWidth, child: action),
              ],
            );
          },
        ),

        const SizedBox(height: 8),
        DestructiveSelectionButton(
          count: selectedCount,
          colorScheme: colorScheme,
          onPressed: () => _deleteSelected(tracks),
        ),
      ],
    );
  }
}
