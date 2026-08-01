import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_history_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/utils/audio_quality_badge_policy.dart';
import 'package:spotiflac_android/utils/string_utils.dart';

enum LibraryItemSource { downloaded, local }

/// A library track backed by either a download-history record or a
/// local-library scan record, unified for shared list and batch handling.
class UnifiedLibraryItem {
  final String id;
  final String trackName;
  final String artistName;
  final String albumName;
  final String? coverUrl;
  final String? localCoverPath;
  final String filePath;
  final String? quality;
  final DateTime addedAt;
  final LibraryItemSource source;

  final DownloadHistoryItem? historyItem;
  final LocalLibraryItem? localItem;

  UnifiedLibraryItem({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.coverUrl,
    this.localCoverPath,
    required this.filePath,
    this.quality,
    required this.addedAt,
    required this.source,
    this.historyItem,
    this.localItem,
  });

  factory UnifiedLibraryItem.fromDownloadHistory(DownloadHistoryItem item) {
    String? quality;
    if (item.bitrate != null && item.bitrate! > 0) {
      quality = buildDisplayAudioQuality(
        bitrateKbps: item.bitrate,
        format: item.format,
      );
    } else if (item.bitDepth != null &&
        item.bitDepth! > 0 &&
        item.sampleRate != null) {
      quality = buildDisplayAudioQuality(
        bitDepth: item.bitDepth,
        sampleRate: item.sampleRate,
      );
    }
    quality ??= item.quality;
    return UnifiedLibraryItem(
      id: 'dl_${item.id}',
      trackName: item.trackName,
      artistName: item.artistName,
      albumName: item.albumName,
      coverUrl: item.coverUrl,
      filePath: item.filePath,
      quality: quality,
      addedAt: item.downloadedAt,
      source: LibraryItemSource.downloaded,
      historyItem: item,
    );
  }

  factory UnifiedLibraryItem.fromLocalLibrary(LocalLibraryItem item) {
    String? quality;
    if (item.bitrate != null && item.bitrate! > 0) {
      quality = buildDisplayAudioQuality(
        bitrateKbps: item.bitrate,
        format: item.format,
      );
    } else if (item.bitDepth != null &&
        item.bitDepth! > 0 &&
        item.sampleRate != null) {
      quality = buildDisplayAudioQuality(
        bitDepth: item.bitDepth,
        sampleRate: item.sampleRate,
      );
    }
    return UnifiedLibraryItem(
      id: 'local_${item.id}',
      trackName: item.trackName,
      artistName: item.artistName,
      albumName: item.albumName,
      coverUrl: null,
      localCoverPath: item.coverPath,
      filePath: item.filePath,
      quality: quality,
      addedAt: item.fileModTime != null
          ? DateTime.fromMillisecondsSinceEpoch(item.fileModTime!)
          : item.scannedAt,
      source: LibraryItemSource.local,
      localItem: item,
    );
  }

  bool get hasCover =>
      coverUrl != null ||
      (localCoverPath != null && localCoverPath!.isNotEmpty);

  String? qualityForMode(String mode) {
    final history = historyItem;
    if (history != null) {
      return buildLibraryAudioQualityLabel(
        mode: mode,
        format: history.format,
        bitrateKbps: history.bitrate,
        bitDepth: history.bitDepth,
        sampleRate: history.sampleRate,
        storedQuality: history.quality ?? quality,
      );
    }

    final local = localItem;
    if (local != null) {
      return buildLibraryAudioQualityLabel(
        mode: mode,
        format: local.format,
        bitrateKbps: local.bitrate,
        bitDepth: local.bitDepth,
        sampleRate: local.sampleRate,
        storedQuality: quality,
      );
    }

    return quality;
  }

  String? get albumArtist => historyItem?.albumArtist ?? localItem?.albumArtist;

  String? get releaseDate => historyItem?.releaseDate ?? localItem?.releaseDate;

  String? get genre => historyItem?.genre ?? localItem?.genre;

  int? get trackNumber => historyItem?.trackNumber ?? localItem?.trackNumber;

  int? get discNumber => historyItem?.discNumber ?? localItem?.discNumber;

  String? get isrc => historyItem?.isrc ?? localItem?.isrc;

  String? get label => historyItem?.label ?? localItem?.label;

  String get searchKey =>
      '${trackName.toLowerCase()}|${artistName.toLowerCase()}|${albumName.toLowerCase()}';
  String get albumKey =>
      '${albumName.toLowerCase()}|${artistName.toLowerCase()}';

  /// Returns the collection key used to match this item against playlist
  /// entries. Uses the same logic as [trackCollectionKey] from the collections
  /// provider: prefer ISRC, fall back to source:id.
  String get collectionKey {
    if (historyItem != null) {
      final isrc = historyItem!.isrc?.trim();
      if (isrc != null && isrc.isNotEmpty) return 'isrc:${isrc.toUpperCase()}';
      final source = historyItem!.service.trim().isNotEmpty
          ? historyItem!.service.trim()
          : 'builtin';
      return '$source:${historyItem!.id}';
    }
    if (localItem != null) {
      final isrc = localItem!.isrc?.trim();
      if (isrc != null && isrc.isNotEmpty) return 'isrc:${isrc.toUpperCase()}';
      return 'local:${localItem!.id}';
    }
    return 'builtin:$id';
  }

  Track toTrack() {
    if (historyItem != null) {
      final h = historyItem!;
      return Track(
        id: h.id,
        name: h.trackName,
        artistName: h.artistName,
        albumName: h.albumName,
        albumArtist: h.albumArtist,
        coverUrl: h.coverUrl,
        isrc: h.isrc,
        duration: h.duration ?? 0,
        trackNumber: h.trackNumber,
        discNumber: h.discNumber,
        releaseDate: h.releaseDate,
        source: h.service,
      );
    }
    if (localItem != null) {
      final l = localItem!;
      return Track(
        id: l.id,
        name: l.trackName,
        artistName: l.artistName,
        albumName: l.albumName,
        albumArtist: l.albumArtist,
        coverUrl: l.coverPath,
        isrc: l.isrc,
        duration: l.duration ?? 0,
        trackNumber: l.trackNumber,
        discNumber: l.discNumber,
        releaseDate: l.releaseDate,
        source: 'local',
      );
    }
    return Track(
      id: id,
      name: trackName,
      artistName: artistName,
      albumName: albumName,
      coverUrl: coverUrl,
      duration: 0,
    );
  }
}
