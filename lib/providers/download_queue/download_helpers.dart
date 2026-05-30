// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, invalid_use_of_internal_member
part of '../download_queue_provider.dart';

extension DownloadQueueNotifierHelpers on DownloadQueueNotifier {
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
    return (value ~/ DownloadQueueNotifier._bytesUiStep) * DownloadQueueNotifier._bytesUiStep;
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
    if (_usesBuiltInCompatibleDownloadProvider(service, 'tidal') &&
        quality == 'HIGH') {
      return '.m4a';
    }
    final q = quality.toLowerCase();
    if (q == 'alac' || q.startsWith('aac')) return '.m4a';
    if (q.startsWith('opus')) return '.opus';
    if (q.startsWith('mp3')) return '.mp3';
    return '.flac';
  }

  bool _usesBuiltInCompatibleDownloadProvider(
    String service,
    String builtInProviderId,
  ) {
    return ref
        .read(extensionProvider.notifier)
        .downloadProviderMatchesBuiltIn(service, builtInProviderId);
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

  bool _isValidISRC(String value) {
    return DownloadQueueNotifier._isrcRegex.hasMatch(value.toUpperCase());
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

}
