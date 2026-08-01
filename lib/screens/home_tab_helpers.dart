part of 'home_tab.dart';

class _RecentAccessView {
  final List<RecentAccessItem> uniqueItems;
  final List<String> downloadIds;
  final Map<String, String> downloadFilePathByRecentKey;
  final bool hasHiddenDownloads;

  const _RecentAccessView({
    required this.uniqueItems,
    required this.downloadIds,
    required this.downloadFilePathByRecentKey,
    required this.hasHiddenDownloads,
  });
}

class _RecentAlbumAggregate {
  int count;
  DownloadHistoryItem mostRecent;

  _RecentAlbumAggregate({required this.count, required this.mostRecent});
}

class _CsvImportOptions {
  final bool confirmed;
  final bool skipDownloaded;

  const _CsvImportOptions({
    required this.confirmed,
    required this.skipDownloaded,
  });
}

const _homeHistoryPreviewLimit = 48;

class _HomeHistoryPreview {
  final List<DownloadHistoryItem> items;

  const _HomeHistoryPreview(this.items);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _HomeHistoryPreview && listEquals(items, other.items);

  @override
  int get hashCode => Object.hashAll(items);
}

final _homeHistoryPreviewProvider = Provider<List<DownloadHistoryItem>>((ref) {
  final preview = ref.watch(
    downloadHistoryProvider.select((s) {
      final items = s.items;
      if (items.length <= _homeHistoryPreviewLimit) {
        return _HomeHistoryPreview(items);
      }
      return _HomeHistoryPreview(
        items.take(_homeHistoryPreviewLimit).toList(growable: false),
      );
    }),
  );
  return preview.items;
});

_RecentAccessView _buildRecentAccessViewData(
  List<RecentAccessItem> items,
  List<DownloadHistoryItem> historyItems,
  Set<String> hiddenIds,
) {
  final albumGroups = <String, _RecentAlbumAggregate>{};
  for (final h in historyItems) {
    final artistForKey = (h.albumArtist != null && h.albumArtist!.isNotEmpty)
        ? h.albumArtist!
        : h.artistName;
    final albumKey = '${h.albumName}|$artistForKey';
    final existing = albumGroups[albumKey];
    if (existing == null) {
      albumGroups[albumKey] = _RecentAlbumAggregate(count: 1, mostRecent: h);
    } else {
      existing.count++;
      if (h.downloadedAt.isAfter(existing.mostRecent.downloadedAt)) {
        existing.mostRecent = h;
      }
    }
  }

  final downloadIds = <String>[];
  final visibleDownloads = <RecentAccessItem>[];
  final downloadFilePathByRecentKey = <String, String>{};
  for (final aggregate in albumGroups.values) {
    final mostRecent = aggregate.mostRecent;
    final artistForKey =
        (mostRecent.albumArtist != null && mostRecent.albumArtist!.isNotEmpty)
        ? mostRecent.albumArtist!
        : mostRecent.artistName;

    final isSingleTrack = aggregate.count == 1;
    final recentId = isSingleTrack
        ? (mostRecent.spotifyId ?? mostRecent.id)
        : '${mostRecent.albumName}|$artistForKey';
    final recent = RecentAccessItem(
      id: recentId,
      name: isSingleTrack ? mostRecent.trackName : mostRecent.albumName,
      subtitle: isSingleTrack ? mostRecent.artistName : artistForKey,
      imageUrl: mostRecent.coverUrl,
      type: isSingleTrack ? RecentAccessType.track : RecentAccessType.album,
      accessedAt: mostRecent.downloadedAt,
      providerId: 'download',
    );

    downloadIds.add(recentId);
    downloadFilePathByRecentKey['${recent.type.name}:${recent.id}'] =
        mostRecent.filePath;
    if (!hiddenIds.contains(recentId)) {
      visibleDownloads.add(recent);
    }
  }

  visibleDownloads.sort((a, b) => b.accessedAt.compareTo(a.accessedAt));
  if (visibleDownloads.length > 10) {
    visibleDownloads.removeRange(10, visibleDownloads.length);
  }

  final allItems = <RecentAccessItem>[...items, ...visibleDownloads];
  allItems.sort((a, b) => b.accessedAt.compareTo(a.accessedAt));

  final seen = <String>{};
  final uniqueItems = <RecentAccessItem>[];
  for (final item in allItems) {
    final key = '${item.type.name}:${item.id}';
    if (seen.add(key)) {
      uniqueItems.add(item);
      if (uniqueItems.length >= 10) {
        break;
      }
    }
  }

  return _RecentAccessView(
    uniqueItems: uniqueItems,
    downloadIds: downloadIds,
    downloadFilePathByRecentKey: downloadFilePathByRecentKey,
    hasHiddenDownloads: hiddenIds.isNotEmpty,
  );
}

final recentAccessViewProvider = Provider<_RecentAccessView>((ref) {
  final historyItems = ref.watch(_homeHistoryPreviewProvider);
  final recentAccessItems = ref.watch(
    recentAccessProvider.select((s) => s.items),
  );
  final hiddenDownloadIds = ref.watch(
    recentAccessProvider.select((s) => s.hiddenDownloadIds),
  );
  return _buildRecentAccessViewData(
    recentAccessItems,
    historyItems,
    hiddenDownloadIds,
  );
});
