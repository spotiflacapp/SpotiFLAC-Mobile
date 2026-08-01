import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/repo_provider.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/providers/track_provider.dart';
import 'package:spotiflac_android/providers/preview_player_provider.dart';
import 'package:spotiflac_android/screens/home_tab.dart';
import 'package:spotiflac_android/screens/repo_tab.dart';
import 'package:spotiflac_android/screens/queue_tab.dart';
import 'package:spotiflac_android/screens/settings/settings_tab.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/services/shell_navigation_service.dart';
import 'package:spotiflac_android/services/share_intent_service.dart';
import 'package:spotiflac_android/services/music_player_service.dart';
import 'package:spotiflac_android/services/notification_service.dart';
import 'package:spotiflac_android/services/app_remote_config_service.dart';
import 'package:spotiflac_android/services/update_checker.dart';
import 'package:spotiflac_android/widgets/app_announcement_dialog.dart';
import 'package:spotiflac_android/widgets/update_dialog.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/widgets/mini_player.dart';
import 'package:spotiflac_android/widgets/selection_bottom_bar.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('MainShell');

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _currentIndex = 0;
  // Preserves the PageView element (and its kept-alive tabs) when the body
  // structure swaps between rail and bottom-bar layouts on rotation.
  final GlobalKey _pageViewKey = GlobalKey();
  late final PageController _pageController;
  late final AnimationController _tabJumpTransitionController;
  bool _hasCheckedUpdate = false;
  bool _hasCheckedAppAnnouncement = false;
  bool _initialSafRepairComplete = false;
  bool _safRepairDialogVisible = false;
  StreamSubscription<String>? _shareSubscription;
  DateTime? _lastBackPress;
  final GlobalKey<NavigatorState> _homeTabNavigatorKey =
      ShellNavigationService.homeTabNavigatorKey;
  final GlobalKey<NavigatorState> _libraryTabNavigatorKey =
      ShellNavigationService.libraryTabNavigatorKey;
  final GlobalKey<NavigatorState> _repoTabNavigatorKey =
      ShellNavigationService.repoTabNavigatorKey;

  late final _PreviewStopNavigatorObserver _homePreviewStopObserver;
  late final _PreviewStopNavigatorObserver _libraryPreviewStopObserver;
  late final _PreviewStopNavigatorObserver _repoPreviewStopObserver;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = context.l10n;
    NotificationService().updateStrings(l10n);
    updateMusicPlayerStrings(
      unknownTitle: l10n.unknownTitle,
      unknownArtist: l10n.unknownArtist,
    );
    setPlaybackNormalizationEnabled(
      ref.read(settingsProvider).playbackNormalization,
    );
    // Deezer & co. localize artist/genre names by IP unless told the app's
    // language (issue #480).
    unawaited(
      PlatformBridge.setMetadataLanguage(
        Localizations.localeOf(context).toLanguageTag(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _homePreviewStopObserver = _PreviewStopNavigatorObserver(
      () => ref.read(previewPlayerProvider.notifier).stop(),
    );
    _libraryPreviewStopObserver = _PreviewStopNavigatorObserver(
      () => ref.read(previewPlayerProvider.notifier).stop(),
    );
    _repoPreviewStopObserver = _PreviewStopNavigatorObserver(
      () => ref.read(previewPlayerProvider.notifier).stop(),
    );
    _pageController = PageController(initialPage: _currentIndex);
    _tabJumpTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1,
    );
    ShellNavigationService.registerTabSelectionHandler(
      owner: this,
      handler: _onShellTabRequested,
    );
    ShellNavigationService.syncState(
      currentTabIndex: _currentIndex,
      showRepoTab: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _repairSafAccessIfNeeded(
        knownLost: ref.read(initialSafAccessLostProvider),
      );
      _initialSafRepairComplete = true;
      if (!mounted) return;
      unawaited(restorePersistedPlaybackSession());
      _setupShareListener();
      await _checkSafMigration();
      final updateDialogShown = await _checkForUpdates();
      if (!updateDialogShown) {
        await _checkAppAnnouncement();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _initialSafRepairComplete) {
      unawaited(_repairSafAccessIfNeeded());
    } else if (state == AppLifecycleState.paused) {
      unawaited(persistCurrentPlaybackSession());
    }
  }

  Future<void> _repairSafAccessIfNeeded({bool knownLost = false}) async {
    if (!Platform.isAndroid || _safRepairDialogVisible) return;

    var accessLost = knownLost;
    if (!accessLost) {
      final settings = ref.read(settingsProvider);
      if (settings.storageMode != 'saf' || settings.downloadTreeUri.isEmpty) {
        return;
      }
      accessLost = !await PlatformBridge.isSafTreeAccessible(
        settings.downloadTreeUri,
      );
    }
    if (!accessLost || !mounted) return;

    _safRepairDialogVisible = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          var isPickingFolder = false;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return PopScope(
                canPop: false,
                child: AlertDialog(
                  icon: Icon(
                    Icons.folder_off_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(context.l10n.downloadFolderAccessLostTitle),
                  content: Text(context.l10n.downloadFolderAccessLostSubtitle),
                  actions: [
                    TextButton(
                      onPressed: isPickingFolder
                          ? null
                          : () {
                              final notifier = ref.read(
                                settingsProvider.notifier,
                              );
                              notifier.setStorageMode('app');
                              notifier.setDownloadTreeUri('');
                              notifier.setDownloadDirectory('');
                              Navigator.of(dialogContext).pop();
                            },
                      child: Text(context.l10n.storageModeAppFolder),
                    ),
                    FilledButton(
                      onPressed: isPickingFolder
                          ? null
                          : () async {
                              setDialogState(() => isPickingFolder = true);
                              try {
                                final result =
                                    await PlatformBridge.pickSafTree();
                                if (result == null) return;
                                final treeUri =
                                    result['tree_uri'] as String? ?? '';
                                final displayName =
                                    result['display_name'] as String? ?? '';
                                if (treeUri.isEmpty) return;

                                final notifier = ref.read(
                                  settingsProvider.notifier,
                                );
                                notifier.setStorageMode('saf');
                                notifier.setDownloadTreeUri(
                                  treeUri,
                                  displayName: displayName.isNotEmpty
                                      ? displayName
                                      : treeUri,
                                );
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                              } catch (e) {
                                _log.w(
                                  'Failed to repair SAF access from startup: $e',
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        context.l10n.snackbarCannotOpenFile(
                                          context.friendlyError(e),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                if (dialogContext.mounted) {
                                  setDialogState(() => isPickingFolder = false);
                                }
                              }
                            },
                      child: isPickingFolder
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(context.l10n.downloadFolderReselect),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      _safRepairDialogVisible = false;
    }
  }

  void _setupShareListener() {
    final pendingUrl = ShareIntentService().consumePendingUrl();
    if (pendingUrl != null) {
      _log.d('Processing pending shared URL: $pendingUrl');
      _handleSharedUrl(pendingUrl);
    }

    _shareSubscription = ShareIntentService().sharedUrlStream.listen(
      (url) {
        _log.d('Received shared URL from stream: $url');
        _handleSharedUrl(url);
      },
      onError: (Object error) {
        _log.e('Share stream error: $error');
      },
      cancelOnError: false,
    );
  }

  Future<void> _handleSharedUrl(String url) async {
    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
    _homeTabNavigatorKey.currentState?.popUntil((route) => route.isFirst);

    if (_currentIndex != 0) {
      _onNavTap(0);
    }
    ref.read(settingsProvider.notifier).setHasSearchedBefore();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.loadingSharedLink)));
    }
    await ref.read(trackProvider.notifier).fetchFromUrl(url);
    final trackState = ref.read(trackProvider);
    if (trackState.error != null && mounted) {
      final l10n = context.l10n;
      final errorMsg = trackState.error!;
      final isRateLimit =
          errorMsg.contains('429') ||
          errorMsg.toLowerCase().contains('rate limit') ||
          errorMsg.toLowerCase().contains('too many requests');
      final displayMessage = errorMsg == 'url_not_recognized'
          ? l10n.errorUrlNotRecognizedMessage
          : isRateLimit
          ? l10n.errorRateLimitedMessage
          : l10n.errorUrlFetchFailed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(displayMessage),
          // Retrying an unrecognized URL is deterministic; skip the action.
          action: errorMsg == 'url_not_recognized'
              ? null
              : SnackBarAction(
                  label: l10n.dialogRetry,
                  onPressed: () => _handleSharedUrl(url),
                ),
        ),
      );
    }
  }

  Future<bool> _checkForUpdates() async {
    if (_hasCheckedUpdate) return false;
    _hasCheckedUpdate = true;

    final settings = ref.read(settingsProvider);

    // The check runs even when the user disabled update prompts: versions
    // that fall forceUpdateThreshold stable releases behind must update, and
    // that enforcement cannot be opted out of.
    final updateInfo = await UpdateChecker.checkForUpdate(
      channel: settings.updateChannel,
    );
    if (updateInfo == null || !mounted) return false;

    final forced =
        updateInfo.releasesBehind >= UpdateChecker.forceUpdateThreshold;
    if (!forced && !settings.checkForUpdates) return false;

    showUpdateDialog(
      context,
      updateInfo: updateInfo,
      forced: forced,
      onDisableUpdates: () {
        ref.read(settingsProvider.notifier).setCheckForUpdates(false);
      },
    );
    return true;
  }

  Future<void> _checkAppAnnouncement() async {
    if (_hasCheckedAppAnnouncement) return;
    _hasCheckedAppAnnouncement = true;

    final locale = Localizations.localeOf(context).toLanguageTag();
    final remoteConfigService = AppRemoteConfigService();
    final announcement = await remoteConfigService.fetchActiveAnnouncement(
      locale: locale,
    );
    if (announcement == null || !mounted) return;

    showAppAnnouncementDialog(
      context,
      announcement: announcement,
      onDismiss: () {
        remoteConfigService.markAnnouncementDismissed(announcement.id);
      },
    );
  }

  static const _safMigrationShownKey = 'saf_migration_prompt_shown';

  Future<void> _checkSafMigration() async {
    if (!Platform.isAndroid) return;

    final settings = ref.read(settingsProvider);
    if (settings.storageMode == 'saf') return;
    if (settings.downloadDirectory.isEmpty) return;

    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    if (androidInfo.version.sdkInt < 29) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_safMigrationShownKey) == true) return;
    await prefs.setBool(_safMigrationShownKey, true);

    if (!mounted) return;

    final colorScheme = Theme.of(context).colorScheme;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.folder_special_outlined,
          size: 32,
          color: colorScheme.primary,
        ),
        title: Text(context.l10n.safMigrationTitle),
        content: ConstrainedBox(
          // Keeps the text column readable on tablets/landscape.
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.safMigrationMessage1),
              const SizedBox(height: 12),
              Text(context.l10n.safMigrationMessage2),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.updateLater),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await PlatformBridge.pickSafTree();
              if (result != null) {
                final treeUri = result['tree_uri'] as String? ?? '';
                final displayName = result['display_name'] as String? ?? '';
                if (treeUri.isNotEmpty) {
                  ref
                      .read(settingsProvider.notifier)
                      .setDownloadTreeUri(
                        treeUri,
                        displayName: displayName.isNotEmpty
                            ? displayName
                            : treeUri,
                      );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.safMigrationSuccess)),
                    );
                  }
                }
              }
            },
            child: Text(context.l10n.setupSelectFolder),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ShellNavigationService.unregisterTabSelectionHandler(this);
    _shareSubscription?.cancel();
    _pageController.dispose();
    _tabJumpTransitionController.dispose();
    super.dispose();
  }

  void _resetHomeToMain() {
    ref.read(previewPlayerProvider.notifier).stop();
    final showStore = ref.read(
      settingsProvider.select((s) => s.showExtensionStore),
    );
    final homeNavigator = _navigatorForTab(0, showStore);
    homeNavigator?.popUntil((route) => route.isFirst);
    // Unfocus BEFORE clear so _onTrackStateChanged can properly
    // clear _urlController (it checks !_searchFocusNode.hasFocus)
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(trackProvider.notifier).clear();
  }

  void _onShellTabRequested(ShellTab tab) {
    final showStore = ref.read(
      settingsProvider.select((s) => s.showExtensionStore),
    );
    final index = switch (tab) {
      ShellTab.home => 0,
      ShellTab.library => 1,
      ShellTab.repository => showStore ? 2 : null,
      ShellTab.settings => showStore ? 3 : 2,
    };
    if (index != null) _onNavTap(index);
  }

  void _onNavTap(int index) {
    if (index == 0 && _currentIndex == 0) {
      _resetHomeToMain();
      return;
    }

    if (_currentIndex != index) {
      final previousIndex = _currentIndex;
      final isNonAdjacentJump = (previousIndex - index).abs() > 1;
      HapticFeedback.selectionClick();
      // Stop any preview snippet when leaving the current tab. (_onPageChanged
      // cannot do this because _currentIndex is already updated below.)
      ref.read(previewPlayerProvider.notifier).stop();
      setState(() => _currentIndex = index);
      final showStore = ref.read(
        settingsProvider.select((s) => s.showExtensionStore),
      );
      ShellNavigationService.syncState(
        currentTabIndex: _currentIndex,
        showRepoTab: showStore,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      // Jump directly when skipping intermediate tabs to avoid
      // sliding through them. For those jumps, keep a short fade-in
      // so the transition still feels intentional.
      if (isNonAdjacentJump) {
        _pageController.jumpToPage(index);
        _tabJumpTransitionController.forward(from: 0);
      } else {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _onPageChanged(int index) {
    if (_currentIndex != index) {
      ref.read(previewPlayerProvider.notifier).stop();
      setState(() => _currentIndex = index);
      final showStore = ref.read(
        settingsProvider.select((s) => s.showExtensionStore),
      );
      ShellNavigationService.syncState(
        currentTabIndex: _currentIndex,
        showRepoTab: showStore,
      );
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  Future<void> _handleBackPress() async {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final handledByRootNavigator = await rootNavigator.maybePop();
    if (handledByRootNavigator) {
      _log.i('Back: step 1 - root navigator handled back');
      _lastBackPress = null;
      return;
    }

    final showStore = ref.read(
      settingsProvider.select((s) => s.showExtensionStore),
    );
    final currentNavigator = _navigatorForTab(_currentIndex, showStore);
    final handledByCurrentNavigator =
        await currentNavigator?.maybePop() ?? false;
    if (handledByCurrentNavigator) {
      _log.i('Back: step 2 - tab navigator handled back (tab=$_currentIndex)');
      _lastBackPress = null;
      return;
    }

    if (!mounted) return;

    final trackState = ref.read(trackProvider);

    final isKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    _log.d(
      'Back: state check - tab=$_currentIndex, '
      'isShowingRecentAccess=${trackState.isShowingRecentAccess}, '
      'hasSearchText=${trackState.hasSearchText}, '
      'hasContent=${trackState.hasContent}, '
      'isLoading=${trackState.isLoading}, '
      'isKeyboardVisible=$isKeyboardVisible',
    );

    if (_currentIndex == 0 &&
        trackState.isShowingRecentAccess &&
        !trackState.isLoading &&
        (trackState.hasSearchText || trackState.hasContent)) {
      _log.i(
        'Back: step 3a - dismiss recent access + clear search/content '
        '(hasSearchText=${trackState.hasSearchText}, hasContent=${trackState.hasContent})',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      ref.read(previewPlayerProvider.notifier).stop();
      ref.read(trackProvider.notifier).clear();
      _lastBackPress = null;
      return;
    }

    if (_currentIndex == 0 && trackState.isShowingRecentAccess) {
      _log.i('Back: step 3b - dismiss recent access only');
      ref.read(trackProvider.notifier).setShowingRecentAccess(false);
      FocusManager.instance.primaryFocus?.unfocus();
      _lastBackPress = null;
      return;
    }

    if (_currentIndex == 0 &&
        !trackState.isLoading &&
        (trackState.hasSearchText || trackState.hasContent)) {
      _log.i(
        'Back: step 4 - clear search/content '
        '(hasSearchText=${trackState.hasSearchText}, hasContent=${trackState.hasContent})',
      );
      // Unfocus BEFORE clear so _onTrackStateChanged can properly
      // clear _urlController (it checks !_searchFocusNode.hasFocus)
      FocusManager.instance.primaryFocus?.unfocus();
      ref.read(previewPlayerProvider.notifier).stop();
      ref.read(trackProvider.notifier).clear();
      _lastBackPress = null;
      return;
    }

    if (_currentIndex == 0 && isKeyboardVisible) {
      _log.i('Back: step 5 - dismiss keyboard');
      FocusManager.instance.primaryFocus?.unfocus();
      _lastBackPress = null;
      return;
    }

    if (_currentIndex != 0) {
      _log.i('Back: step 6 - switch to home tab from tab=$_currentIndex');
      _onNavTap(0);
      _lastBackPress = null;
      return;
    }

    if (trackState.isLoading) {
      _log.i('Back: blocked - loading in progress');
      return;
    }

    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      _log.i('Back: step 8 - double-tap exit');
      unawaited(PlatformBridge.exitApp());
    } else {
      _log.i('Back: step 7 - first tap, showing exit snackbar');
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.pressBackAgainToExit),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  NavigatorState? _navigatorForTab(int index, bool showStore) {
    if (index == 0) return _homeTabNavigatorKey.currentState;
    if (index == 1) return _libraryTabNavigatorKey.currentState;
    if (showStore && index == 2) return _repoTabNavigatorKey.currentState;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider.select((s) => s.playbackNormalization), (
      _,
      enabled,
    ) {
      setPlaybackNormalizationEnabled(enabled);
    });
    final queueState = ref.watch(
      downloadQueueProvider.select((s) => s.queuedCount),
    );
    final showStore = ref.watch(
      settingsProvider.select((s) => s.showExtensionStore),
    );
    final heroAnimationsEnabled = ref.watch(
      settingsProvider.select((s) => s.heroAnimationsEnabled),
    );
    ShellNavigationService.syncState(
      currentTabIndex: _currentIndex,
      showRepoTab: showStore,
    );
    final repoUpdatesCount = ref.watch(
      repoProvider.select((s) => s.updatesAvailableCount),
    );

    final tabs = <Widget>[
      _TabNavigator(
        key: const ValueKey('tab-home'),
        navigatorKey: _homeTabNavigatorKey,
        observers: [_homePreviewStopObserver],
        heroAnimationsEnabled: heroAnimationsEnabled,
        child: const HomeTab(),
      ),
      _TabNavigator(
        key: const ValueKey('tab-library'),
        navigatorKey: _libraryTabNavigatorKey,
        observers: [_libraryPreviewStopObserver],
        heroAnimationsEnabled: heroAnimationsEnabled,
        child: _LibraryTabRoot(parentPageController: _pageController),
      ),
      if (showStore)
        _TabNavigator(
          key: const ValueKey('tab-repo'),
          navigatorKey: _repoTabNavigatorKey,
          observers: [_repoPreviewStopObserver],
          heroAnimationsEnabled: heroAnimationsEnabled,
          child: const RepoTab(),
        ),
      const SettingsTab(),
    ];

    final l10n = context.l10n;
    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: BouncingIcon(child: const Icon(Icons.home)),
        label: l10n.navHome,
      ),
      NavigationDestination(
        icon: AnimatedBadge(
          count: queueState,
          child: Badge(
            isLabelVisible: queueState > 0,
            label: Text('$queueState'),
            child: const Icon(Icons.library_music_outlined),
          ),
        ),
        selectedIcon: SlidingIcon(
          child: AnimatedBadge(
            count: queueState,
            child: Badge(
              isLabelVisible: queueState > 0,
              label: Text('$queueState'),
              child: const Icon(Icons.library_music),
            ),
          ),
        ),
        label: l10n.navLibrary,
      ),
      if (showStore)
        NavigationDestination(
          icon: AnimatedBadge(
            count: repoUpdatesCount,
            child: Badge(
              isLabelVisible: repoUpdatesCount > 0,
              label: Text('$repoUpdatesCount'),
              child: const Icon(Icons.extension_outlined),
            ),
          ),
          selectedIcon: BouncingIcon(
            child: AnimatedBadge(
              count: repoUpdatesCount,
              child: Badge(
                isLabelVisible: repoUpdatesCount > 0,
                label: Text('$repoUpdatesCount'),
                child: const Icon(Icons.extension),
              ),
            ),
          ),
          label: l10n.navStore,
        ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: SpinIcon(child: const Icon(Icons.settings)),
        label: l10n.navSettings,
      ),
    ];

    final maxIndex = tabs.length - 1;
    if (_currentIndex > maxIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _currentIndex = maxIndex);
          _pageController.jumpToPage(maxIndex);
        }
      });
    }

    // Material breakpoint: rail navigation on tablet/landscape widths, the
    // bottom NavigationBar on phones.
    final useNavigationRail = MediaQuery.sizeOf(context).width >= 600;

    final pageView = KeyedSubtree(
      key: _pageViewKey,
      child: AnimatedBuilder(
        animation: _tabJumpTransitionController,
        child: PageView.builder(
          controller: _pageController,
          itemCount: tabs.length,
          onPageChanged: _onPageChanged,
          physics: const NeverScrollableScrollPhysics(),
          // TickerMode mutes animations and lets visibility-aware widgets
          // (e.g. MotionHeaderBanner) pause when their tab is hidden —
          // kept-alive pages otherwise keep running offscreen.
          itemBuilder: (context, index) => _KeepAliveTabPage(
            key: ValueKey('page-$index'),
            child: TickerMode(
              enabled: index == _currentIndex,
              child: tabs[index],
            ),
          ),
        ),
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(
            _tabJumpTransitionController.value,
          );
          return Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.985 + (0.015 * t), child: child),
          );
        },
      ),
    );

    return SelectionOverlayHost(
      child: BackButtonListener(
        onBackButtonPressed: () async {
          await _handleBackPress();
          return true;
        },
        child: Scaffold(
          extendBody: true,
          // The page view keeps one element across the rail<->bar structure
          // swap via _pageViewKey; without it a rotation past the 600dp
          // breakpoint remounts the PageView and snaps back to the first tab.
          body: useNavigationRail
              ? Row(
                  children: [
                    SafeArea(
                      right: false,
                      bottom: false,
                      // The rail needs ~300dp of height for four labeled
                      // destinations; on short viewports (landscape phone with
                      // the mini player showing) it must scroll, not overflow.
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: IntrinsicHeight(
                                  child: NavigationRail(
                                    selectedIndex: _currentIndex.clamp(
                                      0,
                                      maxIndex,
                                    ),
                                    onDestinationSelected: _onNavTap,
                                    labelType: NavigationRailLabelType.all,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainer,
                                    destinations: [
                                      for (final destination in destinations)
                                        NavigationRailDestination(
                                          icon: destination.icon,
                                          selectedIcon:
                                              destination.selectedIcon,
                                          label: Text(destination.label),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: pageView),
                  ],
                )
              : pageView,
          bottomNavigationBar: Builder(
            builder: (context) {
              final bottomBar = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MiniPlayer(),
                  if (!useNavigationRail)
                    DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      child: NavigationBar(
                        selectedIndex: _currentIndex.clamp(0, maxIndex),
                        onDestinationSelected: _onNavTap,
                        animationDuration: const Duration(milliseconds: 500),
                        elevation: 0,
                        height: 64,
                        backgroundColor: settingsGroupColor(
                          context,
                        ).withValues(alpha: 0.72),
                        destinations: destinations,
                      ),
                    ),
                ],
              );
              // The backdrop blur re-filters everything scrolling underneath on
              // every frame; low-end devices get an opaque base instead unless
              // the user forces blur on in appearance settings.
              if (!ref.watch(backdropBlurEnabledProvider)) {
                return ColoredBox(
                  color: settingsGroupColor(context),
                  child: bottomBar,
                );
              }
              return ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  blendMode: BlendMode.src,
                  child: bottomBar,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TabNavigator extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final List<NavigatorObserver> observers;
  final bool heroAnimationsEnabled;

  const _TabNavigator({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.observers = const [],
    required this.heroAnimationsEnabled,
  });

  @override
  State<_TabNavigator> createState() => _TabNavigatorState();
}

class _TabNavigatorState extends State<_TabNavigator> {
  // Nested navigators get no HeroController from MaterialApp; without one,
  // Hero widgets on routes pushed inside a tab never fly.
  final HeroController _heroController =
      MaterialApp.createMaterialHeroController();

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: widget.navigatorKey,
      observers: [
        if (widget.heroAnimationsEnabled) _heroController,
        ...widget.observers,
      ],
      onGenerateInitialRoutes: (_, _) => [
        MaterialPageRoute<void>(builder: (_) => widget.child),
      ],
    );
  }
}

class _PreviewStopNavigatorObserver extends NavigatorObserver {
  _PreviewStopNavigatorObserver(this._onNavigate);

  final VoidCallback _onNavigate;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute != null) {
      _onNavigate();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _onNavigate();
  }
}

class _LibraryTabRoot extends ConsumerWidget {
  final PageController parentPageController;

  const _LibraryTabRoot({required this.parentPageController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showStore = ref.watch(
      settingsProvider.select((s) => s.showExtensionStore),
    );
    return QueueTab(
      parentPageController: parentPageController,
      parentPageIndex: 1,
      nextPageIndex: showStore ? 2 : 3,
    );
  }
}

class _KeepAliveTabPage extends StatefulWidget {
  final Widget child;

  const _KeepAliveTabPage({super.key, required this.child});

  @override
  State<_KeepAliveTabPage> createState() => _KeepAliveTabPageState();
}

class _KeepAliveTabPageState extends State<_KeepAliveTabPage>
    with AutomaticKeepAliveClientMixin<_KeepAliveTabPage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class BouncingIcon extends StatefulWidget {
  final Widget child;
  const BouncingIcon({super.key, required this.child});

  @override
  State<BouncingIcon> createState() => _BouncingIconState();
}

class _BouncingIconState extends State<BouncingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.1,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scaleAnimation, child: widget.child);
  }
}

class SlidingIcon extends StatefulWidget {
  final Widget child;
  const SlidingIcon({super.key, required this.child});

  @override
  State<SlidingIcon> createState() => _SlidingIconState();
}

class _SlidingIconState extends State<SlidingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _offsetAnimation, child: widget.child),
    );
  }
}

class SpinIcon extends StatefulWidget {
  final Widget child;
  const SpinIcon({super.key, required this.child});

  @override
  State<SpinIcon> createState() => _SpinIconState();
}

class _SpinIconState extends State<SpinIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(turns: _rotationAnimation, child: widget.child);
  }
}
