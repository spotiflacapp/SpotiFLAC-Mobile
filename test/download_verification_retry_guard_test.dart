import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/providers/download_verification_retry_guard.dart';

void main() {
  group('DownloadVerificationRetryGuard', () {
    test('failed challenge attempts do not consume the granted retry', () {
      final guard = DownloadVerificationRetryGuard();

      guard.recordVerificationResult('item-1', 'tidal-web', granted: false);

      expect(guard.hasRetriedAfterGrant('item-1', 'tidal-web'), isFalse);
    });

    test('completed grants allow only one automatic retry per service', () {
      final guard = DownloadVerificationRetryGuard();

      guard.recordVerificationResult('item-1', ' TIDAL-WEB ', granted: true);

      expect(guard.hasRetriedAfterGrant('item-1', 'tidal-web'), isTrue);
      expect(guard.hasRetriedAfterGrant('item-1', 'qobuz-web'), isFalse);
      expect(guard.hasRetriedAfterGrant('item-2', 'tidal-web'), isFalse);
    });

    test('manual retry clears every service marker for an item', () {
      final guard = DownloadVerificationRetryGuard()
        ..recordVerificationResult('item-1', 'tidal-web', granted: true)
        ..recordVerificationResult('item-1', 'qobuz-web', granted: true)
        ..recordVerificationResult('item-2', 'tidal-web', granted: true);

      guard.clearItem('item-1');

      expect(guard.hasRetriedAfterGrant('item-1', 'tidal-web'), isFalse);
      expect(guard.hasRetriedAfterGrant('item-1', 'qobuz-web'), isFalse);
      expect(guard.hasRetriedAfterGrant('item-2', 'tidal-web'), isTrue);
    });

    test('queue cleanup retains markers only for remaining items', () {
      final guard = DownloadVerificationRetryGuard()
        ..recordVerificationResult('removed', 'tidal-web', granted: true)
        ..recordVerificationResult('remaining', 'tidal-web', granted: true);

      guard.retainItems({'remaining'});

      expect(guard.hasRetriedAfterGrant('removed', 'tidal-web'), isFalse);
      expect(guard.hasRetriedAfterGrant('remaining', 'tidal-web'), isTrue);
    });
  });
}
