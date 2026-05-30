// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, invalid_use_of_internal_member
part of '../download_queue_provider.dart';

extension DownloadQueueNotifierProcessor on DownloadQueueNotifier {
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

  bool _canUseAndroidNativeWorker(AppSettings settings) {
    if (!Platform.isAndroid || !settings.nativeDownloadWorkerEnabled) {
      return false;
    }
    if (!settings.useExtensionProviders) {
      return false;
    }
    if (_isSafMode(settings)) {
      if (settings.downloadTreeUri.isEmpty) {
        return false;
      }
    }
    final extensionState = ref.read(extensionProvider);
    final hasEnabledDownloadProvider = extensionState.extensions.any(
      (extension) => extension.enabled && extension.hasDownloadProvider,
    );
    if (!hasEnabledDownloadProvider) {
      return false;
    }
    return true;
  }

  String _newNativeWorkerRunId() =>
      'native-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

  String _snapshotRunId(Map<String, dynamic> snapshot) {
    final direct = snapshot['run_id']?.toString() ?? '';
    if (direct.isNotEmpty) return direct;

    final settingsJson = snapshot['settings_json'];
    if (settingsJson is String && settingsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(settingsJson);
        if (decoded is Map) {
          return decoded['run_id']?.toString() ?? '';
        }
      } catch (_) {}
    } else if (settingsJson is Map) {
      return settingsJson['run_id']?.toString() ?? '';
    }
    return '';
  }

  bool _isNativeWorkerSnapshotContractCompatible(
    Map<String, dynamic> snapshot,
  ) {
    final version = snapshot['contract_version'];
    return version == DownloadRequestPayload.nativeWorkerContractVersion;
  }

  bool _isNativeWorkerSnapshotForRun(
    Map<String, dynamic> snapshot,
    String runId,
  ) =>
      runId.isNotEmpty &&
      _snapshotRunId(snapshot) == runId &&
      _isNativeWorkerSnapshotContractCompatible(snapshot);

  Future<void> _persistNativeWorkerRunId(String runId) async {
    _activeNativeWorkerRunId = runId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DownloadQueueNotifier._nativeWorkerRunIdPrefsKey, runId);
  }

  Future<String?> _loadNativeWorkerRunId() async {
    if (_activeNativeWorkerRunId != null) return _activeNativeWorkerRunId;
    final prefs = await SharedPreferences.getInstance();
    final runId = prefs.getString(DownloadQueueNotifier._nativeWorkerRunIdPrefsKey);
    if (runId != null && runId.isNotEmpty) {
      _activeNativeWorkerRunId = runId;
      return runId;
    }
    return null;
  }

  Future<void> _clearNativeWorkerRunId(String runId) async {
    if (_activeNativeWorkerRunId == runId) {
      _activeNativeWorkerRunId = null;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(DownloadQueueNotifier._nativeWorkerRunIdPrefsKey) == runId) {
      await prefs.remove(DownloadQueueNotifier._nativeWorkerRunIdPrefsKey);
    }
  }

  Future<bool> _tryAdoptAndroidNativeWorkerSnapshot(
    List<DownloadItem> restoredItems,
  ) async {
    final settings = ref.read(settingsProvider);
    if (!_canUseAndroidNativeWorker(settings)) {
      return false;
    }

    Map<String, dynamic> snapshot;
    try {
      snapshot = await PlatformBridge.getNativeDownloadWorkerSnapshot();
    } catch (_) {
      return false;
    }
    final runId = await _loadNativeWorkerRunId();
    if (runId == null ||
        runId.isEmpty ||
        !_isNativeWorkerSnapshotForRun(snapshot, runId)) {
      return false;
    }

    final rawItems = snapshot['items'];
    final rawItemIds = snapshot['item_ids'];
    final snapshotIds = rawItems is List
        ? rawItems
              .whereType<Map<Object?, Object?>>()
              .map((item) => item['item_id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet()
        : rawItemIds is List
        ? rawItemIds
              .map((id) => id?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet()
        : <String>{};
    if (snapshotIds.isEmpty) {
      return false;
    }
    if (!restoredItems.any((item) => snapshotIds.contains(item.id))) {
      return false;
    }

    final contexts = <String, _NativeWorkerRequestContext>{};
    for (final item in restoredItems) {
      if (!snapshotIds.contains(item.id)) continue;
      final context = await _buildAndroidNativeWorkerRequest(item, settings);
      if (context != null) {
        contexts[item.id] = context;
      }
    }
    if (contexts.isEmpty) {
      return false;
    }

    _log.i('Adopting Android native worker snapshot');
    final reconciledIds = <String>{};
    _totalQueuedAtStart = contexts.length;
    _completedInSession = 0;
    _failedInSession = 0;
    state = state.copyWith(
      isProcessing: snapshot['is_running'] == true,
      isPaused: snapshot['is_paused'] == true,
    );
    await _applyAndroidNativeWorkerSnapshot(
      snapshot,
      contexts,
      reconciledIds,
      settings,
    );

    if (snapshot['is_running'] == true) {
      unawaited(
        _continueAndroidNativeWorkerAdoption(
          contexts,
          reconciledIds,
          settings,
          runId,
        ),
      );
    } else if (state.items.any(
      (item) => item.status == DownloadStatus.queued,
    )) {
      await _clearNativeWorkerRunId(runId);
      Future.microtask(() => _processQueue());
    } else {
      await _clearNativeWorkerRunId(runId);
    }

    return true;
  }

  Future<void> _continueAndroidNativeWorkerAdoption(
    Map<String, _NativeWorkerRequestContext> contexts,
    Set<String> reconciledIds,
    AppSettings settings,
    String runId,
  ) async {
    try {
      while (true) {
        final snapshot = await PlatformBridge.getNativeDownloadWorkerSnapshot();
        if (!_isNativeWorkerSnapshotForRun(snapshot, runId)) {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        await _applyAndroidNativeWorkerSnapshot(
          snapshot,
          contexts,
          reconciledIds,
          settings,
        );
        if (snapshot['is_running'] != true) {
          await _clearNativeWorkerRunId(runId);
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } catch (e) {
      _log.w('Android native worker adoption stopped: $e');
    } finally {
      state = state.copyWith(isProcessing: false, currentDownload: null);
    }
  }

  Future<bool> _tryProcessQueueWithAndroidNativeWorker(
    AppSettings settings,
  ) async {
    if (!_canUseAndroidNativeWorker(settings)) {
      return false;
    }

    final queuedItems = state.items
        .where((item) => item.status == DownloadStatus.queued)
        .toList(growable: false);
    if (queuedItems.isEmpty) {
      return false;
    }

    _log.i(
      'Starting Android native download worker for ${queuedItems.length} items',
    );

    final isSafMode = _isSafMode(settings);
    if (!isSafMode && state.outputDir.isEmpty) {
      await _initOutputDir();
    }
    if (!isSafMode && state.outputDir.isEmpty) {
      final musicDir = await _ensureDefaultDocumentsOutputDir();
      state = state.copyWith(outputDir: musicDir.path);
    }

    final contexts = <String, _NativeWorkerRequestContext>{};
    final requests = <Map<String, dynamic>>[];
    for (final item in queuedItems) {
      final context = await _buildAndroidNativeWorkerRequest(item, settings);
      if (context == null) {
        _log.w(
          'Native worker gate rejected ${item.track.name}; falling back to Dart queue',
        );
        return false;
      }
      contexts[item.id] = context;
      requests.add({
        'contract_version': DownloadRequestPayload.nativeWorkerContractVersion,
        'item_id': item.id,
        'track_name': item.track.name,
        'artist_name': item.track.artistName,
        'item_json': jsonEncode(item.toJson()),
        'request_json': context.requestJson,
      });
    }

    state = state.copyWith(isProcessing: true, isPaused: false);
    _totalQueuedAtStart = queuedItems.length;
    _completedInSession = 0;
    _failedInSession = 0;

    final runId = _newNativeWorkerRunId();
    await _persistNativeWorkerRunId(runId);
    final reconciledIds = <String>{};
    try {
      await PlatformBridge.startNativeDownloadWorker(
        requests: requests,
        settings: {
          'worker': 'android_native',
          'version': 1,
          'contract_version':
              DownloadRequestPayload.nativeWorkerContractVersion,
          'run_id': runId,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      final runStartWait = Stopwatch()..start();
      while (true) {
        final snapshot = await PlatformBridge.getNativeDownloadWorkerSnapshot();
        if (!_isNativeWorkerSnapshotForRun(snapshot, runId)) {
          if (runStartWait.elapsed > const Duration(seconds: 30)) {
            throw _NativeWorkerStartupTimeout();
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        await _applyAndroidNativeWorkerSnapshot(
          snapshot,
          contexts,
          reconciledIds,
          settings,
        );
        if (snapshot['is_running'] != true) {
          await _clearNativeWorkerRunId(runId);
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } catch (e, stack) {
      if (e is _NativeWorkerStartupTimeout) {
        _log.w(
          'Android native worker did not publish a matching snapshot; cancelling native worker and falling back to Dart queue',
        );
        try {
          await PlatformBridge.cancelNativeDownloadWorker();
        } catch (cancelError) {
          _log.w('Failed to cancel timed-out native worker: $cancelError');
        }
        await _clearNativeWorkerRunId(runId);
        state = state.copyWith(isProcessing: false, currentDownload: null);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return false;
      }
      _log.e('Android native worker failed: $e', e, stack);
      for (final item in queuedItems) {
        final current = _findItemById(item.id);
        if (current == null ||
            current.status == DownloadStatus.completed ||
            current.status == DownloadStatus.failed ||
            current.status == DownloadStatus.skipped) {
          continue;
        }
        updateItemStatus(
          item.id,
          DownloadStatus.failed,
          error: 'Native download worker failed: $e',
          errorType: DownloadErrorType.unknown,
        );
        _failedInSession++;
      }
    } finally {
      state = state.copyWith(isProcessing: false, currentDownload: null);
      _stopConnectivityMonitoring();
      try {
        await PlatformBridge.cleanupConnections();
      } catch (e) {
        _log.e('Native worker cleanup failed: $e');
      }
    }

    if (_totalQueuedAtStart > 0) {
      await _notificationService.showQueueComplete(
        completedCount: _completedInSession,
        failedCount: _failedInSession,
      );
    }

    final hasQueuedItems = state.items.any(
      (item) => item.status == DownloadStatus.queued,
    );
    if (hasQueuedItems && !state.isPaused) {
      _log.i(
        'Found queued items after Android native worker finished, restarting queue...',
      );
      Future.microtask(() => _processQueue());
    }

    return true;
  }

  Future<_NativeWorkerRequestContext?> _buildAndroidNativeWorkerRequest(
    DownloadItem item,
    AppSettings settings,
  ) async {
    if (!_hasActiveDownloadProvider(item.service)) {
      return null;
    }

    var quality = item.qualityOverride ?? state.audioQuality;
    if (quality == 'DEFAULT') quality = state.audioQuality;

    final isSafMode = _isSafMode(settings);
    final rawOutputDir = isSafMode
        ? await _buildRelativeOutputDir(
            item.track,
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
        : await _buildOutputDir(
            item.track,
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
    final outputDir = isSafMode
        ? _sanitizeSafRelativeDir(rawOutputDir)
        : rawOutputDir;
    if (!isSafMode) {
      await _ensureDirExists(outputDir, label: 'Output folder');
    }

    final outputExt = _determineOutputExt(quality, item.service);
    if (settings.embedReplayGain &&
        outputExt != '.flac' &&
        outputExt != '.m4a') {
      return null;
    }

    String? safFileName;
    final safOutputExt = isSafMode ? outputExt : '';
    if (isSafMode) {
      final effectiveFormat = _shouldTreatAsSingleRelease(item.track)
          ? state.singleFilenameFormat
          : state.filenameFormat;
      final baseName = await PlatformBridge.buildFilename(effectiveFormat, {
        'title': item.track.name,
        'artist': item.track.artistName,
        'album': item.track.albumName,
        'track': item.track.trackNumber ?? 0,
        'disc': item.track.discNumber ?? 0,
        'year': _extractYear(item.track.releaseDate) ?? '',
        'date': item.track.releaseDate ?? '',
      });
      safFileName = await _buildSafFileName(baseName, safOutputExt);
    }

    var trackForPayload = item.track;
    String? nativeDeezerTrackId = _extractKnownDeezerTrackId(trackForPayload);
    String? nativeGenre;
    String? nativeLabel;
    String? nativeCopyright;

    if (nativeDeezerTrackId == null &&
        trackForPayload.isrc != null &&
        trackForPayload.isrc!.isNotEmpty &&
        _isValidISRC(trackForPayload.isrc!)) {
      nativeDeezerTrackId = await _searchDeezerTrackIdByIsrc(
        trackForPayload.isrc,
        lookupContext: 'native worker ISRC',
        itemId: item.id,
      );
    }

    if (nativeDeezerTrackId == null &&
        (trackForPayload.isrc == null ||
            trackForPayload.isrc!.isEmpty ||
            !_isValidISRC(trackForPayload.isrc!)) &&
        (trackForPayload.id.startsWith('tidal:') ||
            trackForPayload.id.startsWith('qobuz:'))) {
      final providerLookup = await _resolveProviderTrackForDeezerLookup(
        trackForPayload,
        item.id,
      );
      trackForPayload = providerLookup.track;
      nativeDeezerTrackId ??= providerLookup.deezerTrackId;
    }

    if (nativeDeezerTrackId != null && nativeDeezerTrackId.isNotEmpty) {
      final extendedMetadata = await _loadDeezerExtendedMetadata(
        nativeDeezerTrackId,
      );
      nativeGenre = extendedMetadata.genre;
      nativeLabel = extendedMetadata.label;
      nativeCopyright = extendedMetadata.copyright;
    }

    final resolvedAlbumArtist = _resolveAlbumArtistForMetadata(
      trackForPayload,
      settings,
    );
    final extensionState = ref.read(extensionProvider);
    final postProcessingEnabled =
        settings.useExtensionProviders &&
        extensionState.extensions.any((e) => e.enabled && e.hasPostProcessing);
    final normalizedTrackNumber =
        (trackForPayload.trackNumber != null &&
            trackForPayload.trackNumber! > 0)
        ? trackForPayload.trackNumber!
        : 0;
    final normalizedDiscNumber =
        (trackForPayload.discNumber != null && trackForPayload.discNumber! > 0)
        ? trackForPayload.discNumber!
        : 0;

    String payloadSpotifyId = trackForPayload.id;
    String payloadQobuzId = '';
    String payloadTidalId = '';
    if (trackForPayload.id.startsWith('qobuz:')) {
      payloadQobuzId = trackForPayload.id.substring(6);
      if (_usesBuiltInCompatibleDownloadProvider(item.service, 'qobuz')) {
        payloadSpotifyId = '';
      }
    }
    if (trackForPayload.id.startsWith('tidal:')) {
      payloadTidalId = trackForPayload.id.substring(6);
      if (_usesBuiltInCompatibleDownloadProvider(item.service, 'tidal')) {
        payloadSpotifyId = '';
      }
    }

    final payload = DownloadRequestPayload(
      isrc: trackForPayload.isrc ?? '',
      service: item.service,
      spotifyId: payloadSpotifyId,
      trackName: trackForPayload.name,
      artistName: trackForPayload.artistName,
      albumName: trackForPayload.albumName,
      albumArtist: resolvedAlbumArtist ?? '',
      coverUrl: settings.embedMetadata ? (trackForPayload.coverUrl ?? '') : '',
      outputDir: outputDir,
      filenameFormat: _shouldTreatAsSingleRelease(trackForPayload)
          ? state.singleFilenameFormat
          : state.filenameFormat,
      quality: quality,
      embedMetadata: settings.embedMetadata,
      artistTagMode: settings.artistTagMode,
      embedLyrics:
          settings.embedMetadata &&
          settings.embedLyrics &&
          !_shouldSkipLyrics(
            extensionState,
            trackForPayload.source,
            item.service,
          ),
      embedMaxQualityCover: settings.embedMetadata && settings.maxQualityCover,
      embedReplayGain: settings.embedReplayGain,
      postProcessingEnabled: postProcessingEnabled,
      tidalHighFormat: settings.tidalHighFormat,
      trackNumber: normalizedTrackNumber,
      discNumber: normalizedDiscNumber,
      totalTracks: trackForPayload.totalTracks ?? 0,
      totalDiscs: trackForPayload.totalDiscs ?? 0,
      releaseDate: trackForPayload.releaseDate ?? '',
      itemId: item.id,
      durationMs: trackForPayload.duration * 1000,
      source: trackForPayload.source ?? '',
      genre: nativeGenre ?? '',
      label: nativeLabel ?? '',
      copyright: nativeCopyright ?? '',
      composer: trackForPayload.composer ?? '',
      qobuzId: payloadQobuzId,
      tidalId: payloadTidalId,
      deezerId: nativeDeezerTrackId ?? '',
      lyricsMode: settings.lyricsMode,
      storageMode: isSafMode ? 'saf' : 'app',
      safTreeUri: isSafMode ? settings.downloadTreeUri : '',
      safRelativeDir: isSafMode ? outputDir : '',
      safFileName: safFileName ?? '',
      safOutputExt: safOutputExt,
      outputExt: outputExt,
      stageSafOutput: isSafMode,
      deferSafPublish: isSafMode,
      requiresContainerConversion: _shouldRequestContainerConversion(
        item.service,
        outputExt,
      ),
      songLinkRegion: settings.songLinkRegion,
    ).withStrategy(useExtensions: true, useFallback: state.autoFallback);

    return _NativeWorkerRequestContext(
      item: item,
      requestJson: jsonEncode(payload.toJson()),
      outputDir: outputDir,
      quality: quality,
      storageMode: isSafMode ? 'saf' : 'app',
      outputExt: outputExt,
      downloadTreeUri: isSafMode ? settings.downloadTreeUri : null,
      safRelativeDir: isSafMode ? outputDir : null,
      safFileName: safFileName,
    );
  }

  Future<void> _applyAndroidNativeWorkerSnapshot(
    Map<String, dynamic> snapshot,
    Map<String, _NativeWorkerRequestContext> contexts,
    Set<String> reconciledIds,
    AppSettings settings,
  ) async {
    final rawItems = snapshot['items'];
    final rawDelta = snapshot['item_delta'];
    final itemSnapshots = <Map<String, dynamic>>[];
    if (rawItems is List) {
      for (final rawItem in rawItems) {
        if (rawItem is Map) {
          itemSnapshots.add(Map<String, dynamic>.from(rawItem));
        }
      }
    }
    if (rawDelta is Map) {
      itemSnapshots.add(Map<String, dynamic>.from(rawDelta));
    }
    if (itemSnapshots.isEmpty) {
      return;
    }

    for (final itemSnapshot in itemSnapshots) {
      final itemId = itemSnapshot['item_id']?.toString() ?? '';
      if (itemId.isEmpty || reconciledIds.contains(itemId)) {
        continue;
      }
      final context = contexts[itemId];
      if (context == null) continue;

      final status = itemSnapshot['status']?.toString() ?? 'queued';
      final progress = ((itemSnapshot['progress'] as num?)?.toDouble() ?? 0.0)
          .clamp(0.0, 1.0)
          .toDouble();
      final current = _findItemById(itemId);
      if (current == null) {
        reconciledIds.add(itemId);
        continue;
      }

      if (status == 'queued') {
        updateItemStatus(itemId, DownloadStatus.queued, progress: 0.0);
        continue;
      }

      if (status == 'preparing') {
        updateItemStatus(itemId, DownloadStatus.downloading, progress: 0.0);
        continue;
      }

      if (status == 'downloading') {
        updateItemStatus(
          itemId,
          DownloadStatus.downloading,
          progress: progress,
        );
        continue;
      }

      if (status == 'finalizing') {
        updateItemStatus(
          itemId,
          DownloadStatus.finalizing,
          progress: progress <= 0 ? 0.95 : progress,
        );
        continue;
      }

      if (status == 'completed') {
        final result = itemSnapshot['result'];
        if (result is Map) {
          reconciledIds.add(itemId);
          await _completeAndroidNativeWorkerItem(
            context,
            Map<String, dynamic>.from(result),
            settings,
          );
        }
        continue;
      }

      if (status == 'failed' || status == 'skipped') {
        reconciledIds.add(itemId);
        final result = itemSnapshot['result'];
        final error = itemSnapshot['error']?.toString();
        if (status == 'skipped') {
          updateItemStatus(itemId, DownloadStatus.skipped);
        } else {
          final errorType = result is Map
              ? _downloadErrorTypeFromBackend(
                  Map<String, dynamic>.from(result)['error_type']?.toString(),
                )
              : DownloadErrorType.unknown;
          updateItemStatus(
            itemId,
            DownloadStatus.failed,
            error: error == null || error.isEmpty ? 'Download failed' : error,
            errorType: errorType,
          );
          _failedInSession++;
        }
      }
    }
  }

  Future<void> _completeAndroidNativeWorkerItem(
    _NativeWorkerRequestContext context,
    Map<String, dynamic> result,
    AppSettings settings,
  ) async {
    final item = context.item;
    var filePath = result['file_path'] as String?;
    if (filePath == null || filePath.isEmpty) {
      updateItemStatus(
        item.id,
        DownloadStatus.failed,
        error: 'Native worker completed without a file path',
        errorType: DownloadErrorType.unknown,
      );
      _failedInSession++;
      return;
    }

    if (result['native_finalized'] == true) {
      updateItemStatus(
        item.id,
        DownloadStatus.completed,
        progress: 1.0,
        filePath: filePath,
      );
      final historyItem = result['history_item'];
      if (historyItem is Map) {
        try {
          ref
              .read(downloadHistoryProvider.notifier)
              .adoptNativeHistoryItem(
                DownloadHistoryItem.fromJson(
                  Map<String, dynamic>.from(historyItem),
                ),
              );
        } catch (e) {
          _log.w('Failed to adopt native history item: $e');
          await ref.read(downloadHistoryProvider.notifier).reloadFromStorage();
        }
      } else if (result['history_written'] == true) {
        await ref.read(downloadHistoryProvider.notifier).reloadFromStorage();
      }
      _completedInSession++;
      await _notificationService.showDownloadComplete(
        trackName: item.track.name,
        artistName: item.track.artistName,
        completedCount: _completedInSession,
        totalCount: _totalQueuedAtStart,
        alreadyInLibrary: result['already_exists'] == true,
      );
      removeItem(item.id);
      return;
    }

    final finalizedPath = await _finalizeNativeWorkerDecryption(
      context: context,
      result: result,
      filePath: filePath,
    );
    if (finalizedPath == null) {
      updateItemStatus(
        item.id,
        DownloadStatus.failed,
        error: 'Failed to decrypt encrypted stream',
        errorType: DownloadErrorType.unknown,
      );
      _failedInSession++;
      return;
    }
    filePath = finalizedPath;

    var actualQuality = context.quality;
    final actualBitDepth = result['actual_bit_depth'] as int?;
    final actualSampleRate = result['actual_sample_rate'] as int?;
    final actualFormat =
        _normalizeAudioFormatValue(
          result['audio_codec']?.toString() ?? result['format']?.toString(),
        ) ??
        _normalizeAudioFormatValue(_audioFormatForPath(filePath));
    final actualBitrate = _isLossyAudioFormat(actualFormat)
        ? _readPositiveBitrateKbps(
            result['bitrate'] ?? result['actual_bitrate'],
          )
        : null;
    final resolvedQuality = _resolveDisplayQuality(
      filePath: filePath,
      detectedFormat: actualFormat,
      bitDepth: actualBitDepth,
      sampleRate: actualSampleRate,
      bitrateKbps: actualBitrate,
      storedQuality: actualQuality,
    );
    if (resolvedQuality != null) {
      actualQuality = resolvedQuality;
    }

    final resolvedAlbumArtist = _resolveAlbumArtistForMetadata(
      item.track,
      settings,
    );
    final trackToDownload = _buildTrackForMetadataEmbedding(
      item.track,
      result,
      resolvedAlbumArtist,
    );
    final convertedHighPath = await _finalizeNativeWorkerHighConversion(
      context: context,
      result: result,
      settings: settings,
      track: trackToDownload,
      filePath: filePath,
    );
    if (convertedHighPath == null) {
      updateItemStatus(
        item.id,
        DownloadStatus.failed,
        error: 'Failed to convert HIGH quality download',
        errorType: DownloadErrorType.unknown,
      );
      _failedInSession++;
      return;
    }
    filePath = convertedHighPath;
    final nativeActualQuality = result['_native_actual_quality'] as String?;
    if (nativeActualQuality != null && nativeActualQuality.isNotEmpty) {
      actualQuality = nativeActualQuality;
    }
    final convertedContainerPath =
        await _finalizeNativeWorkerContainerConversion(
          context: context,
          result: result,
          settings: settings,
          track: trackToDownload,
          filePath: filePath,
        );
    if (convertedContainerPath == null) {
      updateItemStatus(
        item.id,
        DownloadStatus.failed,
        error: 'Failed to convert downloaded container',
        errorType: DownloadErrorType.unknown,
      );
      _failedInSession++;
      return;
    }
    filePath = convertedContainerPath;

    updateItemStatus(
      item.id,
      DownloadStatus.completed,
      progress: 1.0,
      filePath: filePath,
    );
    await _saveNativeWorkerExternalLrc(
      context: context,
      result: result,
      settings: settings,
      track: trackToDownload,
      filePath: filePath,
    );
    final postProcessedPath = await _runPostProcessingHooks(
      filePath,
      trackToDownload,
    );
    if (postProcessedPath != null && postProcessedPath.isNotEmpty) {
      filePath = postProcessedPath;
    }
    await _writeNativeWorkerReplayGain(
      context: context,
      settings: settings,
      track: trackToDownload,
      filePath: filePath,
    );
    _completedInSession++;

    await _notificationService.showDownloadComplete(
      trackName: item.track.name,
      artistName: item.track.artistName,
      completedCount: _completedInSession,
      totalCount: _totalQueuedAtStart,
      alreadyInLibrary: result['already_exists'] == true,
    );

    final backendTitle = result['title'] as String?;
    final backendArtist = result['artist'] as String?;
    final backendAlbum = result['album'] as String?;
    final backendYear = result['release_date'] as String?;
    final backendTrackNum = _parsePositiveInt(result['track_number']);
    final backendDiscNum = _parsePositiveInt(result['disc_number']);
    final backendTotalTracks = _parsePositiveInt(result['total_tracks']);
    final backendTotalDiscs = _parsePositiveInt(result['total_discs']);
    final backendISRC = result['isrc'] as String?;
    final backendGenre = result['genre'] as String?;
    final backendLabel = result['label'] as String?;
    final backendCopyright = result['copyright'] as String?;
    final backendComposer = result['composer'] as String?;
    final resultSafFileName = result['file_name'] as String?;
    final lowerFilePath = filePath.toLowerCase();
    final historyFormat =
        _normalizeAudioFormatValue(
          result['audio_codec']?.toString() ?? result['format']?.toString(),
        ) ??
        _normalizeAudioFormatValue(_audioFormatForPath(filePath));
    final isLossyOutput =
        _isLossyAudioFormat(historyFormat) ||
        lowerFilePath.endsWith('.mp3') ||
        lowerFilePath.endsWith('.opus') ||
        lowerFilePath.endsWith('.ogg');
    final historyTotalTracks = _resolvePositiveMetadataInt(
      trackToDownload.totalTracks,
      backendTotalTracks,
    );
    final historyTotalDiscs = _resolvePositiveMetadataInt(
      trackToDownload.totalDiscs,
      backendTotalDiscs,
    );
    final historyTrackNumber = _resolveMetadataIndex(
      sourceValue: trackToDownload.trackNumber,
      backendValue: backendTrackNum,
      total: historyTotalTracks,
    );
    final historyDiscNumber = _resolveMetadataIndex(
      sourceValue: trackToDownload.discNumber,
      backendValue: backendDiscNum,
      total: historyTotalDiscs,
    );
    final historyTitle =
        _resolveMetadataText(trackToDownload.name, backendTitle) ??
        item.track.name;
    final historyArtist =
        _resolveMetadataText(trackToDownload.artistName, backendArtist) ??
        item.track.artistName;
    final historyAlbum =
        _resolveMetadataText(trackToDownload.albumName, backendAlbum) ??
        item.track.albumName;
    final historyIsrc = _resolveMetadataText(trackToDownload.isrc, backendISRC);
    final historyReleaseDate = _resolveMetadataText(
      trackToDownload.releaseDate,
      backendYear,
    );
    final historyComposer = _resolveMetadataText(
      trackToDownload.composer,
      backendComposer,
    );

    if (ref.read(settingsProvider).saveDownloadHistory)
      ref
        .read(downloadHistoryProvider.notifier)
        .addToHistory(
          DownloadHistoryItem(
            id: item.id,
            trackName: historyTitle,
            artistName: historyArtist,
            albumName: historyAlbum,
            albumArtist: normalizeOptionalString(trackToDownload.albumArtist),
            coverUrl: normalizeCoverReference(trackToDownload.coverUrl),
            filePath: filePath,
            storageMode: context.storageMode,
            downloadTreeUri: context.storageMode == 'saf'
                ? context.downloadTreeUri
                : null,
            safRelativeDir: context.storageMode == 'saf'
                ? context.safRelativeDir
                : null,
            safFileName: context.storageMode == 'saf'
                ? ((resultSafFileName != null && resultSafFileName.isNotEmpty)
                      ? resultSafFileName
                      : context.safFileName)
                : null,
            safRepaired: false,
            service: result['service'] as String? ?? item.service,
            downloadedAt: DateTime.now(),
            isrc: historyIsrc,
            spotifyId: trackToDownload.id,
            trackNumber: historyTrackNumber,
            totalTracks: historyTotalTracks,
            discNumber: historyDiscNumber,
            totalDiscs: historyTotalDiscs,
            duration: trackToDownload.duration,
            releaseDate: historyReleaseDate,
            quality: actualQuality,
            bitDepth: isLossyOutput ? null : actualBitDepth,
            sampleRate: isLossyOutput ? null : actualSampleRate,
            bitrate: isLossyOutput ? actualBitrate : null,
            format: historyFormat,
            genre: normalizeOptionalString(backendGenre),
            composer: historyComposer,
            label: normalizeOptionalString(backendLabel),
            copyright: normalizeOptionalString(backendCopyright),
          ),
        );

    removeItem(item.id);
  }

  Future<String?> _finalizeNativeWorkerDecryption({
    required _NativeWorkerRequestContext context,
    required Map<String, dynamic> result,
    required String filePath,
  }) async {
    if (result['already_exists'] == true) {
      return filePath;
    }

    final descriptor = DownloadDecryptionDescriptor.fromDownloadResult(result);
    if (descriptor == null) {
      return filePath;
    }

    _log.i(
      'Native-worker encrypted stream detected, decrypting via ${descriptor.normalizedStrategy}...',
    );

    if (context.storageMode == 'saf' && isContentUri(filePath)) {
      final treeUri = context.downloadTreeUri;
      if (treeUri == null || treeUri.isEmpty) {
        return null;
      }
      final tempPath = await _copySafToTemp(filePath);
      if (tempPath == null) {
        return null;
      }

      String? decryptedTempPath;
      try {
        decryptedTempPath = await FFmpegService.decryptWithDescriptor(
          inputPath: tempPath,
          descriptor: descriptor,
          deleteOriginal: false,
        );
        if (decryptedTempPath == null) {
          return null;
        }

        final dotIndex = decryptedTempPath.lastIndexOf('.');
        final decryptedExt = dotIndex >= 0
            ? decryptedTempPath.substring(dotIndex).toLowerCase()
            : context.outputExt;
        const allowedExt = <String>{'.flac', '.m4a', '.mp4', '.mp3', '.opus'};
        final finalExt = allowedExt.contains(decryptedExt)
            ? decryptedExt
            : context.outputExt;
        final rawFileName =
            (result['file_name'] as String?) ?? context.safFileName ?? 'track';
        final baseName = rawFileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
        final newFileName = '$baseName$finalExt';
        final newUri = await _writeTempToSaf(
          treeUri: treeUri,
          relativeDir: context.safRelativeDir ?? '',
          fileName: newFileName,
          mimeType: _mimeTypeForExt(finalExt),
          srcPath: decryptedTempPath,
        );
        if (newUri == null) {
          return null;
        }
        if (newUri != filePath) {
          await _deleteSafFile(filePath);
        }
        result['file_name'] = newFileName;
        return newUri;
      } finally {
        try {
          await File(tempPath).delete();
        } catch (_) {}
        if (decryptedTempPath != null && decryptedTempPath != tempPath) {
          try {
            await File(decryptedTempPath).delete();
          } catch (_) {}
        }
      }
    }

    final decryptedPath = await FFmpegService.decryptWithDescriptor(
      inputPath: filePath,
      descriptor: descriptor,
      deleteOriginal: true,
    );
    return decryptedPath;
  }

  Future<String?> _finalizeNativeWorkerHighConversion({
    required _NativeWorkerRequestContext context,
    required Map<String, dynamic> result,
    required AppSettings settings,
    required Track track,
    required String filePath,
  }) async {
    if (context.quality != 'HIGH') {
      return filePath;
    }

    final lowerPath = filePath.toLowerCase();
    final resultFileName = (result['file_name'] as String?)?.toLowerCase();
    final looksLikeM4a =
        lowerPath.endsWith('.m4a') ||
        lowerPath.endsWith('.mp4') ||
        (resultFileName != null &&
            (resultFileName.endsWith('.m4a') ||
                resultFileName.endsWith('.mp4')));
    if (!looksLikeM4a) {
      return filePath;
    }

    final tidalHighFormat = settings.tidalHighFormat;
    final format = _lossyFormatForSetting(tidalHighFormat);
    final newExt = _lossyExtensionForFormat(format);
    final displayFormat = _displayFormatForLossyFormat(format);
    final bitrateDisplay = tidalHighFormat.contains('_')
        ? '${tidalHighFormat.split('_').last}kbps'
        : '320kbps';

    Future<void> embedConvertedMetadata(String convertedPath) async {
      if (!settings.embedMetadata) return;
      await _embedMetadataToFile(
        convertedPath,
        track,
        format: _metadataFormatForLossyFormat(format),
        genre: result['genre'] as String?,
        label: result['label'] as String?,
        copyright: result['copyright'] as String?,
        downloadService: context.item.service,
      );
    }

    if (context.storageMode == 'saf' && isContentUri(filePath)) {
      final treeUri = context.downloadTreeUri;
      if (treeUri == null || treeUri.isEmpty) {
        return null;
      }
      final tempPath = await _copySafToTemp(filePath);
      if (tempPath == null) {
        return null;
      }

      String? convertedPath;
      try {
        convertedPath = await FFmpegService.convertM4aToLossy(
          tempPath,
          format: format,
          bitrate: tidalHighFormat,
          deleteOriginal: false,
        );
        if (convertedPath == null) {
          return null;
        }
        await embedConvertedMetadata(convertedPath);
        final rawFileName =
            (result['file_name'] as String?) ?? context.safFileName ?? 'track';
        final baseName = rawFileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
        final newFileName = '$baseName$newExt';
        final newUri = await _writeTempToSaf(
          treeUri: treeUri,
          relativeDir: context.safRelativeDir ?? '',
          fileName: newFileName,
          mimeType: _mimeTypeForExt(newExt),
          srcPath: convertedPath,
        );
        if (newUri == null) {
          return null;
        }
        if (newUri != filePath) {
          await _deleteSafFile(filePath);
        }
        result['file_name'] = newFileName;
        result['_native_actual_quality'] = '$displayFormat $bitrateDisplay';
        return newUri;
      } finally {
        try {
          await File(tempPath).delete();
        } catch (_) {}
        if (convertedPath != null) {
          try {
            await File(convertedPath).delete();
          } catch (_) {}
        }
      }
    }

    final convertedPath = await FFmpegService.convertM4aToLossy(
      filePath,
      format: format,
      bitrate: tidalHighFormat,
      deleteOriginal: true,
    );
    if (convertedPath == null) {
      return null;
    }
    await embedConvertedMetadata(convertedPath);
    result['_native_actual_quality'] = '$displayFormat $bitrateDisplay';
    return convertedPath;
  }

  Future<String?> _finalizeNativeWorkerContainerConversion({
    required _NativeWorkerRequestContext context,
    required Map<String, dynamic> result,
    required AppSettings settings,
    required Track track,
    required String filePath,
  }) async {
    if (context.quality == 'HIGH' || context.outputExt != '.flac') {
      return filePath;
    }
    final resultAudioFormat = _normalizeAudioFormatValue(
      result['audio_codec']?.toString() ??
          result['actual_audio_codec']?.toString(),
    );
    if (_isLossyAudioFormat(resultAudioFormat)) {
      _log.d(
        'Native-worker output is $resultAudioFormat; preserving native container.',
      );
      return filePath;
    }
    final requiresContainerConversion =
        result['requires_container_conversion'] == true ||
        result['requiresContainerConversion'] == true;
    final resultOutputExt = _downloadResultOutputExt(
      result,
      filePath: filePath,
    );
    final lowerPath = filePath.toLowerCase();
    final resultFileName = (result['file_name'] as String?)?.toLowerCase();
    final mayNeedContainerConversion =
        requiresContainerConversion ||
        lowerPath.endsWith('.m4a') ||
        lowerPath.endsWith('.mp4') ||
        resultOutputExt == '.m4a' ||
        resultOutputExt == '.mp4' ||
        isContentUri(filePath);
    if (!mayNeedContainerConversion) {
      return filePath;
    }
    final requestedDecryptionExt =
        DownloadDecryptionDescriptor.fromDownloadResult(
          result,
        )?.normalizedOutputExtension;
    if (!requiresContainerConversion &&
        requestedDecryptionExt != null &&
        requestedDecryptionExt != '.flac') {
      _log.d(
        'Native-worker decrypted output requested $requestedDecryptionExt; preserving native container.',
      );
      return filePath;
    }
    final looksLikeM4a =
        lowerPath.endsWith('.m4a') ||
        lowerPath.endsWith('.mp4') ||
        resultOutputExt == '.m4a' ||
        resultOutputExt == '.mp4' ||
        (resultFileName != null &&
            (resultFileName.endsWith('.m4a') ||
                resultFileName.endsWith('.mp4')));
    if (!requiresContainerConversion &&
        !looksLikeM4a &&
        !isContentUri(filePath)) {
      return filePath;
    }

    Future<void> embedFlacMetadata(String flacPath) async {
      if (!settings.embedMetadata) return;
      await _embedMetadataToFile(
        flacPath,
        track,
        format: 'flac',
        genre: result['genre'] as String?,
        label: result['label'] as String?,
        copyright: result['copyright'] as String?,
        downloadService: context.item.service,
        writeExternalLrc: context.storageMode != 'saf',
      );
    }

    if (context.storageMode == 'saf' && isContentUri(filePath)) {
      final treeUri = context.downloadTreeUri;
      if (treeUri == null || treeUri.isEmpty) {
        return null;
      }
      final tempPath = await _copySafToTemp(filePath);
      if (tempPath == null) {
        return null;
      }

      String? flacPath;
      try {
        final codec = await FFmpegService.probePrimaryAudioCodec(tempPath);
        final isAlreadyNativeFlac =
            codec == 'flac' && await FFmpegService.isNativeFlacFile(tempPath);
        if (!FFmpegService.isLosslessAudioCodec(codec)) {
          _log.d(
            'Preserving native container; audio codec is ${codec ?? 'unknown'}, '
            'no FLAC container conversion needed.',
          );
          return filePath;
        }
        if (isAlreadyNativeFlac) {
          _log.d(
            'Native FLAC payload detected in temporary container; publishing '
            'as FLAC and embedding metadata.',
          );
          await embedFlacMetadata(tempPath);
          final rawFileName =
              (result['file_name'] as String?) ??
              context.safFileName ??
              'track';
          final baseName = rawFileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
          final newFileName = '$baseName.flac';
          final newUri = await _writeTempToSaf(
            treeUri: treeUri,
            relativeDir: context.safRelativeDir ?? '',
            fileName: newFileName,
            mimeType: _mimeTypeForExt('.flac'),
            srcPath: tempPath,
          );
          if (newUri == null) {
            return null;
          }
          if (newUri != filePath) {
            await _deleteSafFile(filePath);
          }
          result['file_name'] = newFileName;
          return newUri;
        }
        flacPath = await FFmpegService.convertM4aToFlac(tempPath);
        if (flacPath == null) {
          return null;
        }
        await embedFlacMetadata(flacPath);
        final rawFileName =
            (result['file_name'] as String?) ?? context.safFileName ?? 'track';
        final baseName = rawFileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
        final newFileName = '$baseName.flac';
        final newUri = await _writeTempToSaf(
          treeUri: treeUri,
          relativeDir: context.safRelativeDir ?? '',
          fileName: newFileName,
          mimeType: _mimeTypeForExt('.flac'),
          srcPath: flacPath,
        );
        if (newUri == null) {
          return null;
        }
        if (newUri != filePath) {
          await _deleteSafFile(filePath);
        }
        result['file_name'] = newFileName;
        return newUri;
      } finally {
        try {
          await File(tempPath).delete();
        } catch (_) {}
        if (flacPath != null) {
          try {
            await File(flacPath).delete();
          } catch (_) {}
        }
      }
    }

    final codec = await FFmpegService.probePrimaryAudioCodec(filePath);
    final isAlreadyNativeFlac =
        codec == 'flac' && await FFmpegService.isNativeFlacFile(filePath);
    if (!FFmpegService.isLosslessAudioCodec(codec)) {
      _log.d(
        'Preserving native container; audio codec is ${codec ?? 'unknown'}, '
        'no FLAC container conversion needed.',
      );
      return filePath;
    }
    if (isAlreadyNativeFlac) {
      var flacPath = filePath;
      if (!filePath.toLowerCase().endsWith('.flac')) {
        final renamedPath = filePath.replaceAll(RegExp(r'\.[^.]+$'), '.flac');
        final targetPath = renamedPath == filePath
            ? '$filePath.flac'
            : renamedPath;
        await File(filePath).rename(targetPath);
        flacPath = targetPath;
      }
      await embedFlacMetadata(flacPath);
      return flacPath;
    }
    final flacPath = await FFmpegService.convertM4aToFlac(filePath);
    if (flacPath == null) {
      return null;
    }
    await embedFlacMetadata(flacPath);
    return flacPath;
  }

  Future<void> _writeNativeWorkerReplayGain({
    required _NativeWorkerRequestContext context,
    required AppSettings settings,
    required Track track,
    required String filePath,
  }) async {
    if (!settings.embedReplayGain) {
      return;
    }
    if (context.outputExt != '.flac' && context.outputExt != '.m4a') {
      return;
    }

    try {
      final rgResult = await FFmpegService.scanReplayGain(filePath);
      if (rgResult == null) {
        return;
      }
      await PlatformBridge.editFileMetadata(filePath, {
        'replaygain_track_gain': rgResult.trackGain,
        'replaygain_track_peak': rgResult.trackPeak,
      });
      _storeTrackReplayGainForAlbum(track, filePath, rgResult);
      _updateAlbumRgFilePath(track, filePath);
      await _checkAndWriteAlbumReplayGain(track);
      _log.d(
        'Native-worker ReplayGain written: gain=${rgResult.trackGain}, peak=${rgResult.trackPeak}',
      );
    } catch (e) {
      _log.w('Failed to write native-worker ReplayGain: $e');
    }
  }

  Future<void> _saveNativeWorkerExternalLrc({
    required _NativeWorkerRequestContext context,
    required Map<String, dynamic> result,
    required AppSettings settings,
    required Track track,
    required String filePath,
  }) async {
    final lyricsMode = settings.lyricsMode;
    final shouldSaveExternalLrc =
        settings.embedMetadata &&
        settings.embedLyrics &&
        !_shouldSkipLyrics(
          ref.read(extensionProvider),
          track.source,
          context.item.service,
        ) &&
        (lyricsMode == 'external' || lyricsMode == 'both');
    if (!shouldSaveExternalLrc) {
      return;
    }

    String? lrcContent = result['lyrics_lrc'] as String?;
    if (lrcContent == null || lrcContent.isEmpty) {
      try {
        lrcContent = await PlatformBridge.getLyricsLRC(
          track.id,
          track.name,
          track.artistName,
          durationMs: track.duration * 1000,
        );
      } catch (e) {
        _log.w('Failed to fetch native-worker external LRC: $e');
      }
    }
    if (lrcContent == null || lrcContent.isEmpty) {
      return;
    }

    if (context.storageMode == 'saf' && isContentUri(filePath)) {
      final treeUri = context.downloadTreeUri;
      if (treeUri == null || treeUri.isEmpty) {
        return;
      }
      final resultFileName = result['file_name'] as String?;
      final fileName = (resultFileName != null && resultFileName.isNotEmpty)
          ? resultFileName
          : context.safFileName;
      final baseName = fileName != null && fileName.isNotEmpty
          ? fileName.replaceFirst(RegExp(r'\.[^.]+$'), '')
          : await PlatformBridge.sanitizeFilename(
              '${track.artistName} - ${track.name}',
            );
      await _writeLrcToSaf(
        treeUri: treeUri,
        relativeDir: context.safRelativeDir ?? '',
        baseName: baseName,
        lrcContent: lrcContent,
      );
      return;
    }

    try {
      final lrcPath = filePath.replaceAll(RegExp(r'\.[^.]+$'), '.lrc');
      final safeLrcPath = lrcPath == filePath ? '$filePath.lrc' : lrcPath;
      await File(safeLrcPath).writeAsString(lrcContent);
      _log.d('Native-worker external LRC saved: $safeLrcPath');
    } catch (e) {
      _log.w('Failed to save native-worker external LRC: $e');
    }
  }

  DownloadErrorType _downloadErrorTypeFromBackend(String? errorType) {
    switch (errorType) {
      case 'not_found':
        return DownloadErrorType.notFound;
      case 'rate_limit':
        return DownloadErrorType.rateLimit;
      case 'network':
        return DownloadErrorType.network;
      case 'permission':
        return DownloadErrorType.permission;
      default:
        return DownloadErrorType.unknown;
    }
  }

  Future<void> _processQueue() async {
    if (state.isProcessing) return;

    final settings = ref.read(settingsProvider);
    updateSettings(settings);
    final isSafMode = _isSafMode(settings);
    var iosDownloadBookmarkActive = false;
    if (settings.downloadNetworkMode == 'wifi_only') {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasWifi = connectivityResult.contains(ConnectivityResult.wifi);
      if (!hasWifi) {
        _log.w('WiFi-only mode enabled but no WiFi connection. Queue paused.');
        _networkPausedByWifiOnly = true;
        _startConnectivityMonitoring();
        state = state.copyWith(isProcessing: false, isPaused: true);
        return;
      }
      _networkPausedByWifiOnly = false;
      _startConnectivityMonitoring();
    } else {
      _stopConnectivityMonitoring();
    }

    if (await _tryProcessQueueWithAndroidNativeWorker(settings)) {
      return;
    }

    state = state.copyWith(isProcessing: true);
    _log.i('Starting queue processing...');

    _totalQueuedAtStart = state.items
        .where((i) => i.status == DownloadStatus.queued)
        .length;
    _completedInSession = 0;
    _failedInSession = 0;

    if (Platform.isAndroid && _totalQueuedAtStart > 0) {
      final firstItem = state.items.firstWhere(
        (item) => item.status == DownloadStatus.queued,
        orElse: () => state.items.first,
      );
      try {
        await _notificationService.cancelDownloadNotification();
        await PlatformBridge.startDownloadService(
          trackName: firstItem.track.name,
          artistName: firstItem.track.artistName,
          queueCount: _totalQueuedAtStart,
        );
        _log.d('Foreground service started');
      } catch (e) {
        _log.e('Failed to start foreground service: $e');
      }
    }

    if (!isSafMode && state.outputDir.isEmpty) {
      _log.d('Output dir empty, initializing...');
      await _initOutputDir();
    }

    // iOS: Validate that outputDir is writable (not iCloud Drive which Go can't access)
    if (!isSafMode && Platform.isIOS && state.outputDir.isNotEmpty) {
      final isICloudPath =
          state.outputDir.contains('Mobile Documents') ||
          state.outputDir.contains('CloudDocs') ||
          state.outputDir.contains('com~apple~CloudDocs');
      if (isICloudPath) {
        _log.w(
          'iOS: iCloud Drive path detected, falling back to app Documents folder',
        );
        _log.w('Go backend cannot write to iCloud Drive due to iOS sandboxing');
        final musicDir = await _ensureDefaultDocumentsOutputDir();
        state = state.copyWith(outputDir: musicDir.path);
        ref.read(settingsProvider.notifier).setDownloadDirectory(musicDir.path);
      } else if (!isValidIosWritablePath(state.outputDir)) {
        _log.w(
          'iOS: Invalid output path detected (container root?), falling back to app Documents folder',
        );
        _log.w('Original path: ${state.outputDir}');
        final correctedPath = await validateOrFixIosPath(state.outputDir);
        _log.i('Corrected path: $correctedPath');
        state = state.copyWith(outputDir: correctedPath);
        ref.read(settingsProvider.notifier).setDownloadDirectory(correctedPath);
      }
    }

    if (!isSafMode && state.outputDir.isEmpty) {
      _log.d('Using fallback directory...');
      final musicDir = await _ensureDefaultDocumentsOutputDir();
      state = state.copyWith(outputDir: musicDir.path);
    }

    if (!isSafMode) {
      _log.d('Output directory: ${state.outputDir}');
    } else {
      _log.d('Output directory: SAF (tree_uri=${settings.downloadTreeUri})');
      try {
        final testResult = await PlatformBridge.createSafFileFromPath(
          treeUri: settings.downloadTreeUri,
          relativeDir: '',
          fileName: '.spotiflac_test',
          mimeType: 'application/octet-stream',
          srcPath: '',
        );
        if (testResult != null) {
          await PlatformBridge.safDelete(testResult);
        }
      } catch (e) {
        _log.e('SAF permission validation failed: $e');
        _log.w('SAF tree URI may be invalid or permission revoked');
        for (final item in state.items) {
          if (item.status == DownloadStatus.queued) {
            updateItemStatus(
              item.id,
              DownloadStatus.failed,
              error:
                  'SAF permission invalid or revoked. Please reconfigure download location in Settings.',
            );
          }
        }
        state = state.copyWith(isProcessing: false);
        return;
      }
    }

    if (!isSafMode &&
        Platform.isIOS &&
        settings.downloadDirectoryBookmark.isNotEmpty) {
      final resolvedPath = await PlatformBridge.startAccessingIosBookmark(
        settings.downloadDirectoryBookmark,
      );
      if (resolvedPath != null && resolvedPath.isNotEmpty) {
        iosDownloadBookmarkActive = true;
        if (resolvedPath != state.outputDir) {
          _log.i('Resolved iOS download bookmark path: $resolvedPath');
          state = state.copyWith(outputDir: resolvedPath);
        }
      } else {
        _log.w(
          'Failed to access iOS download folder bookmark, falling back to app Documents folder',
        );
        final musicDir = await _ensureDefaultDocumentsOutputDir();
        state = state.copyWith(outputDir: musicDir.path);
        ref.read(settingsProvider.notifier).setDownloadDirectory(musicDir.path);
      }
    }

    _log.d('Concurrent downloads: ${state.concurrentDownloads}');
    try {
      await _processQueueParallel();
    } finally {
      if (iosDownloadBookmarkActive) {
        await PlatformBridge.stopAccessingIosBookmark();
        iosDownloadBookmarkActive = false;
      }
    }
    final stoppedWhilePaused = state.isPaused;
    final keepConnectivityMonitoring =
        stoppedWhilePaused && _networkPausedByWifiOnly;

    _stopProgressPolling();
    if (!keepConnectivityMonitoring) {
      _stopConnectivityMonitoring();
    }

    if (Platform.isAndroid) {
      try {
        await PlatformBridge.stopDownloadService();
        _log.d('Foreground service stopped');
      } catch (e) {
        _log.e('Failed to stop foreground service: $e');
      }
    }

    if (_downloadCount > 0) {
      _log.d('Final connection cleanup...');
      try {
        await PlatformBridge.cleanupConnections();
      } catch (e) {
        _log.e('Final cleanup failed: $e');
      }
      _downloadCount = 0;
    }

    _log.i(
      'Queue stats - completed: $_completedInSession, failed: $_failedInSession, totalAtStart: $_totalQueuedAtStart',
    );
    final hasSessionResults = _completedInSession > 0 || _failedInSession > 0;
    if (!stoppedWhilePaused && _totalQueuedAtStart > 0 && hasSessionResults) {
      await _notificationService.showQueueComplete(
        completedCount: _completedInSession,
        failedCount: _failedInSession,
      );

      final settings = ref.read(settingsProvider);
      if (settings.autoExportFailedDownloads && _failedInSession > 0) {
        final exportPath = await exportFailedDownloads();
        if (exportPath != null) {
          _log.i('Auto-exported failed downloads to: $exportPath');
        }
      }
    } else if (!stoppedWhilePaused && _totalQueuedAtStart > 0) {
      await _notificationService.showQueueCanceled(
        canceledCount: _totalQueuedAtStart,
      );
    }

    if (stoppedWhilePaused) {
      _log.i('Queue processing paused');
    } else {
      _log.i('Queue processing finished');
    }
    state = state.copyWith(isProcessing: false, currentDownload: null);

    final hasQueuedItems = state.items.any(
      (item) => item.status == DownloadStatus.queued,
    );
    if (hasQueuedItems && !state.isPaused) {
      _log.i(
        'Found queued items after processing finished, restarting queue...',
      );
      Future.microtask(() => _processQueue());
    }
  }

  Future<void> _processQueueParallel() async {
    final activeDownloads = <String, Future<void>>{};
    var lastLoggedMaxConcurrent = -1;

    _startMultiProgressPolling();

    while (true) {
      if (state.isPaused) {
        if (activeDownloads.isEmpty) {
          _log.d('Queue is paused and no active downloads remain');
          break;
        }
        _log.d('Queue is paused, waiting for active downloads...');
        await Future.any([
          Future.wait(activeDownloads.values),
          Future<void>.delayed(DownloadQueueNotifier._queueSchedulingInterval),
        ]);
        continue;
      }

      final maxConcurrent = max(1, state.concurrentDownloads);
      if (lastLoggedMaxConcurrent != maxConcurrent) {
        _log.d('Parallel worker max concurrency now: $maxConcurrent');
        lastLoggedMaxConcurrent = maxConcurrent;
      }

      final queuedItems = state.items
          .where(
            (item) =>
                item.status == DownloadStatus.queued &&
                !_pausePendingItemIds.contains(item.id),
          )
          .toList();

      if (queuedItems.isEmpty && activeDownloads.isEmpty) {
        _log.d('No more items to process');
        break;
      }

      while (activeDownloads.length < maxConcurrent &&
          queuedItems.isNotEmpty &&
          !state.isPaused) {
        final item = queuedItems.removeAt(0);

        updateItemStatus(item.id, DownloadStatus.downloading);

        final future = _downloadSingleItem(item).whenComplete(() {
          activeDownloads.remove(item.id);
          PlatformBridge.clearItemProgress(item.id).catchError((_) {});
        });

        activeDownloads[item.id] = future;
        _log.d(
          'Started parallel download: ${item.track.name} (${activeDownloads.length}/$maxConcurrent active)',
        );
      }

      if (activeDownloads.isNotEmpty) {
        await Future.any([
          Future.any(activeDownloads.values),
          Future<void>.delayed(DownloadQueueNotifier._queueSchedulingInterval),
        ]);
      } else {
        await Future<void>.delayed(DownloadQueueNotifier._queueSchedulingInterval);
      }
    }

    if (activeDownloads.isNotEmpty) {
      await Future.wait(activeDownloads.values);
    }

    _stopProgressPolling();
    final remainingIds = state.items.map((item) => item.id).toSet();
    _locallyCancelledItemIds.removeWhere((id) => !remainingIds.contains(id));
    _pausePendingItemIds.removeWhere((id) => !remainingIds.contains(id));
  }

  Future<void> _downloadSingleItem(DownloadItem item) async {
    final normalizedService = _normalizeQueuedService(item.service);
    if (normalizedService != item.service) {
      item = item.copyWith(service: normalizedService);
      state = state.copyWith(
        items: [
          for (final existing in state.items)
            if (existing.id == item.id) item else existing,
        ],
        currentDownload: state.currentDownload?.id == item.id
            ? item
            : state.currentDownload,
      );
      _saveQueueToStorage();
    }

    if (!_hasActiveDownloadProvider(item.service)) {
      updateItemStatus(
        item.id,
        DownloadStatus.failed,
        error: 'Download provider is no longer available',
        errorType: DownloadErrorType.notFound,
      );
      return;
    }

    _log.d('Processing: ${item.track.name} by ${item.track.artistName}');
    _log.d('Cover URL: ${item.track.coverUrl}');
    var pausedDuringThisRun = false;

    final currentItem = _findItemById(item.id) ?? item;
    if (_isLocallyCancelled(item.id, item: currentItem)) {
      _log.i('Download was cancelled before start, skipping');
      return;
    }

    if (_isPausePending(item.id)) {
      pausedDuringThisRun = true;
      _requeueItemForPause(item.id);
      _log.i('Download is pause-pending before start, skipping');
      return;
    }

    state = state.copyWith(currentDownload: item);

    updateItemStatus(item.id, DownloadStatus.downloading);

    try {
      bool shouldAbortWork(String stage) {
        final current = _findItemById(item.id);
        if (_isLocallyCancelled(item.id, item: current)) {
          _log.i('Download was cancelled $stage, skipping');
          return true;
        }
        if (_isPausePending(item.id)) {
          pausedDuringThisRun = true;
          _requeueItemForPause(item.id);
          _log.i('Download pause requested $stage, re-queueing');
          return true;
        }
        return false;
      }

      final settings = ref.read(settingsProvider);
      final metadataEmbeddingEnabled = settings.embedMetadata;

      Track trackToDownload = item.track;
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
              final enrichedTotalTracks = _parsePositiveInt(
                data['total_tracks'],
              );
              final enrichedTotalDiscs = _parsePositiveInt(data['total_discs']);
              final enrichedComposer = normalizeOptionalString(
                data['composer']?.toString(),
              );
              trackToDownload = Track(
                id: (data['spotify_id'] as String?) ?? trackToDownload.id,
                name: (data['name'] as String?) ?? trackToDownload.name,
                artistName:
                    (data['artists'] as String?) ?? trackToDownload.artistName,
                albumName:
                    (data['album_name'] as String?) ??
                    trackToDownload.albumName,
                albumArtist: data['album_artist'] as String?,
                artistId:
                    (data['artist_id'] ?? data['artistId'])?.toString() ??
                    trackToDownload.artistId,
                albumId:
                    data['album_id']?.toString() ?? trackToDownload.albumId,
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
                    (data['album_type'] as String?) ??
                    trackToDownload.albumType,
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

        if (shouldAbortWork('during metadata enrichment')) {
          return;
        }
      }

      _log.d('Track coverUrl after enrichment: ${trackToDownload.coverUrl}');

      final resolvedAlbumArtist = _resolveAlbumArtistForMetadata(
        trackToDownload,
        settings,
      );

      var quality = item.qualityOverride ?? state.audioQuality;
      if (quality == 'DEFAULT') quality = state.audioQuality;
      final isSafMode = _isSafMode(settings);
      final relativeOutputDir = isSafMode
          ? await _buildRelativeOutputDir(
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
      String? appOutputDir;
      final initialOutputDir = isSafMode
          ? relativeOutputDir
          : await _buildOutputDir(
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
      var effectiveOutputDir = isSafMode
          ? _sanitizeSafRelativeDir(initialOutputDir)
          : initialOutputDir;
      var effectiveSafMode = isSafMode;

      String? safFileName;
      String? safBaseName;
      String safOutputExt = _determineOutputExt(quality, item.service);
      if (isSafMode) {
        final effectiveFormat = _shouldTreatAsSingleRelease(trackToDownload)
            ? state.singleFilenameFormat
            : state.filenameFormat;
        final baseName = await PlatformBridge.buildFilename(effectiveFormat, {
          'title': trackToDownload.name,
          'artist': trackToDownload.artistName,
          'album': trackToDownload.albumName,
          'track': trackToDownload.trackNumber ?? 0,
          'disc': trackToDownload.discNumber ?? 0,
          'year': _extractYear(trackToDownload.releaseDate) ?? '',
          'date': trackToDownload.releaseDate ?? '',
        });
        safFileName = await _buildSafFileName(baseName, safOutputExt);
        safBaseName = safFileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
      }
      String? finalSafFileName = safFileName;

      String? genre;
      String? label;
      String? copyright;
      final extensionState = ref.read(extensionProvider);
      final selectedExtensionDownloadProvider =
          settings.useExtensionProviders &&
          extensionState.extensions.any(
            (e) =>
                e.enabled &&
                e.hasDownloadProvider &&
                e.id.toLowerCase() == item.service.toLowerCase(),
          );
      final trackSource = (trackToDownload.source ?? '').trim().toLowerCase();
      final shouldSkipExtensionSongLinkPrelookup =
          trackSource.isNotEmpty &&
          extensionState.extensions.any(
            (e) =>
                e.enabled &&
                e.hasMetadataProvider &&
                e.id.toLowerCase() == trackSource,
          );

      String? deezerTrackId = _extractKnownDeezerTrackId(trackToDownload);

      if (deezerTrackId == null &&
          trackToDownload.isrc != null &&
          trackToDownload.isrc!.isNotEmpty &&
          _isValidISRC(trackToDownload.isrc!)) {
        deezerTrackId = await _searchDeezerTrackIdByIsrc(
          trackToDownload.isrc,
          lookupContext: 'ISRC',
          itemId: item.id,
        );

        if (shouldAbortWork('during Deezer ISRC lookup')) {
          return;
        }
      }

      // For tidal:/qobuz: tracks without ISRC, resolve ISRC from provider
      // API directly (faster than SongLink and avoids rate limits).
      if (deezerTrackId == null &&
          (trackToDownload.isrc == null ||
              trackToDownload.isrc!.isEmpty ||
              !_isValidISRC(trackToDownload.isrc!)) &&
          (trackToDownload.id.startsWith('tidal:') ||
              trackToDownload.id.startsWith('qobuz:'))) {
        final providerLookup = await _resolveProviderTrackForDeezerLookup(
          trackToDownload,
          item.id,
        );
        trackToDownload = providerLookup.track;
        deezerTrackId ??= providerLookup.deezerTrackId;

        if (shouldAbortWork('during provider ISRC resolution')) {
          return;
        }
      }

      if (!selectedExtensionDownloadProvider &&
          deezerTrackId == null &&
          !shouldSkipExtensionSongLinkPrelookup &&
          trackToDownload.id.isNotEmpty &&
          !trackToDownload.id.startsWith('deezer:') &&
          !trackToDownload.id.startsWith('extension:') &&
          !trackToDownload.id.startsWith('tidal:') &&
          !trackToDownload.id.startsWith('qobuz:')) {
        final spotifyLookup = await _resolveSpotifyTrackViaDeezer(
          trackToDownload,
        );
        trackToDownload = spotifyLookup.track;
        deezerTrackId ??= spotifyLookup.deezerTrackId;

        if (shouldAbortWork('during SongLink availability lookup')) {
          return;
        }
      } else if (selectedExtensionDownloadProvider && deezerTrackId == null) {
        _log.d(
          'Skipping Flutter SongLink Deezer prelookup for extension provider: ${item.service}',
        );
      } else if (shouldSkipExtensionSongLinkPrelookup &&
          deezerTrackId == null) {
        _log.d(
          'Skipping Flutter SongLink Deezer prelookup for extension-sourced track; backend metadata enrichment will resolve identifiers first',
        );
      }

      if (deezerTrackId != null && deezerTrackId.isNotEmpty) {
        final extendedMetadata = await _loadDeezerExtendedMetadata(
          deezerTrackId,
        );
        genre = extendedMetadata.genre;
        label = extendedMetadata.label;
        copyright = extendedMetadata.copyright;

        if (shouldAbortWork('during extended metadata lookup')) {
          return;
        }
      }

      Map<String, dynamic> result;

      final hasActiveExtensions = extensionState.extensions.any(
        (e) => e.enabled,
      );
      final postProcessingEnabled =
          settings.useExtensionProviders &&
          extensionState.extensions.any(
            (e) => e.enabled && e.hasPostProcessing,
          );
      final useExtensions =
          settings.useExtensionProviders && hasActiveExtensions;

      Future<Map<String, dynamic>> runDownload({
        required bool useSaf,
        required String outputDir,
      }) async {
        final storageMode = useSaf ? 'saf' : 'app';
        final treeUri = useSaf ? settings.downloadTreeUri : '';
        final relativeDir = useSaf ? outputDir : '';
        final fileName = useSaf ? (safFileName ?? '') : '';
        final outputExt = safOutputExt;
        final safPayloadOutputExt = useSaf ? outputExt : '';
        final shouldUseExtensions = useExtensions;
        final shouldUseFallback = state.autoFallback;

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
          await _ensureDirExists(outputDir, label: 'Output folder');
        }

        _log.d('Output dir: $outputDir');

        final normalizedTrackNumber =
            (trackToDownload.trackNumber != null &&
                trackToDownload.trackNumber! > 0)
            ? trackToDownload.trackNumber!
            : 0;
        final normalizedDiscNumber =
            (trackToDownload.discNumber != null &&
                trackToDownload.discNumber! > 0)
            ? trackToDownload.discNumber!
            : 0;

        String payloadSpotifyId = trackToDownload.id;
        String payloadQobuzId = '';
        String payloadTidalId = '';
        if (trackToDownload.id.startsWith('qobuz:')) {
          payloadQobuzId = trackToDownload.id.substring(6);
          if (_usesBuiltInCompatibleDownloadProvider(item.service, 'qobuz')) {
            payloadSpotifyId = '';
          }
        }
        if (trackToDownload.id.startsWith('tidal:')) {
          payloadTidalId = trackToDownload.id.substring(6);
          if (_usesBuiltInCompatibleDownloadProvider(item.service, 'tidal')) {
            payloadSpotifyId = '';
          }
        }

        final payload = DownloadRequestPayload(
          isrc: trackToDownload.isrc ?? '',
          service: item.service,
          spotifyId: payloadSpotifyId,
          trackName: trackToDownload.name,
          artistName: trackToDownload.artistName,
          albumName: trackToDownload.albumName,
          albumArtist: resolvedAlbumArtist ?? '',
          coverUrl: metadataEmbeddingEnabled
              ? (trackToDownload.coverUrl ?? '')
              : '',
          outputDir: outputDir,
          filenameFormat: _shouldTreatAsSingleRelease(trackToDownload)
              ? state.singleFilenameFormat
              : state.filenameFormat,
          quality: quality,
          embedMetadata: metadataEmbeddingEnabled,
          artistTagMode: settings.artistTagMode,
          embedLyrics:
              metadataEmbeddingEnabled &&
              settings.embedLyrics &&
              !_shouldSkipLyrics(
                extensionState,
                trackToDownload.source,
                item.service,
              ),
          embedMaxQualityCover:
              metadataEmbeddingEnabled && settings.maxQualityCover,
          embedReplayGain: settings.embedReplayGain,
          postProcessingEnabled: postProcessingEnabled,
          tidalHighFormat: settings.tidalHighFormat,
          trackNumber: normalizedTrackNumber,
          discNumber: normalizedDiscNumber,
          totalTracks: trackToDownload.totalTracks ?? 0,
          totalDiscs: trackToDownload.totalDiscs ?? 0,
          releaseDate: trackToDownload.releaseDate ?? '',
          itemId: item.id,
          durationMs: trackToDownload.duration * 1000,
          source: trackToDownload.source ?? '',
          genre: genre ?? '',
          label: label ?? '',
          copyright: copyright ?? '',
          composer: trackToDownload.composer ?? '',
          qobuzId: payloadQobuzId,
          tidalId: payloadTidalId,
          deezerId: deezerTrackId ?? '',
          lyricsMode: settings.lyricsMode,
          storageMode: storageMode,
          safTreeUri: treeUri,
          safRelativeDir: relativeDir,
          safFileName: fileName,
          safOutputExt: safPayloadOutputExt,
          outputExt: outputExt,
          requiresContainerConversion: _shouldRequestContainerConversion(
            item.service,
            outputExt,
          ),
          songLinkRegion: settings.songLinkRegion,
        );

        return PlatformBridge.downloadByStrategy(
          payload: payload,
          useExtensions: shouldUseExtensions,
          useFallback: shouldUseFallback,
        );
      }

      if (shouldAbortWork('before native download start')) {
        return;
      }

      result = await runDownload(
        useSaf: effectiveSafMode,
        outputDir: effectiveOutputDir,
      );

      if (effectiveSafMode &&
          result['success'] != true &&
          _isSafWriteFailure(result)) {
        if (_isLocallyCancelled(item.id)) {
          _log.i('Download was cancelled before SAF fallback, skipping');
          return;
        }
        _log.w('SAF write failed, retrying with app-private storage');
        appOutputDir ??= await _buildOutputDir(
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
        final fallbackResult = await runDownload(
          useSaf: false,
          outputDir: appOutputDir,
        );
        if (fallbackResult['success'] == true) {
          effectiveSafMode = false;
          effectiveOutputDir = appOutputDir;
          finalSafFileName = null;
          result = fallbackResult;
        }
      }

      _log.d('Result: $result');

      final itemAfterResult = _findItemById(item.id);
      if (itemAfterResult == null ||
          _isLocallyCancelled(item.id, item: itemAfterResult)) {
        _log.i('Download was cancelled, skipping result processing');
        final filePath = result['file_path'] as String?;
        if (filePath != null && result['success'] == true) {
          await deleteFile(filePath);
          _log.d('Deleted cancelled download file: $filePath');
        }
        return;
      }

      if (_isPausePending(item.id)) {
        pausedDuringThisRun = true;
        final filePath = result['file_path'] as String?;
        if (filePath != null && result['success'] == true) {
          await deleteFile(filePath);
          _log.d('Deleted paused download file: $filePath');
        }
        _requeueItemForPause(item.id);
        _log.i('Download pause requested after result, re-queueing');
        return;
      }

      if (result['success'] == true) {
        var filePath = result['file_path'] as String?;
        final reportedFileName = result['file_name'] as String?;
        if (effectiveSafMode &&
            reportedFileName != null &&
            reportedFileName.isNotEmpty) {
          finalSafFileName = reportedFileName;
        }

        final wasExisting = result['already_exists'] == true;
        if (wasExisting) {
          _log.i('File already exists in library: $filePath');
        }

        _log.i('Download success, file: $filePath');

        final actualBitDepth = result['actual_bit_depth'] as int?;
        final actualSampleRate = result['actual_sample_rate'] as int?;
        String actualQuality = quality;

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
        final resultOutputExt = _downloadResultOutputExt(
          result,
          filePath: filePath,
        );
        final resultAudioFormat = _normalizeAudioFormatValue(
          result['audio_codec']?.toString() ??
              result['actual_audio_codec']?.toString(),
        );
        final resultIsLossyAudio = _isLossyAudioFormat(resultAudioFormat);
        final requiresContainerConversion =
            result['requires_container_conversion'] == true ||
            result['requiresContainerConversion'] == true ||
            (!resultIsLossyAudio &&
                _shouldRequestContainerConversion(actualService, safOutputExt));
        final preferredOutputExt = _extensionPreferredOutputExt(actualService);
        final shouldPreserveNativeM4a =
            !requiresContainerConversion &&
            (resultOutputExt == '.m4a' ||
                resultOutputExt == '.mp4' ||
                preferredOutputExt == '.m4a' ||
                preferredOutputExt == '.mp4' ||
                _extensionPreservesNativeOutputExt(actualService, '.m4a') ||
                _extensionPreservesNativeOutputExt(actualService, '.mp4'));
        final decryptionDescriptor =
            DownloadDecryptionDescriptor.fromDownloadResult(result);
        trackToDownload = _buildTrackForMetadataEmbedding(
          trackToDownload,
          result,
          resolvedAlbumArtist,
        );
        _log.d(
          'Track coverUrl after download result: ${trackToDownload.coverUrl}',
        );

        if (!wasExisting && decryptionDescriptor != null && filePath != null) {
          _log.i(
            'Encrypted stream detected, decrypting via ${decryptionDescriptor.normalizedStrategy}...',
          );
          updateItemStatus(item.id, DownloadStatus.finalizing, progress: 0.9);

          if (effectiveSafMode && isContentUri(filePath)) {
            final currentFilePath = filePath;
            final tempPath = await _copySafToTemp(currentFilePath);
            if (tempPath == null) {
              _log.e('Failed to copy encrypted SAF file to temp for decrypt');
              updateItemStatus(
                item.id,
                DownloadStatus.failed,
                error: 'Failed to access encrypted SAF file',
                errorType: DownloadErrorType.unknown,
              );
              return;
            }

            String? decryptedTempPath;
            try {
              decryptedTempPath = await FFmpegService.decryptWithDescriptor(
                inputPath: tempPath,
                descriptor: decryptionDescriptor,
                deleteOriginal: false,
              );
              if (decryptedTempPath == null) {
                _log.e('FFmpeg decrypt failed for SAF file');
                updateItemStatus(
                  item.id,
                  DownloadStatus.failed,
                  error: 'Failed to decrypt encrypted stream',
                  errorType: DownloadErrorType.unknown,
                );
                return;
              }

              final dotIndex = decryptedTempPath.lastIndexOf('.');
              final decryptedExt = dotIndex >= 0
                  ? decryptedTempPath.substring(dotIndex).toLowerCase()
                  : '.flac';
              final allowedExt = <String>{
                '.flac',
                '.m4a',
                '.mp4',
                '.mp3',
                '.opus',
              };
              final finalExt = allowedExt.contains(decryptedExt)
                  ? decryptedExt
                  : '.flac';

              final newFileName = '${safBaseName ?? 'track'}$finalExt';
              final newUri = await _writeTempToSaf(
                treeUri: settings.downloadTreeUri,
                relativeDir: effectiveOutputDir,
                fileName: newFileName,
                mimeType: _mimeTypeForExt(finalExt),
                srcPath: decryptedTempPath,
              );

              if (newUri == null) {
                _log.e('Failed to write decrypted stream back to SAF');
                updateItemStatus(
                  item.id,
                  DownloadStatus.failed,
                  error: 'Failed to write decrypted file to storage',
                  errorType: DownloadErrorType.unknown,
                );
                return;
              }

              if (newUri != currentFilePath) {
                await _deleteSafFile(currentFilePath);
              }
              filePath = newUri;
              finalSafFileName = newFileName;
              _log.i('SAF decryption completed');
            } finally {
              try {
                await File(tempPath).delete();
              } catch (_) {}
              if (decryptedTempPath != null && decryptedTempPath != tempPath) {
                try {
                  await File(decryptedTempPath).delete();
                } catch (_) {}
              }
            }
          } else {
            final decryptedPath = await FFmpegService.decryptWithDescriptor(
              inputPath: filePath,
              descriptor: decryptionDescriptor,
              deleteOriginal: true,
            );
            if (decryptedPath == null) {
              _log.e('FFmpeg decrypt failed for local file');
              updateItemStatus(
                item.id,
                DownloadStatus.failed,
                error: 'Failed to decrypt encrypted stream',
                errorType: DownloadErrorType.unknown,
              );
              try {
                await deleteFile(filePath);
              } catch (_) {}
              return;
            }
            filePath = decryptedPath;
            _log.i('Local decryption completed');
          }
        }

        final isContentUriPath = filePath != null && isContentUri(filePath);
        final mimeType = isContentUriPath
            ? await _getSafMimeType(filePath)
            : null;
        final isM4aFile =
            filePath != null &&
            (filePath.endsWith('.m4a') ||
                filePath.endsWith('.mp4') ||
                resultOutputExt == '.m4a' ||
                resultOutputExt == '.mp4' ||
                (mimeType != null && mimeType.contains('mp4')));
        final isFlacFile =
            filePath != null &&
            (filePath.endsWith('.flac') ||
                resultOutputExt == '.flac' ||
                (mimeType != null && mimeType.contains('flac')));
        final shouldForceTidalSafM4aHandling =
            !wasExisting &&
            isContentUriPath &&
            effectiveSafMode &&
            _usesBuiltInCompatibleDownloadProvider(actualService, 'tidal') &&
            filePath.endsWith('.flac') &&
            (mimeType == null || mimeType.contains('flac'));

        if (shouldForceTidalSafM4aHandling) {
          _log.w(
            'Tidal SAF file is labeled FLAC but backend returned DASH/M4A stream; converting it back to FLAC.',
          );
        }

        if (isM4aFile || shouldForceTidalSafM4aHandling) {
          final currentFilePath = filePath;

          if (isContentUriPath && effectiveSafMode) {
            if (quality == 'HIGH') {
              final tidalHighFormat = settings.tidalHighFormat;
              _log.i(
                'Tidal HIGH quality (SAF), converting M4A to $tidalHighFormat...',
              );

              final tempPath = await _copySafToTemp(currentFilePath);
              if (tempPath != null) {
                String? convertedPath;
                try {
                  updateItemStatus(
                    item.id,
                    DownloadStatus.finalizing,
                    progress: 0.95,
                  );

                  final format = _lossyFormatForSetting(tidalHighFormat);
                  final displayFormat = _displayFormatForLossyFormat(format);
                  convertedPath = await FFmpegService.convertM4aToLossy(
                    tempPath,
                    format: format,
                    bitrate: tidalHighFormat,
                    deleteOriginal: false,
                  );

                  if (convertedPath != null) {
                    _log.i(
                      'Successfully converted M4A to $format (temp): $convertedPath',
                    );
                    _log.i('Embedding metadata to $format...');
                    updateItemStatus(
                      item.id,
                      DownloadStatus.finalizing,
                      progress: 0.99,
                    );

                    final backendGenre = result['genre'] as String?;
                    final backendLabel = result['label'] as String?;
                    final backendCopyright = result['copyright'] as String?;

                    await _embedMetadataToFile(
                      convertedPath,
                      trackToDownload,
                      format: _metadataFormatForLossyFormat(format),
                      genre: backendGenre ?? genre,
                      label: backendLabel ?? label,
                      copyright: backendCopyright,
                      downloadService: item.service,
                    );

                    final newExt = _lossyExtensionForFormat(format);
                    final newFileName = '${safBaseName ?? 'track'}$newExt';
                    final newUri = await _writeTempToSaf(
                      treeUri: settings.downloadTreeUri,
                      relativeDir: effectiveOutputDir,
                      fileName: newFileName,
                      mimeType: _mimeTypeForExt(newExt),
                      srcPath: convertedPath,
                    );

                    if (newUri != null) {
                      if (newUri != currentFilePath) {
                        await _deleteSafFile(currentFilePath);
                      }
                      filePath = newUri;
                      finalSafFileName = newFileName;
                      final bitrateDisplay = tidalHighFormat.contains('_')
                          ? '${tidalHighFormat.split('_').last}kbps'
                          : '320kbps';
                      actualQuality = '$displayFormat $bitrateDisplay';
                    } else {
                      _log.w(
                        'Failed to write converted $format to SAF, keeping M4A',
                      );
                      actualQuality = 'AAC 320kbps';
                    }
                  } else {
                    _log.w(
                      'M4A to $format conversion failed, keeping M4A file',
                    );
                    actualQuality = 'AAC 320kbps';
                  }
                } catch (e) {
                  _log.w('SAF M4A conversion failed: $e');
                  actualQuality = 'AAC 320kbps';
                } finally {
                  try {
                    await File(tempPath).delete();
                  } catch (_) {}
                  if (convertedPath != null) {
                    try {
                      await File(convertedPath).delete();
                    } catch (_) {}
                  }
                }
              }
            } else if (shouldPreserveNativeM4a) {
              // Decrypted streams are already in their final format.
              // Converting e.g. eac3 M4A to FLAC would produce fake upscaled output.
              _log.d(
                'M4A/MP4 file detected (SAF), preserving native container...',
              );
              final tempPath = await _copySafToTemp(currentFilePath);
              if (tempPath != null) {
                try {
                  if (metadataEmbeddingEnabled) {
                    updateItemStatus(
                      item.id,
                      DownloadStatus.finalizing,
                      progress: 0.99,
                    );
                    final finalTrack = _buildTrackForMetadataEmbedding(
                      trackToDownload,
                      result,
                      resolvedAlbumArtist,
                    );
                    final backendGenre = result['genre'] as String?;
                    final backendLabel = result['label'] as String?;
                    final backendCopyright = result['copyright'] as String?;

                    await _embedMetadataToFile(
                      tempPath,
                      finalTrack,
                      format: 'm4a',
                      genre: backendGenre ?? genre,
                      label: backendLabel ?? label,
                      copyright: backendCopyright,
                      downloadService: item.service,
                      writeExternalLrc: false,
                    );
                  }

                  final preserveExt =
                      currentFilePath.toLowerCase().endsWith('.mp4')
                      ? '.mp4'
                      : '.m4a';
                  final newFileName = '${safBaseName ?? 'track'}$preserveExt';
                  final newUri = await _writeTempToSaf(
                    treeUri: settings.downloadTreeUri,
                    relativeDir: effectiveOutputDir,
                    fileName: newFileName,
                    mimeType: _mimeTypeForExt(preserveExt),
                    srcPath: tempPath,
                  );

                  if (newUri != null) {
                    if (newUri != currentFilePath) {
                      await _deleteSafFile(currentFilePath);
                    }
                    filePath = newUri;
                    finalSafFileName = newFileName;
                  } else {
                    _log.w('Failed to write M4A to SAF, keeping original');
                  }
                } catch (e) {
                  _log.w('SAF native M4A handling failed: $e');
                } finally {
                  try {
                    await File(tempPath).delete();
                  } catch (_) {}
                }
              }
            } else {
              _log.d('M4A file detected (SAF), converting to FLAC...');
              final tempPath = await _copySafToTemp(currentFilePath);
              if (tempPath != null) {
                String? flacPath;
                try {
                  final length = await File(tempPath).length();
                  if (length < 1024) {
                    _log.w('Temp M4A is too small (<1KB), skipping conversion');
                  } else {
                    final codec = await FFmpegService.probePrimaryAudioCodec(
                      tempPath,
                    );
                    final isAlreadyNativeFlac =
                        codec == 'flac' &&
                        await FFmpegService.isNativeFlacFile(tempPath);
                    if (!FFmpegService.isLosslessAudioCodec(codec)) {
                      _log.d(
                        'Preserving native container; audio codec is ${codec ?? 'unknown'}, '
                        'no FLAC container conversion needed.',
                      );
                      final preserveExt = resultOutputExt == '.mp4'
                          ? '.mp4'
                          : '.m4a';
                      final newFileName =
                          '${safBaseName ?? 'track'}$preserveExt';
                      final newUri = await _writeTempToSaf(
                        treeUri: settings.downloadTreeUri,
                        relativeDir: effectiveOutputDir,
                        fileName: newFileName,
                        mimeType: _mimeTypeForExt(preserveExt),
                        srcPath: tempPath,
                      );
                      if (newUri != null) {
                        if (newUri != currentFilePath) {
                          await _deleteSafFile(currentFilePath);
                        }
                        filePath = newUri;
                        finalSafFileName = newFileName;
                      }
                    } else if (isAlreadyNativeFlac) {
                      _log.d(
                        'Native FLAC payload detected in SAF temp file; '
                        'publishing as FLAC and embedding metadata.',
                      );
                      final finalTrack = _buildTrackForMetadataEmbedding(
                        trackToDownload,
                        result,
                        resolvedAlbumArtist,
                      );

                      final backendGenre = result['genre'] as String?;
                      final backendLabel = result['label'] as String?;
                      final backendCopyright = result['copyright'] as String?;

                      await _embedMetadataToFile(
                        tempPath,
                        finalTrack,
                        format: 'flac',
                        genre: backendGenre ?? genre,
                        label: backendLabel ?? label,
                        copyright: backendCopyright,
                        downloadService: item.service,
                        writeExternalLrc: false,
                      );

                      final newFileName = '${safBaseName ?? 'track'}.flac';
                      final newUri = await _writeTempToSaf(
                        treeUri: settings.downloadTreeUri,
                        relativeDir: effectiveOutputDir,
                        fileName: newFileName,
                        mimeType: _mimeTypeForExt('.flac'),
                        srcPath: tempPath,
                      );
                      if (newUri != null) {
                        if (newUri != currentFilePath) {
                          await _deleteSafFile(currentFilePath);
                        }
                        filePath = newUri;
                        finalSafFileName = newFileName;
                      } else {
                        _log.w('Failed to write native FLAC to SAF');
                      }
                    } else {
                      updateItemStatus(
                        item.id,
                        DownloadStatus.finalizing,
                        progress: 0.95,
                      );
                      flacPath = await FFmpegService.convertM4aToFlac(tempPath);
                      if (flacPath != null) {
                        _log.d('Converted to FLAC (temp): $flacPath');
                        _log.d(
                          'Embedding metadata and cover to converted FLAC...',
                        );
                        final finalTrack = _buildTrackForMetadataEmbedding(
                          trackToDownload,
                          result,
                          resolvedAlbumArtist,
                        );

                        final backendGenre = result['genre'] as String?;
                        final backendLabel = result['label'] as String?;
                        final backendCopyright = result['copyright'] as String?;

                        await _embedMetadataToFile(
                          flacPath,
                          finalTrack,
                          format: 'flac',
                          genre: backendGenre ?? genre,
                          label: backendLabel ?? label,
                          copyright: backendCopyright,
                          downloadService: item.service,
                          writeExternalLrc: false,
                        );

                        final newFileName = '${safBaseName ?? 'track'}.flac';
                        final newUri = await _writeTempToSaf(
                          treeUri: settings.downloadTreeUri,
                          relativeDir: effectiveOutputDir,
                          fileName: newFileName,
                          mimeType: _mimeTypeForExt('.flac'),
                          srcPath: flacPath,
                        );

                        if (newUri != null) {
                          if (newUri != currentFilePath) {
                            await _deleteSafFile(currentFilePath);
                          }
                          filePath = newUri;
                          finalSafFileName = newFileName;
                        } else {
                          _log.w('Failed to write FLAC to SAF, keeping M4A');
                        }
                      } else {
                        _log.w(
                          'FFmpeg conversion returned null, keeping M4A file',
                        );
                      }
                    }
                  }
                } catch (e) {
                  _log.w('SAF M4A->FLAC conversion failed: $e');
                } finally {
                  try {
                    await File(tempPath).delete();
                  } catch (_) {}
                  if (flacPath != null) {
                    try {
                      await File(flacPath).delete();
                    } catch (_) {}
                  }
                }
              }
            }
          } else {
            if (quality == 'HIGH') {
              final tidalHighFormat = settings.tidalHighFormat;
              _log.i(
                'Tidal HIGH quality download, converting M4A to $tidalHighFormat...',
              );

              try {
                updateItemStatus(
                  item.id,
                  DownloadStatus.finalizing,
                  progress: 0.95,
                );

                final format = _lossyFormatForSetting(tidalHighFormat);
                final displayFormat = _displayFormatForLossyFormat(format);
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
                  _log.i(
                    'Successfully converted M4A to $format: $convertedPath',
                  );

                  _log.i('Embedding metadata to $format...');
                  updateItemStatus(
                    item.id,
                    DownloadStatus.finalizing,
                    progress: 0.99,
                  );

                  final backendGenre = result['genre'] as String?;
                  final backendLabel = result['label'] as String?;
                  final backendCopyright = result['copyright'] as String?;

                  await _embedMetadataToFile(
                    convertedPath,
                    trackToDownload,
                    format: _metadataFormatForLossyFormat(format),
                    genre: backendGenre ?? genre,
                    label: backendLabel ?? label,
                    copyright: backendCopyright,
                    downloadService: item.service,
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
            } else if (shouldPreserveNativeM4a) {
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
                    updateItemStatus(
                      item.id,
                      DownloadStatus.finalizing,
                      progress: 0.99,
                    );
                    final finalTrack = _buildTrackForMetadataEmbedding(
                      trackToDownload,
                      result,
                      resolvedAlbumArtist,
                    );

                    final backendGenre = result['genre'] as String?;
                    final backendLabel = result['label'] as String?;
                    final backendCopyright = result['copyright'] as String?;

                    await _embedMetadataToFile(
                      targetPath,
                      finalTrack,
                      format: 'm4a',
                      genre: backendGenre ?? genre,
                      label: backendLabel ?? label,
                      copyright: backendCopyright,
                      downloadService: item.service,
                    );
                  }
                }
              } catch (e) {
                _log.w('Native M4A handling failed: $e');
              }
            } else {
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

                      final finalTrack = _buildTrackForMetadataEmbedding(
                        trackToDownload,
                        result,
                        resolvedAlbumArtist,
                      );

                      final backendGenre = result['genre'] as String?;
                      final backendLabel = result['label'] as String?;
                      final backendCopyright = result['copyright'] as String?;

                      await _embedMetadataToFile(
                        flacPath,
                        finalTrack,
                        format: 'flac',
                        genre: backendGenre ?? genre,
                        label: backendLabel ?? label,
                        copyright: backendCopyright,
                        downloadService: item.service,
                      );
                    } else {
                      updateItemStatus(
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

                        _log.d(
                          'Embedding metadata and cover to converted FLAC...',
                        );
                        try {
                          final finalTrack = _buildTrackForMetadataEmbedding(
                            trackToDownload,
                            result,
                            resolvedAlbumArtist,
                          );

                          final backendGenre = result['genre'] as String?;
                          final backendLabel = result['label'] as String?;
                          final backendCopyright =
                              result['copyright'] as String?;

                          if (backendGenre != null ||
                              backendLabel != null ||
                              backendCopyright != null) {
                            _log.d(
                              'Extended metadata from backend - Genre: $backendGenre, Label: $backendLabel, Copyright: $backendCopyright',
                            );
                          }

                          await _embedMetadataToFile(
                            flacPath,
                            finalTrack,
                            format: 'flac',
                            genre: backendGenre ?? genre,
                            label: backendLabel ?? label,
                            copyright: backendCopyright,
                            downloadService: item.service,
                          );
                          _log.d('Metadata and cover embedded successfully');
                        } catch (e) {
                          _log.w('Warning: Failed to embed metadata/cover: $e');
                        }
                      } else {
                        _log.w(
                          'FFmpeg conversion returned null, keeping M4A file',
                        );
                      }
                    }
                  }
                }
              } catch (e) {
                _log.w(
                  'FFmpeg conversion process failed: $e, keeping M4A file',
                );
              }
            }
          }
        } else if (metadataEmbeddingEnabled &&
            isContentUriPath &&
            effectiveSafMode &&
            !isM4aFile &&
            !wasExisting) {
          final currentFilePath = filePath;
          final isOpusFile =
              filePath.endsWith('.opus') ||
              filePath.endsWith('.ogg') ||
              resultOutputExt == '.opus' ||
              resultOutputExt == '.ogg';
          final isMp3File =
              filePath.endsWith('.mp3') || resultOutputExt == '.mp3';
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
          final tempPath = await _copySafToTemp(currentFilePath);
          if (tempPath != null) {
            try {
              updateItemStatus(
                item.id,
                DownloadStatus.finalizing,
                progress: 0.99,
              );

              final finalTrack = _buildTrackForMetadataEmbedding(
                trackToDownload,
                result,
                resolvedAlbumArtist,
              );
              final backendGenre = result['genre'] as String?;
              final backendLabel = result['label'] as String?;
              final backendCopyright = result['copyright'] as String?;

              if (isMp3File) {
                await _embedMetadataToFile(
                  tempPath,
                  finalTrack,
                  format: 'mp3',
                  genre: backendGenre ?? genre,
                  label: backendLabel ?? label,
                  copyright: backendCopyright,
                  downloadService: item.service,
                );
              } else if (isOpusFile) {
                await _embedMetadataToFile(
                  tempPath,
                  finalTrack,
                  format: 'opus',
                  genre: backendGenre ?? genre,
                  label: backendLabel ?? label,
                  copyright: backendCopyright,
                  downloadService: item.service,
                );
              } else {
                await _embedMetadataToFile(
                  tempPath,
                  finalTrack,
                  format: 'flac',
                  genre: backendGenre ?? genre,
                  label: backendLabel ?? label,
                  copyright: backendCopyright,
                  downloadService: item.service,
                  writeExternalLrc: false,
                );
              }

              final newFileName = '${safBaseName ?? 'track'}$ext';
              final newUri = await _writeTempToSaf(
                treeUri: settings.downloadTreeUri,
                relativeDir: effectiveOutputDir,
                fileName: newFileName,
                mimeType: _mimeTypeForExt(ext),
                srcPath: tempPath,
              );

              if (newUri != null) {
                if (newUri != currentFilePath) {
                  await _deleteSafFile(currentFilePath);
                }
                filePath = newUri;
                finalSafFileName = newFileName;
                _log.d('SAF $formatName metadata embedding completed');
              } else {
                _log.w(
                  'Failed to write metadata-updated $formatName back to SAF',
                );
              }
            } catch (e) {
              _log.w('SAF $formatName metadata embedding failed: $e');
            } finally {
              try {
                await File(tempPath).delete();
              } catch (_) {}
            }
          }
        } else if (metadataEmbeddingEnabled &&
            !isContentUriPath &&
            !effectiveSafMode &&
            isFlacFile &&
            !wasExisting &&
            decryptionDescriptor != null) {
          _log.d(
            'Local FLAC after decrypt detected, embedding metadata and cover...',
          );
          try {
            updateItemStatus(
              item.id,
              DownloadStatus.finalizing,
              progress: 0.99,
            );

            final finalTrack = _buildTrackForMetadataEmbedding(
              trackToDownload,
              result,
              resolvedAlbumArtist,
            );
            final backendGenre = result['genre'] as String?;
            final backendLabel = result['label'] as String?;
            final backendCopyright = result['copyright'] as String?;

            await _embedMetadataToFile(
              filePath,
              finalTrack,
              format: 'flac',
              genre: backendGenre ?? genre,
              label: backendLabel ?? label,
              copyright: backendCopyright,
              downloadService: item.service,
            );
            _log.d('Local FLAC metadata embedding completed');
          } catch (e) {
            _log.w('Local FLAC metadata embedding failed: $e');
          }
        }

        final itemAfterDownload = _findItemById(item.id);
        if (itemAfterDownload == null ||
            _isLocallyCancelled(item.id, item: itemAfterDownload)) {
          _log.i('Download was cancelled during finalization, cleaning up');
          if (filePath != null) {
            await deleteFile(filePath);
            _log.d('Deleted cancelled download file: $filePath');
          }
          return;
        }

        if (_isPausePending(item.id)) {
          pausedDuringThisRun = true;
          if (filePath != null) {
            await deleteFile(filePath);
            _log.d(
              'Deleted paused download file during finalization: $filePath',
            );
          }
          _requeueItemForPause(item.id);
          _log.i('Download pause requested during finalization, re-queueing');
          return;
        }

        if (effectiveSafMode &&
            filePath != null &&
            filePath.isNotEmpty &&
            !isContentUri(filePath) &&
            settings.downloadTreeUri.isNotEmpty) {
          final fallbackName = (finalSafFileName ?? safFileName ?? '').trim();
          if (fallbackName.isNotEmpty) {
            try {
              final resolved = await PlatformBridge.resolveSafFile(
                treeUri: settings.downloadTreeUri,
                relativeDir: effectiveOutputDir,
                fileName: fallbackName,
              );
              final resolvedUri = (resolved['uri'] as String? ?? '').trim();
              final resolvedRelativeDir =
                  (resolved['relative_dir'] as String? ?? '').trim();
              if (resolvedUri.isNotEmpty && isContentUri(resolvedUri)) {
                _log.w('Recovered SAF URI from transient path: $filePath');
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

        updateItemStatus(
          item.id,
          DownloadStatus.completed,
          progress: 1.0,
          filePath: filePath,
        );

        final lyricsMode = settings.lyricsMode;
        final shouldSaveExternalLrc =
            metadataEmbeddingEnabled &&
            settings.embedLyrics &&
            !_shouldSkipLyrics(
              extensionState,
              trackToDownload.source,
              item.service,
            ) &&
            (lyricsMode == 'external' || lyricsMode == 'both');
        if (shouldSaveExternalLrc &&
            effectiveSafMode &&
            filePath != null &&
            isContentUri(filePath)) {
          String? lrcContent = result['lyrics_lrc'] as String?;
          if (lrcContent == null || lrcContent.isEmpty) {
            try {
              lrcContent = await PlatformBridge.getLyricsLRC(
                trackToDownload.id,
                trackToDownload.name,
                trackToDownload.artistName,
                durationMs: trackToDownload.duration * 1000,
              );
            } catch (e) {
              _log.w('Failed to fetch lyrics for external LRC: $e');
            }
          }

          if (lrcContent != null && lrcContent.isNotEmpty) {
            final baseName = finalSafFileName != null
                ? finalSafFileName.replaceFirst(RegExp(r'\.[^.]+$'), '')
                : safBaseName ??
                      await PlatformBridge.sanitizeFilename(
                        '${trackToDownload.artistName} - ${trackToDownload.name}',
                      );
            await _writeLrcToSaf(
              treeUri: settings.downloadTreeUri,
              relativeDir: effectiveOutputDir,
              baseName: baseName,
              lrcContent: lrcContent,
            );
          }
        }

        if (filePath != null) {
          await _runPostProcessingHooks(filePath, trackToDownload);
        }

        // Album ReplayGain: update the accumulator path to the final file
        // location.  For SAF downloads the metadata was embedded on a temp
        // copy, so the stored path still points there.  Replace it with the
        // actual output path (SAF content URI or local path) so the later
        // album-gain writer targets the correct file.
        if (filePath != null) {
          _updateAlbumRgFilePath(trackToDownload, filePath);
        }

        // Album ReplayGain: check if all album tracks are now complete and,
        // if so, compute and write album gain/peak to every track file.
        try {
          await _checkAndWriteAlbumReplayGain(trackToDownload);
        } catch (e) {
          _log.w('Album ReplayGain check failed: $e');
        }

        _completedInSession++;

        final historyNotifier = ref.read(downloadHistoryProvider.notifier);
        final existingInHistory =
            await historyNotifier.getBySpotifyIdAsync(trackToDownload.id) ??
            (trackToDownload.isrc != null
                ? await historyNotifier.getByIsrcAsync(trackToDownload.isrc!)
                : null);

        if (wasExisting && existingInHistory != null) {
          _log.i('Track already in library, skipping history update');
          await _notificationService.showDownloadComplete(
            trackName: item.track.name,
            artistName: item.track.artistName,
            completedCount: _completedInSession,
            totalCount: _totalQueuedAtStart,
            alreadyInLibrary: true,
          );
          removeItem(item.id);
          return;
        }

        await _notificationService.showDownloadComplete(
          trackName: item.track.name,
          artistName: item.track.artistName,
          completedCount: _completedInSession,
          totalCount: _totalQueuedAtStart,
          alreadyInLibrary: wasExisting,
        );

        if (filePath != null) {
          final backendTitle = result['title'] as String?;
          final backendArtist = result['artist'] as String?;
          final backendAlbum = result['album'] as String?;
          final backendYear = result['release_date'] as String?;
          final backendTrackNum = _parsePositiveInt(result['track_number']);
          final backendDiscNum = _parsePositiveInt(result['disc_number']);
          final backendTotalTracks = _parsePositiveInt(result['total_tracks']);
          final backendTotalDiscs = _parsePositiveInt(result['total_discs']);
          final backendBitDepth = result['actual_bit_depth'] as int?;
          final backendSampleRate = result['actual_sample_rate'] as int?;
          final backendFormat =
              _normalizeAudioFormatValue(
                result['audio_codec']?.toString() ??
                    result['format']?.toString(),
              ) ??
              _normalizeAudioFormatValue(_audioFormatForPath(filePath));
          final backendBitrateKbps = _readPositiveBitrateKbps(
            result['bitrate'] ?? result['actual_bitrate'],
          );
          final backendISRC = result['isrc'] as String?;
          final backendGenre = result['genre'] as String?;
          final backendLabel = result['label'] as String?;
          final backendCopyright = result['copyright'] as String?;
          final backendComposer = result['composer'] as String?;
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
          int? finalBitrateKbps = _isLossyAudioFormat(finalFormat)
              ? backendBitrateKbps
              : null;
          final lowerFilePath = filePath.toLowerCase();
          final canProbeFinalMetadata =
              filePath.startsWith('content://') ||
              lowerFilePath.endsWith('.flac') ||
              lowerFilePath.endsWith('.m4a') ||
              lowerFilePath.endsWith('.mp4') ||
              lowerFilePath.endsWith('.aac') ||
              lowerFilePath.endsWith('.mp3') ||
              lowerFilePath.endsWith('.opus') ||
              lowerFilePath.endsWith('.ogg');

          if (canProbeFinalMetadata) {
            try {
              final metadata = await PlatformBridge.readFileMetadata(filePath);
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
                final probedFormat = _normalizeAudioFormatValue(
                  metadata['audio_codec']?.toString() ??
                      metadata['format']?.toString(),
                );
                if (probedFormat != null) {
                  finalFormat = probedFormat;
                }
                final probedBitrateKbps = _readPositiveBitrateKbps(
                  metadata['bitrate'] ?? metadata['bit_rate'],
                );
                if (probedBitrateKbps != null &&
                    _isLossyAudioFormat(finalFormat)) {
                  finalBitrateKbps = probedBitrateKbps;
                }

                final resolvedQuality = _resolveDisplayQuality(
                  filePath: filePath,
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
              _log.d('Final audio metadata probe failed for $filePath: $e');
            }
          }

          _log.d('Saving to history - coverUrl: ${trackToDownload.coverUrl}');

          final historyAlbumArtist = normalizeOptionalString(
            trackToDownload.albumArtist,
          );

          final isLossyOutput =
              _isLossyAudioFormat(finalFormat) ||
              lowerFilePath.endsWith('.mp3') ||
              lowerFilePath.endsWith('.opus') ||
              lowerFilePath.endsWith('.ogg');
          final historyBitDepth = isLossyOutput ? null : finalBitDepth;
          final historySampleRate = isLossyOutput ? null : finalSampleRate;
          final historyBitrate = isLossyOutput ? finalBitrateKbps : null;
          final historyTotalTracks = _resolvePositiveMetadataInt(
            trackToDownload.totalTracks,
            backendTotalTracks,
          );
          final historyTotalDiscs = _resolvePositiveMetadataInt(
            trackToDownload.totalDiscs,
            backendTotalDiscs,
          );
          final historyTrackNumber = _resolveMetadataIndex(
            sourceValue: trackToDownload.trackNumber,
            backendValue: backendTrackNum,
            total: historyTotalTracks,
          );
          final historyDiscNumber = _resolveMetadataIndex(
            sourceValue: trackToDownload.discNumber,
            backendValue: backendDiscNum,
            total: historyTotalDiscs,
          );
          final historyTitle =
              _resolveMetadataText(trackToDownload.name, backendTitle) ??
              item.track.name;
          final historyArtist =
              _resolveMetadataText(trackToDownload.artistName, backendArtist) ??
              item.track.artistName;
          final historyAlbum =
              _resolveMetadataText(trackToDownload.albumName, backendAlbum) ??
              item.track.albumName;
          final historyIsrc = _resolveMetadataText(
            trackToDownload.isrc,
            backendISRC,
          );
          final historyReleaseDate = _resolveMetadataText(
            trackToDownload.releaseDate,
            backendYear,
          );
          final historyComposer = _resolveMetadataText(
            trackToDownload.composer,
            backendComposer,
          );

          if (ref.read(settingsProvider).saveDownloadHistory)
            ref
                .read(downloadHistoryProvider.notifier)
                .addToHistory(
                  DownloadHistoryItem(
                    id: item.id,
                    trackName: historyTitle,
                    artistName: historyArtist,
                    albumName: historyAlbum,
                    albumArtist: historyAlbumArtist,
                    coverUrl: normalizeCoverReference(trackToDownload.coverUrl),
                    filePath: filePath,
                    storageMode: effectiveSafMode ? 'saf' : 'app',
                    downloadTreeUri: effectiveSafMode
                        ? settings.downloadTreeUri
                        : null,
                    safRelativeDir: effectiveSafMode ? effectiveOutputDir : null,
                    safFileName: effectiveSafMode
                        ? (finalSafFileName ?? safFileName)
                        : null,
                    safRepaired: false,
                    service: result['service'] as String? ?? item.service,
                    downloadedAt: DateTime.now(),
                    isrc: historyIsrc,
                    spotifyId: trackToDownload.id,
                    trackNumber: historyTrackNumber,
                    totalTracks: historyTotalTracks,
                    discNumber: historyDiscNumber,
                    totalDiscs: historyTotalDiscs,
                    duration: trackToDownload.duration,
                    releaseDate: historyReleaseDate,
                    quality: actualQuality,
                    bitDepth: historyBitDepth,
                    sampleRate: historySampleRate,
                    bitrate: historyBitrate,
                    format: finalFormat,
                    genre: effectiveGenre,
                    composer: historyComposer,
                    label: effectiveLabel,
                    copyright: effectiveCopyright,
                  ),
                );

          removeItem(item.id);
        }
      } else {
        final itemAfterFailure = _findItemById(item.id);
        if (itemAfterFailure == null ||
            _isLocallyCancelled(item.id, item: itemAfterFailure)) {
          _log.i('Download was cancelled, skipping error handling');
          return;
        }

        if (_isPausePending(item.id)) {
          pausedDuringThisRun = true;
          _requeueItemForPause(item.id);
          _log.i('Download pause requested after backend failure, re-queueing');
          return;
        }

        final errorMsg = result['error'] as String? ?? 'Download failed';
        final errorTypeStr = result['error_type'] as String? ?? 'unknown';
        if (errorTypeStr == 'cancelled') {
          if (_isPausePending(item.id)) {
            pausedDuringThisRun = true;
            _requeueItemForPause(item.id);
            _log.i('Download was paused by backend cancellation, re-queueing');
          } else {
            _log.i(
              'Download was cancelled by backend, skipping error handling',
            );
            updateItemStatus(item.id, DownloadStatus.skipped);
          }
          return;
        }

        DownloadErrorType errorType;
        switch (errorTypeStr) {
          case 'not_found':
            errorType = DownloadErrorType.notFound;
            break;
          case 'rate_limit':
            errorType = DownloadErrorType.rateLimit;
            break;
          case 'network':
            errorType = DownloadErrorType.network;
            break;
          case 'permission':
            errorType = DownloadErrorType.permission;
            break;
          default:
            errorType = DownloadErrorType.unknown;
        }

        _log.e('Download failed: $errorMsg (type: $errorTypeStr)');
        updateItemStatus(
          item.id,
          DownloadStatus.failed,
          error: errorMsg,
          errorType: errorType,
        );
        _failedInSession++;

        try {
          await PlatformBridge.cleanupConnections();
        } catch (e) {
          _log.e('Post-failure connection cleanup failed: $e');
        }
      }

      _downloadCount++;
      if (_downloadCount % DownloadQueueNotifier._cleanupInterval == 0) {
        _log.d(
          'Cleaning up idle connections (after $_downloadCount downloads)...',
        );
        try {
          await PlatformBridge.cleanupConnections();
        } catch (e) {
          _log.e('Connection cleanup failed: $e');
        }
      }
    } catch (e, stackTrace) {
      final itemAfterError = _findItemById(item.id);
      if (itemAfterError == null ||
          _isLocallyCancelled(item.id, item: itemAfterError)) {
        _log.i('Download was cancelled, skipping error handling');
        return;
      }

      if (_isPausePending(item.id)) {
        pausedDuringThisRun = true;
        _requeueItemForPause(item.id);
        _log.i('Download pause requested after exception, re-queueing');
        return;
      }

      _log.e('Exception: $e', e, stackTrace);

      String errorMsg = e.toString();
      DownloadErrorType errorType = DownloadErrorType.unknown;

      if (errorMsg.contains('could not find Deezer equivalent') ||
          errorMsg.contains('track not found on Deezer')) {
        errorMsg = 'Track not found on Deezer (Metadata Unavailable)';
        errorType = DownloadErrorType.notFound;
      }

      updateItemStatus(
        item.id,
        DownloadStatus.failed,
        error: errorMsg,
        errorType: errorType,
      );
      _failedInSession++;

      try {
        await PlatformBridge.cleanupConnections();
      } catch (cleanupErr) {
        _log.e('Post-exception connection cleanup failed: $cleanupErr');
      }
    } finally {
      if (pausedDuringThisRun) {
        _pausePendingItemIds.remove(item.id);
      }
    }
  }
}
