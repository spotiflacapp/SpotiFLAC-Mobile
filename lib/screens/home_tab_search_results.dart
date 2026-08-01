// ignore_for_file: invalid_use_of_protected_member
part of 'home_tab.dart';

extension _HomeTabSearchResultsUI on _HomeTabState {
  Widget _buildErrorWidget(String error, ColorScheme colorScheme) {
    final l10n = context.l10n;
    final isRateLimit =
        error.contains('429') ||
        error.toLowerCase().contains('rate limit') ||
        error.toLowerCase().contains('too many requests');
    final isUrlNotRecognized = error == 'url_not_recognized';
    // Re-runs the current query. Skipped for an unrecognized URL, where the
    // outcome is deterministic and retrying would just fail again.
    final retry = _urlController.text.trim().isEmpty
        ? null
        : () => _performSearch(_urlController.text.trim());

    if (isRateLimit) {
      return ErrorCard(error: error, colorScheme: colorScheme, onRetry: retry);
    }

    if (isUrlNotRecognized) {
      return Card(
        elevation: 0,
        color: colorScheme.errorContainer.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: context.tokens.borderRadiusCard,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.link_off, color: colorScheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.errorUrlNotRecognized,
                      style: TextStyle(
                        color: colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.errorUrlNotRecognizedMessage,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ErrorCard(
      error: l10n.errorUrlFetchFailed,
      colorScheme: colorScheme,
      onRetry: retry,
    );
  }

  Widget _buildEmptySearchResultWidget(ColorScheme colorScheme) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surfaceContainerHighest,
            ),
            child: Icon(
              Icons.manage_search,
              size: 46,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.errorNoTracksFound,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.searchEmptyResultSubtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  String _sortOptionLabel(HomeSearchSortOption option) {
    switch (option) {
      case HomeSearchSortOption.defaultOrder:
        return context.l10n.searchSortDefault;
      case HomeSearchSortOption.titleAsc:
        return context.l10n.searchSortTitleAZ;
      case HomeSearchSortOption.titleDesc:
        return context.l10n.searchSortTitleZA;
      case HomeSearchSortOption.artistAsc:
        return context.l10n.searchSortArtistAZ;
      case HomeSearchSortOption.artistDesc:
        return context.l10n.searchSortArtistZA;
      case HomeSearchSortOption.durationAsc:
        return context.l10n.searchSortDurationShort;
      case HomeSearchSortOption.durationDesc:
        return context.l10n.searchSortDurationLong;
      case HomeSearchSortOption.dateAsc:
        return context.l10n.searchSortDateOldest;
      case HomeSearchSortOption.dateDesc:
        return context.l10n.searchSortDateNewest;
    }
  }

  void _showSortOptions(ColorScheme colorScheme) {
    var tempSort = _searchSortOption;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: colorScheme.surfaceContainerLow,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppSheetHandle(),
                  Row(
                    children: [
                      Text(
                        context.l10n.searchSortTitle,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setSheetState(
                          () => tempSort = HomeSearchSortOption.defaultOrder,
                        ),
                        child: Text(context.l10n.libraryFilterReset),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: HomeSearchSortOption.values.map((option) {
                      return FilterChip(
                        label: Text(_sortOptionLabel(option)),
                        selected: tempSort == option,
                        showCheckmark: false,
                        onSelected: (_) =>
                            setSheetState(() => tempSort = option),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (_searchSortOption != tempSort) {
                          setState(() {
                            _searchSortOption = tempSort;
                          });
                        }
                      },
                      child: Text(context.l10n.libraryFilterApply),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  ({List<Track> tracks, List<int> indexes}) _sortTrackResults(
    List<Track> tracks,
    List<int> indexes,
  ) {
    if (tracks.isEmpty ||
        _searchSortOption == HomeSearchSortOption.defaultOrder) {
      return (tracks: tracks, indexes: indexes);
    }
    if (identical(tracks, _sortedTracksSource) &&
        identical(indexes, _sortedTrackIndexesSource) &&
        _sortedTracksMode == _searchSortOption &&
        _sortedTracksCache != null &&
        _sortedTrackIndexesCache != null) {
      return (tracks: _sortedTracksCache!, indexes: _sortedTrackIndexesCache!);
    }
    final paired = List.generate(
      tracks.length,
      (i) => (tracks[i], indexes[i]),
      growable: false,
    );
    final sortedPairs = sortHomeSearchItems<(Track, int)>(
      items: paired,
      option: _searchSortOption,
      nameOf: (p) => p.$1.name,
      artistOf: (p) => p.$1.artistName,
      durationOf: (p) => p.$1.duration,
      dateOf: (p) => p.$1.releaseDate,
    );
    final sortedTracks = sortedPairs.map((p) => p.$1).toList(growable: false);
    final sortedIndexes = sortedPairs.map((p) => p.$2).toList(growable: false);
    _sortedTracksSource = tracks;
    _sortedTrackIndexesSource = indexes;
    _sortedTracksMode = _searchSortOption;
    _sortedTracksCache = sortedTracks;
    _sortedTrackIndexesCache = sortedIndexes;
    return (tracks: sortedTracks, indexes: sortedIndexes);
  }

  List<Widget> _buildSearchResults({
    required List<Track> tracks,
    required bool isLoading,
    required String? error,
    required ColorScheme colorScheme,
    required bool hasResults,
    required bool showEmptySearchResult,
    required String? searchExtensionId,
    required bool showLocalLibraryIndicator,
    required Map<String, (double, double)> thumbnailSizesByExtensionId,
  }) {
    final hasActualData = tracks.isNotEmpty;

    if (!hasActualData && isLoading) {
      return [const SliverToBoxAdapter(child: HomeSearchSkeleton())];
    }
    if (!hasResults) {
      return [const SliverToBoxAdapter(child: SizedBox.shrink())];
    }

    final buckets = _getSearchResultBuckets(tracks);
    final realTracks = buckets.realTracks;
    final realTrackIndexes = buckets.realTrackIndexes;
    final albumItems = buckets.albumItems;
    final playlistItems = buckets.playlistItems;
    final artistItems = buckets.artistItems;

    final sortedTrackResults = _sortTrackResults(realTracks, realTrackIndexes);
    final sortedTracks = sortedTrackResults.tracks;
    final sortedTrackIndexes = sortedTrackResults.indexes;

    final slivers = <Widget>[
      if (error != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildErrorWidget(error, colorScheme),
          ),
        ),
      if (isLoading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(),
          ),
        ),
      if (showEmptySearchResult && !hasActualData)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
              child: _buildEmptySearchResultWidget(colorScheme),
            ),
          ),
        ),
    ];

    bool sortButtonShown = false;

    if (artistItems.isNotEmpty) {
      slivers.addAll(
        _buildVirtualizedResultSection(
          title: context.l10n.searchArtists,
          itemCount: artistItems.length,
          colorScheme: colorScheme,
          showSortButton: !sortButtonShown,
          itemBuilder: (index, showDivider) => _CollectionItemWidget(
            key: ValueKey('artist-${artistItems[index].id}'),
            item: artistItems[index],
            showDivider: showDivider,
            onTap: () => _navigateToExtensionArtist(artistItems[index]),
          ),
        ),
      );
      sortButtonShown = true;
    }

    if (albumItems.isNotEmpty) {
      slivers.addAll(
        _buildVirtualizedResultSection(
          title: context.l10n.searchAlbums,
          itemCount: albumItems.length,
          colorScheme: colorScheme,
          showSortButton: !sortButtonShown,
          itemBuilder: (index, showDivider) => _CollectionItemWidget(
            key: ValueKey('album-${albumItems[index].id}'),
            item: albumItems[index],
            showDivider: showDivider,
            onTap: () => _navigateToExtensionAlbum(albumItems[index]),
          ),
        ),
      );
      sortButtonShown = true;
    }

    if (playlistItems.isNotEmpty) {
      slivers.addAll(
        _buildVirtualizedResultSection(
          title: context.l10n.searchPlaylists,
          itemCount: playlistItems.length,
          colorScheme: colorScheme,
          showSortButton: !sortButtonShown,
          itemBuilder: (index, showDivider) => _CollectionItemWidget(
            key: ValueKey('playlist-${playlistItems[index].id}'),
            item: playlistItems[index],
            showDivider: showDivider,
            onTap: () => _navigateToExtensionPlaylist(playlistItems[index]),
          ),
        ),
      );
      sortButtonShown = true;
    }

    if (sortedTracks.isNotEmpty) {
      final historyLookups = sortedTracks
          .map(historyLookupForTrack)
          .toList(growable: false);
      final existingHistoryKeys = ref
          .watch(
            downloadHistoryBatchExistsProvider(
              HistoryBatchLookupRequest(historyLookups),
            ),
          )
          .maybeWhen(data: (keys) => keys, orElse: () => const <String>{});
      slivers.addAll(
        _buildVirtualizedResultSection(
          title: context.l10n.searchSongs,
          itemCount: sortedTracks.length,
          colorScheme: colorScheme,
          showSortButton: !sortButtonShown,
          itemBuilder: (index, showDivider) => _TrackItemWithStatus(
            key: ValueKey(sortedTracks[index].id),
            track: sortedTracks[index],
            index: sortedTrackIndexes[index],
            showDivider: showDivider,
            onDownload: ({bool forceQualityPicker = false}) => _downloadTrack(
              sortedTrackIndexes[index],
              forceQualityPicker: forceQualityPicker,
            ),
            searchExtensionId: searchExtensionId,
            showLocalLibraryIndicator: showLocalLibraryIndicator,
            thumbnailSizesByExtensionId: thumbnailSizesByExtensionId,
            isInHistory: existingHistoryKeys.contains(
              historyLookups[index].lookupKey,
            ),
          ),
        ),
      );
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 16)));
    return slivers;
  }

  List<Widget> _buildVirtualizedResultSection({
    required String title,
    required int itemCount,
    required ColorScheme colorScheme,
    required Widget Function(int index, bool showDivider) itemBuilder,
    bool showSortButton = false,
  }) {
    final sectionColor = Theme.of(context).brightness == Brightness.dark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.08),
            colorScheme.surface,
          )
        : colorScheme.surfaceContainerHighest;

    return [
      SliverToBoxAdapter(
        child: Padding(
          // Aligned with the clamped result list below on wide screens.
          padding:
              EdgeInsets.fromLTRB(16, 8, 8, 8) +
              EdgeInsets.symmetric(horizontal: wideListInset(context)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (showSortButton)
                SizedBox(
                  height: 32,
                  child: TextButton.icon(
                    onPressed: () => _showSortOptions(colorScheme),
                    icon: Icon(
                      Icons.swap_vert,
                      size: 18,
                      color:
                          _searchSortOption != HomeSearchSortOption.defaultOrder
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    label: Text(
                      _searchSortOption != HomeSearchSortOption.defaultOrder
                          ? _sortOptionLabel(_searchSortOption)
                          : context.l10n.libraryFilterSort,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color:
                            _searchSortOption !=
                                HomeSearchSortOption.defaultOrder
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: wideListInset(context)),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final isFirst = index == 0;
            final isLast = index == itemCount - 1;
            return StaggeredListItem(
              index: index,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: sectionColor,
                  borderRadius: BorderRadius.vertical(
                    top: isFirst ? const Radius.circular(20) : Radius.zero,
                    bottom: isLast ? const Radius.circular(20) : Radius.zero,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: itemBuilder(index, !isLast),
                ),
              ),
            );
          }, childCount: itemCount),
        ),
      ),
    ];
  }

  void _navigateToExtensionAlbum(Track albumItem) async {
    final extensionId = albumItem.source;
    if (extensionId == null || extensionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.errorMissingExtensionSource('album')),
        ),
      );
      return;
    }

    ref.read(settingsProvider.notifier).setHasSearchedBefore();

    ref
        .read(recentAccessProvider.notifier)
        .recordAlbumAccess(
          id: albumItem.id,
          name: albumItem.name,
          artistName: albumItem.artistName,
          imageUrl: albumItem.coverUrl,
          providerId: extensionId,
        );

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => ExtensionAlbumScreen(
          extensionId: extensionId,
          albumId: albumItem.id,
          albumName: albumItem.name,
          coverUrl: albumItem.coverUrl,
          initialAlbumType: albumItem.albumType,
          initialTotalTracks: albumItem.totalTracks,
        ),
      ),
    );
  }

  void _navigateToExtensionPlaylist(Track playlistItem) async {
    final extensionId = playlistItem.source;
    if (extensionId == null || extensionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.errorMissingExtensionSource('playlist')),
        ),
      );
      return;
    }

    ref.read(settingsProvider.notifier).setHasSearchedBefore();

    ref
        .read(recentAccessProvider.notifier)
        .recordPlaylistAccess(
          id: playlistItem.id,
          name: playlistItem.name,
          ownerName: playlistItem.artistName,
          imageUrl: playlistItem.coverUrl,
          providerId: extensionId,
        );

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => ExtensionPlaylistScreen(
          extensionId: extensionId,
          playlistId: playlistItem.id,
          playlistName: playlistItem.name,
          coverUrl: playlistItem.coverUrl,
        ),
      ),
    );
  }

  void _navigateToExtensionArtist(Track artistItem) {
    final extensionId = artistItem.source;
    if (extensionId == null || extensionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.errorMissingExtensionSource('artist')),
        ),
      );
      return;
    }

    ref.read(settingsProvider.notifier).setHasSearchedBefore();

    ref
        .read(recentAccessProvider.notifier)
        .recordArtistAccess(
          id: artistItem.id,
          name: artistItem.name,
          imageUrl: artistItem.coverUrl,
          providerId: extensionId,
        );

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => ExtensionArtistScreen(
          extensionId: extensionId,
          artistId: artistItem.id,
          artistName: artistItem.name,
          coverUrl: artistItem.coverUrl,
        ),
      ),
    );
  }

  String _getSearchHint() {
    final settings = ref.read(settingsProvider);
    final extState = ref.read(extensionProvider);
    final searchProvider = HomeSearchProviderPolicy.resolveProvider(
      settings.searchProvider,
      extState.extensions,
    );

    if (!extState.isInitialized) {
      return context.l10n.homeSearchHintDefault;
    }

    if (searchProvider != null && searchProvider.isNotEmpty) {
      final ext = extState.extensions
          .where((e) => e.id == searchProvider)
          .firstOrNull;
      if (ext != null && ext.enabled) {
        if (ext.searchBehavior?.placeholder != null) {
          return ext.searchBehavior!.placeholder!;
        }
        return context.l10n.homeSearchHintProvider(ext.displayName);
      }
    }
    return context.l10n.homeSearchHintDefault;
  }

  Widget _buildSearchFilterBar(
    List<SearchFilter> filters,
    String? selectedFilter,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(context.l10n.historyFilterAll),
                selected: selectedFilter == 'all',
                onSelected: (_) {
                  ref.read(trackProvider.notifier).setSearchFilter('all');
                  _triggerSearchWithFilter('all');
                },
                showCheckmark: false,
              ),
            ),
            ...filters.map((filter) {
              final isSelected = selectedFilter == filter.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(filter.label ?? filter.id),
                  selected: isSelected,
                  onSelected: (_) {
                    ref.read(trackProvider.notifier).setSearchFilter(filter.id);
                    _triggerSearchWithFilter(filter.id);
                  },
                  showCheckmark: false,
                  avatar: filter.icon != null
                      ? Icon(_getFilterIcon(filter.icon!), size: 18)
                      : null,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  IconData _getFilterIcon(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'music':
      case 'track':
      case 'song':
        return Icons.music_note;
      case 'album':
        return Icons.album;
      case 'artist':
        return Icons.person;
      case 'playlist':
        return Icons.playlist_play;
      case 'video':
        return Icons.video_library;
      case 'podcast':
        return Icons.podcasts;
      default:
        return Icons.search;
    }
  }

  void _triggerSearchWithFilter(String? filter) {
    final text = _urlController.text.trim();
    if (text.isEmpty || text.length < _HomeTabState._minLiveSearchChars) return;
    if (looksLikeUrlOrSpotifyUri(text)) return;

    _lastSearchQuery = null;
    _performSearch(text, filterOverride: filter);
  }

  Widget _buildSearchBar(ColorScheme colorScheme) {
    final hasText = _urlController.text.isNotEmpty;

    return TextField(
      controller: _urlController,
      focusNode: _searchFocusNode,
      autofocus: false,
      decoration: InputDecoration(
        hintText: _getSearchHint(),
        filled: true,
        fillColor: settingsGroupColor(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        prefixIcon: _SearchProviderDropdown(
          onProviderChanged: () {
            _lastSearchQuery = null;
            ref.read(trackProvider.notifier).setSearchFilter(null);
            setState(() {});
            final text = _urlController.text.trim();
            if (text.isNotEmpty &&
                text.length >= _HomeTabState._minLiveSearchChars) {
              _performSearch(text);
            }
          },
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasText)
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: _clearAndRefresh,
                tooltip: context.l10n.dialogClear,
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.file_upload_outlined),
                onPressed: _isCsvImporting
                    ? null
                    : () => _importCsv(context, ref),
                tooltip: context.l10n.homeImportCsvTooltip,
              ),
              IconButton(
                icon: const Icon(Icons.paste),
                onPressed: _pasteFromClipboard,
                tooltip: context.l10n.actionPaste,
              ),
            ],
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
      onSubmitted: (_) => _onSearchSubmitted(),
      onTapOutside: (_) {
        FocusScope.of(context).unfocus();
      },
    );
  }

  void _onSearchSubmitted() {
    _liveSearchDebounce?.cancel();
    _pendingLiveSearchQuery = null;

    final text = _urlController.text.trim();
    if (text.isEmpty) return;

    if (looksLikeUrlOrSpotifyUri(text)) {
      _fetchMetadata();
      _searchFocusNode.unfocus();
      return;
    }

    if (text.length >= 2) {
      _performSearch(text);
    }
    _searchFocusNode.unfocus();
  }
}
