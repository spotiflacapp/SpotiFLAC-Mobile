// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of 'download_history_provider.dart';

/// Startup maintenance: SAF repair, orphan cleanup, and audio-metadata
/// backfill that run staggered after the initial history load.
extension _HistoryStartupMaintenance on DownloadHistoryNotifier {
  void _scheduleStartupMaintenance(List<DownloadHistoryItem> initialItems) {
    if (_startupMaintenanceScheduled) {
      return;
    }
    _startupMaintenanceScheduled = true;

    unawaited(
      Future<void>.delayed(
        DownloadHistoryNotifier._startupMaintenanceDelay,
        () async {
          try {
            final prefs = await SharedPreferences.getInstance();

            if (Platform.isAndroid) {
              await _repairMissingSafEntries(
                initialItems,
                maxItems: DownloadHistoryNotifier._safRepairMaxPerLaunch,
                prefs: prefs,
              );
              await Future<void>.delayed(
                DownloadHistoryNotifier._startupMaintenanceStepGap,
              );
            }

            await _cleanupOrphanedDownloadsIncremental(
              maxItems: DownloadHistoryNotifier._orphanCleanupMaxPerLaunch,
              prefs: prefs,
            );
            await Future<void>.delayed(
              DownloadHistoryNotifier._startupMaintenanceStepGap,
            );

            final currentItems = state.items;
            if (currentItems.isNotEmpty) {
              await _backfillAudioMetadata(
                currentItems,
                maxItems:
                    DownloadHistoryNotifier._audioMetadataBackfillMaxPerLaunch,
                prefs: prefs,
              );
            }
          } catch (e, stack) {
            _historyLog.w('Startup history maintenance failed: $e');
            _historyLog.d('$stack');
          }
        },
      ),
    );
  }

  int _readStartupCursor(SharedPreferences prefs, String key, int totalCount) {
    if (totalCount <= 0) {
      return 0;
    }
    final cursor = prefs.getInt(key) ?? 0;
    if (cursor < 0 || cursor >= totalCount) {
      return 0;
    }
    return cursor;
  }

  Future<void> _writeStartupCursor(
    SharedPreferences prefs,
    String key,
    int nextCursor,
    int totalCount,
  ) async {
    if (totalCount <= 0 || nextCursor <= 0 || nextCursor >= totalCount) {
      await prefs.remove(key);
      return;
    }
    await prefs.setInt(key, nextCursor);
  }

  String _fileNameFromUri(String uri) {
    try {
      final parsed = Uri.parse(uri);
      if (parsed.pathSegments.isNotEmpty) {
        return Uri.decodeComponent(parsed.pathSegments.last);
      }
    } catch (_) {}
    return '';
  }

  List<String> _conversionRenameCandidates(
    String fileName, {
    bool includeAlternateExtensions = false,
  }) {
    if (fileName.trim().isEmpty) return const [];
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0) return [fileName];
    final baseName = fileName.substring(0, dotIndex);
    final extension = fileName.substring(dotIndex);
    final plainBase = baseName.endsWith('_converted')
        ? baseName.substring(0, baseName.length - '_converted'.length)
        : baseName;
    return <String>{
      fileName,
      if (plainBase != baseName) '$plainBase$extension',
      if (plainBase == baseName) '${baseName}_converted$extension',
      if (includeAlternateExtensions)
        for (final audioExtension in DownloadHistoryNotifier._audioExtensions)
          '$plainBase$audioExtension',
    }.toList(growable: false);
  }

  Future<void> _repairMissingSafEntries(
    List<DownloadHistoryItem> items, {
    required int maxItems,
    required SharedPreferences prefs,
  }) async {
    if (_isSafRepairInProgress || items.isEmpty) {
      return;
    }
    _isSafRepairInProgress = true;

    final candidateIndexes = <int>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.storageMode != 'saf') continue;
      if (item.downloadTreeUri == null || item.downloadTreeUri!.isEmpty) {
        continue;
      }
      final hasFilePath = item.filePath.trim().isNotEmpty;
      final hasSafFileName =
          item.safFileName != null && item.safFileName!.trim().isNotEmpty;
      if (!hasFilePath && !hasSafFileName) {
        continue;
      }
      candidateIndexes.add(i);
    }

    if (candidateIndexes.isEmpty) {
      await prefs.remove(DownloadHistoryNotifier._startupSafRepairCursorKey);
      _isSafRepairInProgress = false;
      return;
    }

    final startCursor = _readStartupCursor(
      prefs,
      DownloadHistoryNotifier._startupSafRepairCursorKey,
      candidateIndexes.length,
    );
    final endCursor = (startCursor + maxItems).clamp(
      0,
      candidateIndexes.length,
    );
    final selectedIndexes = candidateIndexes.sublist(startCursor, endCursor);

    if (selectedIndexes.isEmpty) {
      await prefs.remove(DownloadHistoryNotifier._startupSafRepairCursorKey);
      _isSafRepairInProgress = false;
      return;
    }

    final updatedItems = [...items];
    final persistedUpdates = <Map<String, dynamic>>[];
    var changed = false;
    var repairedCount = 0;
    var verifiedCount = 0;

    try {
      for (var c = 0; c < selectedIndexes.length; c++) {
        final i = selectedIndexes[c];
        final item = items[i];
        final rawPath = item.filePath.trim();
        final isDirectSafUri = rawPath.isNotEmpty && isContentUri(rawPath);

        if (isDirectSafUri) {
          final exists = await fileExists(rawPath);
          if (exists) {
            final verified = item.copyWith(
              safRepaired: true,
              safFileName: item.safFileName ?? _fileNameFromUri(rawPath),
            );
            updatedItems[i] = verified;
            changed = true;
            verifiedCount++;
            persistedUpdates.add(verified.toJson());
            continue;
          }
        }

        var fallbackName = (item.safFileName ?? '').trim();
        if (fallbackName.isEmpty && isDirectSafUri) {
          fallbackName = _fileNameFromUri(rawPath);
        }
        if (fallbackName.isEmpty) {
          _historyLog.w('Missing SAF filename for history item: ${item.id}');
          continue;
        }

        try {
          Map<String, dynamic>? resolved;
          String? resolvedFileName;
          for (final candidate in _conversionRenameCandidates(fallbackName)) {
            final candidateResult = await PlatformBridge.resolveSafFile(
              treeUri: item.downloadTreeUri!,
              relativeDir: item.safRelativeDir ?? '',
              fileName: candidate,
            );
            final candidateUri = (candidateResult['uri'] as String? ?? '')
                .trim();
            if (candidateUri.isEmpty) continue;
            resolved = candidateResult;
            resolvedFileName = candidate;
            break;
          }
          if (resolved == null || resolvedFileName == null) continue;
          final newUri = (resolved['uri'] as String).trim();

          final newRelativeDir = resolved['relative_dir'] as String?;
          final updated = item.copyWith(
            filePath: newUri,
            safRelativeDir:
                (newRelativeDir != null && newRelativeDir.isNotEmpty)
                ? newRelativeDir
                : item.safRelativeDir,
            safFileName: resolvedFileName,
            safRepaired: true,
          );

          updatedItems[i] = updated;
          changed = true;
          repairedCount++;
          persistedUpdates.add(updated.toJson());
        } catch (e) {
          _historyLog.w('Failed to repair SAF URI: $e');
        }

        if ((c + 1) % DownloadHistoryNotifier._safRepairBatchSize == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
      }

      if (changed) {
        await _db.upsertBatch(persistedUpdates);
        state = state.copyWith(
          items: updatedItems,
          loadedIndexVersion: state.loadedIndexVersion + 1,
          lookupItems: _lookupItemsWithUpdates(updatedItems),
        );
        _historyLog.i(
          'SAF repair pass: verified=$verifiedCount, repaired=$repairedCount, checked=${selectedIndexes.length}',
        );
      }
      await _writeStartupCursor(
        prefs,
        DownloadHistoryNotifier._startupSafRepairCursorKey,
        endCursor,
        candidateIndexes.length,
      );
    } finally {
      _isSafRepairInProgress = false;
    }
  }

  bool _supportsAudioMetadataProbe(String filePath) {
    final trimmed = filePath.trim().toLowerCase();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('content://')) return true;
    return trimmed.endsWith('.flac') ||
        trimmed.endsWith('.m4a') ||
        trimmed.endsWith('.mp4') ||
        trimmed.endsWith('.aac') ||
        trimmed.endsWith('.mp3') ||
        trimmed.endsWith('.opus') ||
        trimmed.endsWith('.ogg');
  }

  bool _shouldBackfillAudioMetadata(DownloadHistoryItem item) {
    return _needsAverageBitrateBackfill(item) ||
        _shouldBackfillAudioMetadataIgnoringBitrate(item);
  }

  bool _needsAverageBitrateBackfill(DownloadHistoryItem item) {
    return _supportsAudioMetadataProbe(item.filePath) &&
        (item.bitrate == null || item.bitrate! <= 0) &&
        item.duration != null &&
        item.duration! > 0;
  }

  bool _shouldBackfillAudioMetadataIgnoringBitrate(DownloadHistoryItem item) {
    if (!_supportsAudioMetadataProbe(item.filePath)) {
      return false;
    }

    final trimmedPath = item.filePath.trim().toLowerCase();
    final hasResolvedSpecs =
        item.bitDepth != null &&
        item.bitDepth! > 0 &&
        item.sampleRate != null &&
        item.sampleRate! > 0;
    final needsFormatBackfill = normalizeOptionalString(item.format) == null;
    final needsLosslessSpecProbe =
        !hasResolvedSpecs &&
        (trimmedPath.endsWith('.flac') ||
            trimmedPath.endsWith('.m4a') ||
            trimmedPath.endsWith('.mp4') ||
            trimmedPath.endsWith('.aac') ||
            trimmedPath.startsWith('content://'));

    if (hasResolvedSpecs && !isPlaceholderQualityLabel(item.quality)) {
      final needsComposerBackfill =
          normalizeOptionalString(item.composer) == null;
      final needsDurationBackfill = item.duration == null || item.duration == 0;
      final needsTrackNumberBackfill = item.trackNumber == null;
      final needsTotalTracksBackfill = item.totalTracks == null;
      final needsDiscNumberBackfill = item.discNumber == null;
      final needsTotalDiscsBackfill = item.totalDiscs == null;
      return needsComposerBackfill ||
          needsFormatBackfill ||
          needsDurationBackfill ||
          needsTrackNumberBackfill ||
          needsTotalTracksBackfill ||
          needsDiscNumberBackfill ||
          needsTotalDiscsBackfill;
    }

    final needsComposerBackfill =
        normalizeOptionalString(item.composer) == null;
    final needsDurationBackfill = item.duration == null || item.duration == 0;
    final needsTrackNumberBackfill = item.trackNumber == null;
    final needsTotalTracksBackfill = item.totalTracks == null;
    final needsDiscNumberBackfill = item.discNumber == null;
    final needsTotalDiscsBackfill = item.totalDiscs == null;
    return needsLosslessSpecProbe ||
        needsFormatBackfill ||
        isPlaceholderQualityLabel(item.quality) ||
        normalizeOptionalString(item.quality) == null ||
        needsComposerBackfill ||
        needsDurationBackfill ||
        needsTrackNumberBackfill ||
        needsTotalTracksBackfill ||
        needsDiscNumberBackfill ||
        needsTotalDiscsBackfill;
  }

  /// Errors that indicate the file content itself cannot be parsed — as
  /// opposed to transient conditions like a missing file or an unmounted
  /// SAF volume. These never resolve on retry.
  static bool _isPermanentProbeError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('failed to parse') ||
        lower.contains('head incorrect') ||
        lower.contains('invalid') ||
        lower.contains('not a ');
  }

  Set<String> _readAudioProbeFailedPaths(SharedPreferences prefs) {
    final stored = prefs.getStringList(
      DownloadHistoryNotifier._audioProbeFailedPathsKey,
    );
    if (stored == null || stored.isEmpty) return <String>{};
    return stored.toSet();
  }

  Future<void> _rememberAudioProbeFailure(
    SharedPreferences prefs,
    String filePath,
  ) async {
    final normalized = filePath.trim();
    if (normalized.isEmpty) return;
    final stored =
        prefs.getStringList(
          DownloadHistoryNotifier._audioProbeFailedPathsKey,
        ) ??
        <String>[];
    if (stored.contains(normalized)) return;
    stored.add(normalized);
    while (stored.length > DownloadHistoryNotifier._audioProbeFailedPathsMax) {
      stored.removeAt(0);
    }
    await prefs.setStringList(
      DownloadHistoryNotifier._audioProbeFailedPathsKey,
      stored,
    );
  }

  Future<Map<String, dynamic>?> _probeAudioMetadata(
    String filePath, {
    String? fallbackQuality,
  }) async {
    if (!_supportsAudioMetadataProbe(filePath)) {
      return null;
    }

    try {
      final result = await PlatformBridge.readDisplayAudioMetadata(filePath);
      final error = result['error'];
      if (error != null) {
        if (_isPermanentProbeError(error.toString())) {
          // The file content itself is unparseable (e.g. an MP4 stream under
          // a .flac name); retrying on every launch can never succeed.
          return const {'permanent_failure': true};
        }
        return null;
      }

      final bitDepth = readPositiveInt(result['bit_depth']);
      final sampleRate = readPositiveInt(result['sample_rate']);
      final detectedFormat = normalizeAudioFormatValue(
        result['audio_codec']?.toString() ?? result['format']?.toString(),
      );
      final bitrateKbps = readPositiveBitrateKbps(
        result['bitrate'] ?? result['bit_rate'],
      );
      final quality = resolveDisplayQuality(
        filePath: filePath,
        detectedFormat: detectedFormat,
        bitDepth: bitDepth,
        sampleRate: sampleRate,
        bitrateKbps: bitrateKbps,
        storedQuality: fallbackQuality,
      );
      final composer = normalizeOptionalString(result['composer']?.toString());
      final duration = readPositiveInt(result['duration']);
      final trackNumber = readPositiveInt(result['track_number']);
      final totalTracks = readPositiveInt(result['total_tracks']);
      final discNumber = readPositiveInt(result['disc_number']);
      final totalDiscs = readPositiveInt(result['total_discs']);

      if (quality == null &&
          bitDepth == null &&
          sampleRate == null &&
          bitrateKbps == null &&
          detectedFormat == null &&
          composer == null &&
          duration == null &&
          trackNumber == null &&
          totalTracks == null &&
          discNumber == null &&
          totalDiscs == null) {
        return null;
      }

      return {
        'quality': quality,
        'bitDepth': bitDepth,
        'sampleRate': sampleRate,
        'bitrate': bitrateKbps,
        'format': detectedFormat,
        'bitrateKbps': bitrateKbps,
        'composer': composer,
        'duration': duration,
        'trackNumber': trackNumber,
        'totalTracks': totalTracks,
        'discNumber': discNumber,
        'totalDiscs': totalDiscs,
      };
    } catch (e) {
      _historyLog.d('Audio metadata probe failed for $filePath: $e');
      return null;
    }
  }

  Future<void> _backfillAudioMetadata(
    List<DownloadHistoryItem> items, {
    required int maxItems,
    required SharedPreferences prefs,
  }) async {
    if (_isAudioMetadataBackfillInProgress || items.isEmpty) {
      return;
    }
    _isAudioMetadataBackfillInProgress = true;

    try {
      final probeFailedPaths = _readAudioProbeFailedPaths(prefs);
      final candidateIndexes = <int>[];
      for (var i = 0; i < items.length; i++) {
        if (!_shouldBackfillAudioMetadata(items[i])) continue;
        if (probeFailedPaths.contains(items[i].filePath.trim())) continue;
        candidateIndexes.add(i);
      }

      if (candidateIndexes.isEmpty) {
        await prefs.remove(DownloadHistoryNotifier._startupAudioCursorKey);
        return;
      }

      final startCursor = _readStartupCursor(
        prefs,
        DownloadHistoryNotifier._startupAudioCursorKey,
        candidateIndexes.length,
      );
      final endCursor = (startCursor + maxItems).clamp(
        0,
        candidateIndexes.length,
      );
      final selectedIndexes = candidateIndexes.sublist(startCursor, endCursor);

      if (selectedIndexes.isEmpty) {
        await prefs.remove(DownloadHistoryNotifier._startupAudioCursorKey);
        return;
      }

      List<DownloadHistoryItem>? updatedItems;
      final persistedUpdates = <Map<String, dynamic>>[];
      var refreshedCount = 0;

      for (final index in selectedIndexes) {
        final item = items[index];

        Map<String, dynamic>? probed;
        if (_shouldBackfillAudioMetadataIgnoringBitrate(item)) {
          probed = await _probeAudioMetadata(
            item.filePath,
            fallbackQuality: item.quality,
          );
        } else if (_needsAverageBitrateBackfill(item)) {
          // A stat is enough for average bitrate and avoids copying an entire
          // SAF file to cache merely to update the Library badge.
          final stat = await fileStat(item.filePath);
          final bitrate = estimateAverageBitrateKbps(
            fileSizeBytes: stat?.size,
            durationSeconds: item.duration,
          );
          if (bitrate != null) {
            probed = {'bitrate': bitrate};
          }
        }
        if (probed == null) {
          continue;
        }
        if (probed['permanent_failure'] == true) {
          // Remember the path so this file stops being reselected on every
          // launch; the content can never parse, only a re-download fixes it.
          await _rememberAudioProbeFailure(prefs, item.filePath);
          continue;
        }

        final resolvedQuality = normalizeOptionalString(
          probed['quality'] as String?,
        );
        final resolvedBitDepth = probed['bitDepth'] as int?;
        final resolvedSampleRate = probed['sampleRate'] as int?;
        final resolvedBitrate = probed['bitrate'] as int?;
        final resolvedFormat = normalizeOptionalString(
          probed['format'] as String?,
        );
        final resolvedComposer = normalizeOptionalString(
          probed['composer'] as String?,
        );
        final resolvedDuration = probed['duration'] as int?;
        final resolvedTrackNumber = probed['trackNumber'] as int?;
        final resolvedTotalTracks = probed['totalTracks'] as int?;
        final resolvedDiscNumber = probed['discNumber'] as int?;
        final resolvedTotalDiscs = probed['totalDiscs'] as int?;

        final qualityChanged =
            resolvedQuality != null && resolvedQuality != item.quality;
        final bitDepthChanged =
            resolvedBitDepth != null && resolvedBitDepth != item.bitDepth;
        final sampleRateChanged =
            resolvedSampleRate != null && resolvedSampleRate != item.sampleRate;
        final bitrateChanged =
            resolvedBitrate != null && resolvedBitrate != item.bitrate;
        final formatChanged =
            resolvedFormat != null && resolvedFormat != item.format;
        final composerChanged =
            resolvedComposer != null && resolvedComposer != item.composer;
        final durationChanged =
            resolvedDuration != null && resolvedDuration != item.duration;
        final trackNumberChanged =
            resolvedTrackNumber != null &&
            resolvedTrackNumber != item.trackNumber;
        final totalTracksChanged =
            resolvedTotalTracks != null &&
            resolvedTotalTracks != item.totalTracks;
        final discNumberChanged =
            resolvedDiscNumber != null && resolvedDiscNumber != item.discNumber;
        final totalDiscsChanged =
            resolvedTotalDiscs != null && resolvedTotalDiscs != item.totalDiscs;

        if (!qualityChanged &&
            !bitDepthChanged &&
            !sampleRateChanged &&
            !bitrateChanged &&
            !formatChanged &&
            !composerChanged &&
            !durationChanged &&
            !trackNumberChanged &&
            !totalTracksChanged &&
            !discNumberChanged &&
            !totalDiscsChanged) {
          continue;
        }

        final updated = item.copyWith(
          quality: resolvedQuality,
          bitDepth: resolvedBitDepth,
          sampleRate: resolvedSampleRate,
          bitrate: resolvedBitrate,
          format: resolvedFormat,
          composer: resolvedComposer,
          duration: resolvedDuration,
          trackNumber: resolvedTrackNumber,
          totalTracks: resolvedTotalTracks,
          discNumber: resolvedDiscNumber,
          totalDiscs: resolvedTotalDiscs,
        );
        updatedItems ??= [...items];
        updatedItems[index] = updated;
        persistedUpdates.add(updated.toJson());
        refreshedCount++;
      }

      if (persistedUpdates.isNotEmpty && updatedItems != null) {
        await _db.upsertBatch(persistedUpdates);
        state = state.copyWith(
          items: updatedItems,
          loadedIndexVersion: state.loadedIndexVersion + 1,
          lookupItems: _lookupItemsWithUpdates(updatedItems),
        );
      }

      await _writeStartupCursor(
        prefs,
        DownloadHistoryNotifier._startupAudioCursorKey,
        endCursor,
        candidateIndexes.length,
      );

      if (refreshedCount > 0) {
        _historyLog.i(
          'Audio metadata backfill refreshed $refreshedCount items',
        );
      }
    } finally {
      _isAudioMetadataBackfillInProgress = false;
    }
  }
}
