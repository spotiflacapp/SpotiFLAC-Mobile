import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/app_alert_dialog.dart';
import 'package:spotiflac_android/widgets/app_choice_chip.dart';
import 'package:spotiflac_android/services/local_track_batch_actions.dart';
import 'package:spotiflac_android/services/shell_navigation_service.dart';
import 'package:spotiflac_android/widgets/error_card.dart';
import 'package:spotiflac_android/widgets/track_card.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:spotiflac_android/widgets/app_search_field.dart';
import 'package:spotiflac_android/widgets/app_snack_bar.dart';
import 'package:spotiflac_android/widgets/library_search_results.dart';
import 'package:spotiflac_android/widgets/library_track_selection_bar.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';
import 'package:spotiflac_android/utils/audio_quality_badge_policy.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/ordered_range_selection.dart';
import 'package:spotiflac_android/models/download_item.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/models/unified_library_item.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/services/music_player_service.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/local_track_redownload_service.dart';
import 'package:spotiflac_android/services/batch_track_actions.dart';
import 'package:spotiflac_android/services/downloaded_embedded_cover_resolver.dart';
import 'package:spotiflac_android/screens/track_metadata_screen.dart';
import 'package:spotiflac_android/screens/favorite_artists_screen.dart';
import 'package:spotiflac_android/screens/downloaded_album_screen.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';
import 'package:spotiflac_android/screens/library_tracks_folder_screen.dart';
import 'package:spotiflac_android/screens/local_album_screen.dart';
import 'package:spotiflac_android/screens/mornye_library_screen.dart';
import 'package:spotiflac_android/screens/queue_library_refresh_policy.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/widgets/download_service_picker.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/widgets/selection_bottom_bar.dart';
import 'package:spotiflac_android/widgets/smoothed_progress.dart';
import 'package:spotiflac_android/widgets/scroll_edge_fade.dart';
import 'package:spotiflac_android/widgets/two_finger_pinch_listener.dart';

part 'queue_tab_helpers.dart';
part 'queue_tab_widgets.dart';
part 'queue_tab_selection.dart';
part 'queue_tab_navigation.dart';
part 'queue_tab_collection_items.dart';
part 'queue_tab_filter_widgets.dart';
part 'queue_tab_batch_actions.dart';
part 'queue_tab_item_widgets.dart';

String _formatDownloadSizeMB(num bytes) => '${formatMegabytes(bytes)} MB';

String _formatDownloadProgressLabel(
  BuildContext context,
  DownloadItem item, {
  double? visualProgress,
}) {
  final progress = (visualProgress ?? item.progress).clamp(0.0, 1.0);
  final speedSuffix = item.speedMBps > 0
      ? ' • ${item.speedMBps.toStringAsFixed(1)} MB/s'
      : '';

  if (item.bytesTotal > 0) {
    final received = visualProgress != null
        ? item.bytesTotal * progress
        : item.bytesReceived > 0
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

  if (item.error == 'Waiting for verification') {
    return context.l10n.queueWaitingForVerification;
  }
  switch (item.preparationStage) {
    case 'checking_session':
      return context.l10n.queueCheckingDownloadSession;
    case 'resolving_metadata':
      return context.l10n.queueResolvingDownloadMetadata;
    case 'resolving_stream':
      return context.l10n.queueResolvingDownloadStream;
  }
  if (item.error == 'Retrying after verification') {
    return context.l10n.queueResumingAfterVerification;
  }

  return context.l10n.queueDownloadStarting;
}

String _formatDownloadStatusLine(
  BuildContext context,
  DownloadItem item, {
  double? visualProgress,
}) {
  final base = _formatDownloadProgressLabel(
    context,
    item,
    visualProgress: visualProgress,
  );
  final eta = _formatDownloadEta(item, visualProgress: visualProgress);
  return eta == null ? base : '$base • $eta';
}

String? _formatDownloadEta(DownloadItem item, {double? visualProgress}) {
  if (item.speedMBps <= 0 || item.bytesTotal <= 0) return null;
  final progress = (visualProgress ?? item.progress).clamp(0.0, 1.0);
  final received = visualProgress != null
      ? (item.bytesTotal * progress).round()
      : item.bytesReceived > 0
      ? item.bytesReceived
      : (item.bytesTotal * progress).round();
  final remaining = item.bytesTotal - received;
  if (remaining <= 0) return null;
  final seconds = remaining / (item.speedMBps * 1024 * 1024);
  if (!seconds.isFinite || seconds > 3600) return null;
  if (seconds < 60) return '~${seconds.round()}s';
  final minutes = (seconds / 60).floor();
  final secs = (seconds % 60).round();
  return '~${minutes}m${secs.toString().padLeft(2, '0')}s';
}

bool _shouldAnimateDownloadProgress(BuildContext context, DownloadItem item) {
  final progress = item.progress.clamp(0.0, 1.0);
  final animationsDisabled =
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return item.status == DownloadStatus.downloading &&
      progress > 0 &&
      progress < 1 &&
      !animationsDisabled;
}

DownloadHistoryItem? _historyItemForCompletionBridge(
  DownloadItem item,
  List<DownloadHistoryItem> historyItems,
) {
  final filePath = item.filePath?.trim();
  if (filePath != null && filePath.isNotEmpty) {
    for (final historyItem in historyItems) {
      if (historyItem.filePath == filePath) return historyItem;
    }
  }

  for (final historyItem in historyItems) {
    if (historyItem.id == item.id) return historyItem;
  }

  final trackId = item.track.id.trim();
  if (trackId.isNotEmpty) {
    for (final historyItem in historyItems) {
      if (historyItem.spotifyId == trackId) return historyItem;
    }
  }

  final isrc = item.track.isrc?.trim();
  if (isrc != null && isrc.isNotEmpty) {
    for (final historyItem in historyItems) {
      if (historyItem.isrc == isrc) return historyItem;
    }
  }

  return null;
}

class QueueTab extends ConsumerStatefulWidget {
  final String? librarySection;
  final PageController? parentPageController;
  final int parentPageIndex;
  final int? nextPageIndex;

  const QueueTab({
    super.key,
    this.librarySection,
    this.parentPageController,
    this.parentPageIndex = 1,
    this.nextPageIndex,
  });

  @override
  ConsumerState<QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends ConsumerState<QueueTab> {
  static const int _libraryPageSize = 300;
  final LibraryFileAvailabilityCache _fileExistsCache =
      LibraryFileAvailabilityCache();
  late final CompletionBridgePlayableProbeCache _completionBridgePlayableProbe;
  static const double _libraryGridMinExtent = 92;
  static const double _libraryGridDefaultExtent = 126;
  static const double _libraryGridMaxExtent = 190;
  bool _embeddedCoverRefreshScheduled = false;
  // Version counter to trigger targeted cover image rebuilds
  // without rebuilding the entire widget tree via setState.
  final ValueNotifier<int> _embeddedCoverVersion = ValueNotifier<int>(0);

  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  String? _selectionAnchorId;
  final SelectionOverlayController _selectionOverlay =
      SelectionOverlayController();
  List<UnifiedLibraryItem> _selectionOverlayItems = const [];
  double _selectionOverlayBottomPadding = 0;

  /// Keeps the selection overlays hidden while a modal launched from the
  /// selection toolbar is open, so they don't reappear over its animation.
  bool _suppressSelectionOverlay = false;

  bool _isPlaylistSelectionMode = false;
  final Set<String> _selectedPlaylistIds = {};
  final SelectionOverlayController _playlistSelectionOverlay =
      SelectionOverlayController();
  List<UserPlaylistCollection> _playlistSelectionOverlayItems = const [];
  double _playlistSelectionOverlayBottomPadding = 0;

  PageController? _filterPageController;
  final List<String> _filterModes = ['all', 'albums', 'singles', 'playlists'];
  bool _isPageControllerInitialized = false;
  bool _wasTabVisible = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  Timer? _searchDebounce;
  final Map<String, DownloadItem> _completionBridge = {};
  final Map<String, DateTime> _completionBridgeAt = {};
  final Set<String> _bridgePrecacheStarted = {};
  String? _filterSource;
  String? _filterQuality;
  String? _filterFormat;
  String? _filterMetadata;
  String _sortMode = 'latest';
  String _libraryQualityLabelMode = AppSettings.libraryQualityLabelBitrate;
  double _libraryGridExtent = _libraryGridDefaultExtent;
  double? _libraryGridPinchStartExtent;
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

  /// setState is @protected, so the extension part files route rebuilds
  /// through this forwarder.
  void _setState(VoidCallback fn) => setState(fn);

  void _handleLibraryGridPinchStart() {
    _libraryGridPinchStartExtent = _libraryGridExtent;
  }

  void _handleLibraryGridPinchUpdate(double scale) {
    final startExtent = _libraryGridPinchStartExtent;
    if (startExtent == null) return;

    final nextExtent = (startExtent * scale).clamp(
      _libraryGridMinExtent,
      _libraryGridMaxExtent,
    );
    if ((nextExtent - _libraryGridExtent).abs() < 0.5) return;
    setState(() => _libraryGridExtent = nextExtent);
  }

  void _handleLibraryGridPinchEnd() {
    _libraryGridPinchStartExtent = null;
  }

  @override
  void initState() {
    super.initState();
    _completionBridgePlayableProbe = CompletionBridgePlayableProbeCache(
      onPlayable: _fileExistsCache.markExists,
    );
  }

  void _initializePageController() {
    if (_isPageControllerInitialized) return;
    _isPageControllerInitialized = true;
    final settings = ref.read(settingsProvider);
    final initialFilter =
        widget.librarySection ??
        (settings.defaultLibraryView == 'last'
            ? settings.historyFilterMode
            : settings.defaultLibraryView);
    final initialPage = _filterModes
        .indexOf(initialFilter)
        .clamp(0, _filterModes.length - 1);
    if (widget.librarySection == null &&
        settings.historyFilterMode != _filterModes[initialPage]) {
      Future.microtask(() {
        if (!mounted) return;
        ref
            .read(settingsProvider.notifier)
            .setHistoryFilterMode(_filterModes[initialPage]);
      });
    }
    _filterPageController = PageController(initialPage: initialPage);
  }

  /// When the shell switches back to this tab and a fixed default view is
  /// configured, jump the filter pager to it.
  void _applyDefaultLibraryViewOnTabVisible() {
    if (widget.librarySection != null) return;
    final isVisible = TickerMode.valuesOf(context).enabled;
    final becameVisible = isVisible && !_wasTabVisible;
    _wasTabVisible = isVisible;
    if (!becameVisible) return;
    final defaultView = ref.read(settingsProvider).defaultLibraryView;
    if (defaultView == 'last') return;
    final index = _filterModes.indexOf(defaultView);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(settingsProvider).historyFilterMode != defaultView) {
        ref.read(settingsProvider.notifier).setHistoryFilterMode(defaultView);
      }
      final controller = _filterPageController;
      if (controller != null &&
          controller.hasClients &&
          controller.page?.round() != index) {
        controller.jumpToPage(index);
      }
    });
  }

  @override
  void dispose() {
    _hideSelectionOverlay();
    _hidePlaylistSelectionOverlay();
    _fileExistsCache.dispose();
    _completionBridgePlayableProbe.dispose();
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
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || _searchQuery == normalized) return;
      setState(() {
        _searchQuery = normalized;
        _resetLibraryPaging();
      });
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    if (_searchQuery.isEmpty) return;
    setState(() {
      _searchQuery = '';
      _resetLibraryPaging();
    });
  }

  int _libraryPageOffsetFor(String filterMode) =>
      _libraryPageOffsetByFilter[filterMode] ?? 0;

  void _resetLibraryOffsets() {
    _libraryPageOffsetByFilter.clear();
  }

  void _resetLibraryPaging() {
    _resetLibraryOffsets();
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
    _QueueLibraryCountsRequest request, {
    QueueLibraryCounts? nonEmptyFallback,
  }) {
    return value.maybeWhen(
      data: (counts) {
        final cached = _queueLibraryCountsCache[request];
        final resolved = resolveQueueLibraryCountsSnapshot(
          current: counts,
          cached: cached,
          activeDownloadFallback: nonEmptyFallback,
        );
        _queueLibraryCountsCache[request] = resolved;
        _trimQueueLibraryCountsCache();
        return resolved;
      },
      orElse: () =>
          _queueLibraryCountsCache[request] ??
          nonEmptyFallback ??
          const QueueLibraryCounts(
            allTrackCount: 0,
            albumCount: 0,
            singleTrackCount: 0,
          ),
    );
  }

  /// [nonEmptyFallback] is non-null when an in-memory snapshot is available;
  /// it is only invoked when no cached or live page has content.
  _QueueLibraryPageData _resolveQueueLibraryPageData(
    AsyncValue<_QueueLibraryPageData>? value,
    _QueueLibraryPageRequest request, {
    _QueueLibraryPageData Function()? nonEmptyFallback,
  }) {
    void storePage(_QueueLibraryPageData data) {
      final cached = _cachedQueueLibraryPageAt(request, request.offset);
      if (shouldRetainQueueLibraryPageSnapshot(
        currentIsEmpty: data.isEmpty,
        cachedHasContent: cached != null && !cached.isEmpty,
        activeDownloadFallbackAvailable: nonEmptyFallback != null,
      )) {
        return;
      }
      final staleRequests = _queueLibraryPageDataCache.keys
          .where(
            (cachedRequest) =>
                cachedRequest.offset == request.offset &&
                cachedRequest != request &&
                _sameQueueLibraryPageScope(cachedRequest, request),
          )
          .toList(growable: false);
      for (final staleRequest in staleRequests) {
        _queueLibraryPageDataCache.remove(staleRequest);
      }
      _queueLibraryPageDataCache[request] = data;
      _trimQueueLibraryPageDataCache(protectedRequest: request);
    }

    if (value != null) {
      final liveData = value.asData?.value;
      if (liveData != null) {
        storePage(liveData);
      }
      value.whenOrNull(data: storePage);
    }

    final pages = <_QueueLibraryPageData>[];
    for (var offset = 0; offset <= request.offset; offset += _libraryPageSize) {
      final page = _cachedQueueLibraryPageAt(request, offset);
      if (page != null) pages.add(page);
    }

    final combined = _QueueLibraryPageData.combine(pages);
    if (combined.isEmpty && nonEmptyFallback != null) {
      return nonEmptyFallback();
    }
    return combined;
  }

  void _invalidateLibraryDataCaches() {
    _queueLibraryCountsCache.clear();
    _queueLibraryPageDataCache.clear();
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
    return _sameQueueLibraryPageScope(request, protectedRequest) &&
        request.limit == protectedRequest.limit &&
        request.offset <= protectedRequest.offset;
  }

  bool _sameQueueLibraryPageScope(
    _QueueLibraryPageRequest a,
    _QueueLibraryPageRequest b,
  ) {
    return a.filterMode == b.filterMode &&
        a.limit == b.limit &&
        a.searchQuery == b.searchQuery &&
        a.filterSource == b.filterSource &&
        a.filterQuality == b.filterQuality &&
        a.filterFormat == b.filterFormat &&
        a.filterMetadata == b.filterMetadata &&
        a.sortMode == b.sortMode &&
        a.localLibraryEnabled == b.localLibraryEnabled;
  }

  _QueueLibraryPageData? _cachedQueueLibraryPageAt(
    _QueueLibraryPageRequest request,
    int offset,
  ) {
    for (final entry in _queueLibraryPageDataCache.entries) {
      if (entry.key.offset == offset &&
          _sameQueueLibraryPageScope(entry.key, request)) {
        return entry.value;
      }
    }
    return null;
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

  void _onFilterPageChanged(int index) {
    if (widget.librarySection != null) return;
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

    showAppModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: colorScheme.surfaceContainerLow,
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
                          const AppSheetHandle(),

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
                              AppChoiceChip(
                                label: Text(context.l10n.libraryFilterAll),
                                selected: tempSource == null,
                                onSelected: (_) =>
                                    setSheetState(() => tempSource = null),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterDownloaded,
                                ),
                                selected: tempSource == 'downloaded',
                                onSelected: (_) => setSheetState(
                                  () => tempSource = 'downloaded',
                                ),
                              ),
                              AppChoiceChip(
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
                              AppChoiceChip(
                                label: Text(context.l10n.libraryFilterAll),
                                selected: tempQuality == null,
                                onSelected: (_) =>
                                    setSheetState(() => tempQuality = null),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterQualityHiRes,
                                ),
                                selected: tempQuality == 'hires',
                                onSelected: (_) =>
                                    setSheetState(() => tempQuality = 'hires'),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterQualityCD,
                                ),
                                selected: tempQuality == 'cd',
                                onSelected: (_) =>
                                    setSheetState(() => tempQuality = 'cd'),
                              ),
                              AppChoiceChip(
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
                              AppChoiceChip(
                                label: Text(context.l10n.libraryFilterAll),
                                selected: tempFormat == null,
                                onSelected: (_) =>
                                    setSheetState(() => tempFormat = null),
                              ),
                              for (final format
                                  in availableFormats.toList()..sort())
                                AppChoiceChip(
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
                              AppChoiceChip(
                                label: Text(context.l10n.libraryFilterAll),
                                selected: tempMetadata == null,
                                onSelected: (_) =>
                                    setSheetState(() => tempMetadata = null),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterMetadataComplete,
                                ),
                                selected: tempMetadata == 'complete',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'complete',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterMetadataMissingAny,
                                ),
                                selected: tempMetadata == 'missing-any',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-any',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterMetadataMissingYear,
                                ),
                                selected: tempMetadata == 'missing-year',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-year',
                                ),
                              ),
                              AppChoiceChip(
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
                              AppChoiceChip(
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
                              AppChoiceChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingTracks,
                                ),
                                selected: tempMetadata == 'missing-tracks',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-tracks',
                                ),
                              ),
                              AppChoiceChip(
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
                              AppChoiceChip(
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
                              AppChoiceChip(
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
                              AppChoiceChip(
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
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterMetadataMissingIsrc,
                                ),
                                selected: tempMetadata == 'missing-isrc',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-isrc',
                                ),
                              ),
                              AppChoiceChip(
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
                              AppChoiceChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingLyrics,
                                ),
                                selected: tempMetadata == 'missing-lyrics',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-lyrics',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingReplayGain,
                                ),
                                selected: tempMetadata == 'missing-replaygain',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-replaygain',
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
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterSortLatest,
                                ),
                                selected: tempSortMode == 'latest',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'latest',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterSortOldest,
                                ),
                                selected: tempSortMode == 'oldest',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'oldest',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(context.l10n.searchSortTitleAZ),
                                selected: tempSortMode == 'a-z',
                                onSelected: (_) =>
                                    setSheetState(() => tempSortMode = 'a-z'),
                              ),
                              AppChoiceChip(
                                label: Text(context.l10n.searchSortTitleZA),
                                selected: tempSortMode == 'z-a',
                                onSelected: (_) =>
                                    setSheetState(() => tempSortMode = 'z-a'),
                              ),
                              AppChoiceChip(
                                label: Text(context.l10n.searchSortArtistAZ),
                                selected: tempSortMode == 'artist-asc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'artist-asc',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(context.l10n.searchSortArtistZA),
                                selected: tempSortMode == 'artist-desc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'artist-desc',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterSortAlbumAsc,
                                ),
                                selected: tempSortMode == 'album-asc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'album-asc',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterSortAlbumDesc,
                                ),
                                selected: tempSortMode == 'album-desc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'album-desc',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(context.l10n.searchSortDateNewest),
                                selected: tempSortMode == 'release-newest',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'release-newest',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(context.l10n.searchSortDateOldest),
                                selected: tempSortMode == 'release-oldest',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'release-oldest',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterSortGenreAsc,
                                ),
                                selected: tempSortMode == 'genre-asc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'genre-asc',
                                ),
                              ),
                              AppChoiceChip(
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
                            child: AppDialogAction(
                              filled: true,
                              onPressed: () {
                                setState(() {
                                  _filterSource = tempSource;
                                  _filterQuality = tempQuality;
                                  _filterFormat = tempFormat;
                                  _filterMetadata = tempMetadata;
                                  _sortMode = tempSortMode;
                                  _resetLibraryPaging();
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

  @override
  Widget build(BuildContext context) {
    if (context.isMornye && widget.librarySection == null) {
      return MornyeLibraryScreen(
        onOpenSection: (section) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: QueueTab(librarySection: section)),
          ),
        ),
      );
    }
    _initializePageController();
    _applyDefaultLibraryViewOnTabVisible();

    ref.listen(downloadQueueLookupProvider, (previous, next) {
      if (previous == null) return;
      if (identical(previous.notCompletedItemIds, next.notCompletedItemIds)) {
        return;
      }
      for (final id in previous.notCompletedItemIds) {
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
          _fileExistsCache.refreshForPath(nextItem.filePath);
          _completionBridgePlayableProbe.refreshForPath(nextItem.filePath);
          _completionBridge[id] = nextItem;
          _completionBridgeAt[id] = DateTime.now();
        }
      }
    });
    ref.listen<int>(
      downloadHistoryProvider.select((state) => state.loadedIndexVersion),
      (previous, next) {
        if (previous == null || previous == next) return;
        final historyItems = ref.read(downloadHistoryProvider).items;
        for (final bridgeItem in _completionBridge.values) {
          _fileExistsCache.refreshForPath(bridgeItem.filePath);
          _completionBridgePlayableProbe.refreshForPath(bridgeItem.filePath);
          final historyPath = _historyItemForCompletionBridge(
            bridgeItem,
            historyItems,
          )?.filePath;
          _fileExistsCache.refreshForPath(historyPath);
          _completionBridgePlayableProbe.refreshForPath(historyPath);
        }
        // The family provider already reruns for the new revision. Retain its
        // last successful page while SQLite is loading so metadata backfills
        // and download completions cannot flash the Library as empty.
        _resetLibraryOffsets();
        if (mounted) setState(() {});
      },
    );
    ref.listen<int>(
      localLibraryProvider.select((state) => state.loadedIndexVersion),
      (previous, next) {
        if (previous == null || previous == next) return;
        // Keep stale rows visible until the refreshed query replaces them.
        _resetLibraryOffsets();
        if (mounted) setState(() {});
      },
    );

    if (widget.librarySection == 'downloads') {
      final ids = ref.watch(
        downloadQueueLookupProvider.select((s) => s.notCompletedItemIds),
      );
      final colors = Theme.of(context).colorScheme;
      return CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: context.l10n.libraryDownloads),
          _buildQueueHeaderSliver(context, colors),
          SliverList.builder(
            itemCount: ids.length,
            itemBuilder: (context, index) => _QueueItemSliverRow(
              key: ValueKey(ids[index]),
              itemId: ids[index],
              colorScheme: colors,
              itemBuilder: _buildQueueItem,
            ),
          ),
          if (ids.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(context.l10n.libraryNoActiveDownloads)),
            ),
          const NavBarSliverSpacer(),
        ],
      );
    }

    final hasQueueItems = ref.watch(
      downloadQueueLookupProvider.select((lookup) => lookup.itemIds.isNotEmpty),
    );
    final historyTotalCount = ref.watch(
      downloadHistoryProvider.select((state) => state.totalCount),
    );
    // Completion-bridge cells need the finalized in-memory history record
    // immediately, before the database-backed Library page refresh lands.
    final inMemoryHistoryItems = ref.watch(
      downloadHistoryProvider.select((state) => state.items),
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
    final String historyFilterMode =
        widget.librarySection ??
        ref.watch<String>(settingsProvider.select((s) => s.historyFilterMode));
    // Keep this mode out of the page-provider request: changing only badge
    // text must not re-query the database or reset Library pagination.
    _libraryQualityLabelMode = ref.watch(
      settingsProvider.select((s) => s.libraryQualityLabelMode),
    );
    final colorScheme = Theme.of(context).colorScheme;
    final countsRequest = _QueueLibraryCountsRequest(
      searchQuery: _searchQuery,
      filterSource: _filterSource,
      filterQuality: _filterQuality,
      filterFormat: _filterFormat,
      filterMetadata: _filterMetadata,
      localLibraryEnabled: localLibraryEnabled,
    );
    final searchingLibrary =
        _searchQuery.isNotEmpty &&
        !_isSelectionMode &&
        !_isPlaylistSelectionMode;
    final countsValue = searchingLibrary
        ? const AsyncData(
            QueueLibraryCounts(
              allTrackCount: 0,
              albumCount: 0,
              singleTrackCount: 0,
            ),
          )
        : ref.watch(_queueLibraryCountsProvider(countsRequest));
    final historySnapshotFallbackEnabled =
        hasQueueItems &&
        inMemoryHistoryItems.isNotEmpty &&
        countsRequest.allowsInMemoryHistoryFallback;
    final historySnapshotCounts = historySnapshotFallbackEnabled
        ? _historySnapshotCounts(
            inMemoryHistoryItems,
            persistedTotalCount: historyTotalCount,
          )
        : null;
    final queueCounts = _resolveQueueLibraryCounts(
      countsValue,
      countsRequest,
      nonEmptyFallback: historySnapshotCounts,
    );

    _QueueLibraryPageRequest pageRequest(String filterMode) {
      final offset = _libraryPageOffsetFor(filterMode);
      final baseRequest = _QueueLibraryPageRequest(
        filterMode: filterMode,
        limit: _libraryPageSize,
        offset: offset,
        searchQuery: _searchQuery,
        filterSource: _filterSource,
        filterQuality: _filterQuality,
        filterFormat: _filterFormat,
        filterMetadata: _filterMetadata,
        sortMode: _sortMode,
        localLibraryEnabled: localLibraryEnabled,
      );
      if (offset == 0) return baseRequest;
      final previousPage = _cachedQueueLibraryPageAt(
        baseRequest,
        offset - _libraryPageSize,
      );
      return _QueueLibraryPageRequest(
        filterMode: baseRequest.filterMode,
        limit: baseRequest.limit,
        offset: baseRequest.offset,
        searchQuery: baseRequest.searchQuery,
        filterSource: baseRequest.filterSource,
        filterQuality: baseRequest.filterQuality,
        filterFormat: baseRequest.filterFormat,
        filterMetadata: baseRequest.filterMetadata,
        sortMode: baseRequest.sortMode,
        localLibraryEnabled: baseRequest.localLibraryEnabled,
        cursor: previousPage?.nextCursor,
      );
    }

    final activePageRequest = pageRequest(historyFilterMode);
    final activePageValue = searchingLibrary
        ? const AsyncData(_QueueLibraryPageData())
        : ref.watch(_queueLibraryPageProvider(activePageRequest));

    // The in-memory snapshot regroups every history item. It is only needed
    // when a page is still empty, so build it on demand and at most once per
    // mode for this build's (immutable) history list.
    final historySnapshots = <(String, int), _QueueLibraryPageData>{};
    _QueueLibraryPageData pageData(String filterMode) {
      final request = filterMode == historyFilterMode
          ? activePageRequest
          : pageRequest(filterMode);
      final historySnapshotAvailable =
          hasQueueItems &&
          inMemoryHistoryItems.isNotEmpty &&
          request.allowsInMemoryHistoryFallback;
      return _resolveQueueLibraryPageData(
        filterMode == historyFilterMode ? activePageValue : null,
        request,
        nonEmptyFallback: historySnapshotAvailable
            ? () => historySnapshots.putIfAbsent(
                (request.filterMode, request.limit),
                () => _QueueLibraryPageData.fromHistorySnapshot(
                  inMemoryHistoryItems,
                  filterMode: request.filterMode,
                  limit: request.limit,
                ),
              )
            : null,
      );
    }

    _FilterContentData getFilterData(String filterMode) {
      return pageData(filterMode).toFilterContentData(
        collectionState,
        totalTrackCount: switch (filterMode) {
          'singles' => queueCounts.singleTrackCount,
          'albums' || 'playlists' => 0,
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
      'playlists' => 0,
      _ => queueCounts.allTrackCount,
    };
    final hasMoreLibrary = currentLoadedCount < currentTotalCount;
    final isLibraryPageLoading =
        countsValue.isLoading || activePageValue.isLoading;
    final hasAnyLibraryItems =
        queueCounts.allTrackCount > 0 || queueCounts.albumCount > 0;
    final hasLibraryContent =
        historyTotalCount > 0 ||
        inMemoryHistoryItems.isNotEmpty ||
        (localLibraryEnabled && localLibraryTotalCount > 0);
    final hasActiveSearch =
        _searchQuery.isNotEmpty || _searchController.text.trim().isNotEmpty;
    final shouldShowLibraryControls =
        hasLibraryContent || hasAnyLibraryItems || hasActiveSearch;
    if (!searchingLibrary) {
      _scheduleBlankLibraryRepair(
        hasQueueItems: hasQueueItems,
        hasLibraryContent: hasLibraryContent,
        hasAnyLibraryItems: hasAnyLibraryItems,
        isLibraryPageLoading: isLibraryPageLoading,
      );
    }

    final selectionItems = getFilterData(
      historyFilterMode,
    ).filteredUnifiedItems;
    if (_isSelectionMode || _isPlaylistSelectionMode) {
      final bottomPadding = MediaQuery.paddingOf(context).bottom;
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
                if (widget.librarySection == null)
                  AppSliverHeader.tabRoot(title: context.l10n.navLibrary)
                else
                  AppSliverHeader.page(
                    title: widget.librarySection == 'playlists'
                        ? context.l10n.searchPlaylists
                        : context.l10n.searchSongs,
                  ),

                if (shouldShowLibraryControls || hasQueueItems)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: GestureDetector(
                        onTap: () {},
                        child: AppSearchField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          hintText: context.l10n.librarySearchHint,
                          clearTooltip: context.l10n.dialogClear,
                          onChanged: _onSearchChanged,
                          onClear: () {
                            _clearSearch();
                            FocusScope.of(context).unfocus();
                          },
                        ),
                      ),
                    ),
                  ),

                if (!searchingLibrary &&
                    shouldShowLibraryControls &&
                    widget.librarySection == null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          int filteredAllCount;
                          int filteredAlbumCount;
                          int filteredSingleCount;

                          filteredAllCount = queueCounts.allTrackCount;
                          filteredAlbumCount = queueCounts.albumCount;
                          filteredSingleCount = queueCounts.singleTrackCount;

                          return ScrollEdgeFade(
                            axis: Axis.horizontal,
                            size: 48,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: context.isMornye
                                  ? const EdgeInsets.symmetric(vertical: 4)
                                  : EdgeInsets.zero,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: constraints.maxWidth,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
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
                                      isSelected:
                                          historyFilterMode == 'singles',
                                      onTap: () {
                                        _animateToFilterPage(2);
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    _FilterChip(
                                      label: context.l10n.searchPlaylists,
                                      count: collectionState.playlists.length,
                                      isSelected:
                                          historyFilterMode == 'playlists',
                                      onTap: () {
                                        _animateToFilterPage(3);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
              body: searchingLibrary
                  ? CustomScrollView(
                      key: const ValueKey('library-search-results'),
                      slivers: [
                        LibrarySearchResults(
                          query: _searchQuery,
                          onOpenArtist: (artist) => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                body: MornyeLibraryScreen(
                                  page: MornyeLibraryPage.albums,
                                  artist: artist,
                                  onOpenSection: (_) {},
                                ),
                              ),
                            ),
                          ),
                        ),
                        const NavBarSliverSpacer(),
                      ],
                    )
                  : widget.librarySection != null
                  ? _buildFilterContent(
                      context: context,
                      colorScheme: colorScheme,
                      filterMode: historyFilterMode,
                      historyViewMode: 'list',
                      hasQueueItems: false,
                      filterData: getFilterData(historyFilterMode),
                      collectionState: collectionState,
                      hasMoreLibrary: hasMoreLibrary,
                      isPageLoading: isLibraryPageLoading,
                      inMemoryHistoryItems: inMemoryHistoryItems,
                    )
                  : PageView.builder(
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
                          inMemoryHistoryItems: inMemoryHistoryItems,
                        );
                      },
                    ),
            ),
          ), // ScrollConfiguration
        ],
      ),
    );
  }

  Widget _buildQueueHeaderSliver(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return Consumer(
      builder: (context, ref, child) {
        final queueCount = ref.watch(
          downloadQueueLookupProvider.select(
            (lookup) => lookup.notCompletedItemIds.length,
          ),
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
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(context.l10n.cancelDownloadTitle),
        content: Text(context.l10n.cancelDownloadContent(item.track.name)),
        actions: [
          AppDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.cancelDownloadKeep),
          ),
          AppDialogAction(
            isDestructive: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.dialogCancel),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // cancelItem (not dismissItem): the item stays in the queue as
      // cancelled so it can be retried without re-searching the track.
      ref.read(downloadQueueProvider.notifier).cancelItem(item.id);
    }
  }

  Future<void> _showDownloadErrorDialog(
    BuildContext context,
    DownloadItem item,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final isRateLimit = item.errorType == DownloadErrorType.rateLimit;
    final isCancelled = item.status == DownloadStatus.skipped;
    final isFolderAccessLost =
        item.errorMessage == safPermissionLostErrorMessage ||
        item.errorMessage == downloadFolderAccessLostErrorMessage;
    final title = isCancelled
        ? context.l10n.queueCancelledTitle
        : isRateLimit
        ? context.l10n.queueRateLimitTitle
        : context.l10n.updateDownloadFailed;
    final message = isCancelled
        ? context.l10n.queueCancelledMessage
        : isRateLimit
        ? context.l10n.queueRateLimitMessage
        : (item.errorMessage.trim().isNotEmpty
              ? _localizedDownloadError(context, item.errorMessage)
              : context.l10n.updateDownloadFailed);
    final action = await showAppDialog<String>(
      context: context,
      builder: (ctx) => AppAlertDialog(
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
          AppDialogAction(
            isDestructive: true,
            onPressed: () => Navigator.of(ctx).pop('remove'),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: Text(context.l10n.dialogRemove),
          ),
          AppDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.l10n.dialogCancel),
          ),
          if (isFolderAccessLost)
            AppDialogAction(
              filled: true,
              onPressed: () => Navigator.of(ctx).pop('reselect'),
              child: Text(context.l10n.downloadFolderReselect),
            )
          else
            AppDialogAction(
              filled: true,
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
    } else if (action == 'reselect') {
      final reselected = await _reselectDownloadFolder();
      if (reselected && mounted) {
        ref.read(downloadQueueProvider.notifier).retryItem(item.id);
      }
    }
  }

  /// Reopen the platform folder picker to restore download folder access,
  /// then persist the new location. Returns true when a folder was saved.
  Future<bool> _reselectDownloadFolder() async {
    if (Platform.isAndroid) {
      final result = await PlatformBridge.pickSafTree();
      if (result == null) return false;
      final treeUri = result['tree_uri'] as String? ?? '';
      final displayName = result['display_name'] as String? ?? '';
      if (treeUri.isEmpty) return false;
      final notifier = ref.read(settingsProvider.notifier);
      notifier.setStorageMode('saf');
      notifier.setDownloadTreeUri(
        treeUri,
        displayName: displayName.isNotEmpty ? displayName : treeUri,
      );
      return true;
    }
    if (Platform.isIOS) {
      IosPickedDirectory? picked;
      try {
        picked = await PlatformBridge.pickIosDirectory();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.snackbarFolderPickerFailed(
                  context.friendlyError(e),
                ),
              ),
            ),
          );
        }
        return false;
      }
      if (picked == null) return false;
      final validation = validateIosPath(picked.path);
      if (!validation.isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                validation.errorReason ?? context.l10n.setupIcloudNotSupported,
              ),
            ),
          );
        }
        return false;
      }
      ref
          .read(settingsProvider.notifier)
          .setDownloadDirectory(picked.path, iosBookmark: picked.bookmark);
      return true;
    }
    return false;
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
