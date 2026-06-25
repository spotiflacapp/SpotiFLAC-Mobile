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
import 'package:spotiflac_android/services/history_database.dart';
import 'package:spotiflac_android/utils/logger.dart' hide log;
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/utils/artist_utils.dart';
import 'package:spotiflac_android/utils/int_utils.dart';
import 'package:spotiflac_android/utils/extension_auth_launcher.dart';

export 'package:spotiflac_android/services/history_database.dart'
    show HistoryLookupRequest, HistoryBatchLookupRequest;

final _log = AppLogger('DownloadQueue');
final _historyLog = AppLogger('DownloadHistory');

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
    return (value ~/ _bytesUiStep) * _bytesUiStep;
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

  @override
  DownloadQueueState build() {
    ref.listen<AppSettings>(settingsProvider, (previous, next) {
      updateSettings(next);
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

  Directory _defaultDocumentsOutputDir(String documentsPath) {
    return Directory('$documentsPath/$_defaultOutputFolderName');
  }

  Directory _defaultAndroidMusicOutputDir(String storageRootPath) {
    return Directory('$storageRootPath/$_defaultAndroidMusicSubpath');
  }

  Future<Directory> _ensureDefaultDocumentsOutputDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final musicDir = _defaultDocumentsOutputDir(dir.path);
    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
    }
    return musicDir;
  }

  Future<Directory?> _ensureDefaultAndroidMusicOutputDir() async {
    final dir = await getExternalStorageDirectory();
    if (dir == null) return null;

    final musicDir = _defaultAndroidMusicOutputDir(
      dir.parent.parent.parent.parent.path,
    );
    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
    }
    return musicDir;
  }

  Future<void> _initOutputDir() async {
    if (state.outputDir.isEmpty) {
      try {
        if (Platform.isIOS) {
          final musicDir = await _ensureDefaultDocumentsOutputDir();
          state = state.copyWith(outputDir: musicDir.path);
        } else {
          final musicDir =
              await _ensureDefaultAndroidMusicOutputDir() ??
              await _ensureDefaultDocumentsOutputDir();
          state = state.copyWith(outputDir: musicDir.path);
        }
      } catch (e) {
        final musicDir = await _ensureDefaultDocumentsOutputDir();
        state = state.copyWith(outputDir: musicDir.path);
      }
    }
  }

  Future<void> _ensureDirExists(String path, {String? label}) async {
    if (_ensuredDirs.contains(path)) return;
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      if (label != null) {
        _log.d('Created $label: $path');
      } else {
        _log.d('Created folder: $path');
      }
    }
    _ensuredDirs.add(path);
  }

  void setOutputDir(String dir) {
    state = state.copyWith(outputDir: dir);
  }

  bool _shouldTreatAsSingleRelease(Track track) {
    if (track.isSingle) {
      return true;
    }

    final normalizedAlbumType = normalizeOptionalString(
      track.albumType,
    )?.toLowerCase();
    if (normalizedAlbumType != null && normalizedAlbumType.isNotEmpty) {
      return false;
    }

    final totalTracks = track.totalTracks;
    if (totalTracks == 1) {
      return true;
    }

    final normalizedAlbumName = normalizeOptionalString(
      track.albumName,
    )?.toLowerCase();
    if (normalizedAlbumName == 'single' || normalizedAlbumName == 'singles') {
      return totalTracks == null || totalTracks <= 2;
    }

    return false;
  }

  Future<String> _buildOutputDir(
    Track track,
    String folderOrganization, {
    bool separateSingles = false,
    String albumFolderStructure = 'artist_album',
    bool createPlaylistFolder = false,
    bool useAlbumArtistForFolders = true,
    bool usePrimaryArtistOnly = false,
    bool filterContributingArtistsInAlbumArtist = false,
    String? playlistName,
  }) async {
    String baseDir = state.outputDir;
    if (createPlaylistFolder &&
        folderOrganization != 'playlist' &&
        playlistName != null &&
        playlistName.isNotEmpty) {
      final playlistFolder = _sanitizeFolderName(playlistName);
      if (playlistFolder.isNotEmpty) {
        baseDir = '$baseDir${Platform.pathSeparator}$playlistFolder';
        await _ensureDirExists(baseDir, label: 'Playlist folder');
      }
    }
    final normalizedAlbumArtist = normalizeOptionalString(track.albumArtist);
    var folderArtist = useAlbumArtistForFolders
        ? normalizedAlbumArtist ?? track.artistName
        : track.artistName;
    if (useAlbumArtistForFolders &&
        filterContributingArtistsInAlbumArtist &&
        normalizedAlbumArtist != null) {
      folderArtist = _extractPrimaryArtist(folderArtist);
    }
    if (usePrimaryArtistOnly) {
      folderArtist = _extractPrimaryArtist(folderArtist);
    }

    if (separateSingles) {
      final isSingle = _shouldTreatAsSingleRelease(track);
      final artistName = _sanitizeFolderName(folderArtist);

      if (albumFolderStructure == 'artist_album_singles') {
        if (isSingle) {
          final singlesPath =
              '$baseDir${Platform.pathSeparator}$artistName${Platform.pathSeparator}Singles';
          await _ensureDirExists(singlesPath, label: 'Artist Singles folder');
          return singlesPath;
        } else {
          final albumName = _sanitizeFolderName(track.albumName);
          final albumPath =
              '$baseDir${Platform.pathSeparator}$artistName${Platform.pathSeparator}$albumName';
          await _ensureDirExists(albumPath, label: 'Artist Album folder');
          return albumPath;
        }
      }

      if (albumFolderStructure == 'artist_album_flat') {
        if (isSingle) {
          final artistPath = '$baseDir${Platform.pathSeparator}$artistName';
          await _ensureDirExists(artistPath, label: 'Artist folder');
          return artistPath;
        } else {
          final albumName = _sanitizeFolderName(track.albumName);
          final albumPath =
              '$baseDir${Platform.pathSeparator}$artistName${Platform.pathSeparator}$albumName';
          await _ensureDirExists(albumPath, label: 'Artist Album folder');
          return albumPath;
        }
      }

      if (isSingle) {
        final singlesPath = '$baseDir${Platform.pathSeparator}Singles';
        await _ensureDirExists(singlesPath, label: 'Singles folder');
        return singlesPath;
      } else {
        final albumName = _sanitizeFolderName(track.albumName);
        final year = _extractYear(track.releaseDate);
        String albumPath;

        switch (albumFolderStructure) {
          case 'album_only':
            albumPath =
                '$baseDir${Platform.pathSeparator}Albums${Platform.pathSeparator}$albumName';
            break;
          case 'artist_year_album':
            final yearAlbum = year != null ? '[$year] $albumName' : albumName;
            albumPath =
                '$baseDir${Platform.pathSeparator}Albums${Platform.pathSeparator}$artistName${Platform.pathSeparator}$yearAlbum';
            break;
          case 'year_album':
            final yearAlbum = year != null ? '[$year] $albumName' : albumName;
            albumPath =
                '$baseDir${Platform.pathSeparator}Albums${Platform.pathSeparator}$yearAlbum';
            break;
          default:
            albumPath =
                '$baseDir${Platform.pathSeparator}Albums${Platform.pathSeparator}$artistName${Platform.pathSeparator}$albumName';
        }

        await _ensureDirExists(albumPath, label: 'Album folder');
        return albumPath;
      }
    }

    if (folderOrganization == 'none') {
      return baseDir;
    }

    String subPath = '';
    switch (folderOrganization) {
      case 'playlist':
        if (playlistName != null && playlistName.isNotEmpty) {
          subPath = _sanitizeFolderName(playlistName);
        }
        break;
      case 'artist':
        final artistName = _sanitizeFolderName(folderArtist);
        subPath = artistName;
        break;
      case 'album':
        final albumName = _sanitizeFolderName(track.albumName);
        subPath = albumName;
        break;
      case 'artist_album':
        final artistName = _sanitizeFolderName(folderArtist);
        final albumName = _sanitizeFolderName(track.albumName);
        subPath = '$artistName${Platform.pathSeparator}$albumName';
        break;
    }

    if (subPath.isNotEmpty) {
      final fullPath = '$baseDir${Platform.pathSeparator}$subPath';
      await _ensureDirExists(fullPath);
      return fullPath;
    }

    return baseDir;
  }

  String _sanitizeFolderName(String name) {
    final buffer = StringBuffer();
    for (final rune in name.runes) {
      if (rune < 0x20 || rune == 0x7f) {
        continue;
      }
      final char = String.fromCharCode(rune);
      if (_invalidFolderChars.hasMatch(char)) {
        buffer.write(' ');
        continue;
      }
      buffer.write(char);
    }

    var sanitized = buffer.toString().trim();
    sanitized = sanitized.replaceAll(_trimDotsAndSpacesRegex, '');
    sanitized = sanitized.replaceAll(_multiWhitespaceRegex, ' ');
    sanitized = sanitized.replaceAll(_multiUnderscoreRegex, '_');
    sanitized = sanitized.replaceAll(_trimUnderscoresAndSpacesRegex, '');

    if (sanitized.isEmpty) {
      return 'Unknown';
    }
    return sanitized;
  }

  String _truncateUtf8Bytes(String value, int maxBytes) {
    if (maxBytes <= 0 || utf8.encode(value).length <= maxBytes) {
      return value;
    }

    final buffer = StringBuffer();
    var usedBytes = 0;
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final charBytes = utf8.encode(char).length;
      if (usedBytes + charBytes > maxBytes) break;
      buffer.write(char);
      usedBytes += charBytes;
    }
    return buffer.toString();
  }

  String _trimSafeName(String value) {
    var trimmed = value.trim();
    trimmed = trimmed.replaceAll(_trimDotsAndSpacesRegex, '');
    trimmed = trimmed.replaceAll(_trimUnderscoresAndSpacesRegex, '');
    return trimmed.isEmpty ? 'Unknown' : trimmed;
  }

  String _sanitizeSafRelativeDir(String relativeDir) {
    if (relativeDir.trim().isEmpty) return '';
    final parts = relativeDir
        .split('/')
        .map(_sanitizeFolderName)
        .map((part) {
          final truncated = _truncateUtf8Bytes(
            part,
            _maxSafDirSegmentUtf8Bytes,
          );
          return _trimSafeName(truncated);
        })
        .where((part) => part.isNotEmpty && part != '.' && part != '..')
        .toList(growable: false);
    return parts.join('/');
  }

  Future<String> _buildSafFileName(String baseName, String outputExt) async {
    final sanitized = await PlatformBridge.sanitizeFilename(baseName);
    final extBytes = utf8.encode(outputExt).length;
    final maxBaseBytes = max(1, _maxSafFilenameUtf8Bytes - extBytes);
    final truncated = _truncateUtf8Bytes(sanitized, maxBaseBytes);
    return '${_trimSafeName(truncated)}$outputExt';
  }

  static final _featuredArtistPattern = RegExp(
    r'\s*[,;]\s*|\s+(?:feat\.?|ft\.?|featuring|with|x)\s+',
    caseSensitive: false,
  );

  String _extractPrimaryArtist(String artist) {
    final match = _featuredArtistPattern.firstMatch(artist);
    if (match != null && match.start > 0) {
      return artist.substring(0, match.start).trim();
    }
    return artist;
  }

  String? _resolveAlbumArtistForMetadata(Track track, AppSettings settings) {
    var albumArtist = normalizeOptionalString(track.albumArtist);
    if (settings.filterContributingArtistsInAlbumArtist) {
      albumArtist = albumArtist == null
          ? null
          : normalizeOptionalString(_extractPrimaryArtist(albumArtist));
    }
    return albumArtist;
  }

  bool _isSafMode(AppSettings settings) {
    return Platform.isAndroid &&
        settings.storageMode == 'saf' &&
        settings.downloadTreeUri.isNotEmpty;
  }

  bool _isSafWriteFailure(Map<String, dynamic> result) {
    final error = (result['error'] ?? result['message'] ?? '')
        .toString()
        .toLowerCase();
    if (error.isEmpty) return false;
    return error.contains('saf') ||
        error.contains('content uri') ||
        error.contains('permission denied') ||
        error.contains('documentfile');
  }

  Future<String> _buildRelativeOutputDir(
    Track track,
    String folderOrganization, {
    bool separateSingles = false,
    String albumFolderStructure = 'artist_album',
    bool createPlaylistFolder = false,
    bool useAlbumArtistForFolders = true,
    bool usePrimaryArtistOnly = false,
    bool filterContributingArtistsInAlbumArtist = false,
    String? playlistName,
  }) async {
    final playlistPrefix =
        createPlaylistFolder &&
            folderOrganization != 'playlist' &&
            playlistName != null &&
            playlistName.isNotEmpty
        ? _sanitizeFolderName(playlistName)
        : '';
    final normalizedAlbumArtist = normalizeOptionalString(track.albumArtist);
    var folderArtist = useAlbumArtistForFolders
        ? normalizedAlbumArtist ?? track.artistName
        : track.artistName;
    if (useAlbumArtistForFolders &&
        filterContributingArtistsInAlbumArtist &&
        normalizedAlbumArtist != null) {
      folderArtist = _extractPrimaryArtist(folderArtist);
    }
    if (usePrimaryArtistOnly) {
      folderArtist = _extractPrimaryArtist(folderArtist);
    }

    if (separateSingles) {
      final isSingle = _shouldTreatAsSingleRelease(track);
      final artistName = _sanitizeFolderName(folderArtist);

      if (albumFolderStructure == 'artist_album_singles') {
        if (isSingle) {
          return _joinRelativePath(playlistPrefix, '$artistName/Singles');
        }
        final albumName = _sanitizeFolderName(track.albumName);
        return _joinRelativePath(playlistPrefix, '$artistName/$albumName');
      }

      if (albumFolderStructure == 'artist_album_flat') {
        if (isSingle) {
          return _joinRelativePath(playlistPrefix, artistName);
        }
        final albumName = _sanitizeFolderName(track.albumName);
        return _joinRelativePath(playlistPrefix, '$artistName/$albumName');
      }

      if (isSingle) {
        return _joinRelativePath(playlistPrefix, 'Singles');
      }

      final albumName = _sanitizeFolderName(track.albumName);
      final year = _extractYear(track.releaseDate);
      switch (albumFolderStructure) {
        case 'album_only':
          return _joinRelativePath(playlistPrefix, 'Albums/$albumName');
        case 'artist_year_album':
          final yearAlbum = year != null ? '[$year] $albumName' : albumName;
          return _joinRelativePath(
            playlistPrefix,
            'Albums/$artistName/$yearAlbum',
          );
        case 'year_album':
          final yearAlbum = year != null ? '[$year] $albumName' : albumName;
          return _joinRelativePath(playlistPrefix, 'Albums/$yearAlbum');
        default:
          return _joinRelativePath(
            playlistPrefix,
            'Albums/$artistName/$albumName',
          );
      }
    }

    if (folderOrganization == 'none') {
      return playlistPrefix;
    }

    switch (folderOrganization) {
      case 'playlist':
        if (playlistName != null && playlistName.isNotEmpty) {
          return _sanitizeFolderName(playlistName);
        }
        return '';
      case 'artist':
        return _joinRelativePath(
          playlistPrefix,
          _sanitizeFolderName(folderArtist),
        );
      case 'album':
        return _joinRelativePath(
          playlistPrefix,
          _sanitizeFolderName(track.albumName),
        );
      case 'artist_album':
        final artistName = _sanitizeFolderName(folderArtist);
        final albumName = _sanitizeFolderName(track.albumName);
        return _joinRelativePath(playlistPrefix, '$artistName/$albumName');
      default:
        return playlistPrefix;
    }
  }

  String _joinRelativePath(String prefix, String suffix) {
    if (prefix.isEmpty) return suffix;
    if (suffix.isEmpty) return prefix;
    return '$prefix/$suffix';
  }

  String? _extensionPreferredOutputExt(String service) {
    final normalizedService = service.trim().toLowerCase();
    if (normalizedService.isEmpty) return null;

    final extensionState = ref.read(extensionProvider);
    for (final ext in extensionState.extensions) {
      if (!ext.enabled || !ext.hasDownloadProvider) continue;
      if (ext.id.toLowerCase() != normalizedService) continue;

      final preferred = ext.preferredDownloadOutputExtension;
      if (preferred == null) return null;

      final normalized = preferred.startsWith('.')
          ? preferred.toLowerCase()
          : '.${preferred.toLowerCase()}';
      if (normalized == '.mp4') {
        return '.m4a';
      }
      const allowed = <String>{'.flac', '.m4a', '.mp3', '.opus'};
      if (allowed.contains(normalized)) {
        return normalized;
      }
      return null;
    }

    return null;
  }

  bool _extensionPreservesNativeOutputExt(String service, String ext) {
    final normalizedService = service.trim().toLowerCase();
    final normalizedExt = ext.trim().toLowerCase();
    if (normalizedService.isEmpty || normalizedExt.isEmpty) return false;

    final extensionState = ref.read(extensionProvider);
    return extensionState.extensions.any(
      (ext) =>
          ext.enabled &&
          ext.hasDownloadProvider &&
          ext.id.toLowerCase() == normalizedService &&
          ext.preservedNativeOutputExtensions.contains(normalizedExt),
    );
  }

  bool _extensionRequiresNativeContainerConversion(String service) {
    final normalizedService = service.trim().toLowerCase();
    if (normalizedService.isEmpty) return false;

    final extensionState = ref.read(extensionProvider);
    return extensionState.extensions.any(
      (ext) =>
          ext.enabled &&
          ext.hasDownloadProvider &&
          (ext.id.toLowerCase() == normalizedService ||
              ext.replacesBuiltInProviders.contains(normalizedService)) &&
          ext.requiresNativeContainerConversion,
    );
  }

  bool _shouldRequestContainerConversion(String service, String outputExt) {
    return outputExt.trim().toLowerCase() == '.flac' &&
        _extensionRequiresNativeContainerConversion(service);
  }

  String _determineOutputExt(String quality, String service) {
    final extensionPreferred = _extensionPreferredOutputExt(service);
    if (extensionPreferred != null) {
      return extensionPreferred;
    }
    if (_downloadProviderReplacesLegacyProvider(service, 'tidal') &&
        quality == 'HIGH') {
      return '.m4a';
    }
    final q = quality.toLowerCase();
    if (q == 'alac' || q.startsWith('aac')) return '.m4a';
    if (q.startsWith('opus')) return '.opus';
    if (q.startsWith('mp3')) return '.mp3';
    return '.flac';
  }

  bool _downloadProviderReplacesLegacyProvider(
    String service,
    String legacyProviderId,
  ) {
    return ref
        .read(extensionProvider.notifier)
        .downloadProviderReplacesLegacyProvider(service, legacyProviderId);
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

  String _mimeTypeForExt(String ext) {
    switch (ext.toLowerCase()) {
      case '.m4a':
      case '.mp4':
        return 'audio/mp4';
      case '.mp3':
        return 'audio/mpeg';
      case '.opus':
        return 'audio/ogg';
      case '.flac':
        return 'audio/flac';
      case '.lrc':
        return 'application/octet-stream';
      default:
        return 'application/octet-stream';
    }
  }

  String? _normalizeAudioExt(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    final normalized = raw.startsWith('.') ? raw : '.$raw';
    const allowed = {'.flac', '.m4a', '.mp4', '.mp3', '.opus', '.ogg', '.aac'};
    return allowed.contains(normalized) ? normalized : null;
  }

  String? _downloadResultOutputExt(
    Map<String, dynamic> result, {
    String? filePath,
  }) {
    final explicit =
        _normalizeAudioExt(result['actual_extension']) ??
        _normalizeAudioExt(result['output_extension']) ??
        _normalizeAudioExt(result['actual_container']) ??
        _normalizeAudioExt(result['container']);
    if (explicit != null) return explicit;

    for (final candidate in <String?>[
      result['file_name'] as String?,
      filePath,
      result['file_path'] as String?,
    ]) {
      if (candidate == null) continue;
      final lower = candidate.trim().toLowerCase();
      for (final ext in const [
        '.flac',
        '.m4a',
        '.mp4',
        '.mp3',
        '.opus',
        '.ogg',
        '.aac',
      ]) {
        if (lower.endsWith(ext)) return ext;
      }
    }
    return null;
  }

  Future<String?> _getSafMimeType(String uri) async {
    try {
      final stat = await PlatformBridge.safStat(uri);
      return stat['mime_type'] as String?;
    } catch (_) {
      return null;
    }
  }

  String? _extractYear(String? releaseDate) {
    if (releaseDate == null || releaseDate.isEmpty) return null;
    final match = _yearRegex.firstMatch(releaseDate);
    return match?.group(1);
  }

  static final _isrcRegex = RegExp(r'^[A-Z]{2}[A-Z0-9]{3}\d{2}\d{5}$');

  bool _isValidISRC(String value) {
    return _isrcRegex.hasMatch(value.toUpperCase());
  }

  /// Returns true if any enabled extension matching [source] or [service]
  /// declares `skipLyrics: true` in its manifest.
  bool _shouldSkipLyrics(
    ExtensionState extensionState,
    String? source,
    String? service,
  ) {
    final candidates = <String>{};
    if (source != null && source.isNotEmpty) {
      candidates.add(source.trim().toLowerCase());
    }
    if (service != null && service.isNotEmpty) {
      candidates.add(service.trim().toLowerCase());
    }
    if (candidates.isEmpty) return false;
    return extensionState.extensions.any(
      (e) =>
          e.enabled && e.skipLyrics && candidates.contains(e.id.toLowerCase()),
    );
  }

  String? _extractKnownDeezerTrackId(Track track) {
    final deezerId = track.deezerId?.trim();
    if (deezerId != null && deezerId.isNotEmpty) {
      return deezerId;
    }

    if (track.id.startsWith('deezer:')) {
      final rawId = track.id.substring('deezer:'.length).trim();
      if (rawId.isNotEmpty) {
        return rawId;
      }
    }

    final availabilityDeezerId = track.availability?.deezerId?.trim();
    if (availabilityDeezerId != null && availabilityDeezerId.isNotEmpty) {
      return availabilityDeezerId;
    }

    return null;
  }

  Future<String?> _searchDeezerTrackIdByIsrc(
    String? isrc, {
    required String lookupContext,
    String? itemId,
  }) async {
    final normalizedIsrc = normalizeOptionalString(isrc);
    if (normalizedIsrc == null || !_isValidISRC(normalizedIsrc)) {
      return null;
    }

    try {
      _log.d('No Deezer ID, searching by $lookupContext: $normalizedIsrc');
      final deezerResult = await PlatformBridge.searchDeezerByISRC(
        normalizedIsrc,
        itemId: itemId,
      );
      if (deezerResult['success'] == true && deezerResult['track_id'] != null) {
        final deezerTrackId = deezerResult['track_id'].toString();
        _log.d('Found Deezer track ID via $lookupContext: $deezerTrackId');
        return deezerTrackId;
      }
    } catch (e) {
      _log.w('Failed to search Deezer by $lookupContext: $e');
    }

    return null;
  }

  Track _copyTrackWithResolvedMetadata(
    Track track, {
    String? resolvedIsrc,
    int? trackNumber,
    int? totalTracks,
    int? discNumber,
    int? totalDiscs,
    String? releaseDate,
    String? deezerId,
    String? composer,
  }) {
    final normalizedIsrc = normalizeOptionalString(resolvedIsrc);
    final normalizedComposer = normalizeOptionalString(composer);

    return Track(
      id: track.id,
      name: track.name,
      artistName: track.artistName,
      albumName: track.albumName,
      albumArtist: track.albumArtist,
      artistId: track.artistId,
      albumId: track.albumId,
      coverUrl: normalizeCoverReference(track.coverUrl),
      duration: track.duration,
      isrc: (normalizedIsrc != null && _isValidISRC(normalizedIsrc))
          ? normalizedIsrc
          : track.isrc,
      trackNumber: (track.trackNumber != null && track.trackNumber! > 0)
          ? track.trackNumber
          : trackNumber,
      discNumber: (track.discNumber != null && track.discNumber! > 0)
          ? track.discNumber
          : discNumber,
      totalDiscs: (track.totalDiscs != null && track.totalDiscs! > 0)
          ? track.totalDiscs
          : totalDiscs,
      releaseDate: track.releaseDate ?? normalizeOptionalString(releaseDate),
      deezerId: deezerId ?? track.deezerId,
      availability: track.availability,
      source: track.source,
      albumType: track.albumType,
      totalTracks: (track.totalTracks != null && track.totalTracks! > 0)
          ? track.totalTracks
          : totalTracks,
      composer: (track.composer != null && track.composer!.isNotEmpty)
          ? track.composer
          : normalizedComposer,
      itemType: track.itemType,
    );
  }

  Future<_DeezerLookupPreparation> _resolveProviderTrackForDeezerLookup(
    Track track,
    String itemId,
  ) async {
    try {
      final colonIdx = track.id.indexOf(':');
      final provider = track.id.substring(0, colonIdx);
      final effectiveProvider = resolveEffectiveMetadataProvider(
        provider,
        ref.read(extensionProvider),
      );
      final providerTrackId = track.id.substring(colonIdx + 1);

      _log.d(
        'No ISRC, fetching from ${effectiveProvider.isEmpty ? provider : effectiveProvider} API: $providerTrackId',
      );
      final providerData = await PlatformBridge.getProviderMetadata(
        effectiveProvider.isEmpty ? provider : effectiveProvider,
        'track',
        providerTrackId,
      );

      final trackData = providerData['track'] as Map<String, dynamic>?;
      if (trackData == null) {
        return _DeezerLookupPreparation(
          track: track,
          deezerTrackId: _extractKnownDeezerTrackId(track),
        );
      }

      final resolvedIsrc = normalizeOptionalString(
        trackData['isrc'] as String?,
      );
      if (resolvedIsrc == null || !_isValidISRC(resolvedIsrc)) {
        return _DeezerLookupPreparation(
          track: track,
          deezerTrackId: _extractKnownDeezerTrackId(track),
        );
      }

      _log.d(
        'Resolved ISRC from ${effectiveProvider.isEmpty ? provider : effectiveProvider}: $resolvedIsrc',
      );

      final updatedTrack = _copyTrackWithResolvedMetadata(
        track,
        resolvedIsrc: resolvedIsrc,
        releaseDate: trackData['release_date'] as String?,
        trackNumber: trackData['track_number'] as int?,
        totalTracks: trackData['total_tracks'] as int?,
        discNumber: trackData['disc_number'] as int?,
        totalDiscs: trackData['total_discs'] as int?,
        composer: trackData['composer'] as String?,
      );
      final deezerTrackId = await _searchDeezerTrackIdByIsrc(
        resolvedIsrc,
        lookupContext:
            '${effectiveProvider.isEmpty ? provider : effectiveProvider} ISRC',
        itemId: itemId,
      );

      return _DeezerLookupPreparation(
        track: deezerTrackId == null
            ? updatedTrack
            : _copyTrackWithResolvedMetadata(
                updatedTrack,
                deezerId: deezerTrackId,
              ),
        deezerTrackId:
            deezerTrackId ?? _extractKnownDeezerTrackId(updatedTrack),
      );
    } catch (e) {
      _log.w('Failed to resolve ISRC from provider: $e');
      return _DeezerLookupPreparation(
        track: track,
        deezerTrackId: _extractKnownDeezerTrackId(track),
      );
    }
  }

  Future<_DeezerLookupPreparation> _resolveSpotifyTrackViaDeezer(
    Track track,
  ) async {
    try {
      var spotifyId = track.id;
      if (spotifyId.startsWith('spotify:track:')) {
        spotifyId = spotifyId.split(':').last;
      }
      _log.d('No Deezer ID, converting from Spotify via SongLink: $spotifyId');

      final deezerData = await PlatformBridge.convertSpotifyToDeezer(
        'track',
        spotifyId,
      );
      final trackData = deezerData['track'];

      String? deezerTrackId;
      if (trackData is Map<String, dynamic>) {
        final rawId = trackData['spotify_id'] as String?;
        if (rawId != null && rawId.startsWith('deezer:')) {
          deezerTrackId = rawId.split(':')[1];
          _log.d('Found Deezer track ID via SongLink: $deezerTrackId');
        } else if (deezerData['id'] != null) {
          deezerTrackId = deezerData['id'].toString();
          _log.d('Found Deezer track ID via SongLink (legacy): $deezerTrackId');
        }

        final deezerIsrc = normalizeOptionalString(
          trackData['isrc'] as String?,
        );
        final needsEnrich =
            (track.releaseDate == null &&
                normalizeOptionalString(trackData['release_date'] as String?) !=
                    null) ||
            (track.isrc == null && deezerIsrc != null) ||
            (!_isValidISRC(track.isrc ?? '') && deezerIsrc != null) ||
            ((track.trackNumber == null || track.trackNumber! <= 0) &&
                (trackData['track_number'] as int?) != null &&
                (trackData['track_number'] as int?)! > 0) ||
            ((track.totalTracks == null || track.totalTracks! <= 0) &&
                (trackData['total_tracks'] as int?) != null &&
                (trackData['total_tracks'] as int?)! > 0) ||
            ((track.discNumber == null || track.discNumber! <= 0) &&
                (trackData['disc_number'] as int?) != null &&
                (trackData['disc_number'] as int?)! > 0) ||
            ((track.totalDiscs == null || track.totalDiscs! <= 0) &&
                (trackData['total_discs'] as int?) != null &&
                (trackData['total_discs'] as int?)! > 0) ||
            ((track.composer == null || track.composer!.isEmpty) &&
                normalizeOptionalString(trackData['composer'] as String?) !=
                    null) ||
            deezerTrackId != null;

        final updatedTrack = needsEnrich
            ? _copyTrackWithResolvedMetadata(
                track,
                resolvedIsrc: deezerIsrc,
                releaseDate: trackData['release_date'] as String?,
                trackNumber: trackData['track_number'] as int?,
                totalTracks: trackData['total_tracks'] as int?,
                discNumber: trackData['disc_number'] as int?,
                totalDiscs: trackData['total_discs'] as int?,
                composer: trackData['composer'] as String?,
                deezerId: deezerTrackId,
              )
            : track;

        if (needsEnrich) {
          _log.d(
            'Enriched track from Deezer - date: ${updatedTrack.releaseDate}, ISRC: ${updatedTrack.isrc}, track: ${updatedTrack.trackNumber}, disc: ${updatedTrack.discNumber}',
          );
        }

        return _DeezerLookupPreparation(
          track: updatedTrack,
          deezerTrackId:
              deezerTrackId ?? _extractKnownDeezerTrackId(updatedTrack),
        );
      }

      if (deezerData['id'] != null) {
        deezerTrackId = deezerData['id'].toString();
        _log.d('Found Deezer track ID via SongLink (flat): $deezerTrackId');
        return _DeezerLookupPreparation(
          track: _copyTrackWithResolvedMetadata(track, deezerId: deezerTrackId),
          deezerTrackId: deezerTrackId,
        );
      }
    } catch (e) {
      _log.w('Failed to convert Spotify to Deezer via SongLink: $e');
    }

    return _DeezerLookupPreparation(
      track: track,
      deezerTrackId: _extractKnownDeezerTrackId(track),
    );
  }

  Future<_DeezerExtendedMetadataFields> _loadDeezerExtendedMetadata(
    String deezerTrackId,
  ) async {
    try {
      final extendedMetadata = await PlatformBridge.getDeezerExtendedMetadata(
        deezerTrackId,
      );
      if (extendedMetadata == null) {
        return const _DeezerExtendedMetadataFields();
      }

      final metadata = _DeezerExtendedMetadataFields(
        genre: normalizeOptionalString(extendedMetadata['genre']),
        label: normalizeOptionalString(extendedMetadata['label']),
        copyright: normalizeOptionalString(extendedMetadata['copyright']),
      );
      if (metadata.hasAnyValue) {
        _log.d(
          'Extended metadata - Genre: ${metadata.genre}, Label: ${metadata.label}, Copyright: ${metadata.copyright}',
        );
      }
      return metadata;
    } catch (e) {
      _log.w('Failed to fetch extended metadata from Deezer: $e');
      return const _DeezerExtendedMetadataFields();
    }
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
        .toSet();
    if (failedIds.isEmpty) {
      _log.d('retryAllFailed: no failed downloads to retry');
      return;
    }

    _log.i('Retrying ${failedIds.length} failed download(s)');
    _locallyCancelledItemIds.removeAll(failedIds);
    _pausePendingItemIds.removeAll(failedIds);

    for (final item in state.items) {
      if (!failedIds.contains(item.id)) continue;
      final rgKey = _albumRgKey(item.track);
      final rgAcc = _albumRgData[rgKey];
      if (rgAcc == null) continue;
      rgAcc.entries.removeWhere((entry) => entry.trackId == item.track.id);
      if (rgAcc.entries.isEmpty) {
        _albumRgData.remove(rgKey);
      }
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

  String _albumRgKey(Track track) {
    if (track.albumId != null && track.albumId!.isNotEmpty) {
      return 'id:${track.albumId}';
    }
    return 'name:${track.albumName}|${track.albumArtist ?? ''}';
  }

  /// Store a track's ReplayGain scan result for later album gain computation.
  void _storeTrackReplayGainForAlbum(
    Track track,
    String filePath,
    ReplayGainResult rg,
  ) {
    final key = _albumRgKey(track);
    _albumRgData.putIfAbsent(key, () => _AlbumRgAccumulator());
    // Remove any stale entry for this track (e.g. from a previous failed
    // attempt that was retried).  Without this, the same track can accumulate
    // multiple entries and bias the album loudness calculation.
    _albumRgData[key]!.entries.removeWhere((e) => e.trackId == track.id);
    _albumRgData[key]!.entries.add(
      _AlbumRgTrackEntry(
        filePath: filePath,
        trackId: track.id,
        integratedLufs: rg.integratedLufs,
        truePeakLinear: rg.truePeakLinear,
        durationSecs: track.duration.toDouble(),
      ),
    );
  }

  /// Replace the temp path stored in the accumulator with the final output
  /// path.  For SAF downloads the embed happens on a temp file which is later
  /// deleted — this ensures the album-gain writer targets the real file.
  void _updateAlbumRgFilePath(Track track, String finalPath) {
    final key = _albumRgKey(track);
    final accumulator = _albumRgData[key];
    if (accumulator == null) return;
    for (final entry in accumulator.entries) {
      if (entry.trackId == track.id) {
        entry.filePath = finalPath;
        break;
      }
    }
  }

  /// After a track completes, check whether all tracks from the same album
  /// in the current queue are done.  If so, compute album gain and write it
  /// to every track's file.
  Future<void> _checkAndWriteAlbumReplayGain(Track track) async {
    final settings = ref.read(settingsProvider);
    if (!settings.embedReplayGain) return;

    final key = _albumRgKey(track);
    final accumulator = _albumRgData[key];
    if (accumulator == null || accumulator.entries.isEmpty) return;

    // Find queue items for this album that are STILL in the queue.
    // Completed tracks may have already been removed by removeItem(), so
    // their absence means they finished successfully (not that they're
    // still pending).
    final albumItemsInQueue = state.items
        .where((item) => _albumRgKey(item.track) == key)
        .toList();

    // If any item is still in-flight, the album isn't complete yet.
    final pending = albumItemsInQueue.where(
      (item) =>
          item.status == DownloadStatus.queued ||
          item.status == DownloadStatus.downloading ||
          item.status == DownloadStatus.finalizing,
    );
    if (pending.isNotEmpty) return; // still in progress

    // If any item is failed/skipped, the user might retry it later.
    // Don't finalize album RG with partial data — wait until all album
    // tracks are either completed (and possibly removed) or retried.
    final retryable = albumItemsInQueue.where(
      (item) =>
          item.status == DownloadStatus.failed ||
          item.status == DownloadStatus.skipped,
    );
    if (retryable.isNotEmpty) return; // still retryable

    // The accumulator entries represent successfully scanned tracks.  Entries
    // are only added after a successful ReplayGain scan, removed on retry or
    // when a non-completed item is removed from the queue, so every entry
    // here corresponds to a track that completed (or is about to complete)
    // its download.
    final validEntries = accumulator.entries.toList();

    // Single-track albums: album gain == track gain, no extra write needed.
    if (validEntries.length <= 1) {
      _albumRgData.remove(key);
      return;
    }

    // Compute album gain using duration-weighted power-mean of LUFS values.
    // album_loudness = 10 * log10( Σ(10^(Li/10) * di) / Σ(di) )
    // This weights longer tracks more, matching "whole program" loudness.
    double sumWeightedPower = 0;
    double sumDuration = 0;
    double maxPeak = 0;
    for (final entry in validEntries) {
      final weight = entry.durationSecs > 0 ? entry.durationSecs : 1.0;
      sumWeightedPower += pow(10, entry.integratedLufs / 10.0) * weight;
      sumDuration += weight;
      if (entry.truePeakLinear > maxPeak) {
        maxPeak = entry.truePeakLinear;
      }
    }
    final albumLufs = 10.0 * _log10(sumWeightedPower / sumDuration);
    const replayGainReferenceLufs = -18.0;
    final albumGainDb = replayGainReferenceLufs - albumLufs;

    final albumGain =
        '${albumGainDb >= 0 ? "+" : ""}${albumGainDb.toStringAsFixed(2)} dB';
    final albumPeak = maxPeak.toStringAsFixed(6);

    _log.i(
      'Album ReplayGain for "$key": gain=$albumGain, peak=$albumPeak (${validEntries.length} tracks, album LUFS=${albumLufs.toStringAsFixed(1)})',
    );

    for (final entry in validEntries) {
      try {
        await _writeAlbumReplayGain(entry.filePath, albumGain, albumPeak);
      } catch (e) {
        _log.w('Failed to write album ReplayGain to ${entry.filePath}: $e');
      }
    }

    _albumRgData.remove(key);
  }

  /// Write album ReplayGain tags to a single file.
  Future<void> _writeAlbumReplayGain(
    String filePath,
    String albumGain,
    String albumPeak,
  ) async {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.flac') ||
        lower.endsWith('.ape') ||
        lower.endsWith('.wv') ||
        lower.endsWith('.mpc')) {
      // Native writer — only touches the provided fields, preserves the rest.
      await PlatformBridge.editFileMetadata(filePath, {
        'replaygain_album_gain': albumGain,
        'replaygain_album_peak': albumPeak,
      });
    } else if (isContentUri(filePath)) {
      // SAF content:// URI — FFmpeg can read it but can't write back directly.
      // Get the temp output from FFmpeg, then copy it to the SAF URI.
      String? tempPath;
      final ok = await FFmpegService.writeAlbumReplayGainTags(
        filePath,
        albumGain,
        albumPeak,
        returnTempPath: true,
        onTempReady: (path) => tempPath = path,
      );
      if (ok && tempPath != null) {
        try {
          final safOk = await PlatformBridge.writeTempToSaf(
            tempPath!,
            filePath,
          );
          if (!safOk) {
            _log.w('SAF write-back failed for album RG: $filePath');
          }
        } finally {
          try {
            final tmp = File(tempPath!);
            if (await tmp.exists()) await tmp.delete();
          } catch (_) {}
        }
      } else {
        _log.w('FFmpeg album ReplayGain write failed for SAF: $filePath');
      }
    } else {
      // Local MP3 / Opus — use FFmpeg copy-with-metadata approach.
      final ok = await FFmpegService.writeAlbumReplayGainTags(
        filePath,
        albumGain,
        albumPeak,
      );
      if (!ok) {
        _log.w('FFmpeg album ReplayGain write failed for: $filePath');
      }
    }
  }

  /// Re-check album ReplayGain for all albums that still have accumulator data.
  /// Called after removing/dismissing a failed or skipped item, which may
  /// unblock an album that was waiting for retryable items to be resolved.
  void _retriggerAlbumRgChecks() {
    if (_albumRgData.isEmpty) return;
    final settings = ref.read(settingsProvider);
    if (!settings.embedReplayGain) return;

    // Snapshot the keys — _checkAndWriteAlbumReplayGain may mutate the map.
    final keys = _albumRgData.keys.toList();
    for (final key in keys) {
      final acc = _albumRgData[key];
      if (acc == null || acc.entries.isEmpty) continue;
      // Use the first entry's trackId to find a representative track.
      // _checkAndWriteAlbumReplayGain only needs it for _albumRgKey(), so any
      // track from the album works.
      final albumItems = state.items
          .where((item) => _albumRgKey(item.track) == key)
          .toList();
      // If there are no items left in queue for this album but we have
      // accumulator data, all items were completed and removed.  Use a
      // synthetic call — we need a Track to call the check, but the items
      // are gone.  For this case, directly check conditions inline.
      if (albumItems.isEmpty) {
        // All items removed → no pending/retryable.  Trigger computation.
        if (acc.entries.length > 1) {
          _computeAndWriteAlbumRg(key, acc);
        }
        continue;
      }
      // If any representative item is available, use its track.
      final representative = albumItems.first;
      _checkAndWriteAlbumReplayGain(representative.track);
    }
  }

  /// Compute album RG and write it — extracted from _checkAndWriteAlbumReplayGain
  /// for use when no queue items remain (all completed and removed).
  Future<void> _computeAndWriteAlbumRg(
    String key,
    _AlbumRgAccumulator accumulator,
  ) async {
    final validEntries = accumulator.entries.toList();
    if (validEntries.length <= 1) {
      _albumRgData.remove(key);
      return;
    }

    double sumWeightedPower = 0;
    double sumDuration = 0;
    double maxPeak = 0;
    for (final entry in validEntries) {
      final weight = entry.durationSecs > 0 ? entry.durationSecs : 1.0;
      sumWeightedPower += pow(10, entry.integratedLufs / 10.0) * weight;
      sumDuration += weight;
      if (entry.truePeakLinear > maxPeak) {
        maxPeak = entry.truePeakLinear;
      }
    }
    final albumLufs = 10.0 * _log10(sumWeightedPower / sumDuration);
    const replayGainReferenceLufs = -18.0;
    final albumGainDb = replayGainReferenceLufs - albumLufs;

    final albumGain =
        '${albumGainDb >= 0 ? "+" : ""}${albumGainDb.toStringAsFixed(2)} dB';
    final albumPeak = maxPeak.toStringAsFixed(6);

    _log.i(
      'Album ReplayGain for "$key": gain=$albumGain, peak=$albumPeak (${validEntries.length} tracks, album LUFS=${albumLufs.toStringAsFixed(1)})',
    );

    for (final entry in validEntries) {
      try {
        await _writeAlbumReplayGain(entry.filePath, albumGain, albumPeak);
      } catch (e) {
        _log.w('Failed to write album ReplayGain to ${entry.filePath}: $e');
      }
    }

    _albumRgData.remove(key);
  }

  /// Deezer CDN cover size pattern: /WxH-0-0-0-0.jpg
  static final _deezerSizeRegex = RegExp(r'/(\d+)x(\d+)-\d+-\d+-\d+-\d+\.jpg$');

  String _upgradeToMaxQualityCover(String coverUrl) {
    const spotifySize300 = 'ab67616d00001e02';
    const spotifySize640 = 'ab67616d0000b273';
    const spotifySizeMax = 'ab67616d000082c1';

    var result = coverUrl;
    if (result.contains(spotifySize300)) {
      result = result.replaceFirst(spotifySize300, spotifySize640);
    }
    if (result.contains(spotifySize640)) {
      result = result.replaceFirst(spotifySize640, spotifySizeMax);
    }

    if (result.contains('cdn-images.dzcdn.net')) {
      final upgraded = result.replaceFirst(
        _deezerSizeRegex,
        '/1800x1800-000000-80-0-0.jpg',
      );
      if (upgraded != result) {
        _log.d('Cover URL upgraded (Deezer): 1800x1800');
        result = upgraded;
      }
    }

    // Tidal CDN upgrade (1280x1280 → origin)
    if (result.contains('resources.tidal.com') &&
        result.contains('/1280x1280.jpg')) {
      result = result.replaceFirst('/1280x1280.jpg', '/origin.jpg');
      _log.d('Cover URL upgraded (Tidal): origin');
    }

    return result;
  }

  int? _parsePositiveInt(dynamic value) {
    if (value is int && value > 0) return value;
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  bool _isUsableIndex(int? number, int? total) {
    if (number == null || number <= 0) return false;
    return total == null || total <= 0 || number <= total;
  }

  int? _resolvePositiveMetadataInt(int? sourceValue, int? backendValue) {
    if (sourceValue != null && sourceValue > 0) return sourceValue;
    return backendValue;
  }

  int? _resolveMetadataIndex({
    required int? sourceValue,
    required int? backendValue,
    required int? total,
  }) {
    if (_isUsableIndex(sourceValue, total)) return sourceValue;
    if (_isUsableIndex(backendValue, total)) return backendValue;
    return sourceValue != null && sourceValue > 0 ? sourceValue : backendValue;
  }

  String? _resolveMetadataText(String? sourceValue, String? backendValue) {
    return normalizeOptionalString(sourceValue) ??
        normalizeOptionalString(backendValue);
  }

  Track _buildTrackForMetadataEmbedding(
    Track baseTrack,
    Map<String, dynamic> backendResult,
    String? resolvedAlbumArtist,
  ) {
    final backendTrackNum = _parsePositiveInt(backendResult['track_number']);
    final backendDiscNum = _parsePositiveInt(backendResult['disc_number']);
    final backendTotalTracks = _parsePositiveInt(backendResult['total_tracks']);
    final backendTotalDiscs = _parsePositiveInt(backendResult['total_discs']);
    final backendYear = normalizeOptionalString(
      backendResult['release_date'] as String?,
    );
    final backendAlbum = normalizeOptionalString(
      backendResult['album'] as String?,
    );
    final backendIsrc = normalizeOptionalString(
      backendResult['isrc'] as String?,
    );
    final backendCoverUrl = normalizeCoverReference(
      backendResult['cover_url']?.toString(),
    );
    final baseCoverUrl = normalizeCoverReference(baseTrack.coverUrl);
    final resolvedCoverUrl = baseCoverUrl ?? backendCoverUrl;
    final backendAlbumArtist = normalizeOptionalString(
      backendResult['album_artist'] as String?,
    );
    final backendComposer = normalizeOptionalString(
      backendResult['composer']?.toString(),
    );
    final sourceAlbumName = normalizeOptionalString(baseTrack.albumName);
    final sourceAlbumArtist = normalizeOptionalString(baseTrack.albumArtist);
    final sourceIsrc = normalizeOptionalString(baseTrack.isrc);
    final sourceReleaseDate = normalizeOptionalString(baseTrack.releaseDate);
    final sourceComposer = normalizeOptionalString(baseTrack.composer);
    final resolvedTotalTracks = _resolvePositiveMetadataInt(
      baseTrack.totalTracks,
      backendTotalTracks,
    );
    final resolvedTotalDiscs = _resolvePositiveMetadataInt(
      baseTrack.totalDiscs,
      backendTotalDiscs,
    );
    final resolvedTrackNumber = _resolveMetadataIndex(
      sourceValue: baseTrack.trackNumber,
      backendValue: backendTrackNum,
      total: resolvedTotalTracks,
    );
    final resolvedDiscNumber = _resolveMetadataIndex(
      sourceValue: baseTrack.discNumber,
      backendValue: backendDiscNum,
      total: resolvedTotalDiscs,
    );

    final hasOverrides =
        resolvedTrackNumber != baseTrack.trackNumber ||
        resolvedDiscNumber != baseTrack.discNumber ||
        resolvedTotalTracks != baseTrack.totalTracks ||
        resolvedTotalDiscs != baseTrack.totalDiscs ||
        resolvedAlbumArtist != sourceAlbumArtist ||
        (sourceReleaseDate == null && backendYear != null) ||
        (sourceAlbumName == null && backendAlbum != null) ||
        (sourceIsrc == null && backendIsrc != null) ||
        (baseCoverUrl == null && backendCoverUrl != null) ||
        (sourceAlbumArtist == null &&
            resolvedAlbumArtist == null &&
            backendAlbumArtist != null) ||
        (sourceComposer == null && backendComposer != null);

    if (!hasOverrides) {
      return baseTrack;
    }

    return Track(
      id: baseTrack.id,
      name: baseTrack.name,
      artistName: baseTrack.artistName,
      albumName: sourceAlbumName ?? backendAlbum ?? baseTrack.albumName,
      albumArtist:
          resolvedAlbumArtist ?? sourceAlbumArtist ?? backendAlbumArtist,
      artistId: baseTrack.artistId,
      albumId: baseTrack.albumId,
      coverUrl: resolvedCoverUrl,
      duration: baseTrack.duration,
      isrc: sourceIsrc ?? backendIsrc,
      trackNumber: resolvedTrackNumber,
      discNumber: resolvedDiscNumber,
      totalDiscs: resolvedTotalDiscs,
      releaseDate: sourceReleaseDate ?? backendYear,
      deezerId: baseTrack.deezerId,
      availability: baseTrack.availability,
      albumType: baseTrack.albumType,
      totalTracks: resolvedTotalTracks,
      composer: sourceComposer ?? backendComposer,
      source: baseTrack.source,
    );
  }

  /// Unified metadata, cover, lyrics, and ReplayGain embedding for all formats.
  ///
  /// [format] must be one of `'flac'`, `'m4a'`, `'mp3'`, or `'opus'`.
  /// [writeExternalLrc] only applies to FLAC and M4A (non-SAF paths handle LRC separately).
  Future<void> _embedMetadataToFile(
    String filePath,
    Track track, {
    required String format,
    String? genre,
    String? label,
    String? copyright,
    String? downloadService,
    bool writeExternalLrc = true,
  }) async {
    final settings = ref.read(settingsProvider);
    if (!settings.embedMetadata) {
      _log.d(
        'Metadata embedding disabled, skipping $format metadata/cover embed',
      );
      return;
    }

    final isFlac = format == 'flac';
    final isM4a = format == 'm4a';
    final isMp3 = format == 'mp3';

    String? coverPath;
    var coverUrl = normalizeRemoteHttpUrl(track.coverUrl);
    if (coverUrl != null && coverUrl.isNotEmpty) {
      try {
        if (settings.maxQualityCover) {
          coverUrl = _upgradeToMaxQualityCover(coverUrl);
          _log.d('Cover URL upgraded to max quality for $format: $coverUrl');
        }

        final tempDir = await getTemporaryDirectory();
        final uniqueId =
            '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
        coverPath = '${tempDir.path}/cover_${format}_$uniqueId.jpg';

        final httpClient = HttpClient();
        final request = await httpClient.getUrl(Uri.parse(coverUrl));
        final response = await request.close();
        if (response.statusCode == 200) {
          final file = File(coverPath);
          final sink = file.openWrite();
          await response.pipe(sink);
          await sink.close();
          _log.d('Cover downloaded for $format: $coverPath');
        } else {
          _log.w(
            'Failed to download cover for $format: HTTP ${response.statusCode}',
          );
          coverPath = null;
        }
        httpClient.close();
      } catch (e) {
        _log.e('Failed to download cover for $format: $e');
        coverPath = null;
      }
    }

    try {
      final metadata = <String, String>{
        'TITLE': track.name,
        'ARTIST': track.artistName,
        'ALBUM': track.albumName,
      };
      String formatIndexTag(int number, int? total) {
        if (total != null && total > 0) {
          return '$number/$total';
        }
        return number.toString();
      }

      final albumArtist = _resolveAlbumArtistForMetadata(track, settings);
      if (albumArtist != null) {
        metadata['ALBUMARTIST'] = albumArtist;
      }

      if (track.trackNumber != null && track.trackNumber! > 0) {
        final trackTag = formatIndexTag(track.trackNumber!, track.totalTracks);
        metadata['TRACKNUMBER'] = trackTag;
        if (isFlac || isMp3) metadata['TRACK'] = trackTag;
      }
      if (track.discNumber != null && track.discNumber! > 0) {
        final discTag = formatIndexTag(track.discNumber!, track.totalDiscs);
        metadata['DISCNUMBER'] = discTag;
        if (isFlac || isMp3) metadata['DISC'] = discTag;
      }
      if (track.releaseDate != null) {
        metadata['DATE'] = track.releaseDate!;
        if (isFlac || isMp3) {
          metadata['YEAR'] = track.releaseDate!.split('-').first;
        }
      }
      if (track.isrc != null) metadata['ISRC'] = track.isrc!;
      if (genre != null && genre.isNotEmpty) metadata['GENRE'] = genre;
      if (label != null && label.isNotEmpty) metadata['ORGANIZATION'] = label;
      if (copyright != null && copyright.isNotEmpty) {
        metadata['COPYRIGHT'] = copyright;
      }
      if (track.composer != null && track.composer!.isNotEmpty) {
        metadata['COMPOSER'] = track.composer!;
      }

      final lyricsMode = settings.lyricsMode;
      final extensionState = ref.read(extensionProvider);
      final skipLyrics = _shouldSkipLyrics(
        extensionState,
        track.source,
        downloadService,
      );
      final shouldEmbedLyrics =
          settings.embedLyrics &&
          !skipLyrics &&
          (lyricsMode == 'embed' || lyricsMode == 'both');
      final shouldSaveExternalLyrics =
          settings.embedLyrics &&
          !skipLyrics &&
          (lyricsMode == 'external' || lyricsMode == 'both');
      String? lrcContent;

      if (shouldEmbedLyrics || shouldSaveExternalLyrics) {
        try {
          final fetchedLrc = await PlatformBridge.getLyricsLRC(
            track.id,
            track.name,
            track.artistName,
            filePath: '',
            durationMs: track.duration * 1000,
          );
          if (fetchedLrc.isNotEmpty && fetchedLrc != '[instrumental:true]') {
            lrcContent = fetchedLrc;
            _log.d('Lyrics fetched for $format (${fetchedLrc.length} chars)');
          } else if (fetchedLrc == '[instrumental:true]') {
            _log.d('Track is instrumental, skipping lyrics handling');
          }
        } catch (e) {
          _log.w('Failed to fetch lyrics for $format: $e');
        }
      }

      if (shouldEmbedLyrics && lrcContent != null) {
        metadata['LYRICS'] = lrcContent;
        if (isFlac || isMp3) metadata['UNSYNCEDLYRICS'] = lrcContent;
      } else if ((isFlac || isM4a) && !shouldEmbedLyrics) {
        metadata['LYRICS'] = '';
        if (isFlac) {
          metadata['UNSYNCEDLYRICS'] = '';
        }
      }

      if (writeExternalLrc && shouldSaveExternalLyrics && lrcContent != null) {
        try {
          final lrcPath = filePath.replaceAll(RegExp(r'\.[^.]+$'), '.lrc');
          final safeLrcPath = lrcPath == filePath ? '$filePath.lrc' : lrcPath;
          await File(safeLrcPath).writeAsString(lrcContent);
          _log.d('External LRC file saved: $safeLrcPath');
        } catch (e) {
          _log.w('Failed to save external LRC file for $format: $e');
        }
      }

      ReplayGainResult? scannedReplayGain;

      if (settings.embedReplayGain && !isFlac) {
        try {
          final rgResult = await FFmpegService.scanReplayGain(filePath);
          if (rgResult != null) {
            scannedReplayGain = rgResult;
            metadata['REPLAYGAIN_TRACK_GAIN'] = rgResult.trackGain;
            metadata['REPLAYGAIN_TRACK_PEAK'] = rgResult.trackPeak;
            if (format == 'opus') {
              final r128 = FFmpegService.replayGainDbToR128(rgResult.trackGain);
              if (r128 != null) metadata['R128_TRACK_GAIN'] = r128;
            }
            _log.d(
              'ReplayGain for $format: gain=${rgResult.trackGain}, peak=${rgResult.trackPeak}',
            );
            _storeTrackReplayGainForAlbum(track, filePath, rgResult);
          }
        } catch (e) {
          _log.w('Failed to scan ReplayGain for $format: $e');
        }
      }

      final validCover = coverPath != null && await File(coverPath).exists()
          ? coverPath
          : null;

      // AC-4 is passthrough-only: the FFmpeg mov muxer would re-wrap it as
      // QuickTime and break the ISO MP4 from decryption. writeAC4Metadata is a
      // no-op for non-AC-4 files, so other m4a downloads fall through to FFmpeg.
      if (isM4a) {
        try {
          final ac4Meta = <String, String>{
            'title': track.name,
            'artist': track.artistName,
            'album': track.albumName,
            'albumArtist': ?albumArtist,
            if (track.releaseDate != null) 'date': track.releaseDate!,
            if (genre != null && genre.isNotEmpty) 'genre': genre,
            if (track.composer != null && track.composer!.isNotEmpty)
              'composer': track.composer!,
            if (track.trackNumber != null && track.trackNumber! > 0)
              'trackNumber': track.trackNumber!.toString(),
            if (track.totalTracks != null && track.totalTracks! > 0)
              'totalTracks': track.totalTracks!.toString(),
            if (track.discNumber != null && track.discNumber! > 0)
              'discNumber': track.discNumber!.toString(),
            if (track.totalDiscs != null && track.totalDiscs! > 0)
              'totalDiscs': track.totalDiscs!.toString(),
            if (track.isrc != null) 'isrc': track.isrc!,
            if (label != null && label.isNotEmpty) 'label': label,
            if (copyright != null && copyright.isNotEmpty)
              'copyright': copyright,
            if (shouldEmbedLyrics) 'lyrics': ?lrcContent,
          };
          final ac4Result = await PlatformBridge.writeAC4Metadata(
            filePath,
            ac4Meta,
            validCover ?? '',
          );
          if (ac4Result['handled'] == true) {
            _log.d('AC-4 metadata embedded natively for $format');
            return;
          }
        } catch (e) {
          _log.w('AC-4 metadata path failed, falling back to FFmpeg: $e');
        }
      }

      String? ffmpegResult;
      if (isFlac) {
        ffmpegResult = await FFmpegService.embedMetadata(
          flacPath: filePath,
          coverPath: validCover,
          metadata: metadata,
          artistTagMode: settings.artistTagMode,
        );
      } else if (isM4a) {
        ffmpegResult = await FFmpegService.embedMetadataToM4a(
          m4aPath: filePath,
          coverPath: validCover,
          metadata: metadata,
        );
      } else if (isMp3) {
        ffmpegResult = await FFmpegService.embedMetadataToMp3(
          mp3Path: filePath,
          coverPath: validCover,
          metadata: metadata,
        );
      } else {
        ffmpegResult = await FFmpegService.embedMetadataToOpus(
          opusPath: filePath,
          coverPath: validCover,
          metadata: metadata,
          artistTagMode: settings.artistTagMode,
        );
      }

      if (ffmpegResult != null) {
        _log.d('Metadata embedded to $format via FFmpeg');
      } else {
        _log.w('FFmpeg $format metadata embed failed');
      }

      if (isM4a && settings.embedReplayGain && scannedReplayGain != null) {
        try {
          await PlatformBridge.editFileMetadata(filePath, {
            'replaygain_track_gain': scannedReplayGain.trackGain,
            'replaygain_track_peak': scannedReplayGain.trackPeak,
          });
          _log.d(
            'ReplayGain compatibility tags written for $format: gain=${scannedReplayGain.trackGain}, peak=${scannedReplayGain.trackPeak}',
          );
        } catch (e) {
          _log.w('Failed to write native ReplayGain tags for $format: $e');
        }
      }

      if (isFlac) {
        if (settings.artistTagMode == artistTagModeSplitVorbis) {
          try {
            await PlatformBridge.rewriteSplitArtistTags(
              filePath,
              track.artistName,
              albumArtist ?? '',
            );
            _log.d('Split artist tags rewritten via native FLAC writer');
          } catch (e) {
            _log.w('Failed to rewrite split artist tags: $e');
          }
        }

        if (settings.embedReplayGain) {
          try {
            final rgResult = await FFmpegService.scanReplayGain(filePath);
            if (rgResult != null) {
              await PlatformBridge.editFileMetadata(filePath, {
                'replaygain_track_gain': rgResult.trackGain,
                'replaygain_track_peak': rgResult.trackPeak,
              });
              _log.d(
                'ReplayGain for $format: gain=${rgResult.trackGain}, peak=${rgResult.trackPeak}',
              );
              _storeTrackReplayGainForAlbum(track, filePath, rgResult);
            }
          } catch (e) {
            _log.w('Failed to embed ReplayGain via native writer: $e');
          }
        }
      }
    } catch (e) {
      _log.e('Failed to embed metadata to $format: $e');
    } finally {
      if (coverPath != null) {
        try {
          final coverFile = File(coverPath);
          if (await coverFile.exists()) await coverFile.delete();
        } catch (e) {
          _log.w('Failed to cleanup $format cover file: $e');
        }
      }
    }
  }

  Future<String?> _copySafToTemp(String uri) async {
    try {
      return await PlatformBridge.copyContentUriToTemp(uri);
    } catch (e) {
      _log.w('Failed to copy SAF uri to temp: $e');
      return null;
    }
  }

  Future<String?> _writeTempToSaf({
    required String treeUri,
    required String relativeDir,
    required String fileName,
    required String mimeType,
    required String srcPath,
  }) async {
    try {
      return await PlatformBridge.createSafFileFromPath(
        treeUri: treeUri,
        relativeDir: relativeDir,
        fileName: fileName,
        mimeType: mimeType,
        srcPath: srcPath,
      );
    } catch (e) {
      _log.w('Failed to write temp file to SAF: $e');
      return null;
    }
  }

  Future<void> _writeLrcToSaf({
    required String treeUri,
    required String relativeDir,
    required String baseName,
    required String lrcContent,
  }) async {
    try {
      if (lrcContent.isEmpty) return;
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$baseName.lrc';
      await File(tempPath).writeAsString(lrcContent);
      final lrcName = '$baseName.lrc';
      final uri = await _writeTempToSaf(
        treeUri: treeUri,
        relativeDir: relativeDir,
        fileName: lrcName,
        mimeType: _mimeTypeForExt('.lrc'),
        srcPath: tempPath,
      );
      if (uri != null) {
        _log.d('External LRC saved to SAF: $lrcName');
      } else {
        _log.w('Failed to write external LRC to SAF');
      }
      try {
        await File(tempPath).delete();
      } catch (_) {}
    } catch (e) {
      _log.w('Failed to create external LRC in SAF: $e');
    }
  }

  Future<void> _deleteSafFile(String uri) async {
    try {
      await PlatformBridge.safDelete(uri);
    } catch (e) {
      _log.w('Failed to delete SAF file: $e');
    }
  }

  bool _hasWifiConnection(List<ConnectivityResult> results) {
    return results.contains(ConnectivityResult.wifi);
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
    await prefs.setString(_nativeWorkerRunIdPrefsKey, runId);
  }

  Future<String?> _loadNativeWorkerRunId() async {
    if (_activeNativeWorkerRunId != null) return _activeNativeWorkerRunId;
    final prefs = await SharedPreferences.getInstance();
    final runId = prefs.getString(_nativeWorkerRunIdPrefsKey);
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
    if (prefs.getString(_nativeWorkerRunIdPrefsKey) == runId) {
      await prefs.remove(_nativeWorkerRunIdPrefsKey);
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
          'save_download_history': settings.saveDownloadHistory,
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
      if (_downloadProviderReplacesLegacyProvider(item.service, 'qobuz')) {
        payloadSpotifyId = '';
      }
    }
    if (trackForPayload.id.startsWith('tidal:')) {
      payloadTidalId = trackForPayload.id.substring(6);
      if (_downloadProviderReplacesLegacyProvider(item.service, 'tidal')) {
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
      if (settings.saveDownloadHistory) {
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
            await ref
                .read(downloadHistoryProvider.notifier)
                .reloadFromStorage();
          }
        } else if (result['history_written'] == true) {
          await ref.read(downloadHistoryProvider.notifier).reloadFromStorage();
        }
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

    if (settings.saveDownloadHistory) {
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
    }

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

    try {
      await _processQueueSequential();
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

  Future<void> _processQueueSequential() async {
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

      // One download at a time: only start the next item once the current
      // download has finished, to stay within the API's single-request limit.
      if (activeDownloads.isEmpty &&
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
          if (_downloadProviderReplacesLegacyProvider(item.service, 'qobuz')) {
            payloadSpotifyId = '';
          }
        }
        if (trackToDownload.id.startsWith('tidal:')) {
          payloadTidalId = trackToDownload.id.substring(6);
          if (_downloadProviderReplacesLegacyProvider(item.service, 'tidal')) {
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

              // Repair AC-4 (dac4 + ISO MP4) using the still-present encrypted
              // source. No-op for other codecs.
              try {
                await PlatformBridge.ensureAC4Config(
                  decryptedTempPath,
                  tempPath,
                );
              } catch (e) {
                _log.w('AC-4 container repair skipped: $e');
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
            final encryptedSource = filePath;
            final decryptedPath = await FFmpegService.decryptWithDescriptor(
              inputPath: encryptedSource,
              descriptor: decryptionDescriptor,
              deleteOriginal: false,
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
                await deleteFile(encryptedSource);
              } catch (_) {}
              return;
            }
            // Repair AC-4 (dac4 + ISO MP4) using the still-present encrypted
            // source before discarding it. No-op for other codecs.
            try {
              await PlatformBridge.ensureAC4Config(
                decryptedPath,
                encryptedSource,
              );
            } catch (e) {
              _log.w('AC-4 container repair skipped: $e');
            }
            try {
              await deleteFile(encryptedSource);
            } catch (_) {}
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
        final shouldForceDashSafM4aHandling =
            !wasExisting &&
            isContentUriPath &&
            effectiveSafMode &&
            _downloadProviderReplacesLegacyProvider(actualService, 'tidal') &&
            filePath.endsWith('.flac') &&
            (mimeType == null || mimeType.contains('flac'));

        if (shouldForceDashSafM4aHandling) {
          _log.w(
            'SAF file is labeled FLAC but backend returned DASH/M4A stream; converting it back to FLAC.',
          );
        }

        if (isM4aFile || shouldForceDashSafM4aHandling) {
          final currentFilePath = filePath;

          if (isContentUriPath && effectiveSafMode) {
            if (quality == 'HIGH') {
              final tidalHighFormat = settings.tidalHighFormat;
              _log.i(
                'Lossy 320kbps quality (SAF), converting M4A to $tidalHighFormat...',
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
                'Lossy 320kbps quality download, converting M4A to $tidalHighFormat...',
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

          if (settings.saveDownloadHistory) {
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
                    safRelativeDir: effectiveSafMode
                        ? effectiveOutputDir
                        : null,
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
          }

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
          case 'verification_required':
            errorType = DownloadErrorType.verificationRequired;
            break;
          default:
            errorType = _downloadErrorTypeFromMessage(errorMsg);
        }

        _log.e('Download failed: $errorMsg (type: $errorTypeStr)');
        updateItemStatus(
          item.id,
          DownloadStatus.failed,
          error: errorMsg,
          errorType: errorType,
        );
        if (errorType == DownloadErrorType.verificationRequired) {
          unawaited(openPendingExtensionVerification(item.service));
        }
        _failedInSession++;

        try {
          await PlatformBridge.cleanupConnections();
        } catch (e) {
          _log.e('Post-failure connection cleanup failed: $e');
        }
      }

      _downloadCount++;
      if (_downloadCount % _cleanupInterval == 0) {
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
      } else {
        errorType = _downloadErrorTypeFromMessage(errorMsg);
      }

      updateItemStatus(
        item.id,
        DownloadStatus.failed,
        error: errorMsg,
        errorType: errorType,
      );
      if (errorType == DownloadErrorType.verificationRequired) {
        unawaited(openPendingExtensionVerification(item.service));
      }
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
