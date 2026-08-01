package gobackend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	deezerBaseURL     = "https://api.deezer.com/2.0"
	deezerSearchURL   = deezerBaseURL + "/search"
	deezerTrackURL    = deezerBaseURL + "/track/%s"
	deezerAlbumURL    = deezerBaseURL + "/album/%s"
	deezerArtistURL   = deezerBaseURL + "/artist/%s"
	deezerPlaylistURL = deezerBaseURL + "/playlist/%s"

	deezerCacheTTL = 10 * time.Minute

	deezerMaxParallelISRC = 10

	// Deezer API timeout and retry configuration for mobile networks
	deezerAPITimeoutMobile = 25 * time.Second
	deezerMaxRetries       = 2
	deezerRetryDelay       = 500 * time.Millisecond

	deezerMaxSearchCacheEntries = 300
	deezerMaxAlbumCacheEntries  = 200
	deezerMaxArtistCacheEntries = 200
	deezerMaxISRCCacheEntries   = 4000
	deezerCacheCleanupInterval  = 5 * time.Minute
)

type DeezerClient struct {
	httpClient           *http.Client
	searchCache          map[string]*cacheEntry
	albumCache           map[string]*cacheEntry
	artistCache          map[string]*cacheEntry
	isrcCache            map[string]string
	cacheMu              sync.RWMutex
	lastCacheCleanup     time.Time
	cacheCleanupInterval time.Duration
}

var (
	deezerClient     *DeezerClient
	deezerClientOnce sync.Once
)

func GetDeezerClient() *DeezerClient {
	deezerClientOnce.Do(func() {
		deezerClient = &DeezerClient{
			httpClient:           NewMetadataHTTPClient(deezerAPITimeoutMobile),
			searchCache:          make(map[string]*cacheEntry),
			albumCache:           make(map[string]*cacheEntry),
			artistCache:          make(map[string]*cacheEntry),
			isrcCache:            make(map[string]string),
			cacheCleanupInterval: deezerCacheCleanupInterval,
		}
	})
	return deezerClient
}

func (c *DeezerClient) SearchAll(ctx context.Context, query string, trackLimit, artistLimit int, filter string) (*SearchAllResult, error) {
	GoLog("[Deezer] SearchAll: query=%q, trackLimit=%d, artistLimit=%d, filter=%q\n", query, trackLimit, artistLimit, filter)

	albumLimit := 5
	playlistLimit := 5

	if filter != "" {
		switch filter {
		case "track":
			trackLimit = 50
			artistLimit = 0
			albumLimit = 0
			playlistLimit = 0
		case "artist":
			trackLimit = 0
			artistLimit = 20
			albumLimit = 0
			playlistLimit = 0
		case "album":
			trackLimit = 0
			artistLimit = 0
			albumLimit = 20
			playlistLimit = 0
		case "playlist":
			trackLimit = 0
			artistLimit = 0
			albumLimit = 0
			playlistLimit = 20
		}
	}

	cacheKey := fmt.Sprintf("deezer:all:%s:%d:%d:%d:%d:%s", query, trackLimit, artistLimit, albumLimit, playlistLimit, filter)

	c.cacheMu.RLock()
	if entry, ok := c.searchCache[cacheKey]; ok && !entry.isExpired() {
		c.cacheMu.RUnlock()
		GoLog("[Deezer] SearchAll: returning cached result\n")
		return entry.data.(*SearchAllResult), nil
	}
	c.cacheMu.RUnlock()

	result := &SearchAllResult{
		Tracks:    make([]TrackMetadata, 0, trackLimit),
		Artists:   make([]SearchArtistResult, 0, artistLimit),
		Albums:    make([]SearchAlbumResult, 0, albumLimit),
		Playlists: make([]SearchPlaylistResult, 0, playlistLimit),
	}

	if trackLimit > 0 {
		trackURL := fmt.Sprintf("%s/track?q=%s&limit=%d", deezerSearchURL, url.QueryEscape(query), trackLimit)
		GoLog("[Deezer] Fetching tracks from: %s\n", trackURL)

		var trackResp struct {
			Data  []deezerTrack `json:"data"`
			Error *struct {
				Type    string `json:"type"`
				Message string `json:"message"`
				Code    int    `json:"code"`
			} `json:"error"`
		}
		if err := c.getJSON(ctx, trackURL, &trackResp); err != nil {
			GoLog("[Deezer] Track search failed: %v\n", err)
			return nil, fmt.Errorf("deezer track search failed: %w", err)
		}

		if trackResp.Error != nil {
			GoLog("[Deezer] API error: type=%s, code=%d, message=%s\n", trackResp.Error.Type, trackResp.Error.Code, trackResp.Error.Message)
			return nil, fmt.Errorf("deezer API error: %s (code %d)", trackResp.Error.Message, trackResp.Error.Code)
		}

		GoLog("[Deezer] Got %d tracks from API\n", len(trackResp.Data))

		for _, track := range trackResp.Data {
			result.Tracks = append(result.Tracks, c.convertTrack(track))
		}
	}

	if artistLimit > 0 {
		artistURL := fmt.Sprintf("%s/artist?q=%s&limit=%d", deezerSearchURL, url.QueryEscape(query), artistLimit)
		GoLog("[Deezer] Fetching artists from: %s\n", artistURL)

		var artistResp struct {
			Data  []deezerArtist `json:"data"`
			Error *struct {
				Type    string `json:"type"`
				Message string `json:"message"`
				Code    int    `json:"code"`
			} `json:"error"`
		}
		if err := c.getJSON(ctx, artistURL, &artistResp); err == nil {
			if artistResp.Error != nil {
				GoLog("[Deezer] Artist API error: type=%s, code=%d, message=%s\n", artistResp.Error.Type, artistResp.Error.Code, artistResp.Error.Message)
			} else {
				GoLog("[Deezer] Got %d artists from API\n", len(artistResp.Data))
				for _, artist := range artistResp.Data {
					result.Artists = append(result.Artists, SearchArtistResult{
						ID:         fmt.Sprintf("deezer:%d", artist.ID),
						Name:       artist.Name,
						Images:     c.getBestArtistImage(artist),
						Followers:  artist.NbFan,
						Popularity: 0,
					})
				}
			}
		} else {
			GoLog("[Deezer] Artist search failed: %v\n", err)
		}
	}

	if albumLimit > 0 {
		albumURL := fmt.Sprintf("%s/album?q=%s&limit=%d", deezerSearchURL, url.QueryEscape(query), albumLimit)
		GoLog("[Deezer] Fetching albums from: %s\n", albumURL)

		var albumResp struct {
			Data []struct {
				ID          int64        `json:"id"`
				Title       string       `json:"title"`
				Cover       string       `json:"cover"`
				CoverMedium string       `json:"cover_medium"`
				CoverBig    string       `json:"cover_big"`
				CoverXL     string       `json:"cover_xl"`
				NbTracks    int          `json:"nb_tracks"`
				ReleaseDate string       `json:"release_date"`
				RecordType  string       `json:"record_type"`
				Artist      deezerArtist `json:"artist"`
			} `json:"data"`
			Error *struct {
				Type    string `json:"type"`
				Message string `json:"message"`
				Code    int    `json:"code"`
			} `json:"error"`
		}
		if err := c.getJSON(ctx, albumURL, &albumResp); err == nil {
			if albumResp.Error != nil {
				GoLog("[Deezer] Album API error: type=%s, code=%d, message=%s\n", albumResp.Error.Type, albumResp.Error.Code, albumResp.Error.Message)
			} else {
				GoLog("[Deezer] Got %d albums from API\n", len(albumResp.Data))
				for _, album := range albumResp.Data {
					coverURL := album.CoverXL
					if coverURL == "" {
						coverURL = album.CoverBig
					}
					if coverURL == "" {
						coverURL = album.CoverMedium
					}
					if coverURL == "" {
						coverURL = album.Cover
					}

					albumType := album.RecordType
					if albumType == "compile" {
						albumType = "compilation"
					}

					result.Albums = append(result.Albums, SearchAlbumResult{
						ID:          fmt.Sprintf("deezer:%d", album.ID),
						Name:        album.Title,
						Artists:     album.Artist.Name,
						Images:      coverURL,
						ReleaseDate: album.ReleaseDate,
						TotalTracks: album.NbTracks,
						AlbumType:   albumType,
					})
				}
			}
		} else {
			GoLog("[Deezer] Album search failed: %v\n", err)
		}
	}

	if playlistLimit > 0 {
		playlistURL := fmt.Sprintf("%s/playlist?q=%s&limit=%d", deezerSearchURL, url.QueryEscape(query), playlistLimit)
		GoLog("[Deezer] Fetching playlists from: %s\n", playlistURL)

		var playlistResp struct {
			Data []struct {
				ID            int64  `json:"id"`
				Title         string `json:"title"`
				Picture       string `json:"picture"`
				PictureMedium string `json:"picture_medium"`
				PictureBig    string `json:"picture_big"`
				PictureXL     string `json:"picture_xl"`
				NbTracks      int    `json:"nb_tracks"`
				User          struct {
					Name string `json:"name"`
				} `json:"user"`
			} `json:"data"`
			Error *struct {
				Type    string `json:"type"`
				Message string `json:"message"`
				Code    int    `json:"code"`
			} `json:"error"`
		}
		if err := c.getJSON(ctx, playlistURL, &playlistResp); err == nil {
			if playlistResp.Error != nil {
				GoLog("[Deezer] Playlist API error: type=%s, code=%d, message=%s\n", playlistResp.Error.Type, playlistResp.Error.Code, playlistResp.Error.Message)
			} else {
				GoLog("[Deezer] Got %d playlists from API\n", len(playlistResp.Data))
				for _, playlist := range playlistResp.Data {
					pictureURL := playlist.PictureXL
					if pictureURL == "" {
						pictureURL = playlist.PictureBig
					}
					if pictureURL == "" {
						pictureURL = playlist.PictureMedium
					}
					if pictureURL == "" {
						pictureURL = playlist.Picture
					}

					result.Playlists = append(result.Playlists, SearchPlaylistResult{
						ID:          fmt.Sprintf("deezer:%d", playlist.ID),
						Name:        playlist.Title,
						Owner:       playlist.User.Name,
						Images:      pictureURL,
						TotalTracks: playlist.NbTracks,
					})
				}
			}
		} else {
			GoLog("[Deezer] Playlist search failed: %v\n", err)
		}
	}

	GoLog("[Deezer] SearchAll complete: %d tracks, %d artists, %d albums, %d playlists\n", len(result.Tracks), len(result.Artists), len(result.Albums), len(result.Playlists))

	c.cacheMu.Lock()
	now := time.Now()
	c.searchCache[cacheKey] = &cacheEntry{
		data:      result,
		expiresAt: now.Add(deezerCacheTTL),
	}
	c.maybeCleanupCachesLocked(now)
	c.cacheMu.Unlock()

	return result, nil
}

func (c *DeezerClient) GetTrack(ctx context.Context, trackID string) (*TrackResponse, error) {
	trackURL := fmt.Sprintf(deezerTrackURL, trackID)

	var track deezerTrack
	if err := c.getJSON(ctx, trackURL, &track); err != nil {
		return nil, err
	}

	return &TrackResponse{
		Track: c.convertTrack(track),
	}, nil
}

func (c *DeezerClient) SearchByISRC(ctx context.Context, isrc string) (*TrackMetadata, error) {
	directURL := fmt.Sprintf("%s/track/isrc:%s", deezerBaseURL, isrc)

	var track deezerTrack
	if err := c.getJSON(ctx, directURL, &track); err != nil {
		searchURL := fmt.Sprintf("%s/track?q=isrc:%s&limit=1", deezerSearchURL, isrc)
		var resp struct {
			Data []deezerTrack `json:"data"`
		}
		if err := c.getJSON(ctx, searchURL, &resp); err != nil {
			return nil, err
		}
		if len(resp.Data) == 0 {
			return nil, fmt.Errorf("no track found for ISRC: %s", isrc)
		}
		result := c.convertTrack(resp.Data[0])
		return &result, nil
	}

	if track.ID == 0 {
		return nil, fmt.Errorf("no track found for ISRC: %s", isrc)
	}

	result := c.convertTrack(track)
	return &result, nil
}

func (c *DeezerClient) fetchFullTrack(ctx context.Context, trackID string) (*deezerTrack, error) {
	trackURL := fmt.Sprintf(deezerTrackURL, trackID)
	var track deezerTrack
	if err := c.getJSON(ctx, trackURL, &track); err != nil {
		return nil, err
	}
	return &track, nil
}

func (c *DeezerClient) fetchISRCsParallel(ctx context.Context, tracks []deezerTrack) map[string]string {
	result := make(map[string]string, len(tracks))
	var resultMu sync.Mutex

	var tracksToFetch []deezerTrack
	var directISRCs map[string]string
	c.cacheMu.RLock()
	for _, track := range tracks {
		trackIDStr := fmt.Sprintf("%d", track.ID)
		if track.ISRC != "" {
			result[trackIDStr] = track.ISRC
			if _, ok := c.isrcCache[trackIDStr]; !ok {
				if directISRCs == nil {
					directISRCs = make(map[string]string)
				}
				directISRCs[trackIDStr] = track.ISRC
			}
			continue
		}
		if isrc, ok := c.isrcCache[trackIDStr]; ok {
			result[trackIDStr] = isrc
		} else {
			tracksToFetch = append(tracksToFetch, track)
		}
	}
	c.cacheMu.RUnlock()
	if len(directISRCs) > 0 {
		c.cacheMu.Lock()
		for trackIDStr, isrc := range directISRCs {
			c.isrcCache[trackIDStr] = isrc
		}
		c.maybeCleanupCachesLocked(time.Now())
		c.cacheMu.Unlock()
	}

	if len(tracksToFetch) == 0 {
		return result
	}

	sem := make(chan struct{}, deezerMaxParallelISRC)
	var wg sync.WaitGroup

	for _, track := range tracksToFetch {
		wg.Add(1)
		go func(t deezerTrack) {
			defer wg.Done()

			select {
			case sem <- struct{}{}:
				defer func() { <-sem }()
			case <-ctx.Done():
				return
			}

			trackIDStr := fmt.Sprintf("%d", t.ID)
			fullTrack, err := c.fetchFullTrack(ctx, trackIDStr)
			if err != nil || fullTrack == nil {
				return
			}

			resultMu.Lock()
			result[trackIDStr] = fullTrack.ISRC
			resultMu.Unlock()

			c.cacheMu.Lock()
			c.isrcCache[trackIDStr] = fullTrack.ISRC
			c.maybeCleanupCachesLocked(time.Now())
			c.cacheMu.Unlock()
		}(track)
	}

	wg.Wait()
	return result
}

func (c *DeezerClient) GetTrackISRC(ctx context.Context, trackID string) (string, error) {
	c.cacheMu.RLock()
	if isrc, ok := c.isrcCache[trackID]; ok {
		c.cacheMu.RUnlock()
		return isrc, nil
	}
	c.cacheMu.RUnlock()

	fullTrack, err := c.fetchFullTrack(ctx, trackID)
	if err != nil {
		return "", err
	}

	c.cacheMu.Lock()
	c.isrcCache[trackID] = fullTrack.ISRC
	c.maybeCleanupCachesLocked(time.Now())
	c.cacheMu.Unlock()

	return fullTrack.ISRC, nil
}

type AlbumExtendedMetadata struct {
	Genre     string
	Label     string
	Copyright string
}

func (c *DeezerClient) GetAlbumExtendedMetadata(ctx context.Context, albumID string) (*AlbumExtendedMetadata, error) {
	if albumID == "" {
		return nil, fmt.Errorf("empty album ID")
	}

	cacheKey := fmt.Sprintf("album_meta:%s", albumID)
	c.cacheMu.RLock()
	if entry, ok := c.searchCache[cacheKey]; ok && !entry.isExpired() {
		c.cacheMu.RUnlock()
		return entry.data.(*AlbumExtendedMetadata), nil
	}
	c.cacheMu.RUnlock()

	albumURL := fmt.Sprintf(deezerAlbumURL, albumID)

	var album deezerAlbumFull
	if err := c.getJSON(ctx, albumURL, &album); err != nil {
		return nil, fmt.Errorf("failed to fetch album: %w", err)
	}

	var genres []string
	for _, g := range album.Genres.Data {
		if g.Name != "" {
			genres = append(genres, g.Name)
		}
	}

	result := &AlbumExtendedMetadata{
		Genre:     strings.Join(genres, ", "),
		Label:     album.Label,
		Copyright: album.Copyright,
	}

	c.cacheMu.Lock()
	now := time.Now()
	c.searchCache[cacheKey] = &cacheEntry{
		data:      result,
		expiresAt: now.Add(deezerCacheTTL),
	}
	c.maybeCleanupCachesLocked(now)
	c.cacheMu.Unlock()

	GoLog("[Deezer] Album metadata fetched - Genre: %s, Label: %s, Copyright: %s\n", result.Genre, result.Label, result.Copyright)

	return result, nil
}

func (c *DeezerClient) GetTrackAlbumID(ctx context.Context, trackID string) (string, error) {
	trackURL := fmt.Sprintf(deezerTrackURL, trackID)

	var track deezerTrack
	if err := c.getJSON(ctx, trackURL, &track); err != nil {
		return "", err
	}

	return fmt.Sprintf("%d", track.Album.ID), nil
}

func (c *DeezerClient) GetExtendedMetadataByTrackID(ctx context.Context, trackID string) (*AlbumExtendedMetadata, error) {
	albumID, err := c.GetTrackAlbumID(ctx, trackID)
	if err != nil {
		return nil, fmt.Errorf("failed to get album ID: %w", err)
	}

	return c.GetAlbumExtendedMetadata(ctx, albumID)
}

func (c *DeezerClient) GetExtendedMetadataByISRC(ctx context.Context, isrc string) (*AlbumExtendedMetadata, error) {
	if isrc == "" {
		return nil, fmt.Errorf("empty ISRC")
	}

	track, err := c.SearchByISRC(ctx, isrc)
	if err != nil {
		return nil, fmt.Errorf("failed to find track by ISRC: %w", err)
	}

	deezerID := strings.TrimPrefix(track.SpotifyID, "deezer:")

	if deezerID == "" {
		return nil, fmt.Errorf("track found but no Deezer ID")
	}

	return c.GetExtendedMetadataByTrackID(ctx, deezerID)
}

func (c *DeezerClient) getJSON(ctx context.Context, endpoint string, dst any) error {
	var lastErr error

	for attempt := 0; attempt <= deezerMaxRetries; attempt++ {
		if attempt > 0 {
			delay := deezerRetryDelay * time.Duration(1<<(attempt-1))
			var apiErr *deezerAPIError
			if errors.As(lastErr, &apiErr) && apiErr.RetryAfter > 0 {
				delay = apiErr.RetryAfter
			}
			GoLog("[Deezer] Retry %d/%d after %v...\n", attempt, deezerMaxRetries, delay)
			time.Sleep(delay)
		}

		err := c.doGetJSON(ctx, endpoint, dst)
		if err == nil {
			return nil
		}

		lastErr = err
		if !isDeezerRetryableError(err) {
			return err
		}

		GoLog("[Deezer] Attempt %d failed (retryable): %v\n", attempt+1, err)
	}

	return fmt.Errorf("all %d attempts failed: %w", deezerMaxRetries+1, lastErr)
}

type deezerAPIError struct {
	StatusCode int
	Body       string
	RetryAfter time.Duration
}

func (e *deezerAPIError) Error() string {
	return fmt.Sprintf("deezer API returned status %d: %s", e.StatusCode, e.Body)
}

func isDeezerRetryableError(err error) bool {
	if isConnectivityFailure(err) || errors.Is(err, io.ErrUnexpectedEOF) {
		return true
	}
	var apiErr *deezerAPIError
	if errors.As(err, &apiErr) {
		return apiErr.StatusCode == http.StatusTooManyRequests || apiErr.StatusCode >= http.StatusInternalServerError
	}
	return false
}

func (c *DeezerClient) doGetJSON(ctx context.Context, endpoint string, dst any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}

	req.Header.Set("Accept", "application/json")
	// Without an explicit language Deezer localizes artist/genre names by
	// the caller's IP geolocation (issue #480: Arabic metadata on an
	// English device). Follow the app's display language instead.
	req.Header.Set("Accept-Language", metadataAcceptLanguage())

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	if resp.StatusCode != http.StatusOK {
		return &deezerAPIError{StatusCode: resp.StatusCode, Body: string(body), RetryAfter: getRetryAfterDuration(resp)}
	}

	return json.Unmarshal(body, dst)
}

func parseDeezerURL(input string) (string, string, error) {
	trimmed := strings.TrimSpace(input)
	if trimmed == "" {
		return "", "", fmt.Errorf("empty URL")
	}

	parsed, err := url.Parse(trimmed)
	if err != nil {
		return "", "", err
	}

	if parsed.Host != "www.deezer.com" && parsed.Host != "deezer.com" && parsed.Host != "deezer.page.link" {
		return "", "", fmt.Errorf("not a Deezer URL")
	}

	parts := strings.Split(strings.Trim(parsed.Path, "/"), "/")

	if len(parts) > 0 && len(parts[0]) == 2 {
		parts = parts[1:]
	}

	if len(parts) < 2 {
		return "", "", fmt.Errorf("invalid Deezer URL format")
	}

	resourceType := parts[0]
	resourceID := parts[1]

	switch resourceType {
	case "track", "album", "artist", "playlist":
		return resourceType, resourceID, nil
	default:
		return "", "", fmt.Errorf("unsupported Deezer resource type: %s", resourceType)
	}
}
