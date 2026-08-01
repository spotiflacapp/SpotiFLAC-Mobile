// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of 'download_queue_provider.dart';

/// The per-item download pipeline: metadata enrichment, output resolution,
/// the native download call, decrypt/convert/embed finalization, and the
/// history hand-off. Queue scheduling stays in the main file.
extension _SingleItemDownload on DownloadQueueNotifier {
  bool _isStorageWriteFailure(Map<String, dynamic> result) {
    return isStorageWriteFailure(
      errorType: result['error_type']?.toString(),
      errorMessage: (result['error'] ?? result['message'])?.toString(),
    );
  }

  Future<String?> _runPostProcessingHooks(String filePath, Track track) async {
    try {
      final settings = ref.read(settingsProvider);
      final extensionState = ref.read(extensionProvider);
      final resolvedAlbumArtist = _resolveAlbumArtistForMetadata(
        track,
        settings,
      );

      if (!settings.useExtensionProviders) return null;

      final hasPostProcessing = extensionState.extensions.any(
        (e) => e.enabled && e.hasPostProcessing,
      );
      if (!hasPostProcessing) return null;

      _log.d('Running post-processing hooks on: $filePath');

      final metadata = <String, dynamic>{
        'title': track.name,
        'artist': track.artistName,
        'album': track.albumName,
        'track_number': track.trackNumber ?? 0,
        'disc_number': track.discNumber ?? 0,
        'isrc': track.isrc ?? '',
        'release_date': track.releaseDate ?? '',
        'duration_ms': track.duration * 1000,
        'cover_url': track.coverUrl ?? '',
      };
      if (resolvedAlbumArtist != null) {
        metadata['album_artist'] = resolvedAlbumArtist;
      }

      final result = await PlatformBridge.runPostProcessingV2(
        filePath,
        metadata: metadata,
      );

      if (result['success'] == true) {
        final hooksRun = result['hooks_run'] as int? ?? 0;
        final newPath = result['file_path'] as String?;
        _log.i('Post-processing completed: $hooksRun hook(s) executed');

        if (newPath != null && newPath != filePath) {
          _log.d('File path changed by post-processing: $newPath');
          return newPath;
        }
        return filePath;
      } else {
        final error = result['error'] as String? ?? 'Unknown error';
        _log.w('Post-processing failed: $error');
      }
    } catch (e) {
      _log.w('Post-processing error: $e');
    }
    return null;
  }

  Future<void> _downloadSingleItem(DownloadItem item) =>
      _DownloadRun(this, item)._run();
}

/// One download attempt for a single queue item.
///
/// What used to be the ~35 locals of a 1,700-line method live here as fields
/// so the pipeline reads as stage methods: enrich -> resolve output ->
/// resolve identifiers -> download (with SAF fallback) -> decrypt / convert /
/// embed -> publish to history. `n` is the owning notifier; queue state and
/// shared helpers stay there.
class _DownloadRun {
  _DownloadRun(this.n, this.item);

  final DownloadQueueNotifier n;

  DownloadItem item;
  bool pausedDuringThisRun = false;

  late AppSettings settings;
  late bool metadataEmbeddingEnabled;
  late Track trackToDownload;
  String? resolvedAlbumArtist;
  late String quality;
  late String safOutputExt;
  late String effectiveFilenameFormat;
  bool effectiveSafMode = false;
  String effectiveOutputDir = '';
  String? appOutputDir;
  String? safFileName;
  bool qualityVariantCollisionOnly = false;
  String? safBaseName;
  String? finalSafFileName;

  late ExtensionState extensionState;
  late bool selectedExtensionDownloadProvider;
  late bool shouldSkipExtensionSongLinkPrelookup;
  late bool useExtensions;

  String? deezerTrackId;
  String? genre;
  String? label;
  String? copyright;

  late Map<String, dynamic> result;

  // Success-path state shared between finalization stages.
  String? filePath;
  bool wasExisting = false;
  String actualQuality = '';
  String? resultOutputExt;
  bool shouldPreserveNativeM4a = false;
  DownloadDecryptionDescriptor? decryptionDescriptor;

  /// Filled by the SAF embed op from the local temp so the final quality
  /// probe doesn't have to copy the published file back out of SAF.
  Map<String, dynamic>? probedFinalMetadata;

  Future<void> _run() async {
    final normalizedService = n._normalizeQueuedService(item.service);
    if (normalizedService != item.service) {
      item = item.copyWith(service: normalizedService);
      n.state = n.state.copyWith(
        items: [
          for (final existing in n.state.items)
            if (existing.id == item.id) item else existing,
        ],
        currentDownload: n.state.currentDownload?.id == item.id
            ? item
            : n.state.currentDownload,
      );
      n._saveQueueToStorage();
    }

    if (!n._hasActiveDownloadProvider(item.service)) {
      n.updateItemStatus(
        item.id,
        DownloadStatus.failed,
        error: 'Download provider is no longer available',
        errorType: DownloadErrorType.notFound,
      );
      return;
    }

    _log.d('Processing: ${item.track.name} by ${item.track.artistName}');
    _log.d('Cover URL: ${item.track.coverUrl}');

    final currentItem = n._findItemById(item.id) ?? item;
    if (n._isLocallyCancelled(item.id, item: currentItem)) {
      _log.i('Download was cancelled before start, skipping');
      return;
    }

    if (n._isPausePending(item.id)) {
      pausedDuringThisRun = true;
      n._requeueItemForPause(item.id);
      _log.i('Download is pause-pending before start, skipping');
      return;
    }

    n.state = n.state.copyWith(currentDownload: item);

    n.updateItemStatus(item.id, DownloadStatus.downloading);

    try {
      settings = n.ref.read(settingsProvider);
      metadataEmbeddingEnabled = settings.embedMetadata;
      trackToDownload = item.track;

      if (!await _enrichDeezerTrackIfNeeded()) return;

      resolvedAlbumArtist = n._resolveAlbumArtistForMetadata(
        trackToDownload,
        settings,
      );
      await _resolveOutputTarget();
      _resolveExtensionFlags();
      if (!await _resolveTrackIdentifiers()) return;

      // Genre/label/copyright are only consumed at embed time (the payload
      // copy is just echoed back in the response), so this lookup overlaps
      // with the download instead of delaying its start; it is awaited right
      // after the download returns.
      final extendedMetadataFuture = n
          ._loadExtendedMetadataForDeezerId(deezerTrackId)
          .catchError((Object e) {
            _log.w('Extended metadata lookup failed: $e');
            return null;
          });

      if (await _shouldAbort('before native download start')) {
        return;
      }

      if (!await _downloadAndMaybeFallback()) return;

      _log.d('Result: $result');

      final extendedMetadata = await extendedMetadataFuture;
      if (extendedMetadata != null) {
        genre = extendedMetadata.genre;
        label = extendedMetadata.label;
        copyright = extendedMetadata.copyright;
      }

      final resultFilePath = result['file_path'] as String?;
      final resultFileToCleanup =
          (resultFilePath != null && result['success'] == true)
          ? resultFilePath
          : null;
      if (await _shouldAbort(
        'after result',
        deleteFileOnAbort: resultFileToCleanup,
      )) {
        return;
      }

      if (result['success'] == true) {
        if (!await _handleDownloadSuccess()) return;
      } else {
        if (!await _handleBackendFailure()) return;
      }

      n._downloadCount++;
      if (n._downloadCount % DownloadQueueNotifier._cleanupInterval == 0) {
        _log.d(
          'Cleaning up idle connections (after ${n._downloadCount} downloads)...',
        );
        try {
          await PlatformBridge.cleanupConnections();
        } catch (e) {
          _log.e('Connection cleanup failed: $e');
        }
      }
    } catch (e, stackTrace) {
      await _handleRunException(e, stackTrace);
    } finally {
      if (pausedDuringThisRun) {
        n._pausePendingItemIds.remove(item.id);
      }
    }
  }

  /// Shared guard for every checkpoint in the pipeline: an item that vanished
  /// from the queue or was flagged locally-cancelled aborts immediately; a
  /// pause-pending item re-queues instead. [deleteFileOnAbort], when given,
  /// is removed before returning (used once a file has already been written).
  Future<bool> _shouldAbort(String stage, {String? deleteFileOnAbort}) async {
    final current = n._findItemById(item.id);
    if (current == null || n._isLocallyCancelled(item.id, item: current)) {
      _log.i('Download was cancelled $stage, skipping');
      if (deleteFileOnAbort != null) {
        await deleteFile(deleteFileOnAbort);
        _log.d('Deleted cancelled download file: $deleteFileOnAbort');
      }
      return true;
    }
    if (n._isPausePending(item.id)) {
      pausedDuringThisRun = true;
      if (deleteFileOnAbort != null) {
        await deleteFile(deleteFileOnAbort);
        _log.d('Deleted paused download file: $deleteFileOnAbort');
      }
      n._requeueItemForPause(item.id);
      _log.i('Download pause requested $stage, re-queueing');
      return true;
    }
    return false;
  }

  Future<bool> _enrichDeezerTrackIfNeeded() async {
    final needsEnrichment =
        trackToDownload.id.startsWith('deezer:') &&
        (trackToDownload.isrc == null ||
            trackToDownload.isrc!.isEmpty ||
            trackToDownload.trackNumber == null ||
            trackToDownload.trackNumber == 0 ||
            trackToDownload.totalTracks == null ||
            trackToDownload.totalTracks == 0 ||
            (trackToDownload.composer == null ||
                trackToDownload.composer!.isEmpty));

    if (needsEnrichment) {
      try {
        _log.d(
          'Enriching incomplete metadata for Deezer track: ${trackToDownload.name}',
        );
        _log.d(
          'Current ISRC: ${trackToDownload.isrc}, TrackNumber: ${trackToDownload.trackNumber}',
        );
        final rawId = trackToDownload.id.split(':')[1];
        _log.d('Fetching full metadata for Deezer ID: $rawId');
        final fullData = await PlatformBridge.getProviderMetadata(
          'deezer',
          'track',
          rawId,
        );
        _log.d('Got response keys: ${fullData.keys.toList()}');

        if (fullData.containsKey('track')) {
          final trackData = fullData['track'];
          _log.d('Track data type: ${trackData.runtimeType}');
          if (trackData is Map<String, dynamic>) {
            final data = trackData;
            _log.d('Track data keys: ${data.keys.toList()}');
            _log.d('ISRC from API: ${data['isrc']}');
            _log.d('album_type from API: ${data['album_type']}');
            final enrichedTotalTracks = readPositiveInt(data['total_tracks']);
            final enrichedTotalDiscs = readPositiveInt(data['total_discs']);
            final enrichedComposer = normalizeOptionalString(
              data['composer']?.toString(),
            );
            trackToDownload = Track(
              id: (data['spotify_id'] as String?) ?? trackToDownload.id,
              name: (data['name'] as String?) ?? trackToDownload.name,
              artistName:
                  (data['artists'] as String?) ?? trackToDownload.artistName,
              albumName:
                  (data['album_name'] as String?) ?? trackToDownload.albumName,
              albumArtist: data['album_artist'] as String?,
              artistId:
                  (data['artist_id'] ?? data['artistId'])?.toString() ??
                  trackToDownload.artistId,
              albumId: data['album_id']?.toString() ?? trackToDownload.albumId,
              coverUrl: data['images'] as String?,
              duration:
                  ((data['duration_ms'] as int?) ??
                      (trackToDownload.duration * 1000)) ~/
                  1000,
              isrc: (data['isrc'] as String?) ?? trackToDownload.isrc,
              trackNumber: data['track_number'] as int?,
              discNumber: data['disc_number'] as int?,
              totalDiscs: enrichedTotalDiscs ?? trackToDownload.totalDiscs,
              releaseDate: data['release_date'] as String?,
              deezerId: rawId,
              availability: trackToDownload.availability,
              albumType:
                  (data['album_type'] as String?) ?? trackToDownload.albumType,
              totalTracks: enrichedTotalTracks ?? trackToDownload.totalTracks,
              composer: enrichedComposer ?? trackToDownload.composer,
              source: trackToDownload.source,
            );
            _log.d(
              'Metadata enriched: Track ${trackToDownload.trackNumber}, Disc ${trackToDownload.discNumber}, ISRC ${trackToDownload.isrc}, AlbumType ${trackToDownload.albumType}',
            );
          } else {
            _log.w('Unexpected track data type: ${trackData.runtimeType}');
          }
        } else {
          _log.w('Response does not contain track key');
        }
      } catch (e, stack) {
        _log.w('Failed to enrich metadata: $e');
        _log.w('Stack trace: $stack');
      }

      if (await _shouldAbort('during metadata enrichment')) {
        return false;
      }
    }

    _log.d('Track coverUrl after enrichment: ${trackToDownload.coverUrl}');
    return true;
  }

  Future<void> _resolveOutputTarget() async {
    quality = item.qualityOverride ?? n.state.audioQuality;
    if (quality == 'DEFAULT') quality = n.state.audioQuality;
    final isSafMode = n._isSafMode(settings);
    final relativeOutputDir = isSafMode
        ? await n._buildRelativeOutputDir(
            trackToDownload,
            settings.folderOrganization,
            separateSingles: settings.separateSingles,
            albumFolderStructure: settings.albumFolderStructure,
            createPlaylistFolder: settings.createPlaylistFolder,
            useAlbumArtistForFolders: settings.useAlbumArtistForFolders,
            usePrimaryArtistOnly: settings.usePrimaryArtistOnly,
            filterContributingArtistsInAlbumArtist:
                settings.filterContributingArtistsInAlbumArtist,
            playlistName: item.playlistName,
          )
        : '';
    final initialOutputDir = isSafMode
        ? relativeOutputDir
        : await n._buildOutputDir(
            trackToDownload,
            settings.folderOrganization,
            separateSingles: settings.separateSingles,
            albumFolderStructure: settings.albumFolderStructure,
            createPlaylistFolder: settings.createPlaylistFolder,
            useAlbumArtistForFolders: settings.useAlbumArtistForFolders,
            usePrimaryArtistOnly: settings.usePrimaryArtistOnly,
            filterContributingArtistsInAlbumArtist:
                settings.filterContributingArtistsInAlbumArtist,
            playlistName: item.playlistName,
          );
    effectiveOutputDir = isSafMode
        ? n._sanitizeSafRelativeDir(initialOutputDir)
        : initialOutputDir;
    effectiveSafMode = isSafMode;

    safOutputExt = n._determineOutputExt(quality, item.service);
    final baseFilenameFormat = n._shouldTreatAsSingleRelease(trackToDownload)
        ? n.state.singleFilenameFormat
        : n.state.filenameFormat;
    effectiveFilenameFormat = n._filenameFormatForItem(
      item,
      baseFilenameFormat,
    );
    qualityVariantCollisionOnly =
        item.preserveQualityVariant &&
        !_explicitQualityFilenameTokenPattern.hasMatch(baseFilenameFormat);
    if (isSafMode) {
      final builtSafFileName = await n._buildSafFileNameForItem(
        item,
        trackToDownload,
        filenameFormat: effectiveFilenameFormat,
        quality: quality,
        outputExt: safOutputExt,
      );
      safFileName = builtSafFileName;
      safBaseName = builtSafFileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    }
    finalSafFileName = safFileName;
  }

  void _resolveExtensionFlags() {
    extensionState = n.ref.read(extensionProvider);
    selectedExtensionDownloadProvider =
        settings.useExtensionProviders &&
        extensionState.extensions.any(
          (e) =>
              e.enabled &&
              e.hasDownloadProvider &&
              e.id.toLowerCase() == item.service.toLowerCase(),
        );
    final trackSource = (trackToDownload.source ?? '').trim().toLowerCase();
    shouldSkipExtensionSongLinkPrelookup =
        trackSource.isNotEmpty &&
        extensionState.extensions.any(
          (e) =>
              e.enabled &&
              e.hasMetadataProvider &&
              e.id.toLowerCase() == trackSource,
        );
    final hasActiveExtensions = extensionState.extensions.any((e) => e.enabled);
    useExtensions = settings.useExtensionProviders && hasActiveExtensions;
  }

  Future<bool> _resolveTrackIdentifiers() async {
    deezerTrackId = await n._resolveDeezerIdFromKnownOrIsrc(
      trackToDownload,
      item.id,
      lookupContext: 'ISRC',
    );
    if (await _shouldAbort('during Deezer ISRC lookup')) {
      return false;
    }

    // For tidal:/qobuz: tracks without ISRC, resolve ISRC from provider
    // API directly (faster than SongLink and avoids rate limits).
    final providerResolved = await n._resolveDeezerIdViaProviderIfNeeded(
      trackToDownload,
      deezerTrackId,
      item.id,
    );
    trackToDownload = providerResolved.track;
    deezerTrackId = providerResolved.deezerTrackId;
    if (await _shouldAbort('during provider ISRC resolution')) {
      return false;
    }

    if (!selectedExtensionDownloadProvider &&
        deezerTrackId == null &&
        !shouldSkipExtensionSongLinkPrelookup &&
        trackToDownload.id.isNotEmpty &&
        !trackToDownload.id.startsWith('deezer:') &&
        !trackToDownload.id.startsWith('extension:') &&
        !trackToDownload.id.startsWith('tidal:') &&
        !trackToDownload.id.startsWith('qobuz:')) {
      final spotifyLookup = await n._resolveSpotifyTrackViaDeezer(
        trackToDownload,
      );
      trackToDownload = spotifyLookup.track;
      deezerTrackId ??= spotifyLookup.deezerTrackId;

      if (await _shouldAbort('during SongLink availability lookup')) {
        return false;
      }
    } else if (selectedExtensionDownloadProvider && deezerTrackId == null) {
      _log.d(
        'Skipping Flutter SongLink Deezer prelookup for extension provider: ${item.service}',
      );
    } else if (shouldSkipExtensionSongLinkPrelookup && deezerTrackId == null) {
      _log.d(
        'Skipping Flutter SongLink Deezer prelookup for extension-sourced track; backend metadata enrichment will resolve identifiers first',
      );
    }
    return true;
  }

  Future<Map<String, dynamic>> _invokeDownload({
    required bool useSaf,
    required String outputDir,
  }) async {
    final outputExt = safOutputExt;
    final shouldUseExtensions = useExtensions;
    final shouldUseFallback = n.state.autoFallback;

    if (shouldUseExtensions) {
      _log.d('Using extension providers for download');
      _log.d(
        'Quality: $quality${item.qualityOverride != null ? ' (override)' : ''}',
      );
    } else if (shouldUseFallback) {
      _log.d('Using auto-fallback mode');
      _log.d(
        'Quality: $quality${item.qualityOverride != null ? ' (override)' : ''}',
      );
    }

    if (!useSaf) {
      await n._ensureDirExists(outputDir, label: 'Output folder');
    }

    _log.d('Output dir: $outputDir');

    final payload = n._buildDownloadRequestPayload(
      track: trackToDownload,
      item: item,
      settings: settings,
      extensionState: extensionState,
      quality: quality,
      filenameFormat: effectiveFilenameFormat,
      outputDir: outputDir,
      outputExt: outputExt,
      useSaf: useSaf,
      safFileName: safFileName,
      deezerTrackId: deezerTrackId,
      genre: genre,
      label: label,
      copyright: copyright,
      qualityVariantCollisionOnly: qualityVariantCollisionOnly,
    );

    return PlatformBridge.downloadByStrategy(
      payload: payload,
      useExtensions: shouldUseExtensions,
      useFallback: shouldUseFallback,
    );
  }

  Future<bool> _downloadAndMaybeFallback() async {
    result = await _invokeDownload(
      useSaf: effectiveSafMode,
      outputDir: effectiveOutputDir,
    );

    if (result['success'] != true && n._isStorageWriteFailure(result)) {
      if (n._isLocallyCancelled(item.id)) {
        _log.i('Download was cancelled before storage fallback, skipping');
        return false;
      }
      _log.w('Storage write failed, retrying with a writable app folder');
      try {
        await n._activateAppFolderStorageFallback(
          failedOutputDir: effectiveSafMode ? null : effectiveOutputDir,
        );
        final fallbackDir =
            appOutputDir ??
            await n._buildOutputDir(
              trackToDownload,
              settings.folderOrganization,
              separateSingles: settings.separateSingles,
              albumFolderStructure: settings.albumFolderStructure,
              createPlaylistFolder: settings.createPlaylistFolder,
              useAlbumArtistForFolders: settings.useAlbumArtistForFolders,
              usePrimaryArtistOnly: settings.usePrimaryArtistOnly,
              filterContributingArtistsInAlbumArtist:
                  settings.filterContributingArtistsInAlbumArtist,
              playlistName: item.playlistName,
            );
        appOutputDir = fallbackDir;
        final fallbackResult = await _invokeDownload(
          useSaf: false,
          outputDir: fallbackDir,
        );
        result = fallbackResult;
        if (fallbackResult['success'] == true) {
          effectiveSafMode = false;
          effectiveOutputDir = fallbackDir;
          finalSafFileName = null;
        }
      } catch (e) {
        _log.e('App-folder storage fallback failed: $e');
      }
    }
    return true;
  }

  Future<bool> _handleDownloadSuccess() async {
    filePath = result['file_path'] as String?;
    final reportedFileName = result['file_name'] as String?;
    if (effectiveSafMode &&
        reportedFileName != null &&
        reportedFileName.isNotEmpty) {
      finalSafFileName = reportedFileName;
    }

    wasExisting = result['already_exists'] == true;
    if (wasExisting) {
      _log.i('File already exists in library: $filePath');
    }

    _log.i('Download success, file: $filePath');

    final actualBitDepth = result['actual_bit_depth'] as int?;
    final actualSampleRate = result['actual_sample_rate'] as int?;
    actualQuality = quality;

    if (actualBitDepth != null && actualBitDepth > 0) {
      final sampleRateKHz = actualSampleRate != null && actualSampleRate > 0
          ? (actualSampleRate / 1000).toStringAsFixed(
              actualSampleRate % 1000 == 0 ? 0 : 1,
            )
          : '?';
      actualQuality = '$actualBitDepth-bit/${sampleRateKHz}kHz';
      _log.i('Actual quality: $actualQuality');
    }

    final actualService =
        ((result['service'] as String?)?.toLowerCase()) ??
        item.service.toLowerCase();
    resultOutputExt = n._downloadResultOutputExt(result, filePath: filePath);
    final resultAudioFormat = normalizeAudioFormatValue(
      result['audio_codec']?.toString() ??
          result['actual_audio_codec']?.toString(),
    );
    final resultIsLossyAudio = isLossyAudioFormat(resultAudioFormat);
    final requiresContainerConversion =
        result['requires_container_conversion'] == true ||
        result['requiresContainerConversion'] == true ||
        (!resultIsLossyAudio &&
            n._shouldRequestContainerConversion(actualService, safOutputExt));
    final preferredOutputExt = n._extensionPreferredOutputExt(actualService);
    shouldPreserveNativeM4a =
        !requiresContainerConversion &&
        (resultOutputExt == '.m4a' ||
            resultOutputExt == '.mp4' ||
            preferredOutputExt == '.m4a' ||
            preferredOutputExt == '.mp4' ||
            n._extensionPreservesNativeOutputExt(actualService, '.m4a') ||
            n._extensionPreservesNativeOutputExt(actualService, '.mp4'));
    decryptionDescriptor = DownloadDecryptionDescriptor.fromDownloadResult(
      result,
    );
    trackToDownload = n._buildTrackForMetadataEmbedding(
      trackToDownload,
      result,
      resolvedAlbumArtist,
    );
    _log.d('Track coverUrl after download result: ${trackToDownload.coverUrl}');

    if (!await _decryptIfNeeded()) {
      return false;
    }
    await _applyFormatHandling(actualService);

    if (await _shouldAbort(
      'during finalization',
      deleteFileOnAbort: filePath,
    )) {
      return false;
    }

    await _recoverSafUriIfNeeded();

    final hookInput = filePath;
    if (hookInput != null) {
      final postProcessedPath = await n._runPostProcessingHooks(
        hookInput,
        trackToDownload,
      );
      if (postProcessedPath != null && postProcessedPath.isNotEmpty) {
        filePath = postProcessedPath;
        result['file_path'] = postProcessedPath;
      }
    }

    final variantInput = filePath;
    if (variantInput != null && item.preserveQualityVariant) {
      final variantOutcome = await n._finalizeQualityVariantFilename(
        item: item,
        result: result,
        filePath: variantInput,
        storageMode: effectiveSafMode ? 'saf' : 'app',
        downloadTreeUri: settings.downloadTreeUri,
        safRelativeDir: effectiveOutputDir,
        fileName: finalSafFileName ?? safFileName,
        collisionOnly: qualityVariantCollisionOnly,
      );
      filePath = variantOutcome.filePath;
      if (variantOutcome.fileName != null) {
        finalSafFileName = variantOutcome.fileName;
      }
      if (variantOutcome.metadata != null) {
        probedFinalMetadata = variantOutcome.metadata;
      }
    }

    if (normalizeOptionalString(filePath) == null) {
      throw StateError(
        'Download backend reported success without a final file path',
      );
    }

    final lrcTarget = filePath;
    if (effectiveSafMode && lrcTarget != null && isContentUri(lrcTarget)) {
      await n._saveExternalLrc(
        result: result,
        settings: settings,
        extensionState: extensionState,
        track: trackToDownload,
        service: item.service,
        filePath: lrcTarget,
        storageMode: 'saf',
        downloadTreeUri: settings.downloadTreeUri,
        safRelativeDir: effectiveOutputDir,
        resolveBaseName: () async {
          final currentFinalName = finalSafFileName;
          return currentFinalName != null
              ? currentFinalName.replaceFirst(RegExp(r'\.[^.]+$'), '')
              : safBaseName ??
                    await PlatformBridge.sanitizeFilename(
                      '${trackToDownload.artistName} - ${trackToDownload.name}',
                    );
        },
        onFetchError: (e) =>
            _log.w('Failed to fetch lyrics for external LRC: $e'),
      );
    }

    final rgPath = filePath;
    // Album ReplayGain: update the accumulator path to the final file
    // location.  For SAF downloads the metadata was embedded on a temp
    // copy, so the stored path still points there.  Replace it with the
    // actual output path (SAF content URI or local path) so the later
    // album-gain writer targets the correct file.
    if (rgPath != null) {
      n._updateAlbumRgFilePath(trackToDownload, rgPath);
    }
    // Album ReplayGain: check if all album tracks are now complete and,
    // if so, compute and write album gain/peak to every track file.
    try {
      await n._checkAndWriteAlbumReplayGain(trackToDownload);
    } catch (e) {
      _log.w('Album ReplayGain check failed: $e');
    }

    await _persistCompletionAndNotify();
    return true;
  }

  Future<bool> _decryptIfNeeded() async {
    final path = filePath;
    final descriptor = decryptionDescriptor;
    if (wasExisting || descriptor == null || path == null) {
      return true;
    }
    _log.i(
      'Encrypted stream detected, decrypting via ${descriptor.normalizedStrategy}...',
    );
    n.updateItemStatus(item.id, DownloadStatus.finalizing, progress: 0.9);

    final isSafSource = effectiveSafMode && isContentUri(path);
    final decryptOutcome = await n._finalizeDecryption(
      result: result,
      filePath: path,
      storageMode: effectiveSafMode ? 'saf' : 'app',
      downloadTreeUri: settings.downloadTreeUri,
      safRelativeDir: effectiveOutputDir,
      baseName: safBaseName ?? 'track',
      extFallback: '.flac',
      repairAc4: true,
    );
    if (decryptOutcome.path == null) {
      final String errorMsg;
      switch (decryptOutcome.failStage) {
        case DownloadQueueNotifier._decryptStageSafAccess:
          _log.e('Failed to copy encrypted SAF file to temp for decrypt');
          errorMsg = 'Failed to access encrypted SAF file';
          break;
        case DownloadQueueNotifier._decryptStageSafWrite:
          _log.e('Failed to write decrypted stream back to SAF');
          errorMsg = 'Failed to write decrypted file to storage';
          break;
        default:
          _log.e(
            isSafSource
                ? 'FFmpeg decrypt failed for SAF file'
                : 'FFmpeg decrypt failed for local file',
          );
          errorMsg = 'Failed to decrypt encrypted stream';
          break;
      }
      n.updateItemStatus(
        item.id,
        DownloadStatus.failed,
        error: errorMsg,
        errorType: DownloadErrorType.unknown,
      );
      return false;
    }
    filePath = decryptOutcome.path;
    if (decryptOutcome.newFileName != null) {
      finalSafFileName = decryptOutcome.newFileName;
    }
    _log.i(
      isSafSource ? 'SAF decryption completed' : 'Local decryption completed',
    );
    return true;
  }

  Future<void> _applyFormatHandling(String actualService) async {
    final path = filePath;
    if (path == null) return;
    final isContentUriPath = isContentUri(path);
    final mimeType = isContentUriPath ? await n._getSafMimeType(path) : null;
    final isM4aFile =
        (path.endsWith('.m4a') ||
        path.endsWith('.mp4') ||
        resultOutputExt == '.m4a' ||
        resultOutputExt == '.mp4' ||
        (mimeType != null && mimeType.contains('mp4')));
    final isFlacFile =
        (path.endsWith('.flac') ||
        resultOutputExt == '.flac' ||
        (mimeType != null && mimeType.contains('flac')));
    final shouldForceDashSafM4aHandling =
        !wasExisting &&
        isContentUriPath &&
        effectiveSafMode &&
        n._downloadProviderReplacesLegacyProvider(actualService, 'tidal') &&
        path.endsWith('.flac') &&
        (mimeType == null || mimeType.contains('flac'));

    if (shouldForceDashSafM4aHandling) {
      _log.w(
        'SAF file is labeled FLAC but backend returned DASH/M4A stream; converting it back to FLAC.',
      );
    }

    if (isM4aFile || shouldForceDashSafM4aHandling) {
      if (isContentUriPath && effectiveSafMode) {
        if (quality == 'HIGH') {
          await _convertSafM4aToLossy(path);
        } else if (shouldPreserveNativeM4a) {
          await _preserveSafNativeM4a(path);
        } else {
          await _convertSafM4aToFlac(path);
        }
      } else {
        if (quality == 'HIGH') {
          await _convertLocalM4aToLossy(path);
        } else if (shouldPreserveNativeM4a) {
          await _preserveLocalNativeM4a(path);
        } else {
          await _convertLocalM4aToFlac(path);
        }
      }
    } else if (metadataEmbeddingEnabled &&
        isContentUriPath &&
        effectiveSafMode &&
        !isM4aFile &&
        !wasExisting) {
      await _embedSafNonM4a(path);
    } else if (metadataEmbeddingEnabled &&
        !isContentUriPath &&
        !effectiveSafMode &&
        isFlacFile &&
        !wasExisting &&
        decryptionDescriptor != null) {
      await _embedLocalFlacAfterDecrypt(path);
    }
  }

  Future<void> _convertSafM4aToLossy(String currentFilePath) async {
    final tidalHighFormat = settings.tidalHighFormat;
    _log.i(
      'Lossy 320kbps quality (SAF), converting M4A to $tidalHighFormat...',
    );

    final format = lossyFormatForSetting(tidalHighFormat);
    final displayFormat = displayFormatForLossyFormat(format);
    final newExt = lossyExtensionForFormat(format);
    final newFileName = '${safBaseName ?? 'track'}$newExt';
    var opStarted = false;
    var convertFailed = false;
    try {
      final newUri = await n._replaceSafFileVia(
        uri: currentFilePath,
        treeUri: settings.downloadTreeUri,
        relativeDir: effectiveOutputDir,
        op: (tempPath, addCleanup) async {
          opStarted = true;
          n.updateItemStatus(
            item.id,
            DownloadStatus.finalizing,
            progress: 0.95,
          );
          final convertedPath = await FFmpegService.convertM4aToLossy(
            tempPath,
            format: format,
            bitrate: tidalHighFormat,
            deleteOriginal: false,
          );
          if (convertedPath == null) {
            convertFailed = true;
            return null;
          }
          addCleanup(convertedPath);
          _log.i(
            'Successfully converted M4A to $format (temp): $convertedPath',
          );
          _log.i('Embedding metadata to $format...');
          n.updateItemStatus(
            item.id,
            DownloadStatus.finalizing,
            progress: 0.99,
          );

          await _embedFinalMetadata(
            convertedPath,
            format: metadataFormatForLossyFormat(format),
            rebuildTrack: false,
          );

          return (convertedPath, newFileName);
        },
      );

      if (newUri != null) {
        filePath = newUri;
        finalSafFileName = newFileName;
        final bitrateDisplay = tidalHighFormat.contains('_')
            ? '${tidalHighFormat.split('_').last}kbps'
            : '320kbps';
        actualQuality = '$displayFormat $bitrateDisplay';
      } else if (convertFailed) {
        _log.w('M4A to $format conversion failed, keeping M4A file');
        actualQuality = 'AAC 320kbps';
      } else if (opStarted) {
        _log.w('Failed to write converted $format to SAF, keeping M4A');
        actualQuality = 'AAC 320kbps';
      }
    } catch (e) {
      _log.w('SAF M4A conversion failed: $e');
      actualQuality = 'AAC 320kbps';
    }
  }

  Future<void> _preserveSafNativeM4a(String currentFilePath) async {
    // Decrypted streams are already in their final format.
    // Converting e.g. eac3 M4A to FLAC would produce fake upscaled output.
    _log.d('M4A/MP4 file detected (SAF), preserving native container...');
    final preserveExt = currentFilePath.toLowerCase().endsWith('.mp4')
        ? '.mp4'
        : '.m4a';
    final newFileName = '${safBaseName ?? 'track'}$preserveExt';
    var opStarted = false;
    try {
      final newUri = await n._replaceSafFileVia(
        uri: currentFilePath,
        treeUri: settings.downloadTreeUri,
        relativeDir: effectiveOutputDir,
        op: (tempPath, _) async {
          opStarted = true;
          if (metadataEmbeddingEnabled) {
            n.updateItemStatus(
              item.id,
              DownloadStatus.finalizing,
              progress: 0.99,
            );
            await _embedFinalMetadata(
              tempPath,
              format: 'm4a',
              writeExternalLrc: false,
            );
          }
          return (tempPath, newFileName);
        },
      );

      if (newUri != null) {
        filePath = newUri;
        finalSafFileName = newFileName;
      } else if (opStarted) {
        _log.w('Failed to write M4A to SAF, keeping original');
      }
    } catch (e) {
      _log.w('SAF native M4A handling failed: $e');
    }
  }

  Future<void> _convertSafM4aToFlac(String currentFilePath) async {
    _log.d('M4A file detected (SAF), converting to FLAC...');
    String? branch;
    String? producedFileName;
    try {
      final newUri = await n._replaceSafFileVia(
        uri: currentFilePath,
        treeUri: settings.downloadTreeUri,
        relativeDir: effectiveOutputDir,
        op: (tempPath, addCleanup) async {
          final length = await File(tempPath).length();
          if (length < 1024) {
            _log.w('Temp M4A is too small (<1KB), skipping conversion');
            branch = 'skip';
            return null;
          }
          final codec = await FFmpegService.probePrimaryAudioCodec(tempPath);
          final isAlreadyNativeFlac =
              codec == 'flac' && await FFmpegService.isNativeFlacFile(tempPath);
          if (!FFmpegService.isLosslessAudioCodec(codec)) {
            _log.d(
              'Preserving native container; audio codec is ${codec ?? 'unknown'}, '
              'no FLAC container conversion needed.',
            );
            branch = 'preserve';
            final preserveExt = resultOutputExt == '.mp4' ? '.mp4' : '.m4a';
            final newFileName = '${safBaseName ?? 'track'}$preserveExt';
            producedFileName = newFileName;
            return (tempPath, newFileName);
          } else if (isAlreadyNativeFlac) {
            _log.d(
              'Native FLAC payload detected in SAF temp file; '
              'publishing as FLAC and embedding metadata.',
            );
            branch = 'nativeFlac';
            await _embedFinalMetadata(
              tempPath,
              format: 'flac',
              writeExternalLrc: false,
            );

            final newFileName = '${safBaseName ?? 'track'}.flac';
            producedFileName = newFileName;
            return (tempPath, newFileName);
          } else {
            n.updateItemStatus(
              item.id,
              DownloadStatus.finalizing,
              progress: 0.95,
            );
            final flacPath = await FFmpegService.convertM4aToFlac(tempPath);
            if (flacPath == null) {
              _log.w('FFmpeg conversion returned null, keeping M4A file');
              branch = 'convertFailed';
              return null;
            }
            addCleanup(flacPath);
            _log.d('Converted to FLAC (temp): $flacPath');
            _log.d('Embedding metadata and cover to converted FLAC...');
            await _embedFinalMetadata(
              flacPath,
              format: 'flac',
              writeExternalLrc: false,
            );

            final newFileName = '${safBaseName ?? 'track'}.flac';
            branch = 'convert';
            producedFileName = newFileName;
            return (flacPath, newFileName);
          }
        },
      );

      if (newUri != null) {
        filePath = newUri;
        finalSafFileName = producedFileName;
      } else if (branch == 'nativeFlac') {
        _log.w('Failed to write native FLAC to SAF');
      } else if (branch == 'convert') {
        _log.w('Failed to write FLAC to SAF, keeping M4A');
      }
    } catch (e) {
      _log.w('SAF M4A->FLAC conversion failed: $e');
    }
  }

  Future<void> _convertLocalM4aToLossy(String currentFilePath) async {
    final tidalHighFormat = settings.tidalHighFormat;
    _log.i(
      'Lossy 320kbps quality download, converting M4A to $tidalHighFormat...',
    );

    try {
      n.updateItemStatus(item.id, DownloadStatus.finalizing, progress: 0.95);

      final format = lossyFormatForSetting(tidalHighFormat);
      final displayFormat = displayFormatForLossyFormat(format);
      final convertedPath = await FFmpegService.convertM4aToLossy(
        currentFilePath,
        format: format,
        bitrate: tidalHighFormat,
        deleteOriginal: true,
      );

      if (convertedPath != null) {
        filePath = convertedPath;
        final bitrateDisplay = tidalHighFormat.contains('_')
            ? '${tidalHighFormat.split('_').last}kbps'
            : '320kbps';
        actualQuality = '$displayFormat $bitrateDisplay';
        _log.i('Successfully converted M4A to $format: $convertedPath');

        _log.i('Embedding metadata to $format...');
        n.updateItemStatus(item.id, DownloadStatus.finalizing, progress: 0.99);

        await _embedFinalMetadata(
          convertedPath,
          format: metadataFormatForLossyFormat(format),
          rebuildTrack: false,
        );
        _log.d('Metadata embedded successfully');
      } else {
        _log.w('M4A to $format conversion failed, keeping M4A file');
        actualQuality = 'AAC 320kbps';
      }
    } catch (e) {
      _log.w('M4A conversion process failed: $e, keeping M4A file');
      actualQuality = 'AAC 320kbps';
    }
  }

  Future<void> _preserveLocalNativeM4a(String currentFilePath) async {
    _log.d('M4A/MP4 file detected, preserving native container...');

    try {
      var targetPath = currentFilePath;
      final file = File(targetPath);
      if (!await file.exists()) {
        _log.e('File does not exist at path: $filePath');
      } else {
        if (!(targetPath.toLowerCase().endsWith('.m4a') ||
            targetPath.toLowerCase().endsWith('.mp4'))) {
          final renamedPath = targetPath.replaceAll(
            RegExp(r'\.[^.]+$'),
            '.m4a',
          );
          final finalRenamedPath = renamedPath == targetPath
              ? '$targetPath.m4a'
              : renamedPath;
          await file.rename(finalRenamedPath);
          targetPath = finalRenamedPath;
          filePath = finalRenamedPath;
        } else {
          filePath = targetPath;
        }

        if (metadataEmbeddingEnabled) {
          n.updateItemStatus(
            item.id,
            DownloadStatus.finalizing,
            progress: 0.99,
          );
          await _embedFinalMetadata(targetPath, format: 'm4a');
        }
      }
    } catch (e) {
      _log.w('Native M4A handling failed: $e');
    }
  }

  Future<void> _convertLocalM4aToFlac(String currentFilePath) async {
    _log.d(
      'M4A file detected (Hi-Res DASH stream), attempting conversion to FLAC...',
    );

    try {
      final file = File(currentFilePath);
      if (!await file.exists()) {
        _log.e('File does not exist at path: $filePath');
      } else {
        final length = await file.length();
        _log.i('File size before conversion: ${length / 1024} KB');

        if (length < 1024) {
          _log.w(
            'File is too small (<1KB), skipping conversion. Download might be corrupt.',
          );
        } else {
          final codec = await FFmpegService.probePrimaryAudioCodec(
            currentFilePath,
          );
          final isAlreadyNativeFlac =
              codec == 'flac' &&
              await FFmpegService.isNativeFlacFile(currentFilePath);
          if (!FFmpegService.isLosslessAudioCodec(codec)) {
            _log.d(
              'Preserving native container; audio codec is ${codec ?? 'unknown'}, '
              'no FLAC container conversion needed.',
            );
          } else if (isAlreadyNativeFlac) {
            _log.d(
              'Native FLAC payload detected; ensuring .flac '
              'extension and embedding metadata.',
            );
            var flacPath = currentFilePath;
            if (!currentFilePath.toLowerCase().endsWith('.flac')) {
              final renamedPath = currentFilePath.replaceAll(
                RegExp(r'\.[^.]+$'),
                '.flac',
              );
              final targetPath = renamedPath == currentFilePath
                  ? '$currentFilePath.flac'
                  : renamedPath;
              await File(currentFilePath).rename(targetPath);
              flacPath = targetPath;
              filePath = targetPath;
            }

            await _embedFinalMetadata(flacPath, format: 'flac');
          } else {
            n.updateItemStatus(
              item.id,
              DownloadStatus.finalizing,
              progress: 0.95,
            );
            final flacPath = await FFmpegService.convertM4aToFlac(
              currentFilePath,
            );

            if (flacPath != null) {
              filePath = flacPath;
              _log.d('Converted to FLAC: $flacPath');

              _log.d('Embedding metadata and cover to converted FLAC...');
              try {
                final backendGenre = result['genre'] as String?;
                final backendLabel = result['label'] as String?;
                final backendCopyright = result['copyright'] as String?;
                if (backendGenre != null ||
                    backendLabel != null ||
                    backendCopyright != null) {
                  _log.d(
                    'Extended metadata from backend - Genre: $backendGenre, Label: $backendLabel, Copyright: $backendCopyright',
                  );
                }

                await _embedFinalMetadata(flacPath, format: 'flac');
                _log.d('Metadata and cover embedded successfully');
              } catch (e) {
                _log.w('Warning: Failed to embed metadata/cover: $e');
              }
            } else {
              _log.w('FFmpeg conversion returned null, keeping M4A file');
            }
          }
        }
      }
    } catch (e) {
      _log.w('FFmpeg conversion process failed: $e, keeping M4A file');
    }
  }

  Future<void> _embedSafNonM4a(String currentFilePath) async {
    final isOpusFile =
        currentFilePath.endsWith('.opus') ||
        currentFilePath.endsWith('.ogg') ||
        resultOutputExt == '.opus' ||
        resultOutputExt == '.ogg';
    final isMp3File =
        currentFilePath.endsWith('.mp3') || resultOutputExt == '.mp3';
    final ext = isOpusFile
        ? (resultOutputExt == '.ogg' ? '.ogg' : '.opus')
        : isMp3File
        ? '.mp3'
        : '.flac';
    final formatName = isOpusFile
        ? 'Opus'
        : isMp3File
        ? 'MP3'
        : 'FLAC';
    _log.d(
      'SAF $formatName detected, embedding metadata and cover via temp file...',
    );
    final newFileName = '${safBaseName ?? 'track'}$ext';
    var opStarted = false;
    try {
      final newUri = await n._replaceSafFileVia(
        uri: currentFilePath,
        treeUri: settings.downloadTreeUri,
        relativeDir: effectiveOutputDir,
        op: (tempPath, _) async {
          opStarted = true;
          n.updateItemStatus(
            item.id,
            DownloadStatus.finalizing,
            progress: 0.99,
          );

          // writeExternalLrc: false — tempPath lives in the cache dir,
          // so a sidecar .lrc written next to it would be orphaned;
          // the SAF .lrc is written by _saveExternalLrc after publish,
          // reusing the LRC fetched here via result['lyrics_lrc'].
          final embedFormat = isMp3File
              ? 'mp3'
              : isOpusFile
              ? 'opus'
              : 'flac';
          final fetchedLrc = await _embedFinalMetadata(
            tempPath,
            format: embedFormat,
            writeExternalLrc: false,
          );
          final existingLrc = result['lyrics_lrc'] as String?;
          if ((existingLrc == null || existingLrc.isEmpty) &&
              fetchedLrc != null &&
              fetchedLrc.isNotEmpty) {
            result['lyrics_lrc'] = fetchedLrc;
          }

          // Probe quality from the local temp now: the same probe on
          // the published content:// URI would copy the whole file
          // out of SAF again just to read a few header bytes.
          try {
            probedFinalMetadata = await PlatformBridge.readFileMetadata(
              tempPath,
            );
          } catch (_) {}

          return (tempPath, newFileName);
        },
      );

      if (newUri != null) {
        filePath = newUri;
        finalSafFileName = newFileName;
        _log.d('SAF $formatName metadata embedding completed');
      } else if (opStarted) {
        _log.w('Failed to write metadata-updated $formatName back to SAF');
      }
    } catch (e) {
      _log.w('SAF $formatName metadata embedding failed: $e');
    }
  }

  Future<void> _embedLocalFlacAfterDecrypt(String currentFilePath) async {
    _log.d(
      'Local FLAC after decrypt detected, embedding metadata and cover...',
    );
    try {
      n.updateItemStatus(item.id, DownloadStatus.finalizing, progress: 0.99);

      await _embedFinalMetadata(currentFilePath, format: 'flac');
      _log.d('Local FLAC metadata embedding completed');
    } catch (e) {
      _log.w('Local FLAC metadata embedding failed: $e');
    }
  }

  /// Final metadata embed shared by every publish branch. Backend-provided
  /// genre/label/copyright win over the Deezer extended-metadata lookup.
  /// [rebuildTrack] is false only for the lossy-HIGH branches, which embed
  /// the track as-is instead of re-merging the download result into it.
  Future<String?> _embedFinalMetadata(
    String path, {
    required String format,
    bool writeExternalLrc = true,
    bool rebuildTrack = true,
  }) {
    final track = rebuildTrack
        ? n._buildTrackForMetadataEmbedding(
            trackToDownload,
            result,
            resolvedAlbumArtist,
          )
        : trackToDownload;
    return n._embedMetadataToFile(
      path,
      track,
      format: format,
      genre: (result['genre'] as String?) ?? genre,
      label: (result['label'] as String?) ?? label,
      copyright: result['copyright'] as String?,
      downloadService: item.service,
      writeExternalLrc: writeExternalLrc,
    );
  }

  Future<void> _recoverSafUriIfNeeded() async {
    final path = filePath;
    if (!effectiveSafMode ||
        path == null ||
        path.isEmpty ||
        isContentUri(path) ||
        settings.downloadTreeUri.isEmpty) {
      return;
    }
    final fallbackName = (finalSafFileName ?? safFileName ?? '').trim();
    if (fallbackName.isNotEmpty) {
      try {
        final resolved = await PlatformBridge.resolveSafFile(
          treeUri: settings.downloadTreeUri,
          relativeDir: effectiveOutputDir,
          fileName: fallbackName,
        );
        final resolvedUri = (resolved['uri'] as String? ?? '').trim();
        final resolvedRelativeDir = (resolved['relative_dir'] as String? ?? '')
            .trim();
        if (resolvedUri.isNotEmpty && isContentUri(resolvedUri)) {
          _log.w('Recovered SAF URI from transient path: $path');
          filePath = resolvedUri;
          finalSafFileName = fallbackName;
          if (resolvedRelativeDir.isNotEmpty) {
            effectiveOutputDir = resolvedRelativeDir;
          }
        } else {
          _log.w(
            'Failed to recover SAF URI (fileName=$fallbackName, dir=$effectiveOutputDir)',
          );
        }
      } catch (e) {
        _log.w('SAF URI recovery failed: $e');
      }
    } else {
      _log.w(
        'SAF download returned non-URI path without filename metadata: $filePath',
      );
    }
  }

  Future<void> _persistCompletionAndNotify() async {
    final path = filePath;
    final historyNotifier = n.ref.read(downloadHistoryProvider.notifier);
    final existingInHistory = path == null
        ? null
        : await historyNotifier.getByFilePathAsync(path);

    if (wasExisting && existingInHistory != null) {
      _log.i(
        'Track file already exists in library; refreshing its history metadata',
      );
    }

    if (path != null) {
      final historyFilePath = path;
      final backendBitDepth = result['actual_bit_depth'] as int?;
      final backendSampleRate = result['actual_sample_rate'] as int?;
      final backendFormat =
          normalizeAudioFormatValue(
            result['audio_codec']?.toString() ?? result['format']?.toString(),
          ) ??
          normalizeAudioFormatValue(audioFormatForPath(path));
      final backendBitrateKbps = readPositiveBitrateKbps(
        result['bitrate'] ?? result['actual_bitrate'],
      );
      final backendGenre = result['genre'] as String?;
      final backendLabel = result['label'] as String?;
      final backendCopyright = result['copyright'] as String?;
      final effectiveGenre =
          normalizeOptionalString(backendGenre) ??
          normalizeOptionalString(genre) ??
          normalizeOptionalString(existingInHistory?.genre);
      final effectiveLabel =
          normalizeOptionalString(backendLabel) ??
          normalizeOptionalString(label) ??
          normalizeOptionalString(existingInHistory?.label);
      final effectiveCopyright =
          normalizeOptionalString(backendCopyright) ??
          normalizeOptionalString(copyright) ??
          normalizeOptionalString(existingInHistory?.copyright);

      int? finalBitDepth = backendBitDepth;
      int? finalSampleRate = backendSampleRate;
      String? finalFormat = backendFormat;
      int? finalBitrateKbps = backendBitrateKbps;
      final lowerFilePath = path.toLowerCase();
      final canProbeFinalMetadata =
          path.startsWith('content://') ||
          lowerFilePath.endsWith('.flac') ||
          lowerFilePath.endsWith('.m4a') ||
          lowerFilePath.endsWith('.mp4') ||
          lowerFilePath.endsWith('.aac') ||
          lowerFilePath.endsWith('.mp3') ||
          lowerFilePath.endsWith('.opus') ||
          lowerFilePath.endsWith('.ogg');

      if (canProbeFinalMetadata) {
        try {
          final probed = probedFinalMetadata;
          final metadata = (probed != null && probed['error'] == null)
              ? probed
              : await PlatformBridge.readFileMetadata(path);
          if (metadata['error'] == null) {
            final probedBitDepth = metadata['bit_depth'] is num
                ? (metadata['bit_depth'] as num).toInt()
                : int.tryParse(metadata['bit_depth']?.toString() ?? '');
            final probedSampleRate = metadata['sample_rate'] is num
                ? (metadata['sample_rate'] as num).toInt()
                : int.tryParse(metadata['sample_rate']?.toString() ?? '');

            if (probedBitDepth != null && probedBitDepth > 0) {
              finalBitDepth = probedBitDepth;
            }
            if (probedSampleRate != null && probedSampleRate > 0) {
              finalSampleRate = probedSampleRate;
            }
            final probedFormat = normalizeAudioFormatValue(
              metadata['audio_codec']?.toString() ??
                  metadata['format']?.toString(),
            );
            if (probedFormat != null) {
              finalFormat = probedFormat;
            }
            final probedBitrateKbps = readPositiveBitrateKbps(
              metadata['bitrate'] ?? metadata['bit_rate'],
            );
            if (probedBitrateKbps != null) {
              finalBitrateKbps = probedBitrateKbps;
            }

            final resolvedQuality = resolveDisplayQuality(
              filePath: path,
              fileName: finalSafFileName,
              detectedFormat: finalFormat,
              bitDepth: finalBitDepth,
              sampleRate: finalSampleRate,
              bitrateKbps: finalBitrateKbps,
              storedQuality: actualQuality,
            );
            if (resolvedQuality != null) {
              actualQuality = resolvedQuality;
            }
          }
        } catch (e) {
          _log.d('Final audio metadata probe failed for $path: $e');
        }
      }

      _log.d('Saving to history - coverUrl: ${trackToDownload.coverUrl}');

      final isLossyOutput =
          isLossyAudioFormat(finalFormat) ||
          lowerFilePath.endsWith('.mp3') ||
          lowerFilePath.endsWith('.opus') ||
          lowerFilePath.endsWith('.ogg');
      final historyBitDepth = isLossyOutput ? null : finalBitDepth;
      final historySampleRate = isLossyOutput ? null : finalSampleRate;
      final historyBitrate = finalBitrateKbps;

      await persistBeforePublishingDownloadCompletion(
        persist: () async {
          if (!settings.saveDownloadHistory) return;
          await n.ref
              .read(downloadHistoryProvider.notifier)
              .addToHistory(
                n._historyItemFromResult(
                  item: item,
                  trackToDownload: trackToDownload,
                  result: result,
                  filePath: historyFilePath,
                  quality: actualQuality,
                  useSaf: effectiveSafMode,
                  downloadTreeUri: settings.downloadTreeUri,
                  safRelativeDir: effectiveOutputDir,
                  safFileName: finalSafFileName ?? safFileName,
                  bitDepth: historyBitDepth,
                  sampleRate: historySampleRate,
                  bitrate: historyBitrate,
                  format: finalFormat,
                  genre: effectiveGenre,
                  label: effectiveLabel,
                  copyright: effectiveCopyright,
                ),
                preserveTrackVariant: item.preserveQualityVariant,
              );
        },
        publish: () {
          n._completedInSession++;
          n.updateItemStatus(
            item.id,
            DownloadStatus.completed,
            progress: 1.0,
            filePath: path,
          );
        },
      );
      await n._notificationService.showDownloadComplete(
        trackName: item.track.name,
        artistName: item.track.artistName,
        completedCount: n._completedInSession,
        totalCount: n._totalQueuedAtStart,
        alreadyInLibrary: wasExisting,
      );
      n.removeItem(item.id);
    }
  }

  Future<bool> _handleBackendFailure() async {
    if (await _shouldAbort('after backend failure')) {
      return false;
    }

    var errorMsg = result['error'] as String? ?? 'Download failed';
    final errorTypeStr = result['error_type'] as String? ?? 'unknown';
    final retryAfterSeconds = readPositiveInt(result['retry_after_seconds']);
    if (retryAfterSeconds != null && retryAfterSeconds > 0) {
      errorMsg = '$errorMsg retry-after: $retryAfterSeconds';
    }
    if (errorTypeStr == 'cancelled') {
      if (n._isPausePending(item.id)) {
        pausedDuringThisRun = true;
        n._requeueItemForPause(item.id);
        _log.i('Download was paused by backend cancellation, re-queueing');
      } else {
        _log.i('Download was cancelled by backend, skipping error handling');
        n.updateItemStatus(item.id, DownloadStatus.skipped);
      }
      return false;
    }

    final backendErrorType = n._downloadErrorTypeFromBackend(errorTypeStr);
    final errorType = backendErrorType == DownloadErrorType.unknown
        ? n._downloadErrorTypeFromMessage(errorMsg)
        : backendErrorType;

    if (errorType == DownloadErrorType.verificationRequired) {
      await n._handleVerificationRequiredDownload(
        item,
        errorMsg,
        result['service'] as String?,
      );
      return false;
    }
    if (errorType == DownloadErrorType.rateLimit &&
        await n._handleRateLimitedDownload(item, errorMsg)) {
      return false;
    }

    _log.e('Download failed: $errorMsg (type: $errorTypeStr)');
    n.updateItemStatus(
      item.id,
      DownloadStatus.failed,
      error: errorMsg,
      errorType: errorType,
    );
    n._failedInSession++;

    try {
      await PlatformBridge.cleanupConnections();
    } catch (e) {
      _log.e('Post-failure connection cleanup failed: $e');
    }
    return true;
  }

  Future<void> _handleRunException(Object e, StackTrace stackTrace) async {
    if (await _shouldAbort('after exception')) {
      return;
    }

    _log.e('Exception: $e', e, stackTrace);

    String errorMsg = e.toString();
    DownloadErrorType errorType = DownloadErrorType.unknown;

    if (isStorageWriteFailure(errorMessage: errorMsg)) {
      try {
        await n._activateAppFolderStorageFallback(
          failedOutputDir: n._isSafMode(settings)
              ? null
              : (effectiveOutputDir.isNotEmpty
                    ? effectiveOutputDir
                    : n.state.outputDir),
        );
        n.updateItemStatus(item.id, DownloadStatus.queued, progress: 0.0);
        _log.w(
          'Storage exception recovered; re-queued ${item.track.name} in the app folder',
        );
        return;
      } catch (fallbackError) {
        _log.e(
          'Could not recover storage exception with app-folder fallback: '
          '$fallbackError',
        );
      }
    }

    if (errorMsg.contains('could not find Deezer equivalent') ||
        errorMsg.contains('track not found on Deezer')) {
      errorMsg = 'Track not found on Deezer (Metadata Unavailable)';
      errorType = DownloadErrorType.notFound;
    } else {
      errorType = n._downloadErrorTypeFromMessage(errorMsg);
    }

    if (errorType == DownloadErrorType.verificationRequired) {
      await n._handleVerificationRequiredDownload(item, errorMsg, item.service);
      return;
    }
    if (errorType == DownloadErrorType.rateLimit &&
        await n._handleRateLimitedDownload(item, errorMsg)) {
      return;
    }

    n.updateItemStatus(
      item.id,
      DownloadStatus.failed,
      error: errorMsg,
      errorType: errorType,
    );
    n._failedInSession++;

    try {
      await PlatformBridge.cleanupConnections();
    } catch (cleanupErr) {
      _log.e('Post-exception connection cleanup failed: $cleanupErr');
    }
  }
}
