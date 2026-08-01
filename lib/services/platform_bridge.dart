import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/services/download_request_payload.dart';
import 'package:spotiflac_android/utils/audio_format_utils.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('PlatformBridge');

Object? _decodeJsonInBackground(String json) => jsonDecode(json);

class ExtensionSessionGrantEvent {
  final String extensionId;
  final bool success;

  const ExtensionSessionGrantEvent({
    required this.extensionId,
    required this.success,
  });
}

/// Folder picked via the native iOS document picker: the filesystem path plus
/// the security-scoped bookmark that re-grants access across app launches.
class IosPickedDirectory {
  final String path;
  final String bookmark;

  const IosPickedDirectory({required this.path, required this.bookmark});
}

class InstallationState {
  final bool markerExisted;
  final bool markerCreated;
  final bool freshPackageInstall;

  const InstallationState({
    required this.markerExisted,
    required this.markerCreated,
    required this.freshPackageInstall,
  });

  const InstallationState.unsupported()
    : markerExisted = true,
      markerCreated = true,
      freshPackageInstall = false;

  factory InstallationState.fromMap(Map<String, dynamic> map) {
    return InstallationState(
      markerExisted: map['marker_existed'] == true,
      markerCreated: map['marker_created'] == true,
      freshPackageInstall: map['fresh_package_install'] == true,
    );
  }
}

bool shouldResetRestoredInstallation({
  required bool hasPersistedSettings,
  required InstallationState installState,
}) {
  return hasPersistedSettings &&
      !installState.markerExisted &&
      installState.markerCreated &&
      installState.freshPackageInstall;
}

class _BridgeCacheEntry {
  final Map<String, dynamic> value;
  final DateTime expiresAt;

  const _BridgeCacheEntry({required this.value, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class _BridgeListCacheEntry {
  final List<Map<String, dynamic>> value;
  final DateTime expiresAt;

  const _BridgeListCacheEntry({required this.value, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class _BridgeInFlight<T> {
  final String requestId;
  final String scopeKey;
  final Future<T> future;

  const _BridgeInFlight({
    required this.requestId,
    required this.scopeKey,
    required this.future,
  });
}

class PlatformBridge {
  static const _channel = MethodChannel('com.zarz.spotiflac/backend');
  static const _jsonResultFileKey = '__json_file';
  static const _backgroundJsonDecodeThresholdBytes = 128 * 1024;
  static const _metadataCacheTtl = Duration(minutes: 20);
  static const _urlHandleCacheTtl = Duration(minutes: 5);
  static const _customSearchCacheTtl = Duration(minutes: 2);
  static const _bridgeCacheMaxEntries = 256;
  static const _metadataPersistentCacheKey = 'bridge_metadata_lookup_cache_v1';
  static const _downloadProgressEvents = EventChannel(
    'com.zarz.spotiflac/download_progress_stream',
  );
  static const _libraryScanProgressEvents = EventChannel(
    'com.zarz.spotiflac/library_scan_progress_stream',
  );
  static final Map<String, _BridgeCacheEntry> _metadataCache = {};
  static final Map<String, _BridgeCacheEntry> _urlHandleCache = {};
  static final Map<String, _BridgeListCacheEntry> _customSearchCache = {};
  static final Map<String, Future<Map<String, dynamic>>> _metadataInFlight = {};
  static final Map<String, Future<Map<String, dynamic>?>> _urlHandleInFlight =
      {};
  static final Map<String, _BridgeInFlight<List<Map<String, dynamic>>>>
  _customSearchInFlight = {};
  static final Map<String, _BridgeInFlight<Map<String, dynamic>?>>
  _homeFeedInFlight = {};
  static Future<void>? _persistentLookupCacheLoadFuture;
  static int _lookupCacheGeneration = 0;
  static int _extensionRequestSequence = 0;
  static final StreamController<ExtensionSessionGrantEvent>
  _extensionSessionGrantEvents =
      StreamController<ExtensionSessionGrantEvent>.broadcast();
  static bool _backendEventHandlerInstalled = false;

  static bool get supportsCoreBackend => Platform.isAndroid || Platform.isIOS;

  static bool get supportsExtensionSystem =>
      Platform.isAndroid || Platform.isIOS;

  static Stream<ExtensionSessionGrantEvent> extensionSessionGrantEvents() {
    _ensureBackendEventHandler();
    return _extensionSessionGrantEvents.stream;
  }

  static void _ensureBackendEventHandler() {
    if (_backendEventHandlerInstalled) return;
    _backendEventHandlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'extensionSessionGrantCompleted':
          final args = call.arguments;
          if (args is Map) {
            final extensionId = args['extension_id']?.toString().trim() ?? '';
            if (extensionId.isNotEmpty) {
              _extensionSessionGrantEvents.add(
                ExtensionSessionGrantEvent(
                  extensionId: extensionId,
                  success: args['success'] != false,
                ),
              );
            }
          }
          return null;
        default:
          return null;
      }
    });
  }

  static Future<Map<String, dynamic>> _invokeMap(
    String method, [
    dynamic args,
  ]) async {
    final result = await _channel.invokeMethod(method, args);
    return _decodeRequiredMapResult(result, method);
  }

  static Future<InstallationState> ensureInstallMarker() async {
    if (!Platform.isAndroid) return const InstallationState.unsupported();
    final result = await _invokeMap('ensureInstallMarker');
    return InstallationState.fromMap(result);
  }

  static Future<Map<String, dynamic>> _cachedInvoke(
    String cacheKey,
    Map<String, _BridgeCacheEntry> cache,
    Map<String, Future<Map<String, dynamic>>> inFlight,
    Duration ttl,
    String persistentCacheKey,
    Future<Map<String, dynamic>> Function() loader,
  ) async {
    await _ensurePersistentLookupCachesLoaded();
    final cached = _getCachedMap(cache, cacheKey);
    if (cached != null) return cached;

    final pending = inFlight[cacheKey];
    if (pending != null) return _copyStringMap(await pending);

    final generation = _lookupCacheGeneration;
    final future = () async {
      final value = await loader();
      if (generation == _lookupCacheGeneration) {
        _putCachedMap(cache, cacheKey, value, ttl, persistentCacheKey);
      }
      return _copyStringMap(value);
    }();
    inFlight[cacheKey] = future;
    try {
      return _copyStringMap(await future);
    } finally {
      inFlight.remove(cacheKey);
    }
  }

  static String _providerMetadataCacheKey(
    String providerId,
    String resourceType,
    String resourceId,
  ) {
    return [
      providerId.trim().toLowerCase(),
      resourceType.trim().toLowerCase(),
      resourceId.trim(),
    ].join(':');
  }

  static Map<String, dynamic>? _getCachedMap(
    Map<String, _BridgeCacheEntry> cache,
    String key,
  ) {
    _pruneExpiredBridgeCache(cache);
    final entry = cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      cache.remove(key);
      return null;
    }
    return _copyStringMap(entry.value);
  }

  static void _putCachedMap(
    Map<String, _BridgeCacheEntry> cache,
    String key,
    Map<String, dynamic> value,
    Duration ttl,
    String persistentCacheKey,
  ) {
    _pruneExpiredBridgeCache(cache);
    while (cache.length >= _bridgeCacheMaxEntries && cache.isNotEmpty) {
      cache.remove(cache.keys.first);
    }
    cache[key] = _BridgeCacheEntry(
      value: _copyStringMap(value),
      expiresAt: DateTime.now().add(ttl),
    );
    unawaited(
      _persistLookupCache(cache, persistentCacheKey, _lookupCacheGeneration),
    );
  }

  static void _pruneExpiredBridgeCache(Map<String, _BridgeCacheEntry> cache) {
    if (cache.isEmpty) return;
    final now = DateTime.now();
    cache.removeWhere((_, entry) => now.isAfter(entry.expiresAt));
  }

  static dynamic _copyJsonLike(dynamic value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _copyJsonLike(entry.value),
      };
    }
    if (value is List) {
      return value.map(_copyJsonLike).toList(growable: false);
    }
    return value;
  }

  static Map<String, dynamic> _copyStringMap(Map<String, dynamic> value) {
    return <String, dynamic>{
      for (final entry in value.entries) entry.key: _copyJsonLike(entry.value),
    };
  }

  static Map<String, dynamic>? _copyNullableStringMap(
    Map<String, dynamic>? value,
  ) {
    if (value == null) return null;
    return _copyStringMap(value);
  }

  static List<Map<String, dynamic>> _copyMapList(
    List<Map<String, dynamic>> value,
  ) {
    return value.map(_copyStringMap).toList(growable: false);
  }

  static dynamic _canonicalizeJsonLike(dynamic value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return <String, dynamic>{
        for (final entry in entries)
          entry.key.toString(): _canonicalizeJsonLike(entry.value),
      };
    }
    if (value is List) {
      return value.map(_canonicalizeJsonLike).toList(growable: false);
    }
    return value;
  }

  static Future<void> _ensurePersistentLookupCachesLoaded() {
    return _persistentLookupCacheLoadFuture ??= _loadPersistentLookupCaches(
      _lookupCacheGeneration,
    );
  }

  static Future<void> _loadPersistentLookupCaches(int generation) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (generation != _lookupCacheGeneration) return;
      _restorePersistentCache(
        prefs,
        _metadataPersistentCacheKey,
        _metadataCache,
      );
    } catch (e) {
      _log.w('Failed to load bridge lookup cache: $e');
    }
  }

  static void _restorePersistentCache(
    SharedPreferences prefs,
    String prefsKey,
    Map<String, _BridgeCacheEntry> target,
  ) {
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return;

    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;

    final now = DateTime.now();
    for (final entry in decoded.entries) {
      if (target.length >= _bridgeCacheMaxEntries) break;
      final key = entry.key.toString();
      final rawEntry = entry.value;
      if (key.isEmpty || rawEntry is! Map) continue;

      final expiresAtMs = rawEntry['expires_at'];
      final value = rawEntry['value'];
      if (expiresAtMs is! int || value is! Map) continue;

      final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
      if (!expiresAt.isAfter(now)) continue;

      target[key] = _BridgeCacheEntry(
        value: _copyStringMap(Map<String, dynamic>.from(value)),
        expiresAt: expiresAt,
      );
    }
  }

  static Future<void> _persistLookupCache(
    Map<String, _BridgeCacheEntry> cache,
    String prefsKey,
    int generation,
  ) async {
    try {
      _pruneExpiredBridgeCache(cache);
      final data = <String, dynamic>{
        for (final entry in cache.entries)
          entry.key: {
            'expires_at': entry.value.expiresAt.millisecondsSinceEpoch,
            'value': entry.value.value,
          },
      };
      final prefs = await SharedPreferences.getInstance();
      if (generation != _lookupCacheGeneration) return;
      await prefs.setString(prefsKey, jsonEncode(data));
    } catch (e) {
      _log.w('Failed to persist bridge lookup cache: $e');
    }
  }

  static Future<void> _clearPersistentLookupCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_metadataPersistentCacheKey);
      // Legacy key from the removed availability-check feature.
      await prefs.remove('bridge_availability_lookup_cache_v1');
    } catch (e) {
      _log.w('Failed to clear bridge lookup cache: $e');
    }
  }

  static Future<void> _clearLookupCaches() async {
    _lookupCacheGeneration++;
    _persistentLookupCacheLoadFuture = null;
    _metadataCache.clear();
    _urlHandleCache.clear();
    _customSearchCache.clear();
    _metadataInFlight.clear();
    _urlHandleInFlight.clear();
    for (final inFlight in _customSearchInFlight.values) {
      _cancelExtensionRequestUnawaited(inFlight.requestId);
    }
    for (final inFlight in _homeFeedInFlight.values) {
      _cancelExtensionRequestUnawaited(inFlight.requestId);
    }
    _customSearchInFlight.clear();
    _homeFeedInFlight.clear();
    await _clearPersistentLookupCaches();
  }

  static String _nextExtensionRequestId(String kind, String extensionId) {
    _extensionRequestSequence++;
    return [
      kind,
      DateTime.now().microsecondsSinceEpoch,
      _extensionRequestSequence,
      extensionId.trim(),
    ].join(':');
  }

  static void _cancelExtensionRequestUnawaited(String requestId) {
    if (requestId.isEmpty) return;
    unawaited(
      cancelExtensionRequest(requestId).catchError((Object e) {
        _log.w('Failed to cancel extension request $requestId: $e');
      }),
    );
  }

  static Future<void> cancelExtensionRequest(String requestId) async {
    if (requestId.isEmpty) return;
    await _channel.invokeMethod('cancelExtensionRequest', {
      'request_id': requestId,
    });
  }

  static void _cancelCustomSearchInFlightForScope(
    String scopeKey, {
    String? exceptKey,
  }) {
    for (final entry in _customSearchInFlight.entries.toList()) {
      if (entry.key == exceptKey || entry.value.scopeKey != scopeKey) continue;
      _cancelExtensionRequestUnawaited(entry.value.requestId);
    }
  }

  static void cancelExtensionHomeFeedRequests() {
    for (final inFlight in _homeFeedInFlight.values) {
      _cancelExtensionRequestUnawaited(inFlight.requestId);
    }
    _homeFeedInFlight.clear();
  }

  static int _lookupCacheSize() {
    _pruneExpiredBridgeCache(_metadataCache);
    return _metadataCache.length;
  }

  static Future<Map<String, dynamic>> _invokeDownloadMethod(
    String method,
    DownloadRequestPayload payload,
  ) {
    return _invokeMap(method, jsonEncode(payload.toJson()));
  }

  static Future<Map<String, dynamic>> downloadByStrategy({
    required DownloadRequestPayload payload,
    bool? useExtensions,
    bool? useFallback,
  }) async {
    final routedPayload = payload.withStrategy(
      useExtensions: useExtensions,
      useFallback: useFallback,
    );
    _log.i(
      'downloadByStrategy: "${payload.trackName}" by ${payload.artistName} '
      '(service: ${payload.service}, ext: ${routedPayload.useExtensions}, fallback: ${routedPayload.useFallback})',
    );
    final response = await _invokeDownloadMethod(
      'downloadByStrategy',
      routedPayload,
    );
    if (response['success'] == true) {
      final service = response['service'] ?? payload.service;
      final filePath = response['file_path'] ?? '';
      final bitDepth = response['actual_bit_depth'] as num?;
      final sampleRate = response['actual_sample_rate'] as num?;
      final qualityStr = bitDepth != null && sampleRate != null
          ? ' ($bitDepth-bit/${(sampleRate / 1000).toStringAsFixed(1)}kHz)'
          : '';
      _log.i('Download success via $service$qualityStr: $filePath');
    } else {
      final error = response['error'] ?? 'Unknown error';
      final errorType = response['error_type'] ?? '';
      _log.e('Download failed: $error (type: $errorType)');
    }
    return response;
  }

  static Future<Map<String, dynamic>> getAllDownloadProgress() async {
    final result = await _channel.invokeMethod('getAllDownloadProgress');
    return _decodeMapResult(result);
  }

  static Stream<Map<String, dynamic>> downloadProgressStream() {
    return _downloadProgressEvents.receiveBroadcastStream().map(
      _decodeMapResult,
    );
  }

  static Future<void> exitApp() async {
    await _channel.invokeMethod('exitApp');
  }

  static Future<void> clearItemProgress(String itemId) async {
    await _channel.invokeMethod('clearItemProgress', {'item_id': itemId});
  }

  static Future<void> cancelDownload(String itemId) async {
    await _channel.invokeMethod('cancelDownload', {'item_id': itemId});
  }

  /// Drops a stale pre-registered cancel flag for an item with no active
  /// download, so a user-initiated retry does not abort instantly.
  static Future<void> resetDownloadCancel(String itemId) async {
    await _channel.invokeMethod('resetDownloadCancel', {'item_id': itemId});
  }

  /// iOS only: run a verification/OAuth page inside ASWebAuthenticationSession.
  /// The session intercepts the callback scheme in-process, so the flow
  /// completes even where the app's URL scheme is not registered with the OS
  /// (e.g. sideload containers like LiveContainer). Returns true when the
  /// session was presented; the callback is delivered through the native side
  /// exactly like an OS deep link.
  static Future<bool> startIosWebAuthSession(
    String url, {
    String callbackScheme = 'spotiflac',
  }) async {
    final result = await _channel.invokeMethod('startWebAuthSession', {
      'url': url,
      'callback_scheme': callbackScheme,
    });
    return result == true;
  }

  static Future<void> setDownloadDirectory(String path) async {
    await _channel.invokeMethod('setDownloadDirectory', {'path': path});
  }

  static Future<void> setNetworkCompatibilityOptions({
    required bool allowHttp,
    required bool insecureTls,
  }) async {
    await _channel.invokeMethod('setNetworkCompatibilityOptions', {
      'allow_http': allowHttp,
      'insecure_tls': insecureTls,
    });
  }

  static Future<void> setAllowPrivateNetwork(bool allowed) async {
    await _channel.invokeMethod('setAllowPrivateNetwork', {'allowed': allowed});
  }

  static Future<String> buildFilename(
    String template,
    Map<String, dynamic> metadata,
  ) async {
    final result = await _channel.invokeMethod('buildFilename', {
      'template': template,
      'metadata': jsonEncode(metadata),
    });
    return result as String;
  }

  static Future<String> sanitizeFilename(String filename) async {
    final result = await _channel.invokeMethod('sanitizeFilename', {
      'filename': filename,
    });
    return result as String;
  }

  static Future<Map<String, dynamic>?> pickSafTree() async {
    final result = await _channel.invokeMethod('pickSafTree');
    return _decodeNullableMapResult(result, 'pickSafTree');
  }

  static Future<bool> safExists(String uri) async {
    final result = await _channel.invokeMethod('safExists', {'uri': uri});
    return result as bool;
  }

  /// Whether the persisted SAF grant for [treeUri] is still usable: the
  /// permission is present in the system's persisted list and the tree
  /// document still exists and is writable. Returns true on channel errors
  /// so a bridge problem never raises a false "access lost" alarm.
  static Future<bool> isSafTreeAccessible(String treeUri) async {
    try {
      return await validateSafTreeAccess(treeUri);
    } catch (e) {
      _log.w('Failed to check SAF tree accessibility: $e');
      return true;
    }
  }

  /// Strict SAF validation for startup and download preflight. Unlike
  /// [isSafTreeAccessible], channel failures are surfaced to the caller so a
  /// write cannot proceed on an unverified destination.
  static Future<bool> validateSafTreeAccess(String treeUri) async {
    final result = await _channel.invokeMethod('isSafTreeAccessible', {
      'tree_uri': treeUri,
    });
    return result as bool? ?? false;
  }

  static Future<bool> safDelete(String uri) async {
    final result = await _channel.invokeMethod('safDelete', {'uri': uri});
    return result as bool;
  }

  static Future<Map<String, dynamic>> safStat(String uri) {
    return _invokeMap('safStat', {'uri': uri});
  }

  static Future<Map<String, dynamic>> resolveSafFile({
    required String treeUri,
    required String fileName,
    String relativeDir = '',
  }) {
    return _invokeMap('resolveSafFile', {
      'tree_uri': treeUri,
      'relative_dir': relativeDir,
      'file_name': fileName,
    });
  }

  static Future<String?> copyContentUriToTemp(String uri) async {
    final result = await _channel.invokeMethod('safCopyToTemp', {'uri': uri});
    return result as String?;
  }

  static Future<String?> createSafFileFromPath({
    required String treeUri,
    required String relativeDir,
    required String fileName,
    required String mimeType,
    required String srcPath,
  }) async {
    final result = await _channel.invokeMethod('safCreateFromPath', {
      'tree_uri': treeUri,
      'relative_dir': relativeDir,
      'file_name': fileName,
      'mime_type': mimeType,
      'src_path': srcPath,
    });
    return result as String?;
  }

  static Future<Map<String, dynamic>> createUniqueSafFileFromPath({
    required String treeUri,
    required String relativeDir,
    required String fileName,
    required String mimeType,
    required String srcPath,
    String preservedSuffix = '',
  }) {
    return _invokeMap('safCreateUniqueFromPath', {
      'tree_uri': treeUri,
      'relative_dir': relativeDir,
      'file_name': fileName,
      'mime_type': mimeType,
      'src_path': srcPath,
      'preserved_suffix': preservedSuffix,
    });
  }

  static Future<Map<String, dynamic>> createCollisionAwareSafFileFromPath({
    required String treeUri,
    required String relativeDir,
    required String cleanFileName,
    required String variantFileName,
    required String mimeType,
    required String srcPath,
    String preservedSuffix = '',
  }) {
    return _invokeMap('safCreateCollisionAwareFromPath', {
      'tree_uri': treeUri,
      'relative_dir': relativeDir,
      'clean_file_name': cleanFileName,
      'variant_file_name': variantFileName,
      'mime_type': mimeType,
      'src_path': srcPath,
      'preserved_suffix': preservedSuffix,
    });
  }

  static Future<void> openContentUri(String uri, {String mimeType = ''}) async {
    await _channel.invokeMethod('openContentUri', {
      'uri': uri,
      'mime_type': mimeType,
    });
  }

  static Future<bool> shareContentUri(String uri, {String title = ''}) async {
    final result = await _channel.invokeMethod('shareContentUri', {
      'uri': uri,
      'title': title,
    });
    return result as bool? ?? false;
  }

  static Future<bool> shareMultipleContentUris(
    List<String> uris, {
    String title = '',
  }) async {
    final result = await _channel.invokeMethod('shareMultipleContentUris', {
      'uris': uris,
      'title': title,
    });
    return result as bool? ?? false;
  }

  static Future<String> getLyricsLRC(
    String spotifyId,
    String trackName,
    String artistName, {
    String? filePath,
    int durationMs = 0,
  }) async {
    final result = await _channel.invokeMethod('getLyricsLRC', {
      'spotify_id': spotifyId,
      'track_name': trackName,
      'artist_name': artistName,
      'file_path': filePath ?? '',
      'duration_ms': durationMs,
    });
    return result as String;
  }

  static Future<Map<String, dynamic>> getLyricsLRCWithSource(
    String spotifyId,
    String trackName,
    String artistName, {
    String? filePath,
    int durationMs = 0,
  }) {
    return _invokeMap('getLyricsLRCWithSource', {
      'spotify_id': spotifyId,
      'track_name': trackName,
      'artist_name': artistName,
      'file_path': filePath ?? '',
      'duration_ms': durationMs,
    });
  }

  static Future<Map<String, dynamic>> embedLyricsToFile(
    String filePath,
    String lyrics,
  ) {
    return _invokeMap('embedLyricsToFile', {
      'file_path': filePath,
      'lyrics': lyrics,
    });
  }

  static Future<void> cleanupConnections() async {
    await _channel.invokeMethod('cleanupConnections');
  }

  static Future<Map<String, dynamic>> downloadCoverToFile(
    String coverUrl,
    String outputPath, {
    bool maxQuality = true,
  }) {
    return _invokeMap('downloadCoverToFile', {
      'cover_url': coverUrl,
      'output_path': outputPath,
      'max_quality': maxQuality,
    });
  }

  static Future<Map<String, dynamic>> extractCoverToFile(
    String audioPath,
    String outputPath,
  ) {
    return _invokeMap('extractCoverToFile', {
      'audio_path': audioPath,
      'output_path': outputPath,
    });
  }

  static Future<Map<String, dynamic>> fetchAndSaveLyrics({
    required String trackName,
    required String artistName,
    required String spotifyId,
    required int durationMs,
    required String outputPath,
    String audioFilePath = '',
  }) {
    return _invokeMap('fetchAndSaveLyrics', {
      'track_name': trackName,
      'artist_name': artistName,
      'spotify_id': spotifyId,
      'duration_ms': durationMs,
      'output_path': outputPath,
      'audio_file_path': audioFilePath,
    });
  }

  /// Providers not in the list are disabled.
  static Future<void> setLyricsProviders(List<String> providers) async {
    final providersJSON = jsonEncode(providers);
    await _channel.invokeMethod('setLyricsProviders', {
      'providers_json': providersJSON,
    });
  }

  static Future<List<String>> getLyricsProviders() async {
    final result = await _channel.invokeMethod('getLyricsProviders');
    return _decodeStringListResult(result, 'getLyricsProviders');
  }

  static Future<List<Map<String, dynamic>>>
  getAvailableLyricsProviders() async {
    final result = await _channel.invokeMethod('getAvailableLyricsProviders');
    return _decodeMapListResult(result, 'getAvailableLyricsProviders');
  }

  /// Sets advanced lyrics fetch options used by provider-specific integrations.
  static Future<void> setLyricsFetchOptions(
    Map<String, dynamic> options,
  ) async {
    final optionsJSON = jsonEncode(options);
    await _channel.invokeMethod('setLyricsFetchOptions', {
      'options_json': optionsJSON,
    });
  }

  static Future<Map<String, dynamic>> getLyricsFetchOptions() {
    return _invokeMap('getLyricsFetchOptions');
  }

  static Future<Map<String, dynamic>> reEnrichFile(
    Map<String, dynamic> request,
  ) {
    return _invokeMap('reEnrichFile', {'request_json': jsonEncode(request)});
  }

  static Future<Map<String, dynamic>> readFileMetadata(String filePath) {
    return _invokeMap('readFileMetadata', {'file_path': filePath});
  }

  /// Reads the tags and quality fields used for automatic Library display.
  ///
  /// Android's readAudioMetadata implementation can inspect most SAF files
  /// through /proc/self/fd, avoiding the full-file cache copy required by tag
  /// editing. Keep the complete reader as a compatibility fallback for
  /// malformed or incorrectly named files that the lightweight scanner could
  /// only identify from their filename.
  static Future<Map<String, dynamic>> readDisplayAudioMetadata(
    String filePath,
  ) async {
    final scanned = await readAudioMetadata(filePath);
    if (scanned != null &&
        scanned['error'] == null &&
        scanned['metadataFromFilename'] != true) {
      return normalizeScannedAudioMetadata(scanned);
    }
    return readFileMetadata(filePath);
  }

  static Future<Map<String, dynamic>> editFileMetadata(
    String filePath,
    Map<String, String> metadata,
  ) {
    return _invokeMap('editFileMetadata', {
      'file_path': filePath,
      'metadata_json': jsonEncode(metadata),
    });
  }

  /// Writes ISRC and label into an M4A/MP4 file as iTunes freeform atoms.
  /// FFmpeg's MP4 muxer drops these keys, so they must be written natively
  /// after the FFmpeg metadata pass. [filePath] must be a local file path.
  /// Only the keys present in [fields] are touched; an empty value clears it.
  static Future<Map<String, dynamic>> writeM4AFreeformTags(
    String filePath,
    Map<String, String> fields,
  ) {
    return _invokeMap('writeM4AFreeformTags', {
      'file_path': filePath,
      'metadata_json': jsonEncode(fields),
    });
  }

  /// Normalizes a decrypted AC-4 file to a standards-compliant ISO MP4 and
  /// injects the dac4 configuration box from the encrypted [sourcePath]. The
  /// FFmpeg mov muxer drops dac4 and writes a QuickTime-flavored container that
  /// players reject, so this repair is required for AC-4 to be playable.
  static Future<Map<String, dynamic>> ensureAC4Config(
    String filePath,
    String sourcePath,
  ) {
    return _invokeMap('ensureAC4Config', {
      'file_path': filePath,
      'source_path': sourcePath,
    });
  }

  /// Writes iTunes-style metadata (and cover art) into an AC-4 MP4. Returns a
  /// map whose `handled` flag is `true` when the file was AC-4 and metadata was
  /// written natively, signalling the caller to skip the FFmpeg metadata pass
  /// (which would re-wrap the file as QuickTime).
  static Future<Map<String, dynamic>> writeAC4Metadata(
    String filePath,
    Map<String, String> metadata,
    String coverPath,
  ) {
    return _invokeMap('writeAC4Metadata', {
      'file_path': filePath,
      'metadata_json': jsonEncode(metadata),
      'cover_path': coverPath,
    });
  }

  /// Rewrites ARTIST/ALBUMARTIST Vorbis comments as multiple split entries
  /// using the native Go FLAC writer, fixing FFmpeg's tag deduplication.
  static Future<Map<String, dynamic>> rewriteSplitArtistTags(
    String filePath,
    String artist,
    String albumArtist,
  ) {
    return _invokeMap('rewriteSplitArtistTags', {
      'file_path': filePath,
      'artist': artist,
      'album_artist': albumArtist,
    });
  }

  static Future<bool> writeTempToSaf(String tempPath, String safUri) async {
    final map = await _invokeMap('writeTempToSaf', {
      'temp_path': tempPath,
      'saf_uri': safUri,
    });
    return map['success'] == true;
  }

  static Future<bool> writeSafSidecarLrc(String safUri, String lyrics) async {
    final map = await _invokeMap('writeSafSidecarLrc', {
      'saf_uri': safUri,
      'lyrics': lyrics,
    });
    return map['success'] == true;
  }

  static Future<void> startDownloadService({
    String trackName = '',
    String artistName = '',
    int queueCount = 0,
  }) async {
    await _channel.invokeMethod('startDownloadService', {
      'track_name': trackName,
      'artist_name': artistName,
      'queue_count': queueCount,
    });
  }

  static Future<void> stopDownloadService() async {
    await _channel.invokeMethod('stopDownloadService');
  }

  static Future<void> updateDownloadServiceProgress({
    required String trackName,
    required String artistName,
    required int progress,
    required int total,
    required int queueCount,
    String status = 'downloading',
  }) async {
    await _channel.invokeMethod('updateDownloadServiceProgress', {
      'track_name': trackName,
      'artist_name': artistName,
      'progress': progress,
      'total': total,
      'queue_count': queueCount,
      'status': status,
    });
  }

  static Future<bool> isDownloadServiceRunning() async {
    final result = await _channel.invokeMethod('isDownloadServiceRunning');
    return result as bool;
  }

  /// iOS only: keep in-flight downloads running briefly after backgrounding.
  static Future<void> beginBackgroundDownloadTask() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('beginBackgroundDownloadTask');
    } catch (_) {}
  }

  /// iOS only: stop the background-time extension (queue finished or paused).
  static Future<void> endBackgroundDownloadTask() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('endBackgroundDownloadTask');
    } catch (_) {}
  }

  static Future<void> startNativeDownloadWorker({
    required List<Map<String, dynamic>> requests,
    Map<String, dynamic> settings = const {},
  }) async {
    final requestsJson = jsonEncode(requests);
    final settingsJson = jsonEncode(settings);
    final payloadDir = await _nativeWorkerPayloadDir();
    await _cleanupNativeWorkerPayloads(payloadDir);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final requestPath = '${payloadDir.path}/requests_$stamp.json';
    final settingsPath = '${payloadDir.path}/settings_$stamp.json';
    await File(requestPath).writeAsString(requestsJson, flush: true);
    await File(settingsPath).writeAsString(settingsJson, flush: true);
    try {
      await _channel.invokeMethod('startNativeDownloadWorker', {
        'requests_path': requestPath,
        'settings_path': settingsPath,
      });
    } catch (_) {
      unawaited(_deleteFileIfExists(requestPath));
      unawaited(_deleteFileIfExists(settingsPath));
      rethrow;
    }
  }

  static Future<void> _deleteFileIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static Future<Directory> _nativeWorkerPayloadDir() async {
    final tempDir = await getTemporaryDirectory();
    final payloadDir = Directory('${tempDir.path}/native_worker_payloads');
    if (!await payloadDir.exists()) {
      await payloadDir.create(recursive: true);
    }
    return payloadDir;
  }

  static Future<void> _cleanupNativeWorkerPayloads(Directory payloadDir) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    try {
      await for (final entity in payloadDir.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static Future<void> pauseNativeDownloadWorker() async {
    await _channel.invokeMethod('pauseNativeDownloadWorker');
  }

  static Future<void> resumeNativeDownloadWorker() async {
    await _channel.invokeMethod('resumeNativeDownloadWorker');
  }

  static Future<void> cancelNativeDownloadWorker() async {
    await _channel.invokeMethod('cancelNativeDownloadWorker');
  }

  /// [sinceStateSerial]: pass the `state_serial` of the last fully-processed
  /// snapshot; when the native state hasn't advanced past it, the heavy
  /// per-item payload (which grows with every completed item) is omitted and
  /// only compact progress fields are returned.
  static Future<Map<String, dynamic>> getNativeDownloadWorkerSnapshot({
    int sinceStateSerial = 0,
  }) async {
    final result = await _channel.invokeMethod(
      'getNativeDownloadWorkerSnapshot',
      {'since_state_serial': sinceStateSerial},
    );
    return _decodeMapResult(result);
  }

  static Future<int> getTrackCacheSize() async {
    await _ensurePersistentLookupCachesLoaded();
    final result = await _channel.invokeMethod('getTrackCacheSize');
    return (result as int) + _lookupCacheSize();
  }

  static Future<void> clearTrackCache() async {
    await _clearLookupCaches();
    await _channel.invokeMethod('clearTrackCache');
  }

  static Future<Map<String, dynamic>> getProviderMetadata(
    String providerId,
    String resourceType,
    String resourceId,
  ) {
    return _cachedInvoke(
      _providerMetadataCacheKey(providerId, resourceType, resourceId),
      _metadataCache,
      _metadataInFlight,
      _metadataCacheTtl,
      _metadataPersistentCacheKey,
      () async {
        final result = await _channel.invokeMethod('getProviderMetadata', {
          'provider_id': providerId,
          'resource_type': resourceType,
          'resource_id': resourceId,
        });
        if (result == null) {
          throw Exception(
            'getProviderMetadata returned null for $providerId:$resourceType:$resourceId',
          );
        }
        return _decodeRequiredMapResult(result, 'getProviderMetadata');
      },
    );
  }

  static Future<Map<String, dynamic>> searchDeezerByISRC(
    String isrc, {
    String? itemId,
  }) {
    return _invokeMap('searchDeezerByISRC', {
      'isrc': isrc,
      'item_id': itemId ?? '',
    });
  }

  static Future<Map<String, String>?> getDeezerExtendedMetadata(
    String trackId,
  ) async {
    try {
      final result = await _channel.invokeMethod('getDeezerExtendedMetadata', {
        'track_id': trackId,
      });
      if (result == null) return null;
      final data = _decodeRequiredMapResult(
        result,
        'getDeezerExtendedMetadata',
      );
      return {
        'genre': data['genre'] as String? ?? '',
        'label': data['label'] as String? ?? '',
        'copyright': data['copyright'] as String? ?? '',
      };
    } catch (e) {
      _log.w('Failed to get Deezer extended metadata for $trackId: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> convertSpotifyToDeezer(
    String resourceType,
    String spotifyId,
  ) {
    return _cachedInvoke(
      _providerMetadataCacheKey('spotify-to-deezer', resourceType, spotifyId),
      _metadataCache,
      _metadataInFlight,
      _metadataCacheTtl,
      _metadataPersistentCacheKey,
      () => _invokeMap('convertSpotifyToDeezer', {
        'resource_type': resourceType,
        'spotify_id': spotifyId,
      }),
    );
  }

  static Future<Map<String, dynamic>> getGoLogsSince(int index) async {
    final result = await _channel.invokeMethod('getLogsSince', {
      'index': index,
    });
    return _decodeRequiredMapResult(result, 'getGoLogsSince');
  }

  static Future<void> clearGoLogs() async {
    await _channel.invokeMethod('clearLogs');
  }

  /// Ask the Go backend to GC and return freed heap to the OS. Best-effort:
  /// safe to call on memory pressure or when the app is backgrounded.
  static Future<void> releaseNativeMemory({bool underPressure = false}) async {
    try {
      await _channel.invokeMethod(
        underPressure ? 'releaseMemoryUnderPressure' : 'releaseMemory',
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getGoRuntimeMetrics() async {
    final result = await _channel.invokeMethod('getGoRuntimeMetrics');
    return _decodeRequiredMapResult(result, 'getGoRuntimeMetrics');
  }

  /// Tells the backend the app's display language so metadata providers
  /// localize by it instead of IP geolocation. Best-effort.
  static Future<void> setMetadataLanguage(String tag) async {
    try {
      await _channel.invokeMethod('setMetadataLanguage', {'tag': tag});
    } catch (_) {}
  }

  static Future<void> setGoLoggingEnabled(bool enabled) async {
    await _channel.invokeMethod('setLoggingEnabled', {'enabled': enabled});
  }

  static Future<void> initExtensionSystem(
    String extensionsDir,
    String dataDir,
  ) async {
    _log.d('initExtensionSystem: $extensionsDir, $dataDir');
    await _channel.invokeMethod('initExtensionSystem', {
      'extensions_dir': extensionsDir,
      'data_dir': dataDir,
    });
  }

  static Future<Map<String, dynamic>> loadExtensionsFromDir(String dirPath) {
    _log.d('loadExtensionsFromDir: $dirPath');
    return _invokeMap('loadExtensionsFromDir', {'dir_path': dirPath});
  }

  static Future<Map<String, dynamic>> loadExtensionFromPath(
    String filePath,
  ) async {
    _log.d('loadExtensionFromPath: $filePath');
    await _clearLookupCaches();
    return _invokeMap('loadExtensionFromPath', {'file_path': filePath});
  }

  static Future<void> unloadExtension(String extensionId) async {
    _log.d('unloadExtension: $extensionId');
    await _clearLookupCaches();
    await _channel.invokeMethod('unloadExtension', {
      'extension_id': extensionId,
    });
  }

  static Future<void> removeExtension(String extensionId) async {
    _log.d('removeExtension: $extensionId');
    await _clearLookupCaches();
    await _channel.invokeMethod('removeExtension', {
      'extension_id': extensionId,
    });
  }

  static Future<Map<String, dynamic>> upgradeExtension(String filePath) async {
    _log.d('upgradeExtension: $filePath');
    await _clearLookupCaches();
    return _invokeMap('upgradeExtension', {'file_path': filePath});
  }

  static Future<Map<String, dynamic>> checkExtensionUpgrade(String filePath) {
    _log.d('checkExtensionUpgrade: $filePath');
    return _invokeMap('checkExtensionUpgrade', {'file_path': filePath});
  }

  static Future<List<Map<String, dynamic>>> getInstalledExtensions() async {
    final result = await _channel.invokeMethod('getInstalledExtensions');
    return _decodeMapListResult(result, 'getInstalledExtensions');
  }

  static Future<void> setExtensionEnabled(
    String extensionId,
    bool enabled,
  ) async {
    _log.d('setExtensionEnabled: $extensionId = $enabled');
    await _clearLookupCaches();
    await _channel.invokeMethod('setExtensionEnabled', {
      'extension_id': extensionId,
      'enabled': enabled,
    });
  }

  static Future<void> setProviderPriority(List<String> providerIds) async {
    _log.d('setProviderPriority: $providerIds');
    await _clearLookupCaches();
    await _channel.invokeMethod('setProviderPriority', {
      'priority': jsonEncode(providerIds),
    });
  }

  static Future<List<String>> getProviderPriority() async {
    final result = await _channel.invokeMethod('getProviderPriority');
    return _decodeStringListResult(result, 'getProviderPriority');
  }

  static Future<void> setDownloadFallbackExtensionIds(
    List<String>? extensionIds,
  ) async {
    _log.d('setDownloadFallbackExtensionIds: $extensionIds');
    await _clearLookupCaches();
    await _channel.invokeMethod('setDownloadFallbackExtensionIds', {
      'extension_ids': extensionIds == null ? '' : jsonEncode(extensionIds),
    });
  }

  static Future<void> setMetadataProviderPriority(
    List<String> providerIds,
  ) async {
    _log.d('setMetadataProviderPriority: $providerIds');
    await _clearLookupCaches();
    await _channel.invokeMethod('setMetadataProviderPriority', {
      'priority': jsonEncode(providerIds),
    });
  }

  static Future<List<String>> getMetadataProviderPriority() async {
    final result = await _channel.invokeMethod('getMetadataProviderPriority');
    return _decodeStringListResult(result, 'getMetadataProviderPriority');
  }

  static Future<Map<String, dynamic>> getExtensionSettings(String extensionId) {
    return _invokeMap('getExtensionSettings', {'extension_id': extensionId});
  }

  static Future<Map<String, dynamic>> checkExtensionHealth(String extensionId) {
    return _invokeMap('checkExtensionHealth', {'extension_id': extensionId});
  }

  static Future<void> setExtensionSettings(
    String extensionId,
    Map<String, dynamic> settings,
  ) async {
    _log.d('setExtensionSettings: $extensionId');
    await _clearLookupCaches();
    await _channel.invokeMethod('setExtensionSettings', {
      'extension_id': extensionId,
      'settings': jsonEncode(settings),
    });
  }

  static Future<Map<String, dynamic>> invokeExtensionAction(
    String extensionId,
    String actionName,
  ) async {
    _log.d('invokeExtensionAction: $extensionId.$actionName');
    final result = await _channel.invokeMethod('invokeExtensionAction', {
      'extension_id': extensionId,
      'action': actionName,
    });
    if (result == null || (result as String).isEmpty) {
      return {'success': true};
    }
    return _decodeRequiredMapResult(result, 'invokeExtensionAction');
  }

  static Future<List<Map<String, dynamic>>> searchTracksWithMetadataProviders(
    String query, {
    int limit = 20,
    bool includeExtensions = true,
  }) async {
    _log.d(
      'searchTracksWithMetadataProviders: "$query", includeExtensions=$includeExtensions',
    );
    final result = await _channel.invokeMethod(
      'searchTracksWithMetadataProviders',
      {'query': query, 'limit': limit, 'include_extensions': includeExtensions},
    );
    return _decodeMapListResult(result, 'searchTracksWithMetadataProviders');
  }

  static Future<List<Map<String, dynamic>>> searchTracksWithMetadataProvider(
    String extensionId,
    String query, {
    int limit = 20,
  }) async {
    _log.d('searchTracksWithMetadataProvider: $extensionId, query="$query"');
    final result = await _channel.invokeMethod(
      'searchTracksWithMetadataProvider',
      {'extension_id': extensionId, 'query': query, 'limit': limit},
    );
    return _decodeMapListResult(result, 'searchTracksWithMetadataProvider');
  }

  static Future<List<Map<String, dynamic>>> findCollectionAcrossExtensions({
    required String name,
    required String artists,
    required String type,
    required String sourceExtensionId,
  }) async {
    final requestJson = jsonEncode({
      'name': name,
      'artists': artists,
      'type': type,
      'source_extension_id': sourceExtensionId,
    });
    final result = await _channel.invokeMethod(
      'findCollectionAcrossExtensions',
      requestJson,
    );
    return _decodeMapListResult(result, 'findCollectionAcrossExtensions');
  }

  static Future<void> cleanupExtensions() async {
    _log.d('cleanupExtensions');
    await _channel.invokeMethod('cleanupExtensions');
  }

  static Future<Map<String, dynamic>?> getExtensionPendingAuth(
    String extensionId,
  ) async {
    final result = await _channel.invokeMethod('getExtensionPendingAuth', {
      'extension_id': extensionId,
    });
    return _decodeNullableMapResult(result, 'getExtensionPendingAuth');
  }

  static Future<void> setExtensionAuthCode(
    String extensionId,
    String authCode,
  ) async {
    _log.d('setExtensionAuthCode: $extensionId');
    await _channel.invokeMethod('setExtensionAuthCode', {
      'extension_id': extensionId,
      'auth_code': authCode,
    });
  }

  static final Map<String, Future<bool>> _extensionSessionGrantCompletions =
      <String, Future<bool>>{};

  static Future<bool> completeExtensionSessionGrant(
    String extensionId,
    String grant,
  ) {
    final normalizedExtensionId = extensionId.trim();
    final key = normalizedExtensionId.toLowerCase();
    final activeCompletion = _extensionSessionGrantCompletions[key];
    if (activeCompletion != null) {
      _log.d(
        'Joining active completeExtensionSessionGrant: $normalizedExtensionId',
      );
      return activeCompletion;
    }

    late final Future<bool> completion;
    completion = _completeExtensionSessionGrant(normalizedExtensionId, grant)
        .whenComplete(() {
          if (identical(_extensionSessionGrantCompletions[key], completion)) {
            _extensionSessionGrantCompletions.remove(key);
          }
        });
    _extensionSessionGrantCompletions[key] = completion;
    return completion;
  }

  static Future<bool> _completeExtensionSessionGrant(
    String extensionId,
    String grant,
  ) async {
    _log.d('completeExtensionSessionGrant: $extensionId');
    final result = await _channel.invokeMethod(
      'completeExtensionSessionGrant',
      {'extension_id': extensionId, 'grant': grant},
    );
    final success = result != false;
    _extensionSessionGrantEvents.add(
      ExtensionSessionGrantEvent(extensionId: extensionId, success: success),
    );
    return success;
  }

  static Future<void> setExtensionTokens(
    String extensionId, {
    required String accessToken,
    String? refreshToken,
    int? expiresIn,
  }) async {
    _log.d('setExtensionTokens: $extensionId');
    await _channel.invokeMethod('setExtensionTokens', {
      'extension_id': extensionId,
      'access_token': accessToken,
      'refresh_token': refreshToken ?? '',
      'expires_in': expiresIn ?? 0,
    });
  }

  static Future<void> clearExtensionPendingAuth(String extensionId) async {
    await _channel.invokeMethod('clearExtensionPendingAuth', {
      'extension_id': extensionId,
    });
  }

  static Future<bool> isExtensionAuthenticated(String extensionId) async {
    final result = await _channel.invokeMethod('isExtensionAuthenticated', {
      'extension_id': extensionId,
    });
    return result as bool;
  }

  static Future<List<Map<String, dynamic>>> getAllPendingAuthRequests() async {
    final result = await _channel.invokeMethod('getAllPendingAuthRequests');
    return _decodeMapListResult(result, 'getAllPendingAuthRequests');
  }

  static Future<Map<String, dynamic>?> getPendingFFmpegCommand(
    String commandId,
  ) async {
    final result = await _channel.invokeMethod('getPendingFFmpegCommand', {
      'command_id': commandId,
    });
    return _decodeNullableMapResult(result, 'getPendingFFmpegCommand');
  }

  static Future<void> setFFmpegCommandResult(
    String commandId, {
    required bool success,
    String output = '',
    String error = '',
  }) async {
    await _channel.invokeMethod('setFFmpegCommandResult', {
      'command_id': commandId,
      'success': success,
      'output': output,
      'error': error,
    });
  }

  static Future<List<Map<String, dynamic>>>
  getAllPendingFFmpegCommands() async {
    final result = await _channel.invokeMethod('getAllPendingFFmpegCommands');
    return _decodeMapListResult(result, 'setFFmpegCommandResult');
  }

  static Future<List<Map<String, dynamic>>> customSearchWithExtension(
    String extensionId,
    String query, {
    Map<String, dynamic>? options,
    bool cancelPrevious = false,
  }) async {
    final optionsJson = options != null ? jsonEncode(options) : '';
    final scopeKey = 'customSearch:${extensionId.trim()}';
    final cacheKey = [
      scopeKey,
      query,
      jsonEncode(_canonicalizeJsonLike(options ?? const <String, dynamic>{})),
    ].join('\n');
    final inFlight = _customSearchInFlight[cacheKey];
    if (inFlight != null) return _copyMapList(await inFlight.future);
    if (cancelPrevious) {
      _cancelCustomSearchInFlightForScope(scopeKey, exceptKey: cacheKey);
    }

    final cached = _getCachedMapList(_customSearchCache, cacheKey);
    if (cached != null) return cached;

    final requestId = _nextExtensionRequestId('customSearch', extensionId);
    final generation = _lookupCacheGeneration;
    final future = (() async {
      final result = await _channel.invokeMethod('customSearchWithExtension', {
        'extension_id': extensionId,
        'query': query,
        'options': optionsJson,
        'request_id': requestId,
      });
      final decoded = _decodeMapListResult(result, 'customSearchWithExtension');
      if (generation == _lookupCacheGeneration) {
        _putMemoryCachedMapList(
          _customSearchCache,
          cacheKey,
          decoded,
          _customSearchCacheTtl,
        );
      }
      return decoded;
    })();

    final entry = _BridgeInFlight<List<Map<String, dynamic>>>(
      requestId: requestId,
      scopeKey: scopeKey,
      future: future,
    );
    _customSearchInFlight[cacheKey] = entry;
    try {
      return _copyMapList(await future);
    } finally {
      if (identical(_customSearchInFlight[cacheKey], entry)) {
        _customSearchInFlight.remove(cacheKey);
      }
    }
  }

  static Future<Map<String, dynamic>?> handleURLWithExtension(
    String url,
  ) async {
    final cacheKey = url.trim();
    if (cacheKey.isEmpty) return null;

    final cached = _getCachedMap(_urlHandleCache, cacheKey);
    if (cached != null) return cached;

    final inFlight = _urlHandleInFlight[cacheKey];
    if (inFlight != null) return _copyNullableStringMap(await inFlight);

    final generation = _lookupCacheGeneration;
    final future = (() async {
      try {
        final result = await _channel.invokeMethod('handleURLWithExtension', {
          'url': url,
        });
        final decoded = _decodeNullableMapResult(
          result,
          'handleURLWithExtension',
        );
        if (generation == _lookupCacheGeneration &&
            decoded != null &&
            _isCacheableURLHandleResult(decoded)) {
          _putMemoryCachedMap(
            _urlHandleCache,
            cacheKey,
            decoded,
            _urlHandleCacheTtl,
          );
        }
        return decoded;
      } catch (e) {
        return null;
      }
    })();

    _urlHandleInFlight[cacheKey] = future;
    try {
      return _copyNullableStringMap(await future);
    } finally {
      if (identical(_urlHandleInFlight[cacheKey], future)) {
        _urlHandleInFlight.remove(cacheKey);
      }
    }
  }

  static bool _isCacheableURLHandleResult(Map<String, dynamic> result) {
    final type = result['type']?.toString();
    if (type == null || type.isEmpty) return false;
    if (type == 'track') {
      final track = result['track'];
      if (track is! Map) return false;
      final name = track['name']?.toString().trim() ?? '';
      return name.isNotEmpty;
    }
    return type == 'album' || type == 'playlist' || type == 'artist';
  }

  static void _putMemoryCachedMap(
    Map<String, _BridgeCacheEntry> cache,
    String key,
    Map<String, dynamic> value,
    Duration ttl,
  ) {
    _pruneExpiredBridgeCache(cache);
    while (cache.length >= _bridgeCacheMaxEntries && cache.isNotEmpty) {
      cache.remove(cache.keys.first);
    }
    cache[key] = _BridgeCacheEntry(
      value: _copyStringMap(value),
      expiresAt: DateTime.now().add(ttl),
    );
  }

  static List<Map<String, dynamic>>? _getCachedMapList(
    Map<String, _BridgeListCacheEntry> cache,
    String key,
  ) {
    _pruneExpiredBridgeListCache(cache);
    final entry = cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      cache.remove(key);
      return null;
    }
    return _copyMapList(entry.value);
  }

  static void _putMemoryCachedMapList(
    Map<String, _BridgeListCacheEntry> cache,
    String key,
    List<Map<String, dynamic>> value,
    Duration ttl,
  ) {
    _pruneExpiredBridgeListCache(cache);
    while (cache.length >= _bridgeCacheMaxEntries && cache.isNotEmpty) {
      cache.remove(cache.keys.first);
    }
    cache[key] = _BridgeListCacheEntry(
      value: _copyMapList(value),
      expiresAt: DateTime.now().add(ttl),
    );
  }

  static void _pruneExpiredBridgeListCache(
    Map<String, _BridgeListCacheEntry> cache,
  ) {
    if (cache.isEmpty) return;
    final now = DateTime.now();
    cache.removeWhere((_, entry) => now.isAfter(entry.expiresAt));
  }

  static Future<String?> findURLHandler(String url) async {
    final result = await _channel.invokeMethod('findURLHandler', {'url': url});
    if (result == null || result == '') return null;
    return result as String;
  }

  /// MusicBrainz genre and album artist for an ISRC; empty strings when a
  /// lookup finds nothing. One channel call covers both fields to spare
  /// MusicBrainz's 1 req/s budget.
  static Future<({String genre, String albumArtist})> fetchMusicBrainzTags({
    required String isrc,
    String albumName = '',
  }) async {
    final result = await _channel.invokeMethod('fetchMusicBrainzTags', {
      'isrc': isrc,
      'album_name': albumName,
    });
    final decoded = _decodeMapResult(result);
    return (
      genre: decoded['genre']?.toString() ?? '',
      albumArtist: decoded['album_artist']?.toString() ?? '',
    );
  }

  /// Streaming-platform links for a track, keyed by song.link platform ID.
  /// Served from the Go-side memory cache; throws when the lookup fails.
  static Future<Map<String, String>> getTrackPlatformLinks({
    String spotifyId = '',
    String isrc = '',
  }) async {
    final result = await _channel.invokeMethod('getTrackPlatformLinks', {
      'spotify_id': spotifyId,
      'isrc': isrc,
    });
    final decoded = _decodeMapResult(result);
    final platforms = decoded['platforms'];
    if (platforms is! Map) return const {};
    return platforms.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  static Future<Map<String, dynamic>?> getExtensionHomeFeed(
    String extensionId, {
    bool cancelPrevious = false,
  }) async {
    final cacheKey = 'homeFeed:${extensionId.trim()}';
    final inFlight = _homeFeedInFlight[cacheKey];
    if (inFlight != null) {
      if (!cancelPrevious) {
        return _copyNullableStringMap(await inFlight.future);
      }
      _cancelExtensionRequestUnawaited(inFlight.requestId);
      _homeFeedInFlight.remove(cacheKey);
    }

    final requestId = _nextExtensionRequestId('homeFeed', extensionId);
    final future = (() async {
      try {
        final result = await _channel.invokeMethod('getExtensionHomeFeed', {
          'extension_id': extensionId,
          'request_id': requestId,
        });
        return _decodeNullableMapResult(result, 'getExtensionHomeFeed');
      } catch (e) {
        _log.e('getExtensionHomeFeed failed: $e');
        return null;
      }
    })();
    final entry = _BridgeInFlight<Map<String, dynamic>?>(
      requestId: requestId,
      scopeKey: cacheKey,
      future: future,
    );
    _homeFeedInFlight[cacheKey] = entry;
    try {
      return _copyNullableStringMap(await future);
    } finally {
      if (identical(_homeFeedInFlight[cacheKey], entry)) {
        _homeFeedInFlight.remove(cacheKey);
      }
    }
  }

  static Future<void> setLibraryCoverCacheDir(String cacheDir) async {
    _log.i('setLibraryCoverCacheDir: $cacheDir');
    await _channel.invokeMethod('setLibraryCoverCacheDir', {
      'cache_dir': cacheDir,
    });
  }

  static Future<List<Map<String, dynamic>>> scanLibraryFolder(
    String folderPath,
  ) async {
    _log.i('scanLibraryFolder: $folderPath');
    final result = await _channel.invokeMethod('scanLibraryFolder', {
      'folder_path': folderPath,
    });
    return _decodeMapListResultAsync(result, 'scanLibraryFolder');
  }

  static Future<Map<String, dynamic>> scanLibraryFolderIncremental(
    String folderPath,
    Map<String, int> existingFiles,
  ) async {
    _log.i(
      'scanLibraryFolderIncremental: $folderPath (${existingFiles.length} existing files)',
    );
    final result = await _channel.invokeMethod('scanLibraryFolderIncremental', {
      'folder_path': folderPath,
      'existing_files': jsonEncode(existingFiles),
    });
    return _decodeRequiredMapResultAsync(
      result,
      'scanLibraryFolderIncremental',
    );
  }

  static Future<Map<String, dynamic>> scanLibraryFolderIncrementalFromSnapshot(
    String folderPath,
    String snapshotPath,
  ) async {
    final result = await _channel.invokeMethod(
      'scanLibraryFolderIncrementalFromSnapshot',
      {'folder_path': folderPath, 'snapshot_path': snapshotPath},
    );
    return _decodeRequiredMapResultAsync(
      result,
      'scanLibraryFolderIncrementalFromSnapshot',
    );
  }

  static Future<List<Map<String, dynamic>>> scanSafTree(String treeUri) async {
    _log.i('scanSafTree: $treeUri');
    final result = await _channel.invokeMethod('scanSafTree', {
      'tree_uri': treeUri,
    });
    return _decodeMapListResultAsync(result, 'scanSafTree');
  }

  static Future<Map<String, dynamic>> scanSafTreeIncremental(
    String treeUri,
    Map<String, int> existingFiles,
  ) async {
    _log.i(
      'scanSafTreeIncremental: $treeUri (${existingFiles.length} existing files)',
    );
    final result = await _channel.invokeMethod('scanSafTreeIncremental', {
      'tree_uri': treeUri,
      'existing_files': jsonEncode(existingFiles),
    });
    return _decodeRequiredMapResultAsync(result, 'scanSafTreeIncremental');
  }

  static Future<Map<String, dynamic>> scanSafTreeIncrementalFromSnapshot(
    String treeUri,
    String snapshotPath,
  ) async {
    final result = await _channel.invokeMethod(
      'scanSafTreeIncrementalFromSnapshot',
      {'tree_uri': treeUri, 'snapshot_path': snapshotPath},
    );
    return _decodeRequiredMapResultAsync(
      result,
      'scanSafTreeIncrementalFromSnapshot',
    );
  }

  static Future<Map<String, int>> getSafFileModTimes(List<String> uris) async {
    final map = await _invokeMap('getSafFileModTimes', {
      'uris': jsonEncode(uris),
    });
    return map.map((key, value) => MapEntry(key, (value as num).toInt()));
  }

  static Future<Map<String, dynamic>> getLibraryScanProgress() async {
    final result = await _channel.invokeMethod('getLibraryScanProgress');
    return _decodeMapResult(result);
  }

  static Stream<Map<String, dynamic>> libraryScanProgressStream() {
    return _libraryScanProgressEvents.receiveBroadcastStream().map(
      _decodeMapResult,
    );
  }

  static Future<void> cancelLibraryScan() async {
    await _channel.invokeMethod('cancelLibraryScan');
  }

  static Object? _decodeJsonResult(dynamic result) {
    if (result is String) {
      if (result.isEmpty) return null;
      return jsonDecode(result);
    }
    return result;
  }

  static Future<Object?> _decodeJsonResultAsync(dynamic result) async {
    if (result is Map && result[_jsonResultFileKey] is String) {
      final file = File(result[_jsonResultFileKey] as String);
      try {
        final contents = await file.readAsString();
        if (contents.isEmpty) return null;
        return _decodeJsonStringAsync(contents);
      } finally {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    if (result is String &&
        result.length >= _backgroundJsonDecodeThresholdBytes) {
      return _decodeJsonStringAsync(result);
    }
    return _decodeJsonResult(result);
  }

  static Future<Object?> _decodeJsonStringAsync(String json) {
    if (json.length < _backgroundJsonDecodeThresholdBytes) {
      return Future<Object?>.value(jsonDecode(json));
    }
    return compute(_decodeJsonInBackground, json);
  }

  static Map<String, dynamic> _decodeRequiredMapResult(
    dynamic result,
    String method,
  ) {
    final decoded = _decodeJsonResult(result);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw FormatException(
      'Expected map result from $method, got ${decoded.runtimeType}',
    );
  }

  static Map<String, dynamic>? _decodeNullableMapResult(
    dynamic result,
    String method,
  ) {
    final decoded = _decodeJsonResult(result);
    if (decoded == null) return null;
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw FormatException(
      'Expected nullable map result from $method, got ${decoded.runtimeType}',
    );
  }

  static Future<Map<String, dynamic>> _decodeRequiredMapResultAsync(
    dynamic result,
    String method,
  ) async {
    final decoded = await _decodeJsonResultAsync(result);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw FormatException(
      'Expected map result from $method, got ${decoded.runtimeType}',
    );
  }

  static List<dynamic> _decodeRequiredListResult(
    dynamic result,
    String method,
  ) {
    final decoded = _decodeJsonResult(result);
    if (decoded is List) return decoded;
    throw FormatException(
      'Expected list result from $method, got ${decoded.runtimeType}',
    );
  }

  static Future<List<dynamic>> _decodeRequiredListResultAsync(
    dynamic result,
    String method,
  ) async {
    final decoded = await _decodeJsonResultAsync(result);
    if (decoded is List) return decoded;
    throw FormatException(
      'Expected list result from $method, got ${decoded.runtimeType}',
    );
  }

  static List<Map<String, dynamic>> _decodeMapListResult(
    dynamic result,
    String method,
  ) {
    return _decodeRequiredListResult(result, method).map((entry) {
      if (entry is Map) return entry.cast<String, dynamic>();
      throw FormatException(
        'Expected map entry from $method, got ${entry.runtimeType}',
      );
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> _decodeMapListResultAsync(
    dynamic result,
    String method,
  ) async {
    final decoded = await _decodeRequiredListResultAsync(result, method);
    return decoded.map((entry) {
      if (entry is Map) return entry.cast<String, dynamic>();
      throw FormatException(
        'Expected map entry from $method, got ${entry.runtimeType}',
      );
    }).toList();
  }

  static List<String> _decodeStringListResult(dynamic result, String method) {
    return _decodeRequiredListResult(result, method).map((entry) {
      if (entry is String) return entry;
      throw FormatException(
        'Expected string entry from $method, got ${entry.runtimeType}',
      );
    }).toList();
  }

  static Map<String, dynamic> _decodeMapResult(dynamic result) {
    if (result is Map) {
      return result.cast<String, dynamic>();
    }
    if (result is String) {
      if (result.isEmpty) return const <String, dynamic>{};
      final decoded = jsonDecode(result);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    }
    return const <String, dynamic>{};
  }

  /// Present the native iOS folder picker. The security-scoped bookmark is
  /// created inside the picker callback while its access grant is still
  /// active; creating it later from a bare path loses the grant.
  /// Returns null when the user cancels; throws on picker/bookmark failure.
  static Future<IosPickedDirectory?> pickIosDirectory() async {
    final result = await _channel.invokeMethod('pickIosDirectory');
    final map = _decodeNullableMapResult(result, 'pickIosDirectory');
    if (map == null) return null;
    final path = map['path'] as String? ?? '';
    final bookmark = map['bookmark'] as String? ?? '';
    if (path.isEmpty || bookmark.isEmpty) return null;
    return IosPickedDirectory(path: path, bookmark: bookmark);
  }

  /// Create a security-scoped bookmark from a filesystem path picked by
  /// FilePicker on iOS. Must be called while the picker session is still active.
  /// Returns base64-encoded bookmark data, or null on failure.
  static Future<String?> createIosBookmarkFromPath(String path) async {
    try {
      final result = await _channel.invokeMethod('createIosBookmarkFromPath', {
        'path': path,
      });
      return result as String?;
    } catch (e) {
      _log.w('Failed to create iOS bookmark from path: $e');
      return null;
    }
  }

  /// Resolve a base64-encoded iOS security-scoped bookmark and start accessing
  /// the resource. Returns the resolved filesystem path.
  /// The resource stays accessed until [stopAccessingIosBookmark] is called.
  static Future<String?> startAccessingIosBookmark(String bookmark) async {
    try {
      final result = await _channel.invokeMethod('startAccessingIosBookmark', {
        'bookmark': bookmark,
      });
      return result as String?;
    } catch (e) {
      _log.w('Failed to start accessing iOS bookmark: $e');
      return null;
    }
  }

  /// Stop accessing the currently active iOS security-scoped resource.
  static Future<void> stopAccessingIosBookmark() async {
    try {
      await _channel.invokeMethod('stopAccessingIosBookmark');
    } catch (e) {
      _log.w('Failed to stop accessing iOS bookmark: $e');
    }
  }

  static Future<Map<String, dynamic>?> readAudioMetadata(
    String filePath,
  ) async {
    try {
      final result = await _channel.invokeMethod('readAudioMetadata', {
        'file_path': filePath,
      });
      return _decodeNullableMapResult(result, 'readAudioMetadata');
    } catch (e) {
      _log.w('Failed to read audio metadata: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> runPostProcessingV2(
    String filePath, {
    Map<String, dynamic>? metadata,
  }) async {
    final input = <String, dynamic>{};
    if (filePath.startsWith('content://')) {
      input['uri'] = filePath;
    } else {
      input['path'] = filePath;
    }
    return _invokeMap('runPostProcessingV2', {
      'input': jsonEncode(input),
      'metadata': metadata != null ? jsonEncode(metadata) : '',
    });
  }

  static Future<void> initExtensionRepo(String cacheDir) async {
    _log.d('initExtensionRepo: $cacheDir');
    await _channel.invokeMethod('initExtensionRepo', {'cache_dir': cacheDir});
  }

  static Future<void> setRepoRegistryUrl(String registryUrl) async {
    _log.d('setRepoRegistryUrl: $registryUrl');
    await _channel.invokeMethod('setRepoRegistryUrl', {
      'registry_url': registryUrl,
    });
  }

  static Future<String> getRepoRegistryUrl() async {
    _log.d('getRepoRegistryUrl');
    final result = await _channel.invokeMethod('getRepoRegistryUrl');
    return result as String? ?? '';
  }

  static Future<void> clearRepoRegistryUrl() async {
    _log.d('clearRepoRegistryUrl');
    await _channel.invokeMethod('clearRepoRegistryUrl');
  }

  static Future<List<Map<String, dynamic>>> getRepoExtensions({
    bool forceRefresh = false,
  }) async {
    _log.d('getRepoExtensions (forceRefresh: $forceRefresh)');
    final result = await _channel.invokeMethod('getRepoExtensions', {
      'force_refresh': forceRefresh,
    });
    return _decodeMapListResult(result, 'getRepoExtensions');
  }

  static Future<List<Map<String, dynamic>>> searchRepoExtensions(
    String query, {
    String? category,
  }) async {
    _log.d('searchRepoExtensions: "$query" (category: $category)');
    final result = await _channel.invokeMethod('searchRepoExtensions', {
      'query': query,
      'category': category ?? '',
    });
    return _decodeMapListResult(result, 'searchRepoExtensions');
  }

  static Future<List<String>> getRepoCategories() async {
    final result = await _channel.invokeMethod('getRepoCategories');
    return _decodeStringListResult(result, 'getRepoCategories');
  }

  static Future<String> downloadRepoExtension(
    String extensionId,
    String destDir,
  ) async {
    _log.i('downloadRepoExtension: $extensionId to $destDir');
    final result = await _channel.invokeMethod('downloadRepoExtension', {
      'extension_id': extensionId,
      'dest_dir': destDir,
    });
    return result as String;
  }

  static Future<void> clearRepoCache() async {
    _log.d('clearRepoCache');
    await _channel.invokeMethod('clearRepoCache');
  }

  static Future<Map<String, dynamic>> parseCueSheet(
    String cuePath, {
    String audioDir = '',
  }) {
    _log.i('parseCueSheet: $cuePath (audioDir: $audioDir)');
    return _invokeMap('parseCueSheet', {
      'cue_path': cuePath,
      'audio_dir': audioDir,
    });
  }
}
