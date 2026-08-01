part of 'queue_tab.dart';

class _GroupedAlbum {
  final String albumName;
  final String artistName;
  final String? coverUrl;
  final String sampleFilePath;
  final List<DownloadHistoryItem> tracks;
  final int? trackCount;
  final DateTime latestDownload;
  final String searchKey;

  _GroupedAlbum({
    required this.albumName,
    required this.artistName,
    this.coverUrl,
    required this.sampleFilePath,
    required this.tracks,
    this.trackCount,
    required this.latestDownload,
  }) : searchKey = '${albumName.toLowerCase()}|${artistName.toLowerCase()}';

  String get key => '$albumName|$artistName';

  int get displayTrackCount => trackCount ?? tracks.length;
}

class _GroupedLocalAlbum {
  final String albumKey;
  final String albumName;
  final String artistName;
  final String? coverPath;
  final List<LocalLibraryItem> tracks;
  final int? trackCount;
  final DateTime latestScanned;
  final String searchKey;

  _GroupedLocalAlbum({
    required this.albumKey,
    required this.albumName,
    required this.artistName,
    this.coverPath,
    required this.tracks,
    this.trackCount,
    required this.latestScanned,
  }) : searchKey = '${albumName.toLowerCase()}|${artistName.toLowerCase()}';

  String get key => albumKey;

  int get displayTrackCount => trackCount ?? tracks.length;
}

class _FilterContentData {
  final List<DownloadHistoryItem> historyItems;
  final List<UnifiedLibraryItem> unifiedItems;
  final List<UnifiedLibraryItem> filteredUnifiedItems;
  final List<_GroupedAlbum> filteredGroupedAlbums;
  final List<_GroupedLocalAlbum> filteredGroupedLocalAlbums;
  final bool showFilteringIndicator;
  final int? totalTrackCountOverride;
  final int? totalAlbumCountOverride;

  const _FilterContentData({
    required this.historyItems,
    required this.unifiedItems,
    required this.filteredUnifiedItems,
    required this.filteredGroupedAlbums,
    required this.filteredGroupedLocalAlbums,
    required this.showFilteringIndicator,
    this.totalTrackCountOverride,
    this.totalAlbumCountOverride,
  });

  int get totalTrackCount =>
      totalTrackCountOverride ?? filteredUnifiedItems.length;
  int get totalAlbumCount =>
      totalAlbumCountOverride ??
      filteredGroupedAlbums.length + filteredGroupedLocalAlbums.length;
}

class _QueueLibraryPageRequest {
  final String filterMode;
  final int limit;
  final int offset;
  final String searchQuery;
  final String? filterSource;
  final String? filterQuality;
  final String? filterFormat;
  final String? filterMetadata;
  final String sortMode;
  final bool localLibraryEnabled;

  const _QueueLibraryPageRequest({
    required this.filterMode,
    required this.limit,
    required this.offset,
    required this.searchQuery,
    required this.filterSource,
    required this.filterQuality,
    required this.filterFormat,
    required this.filterMetadata,
    required this.sortMode,
    required this.localLibraryEnabled,
  });

  QueueLibraryDbQuery toDbQuery() => QueueLibraryDbQuery(
    limit: limit,
    offset: offset,
    filterMode: filterMode,
    searchQuery: searchQuery,
    source: filterSource,
    quality: filterQuality,
    format: filterFormat,
    metadata: filterMetadata,
    sortMode: sortMode,
    includeLocal: localLibraryEnabled,
  );

  bool get allowsInMemoryHistoryFallback =>
      offset == 0 &&
      searchQuery.trim().isEmpty &&
      filterSource != 'local' &&
      filterQuality == null &&
      filterFormat == null &&
      filterMetadata == null &&
      sortMode == 'latest' &&
      (filterMode == 'all' ||
          filterMode == 'albums' ||
          filterMode == 'singles');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _QueueLibraryPageRequest &&
          filterMode == other.filterMode &&
          limit == other.limit &&
          offset == other.offset &&
          searchQuery == other.searchQuery &&
          filterSource == other.filterSource &&
          filterQuality == other.filterQuality &&
          filterFormat == other.filterFormat &&
          filterMetadata == other.filterMetadata &&
          sortMode == other.sortMode &&
          localLibraryEnabled == other.localLibraryEnabled;

  @override
  int get hashCode => Object.hash(
    filterMode,
    limit,
    offset,
    searchQuery,
    filterSource,
    filterQuality,
    filterFormat,
    filterMetadata,
    sortMode,
    localLibraryEnabled,
  );
}

class _QueueLibraryCountsRequest {
  final String searchQuery;
  final String? filterSource;
  final String? filterQuality;
  final String? filterFormat;
  final String? filterMetadata;
  final bool localLibraryEnabled;

  const _QueueLibraryCountsRequest({
    required this.searchQuery,
    required this.filterSource,
    required this.filterQuality,
    required this.filterFormat,
    required this.filterMetadata,
    required this.localLibraryEnabled,
  });

  QueueLibraryDbQuery toDbQuery() => QueueLibraryDbQuery(
    searchQuery: searchQuery,
    source: filterSource,
    quality: filterQuality,
    format: filterFormat,
    metadata: filterMetadata,
    includeLocal: localLibraryEnabled,
  );

  bool get allowsInMemoryHistoryFallback =>
      searchQuery.trim().isEmpty &&
      filterSource != 'local' &&
      filterQuality == null &&
      filterFormat == null &&
      filterMetadata == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _QueueLibraryCountsRequest &&
          searchQuery == other.searchQuery &&
          filterSource == other.filterSource &&
          filterQuality == other.filterQuality &&
          filterFormat == other.filterFormat &&
          filterMetadata == other.filterMetadata &&
          localLibraryEnabled == other.localLibraryEnabled;

  @override
  int get hashCode => Object.hash(
    searchQuery,
    filterSource,
    filterQuality,
    filterFormat,
    filterMetadata,
    localLibraryEnabled,
  );
}

class _QueueLibraryPageData {
  final List<UnifiedLibraryItem> items;
  final List<DownloadHistoryItem> historyItems;
  final List<LocalLibraryItem> localItems;
  final List<_GroupedAlbum> groupedAlbums;
  final List<_GroupedLocalAlbum> groupedLocalAlbums;

  const _QueueLibraryPageData({
    this.items = const [],
    this.historyItems = const [],
    this.localItems = const [],
    this.groupedAlbums = const [],
    this.groupedLocalAlbums = const [],
  });

  bool get isEmpty =>
      items.isEmpty &&
      historyItems.isEmpty &&
      localItems.isEmpty &&
      groupedAlbums.isEmpty &&
      groupedLocalAlbums.isEmpty;

  factory _QueueLibraryPageData.fromHistorySnapshot(
    List<DownloadHistoryItem> historyItems, {
    required String filterMode,
    required int limit,
  }) {
    final albumTracks = <String, List<DownloadHistoryItem>>{};
    for (final item in historyItems) {
      final albumKey = LibraryDatabase.albumKeyFor(
        item.albumName,
        item.albumArtist,
        item.artistName,
      );
      albumTracks.putIfAbsent(albumKey, () => []).add(item);
    }

    if (filterMode == 'albums') {
      final albums = <_GroupedAlbum>[];
      for (final tracks in albumTracks.values) {
        if (tracks.length <= 1) continue;
        final latest = tracks
            .map((item) => item.downloadedAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        final sample = tracks.first;
        String? coverUrl;
        for (final track in tracks) {
          final candidate = track.coverUrl?.trim();
          if (candidate != null && candidate.isNotEmpty) {
            coverUrl = candidate;
            break;
          }
        }
        albums.add(
          _GroupedAlbum(
            albumName: sample.albumName,
            artistName: sample.albumArtist?.trim().isNotEmpty == true
                ? sample.albumArtist!
                : sample.artistName,
            coverUrl: coverUrl,
            sampleFilePath: sample.filePath,
            tracks: List.unmodifiable(tracks),
            trackCount: tracks.length,
            latestDownload: latest,
          ),
        );
      }
      albums.sort((a, b) => b.latestDownload.compareTo(a.latestDownload));
      return _QueueLibraryPageData(
        groupedAlbums: albums.take(limit).toList(growable: false),
      );
    }

    final selectedHistory =
        (filterMode == 'singles'
                ? historyItems.where((item) {
                    final albumKey = LibraryDatabase.albumKeyFor(
                      item.albumName,
                      item.albumArtist,
                      item.artistName,
                    );
                    return albumTracks[albumKey]?.length == 1;
                  })
                : historyItems)
            .take(limit)
            .toList(growable: false);
    return _QueueLibraryPageData(
      items: selectedHistory
          .map(UnifiedLibraryItem.fromDownloadHistory)
          .toList(growable: false),
      historyItems: selectedHistory,
    );
  }

  factory _QueueLibraryPageData.combine(List<_QueueLibraryPageData> pages) {
    if (pages.isEmpty) return const _QueueLibraryPageData();
    if (pages.length == 1) return pages.first;

    final items = <UnifiedLibraryItem>[];
    final historyItems = <DownloadHistoryItem>[];
    final localItems = <LocalLibraryItem>[];
    final groupedAlbums = <_GroupedAlbum>[];
    final groupedLocalAlbums = <_GroupedLocalAlbum>[];

    for (final page in pages) {
      items.addAll(page.items);
      historyItems.addAll(page.historyItems);
      localItems.addAll(page.localItems);
      groupedAlbums.addAll(page.groupedAlbums);
      groupedLocalAlbums.addAll(page.groupedLocalAlbums);
    }

    return _QueueLibraryPageData(
      items: items,
      historyItems: historyItems,
      localItems: localItems,
      groupedAlbums: groupedAlbums,
      groupedLocalAlbums: groupedLocalAlbums,
    );
  }

  _FilterContentData toFilterContentData(
    LibraryCollectionsState collectionState, {
    int? totalTrackCount,
    int? totalAlbumCount,
  }) {
    final filteredItems = !collectionState.hasPlaylistTracks
        ? items
        : items
              .where(
                (item) =>
                    !collectionState.isTrackInAnyPlaylist(item.collectionKey),
              )
              .toList(growable: false);
    return _FilterContentData(
      historyItems: historyItems,
      unifiedItems: items,
      filteredUnifiedItems: filteredItems,
      filteredGroupedAlbums: groupedAlbums,
      filteredGroupedLocalAlbums: groupedLocalAlbums,
      showFilteringIndicator: false,
      totalTrackCountOverride: totalTrackCount,
      totalAlbumCountOverride: totalAlbumCount,
    );
  }
}

QueueLibraryCounts _historySnapshotCounts(
  List<DownloadHistoryItem> items, {
  required int persistedTotalCount,
}) {
  final albumCounts = <String, int>{};
  for (final item in items) {
    final key = LibraryDatabase.albumKeyFor(
      item.albumName,
      item.albumArtist,
      item.artistName,
    );
    albumCounts[key] = (albumCounts[key] ?? 0) + 1;
  }
  final albumCount = albumCounts.values.where((count) => count > 1).length;
  final singleTrackCount = albumCounts.values
      .where((count) => count == 1)
      .length;
  return QueueLibraryCounts(
    allTrackCount: persistedTotalCount > items.length
        ? persistedTotalCount
        : items.length,
    albumCount: albumCount,
    singleTrackCount: singleTrackCount,
  );
}

final _queueLibraryPageProvider = FutureProvider.autoDispose
    .family<_QueueLibraryPageData, _QueueLibraryPageRequest>((
      ref,
      request,
    ) async {
      ref.watch(
        downloadHistoryProvider.select((state) => state.loadedIndexVersion),
      );
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      // Playlists render from libraryCollectionsProvider, not the DB.
      if (request.filterMode == 'playlists') {
        return const _QueueLibraryPageData();
      }
      final dbQuery = request.toDbQuery();
      if (request.filterMode == 'albums') {
        final rows = await LibraryDatabase.instance.getQueueAlbumPage(dbQuery);
        final groupedAlbums = <_GroupedAlbum>[];
        final groupedLocalAlbums = <_GroupedLocalAlbum>[];
        for (final row in rows) {
          final source = row['queue_source'] as String? ?? '';
          final latestMillis = (row['sort_added'] as num?)?.toInt() ?? 0;
          final latest = DateTime.fromMillisecondsSinceEpoch(latestMillis);
          if (source == 'local') {
            groupedLocalAlbums.add(
              _GroupedLocalAlbum(
                albumKey: row['album_key'] as String? ?? '',
                albumName: row['album_name'] as String? ?? '',
                artistName: row['artist_name'] as String? ?? '',
                coverPath: row['cover_path'] as String?,
                tracks: const [],
                trackCount: (row['track_count'] as num?)?.toInt() ?? 0,
                latestScanned: latest,
              ),
            );
          } else if (source == 'downloaded') {
            groupedAlbums.add(
              _GroupedAlbum(
                albumName: row['album_name'] as String? ?? '',
                artistName: row['artist_name'] as String? ?? '',
                coverUrl: row['cover_url'] as String?,
                sampleFilePath: row['sample_file_path'] as String? ?? '',
                tracks: const [],
                trackCount: (row['track_count'] as num?)?.toInt() ?? 0,
                latestDownload: latest,
              ),
            );
          }
        }
        return _QueueLibraryPageData(
          groupedAlbums: groupedAlbums,
          groupedLocalAlbums: groupedLocalAlbums,
        );
      }

      final rows = await LibraryDatabase.instance.getQueueTrackPage(dbQuery);
      final items = <UnifiedLibraryItem>[];
      final historyItems = <DownloadHistoryItem>[];
      final localItems = <LocalLibraryItem>[];
      for (final row in rows) {
        final source = row['source'] as String? ?? '';
        final itemJson = Map<String, dynamic>.from(row['item'] as Map);
        if (source == 'local') {
          final item = LocalLibraryItem.fromJson(itemJson);
          localItems.add(item);
          items.add(UnifiedLibraryItem.fromLocalLibrary(item));
        } else if (source == 'downloaded') {
          final item = DownloadHistoryItem.fromJson(itemJson);
          historyItems.add(item);
          items.add(UnifiedLibraryItem.fromDownloadHistory(item));
        }
      }
      return _QueueLibraryPageData(
        items: items,
        historyItems: historyItems,
        localItems: localItems,
      );
    });

final _queueLibraryCountsProvider = FutureProvider.autoDispose
    .family<QueueLibraryCounts, _QueueLibraryCountsRequest>((
      ref,
      request,
    ) async {
      ref.watch(
        downloadHistoryProvider.select((state) => state.loadedIndexVersion),
      );
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      return LibraryDatabase.instance.getQueueCounts(request.toDbQuery());
    });

class _QueueItemIdsSnapshot {
  final List<String> ids;

  const _QueueItemIdsSnapshot(this.ids);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _QueueItemIdsSnapshot && listEquals(ids, other.ids);

  @override
  int get hashCode => Object.hashAll(ids);
}

class _FileExistsListenableCache {
  static const int _maxCacheSize = 500;

  final Map<String, bool> _cache = {};
  final Map<String, int> _missCounts = {};
  final Map<String, ValueNotifier<bool>> _notifiers = {};
  final ValueNotifier<bool> _alwaysMissingNotifier = ValueNotifier(false);
  final Set<String> _pendingChecks = {};

  ValueListenable<bool> listenable(String? filePath) {
    final cleanPath = DownloadedEmbeddedCoverResolver.cleanFilePath(filePath);
    if (cleanPath.isEmpty) return _alwaysMissingNotifier;

    final existingNotifier = _notifiers[cleanPath];
    if (existingNotifier != null) {
      final cached = _cache[cleanPath];
      if (cached != null && existingNotifier.value != cached) {
        existingNotifier.value = cached;
      } else if (cached == null) {
        _startCheck(cleanPath);
      }
      return existingNotifier;
    }

    if (_notifiers.length >= _maxCacheSize) {
      final oldestKey = _notifiers.keys.first;
      _notifiers.remove(oldestKey)?.dispose();
      _cache.remove(oldestKey);
    }

    final notifier = ValueNotifier<bool>(_cache[cleanPath] ?? true);
    _notifiers[cleanPath] = notifier;
    _startCheck(cleanPath);
    return notifier;
  }

  void _startCheck(String cleanPath) {
    if (_pendingChecks.contains(cleanPath)) {
      return;
    }

    final cached = _cache[cleanPath];
    if (cached != null) {
      final notifier = _notifiers[cleanPath];
      if (notifier != null && notifier.value != cached) {
        notifier.value = cached;
      }
      return;
    }

    _pendingChecks.add(cleanPath);
    Future.microtask(() async {
      bool exists;
      try {
        exists = await fileExists(cleanPath);
      } catch (_) {
        _pendingChecks.remove(cleanPath);
        Timer(const Duration(milliseconds: 700), () => _startCheck(cleanPath));
        return;
      }
      _pendingChecks.remove(cleanPath);
      if (exists) {
        _missCounts.remove(cleanPath);
        _cache[cleanPath] = true;
      } else {
        final misses = (_missCounts[cleanPath] ?? 0) + 1;
        _missCounts[cleanPath] = misses;
        if (misses < 2) {
          Timer(
            const Duration(milliseconds: 700),
            () => _startCheck(cleanPath),
          );
          return;
        }
        _cache[cleanPath] = false;
      }
      final notifier = _notifiers[cleanPath];
      final value = _cache[cleanPath] ?? true;
      if (notifier != null && notifier.value != value) {
        notifier.value = value;
      }
    });
  }

  void dispose() {
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
    _missCounts.clear();
    _alwaysMissingNotifier.dispose();
  }
}
