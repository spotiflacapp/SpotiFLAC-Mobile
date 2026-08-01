import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/utils/user_facing_error.dart';

void main() {
  group('userFacingErrorMessage', () {
    test('hides an empty generic PlatformException', () {
      expect(
        userFacingErrorMessage(
          PlatformException(code: 'ERROR'),
          fallback: 'Could not save metadata',
        ),
        'Could not save metadata',
      );
      expect(
        userFacingErrorMessage(
          'PlatformException(ERROR, null, null, null)',
          fallback: 'Could not save metadata',
        ),
        'Could not save metadata',
      );
    });

    test('keeps a meaningful PlatformException message', () {
      expect(
        userFacingErrorMessage(
          PlatformException(
            code: 'write_failed',
            message: 'The selected file is not writable',
          ),
        ),
        'The selected file is not writable',
      );
      expect(
        userFacingErrorMessage(
          'PlatformException(ERROR, The selected file is not writable, null, null)',
        ),
        'The selected file is not writable',
      );
    });

    test('turns a meaningful platform code into readable text', () {
      expect(
        userFacingErrorMessage(PlatformException(code: 'permission_denied')),
        'Permission denied',
      );
    });

    test('removes exception wrappers, paths, and stack traces', () {
      expect(
        userFacingErrorMessage(
          "Exception: FileSystemException: Cannot open file, path = '/secret/song.flac'\n#0 internalCall",
        ),
        'Cannot open file',
      );
    });

    test('maps connectivity and internal implementation errors', () {
      expect(
        userFacingErrorMessage('SocketException: Failed host lookup: api.test'),
        'Unable to connect. Check your internet connection.',
      );
      expect(
        userFacingErrorMessage(
          'MissingPluginException(No implementation found for method save)',
          fallback: 'Could not save metadata',
        ),
        'Could not save metadata',
      );
    });

    test('preserves an ordinary backend error', () {
      expect(
        userFacingErrorMessage('Song not found on any service'),
        'Song not found on any service',
      );
    });
  });
}
