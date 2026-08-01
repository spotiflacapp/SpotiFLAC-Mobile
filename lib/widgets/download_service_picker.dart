import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/l10n/l10n.dart';

class DownloadServicePicker extends ConsumerStatefulWidget {
  final String? trackName;
  final String? artistName;
  final String? coverUrl;
  final void Function(String quality, String service) onSelect;
  final String? recommendedService;
  final ScrollController? scrollController;

  const DownloadServicePicker({
    super.key,
    this.trackName,
    this.artistName,
    this.coverUrl,
    required this.onSelect,
    this.recommendedService,
    this.scrollController,
  });

  @override
  ConsumerState<DownloadServicePicker> createState() =>
      _DownloadServicePickerState();

  static void show(
    BuildContext context, {
    String? trackName,
    String? artistName,
    String? coverUrl,
    String? recommendedService,
    required void Function(String quality, String service) onSelect,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      isScrollControlled: true,
      enableDrag: false,
      builder: (context) => AppDraggableSheet(
        builder: (context, scrollController) => DownloadServicePicker(
          trackName: trackName,
          artistName: artistName,
          coverUrl: coverUrl,
          onSelect: onSelect,
          recommendedService: recommendedService,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class _DownloadServicePickerState extends ConsumerState<DownloadServicePicker> {
  late String _selectedService;

  List<Extension> _downloadExtensions() {
    final extensionState = ref.read(extensionProvider);
    return extensionState.extensions
        .where((ext) => ext.enabled && ext.hasDownloadProvider)
        .toList(growable: false);
  }

  bool _serviceExists(String serviceId, List<Extension> downloadExtensions) {
    if (serviceId.isEmpty) return false;
    return downloadExtensions.any((ext) => ext.id == serviceId);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(extensionProvider.notifier).refreshEnabledExtensionHealth();
    });
    final downloadExtensions = _downloadExtensions();
    final recommended = widget.recommendedService;
    if (recommended != null &&
        _serviceExists(recommended, downloadExtensions)) {
      _selectedService = recommended;
    } else {
      _selectedService = ref.read(settingsProvider).defaultService;
    }
    if (!_serviceExists(_selectedService, downloadExtensions)) {
      _selectedService = downloadExtensions.isNotEmpty
          ? downloadExtensions.first.id
          : '';
    }
  }

  List<QualityOption> _getQualityOptions(List<Extension> downloadExtensions) {
    final ext = downloadExtensions
        .where((e) => e.id == _selectedService)
        .firstOrNull;
    if (ext != null && ext.qualityOptions.isNotEmpty) {
      return ext.qualityOptions;
    }

    return const [];
  }

  void _selectService(Extension extension) {
    setState(() => _selectedService = extension.id);
    if (extension.hasServiceHealth) {
      unawaited(
        ref.read(extensionProvider.notifier).checkExtensionHealth(extension.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final extensionState = ref.watch(extensionProvider);
    final downloadExtensions = _downloadExtensions();
    final hasProviders = downloadExtensions.isNotEmpty;
    final qualityOptions = _getQualityOptions(downloadExtensions);

    return SafeArea(
      child: SingleChildScrollView(
        controller: widget.scrollController,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.trackName != null) ...[
              _TrackInfoHeader(
                trackName: widget.trackName!,
                artistName: widget.artistName,
                coverUrl: widget.coverUrl,
              ),
              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ] else ...[
              const AppSheetHandle(),
            ],

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                context.l10n.downloadFrom,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: hasProviders
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final ext in downloadExtensions)
                          _ServiceChip(
                            label: widget.recommendedService == ext.id
                                ? '${ext.displayName} (Recommended)'
                                : ext.displayName,
                            healthStatus: ext.hasServiceHealth
                                ? extensionState.healthStatuses[ext.id]?.status
                                : null,
                            isSelected: _selectedService == ext.id,
                            onTap: () => _selectService(ext),
                            iconPath: ext.iconPath,
                          ),
                      ],
                    )
                  : _NoDownloadProviderHint(
                      primaryText: context.l10n.extensionsNoDownloadProvider,
                      secondaryText: context.l10n.storeAddRepoDescription,
                    ),
            ),
            if (hasProviders) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Text(
                  context.l10n.downloadSelectQuality,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              for (final quality in qualityOptions)
                _QualityOption(
                  title: _localizedQualityLabel(context, quality),
                  subtitle: _localizedQualityDescription(context, quality),
                  icon: _getQualityIcon(quality.id),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onSelect(quality.id, _selectedService);
                  },
                ),
            ],

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  IconData _getQualityIcon(String qualityId) {
    final normalized = qualityId.toUpperCase();
    if (normalized.startsWith('MP3_') || normalized == 'MP3') {
      return Icons.audiotrack;
    }
    if (normalized.startsWith('OPUS_') || normalized == 'OPUS') {
      return Icons.graphic_eq;
    }

    switch (normalized) {
      case 'HI_RES_LOSSLESS':
        return Icons.four_k;
      case 'HI_RES':
        return Icons.high_quality;
      case 'LOSSLESS':
        return Icons.music_note;
      default:
        return Icons.music_note;
    }
  }

  String _localizedQualityLabel(BuildContext context, QualityOption quality) {
    switch (quality.id.toUpperCase()) {
      case 'LOSSLESS':
        return context.l10n.qualityFlacLossless;
      case 'HI_RES':
        return context.l10n.qualityHiResFlac;
      case 'HI_RES_LOSSLESS':
        return context.l10n.qualityHiResFlacMax;
      default:
        return quality.label;
    }
  }

  String _localizedQualityDescription(
    BuildContext context,
    QualityOption quality,
  ) {
    switch (quality.id.toUpperCase()) {
      case 'LOSSLESS':
        return context.l10n.qualityFlacLosslessSubtitle;
      case 'HI_RES':
        return context.l10n.qualityHiResFlacSubtitle;
      case 'HI_RES_LOSSLESS':
        return context.l10n.qualityHiResFlacMaxSubtitle;
      default:
        return quality.description ?? '';
    }
  }
}

class _QualityOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _QualityOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: colorScheme.onPrimaryContainer, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            )
          : null,
      onTap: onTap,
    );
  }
}

class _ServiceChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final String? iconPath;
  final String? healthStatus;

  const _ServiceChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.iconPath,
    this.healthStatus,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? null
              : Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (healthStatus != null) ...[
              _ServiceHealthDot(status: healthStatus!),
              const SizedBox(width: 8),
            ],
            if (iconPath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  File(iconPath!),
                  width: 18,
                  height: 18,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.extension,
                    size: 18,
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceHealthDot extends StatelessWidget {
  final String status;

  const _ServiceHealthDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _serviceHealthColor(status);
    return Tooltip(
      message: _serviceHealthTooltip(context, status),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

Color _serviceHealthColor(String status) {
  switch (status) {
    case 'online':
      return const Color(0xFF24D47A);
    case 'degraded':
    case 'unknown':
      return const Color(0xFFFFC247);
    case 'offline':
      return const Color(0xFFFF5A66);
    default:
      return const Color(0xFFFFC247);
  }
}

String _serviceHealthTooltip(BuildContext context, String status) {
  switch (status) {
    case 'online':
      return context.l10n.extensionHealthServiceOnline;
    case 'degraded':
      return context.l10n.extensionHealthServiceDegraded;
    case 'offline':
      return context.l10n.extensionHealthServiceOffline;
    default:
      return context.l10n.extensionHealthServiceUnknown;
  }
}

class _NoDownloadProviderHint extends StatelessWidget {
  final String primaryText;
  final String secondaryText;

  const _NoDownloadProviderHint({
    required this.primaryText,
    required this.secondaryText,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.extension_outlined,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primaryText,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  secondaryText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackInfoHeader extends StatefulWidget {
  final String trackName;
  final String? artistName;
  final String? coverUrl;

  const _TrackInfoHeader({
    required this.trackName,
    this.artistName,
    this.coverUrl,
  });

  @override
  State<_TrackInfoHeader> createState() => _TrackInfoHeaderState();
}

class _TrackInfoHeaderState extends State<_TrackInfoHeader> {
  bool _expanded = false;
  bool _isOverflowing = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isOverflowing
            ? () => setState(() => _expanded = !_expanded)
            : null,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        child: Column(
          children: [
            const AppSheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: widget.coverUrl != null
                        ? Image.network(
                            widget.coverUrl!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  width: 56,
                                  height: 56,
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.music_note,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                          )
                        : Container(
                            width: 56,
                            height: 56,
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.music_note,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final titleStyle = Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600);
                        final titleSpan = TextSpan(
                          text: widget.trackName,
                          style: titleStyle,
                        );
                        final titlePainter = TextPainter(
                          text: titleSpan,
                          maxLines: 1,
                          textDirection: TextDirection.ltr,
                        )..layout(maxWidth: constraints.maxWidth);
                        final titleOverflows = titlePainter.didExceedMaxLines;

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _isOverflowing != titleOverflows) {
                            setState(() => _isOverflowing = titleOverflows);
                          }
                        });

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.trackName,
                              style: titleStyle,
                              maxLines: _expanded ? 10 : 1,
                              overflow: _expanded
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                            ),
                            if (widget.artistName != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.artistName!,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                maxLines: _expanded ? 3 : 1,
                                overflow: _expanded
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  if (_isOverflowing || _expanded)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
