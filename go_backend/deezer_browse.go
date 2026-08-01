package gobackend

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"time"
)

func (c *DeezerClient) GetAlbum(ctx context.Context, albumID string) (*AlbumResponsePayload, error) {
	c.cacheMu.RLock()
	if entry, ok := c.albumCache[albumID]; ok && !entry.isExpired() {
		c.cacheMu.RUnlock()
		return entry.data.(*AlbumResponsePayload), nil
	}
	c.cacheMu.RUnlock()

	albumURL := fmt.Sprintf(deezerAlbumURL, albumID)

	var album deezerAlbumFull
	if err := c.getJSON(ctx, albumURL, &album); err != nil {
		return nil, err
	}

	albumImage := c.getBestAlbumImage(album)
	artistName := album.Artist.Name
	if len(album.Contributors) > 0 {
		names := make([]string, len(album.Contributors))
		for i, a := range album.Contributors {
			names[i] = a.Name
		}
		artistName = strings.Join(names, ", ")
	}

	var genres []string
	for _, g := range album.Genres.Data {
		if g.Name != "" {
			genres = append(genres, g.Name)
		}
	}
	genreStr := strings.Join(genres, ", ")

	info := AlbumInfoMetadata{
		TotalTracks: album.NbTracks,
		Name:        album.Title,
		ReleaseDate: album.ReleaseDate,
		Artists:     artistName,
		ArtistId:    fmt.Sprintf("deezer:%d", album.Artist.ID),
		Images:      albumImage,
		Genre:       genreStr,
		Label:       album.Label,
	}

	allTracks := album.Tracks.Data

	if album.NbTracks > len(allTracks) {
		GoLog("[Deezer] Album has %d tracks but only got %d, fetching remaining...", album.NbTracks, len(allTracks))

		tracksURL := fmt.Sprintf("%s/tracks?limit=100&index=%d", fmt.Sprintf(deezerAlbumURL, albumID), len(allTracks))

		for len(allTracks) < album.NbTracks {
			var tracksResp struct {
				Data []deezerTrack `json:"data"`
				Next string        `json:"next"`
			}

			if err := c.getJSON(ctx, tracksURL, &tracksResp); err != nil {
				GoLog("[Deezer] Warning: failed to fetch album tracks page: %v", err)
				break
			}

			if len(tracksResp.Data) == 0 {
				break
			}

			allTracks = append(allTracks, tracksResp.Data...)

			if tracksResp.Next == "" {
				break
			}
			tracksURL = tracksResp.Next
		}

		GoLog("[Deezer] Fetched total %d tracks for album", len(allTracks))
	}

	isrcMap := c.fetchISRCsParallel(ctx, allTracks)
	totalDiscs := 0
	for _, track := range allTracks {
		if track.DiskNumber > totalDiscs {
			totalDiscs = track.DiskNumber
		}
	}

	tracks := make([]AlbumTrackMetadata, 0, len(allTracks))
	albumType := album.RecordType
	if albumType == "compile" {
		albumType = "compilation"
	}

	for i, track := range allTracks {
		trackIDStr := fmt.Sprintf("%d", track.ID)
		isrc := isrcMap[trackIDStr]

		trackNum := track.TrackPosition
		if trackNum == 0 {
			trackNum = i + 1
		}

		tracks = append(tracks, AlbumTrackMetadata{
			SpotifyID:   fmt.Sprintf("deezer:%d", track.ID),
			Artists:     deezerTrackArtistDisplay(track),
			Name:        track.Title,
			AlbumName:   album.Title,
			AlbumArtist: artistName,
			DurationMS:  track.Duration * 1000,
			Images:      albumImage,
			ReleaseDate: album.ReleaseDate,
			TrackNumber: trackNum,
			TotalTracks: album.NbTracks,
			DiscNumber:  track.DiskNumber,
			TotalDiscs:  totalDiscs,
			ExternalURL: track.Link,
			ISRC:        isrc,
			AlbumID:     fmt.Sprintf("deezer:%d", album.ID),
			AlbumType:   albumType,
			Explicit:    deezerTrackIsExplicit(track),
		})
	}

	result := &AlbumResponsePayload{
		AlbumInfo: info,
		TrackList: tracks,
	}

	c.cacheMu.Lock()
	now := time.Now()
	c.albumCache[albumID] = &cacheEntry{
		data:      result,
		expiresAt: now.Add(deezerCacheTTL),
	}
	c.maybeCleanupCachesLocked(now)
	c.cacheMu.Unlock()

	return result, nil
}

func (c *DeezerClient) GetArtist(ctx context.Context, artistID string) (*ArtistResponsePayload, error) {
	c.cacheMu.RLock()
	if entry, ok := c.artistCache[artistID]; ok && !entry.isExpired() {
		c.cacheMu.RUnlock()
		return entry.data.(*ArtistResponsePayload), nil
	}
	c.cacheMu.RUnlock()

	artistURL := fmt.Sprintf(deezerArtistURL, artistID)
	var artist deezerArtistFull
	if err := c.getJSON(ctx, artistURL, &artist); err != nil {
		return nil, err
	}

	artistInfo := ArtistInfoMetadata{
		ID:         fmt.Sprintf("deezer:%d", artist.ID),
		Name:       artist.Name,
		Images:     c.getBestArtistImageFull(artist),
		Followers:  artist.NbFan,
		Popularity: 0,
	}

	albumsURL := fmt.Sprintf("%s/albums?limit=100", fmt.Sprintf(deezerArtistURL, artistID))
	var albumsResp struct {
		Data []struct {
			ID          int64  `json:"id"`
			Title       string `json:"title"`
			ReleaseDate string `json:"release_date"`
			NbTracks    int    `json:"nb_tracks"`
			Cover       string `json:"cover"`
			CoverMedium string `json:"cover_medium"`
			CoverBig    string `json:"cover_big"`
			CoverXL     string `json:"cover_xl"`
			RecordType  string `json:"record_type"`
		} `json:"data"`
	}

	albums := make([]ArtistAlbumMetadata, 0)
	if err := c.getJSON(ctx, albumsURL, &albumsResp); err == nil {
		for _, album := range albumsResp.Data {
			albumType := album.RecordType
			if albumType == "compile" {
				albumType = "compilation"
			}

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

			albums = append(albums, ArtistAlbumMetadata{
				ID:          fmt.Sprintf("deezer:%d", album.ID),
				Name:        album.Title,
				ReleaseDate: album.ReleaseDate,
				TotalTracks: album.NbTracks,
				Images:      coverURL,
				AlbumType:   albumType,
				Artists:     artist.Name,
			})
		}

		// The Deezer /artist/{id}/albums endpoint does not return nb_tracks.
		// Fetch track counts in parallel from individual /album/{id} endpoints.
		c.fetchAlbumTrackCounts(ctx, albums)
	}

	result := &ArtistResponsePayload{
		ArtistInfo: artistInfo,
		Albums:     albums,
	}

	c.cacheMu.Lock()
	now := time.Now()
	c.artistCache[artistID] = &cacheEntry{
		data:      result,
		expiresAt: now.Add(deezerCacheTTL),
	}
	c.maybeCleanupCachesLocked(now)
	c.cacheMu.Unlock()

	return result, nil
}

// fetchAlbumTrackCounts fetches nb_tracks for each album in parallel using
// individual /album/{id} calls, since the /artist/{id}/albums endpoint does
// not include this field. Albums whose track count is already known (non-zero)
// are skipped.
func (c *DeezerClient) fetchAlbumTrackCounts(ctx context.Context, albums []ArtistAlbumMetadata) {
	type indexedID struct {
		idx     int
		albumID string
	}
	var toFetch []indexedID
	for i, a := range albums {
		if a.TotalTracks == 0 {
			rawID := strings.TrimPrefix(a.ID, "deezer:")
			if rawID != "" {
				toFetch = append(toFetch, indexedID{idx: i, albumID: rawID})
			}
		}
	}
	if len(toFetch) == 0 {
		return
	}

	const maxParallel = 10
	sem := make(chan struct{}, maxParallel)
	var mu sync.Mutex
	var wg sync.WaitGroup

	for _, item := range toFetch {
		wg.Add(1)
		go func(it indexedID) {
			defer wg.Done()

			select {
			case sem <- struct{}{}:
				defer func() { <-sem }()
			case <-ctx.Done():
				return
			}

			albumURL := fmt.Sprintf(deezerAlbumURL, it.albumID)
			var resp struct {
				NbTracks int `json:"nb_tracks"`
			}
			if err := c.getJSON(ctx, albumURL, &resp); err != nil {
				return
			}

			mu.Lock()
			albums[it.idx].TotalTracks = resp.NbTracks
			mu.Unlock()
		}(item)
	}

	wg.Wait()
}

func (c *DeezerClient) GetPlaylist(ctx context.Context, playlistID string) (*PlaylistResponsePayload, error) {
	playlistURL := fmt.Sprintf(deezerPlaylistURL, playlistID)

	var playlist deezerPlaylistFull
	if err := c.getJSON(ctx, playlistURL, &playlist); err != nil {
		return nil, err
	}

	playlistImage := playlist.PictureXL
	if playlistImage == "" {
		playlistImage = playlist.PictureBig
	}
	if playlistImage == "" {
		playlistImage = playlist.PictureMedium
	}

	var info PlaylistInfoMetadata
	info.Tracks.Total = playlist.NbTracks
	info.Owner.DisplayName = playlist.Creator.Name
	info.Owner.Name = playlist.Title
	info.Owner.Images = playlistImage

	allTracks := playlist.Tracks.Data

	if playlist.NbTracks > len(allTracks) {
		GoLog("[Deezer] Playlist has %d tracks but only got %d, fetching remaining...", playlist.NbTracks, len(allTracks))

		tracksURL := fmt.Sprintf("%s/tracks?limit=100&index=%d", fmt.Sprintf(deezerPlaylistURL, playlistID), len(allTracks))

		for len(allTracks) < playlist.NbTracks {
			var tracksResp struct {
				Data []deezerTrack `json:"data"`
				Next string        `json:"next"`
			}

			if err := c.getJSON(ctx, tracksURL, &tracksResp); err != nil {
				GoLog("[Deezer] Warning: failed to fetch playlist tracks page: %v", err)
				break
			}

			if len(tracksResp.Data) == 0 {
				break
			}

			allTracks = append(allTracks, tracksResp.Data...)

			if tracksResp.Next == "" {
				break
			}
			tracksURL = tracksResp.Next
		}

		GoLog("[Deezer] Fetched total %d tracks for playlist", len(allTracks))
	}

	isrcMap := c.fetchISRCsParallel(ctx, allTracks)

	tracks := make([]AlbumTrackMetadata, 0, len(allTracks))
	for _, track := range allTracks {
		albumImage := track.Album.CoverXL
		if albumImage == "" {
			albumImage = track.Album.CoverBig
		}
		if albumImage == "" {
			albumImage = track.Album.CoverMedium
		}

		trackIDStr := fmt.Sprintf("%d", track.ID)
		isrc := isrcMap[trackIDStr]

		tracks = append(tracks, AlbumTrackMetadata{
			SpotifyID:   fmt.Sprintf("deezer:%d", track.ID),
			Artists:     deezerTrackArtistDisplay(track),
			Name:        track.Title,
			AlbumName:   track.Album.Title,
			AlbumArtist: track.Artist.Name,
			DurationMS:  track.Duration * 1000,
			Images:      albumImage,
			ReleaseDate: "",
			TrackNumber: track.TrackPosition,
			DiscNumber:  track.DiskNumber,
			ExternalURL: track.Link,
			ISRC:        isrc,
			AlbumID:     fmt.Sprintf("deezer:%d", track.Album.ID),
			Explicit:    deezerTrackIsExplicit(track),
		})
	}

	return &PlaylistResponsePayload{
		PlaylistInfo: info,
		TrackList:    tracks,
	}, nil
}
