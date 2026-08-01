import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/widgets/track_collection_action_policy.dart';

void main() {
  group('quality variant track menu', () {
    test('is hidden when quality variants are disabled', () {
      expect(
        resolveQualityVariantMenuAction(
          allowQualityVariants: false,
          hasLocalPlaybackCandidate: true,
        ),
        isNull,
      );
    });

    test('offers another download when the track is not local', () {
      expect(
        resolveQualityVariantMenuAction(
          allowQualityVariants: true,
          hasLocalPlaybackCandidate: false,
        ),
        QualityVariantMenuAction.downloadAnotherQuality,
      );
    });

    test('swaps to local playback when row tap handles the download', () {
      expect(
        resolveQualityVariantMenuAction(
          allowQualityVariants: true,
          hasLocalPlaybackCandidate: true,
        ),
        QualityVariantMenuAction.playLocal,
      );
    });
  });
}
