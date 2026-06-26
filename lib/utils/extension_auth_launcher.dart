import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';

final _log = AppLogger('ExtensionAuthLauncher');

bool isExtensionVerificationRequired(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('verify_required') ||
      message.contains('verification_required') ||
      message.contains('verification required') ||
      message.contains('needsverification') ||
      message.contains('needs verification') ||
      message.contains('unauthorized') ||
      message.contains('precondition required') ||
      _containsHttpStatusCode(message, '401') ||
      _containsHttpStatusCode(message, '428');
}

bool _containsHttpStatusCode(String message, String code) {
  return message.contains('http $code') ||
      message.contains('http status $code') ||
      message.contains('status $code') ||
      message.contains('$code for ') ||
      message.contains('$code:') ||
      message.contains('$code;');
}

Future<bool> openPendingExtensionVerification(String extensionId) async {
  final normalizedExtensionId = extensionId.trim();
  if (normalizedExtensionId.isEmpty) return false;

  try {
    final pending = await PlatformBridge.getExtensionPendingAuth(
      normalizedExtensionId,
    );
    final authUrl = pending?['auth_url']?.toString().trim() ?? '';
    if (authUrl.isEmpty) return false;

    final uri = Uri.tryParse(authUrl);
    if (uri == null) return false;

    var launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!launched) {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    if (launched) {
      _log.i('Opened verification challenge for $normalizedExtensionId');
    } else {
      _log.w(
        'Could not open verification challenge for $normalizedExtensionId',
      );
    }
    return launched;
  } catch (e) {
    _log.w(
      'Failed to open verification challenge for $normalizedExtensionId: $e',
    );
    return false;
  }
}
