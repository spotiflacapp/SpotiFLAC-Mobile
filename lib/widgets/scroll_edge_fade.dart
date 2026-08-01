import 'package:flutter/material.dart';

/// Overlays a gradient on the trailing edge of a scrollable while more
/// content remains beyond it, signalling that the view can scroll.
class ScrollEdgeFade extends StatefulWidget {
  final Widget child;
  final Axis axis;

  /// Thickness of the fade: height for vertical, width for horizontal.
  final double size;

  const ScrollEdgeFade({
    super.key,
    required this.child,
    this.axis = Axis.vertical,
    this.size = 96,
  });

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  bool _hasMore = false;

  bool _onMetrics(ScrollMetrics metrics) {
    if (metrics.axis == widget.axis) {
      final hasMore = metrics.extentAfter > 8;
      if (hasMore != _hasMore) setState(() => _hasMore = hasMore);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    final horizontal = widget.axis == Axis.horizontal;
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) => _onMetrics(notification.metrics),
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (notification) => _onMetrics(notification.metrics),
            child: widget.child,
          ),
        ),
        PositionedDirectional(
          start: horizontal ? null : 0,
          end: 0,
          top: horizontal ? 0 : null,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _hasMore ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: horizontal ? widget.size : null,
                height: horizontal ? null : widget.size,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: horizontal
                        ? AlignmentDirectional.centerStart
                        : Alignment.topCenter,
                    end: horizontal
                        ? AlignmentDirectional.centerEnd
                        : Alignment.bottomCenter,
                    colors: [background.withValues(alpha: 0), background],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
