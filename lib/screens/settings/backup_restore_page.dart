import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/backup_service.dart';
import 'package:spotiflac_android/services/history_database.dart';
import 'package:spotiflac_android/utils/app_bar_layout.dart';
import 'package:spotiflac_android/utils/logger.dart';

class BackupRestorePage extends ConsumerStatefulWidget {
  const BackupRestorePage({super.key});

  @override
  ConsumerState<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends ConsumerState<BackupRestorePage> {
  static final _log = AppLogger('BackupRestorePage');

  bool _isExporting = false;
  bool _isImporting = false;
  bool _includeSecrets = false;

  bool get _isBusy => _isExporting || _isImporting;

  Future<void> _createBackup() async {
    if (_isBusy) return;
    setState(() => _isExporting = true);
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final settings = ref.read(settingsProvider).toJson();
      final history = await HistoryDatabase.instance.getAll();
      final collectionsNotifier = ref.read(
        libraryCollectionsProvider.notifier,
      );
      final collections = await collectionsNotifier.exportCollections();
      final covers = await collectionsNotifier.exportPlaylistCovers();
      final extensions = await ref
          .read(extensionProvider.notifier)
          .exportBackup(includeSecrets: _includeSecrets);

      final envelope = BackupService.buildEnvelope(
        settings: settings,
        history: history,
        collections: collections,
        playlistCovers: covers,
        extensions: extensions,
      );

      final file = await BackupService.writeBackupFile(envelope);

      messenger.showSnackBar(SnackBar(content: Text(l10n.backupCreated)));

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: l10n.backupTitle),
      );
    } catch (e, stack) {
      _log.e('Failed to create backup: $e', e, stack);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.backupCreateFailed)),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (_isBusy) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);

    String? content;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', BackupService.fileExtension],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      content = await File(path).readAsString();
    } catch (e) {
      _log.e('Failed to read backup file: $e');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.backupInvalidFile)),
      );
      return;
    }

    final bundle = BackupService.parse(content);
    if (bundle == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.backupInvalidFile)),
      );
      return;
    }

    if (!mounted) return;
    final confirmed = await _confirmRestore(bundle);
    if (confirmed != true || !mounted) return;

    setState(() => _isImporting = true);
    try {
      if (bundle.hasSettings) {
        await ref
            .read(settingsProvider.notifier)
            .restoreFromBackup(bundle.settings!);
      }
      await ref
          .read(downloadHistoryProvider.notifier)
          .restoreFromBackup(bundle.history);
      await ref
          .read(libraryCollectionsProvider.notifier)
          .restoreFromBackup(
            bundle.collections,
            coverImages: bundle.playlistCovers,
          );

      ExtensionRestoreResult? extResult;
      if (bundle.hasExtensions) {
        extResult = await ref
            .read(extensionProvider.notifier)
            .restoreFromBackup(bundle.extensions);
      }

      final message = StringBuffer(l10n.backupRestored)
        ..write('\n')
        ..write(l10n.backupRestoreRestartHint);
      if (extResult != null && extResult.failed > 0) {
        message
          ..write('\n')
          ..write(l10n.backupExtensionsRestoreFailed(extResult.failed));
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(message.toString()),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e, stack) {
      _log.e('Failed to restore backup: $e', e, stack);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.backupRestoreFailed)),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<bool?> _confirmRestore(BackupBundle bundle) {
    final l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.backupRestoreConfirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.backupRestoreConfirmMessage),
              const SizedBox(height: 16),
              Text(
                l10n.backupContentsTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              if (bundle.hasSettings)
                _ContentRow(
                  icon: Icons.settings_outlined,
                  label: l10n.backupContentsSettings,
                ),
              _ContentRow(
                icon: Icons.history,
                label: l10n.backupContentsHistory(bundle.historyCount),
              ),
              _ContentRow(
                icon: Icons.favorite_outline,
                label: l10n.backupContentsLiked(bundle.likedCount),
              ),
              _ContentRow(
                icon: Icons.bookmark_outline,
                label: l10n.backupContentsWishlist(bundle.wishlistCount),
              ),
              _ContentRow(
                icon: Icons.queue_music_outlined,
                label: l10n.backupContentsPlaylists(bundle.playlistCount),
              ),
              if (bundle.favoriteArtistCount > 0)
                _ContentRow(
                  icon: Icons.person_outline,
                  label: l10n.backupContentsArtists(
                    bundle.favoriteArtistCount,
                  ),
                ),
              if (bundle.extensionCount > 0)
                _ContentRow(
                  icon: Icons.extension_outlined,
                  label: l10n.backupContentsExtensions(
                    bundle.extensionCount,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.dialogCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.backupRestoreConfirmButton),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topPadding = normalizedHeaderTopPadding(context);
    final l10n = context.l10n;

    return Scaffold(
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
                  titlePadding: EdgeInsets.only(left: leftPadding, bottom: 16),
                  title: Text(
                    l10n.backupTitle,
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ActionCard(
                    icon: Icons.backup_outlined,
                    title: l10n.backupExportSectionTitle,
                    description: l10n.backupExportSectionDescription,
                    buttonLabel: l10n.backupExportButton,
                    buttonIcon: Icons.ios_share,
                    isBusy: _isExporting,
                    onPressed: _isBusy ? null : _createBackup,
                    extra: Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _includeSecrets,
                        onChanged: _isBusy
                            ? null
                            : (value) =>
                                  setState(() => _includeSecrets = value),
                        title: Text(l10n.backupIncludeSecrets),
                        subtitle: Text(l10n.backupIncludeSecretsDescription),
                        isThreeLine: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ActionCard(
                    icon: Icons.settings_backup_restore,
                    title: l10n.backupImportSectionTitle,
                    description: l10n.backupImportSectionDescription,
                    buttonLabel: l10n.backupImportButton,
                    buttonIcon: Icons.folder_open_outlined,
                    isBusy: _isImporting,
                    onPressed: _isBusy ? null : _restoreBackup,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final IconData buttonIcon;
  final bool isBusy;
  final VoidCallback? onPressed;
  final Widget? extra;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.buttonIcon,
    required this.isBusy,
    required this.onPressed,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          ?extra,
          const SizedBox(height: 16),          FilledButton.icon(
            onPressed: onPressed,
            icon: isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(buttonIcon),
            label: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

class _ContentRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ContentRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
