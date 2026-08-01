package gobackend

import (
	"errors"
	"fmt"
	"path/filepath"
	"sort"
	"strings"
)

func (m *extensionManager) GetMetadataProviders() []*extensionProviderWrapper {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var providers []*extensionProviderWrapper
	for _, ext := range m.extensions {
		if ext.Enabled && ext.Manifest.IsMetadataProvider() && ext.Error == "" {
			providers = append(providers, newExtensionProviderWrapper(ext))
		}
	}
	return providers
}

func (m *extensionManager) GetDownloadProviders() []*extensionProviderWrapper {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var providers []*extensionProviderWrapper
	for _, ext := range m.extensions {
		if ext.Enabled && ext.Manifest.IsDownloadProvider() && ext.Error == "" {
			providers = append(providers, newExtensionProviderWrapper(ext))
		}
	}
	return providers
}

func metadataTrackDedupKey(track ExtTrackMetadata) string {
	if isrc := strings.TrimSpace(track.ISRC); isrc != "" {
		return "isrc:" + strings.ToUpper(isrc)
	}
	if spotifyID := strings.TrimSpace(track.SpotifyID); spotifyID != "" {
		return "spotify:" + spotifyID
	}
	if providerID := strings.TrimSpace(track.ProviderID); providerID != "" && strings.TrimSpace(track.ID) != "" {
		return providerID + ":" + strings.TrimSpace(track.ID)
	}
	return strings.TrimSpace(track.Name) + "|" + strings.TrimSpace(track.Artists)
}

func (m *extensionManager) SearchTracksWithMetadataProviders(query string, limit int, includeExtensions bool) ([]ExtTrackMetadata, error) {
	return m.SearchTracksWithMetadataProvidersForItemID(query, limit, includeExtensions, "")
}

// SearchTracksWithMetadataProvider searches one explicitly selected metadata
// provider. Unlike the priority-based search, this never falls through to a
// different extension, so callers can reliably attribute the returned fields
// to the provider selected by the user.
func (m *extensionManager) SearchTracksWithMetadataProvider(providerID, query string, limit int) ([]ExtTrackMetadata, error) {
	providerID = strings.TrimSpace(providerID)
	if providerID == "" {
		return nil, fmt.Errorf("metadata provider ID is required")
	}
	if limit <= 0 {
		limit = 20
	}

	ext, err := m.GetExtension(providerID)
	if err != nil {
		return nil, err
	}
	if ext == nil || ext.Manifest == nil || !ext.Manifest.IsMetadataProvider() {
		return nil, fmt.Errorf("extension '%s' is not a metadata provider", providerID)
	}
	if !ext.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", providerID)
	}
	if ext.Error != "" {
		return nil, fmt.Errorf("extension '%s' is unavailable: %s", providerID, ext.Error)
	}

	result, err := newExtensionProviderWrapper(ext).SearchTracks(query, limit)
	if err != nil {
		return nil, err
	}
	if result == nil || len(result.Tracks) <= limit {
		if result == nil {
			return []ExtTrackMetadata{}, nil
		}
		return result.Tracks, nil
	}
	return result.Tracks[:limit], nil
}

func (m *extensionManager) SearchTracksWithMetadataProvidersForItemID(query string, limit int, includeExtensions bool, itemID string) ([]ExtTrackMetadata, error) {
	priority := GetMetadataProviderPriority()
	if limit <= 0 {
		limit = 20
	}

	extensionProviders := make(map[string]*extensionProviderWrapper)
	if includeExtensions {
		for _, provider := range m.GetMetadataProviders() {
			extensionProviders[provider.extension.ID] = provider
		}
	}

	orderedProviderIDs := make([]string, 0, len(priority)+len(extensionProviders))
	seenProviderIDs := make(map[string]struct{}, len(priority)+len(extensionProviders))
	for _, providerID := range priority {
		providerID = strings.TrimSpace(providerID)
		if providerID == "" {
			continue
		}
		orderedProviderIDs = append(orderedProviderIDs, providerID)
		seenProviderIDs[providerID] = struct{}{}
	}
	if includeExtensions {
		remainingIDs := make([]string, 0, len(extensionProviders))
		for providerID := range extensionProviders {
			if _, exists := seenProviderIDs[providerID]; exists {
				continue
			}
			remainingIDs = append(remainingIDs, providerID)
		}
		sort.Strings(remainingIDs)
		orderedProviderIDs = append(orderedProviderIDs, remainingIDs...)
	}

	tracks := make([]ExtTrackMetadata, 0, limit)
	seenTracks := make(map[string]struct{})
	for _, providerID := range orderedProviderIDs {
		if isDownloadCancelled(itemID) {
			return nil, ErrDownloadCancelled
		}

		if !includeExtensions {
			continue
		}
		provider := extensionProviders[providerID]
		if provider == nil {
			continue
		}
		result, err := provider.SearchTracksForItemID(query, limit, itemID)
		providerTracks := []ExtTrackMetadata(nil)
		if result != nil {
			providerTracks = result.Tracks
		}

		if err != nil {
			if errors.Is(err, ErrDownloadCancelled) {
				return nil, ErrDownloadCancelled
			}
			GoLog("[MetadataSearch] Search error from %s: %v\n", providerID, err)
			continue
		}

		for _, track := range providerTracks {
			key := metadataTrackDedupKey(track)
			if key == "" {
				continue
			}
			if _, exists := seenTracks[key]; exists {
				continue
			}
			seenTracks[key] = struct{}{}
			tracks = append(tracks, track)
			if len(tracks) >= limit {
				return tracks, nil
			}
		}
	}

	return tracks, nil
}

// FindURLHandler returns the enabled handler matching the URL. When several
// extensions match (e.g. two Spotify handlers), the user's metadata provider
// priority breaks the tie deterministically instead of Go's random map
// iteration order.
func (m *extensionManager) FindURLHandler(url string) *extensionProviderWrapper {
	m.mu.RLock()
	matches := make([]*loadedExtension, 0, 2)
	for _, ext := range m.extensions {
		if ext.Enabled && ext.Manifest.MatchesURL(url) && ext.Error == "" {
			matches = append(matches, ext)
		}
	}
	m.mu.RUnlock()

	if len(matches) == 0 {
		return nil
	}
	if len(matches) > 1 {
		rank := map[string]int{}
		for i, id := range GetMetadataProviderPriority() {
			rank[strings.ToLower(strings.TrimSpace(id))] = i
		}
		sort.SliceStable(matches, func(i, j int) bool {
			ri, oki := rank[strings.ToLower(matches[i].ID)]
			rj, okj := rank[strings.ToLower(matches[j].ID)]
			switch {
			case oki && okj:
				return ri < rj
			case oki:
				return true
			case okj:
				return false
			default:
				return matches[i].ID < matches[j].ID
			}
		})
	}
	return newExtensionProviderWrapper(matches[0])
}

type ExtURLHandleResultWithExtID struct {
	Result      *ExtURLHandleResult
	ExtensionID string
}

func (m *extensionManager) HandleURLWithExtension(url string) (*ExtURLHandleResultWithExtID, error) {
	handler := m.FindURLHandler(url)
	if handler == nil {
		return nil, fmt.Errorf("no extension found to handle URL: %s", url)
	}

	result, err := handler.HandleURL(url)
	if err != nil {
		return &ExtURLHandleResultWithExtID{
			Result:      nil,
			ExtensionID: handler.extension.ID,
		}, err
	}

	return &ExtURLHandleResultWithExtID{
		Result:      result,
		ExtensionID: handler.extension.ID,
	}, nil
}

func (m *extensionManager) GetPostProcessingProviders() []*extensionProviderWrapper {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var providers []*extensionProviderWrapper
	for _, ext := range m.extensions {
		if ext.Enabled && ext.Manifest.HasPostProcessing() && ext.Error == "" {
			providers = append(providers, newExtensionProviderWrapper(ext))
		}
	}
	return providers
}

func (m *extensionManager) RunPostProcessingV2(input PostProcessInput, metadata map[string]any) (*PostProcessResult, error) {
	providers := m.GetPostProcessingProviders()
	if len(providers) == 0 {
		return &PostProcessResult{Success: true, NewFilePath: input.Path, NewFileURI: input.URI}, nil
	}

	logTag := "[PostProcessV2]"

	currentInput := input
	for _, provider := range providers {
		hooks := provider.extension.Manifest.GetPostProcessingHooks()
		for _, hook := range hooks {
			if !hook.DefaultEnabled {
				continue
			}

			ext := strings.ToLower(filepath.Ext(currentInput.Path))
			if ext == "" && currentInput.Name != "" {
				ext = strings.ToLower(filepath.Ext(currentInput.Name))
			}
			if len(hook.SupportedFormats) > 0 && ext != "" {
				supported := false
				for _, format := range hook.SupportedFormats {
					if "."+format == ext || format == ext[1:] {
						supported = true
						break
					}
				}
				if !supported {
					continue
				}
			}

			GoLog("%s Running hook %s from %s on %s\n", logTag, hook.ID, provider.extension.ID, currentInput.Path)

			result, err := provider.PostProcessV2(currentInput, metadata, hook.ID)
			if err != nil {
				GoLog("%s Hook %s failed: %v\n", logTag, hook.ID, err)
				continue
			}
			if result.Success {
				if err := validatePostProcessResult(provider.extension, currentInput, result); err != nil {
					GoLog("%s Hook %s returned an unsafe result: %v\n", logTag, hook.ID, err)
					continue
				}
			}

			if result.Success && result.NewFilePath != "" {
				currentInput.Path = result.NewFilePath
				if currentInput.Name == "" {
					currentInput.Name = filepath.Base(result.NewFilePath)
				}
			}
			if result.Success && result.NewFileURI != "" {
				currentInput.URI = result.NewFileURI
			}
		}
	}

	return &PostProcessResult{Success: true, NewFilePath: currentInput.Path, NewFileURI: currentInput.URI}, nil
}

func validatePostProcessResult(ext *loadedExtension, input PostProcessInput, result *PostProcessResult) error {
	if ext == nil || ext.Manifest == nil || result == nil {
		return fmt.Errorf("invalid post-processing result")
	}
	if result.NewFileURI != "" && result.NewFileURI != input.URI {
		return fmt.Errorf("an extension cannot replace the destination URI")
	}
	if result.NewFilePath == "" || filepath.Clean(result.NewFilePath) == filepath.Clean(input.Path) {
		return nil
	}
	if !ext.Manifest.Permissions.File {
		return fmt.Errorf("file permission is required to replace the processed file")
	}
	if !filepath.IsAbs(result.NewFilePath) {
		return fmt.Errorf("replacement file path must be absolute")
	}
	if input.Path != "" && isPathWithinBase(filepath.Dir(input.Path), result.NewFilePath) {
		return nil
	}
	if ext.DataDir != "" && isPathWithinBase(ext.DataDir, result.NewFilePath) {
		return nil
	}
	allowedDownloadDirsMu.RLock()
	defer allowedDownloadDirsMu.RUnlock()
	for _, dir := range allowedDownloadDirs {
		if isPathWithinBase(dir, result.NewFilePath) {
			return nil
		}
	}
	return fmt.Errorf("replacement file path is outside allowed directories")
}

func (m *extensionManager) GetLyricsProviders() []*extensionProviderWrapper {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var providers []*extensionProviderWrapper
	for _, ext := range m.extensions {
		if ext.Enabled && ext.Manifest.IsLyricsProvider() && ext.Error == "" {
			providers = append(providers, newExtensionProviderWrapper(ext))
		}
	}

	sort.Slice(providers, func(i, j int) bool {
		return providers[i].extension.ID < providers[j].extension.ID
	})

	return providers
}
