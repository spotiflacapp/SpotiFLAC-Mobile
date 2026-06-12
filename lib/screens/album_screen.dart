import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/recent_access_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/image_cache_utils.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/widgets/track_collection_quick_actions.dart';
import 'package:spotiflac_android/widgets/download_service_picker.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/widgets/playlist_picker_sheet.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';
import 'package:spotiflac_android/widgets/audio_quality_badges.dart';
import 'package:spotiflac_android/widgets/cross_extension_share_sheet.dart';

class _AlbumCache {
  static final Map<String, _CacheEntry> _cache = {};
  static const Duration _ttl = Duration(minutes: 10);

  static List<Track>? get(String albumId) {
    final entry = _cache[albumId];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _cache.remove(albumId);
      return null;
    }
    return entry.tracks;
  }

  static void set(String albumId, List<Track> tracks) {
    _cache[albumId] = _CacheEntry(tracks, DateTime.now().add(_ttl));
  }
}

class _CacheEntry {
  final List<Track> tracks;
  final DateTime expiresAt;
  _CacheEntry(this.tracks, this.expiresAt);
}

class AlbumScreen extends ConsumerStatefulWidget {
  final String albumId;
  final String albumName;
  final String? coverUrl;
  final List<Track>? tracks;
  final String? extensionId;
  final String? artistId;
  final String? artistName;

  const AlbumScreen({
    super.key,
    required this.albumId,
    required this.albumName,
    this.coverUrl,
    this.tracks,
    this.extensionId,
    this.artistId,
    this.artistName,
  });

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  List<Track>? _tracks;
  bool _isLoading = false;
  String? _error;
  bool _showTitleInAppBar = false;
  String? _artistId;
  String? _albumType;
  int? _albumTotalTracks;
  final ScrollController _scrollController = ScrollController();

  String _legacyProviderIdFromResourceId(String value) {
    if (value.startsWith('deezer:')) return 'deezer';
    if (value.startsWith('qobuz:')) return 'qobuz';
    if (value.startsWith('tidal:')) return 'tidal';
    if (value.startsWith('spotify:')) return 'spotify';
    return 'spotify';
  }

  String _effectiveMetadataProviderIdFromAlbumId() {
    if (widget.extensionId != null && widget.extensionId!.isNotEmpty) {
      return widget.extensionId!;
    }
    return resolveEffectiveMetadataProvider(
      _legacyProviderIdFromResourceId(widget.albumId),
      ref.read(extensionProvider),
    );
  }

  String _stripPrefixedResourceId(String value) {
    final colonIndex = value.indexOf(':');
    if (colonIndex <= 0 || colonIndex == value.length - 1) {
      return value;
    }
    return value.substring(colonIndex + 1);
  }

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final providerId = _effectiveMetadataProviderIdFromAlbumId();
      ref
          .read(recentAccessProvider.notifier)
          .recordAlbumAccess(
            id: widget.albumId,
            name: widget.albumName,
            artistName:
                widget.artistName ??
                widget.tracks?.firstOrNull?.albumArtist ??
                widget.tracks?.firstOrNull?.artistName,
            imageUrl: widget.coverUrl,
            providerId: providerId,
          );
    });

    if (widget.tracks != null && widget.tracks!.isNotEmpty) {
      _tracks = widget.tracks;
    } else {
      _tracks = _AlbumCache.get(widget.albumId);
    }
    _artistId = widget.artistId;
    _albumType = _tracks?.firstOrNull?.albumType;
    _albumTotalTracks = _tracks?.firstOrNull?.totalTracks;

    if (_tracks == null || _tracks!.isEmpty) {
      _fetchTracks();
    }
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
    final mediaSize = MediaQuery.of(context).size;
    return (mediaSize.height * 0.55).clamp(360.0, 520.0);
  }

  String? _highResCoverUrl(String? url) {
    if (url == null) return null;
    if (url.contains('ab67616d00001e02')) {
      return url.replaceAll('ab67616d00001e02', 'ab67616d0000b273');
    }
    final deezerRegex = RegExp(r'/(\d+)x(\d+)-(\d+)-(\d+)-(\d+)-(\d+)\.jpg$');
    if (url.contains('cdn-images.dzcdn.net') && deezerRegex.hasMatch(url)) {
      return url.replaceAllMapped(
        deezerRegex,
        (m) => '/1000x1000-${m[3]}-${m[4]}-${m[5]}-${m[6]}.jpg',
      );
    }
    return url;
  }

  String _formatReleaseDate(String date) {
    if (date.length >= 10) {
      final parts = date.substring(0, 10).split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
    } else if (date.length >= 7) {
      final parts = date.split('-');
      if (parts.length >= 2) {
        return '${parts[1]}/${parts[0]}';
      }
    }
    return date;
  }

  Future<void> _fetchTracks() async {
    setState(() => _isLoading = true);
    try {
      final directProviderId = _directMetadataProviderId();
      if (directProviderId != null) {
        final metadata = await PlatformBridge.getProviderMetadata(
          directProviderId,
          'album',
          _metadataResourceId(directProviderId),
        );
        final trackList = metadata['track_list'] as List<dynamic>;
        final albumInfo = metadata['album_info'] as Map<String, dynamic>?;
        final artistId = (albumInfo?['artist_id'] ?? albumInfo?['artistId'])
            ?.toString();
        final albumType = normalizeOptionalString(
          albumInfo?['album_type']?.toString(),
        );
        final totalTracks = albumInfo?['total_tracks'] as int?;
        final tracks = trackList
            .map(
              (t) => _parseTrack(
                t as Map<String, dynamic>,
                albumTypeFallback: albumType,
                totalTracksFallback: totalTracks,
              ),
            )
            .toList();

        _AlbumCache.set(widget.albumId, tracks);

        if (mounted) {
          setState(() {
            _tracks = tracks;
            _artistId = artistId;
            _albumType = albumType;
            _albumTotalTracks = totalTracks;
            _isLoading = false;
          });
        }
        return;
      } else {
        final url = 'https://open.spotify.com/album/${widget.albumId}';
        final result = await PlatformBridge.handleURLWithExtension(url);
        if (result == null || result['tracks'] == null) {
          throw StateError('Failed to load album metadata from extension');
        }

        final trackList = result['tracks'] as List<dynamic>;
        final albumInfo = result['album'] as Map<String, dynamic>?;
        final artistId = (albumInfo?['artist_id'] ?? albumInfo?['artistId'])
            ?.toString();
        final albumType = normalizeOptionalString(
          albumInfo?['album_type']?.toString(),
        );
        final totalTracks = albumInfo?['total_tracks'] as int?;
        final tracks = trackList
            .map(
              (t) => _parseTrack(
                t as Map<String, dynamic>,
                albumTypeFallback: albumType,
                totalTracksFallback: totalTracks,
              ),
            )
            .toList();

        _AlbumCache.set(widget.albumId, tracks);

        if (mounted) {
          setState(() {
            _tracks = tracks;
            _artistId = artistId;
            _albumType = albumType;
            _albumTotalTracks = totalTracks;
            _isLoading = false;
          });
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String? _directMetadataProviderId() {
    final providerId = _effectiveMetadataProviderIdFromAlbumId();
    return providerId.isEmpty ? null : providerId;
  }

  String _metadataResourceId(String providerId) {
    return _stripPrefixedResourceId(widget.albumId);
  }

  Track _parseTrack(
    Map<String, dynamic> data, {
    String? albumTypeFallback,
    int? totalTracksFallback,
  }) {
    return Track(
      id: data['spotify_id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      artistName: data['artists'] as String? ?? '',
      albumName: data['album_name'] as String? ?? '',
      albumArtist: data['album_artist'] as String?,
      artistId:
          (data['artist_id'] ?? data['artistId'])?.toString() ?? _artistId,
      albumId: data['album_id']?.toString() ?? widget.albumId,
      coverUrl: normalizeCoverReference(data['images']?.toString()),
      isrc: data['isrc'] as String?,
      duration: ((data['duration_ms'] as int? ?? 0) / 1000).round(),
      trackNumber: data['track_number'] as int?,
      discNumber: data['disc_number'] as int?,
      totalDiscs: data['total_discs'] as int?,
      releaseDate: data['release_date'] as String?,
      albumType:
          normalizeOptionalString(data['album_type']?.toString()) ??
          albumTypeFallback ??
          _albumType,
      totalTracks:
          data['total_tracks'] as int? ??
          totalTracksFallback ??
          _albumTotalTracks,
      composer: data['composer']?.toString(),
      audioQuality: data['audio_quality']?.toString(),
      audioModes: data['audio_modes']?.toString(),
    );
  }

  String? _recommendedDownloadService() {
    return _directMetadataProviderId();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tracks = _tracks ?? [];
    final pageBackgroundColor = colorScheme.surface;

    return Scaffold(
      backgroundColor: pageBackgroundColor,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          _buildAppBar(context, colorScheme, pageBackgroundColor),
          _buildInfoCard(context, colorScheme),
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: AlbumTrackListSkeleton(itemCount: 10),
              ),
            ),
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildErrorWidget(_error!, colorScheme),
              ),
            ),
          if (!_isLoading && _error == null && tracks.isNotEmpty) ...[
            _buildTrackList(context, colorScheme, tracks),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    ColorScheme colorScheme,
    Color pageBackgroundColor,
  ) {
    final expandedHeight = _calculateExpandedHeight(context);
    final tracks = _tracks ?? [];
    final artistName =
        widget.artistName ??
        (tracks.isNotEmpty
            ? (tracks.first.albumArtist ?? tracks.first.artistName)
            : null);
    final releaseDate = tracks.isNotEmpty ? tracks.first.releaseDate : null;

    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: true,
      stretch: true,
      backgroundColor: pageBackgroundColor,
      surfaceTintColor: Colors.transparent,
      title: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _showTitleInAppBar ? 1.0 : 0.0,
        child: Text(
          widget.albumName,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final collapseRatio =
              (constraints.maxHeight - kToolbarHeight) /
              (expandedHeight - kToolbarHeight);
          final showContent = collapseRatio > 0.3;
          final cacheWidth = coverCacheWidthForViewport(context);

          return FlexibleSpaceBar(
            collapseMode: CollapseMode.pin,
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.coverUrl != null)
                  CachedNetworkImage(
                    imageUrl:
                        _highResCoverUrl(widget.coverUrl) ?? widget.coverUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: cacheWidth,
                    cacheManager: CoverCacheManager.instance,
                    placeholder: (_, _) =>
                        Container(color: colorScheme.surface),
                    errorWidget: (_, _, _) =>
                        Container(color: colorScheme.surface),
                  )
                else
                  Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.album,
                      size: 80,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
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
                        Text(
                          widget.albumName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (artistName != null && artistName.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          ClickableArtistName(
                            artistName: artistName,
                            artistId: _artistId,
                            coverUrl: widget.coverUrl,
                            extensionId: widget.extensionId,
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (tracks.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
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
                                    const Icon(
                                      Icons.music_note,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      context.l10n.tracksCount(tracks.length),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (releaseDate != null && releaseDate.isNotEmpty)
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
                                      const Icon(
                                        Icons.calendar_today,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatReleaseDate(releaseDate),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildLoveAllButton(),
                              const SizedBox(width: 12),
                              Flexible(
                                child: FilledButton.icon(
                                  onPressed: () => _downloadAll(context),
                                  icon: Icon(Icons.download, size: 18),
                                  label: Text(
                                    context.l10n.downloadAllCount(
                                      tracks.length,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black87,
                                    minimumSize: const Size(0, 48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              _buildAddToPlaylistButton(context),
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
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            tooltip: context.l10n.openInOtherServices,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.open_in_new_rounded, color: Colors.white),
            ),
            onPressed: () => _showShareSheet(context, tracks, artistName),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(BuildContext context, ColorScheme colorScheme) {
    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }

  Widget _buildTrackList(
    BuildContext context,
    ColorScheme colorScheme,
    List<Track> tracks,
  ) {
    final historyLookups = tracks
        .map(historyLookupForTrack)
        .toList(growable: false);
    final existingHistoryKeys = ref
        .watch(
          downloadHistoryBatchExistsProvider(
            HistoryBatchLookupRequest(historyLookups),
          ),
        )
        .maybeWhen(data: (keys) => keys, orElse: () => const <String>{});
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final track = tracks[index];
        final isInHistory = existingHistoryKeys.contains(
          historyLookups[index].lookupKey,
        );
        return KeyedSubtree(
          key: ValueKey(track.id),
          child: StaggeredListItem(
            index: index,
            child: _AlbumTrackItem(
              track: track,
              isInHistory: isInHistory,
              onDownload: () => _downloadTrack(context, track),
            ),
          ),
        );
      }, childCount: tracks.length),
    );
  }

  void _downloadTrack(BuildContext context, Track track) {
    final settings = ref.read(settingsProvider);
    if (settings.askQualityBeforeDownload) {
      DownloadServicePicker.show(
        context,
        trackName: track.name,
        artistName: track.artistName,
        coverUrl: track.coverUrl,
        recommendedService: _recommendedDownloadService(),
        onSelect: (quality, service) {
          ref
              .read(downloadQueueProvider.notifier)
              .addToQueue(track, service, qualityOverride: quality);
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

  Future<void> _downloadAll(BuildContext context) async {
    final tracks = _tracks;
    if (tracks == null || tracks.isEmpty) return;

    final historyLookups = tracks
        .map(historyLookupForTrack)
        .toList(growable: false);
    final existingHistoryKeys = await ref.read(
      downloadHistoryBatchExistsProvider(
        HistoryBatchLookupRequest(historyLookups),
      ).future,
    );
    if (!context.mounted) return;
    final settings = ref.read(settingsProvider);
    final localLibState =
        (settings.localLibraryEnabled && settings.localLibraryShowDuplicates)
        ? ref.read(localLibraryProvider)
        : null;
    final tracksToQueue = <Track>[];
    int skippedCount = 0;

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
        artistName: widget.albumName,
        recommendedService: _recommendedDownloadService(),
        onSelect: (quality, service) {
          ref
              .read(downloadQueueProvider.notifier)
              .addMultipleToQueue(
                tracksToQueue,
                service,
                qualityOverride: quality,
              );
          _showQueuedSnackbar(context, tracksToQueue.length, skippedCount);
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
      ref
          .read(downloadQueueProvider.notifier)
          .addMultipleToQueue(tracksToQueue, service);
      _showQueuedSnackbar(context, tracksToQueue.length, skippedCount);
    }
  }

  void _showQueuedSnackbar(BuildContext context, int added, int skipped) {
    final message = skipped > 0
        ? context.l10n.discographySkippedDownloaded(added, skipped)
        : context.l10n.snackbarAddedTracksToQueue(added);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildLoveAllButton() {
    final collectionsState = ref.watch(libraryCollectionsProvider);
    final tracks = _tracks;
    final allLoved =
        tracks != null &&
        tracks.isNotEmpty &&
        tracks.every((t) => collectionsState.isLoved(t));

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.15),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: IconButton(
        onPressed: tracks == null || tracks.isEmpty
            ? null
            : () => _loveAll(tracks),
        icon: Icon(
          allLoved ? Icons.favorite : Icons.favorite_border,
          size: 22,
          color: allLoved ? Colors.redAccent : Colors.white,
        ),
        tooltip: allLoved
            ? context.l10n.trackOptionRemoveFromLoved
            : context.l10n.tooltipLoveAll,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildAddToPlaylistButton(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.15),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: IconButton(
        onPressed: _tracks == null || _tracks!.isEmpty
            ? null
            : () => showAddTracksToPlaylistSheet(context, ref, _tracks!),
        icon: const Icon(Icons.add, size: 22, color: Colors.white),
        tooltip: context.l10n.tooltipAddToPlaylist,
        padding: EdgeInsets.zero,
      ),
    );
  }

  void _showShareSheet(
    BuildContext context,
    List<Track> tracks,
    String? artistName,
  ) {
    final sourceExtensionId = _directMetadataProviderId() ?? '';
    final resolvedArtists =
        artistName ??
        tracks.firstOrNull?.albumArtist ??
        tracks.firstOrNull?.artistName ??
        '';

    CrossExtensionShareSheet.show(
      context,
      name: widget.albumName,
      artists: resolvedArtists,
      type: 'album',
      sourceExtensionId: sourceExtensionId,
    );
  }

  Future<void> _loveAll(List<Track> tracks) async {
    final notifier = ref.read(libraryCollectionsProvider.notifier);
    final state = ref.read(libraryCollectionsProvider);
    final allLoved = tracks.every((t) => state.isLoved(t));

    if (allLoved) {
      for (final track in tracks) {
        final key = trackCollectionKey(track);
        await notifier.removeFromLoved(key);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.snackbarRemovedTracksFromLoved(tracks.length),
            ),
          ),
        );
      }
    } else {
      int addedCount = 0;
      for (final track in tracks) {
        if (!state.isLoved(track)) {
          await notifier.toggleLoved(track);
          addedCount++;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.snackbarAddedTracksToLoved(addedCount)),
          ),
        );
      }
    }
  }

  Widget _buildErrorWidget(String error, ColorScheme colorScheme) {
    final isRateLimit =
        error.contains('429') ||
        error.toLowerCase().contains('rate limit') ||
        error.toLowerCase().contains('too many requests');

    if (isRateLimit) {
      return Card(
        elevation: 0,
        color: colorScheme.errorContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.timer_off, color: colorScheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.errorRateLimited,
                      style: TextStyle(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.errorRateLimitedMessage,
                      style: TextStyle(
                        color: colorScheme.onErrorContainer,
                        fontSize: 12,
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

    return Card(
      elevation: 0,
      color: colorScheme.errorContainer.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(error, style: TextStyle(color: colorScheme.error)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumTrackItem extends ConsumerWidget {
  final Track track;
  final bool isInHistory;
  final VoidCallback onDownload;

  const _AlbumTrackItem({
    required this.track,
    required this.isInHistory,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    final queueItem = ref.watch(
      downloadQueueLookupProvider.select(
        (lookup) => lookup.byTrackId[track.id],
      ),
    );

    final showLocalLibraryIndicator = ref.watch(
      settingsProvider.select(
        (s) => s.localLibraryEnabled && s.localLibraryShowDuplicates,
      ),
    );
    final isInLocalLibrary = showLocalLibraryIndicator
        ? ref.watch(
            localLibraryProvider.select(
              (state) => state.existsInLibrary(
                isrc: track.isrc,
                trackName: track.name,
                artistName: track.artistName,
              ),
            ),
          )
        : false;

    final isQueued = queueItem != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Card(
        elevation: 0,
        color: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 2),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: SizedBox(
            width: 32,
            child: Center(
              child: Text(
                '${track.trackNumber ?? 0}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          title: Text(
            track.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
          subtitle: Row(
            children: [
              Flexible(
                child: ClickableArtistName(
                  artistName: track.artistName,
                  artistId: track.artistId,
                  coverUrl: track.coverUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
              ...buildQualityBadges(
                audioQuality: track.audioQuality,
                audioModes: track.audioModes,
                colorScheme: colorScheme,
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
          trailing: TrackCollectionQuickActions(track: track),
          onTap: () => _handleTap(context, ref, isQueued: isQueued),
          onLongPress: () => TrackCollectionQuickActions.showTrackOptionsSheet(
            context,
            ref,
            track,
          ),
        ),
      ),
    );
  }

  void _handleTap(
    BuildContext context,
    WidgetRef ref, {
    required bool isQueued,
  }) async {
    if (isQueued) return;

    final playedLocal = await _playLocalIfAvailable(context, ref);
    if (playedLocal) {
      return;
    }

    onDownload();
  }

  Future<bool> _playLocalIfAvailable(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final historyNotifier = ref.read(downloadHistoryProvider.notifier);

    try {
      DownloadHistoryItem? historyItem = await historyNotifier
          .getBySpotifyIdAsync(track.id);
      final isrc = track.isrc?.trim();
      historyItem ??= (isrc != null && isrc.isNotEmpty)
          ? await historyNotifier.getByIsrcAsync(isrc)
          : null;
      historyItem ??= await historyNotifier.findByTrackAndArtistAsync(
        track.name,
        track.artistName,
      );

      if (historyItem != null) {
        final exists = await fileExists(historyItem.filePath);
        if (exists) {
          await ref
              .read(playbackProvider.notifier)
              .playLocalPath(
                path: historyItem.filePath,
                title: track.name,
                artist: track.artistName,
                album: track.albumName,
                coverUrl: track.coverUrl ?? '',
              );
          return true;
        }
        historyNotifier.removeFromHistory(historyItem.id);
      }

      final localItem = await ref
          .read(localLibraryProvider.notifier)
          .findExistingAsync(
            isrc: isrc,
            trackName: track.name,
            artistName: track.artistName,
          );

      if (localItem != null && await fileExists(localItem.filePath)) {
        await ref
            .read(playbackProvider.notifier)
            .playLocalPath(
              path: localItem.filePath,
              title: localItem.trackName,
              artist: localItem.artistName,
              album: localItem.albumName,
              coverUrl: localItem.coverPath ?? track.coverUrl ?? '',
            );
        return true;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.snackbarCannotOpenFile('$e'))),
        );
      }
      return true;
    }

    return false;
  }
}
