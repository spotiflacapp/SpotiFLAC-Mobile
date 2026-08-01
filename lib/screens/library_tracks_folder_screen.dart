import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/album_detail_header.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/utils/cover_art_utils.dart';
import 'package:spotiflac_android/screens/collapsing_header_scroll_mixin.dart';
import 'package:spotiflac_android/screens/selection_mode_mixin.dart';
import 'package:spotiflac_android/screens/track_metadata_screen.dart';
import 'package:spotiflac_android/widgets/selection_action_button.dart';
import 'package:spotiflac_android/widgets/selection_bottom_bar.dart';
import 'package:spotiflac_android/widgets/in_library_badge.dart';
import 'package:spotiflac_android/widgets/playlist_picker_sheet.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/widgets/track_detail_actions.dart';

String? _resolveRawCoverUrl(Track track) {
  final rawCover = track.coverUrl?.trim();
  if (rawCover != null &&
      rawCover.isNotEmpty &&
      !rawCover.startsWith('content://')) {
    return rawCover;
  }
  return null;
}

class LibraryTracksFolderScreen extends ConsumerStatefulWidget {
  final LibraryTracksFolderMode mode;
  final String? playlistId;

  const LibraryTracksFolderScreen({
    super.key,
    required this.mode,
    this.playlistId,
  });

  @override
  ConsumerState<LibraryTracksFolderScreen> createState() =>
      _LibraryTracksFolderScreenState();
}

class _LibraryTracksFolderScreenState
    extends ConsumerState<LibraryTracksFolderScreen>
    with
        SelectionModeMixin<LibraryTracksFolderScreen>,
        CollapsingHeaderScrollMixin<LibraryTracksFolderScreen> {
  UserPlaylistCollection? playlist;

  @override
  void initState() {
    super.initState();
    final playlistId = widget.playlistId;
    if (widget.mode == LibraryTracksFolderMode.playlist && playlistId != null) {
      Future.microtask(
        () => ref
            .read(libraryCollectionsProvider.notifier)
            .ensurePlaylistLoaded(playlistId),
      );
    }
  }

  IconData _modeIcon() {
    return switch (widget.mode) {
      LibraryTracksFolderMode.wishlist => Icons.bookmark,
      LibraryTracksFolderMode.loved => Icons.favorite,
      LibraryTracksFolderMode.playlist => Icons.queue_music,
    };
  }

  /// Find the first available cover URL from entries.
  String? _firstRawCoverUrl(List<CollectionTrackEntry> entries) {
    for (final entry in entries) {
      final cover = _resolveRawCoverUrl(entry.track);
      if (cover != null && cover.isNotEmpty) {
        return cover;
      }
    }
    return null;
  }

  Future<void> _removeSelected(List<CollectionTrackEntry> entries) async {
    final keysToRemove = selectedIds.toSet();
    if (keysToRemove.isEmpty) return;

    final count = keysToRemove.length;
    final notifier = ref.read(libraryCollectionsProvider.notifier);

    for (final key in keysToRemove) {
      switch (widget.mode) {
        case LibraryTracksFolderMode.wishlist:
          await notifier.removeFromWishlist(key);
          break;
        case LibraryTracksFolderMode.loved:
          await notifier.removeFromLoved(key);
          break;
        case LibraryTracksFolderMode.playlist:
          if (widget.playlistId != null) {
            await notifier.removeTrackFromPlaylist(widget.playlistId!, key);
          }
          break;
      }
    }

    exitSelectionMode();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.selectionSelected(count))),
    );
  }

  LocalLibraryCoverBatchRequest _coverBatchRequest(
    List<CollectionTrackEntry> entries,
  ) {
    return LocalLibraryCoverBatchRequest(
      entries
          .map(
            (entry) => LocalLibraryCoverRequest(
              isrc: entry.track.isrc?.trim(),
              trackName: entry.track.name,
              artistName: entry.track.artistName,
            ),
          )
          .toList(growable: false),
    );
  }

  void _downloadSelected(List<CollectionTrackEntry> entries) {
    final settings = ref.read(settingsProvider);
    final extensionState = ref.read(extensionProvider);
    final service = resolveEffectiveDownloadService(
      settings.defaultService,
      extensionState,
    );
    if (service.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.extensionsNoDownloadProvider)),
      );
      return;
    }
    final queueNotifier = ref.read(downloadQueueProvider.notifier);
    var count = 0;

    for (final entry in entries) {
      if (!selectedIds.contains(entry.key)) continue;
      queueNotifier.addToQueue(entry.track, service);
      count++;
    }

    exitSelectionMode();

    if (!mounted || count == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.selectionSelected(count))),
    );
  }

  void _addSelectedToPlaylist(List<CollectionTrackEntry> entries) {
    final selectedTracks = entries
        .where((e) => selectedIds.contains(e.key))
        .map((e) => e.track)
        .toList(growable: false);
    if (selectedTracks.isEmpty) return;

    showAddTracksToPlaylistSheet(context, ref, selectedTracks);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    ref.watch(localLibraryProvider.select((s) => s.loadedIndexVersion));
    final List<CollectionTrackEntry> entries;

    switch (widget.mode) {
      case LibraryTracksFolderMode.wishlist:
        playlist = null;
        entries = ref.watch(
          libraryCollectionsProvider.select((state) => state.wishlist),
        );
        break;
      case LibraryTracksFolderMode.loved:
        playlist = null;
        entries = ref.watch(
          libraryCollectionsProvider.select((state) => state.loved),
        );
        break;
      case LibraryTracksFolderMode.playlist:
        final playlistId = widget.playlistId;
        playlist = playlistId == null
            ? null
            : ref.watch(
                libraryCollectionsProvider.select(
                  (state) => state.playlistById(playlistId),
                ),
              );
        entries = playlist?.tracks ?? const <CollectionTrackEntry>[];
        break;
    }

    pruneSelection(entries.map((e) => e.key).toSet());

    final title = switch (widget.mode) {
      LibraryTracksFolderMode.wishlist => context.l10n.collectionWishlist,
      LibraryTracksFolderMode.loved => context.l10n.collectionLoved,
      LibraryTracksFolderMode.playlist =>
        playlist?.name ?? context.l10n.collectionPlaylist,
    };

    final emptyTitle = switch (widget.mode) {
      LibraryTracksFolderMode.wishlist =>
        context.l10n.collectionWishlistEmptyTitle,
      LibraryTracksFolderMode.loved => context.l10n.collectionLovedEmptyTitle,
      LibraryTracksFolderMode.playlist =>
        context.l10n.collectionPlaylistEmptyTitle,
    };

    final emptySubtitle = switch (widget.mode) {
      LibraryTracksFolderMode.wishlist =>
        context.l10n.collectionWishlistEmptySubtitle,
      LibraryTracksFolderMode.loved =>
        context.l10n.collectionLovedEmptySubtitle,
      LibraryTracksFolderMode.playlist =>
        context.l10n.collectionPlaylistEmptySubtitle,
    };
    final folderTracks = entries
        .map((entry) => entry.track)
        .toList(growable: false);
    final historyLookups = folderTracks
        .map(historyLookupForTrack)
        .toList(growable: false);
    final existingHistoryKeys = ref
        .watch(
          downloadHistoryBatchExistsProvider(
            HistoryBatchLookupRequest(historyLookups),
          ),
        )
        .maybeWhen(data: (keys) => keys, orElse: () => const <String>{});

    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final bottomInset = context.navBarBottomInset;

    return PopScope(
      canPop: !isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isSelectionMode) {
          exitSelectionMode();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            CustomScrollView(
              controller: scrollController,
              slivers: [
                _buildAppBar(context, colorScheme, title, entries, playlist),
                if (entries.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyFolderState(
                      title: emptyTitle,
                      subtitle: emptySubtitle,
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: wideListInset(context),
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final entry = entries[index];
                        final isSelected = selectedIds.contains(entry.key);
                        final isInHistory = existingHistoryKeys.contains(
                          historyLookups[index].lookupKey,
                        );
                        return KeyedSubtree(
                          key: ValueKey(entry.key),
                          child: StaggeredListItem(
                            index: index,
                            child: _CollectionTrackTile(
                              entry: entry,
                              mode: widget.mode,
                              playlistId: widget.playlistId,
                              folderTracks: folderTracks,
                              isInHistory: isInHistory,
                              isSelectionMode: isSelectionMode,
                              isSelected: isSelected,
                              onTap: isSelectionMode
                                  ? () => toggleSelection(entry.key)
                                  : null,
                              onLongPress: isSelectionMode
                                  ? null
                                  : () => enterSelectionMode(entry.key),
                            ),
                          ),
                        );
                      }, childCount: entries.length),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(height: isSelectionMode ? 200 : 32),
                ),
                SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
              ],
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: isSelectionMode ? 0 : -(280 + bottomPadding),
              child: _buildSelectionBottomBar(
                context,
                colorScheme,
                entries,
                bottomPadding,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBottomBar(
    BuildContext context,
    ColorScheme colorScheme,
    List<CollectionTrackEntry> entries,
    double bottomPadding,
  ) {
    final selectedCount = selectedIds.length;
    final allSelected = selectedCount == entries.length && entries.isNotEmpty;
    final isWishlist = widget.mode == LibraryTracksFolderMode.wishlist;

    return SelectionBottomBar(
      selectedCount: selectedCount,
      allSelected: allSelected,
      onClose: exitSelectionMode,
      onToggleSelectAll: () {
        if (allSelected) {
          exitSelectionMode();
        } else {
          selectAll(entries.map((e) => e.key));
        }
      },
      bottomPadding: bottomPadding,
      children: [
        Row(
          children: [
            if (isWishlist)
              Expanded(
                child: SelectionActionButton(
                  icon: Icons.download,
                  label: '${context.l10n.settingsDownload} ($selectedCount)',
                  onPressed: selectedCount > 0
                      ? () => _downloadSelected(entries)
                      : null,
                  colorScheme: colorScheme,
                ),
              ),
            if (isWishlist) const SizedBox(width: 8),
            Expanded(
              child: SelectionActionButton(
                icon: Icons.playlist_add,
                label:
                    '${context.l10n.collectionAddToPlaylist} ($selectedCount)',
                onPressed: selectedCount > 0
                    ? () => _addSelectedToPlaylist(entries)
                    : null,
                colorScheme: colorScheme,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: selectedCount > 0
                ? () => _removeSelected(entries)
                : null,
            icon: const Icon(Icons.remove_circle_outline),
            label: Text(
              selectedCount > 0
                  ? '${widget.mode == LibraryTracksFolderMode.playlist ? context.l10n.collectionRemoveFromPlaylist : context.l10n.collectionRemoveFromFolder} ($selectedCount)'
                  : widget.mode == LibraryTracksFolderMode.playlist
                  ? context.l10n.collectionRemoveFromPlaylist
                  : context.l10n.collectionRemoveFromFolder,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: selectedCount > 0
                  ? colorScheme.error
                  : colorScheme.surfaceContainerHighest,
              foregroundColor: selectedCount > 0
                  ? colorScheme.onError
                  : colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickCoverImage() async {
    final playlistId = widget.playlistId;
    if (playlistId == null) return;

    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null) return;

    final path = picked.path;
    if (path == null || path.isEmpty) return;

    await ref
        .read(libraryCollectionsProvider.notifier)
        .setPlaylistCover(playlistId, path);
  }

  Future<void> _removeCoverImage() async {
    final playlistId = widget.playlistId;
    if (playlistId == null) return;

    await ref
        .read(libraryCollectionsProvider.notifier)
        .removePlaylistCover(playlistId);
  }

  Widget _buildAppBar(
    BuildContext context,
    ColorScheme colorScheme,
    String title,
    List<CollectionTrackEntry> entries,
    UserPlaylistCollection? playlist,
  ) {
    final expandedHeight = calculateExpandedHeight(context);
    final customCoverPath = playlist?.coverImagePath;
    final isLovedMode = widget.mode == LibraryTracksFolderMode.loved;
    final isPlaylistMode = widget.mode == LibraryTracksFolderMode.playlist;
    final rawCoverUrl = isLovedMode ? null : _firstRawCoverUrl(entries);
    final localCoverUrl =
        rawCoverUrl == null && !isLovedMode && entries.isNotEmpty
        ? ref
              .watch(
                localLibraryFirstCoverProvider(_coverBatchRequest(entries)),
              )
              .maybeWhen(data: (cover) => cover, orElse: () => null)
        : null;
    final coverUrl = rawCoverUrl ?? localCoverUrl;
    final hasCustomCover =
        customCoverPath != null && customCoverPath.isNotEmpty;
    final hasCoverUrl = coverUrl != null;

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (MediaQuery.sizeOf(context).width * dpr).round().clamp(
      320,
      2048,
    );
    final coverFallback = Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(_modeIcon(), size: 80, color: colorScheme.onSurfaceVariant),
    );
    Widget squarePlaceholder() => Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(_modeIcon(), size: 48, color: colorScheme.onSurfaceVariant),
    );

    final Widget background = hasCustomCover
        ? Image.file(
            File(customCoverPath),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) {
                return child;
              }
              return coverFallback;
            },
            errorBuilder: (_, _, _) => coverFallback,
          )
        : hasCoverUrl
        ? LocalOrNetworkCoverImage(
            url: coverUrl,
            fit: BoxFit.cover,
            localCacheWidth: cacheWidth,
            networkCacheWidth: cacheWidth,
            fadeInDuration: Duration.zero,
            urlTransform: (u) => highResCoverUrl(u) ?? u,
            placeholder: (_) => Container(color: colorScheme.surface),
          )
        : coverFallback;

    return AlbumDetailHeader(
      title: title,
      appBarTitle: isSelectionMode
          ? context.l10n.selectionSelected(selectedIds.length)
          : title,
      expandedHeight: expandedHeight,
      showTitleInAppBar: showTitleInAppBar,
      background: background,
      blurAndScrimBackground: hasCustomCover || hasCoverUrl,
      coverBuilder: (context, coverSize) {
        if (hasCustomCover) {
          return Image.file(
            File(customCoverPath),
            fit: BoxFit.cover,
            width: coverSize,
            height: coverSize,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => squarePlaceholder(),
          );
        }
        if (hasCoverUrl) {
          return LocalOrNetworkCoverImage(
            url: coverUrl,
            fit: BoxFit.cover,
            width: coverSize,
            height: coverSize,
            localCacheWidth: cacheWidth,
            networkCacheWidth: cacheWidth,
            urlTransform: (u) => highResCoverUrl(u) ?? u,
            placeholder: (_) => squarePlaceholder(),
          );
        }
        return squarePlaceholder();
      },
      meta: entries.isNotEmpty
          ? HeaderMetaRow(
              items: [
                HeaderMetaItem(
                  context.l10n.tracksCount(entries.length),
                  icon: _modeIcon(),
                ),
              ],
            )
          : null,
      actions: entries.isNotEmpty
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: _buildPlayAllCenterButton(entries)),
                const SizedBox(width: 8),
                Flexible(child: _buildDownloadAllCenterButton(entries)),
              ],
            )
          : null,
      appBarActions: [
        if (isPlaylistMode && !isSelectionMode) ...[
          IconButton(
            tooltip: context.l10n.collectionRenamePlaylist,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.edit_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
            onPressed: () {
              final id = widget.playlistId ?? playlist?.id;
              if (id == null || id.isEmpty) return;
              _showRenamePlaylistDialog(context, id, playlist?.name ?? title);
            },
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
            onPressed: () => _showCoverOptionsSheet(context, hasCustomCover),
          ),
        ],
      ],
      leading: IconButton(
        tooltip: isSelectionMode
            ? MaterialLocalizations.of(context).closeButtonTooltip
            : MaterialLocalizations.of(context).backButtonTooltip,
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isSelectionMode ? Icons.close : Icons.arrow_back,
            color: Colors.white,
          ),
        ),
        onPressed: isSelectionMode
            ? exitSelectionMode
            : () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildPlayAllCenterButton(List<CollectionTrackEntry> entries) {
    final tracks = entries.map((e) => e.track).toList(growable: false);
    return FilledButton.icon(
      onPressed: tracks.isEmpty ? null : () => _playAll(tracks),
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: Text(
        context.l10n.tooltipPlay,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  Widget _buildDownloadAllCenterButton(List<CollectionTrackEntry> entries) {
    final tracks = entries.map((e) => e.track).toList(growable: false);
    return FilledButton.icon(
      onPressed: tracks.isEmpty ? null : () => _confirmDownloadAll(tracks),
      icon: const Icon(Icons.download_rounded, size: 18),
      label: Text(
        context.l10n.downloadAllCount(tracks.length),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  Future<void> _playAll(List<Track> tracks) async {
    if (tracks.isEmpty) return;

    try {
      await ref.read(musicPlayerControllerProvider).setShuffle(false);
      await ref.read(playbackProvider.notifier).playTrackList(tracks);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.snackbarCannotOpenFile('$e'))),
      );
    }
  }

  void _confirmDownloadAll(List<Track> tracks) {
    confirmDownloadAllDialog(
      context,
      tracks.length,
      () => _downloadAll(tracks),
    );
  }

  Future<void> _downloadAll(List<Track> tracks) async {
    final playlistName = widget.mode == LibraryTracksFolderMode.playlist
        ? playlist?.name ?? context.l10n.collectionPlaylist
        : null;
    await queueTracksSkippingDownloaded(
      context,
      ref,
      tracks,
      artistNameForPicker: switch (widget.mode) {
        LibraryTracksFolderMode.wishlist => context.l10n.collectionWishlist,
        LibraryTracksFolderMode.loved => context.l10n.collectionLoved,
        LibraryTracksFolderMode.playlist => context.l10n.collectionPlaylist,
      },
      playlistName: playlistName,
      resolveDefaultService: false,
    );
  }

  void _showCoverOptionsSheet(BuildContext context, bool hasCustomCover) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 4,
              ),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.image_outlined,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(context.l10n.collectionPlaylistChangeCover),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickCoverImage();
              },
            ),
            if (hasCustomCover)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 4,
                ),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.delete_outline,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                title: Text(context.l10n.collectionPlaylistRemoveCover),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removeCoverImage();
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenamePlaylistDialog(
    BuildContext context,
    String playlistId,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();

    final nextName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(dialogContext.l10n.collectionRenamePlaylist),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: dialogContext.l10n.collectionPlaylistNameHint,
              ),
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) {
                  return dialogContext.l10n.collectionPlaylistNameRequired;
                }
                return null;
              },
              onFieldSubmitted: (_) {
                if (formKey.currentState?.validate() != true) return;
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(dialogContext.l10n.dialogCancel),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: Text(dialogContext.l10n.dialogSave),
            ),
          ],
        );
      },
    );

    if (nextName == null || nextName.trim().isEmpty || !context.mounted) {
      return;
    }

    await ref
        .read(libraryCollectionsProvider.notifier)
        .renamePlaylist(playlistId, nextName.trim());

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.collectionPlaylistRenamed)),
    );
  }
}

class _CollectionTrackTile extends ConsumerWidget {
  final CollectionTrackEntry entry;
  final LibraryTracksFolderMode mode;
  final String? playlistId;
  final List<Track> folderTracks;
  final bool isInHistory;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _CollectionTrackTile({
    required this.entry,
    required this.mode,
    required this.playlistId,
    required this.folderTracks,
    required this.isInHistory,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = entry.track;
    final colorScheme = Theme.of(context).colorScheme;
    final rawCoverUrl = _resolveRawCoverUrl(track);
    final localCoverUrl = rawCoverUrl == null
        ? ref
              .watch(
                localLibraryCoverProvider(
                  LocalLibraryCoverRequest(
                    isrc: track.isrc?.trim(),
                    trackName: track.name,
                    artistName: track.artistName,
                  ),
                ),
              )
              .maybeWhen(data: (cover) => cover, orElse: () => null)
        : null;
    final effectiveCoverUrl = rawCoverUrl ?? localCoverUrl;

    // Fine-grained provider watches – only this tile rebuilds when its own
    // history / local-library entry changes.
    final inMemoryHistoryItem = ref.watch(
      downloadHistoryProvider.select((state) {
        final byId = state.getBySpotifyId(track.id);
        if (byId != null) return byId;
        final isrc = track.isrc?.trim();
        if (isrc != null && isrc.isNotEmpty) {
          final byIsrc = state.getByIsrc(isrc);
          if (byIsrc != null) return byIsrc;
        }
        return state.findByTrackAndArtist(track.name, track.artistName);
      }),
    );
    final showLocalLibraryIndicator = ref.watch(
      settingsProvider.select(
        (s) => s.localLibraryEnabled && s.localLibraryShowDuplicates,
      ),
    );
    final isInLocalLibrary = showLocalLibraryIndicator
        ? ref.watch(
            localLibraryProvider.select((state) {
              final isrc = track.isrc?.trim();
              return state.existsInLibrary(
                isrc: isrc,
                trackName: track.name,
                artistName: track.artistName,
              );
            }),
          )
        : false;

    final heroTag = inMemoryHistoryItem != null
        ? 'cover_${inMemoryHistoryItem.id}'
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Card(
        elevation: 0,
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 2),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelectionMode) ...[
                AnimatedSelectionCheckbox(
                  visible: true,
                  selected: isSelected,
                  colorScheme: colorScheme,
                  size: 24,
                ),
                const SizedBox(width: 12),
              ],
              HeroMode(
                enabled: heroTag != null,
                child: heroTag != null
                    ? Hero(
                        tag: heroTag,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child:
                              effectiveCoverUrl != null &&
                                  effectiveCoverUrl.isNotEmpty
                              ? _buildTrackCover(context, effectiveCoverUrl, 52)
                              : Container(
                                  width: 52,
                                  height: 52,
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.music_note,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child:
                            effectiveCoverUrl != null &&
                                effectiveCoverUrl.isNotEmpty
                            ? _buildTrackCover(context, effectiveCoverUrl, 52)
                            : Container(
                                width: 52,
                                height: 52,
                                color: colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.music_note,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                      ),
              ),
            ],
          ),
          title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Row(
            children: [
              Flexible(
                child: Text(
                  track.artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isInLocalLibrary || isInHistory) ...[
                const SizedBox(width: 6),
                const InLibraryBadge(),
              ],
            ],
          ),
          trailing: isSelectionMode
              ? null
              : isInHistory || isInLocalLibrary
              ? IconButton(
                  tooltip: context.l10n.tooltipPlay,
                  onPressed: () {
                    ref.read(playbackProvider.notifier).playTrackList([track]);
                  },
                  icon: Icon(Icons.play_arrow, color: colorScheme.primary),
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                  ),
                )
              : null,
          onTap: isSelectionMode
              ? onTap
              : () {
                  if (mode == LibraryTracksFolderMode.wishlist) {
                    _downloadTrack(context, ref);
                    return;
                  }

                  _navigateToMetadata(context, ref);
                },
          onLongPress: isSelectionMode ? onTap : onLongPress,
        ),
      ),
    );
  }

  Widget _buildTrackCover(BuildContext context, String coverUrl, double size) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget placeholder() => Container(
      width: size,
      height: size,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant),
    );

    return LocalOrNetworkCoverImage(
      url: coverUrl,
      width: size,
      height: size,
      networkCacheWidth: (size * 2).toInt(),
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 90),
      placeholder: (_) => placeholder(),
    );
  }

  void _downloadTrack(BuildContext context, WidgetRef ref) {
    downloadSingleTrack(context, ref, entry.track);
  }

  Future<void> _navigateToMetadata(BuildContext context, WidgetRef ref) async {
    final track = entry.track;
    final historyNotifier = ref.read(downloadHistoryProvider.notifier);

    var historyItem = await historyNotifier.getBySpotifyIdAsync(track.id);
    if (!context.mounted) return;

    if (historyItem == null && track.isrc != null && track.isrc!.isNotEmpty) {
      historyItem = await historyNotifier.getByIsrcAsync(track.isrc!);
      if (!context.mounted) return;
    }

    historyItem ??= await historyNotifier.findByTrackAndArtistAsync(
      track.name,
      track.artistName,
    );
    if (!context.mounted) return;

    if (historyItem != null) {
      await Navigator.of(context).push(
        slidePageRoute<void>(page: TrackMetadataScreen(item: historyItem)),
      );
      return;
    }

    final localItem = await ref
        .read(localLibraryProvider.notifier)
        .findExistingAsync(
          isrc: track.isrc,
          trackName: track.name,
          artistName: track.artistName,
        );
    if (!context.mounted) return;

    if (localItem != null) {
      await Navigator.of(context).push(
        slidePageRoute<void>(page: TrackMetadataScreen(localItem: localItem)),
      );
      return;
    }

    _downloadTrack(context, ref);
  }
}

class _EmptyFolderState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyFolderState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open,
              size: 60,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum LibraryTracksFolderMode { wishlist, loved, playlist }
