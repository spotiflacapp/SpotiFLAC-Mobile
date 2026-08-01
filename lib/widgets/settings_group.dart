import 'dart:async';

import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';

/// Background fill for grouped cards, matching the Settings group look. Blends a
/// translucent overlay over the surface so it stays visible on AMOLED (pure
/// black) dark themes as well as normal light/dark themes.
Color settingsGroupColor(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark
      ? Color.alphaBlend(
          Colors.white.withValues(alpha: 0.08),
          colorScheme.surface,
        )
      : Color.alphaBlend(
          Colors.black.withValues(alpha: 0.04),
          colorScheme.surface,
        );
}

/// Carries a Settings search result into its destination page.
///
/// Descendant [SettingsSearchTarget] widgets compete to claim the matching
/// label. The first match scrolls into view and briefly highlights itself.
class SettingsSearchHighlightScope extends StatefulWidget {
  const SettingsSearchHighlightScope({
    super.key,
    required this.targetLabel,
    required this.child,
  });

  final String targetLabel;
  final Widget child;

  @override
  State<SettingsSearchHighlightScope> createState() =>
      _SettingsSearchHighlightScopeState();
}

class _SettingsSearchHighlightScopeState
    extends State<SettingsSearchHighlightScope> {
  late _SettingsSearchHighlightController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _SettingsSearchHighlightController(widget.targetLabel);
  }

  @override
  void didUpdateWidget(SettingsSearchHighlightScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetLabel != widget.targetLabel) {
      _controller = _SettingsSearchHighlightController(widget.targetLabel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSearchHighlightInherited(
      controller: _controller,
      child: widget.child,
    );
  }
}

class _SettingsSearchHighlightController {
  _SettingsSearchHighlightController(this.targetLabel);

  final String targetLabel;
  bool _claimed = false;

  bool matches(String label) => label == targetLabel;

  bool claim(String label) {
    if (_claimed || !matches(label)) return false;
    _claimed = true;
    return true;
  }
}

class _SettingsSearchHighlightInherited extends InheritedWidget {
  const _SettingsSearchHighlightInherited({
    required this.controller,
    required super.child,
  });

  final _SettingsSearchHighlightController controller;

  static _SettingsSearchHighlightInherited? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<
          _SettingsSearchHighlightInherited
        >();
  }

  @override
  bool updateShouldNotify(_SettingsSearchHighlightInherited oldWidget) {
    return controller != oldWidget.controller;
  }
}

/// Marks one settings control as a possible deep-link target from search.
class SettingsSearchTarget extends StatefulWidget {
  const SettingsSearchTarget({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  State<SettingsSearchTarget> createState() => _SettingsSearchTargetState();
}

class _SettingsSearchTargetState extends State<SettingsSearchTarget> {
  Timer? _highlightTimer;
  bool _handled = false;
  bool _highlighted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handled) return;

    final scope = _SettingsSearchHighlightInherited.maybeOf(context);
    if (scope?.controller.claim(widget.label) != true) return;
    _handled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  Future<void> _reveal() async {
    if (!mounted) return;
    setState(() => _highlighted = true);

    await Scrollable.ensureVisible(
      context,
      alignment: 0.32,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;

    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _highlighted = false);
    });
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Normal settings rendering stays allocation-light: only the one claimed
    // search target creates an animated decoration and semantics node.
    if (!_handled) return widget.child;

    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: _highlighted,
      child: AnimatedContainer(
        key: ValueKey('settings-highlight:${widget.label}'),
        duration: context.tokens.motionMedium,
        curve: Curves.easeOutCubic,
        color: _highlighted
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  const SettingsGroup({super.key, required this.children, this.margin});

  @override
  Widget build(BuildContext context) {
    final cardColor = settingsGroupColor(context);
    final colorScheme = Theme.of(context).colorScheme;

    final decoration = BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(context.tokens.radiusCard),
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
    );
    final child = Material(
      color: Colors.transparent,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );

    // Explicit caller margin wins as-is. Otherwise center on wide surfaces
    // using the incoming constraint (not screen width) so groups nested in an
    // already clamped box, e.g. a bottom sheet, are not over-inset.
    if (margin != null) {
      return Container(
        margin: margin,
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        margin: EdgeInsets.symmetric(
          horizontal:
              16 +
              (constraints.hasBoundedWidth
                  ? wideInsetForWidth(constraints.maxWidth)
                  : 0),
          vertical: 4,
        ),
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

class SettingsItem extends StatelessWidget {
  final IconData? icon;
  final String title;
  final Widget? titleTrailing;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  const SettingsItem({
    super.key,
    this.icon,
    required this.title,
    this.titleTrailing,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          splashColor: colorScheme.primary.withValues(alpha: 0.12),
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: colorScheme.onSurfaceVariant, size: 24),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                          if (titleTrailing != null) ...[
                            const SizedBox(width: 8),
                            titleTrailing!,
                          ],
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ] else if (onTap != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            indent: icon != null ? 56 : 20,
            endIndent: 20,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
      ],
    );
    return SettingsSearchTarget(label: title, child: content);
  }
}

class SettingsSwitchItem extends StatelessWidget {
  final IconData? icon;
  final String title;
  final Widget? titleTrailing;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool showDivider;
  final bool enabled;

  const SettingsSwitchItem({
    super.key,
    this.icon,
    required this.title,
    this.titleTrailing,
    this.subtitle,
    required this.value,
    this.onChanged,
    this.showDivider = true,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDisabled = !enabled || onChanged == null;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: isDisabled ? 0.5 : 1.0,
          child: InkWell(
            onTap: isDisabled ? null : () => onChanged!(!value),
            splashColor: colorScheme.primary.withValues(alpha: 0.12),
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      color: isDisabled
                          ? colorScheme.outline
                          : colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: isDisabled
                                          ? colorScheme.outline
                                          : null,
                                    ),
                              ),
                            ),
                            if (titleTrailing != null) ...[
                              const SizedBox(width: 8),
                              titleTrailing!,
                            ],
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: isDisabled
                                      ? colorScheme.outline
                                      : colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: value,
                    onChanged: isDisabled ? null : onChanged,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            indent: icon != null ? 56 : 20,
            endIndent: 20,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
      ],
    );
    return SettingsSearchTarget(label: title, child: content);
  }
}

class SettingsSectionHeader extends StatelessWidget {
  final String title;

  const SettingsSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return SettingsSearchTarget(label: title, child: content);
  }
}

/// How a [SettingsChoiceChip] stacks its icon and label.
enum SettingsChipLayout {
  /// Icon beside the label. Fits wide chips in a grid.
  row,

  /// Icon above the label. Fits equal-width chips in a row.
  column,
}

/// Single-select chip used across the settings pages.
///
/// Five private copies of this existed (theme mode, view mode, update channel,
/// download service, generic choice), each re-deriving the same unselected
/// fill and re-declaring radius 12. They now share one implementation, so the
/// selected/unselected treatment is identical everywhere.
class SettingsChoiceChip extends StatelessWidget {
  const SettingsChoiceChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
    this.layout = SettingsChipLayout.row,
    this.expand = false,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;
  final SettingsChipLayout layout;

  /// Wraps the chip in [Expanded] so a row of chips divides the width evenly.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(tokens.radiusCover);

    final unselectedColor = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.05),
            colorScheme.surface,
          )
        : colorScheme.surfaceContainerHigh;
    final foreground = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    final labelText = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        color: foreground,
      ),
    );

    final Widget content;
    if (icon == null) {
      content = Center(child: labelText);
    } else if (layout == SettingsChipLayout.column) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground),
          SizedBox(height: tokens.gapXs + 2),
          labelText,
        ],
      );
    } else {
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: foreground),
          SizedBox(width: tokens.gapSm),
          Flexible(child: labelText),
        ],
      );
    }

    final chip = Material(
      color: isSelected ? colorScheme.primaryContainer : unselectedColor,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: ConstrainedBox(
          // Keeps every chip a comfortable tap target regardless of layout.
          constraints: BoxConstraints(minHeight: tokens.minTouchTarget),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: tokens.gapMd,
              horizontal: tokens.gapMd,
            ),
            child: content,
          ),
        ),
      ),
    );

    return expand ? Expanded(child: chip) : chip;
  }
}

/// Lays out [SettingsChoiceChip]s in an even grid that reflows by width.
class SettingsChoiceGrid extends StatelessWidget {
  const SettingsChoiceGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final spacing = context.tokens.gapSm;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 320).floor().clamp(2, 4);
        final chipWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: chipWidth, child: child),
          ],
        );
      },
    );
  }
}

/// Tone of a [SettingsInfoCard].
enum SettingsInfoTone { neutral, warning, error }

/// Inline explanatory or warning callout inside a settings page.
///
/// The `Container` + icon + text combination was inlined at a dozen call sites
/// with three different radii and four different container colours.
class SettingsInfoCard extends StatelessWidget {
  const SettingsInfoCard({
    super.key,
    required this.message,
    this.icon,
    this.title,
    this.tone = SettingsInfoTone.neutral,
    this.action,
    this.margin,
  });

  final String message;
  final IconData? icon;
  final String? title;
  final SettingsInfoTone tone;

  /// Optional trailing action, e.g. a retry or "grant permission" button.
  final Widget? action;

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (background, foreground) = switch (tone) {
      SettingsInfoTone.neutral => (
        colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        colorScheme.onSurfaceVariant,
      ),
      SettingsInfoTone.warning => (
        colorScheme.tertiaryContainer.withValues(alpha: 0.5),
        colorScheme.onTertiaryContainer,
      ),
      SettingsInfoTone.error => (
        colorScheme.errorContainer.withValues(alpha: 0.6),
        colorScheme.onErrorContainer,
      ),
    };

    return Container(
      margin:
          margin ??
          EdgeInsets.symmetric(
            horizontal: tokens.gapLg,
            vertical: tokens.gapXs,
          ),
      padding: EdgeInsets.all(tokens.gapLg),
      decoration: BoxDecoration(
        color: background,
        borderRadius: tokens.borderRadiusCard,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: foreground),
            SizedBox(width: tokens.gapMd),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: tokens.gapXs),
                ],
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                ),
                if (action != null) ...[
                  SizedBox(height: tokens.gapSm),
                  Align(alignment: Alignment.centerLeft, child: action!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
