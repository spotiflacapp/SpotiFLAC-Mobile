import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/utils/synced_lyrics_scroll.dart';

void main() {
  test('symmetric padding lets the final lyric line reach center', () {
    const viewport = 500.0;
    const lineExtent = 64.0;
    const lineCount = 20;
    final padding = syncedLyricsCenterPadding(
      viewportDimension: viewport,
      estimatedLineExtent: lineExtent,
    );
    final contentExtent = (padding * 2) + (lineCount * lineExtent);
    final maxScrollExtent = contentExtent - viewport;
    final lastLineOffset = syncedLyricsEstimatedOffset(
      index: lineCount - 1,
      estimatedLineExtent: lineExtent,
    );

    expect(padding, 218);
    expect(lastLineOffset, maxScrollExtent);
  });

  test('small viewports retain minimum breathing room', () {
    expect(
      syncedLyricsCenterPadding(viewportDimension: 80, estimatedLineExtent: 64),
      24,
    );
  });
}
