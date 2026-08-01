package gobackend

import (
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLyricsExportWrappersWithoutNetwork(t *testing.T) {
	dir := t.TempDir()
	audioPath := filepath.Join(dir, "sidecar.mp3")
	if err := os.WriteFile(audioPath, []byte("audio"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "sidecar.lrc"), []byte("[00:00.00]Sidecar lyric"), 0600); err != nil {
		t.Fatal(err)
	}

	if lrc, err := GetLyricsLRC("spotify-1", "Song Instrumental", "Artist", "", 180000); err != nil || lrc != "[instrumental:true]" {
		t.Fatalf("GetLyricsLRC instrumental = %q/%v", lrc, err)
	}
	if jsonText, err := GetLyricsLRCWithSource("spotify-1", "Song Instrumental", "Artist", "", 180000); err != nil || !strings.Contains(jsonText, `"instrumental":true`) {
		t.Fatalf("GetLyricsLRCWithSource instrumental = %q/%v", jsonText, err)
	}
	if lrc, err := GetLyricsLRC("", "", "", audioPath, 0); err != nil || !strings.Contains(lrc, "Sidecar lyric") {
		t.Fatalf("GetLyricsLRC sidecar = %q/%v", lrc, err)
	}
	if jsonText, err := GetLyricsLRCWithSource("", "", "", audioPath, 0); err != nil || !strings.Contains(jsonText, "Sidecar lyric") {
		t.Fatalf("GetLyricsLRCWithSource sidecar = %q/%v", jsonText, err)
	}

	outPath := filepath.Join(dir, "lyrics.lrc")
	if err := FetchAndSaveLyrics("Song", "Artist", "", 0, outPath, audioPath); err != nil {
		t.Fatalf("FetchAndSaveLyrics sidecar: %v", err)
	}
	if data := string(mustReadFile(t, outPath)); !strings.Contains(data, "Sidecar lyric") {
		t.Fatalf("saved lyrics = %q", data)
	}
	if response, err := EmbedLyricsToFile(filepath.Join(dir, "not-flac.mp3"), "lyrics"); err != nil || !strings.Contains(response, `"success":false`) {
		t.Fatalf("EmbedLyricsToFile error = %q/%v", response, err)
	}
	if response, err := RewriteSplitArtistTagsExport(filepath.Join(dir, "not-flac.mp3"), "A;B", "A"); err != nil || !strings.Contains(response, `"success":false`) {
		t.Fatalf("RewriteSplitArtistTagsExport error = %q/%v", response, err)
	}
}

func TestLyricsExportWrappersRejectMetadataOnlySidecar(t *testing.T) {
	dir := t.TempDir()
	audioPath := filepath.Join(dir, "metadata-only.mp3")
	if err := os.WriteFile(audioPath, []byte("audio"), 0600); err != nil {
		t.Fatal(err)
	}
	metadataOnly := "[ti:Title]\n[ar:Artist]\n[al:Album]\n[by:SpotiFLAC Mobile]"
	if err := os.WriteFile(filepath.Join(dir, "metadata-only.lrc"), []byte(metadataOnly), 0600); err != nil {
		t.Fatal(err)
	}

	if rawLyricsHasUsableContent(metadataOnly) {
		t.Fatal("metadata-only LRC must not be considered usable")
	}
	if !rawLyricsHasUsableContent("[00:01.00]Actual lyric") {
		t.Fatal("timed lyric must be considered usable")
	}
	if !rawLyricsHasUsableContent("[instrumental:true]") {
		t.Fatal("instrumental marker must be considered usable")
	}

	if lrc, err := GetLyricsLRC("", "", "", audioPath, 0); err != nil || lrc != "" {
		t.Fatalf("GetLyricsLRC metadata-only sidecar = %q/%v", lrc, err)
	}
	if jsonText, err := GetLyricsLRCWithSource("", "", "", audioPath, 0); err != nil ||
		!strings.Contains(jsonText, `"lyrics":""`) || strings.Contains(jsonText, `"source":"Embedded"`) {
		t.Fatalf("GetLyricsLRCWithSource metadata-only sidecar = %q/%v", jsonText, err)
	}
}

func TestSongLinkExportWrappersWithFakeClient(t *testing.T) {
	origClient := globalSongLinkClient
	origRetryConfig := songLinkRetryConfig
	defer func() {
		globalSongLinkClient = origClient
		songLinkRetryConfig = origRetryConfig
		SetSongLinkNetworkOptions(false, false)
	}()
	songLinkRetryConfig = func() RetryConfig {
		return RetryConfig{MaxRetries: 0, InitialDelay: 0, MaxDelay: 0, BackoffFactor: 1}
	}
	globalSongLinkClient = &SongLinkClient{client: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		var body string
		switch req.URL.Host {
		case "api.zarz.moe":
			body = `{"success":true,"songUrls":{"Spotify":"https://open.spotify.com/track/spotify-1","Deezer":"https://www.deezer.com/track/101","Tidal":"https://listen.tidal.com/track/202","YouTube":"https://youtu.be/yt1","AmazonMusic":"https://music.amazon.com/tracks/amz1","Qobuz":"https://open.qobuz.com/track/303"}}`
		case "api.song.link":
			body = `{"linksByPlatform":{"spotify":{"url":"https://open.spotify.com/track/spotify-1"},"deezer":{"url":"https://www.deezer.com/track/101"},"tidal":{"url":"https://listen.tidal.com/track/202"},"youtubeMusic":{"url":"https://music.youtube.com/watch?v=ytm1"},"amazonMusic":{"url":"https://music.amazon.com/tracks/amz1"},"qobuz":{"url":"https://open.qobuz.com/track/303"}}}`
		default:
			t.Fatalf("unexpected SongLink request: %s", req.URL.String())
		}
		return &http.Response{StatusCode: http.StatusOK, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body)), Request: req}, nil
	})}}
	songLinkClientOnce.Do(func() {})

	SetSongLinkNetworkOptions(true, true)
	if spotifyID, err := GetSpotifyIDFromDeezerTrack("101"); err != nil || spotifyID != "spotify-1" {
		t.Fatalf("GetSpotifyIDFromDeezerTrack = %q/%v", spotifyID, err)
	}
	if tidalURL, err := GetTidalURLFromDeezerTrack("101"); err != nil || !strings.Contains(tidalURL, "tidal") {
		t.Fatalf("GetTidalURLFromDeezerTrack = %q/%v", tidalURL, err)
	}
	if urls, err := NewSongLinkClient().GetStreamingURLs("spotify-1"); err != nil || urls["tidal"] == "" || urls["amazon"] == "" {
		t.Fatalf("GetStreamingURLs = %#v/%v", urls, err)
	}
	if youtubeURL, err := NewSongLinkClient().GetYouTubeURLFromSpotify("spotify-1"); err != nil || !strings.Contains(youtubeURL, "youtu") {
		t.Fatalf("GetYouTubeURLFromSpotify = %q/%v", youtubeURL, err)
	}
	if amazonURL, err := NewSongLinkClient().GetAmazonURLFromDeezer("101"); err != nil || !strings.Contains(amazonURL, "amazon") {
		t.Fatalf("GetAmazonURLFromDeezer = %q/%v", amazonURL, err)
	}
	if youtubeURL, err := NewSongLinkClient().GetYouTubeURLFromDeezer("101"); err != nil || !strings.Contains(youtubeURL, "youtube") {
		t.Fatalf("GetYouTubeURLFromDeezer = %q/%v", youtubeURL, err)
	}
	if deezerID, err := NewSongLinkClient().GetDeezerIDFromSpotify("spotify-1"); err != nil || deezerID != "101" {
		t.Fatalf("GetDeezerIDFromSpotify = %q/%v", deezerID, err)
	}
	if album, err := NewSongLinkClient().CheckAlbumAvailability("album-1"); err != nil || !album.Deezer || album.DeezerID == "" {
		t.Fatalf("CheckAlbumAvailability = %#v/%v", album, err)
	}
	if albumID, err := NewSongLinkClient().GetDeezerAlbumIDFromSpotify("album-1"); err != nil || albumID == "" {
		t.Fatalf("GetDeezerAlbumIDFromSpotify = %q/%v", albumID, err)
	}
	if availability, err := NewSongLinkClient().CheckAvailabilityFromURL("https://www.deezer.com/track/101"); err != nil || !availability.Deezer {
		t.Fatalf("CheckAvailabilityFromURL = %#v/%v", availability, err)
	}

	if songLinkExtractDeezerTrackID(nil) != "" || songLinkExtractDeezerTrackID(&TrackMetadata{ExternalURL: "https://www.deezer.com/track/202"}) != "202" {
		t.Fatal("songLinkExtractDeezerTrackID mismatch")
	}

	if linksJSON, err := GetTrackPlatformLinksJSON("spotify-1", ""); err != nil ||
		!strings.Contains(linksJSON, `"tidal":"https://listen.tidal.com/track/202"`) ||
		!strings.Contains(linksJSON, `"spotify":`) {
		t.Fatalf("GetTrackPlatformLinksJSON = %q/%v", linksJSON, err)
	}
	// Second call must come from the links cache, not a new request.
	if cached, hit, cachedErr := trackPlatformLinksCacheLookup(GetSongLinkRegion() + "|spotify:spotify-1"); !hit || cachedErr || cached["tidal"] == "" {
		t.Fatalf("trackPlatformLinksCacheLookup = %#v hit=%v err=%v", cached, hit, cachedErr)
	}
	if _, err := GetTrackPlatformLinksJSON("", ""); err == nil {
		t.Fatal("GetTrackPlatformLinksJSON with empty IDs should error")
	}

	deezerClient = &DeezerClient{
		httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
			body := fakeDeezerResponse(req.URL.Path, req.URL.RawQuery)
			if body == "" {
				body = `{"error":"missing"}`
			}
			return &http.Response{StatusCode: http.StatusOK, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body)), Request: req}, nil
		})},
		searchCache:          map[string]*cacheEntry{},
		albumCache:           map[string]*cacheEntry{},
		artistCache:          map[string]*cacheEntry{},
		isrcCache:            map[string]string{},
		cacheCleanupInterval: time.Hour,
	}
	deezerClientOnce.Do(func() {})
	if jsonText, err := ConvertSpotifyToDeezer("track", "spotify-1"); err != nil || !strings.Contains(jsonText, `"spotify_id":"deezer:101"`) {
		t.Fatalf("ConvertSpotifyToDeezer track = %q/%v", jsonText, err)
	}
	if jsonText, err := ConvertSpotifyToDeezer("album", "album-1"); err != nil || jsonText == "" {
		t.Fatalf("ConvertSpotifyToDeezer album = %q/%v", jsonText, err)
	}
}
