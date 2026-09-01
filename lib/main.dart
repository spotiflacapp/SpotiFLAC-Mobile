import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/app.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/download_schedule_settings_provider.dart';
import 'package:spotiflac_android/providers/engine_settings_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/playback_statistics_provider.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/streaming_engine_provider.dart';
import 'package:spotiflac_android/providers/theme_provider.dart';
import 'package:spotiflac_android/services/notification_service.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/services/share_intent_service.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';
import 'package:spotiflac_android/services/app_state_database.dart';
import 'package:spotiflac_android/utils/local_library_scan_prefs.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('Main');

void main() {
  // Catch uncaught Dart errors so a failing async path is logged, not fatal.
  // Native (Go) crashes still can't be caught here.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        previousOnError?.call(details);
        _log.e('Uncaught Flutter error: ${details.exceptionAsString()}');
      };
      WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
        _log.e('Uncaught platform error: $error', error, stack);
        return true;
      };

      final prefs = await SharedPreferences.getInstance();
      await _prepareAndroidInstallationState(prefs);
      final bootstrapSettings = loadBootstrapSettings(prefs);
      final bootstrapTheme = loadBootstrapThemeSettings(prefs);
      final bootstrapEngineSettings = engineSettingsFromPrefs(prefs);
      final initialSafAccessLost = await _detectInitialSafAccessLoss(
        bootstrapSettings,
      );
      final runtimeProfile = await _resolveRuntimeProfile(prefs);
      _configureImageCache(runtimeProfile);

      runApp(
        ProviderScope(
          overrides: [
            lowEndDeviceProvider.overrideWithValue(
              runtimeProfile.disableOverscrollEffects,
            ),
            deviceSupportsBackdropBlurProvider.overrideWithValue(
              runtimeProfile.enableBackdropBlur,
            ),
            initialSettingsProvider.overrideWithValue(bootstrapSettings),
            initialSafAccessLostProvider.overrideWithValue(
              initialSafAccessLost,
            ),
            initialThemeSettingsProvider.overrideWithValue(bootstrapTheme),
            initialEngineSettingsProvider.overrideWithValue(
              bootstrapEngineSettings,
            ),
          ],
          child: _EagerInitialization(
            child: SpotiFLACApp(
              disableOverscrollEffects: runtimeProfile.disableOverscrollEffects,
            ),
          ),
        ),
      );
    },
    (error, stack) {
      _log.e('Uncaught zone error: $error', error, stack);
    },
  );
}

const _runtimeProfileTierKey = 'runtime_profile_tier_v1';

Future<void> _prepareAndroidInstallationState(SharedPreferences prefs) async {
  if (!Platform.isAndroid) return;

  try {
    final hasPersistedSettings = hasPersistedAppSettings(prefs);
    final installState = await PlatformBridge.ensureInstallMarker();
    final shouldReset = shouldResetRestoredInstallation(
      hasPersistedSettings: hasPersistedSettings,
      installState: installState,
    );
    if (!shouldReset) return;

    _log.w(
      'Android restored state into a fresh installation; resetting '
      'installation-bound settings',
    );
    await resetRestoredInstallationSettings(prefs);
    await prefs.remove(_runtimeProfileTierKey);
    await prefs.remove(localLibraryLastScannedAtKey);
    await AppStateDatabase.instance.clearPendingQueueAfterInstallationRestore();
  } catch (e, stack) {
    _log.w('Failed to inspect restored installation state: $e', e, stack);
  }
}

Future<bool> _detectInitialSafAccessLoss(AppSettings settings) async {
  if (!Platform.isAndroid ||
      settings.isFirstLaunch ||
      settings.storageMode != 'saf' ||
      settings.downloadTreeUri.isEmpty) {
    return false;
  }

  try {
    return !await PlatformBridge.validateSafTreeAccess(
      settings.downloadTreeUri,
    );
  } catch (e, stack) {
    _log.w('Failed to validate SAF access during startup: $e', e, stack);
    return false;
  }
}

Future<_RuntimeProfile> _resolveRuntimeProfile(SharedPreferences prefs) async {
  final cachedTier = prefs.getString(_runtimeProfileTierKey);
  if (cachedTier != null) {
    final cached = _RuntimeProfile.fromTier(cachedTier);
    if (cached != null) return cached;
  }

  const defaults = _RuntimeProfile.standard();

  if (!Platform.isAndroid) {
    await prefs.setString(_runtimeProfileTierKey, defaults.tier);
    return defaults;
  }

  try {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final isArm32Only = androidInfo.supported64BitAbis.isEmpty;
    final isLowRamDevice =
        androidInfo.isLowRamDevice || androidInfo.physicalRamSize <= 2500;

    final profile = (isArm32Only || isLowRamDevice)
        ? const _RuntimeProfile.low()
        : androidInfo.physicalRamSize >= 6000
            ? const _RuntimeProfile.high()
            : defaults;
    await prefs.setString(_runtimeProfileTierKey, profile.tier);
    return profile;
  } catch (e, stack) {
    _log.w('Failed to resolve runtime profile: $e', e, stack);
    return defaults;
  }
}

void _configureImageCache(_RuntimeProfile runtimeProfile) {
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSize = runtimeProfile.imageCacheMaximumSize;
  imageCache.maximumSizeBytes = runtimeProfile.imageCacheMaximumSizeBytes;
}

class _RuntimeProfile {
  final String tier;
  final int imageCacheMaximumSize;
  final int imageCacheMaximumSizeBytes;
  final bool disableOverscrollEffects;
  final bool enableBackdropBlur;

  const _RuntimeProfile._({
    required this.tier,
    required this.imageCacheMaximumSize,
    required this.imageCacheMaximumSizeBytes,
    required this.disableOverscrollEffects,
    required this.enableBackdropBlur,
  });

  const _RuntimeProfile.low()
      : this._(
          tier: 'low',
          imageCacheMaximumSize: 120,
          imageCacheMaximumSizeBytes: 24 << 20,
          disableOverscrollEffects: true,
          enableBackdropBlur: false,
        );

  const _RuntimeProfile.standard()
      : this._(
          tier: 'standard',
          imageCacheMaximumSize: 240,
          imageCacheMaximumSizeBytes: 60 << 20,
          disableOverscrollEffects: false,
          enableBackdropBlur: false,
        );

  const _RuntimeProfile.high()
      : this._(
          tier: 'high',
          imageCacheMaximumSize: 320,
          imageCacheMaximumSizeBytes: 80 << 20,
          disableOverscrollEffects: false,
          enableBackdropBlur: true,
        );

  static _RuntimeProfile? fromTier(String tier) => switch (tier) {
        'low' => const _RuntimeProfile.low(),
        'standard' => const _RuntimeProfile.standard(),
        'high' => const _RuntimeProfile.high(),
        _ => null,
      };
}

class _EagerInitialization extends ConsumerStatefulWidget {
  const _EagerInitialization({required this.child});
  final Widget child;

  @override
  ConsumerState<_EagerInitialization> createState() =>
      _EagerInitializationState();
}

class _EagerInitializationState extends ConsumerState<_EagerInitialization>
    with WidgetsBindingObserver {
  ProviderSubscription<bool>? _localLibraryEnabledSub;
  Timer? _downloadHistoryWarmupTimer;
  Timer? _localLibraryWarmupTimer;
  bool _localLibraryWarmupScheduled = false;
  bool _autoScanTriggeredOnLaunch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializeAppServices();
      _initializeExtensions();
      _initializeDeferredProviders();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _localLibraryEnabledSub?.close();
    _downloadHistoryWarmupTimer?.cancel();
    _localLibraryWarmupTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeAutoScanLocalLibrary();
      if (ref.exists(localLibraryProvider)) {
        unawaited(
          ref
              .read(localLibraryProvider.notifier)
              .refreshSourceAvailability(scanReconnected: true)
              .catchError((Object e, StackTrace stack) {
            _log.w('Failed to refresh library availability: $e', e, stack);
          }),
        );
      }
      if (ref.exists(downloadQueueProvider)) {
        ref
            .read(downloadQueueProvider.notifier)
            .resumePendingDownloadsOnForeground();
      }
    } else if (state == AppLifecycleState.paused) {
      if (ref.exists(downloadQueueProvider)) {
        unawaited(
          ref.read(downloadQueueProvider.notifier).flushQueuePersistence()
              .catchError((Object e, StackTrace stack) {
            _log.w('Failed to flush queue persistence: $e', e, stack);
          }),
        );
      }
      unawaited(
        PlatformBridge.releaseNativeMemory()
            .catchError((Object e, StackTrace stack) {
          _log.w('Failed to release native memory: $e', e, stack);
        }),
      );
    }
  }

  @override
  void didHaveMemoryPressure() {
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();
    if (CoverCacheManager.isInitialized) {
      CoverCacheManager.instance.store.emptyMemoryCache();
    }
    unawaited(
      PlatformBridge.releaseNativeMemory(underPressure: true)
          .catchError((Object e, StackTrace stack) {
        _log.w('Failed to release memory under pressure: $e', e, stack);
      }),
    );
  }

  void _initializeDeferredProviders() {
    _downloadHistoryWarmupTimer = _scheduleProviderWarmup(
      const Duration(milliseconds: 400),
      () => ref.read(downloadHistoryProvider),
    );
    _maybeScheduleLocalLibraryWarmup(
      ref.read(
        settingsProvider.select((settings) => settings.localLibraryEnabled),
      ),
    );

    _localLibraryEnabledSub = ref.listenManual<bool>(
      settingsProvider.select((settings) => settings.localLibraryEnabled),
      (previous, next) {
        if (next == true) {
          _maybeScheduleLocalLibraryWarmup(true);
        }
      },
    );

    unawaited(
      ref.read(engineSavepointProvider.notifier).load()
          .catchError((Object e, StackTrace stack) {
        _log.w('Failed to load engine savepoint: $e', e, stack);
      }),
    );
    unawaited(
      ref.read(streamingEngineControllerProvider).ensureFailureHook()
          .catchError((Object e, StackTrace stack) {
        _log.w('Failed to ensure failure hook: $e', e, stack);
      }),
    );

    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) =>
              ref.read(downloadScheduleSettingsProvider.notifier).attach(prefs))
          .catchError((Object e, StackTrace stack) {
        _log.w('Failed to attach download schedule settings: $e', e, stack);
      }),
    );

    final statsNotifier = ref.read(playbackStatisticsProvider.notifier);
    unawaited(
      statsNotifier.load().catchError((Object e, StackTrace stack) {
        _log.w('Failed to load playback statistics: $e', e, stack);
      }),
    );
    installPlaybackStatisticsRecording(ref);
  }

  Timer _scheduleProviderWarmup(Duration delay, VoidCallback action) {
    return Timer(delay, () {
      if (!mounted) return;
      try {
        action();
      } catch (e, stack) {
        _log.w('Failed during provider warmup: $e', e, stack);
      }
    });
  }

  void _maybeScheduleLocalLibraryWarmup(bool enabled) {
    if (!enabled || _localLibraryWarmupScheduled) return;
    _localLibraryWarmupScheduled = true;
    _localLibraryWarmupTimer = _scheduleProviderWarmup(
      const Duration(milliseconds: 1600),
      () {
        ref.read(localLibraryProvider);
        if (!_autoScanTriggeredOnLaunch) {
          _autoScanTriggeredOnLaunch = true;
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _maybeAutoScanLocalLibrary();
          });
        }
      },
    );
  }

  Future<void> _maybeAutoScanLocalLibrary() async {
    if (!mounted) return;

    final settings = ref.read(settingsProvider);
    if (!settings.localLibraryEnabled) return;
    if (settings.localLibraryAutoScan == 'off') return;

    final libraryState = ref.read(localLibraryProvider);
    if (libraryState.isScanning) return;

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final lastScanned = readLocalLibraryLastScannedAt(prefs);

    if (lastScanned != null) {
      final elapsed = now.difference(lastScanned);

      switch (settings.localLibraryAutoScan) {
        case 'on_open':
          if (elapsed.inMinutes < 10) return;
          break;
        case 'daily':
          if (elapsed.inHours < 24) return;
          break;
        case 'weekly':
          if (elapsed.inDays < 7) return;
          break;
        default:
          return;
      }
    }

    await ref.read(localLibraryProvider.notifier).scanAllSources();
  }

  Future<void> _initializeAppServices() async {
    try {
      await CoverCacheManager.initialize();
      CoverCacheManager.scheduleMaintenance();
      await Future.wait(
        [
          NotificationService().initialize(),
          ShareIntentService().initialize(),
        ],
        eagerError: true,
      );
    } catch (e, stack) {
      _log.e('Failed to initialize app services: $e', e, stack);
    }
  }

  Future<void> _initializeExtensions() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final extensionsDir = '${appDir.path}/extensions';
      final dataDir = '${appDir.path}/extension_data';

      await Directory(extensionsDir).create(recursive: true);
      await Directory(dataDir).create(recursive: true);

      await ref
          .read(extensionProvider.notifier)
          .initialize(extensionsDir, dataDir);
    } catch (e, stack) {
      _log.e('Failed to initialize extensions: $e', e, stack);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
