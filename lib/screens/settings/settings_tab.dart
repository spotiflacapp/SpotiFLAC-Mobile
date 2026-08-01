import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/constants/app_info.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/screens/settings/about_page.dart';
import 'package:spotiflac_android/screens/settings/app_settings_page.dart';
import 'package:spotiflac_android/screens/settings/appearance_settings_page.dart';
import 'package:spotiflac_android/screens/settings/backup_restore_page.dart';
import 'package:spotiflac_android/screens/settings/cache_management_page.dart';
import 'package:spotiflac_android/screens/settings/donate_page.dart';
import 'package:spotiflac_android/screens/settings/download_settings_page.dart';
import 'package:spotiflac_android/screens/settings/extensions_page.dart';
import 'package:spotiflac_android/screens/settings/files_settings_page.dart';
import 'package:spotiflac_android/screens/settings/library_settings_page.dart';
import 'package:spotiflac_android/screens/settings/log_screen.dart';
import 'package:spotiflac_android/screens/settings/lyrics_settings_page.dart';
import 'package:spotiflac_android/screens/settings/metadata_settings_page.dart';
import 'package:spotiflac_android/screens/settings/settings_search_catalog.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/widgets/app_search_field.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';

/// One entry on the Settings tab.
class _Destination {
  const _Destination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.pageBuilder,
    this.keywords = const [],
    this.searchEntries = const [],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget Function() pageBuilder;

  /// Extra search terms for things the title does not spell out (e.g. "SAF"
  /// for the Files page), so a user can find a page by what it does.
  final List<String> keywords;
  final List<SettingsSearchEntry> searchEntries;

  bool matches(SettingsSearchQuery query) {
    return query.matches([title, subtitle, ...keywords]);
  }
}

class _SearchResult {
  const _SearchResult(this.destination, [this.entry]);

  final _Destination destination;
  final SettingsSearchEntry? entry;
}

/// Destinations that stay visually connected inside one settings card.
class _Group {
  const _Group({required this.destinations});

  final List<_Destination> destinations;
}

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  AppLocalizations? _cachedLocalizations;
  List<_Group>? _cachedGroups;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Related destinations share one card; whitespace separates each group
  /// without adding section labels that compete with the page title.
  List<_Group> _groups(BuildContext context) {
    final l10n = context.l10n;
    if (identical(_cachedLocalizations, l10n) && _cachedGroups != null) {
      return _cachedGroups!;
    }

    final searchCatalog = SettingsSearchCatalog(l10n);
    final groups = [
      _Group(
        destinations: [
          _Destination(
            icon: Icons.favorite_outline,
            title: l10n.settingsDonate,
            subtitle: l10n.settingsDonateSubtitle,
            keywords: const ['support', 'ko-fi', 'sponsor'],
            pageBuilder: () => const DonatePage(),
          ),
        ],
      ),
      _Group(
        destinations: [
          _Destination(
            icon: Icons.extension_outlined,
            title: l10n.settingsExtensions,
            subtitle: l10n.settingsExtensionsSubtitle,
            keywords: const ['plugin', 'provider', 'priority', 'store'],
            searchEntries: searchCatalog.extensions,
            pageBuilder: () => const ExtensionsPage(),
          ),
          _Destination(
            icon: Icons.palette_outlined,
            title: l10n.settingsAppearance,
            subtitle: l10n.settingsAppearanceSubtitle,
            keywords: const [
              'theme',
              'dark',
              'light',
              'amoled',
              'color',
              'language',
              'locale',
              'layout',
              'grid',
            ],
            searchEntries: searchCatalog.appearance,
            pageBuilder: () => const AppearanceSettingsPage(),
          ),
        ],
      ),
      _Group(
        destinations: [
          _Destination(
            icon: Icons.library_music_outlined,
            title: l10n.settingsLocalLibrary,
            subtitle: l10n.settingsLocalLibrarySubtitle,
            keywords: const [
              'scan',
              'local',
              'player',
              'playback',
              'duplicate',
            ],
            searchEntries: searchCatalog.library,
            pageBuilder: () => const LibrarySettingsPage(),
          ),
          _Destination(
            icon: Icons.sell_outlined,
            title: l10n.settingsMetadata,
            subtitle: l10n.settingsMetadataSubtitle,
            keywords: const ['tag', 'cover', 'artwork', 'isrc', 'provider'],
            searchEntries: searchCatalog.metadata,
            pageBuilder: () => const MetadataSettingsPage(),
          ),
          _Destination(
            icon: Icons.lyrics_outlined,
            title: l10n.settingsLyrics,
            subtitle: l10n.settingsLyricsSubtitle,
            keywords: const ['lrc', 'synced', 'provider'],
            searchEntries: searchCatalog.lyrics,
            pageBuilder: () => const LyricsSettingsPage(),
          ),
        ],
      ),
      _Group(
        destinations: [
          _Destination(
            icon: Icons.download_outlined,
            title: l10n.settingsDownload,
            subtitle: l10n.settingsDownloadSubtitle,
            keywords: const [
              'quality',
              'flac',
              'concurrent',
              'network',
              'wifi',
              'service',
              'region',
            ],
            searchEntries: searchCatalog.download,
            pageBuilder: () => const DownloadSettingsPage(),
          ),
          _Destination(
            icon: Icons.folder_outlined,
            title: l10n.settingsFiles,
            subtitle: l10n.settingsFilesSubtitle,
            keywords: const [
              'saf',
              'storage',
              'folder',
              'filename',
              'path',
              'permission',
            ],
            searchEntries: searchCatalog.files,
            pageBuilder: () => const FilesSettingsPage(),
          ),
        ],
      ),
      _Group(
        destinations: [
          _Destination(
            icon: Icons.tune_outlined,
            title: l10n.settingsApp,
            subtitle: l10n.settingsAppSubtitle,
            keywords: const ['update', 'channel', 'debug', 'logging'],
            searchEntries: searchCatalog.app,
            pageBuilder: () => const AppSettingsPage(),
          ),
          _Destination(
            icon: Icons.storage_outlined,
            title: l10n.settingsCache,
            subtitle: l10n.settingsCacheSubtitle,
            keywords: const ['clear', 'space', 'image', 'temp'],
            searchEntries: searchCatalog.cache,
            pageBuilder: () => const CacheManagementPage(),
          ),
          _Destination(
            icon: Icons.settings_backup_restore,
            title: l10n.settingsBackup,
            subtitle: l10n.settingsBackupSubtitle,
            keywords: const ['export', 'import', 'restore', 'json'],
            searchEntries: searchCatalog.backup,
            pageBuilder: () => const BackupRestorePage(),
          ),
          _Destination(
            icon: Icons.article_outlined,
            title: l10n.logTitle,
            subtitle: l10n.settingsLogsSubtitle,
            keywords: const ['debug', 'error', 'report'],
            searchEntries: searchCatalog.logs,
            pageBuilder: () => const LogScreen(),
          ),
        ],
      ),
      _Group(
        destinations: [
          _Destination(
            icon: Icons.info_outline,
            title: l10n.settingsAbout,
            subtitle: '${l10n.aboutVersion} ${AppInfo.displayVersion}',
            keywords: const ['version', 'license', 'contributor'],
            searchEntries: searchCatalog.about,
            pageBuilder: () => const AboutPage(),
          ),
        ],
      ),
    ];
    _cachedLocalizations = l10n;
    _cachedGroups = groups;
    return groups;
  }

  Future<void> _navigateTo(
    BuildContext context,
    Widget page, {
    String? targetLabel,
  }) async {
    _searchFocusNode.unfocus();
    _searchFocusNode.canRequestFocus = false;
    FocusManager.instance.primaryFocus?.unfocus();
    final destination = targetLabel == null
        ? page
        : SettingsSearchHighlightScope(targetLabel: targetLabel, child: page);
    await Navigator.of(context).push(slidePageRoute<void>(page: destination));
    if (!mounted) return;

    // A route's focus scope remembers its previously focused child. Keep the
    // search field out of that restoration cycle while the child page is open,
    // then re-enable it without requesting focus when Settings becomes active.
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.canRequestFocus = true;
      _searchFocusNode.unfocus();
    });
  }

  Widget _itemFor(_Destination destination, {required bool showDivider}) {
    return SettingsItem(
      icon: destination.icon,
      title: destination.title,
      subtitle: destination.subtitle,
      showDivider: showDivider,
      onTap: () => _navigateTo(context, destination.pageBuilder()),
    );
  }

  Widget _searchItemFor(_SearchResult result, {required bool showDivider}) {
    final entry = result.entry;
    if (entry == null) {
      return _itemFor(result.destination, showDivider: showDivider);
    }

    return SettingsItem(
      key: ValueKey(
        'settings-search:${result.destination.title}:${entry.title}',
      ),
      icon: entry.icon,
      title: entry.title,
      subtitle: result.destination.title,
      showDivider: showDivider,
      onTap: () => _navigateTo(
        context,
        result.destination.pageBuilder(),
        targetLabel: entry.targetLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bottomInset = context.navBarBottomInset;
    final wideInset = wideListInset(context);
    final query = SettingsSearchQuery(_query);
    final groups = _groups(context);

    final margin = EdgeInsets.fromLTRB(
      tokens.gapLg + wideInset,
      tokens.gapSm,
      tokens.gapLg + wideInset,
      tokens.gapSm,
    );

    final List<Widget> body;
    if (query.isEmpty) {
      body = [
        for (final group in groups)
          SliverToBoxAdapter(
            child: SettingsGroup(
              margin: margin,
              children: [
                for (var i = 0; i < group.destinations.length; i++)
                  _itemFor(
                    group.destinations[i],
                    showDivider: i != group.destinations.length - 1,
                  ),
              ],
            ),
          ),
      ];
    } else {
      final matches = <_SearchResult>[
        for (final group in groups)
          for (final destination in group.destinations) ...[
            if (destination.matches(query)) _SearchResult(destination),
            for (final entry in destination.searchEntries)
              if (entry.matches(query)) _SearchResult(destination, entry),
          ],
      ];
      body = matches.isEmpty
          ? [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(tokens.gapXl),
                  child: Text(
                    context.l10n.settingsSearchNoResults(_query.trim()),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ]
          : [
              SliverToBoxAdapter(
                child: SettingsGroup(
                  margin: margin,
                  children: [
                    for (var i = 0; i < matches.length; i++)
                      _searchItemFor(
                        matches[i],
                        showDivider: i != matches.length - 1,
                      ),
                  ],
                ),
              ),
            ];
    }

    return CustomScrollView(
      slivers: [
        AppSliverHeader.tabRoot(title: context.l10n.settingsTitle),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.gapLg + wideInset,
              tokens.gapSm,
              tokens.gapLg + wideInset,
              tokens.gapSm,
            ),
            child: AppSearchField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hintText: context.l10n.settingsSearchHint,
              clearTooltip: context.l10n.dialogClear,
              onChanged: (value) => setState(() => _query = value),
              onClear: () => setState(() => _query = ''),
            ),
          ),
        ),
        ...body,
        SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
        const SliverFillRemaining(hasScrollBody: false, child: SizedBox()),
      ],
    );
  }
}
