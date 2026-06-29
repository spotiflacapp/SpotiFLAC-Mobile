import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/services/app_remote_config_service.dart';

class AppAnnouncementDialog extends StatelessWidget {
  final RemoteAnnouncement announcement;
  final VoidCallback onDismiss;

  const AppAnnouncementDialog({
    super.key,
    required this.announcement,
    required this.onDismiss,
  });

  void _close(BuildContext context) {
    onDismiss();
    Navigator.pop(context);
  }

  Future<void> _openCta(BuildContext context) async {
    final ctaUrl = announcement.ctaUrl;
    if (ctaUrl == null || ctaUrl.isEmpty) {
      _showCtaOpenFailed(context);
      return;
    }

    final uri = Uri.tryParse(ctaUrl);
    if (uri == null) {
      _showCtaOpenFailed(context);
      return;
    }

    bool launched;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!context.mounted) return;
    if (!launched) {
      _showCtaOpenFailed(context);
      return;
    }

    onDismiss();
    Navigator.pop(context);
  }

  void _showCtaOpenFailed(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.announcementUnableToOpenLink)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUrgent = announcement.priority.toLowerCase() == 'high';

    // The notice can only be closed through an explicit affordance: never by
    // tapping the scrim or the system back button (handled by the barrier and
    // PopScope below). Always keep at least one way out (the X). A
    // non-dismissible announcement may omit the X only when it carries a CTA,
    // so the user can never get permanently trapped.
    final showCloseButton = announcement.dismissible || !announcement.hasCta;

    final actions = <Widget>[
      if (announcement.hasCta)
        FilledButton(
          onPressed: () => _openCta(context),
          child: Text(announcement.ctaLabel!),
        ),
    ];

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isUrgent ? Icons.priority_high_rounded : Icons.campaign_rounded,
              color: isUrgent ? colorScheme.error : colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(announcement.title),
              ),
            ),
            if (showCloseButton)
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                visualDensity: VisualDensity.compact,
                onPressed: () => _close(context),
              ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child: Text(
              announcement.message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ),
        ),
        actions: actions.isEmpty ? null : actions,
      ),
    );
  }
}

Future<void> showAppAnnouncementDialog(
  BuildContext context, {
  required RemoteAnnouncement announcement,
  required VoidCallback onDismiss,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        AppAnnouncementDialog(announcement: announcement, onDismiss: onDismiss),
  );
}
