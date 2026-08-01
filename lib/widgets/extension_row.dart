import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';

/// Square extension icon with a tinted fallback.
///
/// Both the store and the installed-extensions page drew this by hand with the
/// same 44dp box, radius and fallback-icon logic, differing only in whether the
/// image came from a file or the network.
class ExtensionAvatar extends StatelessWidget {
  const ExtensionAvatar({
    super.key,
    required this.fallbackIcon,
    this.filePath,
    this.imageUrl,
    this.background,
    this.foreground,
  });

  /// Shown when no image is available or the image fails to load.
  final IconData fallbackIcon;

  /// Local icon shipped inside an installed extension.
  final String? filePath;

  /// Remote icon from the store registry.
  final String? imageUrl;

  final Color? background;
  final Color? foreground;

  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;
    final borderRadius = tokens.borderRadiusCover;
    final fallback = Icon(
      fallbackIcon,
      color: foreground ?? colorScheme.onPrimaryContainer,
    );

    Widget? image;
    if (filePath != null && filePath!.isNotEmpty) {
      image = Image.file(
        File(filePath!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      image = Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? colorScheme.primaryContainer,
        borderRadius: borderRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: image ?? fallback,
    );
  }
}

/// Row shell shared by the extension store and the installed-extensions list:
/// avatar, title/subtitle column, trailing control, and the group divider.
class ExtensionRow extends StatelessWidget {
  const ExtensionRow({
    super.key,
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.showDivider,
    this.trailing,
    this.onTap,
  });

  final Widget avatar;

  /// A widget rather than a string: the store row appends a version pill.
  final Widget title;

  final Widget subtitle;
  final bool showDivider;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.gapLg,
              vertical: tokens.gapMd,
            ),
            child: Row(
              children: [
                avatar,
                SizedBox(width: tokens.gapLg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DefaultTextStyle.merge(
                        style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        child: title,
                      ),
                      SizedBox(height: tokens.gapXs / 2),
                      subtitle,
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            // Aligns with the text column: avatar width + its trailing gap.
            indent: ExtensionAvatar.size + tokens.gapLg * 2,
            endIndent: tokens.gapLg,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
      ],
    );
  }
}
