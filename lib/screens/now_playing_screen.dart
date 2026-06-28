import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/lyrics_parser.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';

final _log = AppLogger('NowPlaying');

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  final PageController _pageController = PageController();
  ProviderSubscription<AsyncValue<MediaItem?>>? _mediaItemSub;
  String? _loadedSource;
  Map<String, dynamic>? _metadata;
  ParsedLyrics _lyrics = ParsedLyrics.empty;
  bool _loadingMeta = false;

  @override
  void initState() {
    super.initState();
    _mediaItemSub = ref.listenManual<AsyncValue<MediaItem?>>(
      currentMediaItemProvider,
      (previous, next) => _loadMetadataForItem(next.value),
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

  void _loadMetadataForItem(MediaItem? item) {
    if (item == null) return;
    final source = item.extras?['source']?.toString() ?? '';
    if (source.isEmpty) return;
    final resolvedSource = item.extras?['resolvedSource']?.toString();
    unawaited(_loadMetadataFor(source, resolvedSource: resolvedSource));
  }

  Future<void> _loadMetadataFor(String source, {String? resolvedSource}) async {
    if (source == _loadedSource) return;
    _loadedSource = source;
    setState(() {
      _loadingMeta = true;
      _metadata = null;
      _lyrics = ParsedLyrics.empty;
    });
    try {
      String path = (resolvedSource != null && resolvedSource.isNotEmpty)
          ? resolvedSource
          : source;
      if (path == source && source.startsWith('content://')) {
        final temp = await PlatformBridge.copyContentUriToTemp(source);
        if (temp == null || temp.isEmpty) {
          throw Exception('Cannot resolve content URI');
        }
        path = temp;
      }
      final meta = await PlatformBridge.readFileMetadata(path);
      if (!mounted || _loadedSource != source) return;
      setState(() {
        _metadata = meta;
        _lyrics = LyricsParser.parse((meta['lyrics'] ?? '').toString());
        _loadingMeta = false;
      });
    } catch (e) {
      _log.w('Failed to read metadata: $e');
      if (!mounted || _loadedSource != source) return;
      setState(() {
        _metadata = null;
        _lyrics = ParsedLyrics.empty;
        _loadingMeta = false;
      });
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
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

    final bitDepth = (meta['bit_depth'] as num?)?.toInt() ?? 0;
    if (bitDepth > 0) parts.add('$bitDepth-bit');

    final sampleRate = (meta['sample_rate'] as num?)?.toDouble() ?? 0;
    if (sampleRate > 0) {
      final khz = sampleRate / 1000;
      final khzStr = khz == khz.roundToDouble()
          ? khz.toStringAsFixed(0)
          : khz.toStringAsFixed(1);
      parts.add('$khzStr kHz');
    }

    final bitrate = (meta['bitrate'] as num?)?.toInt() ?? 0;
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
        body: const Center(child: Text('Nothing is playing')),
      );
    }

    final source = mediaItem.extras?['source']?.toString() ?? '';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Now Playing'),
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Minimize',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Up next',
            icon: const Icon(Icons.queue_music),
            onPressed: () => _showQueueSheet(colorScheme),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'details':
                  _showDetailsSheet(colorScheme);
                  break;
                case 'external':
                  _openExternally(source);
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'details',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Details'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'external',
                child: ListTile(
                  leading: Icon(Icons.open_in_new),
                  title: Text('Open in external player'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                children: [
                  _playerPage(mediaItem, controller, colorScheme),
                  _lyricsSection(colorScheme),
                ],
              ),
            ),
            _PageTabBar(
              controller: _pageController,
              colorScheme: colorScheme,
              labels: const ['Player', 'Lyrics'],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _playerPage(
    MediaItem mediaItem,
    MusicPlayerController controller,
    ColorScheme colorScheme,
  ) {
    final playback = ref.watch(playbackStateProvider).value;
    final isPlaying = playback?.playing ?? false;
    final position = playback?.position ?? Duration.zero;
    final duration = mediaItem.duration ?? Duration.zero;
    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final posMs = position.inMilliseconds
        .clamp(0, duration.inMilliseconds > 0 ? duration.inMilliseconds : 0)
        .toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final artSize = (constraints.maxWidth - 64).clamp(0.0, 360.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      width: artSize,
                      height: artSize,
                      child: _Artwork(
                        artUri: mediaItem.artUri?.toString(),
                        colorScheme: colorScheme,
                        cacheWidth:
                            (artSize * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      Text(
                        mediaItem.title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
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
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16,
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
                              _fmt(position),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            Expanded(
                              child: Center(
                                child: _QualityBadge(
                                  label: _qualityLabel(),
                                  colorScheme: colorScheme,
                                ),
                              ),
                            ),
                            Text(
                              _fmt(duration),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
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
                        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                        onPressed: () => controller.togglePlayPause(isPlaying),
                      ),
                    ),
                    const SizedBox(width: 20),
                    IconButton(
                      iconSize: 44,
                      icon: const Icon(Icons.skip_next),
                      onPressed: controller.next,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _lyricsSection(ColorScheme colorScheme) {
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
              'No lyrics in this file',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    if (_lyrics.synced) {
      return _SyncedLyricsView(lyrics: _lyrics, colorScheme: colorScheme);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cannot open file: $e')));
    }
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Your library is empty')));
        return;
      }
      media.shuffle();
      await controller.setShuffle(true);
      await controller.playAll(media);
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not shuffle library: $e')));
    }
  }

  void _showQueueSheet(ColorScheme colorScheme) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
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
                final shuffleOn =
                    ref.watch(playbackStateProvider).value?.shuffleMode ==
                    AudioServiceShuffleMode.all;
                final textTheme = Theme.of(context).textTheme;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 16, 8),
                      child: Row(
                        children: [
                          Text(
                            'Up next',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: shuffleOn
                                ? 'Shuffle on'
                                : 'Play in order',
                            isSelected: shuffleOn,
                            icon: const Icon(Icons.shuffle),
                            color: shuffleOn ? colorScheme.primary : null,
                            onPressed: () =>
                                controller.setShuffle(!shuffleOn),
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
                          label: const Text('Shuffle library'),
                        ),
                      ),
                    ),
                    if (queue.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            'Queue is empty',
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
                              contentPadding:
                                  const EdgeInsets.only(left: 16, right: 4),
                              leading: Icon(
                                isCurrent
                                    ? Icons.equalizer
                                    : Icons.music_note,
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
    );
  }

  void _showDetailsSheet(ColorScheme colorScheme) {
    final meta = _metadata;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
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
                  'No metadata available',
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

class _SyncedLyricsView extends ConsumerStatefulWidget {
  final ParsedLyrics lyrics;
  final ColorScheme colorScheme;

  const _SyncedLyricsView({required this.lyrics, required this.colorScheme});

  @override
  ConsumerState<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends ConsumerState<_SyncedLyricsView> {
  final ScrollController _scroll = ScrollController();
  int _active = -1;
  bool _userScrolling = false;
  static const double _estimatedLyricExtent = 64;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeAutoScroll(int index) {
    if (_userScrolling || index < 0 || !_scroll.hasClients) return;
    final position = _scroll.position;
    final target =
        (index * _estimatedLyricExtent) -
        (position.viewportDimension * 0.35) +
        24;
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scroll.animateTo(
      clamped.toDouble(),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final position =
        ref.watch(playbackStateProvider).value?.position ?? Duration.zero;
    final lines = widget.lyrics.lines;
    final active = LyricsParser.activeIndex(lines, position);

    if (active != _active) {
      _active = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeAutoScroll(active);
      });
    }

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
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
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
            content = _wordHighlightedLine(line, position);
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
      ),
    );
  }

  Widget _wordHighlightedLine(LyricLine line, Duration position) {
    final spans = <TextSpan>[];
    for (final word in line.words) {
      final sung = position >= word.time;
      spans.add(
        TextSpan(
          text: word.text,
          style: TextStyle(
            color: sung
                ? widget.colorScheme.onSurface
                : widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
    final rows = <(String, String)>[
      ('Title', s(meta['title'])),
      ('Artist', s(meta['artist'])),
      ('Album', s(meta['album'])),
      ('Album artist', s(meta['album_artist'])),
      ('Genre', s(meta['genre'])),
      ('Composer', s(meta['composer'])),
      ('Date', s(meta['date'])),
      ('Track', s(meta['track_number'])),
      ('Disc', s(meta['disc_number'])),
      ('ISRC', s(meta['isrc'])),
      ('Label', s(meta['label'])),
      ('Copyright', s(meta['copyright'])),
      ('Format', s(meta['format']).toUpperCase()),
      ('Codec', s(meta['audio_codec'])),
      (
        'Sample rate',
        meta['sample_rate'] != null && (meta['sample_rate'] as num? ?? 0) > 0
            ? '${((meta['sample_rate'] as num) / 1000).toStringAsFixed(1)} kHz'
            : '',
      ),
      (
        'Bit depth',
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
                      'Details',
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

class _Artwork extends StatelessWidget {
  final String? artUri;
  final ColorScheme colorScheme;
  final int? cacheWidth;

  const _Artwork({
    required this.artUri,
    required this.colorScheme,
    this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        size: 40,
        color: colorScheme.onSurfaceVariant,
      ),
    );

    final uri = artUri;
    if (uri == null || uri.isEmpty) return placeholder;

    if (uri.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: uri,
        fit: BoxFit.cover,
        cacheManager: CoverCacheManager.instance,
        memCacheWidth: cacheWidth,
        fadeInDuration: const Duration(milliseconds: 150),
        fadeOutDuration: const Duration(milliseconds: 0),
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      );
    }
    if (uri.startsWith('file://')) {
      final path = Uri.parse(uri).toFilePath();
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    return placeholder;
  }
}
