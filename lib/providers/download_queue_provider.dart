import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/models/download_item.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/services/app_state_database.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/services/download_request_payload.dart';
import 'package:spotiflac_android/services/ffmpeg_service.dart';
import 'package:spotiflac_android/services/notification_service.dart';
import 'package:spotiflac_android/utils/logger.dart' hide log;
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/utils/artist_utils.dart';
import 'package:spotiflac_android/utils/int_utils.dart';
import 'package:spotiflac_android/providers/download_history_provider.dart';

export 'package:spotiflac_android/providers/download_history_provider.dart';

export 'package:spotiflac_android/services/history_database.dart'
    show HistoryLookupRequest, HistoryBatchLookupRequest;

part 'download_queue/download_processor.dart';
part 'download_queue/download_helpers.dart';

final _log = AppLogger('DownloadQueue');

final _invalidFolderChars = RegExp(r'[<>:"/\\|?*]');
final _trimDotsAndSpacesRegex = RegExp(r'^[. ]+|[. ]+$');
final _trimUnderscoresAndSpacesRegex = RegExp(r'^[_ ]+|[_ ]+$');
final _multiWhitespaceRegex = RegExp(r'\s+');
final _multiUnderscoreRegex = RegExp(r'_+');

int? _readPositiveBitrateKbps(dynamic value) {
  final parsed = readPositiveInt(value);
  if (parsed == null) return null;
  final kbps = parsed >= 10000 ? (parsed / 1000).round() : parsed;
  return kbps >= 16 ? kbps : null;
}

String? _audioFormatForPath(String? filePath, {String? fileName}) {
  final candidates = <String>[?filePath, ?fileName];
  for (final candidate in candidates) {
    final lower = candidate.trim().toLowerCase();
    if (lower.endsWith('.opus') || lower.endsWith('.ogg')) return 'OPUS';
    if (lower.endsWith('.mp3')) return 'MP3';
    if (lower.endsWith('.aac')) return 'AAC';
    if (lower.endsWith('.m4a') || lower.endsWith('.mp4')) return 'M4A';
  }
  return null;
}

String? _nonPlaceholderQuality(String? quality) {
  final normalized = normalizeOptionalString(quality);
  if (normalized == null || isPlaceholderQualityLabel(normalized)) {
    return null;
  }
  final bitrateMatch = RegExp(
    r'\b(\d+)\s*kbps\b',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (bitrateMatch != null) {
    final bitrate = int.tryParse(bitrateMatch.group(1) ?? '');
    if (bitrate != null && bitrate < 16) return null;
  }
  final lower = normalized.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  const requestedLosslessLabels = {
    'hi_res_lossless',
    'hires_lossless',
    'hi_res',
    'hires',
    'flac_best_available',
  };
  if (requestedLosslessLabels.contains(lower)) return null;
  return normalized;
}

String? _normalizeAudioFormatValue(String? value) {
  final normalized = normalizeOptionalString(
    value,
  )?.toLowerCase().replaceAll('-', '_');
  return switch (normalized) {
    'flac' => 'flac',
    'alac' => 'alac',
    'aac' || 'mp4a' => 'aac',
    'eac3' || 'ec_3' => 'eac3',
    'ac3' || 'ac_3' => 'ac3',
    'ac4' || 'ac_4' => 'ac4',
    'mp3' => 'mp3',
    'opus' || 'ogg' => 'opus',
    'm4a' || 'mp4' => 'm4a',
    _ => null,
  };
}

bool _isLossyAudioFormat(String? value) {
  return const {
    'aac',
    'eac3',
    'ac3',
    'ac4',
    'mp3',
    'opus',
    'm4a',
  }.contains(_normalizeAudioFormatValue(value));
}

String _lossyFormatForSetting(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.startsWith('opus')) return 'opus';
  if (normalized.startsWith('aac') || normalized.startsWith('m4a')) {
    return 'aac';
  }
  return 'mp3';
}

String _lossyExtensionForFormat(String format) {
  return switch (format) {
    'opus' => '.opus',
    'aac' => '.m4a',
    _ => '.mp3',
  };
}

String _metadataFormatForLossyFormat(String format) {
  return format == 'aac' ? 'm4a' : format;
}

String _displayFormatForLossyFormat(String format) {
  return format == 'aac' ? 'AAC' : format.toUpperCase();
}

String? _resolveDisplayQuality({
  required String? filePath,
  String? fileName,
  String? detectedFormat,
  int? bitDepth,
  int? sampleRate,
  int? bitrateKbps,
  String? storedQuality,
}) {
  final format =
      _displayFormatForCodec(detectedFormat) ??
      _audioFormatForPath(filePath, fileName: fileName);
  if (format == 'OPUS' ||
      format == 'MP3' ||
      format == 'AAC' ||
      format == 'EAC3' ||
      format == 'AC3' ||
      format == 'AC4' ||
      (format == 'M4A' && (bitDepth == null || bitDepth <= 0))) {
    return buildDisplayAudioQuality(bitrateKbps: bitrateKbps, format: format) ??
        _nonPlaceholderQuality(storedQuality) ??
        format;
  }
  return buildDisplayAudioQuality(
    bitDepth: bitDepth,
    sampleRate: sampleRate,
    storedQuality: _nonPlaceholderQuality(storedQuality) ?? storedQuality,
  );
}

String? _displayFormatForCodec(String? value) {
  final normalized = normalizeOptionalString(
    value,
  )?.toLowerCase().replaceAll('-', '_');
  return switch (normalized) {
    'flac' => 'FLAC',
    'alac' => 'ALAC',
    'aac' || 'mp4a' => 'AAC',
    'eac3' || 'ec_3' => 'EAC3',
    'ac3' || 'ac_3' => 'AC3',
    'ac4' || 'ac_4' => 'AC4',
    'mp3' => 'MP3',
    'opus' => 'OPUS',
    _ => null,
  };
}

/// log10 helper using dart:math's natural log.
double _log10(num x) => log(x) / ln10;
final _yearRegex = RegExp(r'^(\d{4})');
const _defaultOutputFolderName = 'SpotiFLAC';
const _defaultAndroidMusicSubpath = 'Music/$_defaultOutputFolderName';
const _maxSafFilenameUtf8Bytes = 180;
const _maxSafDirSegmentUtf8Bytes = 120;

class DownloadQueueState {
  static const Object _noChange = Object();
  final List<DownloadItem> items;
  final DownloadQueueLookup lookup;
  final DownloadItem? currentDownload;
  final bool isProcessing;
  final bool isPaused;
  final String outputDir;
  final String filenameFormat;
  final String singleFilenameFormat;
  final String audioQuality;
  final bool autoFallback;
  final int concurrentDownloads;

  const DownloadQueueState({
    this.items = const [],
    this.lookup = const DownloadQueueLookup.empty(),
    this.currentDownload,
    this.isProcessing = false,
    this.isPaused = false,
    this.outputDir = '',
    this.filenameFormat = '{artist} - {title}',
    this.singleFilenameFormat = '{title} - {artist}',
    this.audioQuality = 'LOSSLESS',
    this.autoFallback = true,
    this.concurrentDownloads = 1,
  });

  DownloadQueueState copyWith({
    List<DownloadItem>? items,
    DownloadQueueLookup? lookup,
    Object? currentDownload = _noChange,
    bool? isProcessing,
    bool? isPaused,
    String? outputDir,
    String? filenameFormat,
    String? singleFilenameFormat,
    String? audioQuality,
    bool? autoFallback,
    int? concurrentDownloads,
  }) {
    final resolvedItems = items ?? this.items;
    return DownloadQueueState(
      items: resolvedItems,
      lookup:
          lookup ??
          (items != null
              ? DownloadQueueLookup.fromItems(resolvedItems)
              : this.lookup),
      currentDownload: identical(currentDownload, _noChange)
          ? this.currentDownload
          : currentDownload as DownloadItem?,
      isProcessing: isProcessing ?? this.isProcessing,
      isPaused: isPaused ?? this.isPaused,
      outputDir: outputDir ?? this.outputDir,
      filenameFormat: filenameFormat ?? this.filenameFormat,
      singleFilenameFormat: singleFilenameFormat ?? this.singleFilenameFormat,
      audioQuality: audioQuality ?? this.audioQuality,
      autoFallback: autoFallback ?? this.autoFallback,
      concurrentDownloads: concurrentDownloads ?? this.concurrentDownloads,
    );
  }

  int get queuedCount => items.isEmpty ? 0 : lookup.queuedCount;
  int get completedCount => items.isEmpty ? 0 : lookup.completedCount;
  int get failedCount => items.isEmpty ? 0 : lookup.failedCount;
  int get activeDownloadsCount =>
      items.isEmpty ? 0 : lookup.activeDownloadsCount;
}

class _ProgressUpdate {
  final DownloadStatus status;
  final double progress;
  final double? speedMBps;
  final int? bytesReceived;
  final int? bytesTotal;

  const _ProgressUpdate({
    required this.status,
    required this.progress,
    this.speedMBps,
    this.bytesReceived,
    this.bytesTotal,
  });
}

class _NativeWorkerRequestContext {
  final DownloadItem item;
  final String requestJson;
  final String outputDir;
  final String quality;
  final String storageMode;
  final String outputExt;
  final String? downloadTreeUri;
  final String? safRelativeDir;
  final String? safFileName;

  const _NativeWorkerRequestContext({
    required this.item,
    required this.requestJson,
    required this.outputDir,
    required this.quality,
    required this.storageMode,
    required this.outputExt,
    this.downloadTreeUri,
    this.safRelativeDir,
    this.safFileName,
  });
}

class DownloadQueueNotifier extends Notifier<DownloadQueueState> {
  Timer? _progressTimer;
  Timer? _progressStreamBootstrapTimer;
  Timer? _queuePersistDebounce;
  StreamSubscription<Map<String, dynamic>>? _progressStreamSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  int _downloadCount = 0;
  static const _cleanupInterval = 50;
  static const _progressPollingInterval = Duration(milliseconds: 1200);
  static const _idleProgressPollEveryTicks = 3;
  static const _queueSchedulingInterval = Duration(milliseconds: 250);
  static const _queuePersistDebounceDuration = Duration(milliseconds: 350);
  static const _nativeWorkerRunIdPrefsKey =
      'download_queue_native_worker_run_id';
  static const _bytesUiStep = 104857; // ~0.1 MiB, matches one-decimal MB UI.
  static const _serviceProgressStepPercent = 2;
  final NotificationService _notificationService = NotificationService();
  final AppStateDatabase _appStateDb = AppStateDatabase.instance;
  int _totalQueuedAtStart = 0;
  int _completedInSession = 0;
  int _failedInSession = 0;
  int _queueItemSequence = 0;
  bool _isLoaded = false;
  final Set<String> _ensuredDirs = {};
  int _progressPollingErrorCount = 0;
  bool _isProgressPollingInFlight = false;
  int _idleProgressPollTick = 0;
  bool _hasReceivedProgressStreamEvent = false;
  bool _usingProgressStream = false;
  bool _networkPausedByWifiOnly = false;
  String? _lastServiceTrackName;
  String? _lastServiceArtistName;
  String? _lastServiceStatus;
  int _lastServicePercent = -1;
  int _lastServiceQueueCount = -1;
  DateTime _lastServiceUpdateAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastFinalizingTrackName;
  String? _lastFinalizingArtistName;
  String? _lastNotifTrackName;
  String? _lastNotifArtistName;
  int _lastNotifPercent = -1;
  int _lastNotifQueueCount = -1;
  final Set<String> _locallyCancelledItemIds = {};
  final Set<String> _pausePendingItemIds = {};
  String? _activeNativeWorkerRunId;

  // Album ReplayGain accumulator: keyed by album identifier.
  // Stores per-track loudness data until all album tracks are done,
  // then computes and writes album gain/peak to every track in the album.
  final Map<String, _AlbumRgAccumulator> _albumRgData = {};

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

  @override
  DownloadQueueState build() {
    ref.listen<AppSettings>(settingsProvider, (previous, next) {
      final previousConcurrent =
          previous?.concurrentDownloads ?? state.concurrentDownloads;
      updateSettings(next);
      if (previousConcurrent != next.concurrentDownloads) {
        _log.i(
          'Concurrent downloads updated: $previousConcurrent -> ${next.concurrentDownloads}',
        );
      }
      if (previous?.downloadNetworkMode != next.downloadNetworkMode) {
        _handleDownloadNetworkModeChanged(next.downloadNetworkMode);
      }
    });

    ref.onDispose(() {
      _progressTimer?.cancel();
      _progressStreamBootstrapTimer?.cancel();
      _progressStreamSub?.cancel();
      _connectivitySub?.cancel();
      _progressTimer = null;
      _progressStreamBootstrapTimer = null;
      _progressStreamSub = null;
      _connectivitySub = null;
      if (_queuePersistDebounce?.isActive == true) {
        _queuePersistDebounce?.cancel();
        unawaited(_flushQueueToStorage());
      } else {
        _queuePersistDebounce?.cancel();
      }
      _queuePersistDebounce = null;
    });

    Future.microtask(() async {
      updateSettings(ref.read(settingsProvider));
      await _initOutputDir();
      await _loadQueueFromStorage();
    });
    return const DownloadQueueState();
  }

  Future<void> _loadQueueFromStorage() async {
    if (_isLoaded) return;
    _isLoaded = true;

    try {
      await _appStateDb.migrateQueueFromSharedPreferences();
      final rows = await _appStateDb.getPendingDownloadQueueRows();
      if (rows.isEmpty) {
        _log.d('No queue found in storage');
        return;
      }

      final pendingItems = <DownloadItem>[];
      for (final row in rows) {
        final itemJson = row['item_json'] as String?;
        if (itemJson == null || itemJson.isEmpty) continue;

        try {
          final decoded = jsonDecode(itemJson);
          if (decoded is! Map) continue;
          var item = DownloadItem.fromJson(Map<String, dynamic>.from(decoded));
          final normalizedService = _normalizeQueuedService(item.service);
          if (normalizedService != item.service) {
            item = item.copyWith(service: normalizedService);
          }
          if (item.status == DownloadStatus.downloading ||
              item.status == DownloadStatus.finalizing) {
            item = item.copyWith(status: DownloadStatus.queued, progress: 0);
          }
          if (item.status == DownloadStatus.queued) {
            pendingItems.add(item);
          }
        } catch (_) {
          continue;
        }
      }

      if (pendingItems.isEmpty) {
        _log.d('No pending items to restore');
        await _appStateDb.replacePendingDownloadQueueRows(const []);
        return;
      }

      final normalizedPendingItems = _normalizeRestoredQueueIds(pendingItems);
      state = state.copyWith(items: normalizedPendingItems);
      _log.i(
        'Restored ${normalizedPendingItems.length} pending items from storage',
      );
      if (await _tryAdoptAndroidNativeWorkerSnapshot(normalizedPendingItems)) {
        return;
      }
      Future.microtask(() => _processQueue());
    } catch (e) {
      _log.e('Failed to load queue from storage: $e');
    }
  }

  void _saveQueueToStorage() {
    _queuePersistDebounce?.cancel();
    _queuePersistDebounce = Timer(_queuePersistDebounceDuration, () {
      _flushQueueToStorage();
    });
  }

  Future<void> _flushQueueToStorage() async {
    try {
      final pendingItems = state.items
          .where(
            (item) =>
                item.status == DownloadStatus.queued ||
                item.status == DownloadStatus.downloading ||
                item.status == DownloadStatus.finalizing,
          )
          .toList();

      if (pendingItems.isEmpty) {
        await _appStateDb.replacePendingDownloadQueueRows(const []);
        _log.d('Cleared queue storage (no pending items)');
      } else {
        final nowIso = DateTime.now().toIso8601String();
        final rows = pendingItems
            .map(
              (item) => <String, dynamic>{
                'id': item.id,
                'item_json': jsonEncode(item.toJson()),
                'status': item.status.name,
                'created_at': item.createdAt.toIso8601String(),
                'updated_at': nowIso,
              },
            )
            .toList(growable: false);
        await _appStateDb.replacePendingDownloadQueueRows(rows);
        _log.d('Saved ${pendingItems.length} pending items to storage');
      }
    } catch (e) {
      _log.e('Failed to save queue to storage: $e');
    }
  }

  void _startMultiProgressPolling() {
    _progressTimer?.cancel();
    _progressStreamBootstrapTimer?.cancel();
    _progressStreamBootstrapTimer = null;
    _progressStreamSub?.cancel();
    _progressStreamSub = null;
    _hasReceivedProgressStreamEvent = false;
    _usingProgressStream = false;
    _idleProgressPollTick = 0;

    if (Platform.isAndroid || Platform.isIOS) {
      _attachDownloadProgressStream();
      return;
    }

    _startMultiProgressPollingTimer();
  }

  void _attachDownloadProgressStream() {
    _progressStreamSub = PlatformBridge.downloadProgressStream().listen(
      (allProgress) {
        _hasReceivedProgressStreamEvent = true;
        _usingProgressStream = true;
        _progressStreamBootstrapTimer?.cancel();
        _progressStreamBootstrapTimer = null;
        if (_isProgressPollingInFlight) return;
        _isProgressPollingInFlight = true;
        try {
          _processAllDownloadProgress(allProgress);
          _progressPollingErrorCount = 0;
        } catch (e) {
          _progressPollingErrorCount++;
          if (_progressPollingErrorCount <= 3) {
            _log.w('Progress stream processing failed: $e');
          }
        } finally {
          _isProgressPollingInFlight = false;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_usingProgressStream) {
          _log.w(
            'Download progress stream failed, fallback to polling: $error',
          );
        }
        _progressStreamSub?.cancel();
        _progressStreamSub = null;
        _usingProgressStream = false;
        _progressStreamBootstrapTimer?.cancel();
        _progressStreamBootstrapTimer = null;
        _startMultiProgressPollingTimer();
      },
      cancelOnError: false,
    );

    _progressStreamBootstrapTimer = Timer(const Duration(seconds: 3), () {
      if (_hasReceivedProgressStreamEvent) {
        return;
      }
      _log.w('Download progress stream timeout, fallback to polling');
      _progressStreamSub?.cancel();
      _progressStreamSub = null;
      _usingProgressStream = false;
      _startMultiProgressPollingTimer();
    });
  }

  void _startMultiProgressPollingTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(_progressPollingInterval, (timer) async {
      if (_isProgressPollingInFlight) return;
      _isProgressPollingInFlight = true;
      try {
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
            return;
          }

          _idleProgressPollTick =
              (_idleProgressPollTick + 1) % _idleProgressPollEveryTicks;
          if (_idleProgressPollTick != 0) {
            return;
          }
        } else {
          _idleProgressPollTick = 0;
        }

        final allProgress = await PlatformBridge.getAllDownloadProgress();
        _processAllDownloadProgress(allProgress);
        _progressPollingErrorCount = 0;
      } catch (e) {
        _progressPollingErrorCount++;
        if (_progressPollingErrorCount <= 3) {
          _log.w('Progress polling failed: $e');
        }
      } finally {
        _isProgressPollingInFlight = false;
      }
    });
  }

  void _processAllDownloadProgress(Map<String, dynamic> allProgress) {
    final rawItems = allProgress['items'];
    final items = rawItems is Map
        ? rawItems.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final currentItems = state.items;
    final lookup = state.lookup;
    int queuedCount = 0;
    int downloadingCount = 0;
    DownloadItem? firstDownloading;
    bool hasFinalizingItem = false;
    String? finalizingTrackName;
    String? finalizingArtistName;
    for (int i = 0; i < currentItems.length; i++) {
      final item = currentItems[i];
      if (item.status == DownloadStatus.downloading) {
        downloadingCount++;
        firstDownloading ??= item;
      }
      if (item.status == DownloadStatus.queued ||
          item.status == DownloadStatus.downloading ||
          item.status == DownloadStatus.finalizing) {
        queuedCount++;
      }
      if (item.status == DownloadStatus.finalizing && !hasFinalizingItem) {
        hasFinalizingItem = true;
        finalizingTrackName = item.track.name;
        finalizingArtistName = item.track.artistName;
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
        progressUpdates[itemId] = const _ProgressUpdate(
          status: DownloadStatus.downloading,
          progress: 0.0,
          speedMBps: 0,
          bytesReceived: 0,
          bytesTotal: 0,
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
        );
        if (current.status != next.status ||
            current.progress != next.progress ||
            current.speedMBps != next.speedMBps ||
            current.bytesReceived != next.bytesReceived ||
            current.bytesTotal != next.bytesTotal) {
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
                : ((progressPercent ~/ _serviceProgressStepPercent) *
                          _serviceProgressStepPercent)
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
    _progressTimer?.cancel();
    _progressStreamBootstrapTimer?.cancel();
    _progressStreamSub?.cancel();
    _progressTimer = null;
    _progressStreamBootstrapTimer = null;
    _progressStreamSub = null;
    _progressPollingErrorCount = 0;
    _isProgressPollingInFlight = false;
    _idleProgressPollTick = 0;
    _hasReceivedProgressStreamEvent = false;
    _usingProgressStream = false;
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

  void setOutputDir(String dir) {
    state = state.copyWith(outputDir: dir);
  }

  static final _isrcRegex = RegExp(r'^[A-Z]{2}[A-Z0-9]{3}\d{2}\d{5}$');

  void updateSettings(AppSettings settings) {
    final concurrentDownloads = settings.concurrentDownloads.clamp(1, 5);
    state = state.copyWith(
      outputDir: settings.downloadDirectory.isNotEmpty
          ? settings.downloadDirectory
          : state.outputDir,
      filenameFormat: settings.filenameFormat,
      singleFilenameFormat: settings.singleFilenameFormat,
      audioQuality: settings.audioQuality,
      autoFallback: settings.autoFallback,
      concurrentDownloads: concurrentDownloads,
    );
  }

  String addToQueue(
    Track track,
    String service, {
    String? qualityOverride,
    String? playlistName,
  }) {
    final settings = ref.read(settingsProvider);
    updateSettings(settings);

    final takenIds = state.items.map((item) => item.id).toSet();
    final id = _newQueueItemId(track, takenIds: takenIds);
    final item = DownloadItem(
      id: id,
      track: track,
      service: _normalizeQueuedService(service),
      createdAt: DateTime.now(),
      qualityOverride: qualityOverride,
      playlistName: playlistName,
    );

    state = state.copyWith(items: [...state.items, item]);
    _saveQueueToStorage();

    if (!state.isProcessing) {
      Future.microtask(() => _processQueue());
    }

    return id;
  }

  void addMultipleToQueue(
    List<Track> tracks,
    String service, {
    String? qualityOverride,
    String? playlistName,
  }) {
    final settings = ref.read(settingsProvider);
    updateSettings(settings);

    final takenIds = state.items.map((item) => item.id).toSet();
    final newItems = tracks.map((track) {
      final id = _newQueueItemId(track, takenIds: takenIds);
      takenIds.add(id);
      return DownloadItem(
        id: id,
        track: track,
        service: _normalizeQueuedService(service),
        createdAt: DateTime.now(),
        qualityOverride: qualityOverride,
        playlistName: playlistName,
      );
    }).toList();

    state = state.copyWith(items: [...state.items, ...newItems]);
    _saveQueueToStorage();

    if (!state.isProcessing) {
      Future.microtask(() => _processQueue());
    }
  }

  void updateItemStatus(
    String id,
    DownloadStatus status, {
    double? progress,
    double? speedMBps,
    String? filePath,
    String? error,
    DownloadErrorType? errorType,
  }) {
    final items = state.items;
    final index = state.lookup.indexByItemId[id] ?? -1;
    if (index == -1) return;

    final current = items[index];
    final next = current.copyWith(
      status: status,
      progress: progress ?? current.progress,
      speedMBps: speedMBps ?? current.speedMBps,
      filePath: filePath,
      error: error,
      errorType: errorType,
    );

    if (current.status == next.status &&
        current.progress == next.progress &&
        current.speedMBps == next.speedMBps &&
        current.filePath == next.filePath &&
        current.error == next.error &&
        current.errorType == next.errorType) {
      return;
    }

    final updatedItems = List<DownloadItem>.from(items);
    updatedItems[index] = next;
    state = state.copyWith(items: updatedItems);

    if (Platform.isAndroid && status == DownloadStatus.finalizing) {
      PlatformBridge.clearItemProgress(id).catchError((_) {});
      final queueCount = updatedItems
          .where(
            (entry) =>
                entry.status == DownloadStatus.queued ||
                entry.status == DownloadStatus.downloading ||
                entry.status == DownloadStatus.finalizing,
          )
          .length;
      _maybeUpdateAndroidDownloadService(
        trackName: next.track.name,
        artistName: _notificationService.embeddingMetadataLabel,
        progress: 100,
        total: 100,
        queueCount: queueCount,
        status: 'finalizing',
      );
    }

    if (status == DownloadStatus.completed ||
        status == DownloadStatus.failed ||
        status == DownloadStatus.skipped) {
      _saveQueueToStorage();
    }
  }

  void updateProgress(String id, double progress, {double? speedMBps}) {
    final item = state.lookup.byItemId[id];
    if (item == null) return;
    if (item.status == DownloadStatus.skipped ||
        item.status == DownloadStatus.completed ||
        item.status == DownloadStatus.failed) {
      return;
    }
    updateItemStatus(
      id,
      DownloadStatus.downloading,
      progress: progress,
      speedMBps: speedMBps,
    );
  }

  DownloadItem? _findItemById(String id) {
    return state.lookup.byItemId[id];
  }

  bool _isLocallyCancelled(String id, {DownloadItem? item}) {
    if (_locallyCancelledItemIds.contains(id)) return true;
    final resolved = item ?? _findItemById(id);
    return resolved?.status == DownloadStatus.skipped;
  }

  bool _isPausePending(String id) => _pausePendingItemIds.contains(id);

  void _requeueItemForPause(String id) {
    final updatedItems = state.items
        .map((item) {
          if (item.id != id) return item;
          if (item.status == DownloadStatus.completed ||
              item.status == DownloadStatus.failed ||
              item.status == DownloadStatus.skipped) {
            return item;
          }
          return item.copyWith(
            status: DownloadStatus.queued,
            progress: 0,
            speedMBps: 0,
            bytesReceived: 0,
            bytesTotal: 0,
          );
        })
        .toList(growable: false);

    final currentDownload = state.currentDownload?.id == id
        ? null
        : state.currentDownload;
    state = state.copyWith(
      items: updatedItems,
      currentDownload: currentDownload,
    );
  }

  void _requestNativeCancel(String id) {
    PlatformBridge.cancelDownload(id).catchError((_) {});
    PlatformBridge.clearItemProgress(id).catchError((_) {});
  }

  void cancelItem(String id) {
    _pausePendingItemIds.remove(id);
    _locallyCancelledItemIds.add(id);
    updateItemStatus(id, DownloadStatus.skipped);
    _requestNativeCancel(id);
  }

  void dismissItem(String id) {
    final item = _findItemById(id);
    if (item == null) return;

    final isActive =
        item.status == DownloadStatus.queued ||
        item.status == DownloadStatus.downloading ||
        item.status == DownloadStatus.finalizing;
    final wasFailed =
        item.status == DownloadStatus.failed ||
        item.status == DownloadStatus.skipped;

    if (isActive) {
      _pausePendingItemIds.remove(id);
      _locallyCancelledItemIds.add(id);
      _requestNativeCancel(id);
    } else {
      _locallyCancelledItemIds.remove(id);
    }

    if (item.status != DownloadStatus.completed) {
      final key = _albumRgKey(item.track);
      final accumulator = _albumRgData[key];
      if (accumulator != null) {
        accumulator.entries.removeWhere((e) => e.trackId == item.track.id);
        if (accumulator.entries.isEmpty) {
          _albumRgData.remove(key);
        }
      }
    }

    final items = state.items.where((entry) => entry.id != id).toList();
    final currentDownload = state.currentDownload?.id == id
        ? null
        : state.currentDownload;
    state = state.copyWith(items: items, currentDownload: currentDownload);
    _saveQueueToStorage();

    // Dismissing a failed/skipped item may unblock album RG.
    if (wasFailed) {
      _retriggerAlbumRgChecks();
    }
  }

  void clearCompleted() {
    final removedItems = state.items.where(
      (item) =>
          item.status == DownloadStatus.completed ||
          item.status == DownloadStatus.failed ||
          item.status == DownloadStatus.skipped,
    );
    bool hadFailedOrSkipped = false;
    for (final item in removedItems) {
      if (item.status == DownloadStatus.failed ||
          item.status == DownloadStatus.skipped) {
        hadFailedOrSkipped = true;
        final key = _albumRgKey(item.track);
        final accumulator = _albumRgData[key];
        if (accumulator != null) {
          accumulator.entries.removeWhere((e) => e.trackId == item.track.id);
          if (accumulator.entries.isEmpty) {
            _albumRgData.remove(key);
          }
        }
      }
    }

    final items = state.items
        .where(
          (item) =>
              item.status != DownloadStatus.completed &&
              item.status != DownloadStatus.failed &&
              item.status != DownloadStatus.skipped,
        )
        .toList();

    state = state.copyWith(items: items);
    _saveQueueToStorage();

    if (hadFailedOrSkipped) {
      _retriggerAlbumRgChecks();
    }
  }

  void clearAll() {
    final wasProcessing = state.isProcessing;
    final activeIds = state.items
        .where(
          (item) =>
              item.status == DownloadStatus.queued ||
              item.status == DownloadStatus.downloading ||
              item.status == DownloadStatus.finalizing,
        )
        .map((item) => item.id)
        .toList(growable: false);

    if (activeIds.isNotEmpty) {
      _pausePendingItemIds.addAll(activeIds);
      _locallyCancelledItemIds.addAll(activeIds);
      for (final id in activeIds) {
        _requestNativeCancel(id);
      }
    }

    state = state.copyWith(items: [], isPaused: false, currentDownload: null);
    if (Platform.isAndroid &&
        ref.read(settingsProvider).nativeDownloadWorkerEnabled) {
      PlatformBridge.cancelNativeDownloadWorker().catchError((_) {});
    }
    _notificationService.cancelDownloadNotification();
    _saveQueueToStorage();
    _albumRgData.clear();
    if (!wasProcessing) {
      _locallyCancelledItemIds.clear();
    }
    _pausePendingItemIds.clear();
  }

  void pauseQueue() {
    if (state.isProcessing && !state.isPaused) {
      if (Platform.isAndroid &&
          ref.read(settingsProvider).nativeDownloadWorkerEnabled) {
        PlatformBridge.pauseNativeDownloadWorker().catchError((_) {});
      }
      final activeIds = state.items
          .where(
            (item) =>
                item.status == DownloadStatus.downloading ||
                item.status == DownloadStatus.finalizing,
          )
          .map((item) => item.id)
          .toSet();

      if (activeIds.isNotEmpty) {
        _pausePendingItemIds.addAll(activeIds);
        for (final id in activeIds) {
          _requestNativeCancel(id);
          _requeueItemForPause(id);
        }
      }

      state = state.copyWith(isPaused: true, currentDownload: null);
      _notificationService.cancelDownloadNotification();
      _log.i('Queue paused');
    }
  }

  void resumeQueue() {
    if (state.isPaused) {
      if (Platform.isAndroid &&
          ref.read(settingsProvider).nativeDownloadWorkerEnabled) {
        PlatformBridge.resumeNativeDownloadWorker().catchError((_) {});
      }
      state = state.copyWith(isPaused: false);
      _log.i('Queue resumed');
      if (state.queuedCount > 0 && !state.isProcessing) {
        Future.microtask(() => _processQueue());
      }
    }
  }

  void togglePause() {
    if (state.isPaused) {
      resumeQueue();
    } else {
      pauseQueue();
    }
  }

  void retryItem(String id) {
    final item = state.items.where((i) => i.id == id).firstOrNull;
    if (item == null) {
      _log.w('retryItem: Item not found: $id');
      return;
    }

    if (item.status != DownloadStatus.failed &&
        item.status != DownloadStatus.skipped) {
      _log.w('retryItem: Item status is ${item.status}, not retrying');
      return;
    }

    _log.i('Retrying item: ${item.track.name} (id: $id)');
    _locallyCancelledItemIds.remove(id);

    // Purge stale ReplayGain entry for this track so a re-scan doesn't
    // produce duplicate entries that bias album gain.
    final rgKey = _albumRgKey(item.track);
    final rgAcc = _albumRgData[rgKey];
    if (rgAcc != null) {
      rgAcc.entries.removeWhere((e) => e.trackId == item.track.id);
      if (rgAcc.entries.isEmpty) {
        _albumRgData.remove(rgKey);
      }
    }

    final items = state.items.map((i) {
      if (i.id == id) {
        return i.copyWith(
          status: DownloadStatus.queued,
          progress: 0,
          error: null,
        );
      }
      return i;
    }).toList();
    state = state.copyWith(items: items);
    _saveQueueToStorage();

    if (!state.isProcessing) {
      _log.d('Starting queue processing for retry');
      Future.microtask(() => _processQueue());
    } else {
      _log.d('Queue already processing, item will be picked up');
    }
  }

  void retryAllFailed() {
    final failedIds = state.items
        .where(
          (item) =>
              item.status == DownloadStatus.failed ||
              item.status == DownloadStatus.skipped,
        )
        .map((item) => item.id)
        .toList();

    if (failedIds.isEmpty) {
      _log.i('retryAllFailed: no failed items to retry');
      return;
    }

    _log.i('retryAllFailed: retrying ${failedIds.length} item(s)');
    for (final id in failedIds) {
      retryItem(id);
    }
  }

  void removeItem(String id) {
    final removedItem = state.items.where((item) => item.id == id).firstOrNull;
    _locallyCancelledItemIds.remove(id);
    final items = state.items.where((item) => item.id != id).toList();
    state = state.copyWith(items: items);
    _saveQueueToStorage();

    // Clean stale album RG entries when a track is removed from the queue.
    // Only purge for items that were NOT completed — completed items' RG data
    // must survive removal because album gain is computed after the last track
    // finishes, by which time earlier completed tracks have been removed.
    if (removedItem != null && removedItem.status != DownloadStatus.completed) {
      final key = _albumRgKey(removedItem.track);
      final accumulator = _albumRgData[key];
      if (accumulator != null) {
        accumulator.entries.removeWhere(
          (e) => e.trackId == removedItem.track.id,
        );
        if (accumulator.entries.isEmpty) {
          _albumRgData.remove(key);
        }
      }
      // Removing a failed/skipped item may unblock album RG for the album.
      _retriggerAlbumRgChecks();
    }
  }

  Future<String?> exportFailedDownloads() async {
    final failedItems = state.items
        .where((item) => item.status == DownloadStatus.failed)
        .toList();

    if (failedItems.isEmpty) {
      _log.d('No failed downloads to export');
      return null;
    }

    try {
      String baseDir = state.outputDir;
      if (baseDir.isEmpty) {
        final dir = await getApplicationDocumentsDirectory();
        baseDir = dir.path;
      }

      final failedDownloadsDir = '$baseDir/failed_downloads';
      final failedDir = Directory(failedDownloadsDir);
      if (!await failedDir.exists()) {
        await failedDir.create(recursive: true);
      }

      // Use date-only format for daily grouping (YYYY-MM-DD)
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final fileName = 'failed_downloads_$dateStr.txt';
      final filePath = '$failedDownloadsDir/$fileName';

      final file = File(filePath);
      final bool fileExists = await file.exists();

      final buffer = StringBuffer();

      if (!fileExists) {
        buffer.writeln('# SpotiFLAC Failed Downloads');
        buffer.writeln('# Date: $dateStr');
        buffer.writeln('#');
        buffer.writeln('# Format: [Time] Track - Artist | URL | Error');
        buffer.writeln('');
      }

      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      for (final item in failedItems) {
        final track = item.track;
        final spotifyUrl = track.id.startsWith('deezer:')
            ? 'https://www.deezer.com/track/${track.id.substring(7)}'
            : 'https://open.spotify.com/track/${track.id}';
        final error = item.error ?? 'Unknown error';
        buffer.writeln(
          '[$timeStr] ${track.name} - ${track.artistName} | $spotifyUrl | $error',
        );
      }

      if (fileExists) {
        await file.writeAsString(buffer.toString(), mode: FileMode.append);
        _log.i('Appended ${failedItems.length} failed downloads to: $filePath');
      } else {
        await file.writeAsString(buffer.toString());
        _log.i('Created new failed downloads file: $filePath');
      }

      return filePath;
    } catch (e) {
      _log.e('Failed to export failed downloads: $e');
      return null;
    }
  }

  void clearFailedDownloads() {
    final failedItems = state.items
        .where((item) => item.status == DownloadStatus.failed)
        .toList();
    for (final item in failedItems) {
      final key = _albumRgKey(item.track);
      final accumulator = _albumRgData[key];
      if (accumulator != null) {
        accumulator.entries.removeWhere((e) => e.trackId == item.track.id);
        if (accumulator.entries.isEmpty) {
          _albumRgData.remove(key);
        }
      }
    }

    final items = state.items
        .where((item) => item.status != DownloadStatus.failed)
        .toList();
    state = state.copyWith(items: items);
    _saveQueueToStorage();
    _log.d('Cleared failed downloads from queue');

    // Removing failed items may unblock album RG for affected albums.
    if (failedItems.isNotEmpty) {
      _retriggerAlbumRgChecks();
    }
  }

  void _startConnectivityMonitoring() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      _handleConnectivityResults,
      onError: (Object error, StackTrace stackTrace) {
        _log.w('Connectivity monitoring failed: $error');
      },
      cancelOnError: false,
    );
  }

  void _stopConnectivityMonitoring({bool clearNetworkPause = true}) {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    if (clearNetworkPause) {
      _networkPausedByWifiOnly = false;
    }
  }

  void _handleDownloadNetworkModeChanged(String mode) {
    if (mode == 'wifi_only') {
      if (state.isProcessing || _networkPausedByWifiOnly) {
        _startConnectivityMonitoring();
      }
      return;
    }

    final shouldResume = _networkPausedByWifiOnly && state.isPaused;
    _stopConnectivityMonitoring();
    if (shouldResume) {
      resumeQueue();
    }
  }

  void _handleConnectivityResults(List<ConnectivityResult> results) {
    final settings = ref.read(settingsProvider);
    if (settings.downloadNetworkMode != 'wifi_only') {
      _handleDownloadNetworkModeChanged(settings.downloadNetworkMode);
      return;
    }

    if (_hasWifiConnection(results)) {
      if (_networkPausedByWifiOnly && state.isPaused) {
        _networkPausedByWifiOnly = false;
        _log.i('WiFi restored, resuming network-paused queue');
        resumeQueue();
      }
      return;
    }

    if (state.isProcessing && !state.isPaused) {
      _networkPausedByWifiOnly = true;
      _log.w('WiFi connection lost, pausing active queue');
      pauseQueue();
    }
  }

}

final downloadQueueProvider =
    NotifierProvider<DownloadQueueNotifier, DownloadQueueState>(
      DownloadQueueNotifier.new,
    );

class DownloadQueueLookup {
  final Map<String, DownloadItem> byTrackId;
  final Map<String, DownloadItem> byItemId;
  final Map<String, int> indexByItemId;
  final List<String> itemIds;
  final int queuedCount;
  final int completedCount;
  final int failedCount;
  final int activeDownloadsCount;

  const DownloadQueueLookup.empty()
    : byTrackId = const {},
      byItemId = const {},
      indexByItemId = const {},
      itemIds = const [],
      queuedCount = 0,
      completedCount = 0,
      failedCount = 0,
      activeDownloadsCount = 0;

  DownloadQueueLookup._({
    required Map<String, DownloadItem> byTrackId,
    required Map<String, DownloadItem> byItemId,
    required Map<String, int> indexByItemId,
    required List<String> itemIds,
    required this.queuedCount,
    required this.completedCount,
    required this.failedCount,
    required this.activeDownloadsCount,
  }) : byTrackId = Map.unmodifiable(byTrackId),
       byItemId = Map.unmodifiable(byItemId),
       indexByItemId = Map.unmodifiable(indexByItemId),
       itemIds = List.unmodifiable(itemIds);

  factory DownloadQueueLookup.fromItems(List<DownloadItem> items) {
    final byTrackId = <String, DownloadItem>{};
    final byItemId = <String, DownloadItem>{};
    final indexByItemId = <String, int>{};
    final itemIds = <String>[];
    var queuedCount = 0;
    var completedCount = 0;
    var failedCount = 0;
    var activeDownloadsCount = 0;
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      byTrackId.putIfAbsent(item.track.id, () => item);
      byItemId[item.id] = item;
      indexByItemId[item.id] = index;
      itemIds.add(item.id);
      if (_countsAsQueued(item.status)) queuedCount++;
      if (item.status == DownloadStatus.completed) completedCount++;
      if (item.status == DownloadStatus.failed) failedCount++;
      if (item.status == DownloadStatus.downloading) activeDownloadsCount++;
    }
    return DownloadQueueLookup._(
      byTrackId: byTrackId,
      byItemId: byItemId,
      indexByItemId: indexByItemId,
      itemIds: itemIds,
      queuedCount: queuedCount,
      completedCount: completedCount,
      failedCount: failedCount,
      activeDownloadsCount: activeDownloadsCount,
    );
  }

  static bool _countsAsQueued(DownloadStatus status) =>
      status == DownloadStatus.queued ||
      status == DownloadStatus.downloading ||
      status == DownloadStatus.finalizing;

  static int _deltaForStatus({
    required DownloadStatus previous,
    required DownloadStatus next,
    required bool Function(DownloadStatus status) predicate,
  }) {
    final had = predicate(previous);
    final has = predicate(next);
    if (had == has) return 0;
    return has ? 1 : -1;
  }

  DownloadQueueLookup updatedForIndices({
    required List<DownloadItem> previousItems,
    required List<DownloadItem> nextItems,
    required Iterable<int> changedIndices,
  }) {
    if (previousItems.length != nextItems.length ||
        itemIds.length != nextItems.length ||
        indexByItemId.length != nextItems.length) {
      return DownloadQueueLookup.fromItems(nextItems);
    }

    final normalizedChanged = <int>[];
    for (final index in changedIndices) {
      if (index < 0 || index >= nextItems.length) {
        return DownloadQueueLookup.fromItems(nextItems);
      }
      normalizedChanged.add(index);
    }
    if (normalizedChanged.isEmpty) return this;

    var nextQueuedCount = queuedCount;
    var nextCompletedCount = completedCount;
    var nextFailedCount = failedCount;
    var nextActiveDownloadsCount = activeDownloadsCount;
    Map<String, DownloadItem>? nextByItemId;
    Map<String, DownloadItem>? nextByTrackId;

    for (final index in normalizedChanged) {
      final previous = previousItems[index];
      final next = nextItems[index];
      if (previous.id != next.id || previous.track.id != next.track.id) {
        return DownloadQueueLookup.fromItems(nextItems);
      }

      nextByItemId ??= Map<String, DownloadItem>.from(byItemId);
      nextByItemId[next.id] = next;
      if (byTrackId[next.track.id]?.id == previous.id) {
        nextByTrackId ??= Map<String, DownloadItem>.from(byTrackId);
        nextByTrackId[next.track.id] = next;
      }
      nextQueuedCount += _deltaForStatus(
        previous: previous.status,
        next: next.status,
        predicate: _countsAsQueued,
      );
      nextCompletedCount += _deltaForStatus(
        previous: previous.status,
        next: next.status,
        predicate: (status) => status == DownloadStatus.completed,
      );
      nextFailedCount += _deltaForStatus(
        previous: previous.status,
        next: next.status,
        predicate: (status) => status == DownloadStatus.failed,
      );
      nextActiveDownloadsCount += _deltaForStatus(
        previous: previous.status,
        next: next.status,
        predicate: (status) => status == DownloadStatus.downloading,
      );
    }

    return DownloadQueueLookup._(
      byTrackId: nextByTrackId ?? byTrackId,
      byItemId: nextByItemId ?? byItemId,
      indexByItemId: indexByItemId,
      itemIds: itemIds,
      queuedCount: nextQueuedCount,
      completedCount: nextCompletedCount,
      failedCount: nextFailedCount,
      activeDownloadsCount: nextActiveDownloadsCount,
    );
  }
}

class _NativeWorkerStartupTimeout implements Exception {
  @override
  String toString() => 'Native worker did not publish run snapshot';
}

final downloadQueueLookupProvider = Provider<DownloadQueueLookup>((ref) {
  return ref.watch(downloadQueueProvider.select((s) => s.lookup));
});

class _AlbumRgTrackEntry {
  String filePath;
  final String trackId;
  final double integratedLufs;
  final double truePeakLinear;
  final double durationSecs;

  _AlbumRgTrackEntry({
    required this.filePath,
    required this.trackId,
    required this.integratedLufs,
    required this.truePeakLinear,
    required this.durationSecs,
  });
}

class _AlbumRgAccumulator {
  final List<_AlbumRgTrackEntry> entries = [];
}

class _DeezerLookupPreparation {
  final Track track;
  final String? deezerTrackId;

  const _DeezerLookupPreparation({required this.track, this.deezerTrackId});
}

class _DeezerExtendedMetadataFields {
  final String? genre;
  final String? label;
  final String? copyright;

  const _DeezerExtendedMetadataFields({this.genre, this.label, this.copyright});

  bool get hasAnyValue =>
      (genre != null && genre!.isNotEmpty) ||
      (label != null && label!.isNotEmpty) ||
      (copyright != null && copyright!.isNotEmpty);
}
