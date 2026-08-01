import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/theme/cover_palette.dart';

/// Collapsing album-detail header shared by the album, local-album, and
/// downloaded-album screens: full-bleed [background] (optionally blurred and
/// scrimmed), bottom gradient, centered square cover, title, optional
/// subtitle/meta/actions rows, and a circular back button. Content fades out
/// below 30% expansion; the [title] fades into the toolbar instead.
///
/// Colours come from a scheme derived from [paletteSource] (see [CoverPalette])
/// and are published to descendants through [HeaderPalette], so the header
/// follows both the artwork and the app's light/dark mode instead of assuming a
/// black backdrop with white text.
class AlbumDetailHeader extends StatelessWidget {
  const AlbumDetailHeader({
    super.key,
    required this.title,
    required this.expandedHeight,
    required this.showTitleInAppBar,
    required this.background,
    this.paletteSource,
    this.blurAndScrimBackground = true,
    this.coverBuilder,
    this.subtitle,
    this.meta,
    this.actions,
    this.appBarActions,
    this.appBarTitle,
    this.leading,
    this.backgroundColor,
  });

  final String title;
  final double expandedHeight;
  final bool showTitleInAppBar;

  /// Full-bleed background content (cover image, motion banner, placeholder).
  final Widget background;

  /// Cover URL or local path the header palette is derived from. Null keeps the
  /// app's own colour scheme.
  final String? paletteSource;

  /// Blur the background and dim it 35%; disable for motion banners and
  /// placeholder backgrounds.
  final bool blurAndScrimBackground;

  /// Builds the centered square cover for the given side length; null hides
  /// the cover block (the header wraps it in the shared shadow + rounding).
  final Widget Function(BuildContext context, double coverSize)? coverBuilder;

  /// Artist line under the title (plain text or a clickable artist widget).
  final Widget? subtitle;

  /// "•"-joined meta row under the subtitle.
  final Widget? meta;

  /// Action row (play/shuffle, download-all, ...) under the meta row.
  final Widget? actions;

  /// Extra toolbar actions (top-right).
  final List<Widget>? appBarActions;

  /// Toolbar title when it should differ from [title] (e.g. a selection
  /// count); defaults to [title].
  final String? appBarTitle;

  /// Replaces the default circular back button.
  final Widget? leading;

  final Color? backgroundColor;

  /// Shrinks long titles so up to three lines fit the header.
  double _titleFontSize() {
    final length = title.trim().length;
    if (length > 45) return 18;
    if (length > 30) return 21;
    return 24;
  }

  @override
  Widget build(BuildContext context) {
    return CoverPaletteBuilder(
      imageSource: paletteSource,
      builder: (context, headerScheme) => _buildAppBar(context, headerScheme),
    );
  }

  Widget _buildAppBar(BuildContext context, ColorScheme headerScheme) {
    final tokens = context.tokens;
    // Scrim and gradient are drawn from the palette surface instead of black,
    // so a light theme gets a light header with dark text and a dark theme
    // keeps the familiar dark treatment — both tinted by the artwork.
    final scrimColor = headerScheme.surface;
    final onHeader = headerScheme.onSurface;

    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: true,
      stretch: true,
      backgroundColor: backgroundColor ?? headerScheme.surface,
      surfaceTintColor: Colors.transparent,
      title: AnimatedOpacity(
        duration: tokens.motionFast,
        opacity: showTitleInAppBar ? 1.0 : 0.0,
        child: Text(
          appBarTitle ?? title,
          style: TextStyle(
            color: onHeader,
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
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (blurAndScrimBackground)
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                    child: background,
                  )
                else
                  background,
                if (blurAndScrimBackground)
                  ColoredBox(color: scrimColor.withValues(alpha: 0.4)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: expandedHeight * 0.65,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scrimColor.withValues(alpha: 0),
                          scrimColor.withValues(alpha: 0.92),
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
                    duration: tokens.motionFast,
                    opacity: showContent ? 1.0 : 0.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (coverBuilder != null) ...[
                          Builder(
                            builder: (context) {
                              final coverSize = (constraints.maxWidth * 0.5)
                                  .clamp(150.0, 210.0)
                                  .toDouble();
                              return Container(
                                width: coverSize,
                                height: coverSize,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    tokens.radiusControl,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: headerScheme.shadow.withValues(
                                        alpha: 0.45,
                                      ),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    tokens.radiusControl,
                                  ),
                                  child: coverBuilder!(context, coverSize),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                        ],
                        Text(
                          title,
                          style: TextStyle(
                            color: onHeader,
                            fontSize: _titleFontSize(),
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 6),
                          subtitle!,
                        ],
                        if (meta != null) ...[
                          const SizedBox(height: 12),
                          meta!,
                        ],
                        if (actions != null) ...[
                          const SizedBox(height: 16),
                          actions!,
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            stretchModes: const [StretchMode.zoomBackground],
          );
        },
      ),
      leading:
          leading ??
          IconButton.filledTonal(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back),
            style: IconButton.styleFrom(
              minimumSize: Size.square(tokens.minTouchTarget),
              backgroundColor: headerScheme.surfaceContainerHigh.withValues(
                alpha: 0.75,
              ),
              foregroundColor: headerScheme.onSurfaceVariant,
            ),
            onPressed: () => Navigator.pop(context),
          ),
      actions: appBarActions,
    );
  }
}

/// Primary "play" pill + shuffle circle used by the local and downloaded album
/// headers. Colours follow the [HeaderPalette].
class AlbumPlayActions extends StatelessWidget {
  const AlbumPlayActions({
    super.key,
    required this.playLabel,
    required this.shuffleTooltip,
    required this.onPlay,
    required this.onShuffle,
  });

  final String playLabel;
  final String shuffleTooltip;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = HeaderPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: FilledButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow, size: 20),
            label: Text(
              playLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              minimumSize: Size(0, tokens.minTouchTarget),
              shape: const StadiumBorder(),
            ),
          ),
        ),
        SizedBox(width: tokens.gapMd),
        IconButton.filledTonal(
          tooltip: shuffleTooltip,
          onPressed: onShuffle,
          icon: const Icon(Icons.shuffle),
          style: IconButton.styleFrom(
            minimumSize: Size.square(tokens.minTouchTarget),
            backgroundColor: scheme.secondaryContainer.withValues(alpha: 0.8),
            foregroundColor: scheme.onSecondaryContainer,
          ),
        ),
      ],
    );
  }
}

/// Primary action pill in a detail header (download all, play all). Reads its
/// colours from [HeaderPalette] so it works on light and dark headers alike.
class HeaderFilledButton extends StatelessWidget {
  const HeaderFilledButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = HeaderPalette.of(context);
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: scheme.primary.withValues(alpha: 0.4),
        disabledForegroundColor: scheme.onPrimary.withValues(alpha: 0.7),
        minimumSize: Size(0, tokens.minTouchTarget),
        shape: const StadiumBorder(),
      ),
    );
  }
}

/// Circular header icon button (add-to-playlist, love-all, ...). Sized to the
/// minimum touch target and tinted from the [HeaderPalette].
class HeaderCircleButton extends StatelessWidget {
  const HeaderCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Overrides the palette foreground, e.g. to mark an active "loved" state.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = HeaderPalette.of(context);
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: Size.square(tokens.minTouchTarget),
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        foregroundColor: iconColor ?? scheme.onSurfaceVariant,
      ),
    );
  }
}

/// "•"-joined row of [HeaderMetaItem]s shown under the header subtitle
/// (track count, duration, quality, ...).
class HeaderMetaRow extends StatelessWidget {
  const HeaderMetaRow({super.key, required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final scheme = HeaderPalette.of(context);
    final parts = <Widget>[];
    for (final item in items) {
      if (parts.isNotEmpty) {
        parts.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '•',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
        );
      }
      parts.add(item);
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 4,
      children: parts,
    );
  }
}

/// Single meta label (optional leading icon) for [HeaderMetaRow].
class HeaderMetaItem extends StatelessWidget {
  const HeaderMetaItem(this.label, {super.key, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = HeaderPalette.of(context);
    final textStyle = TextStyle(
      color: scheme.onSurface,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    if (icon == null) return Text(label, style: textStyle);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: scheme.onSurface),
        const SizedBox(width: 4),
        Text(label, style: textStyle),
      ],
    );
  }
}
