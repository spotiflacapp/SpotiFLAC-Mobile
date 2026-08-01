import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/utils/audio_format_utils.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/services/history_database.dart';
import 'package:spotiflac_android/services/sqlite_helpers.dart' as sqlite;

part 'library_database_models.dart';
part 'library_database_queue_sql.dart';

final _log = AppLogger('LibraryDatabase');

class LibraryDatabase {
  static final LibraryDatabase instance = LibraryDatabase._init();
  static const int schemaVersion = 9;
  static const int audioMetadataScanVersion = 1;
  static Database? _database;
  bool _historyAttached = false;

  LibraryDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await sqlite.openAppDatabase(
      'local_library.db',
      version: schemaVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
    return _database!;
  }

  Future<void> _ensureHistoryAttached(Database db) async {
    if (_historyAttached) return;
    await HistoryDatabase.instance.database;
    final dbPath = await getApplicationDocumentsDirectory();
    final historyPath = join(dbPath.path, 'history.db');
    try {
      await db.execute('ATTACH DATABASE ? AS history_db', [historyPath]);
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (!message.contains('already in use') &&
          !message.contains('already exists')) {
        rethrow;
      }
    }
    _historyAttached = true;
  }

  Future<void> _createDB(Database db, int version) async {
    _log.i('Creating library database schema v$version');

    await db.execute('''
      CREATE TABLE library (
        id TEXT PRIMARY KEY,
        track_name TEXT NOT NULL,
        artist_name TEXT NOT NULL,
        album_name TEXT NOT NULL,
        album_artist TEXT,
        file_path TEXT NOT NULL UNIQUE,
        cover_path TEXT,
        scanned_at TEXT NOT NULL,
        file_mod_time INTEGER,
        isrc TEXT,
        track_number INTEGER,
        total_tracks INTEGER,
        disc_number INTEGER,
        total_discs INTEGER,
        duration INTEGER,
        release_date TEXT,
        bit_depth INTEGER,
        sample_rate INTEGER,
        bitrate INTEGER,
        genre TEXT,
        composer TEXT,
        label TEXT,
        copyright TEXT,
        format TEXT,
        audio_metadata_scan_version INTEGER NOT NULL DEFAULT 1,
        track_name_norm TEXT,
        artist_name_norm TEXT,
        album_name_norm TEXT,
        album_artist_norm TEXT,
        match_key TEXT,
        album_key TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_library_isrc ON library(isrc)');
    await db.execute(
      'CREATE INDEX idx_library_track_artist ON library(track_name, artist_name)',
    );
    await db.execute(
      'CREATE INDEX idx_library_album ON library(album_name, album_artist)',
    );
    await db.execute(
      'CREATE INDEX idx_library_file_path ON library(file_path)',
    );
    await _createNormalizedIndexes(db);
    await _createPathKeyTable(db);

    _log.i('Library database schema created with indexes');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    _log.i('Upgrading library database from v$oldVersion to v$newVersion');

    if (oldVersion < 2) {
      await db.execute('ALTER TABLE library ADD COLUMN cover_path TEXT');
      _log.i('Added cover_path column');
    }

    if (oldVersion < 3) {
      await db.execute('ALTER TABLE library ADD COLUMN file_mod_time INTEGER');
      _log.i('Added file_mod_time column for incremental scanning');
    }

    if (oldVersion < 4) {
      await db.execute('ALTER TABLE library ADD COLUMN bitrate INTEGER');
      _log.i('Added bitrate column for lossy format quality');
    }

    if (oldVersion < 5) {
      await db.execute('ALTER TABLE library ADD COLUMN label TEXT');
      await db.execute('ALTER TABLE library ADD COLUMN copyright TEXT');
      _log.i('Added label/copyright columns');
    }

    if (oldVersion < 6) {
      await db.execute('ALTER TABLE library ADD COLUMN total_tracks INTEGER');
      await db.execute('ALTER TABLE library ADD COLUMN total_discs INTEGER');
      await db.execute('ALTER TABLE library ADD COLUMN composer TEXT');
      _log.i('Added total_tracks/total_discs/composer columns');
    }

    if (oldVersion < 7) {
      await sqlite.addColumnIfMissing(db, 'library', 'track_name_norm', 'TEXT');
      await sqlite.addColumnIfMissing(
        db,
        'library',
        'artist_name_norm',
        'TEXT',
      );
      await sqlite.addColumnIfMissing(db, 'library', 'album_name_norm', 'TEXT');
      await sqlite.addColumnIfMissing(
        db,
        'library',
        'album_artist_norm',
        'TEXT',
      );
      await sqlite.addColumnIfMissing(db, 'library', 'match_key', 'TEXT');
      await sqlite.addColumnIfMissing(db, 'library', 'album_key', 'TEXT');
      await _backfillNormalizedColumns(db);
      await _createNormalizedIndexes(db);
      _log.i('Added normalized local library lookup columns');
    }
    if (oldVersion < 8) {
      await _createPathKeyTable(db);
      await sqlite.backfillPathKeys(db, 'library', 'library_path_keys');
      _log.i('Added local library path-key lookup table');
    }
    if (oldVersion < 9) {
      await sqlite.addColumnIfMissing(
        db,
        'library',
        'audio_metadata_scan_version',
        'INTEGER NOT NULL DEFAULT 0',
      );
      _log.i('Marked existing rows for one-time audio metadata rescan');
    }
  }

  Future<void> _createPathKeyTable(DatabaseExecutor db) =>
      sqlite.createPathKeyTable(db, 'library_path_keys');

  void _putPathKeysInBatch(Batch batch, String id, String? filePath) =>
      sqlite.putPathKeysInBatch(batch, 'library_path_keys', id, filePath);

  static String normalizeLookupText(String? value) =>
      sqlite.normalizeLookupText(value);

  static String matchKeyFor(String trackName, String artistName) {
    return '${normalizeLookupText(trackName)}|${normalizeLookupText(artistName)}';
  }

  static String albumKeyFor(
    String albumName,
    String? albumArtist,
    String artistName,
  ) {
    return '${normalizeLookupText(albumName)}|${normalizeLookupText(albumArtist ?? artistName)}';
  }

  Future<void> _createNormalizedIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_match_key ON library(match_key)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_album_key ON library(album_key)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_track_norm ON library(track_name_norm)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_artist_norm ON library(artist_name_norm)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_album_norm ON library(album_name_norm)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_scanned_at ON library(scanned_at)',
    );
  }

  Future<void> _backfillNormalizedColumns(Database db) async {
    final rows = await db.query(
      'library',
      columns: [
        'id',
        'track_name',
        'artist_name',
        'album_name',
        'album_artist',
      ],
    );
    final batch = db.batch();
    for (final row in rows) {
      final trackName = row['track_name'] as String? ?? '';
      final artistName = row['artist_name'] as String? ?? '';
      final albumName = row['album_name'] as String? ?? '';
      final albumArtist = row['album_artist'] as String?;
      batch.update(
        'library',
        _normalizedColumns(
          trackName: trackName,
          artistName: artistName,
          albumName: albumName,
          albumArtist: albumArtist,
        ),
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  Map<String, dynamic> _normalizedColumns({
    required String trackName,
    required String artistName,
    required String albumName,
    required String? albumArtist,
  }) {
    final trackNorm = normalizeLookupText(trackName);
    final artistNorm = normalizeLookupText(artistName);
    final albumNorm = normalizeLookupText(albumName);
    final albumArtistNorm = normalizeLookupText(albumArtist ?? artistName);
    return {
      'track_name_norm': trackNorm,
      'artist_name_norm': artistNorm,
      'album_name_norm': albumNorm,
      'album_artist_norm': albumArtistNorm,
      'match_key': '$trackNorm|$artistNorm',
      'album_key': '$albumNorm|$albumArtistNorm',
    };
  }

  Map<String, dynamic> _jsonToDbRow(Map<String, dynamic> json) {
    final row = {
      'id': json['id'],
      'track_name': json['trackName'],
      'artist_name': json['artistName'],
      'album_name': json['albumName'],
      'album_artist': json['albumArtist'],
      'file_path': json['filePath'],
      'cover_path': json['coverPath'],
      'scanned_at': json['scannedAt'],
      'file_mod_time': json['fileModTime'],
      'isrc': json['isrc'],
      'track_number': json['trackNumber'],
      'total_tracks': json['totalTracks'],
      'disc_number': json['discNumber'],
      'total_discs': json['totalDiscs'],
      'duration': json['duration'],
      'release_date': json['releaseDate'],
      'bit_depth': json['bitDepth'],
      'sample_rate': json['sampleRate'],
      'bitrate': json['bitrate'],
      'genre': json['genre'],
      'composer': json['composer'],
      'label': json['label'],
      'copyright': json['copyright'],
      'format': json['format'],
      'audio_metadata_scan_version':
          (json['audioMetadataScanVersion'] as num?)?.toInt() ??
          audioMetadataScanVersion,
    };
    row.addAll(
      _normalizedColumns(
        trackName: json['trackName'] as String? ?? '',
        artistName: json['artistName'] as String? ?? '',
        albumName: json['albumName'] as String? ?? '',
        albumArtist: json['albumArtist'] as String?,
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
      'filePath': row['file_path'],
      'coverPath': row['cover_path'],
      'scannedAt': row['scanned_at'],
      'fileModTime': row['file_mod_time'],
      'isrc': row['isrc'],
      'trackNumber': row['track_number'],
      'totalTracks': row['total_tracks'],
      'discNumber': row['disc_number'],
      'totalDiscs': row['total_discs'],
      'duration': row['duration'],
      'releaseDate': row['release_date'],
      'bitDepth': row['bit_depth'],
      'sampleRate': row['sample_rate'],
      'bitrate': row['bitrate'],
      'genre': row['genre'],
      'composer': row['composer'],
      'label': row['label'],
      'copyright': row['copyright'],
      'format': row['format'],
    };
  }

  Future<void> upsert(Map<String, dynamic> json) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'library',
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
          'library',
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
    _log.i('Batch inserted ${items.length} items');
  }

  Future<void> replaceAll(List<Map<String, dynamic>> items) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('library_path_keys');
      await txn.delete('library');
      if (items.isEmpty) {
        return;
      }

      final batch = txn.batch();
      for (final json in items) {
        batch.insert(
          'library',
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
    _log.i('Replaced library with ${items.length} items');
  }

  Future<List<Map<String, dynamic>>> getAll({int? limit, int? offset}) async {
    final db = await database;
    final rows = await db.query(
      'library',
      orderBy: 'album_artist, album_name, disc_number, track_number',
      limit: limit,
      offset: offset,
    );
    return rows.map(_dbRowToJson).toList();
  }

  String _escapeLikePattern(String value) {
    return value
        .replaceAll('\\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  String _orderByForSort(LocalLibrarySortMode sortMode) {
    return switch (sortMode) {
      LocalLibrarySortMode.title =>
        'track_name_norm, artist_name_norm, album_name_norm, disc_number, track_number',
      LocalLibrarySortMode.artist =>
        'artist_name_norm, album_name_norm, disc_number, track_number, track_name_norm',
      LocalLibrarySortMode.latest =>
        'scanned_at DESC, album_artist_norm, album_name_norm, disc_number, track_number',
      LocalLibrarySortMode.quality =>
        'COALESCE(bit_depth, 0) DESC, COALESCE(sample_rate, 0) DESC, COALESCE(bitrate, 0) DESC, album_artist_norm, album_name_norm, disc_number, track_number',
      LocalLibrarySortMode.album =>
        'album_artist_norm, album_name_norm, COALESCE(disc_number, 0), COALESCE(track_number, 0), track_name_norm',
    };
  }

  Future<List<Map<String, dynamic>>> getQueueTrackPage(
    QueueLibraryDbQuery request,
  ) async {
    final db = await database;
    await _ensureHistoryAttached(db);
    final args = <Object?>[];
    final unionSql = _queueTrackUnionSql(request, args);
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM ($unionSql)
      ORDER BY ${_queueTrackOrderBy(request.sortMode)}
      LIMIT ? OFFSET ?
      ''',
      [...args, request.limit, request.offset],
    );
    return rows.map(_queueTrackRowToJson).toList(growable: false);
  }

  Future<QueueLibraryCounts> getQueueCounts(QueueLibraryDbQuery request) async {
    final db = await database;
    await _ensureHistoryAttached(db);
    final parts = <String>[];
    final args = <Object?>[];

    if (request.source != 'local') {
      final where = <String>[];
      _appendQueueHistoryFilters(where, args, request);
      parts.add('''
        SELECT
          COUNT(*) AS all_count,
          COUNT(DISTINCT CASE WHEN grouped.track_count > 1 THEN h.album_key END) AS album_count,
          COALESCE(SUM(CASE WHEN grouped.track_count = 1 THEN 1 ELSE 0 END), 0) AS single_count
        FROM history_db.history h
        JOIN (
          SELECT album_key, COUNT(*) AS track_count
          FROM history_db.history
          GROUP BY album_key
        ) grouped ON grouped.album_key = h.album_key
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ''');
    }

    if (request.includeLocal && request.source != 'downloaded') {
      final where = <String>[
        '''
        NOT EXISTS (
          SELECT 1
          FROM library_path_keys lpk
          JOIN history_db.history_path_keys hpk ON hpk.path_key = lpk.path_key
          WHERE lpk.item_id = l.id
        )
        ''',
      ];
      _appendQueueLocalFilters(where, args, request);
      parts.add('''
        SELECT
          COUNT(*) AS all_count,
          COUNT(DISTINCT CASE WHEN grouped.track_count > 1 THEN l.album_key END) AS album_count,
          COALESCE(SUM(CASE WHEN grouped.track_count = 1 THEN 1 ELSE 0 END), 0) AS single_count
        FROM library l
        JOIN (
          SELECT album_key, COUNT(*) AS track_count
          FROM library candidate
          WHERE NOT EXISTS (
            SELECT 1
            FROM library_path_keys lpk
            JOIN history_db.history_path_keys hpk ON hpk.path_key = lpk.path_key
            WHERE lpk.item_id = candidate.id
          )
          GROUP BY album_key
        ) grouped ON grouped.album_key = l.album_key
        WHERE ${where.join(' AND ')}
      ''');
    }

    if (parts.isEmpty) {
      return const QueueLibraryCounts(
        allTrackCount: 0,
        albumCount: 0,
        singleTrackCount: 0,
      );
    }

    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(all_count), 0) AS all_count,
        COALESCE(SUM(single_count), 0) AS single_count,
        COALESCE(SUM(album_count), 0) AS album_count
      FROM (${parts.join(' UNION ALL ')})
      ''', args);
    final row = rows.isNotEmpty ? rows.first : const <String, Object?>{};

    return QueueLibraryCounts(
      allTrackCount: (row['all_count'] as num?)?.toInt() ?? 0,
      albumCount: (row['album_count'] as num?)?.toInt() ?? 0,
      singleTrackCount: (row['single_count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<Map<String, dynamic>>> getQueueAlbumPage(
    QueueLibraryDbQuery request,
  ) async {
    final db = await database;
    await _ensureHistoryAttached(db);
    final args = <Object?>[];
    final unionSql = _queueAlbumUnionSql(request, args);
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM ($unionSql)
      ORDER BY ${_queueAlbumOrderBy(request.sortMode)}
      LIMIT ? OFFSET ?
      ''',
      [...args, request.limit, request.offset],
    );
    return rows.toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getQueueLocalAlbumTracks(
    String albumName,
    String artistName,
  ) async {
    final db = await database;
    final rows = await db.query(
      'library',
      where:
          "LOWER(album_name) = ? AND LOWER(COALESCE(NULLIF(album_artist, ''), artist_name)) = ?",
      whereArgs: [albumName.toLowerCase(), artistName.toLowerCase()],
      orderBy:
          'COALESCE(disc_number, 0), COALESCE(track_number, 0), track_name',
    );
    return rows.map(_dbRowToJson).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getQueueLocalAlbumTracksByKey(
    String albumKey,
  ) async {
    final db = await database;
    final rows = await db.query(
      'library',
      where: 'album_key = ?',
      whereArgs: [albumKey],
      orderBy:
          'COALESCE(disc_number, 0), COALESCE(track_number, 0), track_name',
    );
    return rows.map(_dbRowToJson).toList(growable: false);
  }

  Future<Map<String, dynamic>?> getById(String id) async {
    final db = await database;
    final rows = await db.query(
      'library',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _dbRowToJson(rows.first);
  }

  Future<Map<String, dynamic>?> getByIsrc(String isrc) async {
    final db = await database;
    final rows = await db.query(
      'library',
      where: 'isrc = ?',
      whereArgs: [isrc],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _dbRowToJson(rows.first);
  }

  Future<List<Map<String, dynamic>>> findByTrackAndArtist(
    String trackName,
    String artistName,
  ) async {
    final db = await database;
    final rows = await db.query(
      'library',
      where: 'match_key = ?',
      whereArgs: [matchKeyFor(trackName, artistName)],
    );
    return rows.map(_dbRowToJson).toList();
  }

  Future<Map<String, dynamic>?> findFirstByTrackAndArtist(
    String trackName,
    String artistName,
  ) async {
    final db = await database;
    final rows = await db.query(
      'library',
      where: 'match_key = ?',
      whereArgs: [matchKeyFor(trackName, artistName)],
      orderBy: _orderByForSort(LocalLibrarySortMode.album),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _dbRowToJson(rows.first);
  }

  Future<Map<String, dynamic>?> findExisting({
    String? isrc,
    String? trackName,
    String? artistName,
  }) async {
    if (isrc != null && isrc.isNotEmpty) {
      final byIsrc = await getByIsrc(isrc);
      if (byIsrc != null) return byIsrc;
    }

    if (trackName != null && artistName != null) {
      final matches = await findByTrackAndArtist(trackName, artistName);
      if (matches.isNotEmpty) return matches.first;
    }

    return null;
  }

  /// Resolves a track list with a bounded number of indexed queries instead
  /// of issuing up to three SQLite calls for every track.
  Future<List<Map<String, dynamic>?>> findExistingBatch(
    List<LocalLibraryBatchLookupRequest> requests,
  ) async {
    if (requests.isEmpty) return const [];
    final db = await database;
    final byId = <String, Map<String, dynamic>>{};
    final byIsrc = <String, Map<String, dynamic>>{};
    final byMatchKey = <String, Map<String, dynamic>>{};

    Future<void> loadColumn(
      String column,
      Iterable<String> rawValues,
      Map<String, Map<String, dynamic>> destination,
    ) {
      return sqlite.loadRowsByColumn(
        db,
        table: 'library',
        column: column,
        rawValues: rawValues,
        destination: destination,
        mapRow: _dbRowToJson,
      );
    }

    await Future.wait([
      loadColumn('id', requests.map((request) => request.id ?? ''), byId),
      loadColumn('isrc', requests.map((request) => request.isrc ?? ''), byIsrc),
      loadColumn(
        'match_key',
        requests.map(
          (request) => matchKeyFor(request.trackName, request.artistName),
        ),
        byMatchKey,
      ),
    ]);

    return requests
        .map((request) {
          final id = request.id?.trim() ?? '';
          if (id.isNotEmpty && byId[id] != null) return byId[id];
          final isrc = request.isrc?.trim() ?? '';
          if (isrc.isNotEmpty && byIsrc[isrc] != null) return byIsrc[isrc];
          return byMatchKey[matchKeyFor(request.trackName, request.artistName)];
        })
        .toList(growable: false);
  }

  Future<LocalLibraryLookupIndex> getLookupIndex() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT isrc, match_key FROM library');
    final isrcs = <String>{};
    final matchKeys = <String>{};
    for (final row in rows) {
      final isrc = row['isrc'] as String?;
      if (isrc != null && isrc.isNotEmpty) {
        isrcs.add(isrc);
      }
      final matchKey = row['match_key'] as String?;
      if (matchKey != null && matchKey.isNotEmpty) {
        matchKeys.add(matchKey);
      }
    }
    return LocalLibraryLookupIndex(
      isrcs: Set<String>.unmodifiable(isrcs),
      matchKeys: Set<String>.unmodifiable(matchKeys),
    );
  }

  Future<List<String>> getCoverPaths({int? limit, int? offset}) async {
    final db = await database;
    final rows = await db.query(
      'library',
      columns: ['cover_path'],
      where: 'cover_path IS NOT NULL AND cover_path != ""',
      limit: limit,
      offset: offset,
    );
    return rows
        .map((row) => row['cover_path'] as String?)
        .whereType<String>()
        .toList(growable: false);
  }

  /// Groups of tracks sharing one ISRC across download history and the
  /// local library. Library rows whose path key already appears in history
  /// are excluded so a scanned copy of a download doesn't pair with itself.
  /// Entries come back best-quality first.
  Future<List<IsrcDuplicateGroup>> findIsrcDuplicateGroups() async {
    final db = await database;
    final rows = await db.rawQuery('''
      WITH merged AS (
        SELECT h.id AS id, 'downloaded' AS source, h.track_name, h.artist_name,
               h.album_name, h.file_path, UPPER(TRIM(h.isrc)) AS isrc_key,
               h.bit_depth, h.sample_rate, h.bitrate, h.format
        FROM history_db.history h
        WHERE h.isrc IS NOT NULL AND TRIM(h.isrc) != ''
        UNION ALL
        SELECT l.id AS id, 'local' AS source, l.track_name, l.artist_name,
               l.album_name, l.file_path, UPPER(TRIM(l.isrc)) AS isrc_key,
               l.bit_depth, l.sample_rate, l.bitrate, l.format
        FROM library l
        WHERE l.isrc IS NOT NULL AND TRIM(l.isrc) != ''
          AND NOT EXISTS (
            SELECT 1
            FROM library_path_keys lpk
            JOIN history_db.history_path_keys hpk ON hpk.path_key = lpk.path_key
            WHERE lpk.item_id = l.id
          )
      )
      SELECT * FROM merged
      WHERE isrc_key IN (
        SELECT isrc_key FROM merged GROUP BY isrc_key HAVING COUNT(*) > 1
      )
      ORDER BY isrc_key, bit_depth DESC, sample_rate DESC, bitrate DESC
    ''');

    final groups = <String, List<IsrcDuplicateEntry>>{};
    for (final row in rows) {
      final isrc = row['isrc_key'] as String? ?? '';
      final filePath = row['file_path'] as String? ?? '';
      if (isrc.isEmpty || filePath.isEmpty) continue;
      groups
          .putIfAbsent(isrc, () => [])
          .add(
            IsrcDuplicateEntry(
              id: row['id'] as String,
              source: row['source'] as String,
              trackName: row['track_name'] as String? ?? '',
              artistName: row['artist_name'] as String? ?? '',
              albumName: row['album_name'] as String? ?? '',
              filePath: filePath,
              bitDepth: (row['bit_depth'] as num?)?.toInt(),
              sampleRate: (row['sample_rate'] as num?)?.toInt(),
              bitrate: (row['bitrate'] as num?)?.toInt(),
              format: row['format'] as String?,
            ),
          );
    }
    return [
      for (final entry in groups.entries)
        if (entry.value.length > 1)
          IsrcDuplicateGroup(isrc: entry.key, entries: entry.value),
    ];
  }

  Future<void> deleteByPath(String filePath) async {
    final db = await database;
    final rows = await db.query(
      'library',
      columns: ['id'],
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
    final ids = rows.map((row) => row['id'] as String).toList(growable: false);
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.delete(
          'library_path_keys',
          where: 'item_id = ?',
          whereArgs: [id],
        );
      }
      await txn.delete(
        'library',
        where: 'file_path = ?',
        whereArgs: [filePath],
      );
    });
  }

  Future<void> replaceWithConvertedItem({
    required LocalLibraryItem item,
    required String newFilePath,
    required String targetFormat,
    required String bitrate,
    int? bitDepth,
    int? sampleRate,
    bool keepOriginal = false,
  }) async {
    final db = await database;
    final stat = await fileStat(newFilePath);
    final now = DateTime.now();
    final normalizedFormat = _normalizeConvertedFormat(targetFormat);
    final convertedBitrate =
        _convertedBitrate(targetFormat: targetFormat, bitrate: bitrate) ??
        estimateAverageBitrateKbps(
          fileSizeBytes: stat?.size,
          durationSeconds: item.duration,
        );
    final updated = item.toJson()
      ..['id'] = _generateLibraryId(newFilePath)
      ..['filePath'] = newFilePath
      ..['scannedAt'] = now.toIso8601String()
      ..['fileModTime'] = stat?.modified?.millisecondsSinceEpoch
      ..['format'] = normalizedFormat
      ..['bitrate'] = convertedBitrate
      ..['audioMetadataScanVersion'] = convertedBitrate != null
          ? audioMetadataScanVersion
          : 0;

    if (normalizedFormat == 'mp3' ||
        normalizedFormat == 'opus' ||
        normalizedFormat == 'aac') {
      updated['bitDepth'] = null;
      updated['sampleRate'] = null;
    } else {
      updated['bitDepth'] = bitDepth ?? item.bitDepth;
      updated['sampleRate'] = sampleRate ?? item.sampleRate;
    }

    await db.transaction((txn) async {
      if (!keepOriginal) {
        await txn.delete(
          'library_path_keys',
          where: 'item_id = ?',
          whereArgs: [item.id],
        );
        await txn.delete(
          'library',
          where: 'id = ? OR file_path = ?',
          whereArgs: [item.id, item.filePath],
        );
      }
      await txn.insert(
        'library',
        _jsonToDbRow(updated),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final batch = txn.batch();
      _putPathKeysInBatch(
        batch,
        updated['id'] as String,
        updated['filePath'] as String?,
      );
      await batch.commit(noResult: true);
    });
  }

  Future<void> updateAudioMetadata(
    String id, {
    int? duration,
    int? bitDepth,
    int? sampleRate,
    int? bitrate,
    String? format,
  }) async {
    final values = <String, dynamic>{};
    if (duration != null && duration > 0) {
      values['duration'] = duration;
    }
    if (bitDepth != null && bitDepth > 0) {
      values['bit_depth'] = bitDepth;
    }
    if (sampleRate != null && sampleRate > 0) {
      values['sample_rate'] = sampleRate;
    }
    if (bitrate != null && bitrate > 0) {
      values['bitrate'] = bitrate;
    }
    final normalizedFormat = normalizeAudioFormatValue(format);
    if (normalizedFormat != null) {
      values['format'] = normalizedFormat;
    }
    if (values.isEmpty) return;
    values['audio_metadata_scan_version'] = audioMetadataScanVersion;

    final db = await database;
    await db.update('library', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'library_path_keys',
        where: 'item_id = ?',
        whereArgs: [id],
      );
      await txn.delete('library', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> cleanupMissingFiles() async {
    final db = await database;
    final rows = await db.query('library', columns: ['id', 'file_path']);

    final missingIds = <String>[];
    const checkChunkSize = 16;
    for (var i = 0; i < rows.length; i += checkChunkSize) {
      final end = (i + checkChunkSize < rows.length)
          ? i + checkChunkSize
          : rows.length;
      final chunk = rows.sublist(i, end);
      final checks = await Future.wait<MapEntry<String, bool>>(
        chunk.map((row) async {
          final id = row['id'] as String;
          final filePath = row['file_path'] as String;
          return MapEntry(id, await fileExists(filePath));
        }),
      );
      for (final check in checks) {
        if (!check.value) {
          missingIds.add(check.key);
        }
      }
    }

    if (missingIds.isEmpty) {
      return 0;
    }

    var removed = 0;
    const deleteChunkSize = 500;
    for (var i = 0; i < missingIds.length; i += deleteChunkSize) {
      final end = (i + deleteChunkSize < missingIds.length)
          ? i + deleteChunkSize
          : missingIds.length;
      final idChunk = missingIds.sublist(i, end);
      final placeholders = List.filled(idChunk.length, '?').join(',');
      await db.rawDelete(
        'DELETE FROM library_path_keys WHERE item_id IN ($placeholders)',
        idChunk,
      );
      removed += await db.rawDelete(
        'DELETE FROM library WHERE id IN ($placeholders)',
        idChunk,
      );
    }

    if (removed > 0) {
      _log.i('Cleaned up $removed missing files from library');
    }
    return removed;
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('library_path_keys');
      await txn.delete('library');
    });
    _log.i('Cleared all library data');
  }

  Future<int> getCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM library');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
    _historyAttached = false;
  }

  Future<Map<String, int>> getFileModTimes() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT file_path, COALESCE(file_mod_time, 0) AS file_mod_time, '
      'audio_metadata_scan_version FROM library',
    );
    final result = <String, int>{};
    for (final row in rows) {
      final path = row['file_path'] as String;
      final modTime = (row['file_mod_time'] as num?)?.toInt() ?? 0;
      final scanVersion =
          (row['audio_metadata_scan_version'] as num?)?.toInt() ?? 0;
      // A sentinel timestamp keeps the path in deletion/dedup checks while
      // making the incremental scanner treat a legacy row as changed once.
      result[path] = libraryIncrementalSnapshotModTime(
        storedModTime: modTime,
        storedScanVersion: scanVersion,
      );
    }
    return result;
  }

  Future<String> writeFileModTimesSnapshot() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT file_path, COALESCE(file_mod_time, 0) AS file_mod_time, '
      'audio_metadata_scan_version FROM library',
    );
    final tempDir = await getTemporaryDirectory();
    final file = File(
      join(
        tempDir.path,
        'library_file_mod_times_${DateTime.now().microsecondsSinceEpoch}.tsv',
      ),
    );
    final buffer = StringBuffer();
    for (final row in rows) {
      final path = row['file_path'] as String?;
      if (path == null || path.isEmpty) continue;
      final modTime = (row['file_mod_time'] as num?)?.toInt() ?? 0;
      final scanVersion =
          (row['audio_metadata_scan_version'] as num?)?.toInt() ?? 0;
      buffer
        ..write(
          libraryIncrementalSnapshotModTime(
            storedModTime: modTime,
            storedScanVersion: scanVersion,
          ),
        )
        ..write('\t')
        ..writeln(path);
    }
    await file.writeAsString(buffer.toString(), flush: true);
    return file.path;
  }

  Future<void> updateFileModTimes(Map<String, int> fileModTimes) async {
    if (fileModTimes.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final entry in fileModTimes.entries) {
      batch.update(
        'library',
        {'file_mod_time': entry.value},
        where: 'file_path = ?',
        whereArgs: [entry.key],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<Set<String>> getAllFilePaths() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT file_path FROM library');
    return rows.map((r) => r['file_path'] as String).toSet();
  }

  Future<int> deleteByPaths(List<String> filePaths) async {
    if (filePaths.isEmpty) return 0;
    final db = await database;
    var totalDeleted = 0;
    const chunkSize = 500;
    for (var i = 0; i < filePaths.length; i += chunkSize) {
      final end = (i + chunkSize < filePaths.length)
          ? i + chunkSize
          : filePaths.length;
      final chunk = filePaths.sublist(i, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT id FROM library WHERE file_path IN ($placeholders)',
        chunk,
      );
      final ids = rows
          .map((row) => row['id'] as String)
          .toList(growable: false);
      if (ids.isNotEmpty) {
        final idPlaceholders = List.filled(ids.length, '?').join(',');
        await db.rawDelete(
          'DELETE FROM library_path_keys WHERE item_id IN ($idPlaceholders)',
          ids,
        );
      }
      totalDeleted += await db.rawDelete(
        'DELETE FROM library WHERE file_path IN ($placeholders)',
        chunk,
      );
    }
    if (totalDeleted > 0) {
      _log.i('Deleted $totalDeleted items from library');
    }
    return totalDeleted;
  }

  String _normalizeConvertedFormat(String targetFormat) {
    return normalizeAudioFormatValue(targetFormat) ?? 'mp3';
  }

  int? _convertedBitrate({
    required String targetFormat,
    required String bitrate,
  }) {
    switch (targetFormat.trim().toLowerCase()) {
      case 'mp3':
      case 'opus':
      case 'aac':
        final match = RegExp(r'(\d+)').firstMatch(bitrate);
        return match != null ? int.tryParse(match.group(1)!) : null;
      default:
        return null;
    }
  }

  String _generateLibraryId(String filePath) {
    return 'lib_${_hashString(filePath).toRadixString(16)}';
  }

  int _hashString(String input) {
    var hash = 5381;
    for (final codeUnit in input.codeUnits) {
      hash = (((hash << 5) + hash) + codeUnit) & 0xffffffff;
    }
    return hash;
  }
}
