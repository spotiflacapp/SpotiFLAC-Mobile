part of 'library_database.dart';

// SQL builders for the queue tab's history+local union queries.

String confirmedMissingLyricsSqlPredicate({
  required String hasLyricsExpr,
  required String lyricsKnownExpr,
}) => '($lyricsKnownExpr) AND COALESCE($hasLyricsExpr, 0) = 0';

String confirmedMissingReplayGainSqlPredicate({
  required String hasReplayGainExpr,
  required String replayGainKnownExpr,
}) => '($replayGainKnownExpr) AND COALESCE($hasReplayGainExpr, 0) = 0';

class _QueueOrderTerm {
  final String column;
  final bool descending;

  const _QueueOrderTerm(this.column, {this.descending = false});
}

extension _LibraryDbQueueSql on LibraryDatabase {
  String _queueTrackUnionSql(
    QueueLibraryDbQuery request,
    List<Object?> args, {
    required List<_QueueOrderTerm> orderTerms,
    required bool usesCursor,
  }) {
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
      final selectSql =
          '''
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
          h.has_replaygain,
          h.replaygain_metadata_scan_version,
          h.sort_track,
          h.sort_artist,
          h.sort_album,
          h.sort_genre,
          h.sort_release,
          h.sort_added
        FROM history_db.history h
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        ''';
      parts.add(
        _boundedQueuePart(
          selectSql,
          request,
          args,
          orderTerms,
          usesCursor: usesCursor,
        ),
      );
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
            FROM ${LibraryDatabase.visibleLibraryView} candidate
            WHERE NOT EXISTS (
              SELECT 1
              FROM library_path_keys lpk
              JOIN history_db.history_path_keys hpk ON hpk.path_key = lpk.path_key
              WHERE lpk.item_id = candidate.id
            )
            GROUP BY album_key
            HAVING COUNT(*) = 1
          )
          ''');
      }
      final selectSql =
          '''
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
          l.has_replaygain,
          CASE WHEN l.audio_metadata_scan_version >= ${LibraryDatabase.audioMetadataScanVersion}
            THEN 1 ELSE 0 END AS replaygain_metadata_scan_version,
          l.track_name_norm AS sort_track,
          l.artist_name_norm AS sort_artist,
          l.album_name_norm AS sort_album,
          l.sort_genre,
          l.sort_release,
          l.sort_added
        FROM ${LibraryDatabase.visibleLibraryView} l
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        ''';
      parts.add(
        _boundedQueuePart(
          selectSql,
          request,
          args,
          orderTerms,
          usesCursor: usesCursor,
        ),
      );
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
          NULL AS has_replaygain,
          NULL AS replaygain_metadata_scan_version,
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

  String _queueAlbumUnionSql(
    QueueLibraryDbQuery request,
    List<Object?> args, {
    required List<_QueueOrderTerm> orderTerms,
    required bool usesCursor,
  }) {
    final parts = <String>[];
    if (request.source != 'local') {
      final where = <String>[];
      _appendQueueHistoryFilters(where, args, request);
      final selectSql =
          '''
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
          MIN(COALESCE(h.sort_album, '')) AS sort_album,
          MIN(COALESCE(h.sort_album_artist, '')) AS sort_artist,
          COALESCE(MAX(h.release_date), '') AS sort_release,
          COALESCE(MAX(h.sort_genre), '') AS sort_genre
        FROM history_db.history h
        JOIN (
          SELECT
            album_key,
            COUNT(*) AS track_count,
            MAX(COALESCE(sort_added, 0)) AS latest_added
          FROM history_db.history
          GROUP BY album_key
          HAVING COUNT(*) > ${request.includeSingleTrackAlbums ? 0 : 1}
        ) c
          ON c.album_key = h.album_key
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        GROUP BY c.album_key
        ''';
      parts.add(
        _boundedQueuePart(
          selectSql,
          request,
          args,
          orderTerms,
          usesCursor: usesCursor,
        ),
      );
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
      final selectSql =
          '''
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
          COALESCE(MAX(l.release_date), '') AS sort_release,
          COALESCE(MAX(l.sort_genre), '') AS sort_genre
        FROM ${LibraryDatabase.visibleLibraryView} l
        JOIN (
          SELECT
            album_key,
            COUNT(*) AS track_count,
            MAX(COALESCE(sort_added, 0)) AS latest_added
          FROM ${LibraryDatabase.visibleLibraryView} candidate
          WHERE NOT EXISTS (
            SELECT 1
            FROM library_path_keys lpk
            JOIN history_db.history_path_keys hpk ON hpk.path_key = lpk.path_key
            WHERE lpk.item_id = candidate.id
          )
          GROUP BY album_key
          HAVING COUNT(*) > ${request.includeSingleTrackAlbums ? 0 : 1}
        ) c ON c.album_key = l.album_key
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        GROUP BY c.album_key
        ''';
      parts.add(
        _boundedQueuePart(
          selectSql,
          request,
          args,
          orderTerms,
          usesCursor: usesCursor,
        ),
      );
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
    if (request.albumArtist != null) {
      where.add('h.sort_album_artist = ?');
      args.add(LibraryDatabase.normalizeLookupText(request.albumArtist));
    }
    final query = LibraryDatabase.normalizeLookupText(request.searchQuery);
    if (query.isNotEmpty) {
      final ftsQuery = sqlite.ftsPhraseSearchQuery(query);
      if (HistoryDatabase.instance.searchFtsAvailable && ftsQuery != null) {
        where.add('''
          h.rowid IN (
            SELECT rowid
            FROM history_db.history_search_fts
            WHERE history_search_fts MATCH ?
          )
          ''');
        args.add(ftsQuery);
      } else {
        final like = '%${_escapeLikePattern(query)}%';
        where.add("h.search_text LIKE ? ESCAPE '\\'");
        args.add(like);
      }
    }
    _appendQueueCommonFilters(
      where,
      args,
      request,
      filePathExpr: 'h.file_path',
      formatExpr: 'h.format',
      qualityExpr: 'h.quality',
      bitDepthExpr: 'h.bit_depth',
      albumNameExpr: 'h.album_name',
      artistExpr: 'h.artist_name',
      albumArtistExpr: 'h.album_artist',
      releaseDateExpr: 'h.release_date',
      genreExpr: 'h.genre',
      trackNumberExpr: 'h.track_number',
      totalTracksExpr: 'h.total_tracks',
      discNumberExpr: 'h.disc_number',
      isrcExpr: 'h.isrc',
      labelExpr: 'h.label',
      hasLyricsExpr: 'h.has_lyrics',
      lyricsKnownExpr: 'COALESCE(h.lyrics_metadata_scan_version, 0) >= 1',
      hasReplayGainExpr: 'h.has_replaygain',
      replayGainKnownExpr:
          'COALESCE(h.replaygain_metadata_scan_version, 0) >= 1',
    );
  }

  void _appendQueueLocalFilters(
    List<String> where,
    List<Object?> args,
    QueueLibraryDbQuery request,
  ) {
    if (request.albumArtist != null) {
      where.add('l.album_artist_norm = ?');
      args.add(LibraryDatabase.normalizeLookupText(request.albumArtist));
    }
    final query = LibraryDatabase.normalizeLookupText(request.searchQuery);
    if (query.isNotEmpty) {
      final ftsQuery = sqlite.ftsPhraseSearchQuery(query);
      if (searchFtsAvailable && ftsQuery != null) {
        where.add('''
          l.rowid IN (
            SELECT rowid
            FROM library_search_fts
            WHERE library_search_fts MATCH ?
          )
          ''');
        args.add(ftsQuery);
      } else {
        final like = '%${_escapeLikePattern(query)}%';
        where.add("l.search_text LIKE ? ESCAPE '\\'");
        args.add(like);
      }
    }
    _appendQueueCommonFilters(
      where,
      args,
      request,
      filePathExpr: 'l.file_path',
      formatExpr: 'l.format',
      qualityExpr: 'NULL',
      bitDepthExpr: 'l.bit_depth',
      albumNameExpr: 'l.album_name',
      artistExpr: 'l.artist_name',
      albumArtistExpr: 'l.album_artist',
      releaseDateExpr: 'l.release_date',
      genreExpr: 'l.genre',
      trackNumberExpr: 'l.track_number',
      totalTracksExpr: 'l.total_tracks',
      discNumberExpr: 'l.disc_number',
      isrcExpr: 'l.isrc',
      labelExpr: 'l.label',
      hasLyricsExpr: 'l.has_lyrics',
      lyricsKnownExpr:
          'COALESCE(l.audio_metadata_scan_version, 0) >= ${LibraryDatabase.lyricsMetadataScanVersion}',
      hasReplayGainExpr: 'l.has_replaygain',
      replayGainKnownExpr:
          'COALESCE(l.audio_metadata_scan_version, 0) >= ${LibraryDatabase.audioMetadataScanVersion}',
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
    required String albumNameExpr,
    required String artistExpr,
    required String albumArtistExpr,
    required String releaseDateExpr,
    required String genreExpr,
    required String trackNumberExpr,
    required String totalTracksExpr,
    required String discNumberExpr,
    required String isrcExpr,
    required String labelExpr,
    required String hasLyricsExpr,
    required String lyricsKnownExpr,
    required String hasReplayGainExpr,
    required String replayGainKnownExpr,
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
      case 'missing-tracks':
        where.add('''
          (
            COALESCE($totalTracksExpr, 0) > 0
            AND (
              SELECT COUNT(DISTINCT sub.track_number)
              FROM library AS sub
              WHERE COALESCE(sub.album_name, '') = COALESCE($albumNameExpr, '')
                AND COALESCE(sub.album_artist, '') = COALESCE($albumArtistExpr, '')
            ) < COALESCE($totalTracksExpr, 0)
          ) OR (
            COALESCE($trackNumberExpr, 0) > 0
            AND (
              SELECT MAX(sub.track_number)
              FROM library AS sub
              WHERE COALESCE(sub.album_name, '') = COALESCE($albumNameExpr, '')
                AND COALESCE(sub.album_artist, '') = COALESCE($albumArtistExpr, '')
                AND COALESCE(sub.disc_number, 1) = COALESCE($discNumberExpr, 1)
            ) > (
              SELECT COUNT(DISTINCT sub.track_number)
              FROM library AS sub
              WHERE COALESCE(sub.album_name, '') = COALESCE($albumNameExpr, '')
                AND COALESCE(sub.album_artist, '') = COALESCE($albumArtistExpr, '')
                AND COALESCE(sub.disc_number, 1) = COALESCE($discNumberExpr, 1)
            )
          )
        ''');
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
      case 'missing-lyrics':
        // A default false value on legacy rows means "not scanned yet", not
        // "confirmed missing". Only show files whose lyrics probe completed.
        where.add(
          confirmedMissingLyricsSqlPredicate(
            hasLyricsExpr: hasLyricsExpr,
            lyricsKnownExpr: lyricsKnownExpr,
          ),
        );
        break;
      case 'missing-replaygain':
        // Only files whose tags were read since ReplayGain was indexed.
        where.add(
          confirmedMissingReplayGainSqlPredicate(
            hasReplayGainExpr: hasReplayGainExpr,
            replayGainKnownExpr: replayGainKnownExpr,
          ),
        );
        break;
    }
  }

  String _queueTrackOrderBy(String sortMode) {
    return _queueOrderBy(_queueTrackOrderTerms(sortMode));
  }

  String _queueAlbumOrderBy(String sortMode) {
    return _queueOrderBy(_queueAlbumOrderTerms(sortMode));
  }

  String _boundedQueuePart(
    String selectSql,
    QueueLibraryDbQuery request,
    List<Object?> args,
    List<_QueueOrderTerm> orderTerms, {
    required bool usesCursor,
  }) {
    final cursorPredicate = usesCursor
        ? _queueCursorPredicate(request.cursor, orderTerms, args)
        : '';
    final branchLimit = usesCursor
        ? request.limit
        : request.limit + request.offset;
    args.add(branchLimit);
    final branchOrder = orderTerms
        .where((term) => term.column != 'queue_source')
        .toList(growable: false);
    return '''
      SELECT * FROM (
        SELECT *
        FROM ($selectSql)
        ${cursorPredicate.isEmpty ? '' : 'WHERE $cursorPredicate'}
        ORDER BY ${_queueOrderBy(branchOrder)}
        LIMIT ?
      )
    ''';
  }

  List<_QueueOrderTerm> _queueTrackOrderTerms(String sortMode) {
    return switch (sortMode) {
      'oldest' => const [
        _QueueOrderTerm('sort_added'),
        _QueueOrderTerm('sort_track'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('id'),
      ],
      'a-z' => const [
        _QueueOrderTerm('sort_track'),
        _QueueOrderTerm('sort_artist'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('id'),
      ],
      'z-a' => const [
        _QueueOrderTerm('sort_track', descending: true),
        _QueueOrderTerm('sort_artist', descending: true),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('id'),
      ],
      'artist-asc' => const [
        _QueueOrderTerm('sort_artist'),
        _QueueOrderTerm('sort_track'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('id'),
      ],
      'artist-desc' => const [
        _QueueOrderTerm('sort_artist', descending: true),
        _QueueOrderTerm('sort_track'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('id'),
      ],
      'album-asc' => const [
        _QueueOrderTerm('sort_album'),
        _QueueOrderTerm('sort_track'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('id'),
      ],
      'album-desc' => const [
        _QueueOrderTerm('sort_album', descending: true),
        _QueueOrderTerm('sort_track'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('id'),
      ],
      'release-oldest' => const [
        _QueueOrderTerm('sort_release'),
        _QueueOrderTerm('sort_track'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('id'),
      ],
      'release-newest' => const [
        _QueueOrderTerm('sort_release', descending: true),
        _QueueOrderTerm('sort_track'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('id'),
      ],
      'genre-asc' => const [
        _QueueOrderTerm('sort_genre'),
        _QueueOrderTerm('sort_track'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('id'),
      ],
      'genre-desc' => const [
        _QueueOrderTerm('sort_genre', descending: true),
        _QueueOrderTerm('sort_track'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('id'),
      ],
      _ => const [
        _QueueOrderTerm('sort_added', descending: true),
        _QueueOrderTerm('sort_track'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('id'),
      ],
    };
  }

  List<_QueueOrderTerm> _queueAlbumOrderTerms(String sortMode) {
    return switch (sortMode) {
      'oldest' => const [
        _QueueOrderTerm('sort_added'),
        _QueueOrderTerm('sort_album'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('album_key'),
      ],
      'a-z' || 'album-asc' => const [
        _QueueOrderTerm('sort_album'),
        _QueueOrderTerm('sort_artist'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('album_key'),
      ],
      'z-a' || 'album-desc' => const [
        _QueueOrderTerm('sort_album', descending: true),
        _QueueOrderTerm('sort_artist', descending: true),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('album_key'),
      ],
      'artist-asc' => const [
        _QueueOrderTerm('sort_artist'),
        _QueueOrderTerm('sort_album'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('album_key'),
      ],
      'artist-desc' => const [
        _QueueOrderTerm('sort_artist', descending: true),
        _QueueOrderTerm('sort_album'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('album_key'),
      ],
      'release-oldest' => const [
        _QueueOrderTerm('sort_release'),
        _QueueOrderTerm('sort_album'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('album_key'),
      ],
      'release-newest' => const [
        _QueueOrderTerm('sort_release', descending: true),
        _QueueOrderTerm('sort_album'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('album_key'),
      ],
      'genre-asc' => const [
        _QueueOrderTerm('sort_genre'),
        _QueueOrderTerm('sort_album'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('album_key'),
      ],
      'genre-desc' => const [
        _QueueOrderTerm('sort_genre', descending: true),
        _QueueOrderTerm('sort_album'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('album_key'),
      ],
      _ => const [
        _QueueOrderTerm('sort_added', descending: true),
        _QueueOrderTerm('sort_album'),
        _QueueOrderTerm('queue_source'),
        _QueueOrderTerm('album_key'),
      ],
    };
  }

  String _queueOrderBy(List<_QueueOrderTerm> terms) => terms
      .map((term) => '${term.column} ${term.descending ? 'DESC' : 'ASC'}')
      .join(', ');

  String _queueCursorPredicate(
    QueueLibraryDbCursor? cursor,
    List<_QueueOrderTerm> terms,
    List<Object?> args,
  ) {
    if (cursor == null || cursor.values.length != terms.length) return '';
    final clauses = <String>[];
    final first = terms.first;
    final coarseOperator = first.descending ? '<=' : '>=';
    args.add(cursor.values.first);
    for (var i = 0; i < terms.length; i++) {
      final comparisons = <String>[];
      for (var j = 0; j < i; j++) {
        comparisons.add('${terms[j].column} = ?');
        args.add(cursor.values[j]);
      }
      comparisons.add(
        '${terms[i].column} ${terms[i].descending ? '<' : '>'} ?',
      );
      args.add(cursor.values[i]);
      clauses.add('(${comparisons.join(' AND ')})');
    }
    return '(${first.column} $coarseOperator ?) AND (${clauses.join(' OR ')})';
  }

  QueueLibraryDbCursor? _queueCursorFromRow(
    Map<String, dynamic>? row,
    List<_QueueOrderTerm> terms,
  ) {
    if (row == null) return null;
    final values = <Object>[];
    for (final term in terms) {
      final value = row[term.column];
      if (value is! Object) return null;
      values.add(value);
    }
    return QueueLibraryDbCursor(List<Object>.unmodifiable(values));
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
          'hasReplayGain':
              row['has_replaygain'] == 1 || row['has_replaygain'] == true,
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
        'hasReplayGain':
            row['has_replaygain'] == 1 || row['has_replaygain'] == true,
        'replayGainMetadataScanVersion':
            row['replaygain_metadata_scan_version'] ?? 0,
        'genre': row['genre'],
        'composer': row['composer'],
        'label': row['label'],
        'copyright': row['copyright'],
      },
    };
  }
}
