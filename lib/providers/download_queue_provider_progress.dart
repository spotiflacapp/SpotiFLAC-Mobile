// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of 'download_queue_provider.dart';

class _ProgressUpdate {
  final DownloadStatus status;
  final double progress;
  final double? speedMBps;
  final int? bytesReceived;
  final int? bytesTotal;
  final String preparationStage;

  const _ProgressUpdate({
    required this.status,
    required this.progress,
    this.speedMBps,
    this.bytesReceived,
    this.bytesTotal,
    this.preparationStage = '',
  });
}

extension _DownloadQueueProgress on DownloadQueueNotifier {
  double _normalizeProgressForUi(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if (clamped <= 0) return 0;
    if (clamped >= 1) return 1;
    final rounded = double.parse(clamped.toStringAsFixed(2));
    return rounded == 0 ? 0.01 : rounded;
  }

  double _normalizeSpeedForUi(double value) {
    if (value <= 0) return 0;
    return double.parse(value.toStringAsFixed(1));
  }

  int _normalizeBytesForUi(int value) {
    if (value <= 0) return 0;
    return (value ~/ DownloadQueueNotifier._bytesUiStep) *
        DownloadQueueNotifier._bytesUiStep;
  }

  bool _shouldUpdateProgressNotification({
    required String trackName,
    required String artistName,
    required int progress,
    required int total,
    required int queueCount,
  }) {
    final safeTotal = total > 0 ? total : 1;
    final percent = ((progress * 100) / safeTotal).round().clamp(0, 100);
    final changed =
        trackName != _lastNotifTrackName ||
        artistName != _lastNotifArtistName ||
        percent != _lastNotifPercent ||
        queueCount != _lastNotifQueueCount;
    if (!changed) {
      return false;
    }

    _lastNotifTrackName = trackName;
    _lastNotifArtistName = artistName;
    _lastNotifPercent = percent;
    _lastNotifQueueCount = queueCount;
    return true;
  }

  void _startMultiProgressPolling() {
    _idleProgressPollTick = 0;
    _progressPoller.start(useStream: Platform.isAndroid || Platform.isIOS);
  }

  /// Idle-cadence gate for the fallback polling timer: polls every tick while
  /// a download is active, but only every [_idleProgressPollEveryTicks]th
  /// tick while idle-but-queued, and not at all while paused/empty.
  bool _shouldPollDownloadProgressTick() {
    final currentItems = state.items;
    final hasQueuedItems = currentItems.any(
      (item) => item.status == DownloadStatus.queued,
    );
    final hasActiveItems = currentItems.any(
      (item) =>
          item.status == DownloadStatus.downloading ||
          item.status == DownloadStatus.finalizing,
    );

    if (!hasActiveItems) {
      if (state.isPaused || !hasQueuedItems) {
        _idleProgressPollTick = 0;
        return false;
      }

      _idleProgressPollTick =
          (_idleProgressPollTick + 1) %
          DownloadQueueNotifier._idleProgressPollEveryTicks;
      return _idleProgressPollTick == 0;
    }

    _idleProgressPollTick = 0;
    return true;
  }

  void _processAllDownloadProgress(Map<String, dynamic> allProgress) {
    final rawItems = allProgress['items'];
    final items = rawItems is Map
        ? rawItems.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final currentItems = state.items;
    final lookup = state.lookup;
    final queuedCount = lookup.queuedCount;
    final downloadingCount = lookup.activeDownloadsCount;
    DownloadItem? firstDownloading;
    bool hasFinalizingItem = lookup.finalizingCount > 0;
    String? finalizingTrackName;
    String? finalizingArtistName;
    if (downloadingCount > 0 || hasFinalizingItem) {
      for (final item in currentItems) {
        if (firstDownloading == null &&
            item.status == DownloadStatus.downloading) {
          firstDownloading = item;
        }
        if (finalizingTrackName == null &&
            item.status == DownloadStatus.finalizing) {
          hasFinalizingItem = true;
          finalizingTrackName = item.track.name;
          finalizingArtistName = item.track.artistName;
        }
        if ((downloadingCount == 0 || firstDownloading != null) &&
            (!hasFinalizingItem || finalizingTrackName != null)) {
          break;
        }
      }
    }
    final progressUpdates = <String, _ProgressUpdate>{};

    for (final entry in items.entries) {
      final itemId = entry.key;
      final localItem = lookup.byItemId[itemId];
      if (localItem == null) {
        continue;
      }
      if (_isPausePending(itemId)) {
        PlatformBridge.clearItemProgress(itemId).catchError((_) {});
        continue;
      }
      if (localItem.status == DownloadStatus.skipped) {
        PlatformBridge.clearItemProgress(itemId).catchError((_) {});
        continue;
      }
      if (localItem.status == DownloadStatus.completed ||
          localItem.status == DownloadStatus.failed) {
        continue;
      }
      if (localItem.status == DownloadStatus.finalizing) {
        PlatformBridge.clearItemProgress(itemId).catchError((_) {});
        hasFinalizingItem = true;
        finalizingTrackName = localItem.track.name;
        finalizingArtistName = localItem.track.artistName;
        continue;
      }
      final rawItemProgress = entry.value;
      if (rawItemProgress is! Map) {
        continue;
      }
      final itemProgress = Map<String, dynamic>.from(rawItemProgress);
      final bytesReceived =
          (itemProgress['bytes_received'] as num?)?.toInt() ?? 0;
      final bytesTotal = (itemProgress['bytes_total'] as num?)?.toInt() ?? 0;
      final speedMBps = (itemProgress['speed_mbps'] as num?)?.toDouble() ?? 0.0;
      final isDownloading = itemProgress['is_downloading'] as bool? ?? false;
      final status = itemProgress['status'] as String? ?? 'downloading';
      final progressFromBackend =
          (itemProgress['progress'] as num?)?.toDouble() ?? 0.0;
      final hasRealProgress =
          status != 'preparing' &&
          (bytesReceived > 0 || bytesTotal > 0 || progressFromBackend > 0);

      if (status == 'finalizing') {
        progressUpdates[itemId] = const _ProgressUpdate(
          status: DownloadStatus.finalizing,
          progress: 1.0,
        );
        hasFinalizingItem = true;
        finalizingTrackName = localItem.track.name;
        finalizingArtistName = localItem.track.artistName;
        continue;
      }

      if (status == 'preparing') {
        progressUpdates[itemId] = _ProgressUpdate(
          status: DownloadStatus.downloading,
          progress: 0.0,
          speedMBps: 0,
          bytesReceived: 0,
          bytesTotal: 0,
          preparationStage: itemProgress['stage']?.toString() ?? '',
        );

        if (LogBuffer.loggingEnabled) {
          _log.d('Preparing [$itemId]: waiting for real download bytes');
        }
        continue;
      }

      if (isDownloading || hasRealProgress) {
        double percentage = 0.0;
        if (bytesTotal > 0) {
          percentage = bytesReceived / bytesTotal;
        } else {
          percentage = progressFromBackend;
        }
        final normalizedProgress = _normalizeProgressForUi(percentage);
        final normalizedSpeed = _normalizeSpeedForUi(speedMBps);
        final normalizedBytes = _normalizeBytesForUi(bytesReceived);

        progressUpdates[itemId] = _ProgressUpdate(
          status: DownloadStatus.downloading,
          progress: normalizedProgress,
          speedMBps: normalizedSpeed,
          bytesReceived: normalizedBytes,
          bytesTotal: bytesTotal,
        );

        if (LogBuffer.loggingEnabled) {
          final mbReceived = bytesReceived / (1024 * 1024);
          final mbTotal = bytesTotal / (1024 * 1024);
          if (bytesTotal > 0) {
            _log.d(
              'Progress [$itemId]: ${(percentage * 100).toStringAsFixed(1)}% (${mbReceived.toStringAsFixed(2)}/${mbTotal.toStringAsFixed(2)} MB) @ ${speedMBps.toStringAsFixed(2)} MB/s',
            );
          } else {
            _log.d(
              'Progress [$itemId]: ${(percentage * 100).toStringAsFixed(1)}% (stream/unknown size) @ ${speedMBps.toStringAsFixed(2)} MB/s',
            );
          }
        }
      }
    }

    if (progressUpdates.isNotEmpty) {
      var updatedItems = currentItems;
      bool changed = false;
      final changedIndices = <int>[];

      for (final entry in progressUpdates.entries) {
        final index = lookup.indexByItemId[entry.key];
        if (index == null) continue;
        final current = updatedItems[index];
        if (current.status == DownloadStatus.skipped ||
            current.status == DownloadStatus.completed ||
            current.status == DownloadStatus.failed) {
          continue;
        }
        final update = entry.value;
        if (current.status == DownloadStatus.finalizing &&
            update.status != DownloadStatus.finalizing) {
          continue;
        }
        final next = current.copyWith(
          status: update.status,
          progress: update.progress,
          speedMBps: update.speedMBps ?? current.speedMBps,
          bytesReceived: update.bytesReceived ?? current.bytesReceived,
          bytesTotal: update.bytesTotal ?? current.bytesTotal,
          preparationStage: update.preparationStage,
        );
        if (current.status != next.status ||
            current.progress != next.progress ||
            current.speedMBps != next.speedMBps ||
            current.bytesReceived != next.bytesReceived ||
            current.bytesTotal != next.bytesTotal ||
            current.preparationStage != next.preparationStage) {
          if (!changed) {
            updatedItems = List<DownloadItem>.from(updatedItems);
            changed = true;
          }
          updatedItems[index] = next;
          changedIndices.add(index);
        }
      }

      if (changed) {
        state = state.copyWith(
          items: updatedItems,
          lookup: state.lookup.updatedForIndices(
            previousItems: currentItems,
            nextItems: updatedItems,
            changedIndices: changedIndices,
          ),
        );
      }
    }

    if (hasFinalizingItem && finalizingTrackName != null) {
      final safeArtistName = finalizingArtistName ?? '';
      if (Platform.isAndroid) {
        _maybeUpdateAndroidDownloadService(
          trackName: finalizingTrackName,
          artistName: _notificationService.embeddingMetadataLabel,
          progress: 100,
          total: 100,
          queueCount: queuedCount,
          status: 'finalizing',
        );
      } else if (finalizingTrackName != _lastFinalizingTrackName ||
          safeArtistName != _lastFinalizingArtistName) {
        _notificationService.showDownloadFinalizing(
          trackName: finalizingTrackName,
          artistName: safeArtistName,
        );
        _lastFinalizingTrackName = finalizingTrackName;
        _lastFinalizingArtistName = safeArtistName;
      }
      return;
    }
    _lastFinalizingTrackName = null;
    _lastFinalizingArtistName = null;

    if (items.isNotEmpty) {
      if (downloadingCount > 0 && firstDownloading != null) {
        final rawProgress = items[firstDownloading.id];
        if (rawProgress is! Map) {
          return;
        }
        final selectedProgress = Map<String, dynamic>.from(rawProgress);
        final bytesReceived =
            (selectedProgress['bytes_received'] as num?)?.toInt() ?? 0;
        final bytesTotal =
            (selectedProgress['bytes_total'] as num?)?.toInt() ?? 0;
        final backendStatus =
            selectedProgress['status'] as String? ?? 'downloading';
        final trackName = downloadingCount == 1
            ? firstDownloading.track.name
            : '$downloadingCount downloads';
        final artistName = downloadingCount == 1
            ? firstDownloading.track.artistName
            : 'Downloading...';

        int notifProgress = bytesReceived;
        int notifTotal = bytesTotal;

        final progressPercent =
            (selectedProgress['progress'] as num?)?.toDouble() ?? 0.0;
        if (backendStatus == 'preparing') {
          notifProgress = 0;
          notifTotal = 0;
        } else if (bytesTotal <= 0) {
          notifProgress = (progressPercent * 100).toInt();
          notifTotal = 100;
        }
        final serviceStatus = notifTotal <= 0 ? 'preparing' : 'downloading';

        if (!Platform.isAndroid &&
            _shouldUpdateProgressNotification(
              trackName: trackName,
              artistName: artistName,
              progress: notifProgress,
              total: notifTotal,
              queueCount: queuedCount,
            )) {
          final safeNotifTotal = notifTotal > 0 ? notifTotal : 1;
          _notificationService.showDownloadProgress(
            trackName: trackName,
            artistName: artistName,
            progress: notifProgress,
            total: safeNotifTotal,
          );
        }

        if (Platform.isAndroid) {
          _maybeUpdateAndroidDownloadService(
            trackName: firstDownloading.track.name,
            artistName: firstDownloading.track.artistName,
            progress: notifProgress,
            total: notifTotal,
            queueCount: queuedCount,
            status: serviceStatus,
          );
        }
      }
    }
  }

  void _maybeUpdateAndroidDownloadService({
    required String trackName,
    required String artistName,
    required int progress,
    required int total,
    required int queueCount,
    String status = 'downloading',
  }) {
    final now = DateTime.now();
    final progressBucket = total <= 0
        ? -1
        : (() {
            final progressPercent = ((progress * 100) / total)
                .round()
                .clamp(0, 100)
                .toInt();
            return progressPercent == 100
                ? 100
                : ((progressPercent ~/
                              DownloadQueueNotifier
                                  ._serviceProgressStepPercent) *
                          DownloadQueueNotifier._serviceProgressStepPercent)
                      .clamp(0, 100)
                      .toInt();
          })();

    final didContentChange =
        trackName != _lastServiceTrackName ||
        artistName != _lastServiceArtistName ||
        status != _lastServiceStatus ||
        queueCount != _lastServiceQueueCount ||
        progressBucket != _lastServicePercent;
    final allowHeartbeat =
        now.difference(_lastServiceUpdateAt) >= const Duration(seconds: 5);

    if (!didContentChange && !allowHeartbeat) {
      return;
    }

    _lastServiceTrackName = trackName;
    _lastServiceArtistName = artistName;
    _lastServiceStatus = status;
    _lastServicePercent = progressBucket;
    _lastServiceQueueCount = queueCount;
    _lastServiceUpdateAt = now;

    PlatformBridge.updateDownloadServiceProgress(
      trackName: trackName,
      artistName: artistName,
      progress: progress,
      total: total,
      queueCount: queueCount,
      status: status,
    ).catchError((_) {});
  }

  void _stopProgressPolling() {
    _progressPoller.stop();
    _idleProgressPollTick = 0;
    _lastServiceTrackName = null;
    _lastServiceArtistName = null;
    _lastServiceStatus = null;
    _lastServicePercent = -1;
    _lastServiceQueueCount = -1;
    _lastServiceUpdateAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastFinalizingTrackName = null;
    _lastFinalizingArtistName = null;
    _lastNotifTrackName = null;
    _lastNotifArtistName = null;
    _lastNotifPercent = -1;
    _lastNotifQueueCount = -1;
  }
}
