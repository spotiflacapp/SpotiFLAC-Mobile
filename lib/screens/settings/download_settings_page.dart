import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/screens/settings/download_fallback_extensions_page.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';

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

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            AppSliverHeader.page(title: context.l10n.settingsDownload),

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
                  SettingsItem(
                    icon: Icons.dynamic_feed_outlined,
                    title: context.l10n.settingsConcurrentDownloads,
                    subtitle: settings.concurrentDownloads <= 1
                        ? context.l10n.concurrentDownloadsOne
                        : context.l10n.concurrentDownloadsCount(
                            settings.concurrentDownloads,
                          ),
                    onTap: () => _showConcurrentDownloadsPicker(
                      context,
                      ref,
                      settings.concurrentDownloads,
                    ),
                  ),
                  if (Platform.isAndroid)
                    SettingsSwitchItem(
                      icon: Icons.downloading_outlined,
                      title: context.l10n.downloadNativeWorker,
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
                    subtitle: _getSongLinkRegionLabel(
                      context,
                      settings.songLinkRegion,
                    ),
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

  String _regionCountryName(BuildContext context, String code) {
    final l10n = context.l10n;
    switch (code) {
      case 'US':
        return l10n.regionCountryUS;
      case 'GB':
        return l10n.regionCountryGB;
      case 'FR':
        return l10n.regionCountryFR;
      case 'DE':
        return l10n.regionCountryDE;
      case 'JP':
        return l10n.regionCountryJP;
      case 'KR':
        return l10n.regionCountryKR;
      case 'IN':
        return l10n.regionCountryIN;
      case 'ID':
        return l10n.regionCountryID;
      case 'BR':
        return l10n.regionCountryBR;
      case 'MX':
        return l10n.regionCountryMX;
      case 'AU':
        return l10n.regionCountryAU;
      case 'CA':
        return l10n.regionCountryCA;
      case 'XK':
        return l10n.regionCountryXK;
      default:
        return code;
    }
  }

  String _getSongLinkRegionLabel(BuildContext context, String code) {
    final normalized = code.trim().toUpperCase();
    final effective = normalized.isEmpty ? 'US' : normalized;
    final name = _regionCountryName(context, effective);
    return name == effective ? effective : '$effective - $name';
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

  void _showConcurrentDownloadsPicker(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                context.l10n.settingsConcurrentDownloads,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                context.l10n.settingsConcurrentDownloadsSubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final count in const [1, 2, 3])
              ListTile(
                leading: Icon(
                  count == 1
                      ? Icons.looks_one_outlined
                      : count == 2
                      ? Icons.looks_two_outlined
                      : Icons.looks_3_outlined,
                ),
                title: Text(
                  count == 1
                      ? context.l10n.concurrentDownloadsOne
                      : context.l10n.concurrentDownloadsCount(count),
                ),
                trailing: current == count
                    ? Icon(Icons.check, color: colorScheme.primary)
                    : null,
                onTap: () {
                  ref
                      .read(settingsProvider.notifier)
                      .setConcurrentDownloads(count);
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
    final colorScheme = Theme.of(context).colorScheme;
    final normalizedCurrent = current.trim().toUpperCase();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      isScrollControlled: true,
      builder: (context) => _RegionPickerSheet(
        regions: regions,
        selected: normalizedCurrent,
        countryNameOf: (context, code) => _regionCountryName(context, code),
        onSelected: (code) {
          ref.read(settingsProvider.notifier).setSongLinkRegion(code);
          Navigator.pop(context);
        },
      ),
    );
  }
}

/// Searchable region list.
///
/// The picker previously rendered ~190 ISO codes as a flat list with no filter,
/// so finding a country meant scrolling blind — only a handful of codes have a
/// localized name to recognize them by.
class _RegionPickerSheet extends StatefulWidget {
  const _RegionPickerSheet({
    required this.regions,
    required this.selected,
    required this.countryNameOf,
    required this.onSelected,
  });

  final List<String> regions;
  final String selected;
  final String Function(BuildContext context, String code) countryNameOf;
  final ValueChanged<String> onSelected;

  @override
  State<_RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<_RegionPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final query = _query.trim().toLowerCase();
    final matches = query.isEmpty
        ? widget.regions
        : widget.regions.where((code) {
            if (code.toLowerCase().contains(query)) return true;
            return widget
                .countryNameOf(context, code)
                .toLowerCase()
                .contains(query);
          }).toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
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
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                context.l10n.downloadSongLinkRegionDesc,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: MaterialLocalizations.of(context).searchFieldLabel,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.l10n.dialogClear,
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.searchEmptyResultSubtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final code = matches[index];
                        final isSelected = code == widget.selected;
                        final countryName = widget.countryNameOf(context, code);
                        return ListTile(
                          title: Text(countryName != code ? countryName : code),
                          subtitle: countryName != code ? Text(code) : null,
                          trailing: isSelected
                              ? Icon(Icons.check, color: colorScheme.primary)
                              : null,
                          onTap: () => widget.onSelected(code),
                        );
                      },
                    ),
            ),
          ],
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
                final columns = (constraints.maxWidth / 320).floor().clamp(
                  2,
                  4,
                );
                final chipWidth =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final extension in extensionProviders)
                      SizedBox(
                        width: chipWidth,
                        child: SettingsChoiceChip(
                          layout: SettingsChipLayout.column,
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

class _MetadataSourceSelector extends ConsumerWidget {
  const _MetadataSourceSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final extState = ref.watch(extensionProvider);

    final rawSearchProvider = settings.searchProvider?.trim() ?? '';
    final primarySearchExtension = defaultSearchExtension(extState.extensions);
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

    final content = Padding(
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
          SettingsChoiceGrid(
            children: [
              SettingsChoiceChip(
                icon: Icons.auto_awesome,
                label: defaultProviderLabel,
                isSelected: searchProvider.isEmpty,
                onTap: () =>
                    ref.read(settingsProvider.notifier).setSearchProvider(''),
              ),
              for (final ext in extState.extensions.where(
                (e) => e.enabled && e.hasCustomSearch,
              ))
                SettingsChoiceChip(
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
    return SettingsSearchTarget(
      label: context.l10n.optionsPrimaryProvider,
      child: content,
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

    final content = Padding(
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
          SettingsChoiceGrid(
            children: [
              for (final tab in const [
                'all',
                'track',
                'artist',
                'album',
                'playlist',
              ])
                SettingsChoiceChip(
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
    return SettingsSearchTarget(
      label: context.l10n.optionsDefaultSearchTab,
      child: content,
    );
  }
}
