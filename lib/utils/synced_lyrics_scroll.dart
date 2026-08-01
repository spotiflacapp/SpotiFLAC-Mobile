import 'dart:math' as math;

/// Symmetric list padding that lets the first and last lyric lines reach the
/// vertical center instead of getting pinned to a viewport edge.
double syncedLyricsCenterPadding({
  required double viewportDimension,
  required double estimatedLineExtent,
  double minimumPadding = 24,
}) {
  return math.max(
    minimumPadding,
    (viewportDimension - estimatedLineExtent) / 2,
  );
}

/// Estimated scroll offset when symmetric center padding is applied.
double syncedLyricsEstimatedOffset({
  required int index,
  required double estimatedLineExtent,
}) {
  if (index <= 0) return 0;
  return index * estimatedLineExtent;
}
