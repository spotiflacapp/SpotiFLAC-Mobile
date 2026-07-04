import 'package:flutter/material.dart';

/// Wraps a child in a staggered fade-in + slide-up animation.
///
/// [index] controls the stagger delay (each item delayed by [staggerDelay]).
/// Set [animate] to false to skip the animation (e.g. when scrolling back).
class StaggeredListItem extends StatelessWidget {
  static const int _defaultMaxAnimatedItems = 10;

  final int index;
  final Widget child;
  final Duration duration;
  final Duration staggerDelay;
  final bool animate;
  final int maxAnimatedItems;

  const StaggeredListItem({
    super.key,
    required this.index,
    required this.child,
    this.duration = const Duration(milliseconds: 250),
    this.staggerDelay = const Duration(milliseconds: 40),
    this.animate = true,
    this.maxAnimatedItems = _defaultMaxAnimatedItems,
  });

  @override
  Widget build(BuildContext context) {
    if (!animate || index >= maxAnimatedItems) return child;
    final cappedIndex = index.clamp(0, maxAnimatedItems - 1);
    final delay = staggerDelay * cappedIndex;
    final totalDuration = duration + delay;

    return TweenAnimationBuilder<double>(
      key: ValueKey('stagger_$index'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: totalDuration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final delayFraction = totalDuration.inMilliseconds > 0
            ? delay.inMilliseconds / totalDuration.inMilliseconds
            : 0.0;
        final progress = value <= delayFraction
            ? 0.0
            : ((value - delayFraction) / (1.0 - delayFraction)).clamp(0.0, 1.0);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - progress)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// A convenience wrapper around [AnimatedSwitcher] that crossfades between
/// different widget states (loading, content, empty, error).
///
/// Assign a unique [ValueKey] to each child so the switcher detects changes.
class AnimatedStateSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;

  const AnimatedStateSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 250),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: child,
    );
  }
}

/// Creates a platform-aware material route.
///
/// This intentionally defers route transitions to Flutter's material route and
/// theme so Android predictive back and platform-default animations remain
/// intact.
Route<T> slidePageRoute<T>({required Widget page}) {
  return MaterialPageRoute<T>(builder: (context) => page);
}

/// A directional horizontal transition for adjacent content, such as moving
/// between next/previous items within the same detail context.
Route<T> adjacentHorizontalPageRoute<T>({
  required Widget page,
  required bool fromRight,
}) {
  return _AdjacentHorizontalPageRoute<T>(
    builder: (context) => page,
    fromRight: fromRight,
  );
}

class _AdjacentHorizontalPageRoute<T> extends MaterialPageRoute<T> {
  final bool fromRight;

  _AdjacentHorizontalPageRoute({
    required super.builder,
    required this.fromRight,
  });

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (animation.status == AnimationStatus.reverse) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    final begin = Offset(fromRight ? 0.22 : -0.22, 0);

    return SlideTransition(
      position: Tween<Offset>(begin: begin, end: Offset.zero).animate(curved),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}

/// A shimmer effect widget that can wrap skeleton placeholders.
class ShimmerLoading extends StatefulWidget {
  final Widget child;

  const ShimmerLoading({super.key, required this.child});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseColor = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.08),
            colorScheme.surface,
          )
        : Color.alphaBlend(
            Colors.black.withValues(alpha: 0.10),
            colorScheme.surface,
          );
    final highlightColor = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.14),
            colorScheme.surface,
          )
        : Color.alphaBlend(
            Colors.black.withValues(alpha: 0.01),
            colorScheme.surface,
          );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value,
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
              tileMode: TileMode.clamp,
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A skeleton placeholder box used inside [ShimmerLoading].
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.08),
            colorScheme.surface,
          )
        : Color.alphaBlend(
            Colors.black.withValues(alpha: 0.06),
            colorScheme.surface,
          );
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Track list skeleton – mimics a list of track items while loading.
class TrackListSkeleton extends StatelessWidget {
  final int itemCount;
  final bool showCoverHeader;

  const TrackListSkeleton({
    super.key,
    this.itemCount = 8,
    this.showCoverHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            if (showCoverHeader) const _CollectionHeaderSkeleton(),
            ...List.generate(itemCount, (index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const SkeletonBox(width: 48, height: 48, borderRadius: 8),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                            width: 150 + (index % 3) * 30,
                            height: 15,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              SkeletonBox(
                                width: 90 + (index % 2) * 20,
                                height: 12,
                                borderRadius: 4,
                              ),
                              const SizedBox(width: 8),
                              const SkeletonBox(
                                width: 38,
                                height: 12,
                                borderRadius: 6,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SkeletonBox(width: 24, height: 24, borderRadius: 12),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Grid skeleton – mimics a grid of album/playlist cards while loading.

/// Album track list skeleton – mimics the album screen track list layout
/// (track number + title + artist + trailing icon, no cover art thumbnail).
class AlbumTrackListSkeleton extends StatelessWidget {
  final int itemCount;
  final bool showCoverHeader;

  const AlbumTrackListSkeleton({
    super.key,
    this.itemCount = 10,
    this.showCoverHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            if (showCoverHeader) const _CollectionHeaderSkeleton(),
            ...List.generate(itemCount, (index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Center(
                        child: SkeletonBox(
                          width: 16,
                          height: 14,
                          borderRadius: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                            width: 130 + (index % 4) * 35,
                            height: 15,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              SkeletonBox(
                                width: 70 + (index % 3) * 20,
                                height: 12,
                                borderRadius: 4,
                              ),
                              const SizedBox(width: 8),
                              const SkeletonBox(
                                width: 38,
                                height: 12,
                                borderRadius: 6,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SkeletonBox(width: 24, height: 24, borderRadius: 12),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Header skeleton matching the redesigned album/playlist header: a blurred
/// backdrop block with a centered square cover, title/subtitle bars, a meta
/// line (year + quality badges) and the action button row.
class _CollectionHeaderSkeleton extends StatelessWidget {
  const _CollectionHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final coverSize = (screenWidth * 0.5).clamp(150.0, 210.0).toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        children: [
          SkeletonBox(
            width: coverSize,
            height: coverSize,
            borderRadius: 16,
          ),
          const SizedBox(height: 20),
          SkeletonBox(width: screenWidth * 0.6, height: 22, borderRadius: 6),
          const SizedBox(height: 10),
          SkeletonBox(width: screenWidth * 0.35, height: 15, borderRadius: 4),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SkeletonBox(width: 44, height: 14, borderRadius: 6),
              SizedBox(width: 10),
              SkeletonBox(width: 70, height: 14, borderRadius: 6),
              SizedBox(width: 10),
              SkeletonBox(width: 60, height: 14, borderRadius: 6),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SkeletonBox(width: 48, height: 48, borderRadius: 24),
              const SizedBox(width: 16),
              SkeletonBox(
                width: screenWidth * 0.45,
                height: 48,
                borderRadius: 24,
              ),
              const SizedBox(width: 16),
              const SkeletonBox(width: 48, height: 48, borderRadius: 24),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class GridSkeleton extends StatelessWidget {
  final int itemCount;
  final int crossAxisCount;

  const GridSkeleton({super.key, this.itemCount = 6, this.crossAxisCount = 2});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.75,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: SkeletonBox(
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: 12,
                  ),
                ),
                const SizedBox(height: 8),
                SkeletonBox(
                  width: 80 + (index % 3) * 20,
                  height: 12,
                  borderRadius: 4,
                ),
                const SizedBox(height: 4),
                SkeletonBox(
                  width: 50 + (index % 2) * 15,
                  height: 10,
                  borderRadius: 4,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Artist screen skeleton shown below the SliverAppBar header while the
/// discography loads: optional cover placeholder, "Popular" section, and the
/// horizontal album sections.
class ArtistScreenSkeleton extends StatelessWidget {
  final int popularCount;
  final int albumCount;
  final bool showCoverHeader;
  final bool showPopularSection;

  const ArtistScreenSkeleton({
    super.key,
    this.popularCount = 5,
    this.albumCount = 5,
    this.showCoverHeader = true,
    this.showPopularSection = true,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return ShimmerLoading(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showCoverHeader)
              SkeletonBox(
                width: screenWidth,
                height: screenWidth * 0.75,
                borderRadius: 0,
              ),
            if (showPopularSection) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: SkeletonBox(width: 110, height: 22, borderRadius: 4),
              ),
              ...List.generate(popularCount, (index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 24,
                        child: Center(
                          child: SkeletonBox(
                            width: 12,
                            height: 14,
                            borderRadius: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const SkeletonBox(width: 48, height: 48, borderRadius: 4),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(
                              width: 120 + (index % 4) * 30,
                              height: 14,
                              borderRadius: 4,
                            ),
                            const SizedBox(height: 8),

                            const SkeletonBox(
                              width: 64,
                              height: 14,
                              borderRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const SkeletonBox(width: 18, height: 18, borderRadius: 4),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SkeletonBox(width: 120, height: 22, borderRadius: 4),
            ),
            SizedBox(
              height: 190,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: albumCount,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SkeletonBox(width: 140, height: 140),
                        const SizedBox(height: 8),
                        SkeletonBox(
                          width: 80 + (index % 3) * 20,
                          height: 12,
                          borderRadius: 4,
                        ),
                        const SizedBox(height: 4),
                        SkeletonBox(
                          width: 50 + (index % 2) * 15,
                          height: 10,
                          borderRadius: 4,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Home search skeleton – mimics filter chips + sectioned results
/// (Artists section with rounded card items, Albums section, etc.)
class HomeSearchSkeleton extends StatelessWidget {
  const HomeSearchSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  SkeletonBox(width: 48, height: 32, borderRadius: 16),
                  const SizedBox(width: 8),
                  SkeletonBox(width: 64, height: 32, borderRadius: 16),
                  const SizedBox(width: 8),
                  SkeletonBox(width: 72, height: 32, borderRadius: 16),
                  const SizedBox(width: 8),
                  SkeletonBox(width: 60, height: 32, borderRadius: 16),
                  const SizedBox(width: 8),
                  SkeletonBox(width: 70, height: 32, borderRadius: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _sectionSkeleton(context, 70, 2),
          const SizedBox(height: 16),
          _sectionSkeleton(context, 65, 4),
        ],
      ),
    );
  }

  static Widget _sectionSkeleton(
    BuildContext context,
    double headerWidth,
    int itemCount,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SkeletonBox(width: headerWidth, height: 18, borderRadius: 4),
              const Spacer(),
              const SkeletonBox(width: 50, height: 16, borderRadius: 4),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: List.generate(itemCount, (index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const SkeletonBox(width: 48, height: 48, borderRadius: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                            width: 100 + (index % 3) * 40,
                            height: 14,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 6),
                          SkeletonBox(
                            width: 60 + (index % 2) * 25,
                            height: 12,
                            borderRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SkeletonBox(width: 20, height: 20, borderRadius: 10),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

/// An animated selection indicator that scales in/out and crossfades the
/// checked/unchecked state.
class AnimatedSelectionCheckbox extends StatelessWidget {
  final bool visible;
  final bool selected;
  final ColorScheme colorScheme;
  final double size;

  /// Background color when not selected. Defaults to `Colors.transparent`.
  final Color? unselectedColor;

  const AnimatedSelectionCheckbox({
    super.key,
    required this.visible,
    required this.selected,
    required this.colorScheme,
    this.size = 20,
    this.unselectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : unselectedColor ?? Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outline,
            width: 2,
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: selected
              ? Icon(
                  Icons.check,
                  key: const ValueKey('checked'),
                  size: size - 6,
                  color: colorScheme.onPrimary,
                )
              : SizedBox(
                  key: const ValueKey('unchecked'),
                  width: size - 6,
                  height: size - 6,
                ),
        ),
      ),
    );
  }
}

/// A widget that briefly flashes a success color behind its child and shows
/// an animated checkmark when [showSuccess] transitions to true.
class DownloadSuccessOverlay extends StatefulWidget {
  final bool showSuccess;
  final Widget child;

  const DownloadSuccessOverlay({
    super.key,
    required this.showSuccess,
    required this.child,
  });

  @override
  State<DownloadSuccessOverlay> createState() => _DownloadSuccessOverlayState();
}

class _DownloadSuccessOverlayState extends State<DownloadSuccessOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _flashAnimation;
  late bool _wasSuccess;

  @override
  void initState() {
    super.initState();
    _wasSuccess = widget.showSuccess;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _flashAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.15), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.15, end: 0.0), weight: 70),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(DownloadSuccessOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showSuccess && !_wasSuccess) {
      _controller.forward(from: 0);
    }
    _wasSuccess = widget.showSuccess;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: _flashAnimation.value),
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Wraps a [Badge] child and plays a brief scale-bump whenever [count] changes.
class AnimatedBadge extends StatefulWidget {
  final int count;
  final Widget child;

  const AnimatedBadge({super.key, required this.count, required this.child});

  @override
  State<AnimatedBadge> createState() => _AnimatedBadgeState();
}

class _AnimatedBadgeState extends State<AnimatedBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  int _previousCount = 0;

  @override
  void initState() {
    super.initState();
    _previousCount = widget.count;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 60),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(AnimatedBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != _previousCount && widget.count > _previousCount) {
      _controller.forward(from: 0);
    }
    _previousCount = widget.count;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scaleAnimation, child: widget.child);
  }
}

/// Build a removal animation for [AnimatedList] items.
/// Use as the `builder` callback in [AnimatedListState.removeItem].
Widget buildRemovalAnimation(Widget child, Animation<double> animation) {
  return SizeTransition(
    sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
    child: FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
      child: child,
    ),
  );
}
