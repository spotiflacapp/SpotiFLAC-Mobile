class DownloadRequestPayload {
  static const int nativeWorkerContractVersion = 1;

  final int contractVersion;
  final String isrc;
  final String service;
  final String spotifyId;
  final String trackName;
  final String artistName;
  final String albumName;
  final String albumArtist;
  final String coverUrl;
  final String outputDir;
  final String filenameFormat;
  final String quality;
  final bool embedMetadata;
  final String artistTagMode;
  final bool embedLyrics;
  final bool embedMaxQualityCover;
  final bool embedReplayGain;
  final bool postProcessingEnabled;
  final String tidalHighFormat;
  final int trackNumber;
  final int playlistPosition;
  final int discNumber;
  final int totalTracks;
  final int totalDiscs;
  final String releaseDate;
  final String itemId;
  final int durationMs;
  final String source;
  final String genre;
  final String label;
  final String copyright;
  final String composer;
  final String tidalId;
  final String qobuzId;
  final String deezerId;
  final String lyricsMode;
  final bool useExtensions;
  final bool useFallback;
  final String storageMode;
  final String safTreeUri;
  final String safRelativeDir;
  final String safFileName;
  final String safOutputExt;
  final String outputExt;
  final bool stageSafOutput;
  final bool deferSafPublish;
  final bool requiresContainerConversion;
  final bool allowQualityVariant;
  final String qualityVariant;
  final bool qualityVariantCollisionOnly;
  final String songLinkRegion;

  const DownloadRequestPayload({
    this.contractVersion = nativeWorkerContractVersion,
    this.isrc = '',
    this.service = '',
    this.spotifyId = '',
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.albumArtist = '',
    this.coverUrl = '',
    required this.outputDir,
    required this.filenameFormat,
    this.quality = 'LOSSLESS',
    this.embedMetadata = true,
    this.artistTagMode = 'joined',
    this.embedLyrics = true,
    this.embedMaxQualityCover = true,
    this.embedReplayGain = false,
    this.postProcessingEnabled = false,
    this.tidalHighFormat = 'mp3_320',
    this.trackNumber = 0,
    this.playlistPosition = 0,
    this.discNumber = 0,
    this.totalTracks = 1,
    this.totalDiscs = 0,
    this.releaseDate = '',
    this.itemId = '',
    this.durationMs = 0,
    this.source = '',
    this.genre = '',
    this.label = '',
    this.copyright = '',
    this.composer = '',
    this.tidalId = '',
    this.qobuzId = '',
    this.deezerId = '',
    this.lyricsMode = 'embed',
    this.useExtensions = false,
    this.useFallback = false,
    this.storageMode = 'app',
    this.safTreeUri = '',
    this.safRelativeDir = '',
    this.safFileName = '',
    this.safOutputExt = '',
    this.outputExt = '',
    this.stageSafOutput = false,
    this.deferSafPublish = false,
    this.requiresContainerConversion = false,
    this.allowQualityVariant = false,
    this.qualityVariant = '',
    this.qualityVariantCollisionOnly = false,
    this.songLinkRegion = 'US',
  });

  Map<String, dynamic> toJson() {
    return {
      'contract_version': contractVersion,
      'isrc': isrc,
      'service': service,
      'spotify_id': spotifyId,
      'track_name': trackName,
      'artist_name': artistName,
      'album_name': albumName,
      'album_artist': albumArtist,
      'cover_url': coverUrl,
      'output_dir': outputDir,
      'filename_format': filenameFormat,
      'quality': quality,
      'embed_metadata': embedMetadata,
      'artist_tag_mode': artistTagMode,
      'embed_lyrics': embedLyrics,
      'embed_max_quality_cover': embedMaxQualityCover,
      'embed_replaygain': embedReplayGain,
      'post_processing_enabled': postProcessingEnabled,
      'tidal_high_format': tidalHighFormat,
      'track_number': trackNumber,
      'playlist_position': playlistPosition,
      'disc_number': discNumber,
      'total_tracks': totalTracks,
      'total_discs': totalDiscs,
      'release_date': releaseDate,
      'item_id': itemId,
      'duration_ms': durationMs,
      'source': source,
      'genre': genre,
      'label': label,
      'copyright': copyright,
      'composer': composer,
      'tidal_id': tidalId,
      'qobuz_id': qobuzId,
      'deezer_id': deezerId,
      'lyrics_mode': lyricsMode,
      'use_extensions': useExtensions,
      'use_fallback': useFallback,
      'storage_mode': storageMode,
      'saf_tree_uri': safTreeUri,
      'saf_relative_dir': safRelativeDir,
      'saf_file_name': safFileName,
      'saf_output_ext': safOutputExt,
      'output_ext': outputExt,
      'stage_saf_output': stageSafOutput,
      'defer_saf_publish': deferSafPublish,
      'requires_container_conversion': requiresContainerConversion,
      'allow_quality_variant': allowQualityVariant,
      'quality_variant': qualityVariant,
      'quality_variant_collision_only': qualityVariantCollisionOnly,
      'songlink_region': songLinkRegion,
    };
  }

  DownloadRequestPayload withStrategy({
    bool? useExtensions,
    bool? useFallback,
  }) {
    return DownloadRequestPayload(
      contractVersion: contractVersion,
      isrc: isrc,
      service: service,
      spotifyId: spotifyId,
      trackName: trackName,
      artistName: artistName,
      albumName: albumName,
      albumArtist: albumArtist,
      coverUrl: coverUrl,
      outputDir: outputDir,
      filenameFormat: filenameFormat,
      quality: quality,
      embedMetadata: embedMetadata,
      artistTagMode: artistTagMode,
      embedLyrics: embedLyrics,
      embedMaxQualityCover: embedMaxQualityCover,
      embedReplayGain: embedReplayGain,
      postProcessingEnabled: postProcessingEnabled,
      tidalHighFormat: tidalHighFormat,
      trackNumber: trackNumber,
      playlistPosition: playlistPosition,
      discNumber: discNumber,
      totalTracks: totalTracks,
      totalDiscs: totalDiscs,
      releaseDate: releaseDate,
      itemId: itemId,
      durationMs: durationMs,
      source: source,
      genre: genre,
      label: label,
      copyright: copyright,
      composer: composer,
      tidalId: tidalId,
      qobuzId: qobuzId,
      deezerId: deezerId,
      lyricsMode: lyricsMode,
      useExtensions: useExtensions ?? this.useExtensions,
      useFallback: useFallback ?? this.useFallback,
      storageMode: storageMode,
      safTreeUri: safTreeUri,
      safRelativeDir: safRelativeDir,
      safFileName: safFileName,
      safOutputExt: safOutputExt,
      outputExt: outputExt,
      stageSafOutput: stageSafOutput,
      deferSafPublish: deferSafPublish,
      requiresContainerConversion: requiresContainerConversion,
      allowQualityVariant: allowQualityVariant,
      qualityVariant: qualityVariant,
      qualityVariantCollisionOnly: qualityVariantCollisionOnly,
      songLinkRegion: songLinkRegion,
    );
  }
}
