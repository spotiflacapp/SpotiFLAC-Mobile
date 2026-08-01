package gobackend

import (
	"context"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestDeezerClientWithFakeHTTP(t *testing.T) {
	client := &DeezerClient{
		httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
			body := fakeDeezerResponse(req.URL.Path, req.URL.RawQuery)
			status := http.StatusOK
			if body == "" {
				status = http.StatusNotFound
				body = `{"error":"missing"}`
			}
			return &http.Response{
				StatusCode: status,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(body)),
				Request:    req,
			}, nil
		})},
		searchCache:          map[string]*cacheEntry{},
		albumCache:           map[string]*cacheEntry{},
		artistCache:          map[string]*cacheEntry{},
		isrcCache:            map[string]string{},
		cacheCleanupInterval: time.Millisecond,
	}
	ctx := context.Background()

	search, err := client.SearchAll(ctx, "artist song", 2, 2, "")
	if err != nil {
		t.Fatalf("SearchAll: %v", err)
	}
	if len(search.Tracks) != 1 || len(search.Artists) != 1 || len(search.Albums) != 1 || len(search.Playlists) != 1 {
		t.Fatalf("search = %#v", search)
	}
	cached, err := client.SearchAll(ctx, "artist song", 2, 2, "")
	if err != nil || cached != search {
		t.Fatalf("cached SearchAll = %#v/%v", cached, err)
	}
	if filtered, err := client.SearchAll(ctx, "artist song", 1, 1, "track"); err != nil || len(filtered.Tracks) != 1 || len(filtered.Artists) != 0 {
		t.Fatalf("filtered search = %#v/%v", filtered, err)
	}

	track, err := client.GetTrack(ctx, "101")
	if err != nil {
		t.Fatalf("GetTrack: %v", err)
	}
	if track.Track.SpotifyID != "deezer:101" || track.Track.Artists != "Contributor A, Contributor B" {
		t.Fatalf("track = %#v", track)
	}

	album, err := client.GetAlbum(ctx, "201")
	if err != nil {
		t.Fatalf("GetAlbum: %v", err)
	}
	if album.AlbumInfo.Name != "Album" || len(album.TrackList) != 2 || album.TrackList[1].ISRC == "" {
		t.Fatalf("album = %#v", album)
	}
	if cachedAlbum, err := client.GetAlbum(ctx, "201"); err != nil || cachedAlbum != album {
		t.Fatalf("cached album = %#v/%v", cachedAlbum, err)
	}

	artist, err := client.GetArtist(ctx, "301")
	if err != nil {
		t.Fatalf("GetArtist: %v", err)
	}
	if artist.ArtistInfo.Name != "Artist" || len(artist.Albums) != 1 || artist.Albums[0].TotalTracks == 0 {
		t.Fatalf("artist = %#v", artist)
	}
	if cachedArtist, err := client.GetArtist(ctx, "301"); err != nil || cachedArtist != artist {
		t.Fatalf("cached artist = %#v/%v", cachedArtist, err)
	}

	playlist, err := client.GetPlaylist(ctx, "401")
	if err != nil {
		t.Fatalf("GetPlaylist: %v", err)
	}
	if playlist.PlaylistInfo.Tracks.Total != 2 || len(playlist.TrackList) != 2 {
		t.Fatalf("playlist = %#v", playlist)
	}

	byISRC, err := client.SearchByISRC(ctx, "USRC17607839")
	if err != nil {
		t.Fatalf("SearchByISRC: %v", err)
	}
	if byISRC.SpotifyID != "deezer:101" {
		t.Fatalf("by ISRC = %#v", byISRC)
	}
	if _, err := client.SearchByISRC(ctx, "MISSING"); err == nil {
		t.Fatal("expected missing ISRC error")
	}

	isrc, err := client.GetTrackISRC(ctx, "102")
	if err != nil || isrc != "USRC17607840" {
		t.Fatalf("GetTrackISRC = %q/%v", isrc, err)
	}
	albumID, err := client.GetTrackAlbumID(ctx, "101")
	if err != nil || albumID != "201" {
		t.Fatalf("GetTrackAlbumID = %q/%v", albumID, err)
	}
	extended, err := client.GetAlbumExtendedMetadata(ctx, "201")
	if err != nil {
		t.Fatalf("GetAlbumExtendedMetadata: %v", err)
	}
	if extended.Genre != "Pop, Dance" || extended.Label != "Label" {
		t.Fatalf("extended = %#v", extended)
	}
	if byTrack, err := client.GetExtendedMetadataByTrackID(ctx, "101"); err != nil || byTrack.Label != "Label" {
		t.Fatalf("metadata by track = %#v/%v", byTrack, err)
	}
	if byISRCMeta, err := client.GetExtendedMetadataByISRC(ctx, "USRC17607839"); err != nil || byISRCMeta.Label != "Label" {
		t.Fatalf("metadata by isrc = %#v/%v", byISRCMeta, err)
	}
	if _, err := client.GetExtendedMetadataByISRC(ctx, ""); err == nil {
		t.Fatal("expected empty ISRC metadata error")
	}

	if typ, id, err := parseDeezerURL("https://www.deezer.com/us/track/101"); err != nil || typ != "track" || id != "101" {
		t.Fatalf("parseDeezerURL = %q/%q/%v", typ, id, err)
	}
	if _, _, err := parseDeezerURL("https://example.com/track/101"); err == nil {
		t.Fatal("expected non-Deezer URL error")
	}

	client.cacheMu.Lock()
	client.searchCache["expired"] = &cacheEntry{expiresAt: time.Now().Add(-time.Hour)}
	client.searchCache["keep1"] = &cacheEntry{expiresAt: time.Now().Add(time.Hour)}
	client.searchCache["keep2"] = &cacheEntry{expiresAt: time.Now().Add(2 * time.Hour)}
	client.pruneExpiredCacheEntriesLocked(client.searchCache, time.Now())
	client.trimCacheEntriesLocked(client.searchCache, 1)
	client.isrcCache["1"] = "A"
	client.isrcCache["2"] = "B"
	client.trimStringCacheEntriesLocked(client.isrcCache, 1)
	client.cacheMu.Unlock()
}
