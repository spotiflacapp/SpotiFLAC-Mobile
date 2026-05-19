package gobackend

import (
	"encoding/json"
	"strings"
	"sync"
)

// CrossExtensionShareResult holds the result for one extension.
type CrossExtensionShareResult struct {
	ExtensionID   string `json:"extension_id"`
	DisplayName   string `json:"display_name"`
	Found         bool   `json:"found"`
	ItemID        string `json:"item_id,omitempty"`
	ItemName      string `json:"item_name,omitempty"`
	ItemArtists   string `json:"item_artists,omitempty"`
	Error         string `json:"error,omitempty"`
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

	// Prefer a provider-specific ID to build an internal link.
	itemID := resolveCollectionItemID(bestTrack)
	res.Found = true
	res.ItemID = itemID
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

	res.Found = true
	res.ItemID = resolveCollectionItemID(bestTrack)
	res.ItemName = bestTrack.Artists
	return res
}

// findPlaylistForExtension falls back to album search (playlists are user-specific
// and cannot be cross-matched by name alone; we look for a similarly-named album/playlist).
func findPlaylistForExtension(
	p *extensionProviderWrapper,
	playlistName, artists, searchQuery string,
	res CrossExtensionShareResult,
) CrossExtensionShareResult {
	// Playlists usually cannot be matched across services — return not-found gracefully.
	res.Error = "cross-service playlist matching not supported"
	return res
}

// resolveCollectionItemID picks the best available ID from a track to represent
// the album/artist on the same extension (provider-specific IDs first).
func resolveCollectionItemID(t *ExtTrackMetadata) string {
	if t.TidalID != "" {
		return t.TidalID
	}
	if t.QobuzID != "" {
		return t.QobuzID
	}
	if t.DeezerID != "" {
		return t.DeezerID
	}
	if t.SpotifyID != "" {
		return t.SpotifyID
	}
	return t.ID
}
