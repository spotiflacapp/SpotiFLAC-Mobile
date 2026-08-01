package gobackend

import (
	"path/filepath"
	"testing"
)

func TestExtensionProviderWrapperFullSurface(t *testing.T) {
	ext := newTestLoadedExtension(t, ExtensionTypeMetadataProvider, ExtensionTypeDownloadProvider, ExtensionTypeLyricsProvider)
	provider := newExtensionProviderWrapper(ext)

	search, err := provider.SearchTracks("query", 5)
	if err != nil {
		t.Fatalf("SearchTracks: %v", err)
	}
	if search.Total != 1 || search.Tracks[0].ProviderID != ext.ID || search.Tracks[0].ExternalLinks["tidal"] == "" {
		t.Fatalf("search = %#v", search)
	}

	track, err := provider.GetTrack("track-1")
	if err != nil {
		t.Fatalf("GetTrack: %v", err)
	}
	if track.Name != "Track track-1" || track.ProviderID != ext.ID || track.AudioQuality == "" {
		t.Fatalf("track = %#v", track)
	}

	album, err := provider.GetAlbum("album-1")
	if err != nil {
		t.Fatalf("GetAlbum: %v", err)
	}
	if album.ProviderID != ext.ID || len(album.Tracks) != 1 || album.Tracks[0].ProviderID != ext.ID {
		t.Fatalf("album = %#v", album)
	}

	playlist, err := provider.GetPlaylist("playlist-1")
	if err != nil {
		t.Fatalf("GetPlaylist: %v", err)
	}
	if playlist.Name != "Playlist playlist-1" || playlist.ProviderID != ext.ID {
		t.Fatalf("playlist = %#v", playlist)
	}

	artist, err := provider.GetArtist("artist-1")
	if err != nil {
		t.Fatalf("GetArtist: %v", err)
	}
	if artist.ProviderID != ext.ID || len(artist.Releases) != 1 || artist.Releases[0].ProviderID != ext.ID {
		t.Fatalf("artist = %#v", artist)
	}

	enriched, err := provider.EnrichTrack(&ExtTrackMetadata{ID: "track-1", Name: "Old", ProviderID: ext.ID})
	if err != nil {
		t.Fatalf("EnrichTrack: %v", err)
	}
	if enriched.Name != "Enriched" || enriched.ProviderID != ext.ID {
		t.Fatalf("enriched = %#v", enriched)
	}

	availability, err := provider.CheckAvailabilityForItemID("ISRC", "Song", "Artist", "spotify:1", "dz", "tidal", "qobuz", 0, "")
	if err != nil {
		t.Fatalf("CheckAvailabilityForItemID: %v", err)
	}
	if !availability.Available || availability.TrackID != "download-track" || !availability.SkipFallback {
		t.Fatalf("availability = %#v", availability)
	}

	progress := []int{}
	download, err := provider.Download("track-1", "LOSSLESS", filepath.Join(t.TempDir(), "song.flac"), "", func(percent int) {
		progress = append(progress, percent)
	})
	if err != nil {
		t.Fatalf("Download: %v", err)
	}
	if !download.Success || download.Decryption == nil || download.DecryptionKey != "001122" || len(progress) != 1 || progress[0] != 100 {
		t.Fatalf("download = %#v progress=%v", download, progress)
	}

	lyrics, err := provider.FetchLyrics("Song", "Artist", "Album", 180)
	if err != nil {
		t.Fatalf("GetLyrics: %v", err)
	}
	if lyrics.Provider != ext.ID || len(lyrics.Lines) != 1 || lyrics.Lines[0].Words != "Hello" {
		t.Fatalf("lyrics = %#v", lyrics)
	}

	urlResult, err := provider.HandleURL("https://example.test/track/1")
	if err != nil {
		t.Fatalf("HandleURL: %v", err)
	}
	if urlResult.Track == nil || urlResult.Track.Name == "" || len(urlResult.Tracks) != 1 || urlResult.Album == nil || urlResult.Artist == nil {
		t.Fatalf("url result = %#v", urlResult)
	}

	post, err := provider.PostProcessV2(PostProcessInput{Path: filepath.Join(t.TempDir(), "song.flac")}, map[string]any{"title": "Song"}, "hook")
	if err != nil {
		t.Fatalf("PostProcessV2: %v", err)
	}
	if !post.Success || post.BitDepth != 24 || post.SampleRate != 96000 {
		t.Fatalf("post = %#v", post)
	}
}

func TestExtensionProviderAndManagerSelectionHelpers(t *testing.T) {
	manifest := &ExtensionManifest{Capabilities: map[string]any{
		"replacesBuiltInProviders": []any{" Deezer ", 7, ""},
	}}
	if values := manifestCapabilityStringList(manifest, "replacesBuiltInProviders"); len(values) != 1 || values[0] != "deezer" {
		t.Fatalf("capability list = %#v", values)
	}
	if !extensionReplacesBuiltInProvider(&loadedExtension{Manifest: manifest}, "deezer") || extensionReplacesBuiltInProvider(nil, "deezer") {
		t.Fatal("extension replacement mismatch")
	}
	if trimKnownProviderPrefix("Deezer:101", "deezer") != "101" || trimKnownProviderPrefix("101", "deezer") != "101" {
		t.Fatal("trimKnownProviderPrefix mismatch")
	}
	if metadataTrackDedupKey(ExtTrackMetadata{ISRC: "usrc"}) != "isrc:USRC" ||
		metadataTrackDedupKey(ExtTrackMetadata{SpotifyID: "sp"}) != "spotify:sp" ||
		metadataTrackDedupKey(ExtTrackMetadata{ProviderID: "p", ID: "1"}) != "p:1" {
		t.Fatal("metadata dedup key mismatch")
	}

	manager := &extensionManager{extensions: map[string]*loadedExtension{}}
	downloadExt := newTestLoadedExtension(t, ExtensionTypeDownloadProvider, ExtensionTypeMetadataProvider)
	manager.extensions[downloadExt.ID] = downloadExt
	if providers := manager.GetDownloadProviders(); len(providers) != 1 {
		t.Fatalf("download providers = %#v", providers)
	}
	SetProviderPriority([]string{"deezer", "coverage-ext", "coverage-ext", " "})
	if priority := GetProviderPriority(); len(priority) != 1 || priority[0] != "coverage-ext" {
		t.Fatalf("provider priority = %#v", priority)
	}
	SetExtensionFallbackProviderIDs([]string{"a", "a", " ", "b"})
	if ids := GetExtensionFallbackProviderIDs(); len(ids) != 2 || !isExtensionFallbackAllowed("a") || isExtensionFallbackAllowed("z") {
		t.Fatalf("fallback ids = %#v", ids)
	}
	SetExtensionFallbackProviderIDs(nil)
	if !isExtensionFallbackAllowed("z") {
		t.Fatal("nil fallback list should allow all")
	}
	SetMetadataProviderPriority([]string{"spotify", "deezer", "coverage-ext", "coverage-ext"})
	if priority := GetMetadataProviderPriority(); len(priority) != 1 || priority[0] != "coverage-ext" {
		t.Fatalf("metadata priority = %#v", priority)
	}
}
