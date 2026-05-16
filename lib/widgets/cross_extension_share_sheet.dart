import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/cross_extension_share_service.dart';
import '../services/share_intent_service.dart';
import '../utils/extensions.dart';

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
  State<CrossExtensionShareSheet> createState() => _CrossExtensionShareSheetState();
}

class _CrossExtensionShareSheetState extends State<CrossExtensionShareSheet> {
  final _shareService = CrossExtensionShareService();
  bool _isLoading = true;
  List<CrossShareResult> _results = [];

  @override
  void initState() {
    super.initState();
    _loadCrossLinks();
  }

  Future<void> _loadCrossLinks() async {
    try {
      final results = await _shareService.searchCrossExtension(
        name: widget.name,
        artists: widget.artists,
        type: widget.type,
        sourceExtensionId: widget.sourceExtensionId,
      );
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              context.l10n.openInOtherServices,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_results.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  context.l10n.shareSheetNoExtensions,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final result = _results[index];
                  final hasLink = result.itemId != null && result.itemId!.isNotEmpty;

                  return ListTile(
                    leading: _ExtensionIcon(extensionId: result.extensionId),
                    title: Text(
                      result.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: hasLink
                        ? null
                        : Text(
                            context.l10n.shareSheetNotFound,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                            ),
                          ),
                    trailing: hasLink
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 20),
                                tooltip: context.l10n.shareSheetCopyLink,
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: result.itemId!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('${result.displayName} ID copied'),
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                                tooltip: context.l10n.shareSheetOpenInSpotiFlac,
                                onPressed: () {
                                  Navigator.pop(context);
                                  ShareIntentService.instance.injectUrl(result.itemId!);
                                },
                              ),
                            ],
                          )
                        : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ExtensionIcon extends StatelessWidget {
  final String extensionId;

  const _ExtensionIcon({required this.extensionId});

  Color _colorFromId(String id) {
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
    final letter = extensionId.isNotEmpty ? extensionId[0].toUpperCase() : '?';
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
