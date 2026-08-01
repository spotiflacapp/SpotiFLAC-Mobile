package gobackend

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func manifestCapabilityStringList(manifest *ExtensionManifest, key string) []string {
	if manifest == nil || manifest.Capabilities == nil {
		return nil
	}

	raw, ok := manifest.Capabilities[key]
	if !ok {
		return nil
	}

	values, ok := raw.([]any)
	if !ok {
		return nil
	}

	result := make([]string, 0, len(values))
	for _, value := range values {
		str, ok := value.(string)
		if !ok {
			continue
		}
		trimmed := strings.ToLower(strings.TrimSpace(str))
		if trimmed == "" {
			continue
		}
		result = append(result, trimmed)
	}
	return result
}

func extensionReplacesBuiltInProvider(ext *loadedExtension, providerID string) bool {
	if ext == nil {
		return false
	}

	normalized := strings.ToLower(strings.TrimSpace(providerID))
	if normalized == "" {
		return false
	}

	for _, replaced := range manifestCapabilityStringList(ext.Manifest, "replacesBuiltInProviders") {
		if replaced == normalized {
			return true
		}
	}

	return false
}

func trimKnownProviderPrefix(trackID, providerID string) string {
	trimmedID := strings.TrimSpace(trackID)
	normalizedProvider := strings.ToLower(strings.TrimSpace(providerID))
	if trimmedID == "" || normalizedProvider == "" {
		return trimmedID
	}

	prefix := normalizedProvider + ":"
	if strings.HasPrefix(strings.ToLower(trimmedID), prefix) {
		return trimmedID[len(prefix):]
	}

	return trimmedID
}

func resolvePreferredTrackIDForExtension(ext *loadedExtension, req DownloadRequest, explicitTrackID string) string {
	candidates := make([]string, 0, 8)
	appendCandidate := func(value string) {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			return
		}
		for _, existing := range candidates {
			if existing == trimmed {
				return
			}
		}
		candidates = append(candidates, trimmed)
	}

	appendCandidate(explicitTrackID)

	if extensionReplacesBuiltInProvider(ext, "tidal") {
		appendCandidate(req.TidalID)
		appendCandidate(trimKnownProviderPrefix(req.SpotifyID, "tidal"))
	}
	if extensionReplacesBuiltInProvider(ext, "qobuz") {
		appendCandidate(req.QobuzID)
		appendCandidate(trimKnownProviderPrefix(req.SpotifyID, "qobuz"))
	}
	if extensionReplacesBuiltInProvider(ext, "deezer") {
		appendCandidate(req.DeezerID)
		appendCandidate(trimKnownProviderPrefix(req.SpotifyID, "deezer"))
	}
	if extensionReplacesBuiltInProvider(ext, "spotify") {
		appendCandidate(trimKnownProviderPrefix(req.SpotifyID, "spotify"))
		appendCandidate(req.SpotifyID)
	}

	appendCandidate(req.SpotifyID)
	appendCandidate(req.TidalID)
	appendCandidate(req.QobuzID)
	appendCandidate(req.DeezerID)

	if len(candidates) == 0 {
		return ""
	}
	return candidates[0]
}

func normalizeDownloadResultExtension(candidates ...string) string {
	for _, candidate := range candidates {
		ext := strings.TrimSpace(strings.ToLower(candidate))
		if ext == "" {
			continue
		}
		if !strings.HasPrefix(ext, ".") {
			ext = "." + ext
		}
		if ext == ".mp4" {
			return ".m4a"
		}
		return ext
	}
	return ""
}

// discardRejectedExtensionOutput removes only a newly downloaded file inside
// the host-selected output directory. Existing-library hits are never removed,
// nor are paths outside that narrow directory.
func discardRejectedExtensionOutput(result *ExtDownloadResult, requestedOutputPath string) {
	if result == nil || result.AlreadyExists {
		return
	}

	resultPath := strings.TrimSpace(result.FilePath)
	requestedPath := strings.TrimSpace(requestedOutputPath)
	if resultPath == "" || requestedPath == "" ||
		strings.HasPrefix(resultPath, "content://") ||
		strings.HasPrefix(resultPath, "/proc/self/fd/") {
		return
	}

	resultAbs, resultErr := filepath.Abs(resultPath)
	outputDirAbs, outputErr := filepath.Abs(filepath.Dir(requestedPath))
	if resultErr != nil || outputErr != nil {
		return
	}
	relative, err := filepath.Rel(outputDirAbs, resultAbs)
	if err != nil || relative == "." || relative == ".." ||
		strings.HasPrefix(relative, ".."+string(filepath.Separator)) ||
		filepath.IsAbs(relative) {
		return
	}

	if err := os.Remove(resultAbs); err != nil && !os.IsNotExist(err) {
		GoLog("[DownloadWithExtensionFallback] Warning: failed to remove rejected provider output %q: %v\n", resultAbs, err)
	}
}

func normalizeExtensionDownloadResult(result *ExtDownloadResult) (DownloadResult, bool) {
	if result == nil {
		return DownloadResult{}, false
	}

	downloadResult := DownloadResult{
		FilePath:                    strings.TrimSpace(result.FilePath),
		BitDepth:                    result.BitDepth,
		SampleRate:                  result.SampleRate,
		AudioCodec:                  strings.TrimSpace(result.AudioCodec),
		Title:                       result.Title,
		Artist:                      result.Artist,
		Album:                       result.Album,
		ReleaseDate:                 result.ReleaseDate,
		TrackNumber:                 result.TrackNumber,
		TotalTracks:                 result.TotalTracks,
		DiscNumber:                  result.DiscNumber,
		TotalDiscs:                  result.TotalDiscs,
		ISRC:                        result.ISRC,
		CoverURL:                    result.CoverURL,
		Genre:                       result.Genre,
		Label:                       result.Label,
		Copyright:                   result.Copyright,
		Composer:                    result.Composer,
		LyricsLRC:                   result.LyricsLRC,
		DecryptionKey:               result.DecryptionKey,
		Decryption:                  normalizeDownloadDecryptionInfo(result.Decryption, result.DecryptionKey),
		ActualExtension:             normalizeDownloadResultExtension(result.ActualExtension, result.OutputExtension),
		ActualContainer:             strings.TrimSpace(result.ActualContainer),
		RequiresContainerConversion: result.RequiresContainerConversion,
	}

	alreadyExists := result.AlreadyExists
	if strings.HasPrefix(downloadResult.FilePath, "EXISTS:") {
		alreadyExists = true
		downloadResult.FilePath = strings.TrimPrefix(downloadResult.FilePath, "EXISTS:")
	}

	enrichResultQualityFromFile(&downloadResult)
	return downloadResult, alreadyExists
}

// overlayStr sets *dst = src when dst is empty and src is not. If field is
// non-empty it logs "<field> from enrichment: <src>" on overlay.
func overlayStr(dst *string, src, field string) {
	if src == "" || *dst != "" {
		return
	}
	*dst = src
	if field != "" {
		GoLog("[DownloadWithExtensionFallback] %s from enrichment: %s\n", field, src)
	}
}

// overlayStrTrim is overlayStr but treats a whitespace-only dst as empty too.
func overlayStrTrim(dst *string, src string) {
	if src == "" || strings.TrimSpace(*dst) != "" {
		return
	}
	*dst = src
}

// overlayInt sets *dst = src when dst is zero and src is positive. If field is
// non-empty it logs "<field> from enrichment: <src>" on overlay.
func overlayInt(dst *int, src int, field string) {
	if src <= 0 || *dst != 0 {
		return
	}
	*dst = src
	if field != "" {
		GoLog("[DownloadWithExtensionFallback] %s from enrichment: %d\n", field, src)
	}
}

func overlayExtensionDownloadMetadata(resp *DownloadResponse, result *ExtDownloadResult) {
	if resp == nil || result == nil {
		return
	}

	overlayStrTrim(&resp.Title, result.Title)
	overlayStrTrim(&resp.Artist, result.Artist)
	overlayStrTrim(&resp.Album, result.Album)
	overlayStrTrim(&resp.AlbumArtist, result.AlbumArtist)
	overlayInt(&resp.TrackNumber, result.TrackNumber, "")
	overlayInt(&resp.DiscNumber, result.DiscNumber, "")
	overlayInt(&resp.TotalTracks, result.TotalTracks, "")
	overlayInt(&resp.TotalDiscs, result.TotalDiscs, "")
	overlayStrTrim(&resp.ReleaseDate, result.ReleaseDate)
	overlayStrTrim(&resp.CoverURL, result.CoverURL)
	overlayStrTrim(&resp.ISRC, result.ISRC)
	overlayStrTrim(&resp.Genre, result.Genre)
	overlayStrTrim(&resp.Label, result.Label)
	overlayStrTrim(&resp.Copyright, result.Copyright)
	overlayStrTrim(&resp.Composer, result.Composer)
	if result.LyricsLRC != "" {
		resp.LyricsLRC = result.LyricsLRC
	}
	if result.DecryptionKey != "" {
		resp.DecryptionKey = result.DecryptionKey
	}
	if normalized := normalizeDownloadDecryptionInfo(result.Decryption, result.DecryptionKey); normalized != nil {
		resp.Decryption = normalized
	}
	if ext := normalizeDownloadResultExtension(result.ActualExtension, result.OutputExtension); ext != "" {
		resp.ActualExtension = ext
	}
	if container := strings.TrimSpace(result.ActualContainer); container != "" {
		resp.ActualContainer = container
	}
	if result.RequiresContainerConversion {
		resp.RequiresContainerConversion = true
	}
}

func applyExtensionRequestFallbacks(resp *DownloadResponse, req DownloadRequest) {
	if resp == nil {
		return
	}

	overlayStr(&resp.Album, req.AlbumName, "")
	overlayStr(&resp.AlbumArtist, req.AlbumArtist, "")
	overlayStr(&resp.ReleaseDate, req.ReleaseDate, "")
	overlayStr(&resp.ISRC, req.ISRC, "")
	overlayInt(&resp.TrackNumber, req.TrackNumber, "")
	overlayInt(&resp.TotalTracks, req.TotalTracks, "")
	overlayInt(&resp.DiscNumber, req.DiscNumber, "")
	overlayInt(&resp.TotalDiscs, req.TotalDiscs, "")
	overlayStr(&resp.CoverURL, req.CoverURL, "")
}

func shouldStopProviderFallback(availability *ExtAvailabilityResult) bool {
	return availability != nil && availability.SkipFallback
}

func fallbackRuntimeHealthStatus(ext *loadedExtension) string {
	if ext == nil || ext.Manifest == nil || len(ext.Manifest.ServiceHealth) == 0 {
		return "unknown"
	}

	status := strings.ToLower(strings.TrimSpace(CheckExtensionHealthCached(ext).Status))
	switch status {
	case "online", "degraded", "offline":
		return status
	default:
		return "unknown"
	}
}

func prioritizeFallbackProvidersByHealth(priority []string, extManager *extensionManager, protectedProvider string) []string {
	if len(priority) == 0 || extManager == nil {
		return priority
	}

	online := make([]string, 0, len(priority))
	degraded := make([]string, 0, len(priority))
	unknown := make([]string, 0, len(priority))

	for _, rawProviderID := range priority {
		providerID := strings.TrimSpace(rawProviderID)
		if providerID == "" {
			continue
		}
		if strings.EqualFold(providerID, protectedProvider) || !isExtensionFallbackAllowed(providerID) {
			unknown = append(unknown, providerID)
			continue
		}

		ext, err := extManager.GetExtension(providerID)
		if err != nil || ext == nil || !ext.Enabled || ext.Error != "" || ext.Manifest == nil || !ext.Manifest.IsDownloadProvider() {
			unknown = append(unknown, providerID)
			continue
		}

		switch fallbackRuntimeHealthStatus(ext) {
		case "online":
			online = append(online, providerID)
		case "degraded":
			degraded = append(degraded, providerID)
		case "offline":
			GoLog("[DownloadWithExtensionFallback] Skipping extension provider %s (service health offline)\n", providerID)
		default:
			unknown = append(unknown, providerID)
		}
	}

	result := make([]string, 0, len(online)+len(degraded)+len(unknown))
	result = append(result, online...)
	result = append(result, degraded...)
	result = append(result, unknown...)
	return result
}

// moveProviderToFront preserves the user's explicit provider selection after
// health-based fallback sorting. Health may order the remaining fallback
// candidates, but it must never silently replace the provider the user picked.
func moveProviderToFront(priority []string, providerID string) []string {
	providerID = strings.TrimSpace(providerID)
	if providerID == "" || len(priority) < 2 {
		return priority
	}

	selectedIndex := -1
	for i, candidate := range priority {
		if strings.EqualFold(strings.TrimSpace(candidate), providerID) {
			selectedIndex = i
			break
		}
	}
	if selectedIndex <= 0 {
		return priority
	}

	reordered := make([]string, 0, len(priority))
	reordered = append(reordered, priority[selectedIndex])
	reordered = append(reordered, priority[:selectedIndex]...)
	reordered = append(reordered, priority[selectedIndex+1:]...)
	return reordered
}

func resolveExtensionAvailabilityReason(availability *ExtAvailabilityResult, err error) string {
	if availability != nil {
		if reason := strings.TrimSpace(availability.Reason); reason != "" {
			return reason
		}
	}
	if err != nil {
		return err.Error()
	}
	return "extension requested no further fallback"
}

func buildExtensionFallbackStoppedResponse(providerID string, availability *ExtAvailabilityResult, err error) *DownloadResponse {
	reason := resolveExtensionAvailabilityReason(availability, err)
	errorType := classifyDownloadErrorType(reason)
	if errorType == "unknown" {
		errorType = "extension_error"
	}
	return &DownloadResponse{
		Success:   false,
		Error:     fmt.Sprintf("Fallback stopped by %s: %s", providerID, reason),
		ErrorType: errorType,
		Service:   providerID,
	}
}

func shouldAbortCancelledFallback(itemID string, err error) bool {
	if errors.Is(err, ErrDownloadCancelled) {
		return true
	}
	return itemID != "" && isDownloadCancelled(itemID)
}

func normalizeExtensionDownloadErrorType(errorType, message string) string {
	normalized := strings.TrimSpace(errorType)
	classified := classifyDownloadErrorType(message)
	if classified != "" && classified != "unknown" {
		switch strings.ToLower(normalized) {
		case "", "unknown", "runtime_error", "api_error", "download_error", "extension_error":
			return classified
		}
	}
	return normalized
}
