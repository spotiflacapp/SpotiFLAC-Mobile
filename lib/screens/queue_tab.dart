import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/services/ffmpeg_service.dart';
import 'package:spotiflac_android/services/replaygain_service.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/utils/app_bar_layout.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/utils/audio_conversion_utils.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/lyrics_metadata_helper.dart';
import 'package:spotiflac_android/models/download_item.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/services/music_player_service.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/local_track_redownload_service.dart';
import 'package:spotiflac_android/services/history_database.dart';
import 'package:spotiflac_android/services/downloaded_embedded_cover_resolver.dart';
import 'package:spotiflac_android/screens/track_metadata_screen.dart';
import 'package:spotiflac_android/screens/favorite_artists_screen.dart';
import 'package:spotiflac_android/screens/downloaded_album_screen.dart';
import 'package:spotiflac_android/widgets/re_enrich_field_dialog.dart';
import 'package:spotiflac_android/widgets/batch_progress_dialog.dart';
import 'package:spotiflac_android/widgets/batch_convert_sheet.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';
import 'package:spotiflac_android/widgets/audio_quality_badges.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';
import 'package:spotiflac_android/screens/library_tracks_folder_screen.dart';
import 'package:spotiflac_android/screens/local_album_screen.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';
import 'package:spotiflac_android/utils/path_match_keys.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/widgets/download_service_picker.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';

part 'queue_tab_helpers.dart';
part 'queue_tab_widgets.dart';

String _formatDownloadSizeMB(num bytes) {
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatDownloadProgressLabel(BuildContext context, DownloadItem item) {
  final progress = item.progress.clamp(0.0, 1.0);
  final speedSuffix = item.speedMBps > 0
      ? ' • ${item.speedMBps.toStringAsFixed(1)} MB/s'
      : '';

  if (item.bytesTotal > 0) {
    final received = item.bytesReceived > 0
        ? item.bytesReceived
        : item.bytesTotal * progress;
    final percent = (progress * 100).toStringAsFixed(0);
    return '${_formatDownloadSizeMB(received)} / ${_formatDownloadSizeMB(item.bytesTotal)} • $percent%$speedSuffix';
  }

  if (item.bytesReceived > 0) {
    final canEstimateTotal = progress > 0.01 && progress < 0.995;
    if (canEstimateTotal) {
      final estimatedTotal = item.bytesReceived / progress;
      if (estimatedTotal > item.bytesReceived) {
        return '${_formatDownloadSizeMB(item.bytesReceived)} / ~${_formatDownloadSizeMB(estimatedTotal)}$speedSuffix';
      }
    }
    return '${_formatDownloadSizeMB(item.bytesReceived)}$speedSuffix';
  }

  if (progress > 0) {
    final percent = (progress * 100).toStringAsFixed(0);
    return '$percent%$speedSuffix';
  }

  if (item.speedMBps > 0) {
    return context.l10n.queueDownloadSpeedStatus(
      item.speedMBps.toStringAsFixed(1),
    );
  }

  return context.l10n.queueDownloadStarting;
}

String _formatDownloadStatusLine(BuildContext context, DownloadItem item) {
  final base = _formatDownloadProgressLabel(context, item);
  final eta = _formatDownloadEta(item);
  return eta == null ? base : '$base • $eta';
}

String? _formatDownloadEta(DownloadItem item) {
  if (item.speedMBps <= 0 || item.bytesTotal <= 0) return null;
  final received = item.bytesReceived > 0
      ? item.bytesReceived
      : (item.bytesTotal * item.progress).round();
  final remaining = item.bytesTotal - received;
  if (remaining <= 0) return null;
  final seconds = remaining / (item.speedMBps * 1024 * 1024);
  if (!seconds.isFinite || seconds > 3600) return null;
  if (seconds < 60) return '~${seconds.round()}s';
  final minutes = (seconds / 60).floor();
  final secs = (seconds % 60).round();
  return '~${minutes}m${secs.toString().padLeft(2, '0')}s';
}

class QueueTab extends ConsumerStatefulWidget {
  final PageController? parentPageController;
  final int parentPageIndex;
  final int? nextPageIndex;

  const QueueTab({
    super.key,
    this.parentPageController,
    this.parentPageIndex = 1,
    this.nextPageIndex,
  });

  @override
  ConsumerState<QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends ConsumerState<QueueTab> {
  static const int _libraryPageSize = 300;
  final _FileExistsListenableCache _fileExistsCache =
      _FileExistsListenableCache();
  static const int _maxSearchIndexCacheSize = 4000;
  static const double _libraryGridMinExtent = 92;
  static const double _libraryGridDefaultExtent = 126;
  static const double _libraryGridMaxExtent = 190;
  bool _embeddedCoverRefreshScheduled = false;
  // Version counter to trigger targeted cover image rebuilds
  // without rebuilding the entire widget tree via setState.
  final ValueNotifier<int> _embeddedCoverVersion = ValueNotifier<int>(0);

  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  OverlayEntry? _selectionOverlayEntry;
  List<UnifiedLibraryItem> _selectionOverlayItems = const [];
  double _selectionOverlayBottomPadding = 0;

  /// Keeps the selection overlays hidden while a modal launched from the
  /// selection toolbar is open, so they don't reappear over its animation.
  bool _suppressSelectionOverlay = false;

  bool _isPlaylistSelectionMode = false;
  final Set<String> _selectedPlaylistIds = {};
  OverlayEntry? _playlistSelectionOverlayEntry;
  List<UserPlaylistCollection> _playlistSelectionOverlayItems = const [];
  double _playlistSelectionOverlayBottomPadding = 0;

  PageController? _filterPageController;
  final List<String> _filterModes = ['all', 'albums', 'singles'];
  bool _isPageControllerInitialized = false;
  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  Timer? _searchDebounce;
  List<DownloadHistoryItem>? _historyItemsCache;
  List<LocalLibraryItem>? _localLibraryItemsCache;
  _HistoryStats? _historyStatsCache;
  final Map<String, Track> _completionBridge = {};
  final Map<String, DateTime> _completionBridgeAt = {};
  final Set<String> _bridgePrecacheStarted = {};
  final Map<String, String> _searchIndexCache = {};
  final Map<String, String> _localSearchIndexCache = {};
  Map<String, List<DownloadHistoryItem>> _filteredHistoryCache = const {};
  List<DownloadHistoryItem>? _filterItemsCache;
  String _filterQueryCache = '';
  bool _filterRefreshScheduled = false;
  bool _isFilteringHistory = false;
  int _filterRequestId = 0;
  static const int _filterIsolateThreshold = 800;
  List<LocalLibraryItem>? _localFilterItemsCache;
  String _localFilterQueryCache = '';
  List<LocalLibraryItem> _filteredLocalItemsCache = const [];
  final Map<String, _UnifiedCacheEntry> _unifiedItemsCache = {};
  List<DownloadHistoryItem>? _cachedUnifiedDownloadedSource;
  List<UnifiedLibraryItem> _cachedUnifiedDownloaded = const [];
  List<LocalLibraryItem>? _cachedUnifiedLocalSource;
  List<UnifiedLibraryItem> _cachedUnifiedLocal = const [];
  List<DownloadHistoryItem>? _cachedDownloadedPathKeysSource;
  Set<String> _cachedDownloadedPathKeys = const <String>{};
  final Map<String, List<String>> _localPathMatchKeysCache = {};
  List<LocalLibraryItem>? _cachedLocalSinglesSource;
  Map<String, int>? _cachedLocalSinglesAlbumCountsSource;
  List<LocalLibraryItem> _cachedLocalSingles = const [];
  final Map<String, _FilterContentData> _filterContentDataCache = {};
  List<DownloadHistoryItem>? _filterCacheAllHistoryItems;
  _HistoryStats? _filterCacheHistoryStats;
  List<LocalLibraryItem>? _filterCacheLocalLibraryItems;
  LibraryCollectionsState? _filterCacheCollectionState;
  String _filterCacheSearchQuery = '';
  String? _filterCacheSource;
  String? _filterCacheQuality;
  String? _filterCacheFormat;
  String? _filterCacheMetadata;
  String _filterCacheSortMode = 'latest';
  String? _filterSource;
  String? _filterQuality;
  String? _filterFormat;
  String? _filterMetadata;
  String _sortMode = 'latest';
  double _libraryGridExtent = _libraryGridDefaultExtent;
  double? _libraryGridScaleStartExtent;
  final Map<String, int> _libraryPageOffsetByFilter = {};
  bool _libraryPageLoadScheduled = false;
  final Map<_QueueLibraryCountsRequest, QueueLibraryCounts>
  _queueLibraryCountsCache = {};
  final Map<_QueueLibraryPageRequest, _QueueLibraryPageData>
  _queueLibraryPageDataCache = {};
  DateTime? _lastBlankLibraryRepairAt;

  double _effectiveTextScale() {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    if (textScale < 1.0) return 1.0;
    if (textScale > 1.4) return 1.4;
    return textScale;
  }

  double _queueCoverSize() {
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final scale = (shortestSide / 390).clamp(0.82, 1.0);
    final textScale = _effectiveTextScale();
    return (56 * scale * (1 + ((textScale - 1) * 0.12))).clamp(46.0, 56.0);
  }

  double get _libraryAlbumGridExtent =>
      (_libraryGridExtent * 1.45).clamp(150.0, 300.0);

  void _handleLibraryGridScaleStart(ScaleStartDetails details) {
    if (details.pointerCount < 2) return;
    _libraryGridScaleStartExtent = _libraryGridExtent;
  }

  void _handleLibraryGridScaleUpdate(ScaleUpdateDetails details) {
    final startExtent = _libraryGridScaleStartExtent;
    if (startExtent == null || details.pointerCount < 2) return;

    final nextExtent = (startExtent * details.scale).clamp(
      _libraryGridMinExtent,
      _libraryGridMaxExtent,
    );
    if ((nextExtent - _libraryGridExtent).abs() < 0.5) return;
    setState(() => _libraryGridExtent = nextExtent);
  }

  void _handleLibraryGridScaleEnd(ScaleEndDetails details) {
    _libraryGridScaleStartExtent = null;
  }

  @override
  void initState() {
    super.initState();
  }

  void _initializePageController() {
    if (_isPageControllerInitialized) return;
    _isPageControllerInitialized = true;
    final currentFilter = ref.read(settingsProvider).historyFilterMode;
    final initialPage = _filterModes.indexOf(currentFilter).clamp(0, 2);
    _filterPageController = PageController(initialPage: initialPage);
  }

  @override
  void dispose() {
    _hideSelectionOverlay();
    _hidePlaylistSelectionOverlay();
    _fileExistsCache.dispose();
    _embeddedCoverVersion.dispose();
    _filterPageController?.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final normalized = value.trim().toLowerCase();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || _searchQuery == normalized) return;
      setState(() {
        _searchQuery = normalized;
        _resetLibraryPaging();
      });
      _requestFilterRefresh();
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    if (_searchQuery.isEmpty) return;
    setState(() {
      _searchQuery = '';
      _resetLibraryPaging();
    });
    _requestFilterRefresh();
  }

  int _libraryPageOffsetFor(String filterMode) =>
      _libraryPageOffsetByFilter[filterMode] ?? 0;

  void _resetLibraryPaging() {
    _libraryPageOffsetByFilter.clear();
    _queueLibraryPageDataCache.clear();
  }

  void _loadMoreLibraryItems({
    required String filterMode,
    required bool hasMoreLibrary,
  }) {
    if (_libraryPageLoadScheduled) return;
    _libraryPageLoadScheduled = true;
    setState(() {
      if (hasMoreLibrary) {
        _libraryPageOffsetByFilter[filterMode] =
            _libraryPageOffsetFor(filterMode) + _libraryPageSize;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _libraryPageLoadScheduled = false;
    });
  }

  QueueLibraryCounts _resolveQueueLibraryCounts(
    AsyncValue<QueueLibraryCounts> value,
    _QueueLibraryCountsRequest request,
  ) {
    return value.maybeWhen(
      data: (counts) {
        _queueLibraryCountsCache[request] = counts;
        _trimQueueLibraryCountsCache();
        return counts;
      },
      orElse: () =>
          _queueLibraryCountsCache[request] ??
          const QueueLibraryCounts(
            allTrackCount: 0,
            albumCount: 0,
            singleTrackCount: 0,
          ),
    );
  }

  _QueueLibraryPageData _resolveQueueLibraryPageData(
    AsyncValue<_QueueLibraryPageData>? value,
    _QueueLibraryPageRequest request,
  ) {
    if (value != null) {
      final liveData = value.asData?.value;
      if (liveData != null) {
        _queueLibraryPageDataCache[request] = liveData;
        _trimQueueLibraryPageDataCache(protectedRequest: request);
      }
      value.whenOrNull(
        data: (data) {
          _queueLibraryPageDataCache[request] = data;
          _trimQueueLibraryPageDataCache(protectedRequest: request);
        },
      );
    }

    final pages = <_QueueLibraryPageData>[];
    for (var offset = 0; offset <= request.offset; offset += _libraryPageSize) {
      final page =
          _queueLibraryPageDataCache[_QueueLibraryPageRequest(
            filterMode: request.filterMode,
            limit: request.limit,
            offset: offset,
            searchQuery: request.searchQuery,
            filterSource: request.filterSource,
            filterQuality: request.filterQuality,
            filterFormat: request.filterFormat,
            filterMetadata: request.filterMetadata,
            sortMode: request.sortMode,
            localLibraryEnabled: request.localLibraryEnabled,
          )];
      if (page != null) pages.add(page);
    }

    return _QueueLibraryPageData.combine(pages);
  }

  void _invalidateLibraryDataCaches() {
    _queueLibraryCountsCache.clear();
    _queueLibraryPageDataCache.clear();
    _unifiedItemsCache.clear();
    _invalidateFilterContentCache();
  }

  void _scheduleBlankLibraryRepair({
    required bool hasQueueItems,
    required bool hasLibraryContent,
    required bool hasAnyLibraryItems,
    required bool isLibraryPageLoading,
  }) {
    if (!hasQueueItems ||
        hasLibraryContent ||
        hasAnyLibraryItems ||
        isLibraryPageLoading) {
      return;
    }
    final now = DateTime.now();
    final last = _lastBlankLibraryRepairAt;
    if (last != null && now.difference(last) < const Duration(seconds: 8)) {
      return;
    }
    _lastBlankLibraryRepairAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _invalidateLibraryDataCaches();
      ref.read(downloadHistoryProvider.notifier).reloadFromStorage();
      ref.read(localLibraryProvider.notifier).reloadFromStorage();
      setState(() {});
    });
  }

  void _trimQueueLibraryCountsCache() {
    const maxCountEntries = 24;
    while (_queueLibraryCountsCache.length > maxCountEntries) {
      _queueLibraryCountsCache.remove(_queueLibraryCountsCache.keys.first);
    }
  }

  bool _isProtectedQueueLibraryPage(
    _QueueLibraryPageRequest request,
    _QueueLibraryPageRequest protectedRequest,
  ) {
    return request.filterMode == protectedRequest.filterMode &&
        request.limit == protectedRequest.limit &&
        request.offset <= protectedRequest.offset &&
        request.searchQuery == protectedRequest.searchQuery &&
        request.filterSource == protectedRequest.filterSource &&
        request.filterQuality == protectedRequest.filterQuality &&
        request.filterFormat == protectedRequest.filterFormat &&
        request.filterMetadata == protectedRequest.filterMetadata &&
        request.sortMode == protectedRequest.sortMode &&
        request.localLibraryEnabled == protectedRequest.localLibraryEnabled;
  }

  void _trimQueueLibraryPageDataCache({
    required _QueueLibraryPageRequest protectedRequest,
  }) {
    const maxPageEntries = 96;
    while (_queueLibraryPageDataCache.length > maxPageEntries) {
      final removableKey = _queueLibraryPageDataCache.keys
          .where(
            (request) =>
                !_isProtectedQueueLibraryPage(request, protectedRequest),
          )
          .firstOrNull;
      if (removableKey == null) break;
      _queueLibraryPageDataCache.remove(removableKey);
    }
  }

  bool _handleLibraryScrollNotification({
    required ScrollNotification notification,
    required String filterMode,
    required bool hasMoreLibrary,
    required bool isPageLoading,
  }) {
    if (isPageLoading || !hasMoreLibrary || notification.depth != 0) {
      return false;
    }

    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= 0) return false;
    final threshold = metrics.maxScrollExtent * 0.7;
    final nearEnd =
        metrics.pixels >= threshold ||
        metrics.extentAfter <= metrics.viewportDimension * 1.5;
    if (!nearEnd) return false;

    _loadMoreLibraryItems(
      filterMode: filterMode,
      hasMoreLibrary: hasMoreLibrary,
    );
    return false;
  }

  void _invalidateFilterContentCache() {
    _filterContentDataCache.clear();
    _filterCacheAllHistoryItems = null;
    _filterCacheHistoryStats = null;
    _filterCacheLocalLibraryItems = null;
    _filterCacheCollectionState = null;
  }

  // ignore: unused_element
  void _prepareFilterContentCache({
    required List<DownloadHistoryItem> allHistoryItems,
    required _HistoryStats historyStats,
    required List<LocalLibraryItem> localLibraryItems,
    required LibraryCollectionsState collectionState,
  }) {
    final isCacheValid =
        identical(_filterCacheAllHistoryItems, allHistoryItems) &&
        identical(_filterCacheHistoryStats, historyStats) &&
        identical(_filterCacheLocalLibraryItems, localLibraryItems) &&
        identical(_filterCacheCollectionState, collectionState) &&
        _filterCacheSearchQuery == _searchQuery &&
        _filterCacheSource == _filterSource &&
        _filterCacheQuality == _filterQuality &&
        _filterCacheFormat == _filterFormat &&
        _filterCacheMetadata == _filterMetadata &&
        _filterCacheSortMode == _sortMode;

    if (isCacheValid) {
      return;
    }

    _filterContentDataCache.clear();
    _filterCacheAllHistoryItems = allHistoryItems;
    _filterCacheHistoryStats = historyStats;
    _filterCacheLocalLibraryItems = localLibraryItems;
    _filterCacheCollectionState = collectionState;
    _filterCacheSearchQuery = _searchQuery;
    _filterCacheSource = _filterSource;
    _filterCacheQuality = _filterQuality;
    _filterCacheFormat = _filterFormat;
    _filterCacheMetadata = _filterMetadata;
    _filterCacheSortMode = _sortMode;
  }

  // ignore: unused_element
  void _ensureHistoryCaches(
    List<DownloadHistoryItem> items,
    List<LocalLibraryItem> localItems,
    _HistoryStats historyStats,
  ) {
    final historyChanged = !identical(items, _historyItemsCache);
    final localChanged = !identical(localItems, _localLibraryItemsCache);

    if (!historyChanged && !localChanged) return;

    _historyItemsCache = items;
    _localLibraryItemsCache = localItems;
    _historyStatsCache = historyStats;
    if (historyChanged) {
      _searchIndexCache.clear();
      _cachedUnifiedDownloadedSource = null;
      _cachedUnifiedDownloaded = const [];
      _cachedDownloadedPathKeysSource = null;
      _cachedDownloadedPathKeys = const <String>{};
    }
    if (localChanged) {
      _localSearchIndexCache.clear();
      _localPathMatchKeysCache.clear();
      _localFilterItemsCache = null;
      _localFilterQueryCache = '';
      _filteredLocalItemsCache = const [];
      _cachedLocalSinglesSource = null;
      _cachedLocalSinglesAlbumCountsSource = null;
      _cachedLocalSingles = const [];
      _cachedUnifiedLocalSource = null;
      _cachedUnifiedLocal = const [];
    }
    _unifiedItemsCache.clear();
    _invalidateFilterContentCache();

    if (historyChanged) {
      final validPaths = items
          .map((item) => _cleanFilePath(item.filePath))
          .where((path) => path.isNotEmpty)
          .toSet();
      DownloadedEmbeddedCoverResolver.invalidatePathsNotIn(validPaths);
    }
    _requestFilterRefresh();
  }

  String _buildSearchKey(DownloadHistoryItem item) {
    return '${item.trackName} ${item.artistName} ${item.albumName}'
        .toLowerCase();
  }

  String _buildLocalSearchKey(LocalLibraryItem item) {
    return '${item.trackName} ${item.artistName} ${item.albumName}'
        .toLowerCase();
  }

  String _historySearchKeyForItem(DownloadHistoryItem item) {
    final cached = _searchIndexCache[item.id];
    if (cached != null) return cached;

    final searchKey = _buildSearchKey(item);
    _searchIndexCache[item.id] = searchKey;
    while (_searchIndexCache.length > _maxSearchIndexCacheSize) {
      _searchIndexCache.remove(_searchIndexCache.keys.first);
    }
    return searchKey;
  }

  String _localSearchKeyForItem(LocalLibraryItem item) {
    final cached = _localSearchIndexCache[item.id];
    if (cached != null) return cached;

    final searchKey = _buildLocalSearchKey(item);
    _localSearchIndexCache[item.id] = searchKey;
    while (_localSearchIndexCache.length > _maxSearchIndexCacheSize) {
      _localSearchIndexCache.remove(_localSearchIndexCache.keys.first);
    }
    return searchKey;
  }

  List<UnifiedLibraryItem> _unifiedDownloadedItems(
    List<DownloadHistoryItem> items,
  ) {
    if (identical(items, _cachedUnifiedDownloadedSource)) {
      return _cachedUnifiedDownloaded;
    }
    final unified = items
        .map(UnifiedLibraryItem.fromDownloadHistory)
        .toList(growable: false);
    _cachedUnifiedDownloadedSource = items;
    _cachedUnifiedDownloaded = unified;
    return unified;
  }

  List<UnifiedLibraryItem> _unifiedLocalItems(List<LocalLibraryItem> items) {
    if (identical(items, _cachedUnifiedLocalSource)) {
      return _cachedUnifiedLocal;
    }
    final unified = items
        .map(UnifiedLibraryItem.fromLocalLibrary)
        .toList(growable: false);
    _cachedUnifiedLocalSource = items;
    _cachedUnifiedLocal = unified;
    return unified;
  }

  Set<String> _downloadedPathKeys(List<DownloadHistoryItem> historyItems) {
    if (identical(historyItems, _cachedDownloadedPathKeysSource)) {
      return _cachedDownloadedPathKeys;
    }
    final keys = <String>{};
    for (final item in historyItems) {
      keys.addAll(buildPathMatchKeys(item.filePath));
    }
    _cachedDownloadedPathKeysSource = historyItems;
    _cachedDownloadedPathKeys = Set<String>.unmodifiable(keys);
    return _cachedDownloadedPathKeys;
  }

  List<String> _localPathMatchKeys(LocalLibraryItem item) {
    final cached = _localPathMatchKeysCache[item.id];
    if (cached != null) return cached;
    final keys = buildPathMatchKeys(item.filePath).toList(growable: false);
    _localPathMatchKeysCache[item.id] = keys;
    return keys;
  }

  List<LocalLibraryItem> _localSingleItems(
    List<LocalLibraryItem> items,
    Map<String, int> localAlbumCounts,
  ) {
    if (identical(items, _cachedLocalSinglesSource) &&
        identical(localAlbumCounts, _cachedLocalSinglesAlbumCountsSource)) {
      return _cachedLocalSingles;
    }

    final singles = items
        .where((item) => (localAlbumCounts[item.albumKey] ?? 0) == 1)
        .toList(growable: false);
    _cachedLocalSinglesSource = items;
    _cachedLocalSinglesAlbumCountsSource = localAlbumCounts;
    _cachedLocalSingles = singles;
    return singles;
  }

  List<LocalLibraryItem> _filterLocalItems(
    List<LocalLibraryItem> items,
    String query,
  ) {
    if (query.isEmpty) return items;
    if (identical(items, _localFilterItemsCache) &&
        query == _localFilterQueryCache) {
      return _filteredLocalItemsCache;
    }

    final filtered = items
        .where((item) {
          final searchKey = _localSearchKeyForItem(item);
          return searchKey.contains(query);
        })
        .toList(growable: false);

    _localFilterItemsCache = items;
    _localFilterQueryCache = query;
    _filteredLocalItemsCache = filtered;
    return filtered;
  }

  bool _isFilterCacheValid(List<DownloadHistoryItem> items, String query) {
    return identical(items, _filterItemsCache) && query == _filterQueryCache;
  }

  void _requestFilterRefresh() {
    if (_filterRefreshScheduled) return;
    _filterRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _filterRefreshScheduled = false;
      if (!mounted) return;
      _scheduleHistoryFilterUpdate();
    });
  }

  void _scheduleHistoryFilterUpdate() {
    final items = _historyItemsCache;
    if (items == null) return;
    final query = _searchQuery;
    if (_isFilterCacheValid(items, query)) return;

    final albumCounts =
        _historyStatsCache?.albumCounts ?? const <String, int>{};
    if (items.isEmpty) {
      setState(() {
        _filteredHistoryCache = const {};
        _filterItemsCache = items;
        _filterQueryCache = query;
        _isFilteringHistory = false;
      });
      return;
    }

    if (items.length <= _filterIsolateThreshold) {
      final filteredAll = _applyHistorySearchFilter(items, query);
      final filteredAlbums = _filterHistoryByAlbumCount(
        filteredAll,
        albumCounts,
        2,
      );
      final filteredSingles = _filterHistoryByAlbumCount(
        filteredAll,
        albumCounts,
        1,
      );
      setState(() {
        _filteredHistoryCache = {
          'all': filteredAll,
          'albums': filteredAlbums,
          'singles': filteredSingles,
        };
        _filterItemsCache = items;
        _filterQueryCache = query;
        _isFilteringHistory = false;
      });
      return;
    }

    if (!_isFilteringHistory) {
      setState(() => _isFilteringHistory = true);
    }

    final requestId = ++_filterRequestId;
    final includeSearchKey = query.isNotEmpty;
    final entries = List<List<String>>.generate(items.length, (index) {
      final item = items[index];
      final albumKey =
          '${item.albumName.toLowerCase()}|${(item.albumArtist ?? item.artistName).toLowerCase()}';
      if (!includeSearchKey) {
        return [item.id, albumKey];
      }
      final searchKey = _historySearchKeyForItem(item);
      return [item.id, albumKey, searchKey];
    }, growable: false);
    final payload = <String, Object>{
      'entries': entries,
      'albumCounts': albumCounts,
      'query': query,
    };

    compute(_filterHistoryInIsolate, payload).then((result) {
      if (!mounted || requestId != _filterRequestId) return;
      final itemsById = {for (final item in items) item.id: item};
      final filtered = <String, List<DownloadHistoryItem>>{};
      for (final entry in result.entries) {
        filtered[entry.key] = entry.value
            .map((id) => itemsById[id])
            .whereType<DownloadHistoryItem>()
            .toList(growable: false);
      }
      setState(() {
        _filteredHistoryCache = filtered;
        _filterItemsCache = items;
        _filterQueryCache = query;
        _isFilteringHistory = false;
      });
    });
  }

  List<DownloadHistoryItem> _resolveHistoryItems({
    required String filterMode,
    required List<DownloadHistoryItem> allHistoryItems,
    required Map<String, int> albumCounts,
  }) {
    final query = _searchQuery;
    if (_isFilterCacheValid(allHistoryItems, query)) {
      final cached = _filteredHistoryCache[filterMode];
      if (cached != null) return cached;
    }
    if (allHistoryItems.isEmpty) return const [];
    if (query.isEmpty && filterMode == 'all') return allHistoryItems;
    if (allHistoryItems.length <= _filterIsolateThreshold) {
      return _filterHistoryItems(
        allHistoryItems,
        filterMode,
        albumCounts,
        query,
      );
    }
    return const [];
  }

  List<DownloadHistoryItem> _applyHistorySearchFilter(
    List<DownloadHistoryItem> items,
    String searchQuery,
  ) {
    if (searchQuery.isEmpty) return items;
    final query = searchQuery;
    return items
        .where((item) {
          final searchKey = _historySearchKeyForItem(item);
          return searchKey.contains(query);
        })
        .toList(growable: false);
  }

  List<DownloadHistoryItem> _filterHistoryByAlbumCount(
    List<DownloadHistoryItem> items,
    Map<String, int> albumCounts,
    int targetCount,
  ) {
    return items
        .where((item) {
          final key =
              '${item.albumName.toLowerCase()}|${(item.albumArtist ?? item.artistName).toLowerCase()}';
          final count = albumCounts[key] ?? 0;
          return targetCount == 1 ? count == 1 : count >= targetCount;
        })
        .toList(growable: false);
  }

  bool _shouldShowFilteringIndicator({
    required List<DownloadHistoryItem> allHistoryItems,
    required String filterMode,
  }) {
    if (allHistoryItems.isEmpty) return false;
    if (_searchQuery.isEmpty && filterMode == 'all') return false;
    if (allHistoryItems.length <= _filterIsolateThreshold) return false;
    return !_isFilterCacheValid(allHistoryItems, _searchQuery) ||
        _isFilteringHistory;
  }

  void _onFilterPageChanged(int index) {
    HapticFeedback.selectionClick();
    final filterMode = _filterModes[index];
    ref.read(settingsProvider.notifier).setHistoryFilterMode(filterMode);
  }

  void _animateToFilterPage(int index) {
    if (index >= 0 && index < _filterModes.length) {
      final filterMode = _filterModes[index];
      if (ref.read(settingsProvider).historyFilterMode != filterMode) {
        ref.read(settingsProvider.notifier).setHistoryFilterMode(filterMode);
      }
    }
    _filterPageController?.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _enterSelectionMode(String itemId) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isPlaylistSelectionMode = false;
      _selectedPlaylistIds.clear();
      _isSelectionMode = true;
      _selectedIds.add(itemId);
    });
    _hidePlaylistSelectionOverlay();
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
    _hideSelectionOverlay();
  }

  void _toggleSelection(String itemId) {
    var shouldHideOverlay = false;
    setState(() {
      if (_selectedIds.contains(itemId)) {
        _selectedIds.remove(itemId);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
          shouldHideOverlay = true;
        }
      } else {
        _selectedIds.add(itemId);
      }
    });
    if (shouldHideOverlay) {
      _hideSelectionOverlay();
    }
  }

  void _selectAll(List<UnifiedLibraryItem> items) {
    setState(() {
      _selectedIds.addAll(items.map((e) => e.id));
    });
  }

  void _hideSelectionOverlay() {
    _selectionOverlayEntry?.remove();
    _selectionOverlayEntry = null;
  }

  void _syncSelectionOverlay({
    required List<UnifiedLibraryItem> items,
    required double bottomPadding,
  }) {
    if (!mounted) return;
    if (_suppressSelectionOverlay ||
        !_isSelectionMode ||
        _isPlaylistSelectionMode) {
      _hideSelectionOverlay();
      return;
    }

    _selectionOverlayItems = items;
    _selectionOverlayBottomPadding = bottomPadding;

    if (_selectionOverlayEntry != null) {
      _selectionOverlayEntry!.markNeedsBuild();
      return;
    }

    final overlay = Overlay.of(context, rootOverlay: true);
    _selectionOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final colorScheme = Theme.of(context).colorScheme;
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _AnimatedOverlayBottomBar(
            child: Material(
              color: Colors.transparent,
              child: _buildSelectionBottomBar(
                context,
                colorScheme,
                _selectionOverlayItems,
                _selectionOverlayBottomPadding,
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_selectionOverlayEntry!);
  }

  void _hidePlaylistSelectionOverlay() {
    _playlistSelectionOverlayEntry?.remove();
    _playlistSelectionOverlayEntry = null;
  }

  void _syncPlaylistSelectionOverlay({
    required List<UserPlaylistCollection> playlists,
    required double bottomPadding,
  }) {
    if (!mounted) return;
    if (_suppressSelectionOverlay ||
        !_isPlaylistSelectionMode ||
        _isSelectionMode) {
      _hidePlaylistSelectionOverlay();
      return;
    }

    _playlistSelectionOverlayItems = playlists;
    _playlistSelectionOverlayBottomPadding = bottomPadding;

    if (_playlistSelectionOverlayEntry != null) {
      _playlistSelectionOverlayEntry!.markNeedsBuild();
      return;
    }

    final overlay = Overlay.of(context, rootOverlay: true);
    _playlistSelectionOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final colorScheme = Theme.of(context).colorScheme;
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _AnimatedOverlayBottomBar(
            child: Material(
              color: Colors.transparent,
              child: _buildPlaylistSelectionBottomBar(
                context,
                colorScheme,
                _playlistSelectionOverlayItems,
                _playlistSelectionOverlayBottomPadding,
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_playlistSelectionOverlayEntry!);
  }

  void _enterPlaylistSelectionMode(String playlistId) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
      _isPlaylistSelectionMode = true;
      _selectedPlaylistIds.add(playlistId);
    });
    _hideSelectionOverlay();
  }

  void _exitPlaylistSelectionMode() {
    setState(() {
      _isPlaylistSelectionMode = false;
      _selectedPlaylistIds.clear();
    });
    _hidePlaylistSelectionOverlay();
  }

  void _togglePlaylistSelection(String playlistId) {
    var shouldHideOverlay = false;
    setState(() {
      if (_selectedPlaylistIds.contains(playlistId)) {
        _selectedPlaylistIds.remove(playlistId);
        if (_selectedPlaylistIds.isEmpty) {
          _isPlaylistSelectionMode = false;
          shouldHideOverlay = true;
        }
      } else {
        _selectedPlaylistIds.add(playlistId);
      }
    });
    if (shouldHideOverlay) {
      _hidePlaylistSelectionOverlay();
    }
  }

  void _selectAllPlaylists(List<UserPlaylistCollection> playlists) {
    setState(() {
      _selectedPlaylistIds.addAll(playlists.map((e) => e.id));
    });
  }

  Future<void> _downloadAllSelectedPlaylists(BuildContext context) async {
    final collectionsState = ref.read(libraryCollectionsProvider);
    final selectedPlaylists = collectionsState.playlists
        .where((p) => _selectedPlaylistIds.contains(p.id))
        .toList();

    final totalTracks = selectedPlaylists.fold<int>(
      0,
      (sum, p) => sum + p.tracks.length,
    );

    if (totalTracks == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.snackbarSelectedPlaylistsEmpty)),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.dialogDownloadAllTitle),
        content: Text(
          ctx.l10n.dialogDownloadPlaylistsMessage(
            totalTracks,
            selectedPlaylists.length,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.dialogDownload),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final settings = ref.read(settingsProvider);
    final extensionState = ref.read(extensionProvider);
    final queueNotifier = ref.read(downloadQueueProvider.notifier);

    void enqueueAll({String? qualityOverride, String? service}) {
      final svc =
          service ??
          resolveEffectiveDownloadService(
            settings.defaultService,
            extensionState,
          );
      if (svc.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.extensionsNoDownloadProvider)),
          );
        }
        return;
      }
      for (final playlist in selectedPlaylists) {
        final tracks = playlist.tracks.map((e) => e.track).toList();
        queueNotifier.addMultipleToQueue(
          tracks,
          svc,
          qualityOverride: qualityOverride,
          playlistName: playlist.name,
        );
      }
    }

    if (settings.askQualityBeforeDownload) {
      DownloadServicePicker.show(
        context,
        trackName: context.l10n.tracksCount(totalTracks),
        artistName: context.l10n.playlistsCount(selectedPlaylists.length),
        onSelect: (quality, service) {
          enqueueAll(qualityOverride: quality, service: service);
          if (!mounted) return;
          _exitPlaylistSelectionMode();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.snackbarAddedTracksToQueue(totalTracks),
              ),
            ),
          );
        },
      );
    } else {
      enqueueAll();
      _exitPlaylistSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.snackbarAddedTracksToQueue(totalTracks)),
        ),
      );
    }
  }

  Future<void> _deleteSelectedPlaylists(BuildContext context) async {
    final count = _selectedPlaylistIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.collectionDeletePlaylist),
        content: Text(ctx.l10n.collectionDeletePlaylistsMessage(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(ctx.l10n.dialogDelete),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final notifier = ref.read(libraryCollectionsProvider.notifier);
    for (final id in _selectedPlaylistIds.toList()) {
      await notifier.deletePlaylist(id);
    }

    if (!context.mounted) return;
    _exitPlaylistSelectionMode();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.collectionPlaylistsDeleted(count))),
    );
  }

  Widget _buildPlaylistSelectionBottomBar(
    BuildContext context,
    ColorScheme colorScheme,
    List<UserPlaylistCollection> playlists,
    double bottomPadding,
  ) {
    final selectedCount = _selectedPlaylistIds.length;
    final allSelected =
        selectedCount == playlists.length && playlists.isNotEmpty;

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
                    onPressed: _exitPlaylistSelectionMode,
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
                              ? context.l10n.selectionAllPlaylistsSelected
                              : context.l10n.selectionTapPlaylistsToSelect,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),

                  TextButton.icon(
                    onPressed: () {
                      if (allSelected) {
                        _exitPlaylistSelectionMode();
                      } else {
                        _selectAllPlaylists(playlists);
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

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: selectedCount > 0
                      ? () => _downloadAllSelectedPlaylists(context)
                      : null,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    selectedCount > 0
                        ? context.l10n.bulkDownloadPlaylistsButton(
                            selectedCount,
                          )
                        : context.l10n.bulkDownloadSelectPlaylists,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: selectedCount > 0
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    foregroundColor: selectedCount > 0
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: selectedCount > 0
                      ? () => _deleteSelectedPlaylists(context)
                      : null,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    selectedCount > 0
                        ? context.l10n.selectionDeletePlaylistsCount(
                            selectedCount,
                          )
                        : context.l10n.selectionSelectPlaylistsToDelete,
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

  String _getQualityBadgeText(String quality) {
    final q = quality.trim().toLowerCase();
    if (q.contains('bit')) {
      return quality.split('/').first;
    }

    final bitrateTextMatch = RegExp(
      r'(\d+)\s*k(?:bps)?',
      caseSensitive: false,
    ).firstMatch(quality);
    if (bitrateTextMatch != null) {
      return '${bitrateTextMatch.group(1)}k';
    }

    final bitrateIdMatch = RegExp(r'_(\d+)$').firstMatch(q);
    if (bitrateIdMatch != null) {
      return '${bitrateIdMatch.group(1)}k';
    }

    return quality.split(' ').first;
  }

  Future<void> _deleteSelected(List<UnifiedLibraryItem> allItems) async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.dialogDeleteSelectedTitle),
        content: Text(context.l10n.dialogDeleteSelectedMessage(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.l10n.dialogDelete),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final historyNotifier = ref.read(downloadHistoryProvider.notifier);
      final localLibraryDb = LibraryDatabase.instance;
      final itemsById = {for (final item in allItems) item.id: item};

      int deletedCount = 0;
      for (final id in _selectedIds) {
        final item = itemsById[id];
        if (item != null) {
          try {
            final cleanPath = _cleanFilePath(item.filePath);
            await deleteFile(cleanPath);
          } catch (_) {}

          if (item.source == LibraryItemSource.downloaded) {
            historyNotifier.removeFromHistory(item.historyItem!.id);
          } else {
            await localLibraryDb.deleteByPath(item.filePath);
          }
          deletedCount++;
        }
      }

      if (allItems.any(
        (i) =>
            _selectedIds.contains(i.id) && i.source == LibraryItemSource.local,
      )) {
        ref.read(localLibraryProvider.notifier).reloadFromStorage();
      }

      _exitSelectionMode();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.snackbarDeletedTracks(deletedCount)),
          ),
        );
      }
    }
  }

  String _cleanFilePath(String? filePath) {
    return DownloadedEmbeddedCoverResolver.cleanFilePath(filePath);
  }

  Future<int?> _readFileModTimeMillis(String? filePath) async {
    return DownloadedEmbeddedCoverResolver.readFileModTimeMillis(filePath);
  }

  void _onEmbeddedCoverChanged() {
    if (!mounted || _embeddedCoverRefreshScheduled) return;
    _embeddedCoverRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _embeddedCoverRefreshScheduled = false;
      if (mounted) {
        _embeddedCoverVersion.value++;
      }
    });
  }

  Future<void> _scheduleDownloadedEmbeddedCoverRefreshForPath(
    String? filePath, {
    int? beforeModTime,
    bool force = false,
  }) async {
    await DownloadedEmbeddedCoverResolver.scheduleRefreshForPath(
      filePath,
      beforeModTime: beforeModTime,
      force: force,
      onChanged: _onEmbeddedCoverChanged,
    );
  }

  String? _resolveDownloadedEmbeddedCoverPath(String? filePath) {
    return DownloadedEmbeddedCoverResolver.resolve(
      filePath,
      onChanged: _onEmbeddedCoverChanged,
    );
  }

  ValueListenable<bool> _fileExistsListenable(String? filePath) {
    return _fileExistsCache.listenable(filePath);
  }

  int get _activeFilterCount {
    int count = 0;
    if (_filterSource != null) count++;
    if (_filterQuality != null) count++;
    if (_filterFormat != null) count++;
    if (_filterMetadata != null) count++;
    return count;
  }

  void _resetFilters() {
    setState(() {
      _filterSource = null;
      _filterQuality = null;
      _filterFormat = null;
      _filterMetadata = null;
      _sortMode = 'latest';
      _resetLibraryPaging();
      _unifiedItemsCache.clear();
      _invalidateFilterContentCache();
    });
  }

  String _fileExtLower(String filePath) {
    final dotIndex = filePath.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == filePath.length - 1) {
      return '';
    }
    return filePath.substring(dotIndex + 1).toLowerCase();
  }

  String _itemFormatLower(UnifiedLibraryItem item) {
    final localFormat = normalizeOptionalString(item.localItem?.format);
    if (localFormat != null) {
      return localFormat.toLowerCase().replaceAll('-', '_');
    }
    final historyFormat = normalizeOptionalString(item.historyItem?.format);
    if (historyFormat != null) {
      return historyFormat.toLowerCase().replaceAll('-', '_');
    }
    return _fileExtLower(item.filePath);
  }

  List<UnifiedLibraryItem> _applyAdvancedFilters(
    List<UnifiedLibraryItem> items,
  ) {
    List<UnifiedLibraryItem> filtered;
    if (_activeFilterCount == 0) {
      filtered = items;
    } else {
      filtered = items
          .where((item) {
            if (_filterSource != null) {
              if (_filterSource == 'downloaded' &&
                  item.source != LibraryItemSource.downloaded) {
                return false;
              }
              if (_filterSource == 'local' &&
                  item.source != LibraryItemSource.local) {
                return false;
              }
            }

            if (_filterQuality != null && item.quality != null) {
              final quality = item.quality!.toLowerCase();
              switch (_filterQuality) {
                case 'hires':
                  if (!quality.startsWith('24')) return false;
                case 'cd':
                  if (!quality.startsWith('16')) return false;
                case 'lossy':
                  if (quality.startsWith('24') || quality.startsWith('16')) {
                    return false;
                  }
              }
            } else if (_filterQuality != null && item.quality == null) {
              if (_filterQuality != 'lossy') return false;
            }

            if (_filterFormat != null) {
              final ext = _itemFormatLower(item);
              if (ext != _filterFormat) return false;
            }

            if (!_queueUnifiedItemMatchesMetadataFilter(
              item,
              _filterMetadata,
            )) {
              return false;
            }

            return true;
          })
          .toList(growable: false);
    }

    return _applySorting(filtered);
  }

  List<UnifiedLibraryItem> _applySorting(List<UnifiedLibraryItem> items) {
    if (_sortMode == 'latest') {
      return items;
    }
    final sorted = List<UnifiedLibraryItem>.of(items);
    switch (_sortMode) {
      case 'oldest':
        sorted.sort((a, b) => a.addedAt.compareTo(b.addedAt));
      case 'a-z':
        sorted.sort(
          (a, b) =>
              a.trackName.toLowerCase().compareTo(b.trackName.toLowerCase()),
        );
      case 'z-a':
        sorted.sort(
          (a, b) =>
              b.trackName.toLowerCase().compareTo(a.trackName.toLowerCase()),
        );
      case 'artist-asc':
        sorted.sort((a, b) {
          final comparison = _queueCompareOptionalText(
            a.artistName,
            b.artistName,
          );
          if (comparison != 0) {
            return comparison;
          }
          return _queueCompareOptionalText(a.trackName, b.trackName);
        });
      case 'artist-desc':
        sorted.sort((a, b) {
          final comparison = _queueCompareOptionalText(
            a.artistName,
            b.artistName,
            descending: true,
          );
          if (comparison != 0) {
            return comparison;
          }
          return _queueCompareOptionalText(a.trackName, b.trackName);
        });
      case 'album-asc':
        sorted.sort((a, b) {
          final comparison = _queueCompareOptionalText(
            a.albumName,
            b.albumName,
          );
          if (comparison != 0) {
            return comparison;
          }
          return _queueCompareOptionalText(a.trackName, b.trackName);
        });
      case 'album-desc':
        sorted.sort((a, b) {
          final comparison = _queueCompareOptionalText(
            a.albumName,
            b.albumName,
            descending: true,
          );
          if (comparison != 0) {
            return comparison;
          }
          return _queueCompareOptionalText(a.trackName, b.trackName);
        });
      case 'release-oldest':
        sorted.sort((a, b) {
          final comparison = _queueCompareOptionalDate(
            _queueParseReleaseDate(a.releaseDate),
            _queueParseReleaseDate(b.releaseDate),
          );
          if (comparison != 0) {
            return comparison;
          }
          return _queueCompareOptionalText(a.trackName, b.trackName);
        });
      case 'release-newest':
        sorted.sort((a, b) {
          final comparison = _queueCompareOptionalDate(
            _queueParseReleaseDate(a.releaseDate),
            _queueParseReleaseDate(b.releaseDate),
            descending: true,
          );
          if (comparison != 0) {
            return comparison;
          }
          return _queueCompareOptionalText(a.trackName, b.trackName);
        });
      case 'genre-asc':
        sorted.sort((a, b) {
          final comparison = _queueCompareOptionalText(a.genre, b.genre);
          if (comparison != 0) {
            return comparison;
          }
          return _queueCompareOptionalText(a.trackName, b.trackName);
        });
      case 'genre-desc':
        sorted.sort((a, b) {
          final comparison = _queueCompareOptionalText(
            a.genre,
            b.genre,
            descending: true,
          );
          if (comparison != 0) {
            return comparison;
          }
          return _queueCompareOptionalText(a.trackName, b.trackName);
        });
    }
    return sorted;
  }

  Set<String> _getAvailableFormats(List<UnifiedLibraryItem> items) {
    final formats = <String>{};
    for (final item in items) {
      final ext = _itemFormatLower(item);
      if ([
        'flac',
        'alac',
        'mp3',
        'm4a',
        'aac',
        'eac3',
        'ac3',
        'ac4',
        'opus',
        'ogg',
        'wav',
        'aiff',
      ].contains(ext)) {
        formats.add(ext);
      }
    }
    return formats;
  }

  void _showFilterSheet(
    BuildContext context,
    List<UnifiedLibraryItem> allItems,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final availableFormats = _getAvailableFormats(allItems);

    String? tempSource = _filterSource;
    String? tempQuality = _filterQuality;
    String? tempFormat = _filterFormat;
    String? tempMetadata = _filterMetadata;
    String tempSortMode = _sortMode;

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxSheetHeight = constraints.maxHeight * 0.9;
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxSheetHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 32,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),

                          Row(
                            children: [
                              Text(
                                context.l10n.libraryFilterTitle,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () {
                                  setSheetState(() {
                                    tempSource = null;
                                    tempQuality = null;
                                    tempFormat = null;
                                    tempMetadata = null;
                                    tempSortMode = 'latest';
                                  });
                                },
                                child: Text(context.l10n.libraryFilterReset),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Text(
                            context.l10n.libraryFilterSource,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilterChip(
                                label: Text(context.l10n.libraryFilterAll),
                                selected: tempSource == null,
                                onSelected: (_) =>
                                    setSheetState(() => tempSource = null),
                              ),
                              FilterChip(
                                label: Text(
                                  context.l10n.libraryFilterDownloaded,
                                ),
                                selected: tempSource == 'downloaded',
                                onSelected: (_) => setSheetState(
                                  () => tempSource = 'downloaded',
                                ),
                              ),
                              FilterChip(
                                label: Text(context.l10n.libraryFilterLocal),
                                selected: tempSource == 'local',
                                onSelected: (_) =>
                                    setSheetState(() => tempSource = 'local'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Text(
                            context.l10n.libraryFilterQuality,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilterChip(
                                label: Text(context.l10n.libraryFilterAll),
                                selected: tempQuality == null,
                                onSelected: (_) =>
                                    setSheetState(() => tempQuality = null),
                              ),
                              FilterChip(
                                label: Text(
                                  context.l10n.libraryFilterQualityHiRes,
                                ),
                                selected: tempQuality == 'hires',
                                onSelected: (_) =>
                                    setSheetState(() => tempQuality = 'hires'),
                              ),
                              FilterChip(
                                label: Text(
                                  context.l10n.libraryFilterQualityCD,
                                ),
                                selected: tempQuality == 'cd',
                                onSelected: (_) =>
                                    setSheetState(() => tempQuality = 'cd'),
                              ),
                              FilterChip(
                                label: Text(
                                  context.l10n.libraryFilterQualityLossy,
                                ),
                                selected: tempQuality == 'lossy',
                                onSelected: (_) =>
                                    setSheetState(() => tempQuality = 'lossy'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Text(
                            context.l10n.libraryFilterFormat,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilterChip(
                                label: Text(context.l10n.libraryFilterAll),
                                selected: tempFormat == null,
                                onSelected: (_) =>
                                    setSheetState(() => tempFormat = null),
                              ),
                              for (final format
                                  in availableFormats.toList()..sort())
                                FilterChip(
                                  label: Text(format.toUpperCase()),
                                  selected: tempFormat == format,
                                  onSelected: (_) =>
                                      setSheetState(() => tempFormat = format),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Text(
                            context.l10n.libraryFilterMetadata,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilterChip(
                                label: Text(context.l10n.libraryFilterAll),
                                selected: tempMetadata == null,
                                onSelected: (_) =>
                                    setSheetState(() => tempMetadata = null),
                              ),
                              FilterChip(
                                label: Text(
                                  context.l10n.libraryFilterMetadataComplete,
                                ),
                                selected: tempMetadata == 'complete',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'complete',
                                ),
                              ),
                              FilterChip(
                                label: Text(
                                  context.l10n.libraryFilterMetadataMissingAny,
                                ),
                                selected: tempMetadata == 'missing-any',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-any',
                                ),
                              ),
                              FilterChip(
                                label: Text(
                                  context.l10n.libraryFilterMetadataMissingYear,
                                ),
                                selected: tempMetadata == 'missing-year',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-year',
                                ),
                              ),
                              FilterChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingGenre,
                                ),
                                selected: tempMetadata == 'missing-genre',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-genre',
                                ),
                              ),
                              FilterChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingAlbumArtist,
                                ),
                                selected:
                                    tempMetadata == 'missing-album-artist',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-album-artist',
                                ),
                              ),
                              FilterChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingTrackNumber,
                                ),
                                selected:
                                    tempMetadata == 'missing-track-number',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-track-number',
                                ),
                              ),
                              FilterChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingDiscNumber,
                                ),
                                selected: tempMetadata == 'missing-disc-number',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-disc-number',
                                ),
                              ),
                              FilterChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingArtist,
                                ),
                                selected: tempMetadata == 'missing-artist',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-artist',
                                ),
                              ),
                              FilterChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataIncorrectIsrcFormat,
                                ),
                                selected:
                                    tempMetadata == 'incorrect-isrc-format',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'incorrect-isrc-format',
                                ),
                              ),
                              FilterChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingLabel,
                                ),
                                selected: tempMetadata == 'missing-label',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-label',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Text(
                            context.l10n.libraryFilterSort,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilterChip(
                                label: Text(
                                  context.l10n.libraryFilterSortLatest,
                                ),
                                selected: tempSortMode == 'latest',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'latest',
                                ),
                              ),
                              FilterChip(
                                label: Text(
                                  context.l10n.libraryFilterSortOldest,
                                ),
                                selected: tempSortMode == 'oldest',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'oldest',
                                ),
                              ),
                              FilterChip(
                                label: Text(context.l10n.searchSortTitleAZ),
                                selected: tempSortMode == 'a-z',
                                onSelected: (_) =>
                                    setSheetState(() => tempSortMode = 'a-z'),
                              ),
                              FilterChip(
                                label: Text(context.l10n.searchSortTitleZA),
                                selected: tempSortMode == 'z-a',
                                onSelected: (_) =>
                                    setSheetState(() => tempSortMode = 'z-a'),
                              ),
                              FilterChip(
                                label: Text(context.l10n.searchSortArtistAZ),
                                selected: tempSortMode == 'artist-asc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'artist-asc',
                                ),
                              ),
                              FilterChip(
                                label: Text(context.l10n.searchSortArtistZA),
                                selected: tempSortMode == 'artist-desc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'artist-desc',
                                ),
                              ),
                              FilterChip(
                                label: Text(
                                  context.l10n.libraryFilterSortAlbumAsc,
                                ),
                                selected: tempSortMode == 'album-asc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'album-asc',
                                ),
                              ),
                              FilterChip(
                                label: Text(
                                  context.l10n.libraryFilterSortAlbumDesc,
                                ),
                                selected: tempSortMode == 'album-desc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'album-desc',
                                ),
                              ),
                              FilterChip(
                                label: Text(context.l10n.searchSortDateNewest),
                                selected: tempSortMode == 'release-newest',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'release-newest',
                                ),
                              ),
                              FilterChip(
                                label: Text(context.l10n.searchSortDateOldest),
                                selected: tempSortMode == 'release-oldest',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'release-oldest',
                                ),
                              ),
                              FilterChip(
                                label: Text(
                                  context.l10n.libraryFilterSortGenreAsc,
                                ),
                                selected: tempSortMode == 'genre-asc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'genre-asc',
                                ),
                              ),
                              FilterChip(
                                label: Text(
                                  context.l10n.libraryFilterSortGenreDesc,
                                ),
                                selected: tempSortMode == 'genre-desc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'genre-desc',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () {
                                setState(() {
                                  _filterSource = tempSource;
                                  _filterQuality = tempQuality;
                                  _filterFormat = tempFormat;
                                  _filterMetadata = tempMetadata;
                                  _sortMode = tempSortMode;
                                  _resetLibraryPaging();
                                  _unifiedItemsCache.clear();
                                  _invalidateFilterContentCache();
                                });
                                Navigator.pop(context);
                              },
                              child: Text(context.l10n.libraryFilterApply),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _openFile(
    String filePath, {
    String title = '',
    String artist = '',
    String album = '',
    String coverUrl = '',
  }) async {
    final cleanPath = _cleanFilePath(filePath);
    try {
      final fallbackTitle = cleanPath.split('/').last.split('\\').last;
      await ref
          .read(playbackProvider.notifier)
          .playLocalPath(
            path: cleanPath,
            title: title.isNotEmpty ? title : fallbackTitle,
            artist: artist,
            album: album,
            coverUrl: coverUrl,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.snackbarCannotOpenFile(e.toString())),
          ),
        );
      }
    }
  }

  /// Plays [item] and queues the rest of the merged library (downloaded + local
  /// in display order) so playback continues to the next track. Honors player
  /// mode and shuffle.
  Future<void> _playLibraryItem(
    UnifiedLibraryItem item,
    List<UnifiedLibraryItem> libraryItems,
  ) async {
    final playableItems = libraryItems
        .where(
          (u) => u.filePath.trim().isNotEmpty && !isCueVirtualPath(u.filePath),
        )
        .toList();
    if (playableItems.isEmpty) return;

    var start = playableItems.indexWhere((u) => u.id == item.id);
    if (start < 0) start = 0;

    try {
      await ref
          .read(playbackProvider.notifier)
          .playMediaQueue(
            playableItems.map(_toPlayableMedia),
            startIndex: start,
            externalPath: item.filePath,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.snackbarCannotOpenFile(e.toString())),
          ),
        );
      }
    }
  }

  PlayableMedia _toPlayableMedia(UnifiedLibraryItem item) {
    final history = item.historyItem;
    if (history != null) return playableFromHistory(history);
    final local = item.localItem;
    if (local != null) return playableFromLocal(local);

    final cover = item.coverUrl ?? item.localCoverPath ?? '';
    String? art;
    if (cover.isNotEmpty) {
      art =
          (cover.startsWith('http') ||
              cover.startsWith('content://') ||
              cover.startsWith('file://'))
          ? cover
          : Uri.file(cover).toString();
    }
    return PlayableMedia(
      id: item.id,
      source: item.filePath,
      title: item.trackName,
      artist: item.artistName,
      album: item.albumName,
      artUri: art,
    );
  }

  void _precacheCover(String? url) {
    if (url == null || url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return;
    }
    final dpr = MediaQuery.devicePixelRatioOf(
      context,
    ).clamp(1.0, 3.0).toDouble();
    final targetSize = (360 * dpr).round().clamp(512, 1024).toInt();
    precacheImage(
      ResizeImage(
        cachedCoverImageProvider(url),
        width: targetSize,
        height: targetSize,
      ),
      context,
    );
  }

  Future<void> _navigateToMetadataScreen(DownloadItem item) async {
    final historyItem = ref
        .read(downloadHistoryProvider)
        .items
        .firstWhere(
          (h) => h.filePath == item.filePath,
          orElse: () => DownloadHistoryItem(
            id: item.id,
            trackName: item.track.name,
            artistName: item.track.artistName,
            albumName: item.track.albumName,
            coverUrl: item.track.coverUrl,
            filePath: item.filePath ?? '',
            downloadedAt: DateTime.now(),
            service: item.service,
          ),
        );

    final navigator = Navigator.of(context);
    _precacheCover(historyItem.coverUrl);
    _searchFocusNode.unfocus();
    final beforeModTime = await _readFileModTimeMillis(historyItem.filePath);
    if (!mounted) return;
    final result = await navigator.push(
      slidePageRoute<bool>(page: TrackMetadataScreen(item: historyItem)),
    );
    _searchFocusNode.unfocus();
    if (result == true) {
      await _scheduleDownloadedEmbeddedCoverRefreshForPath(
        historyItem.filePath,
        beforeModTime: beforeModTime,
        force: true,
      );
      return;
    }
    await _scheduleDownloadedEmbeddedCoverRefreshForPath(
      historyItem.filePath,
      beforeModTime: beforeModTime,
    );
  }

  Future<void> _navigateToHistoryMetadataScreen(
    DownloadHistoryItem item, {
    List<DownloadHistoryItem>? navigationItems,
    int? navigationIndex,
  }) async {
    final navigator = Navigator.of(context);
    _precacheCover(item.coverUrl);
    _searchFocusNode.unfocus();
    final beforeModTime = await _readFileModTimeMillis(item.filePath);
    if (!mounted) return;
    final result = await navigator.push(
      slidePageRoute<bool>(
        page: TrackMetadataScreen(
          item: item,
          historyNavigationItems: navigationItems,
          navigationIndex: navigationIndex,
          coverHeroTag: 'cover_lib_dl_${item.id}',
        ),
      ),
    );
    _searchFocusNode.unfocus();
    if (result == true) {
      await _scheduleDownloadedEmbeddedCoverRefreshForPath(
        item.filePath,
        beforeModTime: beforeModTime,
        force: true,
      );
      return;
    }
    await _scheduleDownloadedEmbeddedCoverRefreshForPath(
      item.filePath,
      beforeModTime: beforeModTime,
    );
  }

  void _navigateToLocalMetadataScreen(
    LocalLibraryItem item, {
    List<LocalLibraryItem>? navigationItems,
    int? navigationIndex,
  }) {
    _searchFocusNode.unfocus();
    Navigator.push(
      context,
      slidePageRoute<void>(
        page: TrackMetadataScreen(
          localItem: item,
          localNavigationItems: navigationItems,
          navigationIndex: navigationIndex,
          coverHeroTag: 'cover_lib_local_${item.id}',
        ),
      ),
    ).then((_) => _searchFocusNode.unfocus());
  }

  List<DownloadHistoryItem> _filterHistoryItems(
    List<DownloadHistoryItem> items,
    String filterMode,
    Map<String, int> albumCounts, [
    String searchQuery = '',
  ]) {
    var filteredItems = items;
    if (searchQuery.isNotEmpty) {
      final query = searchQuery;
      filteredItems = items.where((item) {
        final searchKey = _historySearchKeyForItem(item);
        return searchKey.contains(query);
      }).toList();
    }

    if (filterMode == 'all') return filteredItems;

    switch (filterMode) {
      case 'albums':
        return filteredItems.where((item) {
          final key =
              '${item.albumName.toLowerCase()}|${(item.albumArtist ?? item.artistName).toLowerCase()}';
          return (albumCounts[key] ?? 0) > 1;
        }).toList();
      case 'singles':
        return filteredItems.where((item) {
          final key =
              '${item.albumName.toLowerCase()}|${(item.albumArtist ?? item.artistName).toLowerCase()}';
          return (albumCounts[key] ?? 0) == 1;
        }).toList();
      default:
        return filteredItems;
    }
  }

  void _navigateWithUnfocus(Route<dynamic> route) {
    _searchFocusNode.unfocus();
    Navigator.of(context).push(route).then((_) => _searchFocusNode.unfocus());
  }

  void _navigateToDownloadedAlbum(_GroupedAlbum album) {
    _navigateWithUnfocus(
      slidePageRoute(
        page: DownloadedAlbumScreen(
          albumName: album.albumName,
          artistName: album.artistName,
          coverUrl: album.coverUrl,
        ),
      ),
    );
  }

  Future<void> _navigateToLocalAlbum(_GroupedLocalAlbum album) async {
    var tracks = album.tracks;
    if (tracks.isEmpty && album.displayTrackCount > 0) {
      var rows = album.albumKey.isNotEmpty
          ? await LibraryDatabase.instance.getQueueLocalAlbumTracksByKey(
              album.albumKey,
            )
          : await LibraryDatabase.instance.getQueueLocalAlbumTracks(
              album.albumName,
              album.artistName,
            );
      if (rows.isEmpty && album.albumKey.isNotEmpty) {
        rows = await LibraryDatabase.instance.getQueueLocalAlbumTracks(
          album.albumName,
          album.artistName,
        );
      }
      tracks = rows.map(LocalLibraryItem.fromJson).toList(growable: false);
      if (!mounted) return;
    }
    _navigateWithUnfocus(
      slidePageRoute(
        page: LocalAlbumScreen(
          albumName: album.albumName,
          artistName: album.artistName,
          coverPath: album.coverPath,
          tracks: tracks,
        ),
      ),
    );
  }

  void _openWishlistFolder() {
    _navigateWithUnfocus(
      MaterialPageRoute(
        builder: (_) => const LibraryTracksFolderScreen(
          mode: LibraryTracksFolderMode.wishlist,
        ),
      ),
    );
  }

  void _openLovedFolder() {
    _navigateWithUnfocus(
      MaterialPageRoute(
        builder: (_) => const LibraryTracksFolderScreen(
          mode: LibraryTracksFolderMode.loved,
        ),
      ),
    );
  }

  void _openFavoriteArtistsFolder() {
    _navigateWithUnfocus(
      MaterialPageRoute(builder: (_) => const FavoriteArtistsScreen()),
    );
  }

  void _openPlaylistById(String playlistId) {
    _navigateWithUnfocus(
      MaterialPageRoute(
        builder: (_) => LibraryTracksFolderScreen(
          mode: LibraryTracksFolderMode.playlist,
          playlistId: playlistId,
        ),
      ),
    );
  }

  Future<void> _showCreatePlaylistDialog(BuildContext context) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final playlistName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(dialogContext.l10n.collectionCreatePlaylist),
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
              child: Text(dialogContext.l10n.actionCreate),
            ),
          ],
        );
      },
    );

    if (playlistName == null || playlistName.isEmpty) return;
    await ref
        .read(libraryCollectionsProvider.notifier)
        .createPlaylist(playlistName);
  }

  /// Pass a finite [size] (e.g. 56) for list view, or `null` for grid view
  /// where the widget should expand to fill its parent.
  Widget _buildPlaylistCover(
    BuildContext context,
    UserPlaylistCollection playlist,
    ColorScheme colorScheme, [
    double? size,
  ]) {
    final borderRadius = BorderRadius.circular(8);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheExtent = size != null
        ? (size * dpr).round().clamp(64, 1024)
        : 420;
    final placeholder = _playlistIconFallback(colorScheme, size);

    final customCoverPath = playlist.coverImagePath;
    if (customCoverPath != null && customCoverPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          File(customCoverPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: cacheExtent,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return placeholder;
          },
          errorBuilder: (_, _, _) => placeholder,
        ),
      );
    }

    final firstCoverUrl = playlist.tracks
        .where((e) => e.track.coverUrl != null && e.track.coverUrl!.isNotEmpty)
        .map((e) => e.track.coverUrl!)
        .firstOrNull;

    if (firstCoverUrl != null) {
      // Guard against local file paths that may have been stored as coverUrl
      final isLocalPath =
          !firstCoverUrl.startsWith('http://') &&
          !firstCoverUrl.startsWith('https://');
      if (isLocalPath) {
        return ClipRRect(
          borderRadius: borderRadius,
          child: Image.file(
            File(firstCoverUrl),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: cacheExtent,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) return child;
              return placeholder;
            },
            errorBuilder: (_, _, _) => placeholder,
          ),
        );
      }
      return CachedCoverImage(
        imageUrl: firstCoverUrl,
        width: size,
        height: size,
        memCacheWidth: cacheExtent,
        borderRadius: borderRadius,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      );
    }

    return placeholder;
  }

  /// Icon fallback for playlists with no cover.
  /// When [size] is null the container expands to fill its parent (grid view)
  /// and uses a fixed icon size.
  Widget _playlistIconFallback(ColorScheme colorScheme, [double? size]) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF5085A5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.queue_music,
        color: Colors.white,
        size: size != null ? size * 0.5 : 40,
      ),
    );
  }

  /// Handle a track being dropped onto a playlist.
  /// When selection mode is active and the dragged item is among the selected,
  /// all selected tracks are added to the playlist.
  Future<void> _onTrackDroppedOnPlaylist(
    BuildContext context,
    UnifiedLibraryItem item,
    String playlistId,
    String playlistName, {
    List<UnifiedLibraryItem> allItems = const [],
  }) async {
    final notifier = ref.read(libraryCollectionsProvider.notifier);

    if (_isSelectionMode &&
        _selectedIds.isNotEmpty &&
        _selectedIds.contains(item.id)) {
      final selectedItems = allItems
          .where((e) => _selectedIds.contains(e.id))
          .toList();
      if (selectedItems.isEmpty) {
        selectedItems.add(item);
      }

      final batchResult = await notifier.addTracksToPlaylist(
        playlistId,
        selectedItems.map((selected) => selected.toTrack()),
      );
      final addedCount = batchResult.addedCount;
      final alreadyCount = batchResult.alreadyInPlaylistCount;

      if (!context.mounted) return;
      final message = addedCount > 0
          ? alreadyCount > 0
                ? context.l10n.collectionAddedTracksToPlaylistWithExisting(
                    addedCount,
                    playlistName,
                    alreadyCount,
                  )
                : context.l10n.collectionAddedTracksToPlaylist(
                    addedCount,
                    playlistName,
                  )
          : context.l10n.collectionAlreadyInPlaylist(playlistName);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      _exitSelectionMode();
      return;
    }

    final track = item.toTrack();
    final added = await notifier.addTrackToPlaylist(playlistId, track);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? context.l10n.collectionAddedToPlaylist(playlistName)
              : context.l10n.collectionAlreadyInPlaylist(playlistName),
        ),
      ),
    );
  }

  Widget _buildDragFeedback(
    BuildContext context,
    UnifiedLibraryItem item,
    ColorScheme colorScheme,
  ) {
    final isDraggingMultiple =
        _isSelectionMode &&
        _selectedIds.contains(item.id) &&
        _selectedIds.length > 1;
    final count = isDraggingMultiple ? _selectedIds.length : 1;

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_add, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                isDraggingMultiple ? '$count tracks' : item.trackName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _initializePageController();

    ref.listen(downloadQueueLookupProvider, (previous, next) {
      if (previous == null) return;
      for (final id in previous.itemIds) {
        final prevItem = previous.byItemId[id];
        final nextItem = next.byItemId[id];
        if (prevItem == null) continue;
        final wasActive =
            prevItem.status == DownloadStatus.downloading ||
            prevItem.status == DownloadStatus.finalizing ||
            prevItem.status == DownloadStatus.queued;
        final nowCompleted =
            nextItem != null && nextItem.status == DownloadStatus.completed;
        if (wasActive && nowCompleted) {
          _completionBridge[id] = nextItem.track;
          _completionBridgeAt[id] = DateTime.now();
        }
      }
    });
    ref.listen<int>(
      downloadHistoryProvider.select((state) => state.loadedIndexVersion),
      (previous, next) {
        if (previous == null || previous == next) return;
        _invalidateLibraryDataCaches();
        _resetLibraryPaging();
        if (mounted) setState(() {});
      },
    );
    ref.listen<int>(
      localLibraryProvider.select((state) => state.loadedIndexVersion),
      (previous, next) {
        if (previous == null || previous == next) return;
        _invalidateLibraryDataCaches();
        _resetLibraryPaging();
        if (mounted) setState(() {});
      },
    );

    final hasQueueItems = ref.watch(
      downloadQueueLookupProvider.select((lookup) => lookup.itemIds.isNotEmpty),
    );
    final historyTotalCount = ref.watch(
      downloadHistoryProvider.select((state) => state.totalCount),
    );
    final localLibraryTotalCount = ref.watch(
      localLibraryProvider.select((state) => state.totalCount),
    );
    final localLibraryEnabled = ref.watch(
      settingsProvider.select((s) => s.localLibraryEnabled),
    );
    // Watch with selector on key fields to reduce unnecessary rebuilds.
    // LibraryCollectionsState doesn't implement == so watching without
    // selector rebuilds on every provider notification.
    ref.watch(
      libraryCollectionsProvider.select(
        (s) => (
          s.wishlistCount,
          s.lovedCount,
          s.favoriteArtistCount,
          s.playlistCount,
          s.hasPlaylistTracks,
          s.isLoaded,
        ),
      ),
    );
    final collectionState = ref.read(libraryCollectionsProvider);
    final historyViewMode = ref.watch(
      settingsProvider.select((s) => s.historyViewMode),
    );
    final historyFilterMode = ref.watch(
      settingsProvider.select((s) => s.historyFilterMode),
    );
    final colorScheme = Theme.of(context).colorScheme;
    final topPadding = normalizedHeaderTopPadding(context);
    final countsRequest = _QueueLibraryCountsRequest(
      searchQuery: _searchQuery,
      filterSource: _filterSource,
      filterQuality: _filterQuality,
      filterFormat: _filterFormat,
      filterMetadata: _filterMetadata,
      localLibraryEnabled: localLibraryEnabled,
    );
    final countsValue = ref.watch(_queueLibraryCountsProvider(countsRequest));
    final queueCounts = _resolveQueueLibraryCounts(countsValue, countsRequest);

    _QueueLibraryPageRequest pageRequest(String filterMode) =>
        _QueueLibraryPageRequest(
          filterMode: filterMode,
          limit: _libraryPageSize,
          offset: _libraryPageOffsetFor(filterMode),
          searchQuery: _searchQuery,
          filterSource: _filterSource,
          filterQuality: _filterQuality,
          filterFormat: _filterFormat,
          filterMetadata: _filterMetadata,
          sortMode: _sortMode,
          localLibraryEnabled: localLibraryEnabled,
        );

    final activePageRequest = pageRequest(historyFilterMode);
    final activePageValue = ref.watch(
      _queueLibraryPageProvider(activePageRequest),
    );

    _QueueLibraryPageData pageData(String filterMode) {
      final request = filterMode == historyFilterMode
          ? activePageRequest
          : pageRequest(filterMode);
      return _resolveQueueLibraryPageData(
        filterMode == historyFilterMode ? activePageValue : null,
        request,
      );
    }

    _FilterContentData getFilterData(String filterMode) {
      return pageData(filterMode).toFilterContentData(
        collectionState,
        totalTrackCount: switch (filterMode) {
          'singles' => queueCounts.singleTrackCount,
          'albums' => 0,
          _ => queueCounts.allTrackCount,
        },
        totalAlbumCount: filterMode == 'albums' ? queueCounts.albumCount : null,
      );
    }

    final currentPageData = pageData(historyFilterMode);
    final currentLoadedCount = historyFilterMode == 'albums'
        ? currentPageData.groupedAlbums.length +
              currentPageData.groupedLocalAlbums.length
        : currentPageData.items.length;
    final currentTotalCount = switch (historyFilterMode) {
      'albums' => queueCounts.albumCount,
      'singles' => queueCounts.singleTrackCount,
      _ => queueCounts.allTrackCount,
    };
    final hasMoreLibrary = currentLoadedCount < currentTotalCount;
    final isLibraryPageLoading =
        countsValue.isLoading || activePageValue.isLoading;
    final hasAnyLibraryItems =
        queueCounts.allTrackCount > 0 || queueCounts.albumCount > 0;
    final hasLibraryContent =
        historyTotalCount > 0 ||
        (localLibraryEnabled && localLibraryTotalCount > 0);
    final hasActiveSearch =
        _searchQuery.isNotEmpty || _searchController.text.trim().isNotEmpty;
    final shouldShowLibraryControls =
        hasLibraryContent || hasAnyLibraryItems || hasActiveSearch;
    _scheduleBlankLibraryRepair(
      hasQueueItems: hasQueueItems,
      hasLibraryContent: hasLibraryContent,
      hasAnyLibraryItems: hasAnyLibraryItems,
      isLibraryPageLoading: isLibraryPageLoading,
    );

    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final bottomInset = context.navBarBottomInset;
    final selectionItems = getFilterData(
      historyFilterMode,
    ).filteredUnifiedItems;
    if (_isSelectionMode || _isPlaylistSelectionMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isSelectionMode) {
          _syncSelectionOverlay(
            items: selectionItems,
            bottomPadding: bottomPadding,
          );
        }
        if (_isPlaylistSelectionMode) {
          _syncPlaylistSelectionOverlay(
            playlists: collectionState.playlists,
            bottomPadding: bottomPadding,
          );
        }
      });
    }

    return PopScope(
      canPop: !_isSelectionMode && !_isPlaylistSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_isPlaylistSelectionMode) {
            _exitPlaylistSelectionMode();
          } else if (_isSelectionMode) {
            _exitSelectionMode();
          }
        }
      },
      child: Stack(
        children: [
          // ScrollConfiguration disables stretch overscroll to fix _StretchController exception
          // This is a known Flutter issue with NestedScrollView + Material 3 stretch indicator
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(overscroll: false),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  expandedHeight: 120 + topPadding,
                  collapsedHeight: kToolbarHeight,
                  floating: false,
                  pinned: true,
                  backgroundColor: colorScheme.surface,
                  surfaceTintColor: Colors.transparent,
                  automaticallyImplyLeading: false,
                  flexibleSpace: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxHeight = 120 + topPadding;
                      final minHeight = kToolbarHeight + topPadding;
                      final expandRatio =
                          ((constraints.maxHeight - minHeight) /
                                  (maxHeight - minHeight))
                              .clamp(0.0, 1.0);

                      return FlexibleSpaceBar(
                        expandedTitleScale: 1.0,
                        titlePadding: const EdgeInsets.only(
                          left: 24,
                          bottom: 16,
                        ),
                        title: Text(
                          context.l10n.navLibrary,
                          style: TextStyle(
                            fontSize: 20 + (14 * expandRatio),
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                if (shouldShowLibraryControls || hasQueueItems)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: GestureDetector(
                        onTap: () {},
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          autofocus: false,
                          canRequestFocus: true,
                          decoration: InputDecoration(
                            hintText: context.l10n.historySearchHint,
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    tooltip: context.l10n.dialogClear,
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      _clearSearch();
                                      FocusScope.of(context).unfocus();
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: settingsGroupColor(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide(
                                color: colorScheme.primary,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                          ),
                          onChanged: _onSearchChanged,
                          onTapOutside: (_) {
                            FocusScope.of(context).unfocus();
                          },
                        ),
                      ),
                    ),
                  ),

                if (shouldShowLibraryControls)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Builder(
                        builder: (context) {
                          int filteredAllCount;
                          int filteredAlbumCount;
                          int filteredSingleCount;

                          filteredAllCount = queueCounts.allTrackCount;
                          filteredAlbumCount = queueCounts.albumCount;
                          filteredSingleCount = queueCounts.singleTrackCount;

                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _FilterChip(
                                  label: context.l10n.historyFilterAll,
                                  count: filteredAllCount,
                                  isSelected: historyFilterMode == 'all',
                                  onTap: () {
                                    _animateToFilterPage(0);
                                  },
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: context.l10n.historyFilterAlbums,
                                  count: filteredAlbumCount,
                                  isSelected: historyFilterMode == 'albums',
                                  onTap: () {
                                    _animateToFilterPage(1);
                                  },
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: context.l10n.historyFilterSingles,
                                  count: filteredSingleCount,
                                  isSelected: historyFilterMode == 'singles',
                                  onTap: () {
                                    _animateToFilterPage(2);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
              body: PageView.builder(
                controller: _filterPageController!,
                physics: const ClampingScrollPhysics(),
                onPageChanged: _onFilterPageChanged,
                itemCount: _filterModes.length,
                itemBuilder: (context, index) {
                  final filterMode = _filterModes[index];
                  final filterData = getFilterData(filterMode);
                  return _buildFilterContent(
                    context: context,
                    colorScheme: colorScheme,
                    filterMode: filterMode,
                    historyViewMode: historyViewMode,
                    hasQueueItems: hasQueueItems,
                    filterData: filterData,
                    collectionState: collectionState,
                    hasMoreLibrary: filterMode == historyFilterMode
                        ? hasMoreLibrary
                        : false,
                    isPageLoading: isLibraryPageLoading,
                    bottomInset: bottomInset,
                  );
                },
              ),
            ),
          ), // ScrollConfiguration
        ],
      ),
    );
  }

  List<UnifiedLibraryItem> _getUnifiedItems({
    required String filterMode,
    required List<DownloadHistoryItem> historyItems,
    required List<LocalLibraryItem> localLibraryItems,
    required Map<String, int> localAlbumCounts,
  }) {
    if (filterMode == 'albums') return const [];

    final query = _searchQuery;
    final cached = _unifiedItemsCache[filterMode];
    if (cached != null &&
        identical(cached.historyItems, historyItems) &&
        identical(cached.localItems, localLibraryItems) &&
        identical(cached.localAlbumCounts, localAlbumCounts) &&
        cached.query == query) {
      return cached.items;
    }

    final unifiedDownloaded = _unifiedDownloadedItems(historyItems);

    List<LocalLibraryItem> localItemsForMerge;
    if (filterMode == 'all') {
      localItemsForMerge = _filterLocalItems(localLibraryItems, query);
    } else {
      final localSingles = _localSingleItems(
        localLibraryItems,
        localAlbumCounts,
      );
      localItemsForMerge = _filterLocalItems(localSingles, query);
    }

    final unifiedLocal = _unifiedLocalItems(localItemsForMerge);
    final downloadedPathKeys = _downloadedPathKeys(historyItems);

    final dedupedUnifiedLocal = <UnifiedLibraryItem>[];
    for (final item in unifiedLocal) {
      final localSource = item.localItem;
      final localPathKeys = localSource != null
          ? _localPathMatchKeys(localSource)
          : buildPathMatchKeys(item.filePath);
      final overlapsDownloaded = localPathKeys.any(downloadedPathKeys.contains);
      if (!overlapsDownloaded) {
        dedupedUnifiedLocal.add(item);
      }
    }

    final merged = <UnifiedLibraryItem>[
      ...unifiedDownloaded,
      ...dedupedUnifiedLocal,
    ]..sort((a, b) => b.addedAt.compareTo(a.addedAt));

    _unifiedItemsCache[filterMode] = _UnifiedCacheEntry(
      historyItems: historyItems,
      localItems: localLibraryItems,
      localAlbumCounts: localAlbumCounts,
      query: query,
      items: merged,
    );

    return merged;
  }

  // ignore: unused_element
  _FilterContentData _computeFilterContentData({
    required String filterMode,
    required List<DownloadHistoryItem> allHistoryItems,
    required List<_GroupedAlbum> filteredGroupedAlbums,
    required List<_GroupedLocalAlbum> filteredGroupedLocalAlbums,
    required Map<String, int> albumCounts,
    required Map<String, int> localAlbumCounts,
    required List<LocalLibraryItem> localLibraryItems,
    required LibraryCollectionsState collectionState,
  }) {
    final historyItems = _resolveHistoryItems(
      filterMode: filterMode,
      allHistoryItems: allHistoryItems,
      albumCounts: albumCounts,
    );
    final showFilteringIndicator = _shouldShowFilteringIndicator(
      allHistoryItems: allHistoryItems,
      filterMode: filterMode,
    );

    final unifiedItems = _getUnifiedItems(
      filterMode: filterMode,
      historyItems: historyItems,
      localLibraryItems: localLibraryItems,
      localAlbumCounts: localAlbumCounts,
    );
    final filtered = _applyAdvancedFilters(unifiedItems);

    // Remove tracks that are already in any playlist so they don't appear
    // in the main tracks list.  When a track is removed from a playlist (or
    // the playlist is deleted) it will automatically reappear here because it
    // will no longer be in the set.
    final filteredUnifiedItems = !collectionState.hasPlaylistTracks
        ? filtered
        : filtered
              .where(
                (item) =>
                    !collectionState.isTrackInAnyPlaylist(item.collectionKey),
              )
              .toList(growable: false);

    return _FilterContentData(
      historyItems: historyItems,
      unifiedItems: unifiedItems,
      filteredUnifiedItems: filteredUnifiedItems,
      filteredGroupedAlbums: filteredGroupedAlbums,
      filteredGroupedLocalAlbums: filteredGroupedLocalAlbums,
      showFilteringIndicator: showFilteringIndicator,
    );
  }

  Widget _buildQueueHeaderSliver(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return Consumer(
      builder: (context, ref, child) {
        final queueCount = ref.watch(
          downloadQueueLookupProvider.select((lookup) {
            var count = 0;
            for (final id in lookup.itemIds) {
              final entry = lookup.byItemId[id];
              if (entry != null && entry.status != DownloadStatus.completed) {
                count++;
              }
            }
            return count;
          }),
        );
        final failedCount = ref.watch(
          downloadQueueProvider.select((state) => state.failedCount),
        );
        final isProcessing = ref.watch(
          downloadQueueProvider.select((state) => state.isProcessing),
        );
        final isPaused = ref.watch(
          downloadQueueProvider.select((state) => state.isPaused),
        );
        return SliverToBoxAdapter(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: queueCount == 0
                ? const SizedBox(
                    width: double.infinity,
                    key: ValueKey('dl_header_empty'),
                  )
                : Padding(
                    key: const ValueKey('dl_header'),
                    padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.downloading_rounded,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.queueDownloadingCount(queueCount),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        if (failedCount > 0 && !isProcessing)
                          IconButton(
                            onPressed: () => ref
                                .read(downloadQueueProvider.notifier)
                                .retryAllFailed(),
                            icon: const Icon(Icons.replay_rounded, size: 20),
                            tooltip: context.l10n.queueRetryAllFailed(
                              failedCount,
                            ),
                            color: colorScheme.primary,
                            visualDensity: VisualDensity.compact,
                          ),
                        IconButton(
                          onPressed: () => ref
                              .read(downloadQueueProvider.notifier)
                              .togglePause(),
                          icon: Icon(
                            isPaused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            size: 20,
                          ),
                          tooltip: isPaused
                              ? context.l10n.actionResume
                              : context.l10n.actionPause,
                          color: colorScheme.onSurfaceVariant,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () =>
                              _showClearAllDialog(context, ref, colorScheme),
                          icon: const Icon(Icons.clear_all_rounded, size: 20),
                          tooltip: context.l10n.queueClearAll,
                          color: colorScheme.error,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  Future<void> _confirmCancelDownload(
    BuildContext context,
    DownloadItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.cancelDownloadTitle),
        content: Text(context.l10n.cancelDownloadContent(item.track.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.cancelDownloadKeep),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.dialogCancel),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(downloadQueueProvider.notifier).dismissItem(item.id);
    }
  }

  Future<void> _showDownloadErrorDialog(
    BuildContext context,
    DownloadItem item,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final isRateLimit = item.errorType == DownloadErrorType.rateLimit;
    final title = isRateLimit
        ? context.l10n.queueRateLimitTitle
        : context.l10n.updateDownloadFailed;
    final message = isRateLimit
        ? context.l10n.queueRateLimitMessage
        : (item.errorMessage.trim().isNotEmpty
              ? item.errorMessage
              : context.l10n.updateDownloadFailed);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.track.name,
                style: Theme.of(
                  ctx,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              SelectableText(
                message,
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('remove'),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: Text(context.l10n.dialogRemove),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('retry'),
            child: Text(context.l10n.dialogRetry),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'retry') {
      ref.read(downloadQueueProvider.notifier).retryItem(item.id);
    } else if (action == 'remove') {
      ref.read(downloadQueueProvider.notifier).removeItem(item.id);
    }
  }

  Widget _buildDownloadGridItem(
    BuildContext context,
    DownloadItem item,
    ColorScheme colorScheme,
  ) {
    final radius = BorderRadius.circular(8);
    final isDownloading = item.status == DownloadStatus.downloading;
    final isFinalizing = item.status == DownloadStatus.finalizing;
    final isQueued = item.status == DownloadStatus.queued;
    final isFailed = item.status == DownloadStatus.failed;
    final progress = item.progress.clamp(0.0, 1.0);
    final pct = (progress * 100).round();

    final cover = item.track.coverUrl != null
        ? CachedCoverImage(
            imageUrl: item.track.coverUrl!,
            borderRadius: radius,
            fadeInDuration: const Duration(milliseconds: 180),
          )
        : Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: radius,
            ),
            child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant),
          );

    final onTap = isFailed
        ? () => _showDownloadErrorDialog(context, item)
        : item.status == DownloadStatus.skipped
        ? () => ref.read(downloadQueueProvider.notifier).removeItem(item.id)
        : () => _confirmCancelDownload(context, item);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(borderRadius: radius, child: cover),
                if (isDownloading || isFinalizing || isQueued)
                  ClipRRect(
                    borderRadius: radius,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                  ),
                if (isDownloading || isFinalizing || isQueued)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(
                            value: (isFinalizing || isQueued || progress <= 0)
                                ? null
                                : progress,
                            strokeWidth: 3,
                            color: Colors.white,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.25,
                            ),
                          ),
                        ),
                        if (isDownloading && progress > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            '$pct%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (isFailed)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.error_outline,
                        color: colorScheme.error,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.track.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
          Text(
            item.track.artistName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBridgeGridItem(
    BuildContext context,
    Track track,
    ColorScheme colorScheme,
  ) {
    final radius = BorderRadius.circular(8);
    final cover = track.coverUrl != null
        ? CachedCoverImage(imageUrl: track.coverUrl!, borderRadius: radius)
        : Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: radius,
            ),
            child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(borderRadius: radius, child: cover),
              if (track.hasAudioQuality)
                Positioned(
                  left: 4,
                  top: 4,
                  child: AudioQualityBadge(
                    label: track.audioQuality!,
                    colorScheme: colorScheme,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          track.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
        ),
        Text(
          track.artistName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildBridgeListItem(
    BuildContext context,
    Track track,
    ColorScheme colorScheme,
  ) {
    final coverSize = _queueCoverSize();
    final radius = BorderRadius.circular(8);
    final cover = track.coverUrl != null
        ? CachedCoverImage(
            imageUrl: track.coverUrl!,
            width: coverSize,
            height: coverSize,
            borderRadius: radius,
          )
        : Container(
            width: coverSize,
            height: coverSize,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: radius,
            ),
            child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant),
          );
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            cover,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionListItem({
    required BuildContext context,
    required ColorScheme colorScheme,
    IconData? icon,
    Color? iconColor,
    Color? iconBgColor,
    Widget? coverWidget,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final cover =
        coverWidget ??
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: iconBgColor ?? colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon ?? Icons.folder,
            color: iconColor ?? Colors.white,
            size: 28,
          ),
        );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(width: 56, height: 56, child: cover),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollectionGridItem({
    required BuildContext context,
    required ColorScheme colorScheme,
    IconData? icon,
    Color? iconColor,
    Color? iconBgColor,
    Widget? coverWidget,
    required String title,
    required int count,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final cover =
        coverWidget ??
        Container(
          decoration: BoxDecoration(
            color: iconBgColor ?? colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon ?? Icons.folder,
            color: iconColor ?? Colors.white,
            size: 40,
          ),
        );

    return Semantics(
      button: true,
      label: context.l10n.a11yOpenItemCount(title, count),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: cover,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            ),
            Text(
              context.l10n.itemCount(count),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_CollectionEntry> _getVisibleCollectionEntries(
    LibraryCollectionsState collectionState,
  ) {
    final entries = <_CollectionEntry>[];
    if (collectionState.wishlistCount > 0) {
      entries.add(_CollectionEntry.wishlist);
    }
    if (collectionState.lovedCount > 0) {
      entries.add(_CollectionEntry.loved);
    }
    if (collectionState.favoriteArtistCount > 0) {
      entries.add(_CollectionEntry.favoriteArtists);
    }
    for (var i = 0; i < collectionState.playlists.length; i++) {
      entries.add(_CollectionEntry.playlist(i));
    }
    return entries;
  }

  Widget _buildAllTabGridCollectionItem({
    required BuildContext context,
    required ColorScheme colorScheme,
    required _CollectionEntry entry,
    required LibraryCollectionsState collectionState,
    List<UnifiedLibraryItem> filteredUnifiedItems = const [],
  }) {
    switch (entry.type) {
      case _CollectionEntryType.wishlist:
        return _buildCollectionGridItem(
          context: context,
          colorScheme: colorScheme,
          icon: Icons.add_circle_outline,
          iconColor: Colors.white,
          iconBgColor: const Color(0xFF1DB954),
          title: context.l10n.collectionWishlist,
          count: collectionState.wishlistCount,
          onTap: _openWishlistFolder,
        );
      case _CollectionEntryType.loved:
        return _buildCollectionGridItem(
          context: context,
          colorScheme: colorScheme,
          icon: Icons.favorite,
          iconColor: Colors.white,
          iconBgColor: const Color(0xFF8C67AC),
          title: context.l10n.collectionLoved,
          count: collectionState.lovedCount,
          onTap: _openLovedFolder,
        );
      case _CollectionEntryType.favoriteArtists:
        return _buildCollectionGridItem(
          context: context,
          colorScheme: colorScheme,
          icon: Icons.person,
          iconColor: Colors.white,
          iconBgColor: const Color(0xFFE91E63),
          title: context.l10n.collectionFavoriteArtists,
          count: collectionState.favoriteArtistCount,
          onTap: _openFavoriteArtistsFolder,
        );
      case _CollectionEntryType.playlist:
        final playlist = collectionState.playlists[entry.playlistIndex];
        final isSelected = _selectedPlaylistIds.contains(playlist.id);
        return DragTarget<UnifiedLibraryItem>(
          onWillAcceptWithDetails: (_) => !_isPlaylistSelectionMode,
          onAcceptWithDetails: (details) {
            _onTrackDroppedOnPlaylist(
              context,
              details.data,
              playlist.id,
              playlist.name,
              allItems: filteredUnifiedItems,
            );
          },
          builder: (context, candidateData, rejectedData) {
            final isHovering = candidateData.isNotEmpty;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: isHovering
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.primary, width: 2),
                      color: colorScheme.primary.withValues(alpha: 0.1),
                    )
                  : null,
              child: Stack(
                children: [
                  _buildCollectionGridItem(
                    context: context,
                    colorScheme: colorScheme,
                    coverWidget: _buildPlaylistCover(
                      context,
                      playlist,
                      colorScheme,
                    ),
                    title: playlist.name,
                    count: playlist.tracks.length,
                    onTap: _isPlaylistSelectionMode
                        ? () => _togglePlaylistSelection(playlist.id)
                        : () => _openPlaylistById(playlist.id),
                    onLongPress: _isPlaylistSelectionMode
                        ? () => _togglePlaylistSelection(playlist.id)
                        : () => _enterPlaylistSelectionMode(playlist.id),
                  ),
                  if (_isPlaylistSelectionMode)
                    Positioned(
                      left: 0,
                      top: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colorScheme.primary.withValues(alpha: 0.3)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_isPlaylistSelectionMode)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IgnorePointer(
                        child: AnimatedSelectionCheckbox(
                          visible: true,
                          selected: isSelected,
                          colorScheme: colorScheme,
                          size: 20,
                          unselectedColor: colorScheme.surface.withValues(
                            alpha: 0.85,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
    }
  }

  Widget _buildAllTabListCollectionItem({
    required BuildContext context,
    required ColorScheme colorScheme,
    required _CollectionEntry entry,
    required LibraryCollectionsState collectionState,
    List<UnifiedLibraryItem> filteredUnifiedItems = const [],
  }) {
    switch (entry.type) {
      case _CollectionEntryType.wishlist:
        return _buildCollectionListItem(
          context: context,
          colorScheme: colorScheme,
          icon: Icons.add_circle_outline,
          iconColor: Colors.white,
          iconBgColor: const Color(0xFF1DB954),
          title: context.l10n.collectionWishlist,
          subtitle:
              '${context.l10n.collectionFoldersTitle} • ${collectionState.wishlistCount} ${collectionState.wishlistCount == 1 ? 'track' : 'tracks'}',
          onTap: _openWishlistFolder,
        );
      case _CollectionEntryType.loved:
        return _buildCollectionListItem(
          context: context,
          colorScheme: colorScheme,
          icon: Icons.favorite,
          iconColor: Colors.white,
          iconBgColor: const Color(0xFF8C67AC),
          title: context.l10n.collectionLoved,
          subtitle:
              '${context.l10n.collectionFoldersTitle} • ${collectionState.lovedCount} ${collectionState.lovedCount == 1 ? 'track' : 'tracks'}',
          onTap: _openLovedFolder,
        );
      case _CollectionEntryType.favoriteArtists:
        return _buildCollectionListItem(
          context: context,
          colorScheme: colorScheme,
          icon: Icons.person,
          iconColor: Colors.white,
          iconBgColor: const Color(0xFFE91E63),
          title: context.l10n.collectionFavoriteArtists,
          subtitle:
              '${context.l10n.collectionFoldersTitle} • ${context.l10n.collectionArtistCount(collectionState.favoriteArtistCount)}',
          onTap: _openFavoriteArtistsFolder,
        );
      case _CollectionEntryType.playlist:
        final playlist = collectionState.playlists[entry.playlistIndex];
        final isSelected = _selectedPlaylistIds.contains(playlist.id);
        return DragTarget<UnifiedLibraryItem>(
          onWillAcceptWithDetails: (_) => !_isPlaylistSelectionMode,
          onAcceptWithDetails: (details) {
            _onTrackDroppedOnPlaylist(
              context,
              details.data,
              playlist.id,
              playlist.name,
              allItems: filteredUnifiedItems,
            );
          },
          builder: (context, candidateData, rejectedData) {
            final isHovering = candidateData.isNotEmpty;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: isHovering
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.primary, width: 2),
                      color: colorScheme.primary.withValues(alpha: 0.1),
                    )
                  : null,
              child: Row(
                children: [
                  if (_isPlaylistSelectionMode)
                    GestureDetector(
                      onTap: () => _togglePlaylistSelection(playlist.id),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: AnimatedSelectionCheckbox(
                          visible: true,
                          selected: isSelected,
                          colorScheme: colorScheme,
                          size: 24,
                        ),
                      ),
                    ),
                  Expanded(
                    child: _buildCollectionListItem(
                      context: context,
                      colorScheme: colorScheme,
                      coverWidget: _buildPlaylistCover(
                        context,
                        playlist,
                        colorScheme,
                        56,
                      ),
                      title: playlist.name,
                      subtitle:
                          '${playlist.tracks.length} ${playlist.tracks.length == 1 ? 'track' : 'tracks'}',
                      onTap: _isPlaylistSelectionMode
                          ? () => _togglePlaylistSelection(playlist.id)
                          : () => _openPlaylistById(playlist.id),
                      onLongPress: _isPlaylistSelectionMode
                          ? () => _togglePlaylistSelection(playlist.id)
                          : () => _enterPlaylistSelectionMode(playlist.id),
                    ),
                  ),
                ],
              ),
            );
          },
        );
    }
  }

  Widget _buildFilterContent({
    required BuildContext context,
    required ColorScheme colorScheme,
    required String filterMode,
    required String historyViewMode,
    required bool hasQueueItems,
    required _FilterContentData filterData,
    required LibraryCollectionsState collectionState,
    required bool hasMoreLibrary,
    required bool isPageLoading,
    double bottomInset = 0,
  }) {
    final historyItems = filterData.historyItems;
    final showFilteringIndicator = filterData.showFilteringIndicator;
    final filteredGroupedAlbums = filterData.filteredGroupedAlbums;
    final filteredGroupedLocalAlbums = filterData.filteredGroupedLocalAlbums;
    final unifiedItems = filterData.unifiedItems;
    final filteredUnifiedItems = filterData.filteredUnifiedItems;
    final totalTrackCount = filterData.totalTrackCount;
    final totalAlbumCount = filterData.totalAlbumCount;
    final downloadedNavigationItems = <DownloadHistoryItem>[];
    final downloadedNavigationIndexByUnifiedId = <String, int>{};
    final localNavigationItems = <LocalLibraryItem>[];
    final localNavigationIndexByUnifiedId = <String, int>{};

    for (final item in filteredUnifiedItems) {
      final historyItem = item.historyItem;
      if (historyItem != null) {
        downloadedNavigationIndexByUnifiedId[item.id] =
            downloadedNavigationItems.length;
        downloadedNavigationItems.add(historyItem);
      }

      final localItem = item.localItem;
      if (localItem != null) {
        localNavigationIndexByUnifiedId[item.id] = localNavigationItems.length;
        localNavigationItems.add(localItem);
      }
    }

    final activeDownloadIds = filterMode == 'albums'
        ? const <String>[]
        : ref
              .watch(
                downloadQueueLookupProvider.select((lookup) {
                  final ids = <String>[];
                  for (final id in lookup.itemIds) {
                    final entry = lookup.byItemId[id];
                    if (entry != null &&
                        entry.status != DownloadStatus.completed) {
                      ids.add(id);
                    }
                  }
                  return _QueueItemIdsSnapshot(ids);
                }),
              )
              .ids
              .reversed
              .toList(growable: false);

    final libIdSet = <String>{for (final item in filteredUnifiedItems) item.id};
    List<String> bridgeIds = const [];
    if (filterMode != 'albums' && _completionBridge.isNotEmpty) {
      final now = DateTime.now();
      final stale = <String>[];
      final pending = <String>[];
      _completionBridge.forEach((id, _) {
        final landed = libIdSet.contains('dl_$id');
        final addedAt = _completionBridgeAt[id];
        final expired =
            addedAt == null || now.difference(addedAt).inSeconds >= 6;
        if (landed || expired || activeDownloadIds.contains(id)) {
          stale.add(id);
        } else {
          pending.add(id);
        }
      });
      bridgeIds = pending;
      if (stale.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          var changed = false;
          for (final id in stale) {
            if (_completionBridge.remove(id) != null) changed = true;
            _completionBridgeAt.remove(id);
            _bridgePrecacheStarted.remove(id);
          }
          if (changed) setState(() {});
        });
      }
      final toPrecache = pending
          .where((id) => !_bridgePrecacheStarted.contains(id))
          .toList(growable: false);
      if (toPrecache.isNotEmpty) {
        final historyItems = ref.read(downloadHistoryProvider).items;
        for (final id in toPrecache) {
          DownloadHistoryItem? historyItem;
          for (final h in historyItems) {
            if (h.id == id) {
              historyItem = h;
              break;
            }
          }
          if (historyItem == null) continue;
          _bridgePrecacheStarted.add(id);
          final coverUrl = historyItem.coverUrl;
          final embeddedPath = _resolveDownloadedEmbeddedCoverPath(
            historyItem.filePath,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            try {
              if (embeddedPath != null) {
                precacheImage(FileImage(File(embeddedPath)), context);
              }
              if (coverUrl != null && coverUrl.isNotEmpty) {
                precacheImage(
                  CachedNetworkImageProvider(
                    coverUrl,
                    cacheManager: CoverCacheManager.instance,
                  ),
                  context,
                );
              }
            } catch (_) {}
          });
        }
      }
    }

    final leadCount = activeDownloadIds.length + bridgeIds.length;
    final collectionEntries = filterMode == 'all'
        ? _getVisibleCollectionEntries(collectionState)
        : const <_CollectionEntry>[];
    final collectionCount = collectionEntries.length;

    Widget leadGridCell(int index) {
      if (index < activeDownloadIds.length) {
        final id = activeDownloadIds[index];
        return _QueueItemSliverRow(
          key: ValueKey('dlgrid_$id'),
          itemId: id,
          colorScheme: colorScheme,
          itemBuilder: _buildDownloadGridItem,
        );
      }
      final bridgeId = bridgeIds[index - activeDownloadIds.length];
      return KeyedSubtree(
        key: ValueKey('dlgrid_bridge_$bridgeId'),
        child: _buildBridgeGridItem(
          context,
          _completionBridge[bridgeId]!,
          colorScheme,
        ),
      );
    }

    Widget leadListCell(int index) {
      if (index < activeDownloadIds.length) {
        final id = activeDownloadIds[index];
        return _QueueItemSliverRow(
          key: ValueKey('dllist_$id'),
          itemId: id,
          colorScheme: colorScheme,
          itemBuilder: _buildQueueItem,
        );
      }
      final bridgeId = bridgeIds[index - activeDownloadIds.length];
      return KeyedSubtree(
        key: ValueKey('dllist_bridge_$bridgeId'),
        child: _buildBridgeListItem(
          context,
          _completionBridge[bridgeId]!,
          colorScheme,
        ),
      );
    }

    final content = CustomScrollView(
      slivers: [
        if (totalTrackCount > 0 && filterMode == 'all')
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Text(
                    context.l10n.queueTrackCount(totalTrackCount),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (!_isSelectionMode)
                    _buildFilterButton(context, unifiedItems),
                  if (!_isSelectionMode && filteredUnifiedItems.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _showCreatePlaylistDialog(context),
                      icon: const Icon(Icons.add, size: 20),
                      label: Text(context.l10n.collectionCreatePlaylist),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          ),

        if ((filteredGroupedAlbums.isNotEmpty ||
                filteredGroupedLocalAlbums.isNotEmpty) &&
            filterMode == 'albums')
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Text(
                    context.l10n.queueAlbumCount(totalAlbumCount),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  _buildFilterButton(context, unifiedItems),
                ],
              ),
            ),
          ),

        if (filteredGroupedAlbums.isEmpty &&
            filteredGroupedLocalAlbums.isEmpty &&
            filterMode == 'albums' &&
            (historyItems.isNotEmpty || unifiedItems.isNotEmpty))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  const Spacer(),
                  _buildFilterButton(context, unifiedItems),
                ],
              ),
            ),
          ),

        if (filterMode == 'all' &&
            totalTrackCount == 0 &&
            !showFilteringIndicator &&
            (_activeFilterCount > 0 || unifiedItems.isNotEmpty))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  const Spacer(),
                  if (!_isSelectionMode)
                    _buildFilterButton(context, unifiedItems),
                ],
              ),
            ),
          ),

        if (filterMode == 'singles' &&
            totalTrackCount == 0 &&
            !showFilteringIndicator &&
            (_activeFilterCount > 0 || unifiedItems.isNotEmpty))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  const Spacer(),
                  if (!_isSelectionMode)
                    _buildFilterButton(context, unifiedItems),
                ],
              ),
            ),
          ),

        if (showFilteringIndicator)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    context.l10n.queueFilteringIndicator,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (filterMode == 'all') _buildQueueHeaderSliver(context, colorScheme),

        if (filterMode == 'albums' &&
            (filteredGroupedAlbums.isNotEmpty ||
                filteredGroupedLocalAlbums.isNotEmpty))
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _AnimatedLibrarySliverGrid(
              maxCrossAxisExtent: _libraryAlbumGridExtent,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index < filteredGroupedAlbums.length) {
                    final album = filteredGroupedAlbums[index];
                    return KeyedSubtree(
                      key: ValueKey(album.key),
                      child: _buildAlbumGridItem(context, album, colorScheme),
                    );
                  } else {
                    final localIndex = index - filteredGroupedAlbums.length;
                    final album = filteredGroupedLocalAlbums[localIndex];
                    return KeyedSubtree(
                      key: ValueKey('local_${album.key}'),
                      child: _buildLocalAlbumGridItem(
                        context,
                        album,
                        colorScheme,
                      ),
                    );
                  }
                },
                childCount:
                    filteredGroupedAlbums.length +
                    filteredGroupedLocalAlbums.length,
              ),
            ),
          ),

        if (filterMode == 'all') ...[
          if (historyViewMode == 'grid')
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: _AnimatedLibrarySliverGrid(
                maxCrossAxisExtent: _libraryGridExtent,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.66,
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index < collectionCount) {
                      return _buildAllTabGridCollectionItem(
                        context: context,
                        colorScheme: colorScheme,
                        entry: collectionEntries[index],
                        collectionState: collectionState,
                        filteredUnifiedItems: filteredUnifiedItems,
                      );
                    }
                    final afterCollections = index - collectionCount;
                    if (afterCollections < leadCount) {
                      return leadGridCell(afterCollections);
                    }
                    final trackIndex = afterCollections - leadCount;
                    if (trackIndex < filteredUnifiedItems.length) {
                      final item = filteredUnifiedItems[trackIndex];
                      return KeyedSubtree(
                        key: ValueKey(item.id),
                        child: LongPressDraggable<UnifiedLibraryItem>(
                          data: item,
                          feedback: _buildDragFeedback(
                            context,
                            item,
                            colorScheme,
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.4,
                            child: _buildUnifiedGridItem(
                              context,
                              item,
                              colorScheme,
                              downloadedNavigationItems:
                                  downloadedNavigationItems,
                              downloadedNavigationIndex:
                                  downloadedNavigationIndexByUnifiedId[item.id],
                              localNavigationItems: localNavigationItems,
                              localNavigationIndex:
                                  localNavigationIndexByUnifiedId[item.id],
                              libraryItems: filteredUnifiedItems,
                            ),
                          ),
                          child: _buildUnifiedGridItem(
                            context,
                            item,
                            colorScheme,
                            downloadedNavigationItems:
                                downloadedNavigationItems,
                            downloadedNavigationIndex:
                                downloadedNavigationIndexByUnifiedId[item.id],
                            localNavigationItems: localNavigationItems,
                            localNavigationIndex:
                                localNavigationIndexByUnifiedId[item.id],
                            libraryItems: filteredUnifiedItems,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  childCount:
                      leadCount + collectionCount + filteredUnifiedItems.length,
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index < collectionCount) {
                    return _buildAllTabListCollectionItem(
                      context: context,
                      colorScheme: colorScheme,
                      entry: collectionEntries[index],
                      collectionState: collectionState,
                      filteredUnifiedItems: filteredUnifiedItems,
                    );
                  }
                  final afterCollections = index - collectionCount;
                  if (afterCollections < leadCount) {
                    return leadListCell(afterCollections);
                  }
                  final trackIndex = afterCollections - leadCount;
                  if (trackIndex < filteredUnifiedItems.length) {
                    final item = filteredUnifiedItems[trackIndex];
                    return KeyedSubtree(
                      key: ValueKey(item.id),
                      child: LongPressDraggable<UnifiedLibraryItem>(
                        data: item,
                        feedback: _buildDragFeedback(
                          context,
                          item,
                          colorScheme,
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.4,
                          child: _buildUnifiedLibraryItem(
                            context,
                            item,
                            colorScheme,
                            downloadedNavigationItems:
                                downloadedNavigationItems,
                            downloadedNavigationIndex:
                                downloadedNavigationIndexByUnifiedId[item.id],
                            localNavigationItems: localNavigationItems,
                            localNavigationIndex:
                                localNavigationIndexByUnifiedId[item.id],
                            libraryItems: filteredUnifiedItems,
                          ),
                        ),
                        child: _buildUnifiedLibraryItem(
                          context,
                          item,
                          colorScheme,
                          downloadedNavigationItems: downloadedNavigationItems,
                          downloadedNavigationIndex:
                              downloadedNavigationIndexByUnifiedId[item.id],
                          localNavigationItems: localNavigationItems,
                          localNavigationIndex:
                              localNavigationIndexByUnifiedId[item.id],
                          libraryItems: filteredUnifiedItems,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
                childCount:
                    leadCount + collectionCount + filteredUnifiedItems.length,
              ),
            ),
        ],

        if (filterMode == 'singles')
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Text(
                    context.l10n.queueTrackCount(totalTrackCount),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (!_isSelectionMode)
                    _buildFilterButton(context, unifiedItems),
                  if (!_isSelectionMode && filteredUnifiedItems.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _showCreatePlaylistDialog(context),
                      icon: const Icon(Icons.add, size: 20),
                      label: Text(context.l10n.collectionCreatePlaylist),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          ),

        if (filterMode == 'singles')
          _buildQueueHeaderSliver(context, colorScheme),

        if ((filteredUnifiedItems.isNotEmpty || leadCount > 0) &&
            filterMode == 'singles')
          historyViewMode == 'grid'
              ? SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: _AnimatedLibrarySliverGrid(
                    maxCrossAxisExtent: _libraryGridExtent,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.66,
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index < leadCount) {
                        return leadGridCell(index);
                      }
                      final item = filteredUnifiedItems[index - leadCount];
                      return KeyedSubtree(
                        key: ValueKey(item.id),
                        child: _buildUnifiedGridItem(
                          context,
                          item,
                          colorScheme,
                          downloadedNavigationItems: downloadedNavigationItems,
                          downloadedNavigationIndex:
                              downloadedNavigationIndexByUnifiedId[item.id],
                          localNavigationItems: localNavigationItems,
                          localNavigationIndex:
                              localNavigationIndexByUnifiedId[item.id],
                          libraryItems: filteredUnifiedItems,
                        ),
                      );
                    }, childCount: leadCount + filteredUnifiedItems.length),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index < leadCount) {
                      return leadListCell(index);
                    }
                    final item = filteredUnifiedItems[index - leadCount];
                    return KeyedSubtree(
                      key: ValueKey(item.id),
                      child: _buildUnifiedLibraryItem(
                        context,
                        item,
                        colorScheme,
                        downloadedNavigationItems: downloadedNavigationItems,
                        downloadedNavigationIndex:
                            downloadedNavigationIndexByUnifiedId[item.id],
                        localNavigationItems: localNavigationItems,
                        localNavigationIndex:
                            localNavigationIndexByUnifiedId[item.id],
                        libraryItems: filteredUnifiedItems,
                      ),
                    );
                  }, childCount: leadCount + filteredUnifiedItems.length),
                ),

        if (!hasQueueItems &&
            totalTrackCount == 0 &&
            (filterMode != 'albums' ||
                (filteredGroupedAlbums.isEmpty &&
                    filteredGroupedLocalAlbums.isEmpty)) &&
            !showFilteringIndicator &&
            !isPageLoading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(context, colorScheme, filterMode),
          )
        else if (isPageLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),

        if (hasQueueItems ||
            totalTrackCount > 0 ||
            (filterMode == 'albums' &&
                (filteredGroupedAlbums.isNotEmpty ||
                    filteredGroupedLocalAlbums.isNotEmpty)))
          SliverToBoxAdapter(
            child: SizedBox(height: _isSelectionMode ? 100 : 16),
          ),
        SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
      ],
    );

    final scrollAwareContent = NotificationListener<ScrollNotification>(
      onNotification: (notification) => _handleLibraryScrollNotification(
        notification: notification,
        filterMode: filterMode,
        hasMoreLibrary: hasMoreLibrary,
        isPageLoading: isPageLoading,
      ),
      child: content,
    );

    if (historyViewMode != 'grid') return scrollAwareContent;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleStart: _handleLibraryGridScaleStart,
      onScaleUpdate: _handleLibraryGridScaleUpdate,
      onScaleEnd: _handleLibraryGridScaleEnd,
      child: scrollAwareContent,
    );
  }

  Future<void> _showClearAllDialog(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.queueClearAll),
        content: Text(context.l10n.queueClearAllMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: Text(context.l10n.dialogClear),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      ref.read(downloadQueueProvider.notifier).clearAll();
    }
  }

  Widget _buildEmptyState(
    BuildContext context,
    ColorScheme colorScheme,
    String filterMode,
  ) {
    String message;
    String subtitle;
    IconData icon;

    switch (filterMode) {
      case 'albums':
        message = context.l10n.queueEmptyAlbums;
        subtitle = context.l10n.queueEmptyAlbumsSubtitle;
        icon = Icons.album;
        break;
      case 'singles':
        message = context.l10n.queueEmptySingles;
        subtitle = context.l10n.queueEmptySinglesSubtitle;
        icon = Icons.music_note;
        break;
      default:
        message = context.l10n.queueEmptyHistory;
        subtitle = context.l10n.queueEmptyHistorySubtitle;
        icon = Icons.history;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumGridItem(
    BuildContext context,
    _GroupedAlbum album,
    ColorScheme colorScheme,
  ) {
    return ValueListenableBuilder<int>(
      valueListenable: _embeddedCoverVersion,
      builder: (context, _, child) {
        final embeddedCoverPath = _resolveDownloadedEmbeddedCoverPath(
          album.sampleFilePath,
        );
        return _buildAlbumGridItemCore(
          context: context,
          albumName: album.albumName,
          artistName: album.artistName,
          trackCount: album.displayTrackCount,
          colorScheme: colorScheme,
          coverWidget: embeddedCoverPath != null
              ? Image.file(
                  File(embeddedCoverPath),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  cacheWidth: 300,
                  cacheHeight: 300,
                  errorBuilder: (context, error, stackTrace) =>
                      _albumPlaceholder(colorScheme),
                )
              : album.coverUrl != null
              ? CachedCoverImage(
                  imageUrl: album.coverUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  memCacheWidth: 300,
                  memCacheHeight: 300,
                )
              : null,
          badgeColor: colorScheme.primaryContainer,
          badgeTextColor: colorScheme.onPrimaryContainer,
          badgeIcon: Icons.music_note,
          coverUrl: album.coverUrl,
          onTap: () => _navigateToDownloadedAlbum(album),
        );
      },
    );
  }

  Widget _buildLocalAlbumGridItem(
    BuildContext context,
    _GroupedLocalAlbum album,
    ColorScheme colorScheme,
  ) {
    return _buildAlbumGridItemCore(
      context: context,
      albumName: album.albumName,
      artistName: album.artistName,
      trackCount: album.displayTrackCount,
      colorScheme: colorScheme,
      coverWidget: album.coverPath != null
          ? Image.file(
              File(album.coverPath!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: 300,
              cacheHeight: 300,
              errorBuilder: (context, error, stackTrace) =>
                  _albumPlaceholder(colorScheme),
            )
          : null,
      badgeColor: colorScheme.tertiaryContainer,
      badgeTextColor: colorScheme.onTertiaryContainer,
      badgeIcon: Icons.folder,
      onTap: () => _navigateToLocalAlbum(album),
    );
  }

  Widget _albumPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.album, color: colorScheme.onSurfaceVariant, size: 48),
      ),
    );
  }

  Widget _buildAlbumGridItemCore({
    required BuildContext context,
    required String albumName,
    required String artistName,
    required int trackCount,
    required ColorScheme colorScheme,
    required Widget? coverWidget,
    required Color badgeColor,
    required Color badgeTextColor,
    required IconData badgeIcon,
    required VoidCallback onTap,
    String? coverUrl,
  }) {
    return Semantics(
      button: true,
      label: context.l10n.a11yOpenAlbumByArtistTrackCount(
        albumName,
        artistName,
        trackCount,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: coverWidget ?? _albumPlaceholder(colorScheme),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 12, color: badgeTextColor),
                          const SizedBox(width: 4),
                          Text(
                            '$trackCount',
                            style: TextStyle(
                              color: badgeTextColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              albumName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            ClickableArtistName(
              artistName: artistName,
              coverUrl: coverUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasTextValue(String? value) => value != null && value.trim().isNotEmpty;

  List<UnifiedLibraryItem> _selectedItemsFromAll(
    List<UnifiedLibraryItem> allItems,
  ) {
    final itemsById = {for (final item in allItems) item.id: item};
    return _selectedIds
        .map((id) => itemsById[id])
        .whereType<UnifiedLibraryItem>()
        .toList(growable: false);
  }

  bool _isLocalOnlySelection(List<UnifiedLibraryItem> allItems) {
    final selectedItems = _selectedItemsFromAll(allItems);
    return selectedItems.isNotEmpty &&
        selectedItems.every((item) => item.localItem != null);
  }

  Future<void> _safeDeleteTempFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _cleanupTempFileAndParentDir(String path) async {
    await _safeDeleteTempFile(path);
    try {
      final parent = File(path).parent;
      if (await parent.exists()) {
        await parent.delete();
      }
    } catch (_) {}
  }

  Future<bool> _applyQueueFfmpegReEnrichResult(
    LocalLibraryItem item,
    Map<String, dynamic> result,
  ) async {
    final tempPath = result['temp_path'] as String?;
    final safUri = result['saf_uri'] as String?;
    final ffmpegTarget = _hasTextValue(tempPath) ? tempPath! : item.filePath;
    final downloadedCoverPath = result['cover_path'] as String?;
    String? effectiveCoverPath = downloadedCoverPath;
    String? extractedCoverPath;

    if (!_hasTextValue(effectiveCoverPath)) {
      try {
        final tempDir = await Directory.systemTemp.createTemp(
          'reenrich_cover_',
        );
        final coverOutput = '${tempDir.path}${Platform.pathSeparator}cover.jpg';
        final extracted = await PlatformBridge.extractCoverToFile(
          ffmpegTarget,
          coverOutput,
        );
        if (extracted['error'] == null) {
          effectiveCoverPath = coverOutput;
          extractedCoverPath = coverOutput;
        } else {
          try {
            await tempDir.delete(recursive: true);
          } catch (_) {}
        }
      } catch (_) {}
    }

    final metadata = (result['metadata'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, v.toString()),
    );

    final format = item.format?.toLowerCase();
    final lowerPath = item.filePath.toLowerCase();
    final isMp3 = format == 'mp3' || lowerPath.endsWith('.mp3');
    final isM4A =
        format == 'm4a' ||
        format == 'aac' ||
        lowerPath.endsWith('.m4a') ||
        lowerPath.endsWith('.aac');
    final isOpus =
        format == 'opus' ||
        format == 'ogg' ||
        lowerPath.endsWith('.opus') ||
        lowerPath.endsWith('.ogg');

    final artistTagMode = ref.read(settingsProvider).artistTagMode;
    String? ffmpegResult;
    if (isMp3) {
      ffmpegResult = await FFmpegService.embedMetadataToMp3(
        mp3Path: ffmpegTarget,
        coverPath: effectiveCoverPath,
        metadata: metadata,
        preserveMetadata: true,
      );
    } else if (isM4A) {
      ffmpegResult = await FFmpegService.embedMetadataToM4a(
        m4aPath: ffmpegTarget,
        coverPath: effectiveCoverPath,
        metadata: metadata,
        preserveMetadata: true,
      );
    } else if (isOpus) {
      ffmpegResult = await FFmpegService.embedMetadataToOpus(
        opusPath: ffmpegTarget,
        coverPath: effectiveCoverPath,
        metadata: metadata,
        artistTagMode: artistTagMode,
        preserveMetadata: true,
      );
    }

    if (ffmpegResult != null &&
        _hasTextValue(tempPath) &&
        _hasTextValue(safUri)) {
      final ok = await PlatformBridge.writeTempToSaf(ffmpegResult, safUri!);
      if (!ok) {
        if (_hasTextValue(downloadedCoverPath)) {
          await _safeDeleteTempFile(downloadedCoverPath!);
        }
        if (_hasTextValue(extractedCoverPath)) {
          await _cleanupTempFileAndParentDir(extractedCoverPath!);
        }
        await _safeDeleteTempFile(tempPath!);
        return false;
      }
      await writeReEnrichSafSidecarLrc(safUri: safUri, reEnrichResult: result);
    }

    if (_hasTextValue(downloadedCoverPath)) {
      await _safeDeleteTempFile(downloadedCoverPath!);
    }
    if (_hasTextValue(extractedCoverPath)) {
      await _cleanupTempFileAndParentDir(extractedCoverPath!);
    }
    if (_hasTextValue(tempPath)) {
      await _safeDeleteTempFile(tempPath!);
    }

    if (ffmpegResult != null) {
      // Filesystem .lrc sidecar. SAF sidecar is written only after
      // writeTempToSaf succeeds.
      await writeReEnrichSidecarLrc(
        audioFilePath: item.filePath,
        reEnrichResult: result,
      );
    }

    return ffmpegResult != null;
  }

  Future<bool> _reEnrichQueueLocalTrack(
    LocalLibraryItem item, {
    List<String>? updateFields,
  }) async {
    final durationMs = (item.duration ?? 0) * 1000;
    final settings = ref.read(settingsProvider);
    final artistTagMode = settings.artistTagMode;
    await ref.read(settingsProvider.notifier).syncLyricsSettingsToBackend();
    final request = <String, dynamic>{
      'file_path': item.filePath,
      'cover_url': '',
      'max_quality': true,
      'embed_lyrics': settings.embedLyrics,
      'lyrics_mode': settings.lyricsMode,
      'artist_tag_mode': artistTagMode,
      'spotify_id': '',
      'track_name': item.trackName,
      'artist_name': item.artistName,
      'album_name': item.albumName,
      'album_artist': item.albumArtist ?? '',
      'track_number': item.trackNumber ?? 0,
      'disc_number': item.discNumber ?? 0,
      'release_date': item.releaseDate ?? '',
      'isrc': item.isrc ?? '',
      'genre': item.genre ?? '',
      'label': '',
      'copyright': '',
      'duration_ms': durationMs,
      'search_online': true,
      // ignore: use_null_aware_elements
      if (updateFields != null) 'update_fields': updateFields,
    };

    final result = await PlatformBridge.reEnrichFile(request);
    final method = result['method'] as String?;
    if (method == 'native') {
      // Filesystem .lrc sidecar (SAF sidecar handled natively in Kotlin).
      await writeReEnrichSidecarLrc(
        audioFilePath: item.filePath,
        reEnrichResult: result,
      );
      return true;
    }
    if (method == 'ffmpeg') {
      return _applyQueueFfmpegReEnrichResult(item, result);
    }
    return false;
  }

  List<LocalLibraryItem> _selectedFlacEligibleLocalItems(
    List<UnifiedLibraryItem> allItems,
  ) {
    final selectedItems = _selectedItemsFromAll(allItems);
    return selectedItems
        .map((item) => item.localItem)
        .whereType<LocalLibraryItem>()
        .where(LocalTrackRedownloadService.isFlacUpgradeEligible)
        .toList(growable: false);
  }

  Future<void> _queueSelectedLocalAsFlac(
    List<UnifiedLibraryItem> allItems,
  ) async {
    final selectedLocalItems = _selectedFlacEligibleLocalItems(allItems);

    if (selectedLocalItems.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.queueFlacAction),
        content: Text(
          context.l10n.queueFlacConfirmMessage(selectedLocalItems.length),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.queueFlacAction),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final settings = ref.read(settingsProvider);
    final extensionState = ref.read(extensionProvider);
    final includeExtensions =
        settings.useExtensionProviders &&
        extensionState.extensions.any(
          (ext) => ext.enabled && ext.hasMetadataProvider,
        );
    final targetService = LocalTrackRedownloadService.preferredFlacService(
      settings,
      extensionState,
    );
    if (targetService.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.extensionsNoDownloadProvider)),
      );
      return;
    }
    final targetQuality =
        LocalTrackRedownloadService.preferredFlacQualityForService(
          targetService,
          extensionState,
        );

    final matchedTracks = <Track>[];
    var skippedCount = 0;
    final total = selectedLocalItems.length;

    var cancelled = false;
    BatchProgressDialog.show(
      context: context,
      title: context.l10n.queueFlacAction,
      total: total,
      icon: Icons.queue_music,
      onCancel: () {
        cancelled = true;
        BatchProgressDialog.dismiss(context);
      },
    );

    for (var i = 0; i < total; i++) {
      if (!mounted || cancelled) break;

      BatchProgressDialog.update(
        current: i + 1,
        detail: selectedLocalItems[i].trackName,
      );

      try {
        final resolution = await LocalTrackRedownloadService.resolveBestMatch(
          selectedLocalItems[i],
          includeExtensions: includeExtensions,
        );
        if (resolution.canQueue && resolution.match != null) {
          matchedTracks.add(resolution.match!);
        } else {
          skippedCount++;
        }
      } catch (_) {
        skippedCount++;
      }
    }

    if (!mounted) {
      return;
    }

    if (!cancelled) {
      BatchProgressDialog.dismiss(context);
    }

    if (matchedTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.queueFlacNoReliableMatches)),
      );
      return;
    }

    ref
        .read(downloadQueueProvider.notifier)
        .addMultipleToQueue(
          matchedTracks,
          targetService,
          qualityOverride: targetQuality,
        );

    final summary = skippedCount == 0
        ? context.l10n.snackbarAddedTracksToQueue(matchedTracks.length)
        : context.l10n.queueFlacQueuedWithSkipped(
            matchedTracks.length,
            skippedCount,
          );

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(summary)));
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _reEnrichSelectedLocalFromQueue(
    List<UnifiedLibraryItem> allItems,
  ) async {
    final selectedItems = _selectedItemsFromAll(allItems);
    final selectedLocalItems = selectedItems
        .map((item) => item.localItem)
        .whereType<LocalLibraryItem>()
        .toList(growable: false);

    if (selectedLocalItems.isEmpty) {
      return;
    }

    // Hide the selection overlay: set the flag (prevents build() from
    // re-inserting via postFrameCallback) and remove the entry immediately.
    setState(() => _isSelectionMode = false);
    _hideSelectionOverlay();

    final selection = await showReEnrichFieldDialog(
      context,
      selectedCount: selectedLocalItems.length,
    );

    if (selection == null || !mounted) {
      // Cancelled — restore selection mode; the next build cycle will
      // re-create the overlay via _syncSelectionOverlay in postFrameCallback.
      if (mounted) setState(() => _isSelectionMode = true);
      return;
    }

    final updateFields = selection.isAll ? null : selection.fields;

    var successCount = 0;
    final total = selectedLocalItems.length;

    var cancelled = false;
    BatchProgressDialog.show(
      context: context,
      title: context.l10n.trackReEnrichProgress,
      total: total,
      icon: Icons.auto_fix_high,
      onCancel: () {
        cancelled = true;
        BatchProgressDialog.dismiss(context);
      },
    );

    for (var i = 0; i < total; i++) {
      if (!mounted || cancelled) break;
      final item = selectedLocalItems[i];

      BatchProgressDialog.update(
        current: i + 1,
        detail: '${item.trackName} - ${item.artistName}',
      );

      try {
        final ok = await _reEnrichQueueLocalTrack(
          item,
          updateFields: updateFields,
        );
        if (ok) {
          successCount++;
        }
      } catch (_) {}
    }

    if (!mounted) {
      return;
    }

    final settings = ref.read(settingsProvider);
    final localLibraryPath = settings.localLibraryPath.trim();
    final iosBookmark = settings.localLibraryBookmark;
    try {
      if (localLibraryPath.isNotEmpty &&
          !ref.read(localLibraryProvider).isScanning) {
        await ref
            .read(localLibraryProvider.notifier)
            .startScan(
              localLibraryPath,
              iosBookmark: iosBookmark.isNotEmpty ? iosBookmark : null,
            );
      } else {
        await ref.read(localLibraryProvider.notifier).reloadFromStorage();
      }
    } catch (_) {
      await ref.read(localLibraryProvider.notifier).reloadFromStorage();
    }

    _exitSelectionMode();

    if (!mounted) {
      return;
    }

    if (!cancelled) {
      BatchProgressDialog.dismiss(context);
    }
    ScaffoldMessenger.of(context).clearSnackBars();
    final failedCount = total - successCount;
    final summary = failedCount <= 0
        ? '${context.l10n.trackReEnrichSuccess} ($successCount/$total)'
        : context.l10n.trackReEnrichSuccessWithFailures(
            successCount,
            total,
            failedCount,
          );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(summary)));
  }

  /// Share selected tracks via system share sheet
  Future<void> _shareSelected(List<UnifiedLibraryItem> allItems) async {
    final itemsById = {for (final item in allItems) item.id: item};
    final safUris = <String>[];
    final filesToShare = <XFile>[];

    for (final id in _selectedIds) {
      final item = itemsById[id];
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

  Future<void> _showBatchConvertSheet(
    BuildContext context,
    List<UnifiedLibraryItem> allItems,
  ) async {
    final itemsById = {for (final item in allItems) item.id: item};
    final sourceFormats = <String>{};
    final sourceBitDepths = <int?>[];
    final sourceSampleRates = <int?>[];
    for (final id in _selectedIds) {
      final item = itemsById[id];
      if (item == null) continue;
      final sourceFormat = convertibleAudioSourceFormat(
        storedFormat: item.localItem?.format ?? item.historyItem?.format,
        filePath: item.filePath,
        fileName: item.historyItem?.safFileName,
      );
      if (sourceFormat != null) sourceFormats.add(sourceFormat);
      sourceBitDepths.add(
        item.historyItem?.bitDepth ?? item.localItem?.bitDepth,
      );
      sourceSampleRates.add(
        item.historyItem?.sampleRate ?? item.localItem?.sampleRate,
      );
    }

    final formats = audioConversionTargetFormats
        .where(
          (target) => sourceFormats.any(
            (source) => canConvertAudioFormat(
              sourceFormat: source,
              targetFormat: target,
            ),
          ),
        )
        .toList();

    if (formats.isEmpty) return;

    var didStartConversion = false;

    // Resolve localized strings up front; the builder must not look up
    // Localizations via the (possibly deactivated) State context.
    final sheetTitle = context.l10n.selectionBatchConvertConfirmTitle;
    final sheetConfirmLabel = context.l10n.selectionConvertCount(
      _selectedIds.length,
    );

    _suppressSelectionOverlay = true;
    _hideSelectionOverlay();
    _hidePlaylistSelectionOverlay();

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => BatchConvertSheet(
        formats: formats,
        title: sheetTitle,
        confirmLabel: sheetConfirmLabel,
        sourceBitDepth: lowestKnownPositiveInt(sourceBitDepths),
        sourceSampleRate: lowestKnownPositiveInt(sourceSampleRates),
        onConvert: (format, bitrate, losslessQuality, losslessProcessing) {
          didStartConversion = true;
          Navigator.pop(sheetContext);
          _performBatchConversion(
            allItems: allItems,
            targetFormat: format,
            bitrate: bitrate,
            losslessQuality: losslessQuality,
            losslessProcessing: losslessProcessing,
          );
        },
      ),
    );

    // Wait out the sheet's exit animation before restoring the toolbar so it
    // doesn't pop in front of the still-closing sheet.
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) {
      _suppressSelectionOverlay = false;
      return;
    }
    _suppressSelectionOverlay = false;
    if (didStartConversion) return;
    if (_isSelectionMode) {
      _syncSelectionOverlay(
        items: allItems,
        bottomPadding: MediaQuery.of(this.context).padding.bottom,
      );
    } else if (_isPlaylistSelectionMode) {
      _syncPlaylistSelectionOverlay(
        playlists: ref.read(libraryCollectionsProvider).playlists,
        bottomPadding: MediaQuery.of(this.context).padding.bottom,
      );
    }
  }

  /// Perform batch conversion on selected tracks
  Future<void> _performBatchConversion({
    required List<UnifiedLibraryItem> allItems,
    required String targetFormat,
    required String bitrate,
    LosslessConversionQuality losslessQuality =
        const LosslessConversionQuality(),
    LosslessConversionProcessing losslessProcessing =
        const LosslessConversionProcessing(),
  }) async {
    final itemsById = {for (final item in allItems) item.id: item};
    final selectedItems = <UnifiedLibraryItem>[];
    for (final id in _selectedIds) {
      final item = itemsById[id];
      if (item == null) continue;
      final sourceFormat = convertibleAudioSourceFormat(
        storedFormat: item.localItem?.format ?? item.historyItem?.format,
        filePath: item.filePath,
        fileName: item.historyItem?.safFileName,
      );
      if (sourceFormat == null ||
          !canConvertAudioFormat(
            sourceFormat: sourceFormat,
            targetFormat: targetFormat,
          )) {
        continue;
      }
      selectedItems.add(item);
    }

    if (selectedItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.selectionConvertNoConvertible)),
        );
      }
      return;
    }

    final isLossless = isLosslessConversionTarget(targetFormat);
    final losslessLabels = context.l10n.losslessConversionLabels;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.selectionBatchConvertConfirmTitle),
        content: Text(
          isLossless && losslessQuality.hasCaps
              ? context.l10n.selectionBatchConvertConfirmMessageLosslessCapped(
                  selectedItems.length,
                  targetFormat,
                  losslessQualityLabel(
                    losslessQuality,
                    originalLabel: losslessLabels.original,
                    originalQualityLabel: losslessLabels.originalQuality,
                  ),
                )
              : isLossless
              ? context.l10n.selectionBatchConvertConfirmMessageLossless(
                  selectedItems.length,
                  targetFormat,
                )
              : context.l10n.selectionBatchConvertConfirmMessage(
                  selectedItems.length,
                  targetFormat,
                  bitrate,
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.trackConvertFormat),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    int successCount = 0;
    final total = selectedItems.length;
    final historyDb = HistoryDatabase.instance;
    final settings = ref.read(settingsProvider);
    final shouldEmbedLyrics =
        settings.embedLyrics && settings.lyricsMode != 'external';

    var cancelled = false;
    BatchProgressDialog.show(
      context: context,
      title: context.l10n.trackConvertConverting,
      total: total,
      icon: Icons.transform,
      onCancel: () {
        cancelled = true;
        BatchProgressDialog.dismiss(context);
      },
    );

    for (int i = 0; i < total; i++) {
      if (!mounted || cancelled) break;
      final item = selectedItems[i];

      BatchProgressDialog.update(current: i + 1, detail: item.trackName);

      try {
        final metadata = <String, String>{
          'TITLE': item.trackName,
          'ARTIST': item.artistName,
          'ALBUM': item.albumName,
        };
        try {
          final result = await PlatformBridge.readFileMetadata(item.filePath);
          if (result['error'] == null) {
            mergePlatformMetadataForTagEmbed(target: metadata, source: result);
          }
        } catch (_) {}
        await ensureLyricsMetadataForConversion(
          metadata: metadata,
          sourcePath: item.filePath,
          shouldEmbedLyrics: shouldEmbedLyrics,
          trackName: item.trackName,
          artistName: item.artistName,
          spotifyId: item.historyItem?.spotifyId ?? '',
          durationMs:
              ((item.historyItem?.duration ?? item.localItem?.duration) ?? 0) *
              1000,
        );

        String? coverPath;
        try {
          final tempDir = await getTemporaryDirectory();
          final coverOutput =
              '${tempDir.path}${Platform.pathSeparator}batch_cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final coverResult = await PlatformBridge.extractCoverToFile(
            item.filePath,
            coverOutput,
          );
          if (coverResult['error'] == null) {
            coverPath = coverOutput;
          }
        } catch (_) {}

        String workingPath = item.filePath;
        final isSaf = isContentUri(item.filePath);
        String? safTempPath;

        if (isSaf) {
          safTempPath = await PlatformBridge.copyContentUriToTemp(
            item.filePath,
          );
          if (safTempPath == null) continue;
          workingPath = safTempPath;
        }

        final newPath = await FFmpegService.convertAudioFormat(
          inputPath: workingPath,
          targetFormat: targetFormat.toLowerCase(),
          bitrate: bitrate,
          metadata: metadata,
          coverPath: coverPath,
          artistTagMode: settings.artistTagMode,
          deleteOriginal: !isSaf,
          sourceBitDepth:
              item.historyItem?.bitDepth ?? item.localItem?.bitDepth,
          losslessQuality: losslessQuality,
          losslessProcessing: losslessProcessing,
        );

        if (coverPath != null) {
          try {
            await File(coverPath).delete();
          } catch (_) {}
        }

        if (newPath == null) {
          if (safTempPath != null) {
            try {
              await File(safTempPath).delete();
            } catch (_) {}
          }
          continue;
        }

        final sourceBitDepth =
            item.historyItem?.bitDepth ?? item.localItem?.bitDepth;
        final sourceSampleRate =
            item.historyItem?.sampleRate ?? item.localItem?.sampleRate;
        final isLosslessOutput = isLosslessConversionTarget(targetFormat);
        int? convertedBitDepth;
        int? convertedSampleRate;
        if (isLosslessOutput) {
          try {
            final convertedMetadata = await PlatformBridge.readFileMetadata(
              newPath,
            );
            if (convertedMetadata['error'] == null) {
              convertedBitDepth = readPositiveAudioInt(
                convertedMetadata['bit_depth'],
              );
              convertedSampleRate = readPositiveAudioInt(
                convertedMetadata['sample_rate'],
              );
            }
          } catch (_) {}
          convertedBitDepth ??= losslessQuality.effectiveBitDepth(
            sourceBitDepth,
          );
          convertedSampleRate ??= losslessQuality.effectiveSampleRate(
            sourceSampleRate,
          );
        }
        final newQuality = convertedAudioQualityLabel(
          targetFormat: targetFormat,
          bitrate: bitrate,
          labels: losslessLabels,
          losslessQuality: losslessQuality,
          actualBitDepth: convertedBitDepth,
          actualSampleRate: convertedSampleRate,
        );

        if (isSaf && item.historyItem != null) {
          final hi = item.historyItem!;
          final treeUri = hi.downloadTreeUri;
          final relativeDir = hi.safRelativeDir ?? '';
          if (treeUri != null && treeUri.isNotEmpty) {
            final oldFileName = hi.safFileName ?? '';
            final dotIdx = oldFileName.lastIndexOf('.');
            final baseName = dotIdx > 0
                ? oldFileName.substring(0, dotIdx)
                : oldFileName;
            final convTarget = convertTargetExtAndMime(targetFormat);
            final newExt = convTarget.ext;
            final mimeType = convTarget.mime;
            final newFileName = '$baseName$newExt';

            final safUri = await PlatformBridge.createSafFileFromPath(
              treeUri: treeUri,
              relativeDir: relativeDir,
              fileName: newFileName,
              mimeType: mimeType,
              srcPath: newPath,
            );

            if (safUri == null || safUri.isEmpty) {
              try {
                await File(newPath).delete();
              } catch (_) {}
              if (safTempPath != null) {
                try {
                  await File(safTempPath).delete();
                } catch (_) {}
              }
              continue;
            }

            if (!isSameContentUri(item.filePath, safUri)) {
              try {
                await PlatformBridge.safDelete(item.filePath);
              } catch (_) {}
            }

            await historyDb.updateFilePath(
              hi.id,
              safUri,
              newSafFileName: newFileName,
              newQuality: newQuality,
              newFormat: normalizedConvertedAudioFormat(targetFormat),
              newBitrate: convertedAudioBitrateKbps(
                targetFormat: targetFormat,
                bitrate: bitrate,
              ),
              newBitDepth: convertedBitDepth,
              newSampleRate: convertedSampleRate,
              clearAudioSpecs: !isLosslessOutput,
            );
          }
          try {
            await File(newPath).delete();
          } catch (_) {}
          if (safTempPath != null) {
            try {
              await File(safTempPath).delete();
            } catch (_) {}
          }
        } else if (isSaf && item.localItem != null) {
          final uri = Uri.parse(item.filePath);
          final pathSegments = uri.pathSegments;

          String? treeUri;
          String relativeDir = '';
          String oldFileName = '';

          final treeIdx = pathSegments.indexOf('tree');
          final docIdx = pathSegments.indexOf('document');
          if (treeIdx >= 0 && treeIdx + 1 < pathSegments.length) {
            final treeId = pathSegments[treeIdx + 1];
            treeUri =
                'content://${uri.authority}/tree/${Uri.encodeComponent(treeId)}';
          }
          if (docIdx >= 0 && docIdx + 1 < pathSegments.length) {
            final docPath = Uri.decodeFull(pathSegments[docIdx + 1]);
            final slashIdx = docPath.lastIndexOf('/');
            if (slashIdx >= 0) {
              oldFileName = docPath.substring(slashIdx + 1);
              final treeId = treeIdx >= 0 && treeIdx + 1 < pathSegments.length
                  ? Uri.decodeFull(pathSegments[treeIdx + 1])
                  : '';
              if (treeId.isNotEmpty && docPath.startsWith(treeId)) {
                final afterTree = docPath.substring(treeId.length);
                final trimmed = afterTree.startsWith('/')
                    ? afterTree.substring(1)
                    : afterTree;
                final lastSlash = trimmed.lastIndexOf('/');
                relativeDir = lastSlash >= 0
                    ? trimmed.substring(0, lastSlash)
                    : '';
              }
            } else {
              oldFileName = docPath;
            }
          }

          if (treeUri != null && oldFileName.isNotEmpty) {
            final dotIdx = oldFileName.lastIndexOf('.');
            final baseName = dotIdx > 0
                ? oldFileName.substring(0, dotIdx)
                : oldFileName;
            final convTarget = convertTargetExtAndMime(targetFormat);
            final newExt = convTarget.ext;
            final mimeType = convTarget.mime;
            final newFileName = '$baseName$newExt';

            final safUri = await PlatformBridge.createSafFileFromPath(
              treeUri: treeUri,
              relativeDir: relativeDir,
              fileName: newFileName,
              mimeType: mimeType,
              srcPath: newPath,
            );

            if (safUri == null || safUri.isEmpty) {
              try {
                await File(newPath).delete();
              } catch (_) {}
              if (safTempPath != null) {
                try {
                  await File(safTempPath).delete();
                } catch (_) {}
              }
              continue;
            }

            if (!isSameContentUri(item.filePath, safUri)) {
              try {
                await PlatformBridge.safDelete(item.filePath);
              } catch (_) {}
            }
            await LibraryDatabase.instance.replaceWithConvertedItem(
              item: item.localItem!,
              newFilePath: safUri,
              targetFormat: targetFormat,
              bitrate: bitrate,
              bitDepth: convertedBitDepth,
              sampleRate: convertedSampleRate,
            );
          }

          try {
            await File(newPath).delete();
          } catch (_) {}
          if (safTempPath != null) {
            try {
              await File(safTempPath).delete();
            } catch (_) {}
          }
        } else if (item.historyItem != null) {
          await historyDb.updateFilePath(
            item.historyItem!.id,
            newPath,
            newQuality: newQuality,
            newFormat: normalizedConvertedAudioFormat(targetFormat),
            newBitrate: convertedAudioBitrateKbps(
              targetFormat: targetFormat,
              bitrate: bitrate,
            ),
            newBitDepth: convertedBitDepth,
            newSampleRate: convertedSampleRate,
            clearAudioSpecs: !isLosslessOutput,
          );
        } else if (item.localItem != null) {
          await LibraryDatabase.instance.replaceWithConvertedItem(
            item: item.localItem!,
            newFilePath: newPath,
            targetFormat: targetFormat,
            bitrate: bitrate,
            bitDepth: convertedBitDepth,
            sampleRate: convertedSampleRate,
          );
        }

        successCount++;
      } catch (_) {}
    }

    ref.read(downloadHistoryProvider.notifier).reloadFromStorage();
    ref.read(localLibraryProvider.notifier).reloadFromStorage();

    _exitSelectionMode();

    if (mounted) {
      if (!cancelled) {
        BatchProgressDialog.dismiss(context);
      }
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.selectionBatchConvertSuccess(
              successCount,
              total,
              targetFormat,
            ),
          ),
        ),
      );
    }
  }

  /// Batch-scan loudness and write ReplayGain tags to the selected tracks.
  Future<void> _runBatchReplayGain(List<UnifiedLibraryItem> allItems) async {
    final itemsById = {for (final item in allItems) item.id: item};
    final selectedItems = <UnifiedLibraryItem>[];
    for (final id in _selectedIds) {
      final item = itemsById[id];
      if (item == null) continue;
      selectedItems.add(item);
    }

    if (selectedItems.isEmpty) return;

    _suppressSelectionOverlay = true;
    _hideSelectionOverlay();
    _hidePlaylistSelectionOverlay();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.replayGainBatchConfirmTitle),
        content: Text(
          ctx.l10n.replayGainBatchConfirmMessage(selectedItems.length),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.replayGainBatchConfirmTitle),
          ),
        ],
      ),
    );

    if (!mounted) {
      _suppressSelectionOverlay = false;
      return;
    }
    if (confirmed != true) {
      // Restore after the dialog's exit animation.
      await Future<void>.delayed(const Duration(milliseconds: 220));
      _suppressSelectionOverlay = false;
      if (!mounted) return;
      if (_isSelectionMode) {
        _syncSelectionOverlay(
          items: allItems,
          bottomPadding: MediaQuery.paddingOf(context).bottom,
        );
      }
      return;
    }
    _suppressSelectionOverlay = false;

    var cancelled = false;
    int successCount = 0;
    final total = selectedItems.length;

    BatchProgressDialog.show(
      context: context,
      title: context.l10n.replayGainBatchAnalyzing,
      total: total,
      icon: Icons.graphic_eq,
      onCancel: () {
        cancelled = true;
        BatchProgressDialog.dismiss(context);
      },
    );

    for (int i = 0; i < total; i++) {
      if (!mounted || cancelled) break;
      final item = selectedItems[i];
      BatchProgressDialog.update(current: i + 1, detail: item.trackName);
      try {
        final ok = await ReplayGainService.applyToFile(item.filePath);
        if (ok) successCount++;
      } catch (_) {}
    }

    _exitSelectionMode();

    if (!mounted) return;
    if (!cancelled) {
      BatchProgressDialog.dismiss(context);
    }
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.replayGainBatchSuccess(successCount, total)),
      ),
    );
  }

  Widget _buildSelectionBottomBar(
    BuildContext context,
    ColorScheme colorScheme,
    List<UnifiedLibraryItem> unifiedItems,
    double bottomPadding,
  ) {
    final selectedCount = _selectedIds.length;
    final allSelected =
        selectedCount == unifiedItems.length && unifiedItems.isNotEmpty;
    final localOnlySelection = _isLocalOnlySelection(unifiedItems);
    final flacEligibleCount = _selectedFlacEligibleLocalItems(
      unifiedItems,
    ).length;

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
                              : context.l10n.downloadedAlbumTapToSelect,
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
                        _selectAll(unifiedItems);
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

              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 8.0;
                  final itemWidth = (constraints.maxWidth - spacing) / 2;
                  final actions = <Widget>[];

                  if (localOnlySelection && flacEligibleCount > 0) {
                    actions.add(
                      _SelectionActionButton(
                        icon: Icons.download_for_offline_outlined,
                        label:
                            '${context.l10n.queueFlacAction} ($flacEligibleCount)',
                        onPressed: () =>
                            _queueSelectedLocalAsFlac(unifiedItems),
                        colorScheme: colorScheme,
                      ),
                    );
                  }

                  actions.add(
                    _SelectionActionButton(
                      icon: localOnlySelection
                          ? Icons.auto_fix_high_outlined
                          : Icons.share_outlined,
                      label: localOnlySelection
                          ? '${context.l10n.trackReEnrich} ($selectedCount)'
                          : context.l10n.selectionShareCount(selectedCount),
                      onPressed: selectedCount > 0
                          ? () => localOnlySelection
                                ? _reEnrichSelectedLocalFromQueue(unifiedItems)
                                : _shareSelected(unifiedItems)
                          : null,
                      colorScheme: colorScheme,
                    ),
                  );

                  actions.add(
                    _SelectionActionButton(
                      icon: Icons.swap_horiz,
                      label: context.l10n.selectionConvertCount(selectedCount),
                      onPressed: selectedCount > 0
                          ? () => _showBatchConvertSheet(context, unifiedItems)
                          : null,
                      colorScheme: colorScheme,
                    ),
                  );

                  actions.add(
                    _SelectionActionButton(
                      icon: Icons.graphic_eq,
                      label: context.l10n.selectionReplayGainCount(
                        selectedCount,
                      ),
                      onPressed: selectedCount > 0
                          ? () => _runBatchReplayGain(unifiedItems)
                          : null,
                      colorScheme: colorScheme,
                    ),
                  );

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

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: selectedCount > 0
                      ? () => _deleteSelected(unifiedItems)
                      : null,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    selectedCount > 0
                        ? context.l10n.selectionDeleteTracksCount(selectedCount)
                        : context.l10n.selectionSelectToDelete,
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

  Widget _buildQueueItem(
    BuildContext context,
    DownloadItem item,
    ColorScheme colorScheme,
  ) {
    final isCompleted = item.status == DownloadStatus.completed;
    final isActive =
        item.status == DownloadStatus.queued ||
        item.status == DownloadStatus.downloading ||
        item.status == DownloadStatus.finalizing;

    return Dismissible(
      key: ValueKey('dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: isActive
          ? (_) async {
              return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(context.l10n.cancelDownloadTitle),
                      content: Text(
                        context.l10n.cancelDownloadContent(item.track.name),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: Text(context.l10n.cancelDownloadKeep),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: Text(context.l10n.dialogCancel),
                        ),
                      ],
                    ),
                  ) ??
                  false;
            }
          : null,
      onDismissed: (_) {
        ref.read(downloadQueueProvider.notifier).dismissItem(item.id);
      },
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline, color: colorScheme.onErrorContainer),
      ),
      child: DownloadSuccessOverlay(
        showSuccess: isCompleted,
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: isCompleted
                ? () => _navigateToMetadataScreen(item)
                : item.status == DownloadStatus.failed
                ? () => _showDownloadErrorDialog(context, item)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                if (item.status == DownloadStatus.downloading)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: item.progress.clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                colorScheme.primary.withValues(alpha: 0.16),
                                colorScheme.primary.withValues(alpha: 0.04),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      isCompleted
                          ? Hero(
                              tag: 'cover_${item.id}',
                              child: _buildCoverArt(item, colorScheme),
                            )
                          : _buildCoverArt(item, colorScheme),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.track.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            ClickableArtistName(
                              artistName: item.track.artistName,
                              artistId: item.track.artistId,
                              coverUrl: item.track.coverUrl,
                              extensionId: item.track.source,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            if (item.status == DownloadStatus.downloading) ...[
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Icon(
                                    Icons.download_rounded,
                                    size: 12,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _formatDownloadStatusLine(context, item),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (item.status == DownloadStatus.failed) ...[
                              const SizedBox(height: 4),
                              _buildDownloadFailureMessage(
                                context,
                                item,
                                colorScheme,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildActionButtons(context, item, colorScheme),
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

  Widget _buildDownloadFailureMessage(
    BuildContext context,
    DownloadItem item,
    ColorScheme colorScheme,
  ) {
    if (item.errorType != DownloadErrorType.rateLimit) {
      return Text(
        item.errorMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colorScheme.error),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.hourglass_top_rounded,
            size: 14,
            color: colorScheme.tertiary,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.queueRateLimitTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.tertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                context.l10n.queueRateLimitMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.tertiary.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoverArt(DownloadItem item, ColorScheme colorScheme) {
    final coverSize = _queueCoverSize();
    final radius = BorderRadius.circular(8);

    final cover = item.track.coverUrl != null
        ? CachedCoverImage(
            imageUrl: item.track.coverUrl!,
            width: coverSize,
            height: coverSize,
            borderRadius: radius,
            fadeInDuration: const Duration(milliseconds: 180),
            fadeOutDuration: const Duration(milliseconds: 90),
          )
        : Container(
            width: coverSize,
            height: coverSize,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: radius,
            ),
            child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant),
          );

    final isDownloading =
        item.status == DownloadStatus.downloading ||
        item.status == DownloadStatus.finalizing;
    if (!isDownloading) return cover;

    final progress = item.progress.clamp(0.0, 1.0);
    final indeterminate =
        item.status == DownloadStatus.finalizing || progress <= 0;

    return SizedBox(
      width: coverSize,
      height: coverSize,
      child: Stack(
        fit: StackFit.expand,
        children: [
          cover,
          ClipRRect(
            borderRadius: radius,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
          ),
          Center(
            child: SizedBox(
              width: coverSize * 0.6,
              height: coverSize * 0.6,
              child: CircularProgressIndicator(
                value: indeterminate ? null : progress,
                strokeWidth: 3,
                color: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
              ),
            ),
          ),
          if (!indeterminate)
            Center(
              child: Text(
                '${(progress * 100).round()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    DownloadItem item,
    ColorScheme colorScheme,
  ) {
    switch (item.status) {
      case DownloadStatus.queued:
        return IconButton(
          onPressed: () =>
              ref.read(downloadQueueProvider.notifier).cancelItem(item.id),
          icon: Icon(Icons.close, color: colorScheme.error),
          tooltip: context.l10n.dialogCancel,
          style: IconButton.styleFrom(
            backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.3),
          ),
        );
      case DownloadStatus.downloading:
        return IconButton(
          onPressed: () =>
              ref.read(downloadQueueProvider.notifier).cancelItem(item.id),
          icon: Icon(Icons.stop, color: colorScheme.error),
          tooltip: context.l10n.actionStop,
          style: IconButton.styleFrom(
            backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.3),
          ),
        );
      case DownloadStatus.finalizing:
        return Semantics(
          label: context.l10n.queueFinalizingDownload,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  strokeWidth: 3,
                  color: colorScheme.tertiary,
                ),
                ExcludeSemantics(
                  child: Icon(
                    Icons.edit_note,
                    color: colorScheme.tertiary,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        );
      case DownloadStatus.completed:
        return ValueListenableBuilder<bool>(
          valueListenable: _fileExistsListenable(item.filePath),
          builder: (context, fileExists, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (fileExists)
                  IconButton(
                    onPressed: () => _openFile(
                      item.filePath!,
                      title: item.track.name,
                      artist: item.track.artistName,
                      album: item.track.albumName,
                      coverUrl: item.track.coverUrl ?? '',
                    ),
                    icon: Icon(Icons.play_arrow, color: colorScheme.primary),
                    tooltip: context.l10n.tooltipPlay,
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.primaryContainer.withValues(
                        alpha: 0.3,
                      ),
                    ),
                  )
                else
                  Semantics(
                    label: context.l10n.queueDownloadedFileMissing,
                    child: ExcludeSemantics(
                      child: Icon(
                        Icons.error_outline,
                        color: colorScheme.error,
                        size: 20,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Semantics(
                  label: context.l10n.queueDownloadCompleted,
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        color: colorScheme.onPrimaryContainer,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      case DownloadStatus.failed:
      case DownloadStatus.skipped:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () =>
                  ref.read(downloadQueueProvider.notifier).retryItem(item.id),
              icon: Icon(Icons.refresh, color: colorScheme.primary),
              tooltip: context.l10n.dialogRetry,
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.primaryContainer.withValues(
                  alpha: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () =>
                  ref.read(downloadQueueProvider.notifier).removeItem(item.id),
              icon: Icon(
                Icons.close,
                color: item.status == DownloadStatus.failed
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant,
              ),
              tooltip: context.l10n.dialogRemove,
              style: item.status == DownloadStatus.failed
                  ? IconButton.styleFrom(
                      backgroundColor: colorScheme.errorContainer.withValues(
                        alpha: 0.3,
                      ),
                    )
                  : null,
            ),
          ],
        );
    }
  }

  Widget _buildFilterButton(
    BuildContext context,
    List<UnifiedLibraryItem> unifiedItems,
  ) {
    return GestureDetector(
      onLongPress: _activeFilterCount > 0 ? _resetFilters : null,
      child: TextButton.icon(
        onPressed: () => _showFilterSheet(context, unifiedItems),
        icon: Badge(
          isLabelVisible: _activeFilterCount > 0,
          label: Text('$_activeFilterCount'),
          child: const Icon(Icons.filter_list, size: 18),
        ),
        label: Text(context.l10n.libraryFilterTitle),
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
      ),
    );
  }

  /// When [size] is provided, renders at fixed dimensions (list mode).
  /// When [size] is null, fills the parent container (grid mode).
  Widget _buildUnifiedCoverImage(
    UnifiedLibraryItem item,
    ColorScheme colorScheme, [
    double? size,
  ]) {
    final isDownloaded = item.source == LibraryItemSource.downloaded;

    // For downloaded items, listen to embedded cover version so the cover
    // updates after async extraction completes.
    if (isDownloaded) {
      return ValueListenableBuilder<int>(
        valueListenable: _embeddedCoverVersion,
        builder: (context, _, child) =>
            _buildUnifiedCoverImageInner(item, colorScheme, isDownloaded, size),
      );
    }

    return _buildUnifiedCoverImageInner(item, colorScheme, isDownloaded, size);
  }

  Widget _buildUnifiedCoverImageInner(
    UnifiedLibraryItem item,
    ColorScheme colorScheme,
    bool isDownloaded, [
    double? size,
  ]) {
    final cacheSize = size != null ? (size * 2).toInt() : 200;
    final iconSize = size != null ? size * 0.4 : 32.0;

    Widget buildPlaceholder({bool isLocal = false}) {
      final bgColor = (isDownloaded && !isLocal)
          ? colorScheme.surfaceContainerHighest
          : colorScheme.secondaryContainer;
      final fgColor = (isDownloaded && !isLocal)
          ? colorScheme.onSurfaceVariant
          : colorScheme.onSecondaryContainer;
      return Container(
        width: size,
        height: size,
        decoration: size != null
            ? BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        color: size != null ? null : bgColor,
        child: Center(
          child: Icon(Icons.music_note, color: fgColor, size: iconSize),
        ),
      );
    }

    Widget fadeInFileImage(Widget child, int? frame, bool wasSync) {
      if (wasSync) return child;
      final Widget backdrop;
      if (isDownloaded && item.coverUrl != null) {
        backdrop = CachedCoverImage(
          imageUrl: item.coverUrl!,
          width: size,
          height: size,
          memCacheWidth: cacheSize,
          memCacheHeight: cacheSize,
          placeholder: (context, url) => buildPlaceholder(),
          errorWidget: (context, url, error) => buildPlaceholder(),
        );
      } else {
        backdrop = buildPlaceholder(isLocal: !isDownloaded);
      }
      final animated = Stack(
        fit: StackFit.expand,
        children: [
          backdrop,
          AnimatedOpacity(
            opacity: frame == null ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: child,
          ),
        ],
      );
      if (size == null) return animated;
      return SizedBox(width: size, height: size, child: animated);
    }

    if (isDownloaded) {
      final embeddedCoverPath = _resolveDownloadedEmbeddedCoverPath(
        item.filePath,
      );
      if (embeddedCoverPath != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(embeddedCoverPath),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: cacheSize,
            cacheHeight: cacheSize,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                fadeInFileImage(child, frame, wasSynchronouslyLoaded),
            errorBuilder: (context, error, stackTrace) => buildPlaceholder(),
          ),
        );
      }
    }

    if (item.coverUrl != null) {
      return CachedCoverImage(
        imageUrl: item.coverUrl!,
        width: size,
        height: size,
        memCacheWidth: cacheSize,
        memCacheHeight: cacheSize,
        borderRadius: BorderRadius.circular(8),
        placeholder: (context, url) => buildPlaceholder(),
        errorWidget: (context, url, error) => buildPlaceholder(),
        fadeInDuration: const Duration(milliseconds: 180),
        fadeOutDuration: const Duration(milliseconds: 90),
      );
    }

    if (item.localCoverPath != null && item.localCoverPath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(item.localCoverPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
              fadeInFileImage(child, frame, wasSynchronouslyLoaded),
          errorBuilder: (context, error, stackTrace) =>
              buildPlaceholder(isLocal: true),
        ),
      );
    }

    if (size != null) {
      return buildPlaceholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: buildPlaceholder(),
    );
  }

  Widget _buildUnifiedLibraryItem(
    BuildContext context,
    UnifiedLibraryItem item,
    ColorScheme colorScheme, {
    required List<DownloadHistoryItem> downloadedNavigationItems,
    required int? downloadedNavigationIndex,
    required List<LocalLibraryItem> localNavigationItems,
    required int? localNavigationIndex,
    required List<UnifiedLibraryItem> libraryItems,
  }) {
    final fileExistsListenable = _fileExistsListenable(item.filePath);
    final isSelected = _selectedIds.contains(item.id);
    final date = item.addedAt;
    final dateStr =
        '${_months[date.month - 1]} ${date.day}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    final isDownloaded = item.source == LibraryItemSource.downloaded;
    final sourceLabel = isDownloaded
        ? context.l10n.librarySourceDownloaded
        : context.l10n.librarySourceLocal;
    final sourceColor = isDownloaded
        ? colorScheme.primaryContainer
        : colorScheme.secondaryContainer;
    final sourceTextColor = isDownloaded
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSecondaryContainer;

    return Semantics(
      label: context.l10n.a11yTrackByArtist(item.trackName, item.artistName),
      selected: isSelected,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : null,
        child: InkWell(
          onTap: _isSelectionMode
              ? () => _toggleSelection(item.id)
              : isDownloaded
              ? () => _navigateToHistoryMetadataScreen(
                  item.historyItem!,
                  navigationItems: downloadedNavigationItems,
                  navigationIndex: downloadedNavigationIndex,
                )
              : item.localItem != null
              ? () => _navigateToLocalMetadataScreen(
                  item.localItem!,
                  navigationItems: localNavigationItems,
                  navigationIndex: localNavigationIndex,
                )
              : () => _openFile(
                  item.filePath,
                  title: item.trackName,
                  artist: item.artistName,
                  album: item.albumName,
                  coverUrl: item.coverUrl ?? item.localCoverPath ?? '',
                ),
          onLongPress: _isSelectionMode
              ? null
              : () => _enterSelectionMode(item.id),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (_isSelectionMode) ...[
                  Semantics(
                    checked: isSelected,
                    label: isSelected
                        ? context.l10n.a11yDeselectTrack
                        : context.l10n.a11ySelectTrack,
                    child: AnimatedSelectionCheckbox(
                      visible: true,
                      selected: isSelected,
                      colorScheme: colorScheme,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Hero(
                  tag: 'cover_lib_${item.id}',
                  child: _buildUnifiedCoverImage(item, colorScheme, 56),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.trackName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      ClickableArtistName(
                        artistName: item.artistName,
                        coverUrl: item.coverUrl,
                        extensionId: item.historyItem?.service,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: sourceColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              sourceLabel,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: sourceTextColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              dateStr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                            ),
                          ),
                          if (item.quality != null &&
                              item.quality!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: item.quality!.startsWith('24')
                                    ? colorScheme.primaryContainer
                                    : colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.quality!,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: item.quality!.startsWith('24')
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                if (!_isSelectionMode)
                  ValueListenableBuilder<bool>(
                    valueListenable: fileExistsListenable,
                    builder: (context, fileExists, child) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (fileExists)
                            IconButton(
                              onPressed: () =>
                                  _playLibraryItem(item, libraryItems),
                              icon: Icon(
                                Icons.play_arrow,
                                color: colorScheme.primary,
                              ),
                              tooltip: context.l10n.tooltipPlay,
                              style: IconButton.styleFrom(
                                backgroundColor: colorScheme.primaryContainer
                                    .withValues(alpha: 0.3),
                              ),
                            )
                          else
                            Icon(
                              Icons.error_outline,
                              color: colorScheme.error,
                              size: 20,
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedGridItem(
    BuildContext context,
    UnifiedLibraryItem item,
    ColorScheme colorScheme, {
    required List<DownloadHistoryItem> downloadedNavigationItems,
    required int? downloadedNavigationIndex,
    required List<LocalLibraryItem> localNavigationItems,
    required int? localNavigationIndex,
    required List<UnifiedLibraryItem> libraryItems,
  }) {
    final fileExistsListenable = _fileExistsListenable(item.filePath);
    final isSelected = _selectedIds.contains(item.id);
    final isDownloaded = item.source == LibraryItemSource.downloaded;

    return GestureDetector(
      onTap: _isSelectionMode
          ? () => _toggleSelection(item.id)
          : isDownloaded
          ? () => _navigateToHistoryMetadataScreen(
              item.historyItem!,
              navigationItems: downloadedNavigationItems,
              navigationIndex: downloadedNavigationIndex,
            )
          : item.localItem != null
          ? () => _navigateToLocalMetadataScreen(
              item.localItem!,
              navigationItems: localNavigationItems,
              navigationIndex: localNavigationIndex,
            )
          : () => _openFile(
              item.filePath,
              title: item.trackName,
              artist: item.artistName,
              album: item.albumName,
              coverUrl: item.coverUrl ?? item.localCoverPath ?? '',
            ),
      onLongPress: _isSelectionMode ? null : () => _enterSelectionMode(item.id),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Hero(
                      tag: 'cover_lib_${item.id}',
                      child: _buildUnifiedCoverImage(item, colorScheme),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDownloaded
                            ? colorScheme.primaryContainer
                            : colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        isDownloaded ? Icons.download_done : Icons.folder,
                        size: 12,
                        color: isDownloaded
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  if (item.quality != null && item.quality!.isNotEmpty)
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: item.quality!.startsWith('24')
                              ? colorScheme.primary
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _getQualityBadgeText(item.quality!),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: item.quality!.startsWith('24')
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurfaceVariant,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  if (!_isSelectionMode)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: fileExistsListenable,
                        builder: (context, fileExists, child) {
                          return fileExists
                              ? Semantics(
                                  button: true,
                                  label: context.l10n.a11yPlayTrackByArtist(
                                    item.trackName,
                                    item.artistName,
                                  ),
                                  child: GestureDetector(
                                    onTap: () =>
                                        _playLibraryItem(item, libraryItems),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: ExcludeSemantics(
                                        child: Icon(
                                          Icons.play_arrow,
                                          color: colorScheme.onPrimary,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: colorScheme.errorContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.error_outline,
                                    color: colorScheme.error,
                                    size: 14,
                                  ),
                                );
                        },
                      ),
                    ),
                  if (_isSelectionMode)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primary.withValues(alpha: 0.3)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.trackName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
              ClickableArtistName(
                artistName: item.artistName,
                coverUrl: item.coverUrl,
                extensionId: item.historyItem?.service,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (_isSelectionMode)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.primary : colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.outline,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Icon(Icons.check, color: colorScheme.onPrimary, size: 16)
                    : const SizedBox(width: 16, height: 16),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnimatedLibrarySliverGrid extends StatefulWidget {
  final double maxCrossAxisExtent;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final SliverChildDelegate delegate;

  const _AnimatedLibrarySliverGrid({
    required this.maxCrossAxisExtent,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
    required this.childAspectRatio,
    required this.delegate,
  });

  @override
  State<_AnimatedLibrarySliverGrid> createState() =>
      _AnimatedLibrarySliverGridState();
}

class _AnimatedLibrarySliverGridState extends State<_AnimatedLibrarySliverGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  late double _beginExtent;
  late double _endExtent;

  @override
  void initState() {
    super.initState();
    _beginExtent = widget.maxCrossAxisExtent;
    _endExtent = widget.maxCrossAxisExtent;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    )..value = 1;
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(covariant _AnimatedLibrarySliverGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.maxCrossAxisExtent - _endExtent).abs() < 0.1) return;
    _beginExtent = _currentExtent;
    _endExtent = widget.maxCrossAxisExtent;
    _controller.forward(from: 0);
  }

  double get _currentExtent =>
      _beginExtent + ((_endExtent - _beginExtent) * _curve.value);

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _currentExtent,
            mainAxisSpacing: widget.mainAxisSpacing,
            crossAxisSpacing: widget.crossAxisSpacing,
            childAspectRatio: widget.childAspectRatio,
          ),
          delegate: widget.delegate,
        );
      },
    );
  }
}
