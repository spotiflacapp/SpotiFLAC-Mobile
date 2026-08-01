part of 'track_metadata_screen.dart';

extension _TrackMetadataFileActions on _TrackMetadataScreenState {
  void _showEditMetadataSheet(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) async {
    Map<String, dynamic>? fileMetadata;
    try {
      final result = await PlatformBridge.readFileMetadata(cleanFilePath);
      if (result['error'] == null) {
        fileMetadata = result;
      }
    } catch (e) {
      debugPrint('readFileMetadata failed, using item data: $e');
    }

    String val(String key, String? fallback) {
      final v = fileMetadata?[key]?.toString();
      return (v != null && v.isNotEmpty) ? v : (fallback ?? '');
    }

    final initialValues = <String, String>{
      'title': val('title', trackName),
      'artist': val('artist', artistName),
      'album': val('album', albumName),
      'album_artist': val('album_artist', albumArtist),
      'date': val('date', releaseDate),
      'track_number': (fileMetadata?['track_number'] ?? trackNumber ?? '')
          .toString(),
      'total_tracks': (fileMetadata?['total_tracks'] ?? totalTracks ?? '')
          .toString(),
      'disc_number': (fileMetadata?['disc_number'] ?? discNumber ?? '')
          .toString(),
      'total_discs': (fileMetadata?['total_discs'] ?? totalDiscs ?? '')
          .toString(),
      'genre': val('genre', genre),
      'isrc': val('isrc', isrc),
      'label': val('label', label),
      'copyright': val('copyright', copyright),
      'composer': val('composer', composer),
      'comment': fileMetadata?['comment']?.toString() ?? '',
      'lyrics': fileMetadata?['lyrics']?.toString() ?? '',
    };

    final initialDurationSeconds =
        readPositiveInt(fileMetadata?['duration']) ?? duration ?? 0;

    if (!context.mounted) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      builder: (sheetContext) => _EditMetadataSheet(
        colorScheme: colorScheme,
        initialValues: initialValues,
        filePath: cleanFilePath,
        sourceTrackId: _spotifyId,
        durationMs: initialDurationSeconds > 0
            ? initialDurationSeconds * 1000
            : 0,
        artistTagMode: ref.read(settingsProvider).artistTagMode,
      ),
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text(this.context.l10n.snackbarMetadataSaved)),
      );
      try {
        final refreshed = await PlatformBridge.readFileMetadata(cleanFilePath);
        final refreshedLyrics = refreshed['lyrics']?.toString().trim() ?? '';
        final refreshedInstrumental = isInstrumentalLyricsMarker(
          refreshedLyrics,
        );
        final refreshedDisplayLyrics = cleanLyricsForDisplay(refreshedLyrics);
        _setState(() {
          _editedMetadata = refreshed;
          _lyricsError = null;
          _isInstrumental = refreshedInstrumental;
          _embeddedLyricsChecked = true;
          if (refreshedDisplayLyrics.isNotEmpty) {
            _lyrics = refreshedDisplayLyrics;
            _rawLyrics = refreshedLyrics;
            _lyricsSource = context.l10n.trackLyricsEmbeddedSource;
            _lyricsEmbedded = true;
          } else if (refreshedInstrumental) {
            _lyrics = null;
            _rawLyrics = null;
            _lyricsSource = context.l10n.trackLyricsEmbeddedSource;
            _lyricsEmbedded = false;
          } else {
            _lyrics = null;
            _rawLyrics = null;
            _lyricsSource = null;
            _lyricsEmbedded = false;
          }
        });
      } catch (_) {
        _setState(() {});
      }
      await _refreshEmbeddedCoverPreview(force: true);
      _markMetadataChanged();
      await _syncDownloadHistoryMetadata();
    }
  }

  void _confirmDelete(
    BuildContext screenContext,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) {
    showDialog<void>(
      context: screenContext,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.trackDeleteConfirmTitle),
        content: Text(dialogContext.l10n.trackDeleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.dialogCancel),
          ),
          TextButton(
            onPressed: () async {
              var fileDeleted = true;
              if (_isLocalItem) {
                if (_isCueVirtualTrack && _localLibraryItem != null) {
                  await ref
                      .read(localLibraryProvider.notifier)
                      .removeItem(_localLibraryItem!.id);
                } else {
                  fileDeleted = await deleteFile(cleanFilePath);
                  if (fileDeleted && _localLibraryItem != null) {
                    await ref
                        .read(localLibraryProvider.notifier)
                        .removeItem(_localLibraryItem!.id);
                  }
                }
              } else {
                fileDeleted = await deleteFile(cleanFilePath);
                if (fileDeleted) {
                  ref
                      .read(downloadHistoryProvider.notifier)
                      .removeFromHistory(_downloadItem!.id);
                }
              }

              if (!fileDeleted) {
                if (screenContext.mounted) {
                  ScaffoldMessenger.of(screenContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        screenContext.l10n.snackbarError(
                          screenContext.l10n.snackbarFailedToWriteStorage,
                        ),
                      ),
                    ),
                  );
                }
                return;
              }

              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop(true);
                }
              });
            },
            child: Text(
              dialogContext.l10n.dialogDelete,
              style: TextStyle(color: colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _closeOptionsMenuAndRun(BuildContext sheetContext, VoidCallback action) {
    Navigator.pop(sheetContext);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      action();
    });
  }

  Future<void> _openFile(BuildContext context, String filePath) async {
    if (isCueVirtualPath(filePath)) {
      _showCueVirtualTrackSnackBar(context);
      return;
    }
    try {
      final playbackCover =
          normalizeOptionalString(_localCoverPath) ??
          normalizeOptionalString(_embeddedCoverPreviewPath) ??
          normalizeOptionalString(_coverUrl) ??
          '';
      await ref
          .read(playbackProvider.notifier)
          .playLocalPath(
            path: filePath,
            title: trackName,
            artist: artistName,
            album: albumName,
            coverUrl: playbackCover,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.snackbarCannotOpenFile(context.friendlyError(e)),
            ),
          ),
        );
      }
    }
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.trackCopiedToClipboard),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareFile(BuildContext context) async {
    if (_isCueVirtualTrack) {
      _showCueVirtualTrackSnackBar(context);
      return;
    }

    String sharePath = cleanFilePath;
    if (!await fileExists(sharePath)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.snackbarFileNotFound)),
        );
      }
      return;
    }

    final shareTitle = '$trackName - $artistName';

    // For SAF content URIs, use native share intent directly (zero-copy)
    if (isContentUri(sharePath)) {
      try {
        await PlatformBridge.shareContentUri(sharePath, title: shareTitle);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.snackbarCannotOpenFile('Failed to share file'),
              ),
            ),
          );
        }
      }
      return;
    }

    await SharePlus.instance.share(
      ShareParams(files: [XFile(sharePath)], text: shareTitle),
    );
  }

  String _formatFullDate(DateTime date) {
    return '${date.day} ${_TrackMetadataScreenState._months[date.month - 1]} ${date.year}, '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  IconData _getServiceIcon(String service) {
    switch (service.toLowerCase()) {
      case MusicServices.tidal:
        return Icons.waves;
      case MusicServices.qobuz:
        return Icons.album;
      case MusicServices.amazon:
        return Icons.shopping_cart;
      default:
        return Icons.cloud_download;
    }
  }

  Color _getServiceColor(String service, ColorScheme colorScheme) {
    switch (service.toLowerCase()) {
      case MusicServices.tidal:
        return const Color(0xFF0077B5);
      case MusicServices.qobuz:
        return const Color(0xFF0052CC);
      case MusicServices.amazon:
        return const Color(0xFFFF9900);
      default:
        return colorScheme.primary;
    }
  }
}
