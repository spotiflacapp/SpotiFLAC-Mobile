part of 'library_database.dart';

// Row models and query descriptors for the local library database.

int libraryIncrementalSnapshotModTime({
  required int storedModTime,
  required int storedScanVersion,
}) {
  return storedScanVersion >= LibraryDatabase.audioMetadataScanVersion
      ? storedModTime
      : -1;
}

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
  final int? bitrate; // average kbps for both lossless and lossy audio
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

  LocalLibraryItem withAudioMetadata({
    int? duration,
    int? bitDepth,
    int? sampleRate,
    int? bitrate,
    String? format,
  }) {
    return LocalLibraryItem(
      id: id,
      trackName: trackName,
      artistName: artistName,
      albumName: albumName,
      albumArtist: albumArtist,
      filePath: filePath,
      coverPath: coverPath,
      scannedAt: scannedAt,
      fileModTime: fileModTime,
      isrc: isrc,
      trackNumber: trackNumber,
      totalTracks: totalTracks,
      discNumber: discNumber,
      totalDiscs: totalDiscs,
      duration: duration ?? this.duration,
      releaseDate: releaseDate,
      bitDepth: bitDepth ?? this.bitDepth,
      sampleRate: sampleRate ?? this.sampleRate,
      bitrate: bitrate ?? this.bitrate,
      genre: genre,
      composer: composer,
      label: label,
      copyright: copyright,
      format: format ?? this.format,
    );
  }

  String get matchKey =>
      '${LibraryDatabase.normalizeLookupText(trackName)}|${LibraryDatabase.normalizeLookupText(artistName)}';
  String get albumKey =>
      '${LibraryDatabase.normalizeLookupText(albumName)}|${LibraryDatabase.normalizeLookupText(albumArtist ?? artistName)}';
}

enum LocalLibrarySortMode { album, title, artist, latest, quality }

enum LocalLibraryFilterMode { all, albums, singles }

class LocalLibraryLookupIndex {
  final Set<String> isrcs;
  final Set<String> matchKeys;

  const LocalLibraryLookupIndex({
    this.isrcs = const <String>{},
    this.matchKeys = const <String>{},
  });
}

class LocalLibraryBatchLookupRequest {
  final String? id;
  final String? isrc;
  final String trackName;
  final String artistName;

  const LocalLibraryBatchLookupRequest({
    this.id,
    this.isrc,
    required this.trackName,
    required this.artistName,
  });
}

class IsrcDuplicateEntry {
  final String id;
  final String source; // 'downloaded' (history row) or 'local' (library row)
  final String trackName;
  final String artistName;
  final String albumName;
  final String filePath;
  final int? bitDepth;
  final int? sampleRate;
  final int? bitrate;
  final String? format;

  const IsrcDuplicateEntry({
    required this.id,
    required this.source,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.filePath,
    this.bitDepth,
    this.sampleRate,
    this.bitrate,
    this.format,
  });
}

class IsrcDuplicateGroup {
  final String isrc;
  final List<IsrcDuplicateEntry> entries;

  const IsrcDuplicateGroup({required this.isrc, required this.entries});
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
