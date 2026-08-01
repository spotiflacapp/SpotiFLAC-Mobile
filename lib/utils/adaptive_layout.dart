import 'package:flutter/widgets.dart';

/// Widest content span for a surface of [maxWidth]: content is never narrower
/// than [contentMaxWidth], and the centering margin never exceeds 80dp per
/// side — so tablets keep near-full-width rows (issue #493) instead of a
/// fixed 720dp column floating in whitespace.
double adaptiveContentMaxWidth(
  double maxWidth, {
  double contentMaxWidth = 720,
}) => maxWidth > contentMaxWidth + 160 ? maxWidth - 160 : contentMaxWidth;

/// Horizontal inset that centers content of [maxWidth] at
/// [adaptiveContentMaxWidth]; zero once it fits. Prefer this constraint-based
/// form when the widget may live inside an already clamped box (e.g. a bottom
/// sheet), where screen width would over-inset.
double wideInsetForWidth(double maxWidth, {double contentMaxWidth = 720}) =>
    maxWidth > contentMaxWidth
    ? ((maxWidth - contentMaxWidth) / 2).clamp(0.0, 80.0)
    : 0;

/// Horizontal inset that centers full-width list content on tablets/landscape;
/// zero on phones, so rows stop stretching across the whole screen.
double wideListInset(BuildContext context, {double contentMaxWidth = 720}) =>
    wideInsetForWidth(
      MediaQuery.sizeOf(context).width,
      contentMaxWidth: contentMaxWidth,
    );
