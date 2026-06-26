import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';

final _log = AppLogger('ExtensionProvider');

const _metadataProviderPriorityKey = 'metadata_provider_priority';
const _providerPriorityKey = 'provider_priority';
const _spotifyWebExtensionId = 'spotify-web';
const _storeRegistryUrlPrefKey = 'store_registry_url';

/// Result of restoring extensions from a backup.
class ExtensionRestoreResult {
  final int installed;
  final int alreadyPresent;
  final int failed;
  final List<String> failedIds;

  const ExtensionRestoreResult({
    this.installed = 0,
    this.alreadyPresent = 0,
    this.failed = 0,
    this.failedIds = const [],
  });
}

bool _stringListEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<String>? _tryDecodeStringListPreference(String rawJson, String key) {
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is! List) {
      throw const FormatException('expected a JSON list');
    }

    final values = <String>[];
    for (final item in decoded) {
      if (item is! String) {
        throw const FormatException('expected string entries');
      }
      final trimmed = item.trim();
      if (trimmed.isNotEmpty) {
        values.add(trimmed);
      }
    }
    return values;
  } catch (e) {
    _log.w('Ignoring invalid $key preference: $e');
    return null;
  }
}

class Extension {
  final String id;
  final String name;
  final String displayName;
  final String version;
  final String description;
  final bool enabled;
  final String status;
  final String? errorMessage;
  final String? iconPath;
  final List<String> permissions;
  final List<ExtensionSetting> settings;
  final List<QualityOption> qualityOptions;
  final bool hasMetadataProvider;
  final bool hasDownloadProvider;
  final bool hasLyricsProvider;
  final bool skipMetadataEnrichment;
  final bool skipLyrics;
  final bool stopProviderFallback;
  final SearchBehavior? searchBehavior;
  final URLHandler? urlHandler;
  final TrackMatching? trackMatching;
  final PostProcessing? postProcessing;
  final List<ExtensionServiceHealthCheck> serviceHealth;
  final Map<String, dynamic> capabilities;

  const Extension({
    required this.id,
    required this.name,
    required this.displayName,
    required this.version,
    required this.description,
    required this.enabled,
    required this.status,
    this.errorMessage,
    this.iconPath,
    this.permissions = const [],
    this.settings = const [],
    this.qualityOptions = const [],
    this.hasMetadataProvider = false,
    this.hasDownloadProvider = false,
    this.hasLyricsProvider = false,
    this.skipMetadataEnrichment = false,
    this.skipLyrics = false,
    this.stopProviderFallback = false,
    this.searchBehavior,
    this.urlHandler,
    this.trackMatching,
    this.postProcessing,
    this.serviceHealth = const [],
    this.capabilities = const {},
  });

  factory Extension.fromJson(Map<String, dynamic> json) {
    return Extension(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      displayName:
          json['display_name'] as String? ?? json['name'] as String? ?? '',
      version: json['version'] as String? ?? '0.0.0',
      description: json['description'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      status: json['status'] as String? ?? 'loaded',
      errorMessage: json['error_message'] as String?,
      iconPath: json['icon_path'] as String?,
      permissions:
          (json['permissions'] as List<dynamic>?)?.cast<String>() ?? [],
      settings:
          (json['settings'] as List<dynamic>?)
              ?.map((s) => ExtensionSetting.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      qualityOptions:
          (json['quality_options'] as List<dynamic>?)
              ?.map((q) => QualityOption.fromJson(q as Map<String, dynamic>))
              .toList() ??
          [],
      hasMetadataProvider: json['has_metadata_provider'] as bool? ?? false,
      hasDownloadProvider: json['has_download_provider'] as bool? ?? false,
      hasLyricsProvider: json['has_lyrics_provider'] as bool? ?? false,
      skipMetadataEnrichment:
          json['skip_metadata_enrichment'] as bool? ?? false,
      skipLyrics: json['skip_lyrics'] as bool? ?? false,
      stopProviderFallback: json['stop_provider_fallback'] as bool? ?? false,
      searchBehavior: json['search_behavior'] != null
          ? SearchBehavior.fromJson(
              json['search_behavior'] as Map<String, dynamic>,
            )
          : null,
      urlHandler: json['url_handler'] != null
          ? URLHandler.fromJson(json['url_handler'] as Map<String, dynamic>)
          : null,
      trackMatching: json['track_matching'] != null
          ? TrackMatching.fromJson(
              json['track_matching'] as Map<String, dynamic>,
            )
          : null,
      postProcessing: json['post_processing'] != null
          ? PostProcessing.fromJson(
              json['post_processing'] as Map<String, dynamic>,
            )
          : null,
      serviceHealth:
          (json['service_health'] as List<dynamic>?)
              ?.map(
                (h) => ExtensionServiceHealthCheck.fromJson(
                  h as Map<String, dynamic>,
                ),
              )
              .toList() ??
          [],
      capabilities: (json['capabilities'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Extension copyWith({
    String? id,
    String? name,
    String? displayName,
    String? version,
    String? description,
    bool? enabled,
    String? status,
    String? errorMessage,
    String? iconPath,
    List<String>? permissions,
    List<ExtensionSetting>? settings,
    List<QualityOption>? qualityOptions,
    bool? hasMetadataProvider,
    bool? hasDownloadProvider,
    bool? hasLyricsProvider,
    bool? skipMetadataEnrichment,
    bool? skipLyrics,
    bool? stopProviderFallback,
    SearchBehavior? searchBehavior,
    URLHandler? urlHandler,
    TrackMatching? trackMatching,
    PostProcessing? postProcessing,
    List<ExtensionServiceHealthCheck>? serviceHealth,
    Map<String, dynamic>? capabilities,
  }) {
    return Extension(
      id: id ?? this.id,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      version: version ?? this.version,
      description: description ?? this.description,
      enabled: enabled ?? this.enabled,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      iconPath: iconPath ?? this.iconPath,
      permissions: permissions ?? this.permissions,
      settings: settings ?? this.settings,
      qualityOptions: qualityOptions ?? this.qualityOptions,
      hasMetadataProvider: hasMetadataProvider ?? this.hasMetadataProvider,
      hasDownloadProvider: hasDownloadProvider ?? this.hasDownloadProvider,
      hasLyricsProvider: hasLyricsProvider ?? this.hasLyricsProvider,
      skipMetadataEnrichment:
          skipMetadataEnrichment ?? this.skipMetadataEnrichment,
      skipLyrics: skipLyrics ?? this.skipLyrics,
      stopProviderFallback: stopProviderFallback ?? this.stopProviderFallback,
      searchBehavior: searchBehavior ?? this.searchBehavior,
      urlHandler: urlHandler ?? this.urlHandler,
      trackMatching: trackMatching ?? this.trackMatching,
      postProcessing: postProcessing ?? this.postProcessing,
      serviceHealth: serviceHealth ?? this.serviceHealth,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  bool get hasCustomSearch => searchBehavior?.enabled ?? false;
  bool get hasURLHandler => urlHandler?.enabled ?? false;
  bool get hasCustomMatching => trackMatching?.customMatching ?? false;
  bool get hasPostProcessing => postProcessing?.enabled ?? false;
  bool get hasServiceHealth => serviceHealth.isNotEmpty;
  bool get hasHomeFeed => capabilities['homeFeed'] == true;
  bool get hasBrowseCategories => capabilities['browseCategories'] == true;
  bool get requiresNativeContainerConversion =>
      capabilities['requiresContainerConversion'] == true ||
      capabilities['requiresNativeContainerConversion'] == true;
  List<String> get replacesBuiltInProviders {
    final value = capabilities['replacesBuiltInProviders'];
    if (value is! List) return const [];

    final normalized = <String>[];
    for (final item in value) {
      if (item is! String) continue;
      final trimmed = item.trim().toLowerCase();
      if (trimmed.isEmpty || normalized.contains(trimmed)) continue;
      normalized.add(trimmed);
    }
    return normalized;
  }

  String? get preferredDownloadOutputExtension {
    final value = capabilities['downloadOutputExtension'];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<String> get preservedNativeOutputExtensions {
    final value = capabilities['preserveNativeOutputExtensions'];
    if (value is! List) return const [];

    final normalized = <String>[];
    for (final item in value) {
      if (item is! String) continue;
      final trimmed = item.trim().toLowerCase();
      if (trimmed.isEmpty) continue;
      normalized.add(trimmed.startsWith('.') ? trimmed : '.$trimmed');
    }
    return normalized;
  }
}

String resolveEffectiveDownloadService(
  String requestedService,
  ExtensionState extensionState,
) {
  final normalizedRequested = requestedService.trim().toLowerCase();
  final enabledDownloadExtensions = extensionState.extensions
      .where((ext) => ext.enabled && ext.hasDownloadProvider)
      .toList(growable: false);

  if (normalizedRequested.isNotEmpty) {
    final matchingExtension = enabledDownloadExtensions
        .where((ext) => ext.id.trim().toLowerCase() == normalizedRequested)
        .firstOrNull;
    if (matchingExtension != null) {
      return matchingExtension.id;
    }

    final replacementExtension = enabledDownloadExtensions
        .where(
          (ext) => ext.replacesBuiltInProviders.contains(normalizedRequested),
        )
        .firstOrNull;
    if (replacementExtension != null) {
      return replacementExtension.id;
    }
  }

  return enabledDownloadExtensions.firstOrNull?.id ?? '';
}

String resolveEffectiveMetadataProvider(
  String requestedProvider,
  ExtensionState extensionState,
) {
  final normalizedRequested = requestedProvider.trim().toLowerCase();
  final enabledMetadataExtensions = extensionState.extensions
      .where((ext) => ext.enabled && ext.hasMetadataProvider)
      .toList(growable: false);

  if (normalizedRequested.isNotEmpty) {
    final matchingExtension = enabledMetadataExtensions
        .where((ext) => ext.id.trim().toLowerCase() == normalizedRequested)
        .firstOrNull;
    if (matchingExtension != null) {
      return matchingExtension.id;
    }

    final replacementExtension = enabledMetadataExtensions
        .where(
          (ext) => ext.replacesBuiltInProviders.contains(normalizedRequested),
        )
        .firstOrNull;
    if (replacementExtension != null) {
      return replacementExtension.id;
    }
  }

  return enabledMetadataExtensions.firstOrNull?.id ?? '';
}

bool isDeezerCompatibleDownloadService(
  String service,
  ExtensionState extensionState,
) {
  final normalizedService = service.trim().toLowerCase();
  if (normalizedService.isEmpty) {
    return false;
  }

  return extensionState.extensions.any(
    (ext) =>
        ext.enabled &&
        ext.hasDownloadProvider &&
        ext.id.trim().toLowerCase() == normalizedService &&
        ext.replacesBuiltInProviders.contains('deezer'),
  );
}

String resolveProviderDisplayName(
  String providerId, {
  Iterable<Extension> extensions = const [],
}) {
  for (final extension in extensions) {
    if (extension.id == providerId) {
      return extension.displayName;
    }
  }

  return providerId;
}

class SearchFilter {
  final String id;
  final String? label;
  final String? icon;

  const SearchFilter({required this.id, this.label, this.icon});

  factory SearchFilter.fromJson(Map<String, dynamic> json) {
    return SearchFilter(
      id: json['id'] as String? ?? '',
      label: json['label'] as String?,
      icon: json['icon'] as String?,
    );
  }
}

class SearchBehavior {
  final bool enabled;
  final String? placeholder;
  final bool primary;
  final String? icon;
  final String? thumbnailRatio;
  final int? thumbnailWidth;
  final int? thumbnailHeight;
  final List<SearchFilter> filters;

  const SearchBehavior({
    required this.enabled,
    this.placeholder,
    this.primary = false,
    this.icon,
    this.thumbnailRatio,
    this.thumbnailWidth,
    this.thumbnailHeight,
    this.filters = const [],
  });

  factory SearchBehavior.fromJson(Map<String, dynamic> json) {
    return SearchBehavior(
      enabled: json['enabled'] as bool? ?? false,
      placeholder: json['placeholder'] as String?,
      primary: json['primary'] as bool? ?? false,
      icon: json['icon'] as String?,
      thumbnailRatio: json['thumbnailRatio'] as String?,
      thumbnailWidth: json['thumbnailWidth'] as int?,
      thumbnailHeight: json['thumbnailHeight'] as int?,
      filters:
          (json['filters'] as List<dynamic>?)
              ?.map((f) => SearchFilter.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  (double, double) getThumbnailSize({double defaultSize = 56}) {
    if (thumbnailWidth != null && thumbnailHeight != null) {
      return (thumbnailWidth!.toDouble(), thumbnailHeight!.toDouble());
    }

    switch (thumbnailRatio) {
      case 'wide':
        return (defaultSize * 16 / 9, defaultSize);
      case 'portrait':
        return (defaultSize * 2 / 3, defaultSize);
      case 'square':
      default:
        return (defaultSize, defaultSize);
    }
  }
}

class TrackMatching {
  final bool customMatching;
  final String? strategy;
  final int durationTolerance;

  const TrackMatching({
    required this.customMatching,
    this.strategy,
    this.durationTolerance = 3,
  });

  factory TrackMatching.fromJson(Map<String, dynamic> json) {
    return TrackMatching(
      customMatching: json['customMatching'] as bool? ?? false,
      strategy: json['strategy'] as String?,
      durationTolerance: json['durationTolerance'] as int? ?? 3,
    );
  }
}

class PostProcessing {
  final bool enabled;
  final List<PostProcessingHook> hooks;

  const PostProcessing({required this.enabled, this.hooks = const []});

  factory PostProcessing.fromJson(Map<String, dynamic> json) {
    return PostProcessing(
      enabled: json['enabled'] as bool? ?? false,
      hooks:
          (json['hooks'] as List<dynamic>?)
              ?.map(
                (h) => PostProcessingHook.fromJson(h as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }
}

class URLHandler {
  final bool enabled;
  final List<String> patterns;

  const URLHandler({required this.enabled, this.patterns = const []});

  factory URLHandler.fromJson(Map<String, dynamic> json) {
    return URLHandler(
      enabled: json['enabled'] as bool? ?? false,
      patterns: (json['patterns'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  bool matchesURL(String url) {
    if (!enabled || patterns.isEmpty) return false;
    final lowerUrl = url.toLowerCase();
    for (final pattern in patterns) {
      if (lowerUrl.contains(pattern.toLowerCase())) {
        return true;
      }
    }
    return false;
  }
}

class ExtensionServiceHealthCheck {
  final String id;
  final String? label;
  final String url;
  final String method;
  final String? serviceKey;
  final int? timeoutMs;
  final int? cacheTtlSeconds;
  final bool required;

  const ExtensionServiceHealthCheck({
    required this.id,
    this.label,
    required this.url,
    this.method = 'GET',
    this.serviceKey,
    this.timeoutMs,
    this.cacheTtlSeconds,
    this.required = false,
  });

  factory ExtensionServiceHealthCheck.fromJson(Map<String, dynamic> json) {
    return ExtensionServiceHealthCheck(
      id: json['id'] as String? ?? '',
      label: json['label'] as String?,
      url: json['url'] as String? ?? '',
      method: json['method'] as String? ?? 'GET',
      serviceKey: json['serviceKey'] as String?,
      timeoutMs: json['timeoutMs'] as int?,
      cacheTtlSeconds: json['cacheTtlSeconds'] as int?,
      required: json['required'] as bool? ?? false,
    );
  }
}

class ExtensionHealthStatus {
  final String extensionId;
  final String status;
  final DateTime? checkedAt;
  final List<ExtensionHealthCheckStatus> checks;

  const ExtensionHealthStatus({
    required this.extensionId,
    required this.status,
    this.checkedAt,
    this.checks = const [],
  });

  factory ExtensionHealthStatus.fromJson(Map<String, dynamic> json) {
    return ExtensionHealthStatus(
      extensionId: json['extension_id'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      checkedAt: DateTime.tryParse(json['checked_at'] as String? ?? ''),
      checks:
          (json['checks'] as List<dynamic>?)
              ?.map(
                (c) => ExtensionHealthCheckStatus.fromJson(
                  c as Map<String, dynamic>,
                ),
              )
              .toList() ??
          [],
    );
  }

  bool get isSupported => status != 'unsupported';
}

class ExtensionHealthCheckStatus {
  final String id;
  final String? label;
  final String url;
  final String method;
  final String? serviceKey;
  final bool required;
  final String status;
  final int? httpStatus;
  final int latencyMs;
  final String? message;
  final String? error;
  final DateTime? checkedAt;

  const ExtensionHealthCheckStatus({
    required this.id,
    this.label,
    required this.url,
    required this.method,
    this.serviceKey,
    this.required = false,
    required this.status,
    this.httpStatus,
    this.latencyMs = 0,
    this.message,
    this.error,
    this.checkedAt,
  });

  factory ExtensionHealthCheckStatus.fromJson(Map<String, dynamic> json) {
    return ExtensionHealthCheckStatus(
      id: json['id'] as String? ?? '',
      label: json['label'] as String?,
      url: json['url'] as String? ?? '',
      method: json['method'] as String? ?? 'GET',
      serviceKey: json['service_key'] as String?,
      required: json['required'] as bool? ?? false,
      status: json['status'] as String? ?? 'unknown',
      httpStatus: json['http_status'] as int?,
      latencyMs: json['latency_ms'] as int? ?? 0,
      message: json['message'] as String?,
      error: json['error'] as String?,
      checkedAt: DateTime.tryParse(json['checked_at'] as String? ?? ''),
    );
  }

  String get displayLabel => label?.trim().isNotEmpty == true ? label! : id;
}

class PostProcessingHook {
  final String id;
  final String name;
  final String? description;
  final bool defaultEnabled;
  final List<String> supportedFormats;

  const PostProcessingHook({
    required this.id,
    required this.name,
    this.description,
    this.defaultEnabled = false,
    this.supportedFormats = const [],
  });

  factory PostProcessingHook.fromJson(Map<String, dynamic> json) {
    return PostProcessingHook(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      defaultEnabled: json['defaultEnabled'] as bool? ?? false,
      supportedFormats:
          (json['supportedFormats'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}

class QualityOption {
  final String id;
  final String label;
  final String? description;
  final List<QualitySpecificSetting> settings;

  const QualityOption({
    required this.id,
    required this.label,
    this.description,
    this.settings = const [],
  });

  factory QualityOption.fromJson(Map<String, dynamic> json) {
    return QualityOption(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      description: json['description'] as String?,
      settings:
          (json['settings'] as List<dynamic>?)
              ?.map(
                (s) =>
                    QualitySpecificSetting.fromJson(s as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }
}

class QualitySpecificSetting {
  final String key;
  final String label;
  final String type;
  final dynamic defaultValue;
  final String? description;
  final List<String>? options;
  final bool required;
  final bool secret;

  const QualitySpecificSetting({
    required this.key,
    required this.label,
    required this.type,
    this.defaultValue,
    this.description,
    this.options,
    this.required = false,
    this.secret = false,
  });

  factory QualitySpecificSetting.fromJson(Map<String, dynamic> json) {
    return QualitySpecificSetting(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      type: json['type'] as String? ?? 'string',
      defaultValue: json['default'],
      description: json['description'] as String?,
      options: (json['options'] as List<dynamic>?)?.cast<String>(),
      required: json['required'] as bool? ?? false,
      secret: json['secret'] as bool? ?? false,
    );
  }
}

class ExtensionSetting {
  final String key;
  final String label;
  final String type;
  final dynamic defaultValue;
  final String? description;
  final List<String>? options;
  final bool required;
  final String? action;

  const ExtensionSetting({
    required this.key,
    required this.label,
    required this.type,
    this.defaultValue,
    this.description,
    this.options,
    this.required = false,
    this.action,
  });

  factory ExtensionSetting.fromJson(Map<String, dynamic> json) {
    return ExtensionSetting(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      type: json['type'] as String? ?? 'string',
      defaultValue: json['default'],
      description: json['description'] as String?,
      options: (json['options'] as List<dynamic>?)?.cast<String>(),
      required: json['required'] as bool? ?? false,
      action: json['action'] as String?,
    );
  }
}

class ExtensionState {
  final List<Extension> extensions;
  final List<String> providerPriority;
  final List<String> metadataProviderPriority;
  final Map<String, ExtensionHealthStatus> healthStatuses;
  final bool isLoading;
  final String? error;
  final bool isInitialized;

  const ExtensionState({
    this.extensions = const [],
    this.providerPriority = const [],
    this.metadataProviderPriority = const [],
    this.healthStatuses = const {},
    this.isLoading = false,
    this.error,
    this.isInitialized = false,
  });

  ExtensionState copyWith({
    List<Extension>? extensions,
    List<String>? providerPriority,
    List<String>? metadataProviderPriority,
    Map<String, ExtensionHealthStatus>? healthStatuses,
    bool? isLoading,
    String? error,
    bool? isInitialized,
  }) {
    return ExtensionState(
      extensions: extensions ?? this.extensions,
      providerPriority: providerPriority ?? this.providerPriority,
      metadataProviderPriority:
          metadataProviderPriority ?? this.metadataProviderPriority,
      healthStatuses: healthStatuses ?? this.healthStatuses,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

class ExtensionInstallBatchResult {
  final int attempted;
  final int installed;
  final Map<String, String> failures;

  const ExtensionInstallBatchResult({
    required this.attempted,
    required this.installed,
    this.failures = const {},
  });

  bool get hasFailures => failures.isNotEmpty;
  bool get anyInstalled => installed > 0;
}

class ExtensionNotifier extends Notifier<ExtensionState> {
  static const _extensionHealthCacheTtl = Duration(seconds: 60);
  AppLifecycleListener? _appLifecycleListener;
  bool _cleanupInFlight = false;
  Completer<void>? _initializationCompleter;
  final Map<String, DateTime> _healthExpiresAt = {};
  final Map<String, Future<ExtensionHealthStatus?>> _healthInFlight = {};

  @override
  ExtensionState build() {
    _appLifecycleListener ??= AppLifecycleListener(
      onDetach: _scheduleLifecycleCleanup,
    );
    ref.onDispose(() {
      _appLifecycleListener?.dispose();
      _appLifecycleListener = null;
      _healthExpiresAt.clear();
      _healthInFlight.clear();
    });
    return const ExtensionState();
  }

  void _scheduleLifecycleCleanup() {
    if (_cleanupInFlight) return;
    _cleanupInFlight = true;
    unawaited(_cleanupExtensions(reason: 'lifecycle detach'));
  }

  Future<void> _cleanupExtensions({required String reason}) async {
    if (!PlatformBridge.supportsExtensionSystem) {
      _cleanupInFlight = false;
      return;
    }

    try {
      await PlatformBridge.cleanupExtensions();
      _log.d('Extensions cleaned up ($reason)');
    } catch (e) {
      _log.w('Extension cleanup failed ($reason): $e');
    } finally {
      _cleanupInFlight = false;
    }
  }

  Future<void> initialize(String extensionsDir, String dataDir) async {
    if (state.isInitialized) return;
    if (_initializationCompleter != null) {
      await _initializationCompleter!.future;
      return;
    }

    final completer = Completer<void>();
    _initializationCompleter = completer;

    state = state.copyWith(isLoading: true, error: null);

    if (!PlatformBridge.supportsExtensionSystem) {
      state = state.copyWith(
        isInitialized: true,
        isLoading: false,
        extensions: const [],
        error: null,
      );
      _log.i('Extension system disabled on this platform');
      completer.complete();
      _initializationCompleter = null;
      return;
    }

    try {
      await PlatformBridge.initExtensionSystem(extensionsDir, dataDir);
      await loadExtensions(extensionsDir);
      await loadProviderPriority();
      await loadMetadataProviderPriority();
      state = state.copyWith(isInitialized: true, isLoading: false);
      _log.i('Extension system initialized');
    } catch (e) {
      _log.e('Failed to initialize extension system: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
      if (identical(_initializationCompleter, completer)) {
        _initializationCompleter = null;
      }
    }
  }

  Future<void> waitForInitialization({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (state.isInitialized || !PlatformBridge.supportsExtensionSystem) {
      return;
    }

    final future = _initializationCompleter?.future;
    if (future == null) {
      return;
    }

    try {
      await future.timeout(timeout);
    } on TimeoutException {
      _log.w('Timed out waiting for extension initialization after $timeout');
    }
  }

  Future<void> loadExtensions(String dirPath) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await PlatformBridge.loadExtensionsFromDir(dirPath);
      _log.d('Load extensions result: $result');
      await refreshExtensions();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      _log.e('Failed to load extensions: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refreshExtensions() async {
    try {
      final list = await PlatformBridge.getInstalledExtensions();
      final extensions = list.map((e) => Extension.fromJson(e)).toList();
      state = state.copyWith(extensions: extensions);
      await _reconcileDownloadProviderPriority();
      await _reconcileDefaultDownloadService();
      await _reconcileMetadataProviderPriority();
      _reconcileSearchProvider();
      _scheduleExtensionHealthRefresh(extensions);
      _log.d('Loaded ${extensions.length} extensions');

      for (final ext in extensions) {
        if (ext.searchBehavior != null) {
          _log.d(
            'Extension ${ext.id}: thumbnailRatio=${ext.searchBehavior!.thumbnailRatio}',
          );
        }
      }
    } catch (e) {
      _log.e('Failed to refresh extensions: $e');
      state = state.copyWith(error: e.toString());
    }
  }

  void _scheduleExtensionHealthRefresh(List<Extension> extensions) {
    for (final ext in extensions) {
      if (!ext.enabled || !ext.hasServiceHealth) continue;
      unawaited(checkExtensionHealth(ext.id));
    }
  }

  void refreshEnabledExtensionHealth() {
    _scheduleExtensionHealthRefresh(state.extensions);
  }

  Future<ExtensionHealthStatus?> checkExtensionHealth(
    String extensionId, {
    bool force = false,
  }) async {
    final ext = state.extensions
        .where((extension) => extension.id == extensionId)
        .firstOrNull;
    if (ext == null || !ext.hasServiceHealth) {
      return null;
    }

    final expiresAt = _healthExpiresAt[extensionId];
    final cached = state.healthStatuses[extensionId];
    if (!force &&
        cached != null &&
        expiresAt != null &&
        DateTime.now().isBefore(expiresAt)) {
      return cached;
    }

    final inFlight = _healthInFlight[extensionId];
    if (!force && inFlight != null) {
      return inFlight;
    }

    final future = () async {
      try {
        final result = await PlatformBridge.checkExtensionHealth(extensionId);
        final status = ExtensionHealthStatus.fromJson(result);
        final updated = Map<String, ExtensionHealthStatus>.of(
          state.healthStatuses,
        )..[extensionId] = status;
        _healthExpiresAt[extensionId] = DateTime.now().add(
          _extensionHealthCacheTtl,
        );
        state = state.copyWith(healthStatuses: updated);
        return status;
      } catch (e) {
        _log.w('Failed to check extension health for $extensionId: $e');
        final status = ExtensionHealthStatus(
          extensionId: extensionId,
          status: 'unknown',
          checkedAt: DateTime.now(),
          checks: const [],
        );
        final updated = Map<String, ExtensionHealthStatus>.of(
          state.healthStatuses,
        )..[extensionId] = status;
        _healthExpiresAt[extensionId] = DateTime.now().add(
          const Duration(seconds: 20),
        );
        state = state.copyWith(healthStatuses: updated);
        return status;
      } finally {
        _healthInFlight.remove(extensionId);
      }
    }();

    _healthInFlight[extensionId] = future;
    return future;
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<bool> installExtension(String filePath) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await PlatformBridge.loadExtensionFromPath(filePath);
      _log.i('Installed extension: ${result['name']}');
      await refreshExtensions();
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      _log.e('Failed to install extension: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<ExtensionInstallBatchResult> installExtensions(
    List<String> filePaths,
  ) async {
    final uniquePaths = <String>[];
    for (final path in filePaths) {
      final trimmed = path.trim();
      if (trimmed.isEmpty || uniquePaths.contains(trimmed)) continue;
      uniquePaths.add(trimmed);
    }

    if (uniquePaths.isEmpty) {
      return const ExtensionInstallBatchResult(attempted: 0, installed: 0);
    }

    state = state.copyWith(isLoading: true, error: null);

    var installed = 0;
    final failures = <String, String>{};

    for (final path in uniquePaths) {
      try {
        final result = await PlatformBridge.loadExtensionFromPath(path);
        installed++;
        _log.i('Installed extension: ${result['name']}');
      } catch (e) {
        _log.e('Failed to install extension from $path: $e');
        failures[path] = e.toString();
      }
    }

    if (installed > 0) {
      await refreshExtensions();
    }

    final firstError = failures.values.firstOrNull;
    state = state.copyWith(isLoading: false, error: firstError);

    return ExtensionInstallBatchResult(
      attempted: uniquePaths.length,
      installed: installed,
      failures: failures,
    );
  }

  Future<Map<String, dynamic>> checkExtensionUpgrade(String filePath) async {
    try {
      return await PlatformBridge.checkExtensionUpgrade(filePath);
    } catch (e) {
      _log.e('Failed to check extension upgrade: $e');
      return {'error': e.toString()};
    }
  }

  Future<bool> upgradeExtension(String filePath) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await PlatformBridge.upgradeExtension(filePath);
      _log.i(
        'Upgraded extension: ${result['display_name']} to v${result['version']}',
      );
      await refreshExtensions();
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      _log.e('Failed to upgrade extension: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> removeExtension(String extensionId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await PlatformBridge.removeExtension(extensionId);
      _log.i('Removed extension: $extensionId');
      await refreshExtensions();
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      _log.e('Failed to remove extension: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<void> setExtensionEnabled(String extensionId, bool enabled) async {
    try {
      await PlatformBridge.setExtensionEnabled(extensionId, enabled);
      _log.d('Set extension $extensionId enabled: $enabled');

      final ext = state.extensions
          .where((e) => e.id == extensionId)
          .firstOrNull;

      final extensions = state.extensions.map((e) {
        if (e.id == extensionId) {
          return e.copyWith(enabled: enabled);
        }
        return e;
      }).toList();

      state = state.copyWith(extensions: extensions);
      await _reconcileDownloadProviderPriority();
      await _reconcileDefaultDownloadService();
      await _reconcileMetadataProviderPriority();
      _reconcileSearchProvider();

      final updatedExt = extensions
          .where((extension) => extension.id == extensionId)
          .firstOrNull;
      if (enabled && updatedExt?.hasServiceHealth == true) {
        unawaited(checkExtensionHealth(extensionId, force: true));
      }

      if (!enabled && ext != null) {
        final settings = ref.read(settingsProvider);

        if (settings.searchProvider == extensionId) {
          ref.read(settingsProvider.notifier).setSearchProvider(null);
          _log.d(
            'Cleared search provider because extension $extensionId was disabled',
          );
        }

        if (ext.hasDownloadProvider && settings.defaultService == extensionId) {
          final fallbackService =
              _firstEnabledExtensionDownloadProviderId() ?? '';
          ref
              .read(settingsProvider.notifier)
              .setDefaultService(fallbackService);
          _log.d(
            fallbackService.isEmpty
                ? 'Cleared default service because extension $extensionId was disabled'
                : 'Reset default service to $fallbackService because extension $extensionId was disabled',
          );
        }
      }
    } catch (e) {
      _log.e('Failed to set extension enabled: $e');
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> _reconcileDownloadProviderPriority() async {
    if (state.providerPriority.isEmpty) {
      return;
    }

    final sanitized = _sanitizeDownloadProviderPriority(state.providerPriority);
    if (_stringListEquals(sanitized, state.providerPriority)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_providerPriorityKey, jsonEncode(sanitized));
    await PlatformBridge.setProviderPriority(sanitized);
    state = state.copyWith(providerPriority: sanitized);
    _log.d('Reconciled provider priority after extension update: $sanitized');
  }

  Future<void> _reconcileMetadataProviderPriority() async {
    if (state.metadataProviderPriority.isEmpty) {
      return;
    }

    final replaced = _replaceRetiredBuiltInMetadataProviders(
      state.metadataProviderPriority,
    );
    final sanitized = _sanitizeMetadataProviderPriority(replaced);
    if (_stringListEquals(sanitized, state.metadataProviderPriority)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_metadataProviderPriorityKey, jsonEncode(sanitized));
    await PlatformBridge.setMetadataProviderPriority(sanitized);
    state = state.copyWith(metadataProviderPriority: sanitized);
    _log.d(
      'Reconciled metadata provider priority after extension update: $sanitized',
    );
  }

  String? _firstEnabledExtensionDownloadProviderId() {
    return state.extensions
        .where((ext) => ext.enabled && ext.hasDownloadProvider)
        .map((ext) => ext.id)
        .firstOrNull;
  }

  String? _firstEnabledSearchProviderId() {
    return state.extensions
            .where(
              (ext) =>
                  ext.enabled &&
                  ext.hasCustomSearch &&
                  ext.searchBehavior?.primary == true,
            )
            .map((ext) => ext.id)
            .firstOrNull ??
        state.extensions
            .where((ext) => ext.enabled && ext.hasCustomSearch)
            .map((ext) => ext.id)
            .firstOrNull;
  }

  String? replacedBuiltInDownloadProviderFor(String providerId) {
    final normalized = providerId.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    return state.extensions
        .where(
          (ext) =>
              ext.enabled &&
              ext.hasDownloadProvider &&
              ext.replacesBuiltInProviders.contains(normalized),
        )
        .map((ext) => ext.id)
        .firstOrNull;
  }

  String? replacedBuiltInSearchProviderFor(String providerId) {
    final normalized = providerId.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    return state.extensions
        .where(
          (ext) =>
              ext.enabled &&
              ext.hasCustomSearch &&
              ext.replacesBuiltInProviders.contains(normalized),
        )
        .map((ext) => ext.id)
        .firstOrNull;
  }

  String? replacedBuiltInMetadataProviderFor(String providerId) {
    final normalized = providerId.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    return state.extensions
        .where(
          (ext) =>
              ext.enabled &&
              ext.hasMetadataProvider &&
              ext.replacesBuiltInProviders.contains(normalized),
        )
        .map((ext) => ext.id)
        .firstOrNull;
  }

  bool downloadProviderReplacesLegacyProvider(
    String providerId,
    String legacyProviderId,
  ) {
    final normalizedProvider = providerId.trim().toLowerCase();
    final normalizedLegacy = legacyProviderId.trim().toLowerCase();
    if (normalizedProvider.isEmpty || normalizedLegacy.isEmpty) return false;
    if (normalizedProvider == normalizedLegacy) return true;

    final extension = state.extensions
        .where((ext) => ext.enabled && ext.hasDownloadProvider)
        .where((ext) => ext.id.toLowerCase() == normalizedProvider)
        .firstOrNull;
    return extension?.replacesBuiltInProviders.contains(normalizedLegacy) ??
        false;
  }

  Future<void> _reconcileDefaultDownloadService() async {
    final settings = ref.read(settingsProvider);
    final preferredExtensionId = _firstEnabledExtensionDownloadProviderId();
    final currentService = settings.defaultService.trim();

    if (currentService.isEmpty) {
      if (preferredExtensionId != null) {
        ref
            .read(settingsProvider.notifier)
            .setDefaultService(preferredExtensionId);
        _log.d(
          'Adopted first enabled download extension as default service: $preferredExtensionId',
        );
      }
      return;
    }

    final replacementExtensionId = replacedBuiltInDownloadProviderFor(
      currentService,
    );
    if (replacementExtensionId != null) {
      ref
          .read(settingsProvider.notifier)
          .setDefaultService(replacementExtensionId);
      _log.d(
        'Migrated retired built-in service $currentService to $replacementExtensionId',
      );
      return;
    }

    final currentExtension = state.extensions
        .where((ext) => ext.id == currentService)
        .firstOrNull;
    final isMissingOrInvalidExtension =
        currentExtension == null ||
        !currentExtension.enabled ||
        !currentExtension.hasDownloadProvider;
    if (isMissingOrInvalidExtension) {
      final fallbackService = preferredExtensionId ?? '';
      ref.read(settingsProvider.notifier).setDefaultService(fallbackService);
      _log.d(
        fallbackService.isEmpty
            ? 'Cleared default service because $currentService is no longer available'
            : 'Reset default service to $fallbackService because $currentService is no longer available',
      );
    }
  }

  void _reconcileSearchProvider() {
    final settings = ref.read(settingsProvider);
    final currentSearchProvider = settings.searchProvider?.trim() ?? '';
    final preferredSearchProvider = _firstEnabledSearchProviderId() ?? '';

    if (currentSearchProvider.isEmpty) {
      if (preferredSearchProvider.isNotEmpty) {
        ref
            .read(settingsProvider.notifier)
            .setSearchProvider(preferredSearchProvider);
        _log.d(
          'Adopted first enabled search provider as default: $preferredSearchProvider',
        );
      }
      return;
    }

    final replacementExtensionId = replacedBuiltInSearchProviderFor(
      currentSearchProvider,
    );
    if (replacementExtensionId != null) {
      ref
          .read(settingsProvider.notifier)
          .setSearchProvider(replacementExtensionId);
      _log.d(
        'Migrated retired built-in search provider $currentSearchProvider to $replacementExtensionId',
      );
      return;
    }

    final hasMatchingExtension = state.extensions.any(
      (ext) =>
          ext.enabled && ext.hasCustomSearch && ext.id == currentSearchProvider,
    );
    if (!hasMatchingExtension) {
      ref
          .read(settingsProvider.notifier)
          .setSearchProvider(
            preferredSearchProvider.isNotEmpty ? preferredSearchProvider : null,
          );
      _log.d(
        preferredSearchProvider.isNotEmpty
            ? 'Reset stale search provider $currentSearchProvider to $preferredSearchProvider'
            : 'Cleared stale search provider because $currentSearchProvider is no longer available',
      );
    }
  }

  Future<bool> ensureSpotifyWebExtensionReady({
    bool setAsSearchProvider = true,
  }) async {
    try {
      await refreshExtensions();

      var ext = state.extensions
          .where((e) => e.id == _spotifyWebExtensionId)
          .firstOrNull;

      if (ext == null) {
        final cacheDir = await getTemporaryDirectory();
        await PlatformBridge.initExtensionStore(cacheDir.path);

        final tempRoot = await getTemporaryDirectory();
        final installDir = await Directory(
          '${tempRoot.path}/spotiflac_bootstrap_spotify_web',
        ).create(recursive: true);

        final downloadPath = await PlatformBridge.downloadStoreExtension(
          _spotifyWebExtensionId,
          installDir.path,
        );

        final installed = await installExtension(downloadPath);
        if (!installed) {
          _log.w('Failed to install spotify-web extension from store');
          return false;
        }

        await refreshExtensions();
        ext = state.extensions
            .where((e) => e.id == _spotifyWebExtensionId)
            .firstOrNull;
      }

      if (ext == null) {
        _log.w('spotify-web extension is still not available after install');
        return false;
      }

      if (!ext.enabled) {
        await setExtensionEnabled(_spotifyWebExtensionId, true);
      }

      if (setAsSearchProvider) {
        final settings = ref.read(settingsProvider);
        if (settings.searchProvider != _spotifyWebExtensionId) {
          ref
              .read(settingsProvider.notifier)
              .setSearchProvider(_spotifyWebExtensionId);
        }
      }

      _log.i('spotify-web extension is ready');
      return true;
    } catch (e) {
      _log.w('Failed to ensure spotify-web extension is ready: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> getExtensionSettings(String extensionId) async {
    try {
      return await PlatformBridge.getExtensionSettings(extensionId);
    } catch (e) {
      _log.e('Failed to get extension settings: $e');
      return {};
    }
  }

  Future<void> setExtensionSettings(
    String extensionId,
    Map<String, dynamic> settings,
  ) async {
    try {
      await PlatformBridge.setExtensionSettings(extensionId, settings);
      _log.d('Updated settings for extension: $extensionId');
    } catch (e) {
      _log.e('Failed to set extension settings: $e');
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> loadProviderPriority() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString(_providerPriorityKey);

      List<String> priority;
      if (savedJson != null) {
        final saved = _tryDecodeStringListPreference(
          savedJson,
          _providerPriorityKey,
        );
        if (saved != null) {
          priority = _sanitizeDownloadProviderPriority(saved);
          _log.d('Loaded provider priority from prefs: $priority');
          await prefs.setString(_providerPriorityKey, jsonEncode(priority));
          await PlatformBridge.setProviderPriority(priority);
        } else {
          await prefs.remove(_providerPriorityKey);
          priority = await PlatformBridge.getProviderPriority();
          priority = _sanitizeDownloadProviderPriority(priority);
          await prefs.setString(_providerPriorityKey, jsonEncode(priority));
          await PlatformBridge.setProviderPriority(priority);
          _log.d('Recovered provider priority from defaults: $priority');
        }
      } else {
        priority = await PlatformBridge.getProviderPriority();
        priority = _sanitizeDownloadProviderPriority(priority);
        await prefs.setString(_providerPriorityKey, jsonEncode(priority));
        await PlatformBridge.setProviderPriority(priority);
        _log.d('Using default provider priority: $priority');
      }

      state = state.copyWith(providerPriority: priority);
    } catch (e) {
      _log.e('Failed to load provider priority: $e');
    }
  }

  Future<void> setProviderPriority(List<String> priority) async {
    try {
      final sanitized = _sanitizeDownloadProviderPriority(priority);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_providerPriorityKey, jsonEncode(sanitized));

      await PlatformBridge.setProviderPriority(sanitized);
      state = state.copyWith(providerPriority: sanitized);
      _log.d('Saved provider priority: $sanitized');
    } catch (e) {
      _log.e('Failed to set provider priority: $e');
      state = state.copyWith(error: e.toString());
    }
  }

  List<String> _sanitizeDownloadProviderPriority(List<String> input) {
    final allowed = getAllDownloadProviders().toSet();
    final preferredOrder = getAllDownloadProviders();
    final result = <String>[];

    for (final provider in input) {
      if (allowed.contains(provider) && !result.contains(provider)) {
        result.add(provider);
      }
    }

    for (final provider in preferredOrder) {
      if (!result.contains(provider)) {
        result.add(provider);
      }
    }

    return result;
  }

  Future<void> loadMetadataProviderPriority() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString(_metadataProviderPriorityKey);

      List<String> priority;
      if (savedJson != null) {
        final saved = _tryDecodeStringListPreference(
          savedJson,
          _metadataProviderPriorityKey,
        );
        if (saved != null) {
          priority = _sanitizeMetadataProviderPriority(
            _replaceRetiredBuiltInMetadataProviders(saved),
          );
          _log.d('Loaded metadata provider priority from prefs: $priority');
          await prefs.setString(
            _metadataProviderPriorityKey,
            jsonEncode(priority),
          );
          await PlatformBridge.setMetadataProviderPriority(priority);
        } else {
          await prefs.remove(_metadataProviderPriorityKey);
          final backendPriority =
              await PlatformBridge.getMetadataProviderPriority();
          priority = _sanitizeMetadataProviderPriority(backendPriority);
          await prefs.setString(
            _metadataProviderPriorityKey,
            jsonEncode(priority),
          );
          await PlatformBridge.setMetadataProviderPriority(priority);
          _log.d(
            'Recovered metadata provider priority from defaults: $priority',
          );
        }
      } else {
        final backendPriority =
            await PlatformBridge.getMetadataProviderPriority();
        priority = _sanitizeMetadataProviderPriority(backendPriority);
        _log.d('Using default metadata provider priority: $priority');
        await prefs.setString(
          _metadataProviderPriorityKey,
          jsonEncode(priority),
        );
        await PlatformBridge.setMetadataProviderPriority(priority);
      }

      state = state.copyWith(metadataProviderPriority: priority);
    } catch (e) {
      _log.e('Failed to load metadata provider priority: $e');
    }
  }

  Future<void> setMetadataProviderPriority(List<String> priority) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sanitized = _sanitizeMetadataProviderPriority(
        _replaceRetiredBuiltInMetadataProviders(priority),
      );
      await prefs.setString(
        _metadataProviderPriorityKey,
        jsonEncode(sanitized),
      );

      await PlatformBridge.setMetadataProviderPriority(sanitized);
      state = state.copyWith(metadataProviderPriority: sanitized);
      _log.d('Saved metadata provider priority: $sanitized');
    } catch (e) {
      _log.e('Failed to set metadata provider priority: $e');
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> cleanup() async {
    if (_cleanupInFlight) return;
    _cleanupInFlight = true;
    await _cleanupExtensions(reason: 'manual');
  }

  Extension? getExtension(String extensionId) {
    try {
      return state.extensions.firstWhere((ext) => ext.id == extensionId);
    } catch (_) {
      return null;
    }
  }

  List<Extension> get enabledExtensions {
    return state.extensions.where((ext) => ext.enabled).toList();
  }

  List<String> getAllDownloadProviders() {
    return _distinctProviderIds(
      state.extensions
          .where((ext) => ext.enabled && ext.hasDownloadProvider)
          .map((ext) => ext.id),
    );
  }

  List<String> getAllMetadataProviders() {
    final metadataExtensions = state.extensions
        .where((ext) => ext.enabled && ext.hasMetadataProvider)
        .toList();
    final primarySearchMetadataExtensions = metadataExtensions
        .where((ext) => ext.searchBehavior?.primary == true)
        .map((ext) => ext.id);
    final otherMetadataExtensions = metadataExtensions
        .where((ext) => ext.searchBehavior?.primary != true)
        .map((ext) => ext.id);

    return _distinctProviderIds([
      ...primarySearchMetadataExtensions,
      ...otherMetadataExtensions,
    ]);
  }

  List<String> _distinctProviderIds(Iterable<String> ids) {
    final seen = <String>{};
    final result = <String>[];
    for (final id in ids) {
      final normalized = id.trim();
      if (normalized.isNotEmpty && seen.add(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }

  List<String> _replaceRetiredBuiltInMetadataProviders(List<String> input) {
    final result = <String>[];
    for (final provider in input) {
      final replacement = replacedBuiltInMetadataProviderFor(provider);
      final resolved = replacement ?? provider;
      if (!result.contains(resolved)) {
        result.add(resolved);
      }
    }
    return result;
  }

  List<String> _sanitizeMetadataProviderPriority(List<String> input) {
    final allowed = getAllMetadataProviders().toSet();
    final preferredOrder = getAllMetadataProviders();
    final result = <String>[];

    for (final provider in input) {
      if (allowed.contains(provider) && !result.contains(provider)) {
        result.add(provider);
      }
    }

    if (result.isEmpty && preferredOrder.isNotEmpty) {
      return List<String>.from(preferredOrder);
    }

    for (final provider in preferredOrder) {
      if (!result.contains(provider)) {
        result.add(provider);
      }
    }

    return result;
  }

  List<Extension> get searchProviders {
    return state.extensions
        .where((ext) => ext.enabled && ext.hasCustomSearch)
        .toList();
  }

  /// Collects the keys flagged as `secret` in an extension's manifest schema
  /// (top-level settings and quality-specific settings).
  Set<String> _secretKeysFromManifest(Map<String, dynamic> raw) {
    final keys = <String>{};

    void scan(Object? settingsList) {
      if (settingsList is! List) return;
      for (final entry in settingsList) {
        if (entry is Map &&
            entry['secret'] == true &&
            entry['key'] is String) {
          keys.add(entry['key'] as String);
        }
      }
    }

    scan(raw['settings']);
    final quality = raw['quality_options'];
    if (quality is List) {
      for (final option in quality) {
        if (option is Map) {
          scan(option['settings']);
        }
      }
    }
    return keys;
  }

  /// Builds the extensions section of a backup: the store registry URL plus the
  /// installed extensions with their id, version, enabled flag and settings.
  /// Secret-flagged settings (tokens, API keys) are only included when
  /// [includeSecrets] is true.
  Future<Map<String, dynamic>> exportBackup({
    required bool includeSecrets,
  }) async {
    if (!PlatformBridge.supportsExtensionSystem) {
      return {'registry_url': '', 'items': const <Map<String, dynamic>>[]};
    }

    String registryUrl = '';
    try {
      registryUrl = await PlatformBridge.getStoreRegistryUrl();
    } catch (_) {}

    List<Map<String, dynamic>> installed;
    try {
      installed = await PlatformBridge.getInstalledExtensions();
    } catch (e) {
      _log.w('Backup: failed to list extensions: $e');
      installed = const [];
    }

    final items = <Map<String, dynamic>>[];
    for (final raw in installed) {
      final id = raw['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final secretKeys = _secretKeysFromManifest(raw);

      Map<String, dynamic> settings = {};
      try {
        settings = await PlatformBridge.getExtensionSettings(id);
      } catch (_) {}

      final filtered = <String, dynamic>{};
      var omittedSecret = false;
      settings.forEach((key, value) {
        if (secretKeys.contains(key)) {
          if (!includeSecrets) {
            omittedSecret = true;
            return;
          }
        }
        filtered[key] = value;
      });

      items.add({
        'id': id,
        'version': raw['version']?.toString() ?? '',
        'enabled': raw['enabled'] == true,
        'settings': filtered,
        if (omittedSecret) 'secrets_omitted': true,
      });
    }

    return {'registry_url': registryUrl, 'items': items};
  }

  /// Restores extensions from a backup section produced by [exportBackup]:
  /// re-applies the store registry URL, reinstalls each extension from the
  /// store when missing, then merges settings and restores the enabled flag.
  /// Missing settings (e.g. omitted secrets) are merged with the current values
  /// so they are not wiped.
  Future<ExtensionRestoreResult> restoreFromBackup(
    Map<String, dynamic> data,
  ) async {
    if (!PlatformBridge.supportsExtensionSystem) {
      return const ExtensionRestoreResult();
    }

    final registryUrl = (data['registry_url'] as String?)?.trim() ?? '';
    final itemsRaw = data['items'];
    final items = itemsRaw is List
        ? itemsRaw
              .whereType<Map<Object?, Object?>>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];

    Directory? destDir;
    try {
      final tmp = await getTemporaryDirectory();
      destDir = await Directory(
        '${tmp.path}/spotiflac_restore_ext',
      ).create(recursive: true);
      await PlatformBridge.initExtensionStore(destDir.path);
      if (registryUrl.isNotEmpty) {
        await PlatformBridge.setStoreRegistryUrl(registryUrl);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_storeRegistryUrlPrefKey, registryUrl);
      }
    } catch (e) {
      _log.w('Restore: failed to prepare extension store: $e');
    }

    await refreshExtensions();
    final installedIds = state.extensions
        .map((e) => e.id.toLowerCase())
        .toSet();

    var installedCount = 0;
    var alreadyPresent = 0;
    var failed = 0;
    final failedIds = <String>[];

    for (final item in items) {
      final id = item['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final enabled = item['enabled'] != false;
      var present = installedIds.contains(id.toLowerCase());

      if (!present) {
        if (destDir == null) {
          failed++;
          failedIds.add(id);
          continue;
        }
        try {
          final path = await PlatformBridge.downloadStoreExtension(
            id,
            destDir.path,
          );
          final ok = await installExtension(path);
          if (ok) {
            installedCount++;
            present = true;
          } else {
            failed++;
            failedIds.add(id);
          }
        } catch (e) {
          _log.w('Restore: failed to install extension $id: $e');
          failed++;
          failedIds.add(id);
        }
      } else {
        alreadyPresent++;
      }

      if (!present) continue;

      final settings = item['settings'];
      if (settings is Map && settings.isNotEmpty) {
        try {
          final current = await PlatformBridge.getExtensionSettings(id);
          final merged = <String, dynamic>{
            ...current,
            ...Map<String, dynamic>.from(settings),
          };
          await PlatformBridge.setExtensionSettings(id, merged);
        } catch (e) {
          _log.w('Restore: failed to apply settings for $id: $e');
        }
      }

      try {
        await setExtensionEnabled(id, enabled);
      } catch (_) {}
    }

    await refreshExtensions();

    return ExtensionRestoreResult(
      installed: installedCount,
      alreadyPresent: alreadyPresent,
      failed: failed,
      failedIds: failedIds,
    );
  }
}

final extensionProvider = NotifierProvider<ExtensionNotifier, ExtensionState>(
  ExtensionNotifier.new,
);
