import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('MotionHeaderBanner');

class MotionHeaderBanner extends StatefulWidget {
  final String videoUrl;
  final Widget fallback;
  final BoxFit fit;
  final Alignment alignment;

  const MotionHeaderBanner({
    super.key,
    required this.videoUrl,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
  });

  @override
  State<MotionHeaderBanner> createState() => _MotionHeaderBannerState();
}

class _MotionHeaderBannerState extends State<MotionHeaderBanner>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didUpdateWidget(MotionHeaderBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _disposeController();
      _ready = false;
      _failed = false;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final url = widget.videoUrl.trim();
    if (url.isEmpty) {
      setState(() => _failed = true);
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      formatHint: VideoFormat.hls,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
      setState(() => _ready = true);
    } catch (e) {
      _log.w('Failed to play motion banner: $e');
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    controller?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !_ready) return;
    if (state == AppLifecycleState.resumed) {
      controller.play();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final showVideo = _ready && !_failed && controller != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.fallback,
        AnimatedOpacity(
          opacity: showVideo ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 400),
          child: showVideo
              ? FittedBox(
                  fit: widget.fit,
                  alignment: widget.alignment,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
