part of 'home_tab.dart';

/// Dropdown widget for quick search provider switching
class _SearchProviderDropdown extends ConsumerWidget {
  final VoidCallback? onProviderChanged;

  const _SearchProviderDropdown({this.onProviderChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawCurrentProvider = ref.watch(
      settingsProvider.select((s) => s.searchProvider),
    );
    final extensions = ref.watch(extensionProvider.select((s) => s.extensions));
    final providerReadiness = ref.watch(
      extensionProvider.select(
        (s) => (isInitialized: s.isInitialized, error: s.error),
      ),
    );
    final colorScheme = Theme.of(context).colorScheme;

    final searchProviders = extensions
        .where((ext) => ext.enabled && ext.hasCustomSearch)
        .toList();
    final hasAnyProvider = searchProviders.isNotEmpty;
    final isProviderLoading =
        !providerReadiness.isInitialized && providerReadiness.error == null;

    if (!hasAnyProvider) {
      return Padding(
        padding: const EdgeInsets.only(left: 12, right: 8),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: isProviderLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                : Icon(
                    Icons.search_off,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
      );
    }

    final resolvedCurrentProvider =
        rawCurrentProvider != null &&
            rawCurrentProvider.isNotEmpty &&
            searchProviders.any((e) => e.id == rawCurrentProvider)
        ? rawCurrentProvider
        : HomeSearchProviderPolicy.defaultExtension(searchProviders)?.id;
    final currentProvider =
        resolvedCurrentProvider != null && resolvedCurrentProvider.isNotEmpty
        ? resolvedCurrentProvider
        : null;

    Extension? currentExt;
    if (currentProvider != null && currentProvider.isNotEmpty) {
      currentExt = searchProviders
          .where((e) => e.id == currentProvider)
          .firstOrNull;
    }

    IconData displayIcon = Icons.search;
    String? iconPath;
    if (currentExt != null) {
      iconPath = currentExt.iconPath;
      if (currentExt.searchBehavior?.icon != null) {
        displayIcon = _getIconFromName(currentExt.searchBehavior!.icon!);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: PopupMenuButton<String>(
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconPath != null && iconPath.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  File(iconPath),
                  width: 20,
                  height: 20,
                  fit: BoxFit.cover,
                  errorBuilder: (_, e, st) => Icon(displayIcon, size: 20),
                ),
              )
            else
              Icon(displayIcon, size: 20),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        tooltip: context.l10n.homeChangeSearchProviderTooltip,
        offset: const Offset(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (String providerId) {
          ref.read(settingsProvider.notifier).setSearchProvider(providerId);
          onProviderChanged?.call();
        },
        itemBuilder: (context) => [
          ...searchProviders.map(
            (ext) => PopupMenuItem<String>(
              value: ext.id,
              child: Row(
                children: [
                  if (ext.iconPath != null && ext.iconPath!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(
                        File(ext.iconPath!),
                        width: 20,
                        height: 20,
                        fit: BoxFit.cover,
                        errorBuilder: (_, e, st) => Icon(
                          _getIconFromName(ext.searchBehavior?.icon),
                          size: 20,
                          color: currentProvider == ext.id
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Icon(
                      _getIconFromName(ext.searchBehavior?.icon),
                      size: 20,
                      color: currentProvider == ext.id
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      ext.displayName,
                      style: TextStyle(
                        fontWeight: currentProvider == ext.id
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (currentProvider == ext.id)
                    Icon(Icons.check, size: 18, color: colorScheme.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconFromName(String? iconName) {
    switch (iconName) {
      case 'video':
      case 'movie':
        return Icons.video_library;
      case 'music':
        return Icons.music_note;
      case 'podcast':
        return Icons.podcasts;
      case 'book':
      case 'audiobook':
        return Icons.menu_book;
      case 'cloud':
        return Icons.cloud;
      case 'download':
        return Icons.download;
      default:
        return Icons.search;
    }
  }
}

class _TrackItemWithStatus extends ConsumerWidget {
  final Track track;
  final int index;
  final bool showDivider;
  final void Function({bool forceQualityPicker}) onDownload;
  final String? searchExtensionId;
  final bool showLocalLibraryIndicator;
  final Map<String, (double, double)> thumbnailSizesByExtensionId;

  /// Resolved by the result page via one batch lookup instead of a per-row
  /// exists query (which in SAF mode also costs a bridge call per row).
  final bool isInHistory;

  const _TrackItemWithStatus({
    super.key,
    required this.track,
    required this.index,
    required this.showDivider,
    required this.onDownload,
    required this.searchExtensionId,
    required this.showLocalLibraryIndicator,
    required this.thumbnailSizesByExtensionId,
    required this.isInHistory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    final queueItem = ref.watch(
      downloadQueueLookupProvider.select(
        (lookup) => lookup.byTrackId[track.id],
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

    double thumbWidth = 56;
    double thumbHeight = 56;

    final extensionId = track.source ?? searchExtensionId;
    final thumbSize = extensionId == null
        ? null
        : thumbnailSizesByExtensionId[extensionId];
    if (thumbSize != null) {
      thumbWidth = thumbSize.$1;
      thumbHeight = thumbSize.$2;
    }

    final isQueued = queueItem != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => _handleTap(
            context,
            ref,
            isQueued: isQueued,
            isInHistory: isInHistory,
            isInLocalLibrary: isInLocalLibrary,
          ),
          onLongPress: () => TrackCollectionQuickActions.showTrackOptionsSheet(
            context,
            ref,
            track,
            hasLocalPlaybackCandidate: isInHistory || isInLocalLibrary,
          ),
          splashColor: colorScheme.primary.withValues(alpha: 0.12),
          highlightColor: colorScheme.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: track.coverUrl != null
                      ? CachedCoverImage(
                          imageUrl: track.coverUrl!,
                          width: thumbWidth,
                          height: thumbHeight,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: thumbWidth,
                          height: thumbHeight,
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.music_note,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: ClickableArtistName(
                              artistName: track.artistName,
                              artistId: track.artistId,
                              coverUrl: track.coverUrl,
                              extensionId: extensionId,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ...buildQualityBadges(
                            audioQuality: track.audioQuality,
                            audioModes: track.audioModes,
                            colorScheme: colorScheme,
                            explicit: track.isExplicit,
                          ),
                          if (isInLocalLibrary) ...[
                            const SizedBox(width: 6),
                            const InLibraryBadge(),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PreviewButton(track: track),
                TrackCollectionQuickActions(
                  track: track,
                  hasLocalPlaybackCandidate: isInHistory || isInLocalLibrary,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            indent: thumbWidth + 24,
            endIndent: 12,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
      ],
    );
  }

  void _handleTap(
    BuildContext context,
    WidgetRef ref, {
    required bool isQueued,
    required bool isInHistory,
    required bool isInLocalLibrary,
  }) async {
    if (isQueued) return;

    final settings = ref.read(settingsProvider);
    final allowExistingDownload =
        settings.allowQualityVariants || !settings.deduplicateDownloads;

    if (!allowExistingDownload && isInLocalLibrary) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.snackbarAlreadyInLibrary(track.name)),
          ),
        );
      }
      return;
    }

    if (!allowExistingDownload) {
      final historyNotifier = ref.read(downloadHistoryProvider.notifier);
      final historyItem = await historyNotifier.findExistingTrackAsync(
        historyLookupForTrack(track),
      );
      if (historyItem != null) {
        final exists = await fileExists(historyItem.filePath);
        if (exists) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.snackbarAlreadyDownloaded(track.name),
                ),
              ),
            );
          }
          return;
        } else {
          historyNotifier.removeFromHistory(historyItem.id);
        }
      }
    }

    onDownload(
      forceQualityPicker:
          settings.allowQualityVariants && (isInHistory || isInLocalLibrary),
    );
  }
}

/// Widget for displaying album/playlist items in search results
class _CollectionItemWidget extends StatelessWidget {
  final Track item;
  final bool showDivider;
  final VoidCallback onTap;

  const _CollectionItemWidget({
    super.key,
    required this.item,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPlaylist = item.isPlaylistItem;
    final isArtist = item.isArtistItem;

    IconData placeholderIcon = Icons.album;
    if (isPlaylist) placeholderIcon = Icons.playlist_play;
    if (isArtist) placeholderIcon = Icons.person;

    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(isArtist ? 28 : 10),
      child: item.coverUrl != null && item.coverUrl!.isNotEmpty
          ? CachedCoverImage(
              imageUrl: item.coverUrl!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            )
          : Container(
              width: 56,
              height: 56,
              color: colorScheme.surfaceContainerHighest,
              child: Icon(placeholderIcon, color: colorScheme.onSurfaceVariant),
            ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          splashColor: colorScheme.primary.withValues(alpha: 0.12),
          highlightColor: colorScheme.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                cover,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.artistName.isNotEmpty
                            ? item.artistName
                            : (isPlaylist
                                  ? context.l10n.recentTypePlaylist
                                  : (isArtist
                                        ? context.l10n.recentTypeArtist
                                        : context.l10n.recentTypeAlbum)),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            indent: 80,
            endIndent: 12,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
      ],
    );
  }
}

class _DownloadedOrRemoteCover extends StatefulWidget {
  final String? downloadedFilePath;
  final String? imageUrl;
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final IconData fallbackIcon;
  final double fallbackIconSize;
  final ColorScheme colorScheme;

  const _DownloadedOrRemoteCover({
    required this.downloadedFilePath,
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.fallbackIcon,
    required this.colorScheme,
    this.fallbackIconSize = 24,
  });

  @override
  State<_DownloadedOrRemoteCover> createState() =>
      _DownloadedOrRemoteCoverState();
}

class _DownloadedOrRemoteCoverState extends State<_DownloadedOrRemoteCover> {
  String? _embeddedCoverPath;
  bool _refreshScheduled = false;

  @override
  void initState() {
    super.initState();
    _embeddedCoverPath = _resolveEmbeddedCoverPath();
  }

  @override
  void didUpdateWidget(covariant _DownloadedOrRemoteCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.downloadedFilePath != widget.downloadedFilePath ||
        oldWidget.imageUrl != widget.imageUrl) {
      final nextPath = _resolveEmbeddedCoverPath();
      if (nextPath != _embeddedCoverPath) {
        setState(() => _embeddedCoverPath = nextPath);
      }
    }
  }

  String? _resolveEmbeddedCoverPath() {
    final filePath = widget.downloadedFilePath;
    if (filePath == null || filePath.isEmpty) return null;
    return DownloadedEmbeddedCoverResolver.resolve(
      filePath,
      onChanged: _onEmbeddedCoverChanged,
    );
  }

  void _onEmbeddedCoverChanged() {
    if (!mounted || _refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!mounted) return;
      final nextPath = _resolveEmbeddedCoverPath();
      if (nextPath != _embeddedCoverPath) {
        setState(() => _embeddedCoverPath = nextPath);
      }
    });
  }

  Widget _fallback() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: widget.colorScheme.surfaceContainerHighest,
      child: Icon(
        widget.fallbackIcon,
        color: widget.colorScheme.onSurfaceVariant,
        size: widget.fallbackIconSize,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cacheWidth = (widget.width * 2).round();
    final cacheHeight = (widget.height * 2).round();

    Widget child;
    if (_embeddedCoverPath != null) {
      child = Image.file(
        File(_embeddedCoverPath!),
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => _fallback(),
      );
    } else if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      child = CachedCoverImage(
        imageUrl: widget.imageUrl!,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        memCacheWidth: cacheWidth,
        memCacheHeight: cacheHeight,
        errorWidget: (_, _, _) => _fallback(),
      );
    } else {
      child = _fallback();
    }

    return ClipRRect(borderRadius: widget.borderRadius, child: child);
  }
}

/// Legacy `duration_ms` parsing used by extension album/playlist/artist track
/// parsing, kept separate from [extractDurationMs] which also falls back to
/// a `duration` (seconds) field these call sites intentionally ignore.
int _legacyTrackDurationMs(Map<String, dynamic> data) {
  final durationValue = data['duration_ms'];
  if (durationValue is int) return durationValue;
  if (durationValue is double) return durationValue.toInt();
  return 0;
}

/// Prefers the track's own cover, falling back to the parent
/// album/playlist cover, without URL validation.
String? _resolveTrackCoverUrl(String? trackCover, String? fallbackCover) {
  if (trackCover != null && trackCover.isNotEmpty) return trackCover;
  return fallbackCover;
}

/// Shared loading/error+retry scaffold for extension album/playlist/artist
/// detail screens.
class _LoadingOrErrorScaffold extends StatelessWidget {
  final String title;
  final bool isLoading;
  final String? error;
  final Widget loadingBody;
  final VoidCallback onRetry;

  const _LoadingOrErrorScaffold({
    required this.title,
    required this.isLoading,
    required this.error,
    required this.loadingBody,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: loadingBody,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              context.friendlyError(error),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: Text(context.l10n.dialogRetry),
            ),
          ],
        ),
      ),
    );
  }
}

/// Defers swapping the loading scaffold for the loaded screen until the push
/// transition (and its Hero flight) has finished. Swapping mid-flight puts a
/// second hero with the same tag on screen — the flight doesn't adopt it, so
/// the user sees a static cover next to the flying one.
mixin _RouteSettled<T extends StatefulWidget> on State<T> {
  bool _routeSettled = false;
  Animation<double>? _routeAnimation;

  bool get routeSettled => _routeSettled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSettled) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _routeSettled = true;
      return;
    }
    if (!identical(animation, _routeAnimation)) {
      _routeAnimation?.removeStatusListener(_onRouteStatus);
      _routeAnimation = animation;
      animation.addStatusListener(_onRouteStatus);
    }
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _routeAnimation?.removeStatusListener(_onRouteStatus);
      _routeAnimation = null;
      setState(() => _routeSettled = true);
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }
}

/// Loading state for [ExtensionArtistScreen]: the real full-bleed header with
/// the cover and artist name above the discography skeleton.
class _ArtistLoadingScaffold extends StatelessWidget {
  final String artistName;
  final String? coverUrl;

  const _ArtistLoadingScaffold({
    required this.artistName,
    required this.coverUrl,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = coverUrl;
    final hasImage =
        url != null &&
        url.isNotEmpty &&
        Uri.tryParse(url)?.hasAuthority == true;

    final Widget image = hasImage
        ? CachedCoverImage(
            imageUrl: url,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            memCacheWidth: 800,
          )
        : Container(
            color: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.person,
              size: 80,
              color: colorScheme.onSurfaceVariant,
            ),
          );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 420,
            pinned: true,
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.none,
              background: Stack(
                fit: StackFit.expand,
                children: [
                  image,
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.3),
                          Colors.black.withValues(alpha: 0.7),
                          isDark
                              ? colorScheme.surface
                              : Colors.black.withValues(alpha: 0.85),
                        ],
                        stops: const [0.0, 0.5, 0.75, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Text(
                      artistName,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                offset: const Offset(0, 1),
                                blurRadius: 4,
                                color: Colors.black.withValues(alpha: 0.5),
                              ),
                            ],
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
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
          ),
          const SliverToBoxAdapter(
            child: ArtistScreenSkeleton(showCoverHeader: false),
          ),
        ],
      ),
    );
  }
}

class ExtensionAlbumScreen extends ConsumerStatefulWidget {
  final String extensionId;
  final String albumId;
  final String albumName;
  final String? coverUrl;
  final String? initialAlbumType;
  final int? initialTotalTracks;

  const ExtensionAlbumScreen({
    super.key,
    required this.extensionId,
    required this.albumId,
    required this.albumName,
    this.coverUrl,
    this.initialAlbumType,
    this.initialTotalTracks,
  });

  @override
  ConsumerState<ExtensionAlbumScreen> createState() =>
      _ExtensionAlbumScreenState();
}

class _ExtensionAlbumScreenState extends ConsumerState<ExtensionAlbumScreen> {
  List<Track>? _tracks;
  bool _isLoading = true;
  String? _error;
  String? _artistId;
  String? _artistName;
  String? _albumType;
  int? _albumTotalTracks;
  String? _headerVideoUrl;
  String? _headerImageUrl;
  List<String> _audioTraits = const [];

  @override
  void initState() {
    super.initState();
    _albumType = normalizeOptionalString(widget.initialAlbumType);
    _albumTotalTracks = widget.initialTotalTracks;
    _fetchTracks();
  }

  Future<void> _fetchTracks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await PlatformBridge.getProviderMetadata(
        widget.extensionId,
        'album',
        widget.albumId,
      );
      if (!mounted) return;

      final albumInfo = result['album_info'] as Map<String, dynamic>? ?? result;
      final trackList =
          result['track_list'] as List<dynamic>? ??
          result['tracks'] as List<dynamic>?;
      if (trackList == null) {
        setState(() {
          _error = context.l10n.errorNoTracksFound;
          _isLoading = false;
        });
        return;
      }

      final artistId = (albumInfo['artist_id'] ?? albumInfo['artistId'])
          ?.toString();
      final artistName = (albumInfo['artists'] ?? albumInfo['artist'])
          ?.toString();
      final albumType =
          normalizeOptionalString(albumInfo['album_type']?.toString()) ??
          _albumType;
      final totalTracks =
          albumInfo['total_tracks'] as int? ?? _albumTotalTracks;
      final headerVideo = albumInfo['header_video']?.toString();
      final headerImage = albumInfo['header_image']?.toString();
      final audioTraits = (albumInfo['audio_traits'] as List?)
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

      setState(() {
        _tracks = tracks;
        _artistId = artistId;
        _artistName = artistName;
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
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = context.l10n.snackbarError(context.friendlyError(e));
        _isLoading = false;
      });
    }
  }

  Track _parseTrack(
    Map<String, dynamic> data, {
    String? albumTypeFallback,
    int? totalTracksFallback,
  }) {
    final base = Track.fromBackendMap(data, source: widget.extensionId);
    return Track(
      id: (data['id'] ?? '').toString(),
      name: base.name,
      artistName: base.artistName,
      albumName: (data['album_name'] ?? widget.albumName).toString(),
      albumArtist: normalizeOptionalString(data['album_artist']?.toString()),
      artistId: base.artistId ?? _artistId,
      albumId: base.albumId ?? widget.albumId,
      coverUrl: _resolveTrackCoverUrl(
        data['cover_url']?.toString(),
        widget.coverUrl,
      ),
      isrc: base.isrc,
      duration: (_legacyTrackDurationMs(data) / 1000).round(),
      trackNumber: base.trackNumber,
      discNumber: base.discNumber,
      totalDiscs: base.totalDiscs,
      releaseDate: base.releaseDate,
      albumType: base.albumType ?? albumTypeFallback ?? _albumType,
      totalTracks: base.totalTracks ?? totalTracksFallback ?? _albumTotalTracks,
      composer: base.composer,
      source: base.source,
      audioQuality: base.audioQuality,
      audioModes: base.audioModes,
      previewUrl: base.previewUrl,
      explicit: base.explicit,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _error != null) {
      return _LoadingOrErrorScaffold(
        title: widget.albumName,
        isLoading: _isLoading,
        error: _error,
        loadingBody: const AlbumTrackListSkeleton(
          itemCount: 10,
          showCoverHeader: true,
        ),
        onRetry: _fetchTracks,
      );
    }

    return AlbumScreen(
      albumId: widget.albumId,
      albumName: widget.albumName,
      coverUrl: widget.coverUrl,
      headerVideoUrl: _headerVideoUrl,
      headerImageUrl: _headerImageUrl,
      audioTraits: _audioTraits,
      tracks: _tracks,
      extensionId: widget.extensionId,
      artistId: _artistId,
      artistName: _artistName,
    );
  }
}

/// Screen for viewing extension playlist with track fetching
class ExtensionPlaylistScreen extends ConsumerStatefulWidget {
  final String extensionId;
  final String playlistId;
  final String playlistName;
  final String? coverUrl;

  const ExtensionPlaylistScreen({
    super.key,
    required this.extensionId,
    required this.playlistId,
    required this.playlistName,
    this.coverUrl,
  });

  @override
  ConsumerState<ExtensionPlaylistScreen> createState() =>
      _ExtensionPlaylistScreenState();
}

class _ExtensionPlaylistScreenState
    extends ConsumerState<ExtensionPlaylistScreen> {
  List<Track>? _tracks;
  bool _isLoading = true;
  String? _error;
  String? _headerVideoUrl;

  @override
  void initState() {
    super.initState();
    _fetchTracks();
  }

  Future<void> _fetchTracks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await PlatformBridge.getProviderMetadata(
        widget.extensionId,
        'playlist',
        widget.playlistId,
      );
      if (!mounted) return;

      final trackList =
          result['track_list'] as List<dynamic>? ??
          result['tracks'] as List<dynamic>?;
      if (trackList == null) {
        setState(() {
          _error = context.l10n.errorNoTracksFound;
          _isLoading = false;
        });
        return;
      }

      final tracks = trackList
          .map((t) => _parseTrack(t as Map<String, dynamic>))
          .toList();

      final playlistInfo = result['playlist_info'] as Map<String, dynamic>?;
      final headerVideo = playlistInfo?['header_video']?.toString();

      setState(() {
        _tracks = tracks;
        _headerVideoUrl = (headerVideo != null && headerVideo.isNotEmpty)
            ? headerVideo
            : _headerVideoUrl;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = context.l10n.snackbarError(context.friendlyError(e));
        _isLoading = false;
      });
    }
  }

  Track _parseTrack(Map<String, dynamic> data) {
    final base = Track.fromBackendMap(data, source: widget.extensionId);
    return Track(
      id: (data['id'] ?? '').toString(),
      name: base.name,
      artistName: base.artistName,
      albumName: (data['album_name'] ?? '').toString(),
      artistId: base.artistId,
      albumId: base.albumId,
      coverUrl: _resolveTrackCoverUrl(
        data['cover_url']?.toString(),
        widget.coverUrl,
      ),
      isrc: base.isrc,
      duration: (_legacyTrackDurationMs(data) / 1000).round(),
      trackNumber: base.trackNumber,
      discNumber: base.discNumber,
      totalDiscs: base.totalDiscs,
      releaseDate: base.releaseDate,
      totalTracks: base.totalTracks,
      composer: base.composer,
      source: base.source,
      audioQuality: base.audioQuality,
      audioModes: base.audioModes,
      previewUrl: base.previewUrl,
      explicit: base.explicit,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _error != null) {
      return SkeletonCrossfade(
        child: _LoadingOrErrorScaffold(
          title: widget.playlistName,
          isLoading: _isLoading,
          error: _error,
          loadingBody: const TrackListSkeleton(
            itemCount: 8,
            showCoverHeader: true,
          ),
          onRetry: _fetchTracks,
        ),
      );
    }

    return SkeletonCrossfade(
      child: PlaylistScreen(
        playlistName: widget.playlistName,
        coverUrl: widget.coverUrl,
        headerVideoUrl: _headerVideoUrl,
        tracks: _tracks!,
        recommendedService: widget.extensionId,
      ),
    );
  }
}

class ExtensionArtistScreen extends ConsumerStatefulWidget {
  final String extensionId;
  final String artistId;
  final String artistName;
  final String? coverUrl;

  const ExtensionArtistScreen({
    super.key,
    required this.extensionId,
    required this.artistId,
    required this.artistName,
    this.coverUrl,
  });

  @override
  ConsumerState<ExtensionArtistScreen> createState() =>
      _ExtensionArtistScreenState();
}

class _ExtensionArtistScreenState extends ConsumerState<ExtensionArtistScreen>
    with _RouteSettled<ExtensionArtistScreen> {
  List<ArtistAlbum>? _albums;
  List<Track>? _topTracks;
  String? _headerImageUrl;
  String? _headerVideoUrl;
  int? _monthlyListeners;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchArtist();
  }

  Future<void> _fetchArtist() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await PlatformBridge.getProviderMetadata(
        widget.extensionId,
        'artist',
        widget.artistId,
      );
      if (!mounted) return;

      final artistInfo =
          result['artist_info'] as Map<String, dynamic>? ?? result;
      final albumList = result['albums'] as List<dynamic>?;
      final albums =
          albumList
              ?.map((a) => _parseAlbum(a as Map<String, dynamic>))
              .toList() ??
          [];

      final topTracksList = result['top_tracks'] as List<dynamic>?;
      List<Track>? topTracks;
      if (topTracksList != null && topTracksList.isNotEmpty) {
        topTracks = topTracksList
            .map((t) => _parseTrack(t as Map<String, dynamic>))
            .toList();
      }

      final headerImage =
          artistInfo['images'] as String? ??
          artistInfo['header_image'] as String? ??
          artistInfo['cover_url'] as String? ??
          result['header_image'] as String?;
      final headerVideo =
          artistInfo['header_video'] as String? ??
          result['header_video'] as String?;
      final listeners =
          artistInfo['listeners'] as int? ?? result['listeners'] as int?;

      setState(() {
        _albums = albums;
        _topTracks = topTracks;
        _headerImageUrl = headerImage;
        _headerVideoUrl = headerVideo;
        _monthlyListeners = listeners;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = context.l10n.snackbarError(context.friendlyError(e));
        _isLoading = false;
      });
    }
  }

  ArtistAlbum _parseAlbum(Map<String, dynamic> data) {
    return ArtistAlbum(
      id: (data['id'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      artists: (data['artists'] ?? '').toString(),
      releaseDate: (data['release_date'] ?? '').toString(),
      totalTracks: data['total_tracks'] as int? ?? 0,
      coverUrl: normalizeCoverReference(data['cover_url']?.toString()),
      albumType: (data['album_type'] ?? 'album').toString(),
      providerId: (data['provider_id'] ?? widget.extensionId).toString(),
    );
  }

  Track _parseTrack(Map<String, dynamic> data) {
    final base = Track.fromBackendMap(data);
    return Track(
      id: (data['id'] ?? data['spotify_id'] ?? '').toString(),
      name: base.name,
      artistName: base.artistName,
      albumName: base.albumName,
      albumArtist: base.albumArtist,
      artistId: base.artistId ?? widget.artistId,
      albumId: base.albumId,
      coverUrl: base.coverUrl,
      isrc: base.isrc,
      duration: (_legacyTrackDurationMs(data) / 1000).round(),
      trackNumber: base.trackNumber,
      discNumber: base.discNumber,
      totalDiscs: base.totalDiscs,
      releaseDate: base.releaseDate,
      totalTracks: base.totalTracks,
      composer: base.composer,
      source: (data['provider_id'] ?? widget.extensionId).toString(),
      previewUrl: base.previewUrl,
      explicit: base.explicit,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SkeletonCrossfade(
        child: _LoadingOrErrorScaffold(
          title: widget.artistName,
          isLoading: false,
          error: _error,
          loadingBody: const SizedBox.shrink(),
          onRetry: _fetchArtist,
        ),
      );
    }

    if (_isLoading || !routeSettled) {
      return SkeletonCrossfade(
        child: _ArtistLoadingScaffold(
          artistName: widget.artistName,
          coverUrl: widget.coverUrl,
        ),
      );
    }

    return SkeletonCrossfade(
      child: ArtistScreen(
        artistId: widget.artistId,
        artistName: widget.artistName,
        coverUrl: widget.coverUrl,
        headerImageUrl: _headerImageUrl,
        headerVideoUrl: _headerVideoUrl,
        monthlyListeners: _monthlyListeners,
        albums: _albums,
        topTracks: _topTracks,
        extensionId: widget.extensionId, // Skip Spotify/Deezer fetch
      ),
    );
  }
}

/// Swipeable Quick Picks widget with page indicator
class _QuickPicksPageView extends StatefulWidget {
  final ExploreSection section;
  final ColorScheme colorScheme;
  final int itemsPerPage;
  final int totalPages;
  final void Function(ExploreItem) onItemTap;
  final void Function(ExploreItem) onItemMenu;

  const _QuickPicksPageView({
    required this.section,
    required this.colorScheme,
    required this.itemsPerPage,
    required this.totalPages,
    required this.onItemTap,
    required this.onItemMenu,
  });

  @override
  State<_QuickPicksPageView> createState() => _QuickPicksPageViewState();
}

class _QuickPicksPageViewState extends State<_QuickPicksPageView> {
  int _currentPage = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            widget.section.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: widget.itemsPerPage * 64.0,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.totalPages,
            onPageChanged: (page) {
              setState(() => _currentPage = page);
            },
            itemBuilder: (context, pageIndex) {
              final startIndex = pageIndex * widget.itemsPerPage;
              final endIndex = (startIndex + widget.itemsPerPage).clamp(
                0,
                widget.section.items.length,
              );
              final pageItemCount = endIndex - startIndex;

              return Column(
                children: List.generate(pageItemCount, (index) {
                  final item = widget.section.items[startIndex + index];
                  return KeyedSubtree(
                    key: ValueKey(
                      'quick-pick-${item.type}-${item.id}-${item.uri}',
                    ),
                    child: _buildQuickPickItem(item),
                  );
                }),
              );
            },
          ),
        ),
        if (widget.totalPages > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.totalPages, (index) {
                final isActive = index == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: isActive ? 8 : 6,
                  height: isActive ? 8 : 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? widget.colorScheme.primary
                        : widget.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.3,
                          ),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildQuickPickItem(ExploreItem item) {
    return InkWell(
      onTap: () => widget.onItemTap(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: item.coverUrl != null && item.coverUrl!.isNotEmpty
                  ? CachedCoverImage(
                      imageUrl: item.coverUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => Container(
                        width: 48,
                        height: 48,
                        color: widget.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.music_note,
                          color: widget.colorScheme.onSurfaceVariant,
                          size: 24,
                        ),
                      ),
                    )
                  : Container(
                      width: 48,
                      height: 48,
                      color: widget.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.music_note,
                        color: widget.colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: widget.colorScheme.onSurface,
                    ),
                  ),
                  if (item.artists.isNotEmpty)
                    ClickableArtistName(
                      artistName: item.artists,
                      coverUrl: item.coverUrl,
                      extensionId: item.providerId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: widget.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              icon: Icon(
                Icons.more_vert,
                color: widget.colorScheme.onSurfaceVariant,
                size: 20,
              ),
              onPressed: () => widget.onItemMenu(item),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ],
        ),
      ),
    );
  }
}
