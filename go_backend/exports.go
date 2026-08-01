package gobackend

import (
	"encoding/json"
	"runtime/debug"
	"strings"
	"sync"
)

var (
	metadataLanguageMu  sync.RWMutex
	metadataLanguageTag string
)

// SetMetadataLanguage sets the app's display language (BCP 47 tag, e.g.
// "en-US" or "id"), used as Accept-Language on metadata API requests so
// providers localize names by the app language instead of IP geolocation.
func SetMetadataLanguage(tag string) {
	metadataLanguageMu.Lock()
	metadataLanguageTag = strings.TrimSpace(tag)
	metadataLanguageMu.Unlock()
}

func metadataAcceptLanguage() string {
	metadataLanguageMu.RLock()
	tag := metadataLanguageTag
	metadataLanguageMu.RUnlock()
	if tag == "" || strings.HasPrefix(strings.ToLower(tag), "en") {
		return "en-US,en;q=0.9"
	}
	return tag + ",en;q=0.8"
}

// ReleaseMemory drops idle pooled extension runtimes, forces a GC, and
// returns freed heap to the OS. Called from the app on OS memory pressure and
// when backgrounded, so the Go side's RSS doesn't sit at its high-water mark
// after large downloads/tag writes.
func ReleaseMemory() {
	releaseMemory(false)
}

// ReleaseMemoryUnderPressure additionally drops disposable live caches. It is
// reserved for an OS memory-pressure signal; ordinary backgrounding keeps
// network-backed caches warm.
func ReleaseMemoryUnderPressure() {
	releaseMemory(true)
}

func releaseMemory(underPressure bool) {
	drainAllIsolatedRuntimePools()
	CloseIdleConnections()
	if underPressure {
		clearCoverMemoryCache()
		globalLyricsCache.ClearAll()
		clearPrivateIPCache()
		clearExtensionHealthCache()
	}
	debug.FreeOSMemory()
}

// SetSongLinkNetworkOptions is kept for backward compatibility.
func SetSongLinkNetworkOptions(allowHTTP, insecureTLS bool) {
	SetNetworkCompatibilityOptions(allowHTTP, insecureTLS)
}

// GetTrackPlatformLinksJSON returns {"platforms": {platformID: url}} for a
// track, resolved via song.link (memory-cached; either ID may be empty).
func GetTrackPlatformLinksJSON(spotifyTrackID string, isrc string) (string, error) {
	links, err := NewSongLinkClient().GetTrackPlatformLinks(spotifyTrackID, isrc)
	if err != nil {
		return "", err
	}
	return marshalJSONString(map[string]any{"platforms": links})
}

func SetDownloadDirectory(path string) error {
	return setDownloadDir(path)
}

func AllowDownloadDir(path string) {
	if strings.TrimSpace(path) == "" {
		return
	}
	AddAllowedDownloadDir(path)
}

func CheckDuplicatesBatch(outputDir, tracksJSON string) (string, error) {
	return CheckFilesExistParallel(outputDir, tracksJSON)
}

func PreBuildDuplicateIndex(outputDir string) error {
	return PreBuildISRCIndex(outputDir)
}

func InvalidateDuplicateIndex(outputDir string) {
	InvalidateISRCCache(outputDir)
}

func BuildFilename(template string, metadataJSON string) (string, error) {
	var metadata map[string]any
	if err := json.Unmarshal([]byte(metadataJSON), &metadata); err != nil {
		return "", err
	}

	filename := buildFilenameFromTemplate(template, metadata)
	return filename, nil
}

func SanitizeFilename(filename string) string {
	return sanitizeFilename(filename)
}
