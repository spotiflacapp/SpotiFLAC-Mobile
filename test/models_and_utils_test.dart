import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/models/download_item.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/models/theme_settings.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/services/download_request_payload.dart';
import 'package:spotiflac_android/utils/artist_utils.dart';
import 'package:spotiflac_android/utils/mime_utils.dart';
import 'package:spotiflac_android/utils/path_match_keys.dart';
import 'package:spotiflac_android/utils/string_utils.dart';

void main() {
  group('Track', () {
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
        'Rate limit reached, try again later',
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
      expect(item.toJson()['status'], 'failed');
      expect(item.toJson()['errorType'], 'network');
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
      expect(settings.deduplicateDownloads, isTrue);
    });

    test('copyWith updates values and can clear nullable provider fields', () {
      const settings = AppSettings(
        downloadFallbackExtensionIds: ['fallback.ext'],
        searchProvider: 'search.ext',
        homeFeedProvider: 'feed.ext',
      );

      final updated = settings.copyWith(
        defaultService: 'tidal',
        concurrentDownloads: 4,
        embedReplayGain: true,
        lyricsProviders: ['apple_music'],
        deduplicateDownloads: false,
        clearDownloadFallbackExtensionIds: true,
        clearSearchProvider: true,
        clearHomeFeedProvider: true,
      );

      expect(updated.defaultService, 'tidal');
      expect(updated.concurrentDownloads, 4);
      expect(updated.embedReplayGain, isTrue);
      expect(updated.lyricsProviders, ['apple_music']);
      expect(updated.deduplicateDownloads, isFalse);
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
        lastSeenVersion: '4.5.0',
        deduplicateDownloads: false,
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
      expect(decoded.lastSeenVersion, '4.5.0');
      expect(decoded.deduplicateDownloads, isFalse);
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
        trackNumber: 7,
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
        songLinkRegion: 'ID',
      );

      expect(payload.toJson(), {
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
        'track_number': 7,
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
}
