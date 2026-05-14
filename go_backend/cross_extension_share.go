package gobackend

import (
	"encoding/json"
	"strings"
	"sync"
)

// CrossExtensionShareResult holds the result for one extension.
type CrossExtensionShareResult struct {
	ExtensionID string `json:"extension_id"`
	DisplayName string `json:"display_name"`
	Found       bool   `json:"found"`
	ItemID      string `json:"item_id,omitempty"`
	ItemName    string `json:"item_name,omitempty"`
	ItemArtists string `json:"item_artists,omitempty"`
	Error       string `json:"error,omitempty"`
}

// FindCollectionAcrossExtensionsJSON searches for an album, artist, or playlist
// across all enabled metadata-provider extensions (except the source extension).
//
// Parameters (all passed as JSON string):
//
//	{
//	  "name":                 "In Rainbows",       // album/artist/playlist title
//	  "artists":              "Radiohead",          // for album / playlist queries
//	  "type":                 "album",              // "album" | "artist" | "playlist"
//	  "source_extension_id":  "com.example.tidal"  // skip this extension
//	}
//
// Returns JSON array of CrossExtensionShareResult.
func FindCollectionAcrossExtensionsJSON(requestJSON string) (string, error) {
	var req struct {
		Name              string `json:"name"`
		Artists           string `json:"artists"`
		Type              string `json:"type"`
		SourceExtensionID string `json:"source_extension_id"`
	}
	if err := json.Unmarshal([]byte(requestJSON), &req); err != nil {
		return "", err
	}

	req.Name = strings.TrimSpace(req.Name)
	req.Artists = strings.TrimSpace(req.Artists)
	req.Type = strings.TrimSpace(strings.ToLower(req.Type))
	req.SourceExtensionID = strings.TrimSpace(req.SourceExtensionID)

	if req.Name == "" {
		return "[]", nil
	}
	if req.Type == "" {
		req.Type = "album"
	}

	manager := getExtensionManager()
	providers := manager.GetMetadataProviders()

	// Build search query once – "Album Name Artist Name"
	searchQuery := req.Name
	if req.Artists != "" {
		searchQuery = req.Name + " " + req.Artists
	}

	type workItem struct {
		provider *extensionProviderWrapper
	}

	work := make([]workItem, 0, len(providers))
	for _, p := range providers {
		if p.extension.ID == req.SourceExtensionID {
			continue
		}
		work = append(work, workItem{provider: p})
	}

	results := make([]CrossExtensionShareResult, len(work))
	var wg sync.WaitGroup

	for i, w := range work {
		wg.Add(1)
		go func(idx int, wi workItem) {
			defer wg.Done()
			res := CrossExtensionShareResult{
				ExtensionID: wi.provider.extension.ID,
				DisplayName: wi.provider.extension.Manifest.DisplayName,
			}

			switch req.Type {
			case "artist":
				res = findArtistForExtension(wi.provider, req.Name, searchQuery, res)
			case "playlist":
				res = findPlaylistForExtension(wi.provider, req.Name, req.Artists, searchQuery, res)
			default: // "album"
				res = findAlbumForExtension(wi.provider, req.Name, req.Artists, searchQuery, res)
			}

			results[idx] = res
		}(i, w)
	}

	wg.Wait()

	jsonBytes, err := json.Marshal(results)
	if err != nil {
		return "[]", err
	}
	return string(jsonBytes), nil
}

// findAlbumForExtension searches for an album in a single extension.
// Strategy: search tracks with "album artist", pick the best album match.
func findAlbumForExtension(
	p *extensionProviderWrapper,
	albumName, artists, searchQuery string,
	res CrossExtensionShareResult,
) CrossExtensionShareResult {
	searchResult, err := p.SearchTracks(searchQuery, 10)
	if err != nil {
		res.Error = err.Error()
		return res
	}
	if searchResult == nil || len(searchResult.Tracks) == 0 {
		res.Error = "no results"
		return res
	}

	normalAlbum := normalizeLooseTitle(albumName)
	normalArtists := normalizeLooseArtistName(artists)

	// Find the track whose album best matches.
	bestScore := -1
	var bestTrack *ExtTrackMetadata

	for i := range searchResult.Tracks {
		t := &searchResult.Tracks[i]
		trackAlbum := normalizeLooseTitle(t.AlbumName)
		trackArtist := normalizeLooseArtistName(t.Artists + " " + t.AlbumArtist)

		score := 0
		if trackAlbum == normalAlbum {
			score += 100
		} else if strings.Contains(trackAlbum, normalAlbum) || strings.Contains(normalAlbum, trackAlbum) {
			score += 50
		}
		if normalArtists != "" && (strings.Contains(trackArtist, normalArtists) || strings.Contains(normalArtists, trackArtist)) {
			score += 30
		}

		if score > bestScore {
			bestScore = score
			bestTrack = t
		}
	}

	if bestTrack == nil || bestScore < 50 {
		res.Error = "album not found"
		return res
	}

	itemURL := buildAlbumURL(p.extension.ID, bestTrack)
	if itemURL == "" {
		res.Error = "album found but could not resolve link"
		return res
	}

	res.Found = true
	res.ItemID = itemURL
	res.ItemName = bestTrack.AlbumName
	res.ItemArtists = bestTrack.Artists
	return res
}

// findArtistForExtension searches for an artist in a single extension.
func findArtistForExtension(
	p *extensionProviderWrapper,
	artistName, searchQuery string,
	res CrossExtensionShareResult,
) CrossExtensionShareResult {
	searchResult, err := p.SearchTracks(searchQuery, 10)
	if err != nil {
		res.Error = err.Error()
		return res
	}
	if searchResult == nil || len(searchResult.Tracks) == 0 {
		res.Error = "no results"
		return res
	}

	normalArtist := normalizeLooseArtistName(artistName)
	bestScore := -1
	var bestTrack *ExtTrackMetadata

	for i := range searchResult.Tracks {
		t := &searchResult.Tracks[i]
		trackArtist := normalizeLooseArtistName(t.Artists)
		score := 0
		if trackArtist == normalArtist {
			score += 100
		} else if strings.Contains(trackArtist, normalArtist) || strings.Contains(normalArtist, trackArtist) {
			score += 60
		}
		if score > bestScore {
			bestScore = score
			bestTrack = t
		}
	}

	if bestTrack == nil || bestScore < 60 {
		res.Error = "artist not found"
		return res
	}

	itemURL := buildArtistURL(p.extension.ID, bestTrack)
	if itemURL == "" {
		res.Error = "artist found but could not resolve link"
		return res
	}

	res.Found = true
	res.ItemID = itemURL
	res.ItemName = bestTrack.Artists
	return res
}

// findPlaylistForExtension falls back gracefully — playlists are user-specific
// and cannot be reliably cross-matched by name alone.
func findPlaylistForExtension(
	p *extensionProviderWrapper,
	playlistName, artists, searchQuery string,
	res CrossExtensionShareResult,
) CrossExtensionShareResult {
	res.Error = "cross-service playlist matching not supported"
	return res
}

// stripKnownPrefix removes a known scheme prefix ("deezer:", "tidal:", "qobuz:", etc.)
// and returns the bare numeric/string ID.
func stripKnownPrefix(id string) string {
	for _, prefix := range []string{"deezer:", "tidal:", "qobuz:", "spotify:", "soundcloud:", "amazon:", "ytmusic:"} {
		if strings.HasPrefix(id, prefix) {
			return id[len(prefix):]
		}
	}
	return id
}

// buildAlbumURL returns a full, openable URL for the album that contains bestTrack,
// using whatever ID/URL fields the JS extension placed on the track object.
//
// Field priority per extension:
//   - Spotify:     track.AlbumURL  (already a full https://open.spotify.com/album/… URL)
//   - Tidal:       track.AlbumID   ("tidal:12345")  → https://tidal.com/browse/album/12345
//   - Deezer:      track.AlbumID   ("deezer:12345") → https://www.deezer.com/album/12345
//   - Qobuz:       track.AlbumID   ("qobuz:abc")    → https://play.qobuz.com/album/abc
//   - Apple Music: track.AlbumURL  (numeric id string) → https://music.apple.com/album/{id}
//   - Amazon:      track.AlbumID   (ASIN)            → https://music.amazon.com/albums/{ASIN}
//   - YouTube:     track.AlbumID   (MPREb_…)         → https://music.youtube.com/browse/{id}
//   - SoundCloud:  track.ExternalURLs (track permalink — albums don't exist on SC)
func buildAlbumURL(extensionID string, t *ExtTrackMetadata) string {
	switch {
	case strings.Contains(extensionID, "spotify"):
		// Spotify puts a ready-made album URL on every track result.
		if t.AlbumURL != "" {
			return t.AlbumURL
		}
		if t.AlbumID != "" {
			return "https://open.spotify.com/album/" + stripKnownPrefix(t.AlbumID)
		}

	case strings.Contains(extensionID, "tidal"):
		if t.AlbumID != "" {
			return "https://tidal.com/browse/album/" + stripKnownPrefix(t.AlbumID)
		}

	case strings.Contains(extensionID, "deezer"):
		if t.AlbumID != "" {
			return "https://www.deezer.com/album/" + stripKnownPrefix(t.AlbumID)
		}

	case strings.Contains(extensionID, "qobuz"):
		if t.AlbumID != "" {
			return "https://play.qobuz.com/album/" + stripKnownPrefix(t.AlbumID)
		}

	case strings.Contains(extensionID, "apple"), strings.Contains(extensionID, "applemusic"):
		// Apple Music: AlbumURL holds the raw catalog ID; storefront defaults to "us".
		if t.AlbumURL != "" {
			id := stripKnownPrefix(t.AlbumURL)
			if strings.HasPrefix(id, "https://") {
				return id
			}
			return "https://music.apple.com/us/album/" + id
		}
		if t.AlbumID != "" {
			return "https://music.apple.com/us/album/" + stripKnownPrefix(t.AlbumID)
		}

	case strings.Contains(extensionID, "amazon"):
		if t.AlbumID != "" {
			return "https://music.amazon.com/albums/" + stripKnownPrefix(t.AlbumID)
		}

	case strings.Contains(extensionID, "youtube"), strings.Contains(extensionID, "ytmusic"):
		// YouTube Music album IDs start with "MPREb_".
		if t.AlbumID != "" {
			id := stripKnownPrefix(t.AlbumID)
			return "https://music.youtube.com/browse/" + id
		}

	case strings.Contains(extensionID, "soundcloud"):
		// SoundCloud has no album concept; return the track permalink as the best proxy.
		if t.ExternalURLs != "" {
			return t.ExternalURLs
		}
	}

	return ""
}

// buildArtistURL returns a full, openable URL for the primary artist of bestTrack.
//
// Field priority per extension:
//   - Spotify:     track.ArtistID  (bare ID) → https://open.spotify.com/artist/{id}
//   - Tidal:       track.ArtistID  ("tidal:12345") → https://tidal.com/browse/artist/12345
//   - Deezer:      track.ArtistID  ("deezer:12345") → https://www.deezer.com/artist/12345
//   - Qobuz:       track.ArtistID  ("qobuz:abc")    → https://play.qobuz.com/artist/abc
//   - Apple Music: track.ArtistID  (numeric)        → https://music.apple.com/us/artist/{id}
//   - Amazon:      track.ArtistID  (ASIN)            → https://music.amazon.com/artists/{ASIN}
//   - YouTube:     track.ArtistID  (UC…)             → https://music.youtube.com/channel/{id}
//   - SoundCloud:  track.ArtistID  (numeric user ID) → https://soundcloud.com/users/{id}
func buildArtistURL(extensionID string, t *ExtTrackMetadata) string {
	switch {
	case strings.Contains(extensionID, "spotify"):
		if t.ArtistID != "" {
			return "https://open.spotify.com/artist/" + stripKnownPrefix(t.ArtistID)
		}

	case strings.Contains(extensionID, "tidal"):
		if t.ArtistID != "" {
			return "https://tidal.com/browse/artist/" + stripKnownPrefix(t.ArtistID)
		}

	case strings.Contains(extensionID, "deezer"):
		if t.ArtistID != "" {
			return "https://www.deezer.com/artist/" + stripKnownPrefix(t.ArtistID)
		}

	case strings.Contains(extensionID, "qobuz"):
		if t.ArtistID != "" {
			return "https://play.qobuz.com/artist/" + stripKnownPrefix(t.ArtistID)
		}

	case strings.Contains(extensionID, "apple"), strings.Contains(extensionID, "applemusic"):
		if t.ArtistID != "" {
			id := stripKnownPrefix(t.ArtistID)
			if strings.HasPrefix(id, "https://") {
				return id
			}
			return "https://music.apple.com/us/artist/" + id
		}

	case strings.Contains(extensionID, "amazon"):
		if t.ArtistID != "" {
			return "https://music.amazon.com/artists/" + stripKnownPrefix(t.ArtistID)
		}

	case strings.Contains(extensionID, "youtube"), strings.Contains(extensionID, "ytmusic"):
		// YouTube Music artist IDs start with "UC".
		if t.ArtistID != "" {
			id := stripKnownPrefix(t.ArtistID)
			return "https://music.youtube.com/channel/" + id
		}

	case strings.Contains(extensionID, "soundcloud"):
		// SoundCloud artist is a user; numeric ID works via API redirect URL.
		if t.ArtistID != "" {
			return "https://soundcloud.com/users/" + stripKnownPrefix(t.ArtistID)
		}
		// Fall back to the track permalink domain as a best-effort user link.
		if t.ExternalURLs != "" {
			parts := strings.Split(t.ExternalURLs, "/")
			if len(parts) >= 4 {
				return "https://soundcloud.com/" + parts[3]
			}
		}
	}

	return ""
}
