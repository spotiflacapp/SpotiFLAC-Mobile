import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/utils/file_access.dart';

void main() {
  group('shouldValidateIosOutputDir', () {
    test('validates a non-empty app-folder path on iOS', () {
      expect(
        shouldValidateIosOutputDir(
          isIOS: true,
          isSafMode: false,
          outputDir:
              '/private/var/mobile/Containers/Data/Application/ABC/Documents/SpotiFLAC',
          downloadDirectoryBookmark: '',
        ),
        isTrue,
      );
    });

    test(
      'skips validation when a security-scoped bookmark is present (#439)',
      () {
        // The persisted path may look like iCloud Drive or fail the
        // structural writable-path check even though the bookmark grants
        // real write access - the bookmark, not this path shape, is
        // authoritative. Running the check anyway is what silently reset
        // and dropped the user's chosen folder.
        expect(
          shouldValidateIosOutputDir(
            isIOS: true,
            isSafMode: false,
            outputDir:
                '/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Music',
            downloadDirectoryBookmark: 'bookmark-bytes',
          ),
          isFalse,
        );
      },
    );

    test('skips validation off iOS', () {
      expect(
        shouldValidateIosOutputDir(
          isIOS: false,
          isSafMode: false,
          outputDir: '/data/user/0/com.zarz.spotiflac/files/SpotiFLAC',
          downloadDirectoryBookmark: '',
        ),
        isFalse,
      );
    });

    test('skips validation in SAF mode', () {
      expect(
        shouldValidateIosOutputDir(
          isIOS: true,
          isSafMode: true,
          outputDir: '/some/path',
          downloadDirectoryBookmark: '',
        ),
        isFalse,
      );
    });

    test('skips validation when there is no output directory yet', () {
      expect(
        shouldValidateIosOutputDir(
          isIOS: true,
          isSafMode: false,
          outputDir: '',
          downloadDirectoryBookmark: '',
        ),
        isFalse,
      );
    });
  });
}
