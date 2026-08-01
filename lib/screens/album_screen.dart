import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/collection_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/recent_access_provider.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/image_cache_utils.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/utils/cover_art_utils.dart';
import 'package:spotiflac_android/screens/collapsing_header_scroll_mixin.dart';
import 'package:spotiflac_android/screens/selection_mode_mixin.dart';
import 'package:spotiflac_android/widgets/error_card.dart';
import 'package:spotiflac_android/widgets/album_detail_header.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/utils/provider_resource_ids.dart';
import 'package:spotiflac_android/utils/ttl_cache.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/widgets/playlist_picker_sheet.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';
import 'package:spotiflac_android/widgets/cross_extension_share_sheet.dart';
import 'package:spotiflac_android/widgets/track_list_tile.dart';
import 'package:spotiflac_android/widgets/motion_header_banner.dart';
import 'package:spotiflac_android/widgets/track_detail_actions.dart';
import 'package:spotiflac_android/widgets/selection_action_button.dart';
import 'package:spotiflac_android/widgets/selection_bottom_bar.dart';

class _AlbumCache {
  static final _cache = TtlCache<List<Track>>(const Duration(minutes: 10));

  static List<Track>? get(String albumId) => _cache.get(albumId);

  static void set(String albumId, List<Track> tracks) =>
      _cache.set(albumId, tracks);
}

class AlbumScreen extends ConsumerStatefulWidget {
  final String albumId;
  final String albumName;
  final String? coverUrl;
  final String? headerVideoUrl;
  final String? headerImageUrl;
  final List<String>? audioTraits;
  final List<Track>? tracks;
  final String? extensionId;
  final String? artistId;
  final String? artistName;

  const AlbumScreen({
    super.key,
    required this.albumId,
    required this.albumName,
    this.coverUrl,
    this.headerVideoUrl,
    this.headerImageUrl,
    this.audioTraits,
    this.tracks,
    this.extensionId,
    this.artistId,
    this.artistName,
  });

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen>
    with
        SelectionModeMixin<AlbumScreen>,
        CollapsingHeaderScrollMixin<AlbumScreen> {
  List<Track>? _tracks;
  bool _isLoading = false;
  String? _error;
  String? _artistId;
  String? _albumType;
  int? _albumTotalTracks;
  String? _headerVideoUrl;
  String? _headerImageUrl;
  List<String> _audioTraits = const [];

  String _effectiveMetadataProviderIdFromAlbumId() {
    if (widget.extensionId != null && widget.extensionId!.isNotEmpty) {
      return widget.extensionId!;
    }
    return resolveEffectiveMetadataProvider(
      legacyProviderIdFromResourceId(widget.albumId) ?? 'spotify',
      ref.read(extensionProvider),
    );
  }

  @override
  void initState() {
    super.initState();

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
    _headerVideoUrl = widget.headerVideoUrl;
    _headerImageUrl = widget.headerImageUrl;
    _audioTraits = widget.audioTraits ?? const [];

    if (_tracks == null || _tracks!.isEmpty) {
      _fetchTracks();
    }
  }

  Future<void> _fetchTracks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final directProviderId = _directMetadataProviderId();
      if (directProviderId != null) {
        final metadata = await PlatformBridge.getProviderMetadata(
          directProviderId,
          'album',
          _metadataResourceId(directProviderId),
        );
        _applyAlbumMetadata(
          metadata['track_list'] as List<dynamic>,
          metadata['album_info'] as Map<String, dynamic>?,
        );
        return;
      } else {
        final url = 'https://open.spotify.com/album/${widget.albumId}';
        final result = await PlatformBridge.handleURLWithExtension(url);
        if (result == null || result['tracks'] == null) {
          throw StateError('Failed to load album metadata from extension');
        }

        _applyAlbumMetadata(
          result['tracks'] as List<dynamic>,
          result['album'] as Map<String, dynamic>?,
          fallbackSource: result,
        );
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = context.friendlyError(e);
          _isLoading = false;
        });
      }
    }
  }

  /// Parses tracks + header metadata from either the direct-provider payload
  /// (`albumInfo` only) or the extension payload (`albumInfo` falling back to
  /// top-level [fallbackSource] keys), then updates state and the TTL cache.
  void _applyAlbumMetadata(
    List<dynamic> trackList,
    Map<String, dynamic>? albumInfo, {
    Map<String, dynamic>? fallbackSource,
  }) {
    final artistId = (albumInfo?['artist_id'] ?? albumInfo?['artistId'])
        ?.toString();
    final albumType = normalizeOptionalString(
      albumInfo?['album_type']?.toString(),
    );
    final totalTracks = albumInfo?['total_tracks'] as int?;
    final headerVideo =
        (albumInfo?['header_video'] ?? fallbackSource?['header_video'])
            ?.toString();
    final headerImage =
        (albumInfo?['header_image'] ?? fallbackSource?['header_image'])
            ?.toString();
    final audioTraits =
        ((albumInfo?['audio_traits'] ?? fallbackSource?['audio_traits'])
                as List?)
            ?.map((e) => e.toString())
            .toList();
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
        _headerVideoUrl = (headerVideo != null && headerVideo.isNotEmpty)
            ? headerVideo
            : _headerVideoUrl;
        _headerImageUrl = (headerImage != null && headerImage.isNotEmpty)
            ? headerImage
            : _headerImageUrl;
        _audioTraits = (audioTraits != null && audioTraits.isNotEmpty)
            ? audioTraits
            : _audioTraits;
        _error = null;
        _isLoading = false;
      });
    }
  }

  String? _directMetadataProviderId() {
    final providerId = _effectiveMetadataProviderIdFromAlbumId();
    return providerId.isEmpty ? null : providerId;
  }

  String _metadataResourceId(String providerId) {
    return stripPrefixedResourceId(widget.albumId);
  }

  List<Widget> _audioTraitInline() {
    final traits = _audioTraits
        .map((t) => t.toLowerCase().trim())
        .where((t) => t.isNotEmpty)
        .toSet();
    if (traits.isEmpty) return const [];

    bool has(List<String> keys) => keys.any(traits.contains);

    final items = <Widget>[];
    if (has(['atmos', 'dolby_atmos', 'dolby-atmos'])) {
      items.add(HeaderMetaItem('Dolby Atmos', icon: Icons.surround_sound));
    } else if (has(['spatial'])) {
      items.add(HeaderMetaItem('Spatial Audio', icon: Icons.surround_sound));
    }

    if (has(['hi-res-lossless', 'hi_res_lossless', 'hires-lossless'])) {
      items.add(HeaderMetaItem('Hi-Res Lossless', icon: Icons.graphic_eq));
    } else if (has(['lossless'])) {
      items.add(HeaderMetaItem('Lossless', icon: Icons.graphic_eq));
    }

    return items;
  }

  Widget _buildHeaderMeta(BuildContext context, String? releaseDate) {
    final items = <Widget>[];

    final year = _releaseYear(releaseDate);
    if (year != null) items.add(HeaderMetaItem(year));
    items.addAll(_audioTraitInline());

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20),
      child: HeaderMetaRow(items: items),
    );
  }

  String? _releaseYear(String? date) {
    if (date == null || date.isEmpty) return null;
    final match = RegExp(r'(\d{4})').firstMatch(date);
    return match?.group(1);
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
      previewUrl: data['preview_url']?.toString(),
      explicit: parseExplicitFlag(data['explicit']),
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
    final bottomInset = context.navBarBottomInset;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    pruneSelection({
      for (var index = 0; index < tracks.length; index++)
        _trackSelectionId(tracks[index], index),
    });

    return CollectionScaffold(
      scrollController: scrollController,
      isSelectionMode: isSelectionMode,
      onExitSelectionMode: exitSelectionMode,
      backgroundColor: pageBackgroundColor,
      bottomInset: bottomInset,
      selectionBar: _buildSelectionBottomBar(
        context,
        colorScheme,
        tracks,
        bottomPadding,
      ),
      appBar: _buildAppBar(context, colorScheme, pageBackgroundColor),
      slivers: [
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
              child: ErrorCard(
                error: _error!,
                colorScheme: colorScheme,
                onRetry: _fetchTracks,
              ),
            ),
          ),
        if (!_isLoading && _error == null && tracks.isNotEmpty) ...[
          _buildTrackList(context, colorScheme, tracks),
          _buildAlbumFooter(context, colorScheme, tracks),
        ],
      ],
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    ColorScheme colorScheme,
    Color pageBackgroundColor,
  ) {
    final tracks = _tracks ?? [];
    final artistName =
        widget.artistName ??
        (tracks.isNotEmpty
            ? (tracks.first.albumArtist ?? tracks.first.artistName)
            : null);
    final releaseDate = tracks.isNotEmpty ? tracks.first.releaseDate : null;

    final motionUrl = _headerVideoUrl ?? widget.headerVideoUrl;
    final hasMotion =
        motionUrl != null &&
        motionUrl.trim().isNotEmpty &&
        Uri.tryParse(motionUrl)?.hasAuthority == true;
    final coverThumbUrl = widget.coverUrl ?? _headerImageUrl;
    final showSquareCover = !hasMotion;
    final expandedHeight = calculateExpandedHeight(context);
    final cacheWidth = coverCacheWidthForViewport(context);
    final headerBgUrl =
        _headerImageUrl ?? widget.headerImageUrl ?? widget.coverUrl;
    Widget headerBgImage() => headerBgUrl != null
        ? CachedNetworkImage(
            imageUrl: highResCoverUrl(headerBgUrl) ?? headerBgUrl,
            fit: BoxFit.cover,
            memCacheWidth: cacheWidth,
            cacheManager: CoverCacheManager.instance,
            placeholder: (_, _) => Container(color: colorScheme.surface),
            errorWidget: (_, _, _) => Container(color: colorScheme.surface),
          )
        : Container(
            color: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.album,
              size: 80,
              color: colorScheme.onSurfaceVariant,
            ),
          );

    final Widget background = hasMotion
        ? MotionHeaderBanner(videoUrl: motionUrl, fallback: headerBgImage())
        : headerBgImage();

    return AlbumDetailHeader(
      title: widget.albumName,
      expandedHeight: expandedHeight,
      showTitleInAppBar: showTitleInAppBar,
      backgroundColor: pageBackgroundColor,
      background: background,
      paletteSource: coverThumbUrl,
      blurAndScrimBackground: showSquareCover,
      coverBuilder: showSquareCover
          ? (context, coverSize) => coverThumbUrl != null
                ? CachedNetworkImage(
                    imageUrl: highResCoverUrl(coverThumbUrl) ?? coverThumbUrl,
                    fit: BoxFit.cover,
                    width: coverSize,
                    height: coverSize,
                    memCacheWidth: cacheWidth,
                    cacheManager: CoverCacheManager.instance,
                    placeholder: (_, _) =>
                        Container(color: colorScheme.surfaceContainerHighest),
                    errorWidget: (_, _, _) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.album,
                        size: 48,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.album,
                      size: 48,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
          : null,
      subtitle: (artistName != null && artistName.isNotEmpty)
          ? ClickableArtistName(
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
            )
          : null,
      meta: _buildHeaderMeta(context, releaseDate),
      actions: isSelectionMode
          ? null
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLoveAllButton(),
                const SizedBox(width: 12),
                Flexible(
                  child: HeaderFilledButton(
                    icon: Icons.download,
                    label: context.l10n.downloadAllCount(tracks.length),
                    onPressed: tracks.isEmpty
                        ? null
                        : () => _downloadAll(context),
                  ),
                ),
                const SizedBox(width: 12),
                _buildAddToPlaylistButton(context),
              ],
            ),
      appBarTitle: isSelectionMode
          ? context.l10n.selectionSelected(selectedIds.length)
          : null,
      leading: isSelectionMode
          ? Padding(
              padding: const EdgeInsets.only(left: 8),
              child: HeaderCircleButton(
                icon: Icons.close,
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: exitSelectionMode,
              ),
            )
          : null,
      appBarActions: isSelectionMode
          ? const []
          : [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: HeaderCircleButton(
                  icon: Icons.open_in_new_rounded,
                  tooltip: context.l10n.openInOtherServices,
                  onPressed: () => _showShareSheet(context, tracks, artistName),
                ),
              ),
            ],
    );
  }

  Widget _buildAlbumFooter(
    BuildContext context,
    ColorScheme colorScheme,
    List<Track> tracks,
  ) => buildTrackListFooter(context, colorScheme, tracks);

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
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: wideListInset(context)),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final track = tracks[index];
          final selectionId = _trackSelectionId(track, index);
          final isInHistory = existingHistoryKeys.contains(
            historyLookups[index].lookupKey,
          );
          return KeyedSubtree(
            key: ValueKey(selectionId),
            child: StaggeredListItem(
              index: index,
              child: TrackListTile(
                track: track,
                isInHistory: isInHistory,
                onDownload: ({bool forceQualityPicker = false}) =>
                    _downloadTrack(
                      context,
                      track,
                      forceQualityPicker: forceQualityPicker,
                    ),
                clickableArtist: true,
                isSelectionMode: isSelectionMode,
                isSelected: selectedIds.contains(selectionId),
                onToggleSelection: () => toggleSelection(selectionId),
                onEnterSelectionMode: () => enterSelectionMode(selectionId),
                leading: SizedBox(
                  width: 32,
                  child: Center(
                    child: Text(
                      '${track.trackNumber ?? 0}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }, childCount: tracks.length),
      ),
    );
  }

  String _trackSelectionId(Track track, int index) =>
      '$index|${track.discNumber ?? 0}|${track.trackNumber ?? 0}|'
      '${track.id}|${track.name}';

  List<Track> _selectedTracks(List<Track> tracks) => [
    for (var index = 0; index < tracks.length; index++)
      if (selectedIds.contains(_trackSelectionId(tracks[index], index)))
        tracks[index],
  ];

  Widget _buildSelectionBottomBar(
    BuildContext barContext,
    ColorScheme colorScheme,
    List<Track> tracks,
    double bottomPadding,
  ) {
    final selectedCount = selectedIds.length;
    final allSelected = tracks.isNotEmpty && selectedCount == tracks.length;

    return SelectionBottomBar(
      selectedCount: selectedCount,
      allSelected: allSelected,
      onClose: exitSelectionMode,
      onToggleSelectAll: () {
        if (allSelected) {
          exitSelectionMode();
        } else {
          selectAll([
            for (var index = 0; index < tracks.length; index++)
              _trackSelectionId(tracks[index], index),
          ]);
        }
      },
      bottomPadding: bottomPadding,
      children: [
        SizedBox(
          width: double.infinity,
          child: SelectionActionButton(
            icon: Icons.download_rounded,
            label: '${barContext.l10n.dialogDownload} ($selectedCount)',
            onPressed: selectedCount == 0
                ? null
                : () => _downloadSelected(context, tracks),
            colorScheme: colorScheme,
          ),
        ),
      ],
    );
  }

  Future<void> _downloadSelected(
    BuildContext context,
    List<Track> tracks,
  ) async {
    final selectedTracks = _selectedTracks(tracks);
    if (selectedTracks.isEmpty) return;

    await queueTracksSkippingDownloaded(
      context,
      ref,
      selectedTracks,
      artistNameForPicker: widget.albumName,
      recommendedService: _recommendedDownloadService(),
      forceQualityPicker: true,
      onQueued: exitSelectionMode,
    );
  }

  void _downloadTrack(
    BuildContext context,
    Track track, {
    bool forceQualityPicker = false,
  }) {
    downloadSingleTrack(
      context,
      ref,
      track,
      recommendedService: _recommendedDownloadService(),
      forceQualityPicker: forceQualityPicker,
    );
  }

  Future<void> _downloadAll(BuildContext context) async {
    final tracks = _tracks;
    if (tracks == null || tracks.isEmpty) return;
    await queueTracksSkippingDownloaded(
      context,
      ref,
      tracks,
      artistNameForPicker: widget.albumName,
      recommendedService: _recommendedDownloadService(),
    );
  }

  Widget _buildLoveAllButton() {
    final collectionsState = ref.watch(libraryCollectionsProvider);
    final tracks = _tracks;
    final allLoved =
        tracks != null &&
        tracks.isNotEmpty &&
        tracks.every((t) => collectionsState.isLoved(t));

    return HeaderCircleButton(
      icon: allLoved ? Icons.favorite : Icons.favorite_border,
      iconColor: allLoved ? Theme.of(context).colorScheme.error : null,
      tooltip: allLoved
          ? context.l10n.trackOptionRemoveFromLoved
          : context.l10n.tooltipLoveAll,
      onPressed: tracks == null || tracks.isEmpty
          ? null
          : () => _loveAll(tracks),
    );
  }

  Widget _buildAddToPlaylistButton(BuildContext context) {
    return HeaderCircleButton(
      icon: Icons.add,
      tooltip: context.l10n.tooltipAddToPlaylist,
      onPressed: _tracks == null || _tracks!.isEmpty
          ? null
          : () => showAddTracksToPlaylistSheet(context, ref, _tracks!),
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

  Future<void> _loveAll(List<Track> tracks) =>
      loveAllTracks(context, ref, tracks);
}
