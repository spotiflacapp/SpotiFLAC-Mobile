package gobackend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/dop251/goja"
)

func normalizeExtensionTrackMetadataMap(
	track ExtTrackMetadata,
	fallbackCover string,
	fallbackTrackNumber int,
) map[string]any {
	coverURL := track.ResolvedCoverURL()
	if coverURL == "" {
		coverURL = fallbackCover
	}

	trackNum := track.TrackNumber
	if trackNum == 0 && fallbackTrackNumber > 0 {
		trackNum = fallbackTrackNumber
	}

	return map[string]any{
		"id":            track.ID,
		"name":          track.Name,
		"artists":       track.Artists,
		"album_name":    track.AlbumName,
		"album_artist":  track.AlbumArtist,
		"album_id":      track.AlbumID,
		"album_url":     track.AlbumURL,
		"artist_id":     track.ArtistID,
		"artist_url":    track.ArtistURL,
		"external_urls": track.ExternalURL,
		"duration_ms":   track.DurationMS,
		"images":        coverURL,
		"cover_url":     coverURL,
		"preview_url":   track.PreviewURL,
		"release_date":  track.ReleaseDate,
		"track_number":  trackNum,
		"total_tracks":  track.TotalTracks,
		"disc_number":   track.DiscNumber,
		"total_discs":   track.TotalDiscs,
		"isrc":          track.ISRC,
		"provider_id":   track.ProviderID,
		"item_type":     track.ItemType,
		"album_type":    track.AlbumType,
		"spotify_id":    track.SpotifyID,
		"composer":      track.Composer,
		"audio_quality": track.AudioQuality,
		"audio_modes":   track.AudioModes,
		"explicit":      track.Explicit,
	}
}

func normalizeExtensionAlbumInfoMap(album *ExtAlbumMetadata) map[string]any {
	if album == nil {
		return map[string]any{}
	}

	return map[string]any{
		"id":           album.ID,
		"name":         album.Name,
		"artists":      album.Artists,
		"artist_id":    album.ArtistID,
		"images":       album.CoverURL,
		"cover_url":    album.CoverURL,
		"header_image": album.HeaderImage,
		"header_video": album.HeaderVideo,
		"release_date": album.ReleaseDate,
		"total_tracks": album.TotalTracks,
		"album_type":   album.AlbumType,
		"audio_traits": album.AudioTraits,
		"provider_id":  album.ProviderID,
	}
}

func normalizeExtensionArtistAlbumMap(album ExtAlbumMetadata) map[string]any {
	return map[string]any{
		"id":           album.ID,
		"name":         album.Name,
		"artists":      album.Artists,
		"images":       album.CoverURL,
		"cover_url":    album.CoverURL,
		"release_date": album.ReleaseDate,
		"total_tracks": album.TotalTracks,
		"album_type":   album.AlbumType,
		"provider_id":  album.ProviderID,
	}
}

func getExtensionProviderMetadataResponse(
	providerID,
	resourceType,
	resourceID string,
) (map[string]any, error) {
	manager := getExtensionManager()
	ext, err := manager.GetExtension(providerID)
	if err != nil {
		return nil, err
	}

	if !ext.Manifest.IsMetadataProvider() {
		return nil, fmt.Errorf("extension '%s' is not a metadata provider", providerID)
	}
	if !ext.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", providerID)
	}

	provider := newExtensionProviderWrapper(ext)

	switch resourceType {
	case "track":
		track, err := provider.GetTrack(resourceID)
		if err != nil {
			return nil, err
		}
		if track == nil {
			return nil, fmt.Errorf("track not found")
		}
		return map[string]any{
			"track": normalizeExtensionTrackMetadataMap(*track, "", 0),
		}, nil
	case "album":
		album, err := provider.GetAlbum(resourceID)
		if err != nil {
			return nil, err
		}
		if album == nil {
			return nil, fmt.Errorf("album not found")
		}

		tracks := make([]map[string]any, len(album.Tracks))
		for i, track := range album.Tracks {
			tracks[i] = normalizeExtensionTrackMetadataMap(track, album.CoverURL, i+1)
		}

		return map[string]any{
			"album_info": normalizeExtensionAlbumInfoMap(album),
			"track_list": tracks,
		}, nil
	case "playlist":
		playlist, err := provider.GetPlaylist(resourceID)
		if err != nil {
			return nil, err
		}
		if playlist == nil {
			return nil, fmt.Errorf("playlist not found")
		}

		tracks := make([]map[string]any, len(playlist.Tracks))
		for i, track := range playlist.Tracks {
			tracks[i] = normalizeExtensionTrackMetadataMap(track, playlist.CoverURL, i+1)
		}

		return map[string]any{
			"playlist_info": map[string]any{
				"id":           playlist.ID,
				"name":         playlist.Name,
				"images":       playlist.CoverURL,
				"cover_url":    playlist.CoverURL,
				"header_image": playlist.HeaderImage,
				"header_video": playlist.HeaderVideo,
				"provider_id":  playlist.ProviderID,
				"owner": map[string]any{
					"name":   playlist.Artists,
					"images": playlist.CoverURL,
				},
			},
			"track_list": tracks,
		}, nil
	case "artist":
		artist, err := provider.GetArtist(resourceID)
		if err != nil {
			return nil, err
		}
		if artist == nil {
			return nil, fmt.Errorf("artist not found")
		}

		albums := make([]map[string]any, len(artist.Albums))
		for i, album := range artist.Albums {
			albums[i] = normalizeExtensionArtistAlbumMap(album)
		}

		response := map[string]any{
			"artist_info": map[string]any{
				"id":           artist.ID,
				"name":         artist.Name,
				"images":       firstNonEmptyTrimmed(artist.HeaderImage, artist.ImageURL),
				"cover_url":    artist.ImageURL,
				"header_image": artist.HeaderImage,
				"header_video": artist.HeaderVideo,
				"provider_id":  artist.ProviderID,
			},
			"albums": albums,
		}

		if len(artist.Releases) > 0 {
			releases := make([]map[string]any, len(artist.Releases))
			for i, release := range artist.Releases {
				releases[i] = normalizeExtensionArtistAlbumMap(release)
			}
			response["releases"] = releases
		}

		if artist.Listeners > 0 {
			artistInfo := response["artist_info"].(map[string]any)
			artistInfo["listeners"] = artist.Listeners
		}

		if len(artist.TopTracks) > 0 {
			topTracks := make([]map[string]any, len(artist.TopTracks))
			for i, track := range artist.TopTracks {
				topTracks[i] = normalizeExtensionTrackMetadataMap(track, artist.ImageURL, i+1)
			}
			response["top_tracks"] = topTracks
		}

		return response, nil
	default:
		return nil, fmt.Errorf("unsupported provider resource type: %s", resourceType)
	}
}

func firstNonEmptyTrimmed(values ...string) string {
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			return trimmed
		}
	}
	return ""
}

func GetProviderMetadataJSON(providerID, resourceType, resourceID string) (string, error) {
	trimmedProviderID := strings.TrimSpace(providerID)
	if trimmedProviderID == "" {
		return "", fmt.Errorf("empty provider ID")
	}

	switch strings.ToLower(trimmedProviderID) {
	case "deezer":
		if response, ok, err := getEnabledExtensionProviderMetadataResponse(trimmedProviderID, resourceType, resourceID); ok || err != nil {
			if err != nil {
				return "", err
			}
			return marshalJSONString(response)
		}
		return GetDeezerMetadata(resourceType, resourceID)
	default:
		response, err := getExtensionProviderMetadataResponse(trimmedProviderID, resourceType, resourceID)
		if err != nil {
			return "", err
		}

		return marshalJSONString(response)
	}
}

func getEnabledExtensionProviderMetadataResponse(providerID, resourceType, resourceID string) (map[string]any, bool, error) {
	manager := getExtensionManager()
	ext, err := manager.GetExtension(providerID)
	if err != nil || ext == nil || !ext.Enabled || !ext.Manifest.IsMetadataProvider() {
		return nil, false, nil
	}
	response, err := getExtensionProviderMetadataResponse(providerID, resourceType, resourceID)
	if err != nil {
		return nil, true, err
	}
	return response, true, nil
}

func InitExtensionSystem(extensionsDir, dataDir string) error {
	manager := getExtensionManager()
	if err := manager.SetDirectories(extensionsDir, dataDir); err != nil {
		return err
	}

	settingsStore := GetExtensionSettingsStore()
	if err := settingsStore.SetDataDir(dataDir); err != nil {
		return err
	}

	return nil
}

func LoadExtensionsFromDir(dirPath string) (string, error) {
	manager := getExtensionManager()
	loaded, errors := manager.LoadExtensionsFromDirectory(dirPath)

	result := map[string]any{
		"loaded": loaded,
		"errors": make([]string, len(errors)),
	}

	for i, err := range errors {
		result["errors"].([]string)[i] = err.Error()
	}

	return marshalJSONString(result)
}

func LoadExtensionFromPath(filePath string) (string, error) {
	manager := getExtensionManager()
	ext, err := manager.LoadExtensionFromFile(filePath)
	if err != nil {
		return "", err
	}

	result := map[string]any{
		"id":           ext.ID,
		"name":         ext.Manifest.Name,
		"display_name": ext.Manifest.DisplayName,
		"version":      ext.Manifest.Version,
		"enabled":      ext.Enabled,
	}

	return marshalJSONString(result)
}

func UnloadExtensionByID(extensionID string) error {
	manager := getExtensionManager()
	return manager.UnloadExtension(extensionID)
}

func RemoveExtensionByID(extensionID string) error {
	manager := getExtensionManager()
	return manager.RemoveExtension(extensionID)
}

func UpgradeExtensionFromPath(filePath string) (string, error) {
	manager := getExtensionManager()
	ext, err := manager.UpgradeExtension(filePath)
	if err != nil {
		return "", err
	}

	result := map[string]any{
		"id":           ext.ID,
		"display_name": ext.Manifest.DisplayName,
		"version":      ext.Manifest.Version,
		"enabled":      ext.Enabled,
	}

	return marshalJSONString(result)
}

func CheckExtensionUpgradeFromPath(filePath string) (string, error) {
	manager := getExtensionManager()
	return manager.CheckExtensionUpgradeJSON(filePath)
}

func GetInstalledExtensions() (string, error) {
	manager := getExtensionManager()
	return manager.GetInstalledExtensionsJSON()
}

func SetExtensionEnabledByID(extensionID string, enabled bool) error {
	manager := getExtensionManager()
	return manager.SetExtensionEnabled(extensionID, enabled)
}

func SetProviderPriorityJSON(priorityJSON string) error {
	var priority []string
	if err := json.Unmarshal([]byte(priorityJSON), &priority); err != nil {
		return err
	}

	SetProviderPriority(priority)
	return nil
}

func GetProviderPriorityJSON() (string, error) {
	priority := GetProviderPriority()
	return marshalJSONString(priority)
}

func SetExtensionFallbackProviderIDsJSON(providerIDsJSON string) error {
	if strings.TrimSpace(providerIDsJSON) == "" {
		SetExtensionFallbackProviderIDs(nil)
		return nil
	}

	var providerIDs []string
	if err := json.Unmarshal([]byte(providerIDsJSON), &providerIDs); err != nil {
		return err
	}

	SetExtensionFallbackProviderIDs(providerIDs)
	return nil
}

func SetMetadataProviderPriorityJSON(priorityJSON string) error {
	var priority []string
	if err := json.Unmarshal([]byte(priorityJSON), &priority); err != nil {
		return err
	}

	SetMetadataProviderPriority(priority)
	return nil
}

func GetMetadataProviderPriorityJSON() (string, error) {
	priority := GetMetadataProviderPriority()
	return marshalJSONString(priority)
}

func GetExtensionSettingsJSON(extensionID string) (string, error) {
	store := GetExtensionSettingsStore()
	settings := store.GetAll(extensionID)

	return marshalJSONString(settings)
}

func SetExtensionSettingsJSON(extensionID, settingsJSON string) error {
	var settings map[string]any
	if err := json.Unmarshal([]byte(settingsJSON), &settings); err != nil {
		return err
	}

	store := GetExtensionSettingsStore()
	if err := store.SetAll(extensionID, settings); err != nil {
		return err
	}

	manager := getExtensionManager()
	return manager.InitializeExtension(extensionID, settings)
}

func SearchTracksWithMetadataProvidersJSON(query string, limit int, includeExtensions bool) (string, error) {
	manager := getExtensionManager()
	tracks, err := manager.SearchTracksWithMetadataProviders(query, limit, includeExtensions)
	if err != nil {
		return "", err
	}

	return marshalJSONString(tracks)
}

func SearchTracksWithMetadataProviderJSON(providerID, query string, limit int) (string, error) {
	manager := getExtensionManager()
	tracks, err := manager.SearchTracksWithMetadataProvider(providerID, query, limit)
	if err != nil {
		return "", err
	}

	return marshalJSONString(tracks)
}

func preflightExtensionDownloadSession(extensionID string) (bool, error) {
	extensionID = strings.TrimSpace(extensionID)
	if extensionID == "" {
		return false, nil
	}

	ext, err := getExtensionManager().GetExtension(extensionID)
	if err != nil || ext == nil || !ext.Enabled || ext.Manifest == nil ||
		!ext.Manifest.IsDownloadProvider() || ext.Manifest.SignedSession == nil {
		return false, nil
	}

	if _, err := ext.lockReadyVM(); err != nil {
		return false, err
	}
	defer ext.VMMu.Unlock()
	if ext.runtime == nil {
		return false, fmt.Errorf("extension '%s' runtime is unavailable", extensionID)
	}

	return ext.runtime.preflightSignedSession()
}

func DownloadWithExtensionsJSON(requestJSON string) (string, error) {
	var req DownloadRequest
	if err := json.Unmarshal([]byte(requestJSON), &req); err != nil {
		return "", fmt.Errorf("invalid request: %w", err)
	}
	applySongLinkRegionFromRequest(&req)
	defer closeOwnedOutputFD(req.OutputFD)
	if req.ItemID != "" {
		initDownloadCancel(req.ItemID)
		defer clearDownloadCancel(req.ItemID)
		if isDownloadCancelled(req.ItemID) {
			return "", ErrDownloadCancelled
		}
	}

	req.TrackName = strings.TrimSpace(req.TrackName)
	req.ArtistName = strings.TrimSpace(req.ArtistName)
	req.AlbumName = strings.TrimSpace(req.AlbumName)
	req.AlbumArtist = strings.TrimSpace(req.AlbumArtist)
	req.OutputDir = strings.TrimSpace(req.OutputDir)
	req.OutputPath = strings.TrimSpace(req.OutputPath)
	req.OutputExt = strings.TrimSpace(req.OutputExt)
	if req.OutputPath == "" && req.OutputFD <= 0 && req.OutputDir != "" {
		AddAllowedDownloadDir(req.OutputDir)
	}

	sessionProvider := strings.TrimSpace(req.Service)
	if sessionProvider == "" {
		sessionProvider = strings.TrimSpace(req.Source)
	}
	if req.ItemID != "" {
		StartItemProgress(req.ItemID)
		SetItemPreparingStage(req.ItemID, "checking_session")
	}
	preflightStartedAt := time.Now()
	verificationRequired, preflightErr := preflightExtensionDownloadSession(sessionProvider)
	if preflightErr != nil {
		message := fmt.Sprintf("Could not start verification for %s: %v", sessionProvider, preflightErr)
		GoLog("[DownloadWithExtensions] Signed-session preflight for %s failed after %s: %v\n", sessionProvider, time.Since(preflightStartedAt).Round(time.Millisecond), preflightErr)
		if req.ItemID != "" {
			RemoveItemProgress(req.ItemID)
		}
		return marshalJSONString(&DownloadResponse{
			Success:   false,
			Error:     message,
			ErrorType: classifyDownloadErrorType(message),
			Service:   sessionProvider,
		})
	} else if verificationRequired {
		GoLog("[DownloadWithExtensions] Signed-session verification required for %s after %s; skipping metadata preparation\n", sessionProvider, time.Since(preflightStartedAt).Round(time.Millisecond))
		cacheUnpreparedDownloadRequest(downloadPreparationKey(req), req)
		if req.ItemID != "" {
			RemoveItemProgress(req.ItemID)
		}
		return marshalJSONString(&DownloadResponse{
			Success:   false,
			Error:     "Verification required before download",
			ErrorType: "verification_required",
			Service:   sessionProvider,
		})
	} else if sessionProvider != "" {
		LogDebug("DownloadWithExtensions", "Signed-session preflight ready for %s in %s", sessionProvider, time.Since(preflightStartedAt).Round(time.Millisecond))
	}

	if isDownloadCancelled(req.ItemID) {
		if req.ItemID != "" {
			RemoveItemProgress(req.ItemID)
		}
		return "", ErrDownloadCancelled
	}

	result, err := DownloadWithExtensionFallback(req)
	if err != nil {
		if req.ItemID != "" {
			RemoveItemProgress(req.ItemID)
		}
		return "", err
	}
	if req.ItemID != "" && (result == nil || !result.Success) {
		RemoveItemProgress(req.ItemID)
	}

	return marshalJSONString(result)
}

func CleanupExtensions() {
	manager := getExtensionManager()
	manager.UnloadAllExtensions()
}

func InvokeExtensionActionJSON(extensionID, actionName string) (string, error) {
	manager := getExtensionManager()
	result, err := manager.InvokeAction(extensionID, actionName)
	if err != nil {
		return "", err
	}

	return marshalJSONString(result)
}

func GetExtensionPendingAuthJSON(extensionID string) (string, error) {
	req, err := ensureExtensionPendingAuthRequest(extensionID)
	if err != nil {
		return "", err
	}
	if req == nil {
		return "", nil
	}

	result := map[string]any{
		"extension_id": req.ExtensionID,
		"auth_url":     req.AuthURL,
		"callback_url": req.CallbackURL,
	}

	return marshalJSONString(result)
}

func ensureExtensionPendingAuthRequest(extensionID string) (*PendingAuthRequest, error) {
	extensionID = strings.TrimSpace(extensionID)
	if extensionID == "" {
		return nil, nil
	}

	if req := GetPendingAuthRequest(extensionID); req != nil {
		if time.Since(req.CreatedAt) < pendingAuthRequestTTL {
			return req, nil
		}
		// The cached challenge is stale (e.g. verification was requested
		// while the app was backgrounded and never completed); serving it
		// would send the user to an expired page. Start a fresh one.
		ClearPendingAuthRequest(extensionID)
	}

	manager := getExtensionManager()
	ext, err := manager.GetExtension(extensionID)
	if err != nil || ext == nil || !ext.Enabled || ext.Manifest == nil || ext.Manifest.SignedSession == nil {
		return nil, nil
	}

	if err := ext.ensureRuntimeReady(); err != nil {
		return nil, err
	}
	if ext.runtime == nil {
		return nil, fmt.Errorf("extension '%s' runtime is unavailable", extensionID)
	}

	verificationRequired, err := ext.runtime.preflightSignedSession()
	if err != nil {
		return nil, err
	}
	if !verificationRequired {
		return nil, nil
	}
	return GetPendingAuthRequest(extensionID), nil
}

func SetExtensionAuthCodeByID(extensionID, authCode string) {
	SetExtensionAuthCode(extensionID, authCode)
}

func SetExtensionSessionGrantByID(extensionID, grant string) {
	setPendingSignedSessionGrant(extensionID, grant)
}

func SetExtensionTokensByID(extensionID, accessToken, refreshToken string, expiresIn int) {
	var expiresAt time.Time
	if expiresIn > 0 {
		expiresAt = time.Now().Add(time.Duration(expiresIn) * time.Second)
	}
	SetExtensionTokens(extensionID, accessToken, refreshToken, expiresAt)
}

func ClearExtensionPendingAuthByID(extensionID string) {
	ClearPendingAuthRequest(extensionID)
}

func IsExtensionAuthenticatedByID(extensionID string) bool {
	extensionAuthStateMu.RLock()
	defer extensionAuthStateMu.RUnlock()

	state, exists := extensionAuthState[extensionID]
	if !exists {
		return false
	}

	if state.IsAuthenticated && !state.ExpiresAt.IsZero() && time.Now().After(state.ExpiresAt) {
		return false
	}

	return state.IsAuthenticated
}

func GetAllPendingAuthRequestsJSON() (string, error) {
	pendingAuthRequestsMu.RLock()
	defer pendingAuthRequestsMu.RUnlock()

	requests := make([]map[string]any, 0, len(pendingAuthRequests))
	for _, req := range pendingAuthRequests {
		requests = append(requests, map[string]any{
			"extension_id": req.ExtensionID,
			"auth_url":     req.AuthURL,
			"callback_url": req.CallbackURL,
		})
	}

	return marshalJSONString(requests)
}

func GetPendingFFmpegCommandJSON(commandID string) (string, error) {
	cmd := GetPendingFFmpegCommand(commandID)
	if cmd == nil {
		return "", nil
	}

	result := map[string]any{
		"command_id":   commandID,
		"extension_id": cmd.ExtensionID,
		"command":      cmd.Command,
		"input_path":   cmd.InputPath,
		"output_path":  cmd.OutputPath,
	}

	return marshalJSONString(result)
}

func SetFFmpegCommandResultByID(commandID string, success bool, output, errorMsg string) {
	SetFFmpegCommandResult(commandID, success, output, errorMsg)
}

func GetAllPendingFFmpegCommandsJSON() (string, error) {
	ffmpegCommandsMu.RLock()
	defer ffmpegCommandsMu.RUnlock()

	commands := make([]map[string]any, 0)
	for cmdID, cmd := range ffmpegCommands {
		if !cmd.Completed {
			commands = append(commands, map[string]any{
				"command_id":   cmdID,
				"extension_id": cmd.ExtensionID,
				"command":      cmd.Command,
			})
		}
	}

	return marshalJSONString(commands)
}

func EnrichTrackWithExtensionJSON(extensionID, trackJSON string) (string, error) {
	manager := getExtensionManager()
	ext, err := manager.GetExtension(extensionID)
	if err != nil {
		return trackJSON, nil
	}

	if !ext.Manifest.IsMetadataProvider() {
		return trackJSON, nil
	}

	var track ExtTrackMetadata
	if err := json.Unmarshal([]byte(trackJSON), &track); err != nil {
		return trackJSON, fmt.Errorf("failed to parse track: %w", err)
	}

	provider := newExtensionProviderWrapper(ext)
	enrichedTrack, err := provider.EnrichTrack(&track)
	if err != nil {
		return trackJSON, nil
	}

	jsonBytes, err := json.Marshal(enrichedTrack)
	if err != nil {
		return trackJSON, nil
	}

	return string(jsonBytes), nil
}

func CustomSearchWithExtensionJSON(extensionID, query string, optionsJSON string) (string, error) {
	return CustomSearchWithExtensionJSONWithRequestID(extensionID, query, optionsJSON, "")
}

func CustomSearchWithExtensionJSONWithRequestID(extensionID, query string, optionsJSON string, requestID string) (string, error) {
	manager := getExtensionManager()
	ext, err := manager.GetExtension(extensionID)
	if err != nil {
		return "", err
	}

	if !ext.Manifest.HasCustomSearch() {
		return "", fmt.Errorf("extension '%s' does not support custom search", extensionID)
	}

	var options map[string]any
	if optionsJSON != "" {
		if err := json.Unmarshal([]byte(optionsJSON), &options); err != nil {
			options = make(map[string]any)
		}
	}

	provider := newExtensionProviderWrapper(ext)
	tracks, err := provider.CustomSearchForRequestID(query, options, requestID)
	if err != nil {
		return "", err
	}

	result := make([]map[string]any, len(tracks))
	for i, track := range tracks {
		result[i] = normalizeExtensionTrackMetadataMap(track, "", 0)
	}

	return marshalJSONString(result)
}

func HandleURLWithExtensionJSON(url string) (string, error) {
	manager := getExtensionManager()
	resultWithID, err := manager.HandleURLWithExtension(url)
	if err != nil {
		return "", err
	}

	result := resultWithID.Result
	extensionID := resultWithID.ExtensionID

	if result == nil {
		return "", fmt.Errorf("extension %s failed to handle URL", extensionID)
	}

	response := map[string]any{
		"type":         result.Type,
		"extension_id": extensionID,
		"name":         result.Name,
		"cover_url":    result.CoverURL,
		"header_image": result.HeaderImage,
		"header_video": result.HeaderVideo,
	}

	if result.Track != nil {
		response["track"] = normalizeExtensionTrackMetadataMap(*result.Track, "", 0)
	}

	if len(result.Tracks) > 0 {
		tracks := make([]map[string]any, len(result.Tracks))
		for i, track := range result.Tracks {
			tracks[i] = normalizeExtensionTrackMetadataMap(track, "", 0)
		}
		response["tracks"] = tracks
	}

	if result.Album != nil {
		response["album"] = map[string]any{
			"id":           result.Album.ID,
			"name":         result.Album.Name,
			"artists":      result.Album.Artists,
			"cover_url":    result.Album.CoverURL,
			"header_image": result.Album.HeaderImage,
			"header_video": result.Album.HeaderVideo,
			"audio_traits": result.Album.AudioTraits,
			"release_date": result.Album.ReleaseDate,
			"total_tracks": result.Album.TotalTracks,
			"album_type":   result.Album.AlbumType,
			"provider_id":  result.Album.ProviderID,
		}
	}

	if result.Artist != nil {
		artistResponse := map[string]any{
			"id":           result.Artist.ID,
			"name":         result.Artist.Name,
			"image_url":    result.Artist.ImageURL,
			"header_image": result.Artist.HeaderImage,
			"header_video": result.Artist.HeaderVideo,
			"listeners":    result.Artist.Listeners,
			"provider_id":  result.Artist.ProviderID,
		}

		if len(result.Artist.Albums) > 0 {
			albums := make([]map[string]any, len(result.Artist.Albums))
			for i, album := range result.Artist.Albums {
				albumType := album.AlbumType
				if albumType == "" {
					albumType = "album"
				}
				albums[i] = map[string]any{
					"id":           album.ID,
					"name":         album.Name,
					"artists":      album.Artists,
					"images":       album.CoverURL,
					"cover_url":    album.CoverURL,
					"release_date": album.ReleaseDate,
					"total_tracks": album.TotalTracks,
					"album_type":   albumType,
					"provider_id":  album.ProviderID,
				}
			}
			artistResponse["albums"] = albums
		}

		if len(result.Artist.Releases) > 0 {
			releases := make([]map[string]any, len(result.Artist.Releases))
			for i, release := range result.Artist.Releases {
				releaseType := release.AlbumType
				if releaseType == "" {
					releaseType = "album"
				}
				releases[i] = map[string]any{
					"id":           release.ID,
					"name":         release.Name,
					"artists":      release.Artists,
					"images":       release.CoverURL,
					"cover_url":    release.CoverURL,
					"release_date": release.ReleaseDate,
					"total_tracks": release.TotalTracks,
					"album_type":   releaseType,
					"provider_id":  release.ProviderID,
				}
			}
			artistResponse["releases"] = releases
		}

		if len(result.Artist.TopTracks) > 0 {
			topTracks := make([]map[string]any, len(result.Artist.TopTracks))
			for i, track := range result.Artist.TopTracks {
				topTracks[i] = normalizeExtensionTrackMetadataMap(track, "", 0)
			}
			artistResponse["top_tracks"] = topTracks
		}

		response["artist"] = artistResponse
	}

	return marshalJSONString(response)
}

func FindURLHandlerJSON(url string) string {
	manager := getExtensionManager()
	handler := manager.FindURLHandler(url)
	if handler == nil {
		return ""
	}
	return handler.extension.ID
}

func RunPostProcessingV2JSON(inputJSON, metadataJSON string) (string, error) {
	var metadata map[string]any
	if metadataJSON != "" {
		if err := json.Unmarshal([]byte(metadataJSON), &metadata); err != nil {
			metadata = make(map[string]any)
		}
	}

	var input PostProcessInput
	if inputJSON != "" {
		if err := json.Unmarshal([]byte(inputJSON), &input); err != nil {
			input = PostProcessInput{}
		}
	}

	manager := getExtensionManager()
	result, err := manager.RunPostProcessingV2(input, metadata)
	if err != nil {
		return "", err
	}

	return marshalJSONString(result)
}

func callExtensionFunctionJSON(extensionID, functionName string, timeout time.Duration) (string, error) {
	return callExtensionFunctionJSONWithRequestID(extensionID, functionName, timeout, "")
}

func callExtensionFunctionJSONWithRequestID(extensionID, functionName string, timeout time.Duration, requestID string) (string, error) {
	manager := getExtensionManager()
	ext, err := manager.GetExtension(extensionID)
	if err != nil {
		return "", err
	}

	if !ext.Enabled {
		return "", fmt.Errorf("extension '%s' is disabled", extensionID)
	}
	perf := newExtensionCallPerf(extensionID, functionName)
	defer perf.finish()
	initStartedAt := time.Now()
	vm, err := ext.lockReadyVM()
	if err != nil {
		return "", err
	}
	perf.recordInit(time.Since(initStartedAt))
	defer ext.VMMu.Unlock()
	requestCtx := context.Background()
	if requestID != "" {
		if ext.runtime != nil {
			ext.runtime.setActiveRequestID(requestID)
			defer ext.runtime.clearActiveRequestID()
		}
		requestCtx = initExtensionRequestCancel(requestID)
		defer clearExtensionRequestCancel(requestID)
		if isExtensionRequestCancelled(requestID) {
			return "", ErrExtensionRequestCancelled
		}
	}

	jsStartedAt := time.Now()
	result, err := runGojaCallWithTimeoutContextAndRecover(requestCtx, vm, func() (goja.Value, error) {
		return invokeExtensionOrGlobal(vm, functionName)
	}, timeout)
	perf.recordJS(time.Since(jsStartedAt))
	if err != nil {
		if IsRuntimeUnsafeError(err) {
			quarantineRuntimeLocked(ext, vm)
		}
		if isExtensionRequestCancelled(requestID) || errors.Is(err, ErrExtensionRequestCancelled) {
			return "", ErrExtensionRequestCancelled
		}
		return "", fmt.Errorf("%s failed: %w", functionName, err)
	}
	if isExtensionRequestCancelled(requestID) {
		return "", ErrExtensionRequestCancelled
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return "", fmt.Errorf("%s returned null", functionName)
	}

	parseStartedAt := time.Now()
	jsonBytes, err := json.Marshal(result)
	perf.recordParse(time.Since(parseStartedAt))
	if err != nil {
		return "", fmt.Errorf("failed to marshal result: %w", err)
	}
	perf.setPayloadBytes(len(jsonBytes))
	perf.setItems(countExtensionTopLevelItems(vm, result))

	return string(jsonBytes), nil
}

func GetExtensionHomeFeedJSON(extensionID string) (string, error) {
	return callExtensionFunctionJSON(extensionID, "getHomeFeed", 60*time.Second)
}

func GetExtensionHomeFeedJSONWithRequestID(extensionID, requestID string) (string, error) {
	return callExtensionFunctionJSONWithRequestID(extensionID, "getHomeFeed", 60*time.Second, requestID)
}

func CancelExtensionRequestJSON(requestID string) {
	cancelExtensionRequest(requestID)
}
