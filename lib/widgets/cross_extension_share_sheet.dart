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

  bool _isLoading = true;
  List<CrossExtensionShareResult> _results = [];

  @override
  void initState() {
    super.initState();
    _loadCrossLinks();
  }

  Future<void> _loadCrossLinks() async {
    try {
      final results = await CrossExtensionShareService.findAcrossExtensions(
        name: widget.name,
        artists: widget.artists,
        type: widget.type,
        sourceExtensionId: widget.sourceExtensionId,
      );
      if (mounted) {
        setState(() {
          final found = results
              .where((r) => r.itemId != null && r.itemId!.isNotEmpty)
              .toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName));
          final notFound = results
              .where((r) => r.itemId == null || r.itemId!.isEmpty)
              .toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName));
          _results = [...found, ...notFound];
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

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  context.l10n.openInOtherServices,
                  style: textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (widget.name.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                  child: Text(
                    widget.artists.isNotEmpty
                        ? '${widget.name} · ${widget.artists}'
                        : widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              // Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty
                        ? Center(
                            child: Text(
                              context.l10n.shareSheetNoExtensions,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: EdgeInsets.only(
                              top: 8,
                              bottom:
                                  MediaQuery.of(context).padding.bottom + 16,
                            ),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, indent: 68),
                            itemBuilder: (context, index) {
                              final result = _results[index];
                              final hasLink = result.itemId != null &&
                                  result.itemId!.isNotEmpty;
                              return _ResultTile(
                                result: result,
                                hasLink: hasLink,
                                onCopy: () {
                                  Clipboard.setData(
                                    ClipboardData(text: result.itemId!),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        context.l10n.shareSheetLinkCopied(
                                          result.displayName,
                                        ),
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                onOpen: () {
                                  Navigator.pop(context);
                                  ShareIntentService()
                                      .injectUrl(result.itemId!);
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  final CrossExtensionShareResult result;
  final bool hasLink;
  final VoidCallback onCopy;
  final VoidCallback onOpen;

  const _ResultTile({
    required this.result,
    required this.hasLink,
    required this.onCopy,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Opacity(
      opacity: hasLink ? 1.0 : 0.45,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _ExtensionIcon(
          extensionId: result.extensionId,
          displayName: result.displayName,
          hasLink: hasLink,
        ),
        title: Text(
          result.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: hasLink ? null : colorScheme.onSurfaceVariant,
          ),
        ),
        subtitle: hasLink
            ? Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 13,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      result.itemName?.isNotEmpty == true
                          ? result.itemName!
                          : result.itemId!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              )
            : Text(
                context.l10n.shareSheetNotFound,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
        trailing: hasLink
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    tooltip: context.l10n.shareSheetCopyLink,
                    onPressed: onCopy,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.open_in_new_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    tooltip: context.l10n.shareSheetOpenInSpotiFlac,
                    onPressed: onOpen,
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

class _ExtensionIcon extends StatelessWidget {
  final String extensionId;
  final String displayName;
  final bool hasLink;

  const _ExtensionIcon({
    required this.extensionId,
    required this.displayName,
    required this.hasLink,
  });

  Color _colorFromId(String id) {
    const colors = [
      Color(0xFF6750A4),
      Color(0xFF00897B),
      Color(0xFF1E88E5),
      Color(0xFFE67E22),
      Color(0xFFE91E63),
      Color(0xFF00ACC1),
      Color(0xFF43A047),
      Color(0xFF8E24AA),
    ];
    final hash = id.codeUnits.fold(0, (a, b) => a + b);
    return colors[hash % colors.length];
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFromId(extensionId);
    return CircleAvatar(
      radius: 22,
      backgroundColor: hasLink ? color : color.withOpacity(0.4),
      child: Text(
        _initials(displayName),
        style: TextStyle(
          color: hasLink ? Colors.white : Colors.white70,
          fontWeight: FontWeight.bold,
          fontSize: displayName.split(' ').length >= 2 ? 13 : 15,
        ),
      ),
    );
  }
}
