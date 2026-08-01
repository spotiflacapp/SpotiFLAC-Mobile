import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/l10n/l10n.dart';

/// Small "In Library" chip shown next to a track that already exists in the
/// local library or download history.
class InLibraryBadge extends StatelessWidget {
  const InLibraryBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: context.tokens.badgePadding,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: context.tokens.borderRadiusBadge,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_outlined,
            size: 12,
            color: colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 3),
          Text(
            context.l10n.libraryInLibrary,
            style: TextStyle(
              fontSize: context.tokens.badgeFontSize,
              fontWeight: FontWeight.w500,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
