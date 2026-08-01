import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/services/history_database.dart';
import 'package:spotiflac_android/utils/logger.dart' hide log;
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/utils/audio_format_utils.dart';
import 'package:spotiflac_android/utils/int_utils.dart';
import 'package:spotiflac_android/utils/path_match_keys.dart';

part 'download_history_models.dart';
part 'download_history_provider_maintenance.dart';

final _historyLog = AppLogger('DownloadHistory');

typedef StartupOrphanDecision = ({
  Set<String> confirmedIds,
  Set<String> pendingIds,
});

StartupOrphanDecision reconcileStartupOrphanSuspects({
  required Set<String> checkedIds,
  required Set<String> missingIds,
  required Set<String> previousSuspectIds,
}) {
  final currentMissing = missingIds.intersection(checkedIds);
  return (
    confirmedIds: currentMissing.intersection(previousSuspectIds),
    pendingIds: currentMissing.difference(previousSuspectIds),
  );
}

bool historyItemsReferToSameStoredFile(
  DownloadHistoryItem first,
  DownloadHistoryItem second,
) {
  if (first.id == second.id) return true;
  final firstKeys = buildPathMatchKeys(first.filePath);
  if (firstKeys.isEmpty) return false;
  return buildPathMatchKeys(
    second.filePath,
  ).any((key) => firstKeys.contains(key));
}

String? resolvePersistedHistoryQuality({
  required String? incoming,
  required String? existing,
}) {
  return nonPlaceholderQuality(incoming) ??
      nonPlaceholderQuality(existing) ??
      normalizeOptionalString(incoming) ??
      normalizeOptionalString(existing);
}

class DownloadHistoryNotifier extends Notifier<DownloadHistoryState> {
  static const int _initialHistoryLoadLimit = 100;
  static const int _safRepairBatchSize = 20;
  static const int _safRepairMaxPerLaunch = 60;
  static const int _orphanCleanupMaxPerLaunch = 80;
  static const int _audioMetadataBackfillMaxPerLaunch = 24;
  static const _startupMaintenanceDelay = Duration(seconds: 4);
  static const _startupMaintenanceStepGap = Duration(milliseconds: 250);
  static const _startupSafRepairCursorKey =
      'history_startup_saf_repair_cursor_v1';
  static const _startupOrphanCursorKey = 'history_startup_orphan_cursor_v1';
  static const _startupOrphanSuspectPrefix =
      'history_startup_orphan_suspect_v2_';
  static const _legacyStartupOrphanSuspectPrefix =
      'history_startup_orphan_suspect_v1_';
  static const _startupAudioCursorKey = 'history_startup_audio_cursor_v1';
  static const _audioProbeFailedPathsKey =
      'history_audio_probe_failed_paths_v1';
  static const _audioProbeFailedPathsMax = 300;
  final HistoryDatabase _db = HistoryDatabase.instance;
  bool _isLoaded = false;
  bool _isSafRepairInProgress = false;
  bool _isAudioMetadataBackfillInProgress = false;
  bool _startupMaintenanceScheduled = false;
  Future<void> _historyWriteChain = Future<void>.value();
  Timer? _indexBumpTimer;
  DateTime? _lastIndexBumpAt;
  static const _indexBumpWindow = Duration(seconds: 1);

  @override
  DownloadHistoryState build() {
    ref.onDispose(() => _indexBumpTimer?.cancel());
    _loadFromDatabaseSync();
    return DownloadHistoryState();
  }

  void _loadFromDatabaseSync() {
    if (_isLoaded) return;
    _isLoaded = true;
    Future.microtask(() async {
      await _loadFromDatabase();
    });
  }

  Future<void> _loadFromDatabase() async {
    try {
      final migrated = await _db.migrateFromSharedPreferences();
      if (migrated) {
        _historyLog.i('Migrated history from SharedPreferences to SQLite');
      }

      if (Platform.isIOS) {
        final pathsMigrated = await _db.migrateIosContainerPaths();
        if (pathsMigrated) {
          _historyLog.i('Migrated iOS container paths after app update');
        }
      }

      final countFuture = _db.getCount();
      final jsonList = await _db.getAll(limit: _initialHistoryLoadLimit);
      final items = jsonList
          .map((e) => DownloadHistoryItem.fromJson(e))
          .toList();
      final totalCount = await countFuture;

      state = state.copyWith(
        items: items,
        totalCount: totalCount,
        loadedIndexVersion: state.loadedIndexVersion + 1,
        lookupItems: items,
      );
      _historyLog.i(
        'Loaded ${items.length}/$totalCount recent history items from SQLite database',
      );
      _scheduleStartupMaintenance(items);
    } catch (e, stack) {
      _historyLog.e('Failed to load history from database: $e', e, stack);
    }
  }

  Future<void> reloadFromStorage() async {
    await _loadFromDatabase();
  }

  void _bumpHistoryRevision() {
    state = state.copyWith(loadedIndexVersion: state.loadedIndexVersion + 1);
  }

  Future<({DownloadHistoryItem item, String? existingId})> _resolveHistoryItem(
    DownloadHistoryItem item,
  ) async {
    DownloadHistoryItem? existing;
    for (final candidate in state.lookupItems) {
      if (historyItemsReferToSameStoredFile(candidate, item)) {
        existing = candidate;
        break;
      }
    }

    if (existing == null) {
      final json = await _db.getById(item.id);
      if (json != null) {
        existing = DownloadHistoryItem.fromJson(json);
      }
    }

    if (existing == null) {
      final json = await _db.findByFilePath(item.filePath);
      if (json != null) {
        existing = DownloadHistoryItem.fromJson(json);
      }
    }

    final incomingItem = existing != null && existing.id != item.id
        ? DownloadHistoryItem.fromJson(item.toJson()..['id'] = existing.id)
        : item;
    final mergedItem = existing == null
        ? incomingItem
        : incomingItem.copyWith(
            quality: resolvePersistedHistoryQuality(
              incoming: item.quality,
              existing: existing.quality,
            ),
            bitDepth: item.bitDepth ?? existing.bitDepth,
            sampleRate: item.sampleRate ?? existing.sampleRate,
            bitrate: item.bitrate ?? existing.bitrate,
            format:
                normalizeOptionalString(item.format) ??
                normalizeOptionalString(existing.format),
            trackNumber: item.trackNumber ?? existing.trackNumber,
            totalTracks: item.totalTracks ?? existing.totalTracks,
            discNumber: item.discNumber ?? existing.discNumber,
            totalDiscs: item.totalDiscs ?? existing.totalDiscs,
            genre:
                normalizeOptionalString(item.genre) ??
                normalizeOptionalString(existing.genre),
            composer:
                normalizeOptionalString(item.composer) ??
                normalizeOptionalString(existing.composer),
            label:
                normalizeOptionalString(item.label) ??
                normalizeOptionalString(existing.label),
            copyright:
                normalizeOptionalString(item.copyright) ??
                normalizeOptionalString(existing.copyright),
          );
    return (item: mergedItem, existingId: existing?.id);
  }

  void _putResolvedHistoryInMemory(
    DownloadHistoryItem item,
    String? existingId,
  ) {
    if (existingId != null) {
      final updatedItems = state.items
          .where((candidate) => candidate.id != existingId)
          .toList();
      updatedItems.insert(0, item);
      final updatedLookupItems = state.lookupItems
          .where((candidate) => candidate.id != existingId)
          .toList(growable: false);
      state = state.copyWith(
        items: updatedItems,
        lookupItems: [item, ...updatedLookupItems],
      );
      _historyLog.d('Updated existing history entry: ${item.trackName}');
    } else {
      state = state.copyWith(
        items: [item, ...state.items],
        totalCount: state.totalCount + 1,
        lookupItems: [item, ...state.lookupItems],
      );
      _historyLog.d('Added new history entry: ${item.trackName}');
    }
  }

  List<DownloadHistoryItem> _lookupItemsWithUpdates(
    Iterable<DownloadHistoryItem> updates, {
    Set<String> deletedIds = const <String>{},
  }) {
    final byId = <String, DownloadHistoryItem>{
      for (final item in state.lookupItems)
        if (!deletedIds.contains(item.id)) item.id: item,
    };
    for (final item in updates) {
      if (!deletedIds.contains(item.id)) {
        byId[item.id] = item;
      }
    }
    return byId.values.toList(growable: false);
  }

  Future<void> addToHistory(
    DownloadHistoryItem item, {
    bool preserveTrackVariant = false,
  }) => _enqueueHistoryWrite(
    () => _persistHistoryItem(
      item,
      'save to database',
      preserveTrackVariant: preserveTrackVariant,
    ),
  );

  Future<void> adoptNativeHistoryItem(
    DownloadHistoryItem item, {
    bool preserveTrackVariant = false,
  }) => _enqueueHistoryWrite(
    () => _persistHistoryItem(
      item,
      'adopt native history item',
      preserveTrackVariant: preserveTrackVariant,
    ),
  );

  Future<void> _enqueueHistoryWrite(Future<void> Function() operation) {
    final pending = _historyWriteChain.then((_) => operation());
    _historyWriteChain = pending.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return pending;
  }

  Future<void> _persistHistoryItem(
    DownloadHistoryItem item,
    String action, {
    required bool preserveTrackVariant,
  }) async {
    try {
      if (preserveTrackVariant) {
        await _db.upsert(item.toJson());
        _putInMemoryTrackVariant(item);
      } else {
        final resolved = await _resolveHistoryItem(item);
        await _db.upsert(resolved.item.toJson());
        _putResolvedHistoryInMemory(resolved.item, resolved.existingId);
      }
      _scheduleIndexBump();
    } catch (e, stack) {
      _historyLog.e('Failed to $action: $e', e, stack);
      rethrow;
    }
  }

  /// Coalesces the post-persist count refresh + index bump to at most one per
  /// [_indexBumpWindow]. Every bump invalidates the DB-derived views (queue
  /// union queries, grouped counts, per-row exists checks) across all
  /// keep-alive tabs, so per-item bumps during a batch fan out into repeated
  /// full-table work.
  void _scheduleIndexBump() {
    if (_indexBumpTimer != null) return;
    final now = DateTime.now();
    final sinceLast = _lastIndexBumpAt == null
        ? _indexBumpWindow
        : now.difference(_lastIndexBumpAt!);
    if (sinceLast >= _indexBumpWindow) {
      _lastIndexBumpAt = now;
      unawaited(_bumpIndexNow());
      return;
    }
    _indexBumpTimer = Timer(_indexBumpWindow - sinceLast, () {
      _indexBumpTimer = null;
      _lastIndexBumpAt = DateTime.now();
      unawaited(_bumpIndexNow());
    });
  }

  Future<void> _bumpIndexNow() async {
    int? persistedCount;
    try {
      persistedCount = await _db.getCount();
    } catch (error) {
      _historyLog.w('History saved but count refresh failed: $error');
    }
    state = state.copyWith(
      totalCount: persistedCount ?? state.totalCount,
      loadedIndexVersion: state.loadedIndexVersion + 1,
    );
  }

  DownloadHistoryItem _putInMemoryTrackVariant(DownloadHistoryItem item) {
    final isReplacement = state.items.any((existing) => existing.id == item.id);
    final items = [
      item,
      ...state.items.where((existing) => existing.id != item.id),
    ];
    final lookupItems = [
      item,
      ...state.lookupItems.where((existing) => existing.id != item.id),
    ];
    state = state.copyWith(
      items: items,
      totalCount: isReplacement ? state.totalCount : state.totalCount + 1,
      lookupItems: lookupItems,
    );
    _historyLog.d('Added independent history variant: ${item.trackName}');
    return item;
  }

  void removeFromHistory(String id) {
    state = state.copyWith(
      items: state.items.where((item) => item.id != id).toList(),
      totalCount: state.totalCount > 0
          ? state.totalCount - 1
          : state.totalCount,
      lookupItems: state.lookupItems
          .where((item) => item.id != id)
          .toList(growable: false),
    );
    _db
        .deleteById(id)
        .catchError((Object e) {
          _historyLog.e('Failed to delete from database: $e');
        })
        .then((_) {
          _bumpHistoryRevision();
        });
  }

  DownloadHistoryItem? getBySpotifyId(String spotifyId) {
    return state.getBySpotifyId(spotifyId);
  }

  DownloadHistoryItem? getByIsrc(String isrc) {
    return state.getByIsrc(isrc);
  }

  Future<DownloadHistoryItem?> getBySpotifyIdAsync(String spotifyId) async {
    final inMemory = state.getBySpotifyId(spotifyId);
    if (inMemory != null) return inMemory;

    final json = await _db.getBySpotifyId(spotifyId);
    if (json == null) return null;
    return DownloadHistoryItem.fromJson(json);
  }

  Future<DownloadHistoryItem?> getByIsrcAsync(String isrc) async {
    final inMemory = state.getByIsrc(isrc);
    if (inMemory != null) return inMemory;

    final json = await _db.getByIsrc(isrc);
    if (json == null) return null;
    return DownloadHistoryItem.fromJson(json);
  }

  Future<DownloadHistoryItem?> getByFilePathAsync(String filePath) async {
    final targetKeys = buildPathMatchKeys(filePath);
    if (targetKeys.isEmpty) return null;

    for (final item in state.lookupItems) {
      if (buildPathMatchKeys(item.filePath).any(targetKeys.contains)) {
        return item;
      }
    }

    final json = await _db.findByFilePath(filePath);
    if (json == null) return null;
    return DownloadHistoryItem.fromJson(json);
  }

  Future<DownloadHistoryItem?> findByTrackAndArtistAsync(
    String trackName,
    String artistName,
  ) async {
    final inMemory = state.findByTrackAndArtist(trackName, artistName);
    if (inMemory != null) return inMemory;

    final json = await _db.findByTrackAndArtist(trackName, artistName);
    if (json == null) return null;
    return DownloadHistoryItem.fromJson(json);
  }

  Future<DownloadHistoryItem?> findExistingTrackAsync(
    HistoryLookupRequest request,
  ) async {
    final bySpotifyId = state.getBySpotifyId(request.spotifyId);
    if (bySpotifyId != null) return bySpotifyId;

    final isrc = request.isrc?.trim();
    if (isrc != null && isrc.isNotEmpty) {
      final byIsrc = state.getByIsrc(isrc);
      if (byIsrc != null) return byIsrc;
    }

    final byTrackArtist = state.findByTrackAndArtist(
      request.trackName,
      request.artistName,
    );
    if (byTrackArtist != null) return byTrackArtist;

    final json = await _db.findExistingTrack(request);
    if (json == null) return null;
    return DownloadHistoryItem.fromJson(json);
  }

  Future<({DownloadHistoryItem item, int index})?> _historyItemForUpdate(
    String id,
  ) async {
    final index = state.items.indexWhere((item) => item.id == id);
    if (index >= 0) {
      return (item: state.items[index], index: index);
    }

    final json = await _db.getById(id);
    if (json == null) return null;
    return (item: DownloadHistoryItem.fromJson(json), index: -1);
  }

  Future<void> updateAudioMetadataForItem({
    required String id,
    String? quality,
    int? bitDepth,
    int? sampleRate,
    int? bitrate,
    String? format,
    int? trackNumber,
    int? totalTracks,
    int? discNumber,
    int? totalDiscs,
    int? duration,
    String? composer,
  }) async {
    final target = await _historyItemForUpdate(id);
    if (target == null) {
      _historyLog.w(
        'Cannot update audio metadata for missing history item: $id',
      );
      return;
    }

    final current = target.item;
    final updated = current.copyWith(
      quality: quality,
      bitDepth: bitDepth,
      sampleRate: sampleRate,
      bitrate: bitrate,
      format: format,
      trackNumber: trackNumber,
      totalTracks: totalTracks,
      discNumber: discNumber,
      totalDiscs: totalDiscs,
      duration: duration,
      composer: composer,
    );

    if (updated.quality == current.quality &&
        updated.bitDepth == current.bitDepth &&
        updated.sampleRate == current.sampleRate &&
        updated.bitrate == current.bitrate &&
        updated.format == current.format &&
        updated.trackNumber == current.trackNumber &&
        updated.totalTracks == current.totalTracks &&
        updated.discNumber == current.discNumber &&
        updated.totalDiscs == current.totalDiscs &&
        updated.duration == current.duration &&
        updated.composer == current.composer) {
      return;
    }

    final updatedItems = target.index >= 0
        ? ([...state.items]..[target.index] = updated)
        : state.items;
    state = state.copyWith(
      items: updatedItems,
      lookupItems: _lookupItemsWithUpdates([updated]),
    );
    await _db.upsert(updated.toJson());
    // Swiping through older tracks can backfill several quality records in a
    // short burst. Coalesce their DB-derived Library refreshes just like
    // download completion writes instead of rebuilding every view per swipe.
    _scheduleIndexBump();
  }

  Future<void> updateMetadataForItem({
    required String id,
    required String trackName,
    required String artistName,
    required String albumName,
    String? albumArtist,
    String? isrc,
    int? trackNumber,
    int? totalTracks,
    int? discNumber,
    int? totalDiscs,
    String? releaseDate,
    String? genre,
    String? composer,
    String? label,
    String? copyright,
  }) async {
    final target = await _historyItemForUpdate(id);
    if (target == null) {
      _historyLog.w('Cannot update metadata for missing history item: $id');
      return;
    }

    final current = target.item;
    final updated = current.copyWith(
      trackName: trackName,
      artistName: artistName,
      albumName: albumName,
      albumArtist: albumArtist,
      isrc: isrc,
      trackNumber: trackNumber,
      totalTracks: totalTracks,
      discNumber: discNumber,
      totalDiscs: totalDiscs,
      releaseDate: releaseDate,
      genre: genre,
      composer: composer,
      label: label,
      copyright: copyright,
    );

    final updatedItems = target.index >= 0
        ? ([...state.items]..[target.index] = updated)
        : state.items;
    state = state.copyWith(
      items: updatedItems,
      lookupItems: _lookupItemsWithUpdates([updated]),
    );
    await _db.upsert(updated.toJson());
    _bumpHistoryRevision();
  }

  static const _audioExtensions = [
    '.flac',
    '.m4a',
    '.mp3',
    '.opus',
    '.ogg',
    '.wav',
    '.aiff',
    '.aac',
    '.mp4',
  ];

  Future<String?> _findConvertedSibling(
    String originalPath, {
    bool includeAlternateExtensions = true,
  }) async {
    final dotIndex = originalPath.lastIndexOf('.');
    if (dotIndex < 0) return null;
    final directoryPrefix = originalPath.substring(
      0,
      originalPath.lastIndexOf(Platform.pathSeparator) + 1,
    );
    final fileName = originalPath.substring(
      originalPath.lastIndexOf(Platform.pathSeparator) + 1,
    );

    for (final candidateName in _conversionRenameCandidates(
      fileName,
      includeAlternateExtensions: includeAlternateExtensions,
    )) {
      final candidatePath = '$directoryPrefix$candidateName';
      if (candidatePath == originalPath) continue;
      try {
        if (await fileExists(candidatePath)) return candidatePath;
      } catch (_) {}
    }
    return null;
  }

  Future<bool> verifyOrRepairHistoryItem(DownloadHistoryItem item) async {
    if (await fileExists(item.filePath)) return true;

    DownloadHistoryItem? repaired;
    if (item.storageMode == 'saf' &&
        item.downloadTreeUri != null &&
        item.downloadTreeUri!.isNotEmpty) {
      var fileName = (item.safFileName ?? '').trim();
      if (fileName.isEmpty && isContentUri(item.filePath)) {
        fileName = _fileNameFromUri(item.filePath);
      }
      for (final candidate in _conversionRenameCandidates(fileName)) {
        try {
          final resolved = await PlatformBridge.resolveSafFile(
            treeUri: item.downloadTreeUri!,
            relativeDir: item.safRelativeDir ?? '',
            fileName: candidate,
          );
          final uri = (resolved['uri'] as String? ?? '').trim();
          if (uri.isEmpty || !await fileExists(uri)) continue;
          final relativeDir = (resolved['relative_dir'] as String? ?? '')
              .trim();
          repaired = item.copyWith(
            filePath: uri,
            safFileName: candidate,
            safRelativeDir: relativeDir.isEmpty
                ? item.safRelativeDir
                : relativeDir,
            safRepaired: true,
          );
          break;
        } catch (error) {
          _historyLog.w('Failed to resolve renamed SAF file: $error');
        }
      }
    } else if (!isContentUri(item.filePath)) {
      final sibling = await _findConvertedSibling(
        item.filePath,
        includeAlternateExtensions: false,
      );
      if (sibling != null) repaired = item.copyWith(filePath: sibling);
    }

    if (repaired == null) return false;
    await _db.upsert(repaired.toJson());
    final updatedItems = state.items
        .map((entry) => entry.id == repaired!.id ? repaired : entry)
        .toList(growable: false);
    final updatedLookupItems = state.lookupItems
        .map((entry) => entry.id == repaired!.id ? repaired : entry)
        .toList(growable: false);
    state = state.copyWith(
      items: updatedItems,
      lookupItems: updatedLookupItems,
    );
    _historyLog.i(
      'Reconciled renamed conversion: ${item.filePath} -> ${repaired.filePath}',
    );
    return true;
  }

  Future<
    ({
      List<String> orphanedIds,
      Map<String, String> replacementPaths,
      Map<String, String> replacementFileNames,
      Map<String, String> replacementRelativeDirs,
      Map<String, String> pathById,
    })
  >
  _inspectOrphanedEntries(List<Map<String, dynamic>> entries) async {
    final orphanedIds = <String>[];
    final replacementPaths = <String, String>{};
    final replacementFileNames = <String, String>{};
    final replacementRelativeDirs = <String, String>{};
    final pathById = <String, String>{};
    const checkChunkSize = 16;

    for (var i = 0; i < entries.length; i += checkChunkSize) {
      final end = (i + checkChunkSize < entries.length)
          ? i + checkChunkSize
          : entries.length;
      final chunk = entries.sublist(i, end);

      final checks = await Future.wait<MapEntry<String, bool?>?>(
        chunk.map((entry) async {
          final id = entry['id'] as String;
          final filePath = entry['file_path'] as String?;
          if (filePath == null || filePath.isEmpty) return null;
          pathById[id] = filePath;
          try {
            if (await fileExists(filePath)) return MapEntry(id, true);

            if (entry['storage_mode'] == 'saf') {
              final treeUri = (entry['download_tree_uri'] as String? ?? '')
                  .trim();
              var fileName = (entry['saf_file_name'] as String? ?? '').trim();
              if (fileName.isEmpty && isContentUri(filePath)) {
                fileName = _fileNameFromUri(filePath);
              }
              if (treeUri.isEmpty || fileName.isEmpty) {
                return MapEntry(id, null);
              }

              bool treeAccessible;
              try {
                treeAccessible = await PlatformBridge.validateSafTreeAccess(
                  treeUri,
                );
              } catch (error) {
                _historyLog.w(
                  'Unable to verify SAF tree while checking $id: $error',
                );
                return MapEntry(id, null);
              }
              if (!treeAccessible) {
                return MapEntry(id, null);
              }

              for (final candidate in _conversionRenameCandidates(
                fileName,
                includeAlternateExtensions: true,
              )) {
                try {
                  final resolved = await PlatformBridge.resolveSafFile(
                    treeUri: treeUri,
                    relativeDir: entry['saf_relative_dir'] as String? ?? '',
                    fileName: candidate,
                  );
                  final uri = (resolved['uri'] as String? ?? '').trim();
                  if (uri.isEmpty) continue;
                  replacementPaths[id] = uri;
                  replacementFileNames[id] = candidate;
                  final relativeDir =
                      (resolved['relative_dir'] as String? ?? '').trim();
                  if (relativeDir.isNotEmpty) {
                    replacementRelativeDirs[id] = relativeDir;
                  }
                  pathById[id] = uri;
                  return MapEntry(id, true);
                } catch (error) {
                  _historyLog.w(
                    'Unable to resolve SAF file while checking $id: $error',
                  );
                  return MapEntry(id, null);
                }
              }
              return MapEntry(id, false);
            }

            final sibling = await _findConvertedSibling(filePath);
            if (sibling != null) {
              _historyLog.i(
                'Found converted sibling for $id: $filePath -> $sibling',
              );
              replacementPaths[id] = sibling;
              pathById[id] = sibling;
              return MapEntry(id, true);
            }

            return MapEntry(id, false);
          } catch (e) {
            _historyLog.w('Error checking file existence for $id: $e');
            return MapEntry(id, null);
          }
        }),
      );

      for (final check in checks) {
        if (check == null || check.value != false) continue;
        orphanedIds.add(check.key);
        _historyLog.d(
          'Found orphaned entry: ${check.key} (${pathById[check.key] ?? ''})',
        );
      }
    }

    return (
      orphanedIds: orphanedIds,
      replacementPaths: replacementPaths,
      replacementFileNames: replacementFileNames,
      replacementRelativeDirs: replacementRelativeDirs,
      pathById: pathById,
    );
  }

  void _applyHistoryPathAndDeletionChanges({
    required List<String> deletedIds,
    required Map<String, String> replacementPaths,
    Map<String, String> replacementFileNames = const {},
    Map<String, String> replacementRelativeDirs = const {},
  }) {
    if (deletedIds.isEmpty && replacementPaths.isEmpty) {
      return;
    }
    final deletedSet = deletedIds.toSet();
    final updatedItems = <DownloadHistoryItem>[];
    for (final item in state.items) {
      if (deletedSet.contains(item.id)) {
        continue;
      }
      final replacementPath = replacementPaths[item.id];
      final replacementFileName = replacementFileNames[item.id];
      final replacementRelativeDir = replacementRelativeDirs[item.id];
      if (replacementPath != null &&
          (replacementPath != item.filePath ||
              (replacementFileName != null &&
                  replacementFileName != item.safFileName) ||
              (replacementRelativeDir != null &&
                  replacementRelativeDir != item.safRelativeDir))) {
        updatedItems.add(
          item.copyWith(
            filePath: replacementPath,
            safFileName: replacementFileName,
            safRelativeDir: replacementRelativeDir,
          ),
        );
      } else {
        updatedItems.add(item);
      }
    }
    state = state.copyWith(
      items: updatedItems,
      loadedIndexVersion: state.loadedIndexVersion + 1,
      lookupItems: _lookupItemsWithUpdates(
        updatedItems,
        deletedIds: deletedSet,
      ),
      totalCount: max(0, state.totalCount - deletedSet.length),
    );
  }

  Future<int> _cleanupOrphanedDownloadsIncremental({
    required int maxItems,
    required SharedPreferences prefs,
  }) async {
    final cursor = prefs.getInt(_startupOrphanCursorKey) ?? 0;
    final safeCursor = cursor < 0 ? 0 : cursor;
    final entries = await _db.getEntriesWithPathsPage(
      limit: maxItems,
      offset: safeCursor,
    );
    if (entries.isEmpty) {
      await prefs.remove(_startupOrphanCursorKey);
      return 0;
    }

    final result = await _inspectOrphanedEntries(entries);
    final checkedIds = result.pathById.keys.toSet();
    final previousSuspectIds = <String>{
      for (final id in checkedIds)
        if (prefs.getBool('$_startupOrphanSuspectPrefix$id') == true) id,
    };
    final decision = reconcileStartupOrphanSuspects(
      checkedIds: checkedIds,
      missingIds: result.orphanedIds.toSet(),
      previousSuspectIds: previousSuspectIds,
    );
    for (final id in checkedIds) {
      final key = '$_startupOrphanSuspectPrefix$id';
      await prefs.remove('$_legacyStartupOrphanSuspectPrefix$id');
      if (decision.pendingIds.contains(id)) {
        await prefs.setBool(key, true);
        _historyLog.d(
          'Deferring orphan removal until next pass: $id (${result.pathById[id] ?? ''})',
        );
      } else {
        await prefs.remove(key);
      }
    }
    for (final replacement in result.replacementPaths.entries) {
      await _db.updateFilePath(
        replacement.key,
        replacement.value,
        newSafFileName: result.replacementFileNames[replacement.key],
        newSafRelativeDir: result.replacementRelativeDirs[replacement.key],
      );
      await prefs.remove('$_startupOrphanSuspectPrefix${replacement.key}');
    }

    final confirmedOrphanIds = decision.confirmedIds.toList(growable: false);
    final deletedCount = confirmedOrphanIds.isEmpty
        ? 0
        : await _db.deleteByIds(confirmedOrphanIds);

    _applyHistoryPathAndDeletionChanges(
      deletedIds: confirmedOrphanIds,
      replacementPaths: result.replacementPaths,
      replacementFileNames: result.replacementFileNames,
      replacementRelativeDirs: result.replacementRelativeDirs,
    );

    if (entries.length < maxItems) {
      await prefs.remove(_startupOrphanCursorKey);
    } else {
      final nextCursor = result.orphanedIds.isNotEmpty
          ? safeCursor
          : safeCursor + entries.length;
      await prefs.setInt(_startupOrphanCursorKey, nextCursor);
    }

    if (deletedCount > 0 || result.replacementPaths.isNotEmpty) {
      _historyLog.i(
        'Startup orphan cleanup pass: removed=$deletedCount, repaired=${result.replacementPaths.length}, checked=${entries.length}',
      );
    }
    return deletedCount;
  }

  Future<int> cleanupOrphanedDownloads() async {
    _historyLog.i('Starting orphaned downloads cleanup...');
    final orphanedIds = <String>[];
    final replacementPaths = <String, String>{};
    final replacementFileNames = <String, String>{};
    final replacementRelativeDirs = <String, String>{};
    const pageSize = 256;
    var offset = 0;

    while (true) {
      final entries = await _db.getEntriesWithPathsPage(
        limit: pageSize,
        offset: offset,
      );
      if (entries.isEmpty) {
        break;
      }

      final result = await _inspectOrphanedEntries(entries);
      orphanedIds.addAll(result.orphanedIds);
      replacementPaths.addAll(result.replacementPaths);
      replacementFileNames.addAll(result.replacementFileNames);
      replacementRelativeDirs.addAll(result.replacementRelativeDirs);

      if (entries.length < pageSize) {
        break;
      }
      // Deletions are applied only after inspection finishes, so advance by
      // the full page. Subtracting missing rows here can repeatedly fetch the
      // same page forever when an entire page is orphaned.
      offset += entries.length;
    }

    for (final replacement in replacementPaths.entries) {
      await _db.updateFilePath(
        replacement.key,
        replacement.value,
        newSafFileName: replacementFileNames[replacement.key],
        newSafRelativeDir: replacementRelativeDirs[replacement.key],
      );
    }

    if (orphanedIds.isEmpty && replacementPaths.isEmpty) {
      _historyLog.i('No orphaned entries found');
      return 0;
    }

    final deletedCount = orphanedIds.isEmpty
        ? 0
        : await _db.deleteByIds(orphanedIds);
    _applyHistoryPathAndDeletionChanges(
      deletedIds: orphanedIds,
      replacementPaths: replacementPaths,
      replacementFileNames: replacementFileNames,
      replacementRelativeDirs: replacementRelativeDirs,
    );

    _historyLog.i(
      'Cleaned up $deletedCount orphaned entries and repaired ${replacementPaths.length} paths',
    );
    return deletedCount;
  }

  void clearHistory() {
    state = DownloadHistoryState(loadedIndexVersion: state.loadedIndexVersion);
    _db
        .clearAll()
        .then((_) {
          _bumpHistoryRevision();
        })
        .catchError((Object e) {
          _historyLog.e('Failed to clear database: $e');
        });
  }

  /// Replaces all download history with [items] (each in the
  /// [DownloadHistoryItem.toJson] shape) from a restored backup, then reloads
  /// the in-memory state from storage.
  Future<void> restoreFromBackup(List<Map<String, dynamic>> items) async {
    await _db.clearAll();
    if (items.isNotEmpty) {
      await _db.upsertBatch(items);
    }
    await reloadFromStorage();
  }
}

final downloadHistoryProvider =
    NotifierProvider<DownloadHistoryNotifier, DownloadHistoryState>(
      DownloadHistoryNotifier.new,
    );

class DownloadHistoryGroupedCounts {
  final int albumCount;
  final int singleTrackCount;

  const DownloadHistoryGroupedCounts({
    required this.albumCount,
    required this.singleTrackCount,
  });
}

final downloadHistoryGroupedCountsProvider =
    FutureProvider<DownloadHistoryGroupedCounts>((ref) async {
      ref.watch(
        downloadHistoryProvider.select((state) => state.loadedIndexVersion),
      );
      final counts = await HistoryDatabase.instance.getGroupedCounts();
      return DownloadHistoryGroupedCounts(
        albumCount: counts['albums'] ?? 0,
        singleTrackCount: counts['singles'] ?? 0,
      );
    });

HistoryLookupRequest historyLookupForTrack(Track track) {
  return HistoryLookupRequest(
    spotifyId: track.id,
    isrc: track.isrc,
    trackName: track.name,
    artistName: track.artistName,
  );
}

final downloadHistoryExistsProvider = FutureProvider.autoDispose
    .family<bool, HistoryLookupRequest>((ref, request) async {
      ref.watch(
        downloadHistoryProvider.select((state) => state.loadedIndexVersion),
      );
      final notifier = ref.read(downloadHistoryProvider.notifier);
      final row = await HistoryDatabase.instance.findExistingTrack(request);
      if (row == null) return false;
      return notifier.verifyOrRepairHistoryItem(
        DownloadHistoryItem.fromJson(row),
      );
    });

// Deliberately no per-row verifyOrRepairHistoryItem here (issue #495): on a
// >500-track playlist that verify pass meant one SAF stat round-trip per
// already-downloaded track, and any loadedIndexVersion bump mid-pass restarted
// it from zero — above ~500 tracks the future never settled and "Download all"
// silently did nothing. Stale rows are reconciled by the startup repair and
// orphan-cleanup passes; the single-track provider above keeps the verify.
final downloadHistoryBatchExistsProvider = FutureProvider.autoDispose
    .family<Set<String>, HistoryBatchLookupRequest>((ref, request) async {
      ref.watch(
        downloadHistoryProvider.select((state) => state.loadedIndexVersion),
      );
      final rows = await HistoryDatabase.instance.findExistingTracks(
        request.tracks,
      );
      return <String>{
        for (var i = 0; i < rows.length; i++)
          if (rows[i] != null) request.tracks[i].lookupKey,
      };
    });

class DownloadedAlbumTracksRequest {
  final String albumName;
  final String artistName;

  const DownloadedAlbumTracksRequest({
    required this.albumName,
    required this.artistName,
  });

  @override
  bool operator ==(Object other) =>
      other is DownloadedAlbumTracksRequest &&
      other.albumName == albumName &&
      other.artistName == artistName;

  @override
  int get hashCode => Object.hash(albumName, artistName);
}

final downloadedAlbumTracksProvider = FutureProvider.autoDispose
    .family<List<DownloadHistoryItem>, DownloadedAlbumTracksRequest>((
      ref,
      request,
    ) async {
      ref.watch(
        downloadHistoryProvider.select((state) => state.loadedIndexVersion),
      );
      final rows = await HistoryDatabase.instance.getAlbumTracks(
        request.albumName,
        request.artistName,
      );
      return rows.map(DownloadHistoryItem.fromJson).toList(growable: false);
    });
