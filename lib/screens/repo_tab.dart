import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/extension_row.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/widgets/app_search_field.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/repo_provider.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/screens/repo/extension_details_screen.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';

class RepoTab extends ConsumerStatefulWidget {
  const RepoTab({super.key});

  @override
  ConsumerState<RepoTab> createState() => _RepoTabState();
}

class _RepoTabState extends ConsumerState<RepoTab> {
  final _searchController = TextEditingController();
  final _repoUrlController = TextEditingController();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    final cacheDir = await getApplicationCacheDirectory();

    if (!mounted) return;

    await ref.read(repoProvider.notifier).initialize(cacheDir.path);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _repoUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storeFilterState = ref.watch(
      repoProvider.select(
        (s) => (s.extensions, s.selectedCategory, s.searchQuery),
      ),
    );
    final extensions = storeFilterState.$1;
    final selectedCategory = storeFilterState.$2;
    final searchQuery = storeFilterState.$3;
    final isLoading = ref.watch(repoProvider.select((s) => s.isLoading));
    final error = ref.watch(repoProvider.select((s) => s.error));
    final downloadingId = ref.watch(
      repoProvider.select((s) => s.downloadingId),
    );
    final hasRegistryUrl = ref.watch(
      repoProvider.select((s) => s.hasRegistryUrl),
    );
    final registryUrl = ref.watch(repoProvider.select((s) => s.registryUrl));
    final filteredExtensions = RepoState(
      extensions: extensions,
      selectedCategory: selectedCategory,
      searchQuery: searchQuery,
    ).filteredExtensions;
    if (_searchController.text != searchQuery) {
      _searchController.value = TextEditingValue(
        text: searchQuery,
        selection: TextSelection.collapsed(offset: searchQuery.length),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = context.navBarBottomInset;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(repoProvider.notifier).refresh(forceRefresh: true),
        child: CustomScrollView(
          slivers: [
            AppSliverHeader.tabRoot(
              title: context.l10n.storeTitle,
              actions: [
                if (hasRegistryUrl)
                  IconButton(
                    icon: const Icon(Icons.link),
                    tooltip: context.l10n.storeChangeRepoTooltip,
                    onPressed: () => _showChangeRepoDialog(registryUrl),
                  ),
              ],
            ),

            if (!hasRegistryUrl)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildSetupRepoState(colorScheme, error),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: AppSearchField(
                    controller: _searchController,
                    hintText: context.l10n.storeSearch,
                    clearTooltip: context.l10n.dialogClear,
                    onChanged: (value) =>
                        ref.read(repoProvider.notifier).setSearchQuery(value),
                    onClear: () =>
                        ref.read(repoProvider.notifier).setSearchQuery(''),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      _CategoryChip(
                        label: context.l10n.storeFilterAll,
                        icon: Icons.apps,
                        isSelected: selectedCategory == null,
                        onTap: () =>
                            ref.read(repoProvider.notifier).setCategory(null),
                      ),
                      const SizedBox(width: 8),
                      _CategoryChip(
                        label: context.l10n.storeFilterMetadata,
                        icon: Icons.label_outline,
                        isSelected: selectedCategory == RepoCategory.metadata,
                        onTap: () => ref
                            .read(repoProvider.notifier)
                            .setCategory(RepoCategory.metadata),
                      ),
                      const SizedBox(width: 8),
                      _CategoryChip(
                        label: context.l10n.storeFilterDownload,
                        icon: Icons.download_outlined,
                        isSelected: selectedCategory == RepoCategory.download,
                        onTap: () => ref
                            .read(repoProvider.notifier)
                            .setCategory(RepoCategory.download),
                      ),
                      const SizedBox(width: 8),
                      _CategoryChip(
                        label: context.l10n.storeFilterUtility,
                        icon: Icons.build_outlined,
                        isSelected: selectedCategory == RepoCategory.utility,
                        onTap: () => ref
                            .read(repoProvider.notifier)
                            .setCategory(RepoCategory.utility),
                      ),
                      const SizedBox(width: 8),
                      _CategoryChip(
                        label: context.l10n.storeFilterLyrics,
                        icon: Icons.lyrics_outlined,
                        isSelected: selectedCategory == RepoCategory.lyrics,
                        onTap: () => ref
                            .read(repoProvider.notifier)
                            .setCategory(RepoCategory.lyrics),
                      ),
                      const SizedBox(width: 8),
                      _CategoryChip(
                        label: context.l10n.storeFilterIntegration,
                        icon: Icons.link,
                        isSelected:
                            selectedCategory == RepoCategory.integration,
                        onTap: () => ref
                            .read(repoProvider.notifier)
                            .setCategory(RepoCategory.integration),
                      ),
                    ],
                  ),
                ),
              ),

              if (isLoading && extensions.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: TrackListSkeleton(itemCount: 6),
                  ),
                )
              else if (error != null && extensions.isEmpty)
                SliverFillRemaining(child: _buildErrorState(error, colorScheme))
              else if (filteredExtensions.isEmpty)
                SliverFillRemaining(
                  child: _buildEmptyState(
                    hasFilters:
                        searchQuery.isNotEmpty || selectedCategory != null,
                    colorScheme: colorScheme,
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      context.l10n.storeExtensionsCount(
                        filteredExtensions.length,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: SettingsGroup(
                    children: filteredExtensions.asMap().entries.map((entry) {
                      final index = entry.key;
                      final ext = entry.value;
                      return _ExtensionItem(
                        extension: ext,
                        showDivider: index < filteredExtensions.length - 1,
                        isDownloading: downloadingId == ext.id,
                        onInstall: () => _installExtension(ext),
                        onUpdate: () => _updateExtension(ext),
                        onTap: () => _showExtensionDetails(ext),
                      );
                    }).toList(),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ],
            SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupRepoState(ColorScheme colorScheme, String? error) {
    // Bottom padding keeps the content optically centered in the area
    // visible above the translucent nav bar.
    return Padding(
      padding: EdgeInsets.fromLTRB(32, 32, 32, 32 + context.navBarBottomInset),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.extension_outlined,
                size: 72,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 24),
              Text(
                context.l10n.storeAddRepoTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _repoUrlController,
                decoration: InputDecoration(
                  hintText: context.l10n.storeRepoUrlHint,
                  labelText: context.l10n.storeRepoUrlLabel,
                  prefixIcon: const Icon(Icons.link),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                // Reveal the submit button below the field when the keyboard
                // auto-scrolls to the focused input.
                scrollPadding: const EdgeInsets.only(bottom: 120),
                onSubmitted: (_) => _submitRepoUrl(),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 20,
                        color: colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.friendlyError(error),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitRepoUrl,
                  icon: const Icon(Icons.add),
                  label: Text(context.l10n.storeAddRepoButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submitRepoUrl() {
    final url = _repoUrlController.text.trim();
    if (url.isEmpty) return;
    ref.read(repoProvider.notifier).setRegistryUrl(url);
  }

  void _showChangeRepoDialog(String currentUrl) {
    final changeUrlController = TextEditingController(text: currentUrl);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.storeRepoDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.storeRepoDialogCurrent,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              currentUrl,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: changeUrlController,
              decoration: InputDecoration(
                hintText: context.l10n.storeRepoUrlHint,
                labelText: context.l10n.storeNewRepoUrlLabel,
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(repoProvider.notifier).removeRegistryUrl();
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.l10n.dialogRemove),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () {
              final newUrl = changeUrlController.text.trim();
              Navigator.of(context).pop();
              if (newUrl.isNotEmpty) {
                ref.read(repoProvider.notifier).setRegistryUrl(newUrl);
              }
            },
            child: Text(context.l10n.dialogSave),
          ),
        ],
      ),
    ).then((_) => changeUrlController.dispose());
  }

  Widget _buildErrorState(String error, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              context.l10n.storeLoadError,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.friendlyError(error),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(repoProvider.notifier).refresh(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.dialogRetry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required bool hasFilters,
    required ColorScheme colorScheme,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasFilters ? Icons.search_off : Icons.extension_off,
            size: 64,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            hasFilters
                ? context.l10n.storeEmptyNoResults
                : context.l10n.storeEmptyNoExtensions,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (hasFilters) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                _searchController.clear();
                ref.read(repoProvider.notifier).clearSearch();
              },
              child: Text(context.l10n.storeClearFilters),
            ),
          ],
        ],
      ),
    );
  }

  void _showExtensionDetails(RepoExtension ext) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ExtensionDetailsScreen(extension: ext),
      ),
    );
  }

  Future<void> _installExtension(RepoExtension ext) async {
    final tempDir = await getTemporaryDirectory();
    final appDir = await getApplicationDocumentsDirectory();
    final extensionsDir = '${appDir.path}/extensions';

    final success = await ref
        .read(repoProvider.notifier)
        .installExtension(ext.id, tempDir.path, extensionsDir);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? context.l10n.snackbarExtensionInstalledEnable(ext.displayName)
                : context.l10n.snackbarFailedToInstallNamed(ext.displayName),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _updateExtension(RepoExtension ext) async {
    final tempDir = await getTemporaryDirectory();

    final success = await ref
        .read(repoProvider.notifier)
        .updateExtension(ext.id, tempDir.path);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? context.l10n.snackbarExtensionUpdatedVersion(
                    ext.displayName,
                    ext.version,
                  )
                : context.l10n.snackbarFailedToUpdateNamed(ext.displayName),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(label)],
      ),
      selected: isSelected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      backgroundColor: settingsGroupColor(context),
      side: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
      ),
    );
  }
}

class _ExtensionItem extends StatelessWidget {
  final RepoExtension extension;
  final bool showDivider;
  final bool isDownloading;
  final VoidCallback onInstall;
  final VoidCallback onUpdate;
  final VoidCallback? onTap;

  const _ExtensionItem({
    required this.extension,
    required this.showDivider,
    required this.isDownloading,
    required this.onInstall,
    required this.onUpdate,
    this.onTap,
  });

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case RepoCategory.metadata:
        return Icons.label_outline;
      case RepoCategory.download:
        return Icons.download_outlined;
      case RepoCategory.utility:
        return Icons.build_outlined;
      case RepoCategory.lyrics:
        return Icons.lyrics_outlined;
      case RepoCategory.integration:
        return Icons.link;
      default:
        return Icons.extension;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    return ExtensionRow(
      showDivider: showDivider,
      onTap: onTap,
      avatar: ExtensionAvatar(
        imageUrl: extension.iconUrl,
        fallbackIcon: _getCategoryIcon(extension.category),
        background: extension.isInstalled
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        foreground: extension.isInstalled
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurfaceVariant,
      ),
      title: Row(
        children: [
          Expanded(child: Text(extension.displayName)),
          Container(
            padding: tokens.badgePadding,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: tokens.borderRadiusBadge,
            ),
            child: Text(
              'v${extension.version}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      subtitle: extension.requiresNewerApp
          ? Container(
              padding: tokens.badgePadding,
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: tokens.borderRadiusBadge,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 12,
                    color: colorScheme.onErrorContainer,
                  ),
                  SizedBox(width: tokens.gapXs),
                  Text(
                    context.l10n.storeRequiresVersion(
                      extension.minAppVersion ?? '',
                    ),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : Text(
              extension.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Padding(
        padding: EdgeInsets.only(left: tokens.gapMd),
        child: isDownloading
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : extension.hasUpdate
            ? FilledButton.tonal(
                onPressed: onUpdate,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 40),
                ),
                child: Text(context.l10n.storeUpdate),
              )
            : extension.isInstalled
            ? OutlinedButton(
                onPressed: null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 40),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, size: 16, color: colorScheme.outline),
                    SizedBox(width: tokens.gapXs),
                    Text(
                      context.l10n.storeInstalled,
                      style: TextStyle(color: colorScheme.outline),
                    ),
                  ],
                ),
              )
            : FilledButton(
                onPressed: onInstall,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 40),
                ),
                child: Text(context.l10n.storeInstall),
              ),
      ),
    );
  }
}
