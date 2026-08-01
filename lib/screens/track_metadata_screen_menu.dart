// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of 'track_metadata_screen.dart';

// The overflow options sheet and its header cover.
extension _TrackMetadataMenu on _TrackMetadataScreenState {
  void _showOptionsMenu(
    BuildContext screenContext,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) {
    showModalBottomSheet<void>(
      context: screenContext,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      isScrollControlled: true,
      builder: (sheetContext) {
        final l10n = sheetContext.l10n;

        final options = <_MetadataOption>[
          if (_fileExists)
            _MetadataOption(
              icon: Icons.playlist_play,
              label: l10n.trackPlayNext,
              onTap: () => _enqueueThis(ref, playNext: true),
            ),
          if (_fileExists)
            _MetadataOption(
              icon: Icons.queue_music,
              label: l10n.trackAddToQueue,
              onTap: () => _enqueueThis(ref, playNext: false),
            ),
          if (albumName.trim().isNotEmpty)
            _MetadataOption(
              icon: Icons.album_outlined,
              label: l10n.homeGoToAlbum,
              onTap: () => _goToStoredAlbum(screenContext),
            ),
          _MetadataOption(
            icon: Icons.copy_outlined,
            label: l10n.trackCopyFilePath,
            dividerAbove: _fileExists,
            onTap: () => _copyToClipboard(screenContext, cleanFilePath),
          ),
          if (_fileExists)
            _MetadataOption(
              icon: Icons.edit_outlined,
              label: l10n.trackEditMetadata,
              onTap: () =>
                  _showEditMetadataSheet(screenContext, ref, colorScheme),
            ),
          if (!_isLocalItem && (_coverUrl != null || _fileExists))
            _MetadataOption(
              icon: Icons.image_outlined,
              label: l10n.trackSaveCoverArt,
              onTap: _saveCoverArt,
            ),
          if (!_isLocalItem)
            _MetadataOption(
              icon: Icons.lyrics_outlined,
              label: l10n.trackSaveLyrics,
              onTap: _saveLyrics,
            ),
          if (_fileExists)
            _MetadataOption(
              icon: Icons.travel_explore,
              label: l10n.trackReEnrich,
              onTap: _reEnrichMetadata,
            ),
          if (_fileExists && _isConvertibleFormat)
            _MetadataOption(
              icon: Icons.swap_horiz,
              label: l10n.trackConvertFormat,
              onTap: () => _showConvertSheet(screenContext),
            ),
          if (_fileExists && !_isCueFile)
            _MetadataOption(
              icon: Icons.graphic_eq,
              label: l10n.trackReplayGain,
              onTap: () => _rescanReplayGain(),
            ),
          if (_fileExists && _isCueFile)
            _MetadataOption(
              icon: Icons.call_split,
              label: l10n.cueSplitTitle,
              onTap: () => _showCueSplitSheet(screenContext),
            ),
          if (_spotifyId != null || (isrc?.isNotEmpty ?? false))
            _MetadataOption(
              icon: Icons.open_in_new,
              label: l10n.trackOpenOn,
              dividerAbove: true,
              onTap: () => OpenOnPlatformSheet.show(
                screenContext,
                spotifyId: _spotifyId ?? '',
                isrc: isrc ?? '',
              ),
            ),
          _MetadataOption(
            icon: Icons.share_outlined,
            label: l10n.trackMetadataShare,
            dividerAbove: _spotifyId == null && !(isrc?.isNotEmpty ?? false),
            onTap: () => _shareFile(screenContext),
          ),
          _MetadataOption(
            icon: Icons.delete_outline,
            label: l10n.trackRemoveFromDevice,
            destructive: true,
            onTap: () => _confirmDelete(screenContext, ref, colorScheme),
          ),
        ];

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppSheetHandle(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _buildOptionsHeaderCover(colorScheme),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trackName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                artistName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  SettingsGroup(
                    children: [
                      for (int i = 0; i < options.length; i++) ...[
                        if (options[i].dividerAbove && i != 0)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        _MetadataOptionTile(
                          option: options[i],
                          colorScheme: colorScheme,
                          onTap: () => _closeOptionsMenuAndRun(
                            sheetContext,
                            options[i].onTap,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionsHeaderCover(ColorScheme colorScheme) {
    const size = 56.0;
    const cacheWidth = 112;

    Widget placeholder() => Container(
      width: size,
      height: size,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant),
    );

    if (_coverUrl != null) {
      return CachedCoverImage(
        imageUrl: _coverUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: cacheWidth,
        memCacheHeight: cacheWidth,
        errorWidget: (_, _, _) => placeholder(),
      );
    }

    if (_localCoverPath != null && _localCoverPath!.isNotEmpty) {
      return Image.file(
        File(_localCoverPath!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorBuilder: (_, _, _) => placeholder(),
      );
    }

    return placeholder();
  }

  Future<void> _goToStoredAlbum(BuildContext screenContext) async {
    final resolvedAlbumArtist = (albumArtist ?? '').trim();
    final artist = resolvedAlbumArtist.isNotEmpty
        ? resolvedAlbumArtist
        : artistName;

    if (!_isLocalItem) {
      pushViaPreferredNavigator(
        screenContext,
        (_) => DownloadedAlbumScreen(
          albumName: albumName,
          artistName: artist,
          coverUrl: _coverUrl,
        ),
      );
      return;
    }

    try {
      final rows = await LibraryDatabase.instance.getQueueLocalAlbumTracksByKey(
        _localLibraryItem!.albumKey,
      );
      if (!mounted || !screenContext.mounted) return;
      final tracks = rows
          .map(LocalLibraryItem.fromJson)
          .toList(growable: false);
      if (tracks.isNotEmpty) {
        pushViaPreferredNavigator(
          screenContext,
          (_) => LocalAlbumScreen(
            albumName: albumName,
            artistName: artist,
            coverPath: _localCoverPath,
            tracks: tracks,
          ),
        );
        return;
      }
    } catch (e) {
      _log.w('Failed to resolve local album: $e');
    }

    if (!mounted || !screenContext.mounted) return;
    await navigateToAlbum(
      screenContext,
      albumName: albumName,
      artistName: artist,
      coverUrl: _coverUrl,
    );
  }
}
