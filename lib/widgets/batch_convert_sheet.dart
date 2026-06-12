import 'package:flutter/material.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/utils/audio_conversion_utils.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';

/// Modern, card-based batch convert sheet shared by the queue and album
/// screens. It mirrors the single-track convert sheet styling so format and
/// bitrate selection look consistent across the app.
class BatchConvertSheet extends StatefulWidget {
  /// Available target formats.
  final List<String> formats;

  /// Sheet title.
  final String title;

  /// Optional subtitle shown under the title (e.g. number of tracks).
  final String? subtitle;

  /// Label for the primary action button.
  final String confirmLabel;

  /// Called with the selected format and bitrate when the user confirms.
  final void Function(String format, String bitrate) onConvert;

  const BatchConvertSheet({
    super.key,
    required this.formats,
    required this.title,
    required this.confirmLabel,
    required this.onConvert,
    this.subtitle,
  });

  @override
  State<BatchConvertSheet> createState() => _BatchConvertSheetState();
}

class _BatchConvertSheetState extends State<BatchConvertSheet> {
  static const _bitrates = ['128k', '192k', '256k', '320k'];

  late String _selectedFormat;
  late bool _isLosslessTarget;
  late String _selectedBitrate;

  String _defaultBitrateForFormat(String format) {
    if (format == 'Opus') return '128k';
    if (format == 'AAC') return '256k';
    return '320k';
  }

  @override
  void initState() {
    super.initState();
    _selectedFormat = widget.formats.first;
    _isLosslessTarget = isLosslessConversionTarget(_selectedFormat);
    _selectedBitrate = _isLosslessTarget
        ? '320k'
        : _defaultBitrateForFormat(_selectedFormat);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.subtitle!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 20),

            _card(
              cs,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel(cs, context.l10n.trackConvertTargetFormat),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.formats.map((format) {
                      return _choice(
                        cs,
                        label: format,
                        selected: format == _selectedFormat,
                        onTap: () {
                          setState(() {
                            _selectedFormat = format;
                            _isLosslessTarget = isLosslessConversionTarget(
                              format,
                            );
                            if (!_isLosslessTarget) {
                              _selectedBitrate = _defaultBitrateForFormat(
                                format,
                              );
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            if (!_isLosslessTarget)
              _card(
                cs,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(cs, context.l10n.trackConvertBitrate),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _bitrates.map((br) {
                        return _choice(
                          cs,
                          label: br,
                          selected: br == _selectedBitrate,
                          onTap: () => setState(() => _selectedBitrate = br),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

            if (_isLosslessTarget)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.verified, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.trackConvertLosslessHint,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: cs.primary),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    widget.onConvert(_selectedFormat, _selectedBitrate),
                icon: const Icon(Icons.swap_horiz),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                label: Text(widget.confirmLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(ColorScheme cs, {required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: settingsGroupColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }

  Widget _sectionLabel(ColorScheme cs, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  Widget _choice(
    ColorScheme cs, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? cs.primaryContainer : cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : cs.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? cs.onPrimaryContainer : cs.onSurface,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
