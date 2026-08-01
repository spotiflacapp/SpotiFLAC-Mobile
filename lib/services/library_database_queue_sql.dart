part of 'library_database.dart';

// SQL builders for the queue tab's history+local union queries.

extension _LibraryDbQueueSql on LibraryDatabase {
  String _queueTrackUnionSql(QueueLibraryDbQuery request, List<Object?> args) {
    final parts = <String>[];
    if (request.source != 'local') {
      final where = <String>[];
      _appendQueueHistoryFilters(where, args, request);
      if (request.filterMode == 'singles') {
        where.add('''
          h.album_key IN (
            SELECT album_key
            FROM history_db.history
            GROUP BY album_key
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
            album_key,
            COUNT(*) AS track_count,
            MAX(CAST(strftime('%s', downloaded_at) AS INTEGER) * 1000) AS latest_added
          FROM history_db.history
          GROUP BY album_key
          HAVING COUNT(*) > 1
        ) c
          ON c.album_key = h.album_key
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
    final query = LibraryDatabase.normalizeLookupText(request.searchQuery);
    if (query.isNotEmpty) {
      final like = '%${_escapeLikePattern(query)}%';
      where.add("h.search_text LIKE ? ESCAPE '\\'");
      args.add(like);
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
    final query = LibraryDatabase.normalizeLookupText(request.searchQuery);
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
      case 'missing-isrc':
        where.add('TRIM(COALESCE($isrcExpr, \'\')) = \'\'');
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
}
