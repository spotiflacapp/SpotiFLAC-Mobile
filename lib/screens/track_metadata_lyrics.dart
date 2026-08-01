part of 'track_metadata_screen.dart';

extension _TrackMetadataLyricsAndSaving on _TrackMetadataScreenState {
  Widget _buildLyricsCard(BuildContext context, ColorScheme colorScheme) {
    final hasDisplayLyrics = _lyrics?.trim().isNotEmpty == true;
    final hasDisplaySource =
        (hasDisplayLyrics || _isInstrumental) &&
        _lyricsSource?.trim().isNotEmpty == true;
    return Card(
      elevation: 0,
      color: settingsGroupColor(context),
      shape: _sectionCardShape(colorScheme),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lyrics_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.trackLyrics,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (hasDisplayLyrics)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () => _copyToClipboard(context, _lyrics!),
                    tooltip: context.l10n.trackCopyLyrics,
                  ),
              ],
            ),
            if (hasDisplaySource)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.l10n.trackLyricsSource(_lyricsSource!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 12),

            if (_lyricsLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_lyricsError != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _lyricsError!,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                    TextButton(
                      onPressed: _fetchOnlineLyrics,
                      child: Text(context.l10n.dialogRetry),
                    ),
                  ],
                ),
              )
            else if (_isInstrumental)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.music_note,
                      color: colorScheme.tertiary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      context.l10n.trackInstrumental,
                      style: TextStyle(
                        color: colorScheme.onTertiaryContainer,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              )
            else if (hasDisplayLyrics)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Text(
                        _lyrics!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                  if (!_lyricsEmbedded && _fileExists) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: FilledButton.tonalIcon(
                        onPressed: _isEmbedding ? null : _embedLyrics,
                        icon: _isEmbedding
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_alt),
                        label: Text(context.l10n.trackEmbedLyrics),
                      ),
                    ),
                  ],
                ],
              )
            else if (_embeddedLyricsChecked && _fileExists)
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lyrics_outlined,
                          color: colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.l10n.trackLyricsNotInFile,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: FilledButton.tonalIcon(
                      onPressed: _fetchOnlineLyrics,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: Text(context.l10n.trackFetchOnlineLyrics),
                    ),
                  ),
                ],
              )
            else
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: _fetchLyrics,
                  icon: const Icon(Icons.download),
                  label: Text(context.l10n.trackLoadLyrics),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Check for lyrics embedded in the audio file only (no network requests).
  /// Called automatically when the screen opens.
  Future<void> _checkEmbeddedLyrics() async {
    if (_lyricsLoading || !_fileExists) return;
    final generation = _metadataLoadGeneration;
    final sourcePath = cleanFilePath;
    if (!mounted) return;

    _setState(() {
      _lyricsLoading = true;
      _lyricsError = null;
      _isInstrumental = false;
      _lyricsSource = null;
    });

    try {
      final embeddedResult =
          await PlatformBridge.getLyricsLRCWithSource(
            '',
            trackName,
            artistName,
            filePath: sourcePath,
            durationMs: 0,
          ).timeout(
            const Duration(seconds: 5),
            onTimeout: () => <String, dynamic>{'lyrics': '', 'source': ''},
          );

      final embeddedLyrics = embeddedResult['lyrics']?.toString() ?? '';
      final embeddedSource = embeddedResult['source']?.toString() ?? '';

      if (mounted &&
          generation == _metadataLoadGeneration &&
          sourcePath == cleanFilePath) {
        final instrumental = isInstrumentalLyricsMarker(embeddedLyrics);
        final cleanLyrics = cleanLyricsForDisplay(embeddedLyrics);
        if (instrumental || cleanLyrics.isNotEmpty) {
          _setState(() {
            _lyrics = instrumental ? null : cleanLyrics;
            _rawLyrics = instrumental ? null : embeddedLyrics;
            _lyricsSource = embeddedSource.isNotEmpty
                ? embeddedSource
                : context.l10n.trackLyricsEmbeddedSource;
            _lyricsEmbedded = !instrumental;
            _isInstrumental = instrumental;
            _lyricsLoading = false;
            _embeddedLyricsChecked = true;
          });
        } else {
          _setState(() {
            _lyrics = null;
            _rawLyrics = null;
            _lyricsSource = null;
            _lyricsEmbedded = false;
            _lyricsLoading = false;
            _embeddedLyricsChecked = true;
          });
        }
      }
    } catch (e) {
      if (mounted &&
          generation == _metadataLoadGeneration &&
          sourcePath == cleanFilePath) {
        _setState(() {
          _lyricsLoading = false;
          _embeddedLyricsChecked = true;
        });
      }
    }
  }

  /// Fetch lyrics from online providers. Only called by user action.
  Future<void> _fetchOnlineLyrics() async {
    if (_lyricsLoading) return;

    _setState(() {
      _lyricsLoading = true;
      _lyricsError = null;
      _isInstrumental = false;
      _lyricsSource = null;
    });

    try {
      final durationMs = (duration ?? 0) * 1000;

      final result = await PlatformBridge.getLyricsLRCWithSource(
        _spotifyId ?? '',
        trackName,
        artistName,
        filePath: null,
        durationMs: durationMs,
      ).timeout(const Duration(seconds: 20));

      final lrcText = result['lyrics']?.toString() ?? '';
      final source = result['source']?.toString() ?? '';
      final instrumental =
          (result['instrumental'] as bool? ?? false) ||
          isInstrumentalLyricsMarker(lrcText);
      final cleanLyrics = cleanLyricsForDisplay(lrcText);

      if (mounted) {
        if (instrumental) {
          _setState(() {
            _lyrics = null;
            _rawLyrics = null;
            _isInstrumental = true;
            _lyricsSource = source.isNotEmpty ? source : null;
            _lyricsEmbedded = false;
            _lyricsLoading = false;
          });
        } else if (cleanLyrics.isEmpty) {
          _setState(() {
            _lyrics = null;
            _rawLyrics = null;
            _lyricsSource = null;
            _lyricsEmbedded = false;
            _lyricsError = context.l10n.trackLyricsNotAvailable;
            _lyricsLoading = false;
          });
        } else {
          _setState(() {
            _lyrics = cleanLyrics;
            _rawLyrics = lrcText;
            _lyricsSource = source.isNotEmpty ? source : null;
            _lyricsEmbedded = false;
            _lyricsLoading = false;
          });
        }
      }
    } on TimeoutException {
      if (mounted) {
        _setState(() {
          _lyricsError = context.l10n.trackLyricsTimeout;
          _lyricsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _setState(() {
          _lyricsError = context.l10n.trackLyricsLoadFailed;
          _lyricsLoading = false;
        });
      }
    }
  }

  /// Full lyrics fetch: check embedded first, then online.
  /// Used by the "Load Lyrics" button when file doesn't exist (non-local items).
  Future<void> _fetchLyrics() async {
    if (_lyricsLoading) return;

    _setState(() {
      _lyricsLoading = true;
      _lyricsError = null;
      _isInstrumental = false;
      _lyricsSource = null;
    });

    try {
      final durationMs = (duration ?? 0) * 1000;

      if (_fileExists) {
        final embeddedResult =
            await PlatformBridge.getLyricsLRCWithSource(
              '',
              trackName,
              artistName,
              filePath: cleanFilePath,
              durationMs: 0,
            ).timeout(
              const Duration(seconds: 5),
              onTimeout: () => <String, dynamic>{'lyrics': '', 'source': ''},
            );

        final embeddedLyrics = embeddedResult['lyrics']?.toString() ?? '';
        final embeddedSource = embeddedResult['source']?.toString() ?? '';

        final embeddedInstrumental = isInstrumentalLyricsMarker(embeddedLyrics);
        final cleanEmbeddedLyrics = cleanLyricsForDisplay(embeddedLyrics);
        if (embeddedInstrumental || cleanEmbeddedLyrics.isNotEmpty) {
          if (mounted) {
            _setState(() {
              _lyrics = embeddedInstrumental ? null : cleanEmbeddedLyrics;
              _rawLyrics = embeddedInstrumental ? null : embeddedLyrics;
              _lyricsSource = embeddedSource.isNotEmpty
                  ? embeddedSource
                  : context.l10n.trackLyricsEmbeddedSource;
              _lyricsEmbedded = !embeddedInstrumental;
              _isInstrumental = embeddedInstrumental;
              _lyricsLoading = false;
              _embeddedLyricsChecked = true;
            });
          }
          return;
        }
      }

      final result = await PlatformBridge.getLyricsLRCWithSource(
        _spotifyId ?? '',
        trackName,
        artistName,
        filePath: null,
        durationMs: durationMs,
      ).timeout(const Duration(seconds: 20));

      final lrcText = result['lyrics']?.toString() ?? '';
      final source = result['source']?.toString() ?? '';
      final instrumental =
          (result['instrumental'] as bool? ?? false) ||
          isInstrumentalLyricsMarker(lrcText);
      final cleanLyrics = cleanLyricsForDisplay(lrcText);

      if (mounted) {
        if (instrumental) {
          _setState(() {
            _lyrics = null;
            _rawLyrics = null;
            _isInstrumental = true;
            _lyricsSource = source.isNotEmpty ? source : null;
            _lyricsEmbedded = false;
            _lyricsLoading = false;
          });
        } else if (cleanLyrics.isEmpty) {
          _setState(() {
            _lyrics = null;
            _rawLyrics = null;
            _lyricsSource = null;
            _lyricsEmbedded = false;
            _lyricsError = context.l10n.trackLyricsNotAvailable;
            _lyricsLoading = false;
          });
        } else {
          _setState(() {
            _lyrics = cleanLyrics;
            _rawLyrics = lrcText;
            _lyricsSource = source.isNotEmpty ? source : null;
            _lyricsEmbedded = false;
            _lyricsLoading = false;
          });
        }
      }
    } on TimeoutException {
      if (mounted) {
        _setState(() {
          _lyricsError = context.l10n.trackLyricsTimeout;
          _lyricsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _setState(() {
          _lyricsError = context.l10n.trackLyricsLoadFailed;
          _lyricsLoading = false;
        });
      }
    }
  }

  Future<void> _embedLyrics() async {
    if (_isEmbedding || _rawLyrics == null || !_fileExists) return;

    _setState(() => _isEmbedding = true);

    final l10nFailedToWriteStorage = context.l10n.snackbarFailedToWriteStorage;
    final l10nFailedToEmbedLyrics = context.l10n.snackbarFailedToEmbedLyrics;
    final l10nUnsupportedFormat = context.l10n.snackbarUnsupportedAudioFormat;

    String? safTempPath;
    String? coverPath;

    try {
      final rawLyrics = _rawLyrics!;
      var workingPath = cleanFilePath;

      if (_isSafFile) {
        safTempPath = await PlatformBridge.copyContentUriToTemp(cleanFilePath);
        if (safTempPath == null || safTempPath.isEmpty) {
          throw Exception('Failed to access SAF file');
        }
        workingPath = safTempPath;
      }

      final lower = workingPath.toLowerCase();
      final isFlac = lower.endsWith('.flac');
      final isMp3 = lower.endsWith('.mp3');
      final isOpus = lower.endsWith('.opus') || lower.endsWith('.ogg');
      final isM4A = lower.endsWith('.m4a') || lower.endsWith('.aac');

      bool success = false;
      String? error;

      if (isFlac) {
        final result = await PlatformBridge.embedLyricsToFile(
          workingPath,
          rawLyrics,
        );
        if (result['success'] == true) {
          if (_isSafFile) {
            final ok = await PlatformBridge.writeTempToSaf(
              workingPath,
              cleanFilePath,
            );
            success = ok;
            if (!ok) {
              error = l10nFailedToWriteStorage;
            }
          } else {
            success = true;
          }
        } else {
          error = userFacingErrorMessage(
            result['error'],
            fallback: l10nFailedToEmbedLyrics,
          );
        }
      } else if (isMp3 || isOpus || isM4A) {
        final metadata = _buildFallbackMetadata();
        try {
          final result = await PlatformBridge.readFileMetadata(workingPath);
          if (result['error'] == null) {
            final mapped = _mapMetadataForTagEmbed(result);
            metadata.addAll(mapped);
          }
        } catch (e) {
          _log.w('Failed reading file metadata before lyrics embed: $e');
        }

        metadata['LYRICS'] = rawLyrics;
        metadata['UNSYNCEDLYRICS'] = rawLyrics;

        try {
          final tempDir = await getTemporaryDirectory();
          final coverOutput =
              '${tempDir.path}${Platform.pathSeparator}lyrics_cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final coverResult = await PlatformBridge.extractCoverToFile(
            workingPath,
            coverOutput,
          );
          if (coverResult['error'] == null) {
            coverPath = coverOutput;
          }
        } catch (_) {}

        final artistTagMode = ref.read(settingsProvider).artistTagMode;
        String? ffmpegResult;
        if (isMp3) {
          ffmpegResult = await FFmpegService.embedMetadataToMp3(
            mp3Path: workingPath,
            coverPath: coverPath,
            metadata: metadata,
          );
        } else if (isM4A) {
          ffmpegResult = await FFmpegService.embedMetadataToM4a(
            m4aPath: workingPath,
            coverPath: coverPath,
            metadata: metadata,
          );
        } else {
          ffmpegResult = await FFmpegService.embedMetadataToOpus(
            opusPath: workingPath,
            coverPath: coverPath,
            metadata: metadata,
            artistTagMode: artistTagMode,
          );
        }

        if (ffmpegResult == null) {
          error = l10nFailedToEmbedLyrics;
        } else if (_isSafFile) {
          final ok = await PlatformBridge.writeTempToSaf(
            ffmpegResult,
            cleanFilePath,
          );
          success = ok;
          if (!ok) {
            error = l10nFailedToWriteStorage;
          }
        } else {
          success = true;
        }
      } else {
        error = l10nUnsupportedFormat;
      }

      if (mounted) {
        if (success) {
          _setState(() {
            _lyricsEmbedded = true;
            _isEmbedding = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.trackLyricsEmbedded)),
          );
        } else {
          _setState(() => _isEmbedding = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error ?? context.l10n.snackbarFailedToEmbedLyrics),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _setState(() => _isEmbedding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.snackbarError(context.friendlyError(e))),
          ),
        );
      }
    } finally {
      if (coverPath != null) {
        try {
          await File(coverPath).delete();
        } catch (_) {}
      }
      if (safTempPath != null) {
        try {
          await File(safTempPath).delete();
        } catch (_) {}
      }
    }
  }

  String _sanitizeFileNameSegment(String value) {
    var sanitized = value
        .replaceAll(_TrackMetadataScreenState._invalidFileNameChars, '_')
        .trim();
    sanitized = sanitized.replaceAll(
      _TrackMetadataScreenState._leadingOrTrailingDots,
      '',
    );
    sanitized = sanitized.replaceAll(
      _TrackMetadataScreenState._multiUnderscore,
      '_',
    );
    if (sanitized.isEmpty) {
      return 'untitled';
    }
    return sanitized;
  }

  String _buildSaveBaseName() {
    final artist = _sanitizeFileNameSegment(artistName);
    final track = _sanitizeFileNameSegment(trackName);
    return '$artist - $track';
  }

  String _getFileDirectory() {
    if (isContentUri(cleanFilePath)) {
      // SAF URIs don't have a filesystem parent directory
      return '';
    }
    final file = File(cleanFilePath);
    return file.parent.path;
  }

  bool get _isSafFile => isContentUri(cleanFilePath);

  Future<void> _saveCoverArt() async {
    try {
      final baseName = _buildSaveBaseName();

      if (_isSafFile) {
        final tempDir = await Directory.systemTemp.createTemp('cover_');
        final tempOutput =
            '${tempDir.path}${Platform.pathSeparator}$baseName.jpg';

        Map<String, dynamic> result;
        if (_fileExists) {
          // Prefer extracting cover from the already-downloaded file to avoid
          // a redundant network request.
          result = await PlatformBridge.extractCoverToFile(
            cleanFilePath,
            tempOutput,
          );
          if (result['error'] != null &&
              _coverUrl != null &&
              _coverUrl!.isNotEmpty) {
            result = await PlatformBridge.downloadCoverToFile(
              _coverUrl!,
              tempOutput,
              maxQuality: true,
            );
          }
        } else if (_coverUrl != null && _coverUrl!.isNotEmpty) {
          result = await PlatformBridge.downloadCoverToFile(
            _coverUrl!,
            tempOutput,
            maxQuality: true,
          );
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.trackCoverNoSource)),
            );
          }
          return;
        }

        if (result['error'] != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.trackSaveFailed(
                    context.friendlyError(result['error']),
                  ),
                ),
              ),
            );
          }
          try {
            await Directory(tempDir.path).delete(recursive: true);
          } catch (_) {}
          return;
        }

        final treeUri = _downloadItem?.downloadTreeUri;
        final relativeDir = _downloadItem?.safRelativeDir ?? '';
        if (treeUri != null && treeUri.isNotEmpty) {
          final safUri = await PlatformBridge.createSafFileFromPath(
            treeUri: treeUri,
            relativeDir: relativeDir,
            fileName: '$baseName.jpg',
            mimeType: 'image/jpeg',
            srcPath: tempOutput,
          );
          try {
            await Directory(tempDir.path).delete(recursive: true);
          } catch (_) {}
          if (mounted) {
            if (safUri != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.trackCoverSaved(baseName))),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.trackSaveFailed('Failed to write to storage'),
                  ),
                ),
              );
            }
          }
        } else {
          try {
            await Directory(tempDir.path).delete(recursive: true);
          } catch (_) {}
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.trackSaveFailed('No storage access'),
                ),
              ),
            );
          }
        }
        return;
      }

      final dir = _getFileDirectory();
      final outputPath = '$dir${Platform.pathSeparator}$baseName.jpg';

      Map<String, dynamic> result;
      if (_fileExists) {
        result = await PlatformBridge.extractCoverToFile(
          cleanFilePath,
          outputPath,
        );
        if (result['error'] != null &&
            _coverUrl != null &&
            _coverUrl!.isNotEmpty) {
          result = await PlatformBridge.downloadCoverToFile(
            _coverUrl!,
            outputPath,
            maxQuality: true,
          );
        }
      } else if (_coverUrl != null && _coverUrl!.isNotEmpty) {
        result = await PlatformBridge.downloadCoverToFile(
          _coverUrl!,
          outputPath,
          maxQuality: true,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.trackCoverNoSource)),
          );
        }
        return;
      }

      if (mounted) {
        if (result['error'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.trackSaveFailed(
                  context.friendlyError(result['error']),
                ),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.trackCoverSaved(baseName))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.trackSaveFailed(context.friendlyError(e)),
            ),
          ),
        );
      }
    }
  }

  Future<void> _saveLyrics() async {
    try {
      final baseName = _buildSaveBaseName();
      final durationMs = (duration ?? 0) * 1000;
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(context.l10n.trackSaveLyricsProgress)),
          );
      }

      if (_isSafFile) {
        final tempDir = await Directory.systemTemp.createTemp('lyrics_');
        final tempOutput =
            '${tempDir.path}${Platform.pathSeparator}$baseName.lrc';

        final result = await PlatformBridge.fetchAndSaveLyrics(
          trackName: trackName,
          artistName: artistName,
          spotifyId: _spotifyId ?? '',
          durationMs: durationMs,
          outputPath: tempOutput,
          audioFilePath: _fileExists ? cleanFilePath : '',
        );

        if (result['error'] != null) {
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.trackSaveFailed(
                      context.friendlyError(result['error']),
                    ),
                  ),
                ),
              );
          }
          try {
            await Directory(tempDir.path).delete(recursive: true);
          } catch (_) {}
          return;
        }

        final treeUri = _downloadItem?.downloadTreeUri;
        final relativeDir = _downloadItem?.safRelativeDir ?? '';
        if (treeUri != null && treeUri.isNotEmpty) {
          final safUri = await PlatformBridge.createSafFileFromPath(
            treeUri: treeUri,
            relativeDir: relativeDir,
            fileName: '$baseName.lrc',
            mimeType: 'application/octet-stream',
            srcPath: tempOutput,
          );
          try {
            await Directory(tempDir.path).delete(recursive: true);
          } catch (_) {}
          if (mounted) {
            if (safUri != null) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(context.l10n.trackLyricsSaved(baseName)),
                  ),
                );
            } else {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      context.l10n.trackSaveFailed(
                        'Failed to write to storage',
                      ),
                    ),
                  ),
                );
            }
          }
        } else {
          try {
            await Directory(tempDir.path).delete(recursive: true);
          } catch (_) {}
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.trackSaveFailed('No storage access'),
                  ),
                ),
              );
          }
        }
        return;
      }

      final dir = _getFileDirectory();
      final outputPath = '$dir${Platform.pathSeparator}$baseName.lrc';

      final result = await PlatformBridge.fetchAndSaveLyrics(
        trackName: trackName,
        artistName: artistName,
        spotifyId: _spotifyId ?? '',
        durationMs: durationMs,
        outputPath: outputPath,
        audioFilePath: _fileExists ? cleanFilePath : '',
      );

      if (mounted) {
        if (result['error'] != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.trackSaveFailed(
                    context.friendlyError(result['error']),
                  ),
                ),
              ),
            );
        } else {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(context.l10n.trackLyricsSaved(baseName))),
            );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.trackSaveFailed(context.friendlyError(e)),
              ),
            ),
          );
      }
    }
  }

  Future<void> _reEnrichMetadata() async {
    if (!_fileExists) return;

    try {
      final settings = ref.read(settingsProvider);
      final artistTagMode = settings.artistTagMode;
      final messenger = ScaffoldMessenger.of(context);
      final l10n = context.l10n;
      await ref.read(settingsProvider.notifier).syncLyricsSettingsToBackend();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.trackReEnrichSearching)),
      );

      final durationMs = (duration ?? 0) * 1000;
      final request = <String, dynamic>{
        'file_path': cleanFilePath,
        'cover_url': _coverUrl ?? '',
        'max_quality': true,
        'embed_lyrics': settings.embedLyrics,
        'lyrics_mode': settings.lyricsMode,
        'artist_tag_mode': artistTagMode,
        'spotify_id': _spotifyId ?? '',
        'track_name': trackName,
        'artist_name': artistName,
        'album_name': albumName,
        'album_artist': albumArtist ?? '',
        'track_number': trackNumber ?? 0,
        'total_tracks': totalTracks ?? 0,
        'disc_number': discNumber ?? 0,
        'total_discs': totalDiscs ?? 0,
        'release_date': releaseDate ?? '',
        'isrc': isrc ?? '',
        'genre': genre ?? '',
        'label': label ?? '',
        'copyright': copyright ?? '',
        'composer': composer ?? '',
        'duration_ms': durationMs,
        'search_online': true,
        'replace_release_metadata': allowsReleaseIdentityReplacement(
          ReEnrichOperationScope.singleFile,
        ),
      };

      final result = await PlatformBridge.reEnrichFile(request);
      final method = result['method'] as String?;

      final enriched = result['enriched_metadata'] as Map<String, dynamic>?;
      if (enriched != null && mounted) {
        _setState(() {
          _editedMetadata = {
            'title': enriched['track_name'] ?? trackName,
            'artist': enriched['artist_name'] ?? artistName,
            'album': enriched['album_name'] ?? albumName,
            'album_artist': enriched['album_artist'] ?? albumArtist,
            'date': enriched['release_date'] ?? releaseDate,
            'track_number': enriched['track_number'] ?? trackNumber,
            'total_tracks': enriched['total_tracks'] ?? totalTracks,
            'disc_number': enriched['disc_number'] ?? discNumber,
            'total_discs': enriched['total_discs'] ?? totalDiscs,
            'isrc': enriched['isrc'] ?? isrc,
            'genre': enriched['genre'] ?? genre,
            'label': enriched['label'] ?? label,
            'copyright': enriched['copyright'] ?? copyright,
            'composer': enriched['composer'] ?? composer,
          };
        });
      }

      if (method == 'native') {
        // FLAC - handled natively by Go (SAF write-back handled in Kotlin).
        // External .lrc sidecar for filesystem files is written here; SAF
        // sidecars are created natively in the Kotlin reEnrichFile handler.
        await writeReEnrichSidecarLrc(
          audioFilePath: cleanFilePath,
          reEnrichResult: result,
        );
        await _refreshEmbeddedCoverPreview(force: true);
        _markMetadataChanged();
        await _syncDownloadHistoryMetadata();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.trackReEnrichSuccess)),
          );
        }
      } else if (method == 'ffmpeg') {
        // MP3/Opus - need FFmpeg from Dart side
        // For SAF files, Kotlin returns temp_path + saf_uri
        final tempPath = result['temp_path'] as String?;
        final safUri = result['saf_uri'] as String?;
        final ffmpegTarget = tempPath ?? cleanFilePath;

        final downloadedCoverPath = result['cover_path'] as String?;
        String? effectiveCoverPath = downloadedCoverPath;
        String? extractedCoverPath;
        try {
          if (!_hasPath(effectiveCoverPath)) {
            try {
              final tempDir = await Directory.systemTemp.createTemp(
                'reenrich_cover_',
              );
              final coverOutput =
                  '${tempDir.path}${Platform.pathSeparator}cover.jpg';
              final extracted = await PlatformBridge.extractCoverToFile(
                ffmpegTarget,
                coverOutput,
              );
              if (extracted['error'] == null) {
                effectiveCoverPath = coverOutput;
                extractedCoverPath = coverOutput;
              } else {
                try {
                  await tempDir.delete(recursive: true);
                } catch (_) {}
              }
            } catch (_) {}
          }
          final metadata = (result['metadata'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v.toString()),
          );
          final lower = cleanFilePath.toLowerCase();

          String? ffmpegResult;
          if (lower.endsWith('.mp3')) {
            ffmpegResult = await FFmpegService.embedMetadataToMp3(
              mp3Path: ffmpegTarget,
              coverPath: effectiveCoverPath,
              metadata: metadata,
            );
          } else if (lower.endsWith('.m4a') || lower.endsWith('.aac')) {
            ffmpegResult = await FFmpegService.embedMetadataToM4a(
              m4aPath: ffmpegTarget,
              coverPath: effectiveCoverPath,
              metadata: metadata,
            );
          } else if (lower.endsWith('.opus') || lower.endsWith('.ogg')) {
            ffmpegResult = await FFmpegService.embedMetadataToOpus(
              opusPath: ffmpegTarget,
              coverPath: effectiveCoverPath,
              metadata: metadata,
              artistTagMode: artistTagMode,
            );
          }

          if (ffmpegResult != null && tempPath != null && safUri != null) {
            final ok = await PlatformBridge.writeTempToSaf(
              ffmpegResult,
              safUri,
            );
            if (!ok && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.trackSaveFailed(
                      context.l10n.snackbarFailedToWriteStorage,
                    ),
                  ),
                ),
              );
              return;
            }
            await writeReEnrichSafSidecarLrc(
              safUri: safUri,
              reEnrichResult: result,
            );
          }

          if (ffmpegResult != null) {
            // Filesystem .lrc sidecar. SAF sidecar is written only after
            // writeTempToSaf succeeds.
            await writeReEnrichSidecarLrc(
              audioFilePath: cleanFilePath,
              reEnrichResult: result,
            );
            await _refreshEmbeddedCoverPreview(force: true);
            _markMetadataChanged();
            await _syncDownloadHistoryMetadata();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.trackReEnrichSuccess)),
              );
            }
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.trackReEnrichFfmpegFailed)),
            );
          }
        } finally {
          for (final path in [downloadedCoverPath, tempPath]) {
            if (!_hasPath(path)) continue;
            try {
              await File(path!).delete();
            } catch (_) {}
          }
          if (_hasPath(extractedCoverPath)) {
            await _cleanupTempFileAndParent(extractedCoverPath);
          }
        }
      } else {
        if (mounted) {
          final error = context.friendlyError(
            result['error'],
            fallback: context.l10n.metadataSaveFailedFfmpeg,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.trackSaveFailed(error))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.trackSaveFailed(context.friendlyError(e)),
            ),
          ),
        );
      }
    }
  }

  Future<void> _syncDownloadHistoryMetadata() async {
    if (_isLocalItem || _downloadItem == null) return;

    String? normalizedOrNull(String? value) {
      if (value == null) return null;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return trimmed;
    }

    try {
      await ref
          .read(downloadHistoryProvider.notifier)
          .updateMetadataForItem(
            id: _downloadItem!.id,
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            albumArtist: normalizedOrNull(albumArtist),
            isrc: normalizedOrNull(isrc),
            trackNumber: trackNumber,
            totalTracks: totalTracks,
            discNumber: discNumber,
            totalDiscs: totalDiscs,
            releaseDate: normalizedOrNull(releaseDate),
            genre: normalizedOrNull(genre),
            composer: normalizedOrNull(composer),
            label: normalizedOrNull(label),
            copyright: normalizedOrNull(copyright),
          );
    } catch (e) {
      _log.w('Failed to sync download history metadata: $e');
    }
  }
}
