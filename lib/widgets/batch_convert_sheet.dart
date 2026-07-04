import 'package:flutter/material.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/utils/audio_conversion_utils.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';

/// Modern, card-based batch convert sheet shared by the queue and album
/// screens, matching the single-track convert sheet styling.
class BatchConvertSheet extends StatefulWidget {
  final List<String> formats;
  final String title;
  final String? subtitle;
  final String confirmLabel;
  final int? sourceBitDepth;
  final int? sourceSampleRate;
  final void Function(
    String format,
    String bitrate,
    LosslessConversionQuality losslessQuality,
    LosslessConversionProcessing losslessProcessing,
  )
  onConvert;

  const BatchConvertSheet({
    super.key,
    required this.formats,
    required this.title,
    required this.confirmLabel,
    required this.onConvert,
    this.subtitle,
    this.sourceBitDepth,
    this.sourceSampleRate,
  });

  @override
  State<BatchConvertSheet> createState() => _BatchConvertSheetState();
}

class _BatchConvertSheetState extends State<BatchConvertSheet> {
  static const _bitrates = ['128k', '192k', '256k', '320k'];

  late String _selectedFormat;
  late bool _isLosslessTarget;
  late String _selectedBitrate;
  int? _selectedMaxBitDepth;
  int? _selectedMaxSampleRate;
  String _selectedDither = 'none';
  String _selectedResampler = 'swr';

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
    final labels = context.l10n.losslessConversionLabels;
    final bitDepthOptions = availableLosslessBitDepthOptions(
      widget.sourceBitDepth,
    );
    final sampleRateOptions = availableLosslessSampleRateOptions(
      widget.sourceSampleRate,
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SafeArea(
          child: SingleChildScrollView(
            controller: scrollController,
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
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
                                } else {
                                  _selectedMaxBitDepth = null;
                                  _selectedMaxSampleRate = null;
                                  _selectedDither = 'none';
                                  _selectedResampler = 'swr';
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
                              onTap: () =>
                                  setState(() => _selectedBitrate = br),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                if (_isLosslessTarget && bitDepthOptions.isNotEmpty)
                  _card(
                    cs,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel(cs, context.l10n.audioAnalysisBitDepth),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _choice(
                              cs,
                              label: losslessBitDepthLabel(
                                null,
                                originalLabel: labels.original,
                              ),
                              selected: _selectedMaxBitDepth == null,
                              onTap: () => setState(() {
                                _selectedMaxBitDepth = null;
                                _selectedDither = 'none';
                              }),
                            ),
                            ...bitDepthOptions.map((depth) {
                              return _choice(
                                cs,
                                label: losslessBitDepthLabel(
                                  depth,
                                  originalLabel: labels.original,
                                ),
                                selected: depth == _selectedMaxBitDepth,
                                onTap: () => setState(
                                  () => _selectedMaxBitDepth = depth,
                                ),
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),

                if (_isLosslessTarget && sampleRateOptions.isNotEmpty)
                  _card(
                    cs,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel(cs, context.l10n.audioAnalysisSampleRate),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _choice(
                              cs,
                              label: losslessSampleRateLabel(
                                null,
                                originalLabel: labels.original,
                              ),
                              selected: _selectedMaxSampleRate == null,
                              onTap: () => setState(() {
                                _selectedMaxSampleRate = null;
                                _selectedResampler = 'swr';
                              }),
                            ),
                            ...sampleRateOptions.map((rate) {
                              return _choice(
                                cs,
                                label: losslessSampleRateLabel(
                                  rate,
                                  originalLabel: labels.original,
                                ),
                                selected: rate == _selectedMaxSampleRate,
                                onTap: () => setState(
                                  () => _selectedMaxSampleRate = rate,
                                ),
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),

                if (_isLosslessTarget && _selectedMaxBitDepth != null)
                  _card(
                    cs,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel(cs, context.l10n.trackConvertDithering),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: losslessDitherOptions.map((mode) {
                            return _choice(
                              cs,
                              label: context.l10n.losslessDitherOptionLabel(
                                mode,
                              ),
                              selected: mode == _selectedDither,
                              onTap: () =>
                                  setState(() => _selectedDither = mode),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                if (_isLosslessTarget && _selectedMaxSampleRate != null)
                  _card(
                    cs,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel(cs, context.l10n.trackConvertResampler),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: losslessResamplerOptions.map((mode) {
                            return _choice(
                              cs,
                              label: context.l10n.losslessResamplerOptionLabel(
                                mode,
                              ),
                              selected: mode == _selectedResampler,
                              onTap: () =>
                                  setState(() => _selectedResampler = mode),
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
                            _selectedMaxBitDepth == null &&
                                    _selectedMaxSampleRate == null
                                ? context.l10n.trackConvertLosslessHint
                                : context.l10n
                                      .trackConvertLosslessOutputWithCap(
                                        losslessQualityLabel(
                                          LosslessConversionQuality(
                                            maxBitDepth: _selectedMaxBitDepth,
                                            maxSampleRate:
                                                _selectedMaxSampleRate,
                                          ),
                                          originalLabel: labels.original,
                                          originalQualityLabel:
                                              labels.originalQuality,
                                        ),
                                      ),
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
                    onPressed: () => widget.onConvert(
                      _selectedFormat,
                      _selectedBitrate,
                      LosslessConversionQuality(
                        maxBitDepth: _selectedMaxBitDepth,
                        maxSampleRate: _selectedMaxSampleRate,
                      ),
                      LosslessConversionProcessing(
                        dither: _selectedDither,
                        resampler: _selectedResampler,
                      ),
                    ),
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
