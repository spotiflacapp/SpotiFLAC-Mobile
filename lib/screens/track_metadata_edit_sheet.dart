part of 'track_metadata_screen.dart';

class _ResolvedAutoFillTrack {
  final Map<String, dynamic> track;
  final String? deezerId;

  const _ResolvedAutoFillTrack({required this.track, this.deezerId});
}

class _EditMetadataSheet extends StatefulWidget {
  static const _onlineCoverSentinel = '__online_cover__';
  final ColorScheme colorScheme;
  final Map<String, String> initialValues;
  final String filePath;
  final String? sourceTrackId;
  final int durationMs;
  final String artistTagMode;

  const _EditMetadataSheet({
    required this.colorScheme,
    required this.initialValues,
    required this.filePath,
    this.sourceTrackId,
    required this.durationMs,
    required this.artistTagMode,
  });

  @override
  State<_EditMetadataSheet> createState() => _EditMetadataSheetState();
}

class _EditMetadataSheetState extends State<_EditMetadataSheet> {
  static final RegExp _metadataCollapsePattern = RegExp(r'[^a-z0-9]+');
  static final RegExp _metadataWhitespacePattern = RegExp(r'\s+');
  static final RegExp _spotifyTrackIdPattern = RegExp(r'^[A-Za-z0-9]{22}$');
  static final RegExp _deezerTrackIdPattern = RegExp(r'^\d+$');
  static final RegExp _isrcPattern = RegExp(r'^[A-Z]{2}[A-Z0-9]{3}\d{7}$');

  bool _saving = false;
  bool _showAdvanced = false;
  bool _showAutoFill = false;
  bool _fetching = false;
  String? _selectedCoverPath;
  String? _selectedCoverTempDir;
  String? _selectedCoverName;
  String? _currentCoverPath;
  String? _currentCoverTempDir;
  bool _loadingCurrentCover = false;

  final Set<String> _autoFillFields = {};

  static const _fieldDefs = <String, String>{
    'title': 'title',
    'artist': 'artist',
    'album': 'album',
    'album_artist': 'album_artist',
    'date': 'date',
    'track_number': 'track_number',
    'total_tracks': 'total_tracks',
    'disc_number': 'disc_number',
    'total_discs': 'total_discs',
    'genre': 'genre',
    'isrc': 'isrc',
    'lyrics': 'lyrics',
    'label': 'label',
    'copyright': 'copyright',
    'composer': 'composer',
    'cover': 'cover',
  };

  late final TextEditingController _titleCtrl;
  late final TextEditingController _artistCtrl;
  late final TextEditingController _albumCtrl;
  late final TextEditingController _albumArtistCtrl;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _trackNumCtrl;
  late final TextEditingController _trackTotalCtrl;
  late final TextEditingController _discNumCtrl;
  late final TextEditingController _discTotalCtrl;
  late final TextEditingController _genreCtrl;
  late final TextEditingController _isrcCtrl;
  late final TextEditingController _lyricsCtrl;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _copyrightCtrl;
  late final TextEditingController _composerCtrl;
  late final TextEditingController _commentCtrl;

  bool _hasValue(String? value) => value != null && value.trim().isNotEmpty;

  String _resolveImageExtension(String? ext, Uint8List? bytes) {
    final normalized = (ext ?? '').toLowerCase();
    if (normalized == 'png' ||
        normalized == 'jpg' ||
        normalized == 'jpeg' ||
        normalized == 'webp') {
      return normalized == 'jpeg' ? 'jpg' : normalized;
    }
    if (bytes != null && bytes.length >= 8) {
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return 'png';
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return 'jpg';
      }
      if (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return 'webp';
      }
    }
    return 'jpg';
  }

  Future<void> _cleanupSelectedCoverTemp() async {
    final dirPath = _selectedCoverTempDir;
    _selectedCoverPath = null;
    _selectedCoverTempDir = null;
    _selectedCoverName = null;
    if (dirPath == null || dirPath.isEmpty) return;
    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _cleanupCurrentCoverTemp() async {
    final dirPath = _currentCoverTempDir;
    _currentCoverPath = null;
    _currentCoverTempDir = null;
    if (dirPath == null || dirPath.isEmpty) return;
    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _loadCurrentCoverPreview() async {
    if (_loadingCurrentCover) return;
    setState(() => _loadingCurrentCover = true);
    String? newCoverPath;
    String? newCoverDir;
    try {
      final tempDir = await Directory.systemTemp.createTemp(
        'edit_existing_cover_',
      );
      final coverOutput =
          '${tempDir.path}${Platform.pathSeparator}existing_cover.jpg';
      final coverResult = await PlatformBridge.extractCoverToFile(
        widget.filePath,
        coverOutput,
      );
      if (coverResult['error'] == null && await File(coverOutput).exists()) {
        newCoverPath = coverOutput;
        newCoverDir = tempDir.path;
      } else {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}

    if (!mounted) {
      if (newCoverDir != null) {
        try {
          final dir = Directory(newCoverDir);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        } catch (_) {}
      }
      return;
    }

    final oldDir = _currentCoverTempDir;
    setState(() {
      _currentCoverPath = newCoverPath;
      _currentCoverTempDir = newCoverDir;
      _loadingCurrentCover = false;
    });
    if (oldDir != null && oldDir.isNotEmpty && oldDir != newCoverDir) {
      try {
        final dir = Directory(oldDir);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<void> _pickCoverImage() async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      if (picked == null) return;

      final sourcePath = picked.path;
      Uint8List? bytes;
      final needsByteFallback =
          !_hasValue(sourcePath) && !_hasValue(picked.extension);
      if (needsByteFallback) {
        bytes = await picked.readAsBytes();
      }
      final extension = _resolveImageExtension(picked.extension, bytes);

      final tempDir = await Directory.systemTemp.createTemp('edit_cover_');
      final tempPath =
          '${tempDir.path}${Platform.pathSeparator}cover.$extension';

      if (sourcePath != null && sourcePath.isNotEmpty) {
        final sourceFile = File(sourcePath);
        if (!await sourceFile.exists()) {
          throw Exception('Selected image is not accessible');
        }
        await sourceFile.copy(tempPath);
      } else if (bytes != null && bytes.isNotEmpty) {
        await File(tempPath).writeAsBytes(bytes, flush: true);
      } else {
        throw Exception('Unable to read selected image');
      }

      await _cleanupSelectedCoverTemp();
      if (!mounted) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
        return;
      }
      setState(() {
        _selectedCoverPath = tempPath;
        _selectedCoverTempDir = tempDir.path;
        _selectedCoverName = picked.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.snackbarError(e.toString()))),
      );
    }
  }

  String _fieldLabel(String key) {
    final l10n = context.l10n;
    switch (key) {
      case 'title':
        return l10n.editMetadataFieldTitle;
      case 'artist':
        return l10n.editMetadataFieldArtist;
      case 'album':
        return l10n.editMetadataFieldAlbum;
      case 'album_artist':
        return l10n.editMetadataFieldAlbumArtist;
      case 'date':
        return l10n.editMetadataFieldDate;
      case 'track_number':
        return l10n.editMetadataFieldTrackNum;
      case 'total_tracks':
        return l10n.editMetadataFieldTrackTotal;
      case 'disc_number':
        return l10n.editMetadataFieldDiscNum;
      case 'total_discs':
        return l10n.editMetadataFieldDiscTotal;
      case 'genre':
        return l10n.editMetadataFieldGenre;
      case 'isrc':
        return l10n.editMetadataFieldIsrc;
      case 'lyrics':
        return l10n.trackLyrics;
      case 'label':
        return l10n.editMetadataFieldLabel;
      case 'copyright':
        return l10n.editMetadataFieldCopyright;
      case 'composer':
        return l10n.editMetadataFieldComposer;
      case 'cover':
        return l10n.editMetadataFieldCover;
      default:
        return key;
    }
  }

  TextEditingController? _controllerForKey(String key) {
    switch (key) {
      case 'title':
        return _titleCtrl;
      case 'artist':
        return _artistCtrl;
      case 'album':
        return _albumCtrl;
      case 'album_artist':
        return _albumArtistCtrl;
      case 'date':
        return _dateCtrl;
      case 'track_number':
        return _trackNumCtrl;
      case 'total_tracks':
        return _trackTotalCtrl;
      case 'disc_number':
        return _discNumCtrl;
      case 'total_discs':
        return _discTotalCtrl;
      case 'genre':
        return _genreCtrl;
      case 'isrc':
        return _isrcCtrl;
      case 'lyrics':
        return _lyricsCtrl;
      case 'label':
        return _labelCtrl;
      case 'copyright':
        return _copyrightCtrl;
      case 'composer':
        return _composerCtrl;
      default:
        return null;
    }
  }

  void _selectAllFields() {
    setState(() {
      _autoFillFields.addAll(_fieldDefs.keys);
    });
  }

  void _selectEmptyFields() {
    setState(() {
      _autoFillFields.clear();
      for (final key in _fieldDefs.keys) {
        if (key == 'cover') {
          if (!_hasValue(_currentCoverPath) && !_hasValue(_selectedCoverPath)) {
            _autoFillFields.add(key);
          }
          continue;
        }
        final ctrl = _controllerForKey(key);
        if (ctrl != null && ctrl.text.trim().isEmpty) {
          _autoFillFields.add(key);
        }
      }
    });
  }

  void _selectNoFields() {
    setState(_autoFillFields.clear);
  }

  String _normalizeMetadataText(String value) {
    final collapsed = value
        .toLowerCase()
        .replaceAll(_metadataCollapsePattern, ' ')
        .trim();
    return collapsed.replaceAll(_metadataWhitespacePattern, ' ');
  }

  bool _looksLikeIsrc(String value) {
    return _isrcPattern.hasMatch(value.trim().toUpperCase());
  }

  String? _extractRawSpotifyTrackIdFromValue(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;

    if (_spotifyTrackIdPattern.hasMatch(raw)) {
      return raw;
    }

    if (raw.startsWith('spotify:')) {
      final parts = raw.split(':');
      final last = parts.isNotEmpty ? parts.last.trim() : '';
      if (_spotifyTrackIdPattern.hasMatch(last)) {
        return last;
      }
      return null;
    }

    final uri = Uri.tryParse(raw);
    if (uri != null &&
        uri.host.contains('spotify.com') &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'track') {
      final candidate = uri.pathSegments[1].trim();
      if (_spotifyTrackIdPattern.hasMatch(candidate)) {
        return candidate;
      }
    }

    return null;
  }

  String? _extractRawDeezerTrackIdFromValue(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;

    if (_deezerTrackIdPattern.hasMatch(raw)) {
      return raw;
    }

    if (raw.startsWith('deezer:')) {
      final parts = raw.split(':');
      final last = parts.isNotEmpty ? parts.last.trim() : '';
      if (_deezerTrackIdPattern.hasMatch(last)) {
        return last;
      }
    }

    final uri = Uri.tryParse(raw);
    if (uri != null && uri.host.contains('deezer.com')) {
      final trackIndex = uri.pathSegments.indexOf('track');
      if (trackIndex >= 0 && trackIndex + 1 < uri.pathSegments.length) {
        final candidate = uri.pathSegments[trackIndex + 1].trim();
        if (_deezerTrackIdPattern.hasMatch(candidate)) {
          return candidate;
        }
      }
    }

    return null;
  }

  String? _extractRawSpotifyTrackId(Map<String, dynamic> track) {
    for (final candidate in [track['spotify_id'], track['id']]) {
      final spotifyId = _extractRawSpotifyTrackIdFromValue(candidate);
      if (spotifyId != null) return spotifyId;
    }

    final externalLinks = track['external_links'];
    if (externalLinks is Map) {
      final spotifyId = _extractRawSpotifyTrackIdFromValue(
        externalLinks['spotify'],
      );
      if (spotifyId != null) return spotifyId;
    }

    return null;
  }

  String? _extractRawDeezerTrackId(Map<String, dynamic> track) {
    for (final candidate in [
      track['deezer_id'],
      track['spotify_id'],
      track['id'],
    ]) {
      final deezerId = _extractRawDeezerTrackIdFromValue(candidate);
      if (deezerId != null) return deezerId;
    }

    final externalLinks = track['external_links'];
    if (externalLinks is Map) {
      final deezerId = _extractRawDeezerTrackIdFromValue(
        externalLinks['deezer'],
      );
      if (deezerId != null) return deezerId;
    }

    return null;
  }

  Map<String, dynamic> _unwrapTrackPayload(Map<String, dynamic> payload) {
    final track = payload['track'];
    if (track is Map<String, dynamic>) {
      return track;
    }
    return payload;
  }

  void _mergeOnlineTrackData(
    Map<String, String> enriched,
    Map<String, dynamic> track,
  ) {
    void put(String key, Object? value) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null') {
        enriched[key] = text;
      }
    }

    put('title', track['name'] ?? track['title']);
    put('artist', track['artists'] ?? track['artist']);
    put('album', track['album_name'] ?? track['album']);
    put('album_artist', track['album_artist']);
    put('date', track['release_date']);
    put('track_number', track['track_number']);
    put('total_tracks', track['total_tracks']);
    put('disc_number', track['disc_number']);
    put('total_discs', track['total_discs']);
    put('isrc', track['isrc']);
    put('genre', track['genre']);
    put('label', track['label']);
    put('copyright', track['copyright']);
    put('composer', track['composer']);
  }

  Future<_ResolvedAutoFillTrack?> _resolveAutoFillTrackFromIdentifiers(
    String currentIsrc,
  ) async {
    if (_looksLikeIsrc(currentIsrc)) {
      final deezerTrack = await PlatformBridge.searchDeezerByISRC(currentIsrc);
      return _ResolvedAutoFillTrack(
        track: _unwrapTrackPayload(deezerTrack),
        deezerId: _extractRawDeezerTrackId(deezerTrack),
      );
    }

    final sourceTrackId = widget.sourceTrackId?.trim() ?? '';
    if (sourceTrackId.isEmpty) {
      return null;
    }

    final deezerId = _extractRawDeezerTrackIdFromValue(sourceTrackId);
    if (deezerId != null) {
      final deezerTrack = await PlatformBridge.getProviderMetadata(
        'deezer',
        'track',
        deezerId,
      );
      return _ResolvedAutoFillTrack(
        track: _unwrapTrackPayload(deezerTrack),
        deezerId: deezerId,
      );
    }

    final spotifyId = _extractRawSpotifyTrackIdFromValue(sourceTrackId);
    if (spotifyId != null) {
      final deezerTrack = await PlatformBridge.convertSpotifyToDeezer(
        'track',
        spotifyId,
      );
      final track = _unwrapTrackPayload(deezerTrack);
      return _ResolvedAutoFillTrack(
        track: track,
        deezerId:
            _extractRawDeezerTrackId(track) ??
            _extractRawDeezerTrackId(deezerTrack),
      );
    }

    return null;
  }

  int _metadataMatchScore(
    Map<String, dynamic> track, {
    required String currentTitle,
    required String currentArtist,
    required String currentAlbum,
    required String currentIsrc,
  }) {
    var score = 0;

    final candidateIsrc = (track['isrc']?.toString() ?? '')
        .trim()
        .toUpperCase();
    if (currentIsrc.isNotEmpty && candidateIsrc == currentIsrc) {
      score += 10000;
    }

    final candidateTitle = _normalizeMetadataText(
      (track['name'] ?? track['title'] ?? '').toString(),
    );
    final candidateArtist = _normalizeMetadataText(
      (track['artists'] ?? track['artist'] ?? '').toString(),
    );
    final candidateAlbum = _normalizeMetadataText(
      (track['album_name'] ?? track['album'] ?? '').toString(),
    );

    if (currentTitle.isNotEmpty && candidateTitle.isNotEmpty) {
      if (candidateTitle == currentTitle) {
        score += 400;
      } else if (candidateTitle.contains(currentTitle) ||
          currentTitle.contains(candidateTitle)) {
        score += 180;
      }
    }

    if (currentArtist.isNotEmpty && candidateArtist.isNotEmpty) {
      if (candidateArtist == currentArtist) {
        score += 320;
      } else if (candidateArtist.contains(currentArtist) ||
          currentArtist.contains(candidateArtist)) {
        score += 140;
      }
    }

    if (currentAlbum.isNotEmpty && candidateAlbum.isNotEmpty) {
      if (candidateAlbum == currentAlbum) {
        score += 120;
      } else if (candidateAlbum.contains(currentAlbum) ||
          currentAlbum.contains(candidateAlbum)) {
        score += 50;
      }
    }

    return score;
  }

  bool _metadataTextMatches(String current, String candidate) {
    if (current.isEmpty || candidate.isEmpty) return false;
    return current == candidate ||
        candidate.contains(current) ||
        current.contains(candidate);
  }

  bool _metadataMatchIsConfident(
    Map<String, dynamic> track, {
    required String currentTitle,
    required String currentArtist,
    required String currentAlbum,
    required String currentIsrc,
  }) {
    final candidateIsrc = (track['isrc']?.toString() ?? '')
        .trim()
        .toUpperCase();
    if (currentIsrc.isNotEmpty && candidateIsrc == currentIsrc) {
      return true;
    }

    final candidateTitle = _normalizeMetadataText(
      (track['name'] ?? track['title'] ?? '').toString(),
    );
    final candidateArtist = _normalizeMetadataText(
      (track['artists'] ?? track['artist'] ?? '').toString(),
    );
    final candidateAlbum = _normalizeMetadataText(
      (track['album_name'] ?? track['album'] ?? '').toString(),
    );

    final titleMatches = _metadataTextMatches(currentTitle, candidateTitle);
    final artistMatches = _metadataTextMatches(currentArtist, candidateArtist);
    final albumMatches = _metadataTextMatches(currentAlbum, candidateAlbum);

    if (currentTitle.isNotEmpty && currentArtist.isNotEmpty) {
      return titleMatches && artistMatches;
    }
    if (currentTitle.isNotEmpty && currentAlbum.isNotEmpty) {
      return titleMatches && albumMatches;
    }
    if (currentTitle.isNotEmpty) {
      return titleMatches;
    }
    if (currentAlbum.isNotEmpty) {
      return albumMatches;
    }

    return false;
  }

  Future<void> _fetchAndFill() async {
    if (_autoFillFields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.editMetadataAutoFillNoneSelected)),
      );
      return;
    }

    setState(() => _fetching = true);

    try {
      final title = _titleCtrl.text.trim();
      final artist = _artistCtrl.text.trim();
      final album = _albumCtrl.text.trim();
      final currentIsrc = _isrcCtrl.text.trim().toUpperCase();
      final shouldFetchLyrics = _autoFillFields.contains('lyrics');
      final needsTrackLookup = _autoFillFields.any((key) => key != 'lyrics');
      Map<String, dynamic>? best;
      String? deezerId;

      if (needsTrackLookup) {
        try {
          final resolved = await _resolveAutoFillTrackFromIdentifiers(
            currentIsrc,
          );
          if (resolved != null) {
            best = resolved.track;
            deezerId = resolved.deezerId;
          }
        } catch (e) {
          _log.w('Identifier-first autofill lookup failed: $e');
        }
      }

      final queryParts = <String>[];
      if (title.isNotEmpty) queryParts.add(title);
      if (artist.isNotEmpty) queryParts.add(artist);
      if (queryParts.isEmpty && album.isNotEmpty) queryParts.add(album);

      if (needsTrackLookup && best == null && queryParts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.editMetadataAutoFillNoResults)),
          );
        }
        return;
      }

      final normalizedTitle = _normalizeMetadataText(title);
      final normalizedArtist = _normalizeMetadataText(artist);
      final normalizedAlbum = _normalizeMetadataText(album);

      if (needsTrackLookup && best == null) {
        final query = queryParts.join(' ');
        final results = await PlatformBridge.searchTracksWithMetadataProviders(
          query,
          limit: 5,
        );

        if (!mounted) return;

        if (results.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.editMetadataAutoFillNoResults)),
          );
          return;
        }

        // Pick best match using current metadata, not only provider order.
        best = results.first;
        var bestScore = -1;
        for (final result in results) {
          final score = _metadataMatchScore(
            result,
            currentTitle: normalizedTitle,
            currentArtist: normalizedArtist,
            currentAlbum: normalizedAlbum,
            currentIsrc: currentIsrc,
          );
          if (score > bestScore) {
            bestScore = score;
            best = result;
          }
        }

        if (best != null &&
            !_metadataMatchIsConfident(
              best,
              currentTitle: normalizedTitle,
              currentArtist: normalizedArtist,
              currentAlbum: normalizedAlbum,
              currentIsrc: currentIsrc,
            )) {
          best = null;
        }

        if (best == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.editMetadataAutoFillNoResults)),
          );
          return;
        }
      }

      final selectedBest = best;
      if (needsTrackLookup && selectedBest == null) {
        throw StateError('No metadata match resolved for auto-fill');
      }

      final enriched = <String, String>{};
      if (selectedBest != null) {
        enriched.addAll(<String, String>{
          'title': (selectedBest['name'] ?? '').toString(),
          'artist': (selectedBest['artists'] ?? selectedBest['artist'] ?? '')
              .toString(),
          'album': (selectedBest['album_name'] ?? selectedBest['album'] ?? '')
              .toString(),
          'album_artist': (selectedBest['album_artist'] ?? '').toString(),
          'date': (selectedBest['release_date'] ?? '').toString(),
          'track_number': (selectedBest['track_number'] ?? '').toString(),
          'total_tracks': (selectedBest['total_tracks'] ?? '').toString(),
          'disc_number': (selectedBest['disc_number'] ?? '').toString(),
          'total_discs': (selectedBest['total_discs'] ?? '').toString(),
          'isrc': (selectedBest['isrc'] ?? '').toString(),
          'composer': (selectedBest['composer'] ?? '').toString(),
        });
        _mergeOnlineTrackData(enriched, selectedBest);
      }

      final enrichedIsrc = (enriched['isrc'] ?? '').trim();
      final needsIsrc =
          _autoFillFields.contains('isrc') && enrichedIsrc.isEmpty;
      final needsExtended =
          _autoFillFields.contains('genre') ||
          _autoFillFields.contains('label') ||
          _autoFillFields.contains('copyright') ||
          _autoFillFields.contains('composer');

      final rawSpotifyId = selectedBest == null
          ? _extractRawSpotifyTrackIdFromValue(widget.sourceTrackId)
          : _extractRawSpotifyTrackId(selectedBest);

      deezerId ??= selectedBest == null
          ? null
          : _extractRawDeezerTrackId(selectedBest);
      final candidateIsrc = enrichedIsrc.toUpperCase();
      final deezerLookupIsrc = _looksLikeIsrc(currentIsrc)
          ? currentIsrc
          : (_looksLikeIsrc(candidateIsrc) ? candidateIsrc : '');

      if (needsIsrc || needsExtended) {
        try {
          if (deezerId == null && deezerLookupIsrc.isNotEmpty) {
            final deezerResult = await PlatformBridge.searchDeezerByISRC(
              deezerLookupIsrc,
            );
            deezerId = _extractRawDeezerTrackId(deezerResult);
            _mergeOnlineTrackData(enriched, deezerResult);
          }

          if (deezerId == null && rawSpotifyId != null) {
            // Spotify IDs can be mapped through SongLink to a Deezer track.
            final deezerData = await PlatformBridge.convertSpotifyToDeezer(
              'track',
              rawSpotifyId,
            );
            final trackData = deezerData['track'];
            if (trackData is Map<String, dynamic>) {
              deezerId = _extractRawDeezerTrackId(trackData);
              _mergeOnlineTrackData(enriched, trackData);
            }
            deezerId ??= _extractRawDeezerTrackId(deezerData);
          }
        } catch (_) {
          // Deezer resolution is best-effort
        }
      }

      if (!mounted) return;

      if (needsIsrc &&
          (enriched['isrc'] ?? '').trim().isEmpty &&
          deezerId != null) {
        try {
          final deezerMeta = await PlatformBridge.getProviderMetadata(
            'deezer',
            'track',
            deezerId,
          );
          final trackData = _unwrapTrackPayload(deezerMeta);
          _mergeOnlineTrackData(enriched, trackData);
          final deezerIsrc = (trackData['isrc'] ?? '').toString().trim();
          if (deezerIsrc.isNotEmpty) {
            enriched['isrc'] = deezerIsrc;
          }
        } catch (_) {}
      }

      if (!mounted) return;

      if (needsExtended && deezerId != null) {
        try {
          final extended = await PlatformBridge.getDeezerExtendedMetadata(
            deezerId,
          );
          if (extended != null) {
            enriched['genre'] = extended['genre'] ?? '';
            enriched['label'] = extended['label'] ?? '';
            enriched['copyright'] = extended['copyright'] ?? '';
          }
        } catch (_) {
          // Extended metadata is best-effort
        }
      }

      if (shouldFetchLyrics) {
        final lyricsTitle =
            ((selectedBest?['name'] ?? selectedBest?['title'] ?? title)
                    .toString())
                .trim();
        final lyricsArtist =
            ((selectedBest?['artists'] ?? selectedBest?['artist'] ?? artist)
                    .toString())
                .trim();

        if (lyricsTitle.isNotEmpty && lyricsArtist.isNotEmpty) {
          try {
            final lyricsResult = await PlatformBridge.getLyricsLRCWithSource(
              rawSpotifyId ?? '',
              lyricsTitle,
              lyricsArtist,
              durationMs: widget.durationMs,
            );
            final lyricsText = lyricsResult['lyrics']?.toString().trim() ?? '';
            final instrumental =
                (lyricsResult['instrumental'] as bool? ?? false) ||
                lyricsText == '[instrumental:true]';
            if (!instrumental && lyricsText.isNotEmpty) {
              enriched['lyrics'] = lyricsText;
            }
          } catch (e) {
            _log.w('Lyrics autofill failed: $e');
          }
        }
      }

      if (!mounted) return;

      var filledCount = 0;
      for (final key in _autoFillFields) {
        if (key == 'cover') continue;
        final value = enriched[key];
        if (value != null &&
            value.isNotEmpty &&
            value != '0' &&
            value != 'null') {
          final ctrl = _controllerForKey(key);
          if (ctrl != null) {
            ctrl.text = value;
            filledCount++;
          }
        }
      }

      if (_autoFillFields.contains('cover') && selectedBest != null) {
        final coverUrl =
            (selectedBest['cover_url'] ?? selectedBest['images'] ?? '')
                .toString();
        if (coverUrl.isNotEmpty) {
          try {
            final tempDir = await Directory.systemTemp.createTemp(
              'autofill_cover_',
            );
            final coverOutput =
                '${tempDir.path}${Platform.pathSeparator}cover.jpg';
            final response = await HttpClient()
                .getUrl(Uri.parse(coverUrl))
                .then((req) => req.close());
            final file = File(coverOutput);
            final sink = file.openWrite();
            await response.pipe(sink);
            if (await file.exists() && await file.length() > 0) {
              await _cleanupSelectedCoverTemp();
              if (mounted) {
                setState(() {
                  _selectedCoverPath = coverOutput;
                  _selectedCoverTempDir = tempDir.path;
                  _selectedCoverName = _EditMetadataSheet._onlineCoverSentinel;
                });
                filledCount++;
              }
            } else {
              try {
                await tempDir.delete(recursive: true);
              } catch (_) {}
            }
          } catch (_) {
            // Cover download is best-effort
          }
        }
      }

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              filledCount > 0
                  ? context.l10n.editMetadataAutoFillDone(filledCount)
                  : context.l10n.editMetadataAutoFillNoResults,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.snackbarError(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final v = widget.initialValues;
    _titleCtrl = TextEditingController(text: v['title'] ?? '');
    _artistCtrl = TextEditingController(text: v['artist'] ?? '');
    _albumCtrl = TextEditingController(text: v['album'] ?? '');
    _albumArtistCtrl = TextEditingController(text: v['album_artist'] ?? '');
    _dateCtrl = TextEditingController(text: v['date'] ?? '');
    _trackNumCtrl = TextEditingController(text: v['track_number'] ?? '');
    _trackTotalCtrl = TextEditingController(text: v['total_tracks'] ?? '');
    _discNumCtrl = TextEditingController(text: v['disc_number'] ?? '');
    _discTotalCtrl = TextEditingController(text: v['total_discs'] ?? '');
    _genreCtrl = TextEditingController(text: v['genre'] ?? '');
    _isrcCtrl = TextEditingController(text: v['isrc'] ?? '');
    _lyricsCtrl = TextEditingController(text: v['lyrics'] ?? '');
    _labelCtrl = TextEditingController(text: v['label'] ?? '');
    _copyrightCtrl = TextEditingController(text: v['copyright'] ?? '');
    _composerCtrl = TextEditingController(text: v['composer'] ?? '');
    _commentCtrl = TextEditingController(text: v['comment'] ?? '');
    _loadCurrentCoverPreview();
  }

  @override
  void dispose() {
    unawaited(_cleanupSelectedCoverTemp());
    unawaited(_cleanupCurrentCoverTemp());
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _albumArtistCtrl.dispose();
    _dateCtrl.dispose();
    _trackNumCtrl.dispose();
    _trackTotalCtrl.dispose();
    _discNumCtrl.dispose();
    _discTotalCtrl.dispose();
    _genreCtrl.dispose();
    _isrcCtrl.dispose();
    _lyricsCtrl.dispose();
    _labelCtrl.dispose();
    _copyrightCtrl.dispose();
    _composerCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final metadata = <String, String>{
      'title': _titleCtrl.text,
      'artist': _artistCtrl.text,
      'album': _albumCtrl.text,
      'album_artist': _albumArtistCtrl.text,
      'date': _dateCtrl.text,
      'track_number': _trackNumCtrl.text,
      'track_total': _trackTotalCtrl.text,
      'disc_number': _discNumCtrl.text,
      'disc_total': _discTotalCtrl.text,
      'genre': _genreCtrl.text,
      'isrc': _isrcCtrl.text,
      'lyrics': _lyricsCtrl.text,
      'label': _labelCtrl.text,
      'copyright': _copyrightCtrl.text,
      'composer': _composerCtrl.text,
      'comment': _commentCtrl.text,
      'cover_path': _selectedCoverPath ?? '',
      'artist_tag_mode': widget.artistTagMode,
    };

    try {
      final result = await PlatformBridge.editFileMetadata(
        widget.filePath,
        metadata,
      );

      if (result['error'] != null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('${result['error']}')));
        }
        setState(() => _saving = false);
        return;
      }

      final method = result['method'] as String?;

      if (method == 'ffmpeg') {
        // For SAF files, Kotlin returns temp_path + saf_uri
        final tempPath = result['temp_path'] as String?;
        final safUri = result['saf_uri'] as String?;
        final ffmpegTarget = tempPath ?? widget.filePath;

        final lower = widget.filePath.toLowerCase();
        final isMp3 = lower.endsWith('.mp3');
        final isOpus = lower.endsWith('.opus') || lower.endsWith('.ogg');
        final isM4A = lower.endsWith('.m4a') || lower.endsWith('.aac');

        // Always include all known fields so -map_metadata 0 + explicit
        // -metadata flags can both preserve custom tags AND clear fields
        // the user emptied.
        final vorbisMap = <String, String>{
          'TITLE': metadata['title'] ?? '',
          'ARTIST': metadata['artist'] ?? '',
          'ALBUM': metadata['album'] ?? '',
          'ALBUMARTIST': metadata['album_artist'] ?? '',
          'DATE': metadata['date'] ?? '',
          'TRACKNUMBER':
              (metadata['track_number']?.isNotEmpty == true &&
                  metadata['track_number'] != '0')
              ? (metadata['track_total']?.isNotEmpty == true &&
                        metadata['track_total'] != '0'
                    ? '${metadata['track_number']}/${metadata['track_total']}'
                    : metadata['track_number']!)
              : '',
          'DISCNUMBER':
              (metadata['disc_number']?.isNotEmpty == true &&
                  metadata['disc_number'] != '0')
              ? (metadata['disc_total']?.isNotEmpty == true &&
                        metadata['disc_total'] != '0'
                    ? '${metadata['disc_number']}/${metadata['disc_total']}'
                    : metadata['disc_number']!)
              : '',
          'GENRE': metadata['genre'] ?? '',
          'ISRC': metadata['isrc'] ?? '',
          'LYRICS': metadata['lyrics'] ?? '',
          'UNSYNCEDLYRICS': metadata['lyrics'] ?? '',
          'ORGANIZATION': metadata['label'] ?? '',
          'COPYRIGHT': metadata['copyright'] ?? '',
          'COMPOSER': metadata['composer'] ?? '',
          'COMMENT': metadata['comment'] ?? '',
        };
        try {
          final existingMetadata = await PlatformBridge.readFileMetadata(
            ffmpegTarget,
          );
          // Preserve ReplayGain tags if present — these are computed once
          // during download and should survive manual metadata edits.
          final rgFields = <String, String>{
            'REPLAYGAIN_TRACK_GAIN':
                existingMetadata['replaygain_track_gain']?.toString() ?? '',
            'REPLAYGAIN_TRACK_PEAK':
                existingMetadata['replaygain_track_peak']?.toString() ?? '',
            'REPLAYGAIN_ALBUM_GAIN':
                existingMetadata['replaygain_album_gain']?.toString() ?? '',
            'REPLAYGAIN_ALBUM_PEAK':
                existingMetadata['replaygain_album_peak']?.toString() ?? '',
          };
          rgFields.forEach((key, value) {
            if (value.isNotEmpty) {
              vorbisMap[key] = value;
            }
          });
        } catch (_) {
          // Lyrics/ReplayGain preservation is best-effort.
        }

        String? existingCoverPath = _selectedCoverPath ?? _currentCoverPath;
        String? extractedCoverPath;
        if (existingCoverPath == null || existingCoverPath.isEmpty) {
          // Preserve current embedded cover when user does not pick a new one.
          try {
            final tempDir = await Directory.systemTemp.createTemp('cover_');
            final coverOutput =
                '${tempDir.path}${Platform.pathSeparator}cover.jpg';
            final coverResult = await PlatformBridge.extractCoverToFile(
              ffmpegTarget,
              coverOutput,
            );
            if (coverResult['error'] == null) {
              existingCoverPath = coverOutput;
              extractedCoverPath = coverOutput;
            } else {
              try {
                await tempDir.delete(recursive: true);
              } catch (_) {}
            }
          } catch (_) {}
        }

        String? ffmpegResult;
        if (isMp3) {
          ffmpegResult = await FFmpegService.embedMetadataToMp3(
            mp3Path: ffmpegTarget,
            coverPath: existingCoverPath,
            metadata: vorbisMap,
            preserveMetadata: true,
          );
        } else if (isM4A) {
          ffmpegResult = await FFmpegService.embedMetadataToM4a(
            m4aPath: ffmpegTarget,
            coverPath: existingCoverPath,
            metadata: vorbisMap,
            preserveMetadata: true,
          );
        } else if (isOpus) {
          ffmpegResult = await FFmpegService.embedMetadataToOpus(
            opusPath: ffmpegTarget,
            coverPath: existingCoverPath,
            metadata: vorbisMap,
            artistTagMode: widget.artistTagMode,
            preserveMetadata: true,
          );
        }

        // Cleanup extracted temp cover (manual selected cover is cleaned on dispose)
        if (extractedCoverPath != null && extractedCoverPath.isNotEmpty) {
          final extractedFile = File(extractedCoverPath);
          try {
            await extractedFile.delete();
          } catch (_) {}
          try {
            final dir = extractedFile.parent;
            if (await dir.exists()) {
              await dir.delete(recursive: true);
            }
          } catch (_) {}
        }

        if (ffmpegResult == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.metadataSaveFailedFfmpeg)),
            );
          }
          setState(() => _saving = false);
          return;
        }

        if (tempPath != null && safUri != null) {
          final ok = await PlatformBridge.writeTempToSaf(ffmpegResult, safUri);
          if (!ok && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.metadataSaveFailedStorage)),
            );
            setState(() => _saving = false);
            return;
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.snackbarError(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.trackEditMetadata,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_saving)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(context.l10n.dialogSave),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                children: [
                  _buildCoverEditor(cs),
                  _buildAutoFillSection(cs),
                  _sectionCard(
                    icon: Icons.info_outline,
                    title: context.l10n.trackMetadata,
                    children: [
                      _field(context.l10n.editMetadataFieldTitle, _titleCtrl),
                      _field(
                        context.l10n.editMetadataFieldArtist,
                        _artistCtrl,
                      ),
                      _field(context.l10n.editMetadataFieldAlbum, _albumCtrl),
                      _field(
                        context.l10n.editMetadataFieldAlbumArtist,
                        _albumArtistCtrl,
                      ),
                      _field(
                        context.l10n.editMetadataFieldDate,
                        _dateCtrl,
                        hint: context.l10n.editMetadataFieldDateHint,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              context.l10n.editMetadataFieldTrackNum,
                              _trackNumCtrl,
                              keyboard: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              context.l10n.editMetadataFieldTrackTotal,
                              _trackTotalCtrl,
                              keyboard: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              context.l10n.editMetadataFieldDiscNum,
                              _discNumCtrl,
                              keyboard: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              context.l10n.editMetadataFieldDiscTotal,
                              _discTotalCtrl,
                              keyboard: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      _field(context.l10n.editMetadataFieldGenre, _genreCtrl),
                      _field(context.l10n.editMetadataFieldIsrc, _isrcCtrl),
                    ],
                  ),
                  _sectionCard(
                    icon: Icons.lyrics_outlined,
                    title: context.l10n.trackLyrics,
                    children: [
                      _field(
                        context.l10n.trackLyrics,
                        _lyricsCtrl,
                        maxLines: 8,
                        keyboard: TextInputType.multiline,
                      ),
                    ],
                  ),
                  _sectionCard(
                    icon: Icons.tune,
                    title: context.l10n.editMetadataAdvanced,
                    onHeaderTap: () =>
                        setState(() => _showAdvanced = !_showAdvanced),
                    expanded: _showAdvanced,
                    children: [
                      if (_showAdvanced) ...[
                        _field(
                          context.l10n.editMetadataFieldLabel,
                          _labelCtrl,
                        ),
                        _field(
                          context.l10n.editMetadataFieldCopyright,
                          _copyrightCtrl,
                        ),
                        _field(
                          context.l10n.editMetadataFieldComposer,
                          _composerCtrl,
                        ),
                        _field(
                          context.l10n.editMetadataFieldComment,
                          _commentCtrl,
                          maxLines: 3,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoFillSection(ColorScheme cs) {
    return _sectionCard(
      icon: Icons.travel_explore,
      title: context.l10n.editMetadataAutoFill,
      onHeaderTap: () => setState(() => _showAutoFill = !_showAutoFill),
      expanded: _showAutoFill,
      children: [
        if (_showAutoFill) ...[
          Text(
            context.l10n.editMetadataAutoFillDesc,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _quickSelectButton(
                label: context.l10n.editMetadataSelectAll,
                onTap: _selectAllFields,
                cs: cs,
              ),
              const SizedBox(width: 8),
              _quickSelectButton(
                label: context.l10n.editMetadataSelectEmpty,
                onTap: _selectEmptyFields,
                cs: cs,
              ),
              const SizedBox(width: 8),
              _quickSelectButton(
                label: context.l10n.editMetadataSelectNone,
                onTap: _selectNoFields,
                cs: cs,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _fieldDefs.keys.map((key) {
              final selected = _autoFillFields.contains(key);
              return FilterChip(
                label: Text(_fieldLabel(key)),
                selected: selected,
                onSelected: _fetching
                    ? null
                    : (val) {
                        setState(() {
                          if (val) {
                            _autoFillFields.add(key);
                          } else {
                            _autoFillFields.remove(key);
                          }
                        });
                      },
                selectedColor: cs.primaryContainer,
                checkmarkColor: cs.onPrimaryContainer,
                labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_fetching || _saving || _autoFillFields.isEmpty)
                  ? null
                  : _fetchAndFill,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _fetching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_fix_high),
              label: Text(
                _fetching
                    ? context.l10n.editMetadataAutoFillSearching
                    : context.l10n.editMetadataAutoFillFetch,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _quickSelectButton({
    required String label,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    return InkWell(
      onTap: _fetching ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: cs.primary),
        ),
      ),
    );
  }

  Widget _buildCoverEditor(ColorScheme cs) {
    final hasSelectedCover = _hasValue(_selectedCoverPath);
    final hasCurrentCover = _hasValue(_currentCoverPath);
    return _sectionCard(
      icon: Icons.image_outlined,
      title: context.l10n.editMetadataFieldCover,
      children: [
        if (_loadingCurrentCover)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (!hasCurrentCover && !hasSelectedCover)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.l10n.trackCoverNoEmbeddedArt,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _pickCoverImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  hasSelectedCover
                      ? context.l10n.trackCoverReplace
                      : context.l10n.trackCoverPick,
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (hasSelectedCover) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: context.l10n.trackCoverClearSelected,
                onPressed: _saving
                    ? null
                    : () async {
                        await _cleanupSelectedCoverTemp();
                        if (!mounted) return;
                        setState(() {});
                      },
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
        if (hasCurrentCover || hasSelectedCover) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (hasCurrentCover)
                Expanded(
                  child: _buildCoverPreviewTile(
                    cs: cs,
                    path: _currentCoverPath!,
                    label: context.l10n.trackCoverCurrent,
                  ),
                ),
              if (hasCurrentCover && hasSelectedCover)
                const SizedBox(width: 12),
              if (hasSelectedCover)
                Expanded(
                  child: _buildCoverPreviewTile(
                    cs: cs,
                    path: _selectedCoverPath!,
                    label: _selectedCoverName ==
                            _EditMetadataSheet._onlineCoverSentinel
                        ? context.l10n.trackCoverOnline
                        : (_selectedCoverName ??
                              context.l10n.trackCoverSelected),
                  ),
                ),
            ],
          ),
          if (hasSelectedCover) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.trackCoverReplaceNotice,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCoverPreviewTile({
    required ColorScheme cs,
    required String path,
    required String label,
  }) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(path),
              height: 160,
              width: 160,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.broken_image,
                  color: cs.onSurfaceVariant,
                  size: 32,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// Fill for input fields, one step apart from the card so each field reads as
  /// a distinct surface in light/dark/AMOLED.
  Color _fieldFill(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.05), cs.surface)
        : cs.surface;
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    final cs = widget.colorScheme;
    final radius = BorderRadius.circular(14);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
          TextField(
            controller: controller,
            keyboardType: keyboard,
            maxLines: maxLines,
            cursorColor: cs.primary,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: _fieldFill(cs),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  RoundedRectangleBorder _sectionCardShape(ColorScheme cs) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
    );
  }

  /// Titled section card. When [onHeaderTap] is set the header is a full-width
  /// tappable row (ripple clipped to the card) with an auto chevron.
  Widget _sectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
    VoidCallback? onHeaderTap,
    bool expanded = true,
  }) {
    final cs = widget.colorScheme;
    final collapsible = onHeaderTap != null;

    final headerRow = Row(
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
        if (collapsible)
          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Icon(
              Icons.expand_more,
              size: 22,
              color: cs.onSurfaceVariant,
            ),
          ),
      ],
    );

    final Widget header = collapsible
        ? InkWell(
            onTap: onHeaderTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: headerRow,
            ),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: headerRow,
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: settingsGroupColor(context),
        shape: _sectionCardShape(cs),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              if (children.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataItem {
  final String label;
  final String value;

  _MetadataItem(this.label, this.value);
}
