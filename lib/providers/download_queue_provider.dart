import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart'
    show ScaffoldMessenger, SnackBar, SnackBarAction, Text;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/download_item.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/services/app_navigation_service.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/download_verification_retry_guard.dart';
import 'package:spotiflac_android/providers/download_queue_state.dart';
import 'package:spotiflac_android/services/app_state_database.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/services/download_request_payload.dart';
import 'package:spotiflac_android/services/ffmpeg_service.dart';
import 'package:spotiflac_android/services/notification_service.dart';
import 'package:spotiflac_android/utils/logger.dart' hide log;
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/utils/artist_utils.dart';
import 'package:spotiflac_android/utils/audio_format_utils.dart';
import 'package:spotiflac_android/utils/int_utils.dart';
import 'package:spotiflac_android/utils/extension_auth_launcher.dart';
import 'package:spotiflac_android/utils/progress_stream_poller.dart';

import 'package:spotiflac_android/providers/download_history_provider.dart';

export 'package:spotiflac_android/providers/download_history_provider.dart';
export 'package:spotiflac_android/providers/download_queue_state.dart';

export 'package:spotiflac_android/services/history_database.dart'
    show HistoryLookupRequest, HistoryBatchLookupRequest;

part 'download_queue_provider_paths.dart';
part 'download_queue_provider_progress.dart';
part 'download_queue_provider_verification.dart';
part 'download_queue_provider_connectivity.dart';
part 'download_queue_provider_native_worker.dart';
part 'download_queue_provider_finalization.dart';
part 'download_queue_provider_replaygain.dart';
part 'download_queue_provider_embedding.dart';
part 'download_queue_provider_single_item.dart';

final _log = AppLogger('DownloadQueue');

/// Set on queued items when the persisted Android SAF grant fails validation.
/// The queue UI matches on this to offer re-selecting the download folder.
const String safPermissionLostErrorMessage =
    'SAF permission invalid or revoked. Please reconfigure download location in Settings.';

/// Set on queued items when the iOS download folder bookmark can no longer be
/// opened. The queue UI matches on this to offer re-selecting the folder.
const String downloadFolderAccessLostErrorMessage =
    'Download folder access lost. Please re-select your download folder in Settings.';

/// Keeps a download in its finalizing state until its durable Library record
/// has been written. If persistence fails, completion is deliberately not
/// published so the queue can surface the error instead of losing the file
/// from the app while it still exists on disk.
Future<void> persistBeforePublishingDownloadCompletion({
  required Future<void> Function() persist,
  required void Function() publish,
}) async {
  await persist();
  publish();
}

/// Keeps native-worker finalization visually distinct from completion.
/// Download bytes may reach 100% before SAF publishing, metadata persistence,
/// and queue reconciliation have finished.
double nativeWorkerFinalizingProgress(double progress) {
  final normalized = progress.clamp(0.0, 1.0).toDouble();
  if (normalized <= 0) return 0.95;
  return min(normalized, 0.99);
}

/// Whether a backend failure means the selected destination could not be
/// written. This intentionally stays provider-agnostic: once an output path is
/// unwritable, trying more audio providers against that same path only wastes
/// time and hides the actionable storage failure behind a later network error.
bool isStorageWriteFailure({String? errorType, String? errorMessage}) {
  if (errorType?.trim().toLowerCase() == 'permission') return true;

  final message = errorMessage?.trim().toLowerCase() ?? '';
  if (message.isEmpty) return false;
  return message.contains('operation not permitted') ||
      message.contains('permission denied') ||
      message.contains('read-only file system') ||
      message.contains('failed to create file') ||
      message.contains('failed to create directory') ||
      message.contains('failed to access saf directory') ||
      message.contains('failed to create saf file') ||
      message.contains('failed to open saf file') ||
      message.contains('failed to publish saf') ||
      message.contains('failed to publish deferred saf') ||
      message.contains('failed to copy extension output to saf');
}

final _invalidFolderChars = RegExp(r'[<>:"/\\|?*]');
final _trimDotsAndSpacesRegex = RegExp(r'^[. ]+|[. ]+$');
final _trimUnderscoresAndSpacesRegex = RegExp(r'^[_ ]+|[_ ]+$');
final _multiWhitespaceRegex = RegExp(r'\s+');
final _multiUnderscoreRegex = RegExp(r'_+');

/// log10 helper using dart:math's natural log.
double _log10(num x) => log(x) / ln10;
final _yearRegex = RegExp(r'^(\d{4})');
const _defaultOutputFolderName = 'SpotiFLAC';
const _defaultAndroidMusicSubpath = 'Music/$_defaultOutputFolderName';
const _maxSafFilenameUtf8Bytes = 180;
const _maxSafDirSegmentUtf8Bytes = 120;
final _batchUniqueFilenameTokenPattern = RegExp(
  r'\{(?:title|track(?:_raw)?|track:\d+|playlist_position(?:_raw)?|playlist_position:\d+|playlist position|playlistPosition|position(?::\d+)?)\}',
  caseSensitive: false,
);
final _qualityFilenameTokenPattern = RegExp(
  r'\{quality_variant\}',
  caseSensitive: false,
);
final _explicitQualityFilenameTokenPattern = RegExp(
  r'\{(?:quality|quality_variant)\}',
  caseSensitive: false,
);

class DownloadQueueNotifier extends Notifier<DownloadQueueState> {
  Timer? _queuePersistDebounce;
  Future<void> _queuePersistenceWrite = Future<void>.value();
  final Map<String, String> _persistedQueueJsonById = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  int _downloadCount = 0;
  static const _cleanupInterval = 50;
  static const _progressPollingInterval = Duration(milliseconds: 1200);
  static const _idleProgressPollEveryTicks = 3;
  static const _progressStreamBootstrapTimeout = Duration(seconds: 3);
  static const _queueSchedulingInterval = Duration(milliseconds: 250);
  static const _queuePersistDebounceDuration = Duration(milliseconds: 350);
  static const _nativeWorkerRunIdPrefsKey =
      'download_queue_native_worker_run_id';
  static const _bytesUiStep = 104857; // ~0.1 MiB, matches one-decimal MB UI.
  static const _serviceProgressStepPercent = 2;
  static const _decryptStageSafAccess = 'safAccess';
  static const _decryptStageDecrypt = 'decrypt';
  static const _decryptStageSafWrite = 'safWrite';
  final NotificationService _notificationService = NotificationService();
  final AppStateDatabase _appStateDb = AppStateDatabase.instance;
  // Shared across tracks in a batch: an album's tracks embed the same cover,
  // so fetch it once instead of once per track. LRU-capped; files are deleted
  // on eviction and when the queue drains.
  final Map<String, Future<String?>> _embedCoverCache = {};
  late final ProgressStreamPoller<Map<String, dynamic>> _progressPoller =
      ProgressStreamPoller<Map<String, dynamic>>(
        streamProvider: PlatformBridge.downloadProgressStream,
        pollProvider: PlatformBridge.getAllDownloadProgress,
        onProgress: (allProgress) async =>
            _processAllDownloadProgress(allProgress),
        pollingInterval: _progressPollingInterval,
        bootstrapTimeout: _progressStreamBootstrapTimeout,
        onStreamProcessingError: (e) =>
            _log.w('Progress stream processing failed: $e'),
        onStreamFailed: (error) => _log.w(
          'Download progress stream failed, fallback to polling: $error',
        ),
        onStreamTimeout: () =>
            _log.w('Download progress stream timeout, fallback to polling'),
        onPollError: (e) => _log.w('Progress polling failed: $e'),
        shouldPollTick: () => _shouldPollDownloadProgressTick(),
      );
  int _totalQueuedAtStart = 0;
  int _completedInSession = 0;
  int _failedInSession = 0;
  int _queueItemSequence = 0;
  bool _isLoaded = false;
  final Set<String> _ensuredDirs = {};
  final Map<String, Future<void>> _qualityVariantFileLocks = {};
  Future<String>? _appFolderStorageFallback;
  final Set<String> _rejectedAppFolderRoots = {};
  int _idleProgressPollTick = 0;

  Future<T> _withQualityVariantFileLock<T>(
    String path,
    Future<T> Function() action,
  ) async {
    final key = path.toLowerCase();
    final previous = _qualityVariantFileLocks[key];
    final completer = Completer<void>();
    final current = completer.future;
    _qualityVariantFileLocks[key] = current;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_qualityVariantFileLocks[key], current)) {
        _qualityVariantFileLocks.remove(key);
      }
    }
  }

  bool _networkPausedByWifiOnly = false;
  List<ConnectivityResult>? _lastConnectivityResults;
  DateTime _lastConnectionCleanupAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastReconnectRetryPromptAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _connectionCleanupDebounce = Duration(seconds: 2);
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
  final DownloadVerificationRetryGuard _verificationRetryGuard =
      DownloadVerificationRetryGuard();
  final Map<String, Future<bool>> _verificationFlowsByExtension = {};
  final Set<String> _rateLimitRetriedItemIds = {};
  String? _activeNativeWorkerRunId;
  bool get _hasActiveAndroidNativeWorker =>
      Platform.isAndroid && _activeNativeWorkerRunId?.isNotEmpty == true;

  // Album ReplayGain accumulator: keyed by album identifier.
  // Stores per-track loudness data until all album tracks are done,
  // then computes and writes album gain/peak to every track in the album.
  final Map<String, _AlbumRgAccumulator> _albumRgData = {};

  @override
  DownloadQueueState build() {
    ref.listen<AppSettings>(settingsProvider, (previous, next) {
      updateSettings(next);
      if (previous?.downloadNetworkMode != next.downloadNetworkMode) {
        _handleDownloadNetworkModeChanged(next.downloadNetworkMode);
      }
    });

    ref.onDispose(() {
      _progressPoller.stop();
      _connectivitySub?.cancel();
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

  /// Flush any debounced queue persistence to disk immediately. Called when
  /// the app is backgrounded: the OS may kill the process without a graceful
  /// teardown, and a pending debounce timer would silently drop the most
  /// recent queue mutations.
  Future<void> flushQueuePersistence() async {
    if (_queuePersistDebounce?.isActive == true) {
      _queuePersistDebounce?.cancel();
      await _flushQueueToStorage();
    }
    await _queuePersistenceWrite;
  }

  Future<void> _loadQueueFromStorage() async {
    if (_isLoaded) return;
    _isLoaded = true;

    try {
      await _appStateDb.migrateQueueFromSharedPreferences();
      final rows = await _appStateDb.getPendingDownloadQueueRows();
      _persistedQueueJsonById
        ..clear()
        ..addEntries(
          rows
              .map(
                (row) => MapEntry(
                  row['id']?.toString() ?? '',
                  row['item_json']?.toString() ?? '',
                ),
              )
              .where((entry) => entry.key.isNotEmpty),
        );
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
          if (item.status == DownloadStatus.queued ||
              item.status == DownloadStatus.skipped) {
            pendingItems.add(item);
          }
        } catch (_) {
          continue;
        }
      }

      if (pendingItems.isEmpty) {
        _log.d('No pending items to restore');
        await _appStateDb.replacePendingDownloadQueueRows(const []);
        _persistedQueueJsonById.clear();
        return;
      }

      final normalizedPendingItems = _normalizeRestoredQueueIds(pendingItems);
      state = state.copyWith(items: normalizedPendingItems);
      _saveQueueToStorage();
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
    final operation = _queuePersistenceWrite.then((_) => _writeQueueChanges());
    _queuePersistenceWrite = operation.catchError((_) {});
    await operation;
  }

  Future<void> _writeQueueChanges() async {
    try {
      // skipped (user-cancelled) rows persist too, so a cancelled download can
      // still be retried after an app restart instead of being re-searched.
      final pendingItems = state.items
          .where(
            (item) =>
                item.status == DownloadStatus.queued ||
                item.status == DownloadStatus.downloading ||
                item.status == DownloadStatus.finalizing ||
                item.status == DownloadStatus.skipped,
          )
          .toList(growable: false);
      final nowIso = DateTime.now().toIso8601String();
      final currentJsonById = <String, String>{};
      final upserts = <Map<String, dynamic>>[];
      for (final item in pendingItems) {
        final itemJson = jsonEncode(item.toJson());
        currentJsonById[item.id] = itemJson;
        if (_persistedQueueJsonById[item.id] == itemJson) continue;
        upserts.add({
          'id': item.id,
          'item_json': itemJson,
          'status': item.status.name,
          'created_at': item.createdAt.toIso8601String(),
          'updated_at': nowIso,
        });
      }
      final deletedIds = _persistedQueueJsonById.keys
          .where((id) => !currentJsonById.containsKey(id))
          .toList(growable: false);
      if (upserts.isEmpty && deletedIds.isEmpty) return;

      await _appStateDb.applyPendingDownloadQueueChanges(
        upserts: upserts,
        deletedIds: deletedIds,
      );
      _persistedQueueJsonById
        ..clear()
        ..addAll(currentJsonById);
      _log.d(
        'Persisted ${upserts.length} changed and removed '
        '${deletedIds.length} queue items',
      );
    } catch (e) {
      _log.e('Failed to save queue to storage: $e');
    }
  }

  bool _isSafMode(AppSettings settings) {
    return Platform.isAndroid &&
        settings.storageMode == 'saf' &&
        settings.downloadTreeUri.isNotEmpty;
  }

  String _normalizeQueuedService(String service) {
    final normalized = service.trim();
    if (normalized.isEmpty) {
      return normalized;
    }

    final replacement = ref
        .read(extensionProvider.notifier)
        .replacedBuiltInDownloadProviderFor(normalized);
    if (replacement != null && replacement.isNotEmpty) {
      return replacement;
    }

    return normalized;
  }

  bool _hasActiveDownloadProvider(String service) {
    final normalized = service.trim();
    if (normalized.isEmpty) {
      return false;
    }

    final extensionState = ref.read(extensionProvider);
    return extensionState.extensions.any(
      (ext) =>
          ext.enabled &&
          ext.hasDownloadProvider &&
          ext.id.toLowerCase() == normalized.toLowerCase(),
    );
  }

  /// Builds the backend [DownloadRequestPayload] shared by the native-worker
  /// request builder and the inline single-item download path. Fields whose
  /// source value legitimately differs between the two callers (SAF staging,
  /// download strategy) are left as parameters.
  DownloadRequestPayload _buildDownloadRequestPayload({
    required Track track,
    required DownloadItem item,
    required AppSettings settings,
    required ExtensionState extensionState,
    required String quality,
    required String filenameFormat,
    required String outputDir,
    required String outputExt,
    required bool useSaf,
    String? safFileName,
    String? deezerTrackId,
    String? genre,
    String? label,
    String? copyright,
    bool stageSafForDeferredPublish = false,
    bool qualityVariantCollisionOnly = false,
  }) {
    final resolvedAlbumArtist = _resolveAlbumArtistForMetadata(track, settings);
    final postProcessingEnabled =
        settings.useExtensionProviders &&
        extensionState.extensions.any((e) => e.enabled && e.hasPostProcessing);
    final normalizedTrackNumber =
        (track.trackNumber != null && track.trackNumber! > 0)
        ? track.trackNumber!
        : 0;
    final normalizedDiscNumber =
        (track.discNumber != null && track.discNumber! > 0)
        ? track.discNumber!
        : 0;

    String payloadSpotifyId = track.id;
    String payloadQobuzId = '';
    String payloadTidalId = '';
    if (track.id.startsWith('qobuz:')) {
      payloadQobuzId = track.id.substring(6);
      if (_downloadProviderReplacesLegacyProvider(item.service, 'qobuz')) {
        payloadSpotifyId = '';
      }
    }
    if (track.id.startsWith('tidal:')) {
      payloadTidalId = track.id.substring(6);
      if (_downloadProviderReplacesLegacyProvider(item.service, 'tidal')) {
        payloadSpotifyId = '';
      }
    }

    return DownloadRequestPayload(
      isrc: track.isrc ?? '',
      service: item.service,
      spotifyId: payloadSpotifyId,
      trackName: track.name,
      artistName: track.artistName,
      albumName: track.albumName,
      albumArtist: resolvedAlbumArtist ?? '',
      coverUrl: settings.embedMetadata ? (track.coverUrl ?? '') : '',
      outputDir: outputDir,
      filenameFormat: filenameFormat,
      quality: quality,
      embedMetadata: settings.embedMetadata,
      artistTagMode: settings.artistTagMode,
      embedLyrics:
          settings.embedMetadata &&
          settings.embedLyrics &&
          !_shouldSkipLyrics(extensionState, track.source, item.service),
      embedMaxQualityCover: settings.embedMetadata && settings.maxQualityCover,
      embedReplayGain: settings.embedReplayGain,
      postProcessingEnabled: postProcessingEnabled,
      tidalHighFormat: settings.tidalHighFormat,
      trackNumber: normalizedTrackNumber,
      playlistPosition: _validPlaylistPosition(item),
      discNumber: normalizedDiscNumber,
      totalTracks: track.totalTracks ?? 0,
      totalDiscs: track.totalDiscs ?? 0,
      releaseDate: track.releaseDate ?? '',
      itemId: item.id,
      durationMs: track.duration * 1000,
      source: track.source ?? '',
      genre: genre ?? '',
      label: label ?? '',
      copyright: copyright ?? '',
      composer: track.composer ?? '',
      qobuzId: payloadQobuzId,
      tidalId: payloadTidalId,
      deezerId: deezerTrackId ?? '',
      lyricsMode: settings.lyricsMode,
      storageMode: useSaf ? 'saf' : 'app',
      safTreeUri: useSaf ? settings.downloadTreeUri : '',
      safRelativeDir: useSaf ? outputDir : '',
      safFileName: useSaf ? (safFileName ?? '') : '',
      safOutputExt: useSaf ? outputExt : '',
      outputExt: outputExt,
      stageSafOutput: stageSafForDeferredPublish,
      deferSafPublish: stageSafForDeferredPublish,
      requiresContainerConversion: _shouldRequestContainerConversion(
        item.service,
        outputExt,
      ),
      allowQualityVariant: item.preserveQualityVariant,
      qualityVariant: item.preserveQualityVariant
          ? qualityVariantStagingLabel(item.id)
          : '',
      qualityVariantCollisionOnly: qualityVariantCollisionOnly,
      songLinkRegion: settings.songLinkRegion,
    );
  }

  String _newQueueItemId(Track track, {Set<String>? takenIds}) {
    final trimmedIsrc = track.isrc?.trim();
    final trimmedTrackId = track.id.trim();
    final base = (trimmedIsrc != null && trimmedIsrc.isNotEmpty)
        ? trimmedIsrc
        : (trimmedTrackId.isNotEmpty ? trimmedTrackId : 'track');

    while (true) {
      _queueItemSequence++;
      final candidate =
          '$base-${DateTime.now().microsecondsSinceEpoch}-$_queueItemSequence';
      if (takenIds == null || !takenIds.contains(candidate)) {
        return candidate;
      }
    }
  }

  List<DownloadItem> _normalizeRestoredQueueIds(List<DownloadItem> items) {
    if (items.isEmpty) return items;

    final seen = <String>{};
    var regeneratedCount = 0;
    final normalized = <DownloadItem>[];

    for (final item in items) {
      final trimmedId = item.id.trim();
      final shouldRegenerate = trimmedId.isEmpty || seen.contains(trimmedId);
      if (shouldRegenerate) {
        final newId = _newQueueItemId(item.track, takenIds: seen);
        seen.add(newId);
        normalized.add(item.copyWith(id: newId));
        regeneratedCount++;
      } else {
        seen.add(trimmedId);
        normalized.add(item);
      }
    }

    if (regeneratedCount > 0) {
      _log.w(
        'Regenerated $regeneratedCount duplicate/empty queue item IDs during restore',
      );
    }

    return normalized;
  }

  void updateSettings(AppSettings settings) {
    state = state.copyWith(
      outputDir: settings.downloadDirectory.isNotEmpty
          ? settings.downloadDirectory
          : state.outputDir,
      filenameFormat: settings.filenameFormat,
      singleFilenameFormat: settings.singleFilenameFormat,
      audioQuality: settings.audioQuality,
      autoFallback: settings.autoFallback,
    );
  }

  String addToQueue(
    Track track,
    String service, {
    String? qualityOverride,
    String? playlistName,
    int? playlistPosition,
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
      playlistPosition: playlistPosition,
      preserveQualityVariant: settings.allowQualityVariants,
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
    List<int?>? playlistPositions,
  }) {
    final settings = ref.read(settingsProvider);
    updateSettings(settings);

    final takenIds = state.items.map((item) => item.id).toSet();
    final shouldAssignPlaylistPositions =
        playlistName != null && playlistName.trim().isNotEmpty;
    final fromBatch = tracks.length > 1;
    final newItems = tracks.asMap().entries.map((entry) {
      final track = entry.value;
      final index = entry.key;
      final explicitPosition =
          playlistPositions != null &&
              index < playlistPositions.length &&
              (playlistPositions[index] ?? 0) > 0
          ? playlistPositions[index]
          : null;
      final id = _newQueueItemId(track, takenIds: takenIds);
      takenIds.add(id);
      return DownloadItem(
        id: id,
        track: track,
        service: _normalizeQueuedService(service),
        createdAt: DateTime.now(),
        qualityOverride: qualityOverride,
        playlistName: playlistName,
        playlistPosition:
            explicitPosition ??
            (shouldAssignPlaylistPositions ? index + 1 : null),
        fromBatch: fromBatch,
        preserveQualityVariant: settings.allowQualityVariants,
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
    state = state.copyWith(
      items: updatedItems,
      lookup: state.lookup.updatedForIndices(
        previousItems: items,
        nextItems: updatedItems,
        changedIndices: [index],
      ),
    );

    if (Platform.isAndroid && status == DownloadStatus.finalizing) {
      PlatformBridge.clearItemProgress(id).catchError((_) {});
      final queueCount = state.lookup.queuedCount;
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
      _purgeAlbumRgEntry(item.track);
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
    if (_hasActiveAndroidNativeWorker) {
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
      if (_hasActiveAndroidNativeWorker) {
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
      if (_hasActiveAndroidNativeWorker) {
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
    // A cancel issued while the item never started leaves a pre-registered
    // flag in the Go backend that the next attempt would consume and abort
    // instantly; the user asked for a retry, so drop it first.
    unawaited(
      PlatformBridge.resetDownloadCancel(id).catchError((Object e) {
        _log.w('Failed to reset cancel flag for $id: $e');
      }),
    );
    _locallyCancelledItemIds.remove(id);
    _verificationRetryGuard.clearItem(id);
    _rateLimitRetriedItemIds.remove(id);

    // Purge stale ReplayGain entry for this track so a re-scan doesn't
    // produce duplicate entries that bias album gain.
    _purgeAlbumRgEntry(item.track);

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

  void retryAllFailed({bool networkOnly = false}) {
    final failedIds = state.items
        .where(
          (item) =>
              (item.status == DownloadStatus.failed ||
                  item.status == DownloadStatus.skipped) &&
              (!networkOnly || item.errorType == DownloadErrorType.network),
        )
        .map((item) => item.id)
        .toSet();
    if (failedIds.isEmpty) {
      _log.d('retryAllFailed: no failed downloads to retry');
      return;
    }

    _log.i('Retrying ${failedIds.length} failed download(s)');
    for (final id in failedIds) {
      unawaited(
        PlatformBridge.resetDownloadCancel(id).catchError((Object e) {
          _log.w('Failed to reset cancel flag for $id: $e');
        }),
      );
    }
    _locallyCancelledItemIds.removeAll(failedIds);
    _pausePendingItemIds.removeAll(failedIds);

    for (final item in state.items) {
      if (!failedIds.contains(item.id)) continue;
      _purgeAlbumRgEntry(item.track);
    }

    final items = state.items
        .map((item) {
          if (!failedIds.contains(item.id)) return item;
          return item.copyWith(
            status: DownloadStatus.queued,
            progress: 0,
            speedMBps: 0,
            bytesReceived: 0,
            bytesTotal: 0,
            error: null,
          );
        })
        .toList(growable: false);

    state = state.copyWith(items: items, isPaused: false);
    _saveQueueToStorage();

    if (!state.isProcessing) {
      Future.microtask(() => _processQueue());
    }
  }

  /// Reinserts a queued item ahead of all other queued items so the next
  /// free download slot picks it up. During an active native worker run the
  /// current batch keeps its order; the new order applies from the next run.
  void downloadNext(String id) {
    final items = state.items;
    final index = items.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final item = items[index];
    if (item.status != DownloadStatus.queued) return;
    final firstQueuedIndex = items.indexWhere(
      (candidate) => candidate.status == DownloadStatus.queued,
    );
    if (firstQueuedIndex == index) return;
    final reordered = List<DownloadItem>.from(items)
      ..removeAt(index)
      ..insert(firstQueuedIndex, item);
    state = state.copyWith(items: reordered);
    _saveQueueToStorage();
  }

  /// Moves a queued item [offset] positions up (negative) or down (positive)
  /// among the queued items, leaving non-queued rows in place. Same native
  /// worker caveat as [downloadNext]: an in-flight batch keeps its order.
  void moveQueuedItem(String id, int offset) {
    if (offset == 0) return;
    final items = state.items;
    final index = items.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final item = items[index];
    if (item.status != DownloadStatus.queued) return;
    final queuedIndices = <int>[
      for (var i = 0; i < items.length; i++)
        if (items[i].status == DownloadStatus.queued) i,
    ];
    final position = queuedIndices.indexOf(index);
    final targetPosition = position + offset;
    if (targetPosition < 0 || targetPosition >= queuedIndices.length) return;
    final reordered = List<DownloadItem>.from(items)..removeAt(index);
    // Inserting at the target's pre-removal index lands the item directly
    // before it when moving up and directly after it when moving down.
    reordered.insert(queuedIndices[targetPosition], item);
    state = state.copyWith(items: reordered);
    _saveQueueToStorage();
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
      _purgeAlbumRgEntry(removedItem.track);
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
      case 'verification_required':
        return DownloadErrorType.verificationRequired;
      default:
        return DownloadErrorType.unknown;
    }
  }

  DownloadErrorType _downloadErrorTypeFromMessage(String errorMsg) {
    final lowerMsg = errorMsg.toLowerCase();
    if (isExtensionVerificationRequired(errorMsg)) {
      return DownloadErrorType.verificationRequired;
    }
    if (errorMsg.contains('429') ||
        lowerMsg.contains('rate limit') ||
        lowerMsg.contains('too many requests')) {
      return DownloadErrorType.rateLimit;
    }
    if (lowerMsg.contains('not found') ||
        lowerMsg.contains('not available') ||
        lowerMsg.contains('no results')) {
      return DownloadErrorType.notFound;
    }
    if (lowerMsg.contains('permission') ||
        lowerMsg.contains('operation not permitted') ||
        lowerMsg.contains('access denied')) {
      return DownloadErrorType.permission;
    }
    if (lowerMsg.contains('network') ||
        lowerMsg.contains('connection') ||
        lowerMsg.contains('timeout') ||
        lowerMsg.contains('dial')) {
      return DownloadErrorType.network;
    }
    return DownloadErrorType.unknown;
  }

  Future<void> _processQueue() async {
    if (state.isProcessing) return;

    var settings = ref.read(settingsProvider);
    updateSettings(settings);
    var isSafMode = _isSafMode(settings);
    var iosDownloadBookmarkActive = false;

    // Validate SAF before handing the batch to either queue implementation.
    // A restored/missing tree URI and an OEM-revoked grant both fall back to a
    // verified writable app folder instead of failing the whole queue.
    if (Platform.isAndroid && settings.storageMode == 'saf') {
      var safAccessible = settings.downloadTreeUri.isNotEmpty;
      if (safAccessible) {
        try {
          safAccessible = await PlatformBridge.validateSafTreeAccess(
            settings.downloadTreeUri,
          );
        } catch (e) {
          safAccessible = false;
          _log.w('SAF access validation threw an error: $e');
        }
      }
      if (!safAccessible) {
        _log.w(
          'SAF grant is missing or no longer writable; using app-folder fallback',
        );
        try {
          await _activateAppFolderStorageFallback();
          settings = ref.read(settingsProvider);
          isSafMode = false;
        } catch (e) {
          _log.e('Could not activate app-folder storage fallback: $e');
          for (final item in state.items) {
            if (item.status == DownloadStatus.queued) {
              updateItemStatus(
                item.id,
                DownloadStatus.failed,
                error: safPermissionLostErrorMessage,
                errorType: DownloadErrorType.permission,
              );
            }
          }
          return;
        }
      }
    }
    if (Platform.isAndroid &&
        !isSafMode &&
        state.outputDir.isNotEmpty &&
        !await _isDirectoryWritable(Directory(state.outputDir))) {
      final failedOutputDir = state.outputDir;
      _log.w(
        'Configured app-folder path is not writable; resolving a safe fallback',
      );
      try {
        await _activateAppFolderStorageFallback(
          failedOutputDir: failedOutputDir,
        );
        settings = ref.read(settingsProvider);
      } catch (e) {
        _log.e('No writable app-folder fallback is available: $e');
      }
    }
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
    }
    // Monitor in every mode so idle connections are recycled on a network
    // switch, even though only wifi_only pauses the queue.
    _networkPausedByWifiOnly = false;
    _startConnectivityMonitoring();

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

    // iOS: request a background execution window (no foreground service).
    if (Platform.isIOS && _totalQueuedAtStart > 0) {
      await PlatformBridge.beginBackgroundDownloadTask();
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
        _log.e('Failed to access iOS download folder bookmark');
        _log.w(
          'The saved download folder may have been moved, deleted, or its access grant lost',
        );
        for (final item in state.items) {
          if (item.status == DownloadStatus.queued) {
            updateItemStatus(
              item.id,
              DownloadStatus.failed,
              error: downloadFolderAccessLostErrorMessage,
            );
          }
        }
        state = state.copyWith(isProcessing: false);
        await PlatformBridge.endBackgroundDownloadTask();
        return;
      }
    }

    try {
      await _runQueueLoop();
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
    _clearEmbedCoverCache();
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

    if (Platform.isIOS) {
      await PlatformBridge.endBackgroundDownloadTask();
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

  Future<void> _runQueueLoop() async {
    final activeDownloads = <String, Future<void>>{};

    _startMultiProgressPolling();

    while (true) {
      if (state.isPaused) {
        if (activeDownloads.isEmpty) {
          _log.d('Queue is paused and no active download remains');
          break;
        }
        _log.d('Queue is paused, waiting for active download...');
        await Future.any([
          Future.wait(activeDownloads.values),
          Future<void>.delayed(_queueSchedulingInterval),
        ]);
        continue;
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

      final maxConcurrent = ref
          .read(settingsProvider)
          .concurrentDownloads
          .clamp(1, 3);
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
        _log.d('Started download: ${item.track.name}');
      }

      if (activeDownloads.isNotEmpty) {
        await Future.any([
          Future.any(activeDownloads.values),
          Future<void>.delayed(_queueSchedulingInterval),
        ]);
      } else {
        await Future<void>.delayed(_queueSchedulingInterval);
      }
    }

    if (activeDownloads.isNotEmpty) {
      await Future.wait(activeDownloads.values);
    }

    _stopProgressPolling();
    final remainingIds = state.items.map((item) => item.id).toSet();
    _locallyCancelledItemIds.removeWhere((id) => !remainingIds.contains(id));
    _pausePendingItemIds.removeWhere((id) => !remainingIds.contains(id));
    _verificationRetryGuard.retainItems(remainingIds);
    _rateLimitRetriedItemIds.removeWhere((id) => !remainingIds.contains(id));
  }
}

final downloadQueueProvider =
    NotifierProvider<DownloadQueueNotifier, DownloadQueueState>(
      DownloadQueueNotifier.new,
    );

final downloadQueueLookupProvider = Provider<DownloadQueueLookup>((ref) {
  return ref.watch(downloadQueueProvider.select((s) => s.lookup));
});
