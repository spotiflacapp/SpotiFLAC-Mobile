import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/constants/app_info.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('UpdateChecker');

enum _ApkVariant { arm64, arm32, universal }

class _ApkAsset {
  final String name;
  final String url;
  final _ApkVariant variant;

  const _ApkAsset({
    required this.name,
    required this.url,
    required this.variant,
  });
}

class UpdateInfo {
  final String version;
  final String changelog;
  final String downloadUrl;
  final String? apkDownloadUrl;
  final DateTime publishedAt;
  final bool isPrerelease;

  /// How many stable (non-prerelease) releases are newer than the installed
  /// version. Drives the forced-update flow.
  final int releasesBehind;

  const UpdateInfo({
    required this.version,
    required this.changelog,
    required this.downloadUrl,
    this.apkDownloadUrl,
    required this.publishedAt,
    this.isPrerelease = false,
    this.releasesBehind = 0,
  });
}

class UpdateChecker {
  static const String _allReleasesApiUrl =
      'https://api.github.com/repos/${AppInfo.githubRepo}/releases';

  /// Installed versions this many stable releases (or more) behind must
  /// update before continuing to use the app.
  static const int forceUpdateThreshold = 3;

  // The releases payload is tens of KB and update cadence is days, not
  // minutes: serve from cache within the TTL and revalidate with ETag after,
  // instead of re-downloading the full list on every cold start.
  static const Duration _cacheTtl = Duration(hours: 6);
  static const String _cachedBodyKey = 'update_checker_releases_json';
  static const String _cachedAtKey = 'update_checker_releases_fetched_at';
  static const String _cachedEtagKey = 'update_checker_releases_etag';

  static Future<String?> _fetchReleasesBody() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedBody = prefs.getString(_cachedBodyKey);
    final cachedAt = prefs.getInt(_cachedAtKey) ?? 0;
    final ageMs = DateTime.now().millisecondsSinceEpoch - cachedAt;
    if (cachedBody != null && ageMs < _cacheTtl.inMilliseconds) {
      return cachedBody;
    }

    final cachedEtag = prefs.getString(_cachedEtagKey);
    final response = await http
        .get(
          Uri.parse('$_allReleasesApiUrl?per_page=30'),
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            if (cachedBody != null && cachedEtag != null)
              'If-None-Match': cachedEtag,
          },
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 304 && cachedBody != null) {
      await prefs.setInt(_cachedAtKey, DateTime.now().millisecondsSinceEpoch);
      return cachedBody;
    }
    if (response.statusCode != 200) {
      _log.w('GitHub API returned ${response.statusCode}');
      return cachedBody; // stale is better than none for the update prompt
    }

    await prefs.setString(_cachedBodyKey, response.body);
    final etag = response.headers['etag'];
    if (etag != null) {
      await prefs.setString(_cachedEtagKey, etag);
    }
    await prefs.setInt(_cachedAtKey, DateTime.now().millisecondsSinceEpoch);
    return response.body;
  }

  static Future<UpdateInfo?> checkForUpdate({String channel = 'stable'}) async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final releasesJson = await _fetchReleasesBody();
      if (releasesJson == null) {
        return null;
      }

      final releases = (jsonDecode(releasesJson) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      if (releases.isEmpty) {
        _log.i('No releases found');
        return null;
      }

      Map<String, dynamic>? releaseData;
      if (channel == 'preview') {
        releaseData = releases.first;
      } else {
        for (final release in releases) {
          if (release['prerelease'] != true) {
            releaseData = release;
            break;
          }
        }
      }
      if (releaseData == null) {
        _log.i('No stable release found');
        return null;
      }

      final tagName = releaseData['tag_name'] as String? ?? '';
      final latestVersion = tagName.replaceFirst('v', '');
      final isPrerelease = releaseData['prerelease'] as bool? ?? false;

      var releasesBehind = 0;
      for (final release in releases) {
        if (release['prerelease'] == true) continue;
        final version = (release['tag_name'] as String? ?? '').replaceFirst(
          'v',
          '',
        );
        if (version.isNotEmpty && _isNewerVersion(version, AppInfo.version)) {
          releasesBehind++;
        }
      }

      if (!_isNewerVersion(latestVersion, AppInfo.version)) {
        _log.i(
          'No update available (current: ${AppInfo.version}, latest: $latestVersion, channel: $channel)',
        );
        return null;
      }

      final body = releaseData['body'] as String? ?? 'No changelog available';
      final htmlUrl =
          releaseData['html_url'] as String? ?? '${AppInfo.githubUrl}/releases';
      final publishedAt =
          DateTime.tryParse(releaseData['published_at'] as String? ?? '') ??
          DateTime.now();

      final assets = _collectApkAssets(
        releaseData['assets'] as List<dynamic>? ?? const [],
      );
      final selectedAsset = await _selectApkForCurrentDevice(assets);
      final apkUrl = selectedAsset?.url;

      _log.i(
        'Update available: $latestVersion (prerelease: $isPrerelease, '
        'releases behind: $releasesBehind), '
        'APK asset: ${selectedAsset?.name ?? 'none'}, APK URL: $apkUrl',
      );

      return UpdateInfo(
        version: latestVersion,
        changelog: body,
        downloadUrl: htmlUrl,
        apkDownloadUrl: apkUrl,
        publishedAt: publishedAt,
        isPrerelease: isPrerelease,
        releasesBehind: releasesBehind,
      );
    } catch (e) {
      _log.e('Error checking for updates: $e');
      return null;
    }
  }

  static bool _isNewerVersion(String latest, String current) {
    try {
      final latestBase = latest.split('-').first;
      final currentBase = current.split('-').first;

      final latestParts = latestBase.split('.').map(int.parse).toList();
      final currentParts = currentBase.split('.').map(int.parse).toList();

      while (latestParts.length < 3) {
        latestParts.add(0);
      }
      while (currentParts.length < 3) {
        currentParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }

      final latestHasSuffix = latest.contains('-');
      final currentHasSuffix = current.contains('-');

      if (!latestHasSuffix && currentHasSuffix) return true;

      return false;
    } catch (e) {
      _log.e('Error comparing versions: $e');
      return false;
    }
  }

  static String get currentVersion => AppInfo.version;

  static List<_ApkAsset> _collectApkAssets(List<dynamic> assets) {
    final apkAssets = <_ApkAsset>[];

    for (final asset in assets.whereType<Map<Object?, Object?>>()) {
      final assetMap = Map<String, dynamic>.from(asset);
      final name = (assetMap['name'] as String? ?? '').trim();
      final normalizedName = name.toLowerCase();
      if (!normalizedName.endsWith('.apk')) {
        continue;
      }

      final downloadUrl = assetMap['browser_download_url'] as String?;
      final uri = downloadUrl != null ? Uri.tryParse(downloadUrl) : null;
      if (uri == null || uri.scheme != 'https') {
        _log.w('Skipping non-HTTPS APK URL: $downloadUrl');
        continue;
      }

      final variant = _apkVariantFromName(normalizedName);
      if (variant == null) {
        _log.w('Skipping APK with unknown variant: $name');
        continue;
      }

      apkAssets.add(
        _ApkAsset(name: name, url: uri.toString(), variant: variant),
      );
    }

    return apkAssets;
  }

  static _ApkVariant? _apkVariantFromName(String name) {
    if (name.contains('universal')) {
      return _ApkVariant.universal;
    }
    if (name.contains('arm64') || name.contains('arm64-v8a')) {
      return _ApkVariant.arm64;
    }
    if (name.contains('arm32') ||
        name.contains('armeabi') ||
        name.contains('armv7') ||
        name.contains('v7a')) {
      return _ApkVariant.arm32;
    }
    return null;
  }

  static Future<_ApkAsset?> _selectApkForCurrentDevice(
    List<_ApkAsset> assets,
  ) async {
    if (assets.isEmpty) {
      return null;
    }

    _ApkAsset? arm64Asset;
    _ApkAsset? arm32Asset;
    _ApkAsset? universalAsset;
    for (final asset in assets) {
      switch (asset.variant) {
        case _ApkVariant.arm64:
          arm64Asset ??= asset;
          break;
        case _ApkVariant.arm32:
          arm32Asset ??= asset;
          break;
        case _ApkVariant.universal:
          universalAsset ??= asset;
          break;
      }
    }

    final supportedAbis = await _getSupportedAndroidAbis();
    final hasArm64 = supportedAbis.any(_isArm64Abi);
    final hasArm32 = supportedAbis.any(_isArm32Abi);

    if (hasArm64) {
      return arm64Asset ?? universalAsset ?? arm32Asset;
    }
    if (hasArm32) {
      return arm32Asset ?? universalAsset;
    }

    if (universalAsset != null) {
      _log.w(
        'Could not match APK asset to supported ABIs ${supportedAbis.join(', ')}; '
        'falling back to universal APK.',
      );
      return universalAsset;
    }

    _log.w(
      'Could not match APK asset to supported ABIs ${supportedAbis.join(', ')}; '
      'no universal APK available.',
    );
    return null;
  }

  static Future<List<String>> _getSupportedAndroidAbis() async {
    if (!Platform.isAndroid) {
      return const [];
    }

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final supportedAbis = androidInfo.supportedAbis
          .map((abi) => abi.toLowerCase())
          .where((abi) => abi.isNotEmpty)
          .toSet()
          .toList();
      _log.i('Detected supported Android ABIs: ${supportedAbis.join(', ')}');
      return supportedAbis;
    } catch (e) {
      _log.w('Failed to detect supported Android ABIs: $e');
      return const [];
    }
  }

  static bool _isArm64Abi(String abi) =>
      abi.contains('arm64') || abi.contains('aarch64');

  static bool _isArm32Abi(String abi) =>
      abi.contains('armeabi') || abi.contains('armv7') || abi.contains('arm');
}
