import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/screens/track_metadata_screen.dart';
import 'package:spotiflac_android/widgets/download_service_picker.dart';
import 'package:spotiflac_android/widgets/playlist_picker_sheet.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';

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
    extends ConsumerState<LibraryTracksFolderScreen> {
  bool _showTitleInAppBar = false;
  final ScrollController _scrollController = ScrollController();

  bool _isSelectionMode = false;
  final Set<String> _selectedKeys = {};
  UserPlaylistCollection? playlist;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final expandedHeight = _calculateExpandedHeight(context);
    final shouldShow =
        _scrollController.offset > (expandedHeight - kToolbarHeight - 20);
    if (shouldShow != _showTitleInAppBar) {
      setState(() => _showTitleInAppBar = shouldShow);
    }
  }

  double _calculateExpandedHeight(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    return (mediaSize.height * 0.6).clamp(400.0, 580.0);
  }

  double _folderTitleFontSize(String title) {
    final length = title.trim().length;
    if (length > 45) return 18;
    if (length > 30) return 21;
    return 24;
  }

  IconData _modeIcon() {
    return switch (widget.mode) {
      LibraryTracksFolderMode.wishlist => Icons.bookmark,
      LibraryTracksFolderMode.loved => Icons.favorite,
      LibraryTracksFolderMode.playlist => Icons.queue_music,
    };
  }

  String? _resolveRawEntryCoverUrl(CollectionTrackEntry entry) {
    final rawCover = entry.track.coverUrl?.trim();
    if (rawCover != null &&
        rawCover.isNotEmpty &&
        !rawCover.startsWith('content://')) {
      return rawCover;
    }
    return null;
  }

  /// Find the first available cover URL from entries.
  String? _firstRawCoverUrl(List<CollectionTrackEntry> entries) {
    for (final entry in entries) {
      final cover = _resolveRawEntryCoverUrl(entry);
      if (cover != null && cover.isNotEmpty) {
        return cover;
      }
    }
    return null;
  }

  bool _isCoverLocalPath(String url) {
    return !url.startsWith('http://') && !url.startsWith('https://');
  }

  /// Upgrade cover URL to higher resolution for full-screen display.
  String? _highResCoverUrl(String? url) {
    if (url == null) return null;
    // Spotify CDN: upgrade 300 → 640
    if (url.contains('ab67616d00001e02')) {
      return url.replaceAll('ab67616d00001e02', 'ab67616d0000b273');
    }
    // Deezer CDN: upgrade to 1000x1000
    final deezerRegex = RegExp(r'/(\d+)x(\d+)-(\d+)-(\d+)-(\d+)-(\d+)\.jpg$');
    if (url.contains('cdn-images.dzcdn.net') && deezerRegex.hasMatch(url)) {
      return url.replaceAllMapped(
        deezerRegex,
        (m) => '/1000x1000-${m[3]}-${m[4]}-${m[5]}-${m[6]}.jpg',
      );
    }
    return url;
  }

  void _enterSelectionMode(String key) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isSelectionMode = true;
      _selectedKeys.add(key);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedKeys.clear();
    });
  }

  void _toggleSelection(String key) {
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
        if (_selectedKeys.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  void _selectAll(List<CollectionTrackEntry> entries) {
    setState(() {
      _selectedKeys.addAll(entries.map((e) => e.key));
    });
  }

  Future<void> _removeSelected(List<CollectionTrackEntry> entries) async {
    final keysToRemove = _selectedKeys.toSet();
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

    _exitSelectionMode();

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
      if (!_selectedKeys.contains(entry.key)) continue;
      queueNotifier.addToQueue(entry.track, service);
      count++;
    }

    _exitSelectionMode();

    if (!mounted || count == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.selectionSelected(count))),
    );
  }

  void _addSelectedToPlaylist(List<CollectionTrackEntry> entries) {
    final selectedTracks = entries
        .where((e) => _selectedKeys.contains(e.key))
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

    if (_isSelectionMode) {
      final validKeys = entries.map((e) => e.key).toSet();
      _selectedKeys.removeWhere((key) => !validKeys.contains(key));
      if (_selectedKeys.isEmpty && _isSelectionMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _isSelectionMode = false);
        });
      }
    }

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
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            CustomScrollView(
              controller: _scrollController,
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
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final entry = entries[index];
                      final isSelected = _selectedKeys.contains(entry.key);
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
                            isSelectionMode: _isSelectionMode,
                            isSelected: isSelected,
                            onTap: _isSelectionMode
                                ? () => _toggleSelection(entry.key)
                                : null,
                            onLongPress: _isSelectionMode
                                ? null
                                : () => _enterSelectionMode(entry.key),
                          ),
                        ),
                      );
                    }, childCount: entries.length),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(height: _isSelectionMode ? 200 : 32),
                ),
                SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
              ],
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: _isSelectionMode ? 0 : -(280 + bottomPadding),
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
    final selectedCount = _selectedKeys.length;
    final allSelected = selectedCount == entries.length && entries.isNotEmpty;
    final isWishlist = widget.mode == LibraryTracksFolderMode.wishlist;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding > 0 ? 8 : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: _exitSelectionMode,
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.selectionSelected(selectedCount),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          allSelected
                              ? context.l10n.selectionAllSelected
                              : context.l10n.selectionSelectToDelete,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      if (allSelected) {
                        _exitSelectionMode();
                      } else {
                        _selectAll(entries);
                      }
                    },
                    icon: Icon(
                      allSelected ? Icons.deselect : Icons.select_all,
                      size: 20,
                    ),
                    label: Text(
                      allSelected
                          ? context.l10n.actionDeselect
                          : context.l10n.actionSelectAll,
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  if (isWishlist)
                    Expanded(
                      child: _SelectionActionButton(
                        icon: Icons.download,
                        label:
                            '${context.l10n.settingsDownload} ($selectedCount)',
                        onPressed: selectedCount > 0
                            ? () => _downloadSelected(entries)
                            : null,
                        colorScheme: colorScheme,
                      ),
                    ),
                  if (isWishlist) const SizedBox(width: 8),
                  Expanded(
                    child: _SelectionActionButton(
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
          ),
        ),
      ),
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
    final expandedHeight = _calculateExpandedHeight(context);
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

    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: true,
      stretch: true,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      title: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _showTitleInAppBar ? 1.0 : 0.0,
        child: Text(
          _isSelectionMode
              ? context.l10n.selectionSelected(_selectedKeys.length)
              : title,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      actions: [
        if (isPlaylistMode && !_isSelectionMode) ...[
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
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final collapseRatio =
              (constraints.maxHeight - kToolbarHeight) /
              (expandedHeight - kToolbarHeight);
          final showContent = collapseRatio > 0.3;
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final cacheWidth = (MediaQuery.sizeOf(context).width * dpr)
              .round()
              .clamp(320, 2048);
          final coverFallback = Container(
            color: colorScheme.surfaceContainerHighest,
            child: Icon(
              _modeIcon(),
              size: 80,
              color: colorScheme.onSurfaceVariant,
            ),
          );

          return FlexibleSpaceBar(
            collapseMode: CollapseMode.pin,
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (hasCustomCover)
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                    child: Image.file(
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
                    ),
                  )
                else if (hasCoverUrl)
                  _isCoverLocalPath(coverUrl)
                      ? ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: 32,
                            sigmaY: 32,
                          ),
                          child: Image.file(
                            File(coverUrl),
                            fit: BoxFit.cover,
                            cacheWidth: cacheWidth,
                            filterQuality: FilterQuality.low,
                            gaplessPlayback: true,
                            frameBuilder:
                                (_, child, frame, wasSynchronouslyLoaded) {
                                  if (wasSynchronouslyLoaded || frame != null) {
                                    return child;
                                  }
                                  return Container(color: colorScheme.surface);
                                },
                            errorBuilder: (_, _, _) =>
                                Container(color: colorScheme.surface),
                          ),
                        )
                      : ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: 32,
                            sigmaY: 32,
                          ),
                          child: CachedNetworkImage(
                            imageUrl: _highResCoverUrl(coverUrl) ?? coverUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: cacheWidth,
                            cacheManager: CoverCacheManager.instance,
                            placeholder: (_, _) =>
                                Container(color: colorScheme.surface),
                            errorWidget: (_, _, _) =>
                                Container(color: colorScheme.surface),
                          ),
                        )
                else
                  coverFallback,
                if (hasCustomCover || hasCoverUrl)
                  Container(color: Colors.black.withValues(alpha: 0.35)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: expandedHeight * 0.65,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 40,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: showContent ? 1.0 : 0.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Builder(
                          builder: (context) {
                            final coverSize = (constraints.maxWidth * 0.5)
                                .clamp(150.0, 210.0)
                                .toDouble();
                            Widget squarePlaceholder() => Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: Icon(
                                _modeIcon(),
                                size: 48,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            );
                            Widget coverChild;
                            if (hasCustomCover) {
                              coverChild = Image.file(
                                File(customCoverPath),
                                fit: BoxFit.cover,
                                width: coverSize,
                                height: coverSize,
                                cacheWidth: cacheWidth,
                                gaplessPlayback: true,
                                errorBuilder: (_, _, _) => squarePlaceholder(),
                              );
                            } else if (hasCoverUrl &&
                                _isCoverLocalPath(coverUrl)) {
                              coverChild = Image.file(
                                File(coverUrl),
                                fit: BoxFit.cover,
                                width: coverSize,
                                height: coverSize,
                                cacheWidth: cacheWidth,
                                gaplessPlayback: true,
                                errorBuilder: (_, _, _) => squarePlaceholder(),
                              );
                            } else if (hasCoverUrl) {
                              coverChild = CachedNetworkImage(
                                imageUrl:
                                    _highResCoverUrl(coverUrl) ?? coverUrl,
                                fit: BoxFit.cover,
                                width: coverSize,
                                height: coverSize,
                                memCacheWidth: cacheWidth,
                                cacheManager: CoverCacheManager.instance,
                                placeholder: (_, _) => squarePlaceholder(),
                                errorWidget: (_, _, _) => squarePlaceholder(),
                              );
                            } else {
                              coverChild = squarePlaceholder();
                            }
                            return Container(
                              width: coverSize,
                              height: coverSize,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: coverChild,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        Text(
                          title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: _folderTitleFontSize(title),
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (entries.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _modeIcon(),
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  context.l10n.tracksCount(entries.length),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildHeaderActionPlaceholder(),
                              const SizedBox(width: 12),
                              _buildDownloadAllCenterButton(entries),
                              const SizedBox(width: 12),
                              _buildHeaderActionPlaceholder(),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            stretchModes: const [StretchMode.zoomBackground],
          );
        },
      ),
      leading: IconButton(
        tooltip: _isSelectionMode
            ? MaterialLocalizations.of(context).closeButtonTooltip
            : MaterialLocalizations.of(context).backButtonTooltip,
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _isSelectionMode ? Icons.close : Icons.arrow_back,
            color: Colors.white,
          ),
        ),
        onPressed: _isSelectionMode
            ? _exitSelectionMode
            : () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildHeaderActionPlaceholder() =>
      const SizedBox(width: 48, height: 48);

  Widget _buildDownloadAllCenterButton(List<CollectionTrackEntry> entries) {
    final tracks = entries.map((e) => e.track).toList(growable: false);
    return FilledButton.icon(
      onPressed: tracks.isEmpty ? null : () => _confirmDownloadAll(tracks),
      icon: const Icon(Icons.download_rounded, size: 18),
      label: Text(context.l10n.downloadAllCount(tracks.length)),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  void _confirmDownloadAll(List<Track> tracks) {
    if (tracks.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          title: Text(context.l10n.dialogDownloadAllTitle),
          content: Text(context.l10n.dialogDownloadAllMessage(tracks.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.dialogCancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _downloadAll(tracks);
              },
              child: Text(context.l10n.dialogDownload),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadAll(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final historyLookups = tracks
        .map(historyLookupForTrack)
        .toList(growable: false);
    final existingHistoryKeys = await ref.read(
      downloadHistoryBatchExistsProvider(
        HistoryBatchLookupRequest(historyLookups),
      ).future,
    );
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    final localLibState =
        (settings.localLibraryEnabled && settings.localLibraryShowDuplicates)
        ? ref.read(localLibraryProvider)
        : null;
    final playlistName = widget.mode == LibraryTracksFolderMode.playlist
        ? playlist?.name ?? context.l10n.collectionPlaylist
        : null;
    final tracksToQueue = <Track>[];
    var skippedCount = 0;

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final isInHistory = existingHistoryKeys.contains(
        historyLookups[i].lookupKey,
      );
      final isInLocal =
          localLibState?.existsInLibrary(
            isrc: track.isrc,
            trackName: track.name,
            artistName: track.artistName,
          ) ??
          false;

      if (isInHistory || isInLocal) {
        skippedCount++;
      } else {
        tracksToQueue.add(track);
      }
    }

    if (tracksToQueue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.discographySkippedDownloaded(0, skippedCount),
          ),
        ),
      );
      return;
    }

    if (settings.askQualityBeforeDownload) {
      DownloadServicePicker.show(
        context,
        trackName: '${tracksToQueue.length} tracks',
        artistName: switch (widget.mode) {
          LibraryTracksFolderMode.wishlist => context.l10n.collectionWishlist,
          LibraryTracksFolderMode.loved => context.l10n.collectionLoved,
          LibraryTracksFolderMode.playlist => context.l10n.collectionPlaylist,
        },
        onSelect: (quality, service) {
          ref
              .read(downloadQueueProvider.notifier)
              .addMultipleToQueue(
                tracksToQueue,
                service,
                qualityOverride: quality,
                playlistName: playlistName,
              );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                skippedCount > 0
                    ? context.l10n.discographySkippedDownloaded(
                        tracksToQueue.length,
                        skippedCount,
                      )
                    : context.l10n.snackbarAddedTracksToQueue(
                        tracksToQueue.length,
                      ),
              ),
            ),
          );
        },
      );
    } else {
      ref
          .read(downloadQueueProvider.notifier)
          .addMultipleToQueue(
            tracksToQueue,
            settings.defaultService,
            playlistName: playlistName,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skippedCount > 0
                ? context.l10n.discographySkippedDownloaded(
                    tracksToQueue.length,
                    skippedCount,
                  )
                : context.l10n.snackbarAddedTracksToQueue(tracksToQueue.length),
          ),
        ),
      );
    }
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 10,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        context.l10n.libraryInLibrary,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
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

  String? _resolveRawCoverUrl(Track track) {
    final rawCover = track.coverUrl?.trim();
    if (rawCover != null &&
        rawCover.isNotEmpty &&
        !rawCover.startsWith('content://')) {
      return rawCover;
    }
    return null;
  }

  Widget _buildTrackCover(BuildContext context, String coverUrl, double size) {
    final isLocal =
        !coverUrl.startsWith('http://') && !coverUrl.startsWith('https://');
    final colorScheme = Theme.of(context).colorScheme;
    Widget placeholder() => Container(
      width: size,
      height: size,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant),
    );

    if (isLocal) {
      return Image.file(
        File(coverUrl),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return SizedBox(
            width: size,
            height: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                placeholder(),
                AnimatedOpacity(
                  opacity: frame == null ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: child,
                ),
              ],
            ),
          );
        },
        errorBuilder: (_, _, _) => placeholder(),
      );
    }

    return CachedNetworkImage(
      imageUrl: coverUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      memCacheWidth: (size * 2).toInt(),
      cacheManager: CoverCacheManager.instance,
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 90),
      placeholder: (_, _) => placeholder(),
      errorWidget: (_, _, _) => placeholder(),
    );
  }

  void _downloadTrack(BuildContext context, WidgetRef ref) {
    final track = entry.track;
    final settings = ref.read(settingsProvider);

    if (settings.askQualityBeforeDownload) {
      DownloadServicePicker.show(
        context,
        trackName: track.name,
        artistName: track.artistName,
        coverUrl: track.coverUrl,
        onSelect: (quality, service) {
          ref
              .read(downloadQueueProvider.notifier)
              .addToQueue(track, service, qualityOverride: quality);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.snackbarAddedToQueue(track.name)),
            ),
          );
        },
      );
    } else {
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
      ref.read(downloadQueueProvider.notifier).addToQueue(track, service);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.snackbarAddedToQueue(track.name))),
      );
    }
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

class _SelectionActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final ColorScheme colorScheme;

  const _SelectionActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        backgroundColor: onPressed != null
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        foregroundColor: onPressed != null
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
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
