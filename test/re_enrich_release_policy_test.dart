import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/utils/re_enrich_release_policy.dart';

void main() {
  test(
    'only deliberate single-file re-enrich can replace release identity',
    () {
      expect(
        allowsReleaseIdentityReplacement(ReEnrichOperationScope.singleFile),
        isTrue,
      );
      expect(
        allowsReleaseIdentityReplacement(ReEnrichOperationScope.batch),
        isFalse,
      );
    },
  );
}
