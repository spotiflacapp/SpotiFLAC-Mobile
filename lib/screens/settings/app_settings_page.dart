import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';

class AppSettingsPage extends ConsumerWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            AppSliverHeader.page(title: context.l10n.settingsApp),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(title: context.l10n.sectionApp),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  SettingsSwitchItem(
                    icon: Icons.extension,
                    title: context.l10n.optionsExtensionStore,
                    subtitle: context.l10n.optionsExtensionStoreSubtitle,
                    value: settings.showExtensionStore,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .setShowExtensionStore(v),
                  ),
                  _VerificationBrowserModeSelector(
                    currentMode: settings.extensionVerificationBrowserMode,
                    onChanged: (mode) => ref
                        .read(settingsProvider.notifier)
                        .setExtensionVerificationBrowserMode(mode),
                  ),
                  SettingsSwitchItem(
                    icon: Icons.system_update,
                    title: context.l10n.optionsCheckUpdates,
                    subtitle: context.l10n.optionsCheckUpdatesSubtitle,
                    value: settings.checkForUpdates,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .setCheckForUpdates(v),
                    showDivider: settings.checkForUpdates,
                  ),
                  if (settings.checkForUpdates)
                    _UpdateChannelSelector(
                      currentChannel: settings.updateChannel,
                      onChanged: (v) => ref
                          .read(settingsProvider.notifier)
                          .setUpdateChannel(v),
                    ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(title: context.l10n.sectionData),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  SettingsItem(
                    icon: Icons.cleaning_services_outlined,
                    title: context.l10n.cleanupOrphanedDownloads,
                    subtitle: context.l10n.cleanupOrphanedDownloadsSubtitle,
                    onTap: () => _cleanupOrphanedDownloads(context, ref),
                  ),
                  SettingsItem(
                    icon: Icons.delete_forever,
                    title: context.l10n.optionsClearHistory,
                    subtitle: context.l10n.optionsClearHistorySubtitle,
                    onTap: () =>
                        _showClearHistoryDialog(context, ref, colorScheme),
                  ),
                  SettingsSwitchItem(
                    icon: Icons.history_toggle_off_outlined,
                    title: context.l10n.settingsSaveDownloadHistory,
                    subtitle: context.l10n.settingsSaveDownloadHistorySubtitle,
                    value: settings.saveDownloadHistory,
                    onChanged: (enabled) {
                      if (enabled) {
                        ref
                            .read(settingsProvider.notifier)
                            .setSaveDownloadHistory(true);
                        return;
                      }

                      final hasHistory = ref
                          .read(downloadHistoryProvider)
                          .items
                          .isNotEmpty;
                      if (hasHistory) {
                        _showDisableHistoryDialog(context, ref, colorScheme);
                        return;
                      }

                      ref
                          .read(settingsProvider.notifier)
                          .setSaveDownloadHistory(false);
                    },
                    showDivider: false,
                  ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(title: context.l10n.sectionDebug),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  SettingsSwitchItem(
                    icon: Icons.bug_report,
                    title: context.l10n.optionsDetailedLogging,
                    subtitle: settings.enableLogging
                        ? context.l10n.optionsDetailedLoggingOn
                        : context.l10n.optionsDetailedLoggingOff,
                    value: settings.enableLogging,
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).setEnableLogging(v),
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

  void _showDisableHistoryDialog(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.dialogDisableHistoryTitle),
        content: Text(context.l10n.dialogDisableHistoryMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.dialogCancel),
          ),
          TextButton(
            onPressed: () {
              ref.read(downloadHistoryProvider.notifier).clearHistory();
              ref.read(settingsProvider.notifier).setSaveDownloadHistory(false);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.snackbarHistoryCleared)),
              );
            },
            child: Text(
              context.l10n.dialogDisableAndClear,
              style: TextStyle(color: colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearHistoryDialog(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.dialogClearHistoryTitle),
        content: Text(context.l10n.dialogClearHistoryMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.dialogCancel),
          ),
          TextButton(
            onPressed: () {
              ref.read(downloadHistoryProvider.notifier).clearHistory();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.snackbarHistoryCleared)),
              );
            },
            child: Text(
              context.l10n.dialogClear,
              style: TextStyle(color: colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cleanupOrphanedDownloads(
    BuildContext context,
    WidgetRef ref,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(context.l10n.cleanupOrphanedDownloads),
          ],
        ),
      ),
    );
    try {
      final removed = await ref
          .read(downloadHistoryProvider.notifier)
          .cleanupOrphanedDownloads();
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              removed > 0
                  ? context.l10n.cleanupOrphanedDownloadsResult(removed)
                  : context.l10n.cleanupOrphanedDownloadsNone,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.snackbarError(context.friendlyError(e))),
          ),
        );
      }
    }
  }
}

class _UpdateChannelSelector extends StatelessWidget {
  final String currentChannel;
  final ValueChanged<String> onChanged;
  const _UpdateChannelSelector({
    required this.currentChannel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final content = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.new_releases,
                color: colorScheme.onSurfaceVariant,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.optionsUpdateChannel,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentChannel == 'preview'
                          ? context.l10n.optionsUpdateChannelPreview
                          : context.l10n.optionsUpdateChannelStable,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SettingsChoiceChip(
                expand: true,
                label: context.l10n.channelStable,
                isSelected: currentChannel == 'stable',
                onTap: () => onChanged('stable'),
              ),
              const SizedBox(width: 8),
              SettingsChoiceChip(
                expand: true,
                label: context.l10n.channelPreview,
                isSelected: currentChannel == 'preview',
                onTap: () => onChanged('preview'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.optionsUpdateChannelWarning,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return SettingsSearchTarget(
      label: context.l10n.optionsUpdateChannel,
      child: content,
    );
  }
}

class _VerificationBrowserModeSelector extends StatelessWidget {
  final String currentMode;
  final ValueChanged<String> onChanged;

  const _VerificationBrowserModeSelector({
    required this.currentMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final normalizedMode = currentMode == 'in_app_first'
        ? 'in_app_first'
        : currentMode == 'external_first'
        ? 'external_first'
        : 'in_app_first';

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.open_in_browser,
                    color: colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.extensionVerificationBrowserTitle,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          normalizedMode == 'external_first'
                              ? context
                                    .l10n
                                    .extensionVerificationBrowserSubtitleExternal
                              : context
                                    .l10n
                                    .extensionVerificationBrowserSubtitleInApp,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  SettingsChoiceChip(
                    expand: true,
                    label: context.l10n.extensionVerificationBrowserExternal,
                    isSelected: normalizedMode == 'external_first',
                    onTap: () => onChanged('external_first'),
                  ),
                  const SizedBox(width: 8),
                  SettingsChoiceChip(
                    expand: true,
                    label: context.l10n.extensionVerificationBrowserInApp,
                    isSelected: normalizedMode == 'in_app_first',
                    onTap: () => onChanged('in_app_first'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          indent: 56,
          endIndent: 20,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ],
    );
    return SettingsSearchTarget(
      label: context.l10n.extensionVerificationBrowserTitle,
      child: content,
    );
  }
}
