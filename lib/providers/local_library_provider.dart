import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/services/history_database.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/notification_service.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/utils/local_library_scan_prefs.dart';
import 'package:spotiflac_android/utils/path_match_keys.dart';

final _log = AppLogger('LocalLibrary');

const _excludedDownloadedCountKey = 'local_library_excluded_downloaded_count';
final _prefs = SharedPreferences.getInstance();

class LocalLibraryState {
  final bool isScanning;
  final bool scanIsFinalizing;
  final double scanProgress;
  final String? scanCurrentFile;
  final int scanTotalFiles;
  final int scannedFiles;
  final int scanErrorCount;
  final bool scanWasCancelled;
  final int totalCount;
  final int loadedIndexVersion;
  final DateTime? lastScannedAt;
  final int excludedDownloadedCount;
  final Set<String> _trackKeySet;
  final Set<String> _isrcSet;
  final Map<String, String> _filePathById;

  LocalLibraryState({
    this.isScanning = false,
    this.scanIsFinalizing = false,
    this.scanProgress = 0,
    this.scanCurrentFile,
    this.scanTotalFiles = 0,
    this.scannedFiles = 0,
    this.scanErrorCount = 0,
    this.scanWasCancelled = false,
    this.totalCount = 0,
    this.loadedIndexVersion = 0,
    this.lastScannedAt,
    this.excludedDownloadedCount = 0,
    Set<String>? trackKeySet,
    Set<String>? isrcSet,
    Map<String, String>? filePathById,
  }) : _trackKeySet = trackKeySet ?? const <String>{},
       _isrcSet = isrcSet ?? const <String>{},
       _filePathById = filePathById ?? const <String, String>{};

  bool hasIsrc(String isrc) => _isrcSet.contains(isrc);

  bool hasTrack(String trackName, String artistName) {
    final key = LibraryDatabase.matchKeyFor(trackName, artistName);
    return _trackKeySet.contains(key);
  }

  String? filePathForId(String id) => _filePathById[id];

  bool existsInLibrary({String? isrc, String? trackName, String? artistName}) {
    if (isrc != null && isrc.isNotEmpty && hasIsrc(isrc)) {
      return true;
    }
    if (trackName != null && artistName != null) {
      return hasTrack(trackName, artistName);
    }
    return false;
  }

  LocalLibraryState copyWith({
    bool? isScanning,
    bool? scanIsFinalizing,
    double? scanProgress,
    String? scanCurrentFile,
    int? scanTotalFiles,
    int? scannedFiles,
    int? scanErrorCount,
    bool? scanWasCancelled,
    int? totalCount,
    int? loadedIndexVersion,
    DateTime? lastScannedAt,
    int? excludedDownloadedCount,
    Set<String>? trackKeySet,
    Set<String>? isrcSet,
    Map<String, String>? filePathById,
  }) {
    return LocalLibraryState(
      isScanning: isScanning ?? this.isScanning,
      scanIsFinalizing: scanIsFinalizing ?? this.scanIsFinalizing,
      scanProgress: scanProgress ?? this.scanProgress,
      scanCurrentFile: scanCurrentFile ?? this.scanCurrentFile,
      scanTotalFiles: scanTotalFiles ?? this.scanTotalFiles,
      scannedFiles: scannedFiles ?? this.scannedFiles,
      scanErrorCount: scanErrorCount ?? this.scanErrorCount,
      scanWasCancelled: scanWasCancelled ?? this.scanWasCancelled,
      totalCount: totalCount ?? this.totalCount,
      loadedIndexVersion: loadedIndexVersion ?? this.loadedIndexVersion,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
      excludedDownloadedCount:
          excludedDownloadedCount ?? this.excludedDownloadedCount,
      trackKeySet: trackKeySet ?? _trackKeySet,
      isrcSet: isrcSet ?? _isrcSet,
      filePathById: filePathById ?? _filePathById,
    );
  }
}

class LocalLibraryNotifier extends Notifier<LocalLibraryState> {
  final LibraryDatabase _db = LibraryDatabase.instance;
  final HistoryDatabase _historyDb = HistoryDatabase.instance;
  final NotificationService _notificationService = NotificationService();
  static const _progressPollingInterval = Duration(milliseconds: 350);
  static const _progressStreamBootstrapTimeout = Duration(milliseconds: 900);
  Timer? _progressTimer;
  Timer? _progressStreamBootstrapTimer;
  StreamSubscription<Map<String, dynamic>>? _progressStreamSub;
  bool _isLoaded = false;
  bool _hasLoadedFromDatabase = false;
  Future<void>? _loadFuture;
  bool _scanCancelRequested = false;
  int _progressPollingErrorCount = 0;
  bool _isProgressPollingInFlight = false;
  bool _hasReceivedProgressStreamEvent = false;
  bool _usingProgressStream = false;
  static const _scanNotificationHeartbeat = Duration(seconds: 4);
  int _lastScanNotificationPercent = -1;
  int _lastScanNotificationTotalFiles = -1;
  DateTime _lastScanNotificationAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  LocalLibraryState build() {
    ref.onDispose(() {
      _progressTimer?.cancel();
      _progressStreamBootstrapTimer?.cancel();
      _progressStreamSub?.cancel();
    });

    Future.microtask(_ensureLoadedFromDatabase);
    return LocalLibraryState();
  }

  Future<void> _ensureLoadedFromDatabase() {
    if (_hasLoadedFromDatabase) {
      return Future<void>.value();
    }
    return _loadFuture ??= _loadFromDatabase();
  }

  Future<void> _loadFromDatabase() async {
    if (_hasLoadedFromDatabase) return;
    if (_isLoaded) {
      return _loadFuture ?? Future<void>.value();
    }
    _isLoaded = true;

    try {
      final countFuture = _db.getCount();
      final indexFuture = _db.getLookupIndex();
      final prefsFuture = _prefs;
      final count = await countFuture;
      final lookupIndex = await indexFuture;

      DateTime? lastScannedAt;
      var excludedDownloadedCount = 0;
      try {
        final prefs = await prefsFuture;
        lastScannedAt = readLocalLibraryLastScannedAt(prefs);
        excludedDownloadedCount =
            prefs.getInt(_excludedDownloadedCountKey) ?? 0;
      } catch (e) {
        _log.w('Failed to load lastScannedAt: $e');
      }

      state = state.copyWith(
        totalCount: count,
        loadedIndexVersion: state.loadedIndexVersion + 1,
        lastScannedAt: lastScannedAt,
        excludedDownloadedCount: excludedDownloadedCount,
        trackKeySet: lookupIndex.matchKeys,
        isrcSet: lookupIndex.isrcs,
        filePathById: lookupIndex.filePathById,
      );
      _log.i(
        'Loaded local library summary: $count items, lastScannedAt: '
        '$lastScannedAt, excludedDownloadedCount: $excludedDownloadedCount',
      );
      _hasLoadedFromDatabase = true;
    } catch (e, stack) {
      _isLoaded = false;
      _log.e('Failed to load library from database: $e', e, stack);
    } finally {
      _loadFuture = null;
    }
  }

  Future<void> reloadFromStorage() async {
    _isLoaded = false;
    _hasLoadedFromDatabase = false;
    _loadFuture = null;
    await _ensureLoadedFromDatabase();
  }

  Future<void> _refreshSummaryFromStorage({
    DateTime? lastScannedAt,
    int? excludedDownloadedCount,
  }) async {
    // Run both queries concurrently — they are independent.
    final results = await Future.wait([_db.getCount(), _db.getLookupIndex()]);
    final count = results[0] as int;
    final index = results[1] as LibraryLookupIndex;
    state = state.copyWith(
      totalCount: count,
      loadedIndexVersion: state.loadedIndexVersion + 1,
      lastScannedAt: lastScannedAt,
      excludedDownloadedCount: excludedDownloadedCount,
      trackKeySet: index.matchKeys,
      isrcSet: index.isrcs,
      filePathById: index.filePathById,
    );
    _hasLoadedFromDatabase = true;
    _isLoaded = true;
  }

  bool _isDownloadedPath(String? filePath, Set<String> downloadedPathKeys) {
    if (filePath == null || filePath.isEmpty || downloadedPathKeys.isEmpty) {
      return false;
    }
    final candidateKeys = buildPathMatchKeys(filePath);
    for (final key in candidateKeys) {
      if (downloadedPathKeys.contains(key)) {
        return true;
      }
    }
    return false;
  }

  Future<void> startScan(
    String folderPath, {
    bool forceFullScan = false,
    String? iosBookmark,
  }) async {
    if (state.isScanning) {
      _log.w('Scan already in progress');
      return;
    }

    _scanCancelRequested = false;
    _log.i(
      'Starting library scan: $folderPath (incremental: ${!forceFullScan})',
    );
    state = state.copyWith(
      isScanning: true,
      scanIsFinalizing: false,
      scanProgress: 0,
      scanCurrentFile: null,
      scanTotalFiles: 0,
      scannedFiles: 0,
      scanErrorCount: 0,
      scanWasCancelled: false,
    );
    _resetScanNotificationTracking();
    if (_shouldShowScanProgressNotification(
      progress: 0,
      totalFiles: 0,
      isComplete: false,
    )) {
      await _showScanProgressNotification(
        progress: 0,
        scannedFiles: 0,
        totalFiles: 0,
        currentFile: null,
      );
    }

    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final coverCacheDir = '${appSupportDir.path}/library_covers';
      await PlatformBridge.setLibraryCoverCacheDir(coverCacheDir);
      _log.i('Cover cache directory set to: $coverCacheDir');
    } catch (e) {
      _log.w('Failed to set cover cache directory: $e');
    }

    _startProgressPolling();

    String? resolvedPath;
    bool didStartSecurityAccess = false;
    if (Platform.isIOS && iosBookmark != null && iosBookmark.isNotEmpty) {
      resolvedPath = await PlatformBridge.startAccessingIosBookmark(
        iosBookmark,
      );
      if (resolvedPath != null) {
        didStartSecurityAccess = true;
        _log.i('Started iOS security-scoped access: $resolvedPath');
      } else {
        _log.w(
          'Failed to start iOS security-scoped access, '
          'falling back to original path',
        );
      }
    }
    final effectiveFolderPath = resolvedPath ?? folderPath;

    try {
      final isSaf = effectiveFolderPath.startsWith('content://');

      final downloadedPaths = await _historyDb.getAllFilePaths();
      final inMemoryHistoryPaths = ref
          .read(downloadHistoryProvider)
          .items
          .map((item) => item.filePath)
          .where((path) => path.isNotEmpty);
      final allHistoryPaths = <String>{
        ...downloadedPaths,
        ...inMemoryHistoryPaths,
      };
      final downloadedPathKeys = <String>{};
      for (final path in allHistoryPaths) {
        downloadedPathKeys.addAll(buildPathMatchKeys(path));
      }
      _log.i(
        'Excluding ${allHistoryPaths.length} downloaded files from library scan '
        '(${downloadedPathKeys.length} path keys)',
      );

      if (forceFullScan) {
        final results = isSaf
            ? await PlatformBridge.scanSafTree(effectiveFolderPath)
            : await PlatformBridge.scanLibraryFolder(effectiveFolderPath);
        if (_scanCancelRequested) {
          state = state.copyWith(
            isScanning: false,
            scanIsFinalizing: false,
            scanWasCancelled: true,
          );
          await _showScanCancelledNotification();
          return;
        }

        state = state.copyWith(
          scanIsFinalizing: true,
          scanProgress: state.scanProgress >= 99 ? state.scanProgress : 99,
          scanCurrentFile: null,
        );

        final items = <LocalLibraryItem>[];
        int skippedDownloads = 0;
        for (final json in results) {
          final filePath = json['filePath'] as String?;
          if (_isDownloadedPath(filePath, downloadedPathKeys)) {
            skippedDownloads++;
            continue;
          }
          final item = LocalLibraryItem.fromJson(json);
          items.add(item);
        }

        if (skippedDownloads > 0) {
          _log.i('Skipped $skippedDownloads files already in download history');
        }

        await _db.replaceAll(items.map((e) => e.toJson()).toList());

        final now = DateTime.now();
        try {
          final prefs = await SharedPreferences.getInstance();
          await writeLocalLibraryLastScannedAt(prefs, now);
          await prefs.setInt(_excludedDownloadedCountKey, skippedDownloads);
          _log.d('Saved lastScannedAt: $now');
        } catch (e) {
          _log.w('Failed to save lastScannedAt: $e');
        }

        await _refreshSummaryFromStorage(
          lastScannedAt: now,
          excludedDownloadedCount: skippedDownloads,
        );
        state = state.copyWith(
          isScanning: false,
          scanIsFinalizing: false,
          scanProgress: 100,
          lastScannedAt: now,
          scanWasCancelled: false,
          excludedDownloadedCount: skippedDownloads,
        );
        await _pruneLibraryCoverCache();

        _log.i(
          'Full scan complete: ${state.totalCount} tracks found, '
          '$skippedDownloads already in downloads',
        );
        await _showScanCompleteNotification(
          totalTracks: state.totalCount,
          excludedDownloadedCount: skippedDownloads,
          errorCount: state.scanErrorCount,
        );
      } else {
        final existingFiles = await _db.getFileModTimes();
        _log.i(
          'Incremental scan: ${existingFiles.length} existing files in database',
        );

        final backfilledModTimes = await _backfillLegacyFileModTimes(
          isSaf: isSaf,
          existingFiles: existingFiles,
        );
        if (backfilledModTimes.isNotEmpty) {
          await _db.updateFileModTimes(backfilledModTimes);
          existingFiles.addAll(backfilledModTimes);
          _log.i('Backfilled ${backfilledModTimes.length} legacy mod times');
        }

        final useSnapshotBridge =
            Platform.isAndroid && existingFiles.isNotEmpty;
        final snapshotPath = useSnapshotBridge
            ? await _db.writeFileModTimesSnapshot()
            : null;

        Map<String, dynamic> result;
        try {
          if (isSaf) {
            result = useSnapshotBridge && snapshotPath != null
                ? await PlatformBridge.scanSafTreeIncrementalFromSnapshot(
                    effectiveFolderPath,
                    snapshotPath,
                  )
                : await PlatformBridge.scanSafTreeIncremental(
                    effectiveFolderPath,
                    existingFiles,
                  );
          } else {
            result = useSnapshotBridge && snapshotPath != null
                ? await PlatformBridge.scanLibraryFolderIncrementalFromSnapshot(
                    effectiveFolderPath,
                    snapshotPath,
                  )
                : await PlatformBridge.scanLibraryFolderIncremental(
                    effectiveFolderPath,
                    existingFiles,
                  );
          }
        } finally {
          if (snapshotPath != null) {
            try {
              await File(snapshotPath).delete();
            } catch (_) {}
          }
        }

        if (_scanCancelRequested) {
          state = state.copyWith(
            isScanning: false,
            scanIsFinalizing: false,
            scanWasCancelled: true,
          );
          await _showScanCancelledNotification();
          return;
        }

        state = state.copyWith(
          scanIsFinalizing: true,
          scanProgress: state.scanProgress >= 99 ? state.scanProgress : 99,
          scanCurrentFile: null,
        );

        final scannedList =
            (result['files'] as List<dynamic>?) ??
            (result['scanned'] as List<dynamic>?) ??
            [];
        final deletedPaths =
            (result['removedUris'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            (result['deletedPaths'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [];
        final skippedCount = result['skippedCount'] as int? ?? 0;
        final totalFiles = result['totalFiles'] as int? ?? 0;

        _log.i(
          'Incremental result: ${scannedList.length} scanned, '
          '$skippedCount skipped, ${deletedPaths.length} deleted, $totalFiles total',
        );

        final existingPaths = existingFiles.keys.toList(growable: false);
        final existingDownloadedPaths = <String>[];
        for (final path in existingPaths) {
          if (_isDownloadedPath(path, downloadedPathKeys)) {
            existingDownloadedPaths.add(path);
          }
        }
        if (existingDownloadedPaths.isNotEmpty) {
          final removed = await _db.deleteByPaths(existingDownloadedPaths);
          _log.i(
            'Removed $removed downloaded tracks already present in local library index',
          );
        }

        final updatedItems = <LocalLibraryItem>[];
        int skippedDownloads = existingDownloadedPaths.length;
        if (scannedList.isNotEmpty) {
          for (final json in scannedList) {
            final map = json as Map<String, dynamic>;
            final filePath = map['filePath'] as String?;
            if (_isDownloadedPath(filePath, downloadedPathKeys)) {
              skippedDownloads++;
              continue;
            }
            final item = LocalLibraryItem.fromJson(map);
            updatedItems.add(item);
          }
          if (updatedItems.isNotEmpty) {
            await _db.upsertBatch(updatedItems.map((e) => e.toJson()).toList());
            _log.i('Upserted ${updatedItems.length} items');
          }
          if (skippedDownloads > 0) {
            _log.i(
              'Skipped $skippedDownloads files already in download history',
            );
          }
        }

        if (deletedPaths.isNotEmpty) {
          final deleteCount = await _db.deleteByPaths(deletedPaths);
          _log.i('Deleted $deleteCount items from database');
        }

        final now = DateTime.now();
        try {
          final prefs = await SharedPreferences.getInstance();
          await writeLocalLibraryLastScannedAt(prefs, now);
          await prefs.setInt(_excludedDownloadedCountKey, skippedDownloads);
          _log.d('Saved lastScannedAt: $now');
        } catch (e) {
          _log.w('Failed to save lastScannedAt: $e');
        }

        await _refreshSummaryFromStorage(
          lastScannedAt: now,
          excludedDownloadedCount: skippedDownloads,
        );
        state = state.copyWith(
          isScanning: false,
          scanIsFinalizing: false,
          scanProgress: 100,
          lastScannedAt: now,
          scanWasCancelled: false,
          excludedDownloadedCount: skippedDownloads,
        );

        _log.i(
          'Incremental scan complete: ${state.totalCount} total tracks '
          '(${scannedList.length} new/updated, $skippedCount unchanged, '
          '${deletedPaths.length} removed, $skippedDownloads already in downloads)',
        );
        await _showScanCompleteNotification(
          totalTracks: state.totalCount,
          excludedDownloadedCount: skippedDownloads,
          errorCount: state.scanErrorCount,
        );
      }
    } catch (e, stack) {
      _log.e('Library scan failed: $e', e, stack);
      state = state.copyWith(
        isScanning: false,
        scanIsFinalizing: false,
        scanWasCancelled: false,
      );
      await _showScanFailedNotification(e.toString());
    } finally {
      if (didStartSecurityAccess) {
        await PlatformBridge.stopAccessingIosBookmark();
        _log.i('Stopped iOS security-scoped access');
      }
      _stopProgressPolling();
    }
  }

  void _startProgressPolling() {
    _progressTimer?.cancel();
    _progressStreamBootstrapTimer?.cancel();
    _progressStreamBootstrapTimer = null;
    _progressStreamSub?.cancel();
    _progressStreamSub = null;
    _hasReceivedProgressStreamEvent = false;
    _usingProgressStream = false;

    if (Platform.isAndroid || Platform.isIOS) {
      _progressStreamSub = PlatformBridge.libraryScanProgressStream().listen(
        (progress) async {
          _hasReceivedProgressStreamEvent = true;
          _usingProgressStream = true;
          _progressStreamBootstrapTimer?.cancel();
          _progressStreamBootstrapTimer = null;
          if (_isProgressPollingInFlight) return;
          _isProgressPollingInFlight = true;
          try {
            await _handleLibraryScanProgress(progress);
            _progressPollingErrorCount = 0;
          } catch (e) {
            _progressPollingErrorCount++;
            if (_progressPollingErrorCount <= 3) {
              _log.w('Library scan progress stream processing failed: $e');
            }
          } finally {
            _isProgressPollingInFlight = false;
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_usingProgressStream) {
            _log.w(
              'Library scan progress stream failed, fallback to polling: $error',
            );
          }
          _progressStreamSub?.cancel();
          _progressStreamSub = null;
          _usingProgressStream = false;
          _progressStreamBootstrapTimer?.cancel();
          _progressStreamBootstrapTimer = null;
          _startProgressPollingTimer();
        },
        cancelOnError: false,
      );

      Future<void>.microtask(_requestProgressSnapshot);

      _progressStreamBootstrapTimer = Timer(
        _progressStreamBootstrapTimeout,
        () {
          if (_hasReceivedProgressStreamEvent) {
            return;
          }
          _log.w('Library scan progress stream timeout, fallback to polling');
          _progressStreamSub?.cancel();
          _progressStreamSub = null;
          _usingProgressStream = false;
          _startProgressPollingTimer();
        },
      );
      return;
    }

    _startProgressPollingTimer();
  }

  void _startProgressPollingTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(_progressPollingInterval, (_) async {
      if (_isProgressPollingInFlight) return;
      _isProgressPollingInFlight = true;
      try {
        final progress = await PlatformBridge.getLibraryScanProgress();
        await _handleLibraryScanProgress(progress);
        _progressPollingErrorCount = 0;
      } catch (e) {
        _progressPollingErrorCount++;
        if (_progressPollingErrorCount <= 3) {
          _log.w('Library scan progress polling failed: $e');
        }
      } finally {
        _isProgressPollingInFlight = false;
      }
    });
  }

  Future<void> _requestProgressSnapshot() async {
    if (_isProgressPollingInFlight) return;
    _isProgressPollingInFlight = true;
    try {
      final progress = await PlatformBridge.getLibraryScanProgress();
      await _handleLibraryScanProgress(progress);
      _progressPollingErrorCount = 0;
    } catch (e) {
      _progressPollingErrorCount++;
      if (_progressPollingErrorCount <= 3) {
        _log.w('Initial library scan progress fetch failed: $e');
      }
    } finally {
      _isProgressPollingInFlight = false;
    }
  }

  Future<void> _handleLibraryScanProgress(Map<String, dynamic> progress) async {
    final nextProgress = (progress['progress_pct'] as num?)?.toDouble() ?? 0;
    final normalizedProgress = ((nextProgress * 10).round() / 10).clamp(
      0.0,
      100.0,
    );
    final isComplete = progress['is_complete'] == true;
    final displayProgress = isComplete
        ? 99.0
        : (normalizedProgress >= 100.0 ? 99.0 : normalizedProgress);
    final currentFile = progress['current_file'] as String?;
    final totalFiles = (progress['total_files'] as num?)?.toInt() ?? 0;
    final scannedFiles = (progress['scanned_files'] as num?)?.toInt() ?? 0;
    final errorCount = (progress['error_count'] as num?)?.toInt() ?? 0;

    final shouldUpdateState =
        state.scanProgress != displayProgress ||
        state.scanIsFinalizing != isComplete ||
        state.scanCurrentFile != currentFile ||
        state.scanTotalFiles != totalFiles ||
        state.scannedFiles != scannedFiles ||
        state.scanErrorCount != errorCount;

    if (shouldUpdateState) {
      state = state.copyWith(
        scanIsFinalizing: isComplete,
        scanProgress: displayProgress,
        scanCurrentFile: isComplete ? null : currentFile,
        scanTotalFiles: totalFiles,
        scannedFiles: scannedFiles,
        scanErrorCount: errorCount,
      );
    }

    if (_shouldShowScanProgressNotification(
      progress: normalizedProgress,
      totalFiles: totalFiles,
      isComplete: isComplete,
    )) {
      await _showScanProgressNotification(
        progress: normalizedProgress,
        scannedFiles: scannedFiles,
        totalFiles: totalFiles,
        currentFile: currentFile,
      );
    }

    if (isComplete) {
      _stopProgressPolling();
    }
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
    _hasReceivedProgressStreamEvent = false;
    _usingProgressStream = false;
    _resetScanNotificationTracking();
  }

  void _resetScanNotificationTracking() {
    _lastScanNotificationPercent = -1;
    _lastScanNotificationTotalFiles = -1;
    _lastScanNotificationAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _shouldShowScanProgressNotification({
    required double progress,
    required int totalFiles,
    required bool isComplete,
  }) {
    final now = DateTime.now();
    final percent = progress.round().clamp(0, 100);
    final percentChanged = percent != _lastScanNotificationPercent;
    final totalFilesChanged = totalFiles != _lastScanNotificationTotalFiles;
    final heartbeatDue =
        now.difference(_lastScanNotificationAt) >= _scanNotificationHeartbeat;

    if (!percentChanged && !totalFilesChanged && !isComplete && !heartbeatDue) {
      return false;
    }

    _lastScanNotificationPercent = percent;
    _lastScanNotificationTotalFiles = totalFiles;
    _lastScanNotificationAt = now;
    return true;
  }

  Future<void> cancelScan() async {
    if (!state.isScanning) return;

    _log.i('Cancelling library scan');
    _scanCancelRequested = true;
    await PlatformBridge.cancelLibraryScan();
    state = state.copyWith(
      isScanning: false,
      scanIsFinalizing: false,
      scanWasCancelled: true,
    );
    _stopProgressPolling();
    await _showScanCancelledNotification();
  }

  Future<void> _showScanProgressNotification({
    required double progress,
    required int scannedFiles,
    required int totalFiles,
    required String? currentFile,
  }) async {
    try {
      await _notificationService.showLibraryScanProgress(
        progress: progress,
        scannedFiles: scannedFiles,
        totalFiles: totalFiles,
        currentFile: _shortenFileForNotification(currentFile),
      );
    } catch (e) {
      _log.w('Failed to show scan progress notification: $e');
    }
  }

  Future<void> _showScanCompleteNotification({
    required int totalTracks,
    required int excludedDownloadedCount,
    required int errorCount,
  }) async {
    try {
      await _notificationService.showLibraryScanComplete(
        totalTracks: totalTracks,
        excludedDownloadedCount: excludedDownloadedCount,
        errorCount: errorCount,
      );
    } catch (e) {
      _log.w('Failed to show scan complete notification: $e');
    }
  }

  Future<void> _showScanFailedNotification(String message) async {
    try {
      await _notificationService.showLibraryScanFailed(message);
    } catch (e) {
      _log.w('Failed to show scan failure notification: $e');
    }
  }

  Future<void> _showScanCancelledNotification() async {
    try {
      await _notificationService.showLibraryScanCancelled();
    } catch (e) {
      _log.w('Failed to show scan cancelled notification: $e');
    }
  }

  String? _shortenFileForNotification(String? path) {
    final raw = path?.trim() ?? '';
    if (raw.isEmpty) return null;

    var decoded = raw;
    try {
      decoded = Uri.decodeFull(raw);
    } catch (_) {}

    final slashIdx = decoded.lastIndexOf('/');
    final backslashIdx = decoded.lastIndexOf('\\');
    final cut = slashIdx > backslashIdx ? slashIdx : backslashIdx;
    if (cut >= 0 && cut < decoded.length - 1) {
      return decoded.substring(cut + 1);
    }
    return decoded;
  }

  Future<int> cleanupMissingFiles({String? iosBookmark}) async {
    bool didStartSecurityAccess = false;
    if (Platform.isIOS && iosBookmark != null && iosBookmark.isNotEmpty) {
      final resolved = await PlatformBridge.startAccessingIosBookmark(
        iosBookmark,
      );
      if (resolved != null) {
        didStartSecurityAccess = true;
      }
    }
    try {
      final removed = await _db.cleanupMissingFiles();
      if (removed > 0) {
        await _refreshSummaryFromStorage();
      }
      return removed;
    } finally {
      if (didStartSecurityAccess) {
        await PlatformBridge.stopAccessingIosBookmark();
      }
    }
  }

  Future<void> clearLibrary() async {
    await _db.clearAll();

    try {
      final prefs = await SharedPreferences.getInstance();
      await clearLocalLibraryLastScannedAt(prefs);
      await prefs.remove(_excludedDownloadedCountKey);
    } catch (e) {
      _log.w('Failed to clear lastScannedAt: $e');
    }

    state = LocalLibraryState(loadedIndexVersion: state.loadedIndexVersion + 1);
    _log.i('Library cleared');
  }

  Future<void> _pruneLibraryCoverCache() async {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final libraryCoverDir = Directory('${appSupportDir.path}/library_covers');
      if (!await libraryCoverDir.exists()) {
        return;
      }

      final referencedCoverPaths = <String>{};
      var offset = 0;
      const pageSize = 500;
      while (true) {
        final page = await _db.getCoverPaths(limit: pageSize, offset: offset);
        if (page.isEmpty) break;
        referencedCoverPaths.addAll(page);
        if (page.length < pageSize) break;
        offset += pageSize;
      }

      var deletedCount = 0;
      await for (final entity in libraryCoverDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || referencedCoverPaths.contains(entity.path)) {
          continue;
        }
        try {
          await entity.delete();
          deletedCount++;
        } catch (e) {
          _log.w(
            'Failed deleting stale library cover cache ${entity.path}: $e',
          );
        }
      }

      if (deletedCount > 0) {
        _log.i('Pruned $deletedCount stale library cover cache files');
      }
    } catch (e) {
      _log.w('Failed pruning library cover cache: $e');
    }
  }

  Future<void> removeItem(String id) async {
    await _db.delete(id);
    await _refreshSummaryFromStorage();
  }

  bool existsInLibrary({String? isrc, String? trackName, String? artistName}) {
    return state.existsInLibrary(
      isrc: isrc,
      trackName: trackName,
      artistName: artistName,
    );
  }

  Future<LocalLibraryItem?> getById(String id) async {
    final json = await _db.getById(id);
    return json == null ? null : LocalLibraryItem.fromJson(json);
  }

  Future<LocalLibraryItem?> getByIsrcAsync(String isrc) async {
    final json = await _db.getByIsrc(isrc);
    return json == null ? null : LocalLibraryItem.fromJson(json);
  }

  Future<LocalLibraryItem?> findByTrackAndArtistAsync(
    String trackName,
    String artistName,
  ) async {
    final json = await _db.findFirstByTrackAndArtist(trackName, artistName);
    return json == null ? null : LocalLibraryItem.fromJson(json);
  }

  Future<LocalLibraryItem?> findExistingAsync({
    String? id,
    String? isrc,
    String? trackName,
    String? artistName,
  }) async {
    if (id != null && id.isNotEmpty) {
      final byId = await getById(id);
      if (byId != null) return byId;
    }
    if (isrc != null && isrc.isNotEmpty) {
      final byIsrc = await getByIsrcAsync(isrc);
      if (byIsrc != null) return byIsrc;
    }
    if (trackName != null && artistName != null) {
      return findByTrackAndArtistAsync(trackName, artistName);
    }
    return null;
  }

  Future<List<LocalLibraryItem>> search(String query) async {
    if (query.isEmpty) return [];

    final results = await _db.search(query);
    return results.map((e) => LocalLibraryItem.fromJson(e)).toList();
  }

  Future<int> getCount() async {
    return await _db.getCount();
  }

  Future<Map<String, int>> _backfillLegacyFileModTimes({
    required bool isSaf,
    required Map<String, int> existingFiles,
  }) async {
    final legacyPaths = existingFiles.entries
        .where((entry) => entry.value <= 0)
        .map((entry) => entry.key)
        .toList();
    if (legacyPaths.isEmpty) {
      return const {};
    }

    if (isSaf) {
      final uris = legacyPaths
          .where((path) => path.startsWith('content://'))
          .toList();
      if (uris.isEmpty) {
        return const {};
      }
      const chunkSize = 500;
      final backfilled = <String, int>{};
      try {
        for (var i = 0; i < uris.length; i += chunkSize) {
          if (_scanCancelRequested) {
            break;
          }
          final end = (i + chunkSize < uris.length)
              ? i + chunkSize
              : uris.length;
          final chunk = uris.sublist(i, end);
          final chunkResult = await PlatformBridge.getSafFileModTimes(chunk);
          backfilled.addAll(chunkResult);
        }
        return backfilled;
      } catch (e) {
        _log.w('Failed to backfill SAF mod times: $e');
        return const {};
      }
    }

    final paths = legacyPaths
        .where((path) => !path.startsWith('content://'))
        .toList(growable: false);
    const chunkSize = 24;
    final backfilled = <String, int>{};

    for (var i = 0; i < paths.length; i += chunkSize) {
      if (_scanCancelRequested) {
        break;
      }
      final end = (i + chunkSize < paths.length) ? i + chunkSize : paths.length;
      final chunk = paths.sublist(i, end);
      final chunkEntries = await Future.wait<MapEntry<String, int>?>(
        chunk.map((path) async {
          try {
            final stat = await File(path).stat();
            if (stat.type == FileSystemEntityType.file) {
              return MapEntry(path, stat.modified.millisecondsSinceEpoch);
            }
          } catch (_) {}
          return null;
        }),
      );
      for (final entry in chunkEntries) {
        if (entry != null) {
          backfilled[entry.key] = entry.value;
        }
      }
    }
    return backfilled;
  }
}

final localLibraryProvider =
    NotifierProvider<LocalLibraryNotifier, LocalLibraryState>(
      LocalLibraryNotifier.new,
    );

final localLibrarySummaryProvider = Provider<LocalLibraryState>((ref) {
  return ref.watch(localLibraryProvider);
});

class LocalLibraryLookup {
  final LibraryDatabase _db;

  const LocalLibraryLookup(this._db);

  Future<LocalLibraryItem?> byId(String id) async {
    final json = await _db.getById(id);
    return json == null ? null : LocalLibraryItem.fromJson(json);
  }

  Future<LocalLibraryItem?> byIsrc(String isrc) async {
    final json = await _db.getByIsrc(isrc);
    return json == null ? null : LocalLibraryItem.fromJson(json);
  }

  Future<LocalLibraryItem?> byTrackAndArtist(
    String trackName,
    String artistName,
  ) async {
    final json = await _db.findFirstByTrackAndArtist(trackName, artistName);
    return json == null ? null : LocalLibraryItem.fromJson(json);
  }

  Future<LocalLibraryItem?> existing({
    String? id,
    String? isrc,
    String? trackName,
    String? artistName,
  }) async {
    if (id != null && id.isNotEmpty) {
      final item = await byId(id);
      if (item != null) return item;
    }
    if (isrc != null && isrc.isNotEmpty) {
      final item = await byIsrc(isrc);
      if (item != null) return item;
    }
    if (trackName != null && artistName != null) {
      return byTrackAndArtist(trackName, artistName);
    }
    return null;
  }
}

final localLibraryLookupProvider = Provider<LocalLibraryLookup>((ref) {
  ref.watch(localLibraryProvider.select((state) => state.loadedIndexVersion));
  return LocalLibraryLookup(LibraryDatabase.instance);
});

class LocalLibraryCoverRequest {
  final String? isrc;
  final String trackName;
  final String artistName;

  const LocalLibraryCoverRequest({
    this.isrc,
    required this.trackName,
    required this.artistName,
  });

  @override
  bool operator ==(Object other) {
    return other is LocalLibraryCoverRequest &&
        other.isrc == isrc &&
        other.trackName == trackName &&
        other.artistName == artistName;
  }

  @override
  int get hashCode => Object.hash(isrc, trackName, artistName);
}

class LocalLibraryCoverBatchRequest {
  final List<LocalLibraryCoverRequest> tracks;

  const LocalLibraryCoverBatchRequest(this.tracks);

  @override
  bool operator ==(Object other) {
    if (other is! LocalLibraryCoverBatchRequest) return false;
    if (other.tracks.length != tracks.length) return false;
    for (var i = 0; i < tracks.length; i++) {
      if (other.tracks[i] != tracks[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(tracks);
}

String? _nonEmptyCoverPath(Map<String, dynamic>? json) {
  final coverPath = json?['coverPath'] as String?;
  final trimmed = coverPath?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

final localLibraryCoverProvider =
    FutureProvider.family<String?, LocalLibraryCoverRequest>((ref, request) {
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      return LibraryDatabase.instance
          .findExisting(
            isrc: request.isrc,
            trackName: request.trackName,
            artistName: request.artistName,
          )
          .then(_nonEmptyCoverPath);
    });

final localLibraryFirstCoverProvider =
    FutureProvider.family<String?, LocalLibraryCoverBatchRequest>((
      ref,
      request,
    ) async {
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      if (request.tracks.isEmpty) return null;

      // Race all cover lookups concurrently instead of awaiting each one
      // sequentially. For a 12-track album this replaces up to 12 serial
      // DB round-trips with a single Future.wait, then picks the first hit.
      final covers = await Future.wait(
        request.tracks.map(
          (track) => LibraryDatabase.instance
              .findExisting(
                isrc: track.isrc,
                trackName: track.trackName,
                artistName: track.artistName,
              )
              .then(_nonEmptyCoverPath),
        ),
      );
      return covers.firstWhere((c) => c != null, orElse: () => null);
    });

final localLibraryPageProvider =
    FutureProvider.family<List<LocalLibraryItem>, LocalLibraryPageRequest>((
      ref,
      request,
    ) async {
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      final rows = await LibraryDatabase.instance.getPage(request);
      return rows.map(LocalLibraryItem.fromJson).toList(growable: false);
    });

final localLibraryPageCountProvider =
    FutureProvider.family<int, LocalLibraryPageRequest>((ref, request) async {
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      return LibraryDatabase.instance.getPageCount(request);
    });

class LocalLibraryAlbumPageRequest {
  final int limit;
  final int offset;
  final LocalLibraryFilterMode filterMode;
  final LocalLibrarySortMode sortMode;
  final String? searchQuery;

  const LocalLibraryAlbumPageRequest({
    this.limit = 100,
    this.offset = 0,
    this.filterMode = LocalLibraryFilterMode.albums,
    this.sortMode = LocalLibrarySortMode.album,
    this.searchQuery,
  });

  @override
  bool operator ==(Object other) {
    return other is LocalLibraryAlbumPageRequest &&
        other.limit == limit &&
        other.offset == offset &&
        other.filterMode == filterMode &&
        other.sortMode == sortMode &&
        other.searchQuery == searchQuery;
  }

  @override
  int get hashCode =>
      Object.hash(limit, offset, filterMode, sortMode, searchQuery);
}

final localLibraryAlbumPageProvider =
    FutureProvider.family<
      List<LocalLibraryAlbumGroup>,
      LocalLibraryAlbumPageRequest
    >((ref, request) async {
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      return LibraryDatabase.instance.getAlbumPage(
        limit: request.limit,
        offset: request.offset,
        filterMode: request.filterMode,
        sortMode: request.sortMode,
        searchQuery: request.searchQuery,
      );
    });

final localLibraryAlbumCountProvider =
    FutureProvider.family<int, LocalLibraryAlbumPageRequest>((
      ref,
      request,
    ) async {
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      return LibraryDatabase.instance.getAlbumCount(
        filterMode: request.filterMode,
        searchQuery: request.searchQuery,
      );
    });
