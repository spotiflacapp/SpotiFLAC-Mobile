package gobackend

import (
	"context"
	"fmt"
	"strings"
	"time"
)

// GetTrackCacheSize and ClearTrackIDCache back the Settings cache screen. The
// track-ID cache is currently a no-op, so these report an empty cache and clear
// nothing, but the gomobile export contract is kept for the Dart/Kotlin callers.
func GetTrackCacheSize() int {
	return 0
}

func ClearTrackIDCache() {
}

func GetDeezerMetadata(resourceType, resourceID string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	client := GetDeezerClient()
	var data any
	var err error

	switch resourceType {
	case "track":
		data, err = client.GetTrack(ctx, resourceID)
	case "album":
		data, err = client.GetAlbum(ctx, resourceID)
	case "artist":
		data, err = client.GetArtist(ctx, resourceID)
	case "playlist":
		data, err = client.GetPlaylist(ctx, resourceID)
	default:
		return "", fmt.Errorf("unsupported Deezer resource type: %s", resourceType)
	}

	if err != nil {
		return "", err
	}

	return marshalJSONString(data)
}

func GetDeezerExtendedMetadata(trackID string) (string, error) {
	if trackID == "" {
		return "", fmt.Errorf("empty track ID")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	client := GetDeezerClient()
	metadata, err := client.GetExtendedMetadataByTrackID(ctx, trackID)
	if err != nil {
		GoLog("[Deezer] Failed to get extended metadata: %v\n", err)
		return "", err
	}

	result := buildDeezerExtendedMetadataResult(metadata)

	return marshalJSONString(result)
}

func SearchDeezerByISRC(isrc string) (string, error) {
	return SearchDeezerByISRCForItemID(isrc, "")
}

func SearchDeezerByISRCForItemID(isrc string, itemID string) (string, error) {
	parentCtx := context.Background()
	if itemID != "" {
		parentCtx = initDownloadCancel(itemID)
		defer clearDownloadCancel(itemID)
		if isDownloadCancelled(itemID) {
			return "", ErrDownloadCancelled
		}
	}

	ctx, cancel := context.WithTimeout(parentCtx, 10*time.Second)
	defer cancel()

	client := GetDeezerClient()
	track, err := client.SearchByISRC(ctx, isrc)
	if err != nil {
		if isDownloadCancelled(itemID) {
			return "", ErrDownloadCancelled
		}
		return "", err
	}
	if isDownloadCancelled(itemID) {
		return "", ErrDownloadCancelled
	}

	result := buildDeezerISRCSearchResult(track)
	return marshalJSONString(result)
}

func buildDeezerExtendedMetadataResult(metadata *AlbumExtendedMetadata) map[string]string {
	if metadata == nil {
		return map[string]string{
			"genre":     "",
			"label":     "",
			"copyright": "",
		}
	}

	return map[string]string{
		"genre":     metadata.Genre,
		"label":     metadata.Label,
		"copyright": metadata.Copyright,
	}
}

func buildDeezerISRCSearchResult(track *TrackMetadata) map[string]any {
	if track == nil {
		return map[string]any{}
	}

	result := map[string]any{
		"spotify_id":    track.SpotifyID,
		"artists":       track.Artists,
		"name":          track.Name,
		"album_name":    track.AlbumName,
		"album_artist":  track.AlbumArtist,
		"duration_ms":   track.DurationMS,
		"images":        track.Images,
		"release_date":  track.ReleaseDate,
		"track_number":  track.TrackNumber,
		"total_tracks":  track.TotalTracks,
		"disc_number":   track.DiscNumber,
		"total_discs":   track.TotalDiscs,
		"external_urls": track.ExternalURL,
		"isrc":          track.ISRC,
		"album_id":      track.AlbumID,
		"artist_id":     track.ArtistID,
		"album_type":    track.AlbumType,
		"composer":      track.Composer,
	}

	if deezerID := strings.TrimSpace(strings.TrimPrefix(track.SpotifyID, "deezer:")); deezerID != "" {
		result["id"] = deezerID
		result["track_id"] = deezerID
		result["success"] = true
	}

	return result
}

func ConvertSpotifyToDeezer(resourceType, spotifyID string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	songlink := NewSongLinkClient()
	deezerClient := GetDeezerClient()

	if resourceType == "track" {
		deezerID, err := songlink.GetDeezerIDFromSpotify(spotifyID)
		if err != nil {
			return "", fmt.Errorf("could not find Deezer equivalent: %w", err)
		}

		trackResp, err := deezerClient.GetTrack(ctx, deezerID)
		if err != nil {
			return "", fmt.Errorf("failed to fetch Deezer metadata: %w", err)
		}

		return marshalJSONString(trackResp)
	}

	if resourceType == "album" {
		deezerID, err := songlink.GetDeezerAlbumIDFromSpotify(spotifyID)
		if err != nil {
			return "", fmt.Errorf("could not find Deezer album: %w", err)
		}

		albumResp, err := deezerClient.GetAlbum(ctx, deezerID)
		if err != nil {
			return "", fmt.Errorf("failed to fetch Deezer album metadata: %w", err)
		}

		return marshalJSONString(albumResp)
	}

	return "", fmt.Errorf("spotify to Deezer conversion only supported for tracks and albums: please search by name for %s", resourceType)
}

func GetSpotifyIDFromDeezerTrack(deezerTrackID string) (string, error) {
	client := NewSongLinkClient()
	return client.GetSpotifyIDFromDeezer(deezerTrackID)
}

func GetTidalURLFromDeezerTrack(deezerTrackID string) (string, error) {
	client := NewSongLinkClient()
	return client.GetTidalURLFromDeezer(deezerTrackID)
}
