import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';

/// The drag handle shown at the top of every modal sheet.
///
/// Seventeen copies of this container existed across the app in two sizes
/// (40x4 tinted `onSurfaceVariant`, 32x4 tinted `outlineVariant`) with four
/// different margins. Sheets that opt into Material's own `showDragHandle`
/// get an equivalent affordance from the framework and should not add this.
class AppSheetHandle extends StatelessWidget {
  const AppSheetHandle({super.key, this.margin});

  /// Overrides the default spacing around the handle. Sheets whose first row
  /// already carries top padding pass [EdgeInsets.zero].
  final EdgeInsetsGeometry? margin;

  static const double _width = 40;
  static const double _height = 4;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ExcludeSemantics(
      child: Center(
        child: Container(
          width: _width,
          height: _height,
          margin:
              margin ??
              EdgeInsets.only(top: tokens.gapMd, bottom: tokens.gapSm),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(_height / 2),
          ),
        ),
      ),
    );
  }
}

/// A modal-sheet surface whose height and inner scroll position share one drag.
///
/// The child must attach the supplied [ScrollController] to its primary
/// vertical scroll view. Pulling down at the top then moves the whole surface;
/// releasing either restores it or dismisses it at the minimum extent.
class AppDraggableSheet extends StatelessWidget {
  const AppDraggableSheet({
    super.key,
    required this.builder,
    this.initialChildSize = 0.88,
    this.minChildSize = 0.25,
    this.maxChildSize = 0.88,
  });

  final ScrollableWidgetBuilder builder;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      snap: true,
      shouldCloseOnMinExtent: true,
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      builder: builder,
    );
  }
}

/// Standard chrome for modal sheet content: drag handle, optional title block,
/// height cap, keyboard inset and bottom safe area, so each sheet only supplies
/// its own body.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    required this.child,
    this.showHandle = true,
    this.title,
    this.subtitle,
    this.maxHeightFactor,
  });

  final Widget child;
  final bool showHandle;

  /// Leading title row. Rendered with the app's single sheet-title style
  /// instead of the three variants that had accumulated across sheets.
  final String? title;

  /// Secondary line under [title], e.g. the track a sheet is acting on.
  final String? subtitle;

  /// Caps the sheet at this fraction of the screen height.
  final double? maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHandle) const AppSheetHandle(),
        if (title != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.gapXl,
              tokens.gapLg,
              tokens.gapXl,
              subtitle == null ? tokens.gapSm : tokens.gapXs,
            ),
            child: Text(
              title!,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (subtitle != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.gapXl,
              0,
              tokens.gapXl,
              tokens.gapMd,
            ),
            child: Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Flexible(child: child),
      ],
    );

    if (maxHeightFactor != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor!,
        ),
        child: content,
      );
    }

    // Sheets containing text fields must lift above the keyboard; doing it here
    // means no call site has to remember `viewInsets`.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(top: false, child: content),
    );
  }
}

/// Opens a modal bottom sheet wrapped in [AppBottomSheet].
///
/// The shape comes from `ThemeData.bottomSheetTheme`, which is derived from
/// [AppTokens.radiusSheet]; call sites no longer pass a `shape` and therefore
/// cannot drift from the scale.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  String? subtitle,
  double? maxHeightFactor,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
  bool showHandle = true,
  Color? backgroundColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    backgroundColor: backgroundColor,
    builder: (sheetContext) => AppBottomSheet(
      showHandle: showHandle,
      title: title,
      subtitle: subtitle,
      maxHeightFactor: maxHeightFactor,
      child: builder(sheetContext),
    ),
  );
}
