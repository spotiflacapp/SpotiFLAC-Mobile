import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/utils/lyrics_metadata_helper.dart';

void main() {
  group('lyrics display normalization', () {
    test('rejects metadata-only embedded LRC', () {
      const raw = '''
[ti:Banna Re]
[ar:Dhvani Bhanushali]
[al:Banna Re]
[by:SpotiFLAC Mobile]
''';

      expect(cleanLyricsForDisplay(raw), isEmpty);
      expect(hasUsableLyricsContent(raw), isFalse);
      expect(
        hasEmbeddedLyricsMetadata({'LYRICS': raw, 'UNSYNCEDLYRICS': raw}),
        isFalse,
      );
    });

    test('keeps timed, background, and speaker lyric content', () {
      const raw = '''
[ti:Song]
[00:01.25]Lead line
[bg:Background line]
[00:02:500]<00:02.500>v2: Harmony line
''';

      expect(
        cleanLyricsForDisplay(raw),
        'Lead line\nBackground line\nHarmony line',
      );
      expect(hasUsableLyricsContent(raw), isTrue);
    });

    test('recognizes the instrumental marker without rendering it as text', () {
      expect(isInstrumentalLyricsMarker(' [Instrumental:TRUE] '), isTrue);
      expect(hasUsableLyricsContent('[instrumental:true]'), isTrue);
      expect(cleanLyricsForDisplay('[instrumental:true]'), isEmpty);
    });
  });
}
