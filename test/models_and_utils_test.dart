import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/models/download_item.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/models/theme_settings.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/services/app_remote_config_service.dart';
import 'package:spotiflac_android/services/download_request_payload.dart';
import 'package:spotiflac_android/services/history_database.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/utils/artist_utils.dart';
import 'package:spotiflac_android/utils/audio_conversion_utils.dart';
import 'package:spotiflac_android/utils/audio_format_utils.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/mime_utils.dart';
import 'package:spotiflac_android/utils/path_match_keys.dart';
import 'package:spotiflac_android/utils/string_utils.dart';

void main() {
  group('file deletion', () {
    test('confirms a local file is absent before reporting success', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'spotiflac-delete-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final file = File('${tempDir.path}${Platform.pathSeparator}track.flac');
      await file.writeAsBytes([1, 2, 3]);

      expect(await deleteFile(file.path), isTrue);
      expect(await file.exists(), isFalse);
      expect(await deleteFile(file.path), isTrue);
    });

    test('refuses to delete a virtual CUE track path', () async {
      expect(await deleteFile('/music/album.cue#track01'), isFalse);
    });
  });

  group('native worker progress', () {
    test('does not publish 100 percent while finalization is pending', () {
      expect(nativeWorkerFinalizingProgress(0), 0.95);
      expect(nativeWorkerFinalizingProgress(0.7), 0.7);
      expect(nativeWorkerFinalizingProgress(1), 0.99);
    });
  });

  group('storage write failure detection', () {
    test('recognizes typed and common Android filesystem failures', () {
      expect(
        isStorageWriteFailure(
          errorType: 'permission',
          errorMessage: 'provider-specific text',
        ),
        isTrue,
      );
      expect(
        isStorageWriteFailure(
          errorMessage:
              'failed to create file: open /storage/song.flac.partial: '
              'operation not permitted',
        ),
        isTrue,
      );
      expect(
        isStorageWriteFailure(
          errorMessage:
              'Native finalization failed: failed to publish deferred SAF output',
        ),
        isTrue,
      );
    });

    test(
      'does not mistake provider or network failures for storage errors',
      () {
        expect(
          isStorageWriteFailure(
            errorType: 'api_error',
            errorMessage: 'HTTP 404 for /download',
          ),
          isFalse,
        );
        expect(
          isStorageWriteFailure(
            errorType: 'network',
            errorMessage: 'Connection reset by peer',
          ),
          isFalse,
        );
      },
    );
  });

  group('local library incremental scan', () {
    test('rescans legacy metadata rows exactly once', () {
      expect(
        libraryIncrementalSnapshotModTime(
          storedModTime: 1234,
          storedScanVersion: 0,
        ),
        -1,
      );
      expect(
        libraryIncrementalSnapshotModTime(
          storedModTime: 1234,
          storedScanVersion: LibraryDatabase.audioMetadataScanVersion,
        ),
        1234,
      );
    });

    test('keeps a local item current after an audio metadata probe', () {
      final item = LocalLibraryItem(
        id: 'local-1',
        trackName: 'Song',
        artistName: 'Artist',
        albumName: 'Album',
        filePath: '/music/song.flac',
        scannedAt: DateTime(2026),
        bitDepth: 24,
        sampleRate: 96000,
      );

      final updated = item.withAudioMetadata(bitrate: 1840);

      expect(updated.bitrate, 1840);
      expect(updated.bitDepth, 24);
      expect(updated.sampleRate, 96000);
      expect(updated.trackName, 'Song');
      expect(updated.filePath, '/music/song.flac');
    });
  });

  group('app state database migrations', () {
    final source = File(
      'lib/services/app_state_database.dart',
    ).readAsStringSync();

    test('v1 to v2 tolerates an existing playback session table', () {
      expect(
        source,
        contains('CREATE TABLE IF NOT EXISTS \$_playbackSessionTable'),
      );
      expect(
        RegExp(
          r'if \(oldVersion < 2\)\s*\{\s*'
          r'await _createPlaybackSessionTable\(db\);',
        ).hasMatch(source),
        isTrue,
      );
    });
  });

  group('native worker contracts', () {
    final finalizerSource = File(
      'android/app/src/main/kotlin/com/zarz/spotiflac/'
      'NativeDownloadFinalizer.kt',
    ).readAsStringSync();
    final historyDatabaseSource = File(
      'lib/services/history_database.dart',
    ).readAsStringSync();

    int kotlinConstant(String name) {
      final match = RegExp(
        'const val $name = (\\d+)',
      ).firstMatch(finalizerSource);
      expect(match, isNotNull, reason: 'Missing Kotlin constant $name');
      return int.parse(match!.group(1)!);
    }

    test('uses the same worker contract version in Dart and Kotlin', () {
      expect(
        kotlinConstant('NATIVE_WORKER_CONTRACT_VERSION'),
        DownloadRequestPayload.nativeWorkerContractVersion,
      );
    });

    test('uses the same history schema version in Dart and Kotlin', () {
      expect(
        kotlinConstant('HISTORY_SCHEMA_VERSION'),
        HistoryDatabase.schemaVersion,
      );
    });

    Set<String> historyTableColumns(String source) {
      final match = RegExp(
        r'CREATE TABLE(?: IF NOT EXISTS)? history\s*\(([\s\S]*?)\n\s*\)',
      ).firstMatch(source);
      expect(match, isNotNull, reason: 'Missing history CREATE TABLE');
      return match!
          .group(1)!
          .split(',')
          .map((definition) => definition.trim().split(RegExp(r'\s+')).first)
          .where((column) => column.isNotEmpty)
          .toSet();
    }

    Map<String, String> historyIndexes(String source) {
      final indexes = <String, String>{};
      final pattern = RegExp(
        r'CREATE INDEX(?: IF NOT EXISTS)?\s+(\w+)\s+'
        r'ON history\s*\(([^)]+)\)',
      );
      for (final match in pattern.allMatches(source)) {
        indexes[match.group(1)!] = match
            .group(2)!
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }
      return indexes;
    }

    test('uses the same history columns in Dart and native writers', () {
      final dartColumns = historyTableColumns(historyDatabaseSource);
      final nativeColumns = historyTableColumns(finalizerSource);
      expect(nativeColumns, dartColumns);

      final requiredBlock = RegExp(
        r'requiredHistoryColumns\s*=\s*setOf\(([\s\S]*?)\n\s*\)',
      ).firstMatch(finalizerSource);
      expect(requiredBlock, isNotNull);
      final requiredColumns = RegExp(
        r'"([a-z0-9_]+)"',
      ).allMatches(requiredBlock!.group(1)!).map((m) => m.group(1)!).toSet();
      expect(requiredColumns, dartColumns);

      final buildHistoryRow = RegExp(
        r'private fun buildHistoryRow\([\s\S]*?return values',
      ).firstMatch(finalizerSource);
      expect(buildHistoryRow, isNotNull);
      final nativeWrittenColumns = RegExp(
        r'values\.put\("([a-z0-9_]+)"',
      ).allMatches(buildHistoryRow!.group(0)!).map((m) => m.group(1)!).toSet();
      expect(
        dartColumns,
        containsAll(nativeWrittenColumns),
        reason: 'Native finalizer writes a column missing from Dart schema',
      );
    });

    test('uses the same history indexes in Dart and native writers', () {
      expect(
        historyIndexes(finalizerSource),
        historyIndexes(historyDatabaseSource),
      );
    });

    test('matches shared Dart/native finalization quality cases', () {
      final fixture = File(
        'android/app/src/test/resources/finalization_quality_cases.tsv',
      ).readAsLinesSync();
      for (final line in fixture) {
        if (line.isEmpty || line.startsWith('#')) continue;
        final fields = line.split('\t');
        expect(fields, hasLength(6), reason: 'Invalid shared fixture: $line');
        final actual = buildQualityVariantFilenameLabel(
          detectedFormat: fields[0],
          bitDepth: int.tryParse(fields[1]),
          sampleRate: int.tryParse(fields[2]),
          bitrateKbps: int.tryParse(fields[3]),
          measuredQuality: fields[4],
        );
        final expected = fields[5] == '<null>' ? null : fields[5];
        expect(actual, expected, reason: 'Shared fixture: $line');
      }
    });
  });

  group('quality variant filenames', () {
    test('estimates average bitrate without decoding the audio file', () {
      expect(
        estimateAverageBitrateKbps(
          fileSizeBytes: 42.9 * 1000 * 1000 ~/ 1,
          durationSeconds: 204,
        ),
        1682,
      );
      expect(
        estimateAverageBitrateKbps(fileSizeBytes: null, durationSeconds: 204),
        isNull,
      );
      expect(
        estimateAverageBitrateKbps(
          fileSizeBytes: 42 * 1000 * 1000,
          durationSeconds: 0,
        ),
        isNull,
      );
    });

    test('uses measured lossless specifications instead of request labels', () {
      expect(
        buildQualityVariantFilenameLabel(
          detectedFormat: 'flac',
          bitDepth: 24,
          sampleRate: 96000,
          measuredQuality: 'LOSSLESS',
        ),
        '24bit-96kHz',
      );
      expect(
        buildQualityVariantFilenameLabel(
          detectedFormat: 'flac',
          measuredQuality: 'LOSSLESS',
        ),
        isNull,
      );
    });

    test('uses measured bitrate for lossy output', () {
      expect(
        buildQualityVariantFilenameLabel(
          detectedFormat: 'mp3',
          bitrateKbps: 320,
        ),
        '320kbps',
      );
      expect(
        buildQualityVariantFilenameLabel(
          detectedFormat: 'opus',
          measuredQuality: 'OPUS 256kbps',
        ),
        '256kbps',
      );
    });

    test('creates a stable temporary token and replaces only that token', () {
      final token = qualityVariantStagingLabel('queue-item-1');
      expect(token, matches(RegExp(r'^qv_[0-9a-f]{8}$')));
      expect(qualityVariantStagingLabel('queue-item-1'), token);
      expect(
        applyQualityVariantFilenameLabel(
          fileName: 'Artist - Song - $token.flac',
          stagingLabel: token,
          qualityLabel: '16bit-44.1kHz',
        ),
        'Artist - Song - 16bit-44.1kHz.flac',
      );
      expect(
        applyQualityVariantFilenameLabel(
          fileName: 'Post Processed Song.flac',
          stagingLabel: token,
          qualityLabel: '16bit-44.1kHz',
        ),
        'Post Processed Song - 16bit-44.1kHz.flac',
      );
    });

    test('adds measured quality only when a clean filename collides', () {
      const staging = 'qv_12345678';
      const stagedName = 'Artist - Song - qv_12345678.flac';
      expect(
        removeQualityVariantStagingLabel(
          fileName: stagedName,
          stagingLabel: staging,
        ),
        'Artist - Song.flac',
      );
      expect(
        resolveQualityVariantFilename(
          fileName: stagedName,
          stagingLabel: staging,
          qualityLabel: '24bit-96kHz',
          collisionOnly: true,
          cleanNameExists: false,
        ),
        'Artist - Song.flac',
      );
      expect(
        resolveQualityVariantFilename(
          fileName: stagedName,
          stagingLabel: staging,
          qualityLabel: '24bit-96kHz',
          collisionOnly: true,
          cleanNameExists: true,
        ),
        'Artist - Song - 24bit-96kHz.flac',
      );
    });
  });

  group('Library collections', () {
    test('keeps playlist membership without eagerly loading track JSON', () {
      final playlist = UserPlaylistCollection(
        id: 'playlist-1',
        name: 'Playlist',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        tracks: const [],
        previewCover: 'https://example.test/cover.jpg',
        tracksLoaded: false,
        trackKeys: {'track:a', 'track:b'},
      );

      expect(playlist.tracks, isEmpty);
      expect(playlist.tracksLoaded, isFalse);
      expect(playlist.trackCount, 2);
      expect(playlist.containsTrackKey('track:a'), isTrue);
      expect(playlist.previewCover, 'https://example.test/cover.jpg');

      final loaded = playlist.copyWith(
        tracks: [
          CollectionTrackEntry(
            key: 'track:a',
            track: const Track(
              id: 'a',
              name: 'A',
              artistName: 'Artist',
              albumName: 'Album',
              duration: 1000,
            ),
            addedAt: DateTime.utc(2026),
          ),
        ],
      );
      expect(loaded.tracksLoaded, isTrue);
      expect(loaded.trackCount, 1);
    });
  });

  group('Track', () {
    test('preserves a generic extension explicit flag', () {
      final track = Track.fromBackendMap({
        'id': 'extension-track-1',
        'name': 'Explicit Song',
        'artists': 'Artist',
        'album_name': 'Album',
        'duration_ms': 180000,
        'provider_id': 'extension.example',
        'explicit': true,
      });

      expect(track.source, 'extension.example');
      expect(track.explicit, isTrue);
      expect(track.isExplicit, isTrue);
    });

    test('exposes collection, source, and quality flags', () {
      const album = Track(
        id: 'album-1',
        name: 'Album',
        artistName: 'Artist',
        albumName: 'Album',
        duration: 0,
        itemType: 'album',
        source: 'extension.example',
        audioQuality: 'FLAC 1411kbps',
        audioModes: 'STEREO,DOLBY_ATMOS',
      );

      expect(album.isAlbumItem, isTrue);
      expect(album.isPlaylistItem, isFalse);
      expect(album.isArtistItem, isFalse);
      expect(album.isCollection, isTrue);
      expect(album.isFromExtension, isTrue);
      expect(album.hasAudioQuality, isTrue);
      expect(album.isDolbyAtmos, isTrue);
    });

    test('detects singles and eps case-insensitively', () {
      const single = Track(
        id: 'track-1',
        name: 'Song',
        artistName: 'Artist',
        albumName: 'Single',
        duration: 210000,
        albumType: 'SINGLE',
      );
      const ep = Track(
        id: 'track-2',
        name: 'Song 2',
        artistName: 'Artist',
        albumName: 'EP',
        duration: 180000,
        albumType: 'ep',
      );
      const album = Track(
        id: 'track-3',
        name: 'Song 3',
        artistName: 'Artist',
        albumName: 'Album',
        duration: 240000,
        albumType: 'album',
      );

      expect(single.isSingle, isTrue);
      expect(ep.isSingle, isTrue);
      expect(album.isSingle, isFalse);
    });

    test('round-trips json with service availability', () {
      final track = Track.fromJson({
        'id': 'spotify:track:1',
        'name': 'Song',
        'artistName': 'Artist',
        'albumName': 'Album',
        'duration': 123456,
        'availability': {'tidal': true, 'deezer': true, 'deezerId': '31337'},
      });

      expect(track.availability?.tidal, isTrue);
      expect(track.availability?.qobuz, isFalse);
      expect(track.availability?.deezerId, '31337');
      expect(track.toJson()['id'], 'spotify:track:1');
      expect(track.availability!.toJson()['deezer'], isTrue);
    });
  });

  group('DownloadItem', () {
    Track sampleTrack() => const Track(
      id: 'track-1',
      name: 'Song',
      artistName: 'Artist',
      albumName: 'Album',
      duration: 1000,
    );

    test('uses defaults and preserves fields through copyWith', () {
      final createdAt = DateTime.utc(2026, 5, 4, 10);
      final item = DownloadItem(
        id: 'download-1',
        track: sampleTrack(),
        service: 'tidal',
        createdAt: createdAt,
      );

      final updated = item.copyWith(
        status: DownloadStatus.downloading,
        progress: 0.5,
        speedMBps: 1.25,
        bytesReceived: 512,
        bytesTotal: 1024,
        qualityOverride: 'HI_RES',
        playlistName: 'Favorites',
        preparationStage: 'resolving_stream',
        preserveQualityVariant: true,
      );

      expect(item.status, DownloadStatus.queued);
      expect(item.progress, 0);
      expect(updated.id, item.id);
      expect(updated.track, item.track);
      expect(updated.status, DownloadStatus.downloading);
      expect(updated.progress, 0.5);
      expect(updated.speedMBps, 1.25);
      expect(updated.bytesReceived, 512);
      expect(updated.bytesTotal, 1024);
      expect(updated.qualityOverride, 'HI_RES');
      expect(updated.playlistName, 'Favorites');
      expect(updated.preparationStage, 'resolving_stream');
      expect(updated.preserveQualityVariant, isTrue);
    });

    test('maps typed errors to user-facing messages', () {
      final base = DownloadItem(
        id: 'download-1',
        track: sampleTrack(),
        service: 'qobuz',
        createdAt: DateTime.utc(2026),
        error: 'raw backend failure',
      );

      expect(base.errorMessage, 'raw backend failure');
      expect(
        base.copyWith(errorType: DownloadErrorType.notFound).errorMessage,
        'Song not found on any service',
      );
      expect(
        base.copyWith(errorType: DownloadErrorType.rateLimit).errorMessage,
        'Service rate limit reached. Wait before retrying.',
      );
      expect(
        base.copyWith(errorType: DownloadErrorType.network).errorMessage,
        'Connection failed, check your internet',
      );
      expect(
        base.copyWith(errorType: DownloadErrorType.permission).errorMessage,
        'Cannot write to folder, check storage permission',
      );
      expect(base.copyWith(error: null).errorMessage, 'raw backend failure');
    });

    test('decodes json defaults and enums', () {
      final item = DownloadItem.fromJson({
        'id': 'download-1',
        'track': {
          'id': 'track-1',
          'name': 'Song',
          'artistName': 'Artist',
          'albumName': 'Album',
          'duration': 1000,
        },
        'service': 'deezer',
        'status': 'failed',
        'errorType': 'network',
        'createdAt': '2026-05-04T10:00:00.000Z',
      });

      expect(item.status, DownloadStatus.failed);
      expect(item.errorType, DownloadErrorType.network);
      expect(item.progress, 0);
      expect(item.bytesReceived, 0);
      expect(item.preparationStage, isEmpty);
      expect(item.preserveQualityVariant, isFalse);
      expect(item.toJson()['status'], 'failed');
      expect(item.toJson()['errorType'], 'network');
      expect(item.toJson()['preparationStage'], isEmpty);
    });
  });

  group('Download queue lookup', () {
    test('updates counters while sharing unchanged index structures', () {
      DownloadItem item(String id, DownloadStatus status) => DownloadItem(
        id: id,
        track: Track(
          id: 'track-$id',
          name: 'Song $id',
          artistName: 'Artist',
          albumName: 'Album',
          duration: 1000,
        ),
        service: 'extension.test',
        createdAt: DateTime.utc(2026),
        status: status,
      );

      final previous = [
        item('queued', DownloadStatus.queued),
        item('active', DownloadStatus.downloading),
        item('finalizing', DownloadStatus.finalizing),
      ];
      final lookup = DownloadQueueLookup.fromItems(previous);
      expect(lookup.queuedCount, 3);
      expect(lookup.activeDownloadsCount, 1);
      expect(lookup.finalizingCount, 1);

      final next = List<DownloadItem>.from(previous);
      next[2] = previous[2].copyWith(status: DownloadStatus.completed);
      final updated = lookup.updatedForIndices(
        previousItems: previous,
        nextItems: next,
        changedIndices: const [2],
      );

      expect(updated.queuedCount, 2);
      expect(updated.completedCount, 1);
      expect(updated.finalizingCount, 0);
      expect(identical(updated.indexByItemId, lookup.indexByItemId), isTrue);
      expect(identical(updated.itemIds, lookup.itemIds), isTrue);
    });
  });

  group('AppSettings', () {
    test('provides stable defaults', () {
      const settings = AppSettings();

      expect(settings.audioQuality, 'LOSSLESS');
      expect(settings.filenameFormat, '{title} - {artist}');
      expect(settings.artistTagMode, artistTagModeJoined);
      expect(settings.autoFallback, isTrue);
      expect(settings.lyricsProviders, ['lrclib', 'apple_music']);
      expect(settings.lyricsAppleElrcWordSync, isFalse);
      expect(settings.deduplicateDownloads, isTrue);
      expect(settings.allowQualityVariants, isFalse);
      expect(settings.nativeDownloadWorkerEnabled, isFalse);
      expect(
        settings.libraryQualityLabelMode,
        AppSettings.libraryQualityLabelBitrate,
      );
    });

    test('copyWith updates values and can clear nullable provider fields', () {
      const settings = AppSettings(
        downloadFallbackExtensionIds: ['fallback.ext'],
        searchProvider: 'search.ext',
        homeFeedProvider: 'feed.ext',
      );

      final updated = settings.copyWith(
        defaultService: 'tidal',
        embedReplayGain: true,
        lyricsProviders: ['apple_music'],
        lyricsAppleElrcWordSync: true,
        deduplicateDownloads: false,
        allowQualityVariants: true,
        libraryQualityLabelMode: AppSettings.libraryQualityLabelBitDepth,
        clearDownloadFallbackExtensionIds: true,
        clearSearchProvider: true,
        clearHomeFeedProvider: true,
      );

      expect(updated.defaultService, 'tidal');
      expect(updated.embedReplayGain, isTrue);
      expect(updated.lyricsProviders, ['apple_music']);
      expect(updated.lyricsAppleElrcWordSync, isTrue);
      expect(updated.deduplicateDownloads, isFalse);
      expect(updated.allowQualityVariants, isTrue);
      expect(
        updated.libraryQualityLabelMode,
        AppSettings.libraryQualityLabelBitDepth,
      );
      expect(updated.downloadFallbackExtensionIds, isNull);
      expect(updated.searchProvider, isNull);
      expect(updated.homeFeedProvider, isNull);
      expect(updated.audioQuality, settings.audioQuality);
    });

    test('round-trips json including recently added settings', () {
      const settings = AppSettings(
        defaultService: 'qobuz',
        storageMode: 'saf',
        downloadTreeUri: 'content://tree/music',
        downloadFallbackExtensionIds: ['ext.a', 'ext.b'],
        searchProvider: 'search.ext',
        homeFeedProvider: AppSettings.homeFeedProviderOff,
        useAllFilesAccess: true,
        networkCompatibilityMode: true,
        songLinkRegion: 'ID',
        localLibraryEnabled: true,
        localLibraryPath: '/music',
        hasCompletedTutorial: true,
        musixmatchLanguage: 'id',
        lyricsAppleElrcWordSync: true,
        lastSeenVersion: '4.5.0',
        deduplicateDownloads: false,
        allowQualityVariants: true,
        nativeDownloadWorkerEnabled: true,
        libraryQualityLabelMode: AppSettings.libraryQualityLabelBitDepth,
      );

      final decoded = AppSettings.fromJson(settings.toJson());

      expect(decoded.defaultService, 'qobuz');
      expect(decoded.storageMode, 'saf');
      expect(decoded.downloadTreeUri, 'content://tree/music');
      expect(decoded.downloadFallbackExtensionIds, ['ext.a', 'ext.b']);
      expect(decoded.searchProvider, 'search.ext');
      expect(decoded.homeFeedProvider, AppSettings.homeFeedProviderOff);
      expect(decoded.useAllFilesAccess, isTrue);
      expect(decoded.networkCompatibilityMode, isTrue);
      expect(decoded.songLinkRegion, 'ID');
      expect(decoded.localLibraryEnabled, isTrue);
      expect(decoded.localLibraryPath, '/music');
      expect(decoded.hasCompletedTutorial, isTrue);
      expect(decoded.musixmatchLanguage, 'id');
      expect(decoded.lyricsAppleElrcWordSync, isTrue);
      expect(decoded.lastSeenVersion, '4.5.0');
      expect(
        decoded.libraryQualityLabelMode,
        AppSettings.libraryQualityLabelBitDepth,
      );
      expect(decoded.deduplicateDownloads, isFalse);
      expect(decoded.allowQualityVariants, isTrue);
      expect(decoded.nativeDownloadWorkerEnabled, isTrue);
    });
  });

  group('ThemeSettings', () {
    test('serializes, deserializes, copies, and compares values', () {
      const settings = ThemeSettings(
        themeMode: ThemeMode.dark,
        useDynamicColor: false,
        seedColorValue: 0xff123456,
        useAmoled: true,
      );

      final decoded = ThemeSettings.fromJson(settings.toJson());
      final copied = decoded.copyWith(themeMode: ThemeMode.light);

      expect(decoded, settings);
      expect(decoded.hashCode, settings.hashCode);
      expect(decoded.seedColor, const Color(0xff123456));
      expect(copied.themeMode, ThemeMode.light);
      expect(copied.useAmoled, isTrue);
      expect(
        ThemeSettings.fromJson({'theme_mode': 'invalid'}).themeMode,
        ThemeMode.system,
      );
    });
  });

  group('DownloadRequestPayload', () {
    test('serializes all backend field names', () {
      const payload = DownloadRequestPayload(
        isrc: 'ISRC123',
        service: 'tidal',
        spotifyId: 'spotify:track:1',
        trackName: 'Song',
        artistName: 'Artist',
        albumName: 'Album',
        albumArtist: 'Album Artist',
        coverUrl: 'https://example.test/cover.jpg',
        outputDir: '/downloads',
        filenameFormat: '{artist} - {title}',
        quality: 'HI_RES',
        embedMetadata: false,
        artistTagMode: artistTagModeSplitVorbis,
        embedLyrics: false,
        embedMaxQualityCover: false,
        embedReplayGain: true,
        postProcessingEnabled: true,
        tidalHighFormat: 'opus_256',
        trackNumber: 7,
        playlistPosition: 3,
        discNumber: 2,
        totalTracks: 12,
        totalDiscs: 2,
        releaseDate: '2026-05-04',
        itemId: 'item-1',
        durationMs: 250000,
        source: 'extension.example',
        genre: 'Pop',
        label: 'Label',
        copyright: 'Copyright',
        composer: 'Composer',
        tidalId: 'tidal-1',
        qobuzId: 'qobuz-1',
        deezerId: 'deezer-1',
        lyricsMode: 'sidecar',
        useExtensions: true,
        useFallback: true,
        storageMode: 'saf',
        safTreeUri: 'content://tree/music',
        safRelativeDir: 'Album',
        safFileName: 'Song.flac',
        safOutputExt: 'flac',
        outputExt: '.flac',
        allowQualityVariant: true,
        qualityVariant: 'qv_12345678',
        qualityVariantCollisionOnly: true,
        songLinkRegion: 'ID',
      );

      expect(payload.toJson(), {
        'contract_version': DownloadRequestPayload.nativeWorkerContractVersion,
        'isrc': 'ISRC123',
        'service': 'tidal',
        'spotify_id': 'spotify:track:1',
        'track_name': 'Song',
        'artist_name': 'Artist',
        'album_name': 'Album',
        'album_artist': 'Album Artist',
        'cover_url': 'https://example.test/cover.jpg',
        'output_dir': '/downloads',
        'filename_format': '{artist} - {title}',
        'quality': 'HI_RES',
        'embed_metadata': false,
        'artist_tag_mode': artistTagModeSplitVorbis,
        'embed_lyrics': false,
        'embed_max_quality_cover': false,
        'embed_replaygain': true,
        'post_processing_enabled': true,
        'tidal_high_format': 'opus_256',
        'track_number': 7,
        'playlist_position': 3,
        'disc_number': 2,
        'total_tracks': 12,
        'total_discs': 2,
        'release_date': '2026-05-04',
        'item_id': 'item-1',
        'duration_ms': 250000,
        'source': 'extension.example',
        'genre': 'Pop',
        'label': 'Label',
        'copyright': 'Copyright',
        'composer': 'Composer',
        'tidal_id': 'tidal-1',
        'qobuz_id': 'qobuz-1',
        'deezer_id': 'deezer-1',
        'lyrics_mode': 'sidecar',
        'use_extensions': true,
        'use_fallback': true,
        'storage_mode': 'saf',
        'saf_tree_uri': 'content://tree/music',
        'saf_relative_dir': 'Album',
        'saf_file_name': 'Song.flac',
        'saf_output_ext': 'flac',
        'output_ext': '.flac',
        'stage_saf_output': false,
        'defer_saf_publish': false,
        'requires_container_conversion': false,
        'allow_quality_variant': true,
        'quality_variant': 'qv_12345678',
        'quality_variant_collision_only': true,
        'songlink_region': 'ID',
      });
    });

    test('withStrategy only changes requested strategy flags', () {
      const payload = DownloadRequestPayload(
        trackName: 'Song',
        artistName: 'Artist',
        albumName: 'Album',
        outputDir: '/downloads',
        filenameFormat: '{title}',
        useExtensions: false,
        useFallback: true,
      );

      final updated = payload.withStrategy(useExtensions: true);

      expect(updated.useExtensions, isTrue);
      expect(updated.useFallback, isTrue);
      expect(updated.trackName, payload.trackName);
      expect(updated.filenameFormat, payload.filenameFormat);
      expect(updated.allowQualityVariant, payload.allowQualityVariant);
      expect(updated.qualityVariant, payload.qualityVariant);
      expect(
        updated.qualityVariantCollisionOnly,
        payload.qualityVariantCollisionOnly,
      );
    });
  });

  group('artist utils', () {
    test('splits common artist separators and removes duplicates for tags', () {
      expect(splitArtistNames(' A, B & C feat. D x E with F '), [
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
      ]);
      expect(splitArtistTagValues('A, a & B'), ['A', 'B']);
      expect(splitArtistTagValues('   '), isEmpty);
      expect(shouldSplitVorbisArtistTags(artistTagModeSplitVorbis), isTrue);
      expect(shouldSplitVorbisArtistTags(artistTagModeJoined), isFalse);
    });
  });

  group('audio conversion utils', () {
    test('normalizes lightweight library scan metadata for display probes', () {
      final normalized = normalizeScannedAudioMetadata({
        'trackName': 'Song',
        'artistName': 'Artist',
        'albumName': 'Album',
        'albumArtist': 'Album Artist',
        'releaseDate': '2026',
        'trackNumber': 2,
        'totalTracks': 10,
        'discNumber': 1,
        'totalDiscs': 2,
        'bitDepth': 24,
        'sampleRate': 96000,
        'bitrate': 1840,
        'format': 'flac',
      });

      expect(normalized['title'], 'Song');
      expect(normalized['artist'], 'Artist');
      expect(normalized['album'], 'Album');
      expect(normalized['album_artist'], 'Album Artist');
      expect(normalized['date'], '2026');
      expect(normalized['track_number'], 2);
      expect(normalized['total_tracks'], 10);
      expect(normalized['disc_number'], 1);
      expect(normalized['total_discs'], 2);
      expect(normalized['bit_depth'], 24);
      expect(normalized['sample_rate'], 96000);
      expect(normalized['bitrate'], 1840);
      expect(normalized['audio_codec'], 'flac');
    });

    test('does not replace stored tags with filename scan fallbacks', () {
      final normalized = normalizeScannedAudioMetadata({
        'trackName': 'Filename fallback',
        'artistName': 'Unknown Artist',
        'albumName': 'Unknown Album',
        'metadataFromFilename': true,
        'format': 'flac',
      });

      expect(normalized['title'], isNull);
      expect(normalized['artist'], isNull);
      expect(normalized['album'], isNull);
      expect(normalized['audio_codec'], 'flac');
    });

    test('distinguishes an ALAC codec from its M4A container', () {
      expect(normalizeAudioFormatValue('ALAC'), 'alac');
      expect(
        detectedAudioFormatFromMetadata({
          'audio_codec': 'alac',
          'format': 'm4a',
        }),
        'alac',
      );
      expect(
        detectedAudioFormatFromMetadata({'audio_codec': '', 'format': 'alac'}),
        'alac',
      );
    });

    test(
      'detects Dolby formats from stored scan format before file extension',
      () {
        expect(
          convertibleAudioSourceFormat(
            storedFormat: 'eac3',
            filePath: 'content://media/song.m4a',
          ),
          'EAC3',
        );
        expect(convertibleAudioSourceFormat(fileName: 'Song.ac-3'), 'AC3');
        expect(convertibleAudioSourceFormat(storedFormat: 'ac4'), 'AC4');
      },
    );

    test('allows Dolby sources only for lossy batch conversion targets', () {
      expect(
        canConvertAudioFormat(sourceFormat: 'EAC3', targetFormat: 'MP3'),
        isTrue,
      );
      expect(
        canConvertAudioFormat(sourceFormat: 'EAC3', targetFormat: 'Opus'),
        isTrue,
      );
      expect(
        canConvertAudioFormat(sourceFormat: 'EAC3', targetFormat: 'AAC'),
        isTrue,
      );
      expect(
        canConvertAudioFormat(sourceFormat: 'EAC3', targetFormat: 'FLAC'),
        isFalse,
      );
      expect(
        canConvertAudioFormat(sourceFormat: 'EAC3', targetFormat: 'ALAC'),
        isFalse,
      );
    });
  });

  group('string utils', () {
    test('normalizes optional strings and cover references', () {
      expect(normalizeOptionalString(null), isNull);
      expect(normalizeOptionalString(' null '), isNull);
      expect(normalizeOptionalString(' value '), 'value');
      expect(
        normalizeCoverReference('//cdn.example.test/a.jpg'),
        'https://cdn.example.test/a.jpg',
      );
      expect(
        normalizeCoverReference('https://example.test/a.jpg'),
        'https://example.test/a.jpg',
      );
      expect(
        normalizeCoverReference('/storage/music/a.jpg'),
        '/storage/music/a.jpg',
      );
      expect(normalizeCoverReference('relative/a.jpg'), isNull);
      expect(normalizeRemoteHttpUrl('file:///tmp/a.jpg'), isNull);
      expect(
        normalizeRemoteHttpUrl('http://example.test/a.jpg'),
        'http://example.test/a.jpg',
      );
    });

    test('formats display audio quality from strongest available source', () {
      expect(
        buildDisplayAudioQuality(
          bitrateKbps: 320,
          format: 'mp3',
          bitDepth: 24,
          sampleRate: 96000,
          storedQuality: 'LOSSLESS',
        ),
        'MP3 320kbps',
      );
      expect(
        buildDisplayAudioQuality(bitDepth: 24, sampleRate: 96000),
        '24-bit/96kHz',
      );
      expect(formatSampleRateKHz(44100), '44.1kHz');
      expect(buildDisplayAudioQuality(storedQuality: ' Hi-Res '), 'Hi-Res');
      expect(isPlaceholderQualityLabel('lossless'), isTrue);
      expect(isPlaceholderQualityLabel('FLAC 1411kbps'), isFalse);
    });
  });

  group('mime utils', () {
    test('maps known audio extensions and falls back to wildcard', () {
      expect(audioMimeTypeForPath('/music/song.FLAC'), 'audio/flac');
      expect(audioMimeTypeForPath('/music/song.m4a'), 'audio/mp4');
      expect(audioMimeTypeForPath('/music/song.mp3'), 'audio/mpeg');
      expect(audioMimeTypeForPath('/music/song.ogg'), 'audio/ogg');
      expect(audioMimeTypeForPath('/music/song.wav'), 'audio/wav');
      expect(audioMimeTypeForPath('/music/song.aac'), 'audio/aac');
      expect(audioMimeTypeForPath('/music/song'), 'audio/*');
      expect(audioMimeTypeForPath('/music/song.'), 'audio/*');
      expect(audioMimeTypeForPath('/music/song.txt'), 'audio/*');
    });
  });

  group('path match keys', () {
    test('builds normalized variants for local paths and file uris', () {
      final keys = buildPathMatchKeys('EXISTS: /Music/A%20Song.FLAC ');

      expect(keys, contains('/Music/A%20Song.FLAC'));
      expect(keys, contains('/music/a%20song.flac'));
      expect(keys, contains('/Music/A Song.FLAC'));
      expect(keys, contains('/music/a song.flac'));
      expect(keys, contains('file:///Music/A%2520Song.FLAC'));
      expect(keys, contains('/Music/A%20Song'));
      expect(
        identical(buildPathMatchKeys('/Music/A%20Song.FLAC'), keys),
        isTrue,
      );
      expect(buildPathMatchKeys('   '), isEmpty);
    });

    test('normalizes windows-style separators', () {
      final keys = buildPathMatchKeys(r'C:\Music\Song.mp3');

      expect(keys, contains(r'C:\Music\Song.mp3'));
      expect(keys, contains('C:/Music/Song.mp3'));
      expect(keys, contains('c:/music/song.mp3'));
      expect(keys, contains('C:/Music/Song'));
    });
  });

  group('AppRemoteConfig', () {
    test('parses announcement and donate payloads from API JSON', () {
      final config = AppRemoteConfig.fromJson({
        'announcement': {
          'id': 'hello-2026',
          'enabled': true,
          'title': 'Server message',
          'message': 'A clear message for users',
          'cta_enabled': true,
          'cta_label': 'Donate',
          'cta_url': 'https://example.test/donate',
          'starts_at': '2026-05-01T00:00:00Z',
          'ends_at': '2026-06-01T00:00:00Z',
          'min_version': '4.5.0',
          'priority': 'high',
        },
        'donate': {
          'enabled': true,
          'title': 'Support SpotiFLAC Mobile',
          'message': 'Help cover infrastructure.',
          'methods': [
            {
              'id': 'kofi',
              'title': 'Ko-fi',
              'subtitle': 'ko-fi.com/example',
              'url': 'https://ko-fi.com/example',
              'icon': 'kofi',
              'color': '#FF5E5B',
            },
            {
              'id': 'wallet',
              'title': 'USDT',
              'subtitle': 'TRC20',
              'wallet_address': 'T123',
              'icon': 'wallet',
              'color': '0xFF26A17B',
            },
          ],
          'supporters': ['Alice', 'Bob'],
          'notices': ['No paywalls'],
        },
      });

      expect(config.announcement?.id, 'hello-2026');
      expect(config.announcement?.hasCta, isTrue);
      expect(
        config.announcement?.isActive(
          now: DateTime.utc(2026, 5, 11),
          currentVersion: '4.5.1',
        ),
        isTrue,
      );
      expect(config.donate.title, 'Support SpotiFLAC Mobile');
      expect(config.donate.methods, hasLength(2));
      expect(config.donate.methods.first.color, 0xFFFF5E5B);
      expect(config.donate.methods.last.isWallet, isTrue);
      expect(config.donate.supporters, ['Alice', 'Bob']);
      expect(config.donate.notices, ['No paywalls']);
    });

    test('requires enabled announcement CTA with label and url', () {
      final disabledCta = RemoteAnnouncement.fromJson({
        'id': 'notice',
        'title': 'Notice',
        'message': 'No button',
        'cta_label': 'Open',
        'cta_url': 'https://api.zarz.moe',
      });
      final missingLabel = RemoteAnnouncement.fromJson({
        'id': 'notice',
        'title': 'Notice',
        'message': 'No button',
        'cta_enabled': true,
        'cta_url': 'https://example.test',
      });
      final enabledCta = RemoteAnnouncement.fromJson({
        'id': 'notice',
        'title': 'Notice',
        'message': 'With button',
        'cta_enabled': true,
        'cta_label': 'Read More',
        'cta_url': 'https://example.test',
      });

      expect(disabledCta.hasCta, isFalse);
      expect(missingLabel.hasCta, isFalse);
      expect(enabledCta.hasCta, isTrue);
      expect(enabledCta.ctaLabel, 'Read More');
    });

    test('filters inactive announcements by window and app version', () {
      final announcement = RemoteAnnouncement.fromJson({
        'id': 'future',
        'title': 'Future',
        'message': 'Not yet',
        'starts_at': '2026-06-01T00:00:00Z',
        'min_version': '4.6.0',
      });

      expect(
        announcement.isActive(
          now: DateTime.utc(2026, 5, 11),
          currentVersion: '4.5.1',
        ),
        isFalse,
      );
      expect(
        announcement.isActive(
          now: DateTime.utc(2026, 6, 2),
          currentVersion: '4.5.1',
        ),
        isFalse,
      );
      expect(
        announcement.isActive(
          now: DateTime.utc(2026, 6, 2),
          currentVersion: '4.6.0',
        ),
        isTrue,
      );
    });
  });
}
