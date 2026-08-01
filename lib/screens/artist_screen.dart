import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/album_detail_header.dart';
import 'package:spotiflac_android/theme/cover_palette.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/track_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/recent_access_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/utils/provider_resource_ids.dart';
import 'package:spotiflac_android/utils/ttl_cache.dart';
import 'package:spotiflac_android/screens/album_screen.dart';
import 'package:spotiflac_android/screens/home_tab.dart'
    show ExtensionAlbumScreen;
import 'package:spotiflac_android/utils/local_playback.dart';
import 'package:spotiflac_android/widgets/download_service_picker.dart';
import 'package:spotiflac_android/widgets/error_card.dart';
import 'package:spotiflac_android/widgets/selection_bottom_bar.dart';
import 'package:spotiflac_android/widgets/in_library_badge.dart';
import 'package:spotiflac_android/widgets/track_collection_quick_actions.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/screens/selection_mode_mixin.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';
import 'package:spotiflac_android/widgets/motion_header_banner.dart';
import 'package:spotiflac_android/widgets/cross_extension_share_sheet.dart';
import 'package:spotiflac_android/widgets/view_queue_snackbar_action.dart';

part 'artist_screen_widgets.dart';

class _ArtistCache {
  static final _cache = TtlCache<_CacheEntry>(const Duration(minutes: 10));

  static _CacheEntry? get(String artistId) => _cache.get(artistId);

  static void set(
    String artistId, {
    required List<ArtistAlbum> albums,
    List<ArtistAlbum>? releases,
    List<Track>? topTracks,
    String? headerImageUrl,
    String? headerVideoUrl,
    int? monthlyListeners,
  }) {
    _cache.set(
      artistId,
      _CacheEntry(
        albums: albums,
        releases: releases,
        topTracks: topTracks,
        headerImageUrl: headerImageUrl,
        headerVideoUrl: headerVideoUrl,
        monthlyListeners: monthlyListeners,
      ),
    );
  }
}

class _CacheEntry {
  final List<ArtistAlbum> albums;
  final List<ArtistAlbum>? releases;
  final List<Track>? topTracks;
  final String? headerImageUrl;
  final String? headerVideoUrl;
  final int? monthlyListeners;

  _CacheEntry({
    required this.albums,
    this.releases,
    this.topTracks,
    this.headerImageUrl,
    this.headerVideoUrl,
    this.monthlyListeners,
  });
}

class ArtistScreen extends ConsumerStatefulWidget {
  final String artistId;
  final String artistName;
  final String? coverUrl;
  final String? headerImageUrl;
  final String? headerVideoUrl;
  final int? monthlyListeners;
  final List<ArtistAlbum>? albums;
  final List<Track>? topTracks;
  final String? extensionId;

  const ArtistScreen({
    super.key,
    required this.artistId,
    required this.artistName,
    this.coverUrl,
    this.headerImageUrl,
    this.headerVideoUrl,
    this.monthlyListeners,
    this.albums,
    this.topTracks,
    this.extensionId,
  });

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen>
    with SelectionModeMixin<ArtistScreen> {
  bool _isLoadingDiscography = false;
  List<ArtistAlbum>? _albums;
  List<ArtistAlbum>? _releases;
  List<Track>? _topTracks;
  String? _headerImageUrl;
  String? _headerVideoUrl;
  int? _monthlyListeners;
  String? _error;

  bool _showTitleInAppBar = false;
  final ScrollController _scrollController = ScrollController();
  final PageController _popularPageController = PageController();
  final SelectionOverlayController _selectionOverlay =
      SelectionOverlayController();
  int _popularCurrentPage = 0;

  bool _isFetchingDiscography = false;
  List<ArtistAlbum>? _albumBucketSource;
  List<ArtistAlbum> _albumsOnlyBucket = const [];
  List<ArtistAlbum> _singlesBucket = const [];
  List<ArtistAlbum> _compilationsBucket = const [];

  double _responsiveScale({
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

  double _effectiveTextScale() {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    if (textScale < 1.0) return 1.0;
    if (textScale > 1.4) return 1.4;
    return textScale;
  }

  double _artistAlbumTileSize() {
    final scale = _responsiveScale(min: 0.82, max: 1.05);
    final textScale = _effectiveTextScale();
    return 140 * scale * (1 + (textScale - 1) * 0.12);
  }

  double _artistAlbumSectionHeight() {
    final tileSize = _artistAlbumTileSize();
    final textScale = _effectiveTextScale();
    return tileSize + 64 + ((textScale - 1) * 14);
  }

  String? _recommendedDownloadService() {
    return _directMetadataProviderId();
  }

  String _effectiveMetadataProviderIdFromArtistId() {
    if (widget.extensionId != null && widget.extensionId!.isNotEmpty) {
      return widget.extensionId!;
    }
    return resolveEffectiveMetadataProvider(
      legacyProviderIdFromResourceId(widget.artistId) ?? 'spotify',
      ref.read(extensionProvider),
    );
  }

  String? _directMetadataProviderId() {
    final providerId = _effectiveMetadataProviderIdFromArtistId();
    return providerId.isEmpty ? null : providerId;
  }

  String _metadataResourceId(String providerId) {
    return stripPrefixedResourceId(widget.artistId);
  }

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final providerId = _effectiveMetadataProviderIdFromArtistId();
      ref
          .read(recentAccessProvider.notifier)
          .recordArtistAccess(
            id: widget.artistId,
            name: widget.artistName,
            imageUrl: widget.coverUrl,
            providerId: providerId,
          );
    });

    if (widget.extensionId != null) {
      _albums = widget.albums;
      _topTracks = widget.topTracks;
      _headerImageUrl = widget.headerImageUrl;
      _headerVideoUrl = widget.headerVideoUrl;
      _monthlyListeners = widget.monthlyListeners;

      if ((_albums == null || _albums!.isEmpty) ||
          (_topTracks == null || _topTracks!.isEmpty)) {
        _fetchDiscography();
      }
      return;
    }

    final cached = _ArtistCache.get(widget.artistId);

    if (widget.albums != null) {
      _albums = widget.albums;
      _topTracks = widget.topTracks;
      _headerImageUrl = widget.headerImageUrl;
      _headerVideoUrl = widget.headerVideoUrl;
      _monthlyListeners = widget.monthlyListeners;

      if (_topTracks == null || _topTracks!.isEmpty) {
        _fetchDiscography();
      }
    } else if (cached != null) {
      _albums = cached.albums;
      _releases = cached.releases;
      _topTracks = cached.topTracks;
      _headerImageUrl = cached.headerImageUrl;
      _headerVideoUrl = cached.headerVideoUrl;
      _monthlyListeners = cached.monthlyListeners;

      if (_topTracks == null || _topTracks!.isEmpty) {
        _fetchDiscography();
      }
    } else {
      _fetchDiscography();
    }
  }

  void _onScroll() {
    final shouldShow = _scrollController.offset > 280;
    if (shouldShow != _showTitleInAppBar) {
      setState(() => _showTitleInAppBar = shouldShow);
    }
  }

  @override
  void dispose() {
    _selectionOverlay.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _popularPageController.dispose();
    super.dispose();
  }

  Future<void> _fetchDiscography() async {
    setState(() {
      _isLoadingDiscography = true;
      _error = null;
    });
    try {
      List<ArtistAlbum> albums;
      List<ArtistAlbum>? releases;
      List<Track>? topTracks;
      String? headerImage;
      String? headerVideo;
      int? listeners;

      if (_directMetadataProviderId() != null) {
        final providerId = _directMetadataProviderId()!;
        final artistData = await PlatformBridge.getProviderMetadata(
          providerId,
          'artist',
          _metadataResourceId(providerId),
        );
        final albumsList = artistData['albums'] as List<dynamic>? ?? [];
        albums = albumsList
            .map((a) => _parseArtistAlbum(a as Map<String, dynamic>))
            .toList();

        final releasesList = artistData['releases'] as List<dynamic>? ?? [];
        if (releasesList.isNotEmpty) {
          releases = releasesList
              .map((a) => _parseArtistAlbum(a as Map<String, dynamic>))
              .toList();
        }

        final topTracksList = artistData['top_tracks'] as List<dynamic>? ?? [];
        if (topTracksList.isNotEmpty) {
          topTracks = topTracksList
              .map((t) => _parseTrack(t as Map<String, dynamic>))
              .toList();
        }

        final artistInfo = artistData['artist_info'] as Map<String, dynamic>?;
        headerImage =
            artistInfo?['images'] as String? ??
            artistInfo?['header_image'] as String? ??
            artistInfo?['cover_url'] as String? ??
            artistData['header_image'] as String? ??
            artistData['cover_url'] as String? ??
            artistData['image_url'] as String?;
        headerVideo =
            artistInfo?['header_video'] as String? ??
            artistData['header_video'] as String?;
        listeners =
            artistInfo?['listeners'] as int? ?? artistData['listeners'] as int?;
      } else {
        final url = 'https://open.spotify.com/artist/${widget.artistId}';
        final result = await PlatformBridge.handleURLWithExtension(url);

        if (result != null && result['artist'] != null) {
          final artistData = result['artist'] as Map<String, dynamic>;
          final albumsList = artistData['albums'] as List<dynamic>? ?? [];
          albums = albumsList
              .map((a) => _parseArtistAlbum(a as Map<String, dynamic>))
              .toList();

          final topTracksList =
              artistData['top_tracks'] as List<dynamic>? ?? [];
          if (topTracksList.isNotEmpty) {
            topTracks = topTracksList
                .map((t) => _parseTrack(t as Map<String, dynamic>))
                .toList();
          }

          headerImage = artistData['header_image'] as String?;
          headerVideo = artistData['header_video'] as String?;
          listeners = artistData['listeners'] as int?;
        } else {
          throw StateError('Failed to load artist metadata from extension');
        }
      }

      final finalHeaderImage =
          headerImage ?? _headerImageUrl ?? widget.headerImageUrl;
      final finalHeaderVideo =
          headerVideo ?? _headerVideoUrl ?? widget.headerVideoUrl;
      final finalListeners =
          listeners ?? _monthlyListeners ?? widget.monthlyListeners;

      _ArtistCache.set(
        widget.artistId,
        albums: albums,
        releases: releases,
        topTracks: topTracks,
        headerImageUrl: finalHeaderImage,
        headerVideoUrl: finalHeaderVideo,
        monthlyListeners: finalListeners,
      );

      if (mounted) {
        setState(() {
          _albums = albums;
          _releases = releases;
          _topTracks = topTracks;
          _headerImageUrl = finalHeaderImage;
          _headerVideoUrl = finalHeaderVideo;
          _monthlyListeners = finalListeners;
          _error = null;
          _isLoadingDiscography = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = context.friendlyError(e);
          _isLoadingDiscography = false;
        });
      }
    }
  }

  Track _parseTrack(Map<String, dynamic> data, {ArtistAlbum? album}) {
    int durationMs = 0;
    final durationValue = data['duration_ms'];
    if (durationValue is int) {
      durationMs = durationValue;
    } else if (durationValue is double) {
      durationMs = durationValue.toInt();
    }

    final spotifyId = (data['spotify_id'] ?? '').toString();
    final nativeId = (data['id'] ?? '').toString();

    return Track(
      id: spotifyId.isNotEmpty ? spotifyId : nativeId,
      name: (data['name'] ?? '').toString(),
      artistName: (data['artists'] ?? data['artist'] ?? '').toString(),
      albumName: (data['album_name'] ?? data['album'] ?? album?.name ?? '')
          .toString(),
      albumArtist: normalizeOptionalString(data['album_artist']?.toString()),
      artistId:
          (data['artist_id'] ?? data['artistId'])?.toString() ??
          widget.artistId,
      albumId: data['album_id']?.toString() ?? album?.id,
      coverUrl: normalizeCoverReference(
        (data['cover_url'] ?? data['images'] ?? album?.coverUrl)?.toString(),
      ),
      isrc: data['isrc']?.toString(),
      duration: (durationMs / 1000).round(),
      trackNumber: data['track_number'] as int?,
      discNumber: data['disc_number'] as int?,
      totalDiscs: data['total_discs'] as int?,
      releaseDate: data['release_date']?.toString(),
      albumType:
          normalizeOptionalString(data['album_type']?.toString()) ??
          album?.albumType,
      totalTracks: data['total_tracks'] as int? ?? album?.totalTracks,
      composer: data['composer']?.toString(),
      source: data['provider_id']?.toString() ?? widget.extensionId,
      previewUrl: data['preview_url']?.toString(),
      explicit: parseExplicitFlag(data['explicit']),
    );
  }

  ArtistAlbum _parseArtistAlbum(Map<String, dynamic> data) {
    final totalTracksValue = data['total_tracks'];
    final totalTracks = totalTracksValue is int
        ? totalTracksValue
        : int.tryParse(totalTracksValue?.toString() ?? '') ?? 0;

    return ArtistAlbum(
      id: data['id'] as String? ?? '',
      name: (data['name'] ?? data['title'] ?? '').toString(),
      releaseDate: (data['release_date'] ?? '').toString(),
      totalTracks: totalTracks,
      coverUrl: normalizeCoverReference(
        (data['cover_url'] ?? data['images'] ?? data['cover_art'])?.toString(),
      ),
      albumType: (data['album_type'] ?? data['type'] ?? 'album').toString(),
      artists: (data['artists'] ?? data['artist'] ?? widget.artistName)
          .toString(),
      providerId: data['provider_id']?.toString() ?? widget.extensionId,
    );
  }

  void _ensureAlbumBuckets(List<ArtistAlbum> albums) {
    if (identical(albums, _albumBucketSource)) return;
    _albumBucketSource = albums;
    _albumsOnlyBucket = albums
        .where((a) => a.albumType == 'album')
        .toList(growable: false);
    _singlesBucket = albums
        .where((a) => a.albumType == 'single' || a.albumType == 'ep')
        .toList(growable: false);
    _compilationsBucket = albums
        .where((a) => a.albumType == 'compilation')
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final albums = _albums ?? [];
    _ensureAlbumBuckets(albums);
    final releases = _releases ?? const <ArtistAlbum>[];
    final albumsOnly = _albumsOnlyBucket;
    final singles = _singlesBucket;
    final compilations = _compilationsBucket;
    final bottomInset = context.navBarBottomInset;

    final hasDiscography =
        !_isLoadingDiscography && _error == null && albums.isNotEmpty;

    if (isSelectionMode || _selectionOverlay.isVisible) {
      final bottomPadding = MediaQuery.paddingOf(context).bottom;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncSelectionOverlay(albums: albums, bottomPadding: bottomPadding);
      });
    }

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
              controller: _scrollController,
              slivers: [
                _buildHeader(
                  context,
                  colorScheme,
                  albums: albums,
                  hasDiscography: hasDiscography,
                ),
                if (_isLoadingDiscography)
                  SliverToBoxAdapter(
                    child: ArtistScreenSkeleton(
                      showCoverHeader:
                          (_headerImageUrl ??
                              widget.headerImageUrl ??
                              widget.coverUrl) ==
                          null,
                      showPopularSection:
                          !widget.artistId.startsWith('deezer:') &&
                          !widget.artistId.startsWith('qobuz:') &&
                          !widget.artistId.startsWith('tidal:'),
                    ),
                  ),
                if (_error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ErrorCard(
                        error: _error!,
                        colorScheme: colorScheme,
                        onRetry: _fetchDiscography,
                      ),
                    ),
                  ),
                if (!_isLoadingDiscography && _error == null) ...[
                  if (_topTracks != null && _topTracks!.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildPopularSection(colorScheme),
                    ),
                  if (releases.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildAlbumSection(
                        context.l10n.artistReleases,
                        releases,
                        colorScheme,
                      ),
                    ),
                  if (albumsOnly.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildAlbumSection(
                        context.l10n.artistAlbums,
                        albumsOnly,
                        colorScheme,
                      ),
                    ),
                  if (singles.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildAlbumSection(
                        context.l10n.artistSingles,
                        singles,
                        colorScheme,
                        showTypeBadge: true,
                      ),
                    ),
                  if (compilations.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildAlbumSection(
                        context.l10n.artistCompilations,
                        compilations,
                        colorScheme,
                      ),
                    ),
                ],
                SliverToBoxAdapter(
                  child: SizedBox(height: isSelectionMode ? 120 : 32),
                ),
                SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _syncSelectionOverlay({
    required List<ArtistAlbum> albums,
    required double bottomPadding,
  }) {
    if (!isSelectionMode) {
      _selectionOverlay.hide();
      return;
    }
    _selectionOverlay.show(
      context,
      (overlayContext) => _buildSelectionBar(
        overlayContext,
        Theme.of(overlayContext).colorScheme,
        albums,
        bottomPadding,
      ),
    );
  }

  @override
  void exitSelectionMode() {
    HapticFeedback.lightImpact();
    super.exitSelectionMode();
  }

  @override
  void toggleSelection(String itemId) {
    HapticFeedback.selectionClick();
    super.toggleSelection(itemId);
  }

  void _deselectAll() {
    setState(() {
      selectedIds.clear();
    });
  }

  Widget _buildSelectionBar(
    BuildContext context,
    ColorScheme colorScheme,
    List<ArtistAlbum> allAlbums,
    double bottomPadding,
  ) {
    final allSelected =
        selectedIds.length == allAlbums.length && allAlbums.isNotEmpty;
    final selectedCount = selectedIds.length;
    final selectedAlbums = allAlbums
        .where((a) => selectedIds.contains(a.id))
        .toList();
    final totalTracks = selectedAlbums.fold<int>(
      0,
      (sum, a) => sum + a.totalTracks,
    );

    return SelectionBottomBar(
      selectedCount: selectedCount,
      allSelected: allSelected,
      onClose: exitSelectionMode,
      onToggleSelectAll: allSelected
          ? _deselectAll
          : () => selectAll(allAlbums.map((a) => a.id)),
      bottomPadding: bottomPadding,
      allSelectedLabel: context.l10n.tracksCount(totalTracks),
      tapToSelectLabel: selectedCount > 0
          ? context.l10n.tracksCount(totalTracks)
          : context.l10n.discographySelectAlbumsSubtitle,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: selectedCount > 0
                    ? () => _downloadSelectedAlbums(context, selectedAlbums)
                    : null,
                icon: const Icon(Icons.download, size: 18),
                label: Text(context.l10n.discographyDownloadSelected),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showDiscographyOptions(
    BuildContext context,
    ColorScheme colorScheme,
    List<ArtistAlbum> albums,
  ) {
    final albumsOnly = albums.where((a) => a.albumType == 'album').toList();
    final singles = albums
        .where((a) => a.albumType == 'single' || a.albumType == 'ep')
        .toList();

    final totalTracks = albums.fold<int>(0, (sum, a) => sum + a.totalTracks);
    final albumTracks = albumsOnly.fold<int>(
      0,
      (sum, a) => sum + a.totalTracks,
    );
    final singleTracks = singles.fold<int>(0, (sum, a) => sum + a.totalTracks);

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppSheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Row(
                  children: [
                    Icon(Icons.download, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      context.l10n.discographyDownload,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (albums.isNotEmpty)
                _DiscographyOptionTile(
                  icon: Icons.library_music,
                  title: context.l10n.discographyDownloadAll,
                  subtitle: context.l10n.discographyDownloadAllSubtitle(
                    totalTracks,
                    albums.length,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadAlbums(context, albums);
                  },
                ),
              if (albumsOnly.isNotEmpty)
                _DiscographyOptionTile(
                  icon: Icons.album,
                  title: context.l10n.discographyAlbumsOnly,
                  subtitle: context.l10n.discographyAlbumsOnlySubtitle(
                    albumTracks,
                    albumsOnly.length,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadAlbums(context, albumsOnly);
                  },
                ),
              if (singles.isNotEmpty)
                _DiscographyOptionTile(
                  icon: Icons.music_note,
                  title: context.l10n.discographySinglesOnly,
                  subtitle: context.l10n.discographySinglesOnlySubtitle(
                    singleTracks,
                    singles.length,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadAlbums(context, singles);
                  },
                ),
              _DiscographyOptionTile(
                icon: Icons.checklist,
                title: context.l10n.discographySelectAlbums,
                subtitle: context.l10n.discographySelectAlbumsSubtitle,
                onTap: () {
                  Navigator.pop(context);
                  enterSelectionMode(albums.first.id);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadAlbums(
    BuildContext context,
    List<ArtistAlbum> albums,
  ) async {
    final settings = ref.read(settingsProvider);
    if (settings.askQualityBeforeDownload || settings.allowQualityVariants) {
      DownloadServicePicker.show(
        context,
        recommendedService: _recommendedDownloadService(),
        onSelect: (quality, service) {
          _fetchAndQueueAlbums(albums, service, quality);
        },
      );
    } else {
      _fetchAndQueueAlbums(albums, settings.defaultService, null);
    }
  }

  Future<void> _downloadSelectedAlbums(
    BuildContext context,
    List<ArtistAlbum> albums,
  ) async {
    exitSelectionMode();
    await _downloadAlbums(context, albums);
  }

  Future<void> _toggleFavoriteArtist(BuildContext context) async {
    final providerId = _directMetadataProviderId();
    final imageUrl =
        _headerImageUrl ?? widget.headerImageUrl ?? widget.coverUrl;
    final added = await ref
        .read(libraryCollectionsProvider.notifier)
        .toggleFavoriteArtist(
          artistId: _metadataResourceId(providerId ?? ''),
          providerId: providerId,
          name: widget.artistName,
          imageUrl: imageUrl,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? context.l10n.collectionAddedToFavoriteArtists(widget.artistName)
              : context.l10n.collectionRemovedFromFavoriteArtists(
                  widget.artistName,
                ),
        ),
      ),
    );
  }

  Future<void> _fetchAndQueueAlbums(
    List<ArtistAlbum> albums,
    String service,
    String? qualityOverride,
  ) async {
    if (_isFetchingDiscography) return;

    setState(() => _isFetchingDiscography = true);

    if (!mounted) {
      setState(() => _isFetchingDiscography = false);
      return;
    }

    final progressDialogKey = GlobalKey<_FetchingProgressDialogState>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _FetchingProgressDialog(
        key: progressDialogKey,
        totalAlbums: albums.length,
        onCancel: () {
          setState(() => _isFetchingDiscography = false);
          Navigator.pop(ctx);
        },
      ),
    );

    final allTracks = <Track>[];
    int fetchedCount = 0;
    int failedCount = 0;

    for (final album in albums) {
      if (!_isFetchingDiscography) break;

      try {
        final tracks = await _fetchAlbumTracks(album);
        allTracks.addAll(tracks);
      } catch (e) {
        failedCount++;
      }

      fetchedCount++;

      if (mounted) {
        progressDialogKey.currentState?.updateProgress(
          fetchedCount,
          albums.length,
        );
      }
    }

    setState(() => _isFetchingDiscography = false);

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (failedCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.discographyFailedToFetch)),
      );
    }

    if (allTracks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.discographyNoAlbums)),
        );
      }
      return;
    }

    final settings = ref.read(settingsProvider);
    final skipExisting =
        settings.deduplicateDownloads && !settings.allowQualityVariants;
    final historyLookups = allTracks
        .map(historyLookupForTrack)
        .toList(growable: false);
    final existingHistoryKeys = skipExisting
        ? await ref.read(
            downloadHistoryBatchExistsProvider(
              HistoryBatchLookupRequest(historyLookups),
            ).future,
          )
        : const <String>{};
    final tracksToQueue = <Track>[];
    int skippedCount = 0;

    for (var i = 0; i < allTracks.length; i++) {
      final track = allTracks[i];
      final isDownloaded =
          skipExisting &&
          existingHistoryKeys.contains(historyLookups[i].lookupKey);

      if (!isDownloaded) {
        tracksToQueue.add(track);
      } else {
        skippedCount++;
      }
    }

    if (tracksToQueue.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.discographySkippedDownloaded(0, skippedCount),
            ),
          ),
        );
      }
      return;
    }

    ref
        .read(downloadQueueProvider.notifier)
        .addMultipleToQueue(
          tracksToQueue,
          service,
          qualityOverride: qualityOverride,
        );

    if (mounted) {
      final message = skippedCount > 0
          ? context.l10n.discographySkippedDownloaded(
              tracksToQueue.length,
              skippedCount,
            )
          : context.l10n.discographyAddedToQueue(tracksToQueue.length);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: buildViewQueueSnackBarAction(context),
        ),
      );
    }
  }

  Future<List<Track>> _fetchAlbumTracks(ArtistAlbum album) async {
    final providerId = album.providerId;
    if (providerId != null && providerId.isNotEmpty) {
      final resourceId = stripPrefixedResourceId(album.id);
      final metadata = await PlatformBridge.getProviderMetadata(
        providerId,
        'album',
        resourceId,
      );
      if (metadata['track_list'] != null) {
        final tracksList = metadata['track_list'] as List<dynamic>;
        return tracksList
            .map((t) => _parseTrack(t as Map<String, dynamic>, album: album))
            .toList();
      }
    } else {
      final url = 'https://open.spotify.com/album/${album.id}';
      final result = await PlatformBridge.handleURLWithExtension(url);
      if (result != null && result['tracks'] != null) {
        final tracksList = result['tracks'] as List<dynamic>;
        return tracksList
            .map((t) => _parseTrack(t as Map<String, dynamic>, album: album))
            .toList();
      }
    }
    return [];
  }
}
