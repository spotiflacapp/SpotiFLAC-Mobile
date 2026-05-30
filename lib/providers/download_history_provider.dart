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
import 'package:spotiflac_android/utils/int_utils.dart';

export 'package:spotiflac_android/services/history_database.dart'
    show HistoryLookupRequest, HistoryBatchLookupRequest;

final _historyLog = AppLogger('DownloadHistory');

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

class DownloadHistoryItem {
  final String id;
  final String trackName;
  final String artistName;
  final String albumName;
  final String? albumArtist;
  final String? coverUrl;
  final String filePath;
  final String? storageMode;
  final String? downloadTreeUri;
  final String? safRelativeDir;
  final String? safFileName;
  final bool safRepaired;
  final String service;
  final DateTime downloadedAt;
  final String? isrc;
  final String? spotifyId;
  final int? trackNumber;
  final int? totalTracks;
  final int? discNumber;
  final int? totalDiscs;
  final int? duration;
  final String? releaseDate;
  final String? quality;
  final int? bitDepth;
  final int? sampleRate;
  final int? bitrate;
  final String? format;
  final String? genre;
  final String? composer;
  final String? label;
  final String? copyright;

  const DownloadHistoryItem({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.albumArtist,
    this.coverUrl,
    required this.filePath,
    this.storageMode,
    this.downloadTreeUri,
    this.safRelativeDir,
    this.safFileName,
    this.safRepaired = false,
    required this.service,
    required this.downloadedAt,
    this.isrc,
    this.spotifyId,
    this.trackNumber,
    this.totalTracks,
    this.discNumber,
    this.totalDiscs,
    this.duration,
    this.releaseDate,
    this.quality,
    this.bitDepth,
    this.sampleRate,
    this.bitrate,
    this.format,
    this.genre,
    this.composer,
    this.label,
    this.copyright,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'trackName': trackName,
    'artistName': artistName,
    'albumName': albumName,
    'albumArtist': albumArtist,
    'coverUrl': coverUrl,
    'filePath': filePath,
    'storageMode': storageMode,
    'downloadTreeUri': downloadTreeUri,
    'safRelativeDir': safRelativeDir,
    'safFileName': safFileName,
    'safRepaired': safRepaired,
    'service': service,
    'downloadedAt': downloadedAt.toIso8601String(),
    'isrc': isrc,
    'spotifyId': spotifyId,
    'trackNumber': trackNumber,
    'totalTracks': totalTracks,
    'discNumber': discNumber,
    'totalDiscs': totalDiscs,
    'duration': duration,
    'releaseDate': releaseDate,
    'quality': quality,
    'bitDepth': bitDepth,
    'sampleRate': sampleRate,
    'bitrate': bitrate,
    'format': format,
    'genre': genre,
    'composer': composer,
    'label': label,
    'copyright': copyright,
  };

  factory DownloadHistoryItem.fromJson(Map<String, dynamic> json) =>
      DownloadHistoryItem(
        id: json['id'] as String,
        trackName: json['trackName'] as String,
        artistName: json['artistName'] as String,
        albumName: json['albumName'] as String,
        albumArtist: normalizeOptionalString(json['albumArtist'] as String?),
        coverUrl: normalizeCoverReference(json['coverUrl']?.toString()),
        filePath: json['filePath'] as String,
        storageMode: json['storageMode'] as String?,
        downloadTreeUri: json['downloadTreeUri'] as String?,
        safRelativeDir: json['safRelativeDir'] as String?,
        safFileName: json['safFileName'] as String?,
        safRepaired: json['safRepaired'] == true,
        service: json['service'] as String,
        downloadedAt: DateTime.parse(json['downloadedAt'] as String),
        isrc: json['isrc'] as String?,
        spotifyId: json['spotifyId'] as String?,
        trackNumber: json['trackNumber'] as int?,
        totalTracks: json['totalTracks'] as int?,
        discNumber: json['discNumber'] as int?,
        totalDiscs: json['totalDiscs'] as int?,
        duration: json['duration'] as int?,
        releaseDate: json['releaseDate'] as String?,
        quality: json['quality'] as String?,
        bitDepth: json['bitDepth'] as int?,
        sampleRate: json['sampleRate'] as int?,
        bitrate: (json['bitrate'] as num?)?.toInt(),
        format: json['format'] as String?,
        genre: json['genre'] as String?,
        composer: json['composer'] as String?,
        label: json['label'] as String?,
        copyright: json['copyright'] as String?,
      );

  DownloadHistoryItem copyWith({
    String? trackName,
    String? artistName,
    String? albumName,
    String? albumArtist,
    String? coverUrl,
    String? filePath,
    String? storageMode,
    String? downloadTreeUri,
    String? safRelativeDir,
    String? safFileName,
    bool? safRepaired,
    String? isrc,
    String? spotifyId,
    int? trackNumber,
    int? totalTracks,
    int? discNumber,
    int? totalDiscs,
    int? duration,
    String? releaseDate,
    String? quality,
    int? bitDepth,
    int? sampleRate,
    int? bitrate,
    String? format,
    String? genre,
    String? composer,
    String? label,
    String? copyright,
  }) {
    return DownloadHistoryItem(
      id: id,
      trackName: trackName ?? this.trackName,
      artistName: artistName ?? this.artistName,
      albumName: albumName ?? this.albumName,
      albumArtist: albumArtist ?? this.albumArtist,
      coverUrl: normalizeCoverReference(coverUrl ?? this.coverUrl),
      filePath: filePath ?? this.filePath,
      storageMode: storageMode ?? this.storageMode,
      downloadTreeUri: downloadTreeUri ?? this.downloadTreeUri,
      safRelativeDir: safRelativeDir ?? this.safRelativeDir,
      safFileName: safFileName ?? this.safFileName,
      safRepaired: safRepaired ?? this.safRepaired,
      service: service,
      downloadedAt: downloadedAt,
      isrc: isrc ?? this.isrc,
      spotifyId: spotifyId ?? this.spotifyId,
      trackNumber: trackNumber ?? this.trackNumber,
      totalTracks: totalTracks ?? this.totalTracks,
      discNumber: discNumber ?? this.discNumber,
      totalDiscs: totalDiscs ?? this.totalDiscs,
      duration: duration ?? this.duration,
      releaseDate: releaseDate ?? this.releaseDate,
      quality: quality ?? this.quality,
      bitDepth: bitDepth ?? this.bitDepth,
      sampleRate: sampleRate ?? this.sampleRate,
      bitrate: bitrate ?? this.bitrate,
      format: format ?? this.format,
      genre: genre ?? this.genre,
      composer: composer ?? this.composer,
      label: label ?? this.label,
      copyright: copyright ?? this.copyright,
    );
  }
}

class DownloadHistoryState {
  final List<DownloadHistoryItem> items;
  final int totalCount;
  final int loadedIndexVersion;
  final List<DownloadHistoryItem> _lookupItems;
  final Map<String, DownloadHistoryItem> _bySpotifyId;
  final Map<String, DownloadHistoryItem> _byIsrc;
  final Map<String, DownloadHistoryItem> _byTrackArtistKey;

  DownloadHistoryState({
    this.items = const [],
    this.totalCount = 0,
    this.loadedIndexVersion = 0,
    List<DownloadHistoryItem>? lookupItems,
  }) : _lookupItems = List.unmodifiable(lookupItems ?? items),
       _bySpotifyId = Map.fromEntries(
         (lookupItems ?? items)
             .where(
               (item) => item.spotifyId != null && item.spotifyId!.isNotEmpty,
             )
             .map((item) => MapEntry(item.spotifyId!, item)),
       ),
       _byIsrc = Map.fromEntries(
         (lookupItems ?? items)
             .where((item) => item.isrc != null && item.isrc!.isNotEmpty)
             .map((item) => MapEntry(item.isrc!, item)),
       ),
       _byTrackArtistKey = Map.fromEntries(
         (lookupItems ?? items)
             .map(
               (item) => MapEntry(
                 _trackArtistKey(item.trackName, item.artistName),
                 item,
               ),
             )
             .where((entry) => entry.key.isNotEmpty),
       );

  static String _trackArtistKey(String trackName, String artistName) {
    final normalizedTrack = trackName.trim().toLowerCase();
    if (normalizedTrack.isEmpty) return '';
    final normalizedArtist = artistName.trim().toLowerCase();
    return '$normalizedTrack|$normalizedArtist';
  }

  bool isDownloaded(String spotifyId) => _bySpotifyId.containsKey(spotifyId);

  DownloadHistoryItem? getBySpotifyId(String spotifyId) =>
      _bySpotifyId[spotifyId];

  DownloadHistoryItem? getByIsrc(String isrc) => _byIsrc[isrc];

  DownloadHistoryItem? findByTrackAndArtist(
    String trackName,
    String artistName,
  ) {
    final key = _trackArtistKey(trackName, artistName);
    if (key.isEmpty) return null;
    return _byTrackArtistKey[key];
  }

  List<DownloadHistoryItem> get lookupItems => _lookupItems;

  DownloadHistoryState copyWith({
    List<DownloadHistoryItem>? items,
    int? totalCount,
    int? loadedIndexVersion,
    List<DownloadHistoryItem>? lookupItems,
  }) {
    return DownloadHistoryState(
      items: items ?? this.items,
      totalCount: totalCount ?? this.totalCount,
      loadedIndexVersion: loadedIndexVersion ?? this.loadedIndexVersion,
      lookupItems: lookupItems ?? _lookupItems,
    );
  }
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
  static const _startupAudioCursorKey = 'history_startup_audio_cursor_v1';
  final HistoryDatabase _db = HistoryDatabase.instance;
  bool _isLoaded = false;
  bool _isSafRepairInProgress = false;
  bool _isAudioMetadataBackfillInProgress = false;
  bool _startupMaintenanceScheduled = false;

  @override
  DownloadHistoryState build() {
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

  void _scheduleStartupMaintenance(List<DownloadHistoryItem> initialItems) {
    if (_startupMaintenanceScheduled) {
      return;
    }
    _startupMaintenanceScheduled = true;

    unawaited(
      Future<void>.delayed(_startupMaintenanceDelay, () async {
        try {
          final prefs = await SharedPreferences.getInstance();

          if (Platform.isAndroid) {
            await _repairMissingSafEntries(
              initialItems,
              maxItems: _safRepairMaxPerLaunch,
              prefs: prefs,
            );
            await Future<void>.delayed(_startupMaintenanceStepGap);
          }

          await _cleanupOrphanedDownloadsIncremental(
            maxItems: _orphanCleanupMaxPerLaunch,
            prefs: prefs,
          );
          await Future<void>.delayed(_startupMaintenanceStepGap);

          final currentItems = state.items;
          if (currentItems.isNotEmpty) {
            await _backfillAudioMetadata(
              currentItems,
              maxItems: _audioMetadataBackfillMaxPerLaunch,
              prefs: prefs,
            );
          }
        } catch (e, stack) {
          _historyLog.w('Startup history maintenance failed: $e');
          _historyLog.d('$stack');
        }
      }),
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
      if (item.safRepaired) continue;
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
      await prefs.remove(_startupSafRepairCursorKey);
      _isSafRepairInProgress = false;
      return;
    }

    final startCursor = _readStartupCursor(
      prefs,
      _startupSafRepairCursorKey,
      candidateIndexes.length,
    );
    final endCursor = (startCursor + maxItems).clamp(
      0,
      candidateIndexes.length,
    );
    final selectedIndexes = candidateIndexes.sublist(startCursor, endCursor);

    if (selectedIndexes.isEmpty) {
      await prefs.remove(_startupSafRepairCursorKey);
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
          final resolved = await PlatformBridge.resolveSafFile(
            treeUri: item.downloadTreeUri!,
            relativeDir: item.safRelativeDir ?? '',
            fileName: fallbackName,
          );
          final newUri = (resolved['uri'] as String? ?? '').trim();
          if (newUri.isEmpty) continue;

          final newRelativeDir = resolved['relative_dir'] as String?;
          final updated = item.copyWith(
            filePath: newUri,
            safRelativeDir:
                (newRelativeDir != null && newRelativeDir.isNotEmpty)
                ? newRelativeDir
                : item.safRelativeDir,
            safFileName: fallbackName,
            safRepaired: true,
          );

          updatedItems[i] = updated;
          changed = true;
          repairedCount++;
          persistedUpdates.add(updated.toJson());
        } catch (e) {
          _historyLog.w('Failed to repair SAF URI: $e');
        }

        if ((c + 1) % _safRepairBatchSize == 0) {
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
        _startupSafRepairCursorKey,
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

  Future<Map<String, dynamic>?> _probeAudioMetadata(
    String filePath, {
    String? fallbackQuality,
  }) async {
    if (!_supportsAudioMetadataProbe(filePath)) {
      return null;
    }

    try {
      final result = await PlatformBridge.readFileMetadata(filePath);
      if (result['error'] != null) {
        return null;
      }

      final bitDepth = readPositiveInt(result['bit_depth']);
      final sampleRate = readPositiveInt(result['sample_rate']);
      final detectedFormat = _normalizeAudioFormatValue(
        result['audio_codec']?.toString() ?? result['format']?.toString(),
      );
      final rawBitrateKbps = _readPositiveBitrateKbps(result['bitrate']);
      final bitrateKbps = _isLossyAudioFormat(detectedFormat)
          ? rawBitrateKbps
          : null;
      final quality = _resolveDisplayQuality(
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
      final candidateIndexes = <int>[];
      for (var i = 0; i < items.length; i++) {
        if (_shouldBackfillAudioMetadata(items[i])) {
          candidateIndexes.add(i);
        }
      }

      if (candidateIndexes.isEmpty) {
        await prefs.remove(_startupAudioCursorKey);
        return;
      }

      final startCursor = _readStartupCursor(
        prefs,
        _startupAudioCursorKey,
        candidateIndexes.length,
      );
      final endCursor = (startCursor + maxItems).clamp(
        0,
        candidateIndexes.length,
      );
      final selectedIndexes = candidateIndexes.sublist(startCursor, endCursor);

      if (selectedIndexes.isEmpty) {
        await prefs.remove(_startupAudioCursorKey);
        return;
      }

      List<DownloadHistoryItem>? updatedItems;
      final persistedUpdates = <Map<String, dynamic>>[];
      var refreshedCount = 0;

      for (final index in selectedIndexes) {
        final item = items[index];

        final probed = await _probeAudioMetadata(
          item.filePath,
          fallbackQuality: item.quality,
        );
        if (probed == null) {
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
        _startupAudioCursorKey,
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

  Future<void> reloadFromStorage() async {
    await _loadFromDatabase();
  }

  void _bumpHistoryRevision() {
    state = state.copyWith(loadedIndexVersion: state.loadedIndexVersion + 1);
  }

  Future<DownloadHistoryItem> _putInMemoryHistory(
    DownloadHistoryItem item,
  ) async {
    DownloadHistoryItem? existing;
    if (item.spotifyId != null && item.spotifyId!.isNotEmpty) {
      existing = state.getBySpotifyId(item.spotifyId!);
    }
    if (existing == null && item.isrc != null && item.isrc!.isNotEmpty) {
      existing = state.getByIsrc(item.isrc!);
    }
    if (existing == null) {
      final json = await _db.findExisting(
        spotifyId: item.spotifyId,
        isrc: item.isrc,
      );
      if (json != null) {
        existing = DownloadHistoryItem.fromJson(json);
      }
    }
    if (existing == null) {
      final json = await _db.findByTrackAndArtist(
        item.trackName,
        item.artistName,
      );
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

    if (existing != null) {
      final updatedItems = state.items
          .where((i) => i.id != existing!.id)
          .toList();
      updatedItems.insert(0, mergedItem);
      final updatedLookupItems = state.lookupItems
          .where((i) => i.id != existing!.id)
          .toList(growable: false);
      state = state.copyWith(
        items: updatedItems,
        lookupItems: [mergedItem, ...updatedLookupItems],
      );
      _historyLog.d('Updated existing history entry: ${mergedItem.trackName}');
    } else {
      state = state.copyWith(
        items: [mergedItem, ...state.items],
        totalCount: state.totalCount + 1,
        lookupItems: [mergedItem, ...state.lookupItems],
      );
      _historyLog.d('Added new history entry: ${mergedItem.trackName}');
    }
    return mergedItem;
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

  void addToHistory(DownloadHistoryItem item) {
    unawaited(
      () async {
        final mergedItem = await _putInMemoryHistory(item);
        await _db.upsert(mergedItem.toJson());
        _bumpHistoryRevision();
      }().catchError((Object e, StackTrace stack) {
        _historyLog.e('Failed to save to database: $e', e, stack);
      }),
    );
  }

  void adoptNativeHistoryItem(DownloadHistoryItem item) {
    unawaited(
      () async {
        final mergedItem = await _putInMemoryHistory(item);
        await _db.upsert(mergedItem.toJson());
        _bumpHistoryRevision();
      }().catchError((Object e, StackTrace stack) {
        _historyLog.e('Failed to adopt native history item: $e', e, stack);
      }),
    );
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

  void removeBySpotifyId(String spotifyId) {
    state = state.copyWith(
      items: state.items.where((item) => item.spotifyId != spotifyId).toList(),
      lookupItems: state.lookupItems
          .where((item) => item.spotifyId != spotifyId)
          .toList(growable: false),
    );
    unawaited(
      () async {
        final deleted = await _db.deleteBySpotifyId(spotifyId);
        final totalCount = await _db.getCount();
        state = state.copyWith(totalCount: totalCount);
        _bumpHistoryRevision();
        _historyLog.d('Removed $deleted item(s) with spotifyId: $spotifyId');
      }().catchError((Object e, StackTrace stack) {
        _historyLog.e('Failed to delete from database: $e', e, stack);
      }),
    );
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
    _bumpHistoryRevision();
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
    '.aac',
  ];

  Future<String?> _findConvertedSibling(String originalPath) async {
    final dotIndex = originalPath.lastIndexOf('.');
    if (dotIndex < 0) return null;
    final basePath = originalPath.substring(0, dotIndex);
    final originalExt = originalPath.substring(dotIndex).toLowerCase();

    for (final ext in _audioExtensions) {
      if (ext == originalExt) continue;
      final candidatePath = '$basePath$ext';
      try {
        if (await fileExists(candidatePath)) return candidatePath;
      } catch (_) {}
    }
    return null;
  }

  Future<
    ({
      List<String> orphanedIds,
      Map<String, String> replacementPaths,
      Map<String, String> pathById,
    })
  >
  _inspectOrphanedEntries(List<Map<String, dynamic>> entries) async {
    final orphanedIds = <String>[];
    final replacementPaths = <String, String>{};
    final pathById = <String, String>{};
    const checkChunkSize = 16;

    for (var i = 0; i < entries.length; i += checkChunkSize) {
      final end = (i + checkChunkSize < entries.length)
          ? i + checkChunkSize
          : entries.length;
      final chunk = entries.sublist(i, end);

      final checks = await Future.wait<MapEntry<String, bool>?>(
        chunk.map((entry) async {
          final id = entry['id'] as String;
          final filePath = entry['file_path'] as String?;
          if (filePath == null || filePath.isEmpty) return null;
          pathById[id] = filePath;
          try {
            if (await fileExists(filePath)) return MapEntry(id, true);

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
            return MapEntry(id, false);
          }
        }),
      );

      for (final check in checks) {
        if (check == null || check.value) continue;
        orphanedIds.add(check.key);
        _historyLog.d(
          'Found orphaned entry: ${check.key} (${pathById[check.key] ?? ''})',
        );
      }
    }

    return (
      orphanedIds: orphanedIds,
      replacementPaths: replacementPaths,
      pathById: pathById,
    );
  }

  void _applyHistoryPathAndDeletionChanges({
    required List<String> deletedIds,
    required Map<String, String> replacementPaths,
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
      if (replacementPath != null && replacementPath != item.filePath) {
        updatedItems.add(item.copyWith(filePath: replacementPath));
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
    for (final replacement in result.replacementPaths.entries) {
      await _db.updateFilePath(replacement.key, replacement.value);
    }

    final deletedCount = result.orphanedIds.isEmpty
        ? 0
        : await _db.deleteByIds(result.orphanedIds);

    _applyHistoryPathAndDeletionChanges(
      deletedIds: result.orphanedIds,
      replacementPaths: result.replacementPaths,
    );

    if (entries.length < maxItems) {
      await prefs.remove(_startupOrphanCursorKey);
    } else {
      final nextCursor =
          safeCursor + entries.length - result.orphanedIds.length;
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

      if (entries.length < pageSize) {
        break;
      }
      offset += entries.length - result.orphanedIds.length;
    }

    for (final replacement in replacementPaths.entries) {
      await _db.updateFilePath(replacement.key, replacement.value);
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

  Future<int> getDatabaseCount() async {
    return await _db.getCount();
  }
}

final downloadHistoryProvider =
    NotifierProvider<DownloadHistoryNotifier, DownloadHistoryState>(
      DownloadHistoryNotifier.new,
    );

class DownloadHistoryPageRequest {
  final int limit;
  final int offset;

  const DownloadHistoryPageRequest({this.limit = 100, this.offset = 0});

  @override
  bool operator ==(Object other) =>
      other is DownloadHistoryPageRequest &&
      other.limit == limit &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(limit, offset);
}

final downloadHistoryPageProvider =
    FutureProvider.family<
      List<DownloadHistoryItem>,
      DownloadHistoryPageRequest
    >((ref, request) async {
      ref.watch(
        downloadHistoryProvider.select((state) => state.loadedIndexVersion),
      );
      final rows = await HistoryDatabase.instance.getAll(
        limit: request.limit,
        offset: request.offset,
      );
      return rows.map(DownloadHistoryItem.fromJson).toList(growable: false);
    });

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

final downloadHistoryExistsProvider =
    FutureProvider.family<bool, HistoryLookupRequest>((ref, request) async {
      ref.watch(
        downloadHistoryProvider.select((state) => state.loadedIndexVersion),
      );
      return HistoryDatabase.instance.existsTrack(request);
    });

final downloadHistoryBatchExistsProvider =
    FutureProvider.family<Set<String>, HistoryBatchLookupRequest>((
      ref,
      request,
    ) async {
      ref.watch(
        downloadHistoryProvider.select((state) => state.loadedIndexVersion),
      );
      return HistoryDatabase.instance.existingTrackKeys(request.tracks);
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

final downloadedAlbumTracksProvider =
    FutureProvider.family<
      List<DownloadHistoryItem>,
      DownloadedAlbumTracksRequest
    >((ref, request) async {
      ref.watch(
        downloadHistoryProvider.select((state) => state.loadedIndexVersion),
      );
      final rows = await HistoryDatabase.instance.getAlbumTracks(
        request.albumName,
        request.artistName,
      );
      return rows.map(DownloadHistoryItem.fromJson).toList(growable: false);
    });
