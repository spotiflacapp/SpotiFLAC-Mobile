// lib/widgets/cross_extension_share_sheet.dart
//
// Usage example from album_screen.dart:
//
//   IconButton(
//     icon: const Icon(Icons.open_in_new_rounded),
//     tooltip: 'Open in other services',
//     onPressed: () => CrossExtensionShareSheet.show(
//       context,
//       name: album.name,
//       artists: album.artists,
//       type: 'album',
//       sourceExtensionId: album.providerId,
//     ),
//   )

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/cross_extension_share_service.dart';

class CrossExtensionShareSheet extends StatefulWidget {
  final String name;
  final String artists;
  final String type; // "album" | "artist" | "playlist"
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
            // Handle bar
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
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'Open in other services',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                widget.name,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            // Results
            FutureBuilder<List<CrossExtensionShareResult>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final results = snapshot.data ?? [];

                if (results.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No other extensions installed.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: results.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 20, endIndent: 20),
                  itemBuilder: (context, index) {
                    final res = results[index];
                    return _ResultTile(result: res);
                  },
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

  const _ResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (!result.found) {
      // Not found state
      return ListTile(
        leading: _ExtensionIcon(extensionId: result.extensionId),
        title: Text(
          result.displayName,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        subtitle: Text(
          result.error == 'cross-service playlist matching not supported'
              ? 'Playlists can\'t be matched across services'
              : 'Not found',
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

    return ListTile(
      leading: _ExtensionIcon(extensionId: result.extensionId),
      title: Text(
        result.displayName,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: result.itemName != null
          ? Text(
              result.itemName!,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Copy ID button
          if (result.itemId != null)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: 'Copy ID',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: result.itemId!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('ID copied: ${result.itemId}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          Icon(
            Icons.check_circle_rounded,
            color: colorScheme.primary,
            size: 20,
          ),
        ],
      ),
      onTap: result.itemId != null
          ? () {
              // Copy to clipboard as a simple sharing mechanism.
              // You can extend this to open the extension's detail page instead.
              Clipboard.setData(ClipboardData(text: result.itemId!));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${result.displayName} ID copied — open in the app to navigate there.',
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          : null,
    );
  }
}

/// Simple colored circle with the first letter of the extension ID.
/// Replace with actual extension icon loading if your app supports it.
class _ExtensionIcon extends StatelessWidget {
  final String extensionId;

  const _ExtensionIcon({required this.extensionId});

  Color _colorFromId(String id) {
    final colors = [
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
    final letter =
        extensionId.isNotEmpty ? extensionId[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 18,
      backgroundColor: _colorFromId(extensionId),
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
