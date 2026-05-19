// lib/widgets/cross_extension_share_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/services/cross_extension_share_service.dart';
import 'package:spotiflac_android/services/share_intent_service.dart';

class CrossExtensionShareSheet extends StatefulWidget {
  final String name;
  final String artists;
  final String type;
  final String sourceExtensionId;

  const CrossExtensionShareSheet({
    super.key,
    required this.name,
    required this.artists,
    required this.type,
    required this.sourceExtensionId,
  });

  static Future<void> show(
    BuildContext context, {
    required String name,
    required String artists,
    required String type,
    required String sourceExtensionId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CrossExtensionShareSheet(
        name: name,
        artists: artists,
        type: type,
        sourceExtensionId: sourceExtensionId,
      ),
    );
  }

  @override
  State<CrossExtensionShareSheet> createState() =>
      _CrossExtensionShareSheetState();
}

class _CrossExtensionShareSheetState extends State<CrossExtensionShareSheet> {
  late final Future<List<CrossExtensionShareResult>> _future;

  @override
  void initState() {
    super.initState();
    _future = CrossExtensionShareService.findAcrossExtensions(
      name: widget.name,
      artists: widget.artists,
      type: widget.type,
      sourceExtensionId: widget.sourceExtensionId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                context.l10n.openInOtherServices,
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                widget.artists.isNotEmpty
                    ? '${widget.name} · ${widget.artists}'
                    : widget.name,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            FutureBuilder<List<CrossExtensionShareResult>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final results = snapshot.data ?? [];

                if (results.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        context.l10n.shareSheetNoExtensions,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }

                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                    ),
                    itemBuilder: (context, index) => _ResultTile(
                      result: results[index],
                      type: widget.type,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final CrossExtensionShareResult result;
  final String type;

  const _ResultTile({required this.result, required this.type});

  void _copyLink(BuildContext context, String link) {
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.shareSheetCopyLink),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openInApp(BuildContext context, String link) {
    ShareIntentService().injectUrl(link);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (!result.found) {
      return ListTile(
        leading: _ExtensionAvatar(extensionId: result.extensionId),
        title: Text(
          result.displayName,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        subtitle: Text(
          context.l10n.shareSheetNotFound,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant.withOpacity(0.6),
          ),
        ),
        trailing: Icon(
          Icons.close_rounded,
          color: colorScheme.onSurfaceVariant.withOpacity(0.4),
          size: 18,
        ),
      );
    }

    final link = result.resolveLink(type);

    if (link == null || link.isEmpty) {
      return ListTile(
        leading: _ExtensionAvatar(extensionId: result.extensionId),
        title: Text(
          result.displayName,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          result.itemName ?? context.l10n.shareSheetNotFound,
          style: textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          Icons.help_outline_rounded,
          color: colorScheme.onSurfaceVariant.withOpacity(0.4),
          size: 18,
        ),
      );
    }

    return ListTile(
      leading: _ExtensionAvatar(extensionId: result.extensionId),
      title: Text(
        result.displayName,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        link,
        style: textTheme.bodySmall?.copyWith(color: colorScheme.primary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: context.l10n.shareSheetCopyLink,
            onPressed: () => _copyLink(context, link),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
            tooltip: context.l10n.shareSheetOpenInSpotiFlac,
            onPressed: () => _openInApp(context, link),
          ),
        ],
      ),
    );
  }
}

class _ExtensionAvatar extends StatelessWidget {
  final String extensionId;

  const _ExtensionAvatar({required this.extensionId});

  Color _color() {
    const colors = [
      Colors.deepPurple,
      Colors.teal,
      Colors.indigo,
      Colors.orange,
      Colors.pink,
      Colors.cyan,
      Colors.green,
    ];
    final hash = extensionId.codeUnits.fold(0, (a, b) => a + b);
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: _color(),
      child: Text(
        extensionId.isNotEmpty ? extensionId[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
