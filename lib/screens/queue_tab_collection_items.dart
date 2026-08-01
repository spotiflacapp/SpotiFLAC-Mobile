part of 'queue_tab.dart';

extension _QueueTabCollectionItemWidgets on _QueueTabState {
  Widget _buildDownloadGridItem(
    BuildContext context,
    DownloadItem item,
    ColorScheme colorScheme,
  ) {
    final radius = context.tokens.borderRadiusThumb;
    final isDownloading = item.status == DownloadStatus.downloading;
    final isFinalizing = item.status == DownloadStatus.finalizing;
    final isQueued = item.status == DownloadStatus.queued;
    final isFailed = item.status == DownloadStatus.failed;
    final progress = item.progress.clamp(0.0, 1.0);

    final cover = item.track.coverUrl != null
        ? CachedCoverImage(
            imageUrl: item.track.coverUrl!,
            borderRadius: radius,
            fadeInDuration: const Duration(milliseconds: 180),
          )
        : const TrackCoverPlaceholder();

    final onTap = isFailed || item.status == DownloadStatus.skipped
        ? () => _showDownloadErrorDialog(context, item)
        : () => _confirmCancelDownload(context, item);

    return SmoothedProgressScope(
      value: item.progress,
      animate: _shouldAnimateDownloadProgress(context, item),
      child: TrackGridCard(
        onTap: onTap,
        semanticLabel: context.l10n.a11yTrackByArtist(
          item.track.name,
          item.track.artistName,
        ),
        cover: cover,
        overlays: [
          if (isDownloading || isFinalizing || isQueued)
            ClipRRect(
              borderRadius: radius,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
            ),
          if (isDownloading || isFinalizing || isQueued)
            Center(
              child: isDownloading && progress > 0
                  ? SmoothedProgressBuilder(
                      builder: (context, visualProgress, child) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(
                              value: visualProgress,
                              strokeWidth: 3,
                              color: Colors.white,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.25,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${(visualProgress * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                      ),
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
        title: item.track.name,
        subtitle: Text(item.track.artistName),
      ),
    );
  }

  Widget _buildBridgeGridItem(
    BuildContext context,
    DownloadItem item,
    ColorScheme colorScheme,
    DownloadHistoryItem? historyItem, {
    List<DownloadHistoryItem>? navigationItems,
    int? navigationIndex,
  }) {
    final track = item.track;
    final radius = BorderRadius.circular(8);
    final unifiedItem = historyItem == null
        ? null
        : UnifiedLibraryItem.fromDownloadHistory(historyItem);
    final quality =
        unifiedItem?.qualityForMode(_libraryQualityLabelMode) ??
        track.audioQuality;
    final cover = unifiedItem != null
        ? _buildUnifiedCoverImage(unifiedItem, colorScheme)
        : track.coverUrl != null
        ? CachedCoverImage(imageUrl: track.coverUrl!, borderRadius: radius)
        : const TrackCoverPlaceholder();
    final heroTag = historyItem != null
        ? 'cover_lib_dl_${historyItem.id}'
        : 'cover_${item.id}';
    final trackName = historyItem?.trackName ?? track.name;
    final artistName = historyItem?.artistName ?? track.artistName;
    return TrackGridCard(
      semanticLabel: context.l10n.a11yTrackByArtist(trackName, artistName),
      onTap: () => historyItem != null
          ? _navigateToHistoryMetadataScreen(
              historyItem,
              navigationItems: navigationItems,
              navigationIndex: navigationIndex,
            )
          : _navigateToMetadataScreen(item),
      cover: Hero(tag: heroTag, child: cover),
      overlays: [
        if (quality != null && quality.isNotEmpty)
          Positioned(
            left: 4,
            top: 4,
            child: _buildLibraryQualityBadge(context, colorScheme, quality),
          ),
      ],
      title: trackName,
      subtitle: Text(artistName),
    );
  }

  Widget _buildBridgeListItem(
    BuildContext context,
    DownloadItem item,
    ColorScheme colorScheme,
    DownloadHistoryItem? historyItem, {
    List<DownloadHistoryItem>? navigationItems,
    int? navigationIndex,
  }) {
    final track = item.track;
    final coverSize = _queueCoverSize();
    final radius = BorderRadius.circular(8);
    final unifiedItem = historyItem == null
        ? null
        : UnifiedLibraryItem.fromDownloadHistory(historyItem);
    final quality =
        unifiedItem?.qualityForMode(_libraryQualityLabelMode) ??
        track.audioQuality;
    final cover = unifiedItem != null
        ? _buildUnifiedCoverImage(unifiedItem, colorScheme, coverSize)
        : track.coverUrl != null
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
    final heroTag = historyItem != null
        ? 'cover_lib_dl_${historyItem.id}'
        : 'cover_${item.id}';
    final trackName = historyItem?.trackName ?? track.name;
    final artistName = historyItem?.artistName ?? track.artistName;
    return TrackCard(
      onTap: () => historyItem != null
          ? _navigateToHistoryMetadataScreen(
              historyItem,
              navigationItems: navigationItems,
              navigationIndex: navigationIndex,
            )
          : _navigateToMetadataScreen(item),
      leading: Hero(tag: heroTag, child: cover),
      title: trackName,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            artistName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (quality != null && quality.isNotEmpty) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: _buildLibraryQualityBadge(
                context,
                colorScheme,
                quality,
                listStyle: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLibraryQualityBadge(
    BuildContext context,
    ColorScheme colorScheme,
    String quality, {
    bool listStyle = false,
  }) {
    final tokens = context.tokens;
    final isHighlightedQuality = shouldHighlightAudioQualityBadge(quality);
    return Container(
      padding: tokens.badgePadding,
      decoration: BoxDecoration(
        color: isHighlightedQuality
            ? listStyle
                  ? colorScheme.primaryContainer
                  : colorScheme.primary
            : colorScheme.surfaceContainerHighest,
        borderRadius: tokens.borderRadiusBadge,
      ),
      child: Text(
        listStyle ? quality : _getQualityBadgeText(quality),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: isHighlightedQuality
              ? listStyle
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onPrimary
              : colorScheme.onSurfaceVariant,
          fontSize: tokens.badgeFontSize,
          fontWeight: listStyle ? FontWeight.w500 : FontWeight.w600,
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
                    count: playlist.trackCount,
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
                          '${playlist.trackCount} ${playlist.trackCount == 1 ? 'track' : 'tracks'}',
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
}
