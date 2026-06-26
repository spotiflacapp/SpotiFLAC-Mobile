import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/constants/app_info.dart';
import 'package:spotiflac_android/utils/logger.dart';

/// Parsed contents of a backup file.
class BackupBundle {
  final int formatVersion;
  final String appVersion;
  final DateTime? createdAt;

  /// Raw `AppSettings.toJson()` map, or null when not present.
  final Map<String, dynamic>? settings;

  /// History items in `DownloadHistoryItem.toJson()` shape.
  final List<Map<String, dynamic>> history;

  /// Collections in `LibraryCollectionsState.toJson()` shape
  /// (wishlist / loved / playlists / favoriteArtists).
  final Map<String, dynamic> collections;

  /// Playlist cover images keyed by playlist id: `{ id: { ext, data } }`.
  final Map<String, dynamic> playlistCovers;

  /// Extensions section: `{ registry_url, items: [ {id, version, enabled, settings} ] }`.
  final Map<String, dynamic> extensions;

  const BackupBundle({
    required this.formatVersion,
    required this.appVersion,
    required this.createdAt,
    required this.settings,
    required this.history,
    required this.collections,
    required this.playlistCovers,
    required this.extensions,
  });

  bool get hasSettings => settings != null && settings!.isNotEmpty;

  int get historyCount => history.length;

  int _collectionListCount(String key) {
    final value = collections[key];
    return value is List ? value.length : 0;
  }

  int get likedCount => _collectionListCount('loved');
  int get wishlistCount => _collectionListCount('wishlist');
  int get playlistCount => _collectionListCount('playlists');
  int get favoriteArtistCount => _collectionListCount('favoriteArtists');

  int get extensionCount {
    final items = extensions['items'];
    return items is List ? items.length : 0;
  }

  bool get hasExtensions => extensionCount > 0;

  bool get isEmpty =>
      !hasSettings &&
      historyCount == 0 &&
      likedCount == 0 &&
      wishlistCount == 0 &&
      playlistCount == 0 &&
      favoriteArtistCount == 0 &&
      extensionCount == 0;
}

/// Builds and parses SpotiFLAC backup files (a single JSON document containing
/// settings, download history and the user library).
class BackupService {
  static final _log = AppLogger('BackupService');

  static const String magic = 'spotiflac-backup';
  static const int formatVersion = 1;
  static const String fileExtension = 'json';

  /// Builds the backup envelope written to disk.
  static Map<String, dynamic> buildEnvelope({
    required Map<String, dynamic>? settings,
    required List<Map<String, dynamic>> history,
    required Map<String, dynamic> collections,
    required Map<String, dynamic> playlistCovers,
    required Map<String, dynamic> extensions,
  }) {
    return {
      'magic': magic,
      'format_version': formatVersion,
      'app': 'SpotiFLAC Mobile',
      'app_version': AppInfo.displayVersion,
      'created_at': DateTime.now().toIso8601String(),
      'data': {
        'settings': settings,
        'history': history,
        'collections': collections,
        'playlist_covers': playlistCovers,
        'extensions': extensions,
      },
    };
  }

  /// Writes [envelope] to a timestamped file under the app documents directory
  /// and returns the created file.
  static Future<File> writeBackupFile(Map<String, dynamic> envelope) async {
    final dir = await getApplicationDocumentsDirectory();
    final backupsDir = Directory(p.join(dir.path, 'backups'));
    if (!await backupsDir.exists()) {
      await backupsDir.create(recursive: true);
    }

    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final fileName = 'spotiflac_backup_$stamp.$fileExtension';
    final file = File(p.join(backupsDir.path, fileName));

    await file.writeAsString(jsonEncode(envelope), flush: true);
    _log.i('Backup written to ${file.path}');
    return file;
  }

  /// Parses and validates a backup file's contents. Returns null when the
  /// content is not a recognizable SpotiFLAC backup.
  static BackupBundle? parse(String content) {
    dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (e) {
      _log.w('Backup parse failed: not valid JSON ($e)');
      return null;
    }

    if (decoded is! Map) {
      _log.w('Backup parse failed: root is not an object');
      return null;
    }

    final root = Map<String, dynamic>.from(decoded);
    if (root['magic'] != magic) {
      _log.w('Backup parse failed: magic marker missing');
      return null;
    }

    final dataRaw = root['data'];
    if (dataRaw is! Map) {
      _log.w('Backup parse failed: missing data section');
      return null;
    }
    final data = Map<String, dynamic>.from(dataRaw);

    Map<String, dynamic>? settings;
    final settingsRaw = data['settings'];
    if (settingsRaw is Map) {
      settings = Map<String, dynamic>.from(settingsRaw);
    }

    final history = <Map<String, dynamic>>[];
    final historyRaw = data['history'];
    if (historyRaw is List) {
      for (final item in historyRaw) {
        if (item is Map) {
          history.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final collectionsRaw = data['collections'];
    final collections = collectionsRaw is Map
        ? Map<String, dynamic>.from(collectionsRaw)
        : <String, dynamic>{};

    final coversRaw = data['playlist_covers'];
    final playlistCovers = coversRaw is Map
        ? Map<String, dynamic>.from(coversRaw)
        : <String, dynamic>{};

    final extensionsRaw = data['extensions'];
    final extensions = extensionsRaw is Map
        ? Map<String, dynamic>.from(extensionsRaw)
        : <String, dynamic>{};

    return BackupBundle(
      formatVersion: (root['format_version'] as num?)?.toInt() ?? 1,
      appVersion: root['app_version'] as String? ?? '',
      createdAt: DateTime.tryParse(root['created_at'] as String? ?? ''),
      settings: settings,
      history: history,
      collections: collections,
      playlistCovers: playlistCovers,
      extensions: extensions,
    );
  }
}
