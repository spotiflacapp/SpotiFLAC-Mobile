import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:spotiflac_android/services/conversion_library_service.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/services/ffmpeg_service.dart';
import 'package:spotiflac_android/services/replaygain_service.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';
import 'package:spotiflac_android/utils/audio_conversion_utils.dart';
import 'package:spotiflac_android/utils/audio_format_utils.dart';
import 'package:spotiflac_android/utils/cover_art_utils.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/utils/lyrics_metadata_helper.dart';
import 'package:spotiflac_android/utils/mime_utils.dart';
import 'package:spotiflac_android/utils/image_cache_utils.dart';

import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/utils/user_facing_error.dart';
import 'package:spotiflac_android/utils/int_utils.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/utils/re_enrich_release_policy.dart';
import 'package:spotiflac_android/theme/cover_palette.dart' show HeaderPalette;
import 'package:spotiflac_android/widgets/album_detail_header.dart'
    show HeaderMetaRow, HeaderMetaItem;
import 'package:spotiflac_android/widgets/audio_analysis_widget.dart';
import 'package:spotiflac_android/widgets/batch_convert_sheet.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';
import 'package:spotiflac_android/widgets/open_on_platform_sheet.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/constants/music_services.dart';
import 'package:spotiflac_android/screens/collapsing_header_scroll_mixin.dart';
import 'package:spotiflac_android/screens/downloaded_album_screen.dart';
import 'package:spotiflac_android/screens/local_album_screen.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';

part 'track_metadata_screen_cover.dart';
part 'track_metadata_screen_display.dart';
part 'track_metadata_screen_menu.dart';

part 'track_metadata_edit_sheet.dart';
part 'track_metadata_cards.dart';
part 'track_metadata_lyrics.dart';
part 'track_metadata_convert.dart';
part 'track_metadata_actions.dart';

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

class _TrackMetadataScreenState extends ConsumerState<TrackMetadataScreen>
    with CollapsingHeaderScrollMixin<TrackMetadataScreen> {
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
  String? _resolvedAudioFormat;
  String? _embeddedCoverPreviewPath;
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

  @override
  void initState() {
    super.initState();
    _currentDownloadItem = widget.item;
    _currentLocalLibraryItem = widget.localItem;
    _currentNavigationIndex = widget.navigationIndex;
    _checkFile();
  }

  @override
  void dispose() {
    unawaited(_cleanupTempFileAndParentIfNotCached(_embeddedCoverPreviewPath));
    super.dispose();
  }

  /// setState is @protected, so the extension part files route rebuilds
  /// through this forwarder.
  void _setState(VoidCallback fn) => setState(fn);

  @override
  double calculateExpandedHeight(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
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
      } else if (mounted &&
          generation == _metadataLoadGeneration &&
          filePath == cleanFilePath) {
        final localCoverExists =
            _hasPath(_localCoverPath) && await fileExists(_localCoverPath!);
        if (!mounted ||
            generation != _metadataLoadGeneration ||
            filePath != cleanFilePath) {
          return;
        }
        if (!localCoverExists && !_hasPath(_coverUrl)) {
          unawaited(_refreshEmbeddedCoverPreview());
        }
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
      final metadata = await PlatformBridge.readDisplayAudioMetadata(
        sourcePath,
      );
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
      final resolvedFormat = detectedAudioFormatFromMetadata(metadata);
      final storedFormat = _isLocalItem
          ? _localLibraryItem?.format
          : _downloadItem?.format;
      final formatChanged =
          resolvedFormat != null &&
          resolvedFormat != normalizeAudioFormatValue(storedFormat);
      // Lossless files carry an average bitrate too (computed by the backend
      // from file size / duration) — useful for spotting fake 24-bit rips.
      final resolvedBitrate = _readPlausibleBitrateKbps(
        metadata['bitrate'] ?? metadata['bit_rate'],
      );
      final resolvedDuration = readPositiveInt(metadata['duration']);
      final resolvedAlbum = metadata['album']?.toString();
      final resolvedTitle = metadata['title']?.toString();
      final resolvedArtist = metadata['artist']?.toString();
      final resolvedAlbumArtist = metadata['album_artist']?.toString();
      final resolvedDate = metadata['date']?.toString();
      final resolvedGenre = metadata['genre']?.toString();
      final resolvedQuality = _displayQualityForValues(
        format: resolvedFormat ?? _storedAudioFormat,
        bitDepth: resolvedBitDepth ?? bitDepth,
        sampleRate: resolvedSampleRate ?? sampleRate,
        bitrateKbps: resolvedBitrate ?? _audioBitrate,
        storedQuality: _quality,
      );

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
      final resolvedISRC = metadata['isrc']?.toString();
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
      // The file is the source of truth for edited tags: an edit writes the
      // new value into the file, but the cached history item may still carry
      // the old one. Prefer the file value whenever present so re-opening the
      // screen reflects the latest saved tags instead of the stale model.
      // (Empty file values never override the model, so nothing is hidden.)
      bool present(String? v) => v != null && v.trim().isNotEmpty;
      final fileHasTitle = present(resolvedTitle);
      final fileHasArtist = present(resolvedArtist);
      final fileHasAlbumArtist = present(resolvedAlbumArtist);
      final fileHasAlbum = present(resolvedAlbum);
      final fileHasDate = present(resolvedDate);
      final fileHasGenre = present(resolvedGenre);
      final fileHasComposer = present(resolvedComposer);
      final fileHasCopyright = present(resolvedCopyright);
      final fileHasISRC = present(resolvedISRC);
      final fileHasLabel = present(resolvedLabel);
      final fileHasTrackNumber =
          resolvedTrackNumber != null && resolvedTrackNumber > 0;
      final fileHasTotalTracks =
          resolvedTotalTracks != null && resolvedTotalTracks > 0;
      final fileHasDiscNumber =
          resolvedDiscNumber != null && resolvedDiscNumber > 0;
      final fileHasTotalDiscs =
          resolvedTotalDiscs != null && resolvedTotalDiscs > 0;

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
      final localItem = _localLibraryItem;
      final localAudioMetadataChanged =
          localItem != null &&
          ((resolvedBitDepth != null &&
                  resolvedBitDepth != localItem.bitDepth) ||
              (resolvedSampleRate != null &&
                  resolvedSampleRate != localItem.sampleRate) ||
              (resolvedBitrate != null &&
                  resolvedBitrate != localItem.bitrate) ||
              needsDuration ||
              formatChanged);

      if ((resolvedBitDepth != null ||
              resolvedSampleRate != null ||
              resolvedFormat != null ||
              fileHasTitle ||
              fileHasArtist ||
              fileHasAlbumArtist ||
              fileHasAlbum ||
              fileHasDate ||
              fileHasGenre ||
              needsDuration ||
              fileHasTrackNumber ||
              fileHasTotalTracks ||
              fileHasDiscNumber ||
              fileHasTotalDiscs ||
              fileHasComposer ||
              fileHasISRC ||
              fileHasLabel ||
              fileHasCopyright ||
              isPlaceholderQualityLabel(_quality)) &&
          mounted) {
        setState(() {
          _resolvedAudioFormat = resolvedFormat;
          _editedMetadata = {
            ...?_editedMetadata,
            // ignore: use_null_aware_elements
            if (resolvedBitDepth != null) 'bit_depth': resolvedBitDepth,
            // ignore: use_null_aware_elements
            if (resolvedSampleRate != null) 'sample_rate': resolvedSampleRate,
            if (fileHasTitle) 'title': resolvedTitle,
            if (fileHasArtist) 'artist': resolvedArtist,
            if (fileHasAlbumArtist) 'album_artist': resolvedAlbumArtist,
            if (fileHasAlbum) 'album': resolvedAlbum,
            if (fileHasDate) 'date': resolvedDate,
            if (fileHasGenre) 'genre': resolvedGenre,
            if (needsDuration) 'duration': resolvedDuration,
            if (fileHasTrackNumber) 'track_number': resolvedTrackNumber,
            if (fileHasTotalTracks) 'total_tracks': resolvedTotalTracks,
            if (fileHasDiscNumber) 'disc_number': resolvedDiscNumber,
            if (fileHasTotalDiscs) 'total_discs': resolvedTotalDiscs,
            if (fileHasComposer) 'composer': resolvedComposer,
            if (fileHasISRC) 'isrc': resolvedISRC,
            if (fileHasLabel) 'label': resolvedLabel,
            if (fileHasCopyright) 'copyright': resolvedCopyright,
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
      } else if (_isLocalItem && localAudioMetadataChanged) {
        await LibraryDatabase.instance.updateAudioMetadata(
          localItem.id,
          duration: resolvedDuration,
          bitDepth: resolvedBitDepth,
          sampleRate: resolvedSampleRate,
          bitrate: resolvedBitrate,
          format: formatChanged ? resolvedFormat : null,
        );
        if (mounted &&
            generation == _metadataLoadGeneration &&
            sourcePath == cleanFilePath) {
          setState(() {
            _currentLocalLibraryItem = localItem.withAudioMetadata(
              duration: resolvedDuration,
              bitDepth: resolvedBitDepth,
              sampleRate: resolvedSampleRate,
              bitrate: resolvedBitrate,
              format: resolvedFormat,
            );
          });
        }
        await ref.read(localLibraryProvider.notifier).reloadFromStorage();
      }
    } catch (e) {
      _log.w('Failed to resolve audio metadata from file: $e');
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
        showTitleInAppBar = false;
        _lyricsEmbedded = false;
        _isInstrumental = false;
        _embeddedLyricsChecked = false;
        _hasLoadedResolvedAudioMetadata = false;
        _editedMetadata = null;
        _resolvedAudioFormat = null;
        _embeddedCoverPreviewPath = null;
      });

      if (scrollController.hasClients) {
        scrollController.jumpTo(0);
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
    final expandedHeight = calculateExpandedHeight(context);
    final bottomInset = context.navBarBottomInset;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      child: Scaffold(
        body: CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverAppBar(
              expandedHeight: expandedHeight,
              pinned: true,
              stretch: true,
              backgroundColor: colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              title: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: showTitleInAppBar ? 1.0 : 0.0,
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
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: adaptiveContentMaxWidth(
                      MediaQuery.sizeOf(context).width,
                    ),
                  ),
                  child: _buildAnimatedTrackContent(context, ref, colorScheme),
                ),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
          ],
        ),
      ),
    );
  }

  Future<void> _enqueueThis(WidgetRef ref, {required bool playNext}) async {
    final controller = ref.read(musicPlayerControllerProvider);
    final item = widget.item;
    final localItem = widget.localItem;
    if (item != null) {
      if (playNext) {
        await controller.playNextHistory(item);
      } else {
        await controller.addToQueueHistory(item);
      }
    } else if (localItem != null) {
      if (playNext) {
        await controller.playNextLocal(localItem);
      } else {
        await controller.addToQueueLocal(localItem);
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          playNext
              ? context.l10n.snackbarPlayingNext
              : context.l10n.snackbarAddedToQueueGeneric,
        ),
      ),
    );
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
}

class _MetadataOption {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool dividerAbove;

  const _MetadataOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.dividerAbove = false,
  });
}

class _MetadataOptionTile extends StatelessWidget {
  final _MetadataOption option;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _MetadataOptionTile({
    required this.option,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = option.destructive
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;
    final titleColor = option.destructive ? colorScheme.error : null;

    return InkWell(
      onTap: onTap,
      splashColor: colorScheme.primary.withValues(alpha: 0.12),
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(option.icon, color: iconColor, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                option.label,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: titleColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
