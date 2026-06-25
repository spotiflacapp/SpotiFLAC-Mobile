import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';

final _log = AppLogger('ExtensionAuthLauncher');

bool isExtensionVerificationRequired(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('verify_required') ||
      message.contains('verification_required') ||
      message.contains('needsverification') ||
      message.contains('needs verification');
}

Future<void> openPendingExtensionVerification(String extensionId) async {
  final normalizedExtensionId = extensionId.trim();
  if (normalizedExtensionId.isEmpty) return;

  try {
    final pending = await PlatformBridge.getExtensionPendingAuth(
      normalizedExtensionId,
    );
    final authUrl = pending?['auth_url']?.toString().trim() ?? '';
    if (authUrl.isEmpty) return;

    final uri = Uri.tryParse(authUrl);
    if (uri == null) return;

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched) {
      _log.i('Opened verification challenge for $normalizedExtensionId');
    } else {
      _log.w(
        'Could not open verification challenge for $normalizedExtensionId',
      );
    }
  } catch (e) {
    _log.w(
      'Failed to open verification challenge for $normalizedExtensionId: $e',
    );
  }
}
