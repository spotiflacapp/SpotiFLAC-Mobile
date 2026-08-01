// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of 'download_queue_provider.dart';

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

extension _DownloadQueueEmbedding on DownloadQueueNotifier {
  String? _resolveAlbumArtistForMetadata(Track track, AppSettings settings) {
    var albumArtist = normalizeOptionalString(track.albumArtist);
    if (settings.filterContributingArtistsInAlbumArtist) {
      albumArtist = albumArtist == null
          ? null
          : normalizeOptionalString(_extractPrimaryArtist(albumArtist));
    }
    return albumArtist;
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

  /// Returns a known Deezer track ID for [track], or resolves one via ISRC
  /// search. Does not attempt provider-based resolution (see
  /// [_resolveDeezerIdViaProviderIfNeeded]).
  Future<String?> _resolveDeezerIdFromKnownOrIsrc(
    Track track,
    String itemId, {
    required String lookupContext,
  }) async {
    final known = _extractKnownDeezerTrackId(track);
    if (known != null) return known;
    if (track.isrc != null &&
        track.isrc!.isNotEmpty &&
        _isValidISRC(track.isrc!)) {
      return _searchDeezerTrackIdByIsrc(
        track.isrc,
        lookupContext: lookupContext,
        itemId: itemId,
      );
    }
    return null;
  }

  /// For tidal:/qobuz: tracks without a usable ISRC, resolves the ISRC (and
  /// Deezer ID) from the provider API directly. Returns [track] and
  /// [deezerTrackId] unchanged when resolution isn't needed or fails.
  Future<_DeezerLookupPreparation> _resolveDeezerIdViaProviderIfNeeded(
    Track track,
    String? deezerTrackId,
    String itemId,
  ) async {
    if (deezerTrackId == null &&
        (track.isrc == null ||
            track.isrc!.isEmpty ||
            !_isValidISRC(track.isrc!)) &&
        (track.id.startsWith('tidal:') || track.id.startsWith('qobuz:'))) {
      final providerLookup = await _resolveProviderTrackForDeezerLookup(
        track,
        itemId,
      );
      return _DeezerLookupPreparation(
        track: providerLookup.track,
        deezerTrackId: deezerTrackId ?? providerLookup.deezerTrackId,
      );
    }
    return _DeezerLookupPreparation(track: track, deezerTrackId: deezerTrackId);
  }

  /// Loads extended Deezer metadata (genre/label/copyright) for
  /// [deezerTrackId], or returns null when no ID is available.
  Future<_DeezerExtendedMetadataFields?> _loadExtendedMetadataForDeezerId(
    String? deezerTrackId,
  ) {
    if (deezerTrackId == null || deezerTrackId.isEmpty) {
      return Future.value(null);
    }
    return _loadDeezerExtendedMetadata(deezerTrackId);
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
    final backendTrackNum = readPositiveInt(backendResult['track_number']);
    final backendDiscNum = readPositiveInt(backendResult['disc_number']);
    final backendTotalTracks = readPositiveInt(backendResult['total_tracks']);
    final backendTotalDiscs = readPositiveInt(backendResult['total_discs']);
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
  /// Returns the fetched LRC content (when lyrics were fetched) so callers
  /// can reuse it — e.g. the SAF external-.lrc save — without a second
  /// network fetch.
  Future<String?> _embedMetadataToFile(
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
      return null;
    }

    final isFlac = format == 'flac';
    final isM4a = format == 'm4a';
    final isMp3 = format == 'mp3';

    Future<String?>? coverFuture;
    var coverUrl = normalizeRemoteHttpUrl(track.coverUrl);
    if (coverUrl != null && coverUrl.isNotEmpty) {
      if (settings.maxQualityCover) {
        coverUrl = _upgradeToMaxQualityCover(coverUrl);
      }
      // Started here, awaited only after the lyrics fetch below so the two
      // network round trips overlap. Errors are handled inside the fetch
      // (it resolves to null), never as an unhandled rejection.
      coverFuture = _sharedEmbedCover(coverUrl);
    }

    String? lrcContent;
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

      final coverPath = coverFuture == null ? null : await coverFuture;
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
            return lrcContent;
          }
        } catch (e) {
          _log.w('AC-4 metadata path failed, falling back to FFmpeg: $e');
        }
      }

      // Native Go tag writers handle these formats in-process, streaming the
      // audio through untouched — no FFmpeg spawn, no full container remux,
      // no temp-promote copy. The Go side answers method=ffmpeg for files it
      // can't handle natively, and any failure falls back to FFmpeg below.
      // Scanned ReplayGain (opt-in, non-FLAC) keeps the FFmpeg path: its
      // extra tags (e.g. Opus R128_TRACK_GAIN) ride the FFmpeg metadata map.
      var embeddedNatively = false;
      if (scannedReplayGain == null) {
        try {
          final nativeFields = <String, String>{
            'title': track.name,
            'artist': track.artistName,
            'album': track.albumName,
            'artist_tag_mode': settings.artistTagMode,
            'album_artist': ?albumArtist,
            if (track.releaseDate != null) 'date': track.releaseDate!,
            if (track.isrc != null) 'isrc': track.isrc!,
            if (track.composer != null && track.composer!.isNotEmpty)
              'composer': track.composer!,
            if (genre != null && genre.isNotEmpty) 'genre': genre,
            if (label != null && label.isNotEmpty) 'label': label,
            if (copyright != null && copyright.isNotEmpty)
              'copyright': copyright,
            if (track.trackNumber != null && track.trackNumber! > 0)
              'track_number': track.trackNumber!.toString(),
            if (track.totalTracks != null && track.totalTracks! > 0)
              'track_total': track.totalTracks!.toString(),
            if (track.discNumber != null && track.discNumber! > 0)
              'disc_number': track.discNumber!.toString(),
            if (track.totalDiscs != null && track.totalDiscs! > 0)
              'disc_total': track.totalDiscs!.toString(),
            'cover_path': ?validCover,
            if (shouldEmbedLyrics && lrcContent != null) ...{
              'lyrics': lrcContent,
              'unsyncedlyrics': lrcContent,
            } else if ((isFlac || isM4a) && !shouldEmbedLyrics) ...{
              // Mirrors the FFmpeg map: embedding disabled strips lyrics a
              // provider may have pre-embedded (set-or-clear semantics).
              'lyrics': '',
              if (isFlac) 'unsyncedlyrics': '',
            },
          };
          final response = await PlatformBridge.editFileMetadata(
            filePath,
            nativeFields,
          );
          embeddedNatively = response['method'] != 'ffmpeg';
        } catch (e) {
          _log.w('Native $format tag embed failed, falling back to FFmpeg: $e');
        }
      }

      if (embeddedNatively) {
        _log.d('Metadata embedded to $format natively');
      } else {
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
        // The native embed already wrote split tags via artist_tag_mode;
        // this second full-file rewrite is only needed after FFmpeg, whose
        // metadata map can't express repeated ARTIST tags.
        if (!embeddedNatively &&
            settings.artistTagMode == artistTagModeSplitVorbis) {
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
    }
    // The cover file is owned by _embedCoverCache: kept for the next track
    // of the same release, deleted on LRU eviction or when the queue drains.
    return lrcContent;
  }

  static const _embedCoverCacheMax = 8;

  /// One cover fetch per URL, shared by every track in the batch.
  Future<String?> _sharedEmbedCover(String coverUrl) {
    final existing = _embedCoverCache.remove(coverUrl);
    if (existing != null) {
      _embedCoverCache[coverUrl] = existing; // LRU touch
      return existing;
    }
    final fetch = _downloadEmbedCover(coverUrl).then((path) {
      if (path == null) _embedCoverCache.remove(coverUrl); // allow retry
      return path;
    });
    _embedCoverCache[coverUrl] = fetch;
    while (_embedCoverCache.length > _embedCoverCacheMax) {
      _evictEmbedCover(_embedCoverCache.keys.first);
    }
    return fetch;
  }

  Future<String?> _downloadEmbedCover(String coverUrl) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final uniqueId =
          '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
      final coverPath = '${tempDir.path}/cover_embed_$uniqueId.jpg';

      // Go's cover pipeline: shared cache/singleflight, retries, timeouts.
      final result = await PlatformBridge.downloadCoverToFile(
        coverUrl,
        coverPath,
        maxQuality: false,
      );
      if (result['error'] != null) {
        _log.w('Failed to download cover: ${result['error']}');
        return null;
      }
      _log.d('Cover downloaded for embedding: $coverPath');
      return coverPath;
    } catch (e) {
      _log.e('Failed to download cover for embedding: $e');
      return null;
    }
  }

  void _evictEmbedCover(String coverUrl) {
    final pending = _embedCoverCache.remove(coverUrl);
    pending?.then((path) {
      if (path != null) {
        File(path).delete().catchError((_) => File(path));
      }
    });
  }

  void _clearEmbedCoverCache() {
    for (final url in _embedCoverCache.keys.toList()) {
      _evictEmbedCover(url);
    }
  }
}
