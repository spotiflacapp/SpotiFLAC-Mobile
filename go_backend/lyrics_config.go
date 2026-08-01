package gobackend

import (
	"errors"
	"fmt"
	"math"
	"regexp"
	"strings"
	"sync"
	"time"
)

const (
	lyricsProviderUnavailableCooldown = 10 * time.Minute
	lyricsProviderParallelism         = 3
	lyricsProviderPriorityGrace       = 5000 * time.Millisecond
)

const (
	LyricsProviderLRCLIB     = "lrclib"
	LyricsProviderNetease    = "netease"
	LyricsProviderMusixmatch = "musixmatch"
	LyricsProviderAppleMusic = "apple_music"
	LyricsProviderQQMusic    = "qqmusic"
	LyricsProviderSpotify    = "spotify"
	LyricsProviderDeezer     = "deezer"
	LyricsProviderYouTube    = "youtube"
	LyricsProviderKugou      = "kugou"
	LyricsProviderGenius     = "genius"
	LyricsProviderLyricsPlus = "lyricsplus"
)

var DefaultLyricsProviders = []string{
	LyricsProviderLRCLIB,
	LyricsProviderAppleMusic,
}

var (
	lyricsProvidersMu sync.RWMutex
	lyricsProviders   []string // ordered list of enabled providers
	appVersionMu      sync.RWMutex
	appVersion        string
)

type lyricsProviderHealthEntry struct {
	unavailableUntil time.Time
	reason           string
}

type lyricsProviderSearchRequest struct {
	spotifyID       string
	trackName       string
	artistName      string
	primaryArtist   string
	simplifiedTrack string
	durationSec     float64
	fetchOptions    LyricsFetchOptions
}

type lyricsProviderSearchResult struct {
	index        int
	providerName string
	lyrics       *LyricsResponse
	err          error
}

var (
	lyricsProviderHealthMu sync.RWMutex
	lyricsProviderHealth   = make(map[string]lyricsProviderHealthEntry)
)

func SetAppVersion(version string) {
	normalized := strings.TrimSpace(version)

	appVersionMu.Lock()
	defer appVersionMu.Unlock()
	appVersion = normalized
}

func GetAppVersion() string {
	appVersionMu.RLock()
	defer appVersionMu.RUnlock()
	return appVersion
}

func appUserAgent() string {
	version := GetAppVersion()

	if version == "" {
		return "SpotiFLAC-Mobile"
	}

	return "SpotiFLAC-Mobile/" + version
}

type LyricsFetchOptions struct {
	IncludeTranslationNetease  bool   `json:"include_translation_netease"`
	IncludeRomanizationNetease bool   `json:"include_romanization_netease"`
	MultiPersonWordByWord      bool   `json:"multi_person_word_by_word"`
	AppleElrcWordSync          bool   `json:"apple_elrc_word_sync"`
	MusixmatchLanguage         string `json:"musixmatch_language,omitempty"`
}

var defaultLyricsFetchOptions = LyricsFetchOptions{
	IncludeTranslationNetease:  false,
	IncludeRomanizationNetease: false,
	MultiPersonWordByWord:      true,
	AppleElrcWordSync:          false,
	MusixmatchLanguage:         "",
}

var instrumentalTrackPattern = regexp.MustCompile(`(?i)(?:^|[\s\[(\-])(?:instrumental|inst\.?)(?:[\s\])]|$)`)

var (
	lyricsFetchOptionsMu sync.RWMutex
	lyricsFetchOptions   = defaultLyricsFetchOptions
)

func SetLyricsProviderOrder(providers []string) {
	lyricsProvidersMu.Lock()
	defer lyricsProvidersMu.Unlock()

	if len(providers) == 0 {
		lyricsProviders = nil
		clearLyricsProviderHealth()
		return
	}

	validNames := map[string]bool{
		LyricsProviderLRCLIB:     true,
		LyricsProviderNetease:    true,
		LyricsProviderMusixmatch: true,
		LyricsProviderAppleMusic: true,
		LyricsProviderQQMusic:    true,
		LyricsProviderSpotify:    true,
		LyricsProviderDeezer:     true,
		LyricsProviderYouTube:    true,
		LyricsProviderKugou:      true,
		LyricsProviderGenius:     true,
		LyricsProviderLyricsPlus: true,
	}

	var valid []string
	for _, p := range providers {
		normalized := strings.ToLower(strings.TrimSpace(p))
		if validNames[normalized] {
			valid = append(valid, normalized)
		}
	}

	lyricsProviders = valid
	clearLyricsProviderHealth()
	GoLog("[Lyrics] Provider order set to: %v\n", valid)
}

func clearLyricsProviderHealth() {
	lyricsProviderHealthMu.Lock()
	defer lyricsProviderHealthMu.Unlock()
	lyricsProviderHealth = make(map[string]lyricsProviderHealthEntry)
}

func lyricsProviderHealthKey(providerName string) string {
	return strings.ToLower(strings.TrimSpace(providerName))
}

func shouldSkipLyricsProvider(providerName string) (bool, time.Duration, string) {
	key := lyricsProviderHealthKey(providerName)
	if key == "" {
		return false, 0, ""
	}

	now := time.Now()
	lyricsProviderHealthMu.RLock()
	entry, ok := lyricsProviderHealth[key]
	lyricsProviderHealthMu.RUnlock()
	if !ok {
		return false, 0, ""
	}
	if !now.Before(entry.unavailableUntil) {
		lyricsProviderHealthMu.Lock()
		if current, exists := lyricsProviderHealth[key]; exists && !now.Before(current.unavailableUntil) {
			delete(lyricsProviderHealth, key)
		}
		lyricsProviderHealthMu.Unlock()
		return false, 0, ""
	}
	return true, time.Until(entry.unavailableUntil), entry.reason
}

func markLyricsProviderAvailable(providerName string) {
	key := lyricsProviderHealthKey(providerName)
	if key == "" {
		return
	}
	lyricsProviderHealthMu.Lock()
	delete(lyricsProviderHealth, key)
	lyricsProviderHealthMu.Unlock()
}

func markLyricsProviderUnavailable(providerName string, err error) {
	if err == nil || !isLyricsProviderUnavailableError(err) {
		return
	}
	key := lyricsProviderHealthKey(providerName)
	if key == "" {
		return
	}
	reason := strings.TrimSpace(err.Error())
	if len(reason) > 160 {
		reason = reason[:160]
	}
	unavailableUntil := time.Now().Add(lyricsProviderUnavailableCooldown)

	lyricsProviderHealthMu.Lock()
	lyricsProviderHealth[key] = lyricsProviderHealthEntry{
		unavailableUntil: unavailableUntil,
		reason:           reason,
	}
	lyricsProviderHealthMu.Unlock()
	GoLog("[Lyrics] Provider %s marked unavailable for %s: %s\n", providerName, lyricsProviderUnavailableCooldown, reason)
}

// isLyricsProviderUnavailableError reports whether err is a provider/API-level
// failure that should temporarily disable a lyrics source. Providers classify
// their failures with the typed errors in lyrics_errors.go at the point of
// origin; transport failures are handled by isConnectivityFailure.
func isLyricsProviderUnavailableError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, errLyricsNotFound) {
		return false
	}
	if errors.Is(err, errLyricsServiceUnavailable) {
		return true
	}
	return isConnectivityFailure(err)
}

func GetLyricsProviderOrder() []string {
	lyricsProvidersMu.RLock()
	defer lyricsProvidersMu.RUnlock()

	if len(lyricsProviders) == 0 {
		return DefaultLyricsProviders
	}

	result := make([]string, len(lyricsProviders))
	copy(result, lyricsProviders)
	return result
}

func GetAvailableLyricsProviders() []map[string]any {
	return []map[string]any{
		{"id": LyricsProviderLRCLIB, "name": "LRCLIB", "has_proxy_dependency": false, "description": "Open-source synced lyrics database"},
		{"id": LyricsProviderNetease, "name": "Netease", "has_proxy_dependency": true, "description": "NetEase Cloud Music lyrics"},
		{"id": LyricsProviderMusixmatch, "name": "Musixmatch", "has_proxy_dependency": true, "description": "Musixmatch lyrics"},
		{"id": LyricsProviderAppleMusic, "name": "Apple Music", "has_proxy_dependency": true, "description": "Apple Music synced lyrics"},
		{"id": LyricsProviderQQMusic, "name": "QQ Music", "has_proxy_dependency": true, "description": "QQ Music lyrics"},
		{"id": LyricsProviderSpotify, "name": "Spotify", "has_proxy_dependency": true, "description": "Spotify synced lyrics"},
		{"id": LyricsProviderDeezer, "name": "Deezer", "has_proxy_dependency": true, "description": "Deezer lyrics"},
		{"id": LyricsProviderYouTube, "name": "YouTube", "has_proxy_dependency": true, "description": "YouTube lyrics"},
		{"id": LyricsProviderKugou, "name": "Kugou", "has_proxy_dependency": true, "description": "Kugou lyrics"},
		{"id": LyricsProviderGenius, "name": "Genius", "has_proxy_dependency": true, "description": "Genius lyrics"},
		{"id": LyricsProviderLyricsPlus, "name": "LyricsPlus", "has_proxy_dependency": true, "description": "Word-by-word karaoke lyrics (Apple/Musixmatch/Spotify/QQ)"},
	}
}

func normalizeLyricsFetchOptions(opts LyricsFetchOptions) LyricsFetchOptions {
	opts.MusixmatchLanguage = strings.ToLower(strings.TrimSpace(opts.MusixmatchLanguage))
	opts.MusixmatchLanguage = regexp.MustCompile(`[^a-z0-9\-_]`).ReplaceAllString(opts.MusixmatchLanguage, "")
	if len(opts.MusixmatchLanguage) > 16 {
		opts.MusixmatchLanguage = opts.MusixmatchLanguage[:16]
	}
	return opts
}

func SetLyricsFetchOptions(opts LyricsFetchOptions) {
	normalized := normalizeLyricsFetchOptions(opts)

	lyricsFetchOptionsMu.Lock()
	defer lyricsFetchOptionsMu.Unlock()
	changed := lyricsFetchOptions != normalized
	lyricsFetchOptions = normalized

	if changed {
		globalLyricsCache.ClearAll()
	}

	GoLog("[Lyrics] Fetch options set: translation=%v romanization=%v multi_person=%v apple_elrc=%v musixmatch_lang=%q\n",
		normalized.IncludeTranslationNetease,
		normalized.IncludeRomanizationNetease,
		normalized.MultiPersonWordByWord,
		normalized.AppleElrcWordSync,
		normalized.MusixmatchLanguage,
	)
}

func GetLyricsFetchOptions() LyricsFetchOptions {
	lyricsFetchOptionsMu.RLock()
	defer lyricsFetchOptionsMu.RUnlock()
	return lyricsFetchOptions
}

type lyricsCacheEntry struct {
	response  *LyricsResponse
	expiresAt time.Time
}

type lyricsCache struct {
	mu    sync.RWMutex
	cache map[string]*lyricsCacheEntry
}

var globalLyricsCache = &lyricsCache{
	cache: make(map[string]*lyricsCacheEntry),
}

func (c *lyricsCache) generateKey(artist, track string, durationSec float64) string {
	normalizedArtist := strings.ToLower(strings.TrimSpace(artist))
	normalizedTrack := strings.ToLower(strings.TrimSpace(track))
	roundedDuration := math.Round(durationSec/10) * 10
	return fmt.Sprintf("%s|%s|%.0f", normalizedArtist, normalizedTrack, roundedDuration)
}

func (c *lyricsCache) Get(artist, track string, durationSec float64) (*LyricsResponse, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	key := c.generateKey(artist, track, durationSec)
	entry, exists := c.cache[key]
	if !exists {
		return nil, false
	}

	if time.Now().After(entry.expiresAt) {
		return nil, false
	}

	return entry.response, true
}

const lyricsCacheMaxEntries = 500

func (c *lyricsCache) Set(artist, track string, durationSec float64, response *LyricsResponse) {
	c.mu.Lock()
	defer c.mu.Unlock()

	// Bound the cache: without eviction a long session accumulates every
	// looked-up track's full lyrics forever.
	if len(c.cache) >= lyricsCacheMaxEntries {
		now := time.Now()
		for key, entry := range c.cache {
			if now.After(entry.expiresAt) {
				delete(c.cache, key)
			}
		}
		for len(c.cache) >= lyricsCacheMaxEntries {
			var oldestKey string
			var oldestAt time.Time
			for key, entry := range c.cache {
				if oldestKey == "" || entry.expiresAt.Before(oldestAt) {
					oldestKey = key
					oldestAt = entry.expiresAt
				}
			}
			delete(c.cache, oldestKey)
		}
	}

	key := c.generateKey(artist, track, durationSec)
	c.cache[key] = &lyricsCacheEntry{
		response:  response,
		expiresAt: time.Now().Add(lyricsCacheTTL),
	}
}

func (c *lyricsCache) CleanExpired() int {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := time.Now()
	cleaned := 0
	for key, entry := range c.cache {
		if now.After(entry.expiresAt) {
			delete(c.cache, key)
			cleaned++
		}
	}
	return cleaned
}

func (c *lyricsCache) Size() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return len(c.cache)
}

func (c *lyricsCache) ClearAll() int {
	c.mu.Lock()
	defer c.mu.Unlock()

	cleared := len(c.cache)
	c.cache = make(map[string]*lyricsCacheEntry)
	return cleared
}
