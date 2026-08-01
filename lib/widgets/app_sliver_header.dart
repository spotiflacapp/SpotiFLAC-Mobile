import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/utils/app_bar_layout.dart';

/// The collapsing header used by every top-level tab and every settings-style
/// sub-page.
///
/// This replaces five hand-rolled copies of the same `SliverAppBar` +
/// `LayoutBuilder` + `FlexibleSpaceBar` block. Those copies had drifted into two
/// type ramps (tab roots expanded the title to 34pt, sub-pages to 28pt); both
/// now expand to [AppTokens.headerExpandedTitleSize], which matches the
/// Material 3 large top app bar headline.
class AppSliverHeader extends StatelessWidget {
  /// Root of a navigation tab: no back button, and the title stays aligned with
  /// the content margin at every collapse ratio.
  const AppSliverHeader.tabRoot({super.key, required this.title, this.actions})
    : leading = null,
      _showLeading = false;

  /// A pushed page: shows [leading] (a back button by default) and slides the
  /// title clear of it as the header collapses.
  const AppSliverHeader.page({
    super.key,
    required this.title,
    this.actions,
    this.leading,
  }) : _showLeading = true;

  final String title;
  final List<Widget>? actions;

  /// Overrides the default back button. Only used by the page variant.
  final Widget? leading;

  final bool _showLeading;

  /// Left inset of the collapsed title when a leading button is present: enough
  /// to clear a 48dp icon button plus the 8dp toolbar margin.
  static const double _leadingClearance = 56;

  /// Content margin the expanded title aligns to.
  static const double _contentMargin = 24;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;
    final topPadding = normalizedHeaderTopPadding(context);
    final maxHeight = tokens.headerExpandedHeight + topPadding;
    final minHeight = kToolbarHeight + topPadding;

    return SliverAppBar(
      expandedHeight: maxHeight,
      collapsedHeight: kToolbarHeight,
      floating: false,
      pinned: true,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      leading: _showLeading
          ? leading ??
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                )
          : null,
      actions: actions,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final expandRatio =
              ((constraints.maxHeight - minHeight) / (maxHeight - minHeight))
                  .clamp(0.0, 1.0);
          final leftPadding = _showLeading
              ? _leadingClearance -
                    ((_leadingClearance - _contentMargin) * expandRatio)
              : _contentMargin;
          final fontSize =
              tokens.headerCollapsedTitleSize +
              (tokens.headerExpandedTitleSize -
                      tokens.headerCollapsedTitleSize) *
                  expandRatio;

          return FlexibleSpaceBar(
            expandedTitleScale: 1.0,
            titlePadding: EdgeInsets.only(
              left: leftPadding,
              right: tokens.gapLg,
              bottom: tokens.gapLg,
            ),
            title: Text(
              title,
              // The title grows as the header expands; without a cap a long
              // localized title overflowed instead of ellipsizing.
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }
}
