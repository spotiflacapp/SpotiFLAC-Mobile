import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/download_history_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/screens/downloaded_album_screen.dart';
import 'package:spotiflac_android/screens/local_album_screen.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/music_player_service.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/int_utils.dart';
import 'package:spotiflac_android/utils/lyrics_parser.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/utils/synced_lyrics_scroll.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:spotiflac_android/widgets/player_artwork.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';

final _log = AppLogger('NowPlaying');

/// Hero tag shared by the mini player artwork and the full player artwork so
/// the cover visually expands when the player opens.
const kNowPlayingArtworkHeroTag = 'now-playing-artwork';

/// Slide-up route for the full player. Supports live drag-to-dismiss: the
/// page follows the finger (via [startDrag]/[updateDrag]/[endDrag]) and
/// settles open or pops based on release position and velocity.
class NowPlayingRoute extends PageRoute<void> {
  NowPlayingRoute() : super(fullscreenDialog: true);

  bool _dragging = false;
  bool _popViaDrag = false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 400);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  void startDrag() {
    _dragging = true;
    controller?.stop();
    changedInternalState();
  }

  void updateDrag(DragUpdateDetails details, double pageHeight) {
    controller?.value -= (details.primaryDelta ?? 0) / pageHeight;
  }

  void endDrag(DragEndDetails details, double pageHeight) {
    _dragging = false;
    changedInternalState();
    final velocity = (details.primaryVelocity ?? 0) / pageHeight;
    final value = controller?.value ?? 1.0;
    if (velocity > 1.0 || (velocity >= 0 && value < 0.7)) {
      _popViaDrag = true;
      navigator?.pop();
    } else {
      controller?.fling();
    }
  }

  void cancelDrag() {
    _dragging = false;
    changedInternalState();
    controller?.fling();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _RouteDragRegion(route: this, child: const NowPlayingScreen());
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reversing = animation.status == AnimationStatus.reverse;
    // Button/back pop: the sheet stays put and fades out where it is, so the
    // Hero cover is the only thing traveling down to the mini player. A drag
    // dismissal instead keeps sliding from the finger's position, dissolving
    // on the way down.
    final inPlacePop = reversing && !_popViaDrag;
    // Linear while dragging so the page tracks the finger 1:1.
    final slide = _dragging
        ? animation
        : CurvedAnimation(
            parent: animation,
            curve: Easing.emphasizedDecelerate,
            reverseCurve: Easing.emphasizedAccelerate,
          );
    final position = inPlacePop
        ? const AlwaysStoppedAnimation(Offset.zero)
        : slide.drive(Tween(begin: const Offset(0, 1), end: Offset.zero));
    final opacity = inPlacePop
        ? CurvedAnimation(parent: animation, curve: const Interval(0.3, 1.0))
        : reversing
        ? CurvedAnimation(parent: animation, curve: const Interval(0.0, 0.5))
        : const AlwaysStoppedAnimation(1.0);
    return SlideTransition(
      position: position,
      child: FadeTransition(opacity: opacity, child: child),
    );
  }
}

/// Routes vertical drags to [NowPlayingRoute]. Scrollables inside [child]
/// still win the gesture arena, so this only fires on non-scrolling regions
/// (app bar, artwork, tab bar).
class _RouteDragRegion extends StatelessWidget {
  final NowPlayingRoute route;
  final Widget child;

  const _RouteDragRegion({required this.route, required this.child});

  @override
  Widget build(BuildContext context) {
    final pageHeight = MediaQuery.sizeOf(context).height;
    return GestureDetector(
      onVerticalDragStart: (_) => route.startDrag(),
      onVerticalDragUpdate: (details) => route.updateDrag(details, pageHeight),
      onVerticalDragEnd: (details) => route.endDrag(details, pageHeight),
      onVerticalDragCancel: route.cancelDrag,
      child: child,
    );
  }
}

/// AppBar wrapper that fades with the route transition (see contentOpacity
/// in [_NowPlayingScreenState.build]).
class _FadingAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Animation<double> opacity;
  final AppBar child;

  const _FadingAppBar({required this.opacity, required this.child});

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: opacity, child: child);
}

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  final PageController _pageController = PageController();
  ProviderSubscription<AsyncValue<MediaItem?>>? _mediaItemSub;
  String? _loadedSource;
  String? _loadedResolvedSource;
  String? _loadedMetadataPath;
  Map<String, dynamic>? _metadata;
  ParsedLyrics _lyrics = ParsedLyrics.empty;
  bool _loadingMeta = false;
  int _currentPage = 0;
  bool _bottomDragForwarding = false;
  double _bottomDragTotal = 0;
  bool _queueSheetShowing = false;

  @override
  void initState() {
    super.initState();
    _mediaItemSub = ref.listenManual<AsyncValue<MediaItem?>>(
      currentMediaItemProvider,
      (previous, next) => _loadMetadataForItem(
        next.value,
        // When automatic playback advances while Lyrics is already visible,
        // onPageChanged will not run again. Inspect an unresolved SAF URI now
        // instead of leaving the new track with an empty Lyrics page.
        inspectUnresolvedContentUri: _currentPage == 1,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadMetadataForItem(ref.read(currentMediaItemProvider).value);
    });
  }

  @override
  void dispose() {
    _mediaItemSub?.close();
    _pageController.dispose();
    super.dispose();
  }

  void _loadMetadataForItem(
    MediaItem? item, {
    bool inspectUnresolvedContentUri = false,
  }) {
    if (item == null) return;
    final source = item.extras?['source']?.toString() ?? '';
    if (source.isEmpty) return;
    final resolvedSource = item.extras?['resolvedSource']?.toString();
    unawaited(
      _loadMetadataFor(
        source,
        resolvedSource: resolvedSource,
        fallbackMetadata: playbackAudioMetadataFromMediaItem(item),
        inspectUnresolvedContentUri: inspectUnresolvedContentUri,
      ),
    );
  }

  Future<void> _loadMetadataFor(
    String source, {
    String? resolvedSource,
    Map<String, dynamic> fallbackMetadata = const {},
    bool inspectUnresolvedContentUri = false,
  }) async {
    final effectiveResolvedSource = resolvedSource?.trim();
    final path =
        (effectiveResolvedSource != null && effectiveResolvedSource.isNotEmpty)
        ? effectiveResolvedSource
        : source;
    final unresolvedContentUri =
        path == source && source.startsWith('content://');
    final sameItem =
        source == _loadedSource &&
        effectiveResolvedSource == _loadedResolvedSource;

    if (sameItem) {
      if (_metadata == null && fallbackMetadata.isNotEmpty) {
        setState(() => _metadata = fallbackMetadata);
      }
      if (_loadingMeta || _loadedMetadataPath == path) return;
      if (unresolvedContentUri && !inspectUnresolvedContentUri) return;
      setState(() => _loadingMeta = true);
    } else {
      _loadedSource = source;
      _loadedResolvedSource = effectiveResolvedSource;
      _loadedMetadataPath = null;
      setState(() {
        _loadingMeta = !unresolvedContentUri || inspectUnresolvedContentUri;
        _metadata = fallbackMetadata.isEmpty ? null : fallbackMetadata;
        _lyrics = ParsedLyrics.empty;
      });
    }

    // Avoid copying a restored SAF file merely because the player shell became
    // visible. If the user opens Lyrics before playback resolves a local temp
    // source, inspect the content URI on demand instead.
    if (unresolvedContentUri && !inspectUnresolvedContentUri) return;

    try {
      final meta = await readPlaybackFileMetadataWithRetry(path);
      if (!mounted ||
          _loadedSource != source ||
          _loadedResolvedSource != effectiveResolvedSource) {
        return;
      }
      setState(() {
        _loadedMetadataPath = path;
        _metadata = mergePlaybackFileMetadata(fallbackMetadata, meta);
        _lyrics = LyricsParser.parse((meta['lyrics'] ?? '').toString());
        _loadingMeta = false;
      });
    } catch (e) {
      _log.w('Failed to read metadata: $e');
      if (!mounted ||
          _loadedSource != source ||
          _loadedResolvedSource != effectiveResolvedSource) {
        return;
      }
      setState(() {
        _metadata = fallbackMetadata.isEmpty ? null : fallbackMetadata;
        _lyrics = ParsedLyrics.empty;
        _loadingMeta = false;
      });
    }
  }

  String? _qualityLabel() {
    final meta = _metadata;
    if (meta == null) return null;

    final parts = <String>[];
    final format = (meta['format'] ?? meta['audio_codec'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (format.isNotEmpty) parts.add(format);

    final bitDepth = readPositiveInt(meta['bit_depth']) ?? 0;
    if (bitDepth > 0) parts.add('$bitDepth-bit');

    final sampleRate = readPositiveInt(meta['sample_rate'])?.toDouble() ?? 0;
    if (sampleRate > 0) {
      final khz = sampleRate / 1000;
      final khzStr = khz == khz.roundToDouble()
          ? khz.toStringAsFixed(0)
          : khz.toStringAsFixed(1);
      parts.add('$khzStr kHz');
    }

    final bitrate = readPositiveInt(meta['bitrate']) ?? 0;
    if (bitDepth == 0 && bitrate > 0) parts.add('$bitrate kbps');

    if (parts.isEmpty) return null;
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mediaItem = ref.watch(currentMediaItemProvider).value;
    final controller = ref.read(musicPlayerControllerProvider);

    if (mediaItem == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Center(child: Text(context.l10n.nowPlayingNothingPlaying)),
      );
    }

    final source = mediaItem.extras?['source']?.toString() ?? '';

    // Fade the page content in during the last 60% of the slide-up so only
    // the sheet surface and the flying Hero artwork move together; without
    // this the title/controls slide separately and look detached from the
    // cover. On pop/drag the content fades out first, then the cover flies.
    final routeAnimation =
        ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    final contentOpacity = CurvedAnimation(
      parent: routeAnimation,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: _FadingAppBar(
        opacity: contentOpacity,
        child: AppBar(
          backgroundColor: colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(context.l10n.nowPlayingTitle),
          centerTitle: true,
          leading: IconButton(
            tooltip: context.l10n.nowPlayingMinimize,
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          actions: [
            IconButton(
              tooltip: context.l10n.nowPlayingUpNext,
              icon: const Icon(Icons.queue_music),
              onPressed: () => _showQueueSheet(colorScheme),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showMoreActions(
                mediaItem: mediaItem,
                source: source,
                colorScheme: colorScheme,
              ),
            ),
          ],
        ),
      ),
      body: FadeTransition(
        opacity: contentOpacity,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (page) {
                    if (_currentPage != page) {
                      setState(() => _currentPage = page);
                    }
                    if (page == 1) {
                      _loadMetadataForItem(
                        ref.read(currentMediaItemProvider).value,
                        inspectUnresolvedContentUri: true,
                      );
                    }
                  },
                  children: [
                    _playerPage(mediaItem, controller, colorScheme),
                    _lyricsSection(colorScheme, isActive: _currentPage == 1),
                  ],
                ),
              ),
              _queueSwipeRegion(
                colorScheme,
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PageTabBar(
                      controller: _pageController,
                      colorScheme: colorScheme,
                      labels: [
                        context.l10n.nowPlayingTabPlayer,
                        context.l10n.nowPlayingTabLyrics,
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Swipe up (player content or bottom tab strip) opens the queue sheet; a
  /// downward drag is forwarded to the route's drag-to-dismiss instead.
  Widget _queueSwipeRegion(ColorScheme colorScheme, Widget child) {
    final route = ModalRoute.of(context);
    final npRoute = route is NowPlayingRoute ? route : null;
    final pageHeight = MediaQuery.sizeOf(context).height;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) {
        _bottomDragForwarding = false;
        _bottomDragTotal = 0;
      },
      onVerticalDragUpdate: (details) {
        if (_bottomDragForwarding) {
          npRoute?.updateDrag(details, pageHeight);
          return;
        }
        _bottomDragTotal += details.primaryDelta ?? 0;
        if (_bottomDragTotal > 12 && npRoute != null) {
          npRoute.startDrag();
          _bottomDragForwarding = true;
        }
      },
      onVerticalDragEnd: (details) {
        if (_bottomDragForwarding) {
          npRoute?.endDrag(details, pageHeight);
        } else if ((details.primaryVelocity ?? 0) < -300 ||
            _bottomDragTotal < -40) {
          _showQueueSheet(colorScheme);
        }
      },
      onVerticalDragCancel: () {
        if (_bottomDragForwarding) npRoute?.cancelDrag();
      },
      child: child,
    );
  }

  /// The artwork sits inside a scroll view, which wins vertical drags from
  /// the route-level drag region — so the artwork hooks the route directly.
  Widget _artworkDragRegion(BuildContext context, Widget child) {
    final route = ModalRoute.of(context);
    if (route is! NowPlayingRoute) return child;
    final pageHeight = MediaQuery.sizeOf(context).height;
    return GestureDetector(
      onVerticalDragStart: (_) => route.startDrag(),
      onVerticalDragUpdate: (details) => route.updateDrag(details, pageHeight),
      onVerticalDragEnd: (details) => route.endDrag(details, pageHeight),
      onVerticalDragCancel: route.cancelDrag,
      child: child,
    );
  }

  Widget _playerPage(
    MediaItem mediaItem,
    MusicPlayerController controller,
    ColorScheme colorScheme,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget artworkAt(double artSize) => Center(
          child: _artworkDragRegion(
            context,
            Hero(
              tag: kNowPlayingArtworkHeroTag,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: artSize,
                  height: artSize,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween(begin: 0.94, end: 1.0).animate(animation),
                        child: child,
                      ),
                    ),
                    child: PlayerArtwork(
                      key: ValueKey(
                        mediaItem.artUri?.toString() ?? mediaItem.id,
                      ),
                      artUri: mediaItem.artUri?.toString(),
                      colorScheme: colorScheme,
                      cacheWidth:
                          (artSize * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // Tablet/landscape: artwork pane left, metadata and controls right,
        // instead of one narrow column in a sea of empty space.
        final twoPane =
            constraints.maxWidth >= 720 &&
            constraints.maxWidth > constraints.maxHeight;
        if (twoPane) {
          final artSize = (constraints.maxHeight - 96).clamp(0.0, 420.0);
          return Row(
            children: [
              Expanded(child: artworkAt(artSize)),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 32,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _metadataAndControls(
                        mediaItem,
                        controller,
                        colorScheme,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final artSize = (constraints.maxWidth - 64).clamp(0.0, 360.0);
        // Not user-scrollable: a swipe up here opens the queue instead,
        // and a swipe down still dismisses the player via the route.
        return _queueSwipeRegion(
          colorScheme,
          SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 32,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  artworkAt(artSize),
                  const SizedBox(height: 32),
                  ..._metadataAndControls(mediaItem, controller, colorScheme),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Title/artist, seek slider, and transport buttons — shared by the
  /// portrait column and the landscape right pane.
  List<Widget> _metadataAndControls(
    MediaItem mediaItem,
    MusicPlayerController controller,
    ColorScheme colorScheme,
  ) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Column(
            key: ValueKey(mediaItem.id),
            children: [
              Text(
                mediaItem.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                mediaItem.artist ?? '',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      _PlaybackControls(
        duration: mediaItem.duration ?? Duration.zero,
        controller: controller,
        colorScheme: colorScheme,
        qualityLabel: _qualityLabel(),
      ),
    ];
  }

  Widget _lyricsSection(ColorScheme colorScheme, {required bool isActive}) {
    if (_loadingMeta) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 40,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.nowPlayingNoLyrics,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    if (_lyrics.synced) {
      return _SyncedLyricsView(
        lyrics: _lyrics,
        colorScheme: colorScheme,
        isActive: isActive,
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Text(
        _lyrics.plainText,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          height: 1.6,
          color: colorScheme.onSurface,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Future<void> _openExternally(String source) async {
    if (source.isEmpty) return;
    try {
      await openFile(source);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.snackbarCannotOpenFile(context.friendlyError(e)),
          ),
        ),
      );
    }
  }

  Future<void> _showMoreActions({
    required MediaItem mediaItem,
    required String source,
    required ColorScheme colorScheme,
  }) async {
    final action = await showAppBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      title: mediaItem.title,
      subtitle: mediaItem.artist,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: SettingsGroup(
          children: [
            if ((mediaItem.album ?? '').trim().isNotEmpty)
              SettingsItem(
                icon: Icons.album_outlined,
                title: sheetContext.l10n.homeGoToAlbum,
                onTap: () => Navigator.of(sheetContext).pop('album'),
              ),
            SettingsItem(
              icon: Icons.info_outline,
              title: sheetContext.l10n.nowPlayingDetails,
              onTap: () => Navigator.of(sheetContext).pop('details'),
            ),
            SettingsItem(
              icon: Icons.open_in_new,
              title: sheetContext.l10n.nowPlayingOpenInExternalPlayer,
              trailing: Icon(
                Icons.open_in_new,
                size: 18,
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
              ),
              showDivider: false,
              onTap: () => Navigator.of(sheetContext).pop('external'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'album':
        await _goToCurrentAlbum(mediaItem: mediaItem, source: source);
        break;
      case 'details':
        _showDetailsSheet(colorScheme);
        break;
      case 'external':
        await _openExternally(source);
        break;
    }
  }

  Future<void> _goToCurrentAlbum({
    required MediaItem mediaItem,
    required String source,
  }) async {
    final albumName = (mediaItem.album ?? '').trim();
    if (albumName.isEmpty) return;

    // Prefer the stored collection so this action remains useful offline and
    // opens the exact files the user is currently playing.
    try {
      final historyItem = source.isEmpty
          ? null
          : await ref
                .read(downloadHistoryProvider.notifier)
                .getByFilePathAsync(source);
      if (!mounted) return;
      if (historyItem != null) {
        final albumArtist = (historyItem.albumArtist ?? '').trim();
        pushViaPreferredNavigator(
          context,
          (_) => DownloadedAlbumScreen(
            albumName: historyItem.albumName,
            artistName: albumArtist.isNotEmpty
                ? albumArtist
                : historyItem.artistName,
            coverUrl: historyItem.coverUrl,
          ),
        );
        return;
      }
    } catch (e) {
      _log.w('Failed to resolve downloaded album: $e');
    }

    try {
      final row = await LibraryDatabase.instance.getById(mediaItem.id);
      if (!mounted) return;
      if (row != null) {
        final item = LocalLibraryItem.fromJson(row);
        final rows = await LibraryDatabase.instance
            .getQueueLocalAlbumTracksByKey(item.albumKey);
        if (!mounted) return;
        final tracks = rows
            .map(LocalLibraryItem.fromJson)
            .toList(growable: false);
        if (tracks.isNotEmpty) {
          final albumArtist = (item.albumArtist ?? '').trim();
          pushViaPreferredNavigator(
            context,
            (_) => LocalAlbumScreen(
              albumName: item.albumName,
              artistName: albumArtist.isNotEmpty
                  ? albumArtist
                  : item.artistName,
              coverPath: item.coverPath,
              tracks: tracks,
            ),
          );
          return;
        }
      }
    } catch (e) {
      _log.w('Failed to resolve local album: $e');
    }

    if (!mounted) return;
    await navigateToAlbum(
      context,
      albumName: albumName,
      artistName: mediaItem.artist,
      coverUrl: mediaItem.artUri?.toString(),
    );
  }

  Future<void> _shuffleLibrary(MusicPlayerController controller) async {
    try {
      final rows = await LibraryDatabase.instance.getAll();
      final media = rows
          .map(LocalLibraryItem.fromJson)
          .where((i) => i.filePath.trim().isNotEmpty)
          .map(playableFromLocal)
          .toList();
      if (media.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.nowPlayingLibraryEmpty)),
        );
        return;
      }
      media.shuffle();
      await controller.setShuffle(true);
      await controller.playAll(media);
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.nowPlayingShuffleLibraryFailed(
              context.friendlyError(e),
            ),
          ),
        ),
      );
    }
  }

  void _showQueueSheet(ColorScheme colorScheme) {
    if (_queueSheetShowing) return;
    _queueSheetShowing = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return Consumer(
              builder: (context, ref, _) {
                final queue = ref.watch(playQueueProvider).value ?? const [];
                final current = ref.watch(currentMediaItemProvider).value;
                final controller = ref.read(musicPlayerControllerProvider);
                final shuffleOn = ref.watch(
                  playbackStateProvider.select(
                    (s) => s.value?.shuffleMode == AudioServiceShuffleMode.all,
                  ),
                );
                final repeatMode = ref.watch(
                  playbackStateProvider.select(
                    (s) => s.value?.repeatMode ?? AudioServiceRepeatMode.none,
                  ),
                );
                final textTheme = Theme.of(context).textTheme;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 16, 8),
                      child: Row(
                        children: [
                          Text(
                            context.l10n.nowPlayingUpNext,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: switch (repeatMode) {
                              AudioServiceRepeatMode.one =>
                                context.l10n.nowPlayingRepeatOne,
                              AudioServiceRepeatMode.none =>
                                context.l10n.nowPlayingRepeatOff,
                              _ => context.l10n.nowPlayingRepeatAll,
                            },
                            isSelected:
                                repeatMode != AudioServiceRepeatMode.none,
                            icon: Icon(
                              repeatMode == AudioServiceRepeatMode.one
                                  ? Icons.repeat_one
                                  : Icons.repeat,
                            ),
                            color: repeatMode != AudioServiceRepeatMode.none
                                ? colorScheme.primary
                                : null,
                            onPressed: () =>
                                controller.setRepeatMode(switch (repeatMode) {
                                  AudioServiceRepeatMode.none =>
                                    AudioServiceRepeatMode.all,
                                  AudioServiceRepeatMode.all =>
                                    AudioServiceRepeatMode.one,
                                  _ => AudioServiceRepeatMode.none,
                                }),
                          ),
                          IconButton(
                            tooltip: shuffleOn
                                ? context.l10n.nowPlayingShuffleOn
                                : context.l10n.nowPlayingPlayInOrder,
                            isSelected: shuffleOn,
                            icon: const Icon(Icons.shuffle),
                            color: shuffleOn ? colorScheme.primary : null,
                            onPressed: () => controller.setShuffle(!shuffleOn),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () => _shuffleLibrary(controller),
                          icon: const Icon(Icons.shuffle, size: 18),
                          label: Text(context.l10n.nowPlayingShuffleLibrary),
                        ),
                      ),
                    ),
                    if (queue.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            context.l10n.nowPlayingQueueEmpty,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ReorderableListView.builder(
                          scrollController: scrollController,
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                          itemCount: queue.length,
                          onReorderItem: (oldIndex, newIndex) {
                            controller.moveQueueItem(oldIndex, newIndex);
                          },
                          proxyDecorator: (child, index, animation) {
                            return Material(
                              elevation: 4,
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              child: child,
                            );
                          },
                          itemBuilder: (context, i) {
                            final item = queue[i];
                            final isCurrent = current?.id == item.id;
                            return ListTile(
                              key: ValueKey('${item.id}_$i'),
                              contentPadding: const EdgeInsets.only(
                                left: 16,
                                right: 4,
                              ),
                              leading: Icon(
                                isCurrent ? Icons.equalizer : Icons.music_note,
                                color: isCurrent
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyLarge?.copyWith(
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isCurrent
                                      ? colorScheme.primary
                                      : colorScheme.onSurface,
                                ),
                              ),
                              subtitle: Text(
                                item.artist ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: ReorderableDragStartListener(
                                index: i,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.drag_handle,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              onTap: () => controller.jumpTo(i),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    ).whenComplete(() => _queueSheetShowing = false);
  }

  void _showDetailsSheet(ColorScheme colorScheme) {
    final meta = _metadata;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            if (meta == null) {
              return Center(
                child: Text(
                  context.l10n.nowPlayingNoMetadata,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return _MetadataList(
              meta: meta,
              colorScheme: colorScheme,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }
}

class _PlaybackControls extends ConsumerWidget {
  final Duration duration;
  final MusicPlayerController controller;
  final ColorScheme colorScheme;
  final String? qualityLabel;

  const _PlaybackControls({
    required this.duration,
    required this.controller,
    required this.colorScheme,
    required this.qualityLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(playbackPositionProvider);
    final isPlaying = ref.watch(playbackPlayingProvider);
    final isLoading = ref.watch(playbackLoadingProvider);
    final shuffleOn = ref.watch(
      playbackStateProvider.select(
        (s) => s.value?.shuffleMode == AudioServiceShuffleMode.all,
      ),
    );
    final repeatMode = ref.watch(
      playbackStateProvider.select(
        (s) => s.value?.repeatMode ?? AudioServiceRepeatMode.none,
      ),
    );
    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final posMs = position.inMilliseconds
        .clamp(0, duration.inMilliseconds > 0 ? duration.inMilliseconds : 0)
        .toDouble();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: colorScheme.primary,
                  inactiveTrackColor: colorScheme.onSurface.withValues(
                    alpha: 0.18,
                  ),
                  thumbColor: colorScheme.primary,
                  // A 7dp thumb was hard to grab; 10dp with a 24dp overlay
                  // gives the drag gesture a full-size target.
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 10,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 24,
                  ),
                ),
                child: Slider(
                  value: posMs.clamp(0, maxMs),
                  max: maxMs,
                  onChanged: duration.inMilliseconds > 0
                      ? (value) => controller.seek(
                          Duration(milliseconds: value.round()),
                        )
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Text(
                      formatClock(position.inSeconds),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _QualityBadge(
                          label: qualityLabel,
                          colorScheme: colorScheme,
                        ),
                      ),
                    ),
                    Text(
                      formatClock(duration.inSeconds),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 24,
              tooltip: shuffleOn
                  ? context.l10n.nowPlayingShuffleOn
                  : context.l10n.nowPlayingPlayInOrder,
              color: shuffleOn
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              icon: const Icon(Icons.shuffle),
              onPressed: () => controller.setShuffle(!shuffleOn),
            ),
            const SizedBox(width: 8),
            IconButton(
              iconSize: 44,
              icon: const Icon(Icons.skip_previous),
              onPressed: controller.previous,
            ),
            const SizedBox(width: 20),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                iconSize: 44,
                padding: const EdgeInsets.all(12),
                color: colorScheme.onPrimary,
                icon: isLoading
                    ? const SizedBox.square(
                        dimension: 32,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: isLoading
                    ? null
                    : () => controller.togglePlayPause(isPlaying),
              ),
            ),
            const SizedBox(width: 20),
            IconButton(
              iconSize: 44,
              icon: const Icon(Icons.skip_next),
              onPressed: controller.next,
            ),
            const SizedBox(width: 8),
            IconButton(
              iconSize: 24,
              tooltip: switch (repeatMode) {
                AudioServiceRepeatMode.one => context.l10n.nowPlayingRepeatOne,
                AudioServiceRepeatMode.none => context.l10n.nowPlayingRepeatOff,
                _ => context.l10n.nowPlayingRepeatAll,
              },
              color: repeatMode == AudioServiceRepeatMode.none
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.primary,
              icon: Icon(
                repeatMode == AudioServiceRepeatMode.one
                    ? Icons.repeat_one
                    : Icons.repeat,
              ),
              onPressed: () => controller.setRepeatMode(switch (repeatMode) {
                AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
                AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
                _ => AudioServiceRepeatMode.none,
              }),
            ),
          ],
        ),
      ],
    );
  }
}

class _SyncedLyricsView extends ConsumerStatefulWidget {
  final ParsedLyrics lyrics;
  final ColorScheme colorScheme;
  final bool isActive;

  const _SyncedLyricsView({
    required this.lyrics,
    required this.colorScheme,
    required this.isActive,
  });

  @override
  ConsumerState<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends ConsumerState<_SyncedLyricsView> {
  final ScrollController _scroll = ScrollController();
  ProviderSubscription<Duration>? _positionSubscription;
  late List<GlobalKey> _lineKeys;
  int _active = -1;
  bool _userScrolling = false;
  static const double _estimatedLyricExtent = 64;

  @override
  void initState() {
    super.initState();
    _resetLineKeys();
    _syncPositionSubscription();
  }

  @override
  void didUpdateWidget(covariant _SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _resetLineKeys();
    }
    if (oldWidget.isActive != widget.isActive ||
        oldWidget.lyrics != widget.lyrics) {
      _syncPositionSubscription();
    }
  }

  void _resetLineKeys() {
    _lineKeys = List<GlobalKey>.generate(
      widget.lyrics.lines.length,
      (index) => GlobalKey(debugLabel: 'lyric-line-$index'),
      growable: false,
    );
  }

  void _syncPositionSubscription() {
    _positionSubscription?.close();
    _positionSubscription = null;
    if (!widget.isActive) return;

    _active = LyricsParser.activeIndex(
      widget.lyrics.lines,
      ref.read(playbackPositionProvider),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_maybeAutoScroll(_active));
    });
    _positionSubscription = ref.listenManual<Duration>(
      playbackPositionProvider,
      (previous, next) {
        final active = LyricsParser.activeIndex(widget.lyrics.lines, next);
        if (active == _active || !mounted) return;
        setState(() => _active = active);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_maybeAutoScroll(active));
        });
      },
    );
  }

  @override
  void dispose() {
    _positionSubscription?.close();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _maybeAutoScroll(int index) async {
    if (_userScrolling || index < 0 || !_scroll.hasClients) return;
    if (index < _lineKeys.length) {
      final lineContext = _lineKeys[index].currentContext;
      if (lineContext != null) {
        await Scrollable.ensureVisible(
          lineContext,
          alignment: 0.5,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
        return;
      }
    }

    final position = _scroll.position;
    final target = syncedLyricsEstimatedOffset(
      index: index,
      estimatedLineExtent: _estimatedLyricExtent,
    );
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    await _scroll.animateTo(
      clamped.toDouble(),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || _userScrolling || index >= _lineKeys.length) return;
    final lineContext = _lineKeys[index].currentContext;
    if (lineContext != null && lineContext.mounted) {
      await Scrollable.ensureVisible(
        lineContext,
        alignment: 0.5,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    final active = _active;

    return NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (notification.direction != ScrollDirection.idle) {
          _userScrolling = true;
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) _userScrolling = false;
          });
        }
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final centerPadding = syncedLyricsCenterPadding(
            viewportDimension: constraints.maxHeight,
            estimatedLineExtent: _estimatedLyricExtent,
          );
          return ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(24, centerPadding, 24, centerPadding),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[index];
              final isActive = index == active;
              final isPast = index < active;

              final color = isActive
                  ? widget.colorScheme.onSurface
                  : isPast
                  ? widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                  : widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.8);

              final text = line.text.trim().isEmpty
                  ? '\u00b7\u00b7\u00b7'
                  : line.text;

              Widget content;
              if (isActive && line.hasWordTiming) {
                content = _WordHighlightedLyricLine(
                  line: line,
                  colorScheme: widget.colorScheme,
                );
              } else {
                content = Text(
                  text,
                  textAlign: TextAlign.center,
                  style:
                      (isActive
                              ? Theme.of(context).textTheme.headlineSmall
                              : Theme.of(context).textTheme.titleLarge)
                          ?.copyWith(
                            height: 1.4,
                            fontWeight: isActive
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: color,
                          ),
                );
              }

              return Padding(
                key: _lineKeys[index],
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: GestureDetector(
                  onTap: () =>
                      ref.read(musicPlayerControllerProvider).seek(line.time),
                  child: AnimatedScale(
                    scale: isActive ? 1.0 : 0.96,
                    alignment: Alignment.center,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: isActive ? 1.0 : (isPast ? 0.55 : 0.85),
                      duration: const Duration(milliseconds: 280),
                      child: content,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _WordHighlightedLyricLine extends ConsumerWidget {
  final LyricLine line;
  final ColorScheme colorScheme;

  const _WordHighlightedLyricLine({
    required this.line,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(playbackPositionProvider);
    final spans = <TextSpan>[];
    for (final word in line.words) {
      final sung = position >= word.time;
      spans.add(
        TextSpan(
          text: word.text,
          style: TextStyle(
            color: sung
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      );
    }
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          height: 1.4,
          fontWeight: FontWeight.bold,
        ),
        children: spans,
      ),
    );
  }
}

class _MetadataList extends StatelessWidget {
  final Map<String, dynamic> meta;
  final ColorScheme colorScheme;
  final ScrollController scrollController;

  const _MetadataList({
    required this.meta,
    required this.colorScheme,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    String s(Object? v) => (v ?? '').toString();
    final l10n = context.l10n;
    final rows = <(String, String)>[
      (l10n.editMetadataFieldTitle, s(meta['title'])),
      (l10n.editMetadataFieldArtist, s(meta['artist'])),
      (l10n.editMetadataFieldAlbum, s(meta['album'])),
      (l10n.editMetadataFieldAlbumArtist, s(meta['album_artist'])),
      (l10n.editMetadataFieldGenre, s(meta['genre'])),
      (l10n.editMetadataFieldComposer, s(meta['composer'])),
      (l10n.editMetadataFieldDate, s(meta['date'])),
      (l10n.editMetadataFieldTrackNum, s(meta['track_number'])),
      (l10n.editMetadataFieldDiscNum, s(meta['disc_number'])),
      (l10n.editMetadataFieldIsrc, s(meta['isrc'])),
      (l10n.editMetadataFieldLabel, s(meta['label'])),
      (l10n.editMetadataFieldCopyright, s(meta['copyright'])),
      (l10n.libraryFilterFormat, s(meta['format']).toUpperCase()),
      (l10n.audioAnalysisCodec, s(meta['audio_codec'])),
      (
        l10n.audioAnalysisSampleRate,
        meta['sample_rate'] != null && (meta['sample_rate'] as num? ?? 0) > 0
            ? '${((meta['sample_rate'] as num) / 1000).toStringAsFixed(1)} kHz'
            : '',
      ),
      (
        l10n.audioAnalysisBitDepth,
        (meta['bit_depth'] as num? ?? 0) > 0 ? '${meta['bit_depth']}-bit' : '',
      ),
    ].where((r) => r.$2.trim().isNotEmpty && r.$2 != '0').toList();

    final textTheme = Theme.of(context).textTheme;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Card(
          elevation: 0,
          color: settingsGroupColor(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.nowPlayingDetails,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...rows.map(
                  (row) => Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text(
                            row.$1,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            row.$2,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PageTabBar extends StatelessWidget {
  final PageController controller;
  final ColorScheme colorScheme;
  final List<String> labels;

  const _PageTabBar({
    required this.controller,
    required this.colorScheme,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        double page = 0;
        if (controller.hasClients && controller.position.haveDimensions) {
          page = controller.page ?? controller.initialPage.toDouble();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final tabWidth = constraints.maxWidth / labels.length;
            final indicatorWidth = (tabWidth * 0.5).clamp(28.0, 80.0);
            final base =
                Theme.of(context).textTheme.labelLarge ?? const TextStyle();

            return SizedBox(
              height: 38,
              child: Stack(
                children: [
                  Row(
                    children: List.generate(labels.length, (i) {
                      // Distance of this tab from the current page position,
                      // used to interpolate color/weight as the user swipes.
                      final t = (1.0 - (page - i).abs()).clamp(0.0, 1.0);
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => controller.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                          ),
                          child: Center(
                            child: Text(
                              labels[i],
                              style: base.copyWith(
                                fontWeight: FontWeight.lerp(
                                  FontWeight.w500,
                                  FontWeight.bold,
                                  t,
                                ),
                                color: Color.lerp(
                                  colorScheme.onSurfaceVariant.withValues(
                                    alpha: 0.55,
                                  ),
                                  colorScheme.primary,
                                  t,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  // Sliding underline that tracks the swipe in real time.
                  Positioned(
                    bottom: 0,
                    left:
                        page.clamp(0, (labels.length - 1).toDouble()) *
                            tabWidth +
                        (tabWidth - indicatorWidth) / 2,
                    child: Container(
                      width: indicatorWidth,
                      height: 3,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _QualityBadge extends StatelessWidget {
  final String? label;
  final ColorScheme colorScheme;

  const _QualityBadge({required this.label, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final text = label;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq, size: 11, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10.5,
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
