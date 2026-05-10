import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/utils/path_match_keys.dart';

final _log = AppLogger('HistoryDatabase');
final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

String? _currentContainerPath;

class HistoryLookupRequest {
  final String spotifyId;
  final String? isrc;
  final String trackName;
  final String artistName;

  const HistoryLookupRequest({
    required this.spotifyId,
    this.isrc,
    required this.trackName,
    required this.artistName,
  });

  String get lookupKey =>
      '${spotifyId.trim()}|${HistoryDatabase.normalizeIsrc(isrc)}|'
      '${HistoryDatabase.matchKeyFor(trackName, artistName)}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistoryLookupRequest &&
          spotifyId == other.spotifyId &&
          isrc == other.isrc &&
          trackName == other.trackName &&
          artistName == other.artistName;

  @override
  int get hashCode => Object.hash(spotifyId, isrc, trackName, artistName);
}

class HistoryBatchLookupRequest {
  final List<HistoryLookupRequest> tracks;

  const HistoryBatchLookupRequest(this.tracks);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HistoryBatchLookupRequest ||
        other.tracks.length != tracks.length) {
      return false;
    }
    for (var i = 0; i < tracks.length; i++) {
      if (tracks[i] != other.tracks[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(tracks);
}

class HistoryDatabase {
  static final HistoryDatabase instance = HistoryDatabase._init();
  static Database? _database;

  HistoryDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('history.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, fileName);

    _log.i('Initializing database at: $path');

    return await openDatabase(
      path,
      version: 9,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode = WAL');
        await db.execute('PRAGMA synchronous = NORMAL');
      },
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    _log.i('Creating database schema v$version');

    await db.execute('''
      CREATE TABLE history (
        id TEXT PRIMARY KEY,
        track_name TEXT NOT NULL,
        artist_name TEXT NOT NULL,
        album_name TEXT NOT NULL,
        album_artist TEXT,
        cover_url TEXT,
        file_path TEXT NOT NULL,
        storage_mode TEXT,
        download_tree_uri TEXT,
        saf_relative_dir TEXT,
        saf_file_name TEXT,
        saf_repaired INTEGER,
        service TEXT NOT NULL,
        downloaded_at TEXT NOT NULL,
        isrc TEXT,
        spotify_id TEXT,
        track_number INTEGER,
        total_tracks INTEGER,
        disc_number INTEGER,
        total_discs INTEGER,
        duration INTEGER,
        release_date TEXT,
        quality TEXT,
        bit_depth INTEGER,
        sample_rate INTEGER,
        bitrate INTEGER,
        format TEXT,
        genre TEXT,
        composer TEXT,
        label TEXT,
        copyright TEXT,
        spotify_id_norm TEXT,
        isrc_norm TEXT,
        match_key TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_spotify_id ON history(spotify_id)');
    await db.execute('CREATE INDEX idx_isrc ON history(isrc)');
    await db.execute(
      'CREATE INDEX idx_downloaded_at ON history(downloaded_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_album ON history(album_name, album_artist)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_track_artist ON history(track_name, artist_name)',
    );
    await _createNormalizedIndexes(db);
    await _createPathKeyTable(db);

    _log.i('Database schema created with indexes');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    _log.i('Upgrading database from v$oldVersion to v$newVersion');
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE history ADD COLUMN storage_mode TEXT');
      await db.execute('ALTER TABLE history ADD COLUMN download_tree_uri TEXT');
      await db.execute('ALTER TABLE history ADD COLUMN saf_relative_dir TEXT');
      await db.execute('ALTER TABLE history ADD COLUMN saf_file_name TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE history ADD COLUMN saf_repaired INTEGER');
    }
    if (oldVersion < 4) {
      final columns = await db.rawQuery('PRAGMA table_info(history)');
      final hasComposer = columns.any(
        (row) => (row['name']?.toString().toLowerCase() ?? '') == 'composer',
      );
      if (!hasComposer) {
        await db.execute('ALTER TABLE history ADD COLUMN composer TEXT');
      }
    }
    if (oldVersion < 5) {
      final columns = await db.rawQuery('PRAGMA table_info(history)');
      final hasTotalTracks = columns.any(
        (row) =>
            (row['name']?.toString().toLowerCase() ?? '') == 'total_tracks',
      );
      final hasTotalDiscs = columns.any(
        (row) => (row['name']?.toString().toLowerCase() ?? '') == 'total_discs',
      );
      if (!hasTotalTracks) {
        await db.execute('ALTER TABLE history ADD COLUMN total_tracks INTEGER');
      }
      if (!hasTotalDiscs) {
        await db.execute('ALTER TABLE history ADD COLUMN total_discs INTEGER');
      }
    }
    if (oldVersion < 6) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_history_track_artist ON history(track_name, artist_name)',
      );
    }
    if (oldVersion < 7) {
      await _createPathKeyTable(db);
      await _backfillPathKeys(db);
    }
    if (oldVersion < 8) {
      await _addColumnIfMissing(db, 'history', 'spotify_id_norm', 'TEXT');
      await _addColumnIfMissing(db, 'history', 'isrc_norm', 'TEXT');
      await _addColumnIfMissing(db, 'history', 'match_key', 'TEXT');
      await _backfillNormalizedColumns(db);
      await _createNormalizedIndexes(db);
    }
    if (oldVersion < 9) {
      await _addColumnIfMissing(db, 'history', 'bitrate', 'INTEGER');
      await _addColumnIfMissing(db, 'history', 'format', 'TEXT');
    }
  }

  static String normalizeLookupText(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  static String normalizeIsrc(String? value) {
    return (value ?? '').trim().toUpperCase().replaceAll(RegExp(r'[-\s]'), '');
  }

  static String normalizeSpotifyId(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  static String matchKeyFor(String? trackName, String? artistName) {
    final track = normalizeLookupText(trackName);
    if (track.isEmpty) return '';
    return '$track|${normalizeLookupText(artistName)}';
  }

  static List<String> spotifyLookupCandidates(String? rawId) {
    final trimmed = rawId?.trim() ?? '';
    if (trimmed.isEmpty) return const [];
    final candidates = <String>{trimmed};
    final lowered = trimmed.toLowerCase();
    if (lowered.startsWith('spotify:track:')) {
      final compact = trimmed.split(':').last.trim();
      if (compact.isNotEmpty) candidates.add(compact);
    } else if (!trimmed.contains(':')) {
      candidates.add('spotify:track:$trimmed');
    }
    return candidates.toList(growable: false);
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any(
      (row) => (row['name']?.toString().toLowerCase() ?? '') == column,
    );
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  Future<void> _createNormalizedIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_spotify_id_norm ON history(spotify_id_norm)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_isrc_norm ON history(isrc_norm)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_match_key ON history(match_key)',
    );
  }

  Future<void> _backfillNormalizedColumns(Database db) async {
    final rows = await db.query(
      'history',
      columns: ['id', 'spotify_id', 'isrc', 'track_name', 'artist_name'],
    );
    final batch = db.batch();
    for (final row in rows) {
      batch.update(
        'history',
        _normalizedColumns(
          spotifyId: row['spotify_id'] as String?,
          isrc: row['isrc'] as String?,
          trackName: row['track_name'] as String?,
          artistName: row['artist_name'] as String?,
        ),
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  Map<String, dynamic> _normalizedColumns({
    required String? spotifyId,
    required String? isrc,
    required String? trackName,
    required String? artistName,
  }) {
    return {
      'spotify_id_norm': normalizeSpotifyId(spotifyId),
      'isrc_norm': normalizeIsrc(isrc),
      'match_key': matchKeyFor(trackName, artistName),
    };
  }

  Future<void> _createPathKeyTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS history_path_keys (
        item_id TEXT NOT NULL,
        path_key TEXT NOT NULL,
        PRIMARY KEY (item_id, path_key)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_path_keys_key ON history_path_keys(path_key)',
    );
  }

  Future<void> _backfillPathKeys(Database db) async {
    final rows = await db.query('history', columns: ['id', 'file_path']);
    final batch = db.batch();
    for (final row in rows) {
      _putPathKeysInBatch(
        batch,
        row['id'] as String,
        row['file_path'] as String?,
      );
    }
    await batch.commit(noResult: true);
  }

  void _putPathKeysInBatch(Batch batch, String id, String? filePath) {
    batch.delete('history_path_keys', where: 'item_id = ?', whereArgs: [id]);
    for (final key in buildPathMatchKeys(filePath)) {
      batch.insert('history_path_keys', {
        'item_id': id,
        'path_key': key,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static final _iosContainerPattern = RegExp(
    r'/var/mobile/Containers/Data/Application/[A-F0-9\-]+/',
    caseSensitive: false,
  );

  Future<void> _initContainerPath() async {
    if (!Platform.isIOS || _currentContainerPath != null) return;

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final match = _iosContainerPattern.firstMatch(docDir.path);
      if (match != null) {
        _currentContainerPath = match.group(0);
        _log.d('iOS container path: $_currentContainerPath');
      }
    } catch (e) {
      _log.w('Failed to get iOS container path: $e');
    }
  }

  String _normalizeIosPath(String? filePath) {
    if (filePath == null || filePath.isEmpty) return filePath ?? '';
    if (!Platform.isIOS || _currentContainerPath == null) return filePath;

    if (_iosContainerPattern.hasMatch(filePath)) {
      final normalized = filePath.replaceFirst(
        _iosContainerPattern,
        _currentContainerPath!,
      );
      if (normalized != filePath) {
        _log.d('Normalized iOS path: $filePath -> $normalized');
      }
      return normalized;
    }

    return filePath;
  }

  Future<bool> migrateIosContainerPaths() async {
    if (!Platform.isIOS) return false;

    await _initContainerPath();
    if (_currentContainerPath == null) return false;

    final prefs = await _prefs;
    final lastContainer = prefs.getString('ios_last_container_path');

    if (lastContainer == _currentContainerPath) {
      _log.d('iOS container path unchanged, skipping migration');
      return false;
    }

    _log.i('iOS container changed: $lastContainer -> $_currentContainerPath');

    try {
      final db = await database;

      final rows = await db.query('history', columns: ['id', 'file_path']);
      int updatedCount = 0;
      final batch = db.batch();

      for (final row in rows) {
        final id = row['id'] as String;
        final oldPath = row['file_path'] as String?;

        if (oldPath != null && _iosContainerPattern.hasMatch(oldPath)) {
          final newPath = _normalizeIosPath(oldPath);
          if (newPath != oldPath) {
            batch.update(
              'history',
              {'file_path': newPath},
              where: 'id = ?',
              whereArgs: [id],
            );
            _putPathKeysInBatch(batch, id, newPath);
            updatedCount++;
          }
        }
      }

      if (updatedCount > 0) {
        await batch.commit(noResult: true);
      }

      await prefs.setString('ios_last_container_path', _currentContainerPath!);

      _log.i('iOS path migration complete: $updatedCount paths updated');
      return updatedCount > 0;
    } catch (e, stack) {
      _log.e('iOS path migration failed: $e', e, stack);
      return false;
    }
  }

  Future<bool> migrateFromSharedPreferences() async {
    final prefs = await _prefs;
    final migrationKey = 'history_migrated_to_sqlite';

    if (prefs.getBool(migrationKey) == true) {
      _log.d('Already migrated to SQLite');
      return false;
    }

    final jsonStr = prefs.getString('download_history');
    if (jsonStr == null || jsonStr.isEmpty) {
      _log.d('No SharedPreferences history to migrate');
      await prefs.setBool(migrationKey, true);
      return false;
    }

    try {
      final jsonList = List<dynamic>.from(jsonDecode(jsonStr) as List);
      _log.i(
        'Migrating ${jsonList.length} items from SharedPreferences to SQLite',
      );

      final db = await database;
      final batch = db.batch();

      for (final json in jsonList) {
        final map = Map<String, dynamic>.from(json as Map);
        batch.insert(
          'history',
          _jsonToDbRow(map),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        _putPathKeysInBatch(
          batch,
          map['id'] as String,
          map['filePath'] as String?,
        );
      }

      await batch.commit(noResult: true);

      await prefs.setBool(migrationKey, true);
      _log.i('Migration complete: ${jsonList.length} items');

      return true;
    } catch (e, stack) {
      _log.e('Migration failed: $e', e, stack);
      return false;
    }
  }

  Map<String, dynamic> _jsonToDbRow(Map<String, dynamic> json) {
    final row = {
      'id': json['id'],
      'track_name': json['trackName'],
      'artist_name': json['artistName'],
      'album_name': json['albumName'],
      'album_artist': json['albumArtist'],
      'cover_url': json['coverUrl'],
      'file_path': json['filePath'],
      'storage_mode': json['storageMode'],
      'download_tree_uri': json['downloadTreeUri'],
      'saf_relative_dir': json['safRelativeDir'],
      'saf_file_name': json['safFileName'],
      'saf_repaired': json['safRepaired'] == true ? 1 : 0,
      'service': json['service'],
      'downloaded_at': json['downloadedAt'],
      'isrc': json['isrc'],
      'spotify_id': json['spotifyId'],
      'track_number': json['trackNumber'],
      'total_tracks': json['totalTracks'],
      'disc_number': json['discNumber'],
      'total_discs': json['totalDiscs'],
      'duration': json['duration'],
      'release_date': json['releaseDate'],
      'quality': json['quality'],
      'bit_depth': json['bitDepth'],
      'sample_rate': json['sampleRate'],
      'bitrate': json['bitrate'],
      'format': json['format'],
      'genre': json['genre'],
      'composer': json['composer'],
      'label': json['label'],
      'copyright': json['copyright'],
    };
    row.addAll(
      _normalizedColumns(
        spotifyId: json['spotifyId'] as String?,
        isrc: json['isrc'] as String?,
        trackName: json['trackName'] as String?,
        artistName: json['artistName'] as String?,
      ),
    );
    return row;
  }

  Map<String, dynamic> _dbRowToJson(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'trackName': row['track_name'],
      'artistName': row['artist_name'],
      'albumName': row['album_name'],
      'albumArtist': row['album_artist'],
      'coverUrl': row['cover_url'],
      'filePath': _normalizeIosPath(row['file_path'] as String?),
      'storageMode': row['storage_mode'],
      'downloadTreeUri': row['download_tree_uri'],
      'safRelativeDir': row['saf_relative_dir'],
      'safFileName': row['saf_file_name'],
      'safRepaired': row['saf_repaired'] == 1 || row['saf_repaired'] == true,
      'service': row['service'],
      'downloadedAt': row['downloaded_at'],
      'isrc': row['isrc'],
      'spotifyId': row['spotify_id'],
      'trackNumber': row['track_number'],
      'totalTracks': row['total_tracks'],
      'discNumber': row['disc_number'],
      'totalDiscs': row['total_discs'],
      'duration': row['duration'],
      'releaseDate': row['release_date'],
      'quality': row['quality'],
      'bitDepth': row['bit_depth'],
      'sampleRate': row['sample_rate'],
      'bitrate': row['bitrate'],
      'format': row['format'],
      'genre': row['genre'],
      'composer': row['composer'],
      'label': row['label'],
      'copyright': row['copyright'],
    };
  }

  Future<void> upsert(Map<String, dynamic> json) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'history',
        _jsonToDbRow(json),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final batch = txn.batch();
      _putPathKeysInBatch(
        batch,
        json['id'] as String,
        json['filePath'] as String?,
      );
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsertBatch(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final json in items) {
        batch.insert(
          'history',
          _jsonToDbRow(json),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        _putPathKeysInBatch(
          batch,
          json['id'] as String,
          json['filePath'] as String?,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getAll({int? limit, int? offset}) async {
    final db = await database;
    final rows = await db.query(
      'history',
      orderBy: 'downloaded_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_dbRowToJson).toList();
  }

  Future<List<Map<String, dynamic>>> getAlbumTracks(
    String albumName,
    String artistName,
  ) async {
    final db = await database;
    final rows = await db.query(
      'history',
      where:
          'LOWER(album_name) = ? AND LOWER(COALESCE(album_artist, artist_name)) = ?',
      whereArgs: [albumName.toLowerCase(), artistName.toLowerCase()],
      orderBy:
          'COALESCE(disc_number, 0), COALESCE(track_number, 0), track_name',
    );
    return rows.map(_dbRowToJson).toList(growable: false);
  }

  Future<Map<String, dynamic>?> findByTrackAndArtist(
    String trackName,
    String artistName,
  ) async {
    final db = await database;
    final rows = await db.query(
      'history',
      where: 'LOWER(track_name) = ? AND LOWER(artist_name) = ?',
      whereArgs: [trackName.toLowerCase(), artistName.toLowerCase()],
      orderBy: 'downloaded_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _dbRowToJson(rows.first);
  }

  Future<Map<String, dynamic>?> getById(String id) async {
    final db = await database;
    final rows = await db.query(
      'history',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _dbRowToJson(rows.first);
  }

  Future<Map<String, dynamic>?> getBySpotifyId(String spotifyId) async {
    final db = await database;
    final rows = await db.query(
      'history',
      where: 'spotify_id = ?',
      whereArgs: [spotifyId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _dbRowToJson(rows.first);
  }

  Future<Map<String, dynamic>?> getByIsrc(String isrc) async {
    final db = await database;
    final rows = await db.query(
      'history',
      where: 'isrc = ?',
      whereArgs: [isrc],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _dbRowToJson(rows.first);
  }

  Future<bool> existsTrack(HistoryLookupRequest request) async {
    final row = await findExistingTrack(request, columns: ['id']);
    return row != null;
  }

  Future<Map<String, dynamic>?> findExistingTrack(
    HistoryLookupRequest request, {
    List<String>? columns,
  }) async {
    final db = await database;
    final spotifyCandidates = spotifyLookupCandidates(request.spotifyId);
    if (spotifyCandidates.isNotEmpty) {
      final placeholders = List.filled(spotifyCandidates.length, '?').join(',');
      final normalized = spotifyCandidates.map(normalizeSpotifyId).toList();
      final rows = await db.query(
        'history',
        columns: columns,
        where:
            'spotify_id IN ($placeholders) OR spotify_id_norm IN ($placeholders)',
        whereArgs: [...spotifyCandidates, ...normalized],
        orderBy: 'downloaded_at DESC',
        limit: 1,
      );
      if (rows.isNotEmpty) return _dbRowToJson(rows.first);
    }

    final isrcNorm = normalizeIsrc(request.isrc);
    if (isrcNorm.isNotEmpty) {
      final rows = await db.query(
        'history',
        columns: columns,
        where: 'isrc_norm = ?',
        whereArgs: [isrcNorm],
        orderBy: 'downloaded_at DESC',
        limit: 1,
      );
      if (rows.isNotEmpty) return _dbRowToJson(rows.first);
    }

    final matchKey = matchKeyFor(request.trackName, request.artistName);
    if (matchKey.isNotEmpty) {
      final rows = await db.query(
        'history',
        columns: columns,
        where: 'match_key = ?',
        whereArgs: [matchKey],
        orderBy: 'downloaded_at DESC',
        limit: 1,
      );
      if (rows.isNotEmpty) return _dbRowToJson(rows.first);
    }
    return null;
  }

  Future<Set<String>> existingTrackKeys(
    List<HistoryLookupRequest> requests,
  ) async {
    if (requests.isEmpty) return const <String>{};
    final db = await database;
    final found = <String>{};
    final rawSpotifyToKeys = <String, Set<String>>{};
    final normSpotifyToKeys = <String, Set<String>>{};
    final isrcToKeys = <String, Set<String>>{};
    final matchToKeys = <String, Set<String>>{};

    void add(Map<String, Set<String>> map, String value, String key) {
      if (value.isEmpty) return;
      map.putIfAbsent(value, () => <String>{}).add(key);
    }

    for (final request in requests) {
      final key = request.lookupKey;
      for (final candidate in spotifyLookupCandidates(request.spotifyId)) {
        add(rawSpotifyToKeys, candidate, key);
        add(normSpotifyToKeys, normalizeSpotifyId(candidate), key);
      }
      add(isrcToKeys, normalizeIsrc(request.isrc), key);
      add(matchToKeys, matchKeyFor(request.trackName, request.artistName), key);
    }

    Future<void> queryColumn(
      String column,
      Map<String, Set<String>> keyMap,
    ) async {
      final values = keyMap.keys.toList(growable: false);
      const chunkSize = 450;
      for (var i = 0; i < values.length; i += chunkSize) {
        final end = (i + chunkSize < values.length)
            ? i + chunkSize
            : values.length;
        final chunk = values.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        final rows = await db.rawQuery(
          'SELECT DISTINCT $column AS lookup_value FROM history WHERE $column IN ($placeholders)',
          chunk,
        );
        for (final row in rows) {
          final value = row['lookup_value'] as String?;
          if (value == null) continue;
          found.addAll(keyMap[value] ?? const <String>{});
        }
      }
    }

    await queryColumn('spotify_id', rawSpotifyToKeys);
    await queryColumn('spotify_id_norm', normSpotifyToKeys);
    await queryColumn('isrc_norm', isrcToKeys);
    await queryColumn('match_key', matchToKeys);
    return found;
  }

  Future<bool> existsBySpotifyId(String spotifyId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT 1 FROM history WHERE spotify_id = ? LIMIT 1',
      [spotifyId],
    );
    return result.isNotEmpty;
  }

  Future<Set<String>> getAllSpotifyIds() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT spotify_id FROM history WHERE spotify_id IS NOT NULL AND spotify_id != ""',
    );
    return rows.map((r) => r['spotify_id'] as String).toSet();
  }

  Future<void> deleteById(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'history_path_keys',
        where: 'item_id = ?',
        whereArgs: [id],
      );
      await txn.delete('history', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> deleteBySpotifyId(String spotifyId) async {
    final db = await database;
    final rows = await db.query(
      'history',
      columns: ['id'],
      where: 'spotify_id = ?',
      whereArgs: [spotifyId],
    );
    final ids = rows.map((row) => row['id'] as String).toList(growable: false);
    return db.transaction<int>((txn) async {
      for (final id in ids) {
        await txn.delete(
          'history_path_keys',
          where: 'item_id = ?',
          whereArgs: [id],
        );
      }
      return txn.delete(
        'history',
        where: 'spotify_id = ?',
        whereArgs: [spotifyId],
      );
    });
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('history_path_keys');
      await txn.delete('history');
    });
    _log.i('Cleared all history');
  }

  Future<int> getCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM history');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<String, int>> getGroupedCounts() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        SUM(CASE WHEN track_count > 1 THEN 1 ELSE 0 END) AS albums,
        SUM(CASE WHEN track_count = 1 THEN 1 ELSE 0 END) AS singles
      FROM (
        SELECT COUNT(*) AS track_count
        FROM history
        GROUP BY LOWER(album_name), LOWER(COALESCE(album_artist, artist_name))
      )
      ''');
    final row = rows.isEmpty ? const <String, Object?>{} : rows.first;
    return {
      'albums': (row['albums'] as num?)?.toInt() ?? 0,
      'singles': (row['singles'] as num?)?.toInt() ?? 0,
    };
  }

  Future<Map<String, dynamic>?> findExisting({
    String? spotifyId,
    String? isrc,
  }) async {
    if (spotifyId != null && spotifyId.isNotEmpty) {
      final bySpotify = await getBySpotifyId(spotifyId);
      if (bySpotify != null) return bySpotify;

      if (spotifyId.startsWith('deezer:')) {
        final deezerId = spotifyId.substring(7);
        final db = await database;
        final rows = await db.query(
          'history',
          where: 'spotify_id LIKE ?',
          whereArgs: ['deezer:$deezerId'],
          limit: 1,
        );
        if (rows.isNotEmpty) return _dbRowToJson(rows.first);
      }
    }

    if (isrc != null && isrc.isNotEmpty) {
      return await getByIsrc(isrc);
    }

    return null;
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  Future<void> updateFilePath(
    String id,
    String newFilePath, {
    String? newSafFileName,
    String? newQuality,
    int? newBitDepth,
    int? newSampleRate,
    bool clearAudioSpecs = false,
  }) async {
    final db = await database;
    final values = <String, dynamic>{'file_path': newFilePath};
    if (newSafFileName != null) {
      values['saf_file_name'] = newSafFileName;
    }
    if (newQuality != null) {
      values['quality'] = newQuality;
    }
    if (clearAudioSpecs) {
      values['bit_depth'] = null;
      values['sample_rate'] = null;
    } else {
      if (newBitDepth != null) {
        values['bit_depth'] = newBitDepth;
      }
      if (newSampleRate != null) {
        values['sample_rate'] = newSampleRate;
      }
    }
    await db.transaction((txn) async {
      await txn.update('history', values, where: 'id = ?', whereArgs: [id]);
      final batch = txn.batch();
      _putPathKeysInBatch(batch, id, newFilePath);
      await batch.commit(noResult: true);
    });
  }

  Future<void> updateAudioMetadata(
    String id, {
    String? newQuality,
    int? newBitDepth,
    int? newSampleRate,
  }) async {
    final db = await database;
    final values = <String, dynamic>{};
    if (newQuality != null) {
      values['quality'] = newQuality;
    }
    if (newBitDepth != null) {
      values['bit_depth'] = newBitDepth;
    }
    if (newSampleRate != null) {
      values['sample_rate'] = newSampleRate;
    }
    if (values.isEmpty) {
      return;
    }
    await db.update('history', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<Set<String>> getAllFilePaths() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT file_path FROM history WHERE file_path IS NOT NULL AND file_path != ""',
    );
    return rows.map((r) => r['file_path'] as String).toSet();
  }

  Future<List<Map<String, dynamic>>> getAllEntriesWithPaths() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT id, file_path, storage_mode, download_tree_uri, saf_relative_dir, saf_file_name
      FROM history 
      WHERE file_path IS NOT NULL AND file_path != ""
    ''');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<List<Map<String, dynamic>>> getEntriesWithPathsPage({
    required int limit,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.query(
      'history',
      columns: [
        'id',
        'file_path',
        'storage_mode',
        'download_tree_uri',
        'saf_relative_dir',
        'saf_file_name',
      ],
      where: 'file_path IS NOT NULL AND file_path != ""',
      orderBy: 'downloaded_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<int> deleteByIds(List<String> ids) async {
    if (ids.isEmpty) return 0;

    final db = await database;
    var totalDeleted = 0;
    const chunkSize = 500;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
      final chunk = ids.sublist(i, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      await db.rawDelete(
        'DELETE FROM history_path_keys WHERE item_id IN ($placeholders)',
        chunk,
      );
      totalDeleted += await db.rawDelete(
        'DELETE FROM history WHERE id IN ($placeholders)',
        chunk,
      );
    }
    _log.i('Deleted $totalDeleted orphaned entries');
    return totalDeleted;
  }
}
