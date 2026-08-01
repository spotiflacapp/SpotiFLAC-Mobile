part of 'home_tab.dart';

extension _HomeTabRecentUI on _HomeTabState {
  Widget _buildRecentAccess(_RecentAccessView view, ColorScheme colorScheme) {
    final uniqueItems = view.uniqueItems;
    final downloadIds = view.downloadIds;
    final hasHiddenDownloads = view.hasHiddenDownloads;

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(16, 8, 16, 8) +
          EdgeInsets.symmetric(horizontal: wideListInset(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.l10n.homeRecent,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (uniqueItems.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    // Clearing history is not undoable, so ask first.
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(dialogContext.l10n.dialogClearAll),
                        content: Text(
                          dialogContext.l10n.dialogClearHistoryMessage,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: Text(dialogContext.l10n.dialogCancel),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: Text(dialogContext.l10n.dialogClearAll),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    for (final id in downloadIds) {
                      ref
                          .read(recentAccessProvider.notifier)
                          .hideDownloadFromRecents(id);
                    }
                    ref.read(recentAccessProvider.notifier).clearHistory();
                  },
                  child: Text(
                    context.l10n.dialogClearAll,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (uniqueItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      hasHiddenDownloads ? Icons.visibility_off : Icons.history,
                      size: 48,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.recentEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (hasHiddenDownloads) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          ref
                              .read(recentAccessProvider.notifier)
                              .clearHiddenDownloads();
                        },
                        icon: const Icon(Icons.visibility, size: 18),
                        label: Text(context.l10n.recentShowAllDownloads),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            ...uniqueItems.map(
              (item) => _buildRecentAccessItem(
                item,
                colorScheme,
                view.downloadFilePathByRecentKey,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentAccessItem(
    RecentAccessItem item,
    ColorScheme colorScheme,
    Map<String, String> downloadFilePathByRecentKey,
  ) {
    IconData typeIcon;
    String typeLabel;
    final isDownloaded = item.providerId == 'download';

    switch (item.type) {
      case RecentAccessType.artist:
        typeIcon = Icons.person;
        typeLabel = context.l10n.recentTypeArtist;
      case RecentAccessType.album:
        typeIcon = Icons.album;
        typeLabel = context.l10n.recentTypeAlbum;
      case RecentAccessType.track:
        typeIcon = Icons.music_note;
        typeLabel = context.l10n.recentTypeSong;
      case RecentAccessType.playlist:
        typeIcon = Icons.playlist_play;
        typeLabel = context.l10n.recentTypePlaylist;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: () => _navigateToRecentItem(item),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              _DownloadedOrRemoteCover(
                downloadedFilePath: isDownloaded
                    ? downloadFilePathByRecentKey['${item.type.name}:${item.id}']
                    : null,
                imageUrl: item.imageUrl,
                width: 56,
                height: 56,
                borderRadius: BorderRadius.circular(
                  item.type == RecentAccessType.artist ? 28 : 4,
                ),
                fallbackIcon: typeIcon,
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isDownloaded
                          ? (item.subtitle != null
                                ? '${context.l10n.recentTypeSong} • ${item.subtitle}'
                                : context.l10n.recentTypeSong)
                          : (item.subtitle != null
                                ? '$typeLabel • ${item.subtitle}'
                                : typeLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDownloaded
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.l10n.actionDismiss,
                icon: Icon(
                  Icons.close,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: () {
                  if (item.providerId == 'download') {
                    ref
                        .read(recentAccessProvider.notifier)
                        .hideDownloadFromRecents(item.id);
                  } else {
                    ref.read(recentAccessProvider.notifier).removeItem(item);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isEnabledMetadataExtension(String? providerId) {
    final normalized = providerId?.trim();
    if (normalized == null || normalized.isEmpty) return false;

    return ref
        .read(extensionProvider)
        .extensions
        .any(
          (ext) =>
              ext.enabled && ext.hasMetadataProvider && ext.id == normalized,
        );
  }

  Future<void> _navigateToRecentItem(RecentAccessItem item) async {
    _searchFocusNode.unfocus();

    switch (item.type) {
      case RecentAccessType.artist:
        if (_isEnabledMetadataExtension(item.providerId)) {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => ExtensionArtistScreen(
                extensionId: item.providerId!,
                artistId: item.id,
                artistName: item.name,
                coverUrl: item.imageUrl,
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => ArtistScreen(
                artistId: item.id,
                artistName: item.name,
                coverUrl: item.imageUrl,
              ),
            ),
          );
        }
        return;
      case RecentAccessType.album:
        if (item.providerId == 'download') {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => DownloadedAlbumScreen(
                albumName: item.name,
                artistName: item.subtitle ?? '',
                coverUrl: item.imageUrl,
              ),
            ),
          );
        } else if (_isEnabledMetadataExtension(item.providerId)) {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => ExtensionAlbumScreen(
                extensionId: item.providerId!,
                albumId: item.id,
                albumName: item.name,
                coverUrl: item.imageUrl,
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => AlbumScreen(
                albumId: item.id,
                albumName: item.name,
                coverUrl: item.imageUrl,
              ),
            ),
          );
        }
        return;
      case RecentAccessType.track:
        final historyItem = await ref
            .read(downloadHistoryProvider.notifier)
            .getBySpotifyIdAsync(item.id);
        if (!mounted) return;
        if (historyItem != null) {
          _navigateToMetadataScreen(historyItem);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(item.name)));
        }
        return;
      case RecentAccessType.playlist:
        if (item.id.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.recentPlaylistInfo(item.name))),
          );
          return;
        }

        if (_isEnabledMetadataExtension(item.providerId)) {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => ExtensionPlaylistScreen(
                extensionId: item.providerId!,
                playlistId: item.id,
                playlistName: item.name,
                coverUrl: item.imageUrl,
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => PlaylistScreen(
                playlistName: item.name,
                coverUrl: item.imageUrl,
                tracks: const [],
                playlistId: item.id,
              ),
            ),
          );
        }
        return;
    }
  }

  Future<void> _navigateToMetadataScreen(
    DownloadHistoryItem item, {
    List<DownloadHistoryItem>? navigationItems,
    int? navigationIndex,
  }) async {
    final navigator = Navigator.of(context);
    precacheCoverImage(context, item.coverUrl);
    final beforeModTime =
        await DownloadedEmbeddedCoverResolver.readFileModTimeMillis(
          item.filePath,
        );
    if (!mounted) return;
    final result = await navigator.push(
      slidePageRoute<bool>(
        page: TrackMetadataScreen(
          item: item,
          historyNavigationItems: navigationItems,
          navigationIndex: navigationIndex,
        ),
      ),
    );
    await DownloadedEmbeddedCoverResolver.scheduleRefreshForPath(
      item.filePath,
      beforeModTime: beforeModTime,
      force: result == true,
      onChanged: _onEmbeddedCoverChanged,
    );
  }
}
