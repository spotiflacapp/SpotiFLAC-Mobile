import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/utils/app_bar_layout.dart';
import 'package:spotiflac_android/screens/settings/download_fallback_extensions_page.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';

class DownloadSettingsPage extends ConsumerStatefulWidget {
  const DownloadSettingsPage({super.key});

  @override
  ConsumerState<DownloadSettingsPage> createState() =>
      _DownloadSettingsPageState();
}

class _DownloadSettingsPageState extends ConsumerState<DownloadSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final extensionState = ref.watch(extensionProvider);
    final hasDownloadExtensions = extensionState.extensions.any(
      (extension) => extension.enabled && extension.hasDownloadProvider,
    );
    final selectedDownloadService = resolveEffectiveDownloadService(
      settings.defaultService,
      extensionState,
    );
    final selectedDownloadExtension = extensionState.extensions
        .where(
          (extension) =>
              extension.enabled &&
              extension.hasDownloadProvider &&
              extension.id == selectedDownloadService,
        )
        .firstOrNull;
    final qualityOptions =
        selectedDownloadExtension?.qualityOptions ?? const <QualityOption>[];
    final canSelectQuality = qualityOptions.isNotEmpty;
    final usesTidalCompatibilityOptions = selectedDownloadService.isNotEmpty
        ? ref
              .read(extensionProvider.notifier)
              .downloadProviderReplacesLegacyProvider(
                selectedDownloadService,
                'tidal',
              )
        : false;
    final nativeWorkerAvailable = Platform.isAndroid && hasDownloadExtensions;
    final colorScheme = Theme.of(context).colorScheme;
    final topPadding = normalizedHeaderTopPadding(context);

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 120 + topPadding,
              collapsedHeight: kToolbarHeight,
              floating: false,
              pinned: true,
              backgroundColor: colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  final maxHeight = 120 + topPadding;
                  final minHeight = kToolbarHeight + topPadding;
                  final expandRatio =
                      ((constraints.maxHeight - minHeight) /
                              (maxHeight - minHeight))
                          .clamp(0.0, 1.0);
                  final leftPadding = 56 - (32 * expandRatio);
                  return FlexibleSpaceBar(
                    expandedTitleScale: 1.0,
                    titlePadding: EdgeInsets.only(
                      left: leftPadding,
                      bottom: 16,
                    ),
                    title: Text(
                      context.l10n.settingsDownload,
                      style: TextStyle(
                        fontSize: 20 + (8 * expandRatio),
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  );
                },
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(title: context.l10n.sectionService),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  _ServiceSelector(
                    currentService: settings.defaultService,
                    onChanged: (service) => ref
                        .read(settingsProvider.notifier)
                        .setDefaultService(service),
                  ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(
                title: context.l10n.sectionAudioQuality,
              ),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  SettingsSwitchItem(
                    icon: Icons.tune,
                    title: context.l10n.downloadAskBeforeDownload,
                    subtitle: !hasDownloadExtensions
                        ? context.l10n.extensionsNoDownloadProvider
                        : canSelectQuality
                        ? context.l10n.downloadAskQualitySubtitle
                        : context.l10n.downloadSelectServiceToEnable,
                    value: settings.askQualityBeforeDownload,
                    enabled: hasDownloadExtensions && canSelectQuality,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setAskQualityBeforeDownload(value),
                  ),
                  if (!settings.askQualityBeforeDownload &&
                      canSelectQuality) ...[
                    for (final quality in qualityOptions)
                      _QualityOption(
                        title: _localizedQualityLabel(context, quality),
                        subtitle: _localizedQualityDescription(
                          context,
                          quality,
                        ),
                        icon: _qualityIcon(quality.id),
                        isSelected: settings.audioQuality == quality.id,
                        onTap: () => ref
                            .read(settingsProvider.notifier)
                            .setAudioQuality(quality.id),
                        showDivider:
                            quality != qualityOptions.last ||
                            (usesTidalCompatibilityOptions &&
                                settings.audioQuality == 'HIGH'),
                      ),
                    if (usesTidalCompatibilityOptions &&
                        settings.audioQuality == 'HIGH')
                      SettingsItem(
                        icon: Icons.tune,
                        title: context.l10n.downloadLossyFormat,
                        subtitle: _getLossyCompatibilityFormatLabel(
                          context,
                          settings.tidalHighFormat,
                        ),
                        onTap: () => _showLossyCompatibilityFormatPicker(
                          context,
                          ref,
                          settings.tidalHighFormat,
                        ),
                        showDivider: false,
                      ),
                  ],
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(
                title: context.l10n.sectionPerformance,
              ),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  SettingsItem(
                    icon: Icons.wifi,
                    title: context.l10n.settingsDownloadNetwork,
                    subtitle: settings.downloadNetworkMode == 'wifi_only'
                        ? context.l10n.settingsDownloadNetworkWifiOnly
                        : context.l10n.settingsDownloadNetworkAny,
                    onTap: () => _showNetworkModePicker(
                      context,
                      ref,
                      settings.downloadNetworkMode,
                    ),
                  ),
                  if (Platform.isAndroid)
                    SettingsSwitchItem(
                      icon: Icons.downloading_outlined,
                      title: context.l10n.downloadNativeWorker,
                      titleTrailing: BetaBadge(label: context.l10n.badgeBeta),
                      subtitle: hasDownloadExtensions
                          ? context.l10n.downloadNativeWorkerSubtitle
                          : context.l10n.extensionsNoDownloadProvider,
                      value:
                          settings.nativeDownloadWorkerEnabled &&
                          nativeWorkerAvailable,
                      enabled: nativeWorkerAvailable,
                      onChanged: (value) => ref
                          .read(settingsProvider.notifier)
                          .setNativeDownloadWorkerEnabled(value),
                    ),
                  SettingsSwitchItem(
                    icon: Icons.security_outlined,
                    title: context.l10n.downloadNetworkCompatibilityMode,
                    subtitle: settings.networkCompatibilityMode
                        ? context.l10n.downloadNetworkCompatibilityModeEnabled
                        : context.l10n.downloadNetworkCompatibilityModeDisabled,
                    value: settings.networkCompatibilityMode,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setNetworkCompatibilityMode(value),
                  ),
                  SettingsSwitchItem(
                    icon: Icons.lan_outlined,
                    title: context.l10n.downloadAllowLocalNetwork,
                    subtitle: settings.allowLocalNetwork
                        ? context.l10n.downloadAllowLocalNetworkEnabled
                        : context.l10n.downloadAllowLocalNetworkDisabled,
                    value: settings.allowLocalNetwork,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setAllowLocalNetwork(value),
                    showDivider: false,
                  ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(
                title: context.l10n.sectionSearchSource,
              ),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  const _MetadataSourceSelector(),
                  const _DefaultSearchTabSelector(),
                  SettingsSwitchItem(
                    icon: Icons.sync,
                    title: context.l10n.optionsAutoFallback,
                    subtitle: context.l10n.optionsAutoFallbackSubtitle,
                    value: settings.autoFallback,
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).setAutoFallback(v),
                  ),
                  SettingsItem(
                    icon: Icons.extension_outlined,
                    title: context.l10n.downloadFallbackExtensions,
                    subtitle: context.l10n.downloadFallbackExtensionsSubtitle,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const DownloadFallbackExtensionsPage(),
                      ),
                    ),
                    showDivider: false,
                  ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(title: context.l10n.sectionDownload),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  SettingsItem(
                    icon: Icons.public,
                    title: context.l10n.downloadSongLinkRegion,
                    subtitle: _getSongLinkRegionLabel(settings.songLinkRegion),
                    onTap: () => _showSongLinkRegionPicker(
                      context,
                      ref,
                      settings.songLinkRegion,
                    ),
                  ),
                  SettingsSwitchItem(
                    icon: Icons.file_download_outlined,
                    title: context.l10n.settingsAutoExportFailed,
                    subtitle: context.l10n.settingsAutoExportFailedSubtitle,
                    value: settings.autoExportFailedDownloads,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setAutoExportFailedDownloads(value),
                    showDivider: false,
                  ),
                ],
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  String _getSongLinkRegionLabel(String code) {
    const names = <String, String>{
      'US': 'United States',
      'GB': 'United Kingdom',
      'FR': 'France',
      'DE': 'Germany',
      'JP': 'Japan',
      'KR': 'South Korea',
      'IN': 'India',
      'ID': 'Indonesia',
      'BR': 'Brazil',
      'MX': 'Mexico',
      'AU': 'Australia',
      'CA': 'Canada',
      'XK': 'Kosovo',
    };
    final normalized = code.trim().toUpperCase();
    final effective = normalized.isEmpty ? 'US' : normalized;
    final name = names[effective];
    return name == null ? effective : '$effective - $name';
  }

  IconData _qualityIcon(String qualityId) {
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
      case 'HIGH':
        return context.l10n.downloadLossy320;
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
      case 'HIGH':
        return _getLossyCompatibilityFormatLabel(
          context,
          ref.read(settingsProvider).tidalHighFormat,
        );
      default:
        return quality.description ?? '';
    }
  }

  String _getLossyCompatibilityFormatLabel(
    BuildContext context,
    String format,
  ) {
    switch (format) {
      case 'mp3_320':
        return context.l10n.downloadLossyMp3;
      case 'aac_320':
        return context.l10n.downloadLossyAac;
      case 'opus_256':
        return context.l10n.downloadLossyOpus256;
      case 'opus_128':
        return context.l10n.downloadLossyOpus128;
      default:
        return context.l10n.downloadLossyMp3;
    }
  }

  void _showLossyCompatibilityFormatPicker(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                context.l10n.downloadLossy320Format,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                context.l10n.downloadLossy320FormatDesc,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.audiotrack),
              title: Text(context.l10n.downloadLossyMp3),
              subtitle: Text(context.l10n.downloadLossyMp3Subtitle),
              trailing: current == 'mp3_320'
                  ? Icon(Icons.check, color: colorScheme.primary)
                  : null,
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setTidalHighFormat('mp3_320');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.album_outlined),
              title: Text(context.l10n.downloadLossyAac),
              subtitle: Text(context.l10n.downloadLossyAacSubtitle),
              trailing: current == 'aac_320'
                  ? Icon(Icons.check, color: colorScheme.primary)
                  : null,
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setTidalHighFormat('aac_320');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: Text(context.l10n.downloadLossyOpus256),
              subtitle: Text(context.l10n.downloadLossyOpus256Subtitle),
              trailing: current == 'opus_256'
                  ? Icon(Icons.check, color: colorScheme.primary)
                  : null,
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setTidalHighFormat('opus_256');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: Text(context.l10n.downloadLossyOpus128),
              subtitle: Text(context.l10n.downloadLossyOpus128Subtitle),
              trailing: current == 'opus_128'
                  ? Icon(Icons.check, color: colorScheme.primary)
                  : null,
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setTidalHighFormat('opus_128');
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showNetworkModePicker(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                context.l10n.settingsDownloadNetwork,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                context.l10n.settingsDownloadNetworkSubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.signal_cellular_alt),
              title: Text(context.l10n.settingsDownloadNetworkAny),
              subtitle: Text(context.l10n.downloadNetworkAnySubtitle),
              trailing: current == 'any'
                  ? Icon(Icons.check, color: colorScheme.primary)
                  : null,
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setDownloadNetworkMode('any');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.wifi),
              title: Text(context.l10n.settingsDownloadNetworkWifiOnly),
              subtitle: Text(context.l10n.downloadNetworkWifiOnlySubtitle),
              trailing: current == 'wifi_only'
                  ? Icon(Icons.check, color: colorScheme.primary)
                  : null,
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setDownloadNetworkMode('wifi_only');
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showSongLinkRegionPicker(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) {
    const regions = [
      'AD',
      'AE',
      'AG',
      'AL',
      'AM',
      'AO',
      'AR',
      'AT',
      'AU',
      'AZ',
      'BA',
      'BB',
      'BD',
      'BE',
      'BF',
      'BG',
      'BH',
      'BI',
      'BJ',
      'BN',
      'BO',
      'BR',
      'BS',
      'BT',
      'BW',
      'BZ',
      'CA',
      'CD',
      'CG',
      'CH',
      'CI',
      'CL',
      'CM',
      'CO',
      'CR',
      'CV',
      'CW',
      'CY',
      'CZ',
      'DE',
      'DJ',
      'DK',
      'DM',
      'DO',
      'DZ',
      'EC',
      'EE',
      'EG',
      'ES',
      'ET',
      'FI',
      'FJ',
      'FM',
      'FR',
      'GA',
      'GB',
      'GD',
      'GE',
      'GH',
      'GM',
      'GN',
      'GQ',
      'GR',
      'GT',
      'GW',
      'GY',
      'HK',
      'HN',
      'HR',
      'HT',
      'HU',
      'ID',
      'IE',
      'IL',
      'IN',
      'IQ',
      'IS',
      'IT',
      'JM',
      'JO',
      'JP',
      'KE',
      'KG',
      'KH',
      'KI',
      'KM',
      'KN',
      'KR',
      'KW',
      'KZ',
      'LA',
      'LB',
      'LC',
      'LI',
      'LK',
      'LR',
      'LS',
      'LT',
      'LU',
      'LV',
      'LY',
      'MA',
      'MC',
      'MD',
      'ME',
      'MG',
      'MH',
      'MK',
      'ML',
      'MN',
      'MO',
      'MR',
      'MT',
      'MU',
      'MV',
      'MW',
      'MX',
      'MY',
      'MZ',
      'NA',
      'NE',
      'NG',
      'NI',
      'NL',
      'NO',
      'NP',
      'NR',
      'NZ',
      'OM',
      'PA',
      'PE',
      'PG',
      'PH',
      'PK',
      'PL',
      'PS',
      'PT',
      'PW',
      'PY',
      'QA',
      'RO',
      'RS',
      'RW',
      'SA',
      'SB',
      'SC',
      'SE',
      'SG',
      'SI',
      'SK',
      'SL',
      'SM',
      'SN',
      'SR',
      'ST',
      'SV',
      'SZ',
      'TD',
      'TG',
      'TH',
      'TJ',
      'TL',
      'TN',
      'TO',
      'TR',
      'TT',
      'TV',
      'TW',
      'TZ',
      'UA',
      'UG',
      'US',
      'UY',
      'UZ',
      'VC',
      'VE',
      'VN',
      'VU',
      'WS',
      'XK',
      'ZA',
      'ZM',
      'ZW',
    ];
    const names = <String, String>{
      'US': 'United States',
      'GB': 'United Kingdom',
      'FR': 'France',
      'DE': 'Germany',
      'JP': 'Japan',
      'KR': 'South Korea',
      'IN': 'India',
      'ID': 'Indonesia',
      'BR': 'Brazil',
      'MX': 'Mexico',
      'AU': 'Australia',
      'CA': 'Canada',
      'XK': 'Kosovo',
    };
    final colorScheme = Theme.of(context).colorScheme;
    final normalizedCurrent = current.trim().toUpperCase();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Text(
                  context.l10n.downloadSongLinkRegion,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Text(
                  context.l10n.downloadSongLinkRegionDesc,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: regions.length,
                  itemBuilder: (context, index) {
                    final code = regions[index];
                    final isSelected = code == normalizedCurrent;
                    return ListTile(
                      title: Text(code),
                      subtitle: names[code] != null ? Text(names[code]!) : null,
                      trailing: isSelected
                          ? Icon(Icons.check, color: colorScheme.primary)
                          : null,
                      onTap: () {
                        ref
                            .read(settingsProvider.notifier)
                            .setSongLinkRegion(code);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualityOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final bool showDivider;

  const _QualityOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SettingsItem(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: isSelected
          ? Icon(Icons.check, color: colorScheme.primary)
          : null,
      onTap: onTap,
      showDivider: showDivider,
    );
  }
}

class _ServiceSelector extends ConsumerWidget {
  final String currentService;
  final ValueChanged<String> onChanged;
  const _ServiceSelector({
    required this.currentService,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final extState = ref.watch(extensionProvider);

    final extensionProviders = extState.extensions
        .where((e) => e.enabled && e.hasDownloadProvider)
        .toList();

    final effectiveService =
        extensionProviders.any((extension) => extension.id == currentService)
        ? currentService
        : '';

    return Padding(
      padding: const EdgeInsets.all(12),
      child: extensionProviders.isEmpty
          ? Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.extensionsNoDownloadProvider,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                final chipWidth = (constraints.maxWidth - spacing) / 2;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final extension in extensionProviders)
                      SizedBox(
                        width: chipWidth,
                        child: _ServiceChip(
                          icon: Icons.extension,
                          label: extension.displayName,
                          isSelected: effectiveService == extension.id,
                          onTap: () => onChanged(extension.id),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _ServiceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _ServiceChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedColor = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.05),
            colorScheme.surface,
          )
        : colorScheme.surfaceContainerHigh;
    return Material(
      color: isSelected ? colorScheme.primaryContainer : unselectedColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataSourceSelector extends ConsumerWidget {
  const _MetadataSourceSelector();

  Extension? _defaultSearchExtension(List<Extension> extensions) {
    return extensions
            .where(
              (ext) =>
                  ext.enabled &&
                  ext.hasCustomSearch &&
                  ext.searchBehavior?.primary == true,
            )
            .firstOrNull ??
        extensions
            .where((ext) => ext.enabled && ext.hasCustomSearch)
            .firstOrNull;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final extState = ref.watch(extensionProvider);

    final rawSearchProvider = settings.searchProvider?.trim() ?? '';
    final primarySearchExtension = _defaultSearchExtension(extState.extensions);
    final defaultProviderTarget =
        primarySearchExtension?.displayName ??
        context.l10n.extensionsNoCustomSearch;
    final defaultProviderLabel =
        '${context.l10n.extensionsHomeFeedAuto} ($defaultProviderTarget)';
    final searchProvider =
        extState.extensions.any(
          (e) => e.enabled && e.hasCustomSearch && e.id == rawSearchProvider,
        )
        ? rawSearchProvider
        : '';

    Extension? activeExtension;
    if (searchProvider.isNotEmpty) {
      activeExtension = extState.extensions
          .where((e) => e.id == searchProvider && e.enabled)
          .firstOrNull;
    }
    final hasNonDefaultProvider = activeExtension != null;

    String subtitle;
    if (activeExtension != null) {
      subtitle = context.l10n.optionsUsingExtension(
        activeExtension.displayName,
      );
    } else {
      subtitle = context.l10n.optionsPrimaryProviderSubtitle;
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.optionsPrimaryProvider,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: hasNonDefaultProvider
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _SettingsChoiceGrid(
            children: [
              _SettingsChoiceChip(
                icon: Icons.auto_awesome,
                label: defaultProviderLabel,
                isSelected: searchProvider.isEmpty,
                onTap: () =>
                    ref.read(settingsProvider.notifier).setSearchProvider(''),
              ),
              for (final ext in extState.extensions.where(
                (e) => e.enabled && e.hasCustomSearch,
              ))
                _SettingsChoiceChip(
                  icon: Icons.extension,
                  label: ext.displayName,
                  isSelected: searchProvider == ext.id,
                  onTap: () => ref
                      .read(settingsProvider.notifier)
                      .setSearchProvider(ext.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsChoiceGrid extends StatelessWidget {
  final List<Widget> children;
  const _SettingsChoiceGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final chipWidth = (constraints.maxWidth - spacing) / 2;
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

class _SettingsChoiceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _SettingsChoiceChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedColor = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.05),
            colorScheme.surface,
          )
        : colorScheme.surfaceContainerHigh;
    return Material(
      color: isSelected ? colorScheme.primaryContainer : unselectedColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DefaultSearchTabSelector extends ConsumerWidget {
  const _DefaultSearchTabSelector();

  String _labelForTab(BuildContext context, String tab) {
    return switch (tab) {
      'track' => context.l10n.searchTracks,
      'artist' => context.l10n.searchArtists,
      'album' => context.l10n.searchAlbums,
      'playlist' => context.l10n.searchPlaylists,
      _ => context.l10n.historyFilterAll,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final current = settings.defaultSearchTab;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.optionsDefaultSearchTab,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.optionsDefaultSearchTabSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _SettingsChoiceGrid(
            children: [
              for (final tab in const [
                'all',
                'track',
                'artist',
                'album',
                'playlist',
              ])
                _SettingsChoiceChip(
                  icon: switch (tab) {
                    'track' => Icons.music_note,
                    'artist' => Icons.person,
                    'album' => Icons.album,
                    'playlist' => Icons.queue_music,
                    _ => Icons.grid_view,
                  },
                  label: _labelForTab(context, tab),
                  isSelected: current == tab,
                  onTap: () => ref
                      .read(settingsProvider.notifier)
                      .setDefaultSearchTab(tab),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
