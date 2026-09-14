import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/utils/extension_auth_launcher.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';

final _log = AppLogger('TrackProvider');
const _extensionInitRetryTimeout = Duration(seconds: 30);

class TrackState {
  final List<Track> tracks;
  final bool isLoading;
  final String? error;
  final String? albumId;
  final String? albumName;
  final String? playlistName;
  final String? playlistId;
  final String? artistId;
  final String? artistName;
  final String? coverUrl;
  final String? headerImageUrl;
  final String? headerVideoUrl;
  final int? monthlyListeners;
  final List<ArtistAlbum>? artistAlbums;
  final List<Track>? artistTopTracks;
  final bool hasSearchText;
  final bool isShowingRecentAccess;
  final String? searchExtensionId;
  final String? selectedSearchFilter;
  final String? searchSource;

  const TrackState({
    this.tracks = const [],
    this.isLoading = false,
    this.error,
    this.albumId,
    this.albumName,
    this.playlistName,
    this.playlistId,
    this.artistId,
    this.artistName,
    this.coverUrl,
    this.headerImageUrl,
    this.headerVideoUrl,
    this.monthlyListeners,
    this.artistAlbums,
    this.artistTopTracks,
    this.hasSearchText = false,
    this.isShowingRecentAccess = false,
    this.searchExtensionId,
    this.selectedSearchFilter,
    this.searchSource,
  });

  bool get hasContent => tracks.isNotEmpty || artistAlbums != null;

  TrackState copyWith({
    List<Track>? tracks,
    bool? isLoading,
    String? error,
    String? albumId,
    String? albumName,
    String? playlistName,
    String? playlistId,
    String? artistId,
    String? artistName,
    String? coverUrl,
    String? headerImageUrl,
    String? headerVideoUrl,
    int? monthlyListeners,
    List<ArtistAlbum>? artistAlbums,
    List<Track>? artistTopTracks,
    bool? hasSearchText,
    bool? isShowingRecentAccess,
    String? searchExtensionId,
    String? selectedSearchFilter,
    bool clearSelectedSearchFilter = false,
    String? searchSource,
    bool clearSearchSource = false,
  }) {
    return TrackState(
      tracks: tracks ?? this.tracks,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      albumId: albumId ?? this.albumId,
      albumName: albumName ?? this.albumName,
      playlistName: playlistName ?? this.playlistName,
      playlistId: playlistId ?? this.playlistId,
      artistId: artistId ?? this.artistId,
      artistName: artistName ?? this.artistName,
      coverUrl: coverUrl ?? this.coverUrl,
      headerImageUrl: headerImageUrl ?? this.headerImageUrl,
      headerVideoUrl: headerVideoUrl ?? this.headerVideoUrl,
      monthlyListeners: monthlyListeners ?? this.monthlyListeners,
      artistAlbums: artistAlbums ?? this.artistAlbums,
      artistTopTracks: artistTopTracks ?? this.artistTopTracks,
      hasSearchText: hasSearchText ?? this.hasSearchText,
      isShowingRecentAccess:
          isShowingRecentAccess ?? this.isShowingRecentAccess,
      searchExtensionId: searchExtensionId,
      selectedSearchFilter: clearSelectedSearchFilter
          ? null
          : (selectedSearchFilter ?? this.selectedSearchFilter),
      searchSource: clearSearchSource
          ? null
          : (searchSource ?? this.searchSource),
    );
  }
}

class ArtistAlbum {
  final String id;
  final String name;
  final String releaseDate;
  final int totalTracks;
  final String? coverUrl;
  final String albumType;
  final String artists;
  final String? providerId;

  const ArtistAlbum({
    required this.id,
    required this.name,
    required this.releaseDate,
    required this.totalTracks,
    this.coverUrl,
    required this.albumType,
    required this.artists,
    this.providerId,
  });
}

class TrackNotifier extends Notifier<TrackState> {
  int _currentRequestId = 0;
  static const _verificationRequestCooldown = Duration(seconds: 15);
  final Map<String, DateTime> _lastVerificationRequests = {};
  final Map<String, Future<bool>> _verificationRequests = {};

  @override
  TrackState build() {
    return const TrackState();
  }

  bool _isRequestValid(int requestId) => requestId == _currentRequestId;

  void cancelSearch() {
    _currentRequestId++;
    PlatformBridge.cancelExtensionSearchRequests();
    state = TrackState(
      hasSearchText: state.hasSearchText,
      isShowingRecentAccess: state.isShowingRecentAccess,
      selectedSearchFilter: state.selectedSearchFilter,
    );
  }

  Future<void> fetchFromUrl(String url, {bool useDeezerFallback = true}) async {
    final requestId = ++_currentRequestId;

    state = TrackState(isLoading: true, hasSearchText: state.hasSearchText);

    try {
      var extensionHandler = await PlatformBridge.findURLHandler(url);
      if (extensionHandler == null) {
        final extensionState = ref.read(extensionProvider);
        if (!extensionState.isInitialized && extensionState.isLoading) {
          _log.i(
            'Extension URL handlers not ready yet, waiting for initialization...',
          );
          await ref
              .read(extensionProvider.notifier)
              .waitForInitialization(timeout: _extensionInitRetryTimeout);
          if (!_isRequestValid(requestId)) return;
          extensionHandler = await PlatformBridge.findURLHandler(url);
        }
      }

      if (extensionHandler == null) {
        state = TrackState(
          isLoading: false,
          error: 'url_not_recognized',
          hasSearchText: state.hasSearchText,
        );
        return;
      }

      _log.i('Found extension URL handler: $extensionHandler');

      Map<String, dynamic>? result;
      for (int attempt = 1; attempt <= 3; attempt++) {
        result = await PlatformBridge.handleURLWithExtension(url);
        if (!_isRequestValid(requestId)) return;

        if (result != null &&
            result['type'] == 'track' &&
            result['track'] != null) {
          final trackData = result['track'] as Map<String, dynamic>;
          final name = trackData['name']?.toString() ?? '';
          if (name.isNotEmpty) {
            break;
          }
        } else if (result != null &&
            (result['type'] == 'album' || result['type'] == 'playlist')) {
          break;
        } else if (result != null && result['type'] == 'artist') {
          break;
        }

        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      if (result != null) {
        final type = result['type'] as String?;
        final extensionId = result['extension_id'] as String?;

        if (type == 'track' && result['track'] != null) {
          final trackData = result['track'] as Map<String, dynamic>;
          final track = Track.fromBackendMap(trackData, source: extensionId);

          if (track.name.isEmpty) {
            state = TrackState(
              isLoading: false,
              error: 'Failed to load track metadata from extension',
            );
            return;
          }

          state = TrackState(
            tracks: [track],
            isLoading: false,
            coverUrl: track.coverUrl,
            searchExtensionId: extensionId,
          );
          return;
        } else if ((type == 'album' || type == 'playlist') &&
            result['tracks'] != null) {
          final trackList = result['tracks'] as List<dynamic>;
          final collectionName = result['name'] as String?;
          final tracks = trackList
              .map(
                (t) => Track.fromBackendMap(
                  t as Map<String, dynamic>,
                  source: extensionId,
                  playlistName: type == 'playlist' ? collectionName : null,
                ),
              )
              .toList();
          state = TrackState(
            tracks: tracks,
            isLoading: false,
            albumId:
                (result['album'] as Map<String, dynamic>?)?['id'] as String?,
            albumName:
                collectionName ??
                (result['album'] as Map<String, dynamic>?)?['name'] as String?,
            playlistName: type == 'playlist' ? collectionName : null,
            playlistId: type == 'playlist' ? result['id'] as String? : null,
            coverUrl: normalizeCoverReference(result['cover_url']?.toString()),
            headerVideoUrl: normalizeRemoteHttpUrl(
              result['header_video']?.toString(),
            ),
            searchExtensionId: extensionId,
          );
          return;
        } else if (type == 'artist' && result['artist'] != null) {
          final artistData = result['artist'] as Map<String, dynamic>;
          final albumsList = artistData['albums'] as List<dynamic>? ?? [];
          final albums = albumsList
              .map((a) => _parseArtistAlbum(a as Map<String, dynamic>))
              .toList();

          final topTracksList =
              artistData['top_tracks'] as List<dynamic>? ?? [];
          final topTracks = topTracksList
              .map(
                (t) => Track.fromBackendMap(
                  t as Map<String, dynamic>,
                  source: extensionId,
                ),
              )
              .toList();

          state = TrackState(
            tracks: [],
            isLoading: false,
            artistId: artistData['id'] as String?,
            artistName: artistData['name'] as String?,
            coverUrl: normalizeRemoteHttpUrl(
              (artistData['image_url'] ?? artistData['images'])?.toString(),
            ),
            headerImageUrl: normalizeRemoteHttpUrl(
              artistData['header_image']?.toString(),
            ),
            headerVideoUrl: normalizeRemoteHttpUrl(
              artistData['header_video']?.toString(),
            ),
            monthlyListeners: artistData['listeners'] as int?,
            artistAlbums: albums,
            artistTopTracks: topTracks.isNotEmpty ? topTracks : null,
            searchExtensionId: extensionId,
          );
          return;
        }
      }

      state = TrackState(
        isLoading: false,
        error: 'url_not_recognized',
        hasSearchText: state.hasSearchText,
      );
    } catch (e) {
      if (!_isRequestValid(requestId)) return;
      state = TrackState(
        isLoading: false,
        error: e.toString(),
        hasSearchText: state.hasSearchText,
      );
    }
  }

  Future<void> search(String query, {String? filterOverride}) async {
    final requestId = ++_currentRequestId;
    final currentFilter = filterOverride ?? state.selectedSearchFilter;
    final requestFilter = currentFilter == 'all' ? null : currentFilter;
    final settings = ref.read(settingsProvider);
    final extensionState = ref.read(extensionProvider);

    String? resolvedProvider;
    final explicitProvider = settings.searchProvider?.trim();
    if (explicitProvider != null && explicitProvider.isNotEmpty) {
      resolvedProvider = explicitProvider;
    } else {
      resolvedProvider = defaultSearchExtension(extensionState.extensions)?.id;
    }

    if (resolvedProvider != null &&
        resolvedProvider.isNotEmpty &&
        !extensionState.extensions.any(
          (ext) => ext.enabled && ext.id == resolvedProvider,
        ) &&
        settings.searchProvider?.trim() == resolvedProvider) {
      ref.read(settingsProvider.notifier).setSearchProvider(null);
      resolvedProvider = defaultSearchExtension(extensionState.extensions)?.id;
    }

    final isEnabledExtensionProvider =
        resolvedProvider != null &&
        resolvedProvider.isNotEmpty &&
        extensionState.extensions.any(
          (ext) => ext.enabled && ext.id == resolvedProvider,
        );

    if (resolvedProvider != null &&
        resolvedProvider.isNotEmpty &&
        isEnabledExtensionProvider) {
      final resolvedFilter = requestFilter ?? 'track';
      Map<String, dynamic>? options;
      options = {'filter': resolvedFilter};
      await customSearch(
        resolvedProvider,
        query,
        options: options,
        selectedFilter: resolvedFilter,
      );
      return;
    }

    state = TrackState(
      isLoading: true,
      hasSearchText: state.hasSearchText,
      isShowingRecentAccess: state.isShowingRecentAccess,
      selectedSearchFilter: currentFilter,
    );

    try {
      final includeExtensions = settings.useExtensionProviders;

      final metadataTrackResults =
          await PlatformBridge.searchTracksWithMetadataProviders(
            query,
            limit: 20,
            includeExtensions: includeExtensions,
          );
      if (!_isRequestValid(requestId)) {
        _log.w('Search request cancelled (requestId=$requestId)');
        return;
      }

      final tracks = <Track>[];
      for (int i = 0; i < metadataTrackResults.length; i++) {
        final t = metadataTrackResults[i];
        try {
          tracks.add(Track.fromBackendMap(t));
        } catch (e) {
          _log.e('Failed to parse track[$i]: $e', e);
        }
      }

      _log.i(
        'Search completed: provider=metadata_extensions, '
        'tracks=${tracks.length}, extensions=$includeExtensions, '
        'filter=$requestFilter',
      );

      state = TrackState(
        tracks: tracks,
        isLoading: false,
        hasSearchText: state.hasSearchText,
        isShowingRecentAccess: state.isShowingRecentAccess,
        selectedSearchFilter: currentFilter,
        searchSource: resolvedProvider,
      );
    } catch (e, stackTrace) {
      if (!_isRequestValid(requestId)) return;
      _log.e('Search failed: $e', e, stackTrace);
      state = TrackState(
        isLoading: false,
        error: e.toString(),
        hasSearchText: state.hasSearchText,
        isShowingRecentAccess: state.isShowingRecentAccess,
        selectedSearchFilter: currentFilter,
      );
    }
  }

  Future<void> customSearch(
    String extensionId,
    String query, {
    Map<String, dynamic>? options,
    String? selectedFilter,
    bool allowVerificationRetry = true,
    Future<void>? cancellationSignal,
    void Function()? onVerificationDeferred,
  }) async {
    final requestId = ++_currentRequestId;
    final currentFilter = selectedFilter ?? state.selectedSearchFilter;

    state = TrackState(
      isLoading: true,
      hasSearchText: state.hasSearchText,
      isShowingRecentAccess: state.isShowingRecentAccess,
      selectedSearchFilter: currentFilter,
    );

    try {
      final results = await PlatformBridge.customSearchWithExtension(
        extensionId,
        query,
        options: options,
        cancelPrevious: true,
      );

      if (!_isRequestValid(requestId)) {
        _log.w('Custom search request cancelled (requestId=$requestId)');
        return;
      }

      final tracks = <Track>[];
      for (int i = 0; i < results.length; i++) {
        final t = results[i];
        try {
          tracks.add(Track.fromBackendMap(t, source: extensionId));
        } catch (e) {
          _log.e('Failed to parse custom search track[$i]: $e', e);
        }
      }

      _log.i(
        'Custom search completed: extension=$extensionId, '
        'tracks=${tracks.length}',
      );

      state = TrackState(
        tracks: tracks,
        isLoading: false,
        hasSearchText: state.hasSearchText,
        isShowingRecentAccess: state.isShowingRecentAccess,
        searchExtensionId: extensionId,
        selectedSearchFilter: currentFilter,
      );
    } catch (e, stackTrace) {
      if (!_isRequestValid(requestId)) return;
      _log.e('Custom search failed: $e', e, stackTrace);
      if (isExtensionVerificationRequired(e)) {
        onVerificationDeferred?.call();
      }
      if (allowVerificationRetry && isExtensionVerificationRequired(e)) {
        _log.i(
          'Custom search requires verification; waiting for $extensionId grant',
        );
        state = TrackState(
          isLoading: true,
          hasSearchText: state.hasSearchText,
          isShowingRecentAccess: state.isShowingRecentAccess,
          searchExtensionId: extensionId,
          selectedSearchFilter: currentFilter,
        );
        final verified = await openVerificationAndAwaitGrant(
          extensionId,
          browserMode: ref
              .read(settingsProvider)
              .extensionVerificationBrowserMode,
          cancellationSignal: cancellationSignal,
        );
        if (!_isRequestValid(requestId)) return;
        if (!verified) {
          onVerificationDeferred?.call();
          state = TrackState(
            isLoading: false,
            error: cancellationSignal == null ? e.toString() : null,
            hasSearchText: state.hasSearchText,
            isShowingRecentAccess: state.isShowingRecentAccess,
            searchExtensionId: extensionId,
            selectedSearchFilter: currentFilter,
          );
          return;
        }

        _log.i(
          'Verification complete for $extensionId; retrying custom search',
        );
        await customSearch(
          extensionId,
          query,
          options: options,
          selectedFilter: currentFilter,
          allowVerificationRetry: false,
          cancellationSignal: cancellationSignal,
          onVerificationDeferred: onVerificationDeferred,
        );
        return;
      }
      state = TrackState(
        isLoading: false,
        error: e.toString(),
        hasSearchText: state.hasSearchText,
        isShowingRecentAccess: state.isShowingRecentAccess,
        selectedSearchFilter: currentFilter,
      );
    }
  }

  Future<bool> requestSearchVerification(
    String extensionId, {
    required String browserMode,
    Future<void>? cancellationSignal,
  }) async {
    final normalizedExtensionId = extensionId.trim();
    if (normalizedExtensionId.isEmpty) return Future.value(false);
    final key = normalizedExtensionId.toLowerCase();
    final activeRequest = _verificationRequests[key];
    if (activeRequest != null) return activeRequest;

    final now = DateTime.now();
    final lastRequest = _lastVerificationRequests[key];
    if (lastRequest != null &&
        now.difference(lastRequest) < _verificationRequestCooldown) {
      return false;
    }

    await PlatformBridge.clearExtensionPendingAuth(normalizedExtensionId);

    late final Future<bool> request;
    request = openVerificationAndAwaitGrant(
      normalizedExtensionId,
      browserMode: browserMode,
      cancellationSignal: cancellationSignal,
    ).whenComplete(() {
      if (identical(_verificationRequests[key], request)) {
        _verificationRequests.remove(key);
      }
    });
    _lastVerificationRequests[key] = now;
    _verificationRequests[key] = request;
    return request;
  }

  void clear() {
    state = const TrackState();
  }

  void setSearchFilter(String? filter) {
    if (state.selectedSearchFilter == filter) return;
    state = state.copyWith(
      selectedSearchFilter: filter,
      clearSelectedSearchFilter: filter == null,
    );
  }

  void setSearchText(bool hasText) {
    if (state.hasSearchText == hasText) {
      return;
    }
    state = state.copyWith(hasSearchText: hasText);
  }

  void setShowingRecentAccess(bool showing) {
    if (state.isShowingRecentAccess == showing) {
      return;
    }
    state = state.copyWith(isShowingRecentAccess: showing);
  }

  void setTracksFromCollection({
    required List<Track> tracks,
    String? albumName,
    String? playlistName,
    String? coverUrl,
  }) {
    state = TrackState(
      tracks: tracks,
      isLoading: false,
      albumName: albumName,
      playlistName: playlistName,
      coverUrl: coverUrl,
      hasSearchText: state.hasSearchText,
      isShowingRecentAccess: state.isShowingRecentAccess,
    );
  }

  ArtistAlbum _parseArtistAlbum(Map<String, dynamic> data) {
    return ArtistAlbum(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      releaseDate: data['release_date'] as String? ?? '',
      totalTracks: data['total_tracks'] as int? ?? 0,
      coverUrl: normalizeCoverReference(
        (data['cover_url'] ?? data['images'])?.toString(),
      ),
      albumType: data['album_type'] as String? ?? 'album',
      artists: data['artists'] as String? ?? '',
      providerId: data['provider_id']?.toString(),
    );
  }
}

final trackProvider = NotifierProvider<TrackNotifier, TrackState>(
  TrackNotifier.new,
);
