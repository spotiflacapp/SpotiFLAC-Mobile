part of 'queue_tab.dart';

enum LibraryItemSource { downloaded, local }

class UnifiedLibraryItem {
  final String id;
  final String trackName;
  final String artistName;
  final String albumName;
  final String? coverUrl;
  final String? localCoverPath;
  final String filePath;
  final String? quality;
  final DateTime addedAt;
  final LibraryItemSource source;

  final DownloadHistoryItem? historyItem;
  final LocalLibraryItem? localItem;

  UnifiedLibraryItem({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.coverUrl,
    this.localCoverPath,
    required this.filePath,
    this.quality,
    required this.addedAt,
    required this.source,
    this.historyItem,
    this.localItem,
  });

  factory UnifiedLibraryItem.fromDownloadHistory(DownloadHistoryItem item) {
    String? quality;
    if (item.bitrate != null && item.bitrate! > 0) {
      quality = buildDisplayAudioQuality(
        bitrateKbps: item.bitrate,
        format: item.format,
      );
    } else if (item.bitDepth != null &&
        item.bitDepth! > 0 &&
        item.sampleRate != null) {
      quality = buildDisplayAudioQuality(
        bitDepth: item.bitDepth,
        sampleRate: item.sampleRate,
      );
    }
    quality ??= item.quality;
    return UnifiedLibraryItem(
      id: 'dl_${item.id}',
      trackName: item.trackName,
      artistName: item.artistName,
      albumName: item.albumName,
      coverUrl: item.coverUrl,
      filePath: item.filePath,
      quality: quality,
      addedAt: item.downloadedAt,
      source: LibraryItemSource.downloaded,
      historyItem: item,
    );
  }

  factory UnifiedLibraryItem.fromLocalLibrary(LocalLibraryItem item) {
    String? quality;
    if (item.bitrate != null && item.bitrate! > 0) {
      quality = buildDisplayAudioQuality(
        bitrateKbps: item.bitrate,
        format: item.format,
      );
    } else if (item.bitDepth != null &&
        item.bitDepth! > 0 &&
        item.sampleRate != null) {
      quality = buildDisplayAudioQuality(
        bitDepth: item.bitDepth,
        sampleRate: item.sampleRate,
      );
    }
    return UnifiedLibraryItem(
      id: 'local_${item.id}',
      trackName: item.trackName,
      artistName: item.artistName,
      albumName: item.albumName,
      coverUrl: null,
      localCoverPath: item.coverPath,
      filePath: item.filePath,
      quality: quality,
      addedAt: item.fileModTime != null
          ? DateTime.fromMillisecondsSinceEpoch(item.fileModTime!)
          : item.scannedAt,
      source: LibraryItemSource.local,
      localItem: item,
    );
  }

  bool get hasCover =>
      coverUrl != null ||
      (localCoverPath != null && localCoverPath!.isNotEmpty);

  String? get albumArtist => historyItem?.albumArtist ?? localItem?.albumArtist;

  String? get releaseDate => historyItem?.releaseDate ?? localItem?.releaseDate;

  String? get genre => historyItem?.genre ?? localItem?.genre;

  int? get trackNumber => historyItem?.trackNumber ?? localItem?.trackNumber;

  int? get discNumber => historyItem?.discNumber ?? localItem?.discNumber;

  String? get isrc => historyItem?.isrc ?? localItem?.isrc;

  String? get label => historyItem?.label ?? localItem?.label;

  String get searchKey =>
      '${trackName.toLowerCase()}|${artistName.toLowerCase()}|${albumName.toLowerCase()}';
  String get albumKey =>
      '${albumName.toLowerCase()}|${artistName.toLowerCase()}';

  /// Returns the collection key used to match this item against playlist
  /// entries. Uses the same logic as [trackCollectionKey] from the collections
  /// provider: prefer ISRC, fall back to source:id.
  String get collectionKey {
    if (historyItem != null) {
      final isrc = historyItem!.isrc?.trim();
      if (isrc != null && isrc.isNotEmpty) return 'isrc:${isrc.toUpperCase()}';
      final source = historyItem!.service.trim().isNotEmpty
          ? historyItem!.service.trim()
          : 'builtin';
      return '$source:${historyItem!.id}';
    }
    if (localItem != null) {
      final isrc = localItem!.isrc?.trim();
      if (isrc != null && isrc.isNotEmpty) return 'isrc:${isrc.toUpperCase()}';
      return 'local:${localItem!.id}';
    }
    return 'builtin:$id';
  }

  Track toTrack() {
    if (historyItem != null) {
      final h = historyItem!;
      return Track(
        id: h.id,
        name: h.trackName,
        artistName: h.artistName,
        albumName: h.albumName,
        albumArtist: h.albumArtist,
        coverUrl: h.coverUrl,
        isrc: h.isrc,
        duration: h.duration ?? 0,
        trackNumber: h.trackNumber,
        discNumber: h.discNumber,
        releaseDate: h.releaseDate,
        source: h.service,
      );
    }
    if (localItem != null) {
      final l = localItem!;
      return Track(
        id: l.id,
        name: l.trackName,
        artistName: l.artistName,
        albumName: l.albumName,
        albumArtist: l.albumArtist,
        coverUrl: l.coverPath,
        isrc: l.isrc,
        duration: l.duration ?? 0,
        trackNumber: l.trackNumber,
        discNumber: l.discNumber,
        releaseDate: l.releaseDate,
        source: 'local',
      );
    }
    return Track(
      id: id,
      name: trackName,
      artistName: artistName,
      albumName: albumName,
      coverUrl: coverUrl,
      duration: 0,
    );
  }
}

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
  final String albumName;
  final String artistName;
  final String? coverPath;
  final List<LocalLibraryItem> tracks;
  final int? trackCount;
  final DateTime latestScanned;
  final String searchKey;

  _GroupedLocalAlbum({
    required this.albumName,
    required this.artistName,
    this.coverPath,
    required this.tracks,
    this.trackCount,
    required this.latestScanned,
  }) : searchKey = '${albumName.toLowerCase()}|${artistName.toLowerCase()}';

  String get key => '$albumName|$artistName';

  int get displayTrackCount => trackCount ?? tracks.length;
}

class _HistoryStats {
  final Map<String, int> albumCounts;
  final List<_GroupedAlbum> groupedAlbums;
  final int albumCount;
  final int singleTracks;

  const _HistoryStats({
    required this.albumCounts,
    required this.groupedAlbums,
    required this.albumCount,
    required this.singleTracks,
  });
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
    filterMode: filterMode,
    searchQuery: searchQuery,
    source: filterSource,
    quality: filterQuality,
    format: filterFormat,
    metadata: filterMetadata,
    sortMode: sortMode,
    includeLocal: localLibraryEnabled,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _QueueLibraryPageRequest &&
          filterMode == other.filterMode &&
          limit == other.limit &&
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

final _queueLibraryPageProvider =
    FutureProvider.family<_QueueLibraryPageData, _QueueLibraryPageRequest>((
      ref,
      request,
    ) async {
      ref.watch(
        downloadHistoryProvider.select((state) => state.loadedIndexVersion),
      );
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
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

final _queueLibraryCountsProvider =
    FutureProvider.family<QueueLibraryCounts, _QueueLibraryCountsRequest>((
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

class _UnifiedCacheEntry {
  final List<DownloadHistoryItem> historyItems;
  final List<LocalLibraryItem> localItems;
  final Map<String, int> localAlbumCounts;
  final String query;
  final List<UnifiedLibraryItem> items;

  const _UnifiedCacheEntry({
    required this.historyItems,
    required this.localItems,
    required this.localAlbumCounts,
    required this.query,
    required this.items,
  });
}

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
      final exists = await fileExists(cleanPath);
      _pendingChecks.remove(cleanPath);
      _cache[cleanPath] = exists;
      final notifier = _notifiers[cleanPath];
      if (notifier != null && notifier.value != exists) {
        notifier.value = exists;
      }
    });
  }

  void dispose() {
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
    _alwaysMissingNotifier.dispose();
  }
}

bool _queueHasMetadataValue(String? value) {
  return value != null && value.trim().isNotEmpty;
}

String _queueNormalizedMetadataValue(String? value) {
  return value?.trim().toLowerCase() ?? '';
}

DateTime? _queueParseReleaseDate(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }

  final parsed = DateTime.tryParse(trimmed);
  if (parsed != null) {
    return parsed;
  }

  final yearMatch = RegExp(r'(\d{4})').firstMatch(trimmed);
  if (yearMatch == null) {
    return null;
  }

  final year = int.tryParse(yearMatch.group(1)!);
  if (year == null || year <= 0) {
    return null;
  }
  return DateTime(year);
}

bool _queueMatchesMetadataFilter({
  required String? filterMetadata,
  required String? artistName,
  required String? albumArtist,
  required String? releaseDate,
  required String? genre,
  required int? trackNumber,
  required int? discNumber,
  required String? isrc,
  required String? label,
}) {
  if (filterMetadata == null) {
    return true;
  }

  final hasArtist = _queueHasMetadataValue(artistName);
  final hasAlbumArtist = _queueHasMetadataValue(albumArtist);
  final hasReleaseDate = _queueParseReleaseDate(releaseDate) != null;
  final hasGenre = _queueHasMetadataValue(genre);
  final hasTrackNumber = trackNumber != null && trackNumber > 0;
  final hasDiscNumber = discNumber != null && discNumber > 0;
  final hasLabel = _queueHasMetadataValue(label);
  final hasIncorrectIsrc = _queueHasIncorrectIsrcFormat(isrc);
  final isComplete =
      hasArtist &&
      hasAlbumArtist &&
      hasReleaseDate &&
      hasGenre &&
      hasTrackNumber &&
      hasDiscNumber &&
      hasLabel &&
      !hasIncorrectIsrc;

  switch (filterMetadata) {
    case 'complete':
      return isComplete;
    case 'missing-any':
      return !isComplete;
    case 'missing-year':
      return !hasReleaseDate;
    case 'missing-genre':
      return !hasGenre;
    case 'missing-album-artist':
      return !hasAlbumArtist;
    case 'missing-track-number':
      return !hasTrackNumber;
    case 'missing-disc-number':
      return !hasDiscNumber;
    case 'missing-artist':
      return !hasArtist;
    case 'incorrect-isrc-format':
      return hasIncorrectIsrc;
    case 'missing-label':
      return !hasLabel;
    default:
      return true;
  }
}

bool _queueHasIncorrectIsrcFormat(String? isrc) {
  final raw = isrc?.trim() ?? '';
  if (raw.isEmpty) return false;
  final normalized = raw.toUpperCase().replaceAll(RegExp(r'[-\s]'), '');
  return !RegExp(r'^[A-Z]{2}[A-Z0-9]{3}\d{7}$').hasMatch(normalized);
}

bool _queueUnifiedItemMatchesMetadataFilter(
  UnifiedLibraryItem item,
  String? filterMetadata,
) {
  return _queueMatchesMetadataFilter(
    filterMetadata: filterMetadata,
    artistName: item.artistName,
    albumArtist: item.albumArtist,
    releaseDate: item.releaseDate,
    genre: item.genre,
    trackNumber: item.trackNumber,
    discNumber: item.discNumber,
    isrc: item.isrc,
    label: item.label,
  );
}

int _queueCompareOptionalText(
  String? left,
  String? right, {
  bool descending = false,
}) {
  final normalizedLeft = _queueNormalizedMetadataValue(left);
  final normalizedRight = _queueNormalizedMetadataValue(right);
  final leftEmpty = normalizedLeft.isEmpty;
  final rightEmpty = normalizedRight.isEmpty;

  if (leftEmpty && rightEmpty) {
    return 0;
  }
  if (leftEmpty) {
    return 1;
  }
  if (rightEmpty) {
    return -1;
  }

  final comparison = normalizedLeft.compareTo(normalizedRight);
  return descending ? -comparison : comparison;
}

int _queueCompareOptionalDate(
  DateTime? left,
  DateTime? right, {
  bool descending = false,
}) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }

  final comparison = left.compareTo(right);
  return descending ? -comparison : comparison;
}

Map<String, List<String>> _filterHistoryInIsolate(Map<String, Object> payload) {
  final entries = (payload['entries'] as List).cast<List<Object?>>();
  final albumCounts = Map<String, int>.from(payload['albumCounts'] as Map);
  final query = (payload['query'] as String?) ?? '';
  final hasQuery = query.isNotEmpty;

  final allIds = <String>[];
  final albumIds = <String>[];
  final singleIds = <String>[];

  for (final entry in entries) {
    final id = entry[0] as String;
    final albumKey = entry[1] as String;
    if (hasQuery) {
      final searchKey = entry[2] as String;
      if (!searchKey.contains(query)) {
        continue;
      }
    }

    allIds.add(id);
    final count = albumCounts[albumKey] ?? 0;
    if (count > 1) {
      albumIds.add(id);
    } else if (count == 1) {
      singleIds.add(id);
    }
  }

  return {'all': allIds, 'albums': albumIds, 'singles': singleIds};
}
