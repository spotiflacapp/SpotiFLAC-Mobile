import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/services/history_database.dart';
import 'package:spotiflac_android/utils/path_match_keys.dart';

final _log = AppLogger('LibraryDatabase');

class LocalLibraryItem {
  final String id;
  final String trackName;
  final String artistName;
  final String albumName;
  final String? albumArtist;
  final String filePath;
  final String? coverPath;
  final DateTime scannedAt;
  final int? fileModTime;
  final String? isrc;
  final int? trackNumber;
  final int? totalTracks;
  final int? discNumber;
  final int? totalDiscs;
  final int? duration;
  final String? releaseDate;
  final int? bitDepth;
  final int? sampleRate;
  final int? bitrate; // kbps, for lossy formats (mp3, opus, ogg)
  final String? genre;
  final String? composer;
  final String? label;
  final String? copyright;
  final String? format; // flac, alac, eac3, ac3, ac4, mp3, opus, m4a

  const LocalLibraryItem({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.albumArtist,
    required this.filePath,
    this.coverPath,
    required this.scannedAt,
    this.fileModTime,
    this.isrc,
    this.trackNumber,
    this.totalTracks,
    this.discNumber,
    this.totalDiscs,
    this.duration,
    this.releaseDate,
    this.bitDepth,
    this.sampleRate,
    this.bitrate,
    this.genre,
    this.composer,
    this.label,
    this.copyright,
    this.format,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'trackName': trackName,
    'artistName': artistName,
    'albumName': albumName,
    'albumArtist': albumArtist,
    'filePath': filePath,
    'coverPath': coverPath,
    'scannedAt': scannedAt.toIso8601String(),
    'fileModTime': fileModTime,
    'isrc': isrc,
    'trackNumber': trackNumber,
    'totalTracks': totalTracks,
    'discNumber': discNumber,
    'totalDiscs': totalDiscs,
    'duration': duration,
    'releaseDate': releaseDate,
    'bitDepth': bitDepth,
    'sampleRate': sampleRate,
    'bitrate': bitrate,
    'genre': genre,
    'composer': composer,
    'label': label,
    'copyright': copyright,
    'format': format,
  };

  factory LocalLibraryItem.fromJson(Map<String, dynamic> json) =>
      LocalLibraryItem(
        id: json['id'] as String,
        trackName: json['trackName'] as String,
        artistName: json['artistName'] as String,
        albumName: json['albumName'] as String,
        albumArtist: json['albumArtist'] as String?,
        filePath: json['filePath'] as String,
        coverPath: json['coverPath'] as String?,
        scannedAt: DateTime.parse(json['scannedAt'] as String),
        fileModTime: (json['fileModTime'] as num?)?.toInt(),
        isrc: json['isrc'] as String?,
        trackNumber: (json['trackNumber'] as num?)?.toInt(),
        totalTracks: (json['totalTracks'] as num?)?.toInt(),
        discNumber: (json['discNumber'] as num?)?.toInt(),
        totalDiscs: (json['totalDiscs'] as num?)?.toInt(),
        duration: (json['duration'] as num?)?.toInt(),
        releaseDate: json['releaseDate'] as String?,
        bitDepth: (json['bitDepth'] as num?)?.toInt(),
        sampleRate: (json['sampleRate'] as num?)?.toInt(),
        bitrate: (json['bitrate'] as num?)?.toInt(),
        genre: json['genre'] as String?,
        composer: json['composer'] as String?,
        label: json['label'] as String?,
        copyright: json['copyright'] as String?,
        format: json['format'] as String?,
      );

  String get matchKey =>
      '${LibraryDatabase.normalizeLookupText(trackName)}|${LibraryDatabase.normalizeLookupText(artistName)}';
  String get albumKey =>
      '${LibraryDatabase.normalizeLookupText(albumName)}|${LibraryDatabase.normalizeLookupText(albumArtist ?? artistName)}';
}

enum LocalLibrarySortMode { album, title, artist, latest, quality }

enum LocalLibraryFilterMode { all, albums, singles }

class LocalLibraryPageRequest {
  final int limit;
  final int offset;
  final LocalLibrarySortMode sortMode;
  final LocalLibraryFilterMode filterMode;
  final String? searchQuery;
  final String? format;

  const LocalLibraryPageRequest({
    this.limit = 100,
    this.offset = 0,
    this.sortMode = LocalLibrarySortMode.album,
    this.filterMode = LocalLibraryFilterMode.all,
    this.searchQuery,
    this.format,
  });

  @override
  bool operator ==(Object other) {
    return other is LocalLibraryPageRequest &&
        other.limit == limit &&
        other.offset == offset &&
        other.sortMode == sortMode &&
        other.filterMode == filterMode &&
        other.searchQuery == searchQuery &&
        other.format == format;
  }

  @override
  int get hashCode =>
      Object.hash(limit, offset, sortMode, filterMode, searchQuery, format);
}

class LocalLibraryAlbumGroup {
  final String albumKey;
  final String albumName;
  final String artistName;
  final String? coverPath;
  final int trackCount;
  final int? maxBitDepth;
  final int? maxSampleRate;
  final int? maxBitrate;
  final String? format;
  final String? releaseDate;
  final String? genre;

  const LocalLibraryAlbumGroup({
    required this.albumKey,
    required this.albumName,
    required this.artistName,
    this.coverPath,
    required this.trackCount,
    this.maxBitDepth,
    this.maxSampleRate,
    this.maxBitrate,
    this.format,
    this.releaseDate,
    this.genre,
  });

  factory LocalLibraryAlbumGroup.fromDbRow(Map<String, dynamic> row) {
    return LocalLibraryAlbumGroup(
      albumKey: row['album_key'] as String,
      albumName: row['album_name'] as String? ?? '',
      artistName: row['artist_name'] as String? ?? '',
      coverPath: row['cover_path'] as String?,
      trackCount: (row['track_count'] as num?)?.toInt() ?? 0,
      maxBitDepth: (row['max_bit_depth'] as num?)?.toInt(),
      maxSampleRate: (row['max_sample_rate'] as num?)?.toInt(),
      maxBitrate: (row['max_bitrate'] as num?)?.toInt(),
      format: row['format'] as String?,
      releaseDate: row['release_date'] as String?,
      genre: row['genre'] as String?,
    );
  }
}

class LocalLibraryLookupIndex {
  final Set<String> isrcs;
  final Set<String> matchKeys;
  final Map<String, String> filePathById;

  const LocalLibraryLookupIndex({
    this.isrcs = const <String>{},
    this.matchKeys = const <String>{},
    this.filePathById = const <String, String>{},
  });
}

class QueueLibraryDbQuery {
  final int limit;
  final int offset;
  final String filterMode;
  final String? searchQuery;
  final String? source;
  final String? quality;
  final String? format;
  final String? metadata;
  final String sortMode;
  final bool includeLocal;

  const QueueLibraryDbQuery({
    this.limit = 100,
    this.offset = 0,
    this.filterMode = 'all',
    this.searchQuery,
    this.source,
    this.quality,
    this.format,
    this.metadata,
    this.sortMode = 'latest',
    this.includeLocal = true,
  });
}

class QueueLibraryCounts {
  final int allTrackCount;
  final int albumCount;
  final int singleTrackCount;

  const QueueLibraryCounts({
    required this.allTrackCount,
    required this.albumCount,
    required this.singleTrackCount,
  });
}

class LibraryDatabase {
  static final LibraryDatabase instance = LibraryDatabase._init();
  static Database? _database;
  bool _historyAttached = false;

  LibraryDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('local_library.db');
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

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, fileName);

    _log.i('Initializing library database at: $path');

    return await openDatabase(
      path,
      version: 8,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode = WAL');
        await db.execute('PRAGMA synchronous = NORMAL');
      },
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
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
      await _addColumnIfMissing(db, 'library', 'track_name_norm', 'TEXT');
      await _addColumnIfMissing(db, 'library', 'artist_name_norm', 'TEXT');
      await _addColumnIfMissing(db, 'library', 'album_name_norm', 'TEXT');
      await _addColumnIfMissing(db, 'library', 'album_artist_norm', 'TEXT');
      await _addColumnIfMissing(db, 'library', 'match_key', 'TEXT');
      await _addColumnIfMissing(db, 'library', 'album_key', 'TEXT');
      await _backfillNormalizedColumns(db);
      await _createNormalizedIndexes(db);
      _log.i('Added normalized local library lookup columns');
    }
    if (oldVersion < 8) {
      await _createPathKeyTable(db);
      await _backfillPathKeys(db);
      _log.i('Added local library path-key lookup table');
    }
  }

  Future<void> _createPathKeyTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_path_keys (
        item_id TEXT NOT NULL,
        path_key TEXT NOT NULL,
        PRIMARY KEY (item_id, path_key)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_path_keys_key ON library_path_keys(path_key)',
    );
  }

  Future<void> _backfillPathKeys(Database db) async {
    final rows = await db.query('library', columns: ['id', 'file_path']);
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
    batch.delete('library_path_keys', where: 'item_id = ?', whereArgs: [id]);
    for (final key in buildPathMatchKeys(filePath)) {
      batch.insert('library_path_keys', {
        'item_id': id,
        'path_key': key,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static String normalizeLookupText(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

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

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
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

  Future<List<Map<String, dynamic>>> getPage(
    LocalLibraryPageRequest request,
  ) async {
    final db = await database;
    final where = <String>[];
    final whereArgs = <Object?>[];
    _appendPageFilters(where, whereArgs, request);

    final rows = await db.query(
      'library',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: whereArgs,
      orderBy: _orderByForSort(request.sortMode),
      limit: request.limit,
      offset: request.offset,
    );
    return rows.map(_dbRowToJson).toList(growable: false);
  }

  Future<int> getPageCount(LocalLibraryPageRequest request) async {
    final db = await database;
    final where = <String>[];
    final whereArgs = <Object?>[];
    _appendPageFilters(where, whereArgs, request);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM library'
      '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}',
      whereArgs,
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<List<LocalLibraryAlbumGroup>> getAlbumPage({
    int limit = 100,
    int offset = 0,
    LocalLibraryFilterMode filterMode = LocalLibraryFilterMode.albums,
    LocalLibrarySortMode sortMode = LocalLibrarySortMode.album,
    String? searchQuery,
  }) async {
    final db = await database;
    final where = <String>[];
    final whereArgs = <Object?>[];
    _appendSearchFilter(where, whereArgs, searchQuery);
    final having = switch (filterMode) {
      LocalLibraryFilterMode.singles => 'COUNT(*) = 1',
      LocalLibraryFilterMode.albums => 'COUNT(*) > 1',
      LocalLibraryFilterMode.all => null,
    };
    final rows = await db.rawQuery(
      '''
      SELECT
        album_key,
        MIN(album_name) AS album_name,
        COALESCE(NULLIF(MIN(album_artist), ''), MIN(artist_name)) AS artist_name,
        MAX(CASE WHEN cover_path IS NOT NULL AND cover_path != '' THEN cover_path END) AS cover_path,
        COUNT(*) AS track_count,
        MAX(bit_depth) AS max_bit_depth,
        MAX(sample_rate) AS max_sample_rate,
        MAX(bitrate) AS max_bitrate,
        MAX(format) AS format,
        MAX(release_date) AS release_date,
        MAX(genre) AS genre
      FROM library
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      GROUP BY album_key
      ${having == null ? '' : 'HAVING $having'}
      ORDER BY ${_albumOrderByForSort(sortMode)}
      LIMIT ? OFFSET ?
      ''',
      [...whereArgs, limit, offset],
    );
    return rows.map(LocalLibraryAlbumGroup.fromDbRow).toList(growable: false);
  }

  Future<int> getAlbumCount({
    LocalLibraryFilterMode filterMode = LocalLibraryFilterMode.albums,
    String? searchQuery,
  }) async {
    final db = await database;
    final where = <String>[];
    final whereArgs = <Object?>[];
    _appendSearchFilter(where, whereArgs, searchQuery);
    final having = switch (filterMode) {
      LocalLibraryFilterMode.singles => 'COUNT(*) = 1',
      LocalLibraryFilterMode.albums => 'COUNT(*) > 1',
      LocalLibraryFilterMode.all => null,
    };
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS count FROM (
        SELECT album_key
        FROM library
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        GROUP BY album_key
        ${having == null ? '' : 'HAVING $having'}
      )
      ''', whereArgs);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  void _appendPageFilters(
    List<String> where,
    List<Object?> whereArgs,
    LocalLibraryPageRequest request,
  ) {
    _appendSearchFilter(where, whereArgs, request.searchQuery);
    final normalizedFormat = request.format?.trim().toLowerCase();
    if (normalizedFormat != null && normalizedFormat.isNotEmpty) {
      where.add('LOWER(format) = ?');
      whereArgs.add(normalizedFormat);
    }
    switch (request.filterMode) {
      case LocalLibraryFilterMode.all:
        break;
      case LocalLibraryFilterMode.albums:
        where.add(
          'album_key IN (SELECT album_key FROM library GROUP BY album_key HAVING COUNT(*) > 1)',
        );
        break;
      case LocalLibraryFilterMode.singles:
        where.add(
          'album_key IN (SELECT album_key FROM library GROUP BY album_key HAVING COUNT(*) = 1)',
        );
        break;
    }
  }

  void _appendSearchFilter(
    List<String> where,
    List<Object?> whereArgs,
    String? searchQuery,
  ) {
    final query = normalizeLookupText(searchQuery);
    if (query.isEmpty) return;
    final like = '%${_escapeLikePattern(query)}%';
    where.add(
      "(track_name_norm LIKE ? ESCAPE '\\' OR artist_name_norm LIKE ? ESCAPE '\\' OR album_name_norm LIKE ? ESCAPE '\\' OR album_artist_norm LIKE ? ESCAPE '\\')",
    );
    whereArgs.addAll([like, like, like, like]);
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

  String _albumOrderByForSort(LocalLibrarySortMode sortMode) {
    return switch (sortMode) {
      LocalLibrarySortMode.latest =>
        'MAX(scanned_at) DESC, artist_name, album_name',
      LocalLibrarySortMode.quality =>
        'MAX(COALESCE(bit_depth, 0)) DESC, MAX(COALESCE(sample_rate, 0)) DESC, MAX(COALESCE(bitrate, 0)) DESC, artist_name, album_name',
      LocalLibrarySortMode.title => 'album_name, artist_name',
      LocalLibrarySortMode.artist ||
      LocalLibrarySortMode.album => 'artist_name, album_name',
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

    // Build all three SQL strings and arg lists upfront (synchronous), then
    // fire all three COUNT queries concurrently with Future.wait. Previously
    // they ran sequentially, blocking each on the previous DB round-trip.
    final allArgs = <Object?>[];
    final allSql = _queueTrackUnionSql(
      QueueLibraryDbQuery(
        limit: request.limit,
        offset: request.offset,
        filterMode: 'all',
        searchQuery: request.searchQuery,
        source: request.source,
        quality: request.quality,
        format: request.format,
        metadata: request.metadata,
        sortMode: request.sortMode,
        includeLocal: request.includeLocal,
      ),
      allArgs,
    );

    final singleArgs = <Object?>[];
    final singleSql = _queueTrackUnionSql(
      QueueLibraryDbQuery(
        limit: request.limit,
        offset: request.offset,
        filterMode: 'singles',
        searchQuery: request.searchQuery,
        source: request.source,
        quality: request.quality,
        format: request.format,
        metadata: request.metadata,
        sortMode: request.sortMode,
        includeLocal: request.includeLocal,
      ),
      singleArgs,
    );

    final albumArgs = <Object?>[];
    final albumSql = _queueAlbumUnionSql(request, albumArgs);

    final results = await Future.wait([
      db.rawQuery('SELECT COUNT(*) AS count FROM ($allSql)', allArgs),
      db.rawQuery('SELECT COUNT(*) AS count FROM ($singleSql)', singleArgs),
      db.rawQuery('SELECT COUNT(*) AS count FROM ($albumSql)', albumArgs),
    ]);

    return QueueLibraryCounts(
      allTrackCount: Sqflite.firstIntValue(results[0]) ?? 0,
      singleTrackCount: Sqflite.firstIntValue(results[1]) ?? 0,
      albumCount: Sqflite.firstIntValue(results[2]) ?? 0,
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
    // Use the pre-computed album_key column (indexed) instead of applying
    // LOWER() to bare columns at query time, which bypasses all indexes.
    final key = albumKeyFor(albumName, null, artistName);
    final rows = await db.query(
      'library',
      where: 'album_key = ?',
      whereArgs: [key],
      orderBy:
          'COALESCE(disc_number, 0), COALESCE(track_number, 0), track_name_norm',
    );
    return rows.map(_dbRowToJson).toList(growable: false);
  }

  String _queueTrackUnionSql(QueueLibraryDbQuery request, List<Object?> args) {
    final parts = <String>[];
    if (request.source != 'local') {
      final where = <String>[];
      _appendQueueHistoryFilters(where, args, request);
      if (request.filterMode == 'singles') {
        where.add('''
          LOWER(h.album_name) || '|' || LOWER(COALESCE(h.album_artist, h.artist_name))
          IN (
            SELECT LOWER(album_name) || '|' || LOWER(COALESCE(album_artist, artist_name))
            FROM history_db.history
            GROUP BY LOWER(album_name), LOWER(COALESCE(album_artist, artist_name))
            HAVING COUNT(*) = 1
          )
          ''');
      }
      parts.add('''
        SELECT
          'downloaded' AS queue_source,
          'dl_' || h.id AS unified_id,
          h.id,
          h.track_name,
          h.artist_name,
          h.album_name,
          h.album_artist,
          h.cover_url,
          h.file_path,
          h.storage_mode,
          h.download_tree_uri,
          h.saf_relative_dir,
          h.saf_file_name,
          h.saf_repaired,
          h.service,
          h.downloaded_at,
          h.isrc,
          h.spotify_id,
          h.track_number,
          h.total_tracks,
          h.disc_number,
          h.total_discs,
          h.duration,
          h.release_date,
          h.quality,
          h.bit_depth,
          h.sample_rate,
          h.genre,
          h.composer,
          h.label,
          h.copyright,
          NULL AS cover_path,
          NULL AS scanned_at,
          NULL AS file_mod_time,
          h.bitrate,
          h.format,
          LOWER(h.track_name) AS sort_track,
          LOWER(h.artist_name) AS sort_artist,
          LOWER(h.album_name) AS sort_album,
          LOWER(COALESCE(h.genre, '')) AS sort_genre,
          h.release_date AS sort_release,
          CAST(strftime('%s', h.downloaded_at) AS INTEGER) * 1000 AS sort_added
        FROM history_db.history h
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
      if (request.filterMode == 'singles') {
        where.add('''
          l.album_key IN (
            SELECT album_key
            FROM library
            WHERE NOT EXISTS (
              SELECT 1
              FROM library_path_keys lpk
              JOIN history_db.history_path_keys hpk ON hpk.path_key = lpk.path_key
              WHERE lpk.item_id = library.id
            )
            GROUP BY album_key
            HAVING COUNT(*) = 1
          )
          ''');
      }
      parts.add('''
        SELECT
          'local' AS queue_source,
          'local_' || l.id AS unified_id,
          l.id,
          l.track_name,
          l.artist_name,
          l.album_name,
          l.album_artist,
          NULL AS cover_url,
          l.file_path,
          NULL AS storage_mode,
          NULL AS download_tree_uri,
          NULL AS saf_relative_dir,
          NULL AS saf_file_name,
          0 AS saf_repaired,
          'local' AS service,
          NULL AS downloaded_at,
          l.isrc,
          NULL AS spotify_id,
          l.track_number,
          l.total_tracks,
          l.disc_number,
          l.total_discs,
          l.duration,
          l.release_date,
          NULL AS quality,
          l.bit_depth,
          l.sample_rate,
          l.genre,
          l.composer,
          l.label,
          l.copyright,
          l.cover_path,
          l.scanned_at,
          l.file_mod_time,
          l.bitrate,
          l.format,
          l.track_name_norm AS sort_track,
          l.artist_name_norm AS sort_artist,
          l.album_name_norm AS sort_album,
          LOWER(COALESCE(l.genre, '')) AS sort_genre,
          l.release_date AS sort_release,
          COALESCE(l.file_mod_time, CAST(strftime('%s', l.scanned_at) AS INTEGER) * 1000) AS sort_added
        FROM library l
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        ''');
    }

    if (parts.isEmpty) {
      return '''
        SELECT
          NULL AS queue_source,
          NULL AS unified_id,
          NULL AS id,
          NULL AS track_name,
          NULL AS artist_name,
          NULL AS album_name,
          NULL AS album_artist,
          NULL AS cover_url,
          NULL AS file_path,
          NULL AS storage_mode,
          NULL AS download_tree_uri,
          NULL AS saf_relative_dir,
          NULL AS saf_file_name,
          NULL AS saf_repaired,
          NULL AS service,
          NULL AS downloaded_at,
          NULL AS isrc,
          NULL AS spotify_id,
          NULL AS track_number,
          NULL AS total_tracks,
          NULL AS disc_number,
          NULL AS total_discs,
          NULL AS duration,
          NULL AS release_date,
          NULL AS quality,
          NULL AS bit_depth,
          NULL AS sample_rate,
          NULL AS genre,
          NULL AS composer,
          NULL AS label,
          NULL AS copyright,
          NULL AS cover_path,
          NULL AS scanned_at,
          NULL AS file_mod_time,
          NULL AS bitrate,
          NULL AS format,
          NULL AS sort_track,
          NULL AS sort_artist,
          NULL AS sort_album,
          NULL AS sort_genre,
          NULL AS sort_release,
          NULL AS sort_added
        WHERE 0
      ''';
    }
    return parts.join(' UNION ALL ');
  }

  String _queueAlbumUnionSql(QueueLibraryDbQuery request, List<Object?> args) {
    final parts = <String>[];
    if (request.source != 'local') {
      final where = <String>[];
      _appendQueueHistoryFilters(where, args, request);
      parts.add('''
        SELECT
          'downloaded' AS queue_source,
          c.album_key,
          MIN(h.album_name) AS album_name,
          COALESCE(NULLIF(MIN(h.album_artist), ''), MIN(h.artist_name)) AS artist_name,
          MAX(CASE WHEN h.cover_url IS NOT NULL AND h.cover_url != '' THEN h.cover_url END) AS cover_url,
          NULL AS cover_path,
          MAX(h.file_path) AS sample_file_path,
          COUNT(*) AS track_count,
          c.latest_added AS sort_added,
          MIN(LOWER(COALESCE(h.album_name, ''))) AS sort_album,
          MIN(LOWER(COALESCE(h.album_artist, h.artist_name, ''))) AS sort_artist,
          MAX(h.release_date) AS sort_release,
          MAX(LOWER(COALESCE(h.genre, ''))) AS sort_genre
        FROM history_db.history h
        JOIN (
          SELECT
            LOWER(album_name) || '|' || LOWER(COALESCE(album_artist, artist_name)) AS album_key,
            COUNT(*) AS track_count,
            MAX(CAST(strftime('%s', downloaded_at) AS INTEGER) * 1000) AS latest_added
          FROM history_db.history
          GROUP BY LOWER(album_name), LOWER(COALESCE(album_artist, artist_name))
          HAVING COUNT(*) > 1
        ) c
          ON c.album_key = LOWER(h.album_name) || '|' || LOWER(COALESCE(h.album_artist, h.artist_name))
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        GROUP BY c.album_key
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
          'local' AS queue_source,
          c.album_key,
          MIN(l.album_name) AS album_name,
          COALESCE(NULLIF(MIN(l.album_artist), ''), MIN(l.artist_name)) AS artist_name,
          NULL AS cover_url,
          MAX(CASE WHEN l.cover_path IS NOT NULL AND l.cover_path != '' THEN l.cover_path END) AS cover_path,
          MAX(l.file_path) AS sample_file_path,
          COUNT(*) AS track_count,
          c.latest_added AS sort_added,
          MIN(l.album_name_norm) AS sort_album,
          MIN(l.album_artist_norm) AS sort_artist,
          MAX(l.release_date) AS sort_release,
          MAX(LOWER(COALESCE(l.genre, ''))) AS sort_genre
        FROM library l
        JOIN (
          SELECT
            album_key,
            COUNT(*) AS track_count,
            MAX(COALESCE(file_mod_time, CAST(strftime('%s', scanned_at) AS INTEGER) * 1000)) AS latest_added
          FROM library
          WHERE NOT EXISTS (
            SELECT 1
            FROM library_path_keys lpk
            JOIN history_db.history_path_keys hpk ON hpk.path_key = lpk.path_key
            WHERE lpk.item_id = library.id
          )
          GROUP BY album_key
          HAVING COUNT(*) > 1
        ) c ON c.album_key = l.album_key
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        GROUP BY c.album_key
        ''');
    }

    if (parts.isEmpty) {
      return '''
        SELECT
          NULL AS queue_source,
          NULL AS album_key,
          NULL AS album_name,
          NULL AS artist_name,
          NULL AS cover_url,
          NULL AS cover_path,
          NULL AS sample_file_path,
          NULL AS track_count,
          NULL AS sort_added,
          NULL AS sort_album,
          NULL AS sort_artist,
          NULL AS sort_release,
          NULL AS sort_genre
        WHERE 0
      ''';
    }
    return parts.join(' UNION ALL ');
  }

  void _appendQueueHistoryFilters(
    List<String> where,
    List<Object?> args,
    QueueLibraryDbQuery request,
  ) {
    final query = normalizeLookupText(request.searchQuery);
    if (query.isNotEmpty) {
      final like = '%${_escapeLikePattern(query)}%';
      where.add('''
        (
          LOWER(h.track_name) LIKE ? ESCAPE '\\' OR
          LOWER(h.artist_name) LIKE ? ESCAPE '\\' OR
          LOWER(h.album_name) LIKE ? ESCAPE '\\' OR
          LOWER(COALESCE(h.album_artist, '')) LIKE ? ESCAPE '\\'
        )
        ''');
      args.addAll([like, like, like, like]);
    }
    _appendQueueCommonFilters(
      where,
      args,
      request,
      filePathExpr: 'h.file_path',
      formatExpr: 'h.format',
      qualityExpr: 'h.quality',
      bitDepthExpr: 'h.bit_depth',
      artistExpr: 'h.artist_name',
      albumArtistExpr: 'h.album_artist',
      releaseDateExpr: 'h.release_date',
      genreExpr: 'h.genre',
      trackNumberExpr: 'h.track_number',
      discNumberExpr: 'h.disc_number',
      isrcExpr: 'h.isrc',
      labelExpr: 'h.label',
    );
  }

  void _appendQueueLocalFilters(
    List<String> where,
    List<Object?> args,
    QueueLibraryDbQuery request,
  ) {
    final query = normalizeLookupText(request.searchQuery);
    if (query.isNotEmpty) {
      final like = '%${_escapeLikePattern(query)}%';
      where.add('''
        (
          l.track_name_norm LIKE ? ESCAPE '\\' OR
          l.artist_name_norm LIKE ? ESCAPE '\\' OR
          l.album_name_norm LIKE ? ESCAPE '\\' OR
          l.album_artist_norm LIKE ? ESCAPE '\\'
        )
        ''');
      args.addAll([like, like, like, like]);
    }
    _appendQueueCommonFilters(
      where,
      args,
      request,
      filePathExpr: 'l.file_path',
      formatExpr: 'l.format',
      qualityExpr: 'NULL',
      bitDepthExpr: 'l.bit_depth',
      artistExpr: 'l.artist_name',
      albumArtistExpr: 'l.album_artist',
      releaseDateExpr: 'l.release_date',
      genreExpr: 'l.genre',
      trackNumberExpr: 'l.track_number',
      discNumberExpr: 'l.disc_number',
      isrcExpr: 'l.isrc',
      labelExpr: 'l.label',
    );
  }

  void _appendQueueCommonFilters(
    List<String> where,
    List<Object?> args,
    QueueLibraryDbQuery request, {
    required String filePathExpr,
    required String? formatExpr,
    required String qualityExpr,
    required String bitDepthExpr,
    required String artistExpr,
    required String albumArtistExpr,
    required String releaseDateExpr,
    required String genreExpr,
    required String trackNumberExpr,
    required String discNumberExpr,
    required String isrcExpr,
    required String labelExpr,
  }) {
    final quality = request.quality?.trim().toLowerCase();
    if (quality != null && quality.isNotEmpty) {
      final isHiRes =
          '(COALESCE($bitDepthExpr, 0) >= 24 OR LOWER(COALESCE($qualityExpr, \'\')) LIKE \'24%\')';
      final isCd =
          '(COALESCE($bitDepthExpr, 0) = 16 OR LOWER(COALESCE($qualityExpr, \'\')) LIKE \'16%\')';
      switch (quality) {
        case 'hires':
          where.add(isHiRes);
          break;
        case 'cd':
          where.add(isCd);
          break;
        case 'lossy':
          where.add('NOT ($isHiRes OR $isCd)');
          break;
      }
    }

    final format = request.format?.trim().toLowerCase();
    if (format != null && format.isNotEmpty) {
      if (formatExpr == null) {
        where.add('LOWER($filePathExpr) LIKE ?');
        args.add('%.$format');
      } else {
        where.add(
          '(LOWER(COALESCE($formatExpr, \'\')) = ? OR LOWER($filePathExpr) LIKE ?)',
        );
        args.addAll([format, '%.$format']);
      }
    }

    final metadata = request.metadata?.trim();
    if (metadata == null || metadata.isEmpty) return;
    final hasArtist = 'TRIM(COALESCE($artistExpr, \'\')) != \'\'';
    final hasAlbumArtist = 'TRIM(COALESCE($albumArtistExpr, \'\')) != \'\'';
    final hasReleaseDate =
        'TRIM(COALESCE($releaseDateExpr, \'\')) GLOB \'*[0-9][0-9][0-9][0-9]*\'';
    final hasGenre = 'TRIM(COALESCE($genreExpr, \'\')) != \'\'';
    final hasTrackNumber = 'COALESCE($trackNumberExpr, 0) > 0';
    final hasDiscNumber = 'COALESCE($discNumberExpr, 0) > 0';
    final hasLabel = 'TRIM(COALESCE($labelExpr, \'\')) != \'\'';
    final normalizedIsrc =
        'REPLACE(REPLACE(UPPER(TRIM(COALESCE($isrcExpr, \'\'))), \'-\', \'\'), \' \', \'\')';
    final hasIncorrectIsrc =
        'TRIM(COALESCE($isrcExpr, \'\')) != \'\' AND LENGTH($normalizedIsrc) != 12';
    final isComplete =
        '($hasArtist AND $hasAlbumArtist AND $hasReleaseDate AND $hasGenre AND $hasTrackNumber AND $hasDiscNumber AND $hasLabel AND NOT ($hasIncorrectIsrc))';

    switch (metadata) {
      case 'complete':
        where.add(isComplete);
        break;
      case 'missing-any':
        where.add('NOT $isComplete');
        break;
      case 'missing-year':
        where.add('NOT ($hasReleaseDate)');
        break;
      case 'missing-genre':
        where.add('NOT ($hasGenre)');
        break;
      case 'missing-album-artist':
        where.add('NOT ($hasAlbumArtist)');
        break;
      case 'missing-track-number':
        where.add('NOT ($hasTrackNumber)');
        break;
      case 'missing-disc-number':
        where.add('NOT ($hasDiscNumber)');
        break;
      case 'missing-artist':
        where.add('NOT ($hasArtist)');
        break;
      case 'incorrect-isrc-format':
        where.add('($hasIncorrectIsrc)');
        break;
      case 'missing-label':
        where.add('NOT ($hasLabel)');
        break;
    }
  }

  String _queueTrackOrderBy(String sortMode) {
    return switch (sortMode) {
      'oldest' => 'sort_added ASC, sort_track ASC',
      'a-z' => 'sort_track ASC, sort_artist ASC',
      'z-a' => 'sort_track DESC, sort_artist DESC',
      'artist-asc' => 'sort_artist ASC, sort_track ASC',
      'artist-desc' => 'sort_artist DESC, sort_track ASC',
      'album-asc' => 'sort_album ASC, sort_track ASC',
      'album-desc' => 'sort_album DESC, sort_track ASC',
      'release-oldest' => 'sort_release ASC, sort_track ASC',
      'release-newest' => 'sort_release DESC, sort_track ASC',
      'genre-asc' => 'sort_genre ASC, sort_track ASC',
      'genre-desc' => 'sort_genre DESC, sort_track ASC',
      _ => 'sort_added DESC, sort_track ASC',
    };
  }

  String _queueAlbumOrderBy(String sortMode) {
    return switch (sortMode) {
      'oldest' => 'sort_added ASC, sort_album ASC',
      'a-z' || 'album-asc' => 'sort_album ASC, sort_artist ASC',
      'z-a' || 'album-desc' => 'sort_album DESC, sort_artist DESC',
      'artist-asc' => 'sort_artist ASC, sort_album ASC',
      'artist-desc' => 'sort_artist DESC, sort_album ASC',
      'release-oldest' => 'sort_release ASC, sort_album ASC',
      'release-newest' => 'sort_release DESC, sort_album ASC',
      'genre-asc' => 'sort_genre ASC, sort_album ASC',
      'genre-desc' => 'sort_genre DESC, sort_album ASC',
      _ => 'sort_added DESC, sort_album ASC',
    };
  }

  Map<String, dynamic> _queueTrackRowToJson(Map<String, dynamic> row) {
    final source = row['queue_source'] as String? ?? '';
    if (source == 'local') {
      return {
        'source': source,
        'item': {
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
        },
      };
    }

    return {
      'source': source,
      'item': {
        'id': row['id'],
        'trackName': row['track_name'],
        'artistName': row['artist_name'],
        'albumName': row['album_name'],
        'albumArtist': row['album_artist'],
        'coverUrl': row['cover_url'],
        'filePath': row['file_path'],
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
      },
    };
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

  Future<Map<String, dynamic>?> getByFilePath(String filePath) async {
    final db = await database;
    final rows = await db.query(
      'library',
      where: 'file_path = ?',
      whereArgs: [filePath],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _dbRowToJson(rows.first);
  }

  Future<bool> existsByIsrc(String isrc) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT 1 FROM library WHERE isrc = ? LIMIT 1',
      [isrc],
    );
    return result.isNotEmpty;
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

  Future<Set<String>> getAllIsrcs() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT isrc FROM library WHERE isrc IS NOT NULL AND isrc != ""',
    );
    return rows.map((r) => r['isrc'] as String).toSet();
  }

  Future<Set<String>> getAllTrackKeys() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT match_key FROM library WHERE match_key IS NOT NULL AND match_key != ""',
    );
    return rows.map((r) => r['match_key'] as String).toSet();
  }

  Future<LocalLibraryLookupIndex> getLookupIndex() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT id, file_path, isrc, match_key FROM library',
    );
    final isrcs = <String>{};
    final matchKeys = <String>{};
    final filePathById = <String, String>{};
    for (final row in rows) {
      final id = row['id'] as String?;
      final filePath = row['file_path'] as String?;
      if (id != null && id.isNotEmpty && filePath != null) {
        filePathById[id] = filePath;
      }
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
      filePathById: Map<String, String>.unmodifiable(filePathById),
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
  }) async {
    final db = await database;
    final stat = await fileStat(newFilePath);
    final now = DateTime.now();
    final normalizedFormat = _normalizeConvertedFormat(targetFormat);
    final updated = item.toJson()
      ..['id'] = _generateLibraryId(newFilePath)
      ..['filePath'] = newFilePath
      ..['scannedAt'] = now.toIso8601String()
      ..['fileModTime'] = stat?.modified?.millisecondsSinceEpoch
      ..['format'] = normalizedFormat
      ..['bitrate'] = _convertedBitrate(
        targetFormat: targetFormat,
        bitrate: bitrate,
      );

    if (normalizedFormat == 'mp3' ||
        normalizedFormat == 'opus' ||
        normalizedFormat == 'aac') {
      updated['bitDepth'] = null;
    }

    await db.transaction((txn) async {
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
    if (values.isEmpty) return;

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

  Future<List<Map<String, dynamic>>> search(
    String query, {
    int limit = 50,
  }) async {
    final db = await database;
    final searchQuery = '%${_escapeLikePattern(query.toLowerCase())}%';
    final rows = await db.query(
      'library',
      where:
          "LOWER(track_name) LIKE ? ESCAPE '\\' OR LOWER(artist_name) LIKE ? ESCAPE '\\' OR LOWER(album_name) LIKE ? ESCAPE '\\'",
      whereArgs: [searchQuery, searchQuery, searchQuery],
      orderBy: 'track_name',
      limit: limit,
    );
    return rows.map(_dbRowToJson).toList();
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
      'SELECT file_path, COALESCE(file_mod_time, 0) AS file_mod_time FROM library',
    );
    final result = <String, int>{};
    for (final row in rows) {
      final path = row['file_path'] as String;
      final modTime = (row['file_mod_time'] as num?)?.toInt() ?? 0;
      result[path] = modTime;
    }
    return result;
  }

  Future<String> writeFileModTimesSnapshot() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT file_path, COALESCE(file_mod_time, 0) AS file_mod_time FROM library',
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
      buffer
        ..write(modTime)
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
    switch (targetFormat.trim().toLowerCase()) {
      case 'alac':
        return 'm4a';
      case 'aac':
        return 'aac';
      case 'flac':
        return 'flac';
      case 'opus':
        return 'opus';
      default:
        return 'mp3';
    }
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
