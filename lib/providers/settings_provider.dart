import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/constants/app_info.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/artist_utils.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/logger.dart';

const _settingsKey = 'app_settings';
const _settingsCorruptBackupKey = 'app_settings_corrupt_backup';
const _migrationVersionKey = 'settings_migration_version';
const _currentMigrationVersion = 11;
const _spotifyClientSecretKey = 'spotify_client_secret';
const _retiredBuiltInProviderIds = {'deezer', 'qobuz', 'tidal', 'youtube'};
final _log = AppLogger('SettingsProvider');

/// Startup override used to render the correct route/locale on the first
/// frame. The notifier still performs migrations and full validation after it
/// mounts.
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

/// Set during bootstrap when the saved Android SAF tree no longer has a valid
/// persisted grant. MainShell consumes this once to block downloads until the
/// user explicitly repairs or changes the destination.
final initialSafAccessLostProvider = Provider<bool>((ref) => false);

bool hasPersistedAppSettings(SharedPreferences prefs) {
  final rawSettings = prefs.getString(_settingsKey);
  return rawSettings != null && rawSettings.isNotEmpty;
}

AppSettings loadBootstrapSettings(SharedPreferences prefs) {
  final rawSettings = prefs.getString(_settingsKey);
  if (rawSettings == null || rawSettings.isEmpty) return const AppSettings();
  try {
    final decoded = jsonDecode(rawSettings);
    if (decoded is! Map) return const AppSettings();
    return AppSettings.fromJson(Map<String, dynamic>.from(decoded));
  } catch (_) {
    return const AppSettings();
  }
}

/// Removes values that are only valid for one OS installation while keeping
/// portable user preferences. This is used when Android restores app data into
/// a fresh package install despite backup being disabled (for example an OEM
/// device-to-device transfer).
AppSettings resetInstallationBoundSettings(AppSettings settings) {
  return settings.copyWith(
    downloadDirectory: '',
    downloadDirectoryBookmark: '',
    storageMode: 'app',
    downloadTreeUri: '',
    isFirstLaunch: true,
    useAllFilesAccess: false,
    localLibraryEnabled: false,
    localLibraryPath: '',
    localLibraryBookmark: '',
    localLibraryAutoScan: 'off',
    hasCompletedTutorial: false,
  );
}

Future<void> resetRestoredInstallationSettings(SharedPreferences prefs) async {
  final rawSettings = prefs.getString(_settingsKey);
  if (rawSettings == null || rawSettings.isEmpty) return;

  try {
    final decoded = jsonDecode(rawSettings);
    if (decoded is! Map) {
      await prefs.remove(_settingsKey);
      return;
    }
    final restored = AppSettings.fromJson(Map<String, dynamic>.from(decoded));
    final sanitized = resetInstallationBoundSettings(restored);
    await prefs.setString(_settingsKey, jsonEncode(sanitized.toJson()));
  } catch (e) {
    _log.w('Failed to sanitize restored settings; resetting to defaults: $e');
    await prefs.remove(_settingsKey);
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  static final RegExp _isoRegionPattern = RegExp(r'^[A-Z]{2}$');
  static const Set<String> _searchTabValues = {
    'all',
    'track',
    'artist',
    'album',
    'playlist',
  };
  static const Set<String> _libraryViewValues = {
    'last',
    'all',
    'albums',
    'singles',
    'playlists',
  };
  static const Set<String> _extensionVerificationBrowserModeValues = {
    'external_first',
    'in_app_first',
  };

  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _isSavingSettings = false;
  bool _saveQueued = false;
  String? _pendingSettingsJson;

  @override
  AppSettings build() {
    unawaited(_loadSettings());
    return ref.read(initialSettingsProvider);
  }

  Future<void> _loadSettings() async {
    final prefs = await _prefs;
    final rawSettings = prefs.getString(_settingsKey);
    if (rawSettings != null) {
      AppSettings? loaded;
      try {
        final decoded = jsonDecode(rawSettings);
        if (decoded is! Map) {
          throw const FormatException('settings root must be a JSON object');
        }
        loaded = AppSettings.fromJson(Map<String, dynamic>.from(decoded));
      } catch (e, stack) {
        _log.e('Failed to load settings, resetting to defaults: $e', e, stack);
        try {
          await prefs.setString(_settingsCorruptBackupKey, rawSettings);
          await prefs.remove(_settingsKey);
        } catch (backupError) {
          _log.w('Failed to backup corrupt settings: $backupError');
        }
      }

      if (loaded != null) {
        final sanitizedDownloadFallbackExtensionIds =
            _sanitizeDownloadFallbackExtensionIds(
              loaded.downloadFallbackExtensionIds,
            );
        final sanitizedDefaultSearchTab = _normalizeDefaultSearchTab(
          loaded.defaultSearchTab,
        );
        state = loaded.copyWith(
          useExtensionProviders: true,
          downloadFallbackExtensionIds: sanitizedDownloadFallbackExtensionIds,
          clearDownloadFallbackExtensionIds:
              loaded.downloadFallbackExtensionIds != null &&
              sanitizedDownloadFallbackExtensionIds == null,
          defaultSearchTab: sanitizedDefaultSearchTab,
          defaultLibraryView: _normalizeDefaultLibraryView(
            loaded.defaultLibraryView,
          ),
          libraryQualityLabelMode: _normalizeLibraryQualityLabelMode(
            loaded.libraryQualityLabelMode,
          ),
          defaultService: loaded.defaultService,
          searchProvider: loaded.searchProvider,
          extensionVerificationBrowserMode:
              _normalizeExtensionVerificationBrowserMode(
                loaded.extensionVerificationBrowserMode,
              ),
        );

        await _runMigrations(prefs);
        await _normalizeIosDownloadDirectoryIfNeeded();
        await _normalizeSongLinkRegionIfNeeded();
      }
    }

    await _cleanupRetiredSpotifySettings();

    LogBuffer.loggingEnabled = state.enableLogging;

    _syncLyricsSettingsToBackend();
    _syncNetworkCompatibilitySettingsToBackend();
    _syncExtensionFallbackSettingsToBackend();
  }

  void _syncLyricsSettingsToBackend() {
    unawaited(syncLyricsSettingsToBackend());
  }

  Future<void> syncLyricsSettingsToBackend() async {
    if (!PlatformBridge.supportsCoreBackend) return;

    try {
      await PlatformBridge.setLyricsProviders(state.lyricsProviders);
    } catch (e) {
      _log.w('Failed to sync lyrics providers to backend: $e');
    }

    try {
      await PlatformBridge.setLyricsFetchOptions({
        'include_translation_netease': state.lyricsIncludeTranslationNetease,
        'include_romanization_netease': state.lyricsIncludeRomanizationNetease,
        'multi_person_word_by_word': state.lyricsMultiPersonWordByWord,
        'apple_elrc_word_sync': state.lyricsAppleElrcWordSync,
        'musixmatch_language': state.musixmatchLanguage,
      });
    } catch (e) {
      _log.w('Failed to sync lyrics fetch options to backend: $e');
    }
  }

  void _syncNetworkCompatibilitySettingsToBackend() {
    if (!PlatformBridge.supportsCoreBackend) return;

    final compatibilityMode = state.networkCompatibilityMode;
    PlatformBridge.setNetworkCompatibilityOptions(
      allowHttp: compatibilityMode,
      insecureTls: compatibilityMode,
    ).catchError((Object e) {
      _log.w('Failed to sync network compatibility options to backend: $e');
    });

    PlatformBridge.setAllowPrivateNetwork(state.allowLocalNetwork).catchError((
      Object e,
    ) {
      _log.w('Failed to sync allow local network option to backend: $e');
    });
  }

  void _syncExtensionFallbackSettingsToBackend() {
    if (!PlatformBridge.supportsCoreBackend) return;

    PlatformBridge.setDownloadFallbackExtensionIds(
      state.downloadFallbackExtensionIds,
    ).catchError((Object e) {
      _log.w('Failed to sync extension fallback settings to backend: $e');
    });
  }

  Future<void> _runMigrations(SharedPreferences prefs) async {
    final lastMigration = prefs.getInt(_migrationVersionKey) ?? 0;

    if (lastMigration < _currentMigrationVersion) {
      if (state.downloadTreeUri.isNotEmpty && state.storageMode != 'saf') {
        state = state.copyWith(storageMode: 'saf');
      }
      // Migration 2: existing users who already completed setup should skip tutorial
      if (!state.isFirstLaunch && !state.hasCompletedTutorial) {
        state = state.copyWith(hasCompletedTutorial: true);
      }
      if (state.lyricsProviders.contains('spotify_api')) {
        final updatedProviders = state.lyricsProviders
            .where((provider) => provider != 'spotify_api')
            .toList();
        state = state.copyWith(
          lyricsProviders: updatedProviders.isEmpty
              ? const ['lrclib', 'apple_music']
              : updatedProviders,
        );
      }
      state = state.copyWith(lastSeenVersion: AppInfo.version);
      // Migration 7/11: retired built-in services are now reconciled after
      // extensions load so manifest-declared replacements can adopt old prefs.
      if (!state.useExtensionProviders) {
        state = state.copyWith(useExtensionProviders: true);
      }
      await prefs.setInt(_migrationVersionKey, _currentMigrationVersion);
      await _saveSettings();
    }
  }

  Future<void> _saveSettings() async {
    _pendingSettingsJson = jsonEncode(state.toJson());

    if (_isSavingSettings) {
      _saveQueued = true;
      return;
    }

    _isSavingSettings = true;
    try {
      final prefs = await _prefs;
      do {
        final jsonToWrite = _pendingSettingsJson;
        _saveQueued = false;
        if (jsonToWrite != null) {
          await prefs.setString(_settingsKey, jsonToWrite);
        }
      } while (_saveQueued);
    } catch (e) {
      _log.e('Failed to save settings: $e');
    } finally {
      _isSavingSettings = false;
    }
  }

  /// Restores settings from a backup payload (the map produced by
  /// [AppSettings.toJson]). Device-specific storage location fields
  /// (download directory and SAF tree URI) are intentionally preserved from the
  /// current device, because a SAF tree URI from another phone is not valid
  /// here and would break downloads.
  Future<void> restoreFromBackup(Map<String, dynamic> json) async {
    final current = state;
    AppSettings restored;
    try {
      restored = AppSettings.fromJson(Map<String, dynamic>.from(json));
    } catch (e, stack) {
      _log.e('Failed to parse settings from backup: $e', e, stack);
      rethrow;
    }

    state = restored.copyWith(
      // Always keep extension providers enabled (matches _loadSettings).
      useExtensionProviders: true,
      // Preserve this device's storage location; the backup's values point at
      // the original device and would not resolve here.
      downloadDirectory: current.downloadDirectory,
      downloadDirectoryBookmark: current.downloadDirectoryBookmark,
      storageMode: current.storageMode,
      downloadTreeUri: current.downloadTreeUri,
    );

    await _saveSettings();

    LogBuffer.loggingEnabled = state.enableLogging;
    _syncLyricsSettingsToBackend();
    _syncNetworkCompatibilitySettingsToBackend();
    _syncExtensionFallbackSettingsToBackend();
  }

  Future<void> _normalizeIosDownloadDirectoryIfNeeded() async {
    if (!Platform.isIOS) return;

    // A security-scoped bookmark is the source of truth for folders picked
    // from Files: its stored path may legitimately point outside the app
    // container, and the download flow re-resolves the real path from the
    // bookmark. "Fixing" the path here would also drop the bookmark and
    // silently revert the user's chosen folder.
    if (state.downloadDirectoryBookmark.isNotEmpty) return;

    final currentDir = state.downloadDirectory.trim();
    if (currentDir.isEmpty) return;

    final normalizedDir = await validateOrFixIosPath(currentDir);
    if (normalizedDir == currentDir) return;

    _log.i('Normalized iOS download directory: $currentDir -> $normalizedDir');
    state = state.copyWith(
      downloadDirectory: normalizedDir,
      downloadDirectoryBookmark: '',
    );
    await _saveSettings();
  }

  String _normalizeSongLinkRegion(String region) {
    final normalized = region.trim().toUpperCase();
    if (_isoRegionPattern.hasMatch(normalized)) return normalized;
    return 'US';
  }

  String _normalizeDefaultSearchTab(String value) {
    final normalized = value.trim().toLowerCase();
    if (_searchTabValues.contains(normalized)) return normalized;
    return 'all';
  }

  String _normalizeDefaultLibraryView(String value) {
    final normalized = value.trim().toLowerCase();
    if (_libraryViewValues.contains(normalized)) return normalized;
    return 'last';
  }

  String _normalizeLibraryQualityLabelMode(String value) {
    return value == AppSettings.libraryQualityLabelBitDepth
        ? AppSettings.libraryQualityLabelBitDepth
        : AppSettings.libraryQualityLabelBitrate;
  }

  String _normalizeExtensionVerificationBrowserMode(String value) {
    final normalized = value.trim().toLowerCase();
    if (_extensionVerificationBrowserModeValues.contains(normalized)) {
      return normalized;
    }
    return 'in_app_first';
  }

  String? _sanitizeRetiredBuiltInProviderId(String? providerId) {
    final normalized = providerId?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return providerId;
    return _retiredBuiltInProviderIds.contains(normalized) ? null : providerId;
  }

  Future<void> _normalizeSongLinkRegionIfNeeded() async {
    final normalized = _normalizeSongLinkRegion(state.songLinkRegion);
    if (normalized == state.songLinkRegion) return;
    state = state.copyWith(songLinkRegion: normalized);
    await _saveSettings();
  }

  List<String>? _sanitizeDownloadFallbackExtensionIds(List<String>? ids) {
    if (ids == null) {
      return null;
    }

    final result = <String>[];
    for (final id in ids) {
      final normalized = id.trim();
      if (normalized.isEmpty || result.contains(normalized)) {
        continue;
      }
      result.add(normalized);
    }
    return result;
  }

  Future<void> _cleanupRetiredSpotifySettings() async {
    final storedSecret = await _secureStorage.read(
      key: _spotifyClientSecretKey,
    );
    if (storedSecret != null && storedSecret.isNotEmpty) {
      await _secureStorage.delete(key: _spotifyClientSecretKey);
    }
  }

  void setDefaultService(String service) {
    state = state.copyWith(
      defaultService: _sanitizeRetiredBuiltInProviderId(service) ?? '',
    );
    _saveSettings();
  }

  void setAudioQuality(String quality) {
    state = state.copyWith(audioQuality: quality);
    _saveSettings();
  }

  void setFilenameFormat(String format) {
    state = state.copyWith(filenameFormat: format);
    _saveSettings();
  }

  void setSingleFilenameFormat(String format) {
    state = state.copyWith(singleFilenameFormat: format);
    _saveSettings();
  }

  void setDownloadDirectory(String directory, {String? iosBookmark}) {
    state = state.copyWith(
      downloadDirectory: directory,
      downloadDirectoryBookmark: iosBookmark ?? '',
    );
    _saveSettings();
  }

  void setStorageMode(String mode) {
    final normalized = mode == 'saf' ? 'saf' : 'app';
    state = state.copyWith(storageMode: normalized);
    _saveSettings();
  }

  /// Atomically leaves SAF and persists a writable app-managed destination.
  ///
  /// Keeping these fields in one update avoids an intermediate saved state
  /// where app-folder mode still points at the SAF display name, or where an
  /// invalid tree URI can switch the mode back to SAF.
  Future<void> useAppFolderStorage(String directory) async {
    state = state.copyWith(
      storageMode: 'app',
      downloadDirectory: directory,
      downloadDirectoryBookmark: '',
      downloadTreeUri: '',
    );
    await _saveSettings();
  }

  void setDownloadTreeUri(String uri, {String? displayName}) {
    final nextDisplay = displayName ?? state.downloadDirectory;
    state = state.copyWith(
      downloadTreeUri: uri,
      storageMode: uri.isNotEmpty ? 'saf' : state.storageMode,
      downloadDirectory: nextDisplay,
      downloadDirectoryBookmark: uri.isNotEmpty
          ? ''
          : state.downloadDirectoryBookmark,
    );
    _saveSettings();
  }

  void setAutoFallback(bool enabled) {
    state = state.copyWith(autoFallback: enabled);
    _saveSettings();
  }

  void setEmbedLyrics(bool enabled) {
    state = state.copyWith(embedLyrics: enabled);
    _saveSettings();
  }

  void setEmbedReplayGain(bool enabled) {
    state = state.copyWith(embedReplayGain: enabled);
    _saveSettings();
  }

  void setPlaybackNormalization(bool enabled) {
    state = state.copyWith(playbackNormalization: enabled);
    _saveSettings();
  }

  void setEmbedMetadata(bool enabled) {
    state = state.copyWith(embedMetadata: enabled);
    _saveSettings();
  }

  void setArtistTagMode(String mode) {
    if (mode == artistTagModeJoined || mode == artistTagModeSplitVorbis) {
      state = state.copyWith(artistTagMode: mode);
      _saveSettings();
    }
  }

  void setLyricsMode(String mode) {
    if (mode == 'embed' || mode == 'external' || mode == 'both') {
      state = state.copyWith(lyricsMode: mode);
      _saveSettings();
    }
  }

  void setLyricsProviders(List<String> providers) {
    state = state.copyWith(lyricsProviders: providers);
    _saveSettings();
    _syncLyricsSettingsToBackend();
  }

  void setLyricsIncludeTranslationNetease(bool enabled) {
    state = state.copyWith(lyricsIncludeTranslationNetease: enabled);
    _saveSettings();
    _syncLyricsSettingsToBackend();
  }

  void setLyricsIncludeRomanizationNetease(bool enabled) {
    state = state.copyWith(lyricsIncludeRomanizationNetease: enabled);
    _saveSettings();
    _syncLyricsSettingsToBackend();
  }

  void setLyricsMultiPersonWordByWord(bool enabled) {
    state = state.copyWith(lyricsMultiPersonWordByWord: enabled);
    _saveSettings();
    _syncLyricsSettingsToBackend();
  }

  void setLyricsAppleElrcWordSync(bool enabled) {
    state = state.copyWith(lyricsAppleElrcWordSync: enabled);
    _saveSettings();
    _syncLyricsSettingsToBackend();
  }

  void setMusixmatchLanguage(String languageCode) {
    state = state.copyWith(
      musixmatchLanguage: languageCode.trim().toLowerCase(),
    );
    _saveSettings();
    _syncLyricsSettingsToBackend();
  }

  void setMaxQualityCover(bool enabled) {
    state = state.copyWith(maxQualityCover: enabled);
    _saveSettings();
  }

  void setFirstLaunchComplete() {
    state = state.copyWith(isFirstLaunch: false);
    _saveSettings();
  }

  void setCheckForUpdates(bool enabled) {
    state = state.copyWith(checkForUpdates: enabled);
    _saveSettings();
  }

  void setUpdateChannel(String channel) {
    state = state.copyWith(updateChannel: channel);
    _saveSettings();
  }

  void setHasSearchedBefore() {
    if (!state.hasSearchedBefore) {
      state = state.copyWith(hasSearchedBefore: true);
      _saveSettings();
    }
  }

  void setFolderOrganization(String organization) {
    state = state.copyWith(folderOrganization: organization);
    _saveSettings();
  }

  void setCreatePlaylistFolder(bool enabled) {
    state = state.copyWith(createPlaylistFolder: enabled);
    _saveSettings();
  }

  void setUseAlbumArtistForFolders(bool enabled) {
    state = state.copyWith(useAlbumArtistForFolders: enabled);
    _saveSettings();
  }

  void setUsePrimaryArtistOnly(bool enabled) {
    state = state.copyWith(usePrimaryArtistOnly: enabled);
    _saveSettings();
  }

  void setFilterContributingArtistsInAlbumArtist(bool enabled) {
    state = state.copyWith(filterContributingArtistsInAlbumArtist: enabled);
    _saveSettings();
  }

  void setHistoryViewMode(String mode) {
    state = state.copyWith(historyViewMode: mode);
    _saveSettings();
  }

  void setHistoryFilterMode(String mode) {
    state = state.copyWith(historyFilterMode: mode);
    _saveSettings();
  }

  void setAskQualityBeforeDownload(bool enabled) {
    state = state.copyWith(askQualityBeforeDownload: enabled);
    _saveSettings();
  }

  void setSearchProvider(String? provider) {
    final sanitized = _sanitizeRetiredBuiltInProviderId(provider);
    if (sanitized == null || sanitized.isEmpty) {
      state = state.copyWith(clearSearchProvider: true);
    } else {
      state = state.copyWith(searchProvider: sanitized);
    }
    _saveSettings();
  }

  void setDefaultSearchTab(String tab) {
    state = state.copyWith(defaultSearchTab: _normalizeDefaultSearchTab(tab));
    _saveSettings();
  }

  void setDefaultLibraryView(String view) {
    state = state.copyWith(
      defaultLibraryView: _normalizeDefaultLibraryView(view),
    );
    _saveSettings();
  }

  void setLibraryQualityLabelMode(String mode) {
    state = state.copyWith(
      libraryQualityLabelMode: _normalizeLibraryQualityLabelMode(mode),
    );
    _saveSettings();
  }

  void setHomeFeedProvider(String? provider) {
    if (provider == null || provider.isEmpty) {
      state = state.copyWith(clearHomeFeedProvider: true);
    } else {
      state = state.copyWith(homeFeedProvider: provider);
    }
    _saveSettings();
  }

  void setEnableLogging(bool enabled) {
    state = state.copyWith(enableLogging: enabled);
    _saveSettings();
    LogBuffer.loggingEnabled = enabled;
  }

  void setUseExtensionProviders(bool enabled) {
    state = state.copyWith(useExtensionProviders: true);
    _saveSettings();
  }

  void setDownloadFallbackExtensionIds(List<String>? extensionIds) {
    final sanitized = _sanitizeDownloadFallbackExtensionIds(extensionIds);
    state = state.copyWith(
      downloadFallbackExtensionIds: sanitized,
      clearDownloadFallbackExtensionIds:
          extensionIds == null && state.downloadFallbackExtensionIds != null,
    );
    _saveSettings();
    _syncExtensionFallbackSettingsToBackend();
  }

  void setSeparateSingles(bool enabled) {
    state = state.copyWith(separateSingles: enabled);
    _saveSettings();
  }

  void setAlbumFolderStructure(String structure) {
    state = state.copyWith(albumFolderStructure: structure);
    _saveSettings();
  }

  void setShowExtensionStore(bool enabled) {
    state = state.copyWith(showExtensionStore: enabled);
    _saveSettings();
  }

  void setHeroAnimationsEnabled(bool enabled) {
    state = state.copyWith(heroAnimationsEnabled: enabled);
    _saveSettings();
  }

  void setForceBackdropBlur(bool enabled) {
    state = state.copyWith(forceBackdropBlur: enabled);
    _saveSettings();
  }

  void setExtensionVerificationBrowserMode(String mode) {
    state = state.copyWith(
      extensionVerificationBrowserMode:
          _normalizeExtensionVerificationBrowserMode(mode),
    );
    _saveSettings();
  }

  void setLocale(String locale) {
    state = state.copyWith(locale: locale);
    _saveSettings();
  }

  void setTidalHighFormat(String format) {
    state = state.copyWith(tidalHighFormat: format);
    _saveSettings();
  }

  void setUseAllFilesAccess(bool enabled) {
    state = state.copyWith(useAllFilesAccess: enabled);
    _saveSettings();
  }

  void setAutoExportFailedDownloads(bool enabled) {
    state = state.copyWith(autoExportFailedDownloads: enabled);
    _saveSettings();
  }

  void setDownloadNetworkMode(String mode) {
    state = state.copyWith(downloadNetworkMode: mode);
    _saveSettings();
  }

  void setConcurrentDownloads(int count) {
    state = state.copyWith(concurrentDownloads: count.clamp(1, 3));
    _saveSettings();
  }

  void setNetworkCompatibilityMode(bool enabled) {
    state = state.copyWith(networkCompatibilityMode: enabled);
    _saveSettings();
    _syncNetworkCompatibilitySettingsToBackend();
  }

  void setAllowLocalNetwork(bool enabled) {
    state = state.copyWith(allowLocalNetwork: enabled);
    _saveSettings();
    _syncNetworkCompatibilitySettingsToBackend();
  }

  void setSongLinkRegion(String region) {
    final normalized = _normalizeSongLinkRegion(region);
    state = state.copyWith(songLinkRegion: normalized);
    _saveSettings();
  }

  void setNativeDownloadWorkerEnabled(bool enabled) {
    state = state.copyWith(nativeDownloadWorkerEnabled: enabled);
    _saveSettings();
  }

  void setLocalLibraryEnabled(bool enabled) {
    state = state.copyWith(localLibraryEnabled: enabled);
    _saveSettings();
  }

  void setLocalLibraryPath(String path) {
    state = state.copyWith(localLibraryPath: path);
    _saveSettings();
  }

  void setLocalLibraryBookmark(String bookmark) {
    state = state.copyWith(localLibraryBookmark: bookmark);
    _saveSettings();
  }

  void setLocalLibraryPathAndBookmark(String path, String bookmark) {
    state = state.copyWith(
      localLibraryPath: path,
      localLibraryBookmark: bookmark,
    );
    _saveSettings();
  }

  void setLocalLibraryShowDuplicates(bool show) {
    state = state.copyWith(localLibraryShowDuplicates: show);
    _saveSettings();
  }

  void setLocalLibraryAutoScan(String mode) {
    state = state.copyWith(localLibraryAutoScan: mode);
    _saveSettings();
  }

  void setTutorialComplete() {
    state = state.copyWith(hasCompletedTutorial: true);
    _saveSettings();
  }

  void setDeduplicateDownloads(bool enabled) {
    state = state.copyWith(deduplicateDownloads: enabled);
    _saveSettings();
  }

  void setAllowQualityVariants(bool enabled) {
    state = state.copyWith(allowQualityVariants: enabled);
    _saveSettings();
  }

  void setSaveDownloadHistory(bool enabled) {
    state = state.copyWith(saveDownloadHistory: enabled);
    _saveSettings();
  }

  void setPlayerMode(String mode) {
    final normalized = mode == 'internal' ? 'internal' : 'external';
    state = state.copyWith(playerMode: normalized);
    _saveSettings();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
