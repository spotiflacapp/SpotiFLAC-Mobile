part of 'home_tab.dart';

extension _HomeTabExploreUI on _HomeTabState {
  List<Widget> _buildExploreSections(
    List<ExploreSection> sections,
    String? greeting,
    ColorScheme colorScheme,
  ) {
    final hasGreeting = greeting != null && greeting.isNotEmpty;
    final sectionOffset = hasGreeting ? 1 : 0;
    final totalCount = sections.length + sectionOffset + 1;

    return [
      SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (hasGreeting && index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                greeting,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }

          final sectionIndex = index - sectionOffset;
          if (sectionIndex < sections.length) {
            final section = sections[sectionIndex];
            return KeyedSubtree(
              key: ValueKey('explore-section-${section.uri}-${section.title}'),
              child: _buildExploreSection(section, colorScheme),
            );
          }

          return const SizedBox(height: 24);
        }, childCount: totalCount),
      ),
    ];
  }

  Widget _buildExploreSection(ExploreSection section, ColorScheme colorScheme) {
    final sectionHeight = _exploreSectionHeight(context);
    if (section.isYTMusicQuickPicks) {
      return _buildYTMusicQuickPicksSection(section, colorScheme);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            section.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: sectionHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: section.items.length,
            itemBuilder: (context, index) {
              final item = section.items[index];
              return StaggeredListItem(
                key: ValueKey(
                  'explore-item-${item.type}-${item.id}-${item.uri}',
                ),
                index: index,
                staggerDelay: const Duration(milliseconds: 50),
                child: _buildExploreItem(item, colorScheme),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Skeleton mirroring [_buildExploreSection]'s layout — album cards or
  /// artist circles — shown while the home feed loads. Wrap in
  /// [ShimmerLoading] for the sweep effect.
  Widget _buildExploreSectionSkeleton({required bool isArtist}) {
    final cardSize = _exploreCardSize(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: SkeletonBox(width: 140, height: 20, borderRadius: 4),
        ),
        SizedBox(
          height: _exploreSectionHeight(context),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: 6,
            itemBuilder: (context, index) => SizedBox(
              width: cardSize,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  crossAxisAlignment: isArtist
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(
                      width: cardSize,
                      height: cardSize,
                      borderRadius: isArtist ? cardSize / 2 : 10,
                    ),
                    const SizedBox(height: 8),
                    SkeletonBox(
                      width: cardSize * (isArtist ? 0.6 : 0.85),
                      height: 14,
                      borderRadius: 4,
                    ),
                    if (!isArtist) ...[
                      const SizedBox(height: 6),
                      SkeletonBox(
                        width: cardSize * 0.5,
                        height: 12,
                        borderRadius: 4,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildYTMusicQuickPicksSection(
    ExploreSection section,
    ColorScheme colorScheme,
  ) {
    const itemsPerPage = 5;
    final totalPages = (section.items.length / itemsPerPage).ceil();

    return _QuickPicksPageView(
      section: section,
      colorScheme: colorScheme,
      itemsPerPage: itemsPerPage,
      totalPages: totalPages,
      onItemTap: _navigateToExploreItem,
      onItemMenu: _showTrackBottomSheet,
    );
  }

  Widget _buildExploreItem(ExploreItem item, ColorScheme colorScheme) {
    final isArtist = item.type == 'artist';
    final cardSize = _exploreCardSize(context);
    final iconSize = cardSize * 0.3;

    return Semantics(
      button: true,
      label: context.l10n.a11yOpenItem(item.type, item.name),
      child: GestureDetector(
        onTap: () => _navigateToExploreItem(item),
        child: SizedBox(
          width: cardSize,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              crossAxisAlignment: isArtist
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(
                    isArtist ? cardSize / 2 : 10,
                  ),
                  child: item.coverUrl != null && item.coverUrl!.isNotEmpty
                      ? CachedCoverImage(
                          imageUrl: item.coverUrl!,
                          width: cardSize,
                          height: cardSize,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => ShimmerLoading(
                            child: Container(
                              width: cardSize,
                              height: cardSize,
                              color: colorScheme.surfaceContainerHighest,
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: cardSize,
                            height: cardSize,
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              _getIconForType(item.type),
                              color: colorScheme.onSurfaceVariant,
                              size: iconSize,
                            ),
                          ),
                        )
                      : Container(
                          width: cardSize,
                          height: cardSize,
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            _getIconForType(item.type),
                            color: colorScheme.onSurfaceVariant,
                            size: iconSize,
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: isArtist ? TextAlign.center : TextAlign.start,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (item.artists.isNotEmpty && !isArtist)
                  ClickableArtistName(
                    artistName: item.artists,
                    coverUrl: item.coverUrl,
                    extensionId: item.providerId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'track':
        return Icons.music_note;
      case 'album':
        return Icons.album;
      case 'playlist':
        return Icons.playlist_play;
      case 'artist':
        return Icons.person;
      case 'station':
        return Icons.radio;
      default:
        return Icons.music_note;
    }
  }

  String? _providerIdForExploreItem(ExploreItem item) {
    final itemProviderId = item.providerId?.trim();
    if (itemProviderId != null && itemProviderId.isNotEmpty) {
      return itemProviderId;
    }

    final feedProviderId = ref.read(exploreProvider).providerId?.trim();
    if (feedProviderId != null && feedProviderId.isNotEmpty) {
      return feedProviderId;
    }

    return null;
  }

  void _showMissingExploreProviderMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.extensionsNoHomeFeedExtensions)),
    );
  }

  void _navigateToExploreItem(ExploreItem item) async {
    final extensionId = _providerIdForExploreItem(item);

    switch (item.type) {
      case 'track':
        _showTrackBottomSheet(item);
        return;
      case 'album':
        if (extensionId == null) {
          _showMissingExploreProviderMessage();
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (context) => ExtensionAlbumScreen(
              extensionId: extensionId,
              albumId: item.id,
              albumName: item.name,
              coverUrl: item.coverUrl,
            ),
          ),
        );
        return;
      case 'playlist':
        if (extensionId == null) {
          _showMissingExploreProviderMessage();
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (context) => ExtensionPlaylistScreen(
              extensionId: extensionId,
              playlistId: item.id,
              playlistName: item.name,
              coverUrl: item.coverUrl,
            ),
          ),
        );
        return;
      case 'artist':
        if (extensionId == null) {
          _showMissingExploreProviderMessage();
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (context) => ExtensionArtistScreen(
              extensionId: extensionId,
              artistId: item.id,
              artistName: item.name,
              coverUrl: item.coverUrl,
            ),
          ),
        );
        return;
      default:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${item.type}: ${item.name}')));
        return;
    }
  }

  void _showTrackBottomSheet(ExploreItem item) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppSheetHandle(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: item.coverUrl != null && item.coverUrl!.isNotEmpty
                        ? CachedCoverImage(
                            imageUrl: item.coverUrl!,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 64,
                            height: 64,
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.music_note,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        ClickableArtistName(
                          artistName: item.artists,
                          coverUrl: item.coverUrl,
                          extensionId: item.providerId,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.download, color: colorScheme.primary),
              title: Text(context.l10n.downloadTitle),
              onTap: () {
                Navigator.pop(context);
                _handleExploreTrackPrimaryAction(item);
              },
            ),
            ListTile(
              leading: Icon(Icons.album, color: colorScheme.onSurfaceVariant),
              title: Text(context.l10n.homeGoToAlbum),
              onTap: () {
                Navigator.pop(context);
                _navigateToTrackAlbum(item);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _handleExploreTrackPrimaryAction(ExploreItem item) async {
    final settings = ref.read(settingsProvider);

    final track = Track(
      id: item.id,
      name: item.name,
      artistName: item.artists,
      albumName: item.albumName ?? '',
      albumId: item.albumId,
      duration: item.durationMs ~/ 1000,
      trackNumber: null,
      discNumber: null,
      totalDiscs: null,
      isrc: null,
      releaseDate: item.releaseDate,
      coverUrl: item.coverUrl,
      source: _providerIdForExploreItem(item),
    );

    if (settings.askQualityBeforeDownload || settings.allowQualityVariants) {
      DownloadServicePicker.show(
        context,
        trackName: track.name,
        artistName: track.artistName,
        coverUrl: track.coverUrl,
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

  Future<void> _navigateToTrackAlbum(ExploreItem item) async {
    if (item.albumId != null && item.albumId!.isNotEmpty) {
      final extensionId = _providerIdForExploreItem(item);
      if (extensionId == null) {
        _showMissingExploreProviderMessage();
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (context) => ExtensionAlbumScreen(
            extensionId: extensionId,
            albumId: item.albumId!,
            albumName: item.albumName ?? 'Album',
            coverUrl: item.coverUrl,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.homeAlbumInfoUnavailable)),
      );
    }
  }
}
