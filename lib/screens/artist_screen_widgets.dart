// ignore_for_file: invalid_use_of_protected_member
part of 'artist_screen.dart';

extension _ArtistScreenSections on _ArtistScreenState {
  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme, {
    required List<ArtistAlbum> albums,
    required bool hasDiscography,
  }) {
    String? imageUrl = _headerImageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      imageUrl = widget.headerImageUrl;
    }
    if (imageUrl == null || imageUrl.isEmpty) {
      imageUrl = widget.coverUrl;
    }

    final hasValidImage =
        imageUrl != null &&
        imageUrl.isNotEmpty &&
        Uri.tryParse(imageUrl)?.hasAuthority == true;

    String? headerVideoUrl = _headerVideoUrl;
    if (headerVideoUrl == null || headerVideoUrl.isEmpty) {
      headerVideoUrl = widget.headerVideoUrl;
    }
    final hasMotionBanner =
        headerVideoUrl != null &&
        headerVideoUrl.isNotEmpty &&
        Uri.tryParse(headerVideoUrl)?.hasAuthority == true;

    String? listenersText;
    final listeners = _monthlyListeners ?? widget.monthlyListeners;
    if (listeners != null && listeners > 0) {
      final formatter = NumberFormat.compact();
      listenersText = context.l10n.artistMonthlyListeners(
        formatter.format(listeners),
      );
    }

    final favoriteProviderId = _directMetadataProviderId();
    final favoriteArtistId = _metadataResourceId(favoriteProviderId ?? '');
    final isFavoriteArtist = ref.watch(
      libraryCollectionsProvider.select(
        (state) => state.isFavoriteArtist(
          artistId: favoriteArtistId,
          providerId: favoriteProviderId,
        ),
      ),
    );

    return CoverPaletteBuilder(
      imageSource: hasValidImage ? imageUrl : null,
      builder: (context, headerScheme) => _buildArtistAppBar(
        context,
        colorScheme,
        headerScheme,
        albums: albums,
        hasDiscography: hasDiscography,
        imageUrl: imageUrl,
        hasValidImage: hasValidImage,
        headerVideoUrl: headerVideoUrl,
        hasMotionBanner: hasMotionBanner,
        listenersText: listenersText,
        isFavoriteArtist: isFavoriteArtist,
      ),
    );
  }

  Widget _buildArtistAppBar(
    BuildContext context,
    ColorScheme colorScheme,
    ColorScheme headerScheme, {
    required List<ArtistAlbum> albums,
    required bool hasDiscography,
    required String? imageUrl,
    required bool hasValidImage,
    required String? headerVideoUrl,
    required bool hasMotionBanner,
    required String? listenersText,
    required bool isFavoriteArtist,
  }) {
    return SliverAppBar(
      expandedHeight: hasDiscography ? 420 : 380,
      pinned: true,
      stretch: true,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      title: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _showTitleInAppBar ? 1.0 : 0.0,
        child: Text(
          widget.artistName,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.none,
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (hasMotionBanner)
              MotionHeaderBanner(
                videoUrl: headerVideoUrl!,
                fallback: hasValidImage
                    ? CachedCoverImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        memCacheWidth: 800,
                        placeholder: (context, url) => Container(
                          color: colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.person,
                            size: 80,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.person,
                          size: 80,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              )
            else if (hasValidImage)
              CachedCoverImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                memCacheWidth: 800,
                placeholder: (context, url) =>
                    Container(color: colorScheme.surfaceContainerHighest),
                errorWidget: (context, url, error) => Container(
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.person,
                    size: 80,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Container(
                color: colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.person,
                  size: 80,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    headerScheme.surface.withValues(alpha: 0),
                    headerScheme.surface.withValues(alpha: 0.35),
                    headerScheme.surface.withValues(alpha: 0.75),
                    headerScheme.surface,
                  ],
                  stops: const [0.0, 0.5, 0.75, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.artistName,
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: headerScheme.onSurface,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (listenersText != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            listenersText,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: headerScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!isSelectionMode) ...[
                    const SizedBox(width: 12),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: headerScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: () => _toggleFavoriteArtist(context),
                        icon: Icon(
                          isFavoriteArtist
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 26,
                        ),
                        color: isFavoriteArtist
                            ? headerScheme.error
                            : headerScheme.onPrimaryContainer,
                        tooltip: isFavoriteArtist
                            ? context.l10n.artistOptionRemoveFromFavorites
                            : context.l10n.artistOptionAddToFavorites,
                      ),
                    ),
                  ],
                  if (hasDiscography && !isSelectionMode) ...[
                    const SizedBox(width: 12),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: headerScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: () => _showDiscographyOptions(
                          context,
                          colorScheme,
                          albums,
                        ),
                        icon: const Icon(Icons.download_rounded, size: 26),
                        color: headerScheme.onPrimaryContainer,
                        tooltip: context.l10n.discographyDownload,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        stretchModes: const [StretchMode.zoomBackground],
      ),
      leading: HeaderCircleButton(
        icon: Icons.arrow_back,
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: HeaderCircleButton(
            icon: Icons.open_in_new_rounded,
            tooltip: context.l10n.openInOtherServices,
            onPressed: () => _showShareSheet(context),
          ),
        ),
      ],
    );
  }

  void _showShareSheet(BuildContext context) {
    CrossExtensionShareSheet.show(
      context,
      name: widget.artistName,
      artists: '',
      type: 'artist',
      sourceExtensionId: _directMetadataProviderId() ?? '',
    );
  }

  Widget _buildPopularSection(ColorScheme colorScheme) {
    if (_topTracks == null || _topTracks!.isEmpty) {
      return const SizedBox.shrink();
    }

    final tracks = _topTracks!;
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
    const tracksPerPage = 5;
    final pageCount = (tracks.length / tracksPerPage).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text(
            context.l10n.artistPopular,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: tracksPerPage * 64.0,
          child: PageView.builder(
            controller: _popularPageController,
            itemCount: pageCount,
            onPageChanged: (page) {
              setState(() {
                _popularCurrentPage = page;
              });
            },
            itemBuilder: (context, pageIndex) {
              final startIndex = pageIndex * tracksPerPage;
              final endIndex = (startIndex + tracksPerPage).clamp(
                0,
                tracks.length,
              );
              final pageTracks = tracks.sublist(startIndex, endIndex);

              return Column(
                children: pageTracks.asMap().entries.map((entry) {
                  final globalIndex = startIndex + entry.key;
                  return _buildPopularTrackItem(
                    globalIndex + 1,
                    entry.value,
                    colorScheme,
                    existingHistoryKeys.contains(
                      historyLookups[globalIndex].lookupKey,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
        if (pageCount > 1)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(pageCount, (index) {
                  final isActive = _popularCurrentPage == index;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 8 : 6,
                    height: isActive ? 8 : 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                  );
                }),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPopularTrackItem(
    int rank,
    Track track,
    ColorScheme colorScheme,
    bool isInHistory,
  ) {
    return Consumer(
      builder: (context, ref, child) {
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

        return InkWell(
          onTap: () => _handlePopularTrackTap(
            track,
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '$rank',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 12),
                track.coverUrl != null
                    ? CachedCoverImage(
                        imageUrl: track.coverUrl!,
                        width: 48,
                        height: 48,
                        borderRadius: BorderRadius.circular(4),
                        placeholder: (context, url) => ShimmerLoading(
                          child: Container(
                            width: 48,
                            height: 48,
                            color: colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 48,
                          height: 48,
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.music_note,
                            color: colorScheme.onSurfaceVariant,
                            size: 24,
                          ),
                        ),
                      )
                    : Container(
                        width: 48,
                        height: 48,
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.music_note,
                          color: colorScheme.onSurfaceVariant,
                          size: 24,
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
                      if (track.albumName.isNotEmpty ||
                          isInLocalLibrary ||
                          isInHistory)
                        Row(
                          children: [
                            if (track.albumName.isNotEmpty)
                              Expanded(
                                child: ClickableAlbumName(
                                  albumName: track.albumName,
                                  albumId: track.albumId,
                                  artistName: track.artistName,
                                  coverUrl: track.coverUrl,
                                  extensionId: widget.extensionId,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (isInLocalLibrary || isInHistory) ...[
                              if (track.albumName.isNotEmpty)
                                const SizedBox(width: 6),
                              const InLibraryBadge(),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
                TrackCollectionQuickActions(
                  track: track,
                  hasLocalPlaybackCandidate: isInHistory || isInLocalLibrary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handlePopularTrackTap(
    Track track, {
    required bool isQueued,
    required bool isInHistory,
    required bool isInLocalLibrary,
  }) async {
    if (isQueued) return;

    final settings = ref.read(settingsProvider);
    if (settings.allowQualityVariants && (isInHistory || isInLocalLibrary)) {
      _downloadTrack(track);
      return;
    }

    final playedLocal = await playLocalIfAvailable(context, ref, track);
    if (playedLocal) {
      return;
    }

    _downloadTrack(track);
  }

  void _downloadTrack(Track track) {
    final settings = ref.read(settingsProvider);
    ref.read(settingsProvider.notifier).setHasSearchedBefore();

    void enqueue(String service, {String? quality}) {
      ref
          .read(downloadQueueProvider.notifier)
          .addToQueue(track, service, qualityOverride: quality);
      showAddedToQueueSnackBar(context, track.name);
    }

    if (settings.askQualityBeforeDownload || settings.allowQualityVariants) {
      DownloadServicePicker.show(
        context,
        recommendedService: _recommendedDownloadService(),
        onSelect: (quality, service) {
          if (!mounted) return;
          enqueue(service, quality: quality);
        },
      );
      return;
    }

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
    enqueue(service);
  }

  Widget _buildAlbumSection(
    String title,
    List<ArtistAlbum> albums,
    ColorScheme colorScheme, {
    bool showTypeBadge = false,
  }) {
    final sectionHeight = _artistAlbumSectionHeight();
    final tileSize = _artistAlbumTileSize();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text(
            '$title (${albums.length})',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: sectionHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return KeyedSubtree(
                key: ValueKey(album.id),
                child: _buildAlbumCard(
                  album,
                  colorScheme,
                  tileSize: tileSize,
                  sectionHeight: sectionHeight,
                  showTypeBadge: showTypeBadge,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumCard(
    ArtistAlbum album,
    ColorScheme colorScheme, {
    required double tileSize,
    required double sectionHeight,
    bool showTypeBadge = false,
  }) {
    final isSelected = selectedIds.contains(album.id);

    return Semantics(
      button: true,
      selected: isSelectionMode && isSelected,
      label: isSelectionMode
          ? context.l10n.a11ySelectAlbum(album.name)
          : context.l10n.a11yOpenAlbum(album.name),
      child: GestureDetector(
        onTap: () {
          if (isSelectionMode) {
            toggleSelection(album.id);
          } else {
            _navigateToAlbum(album);
          }
        },
        onLongPress: () {
          if (!isSelectionMode) {
            enterSelectionMode(album.id);
          }
        },
        child: Container(
          width: tileSize,
          height: sectionHeight,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: tileSize,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: album.coverUrl != null
                          ? CachedCoverImage(
                              imageUrl: album.coverUrl!,
                              width: tileSize,
                              height: tileSize,
                              fit: BoxFit.cover,
                              memCacheWidth: (tileSize * 2).round(),
                              memCacheHeight: (tileSize * 2).round(),
                              placeholder: (context, url) => ShimmerLoading(
                                child: Container(
                                  color: colorScheme.surfaceContainerHighest,
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.album,
                                  color: colorScheme.onSurfaceVariant,
                                  size: 40,
                                ),
                              ),
                            )
                          : Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.album,
                                color: colorScheme.onSurfaceVariant,
                                size: 40,
                              ),
                            ),
                    ),
                    if (isSelectionMode)
                      Positioned.fill(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: isSelected
                                ? colorScheme.primary.withValues(alpha: 0.3)
                                : Colors.black.withValues(alpha: 0.1),
                            border: isSelected
                                ? Border.all(
                                    color: colorScheme.primary,
                                    width: 3,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    if (isSelectionMode)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: AnimatedSelectionCheckbox(
                          visible: true,
                          selected: isSelected,
                          colorScheme: colorScheme,
                          size: 28,
                          unselectedColor: colorScheme.surface.withValues(
                            alpha: 0.9,
                          ),
                        ),
                      ),
                    if (showTypeBadge)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            album.albumType == 'ep'
                                ? context.l10n.releaseTypeEp
                                : context.l10n.releaseTypeSingle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        album.name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      album.totalTracks > 0
                          ? '${album.releaseDate.length >= 4 ? album.releaseDate.substring(0, 4) : album.releaseDate} ${context.l10n.tracksCount(album.totalTracks)}'
                          : album.releaseDate.length >= 4
                          ? album.releaseDate.substring(0, 4)
                          : album.releaseDate,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToAlbum(ArtistAlbum album) {
    ref.read(settingsProvider.notifier).setHasSearchedBefore();

    if (album.providerId != null && album.providerId!.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (context) => ExtensionAlbumScreen(
            extensionId: album.providerId!,
            albumId: album.id,
            albumName: album.name,
            coverUrl: album.coverUrl,
            initialAlbumType: album.albumType,
            initialTotalTracks: album.totalTracks,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (context) => AlbumScreen(
            albumId: album.id,
            albumName: album.name,
            coverUrl: album.coverUrl,
          ),
        ),
      );
    }
  }
}

class _DiscographyOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DiscographyOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: colorScheme.onPrimaryContainer, size: 24),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
      ),
      trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}

class _FetchingProgressDialog extends StatefulWidget {
  final int totalAlbums;
  final VoidCallback onCancel;

  const _FetchingProgressDialog({
    super.key,
    required this.totalAlbums,
    required this.onCancel,
  });

  @override
  State<_FetchingProgressDialog> createState() =>
      _FetchingProgressDialogState();
}

class _FetchingProgressDialogState extends State<_FetchingProgressDialog> {
  int _current = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _total = widget.totalAlbums;
  }

  void updateProgress(int current, int total) {
    if (mounted) {
      setState(() {
        _current = current;
        _total = total;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = _total > 0 ? _current / _total : 0.0;

    return AlertDialog(
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress > 0 ? progress : null,
                  strokeWidth: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
                Icon(Icons.library_music, color: colorScheme.primary, size: 24),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.l10n.discographyFetchingTracks,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.discographyFetchingAlbum(_current, _total),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              backgroundColor: colorScheme.surfaceContainerHighest,
              minHeight: 6,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: Text(context.l10n.dialogCancel),
        ),
      ],
    );
  }
}
