import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/track_provider.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/recent_access_provider.dart';
import 'package:spotiflac_android/providers/explore_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/screens/track_metadata_screen.dart';
import 'package:spotiflac_android/screens/album_screen.dart';
import 'package:spotiflac_android/screens/artist_screen.dart';
import 'package:spotiflac_android/screens/home_search_logic.dart';
import 'package:spotiflac_android/services/csv_import_service.dart';
import 'package:spotiflac_android/services/downloaded_embedded_cover_resolver.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/screens/playlist_screen.dart';
import 'package:spotiflac_android/screens/downloaded_album_screen.dart';
import 'package:spotiflac_android/widgets/download_service_picker.dart';
import 'package:spotiflac_android/widgets/track_collection_quick_actions.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';
import 'package:spotiflac_android/widgets/audio_quality_badges.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';
import 'package:spotiflac_android/widgets/error_card.dart';
import 'package:spotiflac_android/widgets/in_library_badge.dart';
import 'package:spotiflac_android/widgets/preview_button.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/widgets/view_queue_snackbar_action.dart';

part 'home_tab_helpers.dart';
part 'home_tab_explore.dart';
part 'home_tab_recent.dart';
part 'home_tab_import.dart';
part 'home_tab_search_results.dart';
part 'home_tab_widgets.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});
  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  final _urlController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String? _lastSearchQuery;
  String? _activeSearchInput;
  bool _isResettingSearchSurface = false;
  late final ProviderSubscription<TrackState> _trackStateSub;
  late final ProviderSubscription<bool> _extensionInitSub;
  late final ProviderSubscription<bool> _homeFeedExtSub;

  Timer? _liveSearchDebounce;
  bool _isLiveSearchInProgress = false;
  String? _pendingLiveSearchQuery;
  static const int _minLiveSearchChars = 3;
  static const Duration _liveSearchDelay = Duration(milliseconds: 800);

  bool _embeddedCoverRefreshScheduled = false;
  List<Extension>? _thumbnailSizesExtensionsCache;
  bool _isCsvImporting = false;

  void _setCsvImporting(bool value) {
    if (_isCsvImporting == value) return;
    if (!mounted) {
      _isCsvImporting = value;
      return;
    }
    setState(() {
      _isCsvImporting = value;
    });
  }

  Map<String, (double, double)>? _thumbnailSizesCache;
  List<Track>? _searchBucketsSourceTracks;
  HomeSearchResultBuckets? _searchBucketsCache;
  HomeSearchSortOption _searchSortOption = HomeSearchSortOption.defaultOrder;
  List<Track>? _sortedTracksSource;
  List<int>? _sortedTrackIndexesSource;
  HomeSearchSortOption? _sortedTracksMode;
  List<Track>? _sortedTracksCache;
  List<int>? _sortedTrackIndexesCache;

  double _responsiveScale({
    required BuildContext context,
    double min = 0.82,
    double max = 1.08,
    double baseShortestSide = 390,
  }) {
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final scale = shortestSide / baseShortestSide;
    if (scale < min) return min;
    if (scale > max) return max;
    return scale;
  }

  double _effectiveTextScale(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    if (textScale < 1.0) return 1.0;
    if (textScale > 1.4) return 1.4;
    return textScale;
  }

  double _recentDownloadCoverSize(BuildContext context) {
    final scale = _responsiveScale(context: context, min: 0.82, max: 1.05);
    final textScale = _effectiveTextScale(context);
    return 100 * scale * (1 + (textScale - 1) * 0.15);
  }

  double _recentDownloadsRowHeight(BuildContext context) {
    final coverSize = _recentDownloadCoverSize(context);
    final textScale = _effectiveTextScale(context);
    return coverSize + 28 + ((textScale - 1) * 8);
  }

  double _exploreCardSize(BuildContext context) {
    final scale = _responsiveScale(context: context, min: 0.82, max: 1.08);
    final textScale = _effectiveTextScale(context);
    return 145 * scale * (1 + (textScale - 1) * 0.12);
  }

  double _exploreSectionHeight(BuildContext context) {
    final cardSize = _exploreCardSize(context);
    final textScale = _effectiveTextScale(context);
    return cardSize + 58 + ((textScale - 1) * 12);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);

    // Run an initial fetch check in case extensions were already initialized
    // before HomeTab was mounted (e.g. auto-installed during first setup).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchExploreIfNeeded();
    });

    _trackStateSub = ref.listenManual<TrackState>(trackProvider, (
      previous,
      next,
    ) {
      _onTrackStateChanged(previous, next);
      if (previous != null &&
          previous.isLoading &&
          !next.isLoading &&
          next.error == null) {
        _navigateToDetailIfNeeded();
      }
    });

    _extensionInitSub = ref.listenManual<bool>(
      extensionProvider.select((s) => s.isInitialized),
      (previous, next) {
        if (next == true && previous != true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fetchExploreIfNeeded();
          });
        }
      },
    );

    _homeFeedExtSub = ref.listenManual<bool>(
      extensionProvider.select(
        (s) => s.extensions.any((e) => e.enabled && e.hasHomeFeed),
      ),
      (previous, next) {
        if (next == true && previous != true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref
                  .read(exploreProvider.notifier)
                  .fetchHomeFeed(forceRefresh: true);
            }
          });
        }
      },
    );
  }

  void _fetchExploreIfNeeded() {
    if (ref.read(settingsProvider).homeFeedProvider ==
        AppSettings.homeFeedProviderOff) {
      ref.read(exploreProvider.notifier).clear();
      return;
    }

    final extState = ref.read(extensionProvider);
    final exploreState = ref.read(exploreProvider);
    final hasHomeFeedExtension = extState.extensions.any(
      (e) => e.enabled && e.hasHomeFeed,
    );
    if (hasHomeFeedExtension &&
        !exploreState.hasContent &&
        !exploreState.isLoading) {
      ref.read(exploreProvider.notifier).fetchHomeFeed();
    }
  }

  @override
  void dispose() {
    _liveSearchDebounce?.cancel();
    _trackStateSub.close();
    _extensionInitSub.close();
    _homeFeedExtSub.close();
    _urlController.removeListener(_onSearchChanged);
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _urlController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Map<String, (double, double)> _getThumbnailSizesByExtensionId(
    List<Extension> extensions,
  ) {
    final cached = _thumbnailSizesCache;
    if (cached != null &&
        identical(extensions, _thumbnailSizesExtensionsCache)) {
      return cached;
    }

    final map = <String, (double, double)>{
      for (final extension in extensions)
        if (extension.searchBehavior != null)
          extension.id: extension.searchBehavior!.getThumbnailSize(
            defaultSize: 56,
          ),
    };
    _thumbnailSizesExtensionsCache = extensions;
    _thumbnailSizesCache = map;
    return map;
  }

  List<SearchFilter> _resolveSearchFilters(
    BuildContext context,
    String? currentSearchProvider,
    List<Extension> extensions,
  ) {
    final resolvedSearchProvider = HomeSearchProviderPolicy.resolveProvider(
      currentSearchProvider,
      extensions,
    );
    final isUsingExtensionSearch =
        resolvedSearchProvider != null &&
        resolvedSearchProvider.isNotEmpty &&
        extensions.any((e) => e.id == resolvedSearchProvider && e.enabled);

    if (isUsingExtensionSearch) {
      final currentSearchExtension = extensions
          .where((e) => e.id == resolvedSearchProvider && e.enabled)
          .firstOrNull;
      final filters = currentSearchExtension?.searchBehavior?.filters;
      if (filters != null && filters.isNotEmpty) {
        return filters;
      }
    }

    return [
      SearchFilter(
        id: 'track',
        label: context.l10n.searchTracks,
        icon: 'music',
      ),
      SearchFilter(
        id: 'artist',
        label: context.l10n.searchArtists,
        icon: 'artist',
      ),
      SearchFilter(
        id: 'album',
        label: context.l10n.searchAlbums,
        icon: 'album',
      ),
      SearchFilter(
        id: 'playlist',
        label: context.l10n.searchPlaylists,
        icon: 'playlist',
      ),
    ];
  }

  HomeSearchResultBuckets _getSearchResultBuckets(List<Track> tracks) {
    final cached = _searchBucketsCache;
    if (cached != null && identical(tracks, _searchBucketsSourceTracks)) {
      return cached;
    }

    final buckets = bucketHomeSearchResults(tracks);
    _searchBucketsSourceTracks = tracks;
    _searchBucketsCache = buckets;
    return buckets;
  }

  void _invalidateSearchSortCaches() {
    _sortedTracksSource = null;
    _sortedTrackIndexesSource = null;
    _sortedTracksMode = null;
    _sortedTracksCache = null;
    _sortedTrackIndexesCache = null;
  }

  void _onSearchFocusChanged() {
    if (mounted) {
      setState(() {});
    }
    if (_searchFocusNode.hasFocus) {
      ref.read(trackProvider.notifier).setShowingRecentAccess(true);
    }
  }

  void _onTrackStateChanged(TrackState? previous, TrackState next) {
    if (previous != null &&
        !next.hasContent &&
        !next.hasSearchText &&
        !next.isLoading &&
        _urlController.text.isNotEmpty &&
        !_searchFocusNode.hasFocus) {
      _urlController.clear();
    }
  }

  bool _isLiveSearchEnabled() {
    final settings = ref.read(settingsProvider);
    final extState = ref.read(extensionProvider);
    if (!extState.isInitialized && extState.error == null) return true;

    final searchProvider = HomeSearchProviderPolicy.resolveProvider(
      settings.searchProvider,
      extState.extensions,
    );

    if (searchProvider == null || searchProvider.isEmpty) return false;

    final extension = extState.extensions
        .where((e) => e.id == searchProvider && e.enabled)
        .firstOrNull;
    return extension != null;
  }

  void _onSearchChanged() {
    final text = _urlController.text.trim();

    ref.read(trackProvider.notifier).setSearchText(text.isNotEmpty);

    if (text.isEmpty) {
      _liveSearchDebounce?.cancel();
      _activeSearchInput = null;
      _lastSearchQuery = null;
      if (!_isResettingSearchSurface) {
        _resetSearchSurface(clearText: false);
      }
      return;
    }

    if (_activeSearchInput != null && _activeSearchInput != text) {
      _activeSearchInput = null;
    }

    if (_isLiveSearchEnabled() && text.length >= _minLiveSearchChars) {
      if (looksLikeUrlOrSpotifyUri(text)) return;

      _liveSearchDebounce?.cancel();
      _liveSearchDebounce = Timer(_liveSearchDelay, () {
        if (mounted && _urlController.text.trim() == text) {
          _executeLiveSearch(text);
        }
      });
    }
  }

  Future<void> _executeLiveSearch(String query) async {
    if (_isLiveSearchInProgress) {
      _pendingLiveSearchQuery = query;
      return;
    }

    _isLiveSearchInProgress = true;
    _pendingLiveSearchQuery = null;

    try {
      await _performSearch(query);
    } finally {
      _isLiveSearchInProgress = false;

      final pending = _pendingLiveSearchQuery;
      _pendingLiveSearchQuery = null;

      if (pending != null &&
          pending != query &&
          mounted &&
          _urlController.text.trim() == pending) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (mounted && _urlController.text.trim() == pending) {
          _executeLiveSearch(pending);
        }
      }
    }
  }

  Future<void> _performSearch(String query, {String? filterOverride}) async {
    var extState = ref.read(extensionProvider);
    if (!extState.isInitialized && extState.error == null) {
      await ref.read(extensionProvider.notifier).waitForInitialization();
      extState = ref.read(extensionProvider);
    }

    final settings = ref.read(settingsProvider);
    final searchProvider = HomeSearchProviderPolicy.resolveProvider(
      settings.searchProvider,
      extState.extensions,
    );
    final storedFilter = ref.read(trackProvider).selectedSearchFilter;
    final selectedFilter = switch (filterOverride) {
      'all' => null,
      final explicit? => HomeSearchProviderPolicy.sanitizeFilter(
        explicit,
        searchProvider,
        extState.extensions,
      ),
      null => switch (storedFilter) {
        'all' => null,
        final stored? => HomeSearchProviderPolicy.sanitizeFilter(
          stored,
          searchProvider,
          extState.extensions,
        ),
        null => HomeSearchProviderPolicy.preferredFilter(
          settings.defaultSearchTab,
          searchProvider,
          extState.extensions,
        ),
      },
    };

    final searchKey =
        '${searchProvider ?? 'default'}:$query:${selectedFilter ?? 'all'}';
    if (_lastSearchQuery == searchKey) {
      _activeSearchInput = query;
      ref.read(trackProvider.notifier).setSearchText(query.trim().isNotEmpty);
      if (mounted) setState(() {});
      return;
    }
    _lastSearchQuery = searchKey;
    _activeSearchInput = query;
    _searchSortOption = HomeSearchSortOption.defaultOrder;
    _invalidateSearchSortCaches();
    ref.read(trackProvider.notifier).setSearchText(query.trim().isNotEmpty);

    final isExtensionEnabled =
        searchProvider != null &&
        searchProvider.isNotEmpty &&
        extState.extensions.any((e) => e.id == searchProvider && e.enabled);

    if (isExtensionEnabled) {
      Map<String, dynamic>? options;
      if (selectedFilter != null) {
        options = {'filter': selectedFilter};
      }
      await ref
          .read(trackProvider.notifier)
          .customSearch(
            searchProvider,
            query,
            options: options,
            selectedFilter: selectedFilter,
          );
    } else {
      if (searchProvider != null &&
          searchProvider.isNotEmpty &&
          !isExtensionEnabled) {
        ref.read(settingsProvider.notifier).setSearchProvider(null);
      }
      await ref
          .read(trackProvider.notifier)
          .search(query, filterOverride: selectedFilter);
    }
    ref.read(settingsProvider.notifier).setHasSearchedBefore();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _urlController.text = data!.text!;
      final text = data.text!.trim();
      if (looksLikeUrlOrSpotifyUri(text)) {
        _fetchMetadata();
      }
    }
  }

  Future<void> _clearAndRefresh() async {
    _resetSearchSurface();
  }

  void _resetSearchSurface({bool clearText = true}) {
    if (_isResettingSearchSurface) return;
    _isResettingSearchSurface = true;
    try {
      _liveSearchDebounce?.cancel();
      _pendingLiveSearchQuery = null;
      _lastSearchQuery = null;
      _activeSearchInput = null;
      FocusManager.instance.primaryFocus?.unfocus();
      if (clearText && _urlController.text.isNotEmpty) {
        _urlController.clear();
      }
      ref.read(trackProvider.notifier).clear();
      if (mounted) setState(() {});
    } finally {
      _isResettingSearchSurface = false;
    }
  }

  Future<void> _fetchMetadata() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (looksLikeUrlOrSpotifyUri(url)) {
      await ref.read(trackProvider.notifier).fetchFromUrl(url);
      final trackState = ref.read(trackProvider);
      if (trackState.error != null && mounted) {
        final l10n = context.l10n;
        final errorMsg = trackState.error!;
        final isRateLimit =
            errorMsg.contains('429') ||
            errorMsg.toLowerCase().contains('rate limit') ||
            errorMsg.toLowerCase().contains('too many requests');
        final displayMessage = errorMsg == 'url_not_recognized'
            ? l10n.errorUrlNotRecognizedMessage
            : isRateLimit
            ? l10n.errorRateLimitedMessage
            : l10n.errorUrlFetchFailed;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayMessage),
            // Retrying an unrecognized URL is deterministic; skip the action.
            action: errorMsg == 'url_not_recognized'
                ? null
                : SnackBarAction(
                    label: l10n.dialogRetry,
                    onPressed: _fetchMetadata,
                  ),
          ),
        );
        ref.read(trackProvider.notifier).clear();
      } else {
        _navigateToDetailIfNeeded();
      }
    } else {
      await ref.read(trackProvider.notifier).search(url);
    }
    ref.read(settingsProvider.notifier).setHasSearchedBefore();
  }

  void _navigateToDetailIfNeeded() {
    final trackState = ref.read(trackProvider);

    if (trackState.albumId != null &&
        trackState.albumName != null &&
        trackState.tracks.isNotEmpty) {
      final extensionId = trackState.searchExtensionId;
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (context) => AlbumScreen(
            albumId: trackState.albumId!,
            albumName: trackState.albumName!,
            coverUrl: trackState.coverUrl,
            tracks: trackState.tracks,
            extensionId: extensionId,
          ),
        ),
      );
      ref.read(trackProvider.notifier).clear();
      _urlController.clear();
      return;
    }

    if (trackState.playlistName != null && trackState.tracks.isNotEmpty) {
      ref
          .read(recentAccessProvider.notifier)
          .recordPlaylistAccess(
            id: trackState.playlistName!,
            name: trackState.playlistName!,
            imageUrl: trackState.coverUrl,
            providerId: trackState.searchExtensionId ?? 'spotify',
          );

      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (context) => PlaylistScreen(
            playlistName: trackState.playlistName!,
            coverUrl: trackState.coverUrl,
            tracks: trackState.tracks,
            recommendedService:
                trackState.searchExtensionId ?? trackState.searchSource,
          ),
        ),
      );
      ref.read(trackProvider.notifier).clear();
      _urlController.clear();
      return;
    }

    if (trackState.artistId != null &&
        trackState.artistName != null &&
        trackState.artistAlbums != null) {
      final extensionId = trackState.searchExtensionId;
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (context) => ArtistScreen(
            artistId: trackState.artistId!,
            artistName: trackState.artistName!,
            coverUrl: trackState.coverUrl,
            headerImageUrl: trackState.headerImageUrl,
            headerVideoUrl: trackState.headerVideoUrl,
            albums: trackState.artistAlbums!,
            extensionId: extensionId,
          ),
        ),
      );
      ref.read(trackProvider.notifier).clear();
      _urlController.clear();
      return;
    }
  }

  void _downloadTrack(int index, {bool forceQualityPicker = false}) {
    final trackState = ref.read(trackProvider);
    if (index >= 0 && index < trackState.tracks.length) {
      final track = trackState.tracks[index];
      final settings = ref.read(settingsProvider);

      if (settings.askQualityBeforeDownload || forceQualityPicker) {
        DownloadServicePicker.show(
          context,
          trackName: track.name,
          artistName: track.artistName,
          coverUrl: track.coverUrl,
          recommendedService:
              trackState.searchExtensionId ?? trackState.searchSource,
          onSelect: (quality, service) {
            ref
                .read(downloadQueueProvider.notifier)
                .addToQueue(track, service, qualityOverride: quality);
            showAddedToQueueSnackBar(context, track.name);
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
        showAddedToQueueSnackBar(context, track.name);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final hasActualResults = ref.watch(
      trackProvider.select((s) => s.tracks.isNotEmpty),
    );
    final isLoading = ref.watch(trackProvider.select((s) => s.isLoading));
    final searchError = ref.watch(trackProvider.select((s) => s.error));
    final hasSearchedBefore = ref.watch(
      settingsProvider.select((s) => s.hasSearchedBefore),
    );
    final explicitSearchProvider = ref.watch(
      settingsProvider.select((s) => s.searchProvider),
    );
    final defaultSearchTab = ref.watch(
      settingsProvider.select((s) => s.defaultSearchTab),
    );
    final extensions = ref.watch(extensionProvider.select((s) => s.extensions));
    final extensionReadiness = ref.watch(
      extensionProvider.select(
        (s) => (isInitialized: s.isInitialized, error: s.error),
      ),
    );

    final hasExploreContent = ref.watch(
      exploreProvider.select((s) => s.sections.isNotEmpty),
    );
    final exploreLoading = ref.watch(
      exploreProvider.select((s) => s.isLoading),
    );
    final hasHomeFeedExtension = ref.watch(
      extensionProvider.select(
        (s) => s.extensions.any((e) => e.enabled && e.hasHomeFeed),
      ),
    );
    final homeFeedDisabled = ref.watch(
      settingsProvider.select(
        (s) => s.homeFeedProvider == AppSettings.homeFeedProviderOff,
      ),
    );

    final colorScheme = Theme.of(context).colorScheme;
    final searchText = _urlController.text.trim();
    final hasSearchInput = searchText.isNotEmpty;
    final isSearchFocused = _searchFocusNode.hasFocus;
    final hasShortSearchInput =
        hasSearchInput && searchText.length < _minLiveSearchChars;
    final hasSearchError = hasSearchInput && searchError != null;
    final hasActiveSearchSurface =
        hasSearchInput &&
        (_activeSearchInput == searchText ||
            hasActualResults ||
            isLoading ||
            hasSearchError);
    final showEmptySearchResult =
        hasActiveSearchSurface &&
        !hasActualResults &&
        !isLoading &&
        searchError == null;
    final isShowingRecentAccess = ref.watch(
      trackProvider.select((s) => s.isShowingRecentAccess),
    );
    final screenHeight = MediaQuery.sizeOf(context).height;
    final bottomInset = context.navBarBottomInset;
    final hasHistoryItems = ref.watch(
      _homeHistoryPreviewProvider.select((items) => items.isNotEmpty),
    );

    final recentModeRequested = isShowingRecentAccess || isSearchFocused;
    final showRecentAccess =
        recentModeRequested &&
        (!hasSearchInput ||
            hasShortSearchInput ||
            (!hasActualResults &&
                !hasSearchError &&
                !hasActiveSearchSurface)) &&
        !isLoading;
    final isSearchProviderLoading =
        !extensionReadiness.isInitialized && extensionReadiness.error == null;
    final hasSearchProvider = HomeSearchProviderPolicy.hasProvider(
      explicitSearchProvider,
      extensions,
    );
    final showSearchBar = HomeSearchProviderPolicy.shouldShowSearchBar(
      hasSearchProvider: hasSearchProvider,
      isSearchProviderLoading: isSearchProviderLoading,
      hasHomeFeedExtension: hasHomeFeedExtension,
      hasExploreContent: hasExploreContent,
      hasSearchInput: hasSearchInput,
    );
    final hasResults =
        hasSearchInput || hasActualResults || isLoading || showRecentAccess;
    final showExplore =
        !hasActualResults &&
        !isLoading &&
        !hasActiveSearchSurface &&
        !showRecentAccess &&
        !homeFeedDisabled &&
        (hasHomeFeedExtension || hasExploreContent) &&
        hasExploreContent;
    final showEmptyHomeState =
        !isSearchProviderLoading &&
        !hasSearchProvider &&
        !hasHomeFeedExtension &&
        !hasExploreContent &&
        !hasResults;

    ref.listen<String>(settingsProvider.select((s) => s.defaultSearchTab), (
      previous,
      next,
    ) {
      if (previous == next) return;
      final selectedSearchFilter = ref.read(
        trackProvider.select((s) => s.selectedSearchFilter),
      );
      if (selectedSearchFilter != null && selectedSearchFilter.isNotEmpty) {
        return;
      }

      final text = _urlController.text.trim();
      if (text.isEmpty || text.length < _minLiveSearchChars) return;
      if (looksLikeUrlOrSpotifyUri(text)) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _lastSearchQuery = null;
        _performSearch(text);
      });
    });

    if (hasActualResults &&
        isShowingRecentAccess &&
        hasSearchInput &&
        !isSearchFocused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(trackProvider.notifier).setShowingRecentAccess(false);
        }
      });
    }

    return GestureDetector(
      onTap: () {
        if (_searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
        }
      },
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: () => ref.read(exploreProvider.notifier).refresh(),
          notificationPredicate: (notification) => showExplore,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              AppSliverHeader.tabRoot(title: context.l10n.homeTitle),

              SliverToBoxAdapter(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: (hasResults || showExplore)
                      ? const SizedBox.shrink()
                      : _buildHomeIntro(
                          colorScheme: colorScheme,
                          screenHeight: screenHeight,
                          showEmptyHomeState: showEmptyHomeState,
                        ),
                ),
              ),

              if (showSearchBar)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      (hasResults || showExplore) ? 8 : 32,
                      16,
                      (hasResults || showExplore) ? 8 : 16,
                    ),
                    child: _buildSearchBar(colorScheme),
                  ),
                ),

              if (hasActiveSearchSurface &&
                  !showRecentAccess &&
                  !showEmptySearchResult)
                Consumer(
                  builder: (context, ref, _) {
                    final currentSearchProvider = ref.watch(
                      settingsProvider.select((s) => s.searchProvider),
                    );
                    final extensions = ref.watch(
                      extensionProvider.select((s) => s.extensions),
                    );
                    final selectedSearchFilter = ref.watch(
                      trackProvider.select((s) => s.selectedSearchFilter),
                    );
                    final searchFilters = _resolveSearchFilters(
                      context,
                      currentSearchProvider,
                      extensions,
                    );
                    if (searchFilters.isEmpty) {
                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                    }
                    return SliverToBoxAdapter(
                      child: _buildSearchFilterBar(
                        searchFilters,
                        HomeSearchProviderPolicy.displayFilterSelection(
                          selectedSearchFilter,
                          defaultSearchTab,
                          currentSearchProvider,
                          extensions,
                        ),
                        colorScheme,
                      ),
                    );
                  },
                ),

              if (showRecentAccess)
                Consumer(
                  builder: (context, ref, _) {
                    final recentAccessView = ref.watch(
                      recentAccessViewProvider,
                    );
                    return SliverToBoxAdapter(
                      child: _buildRecentAccess(recentAccessView, colorScheme),
                    );
                  },
                ),

              SliverToBoxAdapter(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child:
                      (hasResults ||
                          showRecentAccess ||
                          showExplore ||
                          showEmptyHomeState)
                      ? const SizedBox.shrink()
                      : Column(
                          children: [
                            if (!hasSearchedBefore)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  context.l10n.homeSupports,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            if (hasHistoryItems)
                              Consumer(
                                builder: (context, ref, _) {
                                  final historyItems = ref.watch(
                                    _homeHistoryPreviewProvider,
                                  );
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      32,
                                      24,
                                      24,
                                    ),
                                    child: _buildRecentDownloads(
                                      historyItems,
                                      colorScheme,
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                ),
              ),

              if (showExplore)
                Consumer(
                  builder: (context, ref, _) {
                    final exploreSections = ref.watch(
                      exploreProvider.select((s) => s.sections),
                    );
                    final exploreGreeting = ref.watch(
                      exploreProvider.select((s) => s.greeting),
                    );
                    return SliverMainAxisGroup(
                      slivers: _buildExploreSections(
                        exploreSections,
                        exploreGreeting,
                        colorScheme,
                      ),
                    );
                  },
                ),

              if (hasHomeFeedExtension &&
                  !homeFeedDisabled &&
                  !hasActualResults &&
                  !isLoading &&
                  exploreLoading)
                SliverToBoxAdapter(
                  child: ShimmerLoading(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildExploreSectionSkeleton(isArtist: false),
                        _buildExploreSectionSkeleton(isArtist: true),
                      ],
                    ),
                  ),
                ),

              Consumer(
                builder: (context, ref, _) {
                  final tracks = ref.watch(
                    trackProvider.select((s) => s.tracks),
                  );
                  final isLoading = ref.watch(
                    trackProvider.select((s) => s.isLoading),
                  );
                  final error = ref.watch(trackProvider.select((s) => s.error));
                  final searchExtensionId = ref.watch(
                    trackProvider.select((s) => s.searchExtensionId),
                  );
                  final localLibrarySettings = ref.watch(
                    settingsProvider.select(
                      (s) =>
                          (s.localLibraryEnabled, s.localLibraryShowDuplicates),
                    ),
                  );
                  final extensions = ref.watch(
                    extensionProvider.select((s) => s.extensions),
                  );
                  final showLocalLibraryIndicator =
                      localLibrarySettings.$1 && localLibrarySettings.$2;
                  final thumbnailSizesByExtensionId =
                      _getThumbnailSizesByExtensionId(extensions);
                  final hasResults =
                      tracks.isNotEmpty ||
                      isLoading ||
                      error != null ||
                      hasActiveSearchSurface;

                  return SliverMainAxisGroup(
                    slivers: _buildSearchResults(
                      tracks: tracks,
                      isLoading: isLoading,
                      error: error,
                      colorScheme: colorScheme,
                      hasResults: hasResults,
                      showEmptySearchResult: showEmptySearchResult,
                      searchExtensionId: searchExtensionId,
                      showLocalLibraryIndicator: showLocalLibraryIndicator,
                      thumbnailSizesByExtensionId: thumbnailSizesByExtensionId,
                    ),
                  );
                },
              ),
              SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeIntro({
    required ColorScheme colorScheme,
    required double screenHeight,
    required bool showEmptyHomeState,
  }) {
    if (showEmptyHomeState) {
      final emptyHeight = (screenHeight - 220).clamp(280.0, 520.0).toDouble();
      return SizedBox(
        height: emptyHeight,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.extension_outlined,
                  size: 56,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.homeEmptyTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.homeEmptySubtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SizedBox(height: screenHeight * 0.06),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/images/logo-transparent.png',
              color: colorScheme.onPrimary,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'SpotiFLAC Mobile',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.homeSubtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _onEmbeddedCoverChanged() {
    if (!mounted || _embeddedCoverRefreshScheduled) return;
    _embeddedCoverRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _embeddedCoverRefreshScheduled = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  Widget _buildRecentDownloads(
    List<DownloadHistoryItem> items,
    ColorScheme colorScheme,
  ) {
    final itemCount = items.length < 10 ? items.length : 10;
    final coverSize = _recentDownloadCoverSize(context);
    final rowHeight = _recentDownloadsRowHeight(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            context.l10n.homeRecent,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          height: rowHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: itemCount,
            itemBuilder: (context, index) {
              final item = items[index];
              return KeyedSubtree(
                key: ValueKey(item.id),
                child: Semantics(
                  button: true,
                  label: context.l10n.a11yOpenTrackByArtist(
                    item.trackName,
                    item.artistName,
                  ),
                  child: GestureDetector(
                    onTap: () => _navigateToMetadataScreen(
                      item,
                      navigationItems: items
                          .take(itemCount)
                          .toList(growable: false),
                      navigationIndex: index,
                    ),
                    child: Container(
                      width: coverSize,
                      margin: const EdgeInsets.only(right: 12),
                      child: Column(
                        children: [
                          _DownloadedOrRemoteCover(
                            downloadedFilePath: item.filePath,
                            imageUrl: item.coverUrl,
                            width: coverSize,
                            height: coverSize,
                            borderRadius: BorderRadius.circular(12),
                            fallbackIcon: Icons.music_note,
                            fallbackIconSize: 32,
                            colorScheme: colorScheme,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.trackName,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
