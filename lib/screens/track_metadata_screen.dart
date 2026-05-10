import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:spotiflac_android/services/history_database.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/services/ffmpeg_service.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/utils/lyrics_metadata_helper.dart';
import 'package:spotiflac_android/utils/mime_utils.dart';
import 'package:spotiflac_android/utils/image_cache_utils.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/utils/int_utils.dart';
import 'package:spotiflac_android/widgets/audio_analysis_widget.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';

part 'track_metadata_edit_sheet.dart';

final _log = AppLogger('TrackMetadata');

class _EmbeddedCoverPreviewCacheEntry {
  final String previewPath;
  final String? sourceValidationToken;

  const _EmbeddedCoverPreviewCacheEntry({
    required this.previewPath,
    this.sourceValidationToken,
  });
}

class TrackMetadataScreen extends ConsumerStatefulWidget {
  final DownloadHistoryItem? item;
  final LocalLibraryItem? localItem;
  final List<DownloadHistoryItem>? historyNavigationItems;
  final List<LocalLibraryItem>? localNavigationItems;
  final int? navigationIndex;
  final String? coverHeroTag;

  const TrackMetadataScreen({
    super.key,
    this.item,
    this.localItem,
    this.historyNavigationItems,
    this.localNavigationItems,
    this.navigationIndex,
    this.coverHeroTag,
  }) : assert(
         item != null || localItem != null,
         'Either item or localItem must be provided',
       ),
       assert(
         historyNavigationItems == null || localNavigationItems == null,
         'Provide only one navigation list type',
       ),
       assert(
         navigationIndex == null ||
             ((historyNavigationItems != null &&
                     navigationIndex >= 0 &&
                     navigationIndex < historyNavigationItems.length) ||
                 (localNavigationItems != null &&
                     navigationIndex >= 0 &&
                     navigationIndex < localNavigationItems.length)),
         'navigationIndex must be within the provided navigation list',
       );

  @override
  ConsumerState<TrackMetadataScreen> createState() =>
      _TrackMetadataScreenState();
}

class _TrackMetadataScreenState extends ConsumerState<TrackMetadataScreen> {
  static const int _maxCoverPreviewCacheEntries = 96;
  static final Map<String, _EmbeddedCoverPreviewCacheEntry>
  _embeddedCoverPreviewCache = {};

  bool _fileExists = false;
  bool _hasCheckedFile = false;
  int? _fileSize;
  String? _lyrics;
  String? _rawLyrics;
  bool _lyricsLoading = false;
  String? _lyricsError;
  String? _lyricsSource;
  bool _showTitleInAppBar = false;
  bool _lyricsEmbedded = false;
  bool _isEmbedding = false;
  bool _isInstrumental = false;
  bool _embeddedLyricsChecked = false;
  bool _isConverting = false;
  bool _hasMetadataChanges = false;
  bool _hasLoadedResolvedAudioMetadata = false;
  bool _isTrackSwipeNavigationInFlight = false;
  int _metadataLoadGeneration = 0;
  int _metadataTransitionDirection = 0;
  late DownloadHistoryItem? _currentDownloadItem;
  late LocalLibraryItem? _currentLocalLibraryItem;
  late int? _currentNavigationIndex;
  Map<String, dynamic>? _editedMetadata;
  String? _embeddedCoverPreviewPath;
  final ScrollController _scrollController = ScrollController();
  static final RegExp _lrcTimestampPattern = RegExp(
    r'^\[\d{2}:\d{2}\.\d{2,3}\]',
  );
  static final RegExp _lrcMetadataPattern = RegExp(r'^\[[a-zA-Z]+:.*\]$');
  static final RegExp _lrcInlineTimestampPattern = RegExp(
    r'<\d{2}:\d{2}\.\d{2,3}>',
  );
  static final RegExp _lrcSpeakerPrefixPattern = RegExp(r'^(v1|v2):\s*');
  static final RegExp _lrcBackgroundLinePattern = RegExp(r'^\[bg:(.*)\]$');
  static final RegExp _invalidFileNameChars = RegExp(r'[<>:"/\\|?*\x00-\x1f]');
  static final RegExp _multiUnderscore = RegExp(r'_+');
  static final RegExp _leadingOrTrailingDots = RegExp(r'^\.+|\.+$');
  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String get _coverCacheKey => _itemId;

  bool _isCacheTrackedPath(String? path) {
    if (!_hasPath(path)) return false;
    return _embeddedCoverPreviewCache.values.any(
      (entry) => entry.previewPath == path,
    );
  }

  bool _isVolatileSafTempPath(String path) {
    if (path.isEmpty) return false;
    return path.contains(
      '${Platform.pathSeparator}cache${Platform.pathSeparator}saf_',
    );
  }

  Future<String?> _readLocalFileValidationToken(String path) async {
    if (path.isEmpty || isContentUri(path) || _isVolatileSafTempPath(path)) {
      return null;
    }
    try {
      final stat = await fileStat(path);
      if (stat == null) return null;
      return '${stat.modified?.millisecondsSinceEpoch ?? 0}:${stat.size ?? 0}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheEmbeddedCoverPreview(
    String cacheKey,
    String sourcePath,
    String previewPath,
  ) async {
    final sourceValidationToken = await _readLocalFileValidationToken(
      sourcePath,
    );
    final existing = _embeddedCoverPreviewCache[cacheKey];
    _embeddedCoverPreviewCache[cacheKey] = _EmbeddedCoverPreviewCacheEntry(
      previewPath: previewPath,
      sourceValidationToken: sourceValidationToken,
    );
    if (existing != null && existing.previewPath != previewPath) {
      await _cleanupTempFileAndParentIfNotCached(existing.previewPath);
    }

    while (_embeddedCoverPreviewCache.length > _maxCoverPreviewCacheEntries) {
      final oldestKey = _embeddedCoverPreviewCache.keys.first;
      final removed = _embeddedCoverPreviewCache.remove(oldestKey);
      if (removed != null) {
        await _cleanupTempFileAndParentIfNotCached(removed.previewPath);
      }
    }
  }

  Future<void> _invalidateEmbeddedCoverPreviewCacheForPath(
    String cacheKey,
  ) async {
    if (cacheKey.isEmpty) return;
    final removed = _embeddedCoverPreviewCache.remove(cacheKey);
    if (removed != null) {
      await _cleanupTempFileAndParentIfNotCached(removed.previewPath);
    }
  }

  Future<String?> _getCachedEmbeddedCoverPreviewPathIfValid(
    String cacheKey,
    String sourcePath,
  ) async {
    if (cacheKey.isEmpty) return null;
    final cached = _embeddedCoverPreviewCache[cacheKey];
    if (cached == null) return null;

    if (!await fileExists(cached.previewPath)) {
      _embeddedCoverPreviewCache.remove(cacheKey);
      return null;
    }

    if (!isContentUri(sourcePath) && !_isVolatileSafTempPath(sourcePath)) {
      final currentToken = await _readLocalFileValidationToken(sourcePath);
      if (currentToken != null &&
          cached.sourceValidationToken != null &&
          currentToken != cached.sourceValidationToken) {
        _embeddedCoverPreviewCache.remove(cacheKey);
        await _cleanupTempFileAndParentIfNotCached(cached.previewPath);
        return null;
      }
    }

    return cached.previewPath;
  }

  @override
  void initState() {
    super.initState();
    _currentDownloadItem = widget.item;
    _currentLocalLibraryItem = widget.localItem;
    _currentNavigationIndex = widget.navigationIndex;
    _scrollController.addListener(_onScroll);
    _checkFile();
  }

  @override
  void dispose() {
    unawaited(_cleanupTempFileAndParentIfNotCached(_embeddedCoverPreviewPath));
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final expandedHeight = _calculateExpandedHeight(context);
    final shouldShow =
        _scrollController.offset > (expandedHeight - kToolbarHeight - 20);
    if (shouldShow != _showTitleInAppBar) {
      setState(() => _showTitleInAppBar = shouldShow);
    }
  }

  double _calculateExpandedHeight(BuildContext context) {
    final mediaSize = MediaQuery.of(context).size;
    return (mediaSize.height * 0.55).clamp(360.0, 520.0);
  }

  Future<void> _checkFile() async {
    final generation = _metadataLoadGeneration;
    final filePath = cleanFilePath;

    bool exists = false;
    int? size;
    try {
      final stat = await fileStat(filePath);
      if (stat != null) {
        exists = true;
        size = stat.size;
      }
    } catch (_) {}

    if (mounted &&
        generation == _metadataLoadGeneration &&
        filePath == cleanFilePath &&
        (exists != _fileExists || size != _fileSize || !_hasCheckedFile)) {
      setState(() {
        _fileExists = exists;
        _fileSize = size;
        _hasCheckedFile = true;
      });
    }

    if (mounted &&
        generation == _metadataLoadGeneration &&
        filePath == cleanFilePath &&
        exists &&
        _lyrics == null &&
        !_lyricsLoading) {
      _checkEmbeddedLyrics();
    }
    if (mounted &&
        generation == _metadataLoadGeneration &&
        filePath == cleanFilePath &&
        exists &&
        !_isCueVirtualTrack &&
        !_hasLoadedResolvedAudioMetadata) {
      unawaited(_refreshResolvedAudioMetadataFromFile());
    }
    if (mounted &&
        generation == _metadataLoadGeneration &&
        filePath == cleanFilePath &&
        exists &&
        !_hasPath(_embeddedCoverPreviewPath)) {
      final cachedPath = await _getCachedEmbeddedCoverPreviewPathIfValid(
        _coverCacheKey,
        filePath,
      );
      if (mounted &&
          generation == _metadataLoadGeneration &&
          filePath == cleanFilePath &&
          _hasPath(cachedPath)) {
        setState(() => _embeddedCoverPreviewPath = cachedPath);
      }
    }
  }

  bool _hasPath(String? path) => path != null && path.trim().isNotEmpty;

  Future<void> _cleanupTempFileAndParent(String? path) async {
    if (!_hasPath(path)) return;
    final file = File(path!);
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    try {
      final dir = file.parent;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _cleanupTempFileAndParentIfNotCached(String? path) async {
    if (_isCacheTrackedPath(path)) return;
    await _cleanupTempFileAndParent(path);
  }

  Future<void> _refreshResolvedAudioMetadataFromFile() async {
    final generation = _metadataLoadGeneration;
    final sourcePath = cleanFilePath;
    if ((_isLocalItem && _localLibraryItem == null) ||
        (!_isLocalItem && _downloadItem == null) ||
        _isCueVirtualTrack ||
        _hasLoadedResolvedAudioMetadata) {
      return;
    }

    _hasLoadedResolvedAudioMetadata = true;

    try {
      final metadata = await PlatformBridge.readFileMetadata(sourcePath);
      if (!mounted ||
          generation != _metadataLoadGeneration ||
          sourcePath != cleanFilePath) {
        return;
      }
      if (metadata['error'] != null) {
        return;
      }

      final resolvedBitDepth = readPositiveInt(metadata['bit_depth']);
      final resolvedSampleRate = readPositiveInt(metadata['sample_rate']);
      final resolvedFormat = _normalizeAudioFormatValue(
        metadata['audio_codec']?.toString() ?? metadata['format']?.toString(),
      );
      final resolvedBitrate = _isBitrateFormatValue(resolvedFormat)
          ? _readPlausibleBitrateKbps(
              metadata['bitrate'] ?? metadata['bit_rate'],
            )
          : null;
      final resolvedDuration = readPositiveInt(metadata['duration']);
      final resolvedAlbum = metadata['album']?.toString();
      final resolvedQuality = _displayQualityForValues(
        format: resolvedFormat ?? _storedAudioFormat,
        bitDepth: resolvedBitDepth ?? bitDepth,
        sampleRate: resolvedSampleRate ?? sampleRate,
        bitrateKbps: resolvedBitrate ?? _audioBitrate,
        storedQuality: _quality,
      );

      final needsAlbum =
          resolvedAlbum != null &&
          resolvedAlbum.isNotEmpty &&
          (albumName.isEmpty);
      final needsDuration =
          resolvedDuration != null &&
          resolvedDuration > 0 &&
          (duration == null || duration == 0);

      // Resolve label/copyright from file when the model doesn't carry them
      // (e.g. local library items, or download history items without these fields).
      final resolvedTrackNumber = readPositiveInt(metadata['track_number']);
      final resolvedTotalTracks = readPositiveInt(metadata['total_tracks']);
      final resolvedDiscNumber = readPositiveInt(metadata['disc_number']);
      final resolvedTotalDiscs = readPositiveInt(metadata['total_discs']);
      final resolvedComposer = metadata['composer']?.toString();
      final resolvedLabel = metadata['label']?.toString();
      final resolvedCopyright = metadata['copyright']?.toString();
      final needsTrackNumber =
          resolvedTrackNumber != null &&
          resolvedTrackNumber > 0 &&
          trackNumber == null;
      final needsTotalTracks =
          resolvedTotalTracks != null &&
          resolvedTotalTracks > 0 &&
          totalTracks == null;
      final needsDiscNumber =
          resolvedDiscNumber != null &&
          resolvedDiscNumber > 0 &&
          discNumber == null;
      final needsTotalDiscs =
          resolvedTotalDiscs != null &&
          resolvedTotalDiscs > 0 &&
          totalDiscs == null;
      final needsComposer =
          resolvedComposer != null &&
          resolvedComposer.isNotEmpty &&
          (composer == null || composer!.isEmpty);
      final needsLabel =
          resolvedLabel != null &&
          resolvedLabel.isNotEmpty &&
          (label == null || label!.isEmpty);
      final needsCopyright =
          resolvedCopyright != null &&
          resolvedCopyright.isNotEmpty &&
          (copyright == null || copyright!.isEmpty);

      final shouldPersistResolvedAudioMetadata =
          !_isLocalItem &&
          (resolvedBitDepth != null ||
              resolvedSampleRate != null ||
              resolvedBitrate != null ||
              resolvedFormat != null ||
              needsTrackNumber ||
              needsTotalTracks ||
              needsDiscNumber ||
              needsTotalDiscs ||
              needsDuration ||
              needsComposer ||
              (isPlaceholderQualityLabel(_quality) && resolvedQuality != null));

      if ((resolvedBitDepth != null ||
              resolvedSampleRate != null ||
              needsAlbum ||
              needsDuration ||
              needsTrackNumber ||
              needsTotalTracks ||
              needsDiscNumber ||
              needsTotalDiscs ||
              needsComposer ||
              needsLabel ||
              needsCopyright ||
              isPlaceholderQualityLabel(_quality)) &&
          mounted) {
        setState(() {
          _editedMetadata = {
            ...?_editedMetadata,
            // ignore: use_null_aware_elements
            if (resolvedBitDepth != null) 'bit_depth': resolvedBitDepth,
            // ignore: use_null_aware_elements
            if (resolvedSampleRate != null) 'sample_rate': resolvedSampleRate,
            if (needsAlbum) 'album': resolvedAlbum,
            if (needsDuration) 'duration': resolvedDuration,
            if (needsTrackNumber) 'track_number': resolvedTrackNumber,
            if (needsTotalTracks) 'total_tracks': resolvedTotalTracks,
            if (needsDiscNumber) 'disc_number': resolvedDiscNumber,
            if (needsTotalDiscs) 'total_discs': resolvedTotalDiscs,
            if (needsComposer) 'composer': resolvedComposer,
            if (needsLabel) 'label': resolvedLabel,
            if (needsCopyright) 'copyright': resolvedCopyright,
          };
        });
      }

      if (shouldPersistResolvedAudioMetadata) {
        await ref
            .read(downloadHistoryProvider.notifier)
            .updateAudioMetadataForItem(
              id: _downloadItem!.id,
              quality: resolvedQuality,
              bitDepth: resolvedBitDepth,
              sampleRate: resolvedSampleRate,
              bitrate: resolvedBitrate,
              format: resolvedFormat,
              trackNumber: needsTrackNumber ? resolvedTrackNumber : null,
              totalTracks: needsTotalTracks ? resolvedTotalTracks : null,
              discNumber: needsDiscNumber ? resolvedDiscNumber : null,
              totalDiscs: needsTotalDiscs ? resolvedTotalDiscs : null,
              duration: needsDuration ? resolvedDuration : null,
              composer: needsComposer ? resolvedComposer : null,
            );
        if (mounted && _downloadItem != null) {
          setState(() {
            _currentDownloadItem = _downloadItem!.copyWith(
              quality: resolvedQuality,
              bitDepth: resolvedBitDepth,
              sampleRate: resolvedSampleRate,
              bitrate: resolvedBitrate,
              format: resolvedFormat,
              trackNumber: needsTrackNumber ? resolvedTrackNumber : null,
              totalTracks: needsTotalTracks ? resolvedTotalTracks : null,
              discNumber: needsDiscNumber ? resolvedDiscNumber : null,
              totalDiscs: needsTotalDiscs ? resolvedTotalDiscs : null,
              duration: needsDuration ? resolvedDuration : null,
              composer: needsComposer ? resolvedComposer : null,
            );
          });
        }
      } else if (_isLocalItem && needsDuration) {
        await LibraryDatabase.instance.updateAudioMetadata(
          _localLibraryItem!.id,
          duration: resolvedDuration,
        );
        await ref.read(localLibraryProvider.notifier).reloadFromStorage();
      }
    } catch (e) {
      _log.w('Failed to resolve audio metadata from file: $e');
    }
  }

  Future<void> _refreshEmbeddedCoverPreview({bool force = false}) async {
    final generation = _metadataLoadGeneration;
    final cacheKey = _coverCacheKey;
    final sourcePath = cleanFilePath;
    if (!force) {
      final cachedPath = await _getCachedEmbeddedCoverPreviewPathIfValid(
        cacheKey,
        sourcePath,
      );
      if (_hasPath(cachedPath)) {
        if (mounted &&
            generation == _metadataLoadGeneration &&
            sourcePath == cleanFilePath &&
            _embeddedCoverPreviewPath != cachedPath) {
          setState(() => _embeddedCoverPreviewPath = cachedPath);
        }
        return;
      }
    }

    String? newPreviewPath;
    try {
      if (!_fileExists) {
        await _invalidateEmbeddedCoverPreviewCacheForPath(cacheKey);
        await _cleanupTempFileAndParentIfNotCached(_embeddedCoverPreviewPath);
        if (mounted &&
            generation == _metadataLoadGeneration &&
            sourcePath == cleanFilePath) {
          setState(() => _embeddedCoverPreviewPath = null);
        }
        return;
      }
      if (force) {
        await _invalidateEmbeddedCoverPreviewCacheForPath(cacheKey);
      }
      final tempDir = await Directory.systemTemp.createTemp(
        'track_cover_preview_',
      );
      final outputPath =
          '${tempDir.path}${Platform.pathSeparator}cover_preview.jpg';
      final result = await PlatformBridge.extractCoverToFile(
        sourcePath,
        outputPath,
      );
      if (result['error'] == null && await File(outputPath).exists()) {
        newPreviewPath = outputPath;
        await _cacheEmbeddedCoverPreview(cacheKey, sourcePath, outputPath);
      } else {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}

    final oldPreviewPath = _embeddedCoverPreviewPath;
    if (!mounted ||
        generation != _metadataLoadGeneration ||
        sourcePath != cleanFilePath) {
      if (newPreviewPath != null) {
        await _cleanupTempFileAndParentIfNotCached(newPreviewPath);
      }
      return;
    }

    setState(() => _embeddedCoverPreviewPath = newPreviewPath);
    if (oldPreviewPath != null && oldPreviewPath != newPreviewPath) {
      await _cleanupTempFileAndParentIfNotCached(oldPreviewPath);
    }
  }

  bool get _isLocalItem => _currentLocalLibraryItem != null;
  DownloadHistoryItem? get _downloadItem => _currentDownloadItem;
  LocalLibraryItem? get _localLibraryItem => _currentLocalLibraryItem;
  bool get _hasHistoryNavigation =>
      widget.historyNavigationItems != null && widget.navigationIndex != null;
  bool get _hasLocalNavigation =>
      widget.localNavigationItems != null && widget.navigationIndex != null;
  bool get _hasTrackSwipeNavigation =>
      _hasHistoryNavigation || _hasLocalNavigation;
  int? get _navigationIndex => _currentNavigationIndex;
  int get _navigationLength =>
      widget.historyNavigationItems?.length ??
      widget.localNavigationItems?.length ??
      0;

  String get _itemId =>
      _isLocalItem ? _localLibraryItem!.id : _downloadItem!.id;
  String get trackName =>
      _editedMetadata?['title']?.toString() ??
      (_isLocalItem ? _localLibraryItem!.trackName : _downloadItem!.trackName);
  String get artistName =>
      _editedMetadata?['artist']?.toString() ??
      (_isLocalItem
          ? _localLibraryItem!.artistName
          : _downloadItem!.artistName);
  String get albumName =>
      _editedMetadata?['album']?.toString() ??
      (_isLocalItem ? _localLibraryItem!.albumName : _downloadItem!.albumName);
  String? get albumArtist {
    final edited = _editedMetadata?['album_artist']?.toString();
    if (edited != null && edited.isNotEmpty) return edited;
    return normalizeOptionalString(
      _isLocalItem
          ? _localLibraryItem!.albumArtist
          : _downloadItem!.albumArtist,
    );
  }

  int? get trackNumber {
    final edited = _editedMetadata?['track_number'];
    if (edited != null) {
      final v = int.tryParse(edited.toString());
      if (v != null && v > 0) return v;
    }
    return _isLocalItem
        ? _localLibraryItem!.trackNumber
        : _downloadItem!.trackNumber;
  }

  int? get totalTracks =>
      readPositiveInt(_editedMetadata?['total_tracks']) ??
      (_isLocalItem
          ? _localLibraryItem!.totalTracks
          : _downloadItem!.totalTracks);

  int? get discNumber {
    final edited = _editedMetadata?['disc_number'];
    if (edited != null) {
      final v = int.tryParse(edited.toString());
      if (v != null && v > 0) return v;
    }
    return _isLocalItem
        ? _localLibraryItem!.discNumber
        : _downloadItem!.discNumber;
  }

  int? get totalDiscs =>
      readPositiveInt(_editedMetadata?['total_discs']) ??
      (_isLocalItem
          ? _localLibraryItem!.totalDiscs
          : _downloadItem!.totalDiscs);

  String? get releaseDate =>
      _editedMetadata?['date']?.toString() ??
      (_isLocalItem
          ? _localLibraryItem!.releaseDate
          : _downloadItem!.releaseDate);
  String? get isrc {
    final raw =
        _editedMetadata?['isrc']?.toString() ??
        (_isLocalItem ? _localLibraryItem!.isrc : _downloadItem!.isrc);
    if (raw == null || raw.trim().isEmpty) return null;
    final upper = raw.trim().toUpperCase();
    // Only accept valid ISRC codes (CC-XXX-YY-NNNNN, 12 alphanumeric chars).
    // Strip hyphens/spaces that some sources include.
    final stripped = upper.replaceAll(RegExp(r'[-\s]'), '');
    if (_isrcValidationPattern.hasMatch(stripped)) return stripped;
    return null;
  }

  static final RegExp _isrcValidationPattern = RegExp(
    r'^[A-Z]{2}[A-Z0-9]{3}\d{7}$',
  );
  String? get genre =>
      _editedMetadata?['genre']?.toString() ??
      (_isLocalItem ? _localLibraryItem!.genre : _downloadItem!.genre);
  String? get label =>
      _editedMetadata?['label']?.toString() ??
      (_isLocalItem ? _localLibraryItem!.label : _downloadItem!.label);
  String? get copyright =>
      _editedMetadata?['copyright']?.toString() ??
      (_isLocalItem ? _localLibraryItem!.copyright : _downloadItem!.copyright);
  String? get composer =>
      _editedMetadata?['composer']?.toString() ??
      (_isLocalItem ? _localLibraryItem!.composer : null);
  int? get duration =>
      readPositiveInt(_editedMetadata?['duration']) ??
      (_isLocalItem ? _localLibraryItem!.duration : _downloadItem!.duration);
  int? get bitDepth =>
      readPositiveInt(_editedMetadata?['bit_depth']) ??
      (_isLocalItem ? _localLibraryItem!.bitDepth : _downloadItem!.bitDepth);
  int? get sampleRate =>
      readPositiveInt(_editedMetadata?['sample_rate']) ??
      (_isLocalItem
          ? _localLibraryItem!.sampleRate
          : _downloadItem!.sampleRate);
  int? get _audioBitrate =>
      _isLocalItem ? _localLibraryItem!.bitrate : _downloadItem?.bitrate;
  String? get _storedAudioFormat =>
      _isLocalItem ? _localLibraryItem?.format : _downloadItem?.format;

  String get _filePath =>
      _isLocalItem ? _localLibraryItem!.filePath : _downloadItem!.filePath;
  String get _coverHeroTag =>
      widget.coverHeroTag ??
      (_isLocalItem ? 'cover_lib_$_itemId' : 'cover_$_itemId');
  String? get _coverUrl =>
      _isLocalItem ? null : normalizeRemoteHttpUrl(_downloadItem!.coverUrl);
  String? get _localCoverPath =>
      _isLocalItem ? _localLibraryItem!.coverPath : null;
  String? get _spotifyId => _isLocalItem ? null : _downloadItem!.spotifyId;
  String get _service => _isLocalItem ? 'local' : _downloadItem!.service;
  DateTime get _addedAt {
    if (_isLocalItem) {
      final modTime = _localLibraryItem!.fileModTime;
      if (modTime != null && modTime > 0) {
        return DateTime.fromMillisecondsSinceEpoch(modTime);
      }
      return _localLibraryItem!.scannedAt;
    }
    return _downloadItem!.downloadedAt;
  }

  String? get _quality => _isLocalItem ? null : _downloadItem!.quality;

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

  int? _readPlausibleBitrateKbps(dynamic value) {
    final parsed = readPositiveInt(value);
    if (parsed == null) return null;
    final kbps = parsed >= 10000 ? (parsed / 1000).round() : parsed;
    return kbps >= 16 ? kbps : null;
  }

  bool _isBitrateFormatValue(String? value) {
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

  String? _usableStoredQuality(String? quality) {
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
    return normalized;
  }

  String? _displayQualityForValues({
    required String? format,
    int? bitDepth,
    int? sampleRate,
    int? bitrateKbps,
    String? storedQuality,
  }) {
    final normalizedFormat = _normalizeAudioFormatValue(format);
    final formatLabel = normalizedFormat == null
        ? normalizeOptionalString(format)?.toUpperCase()
        : _formatLabelForRaw(normalizedFormat);
    if (_isBitrateFormatValue(normalizedFormat)) {
      return buildDisplayAudioQuality(
            bitrateKbps: bitrateKbps,
            format: formatLabel,
          ) ??
          _usableStoredQuality(storedQuality) ??
          formatLabel;
    }
    return buildDisplayAudioQuality(
      bitDepth: bitDepth,
      sampleRate: sampleRate,
      storedQuality: _usableStoredQuality(storedQuality),
    );
  }

  String _displayServiceTrackId(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return raw;
    final spotifyTrackIdPattern = RegExp(r'^[A-Za-z0-9]{22}$');

    if (raw.startsWith('deezer:')) return raw.substring('deezer:'.length);
    if (raw.startsWith('tidal:')) return raw.substring('tidal:'.length);
    if (raw.startsWith('qobuz:')) return raw.substring('qobuz:'.length);
    if (spotifyTrackIdPattern.hasMatch(raw)) return raw;

    if (raw.startsWith('spotify:')) {
      final last = raw.split(':').last.trim();
      if (spotifyTrackIdPattern.hasMatch(last)) return last;
      return raw;
    }

    final uri = Uri.tryParse(raw);
    if (uri != null &&
        uri.host.contains('spotify.com') &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'track') {
      final candidate = uri.pathSegments[1].trim();
      if (spotifyTrackIdPattern.hasMatch(candidate)) {
        return candidate;
      }
    }

    return raw;
  }

  String _serviceForTrackId(String value, {required String fallbackService}) {
    final raw = value.trim();
    if (raw.isEmpty) return fallbackService;
    final spotifyTrackIdPattern = RegExp(r'^[A-Za-z0-9]{22}$');

    if (raw.startsWith('deezer:')) return 'deezer';
    if (raw.startsWith('tidal:')) return 'tidal';
    if (raw.startsWith('qobuz:')) return 'qobuz';
    if (raw.startsWith('spotify:')) return 'spotify';
    if (spotifyTrackIdPattern.hasMatch(raw)) return 'spotify';

    final uri = Uri.tryParse(raw);
    if (uri != null) {
      final host = uri.host.toLowerCase();
      if (host.contains('spotify.com')) return 'spotify';
      if (host.contains('deezer.com')) return 'deezer';
      if (host.contains('tidal.com')) return 'tidal';
      if (host.contains('qobuz.com')) return 'qobuz';
    }

    return fallbackService;
  }

  String? get _displayAudioQuality {
    final fileName = _extractFileNameFromPathOrUri(cleanFilePath);
    final fileExt = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : null;

    return _displayQualityForValues(
      format: _storedAudioFormat ?? fileExt,
      bitDepth: bitDepth,
      sampleRate: sampleRate,
      bitrateKbps: _audioBitrate,
      storedQuality: _quality,
    );
  }

  /// The raw file path, with EXISTS: prefix stripped but #trackNN preserved.
  /// Use this when you need the full virtual path (e.g. for display or DB lookups).
  String get rawFilePath {
    final path = _filePath;
    return path.startsWith('EXISTS:') ? path.substring(7) : path;
  }

  /// The clean file path with both EXISTS: prefix and #trackNN suffix stripped.
  /// Use this for actual filesystem/SAF operations.
  String get cleanFilePath {
    var path = _filePath;
    if (path.startsWith('EXISTS:')) path = path.substring(7);
    if (isCueVirtualPath(path)) path = stripCueTrackSuffix(path);
    return path;
  }

  bool get _isCueVirtualTrack => isCueVirtualPath(rawFilePath);

  String _cueVirtualTrackGuidance(BuildContext context) {
    return 'This CUE track is virtual. Use ${context.l10n.cueSplitButton} first.';
  }

  void _showCueVirtualTrackSnackBar(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_cueVirtualTrackGuidance(context))));
  }

  void _hideCurrentSnackBar() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  String get _l10nCueSplitFailed => context.l10n.cueSplitFailed;
  String get _l10nCueSplitNoAudioFile => context.l10n.cueSplitNoAudioFile;

  String _l10nCueSplitSplitting(int current, int total) {
    return context.l10n.cueSplitSplitting(current, total);
  }

  String _l10nCueSplitSuccess(int count) {
    return context.l10n.cueSplitSuccess(count);
  }

  void _showSnackBarMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showLongSnackBarMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 60)),
    );
  }

  String _formatPathForDisplay(String pathOrUri) {
    if (pathOrUri.isEmpty || !pathOrUri.startsWith('content://')) {
      return pathOrUri;
    }

    try {
      final uri = Uri.parse(pathOrUri);
      final segments = uri.pathSegments;
      String? documentId;

      final documentIndex = segments.indexOf('document');
      if (documentIndex != -1 && documentIndex + 1 < segments.length) {
        documentId = Uri.decodeComponent(segments[documentIndex + 1]);
      }

      if (documentId == null || documentId.isEmpty) {
        final treeIndex = segments.indexOf('tree');
        if (treeIndex != -1 && treeIndex + 1 < segments.length) {
          documentId = Uri.decodeComponent(segments[treeIndex + 1]);
        }
      }

      if (documentId == null || documentId.isEmpty) return pathOrUri;

      final separatorIndex = documentId.indexOf(':');
      if (separatorIndex <= 0) return documentId;

      final volumeId = documentId.substring(0, separatorIndex);
      final relativePath = documentId
          .substring(separatorIndex + 1)
          .replaceAll('\\', '/');

      if (volumeId.toLowerCase() == 'primary') {
        if (relativePath.isEmpty) return '/storage/emulated/0';
        return '/storage/emulated/0/$relativePath';
      }

      if (relativePath.isEmpty) return volumeId;
      return 'SD Card/$relativePath';
    } catch (_) {
      return pathOrUri;
    }
  }

  void _markMetadataChanged() {
    _hasMetadataChanges = true;
  }

  void _popWithMetadataResult() {
    Navigator.pop(context, _hasMetadataChanges ? true : null);
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity == null || velocity.abs() < 350) return;
    if (velocity < 0) {
      unawaited(_navigateToAdjacentTrack(1));
    } else {
      unawaited(_navigateToAdjacentTrack(-1));
    }
  }

  Future<void> _navigateToAdjacentTrack(int offset) async {
    if (_isTrackSwipeNavigationInFlight || !_hasTrackSwipeNavigation) return;
    final currentIndex = _navigationIndex;
    if (currentIndex == null) return;
    final targetIndex = currentIndex + offset;
    if (targetIndex < 0 || targetIndex >= _navigationLength) return;

    _isTrackSwipeNavigationInFlight = true;
    final oldPreviewPath = _embeddedCoverPreviewPath;

    try {
      setState(() {
        _metadataLoadGeneration++;
        _metadataTransitionDirection = offset > 0 ? 1 : -1;
        _currentNavigationIndex = targetIndex;
        if (_hasHistoryNavigation) {
          _currentDownloadItem = widget.historyNavigationItems![targetIndex];
          _currentLocalLibraryItem = null;
        } else {
          _currentDownloadItem = null;
          _currentLocalLibraryItem = widget.localNavigationItems![targetIndex];
        }
        _fileExists = false;
        _hasCheckedFile = false;
        _fileSize = null;
        _lyrics = null;
        _rawLyrics = null;
        _lyricsLoading = false;
        _lyricsError = null;
        _lyricsSource = null;
        _showTitleInAppBar = false;
        _lyricsEmbedded = false;
        _isInstrumental = false;
        _embeddedLyricsChecked = false;
        _hasLoadedResolvedAudioMetadata = false;
        _editedMetadata = null;
        _embeddedCoverPreviewPath = null;
      });

      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }

      if (oldPreviewPath != null) {
        unawaited(_cleanupTempFileAndParentIfNotCached(oldPreviewPath));
      }
      await _checkFile();
    } finally {
      if (mounted) {
        _isTrackSwipeNavigationInFlight = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final expandedHeight = _calculateExpandedHeight(context);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      child: Scaffold(
        body: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              expandedHeight: expandedHeight,
              pinned: true,
              stretch: true,
              backgroundColor: colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              title: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _showTitleInAppBar ? 1.0 : 0.0,
                child: Text(
                  trackName,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  final collapseRatio =
                      (constraints.maxHeight - kToolbarHeight) /
                      (expandedHeight - kToolbarHeight);
                  final showContent = collapseRatio > 0.3;

                  return FlexibleSpaceBar(
                    collapseMode: CollapseMode.pin,
                    background: _buildHeaderBackground(
                      context,
                      colorScheme,
                      expandedHeight,
                      showContent,
                    ),
                    stretchModes: const [StretchMode.zoomBackground],
                  );
                },
              ),
              leading: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                onPressed: _popWithMetadataResult,
              ),
              actions: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.more_vert, color: Colors.white),
                  ),
                  onPressed: () => _showOptionsMenu(context, ref, colorScheme),
                ),
              ],
            ),

            SliverToBoxAdapter(
              child: _buildAnimatedTrackContent(context, ref, colorScheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedTrackContent(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) {
    final currentKey = ValueKey<String>('metadata_content_$_itemId');
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (child, animation) {
        if (_metadataTransitionDirection == 0) {
          return child;
        }
        final isIncoming = child.key == currentKey;
        final direction = _metadataTransitionDirection.toDouble();
        final begin = Offset(
          isIncoming ? 0.18 * direction : -0.18 * direction,
          0,
        );
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return ClipRect(
          child: SlideTransition(
            position: Tween<Offset>(
              begin: begin,
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: animation, child: child),
          ),
        );
      },
      child: Padding(
        key: currentKey,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMetadataCard(context, colorScheme, _fileSize),

            const SizedBox(height: 16),

            _buildFileInfoCard(context, colorScheme, _fileExists, _fileSize),

            const SizedBox(height: 16),

            _buildLyricsCard(context, colorScheme),

            if (_fileExists) ...[
              const SizedBox(height: 16),
              AudioAnalysisCard(filePath: _filePath),
            ],

            const SizedBox(height: 24),

            _buildActionButtons(context, ref, colorScheme, _fileExists),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBackground(
    BuildContext context,
    ColorScheme colorScheme,
    double expandedHeight,
    bool showContent,
  ) {
    final cacheWidth = coverCacheWidthForViewport(context);
    final coverChild = _hasPath(_embeddedCoverPreviewPath)
        ? Image.file(
            File(_embeddedCoverPreviewPath!),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => Container(color: colorScheme.surface),
          )
        : _coverUrl != null
        ? CachedCoverImage(
            imageUrl: _coverUrl!,
            fit: BoxFit.cover,
            memCacheWidth: cacheWidth,
            placeholder: (_, _) => Container(color: colorScheme.surface),
            errorWidget: (_, _, _) => Container(color: colorScheme.surface),
          )
        : _localCoverPath != null && _localCoverPath!.isNotEmpty
        ? Image.file(
            File(_localCoverPath!),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => Container(color: colorScheme.surface),
          )
        : Container(
            color: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.music_note,
              size: 80,
              color: colorScheme.onSurfaceVariant,
            ),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        Hero(
          tag: _coverHeroTag,
          child: Material(color: Colors.transparent, child: coverChild),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: expandedHeight * 0.65,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.85),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 40,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: showContent ? 1.0 : 0.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trackName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  artistName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  albumName,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_displayAudioQuality != null &&
                        _displayAudioQuality!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _displayAudioQuality!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (duration != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _formatDuration(duration!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (_service != 'local')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _service[0].toUpperCase() + _service.substring(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.folder,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Local',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_hasCheckedFile && !_fileExists)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.warning_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              context.l10n.trackFileNotFound,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataCard(
    BuildContext context,
    ColorScheme colorScheme,
    int? fileSize,
  ) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  context.l10n.trackMetadata,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildMetadataGrid(context, colorScheme),

            if (_spotifyId != null && _spotifyId!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final openService = _serviceForTrackId(
                    _spotifyId!,
                    fallbackService: _service.toLowerCase(),
                  );
                  String buttonLabel;
                  if (openService == 'deezer') {
                    buttonLabel = context.l10n.trackOpenInDeezer;
                  } else if (openService == 'amazon') {
                    buttonLabel = 'Open in Amazon Music';
                  } else if (openService == 'tidal') {
                    buttonLabel = 'Open in Tidal';
                  } else if (openService == 'qobuz') {
                    buttonLabel = 'Open in Qobuz';
                  } else {
                    buttonLabel = context.l10n.trackOpenInSpotify;
                  }
                  return OutlinedButton.icon(
                    onPressed: () => _openServiceUrl(context),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(buttonLabel),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openServiceUrl(BuildContext context) async {
    if (_spotifyId == null) return;

    final openService = _serviceForTrackId(
      _spotifyId!,
      fallbackService: _service.toLowerCase(),
    );
    final rawId = _displayServiceTrackId(_spotifyId!);

    String webUrl;
    Uri? appUri;
    String serviceName;

    if (openService == 'deezer') {
      webUrl = 'https://www.deezer.com/track/$rawId';
      appUri = Uri.parse('deezer://www.deezer.com/track/$rawId');
      serviceName = 'Deezer';
    } else if (openService == 'amazon') {
      webUrl = 'https://music.amazon.com/search/$rawId';
      appUri = Uri.parse('amznm://search/$rawId');
      serviceName = 'Amazon Music';
    } else if (openService == 'tidal') {
      webUrl = 'https://listen.tidal.com/track/$rawId';
      appUri = Uri.parse('tidal://track/$rawId');
      serviceName = 'Tidal';
    } else if (openService == 'qobuz') {
      webUrl = 'https://play.qobuz.com/track/$rawId';
      appUri = Uri.parse('qobuz://track/$rawId');
      serviceName = 'Qobuz';
    } else {
      webUrl = 'https://open.spotify.com/track/$rawId';
      appUri = Uri.parse('spotify:track:$rawId');
      serviceName = 'Spotify';
    }

    try {
      final launched = await launchUrl(
        appUri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        await launchUrl(
          Uri.parse(webUrl),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      try {
        await launchUrl(
          Uri.parse(webUrl),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        if (context.mounted) {
          _copyToClipboard(context, webUrl);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.snackbarUrlCopied(serviceName)),
            ),
          );
        }
      }
    }
  }

  Widget _buildMetadataGrid(BuildContext context, ColorScheme colorScheme) {
    final audioQualityStr = _displayAudioQuality;

    final items = <_MetadataItem>[
      _MetadataItem(context.l10n.trackTrackName, trackName),
      _MetadataItem(context.l10n.trackArtist, artistName),
      if (albumArtist != null && albumArtist != artistName)
        _MetadataItem(context.l10n.trackAlbumArtist, albumArtist!),
      _MetadataItem(context.l10n.trackAlbum, albumName),
      if (trackNumber != null && trackNumber! > 0)
        _MetadataItem(context.l10n.trackTrackNumber, trackNumber.toString()),
      if (totalTracks != null && totalTracks! > 0)
        _MetadataItem('Track Total', totalTracks.toString()),
      if (discNumber != null && discNumber! > 0)
        _MetadataItem(context.l10n.trackDiscNumber, discNumber.toString()),
      if (totalDiscs != null && totalDiscs! > 0)
        _MetadataItem('Disc Total', totalDiscs.toString()),
      if (duration != null)
        _MetadataItem(context.l10n.trackDuration, _formatDuration(duration!)),
      if (audioQualityStr != null)
        _MetadataItem(context.l10n.trackAudioQuality, audioQualityStr),
      if (releaseDate != null && releaseDate!.isNotEmpty)
        _MetadataItem(context.l10n.trackReleaseDate, releaseDate!),
      if (genre != null && genre!.isNotEmpty)
        _MetadataItem(context.l10n.trackGenre, genre!),
      if (label != null && label!.isNotEmpty)
        _MetadataItem(context.l10n.trackLabel, label!),
      if (copyright != null && copyright!.isNotEmpty)
        _MetadataItem(context.l10n.trackCopyright, copyright!),
      if (composer != null && composer!.isNotEmpty)
        _MetadataItem('Composer', composer!),
      if (isrc != null && isrc!.isNotEmpty) _MetadataItem('ISRC', isrc!),
    ];

    if (!_isLocalItem && _spotifyId != null && _spotifyId!.isNotEmpty) {
      final idService = _serviceForTrackId(
        _spotifyId!,
        fallbackService: _service.toLowerCase(),
      );
      final cleanId = _displayServiceTrackId(_spotifyId!);
      String idLabel;
      switch (idService) {
        case 'deezer':
          idLabel = 'Deezer ID';
        case 'amazon':
          idLabel = 'Amazon ASIN';
        case 'tidal':
          idLabel = 'Tidal ID';
        case 'qobuz':
          idLabel = 'Qobuz ID';
        default:
          idLabel = 'Spotify ID';
      }
      items.add(_MetadataItem(idLabel, cleanId));
    }

    items.add(
      _MetadataItem(context.l10n.trackMetadataService, _service.toUpperCase()),
    );
    items.add(
      _MetadataItem(context.l10n.trackDownloaded, _formatFullDate(_addedAt)),
    );

    return Column(
      children: items.map((metadata) {
        final isCopyable =
            metadata.label == 'ISRC' ||
            metadata.label == 'Spotify ID' ||
            metadata.label == 'Deezer ID' ||
            metadata.label == 'Amazon ASIN' ||
            metadata.label == 'Tidal ID' ||
            metadata.label == 'Qobuz ID';
        return InkWell(
          onTap: isCopyable
              ? () => _copyToClipboard(context, metadata.value)
              : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    metadata.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    metadata.value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                if (isCopyable)
                  Icon(
                    Icons.copy,
                    size: 14,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  String _formatLabelForRaw(String raw) {
    final normalized = raw.toLowerCase().replaceAll('-', '_');
    return switch (normalized) {
      'flac' => 'FLAC',
      'alac' => 'ALAC',
      'eac3' || 'ec_3' => 'EAC3',
      'ac3' || 'ac_3' => 'AC3',
      'ac4' || 'ac_4' => 'AC4',
      'aac' || 'mp4a' => 'AAC',
      'm4a' || 'mp4' => 'M4A',
      'mp3' => 'MP3',
      'opus' => 'Opus',
      'ogg' => 'OGG',
      _ => raw.toUpperCase(),
    };
  }

  String _displayFormatLabelForFile(String fileName) {
    final storedFormat = normalizeOptionalString(_storedAudioFormat);
    final raw =
        storedFormat ??
        (fileName.contains('.') ? fileName.split('.').last : 'Unknown');
    return _formatLabelForRaw(raw);
  }

  bool _isBitrateFormatLabel(String label) {
    return const {
      'MP3',
      'OPUS',
      'OGG',
      'M4A',
      'AAC',
      'EAC3',
      'AC3',
      'AC4',
    }.contains(label.toUpperCase());
  }

  Widget _buildFileInfoCard(
    BuildContext context,
    ColorScheme colorScheme,
    bool fileExists,
    int? fileSize,
  ) {
    final displayFilePath = _formatPathForDisplay(rawFilePath);
    final fileName = _extractFileNameFromPathOrUri(rawFilePath);
    final fileExtension = _displayFormatLabelForFile(fileName);
    final resolvedQuality = _displayAudioQuality;
    final lossyBitrateLabel = _extractLossyBitrateLabel(resolvedQuality);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.trackFileInfo,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    fileExtension,
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (fileSize != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _formatFileSize(fileSize),
                      style: TextStyle(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_isBitrateFormatLabel(fileExtension) &&
                    lossyBitrateLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      lossyBitrateLabel,
                      style: TextStyle(
                        color: colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  )
                else if (_audioBitrate != null &&
                    _audioBitrate! > 0 &&
                    _isBitrateFormatLabel(fileExtension))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_audioBitrate}kbps',
                      style: TextStyle(
                        color: colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  )
                else if (bitDepth != null &&
                    bitDepth! > 0 &&
                    sampleRate != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      buildDisplayAudioQuality(
                            bitDepth: bitDepth,
                            sampleRate: sampleRate,
                          ) ??
                          '',
                      style: TextStyle(
                        color: colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getServiceColor(_service, colorScheme),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getServiceIcon(_service),
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _service.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            InkWell(
              onTap: () => _copyToClipboard(context, cleanFilePath),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayFilePath,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.copy,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLyricsCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lyrics_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.trackLyrics,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (_lyrics != null)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () => _copyToClipboard(context, _lyrics!),
                    tooltip: context.l10n.trackCopyLyrics,
                  ),
              ],
            ),
            if (_lyricsSource != null && _lyricsSource!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Source: ${_lyricsSource!}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 12),

            if (_lyricsLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_lyricsError != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _lyricsError!,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                    TextButton(
                      onPressed: _fetchOnlineLyrics,
                      child: Text(context.l10n.dialogRetry),
                    ),
                  ],
                ),
              )
            else if (_isInstrumental)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.music_note,
                      color: colorScheme.tertiary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      context.l10n.trackInstrumental,
                      style: TextStyle(
                        color: colorScheme.onTertiaryContainer,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              )
            else if (_lyrics != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Text(
                        _lyrics!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                  if (!_lyricsEmbedded && _fileExists) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: FilledButton.tonalIcon(
                        onPressed: _isEmbedding ? null : _embedLyrics,
                        icon: _isEmbedding
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_alt),
                        label: Text(context.l10n.trackEmbedLyrics),
                      ),
                    ),
                  ],
                ],
              )
            else if (_embeddedLyricsChecked && _fileExists)
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lyrics_outlined,
                          color: colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.l10n.trackLyricsNotInFile,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: FilledButton.tonalIcon(
                      onPressed: _fetchOnlineLyrics,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: Text(context.l10n.trackFetchOnlineLyrics),
                    ),
                  ),
                ],
              )
            else
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: _fetchLyrics,
                  icon: const Icon(Icons.download),
                  label: Text(context.l10n.trackLoadLyrics),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Check for lyrics embedded in the audio file only (no network requests).
  /// Called automatically when the screen opens.
  Future<void> _checkEmbeddedLyrics() async {
    if (_lyricsLoading || !_fileExists) return;
    final generation = _metadataLoadGeneration;
    final sourcePath = cleanFilePath;
    if (!mounted) return;

    setState(() {
      _lyricsLoading = true;
      _lyricsError = null;
      _isInstrumental = false;
      _lyricsSource = null;
    });

    try {
      final embeddedResult =
          await PlatformBridge.getLyricsLRCWithSource(
            '',
            trackName,
            artistName,
            filePath: sourcePath,
            durationMs: 0,
          ).timeout(
            const Duration(seconds: 5),
            onTimeout: () => <String, dynamic>{'lyrics': '', 'source': ''},
          );

      final embeddedLyrics = embeddedResult['lyrics']?.toString() ?? '';
      final embeddedSource = embeddedResult['source']?.toString() ?? '';

      if (mounted &&
          generation == _metadataLoadGeneration &&
          sourcePath == cleanFilePath) {
        if (embeddedLyrics.isNotEmpty) {
          final cleanLyrics = _cleanLrcForDisplay(embeddedLyrics);
          setState(() {
            _lyrics = cleanLyrics;
            _rawLyrics = embeddedLyrics;
            _lyricsSource = embeddedSource.isNotEmpty
                ? embeddedSource
                : 'Embedded';
            _lyricsEmbedded = true;
            _lyricsLoading = false;
            _embeddedLyricsChecked = true;
          });
        } else {
          setState(() {
            _lyricsLoading = false;
            _embeddedLyricsChecked = true;
          });
        }
      }
    } catch (e) {
      if (mounted &&
          generation == _metadataLoadGeneration &&
          sourcePath == cleanFilePath) {
        setState(() {
          _lyricsLoading = false;
          _embeddedLyricsChecked = true;
        });
      }
    }
  }

  /// Fetch lyrics from online providers. Only called by user action.
  Future<void> _fetchOnlineLyrics() async {
    if (_lyricsLoading) return;

    setState(() {
      _lyricsLoading = true;
      _lyricsError = null;
      _isInstrumental = false;
      _lyricsSource = null;
    });

    try {
      final durationMs = (duration ?? 0) * 1000;

      final result = await PlatformBridge.getLyricsLRCWithSource(
        _spotifyId ?? '',
        trackName,
        artistName,
        filePath: null,
        durationMs: durationMs,
      ).timeout(const Duration(seconds: 20));

      final lrcText = result['lyrics']?.toString() ?? '';
      final source = result['source']?.toString() ?? '';
      final instrumental =
          (result['instrumental'] as bool? ?? false) ||
          lrcText == '[instrumental:true]';

      if (mounted) {
        if (instrumental) {
          setState(() {
            _isInstrumental = true;
            _lyricsSource = source.isNotEmpty ? source : null;
            _lyricsLoading = false;
          });
        } else if (lrcText.isEmpty) {
          setState(() {
            _lyricsError = context.l10n.trackLyricsNotAvailable;
            _lyricsLoading = false;
          });
        } else {
          final cleanLyrics = _cleanLrcForDisplay(lrcText);
          setState(() {
            _lyrics = cleanLyrics;
            _rawLyrics = lrcText;
            _lyricsSource = source.isNotEmpty ? source : null;
            _lyricsEmbedded = false;
            _lyricsLoading = false;
          });
        }
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _lyricsError = context.l10n.trackLyricsTimeout;
          _lyricsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lyricsError = context.l10n.trackLyricsLoadFailed;
          _lyricsLoading = false;
        });
      }
    }
  }

  /// Full lyrics fetch: check embedded first, then online.
  /// Used by the "Load Lyrics" button when file doesn't exist (non-local items).
  Future<void> _fetchLyrics() async {
    if (_lyricsLoading) return;

    setState(() {
      _lyricsLoading = true;
      _lyricsError = null;
      _isInstrumental = false;
      _lyricsSource = null;
    });

    try {
      final durationMs = (duration ?? 0) * 1000;

      if (_fileExists) {
        final embeddedResult =
            await PlatformBridge.getLyricsLRCWithSource(
              '',
              trackName,
              artistName,
              filePath: cleanFilePath,
              durationMs: 0,
            ).timeout(
              const Duration(seconds: 5),
              onTimeout: () => <String, dynamic>{'lyrics': '', 'source': ''},
            );

        final embeddedLyrics = embeddedResult['lyrics']?.toString() ?? '';
        final embeddedSource = embeddedResult['source']?.toString() ?? '';

        if (embeddedLyrics.isNotEmpty) {
          if (mounted) {
            final cleanLyrics = _cleanLrcForDisplay(embeddedLyrics);
            setState(() {
              _lyrics = cleanLyrics;
              _rawLyrics = embeddedLyrics;
              _lyricsSource = embeddedSource.isNotEmpty
                  ? embeddedSource
                  : 'Embedded';
              _lyricsEmbedded = true;
              _lyricsLoading = false;
              _embeddedLyricsChecked = true;
            });
          }
          return;
        }
      }

      final result = await PlatformBridge.getLyricsLRCWithSource(
        _spotifyId ?? '',
        trackName,
        artistName,
        filePath: null,
        durationMs: durationMs,
      ).timeout(const Duration(seconds: 20));

      final lrcText = result['lyrics']?.toString() ?? '';
      final source = result['source']?.toString() ?? '';
      final instrumental =
          (result['instrumental'] as bool? ?? false) ||
          lrcText == '[instrumental:true]';

      if (mounted) {
        if (instrumental) {
          setState(() {
            _isInstrumental = true;
            _lyricsSource = source.isNotEmpty ? source : null;
            _lyricsLoading = false;
          });
        } else if (lrcText.isEmpty) {
          setState(() {
            _lyricsError = context.l10n.trackLyricsNotAvailable;
            _lyricsLoading = false;
          });
        } else {
          final cleanLyrics = _cleanLrcForDisplay(lrcText);
          setState(() {
            _lyrics = cleanLyrics;
            _rawLyrics = lrcText;
            _lyricsSource = source.isNotEmpty ? source : null;
            _lyricsEmbedded = false;
            _lyricsLoading = false;
          });
        }
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _lyricsError = context.l10n.trackLyricsTimeout;
          _lyricsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lyricsError = context.l10n.trackLyricsLoadFailed;
          _lyricsLoading = false;
        });
      }
    }
  }

  Future<void> _embedLyrics() async {
    if (_isEmbedding || _rawLyrics == null || !_fileExists) return;

    setState(() => _isEmbedding = true);

    final l10nFailedToWriteStorage = context.l10n.snackbarFailedToWriteStorage;
    final l10nFailedToEmbedLyrics = context.l10n.snackbarFailedToEmbedLyrics;
    final l10nUnsupportedFormat = context.l10n.snackbarUnsupportedAudioFormat;

    String? safTempPath;
    String? coverPath;

    try {
      final rawLyrics = _rawLyrics!;
      var workingPath = cleanFilePath;

      if (_isSafFile) {
        safTempPath = await PlatformBridge.copyContentUriToTemp(cleanFilePath);
        if (safTempPath == null || safTempPath.isEmpty) {
          throw Exception('Failed to access SAF file');
        }
        workingPath = safTempPath;
      }

      final lower = workingPath.toLowerCase();
      final isFlac = lower.endsWith('.flac');
      final isMp3 = lower.endsWith('.mp3');
      final isOpus = lower.endsWith('.opus') || lower.endsWith('.ogg');
      final isM4A = lower.endsWith('.m4a') || lower.endsWith('.aac');

      bool success = false;
      String? error;

      if (isFlac) {
        final result = await PlatformBridge.embedLyricsToFile(
          workingPath,
          rawLyrics,
        );
        if (result['success'] == true) {
          if (_isSafFile) {
            final ok = await PlatformBridge.writeTempToSaf(
              workingPath,
              cleanFilePath,
            );
            success = ok;
            if (!ok) {
              error = l10nFailedToWriteStorage;
            }
          } else {
            success = true;
          }
        } else {
          error = result['error']?.toString() ?? l10nFailedToEmbedLyrics;
        }
      } else if (isMp3 || isOpus || isM4A) {
        final metadata = _buildFallbackMetadata();
        try {
          final result = await PlatformBridge.readFileMetadata(workingPath);
          if (result['error'] == null) {
            final mapped = _mapMetadataForTagEmbed(result);
            metadata.addAll(mapped);
          }
        } catch (e) {
          _log.w('Failed reading file metadata before lyrics embed: $e');
        }

        metadata['LYRICS'] = rawLyrics;
        metadata['UNSYNCEDLYRICS'] = rawLyrics;

        try {
          final tempDir = await getTemporaryDirectory();
          final coverOutput =
              '${tempDir.path}${Platform.pathSeparator}lyrics_cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final coverResult = await PlatformBridge.extractCoverToFile(
            workingPath,
            coverOutput,
          );
          if (coverResult['error'] == null) {
            coverPath = coverOutput;
          }
        } catch (_) {}

        final artistTagMode = ref.read(settingsProvider).artistTagMode;
        String? ffmpegResult;
        if (isMp3) {
          ffmpegResult = await FFmpegService.embedMetadataToMp3(
            mp3Path: workingPath,
            coverPath: coverPath,
            metadata: metadata,
          );
        } else if (isM4A) {
          ffmpegResult = await FFmpegService.embedMetadataToM4a(
            m4aPath: workingPath,
            coverPath: coverPath,
            metadata: metadata,
          );
        } else {
          ffmpegResult = await FFmpegService.embedMetadataToOpus(
            opusPath: workingPath,
            coverPath: coverPath,
            metadata: metadata,
            artistTagMode: artistTagMode,
          );
        }

        if (ffmpegResult == null) {
          error = l10nFailedToEmbedLyrics;
        } else if (_isSafFile) {
          final ok = await PlatformBridge.writeTempToSaf(
            ffmpegResult,
            cleanFilePath,
          );
          success = ok;
          if (!ok) {
            error = l10nFailedToWriteStorage;
          }
        } else {
          success = true;
        }
      } else {
        error = l10nUnsupportedFormat;
      }

      if (mounted) {
        if (success) {
          setState(() {
            _lyricsEmbedded = true;
            _isEmbedding = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.trackLyricsEmbedded)),
          );
        } else {
          setState(() => _isEmbedding = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error ?? context.l10n.snackbarFailedToEmbedLyrics),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isEmbedding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.snackbarError(e.toString()))),
        );
      }
    } finally {
      if (coverPath != null) {
        try {
          await File(coverPath).delete();
        } catch (_) {}
      }
      if (safTempPath != null) {
        try {
          await File(safTempPath).delete();
        } catch (_) {}
      }
    }
  }

  String _sanitizeFileNameSegment(String value) {
    var sanitized = value.replaceAll(_invalidFileNameChars, '_').trim();
    sanitized = sanitized.replaceAll(_leadingOrTrailingDots, '');
    sanitized = sanitized.replaceAll(_multiUnderscore, '_');
    if (sanitized.isEmpty) {
      return 'untitled';
    }
    return sanitized;
  }

  String _buildSaveBaseName() {
    final artist = _sanitizeFileNameSegment(artistName);
    final track = _sanitizeFileNameSegment(trackName);
    return '$artist - $track';
  }

  String _getFileDirectory() {
    if (isContentUri(cleanFilePath)) {
      // SAF URIs don't have a filesystem parent directory
      return '';
    }
    final file = File(cleanFilePath);
    return file.parent.path;
  }

  bool get _isSafFile => isContentUri(cleanFilePath);

  Future<void> _saveCoverArt() async {
    try {
      final baseName = _buildSaveBaseName();

      if (_isSafFile) {
        final tempDir = await Directory.systemTemp.createTemp('cover_');
        final tempOutput =
            '${tempDir.path}${Platform.pathSeparator}$baseName.jpg';

        Map<String, dynamic> result;
        if (_fileExists) {
          // Prefer extracting cover from the already-downloaded file to avoid
          // a redundant network request.
          result = await PlatformBridge.extractCoverToFile(
            cleanFilePath,
            tempOutput,
          );
          // Fall back to downloading from URL if extraction failed.
          if (result['error'] != null &&
              _coverUrl != null &&
              _coverUrl!.isNotEmpty) {
            result = await PlatformBridge.downloadCoverToFile(
              _coverUrl!,
              tempOutput,
              maxQuality: true,
            );
          }
        } else if (_coverUrl != null && _coverUrl!.isNotEmpty) {
          result = await PlatformBridge.downloadCoverToFile(
            _coverUrl!,
            tempOutput,
            maxQuality: true,
          );
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.trackCoverNoSource)),
            );
          }
          return;
        }

        if (result['error'] != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.trackSaveFailed(result['error'].toString()),
                ),
              ),
            );
          }
          try {
            await Directory(tempDir.path).delete(recursive: true);
          } catch (_) {}
          return;
        }

        final treeUri = _downloadItem?.downloadTreeUri;
        final relativeDir = _downloadItem?.safRelativeDir ?? '';
        if (treeUri != null && treeUri.isNotEmpty) {
          final safUri = await PlatformBridge.createSafFileFromPath(
            treeUri: treeUri,
            relativeDir: relativeDir,
            fileName: '$baseName.jpg',
            mimeType: 'image/jpeg',
            srcPath: tempOutput,
          );
          try {
            await Directory(tempDir.path).delete(recursive: true);
          } catch (_) {}
          if (mounted) {
            if (safUri != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.trackCoverSaved(baseName))),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.trackSaveFailed('Failed to write to storage'),
                  ),
                ),
              );
            }
          }
        } else {
          try {
            await Directory(tempDir.path).delete(recursive: true);
          } catch (_) {}
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.trackSaveFailed('No storage access'),
                ),
              ),
            );
          }
        }
        return;
      }

      final dir = _getFileDirectory();
      final outputPath = '$dir${Platform.pathSeparator}$baseName.jpg';

      Map<String, dynamic> result;
      if (_fileExists) {
        // Prefer extracting cover from the already-downloaded file to avoid
        // a redundant network request.
        result = await PlatformBridge.extractCoverToFile(
          cleanFilePath,
          outputPath,
        );
        // Fall back to downloading from URL if extraction failed.
        if (result['error'] != null &&
            _coverUrl != null &&
            _coverUrl!.isNotEmpty) {
          result = await PlatformBridge.downloadCoverToFile(
            _coverUrl!,
            outputPath,
            maxQuality: true,
          );
        }
      } else if (_coverUrl != null && _coverUrl!.isNotEmpty) {
        result = await PlatformBridge.downloadCoverToFile(
          _coverUrl!,
          outputPath,
          maxQuality: true,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.trackCoverNoSource)),
          );
        }
        return;
      }

      if (mounted) {
        if (result['error'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.trackSaveFailed(result['error'].toString()),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.trackCoverSaved(baseName))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.trackSaveFailed(e.toString()))),
        );
      }
    }
  }

  Future<void> _saveLyrics() async {
    try {
      final baseName = _buildSaveBaseName();
      final durationMs = (duration ?? 0) * 1000;
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(context.l10n.trackSaveLyricsProgress)),
          );
      }

      if (_isSafFile) {
        // SAF file: save to temp, then copy to SAF tree
        final tempDir = await Directory.systemTemp.createTemp('lyrics_');
        final tempOutput =
            '${tempDir.path}${Platform.pathSeparator}$baseName.lrc';

        final result = await PlatformBridge.fetchAndSaveLyrics(
          trackName: trackName,
          artistName: artistName,
          spotifyId: _spotifyId ?? '',
          durationMs: durationMs,
          outputPath: tempOutput,
          audioFilePath: _fileExists ? cleanFilePath : '',
        );

        if (result['error'] != null) {
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.trackSaveFailed(result['error'].toString()),
                  ),
                ),
              );
          }
          try {
            await Directory(tempDir.path).delete(recursive: true);
          } catch (_) {}
          return;
        }

        final treeUri = _downloadItem?.downloadTreeUri;
        final relativeDir = _downloadItem?.safRelativeDir ?? '';
        if (treeUri != null && treeUri.isNotEmpty) {
          final safUri = await PlatformBridge.createSafFileFromPath(
            treeUri: treeUri,
            relativeDir: relativeDir,
            fileName: '$baseName.lrc',
            mimeType: 'application/octet-stream',
            srcPath: tempOutput,
          );
          try {
            await Directory(tempDir.path).delete(recursive: true);
          } catch (_) {}
          if (mounted) {
            if (safUri != null) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(context.l10n.trackLyricsSaved(baseName)),
                  ),
                );
            } else {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      context.l10n.trackSaveFailed(
                        'Failed to write to storage',
                      ),
                    ),
                  ),
                );
            }
          }
        } else {
          try {
            await Directory(tempDir.path).delete(recursive: true);
          } catch (_) {}
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.trackSaveFailed('No storage access'),
                  ),
                ),
              );
          }
        }
        return;
      }

      final dir = _getFileDirectory();
      final outputPath = '$dir${Platform.pathSeparator}$baseName.lrc';

      final result = await PlatformBridge.fetchAndSaveLyrics(
        trackName: trackName,
        artistName: artistName,
        spotifyId: _spotifyId ?? '',
        durationMs: durationMs,
        outputPath: outputPath,
        audioFilePath: _fileExists ? cleanFilePath : '',
      );

      if (mounted) {
        if (result['error'] != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.trackSaveFailed(result['error'].toString()),
                ),
              ),
            );
        } else {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(context.l10n.trackLyricsSaved(baseName))),
            );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(context.l10n.trackSaveFailed(e.toString()))),
          );
      }
    }
  }

  Future<void> _reEnrichMetadata() async {
    if (!_fileExists) return;

    try {
      final artistTagMode = ref.read(settingsProvider).artistTagMode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.trackReEnrichSearching)),
      );

      final durationMs = (duration ?? 0) * 1000;
      final request = <String, dynamic>{
        'file_path': cleanFilePath,
        'cover_url': _coverUrl ?? '',
        'max_quality': true,
        'embed_lyrics': true,
        'artist_tag_mode': artistTagMode,
        'spotify_id': _spotifyId ?? '',
        'track_name': trackName,
        'artist_name': artistName,
        'album_name': albumName,
        'album_artist': albumArtist ?? '',
        'track_number': trackNumber ?? 0,
        'total_tracks': totalTracks ?? 0,
        'disc_number': discNumber ?? 0,
        'total_discs': totalDiscs ?? 0,
        'release_date': releaseDate ?? '',
        'isrc': isrc ?? '',
        'genre': genre ?? '',
        'label': label ?? '',
        'copyright': copyright ?? '',
        'composer': composer ?? '',
        'duration_ms': durationMs,
        'search_online': true,
      };

      final result = await PlatformBridge.reEnrichFile(request);
      final method = result['method'] as String?;

      final enriched = result['enriched_metadata'] as Map<String, dynamic>?;
      if (enriched != null && mounted) {
        setState(() {
          _editedMetadata = {
            'title': enriched['track_name'] ?? trackName,
            'artist': enriched['artist_name'] ?? artistName,
            'album': enriched['album_name'] ?? albumName,
            'album_artist': enriched['album_artist'] ?? albumArtist,
            'date': enriched['release_date'] ?? releaseDate,
            'track_number': enriched['track_number'] ?? trackNumber,
            'total_tracks': enriched['total_tracks'] ?? totalTracks,
            'disc_number': enriched['disc_number'] ?? discNumber,
            'total_discs': enriched['total_discs'] ?? totalDiscs,
            'isrc': enriched['isrc'] ?? isrc,
            'genre': enriched['genre'] ?? genre,
            'label': enriched['label'] ?? label,
            'copyright': enriched['copyright'] ?? copyright,
            'composer': enriched['composer'] ?? composer,
          };
        });
      }

      if (method == 'native') {
        // FLAC - handled natively by Go (SAF write-back handled in Kotlin)
        await _refreshEmbeddedCoverPreview(force: true);
        _markMetadataChanged();
        await _syncDownloadHistoryMetadata();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.trackReEnrichSuccess)),
          );
        }
      } else if (method == 'ffmpeg') {
        // MP3/Opus - need FFmpeg from Dart side
        // For SAF files, Kotlin returns temp_path + saf_uri
        final tempPath = result['temp_path'] as String?;
        final safUri = result['saf_uri'] as String?;
        final ffmpegTarget = tempPath ?? cleanFilePath;

        final downloadedCoverPath = result['cover_path'] as String?;
        String? effectiveCoverPath = downloadedCoverPath;
        String? extractedCoverPath;
        if (!_hasPath(effectiveCoverPath)) {
          try {
            final tempDir = await Directory.systemTemp.createTemp(
              'reenrich_cover_',
            );
            final coverOutput =
                '${tempDir.path}${Platform.pathSeparator}cover.jpg';
            final extracted = await PlatformBridge.extractCoverToFile(
              ffmpegTarget,
              coverOutput,
            );
            if (extracted['error'] == null) {
              effectiveCoverPath = coverOutput;
              extractedCoverPath = coverOutput;
            } else {
              try {
                await tempDir.delete(recursive: true);
              } catch (_) {}
            }
          } catch (_) {}
        }
        final metadata = (result['metadata'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v.toString()),
        );
        final lower = cleanFilePath.toLowerCase();

        String? ffmpegResult;
        if (lower.endsWith('.mp3')) {
          ffmpegResult = await FFmpegService.embedMetadataToMp3(
            mp3Path: ffmpegTarget,
            coverPath: effectiveCoverPath,
            metadata: metadata,
          );
        } else if (lower.endsWith('.m4a') || lower.endsWith('.aac')) {
          ffmpegResult = await FFmpegService.embedMetadataToM4a(
            m4aPath: ffmpegTarget,
            coverPath: effectiveCoverPath,
            metadata: metadata,
          );
        } else if (lower.endsWith('.opus') || lower.endsWith('.ogg')) {
          ffmpegResult = await FFmpegService.embedMetadataToOpus(
            opusPath: ffmpegTarget,
            coverPath: effectiveCoverPath,
            metadata: metadata,
            artistTagMode: artistTagMode,
          );
        }

        if (ffmpegResult != null && tempPath != null && safUri != null) {
          final ok = await PlatformBridge.writeTempToSaf(ffmpegResult, safUri);
          if (!ok && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.trackSaveFailed(
                    context.l10n.snackbarFailedToWriteStorage,
                  ),
                ),
              ),
            );
            if (_hasPath(downloadedCoverPath)) {
              try {
                await File(downloadedCoverPath!).delete();
              } catch (_) {}
            }
            if (_hasPath(extractedCoverPath)) {
              await _cleanupTempFileAndParent(extractedCoverPath);
            }
            if (tempPath.isNotEmpty) {
              try {
                await File(tempPath).delete();
              } catch (_) {}
            }
            return;
          }
        }

        if (tempPath != null && tempPath.isNotEmpty) {
          try {
            await File(tempPath).delete();
          } catch (_) {}
        }

        if (ffmpegResult != null) {
          await _refreshEmbeddedCoverPreview(force: true);
          _markMetadataChanged();
          await _syncDownloadHistoryMetadata();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.trackReEnrichSuccess)),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.trackReEnrichFfmpegFailed)),
          );
        }

        if (_hasPath(downloadedCoverPath)) {
          try {
            await File(downloadedCoverPath!).delete();
          } catch (_) {}
        }
        if (_hasPath(extractedCoverPath)) {
          await _cleanupTempFileAndParent(extractedCoverPath);
        }
      } else {
        if (mounted) {
          final error = result['error']?.toString() ?? 'Unknown error';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.trackSaveFailed(error))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.trackSaveFailed(e.toString()))),
        );
      }
    }
  }

  Future<void> _syncDownloadHistoryMetadata() async {
    if (_isLocalItem || _downloadItem == null) return;

    String? normalizedOrNull(String? value) {
      if (value == null) return null;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return trimmed;
    }

    try {
      await ref
          .read(downloadHistoryProvider.notifier)
          .updateMetadataForItem(
            id: _downloadItem!.id,
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            albumArtist: normalizedOrNull(albumArtist),
            isrc: normalizedOrNull(isrc),
            trackNumber: trackNumber,
            totalTracks: totalTracks,
            discNumber: discNumber,
            totalDiscs: totalDiscs,
            releaseDate: normalizedOrNull(releaseDate),
            genre: normalizedOrNull(genre),
            composer: normalizedOrNull(composer),
            label: normalizedOrNull(label),
            copyright: normalizedOrNull(copyright),
          );
    } catch (e) {
      _log.w('Failed to sync download history metadata: $e');
    }
  }

  String _cleanLrcForDisplay(String lrc) {
    final lines = lrc.split('\n');
    final cleanLines = <String>[];

    for (final line in lines) {
      var cleaned = line.trim();

      if (_lrcMetadataPattern.hasMatch(cleaned) &&
          !_lrcBackgroundLinePattern.hasMatch(cleaned)) {
        continue;
      }

      // Convert [bg:...] wrapper to a plain secondary vocal line.
      final bgMatch = _lrcBackgroundLinePattern.firstMatch(cleaned);
      if (bgMatch != null) {
        cleaned = bgMatch.group(1)?.trim() ?? '';
      }

      cleaned = cleaned.replaceAll(_lrcTimestampPattern, '').trim();
      cleaned = cleaned.replaceAll(_lrcInlineTimestampPattern, '');
      cleaned = cleaned.replaceFirst(_lrcSpeakerPrefixPattern, '');
      cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (cleaned.isNotEmpty) {
        cleanLines.add(cleaned);
      }
    }

    return cleanLines.join('\n');
  }

  Widget _buildActionButtons(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
    bool fileExists,
  ) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: fileExists
                ? () => _openFile(context, rawFilePath)
                : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(context.l10n.trackMetadataPlay),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _confirmDelete(context, ref, colorScheme),
            icon: Icon(Icons.delete_outline, color: colorScheme.error),
            label: Text(
              context.l10n.trackMetadataDelete,
              style: TextStyle(color: colorScheme.error),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ],
    );
  }

  void _showOptionsMenu(
    BuildContext screenContext,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) {
    showModalBottomSheet<void>(
      context: screenContext,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(screenContext).size.height * 0.7,
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(sheetContext.l10n.trackCopyFilePath),
                onTap: () {
                  _closeOptionsMenuAndRun(
                    sheetContext,
                    () => _copyToClipboard(screenContext, cleanFilePath),
                  );
                },
              ),
              if (_fileExists)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(sheetContext.l10n.trackEditMetadata),
                  onTap: () {
                    _closeOptionsMenuAndRun(
                      sheetContext,
                      () => _showEditMetadataSheet(
                        screenContext,
                        ref,
                        colorScheme,
                      ),
                    );
                  },
                ),
              if (!_isLocalItem && (_coverUrl != null || _fileExists))
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: Text(sheetContext.l10n.trackSaveCoverArt),
                  subtitle: Text(sheetContext.l10n.trackSaveCoverArtSubtitle),
                  onTap: () {
                    _closeOptionsMenuAndRun(sheetContext, _saveCoverArt);
                  },
                ),
              if (!_isLocalItem)
                ListTile(
                  leading: const Icon(Icons.lyrics_outlined),
                  title: Text(sheetContext.l10n.trackSaveLyrics),
                  subtitle: Text(sheetContext.l10n.trackSaveLyricsSubtitle),
                  onTap: () {
                    _closeOptionsMenuAndRun(sheetContext, _saveLyrics);
                  },
                ),
              if (_fileExists)
                ListTile(
                  leading: const Icon(Icons.travel_explore),
                  title: Text(sheetContext.l10n.trackReEnrich),
                  subtitle: Text(sheetContext.l10n.trackReEnrichOnlineSubtitle),
                  onTap: () {
                    _closeOptionsMenuAndRun(sheetContext, _reEnrichMetadata);
                  },
                ),
              if (_fileExists && _isConvertibleFormat)
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(sheetContext.l10n.trackConvertFormat),
                  subtitle: Text(sheetContext.l10n.trackConvertFormatSubtitle),
                  onTap: () {
                    _closeOptionsMenuAndRun(
                      sheetContext,
                      () => _showConvertSheet(screenContext),
                    );
                  },
                ),
              if (_fileExists && _isCueFile)
                ListTile(
                  leading: const Icon(Icons.call_split),
                  title: Text(sheetContext.l10n.cueSplitTitle),
                  subtitle: Text(sheetContext.l10n.cueSplitSubtitle),
                  onTap: () {
                    _closeOptionsMenuAndRun(
                      sheetContext,
                      () => _showCueSplitSheet(screenContext),
                    );
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.share),
                title: Text(sheetContext.l10n.trackMetadataShare),
                onTap: () {
                  _closeOptionsMenuAndRun(
                    sheetContext,
                    () => _shareFile(screenContext),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.delete, color: colorScheme.error),
                title: Text(
                  sheetContext.l10n.trackRemoveFromDevice,
                  style: TextStyle(color: colorScheme.error),
                ),
                onTap: () {
                  _closeOptionsMenuAndRun(
                    sheetContext,
                    () => _confirmDelete(screenContext, ref, colorScheme),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether the current file format supports conversion
  bool get _isConvertibleFormat {
    final lower = cleanFilePath.toLowerCase();
    return lower.endsWith('.flac') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.opus') ||
        lower.endsWith('.ogg');
  }

  /// Whether the current file is a CUE sheet (or CUE-referenced)
  bool get _isCueFile {
    if (isCueVirtualPath(rawFilePath)) return true;
    final lower = cleanFilePath.toLowerCase();
    if (lower.endsWith('.cue')) return true;
    if (_isLocalItem && _localLibraryItem != null) {
      final format = _localLibraryItem!.format ?? '';
      if (format.startsWith('cue+')) return true;
    }
    return false;
  }

  String get _currentFileFormat {
    // For CUE tracks, use the format from the library item (e.g. "cue+flac")
    if (_isCueFile && _isLocalItem && _localLibraryItem != null) {
      final format = _localLibraryItem!.format ?? '';
      if (format.startsWith('cue+')) {
        final audioFmt = format.substring(4).toUpperCase();
        return 'CUE+$audioFmt';
      }
    }
    if (_isLocalItem && _localLibraryItem != null) {
      final format = normalizeOptionalString(
        _localLibraryItem!.format,
      )?.toLowerCase().replaceAll('-', '_');
      switch (format) {
        case 'flac':
          return 'FLAC';
        case 'alac':
        case 'm4a':
          return 'M4A';
        case 'mp3':
          return 'MP3';
        case 'opus':
        case 'ogg':
          return 'Opus';
      }
    }
    final lower = cleanFilePath.toLowerCase();
    if (lower.endsWith('.flac')) return 'FLAC';
    if (lower.endsWith('.m4a')) return 'M4A';
    if (lower.endsWith('.mp3')) return 'MP3';
    if (lower.endsWith('.opus') || lower.endsWith('.ogg')) return 'Opus';
    if (lower.endsWith('.cue')) return 'CUE';
    return 'Unknown';
  }

  Map<String, String> _buildFallbackMetadata() {
    String formatIndexTag(int number, int? total) {
      if (total != null && total > 0) {
        return '$number/$total';
      }
      return number.toString();
    }

    return {
      'TITLE': trackName,
      'ARTIST': artistName,
      'ALBUM': albumName,
      if (albumArtist != null && albumArtist!.isNotEmpty)
        'ALBUMARTIST': albumArtist!,
      if (trackNumber != null)
        'TRACKNUMBER': formatIndexTag(trackNumber!, totalTracks),
      if (discNumber != null)
        'DISCNUMBER': formatIndexTag(discNumber!, totalDiscs),
      if (releaseDate != null && releaseDate!.isNotEmpty) 'DATE': releaseDate!,
      if (isrc != null && isrc!.isNotEmpty) 'ISRC': isrc!,
      if (genre != null && genre!.isNotEmpty) 'GENRE': genre!,
      if (label != null && label!.isNotEmpty) 'LABEL': label!,
      if (copyright != null && copyright!.isNotEmpty) 'COPYRIGHT': copyright!,
      if (composer != null && composer!.isNotEmpty) 'COMPOSER': composer!,
    };
  }

  Map<String, String> _mapMetadataForTagEmbed(Map<String, dynamic> source) {
    final mapped = <String, String>{};

    void put(String key, dynamic value) {
      final normalized = value?.toString().trim();
      if (normalized == null || normalized.isEmpty) return;
      mapped[key] = normalized;
    }

    put('TITLE', source['title']);
    put('ARTIST', source['artist']);
    put('ALBUM', source['album']);
    put('ALBUMARTIST', source['album_artist']);
    put('DATE', source['date']);
    put('ISRC', source['isrc']);
    put('GENRE', source['genre']);
    put('ORGANIZATION', source['label']);
    put('COPYRIGHT', source['copyright']);
    put('COMPOSER', source['composer']);
    put('COMMENT', source['comment']);
    put('LYRICS', source['lyrics']);
    put('UNSYNCEDLYRICS', source['lyrics']);

    final trackNumber = source['track_number'];
    final totalTracks = source['total_tracks'];
    if (trackNumber != null && trackNumber.toString() != '0') {
      final trackTag =
          totalTracks != null &&
              totalTracks.toString().isNotEmpty &&
              totalTracks.toString() != '0'
          ? '${trackNumber.toString()}/${totalTracks.toString()}'
          : trackNumber;
      put('TRACKNUMBER', trackTag);
    }
    final discNumber = source['disc_number'];
    final totalDiscs = source['total_discs'];
    if (discNumber != null && discNumber.toString() != '0') {
      final discTag =
          totalDiscs != null &&
              totalDiscs.toString().isNotEmpty &&
              totalDiscs.toString() != '0'
          ? '${discNumber.toString()}/${totalDiscs.toString()}'
          : discNumber;
      put('DISCNUMBER', discTag);
    }

    return mapped;
  }

  String _buildConvertedQualityLabel(String targetFormat, String bitrate) {
    final upper = targetFormat.toUpperCase();
    if (upper == 'ALAC' || upper == 'FLAC') {
      return '$upper Lossless';
    }
    final normalizedBitrate = bitrate.trim().toLowerCase();
    return '$upper $normalizedBitrate';
  }

  String? _extractLossyBitrateLabel(String? quality) {
    if (quality == null || quality.isEmpty) return null;
    final match = RegExp(
      r'(\d+)\s*k(?:bps)?',
      caseSensitive: false,
    ).firstMatch(quality);
    if (match == null) return null;
    return '${match.group(1)}kbps';
  }

  String _extractFileNameFromPathOrUri(String pathOrUri) {
    if (pathOrUri.isEmpty) return '';
    try {
      if (pathOrUri.startsWith('content://')) {
        final uri = Uri.parse(pathOrUri);
        if (uri.pathSegments.isNotEmpty) {
          var last = Uri.decodeComponent(uri.pathSegments.last);
          if (last.contains('/')) {
            last = last.split('/').last;
          }
          if (last.contains(':')) {
            last = last.split(':').last;
          }
          if (last.isNotEmpty) return last;
        }
      }
    } catch (_) {}

    final normalized = pathOrUri.replaceAll('\\', '/');
    if (normalized.contains('/')) {
      return normalized.split('/').last;
    }
    return normalized;
  }

  void _showConvertSheet(BuildContext context) {
    final currentFormat = _currentFileFormat;
    final isLosslessSource = currentFormat == 'FLAC' || currentFormat == 'M4A';

    final formats = <String>[];
    if (currentFormat == 'FLAC') {
      formats.addAll(['ALAC', 'MP3', 'Opus']);
    } else if (currentFormat == 'M4A') {
      formats.addAll(['FLAC', 'MP3', 'Opus']);
    } else if (currentFormat == 'MP3') {
      formats.add('Opus');
    } else if (currentFormat == 'Opus') {
      formats.add('MP3');
    } else {
      formats.addAll(['MP3', 'Opus']);
    }

    String selectedFormat = formats.first;
    String selectedBitrate = selectedFormat == 'Opus' ? '128k' : '320k';
    bool isLosslessTarget =
        selectedFormat == 'ALAC' || selectedFormat == 'FLAC';

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final colorScheme = Theme.of(context).colorScheme;
            final bitrates = ['128k', '192k', '256k', '320k'];

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.4,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n.trackConvertTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      context.l10n.trackConvertTargetFormat,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: formats.map((format) {
                        final isSelected = format == selectedFormat;
                        return ChoiceChip(
                          label: Text(format),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setSheetState(() {
                                selectedFormat = format;
                                isLosslessTarget =
                                    format == 'ALAC' || format == 'FLAC';
                                if (!isLosslessTarget) {
                                  selectedBitrate = format == 'Opus'
                                      ? '128k'
                                      : '320k';
                                }
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),

                    if (!isLosslessTarget) ...[
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.trackConvertBitrate,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: bitrates.map((br) {
                          final isSelected = br == selectedBitrate;
                          return ChoiceChip(
                            label: Text(br),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setSheetState(() => selectedBitrate = br);
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ],

                    if (isLosslessTarget && isLosslessSource) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(
                            Icons.verified,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            context.l10n.trackConvertLosslessHint,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.primary),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _confirmAndConvert(
                            context: this.context,
                            sourceFormat: currentFormat,
                            targetFormat: selectedFormat,
                            bitrate: selectedBitrate,
                          );
                        },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          isLosslessTarget
                              ? '$currentFormat  ->  $selectedFormat (Lossless)'
                              : '$currentFormat  ->  $selectedFormat @ $selectedBitrate',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showCueSplitSheet(BuildContext context) async {
    var cuePath = cleanFilePath;
    final trackSuffix = RegExp(r'#track\d+$');
    if (trackSuffix.hasMatch(cuePath)) {
      cuePath = cuePath.replaceFirst(trackSuffix, '');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.snackbarLoadingCueSheet)),
    );

    try {
      final cueInfo = await PlatformBridge.parseCueSheet(cuePath);

      if (!mounted) return;
      _hideCurrentSnackBar();

      if (cueInfo.containsKey('error')) {
        _showSnackBarMessage(_l10nCueSplitNoAudioFile);
        return;
      }

      final album = cueInfo['album'] as String? ?? 'Unknown Album';
      final artist = cueInfo['artist'] as String? ?? 'Unknown Artist';
      final audioPath = cueInfo['audio_path'] as String? ?? '';
      final genre = cueInfo['genre'] as String? ?? '';
      final date = cueInfo['date'] as String? ?? '';
      final tracksRaw = cueInfo['tracks'] as List<dynamic>? ?? [];

      if (audioPath.isEmpty) {
        _showSnackBarMessage(_l10nCueSplitNoAudioFile);
        return;
      }

      final tracks = tracksRaw
          .map((t) => CueSplitTrackInfo.fromJson(t as Map<String, dynamic>))
          .toList();

      if (tracks.isEmpty) {
        _showSnackBarMessage(_l10nCueSplitFailed);
        return;
      }

      if (!mounted) return;

      showModalBottomSheet<void>(
        context: this.context,
        useRootNavigator: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) {
          final colorScheme = Theme.of(sheetContext).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    sheetContext.l10n.cueSplitTitle,
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    sheetContext.l10n.cueSplitAlbum(album),
                    style: Theme.of(sheetContext).textTheme.bodyMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sheetContext.l10n.cueSplitArtist(artist),
                    style: Theme.of(sheetContext).textTheme.bodyMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sheetContext.l10n.cueSplitTrackCount(tracks.length),
                    style: Theme.of(sheetContext).textTheme.bodyMedium
                        ?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: tracks.length,
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        final duration = track.endSec > 0
                            ? track.endSec - track.startSec
                            : 0.0;
                        final durationStr = duration > 0
                            ? '${(duration ~/ 60).toString().padLeft(2, '0')}:${(duration.toInt() % 60).toString().padLeft(2, '0')}'
                            : '';
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: colorScheme.primaryContainer,
                            child: Text(
                              '${track.number}',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          title: Text(
                            track.title,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: track.artist.isNotEmpty
                              ? Text(
                                  track.artist,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          trailing: durationStr.isNotEmpty
                              ? Text(
                                  durationStr,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _confirmAndSplitCue(
                          context: this.context,
                          audioPath: audioPath,
                          album: album,
                          artist: artist,
                          genre: genre,
                          date: date,
                          tracks: tracks,
                        );
                      },
                      icon: const Icon(Icons.call_split),
                      label: Text(sheetContext.l10n.cueSplitButton),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      _hideCurrentSnackBar();
      _showSnackBarMessage(_l10nCueSplitFailed);
      _log.e('Failed to parse CUE sheet: $e');
    }
  }

  void _confirmAndSplitCue({
    required BuildContext context,
    required String audioPath,
    required String album,
    required String artist,
    required String genre,
    required String date,
    required List<CueSplitTrackInfo> tracks,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(dialogContext.l10n.cueSplitConfirmTitle),
          content: Text(
            dialogContext.l10n.cueSplitConfirmMessage(album, tracks.length),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(dialogContext.l10n.dialogCancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _performCueSplit(
                  audioPath: audioPath,
                  album: album,
                  artist: artist,
                  genre: genre,
                  date: date,
                  tracks: tracks,
                );
              },
              child: Text(dialogContext.l10n.cueSplitButton),
            ),
          ],
        );
      },
    );
  }

  Future<Directory> _resolvePersistentCueSplitOutputDir() async {
    final settings = ref.read(settingsProvider);
    final queueState = ref.read(downloadQueueProvider);
    final configuredOutputDir = queueState.outputDir.trim();
    if (settings.storageMode != 'saf' &&
        configuredOutputDir.isNotEmpty &&
        !isContentUri(configuredOutputDir)) {
      final dir = Directory(configuredOutputDir);
      await dir.create(recursive: true);
      return dir;
    }

    if (Platform.isAndroid) {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final musicDir = Directory(
          '${externalDir.parent.parent.parent.parent.path}'
          '${Platform.pathSeparator}Music'
          '${Platform.pathSeparator}SpotiFLAC',
        );
        await musicDir.create(recursive: true);
        return musicDir;
      }
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final fallbackDir = Directory(
      '${docsDir.path}${Platform.pathSeparator}SpotiFLAC',
    );
    await fallbackDir.create(recursive: true);
    return fallbackDir;
  }

  Future<List<String>?> _exportCueSplitOutputsToSaf({
    required List<String> outputPaths,
    required String treeUri,
    required String relativeDir,
  }) async {
    final exportedUris = <String>[];
    for (final path in outputPaths) {
      final fileName = path.split(Platform.pathSeparator).last;
      final safUri = await PlatformBridge.createSafFileFromPath(
        treeUri: treeUri,
        relativeDir: relativeDir,
        fileName: fileName,
        mimeType: audioMimeTypeForPath(path),
        srcPath: path,
      );
      if (safUri != null && safUri.isNotEmpty) {
        exportedUris.add(safUri);
      }
    }
    return exportedUris.isEmpty ? null : exportedUris;
  }

  Future<void> _performCueSplit({
    required String audioPath,
    required String album,
    required String artist,
    required String genre,
    required String date,
    required List<CueSplitTrackInfo> tracks,
  }) async {
    if (_isConverting) return;
    setState(() => _isConverting = true);

    String? safTempAudioPath;
    Directory? tempSplitDir;
    try {
      // For SAF content:// audio paths, copy to temp for FFmpeg processing
      String workingAudioPath = audioPath;
      final isSafSource = isContentUri(audioPath);
      if (isSafSource) {
        final tempPath = await PlatformBridge.copyContentUriToTemp(audioPath);
        if (tempPath == null || tempPath.isEmpty) {
          throw Exception('Failed to copy SAF audio file to temp');
        }
        safTempAudioPath = tempPath;
        workingAudioPath = tempPath;
      }

      final String outputDir;
      final treeUri = !_isLocalItem
          ? (_downloadItem?.downloadTreeUri ?? '')
          : '';
      final relativeDir = !_isLocalItem
          ? (_downloadItem?.safRelativeDir ?? '')
          : '';
      final writeBackToSaf = isSafSource && treeUri.isNotEmpty;
      if (writeBackToSaf) {
        final tempDir = await getTemporaryDirectory();
        tempSplitDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}'
          'cue_split_${DateTime.now().millisecondsSinceEpoch}',
        );
        await tempSplitDir.create(recursive: true);
        outputDir = tempSplitDir.path;
      } else if (isSafSource) {
        final persistentDir = await _resolvePersistentCueSplitOutputDir();
        outputDir = persistentDir.path;
      } else {
        outputDir = File(audioPath).parent.path;
      }

      if (!mounted) return;
      _showLongSnackBarMessage(_l10nCueSplitSplitting(1, tracks.length));

      String? coverPath;
      try {
        final tempDir = await getTemporaryDirectory();
        final coverOutput =
            '${tempDir.path}${Platform.pathSeparator}cue_cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final coverResult = await PlatformBridge.extractCoverToFile(
          workingAudioPath,
          coverOutput,
        );
        if (coverResult['error'] == null) {
          coverPath = coverOutput;
        }
      } catch (_) {}

      final albumMetadata = <String, String>{
        'artist': artist,
        'album': album,
        'genre': genre,
        'date': date,
      };

      final outputPaths = await FFmpegService.splitCueToTracks(
        audioPath: workingAudioPath,
        outputDir: outputDir,
        tracks: tracks,
        albumMetadata: albumMetadata,
        coverPath: coverPath,
        onProgress: (current, total) {
          if (mounted) {
            _hideCurrentSnackBar();
            _showLongSnackBarMessage(_l10nCueSplitSplitting(current, total));
          }
        },
      );

      var finalOutputPaths = outputPaths;

      // Embed cover art into split FLAC files using Go backend
      if (coverPath != null && finalOutputPaths != null) {
        for (final path in finalOutputPaths) {
          if (path.toLowerCase().endsWith('.flac')) {
            try {
              // Only send the cover_path field — EditFlacFields uses
              // field-presence semantics, so omitting artist/album_artist
              // means those keys won't be rewritten.  This preserves any
              // existing split artist Vorbis Comments.
              await PlatformBridge.editFileMetadata(path, {
                'cover_path': coverPath,
              });
            } catch (e) {
              _log.w('Failed to embed cover to split track: $e');
            }
          }
        }
      }

      if (writeBackToSaf && finalOutputPaths != null) {
        final exportedUris = await _exportCueSplitOutputsToSaf(
          outputPaths: finalOutputPaths,
          treeUri: treeUri,
          relativeDir: relativeDir,
        );
        finalOutputPaths = exportedUris;
      }

      if (coverPath != null) {
        try {
          await File(coverPath).delete();
        } catch (_) {}
      }

      if (mounted) {
        _hideCurrentSnackBar();
        if (finalOutputPaths != null && finalOutputPaths.isNotEmpty) {
          _showSnackBarMessage(_l10nCueSplitSuccess(finalOutputPaths.length));
        } else {
          _showSnackBarMessage(_l10nCueSplitFailed);
        }
      }
    } catch (e) {
      _log.e('CUE split failed: $e');
      if (mounted) {
        _hideCurrentSnackBar();
        _showSnackBarMessage(_l10nCueSplitFailed);
      }
    } finally {
      if (safTempAudioPath != null) {
        try {
          await File(safTempAudioPath).delete();
        } catch (_) {}
      }
      if (tempSplitDir != null) {
        try {
          await tempSplitDir.delete(recursive: true);
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _isConverting = false);
      }
    }
  }

  void _confirmAndConvert({
    required BuildContext context,
    required String sourceFormat,
    required String targetFormat,
    required String bitrate,
  }) {
    final isLossless =
        targetFormat.toUpperCase() == 'ALAC' ||
        targetFormat.toUpperCase() == 'FLAC';
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(dialogContext.l10n.trackConvertConfirmTitle),
          content: Text(
            isLossless
                ? dialogContext.l10n.trackConvertConfirmMessageLossless(
                    sourceFormat,
                    targetFormat,
                  )
                : dialogContext.l10n.trackConvertConfirmMessage(
                    sourceFormat,
                    targetFormat,
                    bitrate,
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(dialogContext.l10n.dialogCancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _performConversion(
                  targetFormat: targetFormat,
                  bitrate: bitrate,
                );
              },
              child: Text(dialogContext.l10n.trackConvertFormat),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performConversion({
    required String targetFormat,
    required String bitrate,
  }) async {
    if (_isConverting) return;
    setState(() => _isConverting = true);

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.trackConvertConverting)),
      );

      final settings = ref.read(settingsProvider);
      final shouldEmbedLyrics =
          settings.embedLyrics && settings.lyricsMode != 'external';
      final metadata = _buildFallbackMetadata();
      try {
        final result = await PlatformBridge.readFileMetadata(cleanFilePath);
        if (result['error'] == null) {
          mergePlatformMetadataForTagEmbed(target: metadata, source: result);
        } else {
          _log.w('readFileMetadata returned error, using fallback metadata');
        }
      } catch (e) {
        _log.w('readFileMetadata threw, using fallback metadata: $e');
      }
      await ensureLyricsMetadataForConversion(
        metadata: metadata,
        sourcePath: cleanFilePath,
        shouldEmbedLyrics: shouldEmbedLyrics,
        trackName: trackName,
        artistName: artistName,
        spotifyId: _spotifyId ?? '',
        durationMs: (duration ?? 0) * 1000,
      );

      String? coverPath;
      try {
        final tempDir = await getTemporaryDirectory();
        final coverOutput =
            '${tempDir.path}${Platform.pathSeparator}convert_cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final coverResult = await PlatformBridge.extractCoverToFile(
          cleanFilePath,
          coverOutput,
        );
        if (coverResult['error'] == null) {
          coverPath = coverOutput;
        }
      } catch (_) {}

      String workingPath = cleanFilePath;
      final isSaf = _isSafFile;
      String? safTempPath;

      if (isSaf) {
        safTempPath = await PlatformBridge.copyContentUriToTemp(cleanFilePath);
        if (safTempPath == null) {
          if (mounted) {
            setState(() => _isConverting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.trackConvertFailed)),
            );
          }
          return;
        }
        workingPath = safTempPath;
      }

      final newPath = await FFmpegService.convertAudioFormat(
        inputPath: workingPath,
        targetFormat: targetFormat.toLowerCase(),
        bitrate: bitrate,
        metadata: metadata,
        coverPath: coverPath,
        artistTagMode: ref.read(settingsProvider).artistTagMode,
        deleteOriginal: !isSaf,
      );

      if (coverPath != null) {
        try {
          await File(coverPath).delete();
        } catch (_) {}
      }

      if (newPath == null) {
        if (safTempPath != null) {
          try {
            await File(safTempPath).delete();
          } catch (_) {}
        }
        if (mounted) {
          setState(() => _isConverting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.trackConvertFailed)),
          );
        }
        return;
      }

      final newQuality = _buildConvertedQualityLabel(targetFormat, bitrate);

      if (isSaf) {
        String? treeUri;
        String relativeDir = '';
        String oldFileName = '';
        if (_isLocalItem) {
          final uri = Uri.parse(cleanFilePath);
          final pathSegments = uri.pathSegments;
          final treeIdx = pathSegments.indexOf('tree');
          final docIdx = pathSegments.indexOf('document');
          if (treeIdx >= 0 && treeIdx + 1 < pathSegments.length) {
            final treeId = pathSegments[treeIdx + 1];
            treeUri =
                'content://${uri.authority}/tree/${Uri.encodeComponent(treeId)}';
          }
          if (docIdx >= 0 && docIdx + 1 < pathSegments.length) {
            final docPath = Uri.decodeFull(pathSegments[docIdx + 1]);
            final slashIdx = docPath.lastIndexOf('/');
            if (slashIdx >= 0) {
              oldFileName = docPath.substring(slashIdx + 1);
              final treeId = treeIdx >= 0 && treeIdx + 1 < pathSegments.length
                  ? Uri.decodeFull(pathSegments[treeIdx + 1])
                  : '';
              if (treeId.isNotEmpty && docPath.startsWith(treeId)) {
                final afterTree = docPath.substring(treeId.length);
                final trimmed = afterTree.startsWith('/')
                    ? afterTree.substring(1)
                    : afterTree;
                final lastSlash = trimmed.lastIndexOf('/');
                relativeDir = lastSlash >= 0
                    ? trimmed.substring(0, lastSlash)
                    : '';
              }
            } else {
              oldFileName = docPath;
            }
          }
        } else {
          treeUri = _downloadItem?.downloadTreeUri;
          relativeDir = _downloadItem?.safRelativeDir ?? '';
          oldFileName =
              (_downloadItem?.safFileName != null &&
                  _downloadItem!.safFileName!.isNotEmpty)
              ? _downloadItem!.safFileName!
              : _extractFileNameFromPathOrUri(cleanFilePath);
        }
        if (treeUri == null || treeUri.isEmpty) {
          try {
            await File(newPath).delete();
          } catch (_) {}
          if (safTempPath != null) {
            try {
              await File(safTempPath).delete();
            } catch (_) {}
          }
          if (mounted) {
            setState(() => _isConverting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.trackConvertFailed)),
            );
          }
          return;
        }

        final dotIdx = oldFileName.lastIndexOf('.');
        final baseName = dotIdx > 0
            ? oldFileName.substring(0, dotIdx)
            : oldFileName;
        String newExt;
        String mimeType;
        switch (targetFormat.toLowerCase()) {
          case 'opus':
            newExt = '.opus';
            mimeType = 'audio/opus';
            break;
          case 'alac':
            newExt = '.m4a';
            mimeType = 'audio/mp4';
            break;
          case 'flac':
            newExt = '.flac';
            mimeType = 'audio/flac';
            break;
          default:
            newExt = '.mp3';
            mimeType = 'audio/mpeg';
            break;
        }
        final newFileName = '$baseName$newExt';

        final safUri = await PlatformBridge.createSafFileFromPath(
          treeUri: treeUri,
          relativeDir: relativeDir,
          fileName: newFileName,
          mimeType: mimeType,
          srcPath: newPath,
        );

        if (safUri == null || safUri.isEmpty) {
          try {
            await File(newPath).delete();
          } catch (_) {}
          if (safTempPath != null) {
            try {
              await File(safTempPath).delete();
            } catch (_) {}
          }
          if (mounted) {
            setState(() => _isConverting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.trackConvertFailed)),
            );
          }
          return;
        }

        final deletedOriginal = await PlatformBridge.safDelete(
          cleanFilePath,
        ).catchError((_) => false);
        if (deletedOriginal != true) {
          _log.w('Converted SAF file created but failed deleting original URI');
        }

        if (!_isLocalItem) {
          await HistoryDatabase.instance.updateFilePath(
            _downloadItem!.id,
            safUri,
            newSafFileName: newFileName,
            newQuality: newQuality,
            clearAudioSpecs: true,
          );
          await ref.read(downloadHistoryProvider.notifier).reloadFromStorage();
        } else {
          await LibraryDatabase.instance.replaceWithConvertedItem(
            item: _localLibraryItem!,
            newFilePath: safUri,
            targetFormat: targetFormat,
            bitrate: bitrate,
          );
          await ref.read(localLibraryProvider.notifier).reloadFromStorage();
        }

        try {
          await File(newPath).delete();
        } catch (_) {}
        if (safTempPath != null) {
          try {
            await File(safTempPath).delete();
          } catch (_) {}
        }
      } else {
        if (!_isLocalItem) {
          await HistoryDatabase.instance.updateFilePath(
            _downloadItem!.id,
            newPath,
            newQuality: newQuality,
            clearAudioSpecs: true,
          );
          await ref.read(downloadHistoryProvider.notifier).reloadFromStorage();
        } else {
          await LibraryDatabase.instance.replaceWithConvertedItem(
            item: _localLibraryItem!,
            newFilePath: newPath,
            targetFormat: targetFormat,
            bitrate: bitrate,
          );
          await ref.read(localLibraryProvider.notifier).reloadFromStorage();
        }
      }

      if (mounted) {
        setState(() => _isConverting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.trackConvertSuccess(targetFormat)),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConverting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.trackSaveFailed(e.toString()))),
        );
      }
    }
  }

  void _showEditMetadataSheet(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) async {
    Map<String, dynamic>? fileMetadata;
    try {
      final result = await PlatformBridge.readFileMetadata(cleanFilePath);
      if (result['error'] == null) {
        fileMetadata = result;
      }
    } catch (e) {
      debugPrint('readFileMetadata failed, using item data: $e');
    }

    String val(String key, String? fallback) {
      final v = fileMetadata?[key]?.toString();
      return (v != null && v.isNotEmpty) ? v : (fallback ?? '');
    }

    final initialValues = <String, String>{
      'title': val('title', trackName),
      'artist': val('artist', artistName),
      'album': val('album', albumName),
      'album_artist': val('album_artist', albumArtist),
      'date': val('date', releaseDate),
      'track_number': (fileMetadata?['track_number'] ?? trackNumber ?? '')
          .toString(),
      'total_tracks': (fileMetadata?['total_tracks'] ?? totalTracks ?? '')
          .toString(),
      'disc_number': (fileMetadata?['disc_number'] ?? discNumber ?? '')
          .toString(),
      'total_discs': (fileMetadata?['total_discs'] ?? totalDiscs ?? '')
          .toString(),
      'genre': val('genre', genre),
      'isrc': val('isrc', isrc),
      'label': val('label', label),
      'copyright': val('copyright', copyright),
      'composer': val('composer', composer),
      'comment': fileMetadata?['comment']?.toString() ?? '',
      'lyrics': fileMetadata?['lyrics']?.toString() ?? '',
    };

    final initialDurationSeconds =
        readPositiveInt(fileMetadata?['duration']) ?? duration ?? 0;

    if (!context.mounted) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => _EditMetadataSheet(
        colorScheme: colorScheme,
        initialValues: initialValues,
        filePath: cleanFilePath,
        sourceTrackId: _spotifyId,
        durationMs: initialDurationSeconds > 0
            ? initialDurationSeconds * 1000
            : 0,
        artistTagMode: ref.read(settingsProvider).artistTagMode,
      ),
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text(this.context.l10n.snackbarMetadataSaved)),
      );
      try {
        final refreshed = await PlatformBridge.readFileMetadata(cleanFilePath);
        final refreshedLyrics = refreshed['lyrics']?.toString().trim() ?? '';
        setState(() {
          _editedMetadata = refreshed;
          _lyricsError = null;
          _isInstrumental = false;
          _embeddedLyricsChecked = true;
          if (refreshedLyrics.isNotEmpty) {
            _lyrics = _cleanLrcForDisplay(refreshedLyrics);
            _rawLyrics = refreshedLyrics;
            _lyricsSource = 'Embedded';
            _lyricsEmbedded = true;
          } else {
            _lyrics = null;
            _rawLyrics = null;
            _lyricsSource = null;
            _lyricsEmbedded = false;
          }
        });
      } catch (_) {
        setState(() {});
      }
      await _refreshEmbeddedCoverPreview(force: true);
      _markMetadataChanged();
      await _syncDownloadHistoryMetadata();
    }
  }

  void _confirmDelete(
    BuildContext screenContext,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) {
    showDialog<void>(
      context: screenContext,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.trackDeleteConfirmTitle),
        content: Text(dialogContext.l10n.trackDeleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.dialogCancel),
          ),
          TextButton(
            onPressed: () async {
              if (_isLocalItem) {
                if (_isCueVirtualTrack && _localLibraryItem != null) {
                  await ref
                      .read(localLibraryProvider.notifier)
                      .removeItem(_localLibraryItem!.id);
                } else {
                  try {
                    await deleteFile(cleanFilePath);
                  } catch (e) {
                    debugPrint('Failed to delete file: $e');
                  }
                  if (_localLibraryItem != null) {
                    await ref
                        .read(localLibraryProvider.notifier)
                        .removeItem(_localLibraryItem!.id);
                  }
                }
              } else {
                try {
                  await deleteFile(cleanFilePath);
                } catch (e) {
                  debugPrint('Failed to delete file: $e');
                }

                ref
                    .read(downloadHistoryProvider.notifier)
                    .removeFromHistory(_downloadItem!.id);
              }

              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop(true);
                }
              });
            },
            child: Text(
              dialogContext.l10n.dialogDelete,
              style: TextStyle(color: colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _closeOptionsMenuAndRun(BuildContext sheetContext, VoidCallback action) {
    Navigator.pop(sheetContext);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      action();
    });
  }

  Future<void> _openFile(BuildContext context, String filePath) async {
    if (isCueVirtualPath(filePath)) {
      _showCueVirtualTrackSnackBar(context);
      return;
    }
    try {
      await ref
          .read(playbackProvider.notifier)
          .playLocalPath(
            path: filePath,
            title: trackName,
            artist: artistName,
            album: albumName,
            coverUrl: _coverUrl ?? '',
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.snackbarCannotOpenFile(e.toString())),
          ),
        );
      }
    }
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.trackCopiedToClipboard),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareFile(BuildContext context) async {
    if (_isCueVirtualTrack) {
      _showCueVirtualTrackSnackBar(context);
      return;
    }

    String sharePath = cleanFilePath;
    if (!await fileExists(sharePath)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.snackbarFileNotFound)),
        );
      }
      return;
    }

    final shareTitle = '$trackName - $artistName';

    // For SAF content URIs, use native share intent directly (zero-copy)
    if (isContentUri(sharePath)) {
      try {
        await PlatformBridge.shareContentUri(sharePath, title: shareTitle);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.snackbarCannotOpenFile('Failed to share file'),
              ),
            ),
          );
        }
      }
      return;
    }

    await SharePlus.instance.share(
      ShareParams(files: [XFile(sharePath)], text: shareTitle),
    );
  }

  String _formatFullDate(DateTime date) {
    return '${date.day} ${_months[date.month - 1]} ${date.year}, '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  IconData _getServiceIcon(String service) {
    switch (service.toLowerCase()) {
      case 'tidal':
        return Icons.waves;
      case 'qobuz':
        return Icons.album;
      case 'amazon':
        return Icons.shopping_cart;
      default:
        return Icons.cloud_download;
    }
  }

  Color _getServiceColor(String service, ColorScheme colorScheme) {
    switch (service.toLowerCase()) {
      case 'tidal':
        return const Color(0xFF0077B5);
      case 'qobuz':
        return const Color(0xFF0052CC);
      case 'amazon':
        return const Color(0xFFFF9900);
      default:
        return colorScheme.primary;
    }
  }
}
