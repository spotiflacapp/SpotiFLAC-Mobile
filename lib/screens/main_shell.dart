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
import 'package:spotiflac_android/providers/store_provider.dart';
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
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('MainShell');

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late final PageController _pageController;
  late final AnimationController _tabJumpTransitionController;
  bool _hasCheckedUpdate = false;
  bool _hasCheckedAppAnnouncement = false;
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
  }

  @override
  void initState() {
    super.initState();
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
    ShellNavigationService.syncState(
      currentTabIndex: _currentIndex,
      showRepoTab: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _setupShareListener();
      _checkSafMigration();
      final updateDialogShown = await _checkForUpdates();
      if (!updateDialogShown) {
        await _checkAppAnnouncement();
      }
    });
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(displayMessage)));
    }
  }

  Future<bool> _checkForUpdates() async {
    if (_hasCheckedUpdate) return false;
    _hasCheckedUpdate = true;

    final settings = ref.read(settingsProvider);
    if (!settings.checkForUpdates) return false;

    final updateInfo = await UpdateChecker.checkForUpdate(
      channel: settings.updateChannel,
    );
    if (updateInfo != null && mounted) {
      showUpdateDialog(
        context,
        updateInfo: updateInfo,
        onDisableUpdates: () {
          ref.read(settingsProvider.notifier).setCheckForUpdates(false);
        },
      );
      return true;
    }

    return false;
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.safMigrationMessage1),
            const SizedBox(height: 12),
            Text(context.l10n.safMigrationMessage2),
          ],
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

    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

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
    final queueState = ref.watch(
      downloadQueueProvider.select((s) => s.queuedCount),
    );
    final showStore = ref.watch(
      settingsProvider.select((s) => s.showExtensionStore),
    );
    ShellNavigationService.syncState(
      currentTabIndex: _currentIndex,
      showRepoTab: showStore,
    );
    final repoUpdatesCount = ref.watch(
      storeProvider.select((s) => s.updatesAvailableCount),
    );

    final tabs = <Widget>[
      _TabNavigator(
        key: const ValueKey('tab-home'),
        navigatorKey: _homeTabNavigatorKey,
        observers: [_homePreviewStopObserver],
        child: const HomeTab(),
      ),
      _TabNavigator(
        key: const ValueKey('tab-library'),
        navigatorKey: _libraryTabNavigatorKey,
        observers: [_libraryPreviewStopObserver],
        child: _LibraryTabRoot(parentPageController: _pageController),
      ),
      if (showStore)
        _TabNavigator(
          key: const ValueKey('tab-repo'),
          navigatorKey: _repoTabNavigatorKey,
          observers: [_repoPreviewStopObserver],
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

    return BackButtonListener(
      onBackButtonPressed: () async {
        await _handleBackPress();
        return true;
      },
      child: Scaffold(
        extendBody: true,
        body: AnimatedBuilder(
          animation: _tabJumpTransitionController,
          child: PageView.builder(
            controller: _pageController,
            itemCount: tabs.length,
            onPageChanged: _onPageChanged,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) => _KeepAliveTabPage(
              key: ValueKey('page-$index'),
              child: tabs[index],
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
        bottomNavigationBar: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MiniPlayer(),
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
            ),
          ),
        ),
      ),
    );
  }
}

class _TabNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final List<NavigatorObserver> observers;

  const _TabNavigator({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.observers = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      observers: observers,
      onGenerateInitialRoutes: (_, _) => [
        MaterialPageRoute<void>(builder: (_) => child),
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

class SwingIcon extends StatefulWidget {
  final Widget child;
  const SwingIcon({super.key, required this.child});

  @override
  State<SwingIcon> createState() => _SwingIconState();
}

class _SwingIconState extends State<SwingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _rotationAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.2), weight: 20),
      TweenSequenceItem(tween: Tween(begin: -0.2, end: 0.15), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.15, end: -0.1), weight: 20),
      TweenSequenceItem(tween: Tween(begin: -0.1, end: 0.05), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.05, end: 0.0), weight: 20),
    ]).animate(_controller);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rotationAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotationAnimation.value,
          alignment: Alignment.topCenter,
          child: child,
        );
      },
      child: widget.child,
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
