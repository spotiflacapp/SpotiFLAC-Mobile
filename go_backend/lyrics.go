package gobackend

import (
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	lyricsCacheTTL       = 24 * time.Hour
	durationToleranceSec = 10.0
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

var lyricsNotFoundSignals = []string{
	"lyrics not found",
	"no lyrics found",
	"no songs found",
	"not found on",
	"empty track",
	"empty search query",
	"needs a deezer id",
}

// Provider/API-level failures that should temporarily disable a lyrics source.
// Transport failures are handled by isConnectivityFailure via typed errors.
var lyricsServiceUnavailableSignals = []string{
	"fetch failed",
	"missing required parameters",
	"request failed",
	"request unsuccessful",
	"search failed",
	"search unavailable",
	"rate limit",
	"too many requests",
	"operation too frequent",
	"操作频繁",
	"proxy returned http 429",
	"proxy returned http 5",
	"unexpected status code: 429",
	"unexpected status code: 5",
	"unexpected response code",
	"returned http 429",
	"returned http 5",
}

func isLyricsProviderUnavailableError(err error) bool {
	if err == nil {
		return false
	}

	msg := strings.ToLower(err.Error())
	for _, signal := range lyricsNotFoundSignals {
		if strings.Contains(msg, signal) {
			return false
		}
	}
	if isConnectivityFailure(err) {
		return true
	}
	for _, signal := range lyricsServiceUnavailableSignals {
		if strings.Contains(msg, signal) {
			return true
		}
	}
	return false
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

func GetAvailableLyricsProviders() []map[string]interface{} {
	return []map[string]interface{}{
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

func (c *lyricsCache) Set(artist, track string, durationSec float64, response *LyricsResponse) {
	c.mu.Lock()
	defer c.mu.Unlock()

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

type LRCLibResponse struct {
	ID           int     `json:"id"`
	Name         string  `json:"name"`
	TrackName    string  `json:"trackName"`
	ArtistName   string  `json:"artistName"`
	AlbumName    string  `json:"albumName"`
	Duration     float64 `json:"duration"`
	Instrumental bool    `json:"instrumental"`
	PlainLyrics  string  `json:"plainLyrics"`
	SyncedLyrics string  `json:"syncedLyrics"`
}

type LyricsLine struct {
	StartTimeMs int64  `json:"startTimeMs"`
	Words       string `json:"words"`
	EndTimeMs   int64  `json:"endTimeMs"`
}

type LyricsResponse struct {
	Lines        []LyricsLine `json:"lines"`
	SyncType     string       `json:"syncType"`
	Instrumental bool         `json:"instrumental"`
	PlainLyrics  string       `json:"plainLyrics"`
	Provider     string       `json:"provider"`
	Source       string       `json:"source"`
}

type LyricsClient struct {
	httpClient *http.Client
}

func NewLyricsClient() *LyricsClient {
	return &LyricsClient{
		httpClient: NewHTTPClientWithTimeout(15 * time.Second),
	}
}

func (c *LyricsClient) FetchLyricsWithMetadata(artist, track string) (*LyricsResponse, error) {
	baseURL := "https://lrclib.net/api/get"
	params := url.Values{}
	params.Set("artist_name", artist)
	params.Set("track_name", track)

	fullURL := baseURL + "?" + params.Encode()

	req, err := http.NewRequest("GET", fullURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("User-Agent", getRandomUserAgent())

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch lyrics: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == 404 {
		return nil, fmt.Errorf("lyrics not found")
	}

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	var lrcResp LRCLibResponse
	if err := json.NewDecoder(resp.Body).Decode(&lrcResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return c.parseLRCLibResponse(&lrcResp), nil
}

func (c *LyricsClient) FetchLyricsFromLRCLibSearch(query string, durationSec float64) (*LyricsResponse, error) {
	baseURL := "https://lrclib.net/api/search"
	params := url.Values{}
	params.Set("q", query)

	fullURL := baseURL + "?" + params.Encode()

	req, err := http.NewRequest("GET", fullURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("User-Agent", getRandomUserAgent())

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to search lyrics: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	var results []LRCLibResponse
	if err := json.NewDecoder(resp.Body).Decode(&results); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	if len(results) == 0 {
		return nil, fmt.Errorf("no lyrics found")
	}

	bestMatch := c.findBestMatch(results, durationSec)
	if bestMatch != nil {
		return c.parseLRCLibResponse(bestMatch), nil
	}

	for _, result := range results {
		if result.SyncedLyrics != "" {
			return c.parseLRCLibResponse(&result), nil
		}
	}

	return c.parseLRCLibResponse(&results[0]), nil
}

func (c *LyricsClient) findBestMatch(results []LRCLibResponse, targetDurationSec float64) *LRCLibResponse {
	var bestSynced *LRCLibResponse
	var bestPlain *LRCLibResponse

	for i := range results {
		result := &results[i]

		durationMatches := targetDurationSec == 0 || c.durationMatches(result.Duration, targetDurationSec)

		if durationMatches {
			if result.SyncedLyrics != "" && bestSynced == nil {
				bestSynced = result
			} else if result.PlainLyrics != "" && bestPlain == nil {
				bestPlain = result
			}
		}
	}

	if bestSynced != nil {
		return bestSynced
	}
	return bestPlain
}

func plainLyricsFromTimedLines(lines []LyricsLine) string {
	parts := make([]string, 0, len(lines))
	for _, line := range lines {
		words := strings.TrimSpace(line.Words)
		if words == "" {
			continue
		}
		parts = append(parts, words)
	}
	return strings.Join(parts, "\n")
}

func (c *LyricsClient) durationMatches(lrcDuration, targetDuration float64) bool {
	diff := math.Abs(lrcDuration - targetDuration)
	return diff <= durationToleranceSec
}

func (c *LyricsClient) FetchLyricsAllSources(spotifyID, trackName, artistName string, durationSec float64) (*LyricsResponse, error) {
	primaryArtist := normalizeArtistName(artistName)
	fetchOptions := GetLyricsFetchOptions()

	if isLikelyInstrumentalTrack(trackName) {
		GoLog("[Lyrics] Track marked instrumental by title heuristic, skipping lyrics search: %s - %s\n", artistName, trackName)
		instrumental := &LyricsResponse{
			Instrumental: true,
			Source:       "Heuristic: Instrumental",
		}
		globalLyricsCache.Set(artistName, trackName, durationSec, instrumental)
		return instrumental, nil
	}

	extManager := getExtensionManager()
	var extensionProviders []*extensionProviderWrapper
	if extManager != nil {
		extensionProviders = extManager.GetLyricsProviders()
	}

	var cachedNonExtension *LyricsResponse
	if cached, found := globalLyricsCache.Get(artistName, trackName, durationSec); found {
		isExtensionCache := strings.HasPrefix(cached.Source, "Extension:")
		if len(extensionProviders) == 0 || isExtensionCache {
			fmt.Printf("[Lyrics] Cache hit for: %s - %s\n", artistName, trackName)
			cachedCopy := *cached
			cachedCopy.Source = cached.Source + " (cached)"
			return &cachedCopy, nil
		}

		// If extension providers are currently enabled, don't let stale built-in cache
		// mask newly installed/activated extensions.
		cachedNonExtension = cached
		GoLog("[Lyrics] Ignoring cached non-extension lyrics because extension providers are available\n")
	}

	isValidResult := func(l *LyricsResponse) bool {
		return lyricsHasUsableText(l)
	}

	if len(extensionProviders) > 0 {
		for _, provider := range extensionProviders {
			providerName := "extension:" + provider.extension.ID
			if skip, remaining, reason := shouldSkipLyricsProvider(providerName); skip {
				GoLog("[Lyrics] Skipping unavailable extension lyrics provider %s for %s: %s\n", provider.extension.ID, remaining.Round(time.Second), reason)
				continue
			}
			GoLog("[Lyrics] Trying extension lyrics provider: %s\n", provider.extension.ID)
			lyrics, err := provider.FetchLyrics(trackName, artistName, "", durationSec)
			if err == nil && isValidResult(lyrics) {
				GoLog("[Lyrics] Got lyrics from extension: %s\n", provider.extension.ID)
				markLyricsProviderAvailable(providerName)
				globalLyricsCache.Set(artistName, trackName, durationSec, lyrics)
				return lyrics, nil
			}
			if err != nil {
				GoLog("[Lyrics] Extension %s failed: %v\n", provider.extension.ID, err)
				markLyricsProviderUnavailable(providerName, err)
			}
		}
	}

	if cachedNonExtension != nil {
		cachedCopy := *cachedNonExtension
		cachedCopy.Source = cachedNonExtension.Source + " (cached fallback)"
		GoLog("[Lyrics] Extension providers unavailable for this track, using cached built-in lyrics\n")
		return &cachedCopy, nil
	}

	providerOrder := GetLyricsProviderOrder()
	simplifiedTrack := simplifyTrackName(trackName)
	request := lyricsProviderSearchRequest{
		spotifyID:       spotifyID,
		trackName:       trackName,
		artistName:      artistName,
		primaryArtist:   primaryArtist,
		simplifiedTrack: simplifiedTrack,
		durationSec:     durationSec,
		fetchOptions:    fetchOptions,
	}

	GoLog("[Lyrics] Searching for: %s - %s (providers: %v)\n", artistName, trackName, providerOrder)

	lyrics, err := fetchBuiltInLyricsProviders(providerOrder, request, c.fetchBuiltInLyricsProvider)
	if err == nil && isValidResult(lyrics) {
		globalLyricsCache.Set(artistName, trackName, durationSec, lyrics)
		return lyrics, nil
	}

	return nil, fmt.Errorf("lyrics not found from any source")
}

func fetchBuiltInLyricsProviders(
	providerOrder []string,
	request lyricsProviderSearchRequest,
	fetchProvider func(string, lyricsProviderSearchRequest) (*LyricsResponse, error, bool),
) (*LyricsResponse, error) {
	type providerCandidate struct {
		index int
		name  string
	}

	candidates := make([]providerCandidate, 0, len(providerOrder))
	results := make(chan lyricsProviderSearchResult, len(providerOrder))
	sem := make(chan struct{}, lyricsProviderParallelism)
	var wg sync.WaitGroup

	for index, providerName := range providerOrder {
		if skip, remaining, reason := shouldSkipLyricsProvider(providerName); skip {
			GoLog("[Lyrics] Skipping unavailable provider %s for %s: %s\n", providerName, remaining.Round(time.Second), reason)
			continue
		}

		knownProvider := isKnownBuiltInLyricsProvider(providerName)
		if !knownProvider {
			GoLog("[Lyrics] Unknown provider: %s, skipping\n", providerName)
			continue
		}

		candidate := providerCandidate{index: index, name: providerName}
		candidates = append(candidates, candidate)
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			GoLog("[Lyrics] Trying provider: %s\n", candidate.name)
			lyrics, err, ok := fetchProvider(candidate.name, request)
			if !ok {
				results <- lyricsProviderSearchResult{index: candidate.index, providerName: candidate.name, err: fmt.Errorf("unknown provider")}
				return
			}
			if err == nil && lyricsHasUsableText(lyrics) {
				GoLog("[Lyrics] Got lyrics from: %s\n", candidate.name)
				markLyricsProviderAvailable(candidate.name)
			} else if err != nil {
				GoLog("[Lyrics] Provider %s failed: %v\n", candidate.name, err)
				markLyricsProviderUnavailable(candidate.name, err)
			}
			results <- lyricsProviderSearchResult{index: candidate.index, providerName: candidate.name, lyrics: lyrics, err: err}
		}()
	}

	if len(candidates) == 0 {
		return nil, fmt.Errorf("lyrics not found from any source")
	}

	go func() {
		wg.Wait()
		close(results)
	}()

	completed := make(map[int]bool, len(candidates))
	var best *lyricsProviderSearchResult
	var lastErr error
	var graceTimer *time.Timer
	var grace <-chan time.Time

	stopGrace := func() {
		if graceTimer != nil {
			if !graceTimer.Stop() {
				select {
				case <-graceTimer.C:
				default:
				}
			}
			graceTimer = nil
			grace = nil
		}
	}
	defer stopGrace()

	hasPendingEarlier := func(index int) bool {
		for _, candidate := range candidates {
			if candidate.index >= index {
				return false
			}
			if !completed[candidate.index] {
				return true
			}
		}
		return false
	}

	for remaining := len(candidates); remaining > 0; {
		if best != nil && !hasPendingEarlier(best.index) {
			return best.lyrics, nil
		}
		if best != nil && graceTimer == nil {
			graceTimer = time.NewTimer(lyricsProviderPriorityGrace)
			grace = graceTimer.C
		}

		select {
		case result, ok := <-results:
			if !ok {
				remaining = 0
				break
			}
			remaining--
			completed[result.index] = true
			if result.err != nil {
				lastErr = result.err
			}
			if lyricsHasUsableText(result.lyrics) && (best == nil || result.index < best.index) {
				copied := result
				best = &copied
				stopGrace()
			}
		case <-grace:
			if best != nil {
				GoLog("[Lyrics] Returning provider %s after %s priority grace\n", best.providerName, lyricsProviderPriorityGrace)
				return best.lyrics, nil
			}
		}
	}

	if best != nil {
		return best.lyrics, nil
	}
	if lastErr != nil {
		return nil, lastErr
	}
	return nil, fmt.Errorf("lyrics not found from any source")
}

func isKnownBuiltInLyricsProvider(providerName string) bool {
	switch providerName {
	case LyricsProviderLRCLIB,
		LyricsProviderNetease,
		LyricsProviderMusixmatch,
		LyricsProviderAppleMusic,
		LyricsProviderQQMusic,
		LyricsProviderSpotify,
		LyricsProviderDeezer,
		LyricsProviderYouTube,
		LyricsProviderKugou,
		LyricsProviderGenius,
		LyricsProviderLyricsPlus:
		return true
	default:
		return false
	}
}

func (c *LyricsClient) fetchBuiltInLyricsProvider(providerName string, request lyricsProviderSearchRequest) (*LyricsResponse, error, bool) {
	switch providerName {
	case LyricsProviderLRCLIB:
		lyrics, err := c.tryLRCLIB(request.primaryArtist, request.artistName, request.trackName, request.simplifiedTrack, request.durationSec)
		return lyrics, err, true

	case LyricsProviderNetease:
		neteaseClient := NewNeteaseClient()
		lyrics, err := neteaseClient.FetchLyrics(
			request.trackName,
			request.primaryArtist,
			request.durationSec,
			request.fetchOptions.IncludeTranslationNetease,
			request.fetchOptions.IncludeRomanizationNetease,
		)
		if err != nil && !isLyricsProviderUnavailableError(err) && request.primaryArtist != request.artistName {
			lyrics, err = neteaseClient.FetchLyrics(
				request.trackName,
				request.artistName,
				request.durationSec,
				request.fetchOptions.IncludeTranslationNetease,
				request.fetchOptions.IncludeRomanizationNetease,
			)
		}
		if err != nil && !isLyricsProviderUnavailableError(err) && request.simplifiedTrack != request.trackName {
			lyrics, err = neteaseClient.FetchLyrics(
				request.simplifiedTrack,
				request.primaryArtist,
				request.durationSec,
				request.fetchOptions.IncludeTranslationNetease,
				request.fetchOptions.IncludeRomanizationNetease,
			)
		}
		return lyrics, err, true

	case LyricsProviderMusixmatch:
		musixmatchClient := NewMusixmatchClient()
		lyrics, err := musixmatchClient.FetchLyrics(
			request.trackName,
			request.primaryArtist,
			request.durationSec,
			request.fetchOptions.MusixmatchLanguage,
		)
		if err != nil && !isLyricsProviderUnavailableError(err) && request.primaryArtist != request.artistName {
			lyrics, err = musixmatchClient.FetchLyrics(
				request.trackName,
				request.artistName,
				request.durationSec,
				request.fetchOptions.MusixmatchLanguage,
			)
		}
		return lyrics, err, true

	case LyricsProviderAppleMusic:
		appleClient := NewAppleMusicClient()
		lyrics, err := appleClient.FetchLyrics(request.trackName, request.primaryArtist, request.durationSec, request.fetchOptions.MultiPersonWordByWord, request.fetchOptions.AppleElrcWordSync)
		if err != nil && !isLyricsProviderUnavailableError(err) && request.primaryArtist != request.artistName {
			lyrics, err = appleClient.FetchLyrics(request.trackName, request.artistName, request.durationSec, request.fetchOptions.MultiPersonWordByWord, request.fetchOptions.AppleElrcWordSync)
		}
		return lyrics, err, true

	case LyricsProviderQQMusic:
		qqClient := NewQQMusicClient()
		lyrics, err := qqClient.FetchLyrics(request.trackName, request.primaryArtist, request.durationSec, request.fetchOptions.MultiPersonWordByWord)
		if err != nil && !isLyricsProviderUnavailableError(err) && request.primaryArtist != request.artistName {
			lyrics, err = qqClient.FetchLyrics(request.trackName, request.artistName, request.durationSec, request.fetchOptions.MultiPersonWordByWord)
		}
		return lyrics, err, true

	case LyricsProviderSpotify:
		spotifyClient := NewSpotifyLyricsClient()
		lyrics, err := spotifyClient.FetchLyrics(request.spotifyID, request.trackName, request.primaryArtist, request.durationSec)
		if err != nil && !isLyricsProviderUnavailableError(err) && request.primaryArtist != request.artistName {
			lyrics, err = spotifyClient.FetchLyrics(request.spotifyID, request.trackName, request.artistName, request.durationSec)
		}
		if err != nil && !isLyricsProviderUnavailableError(err) && request.simplifiedTrack != request.trackName {
			lyrics, err = spotifyClient.FetchLyrics("", request.simplifiedTrack, request.primaryArtist, request.durationSec)
		}
		return lyrics, err, true

	case LyricsProviderDeezer:
		deezerClient := NewDeezerLyricsClient()
		lyrics, err := deezerClient.FetchLyrics(request.spotifyID, request.trackName, request.primaryArtist, request.durationSec)
		if err != nil && !isLyricsProviderUnavailableError(err) && request.primaryArtist != request.artistName {
			lyrics, err = deezerClient.FetchLyrics(request.spotifyID, request.trackName, request.artistName, request.durationSec)
		}
		return lyrics, err, true

	case LyricsProviderYouTube:
		youtubeClient := NewYouTubeLyricsClient()
		lyrics, err := youtubeClient.FetchLyrics(request.trackName, request.primaryArtist, request.durationSec)
		if err != nil && !isLyricsProviderUnavailableError(err) && request.primaryArtist != request.artistName {
			lyrics, err = youtubeClient.FetchLyrics(request.trackName, request.artistName, request.durationSec)
		}
		if err != nil && !isLyricsProviderUnavailableError(err) && request.simplifiedTrack != request.trackName {
			lyrics, err = youtubeClient.FetchLyrics(request.simplifiedTrack, request.primaryArtist, request.durationSec)
		}
		return lyrics, err, true

	case LyricsProviderKugou:
		kugouClient := NewKugouLyricsClient()
		lyrics, err := kugouClient.FetchLyrics(request.trackName, request.primaryArtist, request.durationSec)
		if err != nil && !isLyricsProviderUnavailableError(err) && request.primaryArtist != request.artistName {
			lyrics, err = kugouClient.FetchLyrics(request.trackName, request.artistName, request.durationSec)
		}
		if err != nil && !isLyricsProviderUnavailableError(err) && request.simplifiedTrack != request.trackName {
			lyrics, err = kugouClient.FetchLyrics(request.simplifiedTrack, request.primaryArtist, request.durationSec)
		}
		return lyrics, err, true

	case LyricsProviderGenius:
		geniusClient := NewGeniusLyricsClient()
		lyrics, err := geniusClient.FetchLyrics(request.trackName, request.primaryArtist, request.durationSec)
		if err != nil && !isLyricsProviderUnavailableError(err) && request.primaryArtist != request.artistName {
			lyrics, err = geniusClient.FetchLyrics(request.trackName, request.artistName, request.durationSec)
		}
		if err != nil && !isLyricsProviderUnavailableError(err) && request.simplifiedTrack != request.trackName {
			lyrics, err = geniusClient.FetchLyrics(request.simplifiedTrack, request.primaryArtist, request.durationSec)
		}
		return lyrics, err, true

	case LyricsProviderLyricsPlus:
		lyricsPlusClient := NewLyricsPlusClient()
		lyrics, err := lyricsPlusClient.FetchLyrics(
			request.trackName,
			request.primaryArtist,
			"",
			request.durationSec,
			request.fetchOptions.MultiPersonWordByWord,
			request.fetchOptions.AppleElrcWordSync,
		)
		if err != nil && !isLyricsProviderUnavailableError(err) && request.primaryArtist != request.artistName {
			lyrics, err = lyricsPlusClient.FetchLyrics(
				request.trackName,
				request.artistName,
				"",
				request.durationSec,
				request.fetchOptions.MultiPersonWordByWord,
				request.fetchOptions.AppleElrcWordSync,
			)
		}
		if err != nil && !isLyricsProviderUnavailableError(err) && request.simplifiedTrack != request.trackName {
			lyrics, err = lyricsPlusClient.FetchLyrics(
				request.simplifiedTrack,
				request.primaryArtist,
				"",
				request.durationSec,
				request.fetchOptions.MultiPersonWordByWord,
				request.fetchOptions.AppleElrcWordSync,
			)
		}
		return lyrics, err, true
	default:
		return nil, fmt.Errorf("unknown provider: %s", providerName), false
	}
}

func (c *LyricsClient) tryLRCLIB(primaryArtist, artistName, trackName, simplifiedTrack string, durationSec float64) (*LyricsResponse, error) {
	var lyrics *LyricsResponse
	var err error

	lyrics, err = c.FetchLyricsWithMetadata(primaryArtist, trackName)
	if err == nil && lyrics != nil && (len(lyrics.Lines) > 0 || lyrics.Instrumental) {
		lyrics.Source = "LRCLIB"
		return lyrics, nil
	}
	if isLyricsProviderUnavailableError(err) {
		return nil, err
	}

	if primaryArtist != artistName {
		lyrics, err = c.FetchLyricsWithMetadata(artistName, trackName)
		if err == nil && lyrics != nil && (len(lyrics.Lines) > 0 || lyrics.Instrumental) {
			lyrics.Source = "LRCLIB"
			return lyrics, nil
		}
		if isLyricsProviderUnavailableError(err) {
			return nil, err
		}
	}

	if simplifiedTrack != trackName {
		lyrics, err = c.FetchLyricsWithMetadata(primaryArtist, simplifiedTrack)
		if err == nil && lyrics != nil && (len(lyrics.Lines) > 0 || lyrics.Instrumental) {
			lyrics.Source = "LRCLIB (simplified)"
			return lyrics, nil
		}
		if isLyricsProviderUnavailableError(err) {
			return nil, err
		}
	}

	query := primaryArtist + " " + trackName
	lyrics, err = c.FetchLyricsFromLRCLibSearch(query, durationSec)
	if err == nil && lyrics != nil && (len(lyrics.Lines) > 0 || lyrics.Instrumental) {
		lyrics.Source = "LRCLIB Search"
		return lyrics, nil
	}
	if isLyricsProviderUnavailableError(err) {
		return nil, err
	}

	if simplifiedTrack != trackName {
		query = primaryArtist + " " + simplifiedTrack
		lyrics, err = c.FetchLyricsFromLRCLibSearch(query, durationSec)
		if err == nil && lyrics != nil && (len(lyrics.Lines) > 0 || lyrics.Instrumental) {
			lyrics.Source = "LRCLIB Search (simplified)"
			return lyrics, nil
		}
		if isLyricsProviderUnavailableError(err) {
			return nil, err
		}
	}

	return nil, fmt.Errorf("LRCLIB: no lyrics found")
}

func (c *LyricsClient) parseLRCLibResponse(resp *LRCLibResponse) *LyricsResponse {
	result := &LyricsResponse{
		Instrumental: resp.Instrumental,
		PlainLyrics:  resp.PlainLyrics,
		Provider:     "LRCLIB",
	}

	if resp.SyncedLyrics != "" {
		result.Lines = parseSyncedLyrics(resp.SyncedLyrics)
		result.SyncType = "LINE_SYNCED"
	} else if resp.PlainLyrics != "" {
		result.SyncType = "UNSYNCED"
		lines := strings.Split(resp.PlainLyrics, "\n")
		for _, line := range lines {
			if strings.TrimSpace(line) != "" {
				result.Lines = append(result.Lines, LyricsLine{
					StartTimeMs: 0,
					Words:       line,
					EndTimeMs:   0,
				})
			}
		}
	}

	return result
}

func parseSyncedLyrics(syncedLyrics string) []LyricsLine {
	var lines []LyricsLine
	lrcPattern := regexp.MustCompile(`\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)`)

	for _, line := range strings.Split(syncedLyrics, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Preserve Apple/QQ background vocal tags by attaching them to
		// the previous timed line. This keeps [bg:...] in final exported LRC.
		if strings.HasPrefix(line, "[bg:") && len(lines) > 0 {
			lines[len(lines)-1].Words = strings.TrimSpace(lines[len(lines)-1].Words + "\n" + line)
			continue
		}

		matches := lrcPattern.FindStringSubmatch(line)
		if len(matches) == 5 {
			startMs := lrcTimestampToMs(matches[1], matches[2], matches[3])
			words := strings.TrimSpace(matches[4])
			if words == "" {
				continue
			}

			lines = append(lines, LyricsLine{
				StartTimeMs: startMs,
				Words:       words,
				EndTimeMs:   0,
			})
		}
	}

	for i := 0; i < len(lines)-1; i++ {
		lines[i].EndTimeMs = lines[i+1].StartTimeMs
	}

	if len(lines) > 0 {
		lines[len(lines)-1].EndTimeMs = lines[len(lines)-1].StartTimeMs + 5000
	}

	return lines
}

func plainTextLyricsLines(rawLyrics string) []LyricsLine {
	var lines []LyricsLine
	for _, line := range strings.Split(rawLyrics, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		lines = append(lines, LyricsLine{
			StartTimeMs: 0,
			Words:       trimmed,
			EndTimeMs:   0,
		})
	}
	return lines
}

func lyricsHasUsableText(lyrics *LyricsResponse) bool {
	if lyrics == nil {
		return false
	}
	if lyrics.Instrumental {
		return true
	}
	if strings.TrimSpace(lyrics.PlainLyrics) != "" {
		return true
	}
	for _, line := range lyrics.Lines {
		if strings.TrimSpace(line.Words) != "" {
			return true
		}
	}
	return false
}

func detectLyricsErrorPayload(raw string) (string, bool) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" || !strings.HasPrefix(trimmed, "{") {
		return "", false
	}

	var payload map[string]interface{}
	if err := json.Unmarshal([]byte(trimmed), &payload); err != nil {
		return "", false
	}

	lyricsKeys := []string{"lyrics", "lyric", "lrc", "content", "lines", "syncedLyrics", "unsyncedLyrics"}
	hasLyricsKey := false
	for _, key := range lyricsKeys {
		if _, ok := payload[key]; ok {
			hasLyricsKey = true
			break
		}
	}

	errorKeys := []string{"message", "error", "detail", "reason"}
	for _, key := range errorKeys {
		if msg, ok := payload[key].(string); ok {
			msg = strings.TrimSpace(msg)
			if msg != "" && !hasLyricsKey {
				return msg, true
			}
		}
	}

	if success, ok := payload["success"].(bool); ok && !success && !hasLyricsKey {
		return "request unsuccessful", true
	}
	if isError, ok := payload["isError"].(bool); ok && isError && !hasLyricsKey {
		return "request unsuccessful", true
	}
	if code, ok := payload["code"].(float64); ok && code != 0 && code != 200 && !hasLyricsKey {
		if msg, ok := payload["message"].(string); ok && strings.TrimSpace(msg) != "" {
			return strings.TrimSpace(msg), true
		}
		if msg, ok := payload["msg"].(string); ok && strings.TrimSpace(msg) != "" {
			return strings.TrimSpace(msg), true
		}
		return fmt.Sprintf("unexpected response code %.0f", code), true
	}

	return "", false
}

func lrcTimestampToMs(minutes, seconds, centiseconds string) int64 {
	min, _ := strconv.ParseInt(minutes, 10, 64)
	sec, _ := strconv.ParseInt(seconds, 10, 64)
	cs, _ := strconv.ParseInt(centiseconds, 10, 64)

	if len(centiseconds) == 2 {
		cs *= 10
	}

	return min*60*1000 + sec*1000 + cs
}

func msToLRCTimestamp(ms int64) string {
	return fmt.Sprintf("[%s]", msToLRCTimestampInline(ms))
}

func msToLRCTimestampInline(ms int64) string {
	totalSeconds := ms / 1000
	minutes := totalSeconds / 60
	seconds := totalSeconds % 60
	centiseconds := (ms % 1000) / 10

	return fmt.Sprintf("%02d:%02d.%02d", minutes, seconds, centiseconds)
}

// extractLyricsSourceFromLRC reads the provider recorded in the LRC [by:] tag,
// e.g. "[by:SpotiFLAC-Mobile (source: LRCLIB)]". Returns "" when absent.
const lrcSourceMarker = "(source: "

func lyricsSourceUsesPaxsenix(source string) bool {
	s := strings.ToLower(strings.TrimSpace(source))
	if s == "" {
		return false
	}
	if strings.HasPrefix(s, "lrclib") ||
		strings.HasPrefix(s, "extension:") ||
		strings.HasPrefix(s, "heuristic") {
		return false
	}
	return true
}

func extractLyricsSourceFromLRC(lrc string) string {
	for _, line := range strings.Split(lrc, "\n") {
		trimmed := strings.TrimSpace(line)
		if !strings.HasPrefix(strings.ToLower(trimmed), "[by:") {
			continue
		}
		idx := strings.Index(trimmed, lrcSourceMarker)
		if idx < 0 {
			return ""
		}
		rest := strings.TrimSpace(trimmed[idx+len(lrcSourceMarker):])
		rest = strings.TrimSuffix(rest, "]")
		rest = strings.TrimSuffix(rest, ")")
		return strings.TrimSpace(rest)
	}
	return ""
}

func convertToLRCWithMetadata(lyrics *LyricsResponse, trackName, artistName string) string {
	if lyrics == nil || len(lyrics.Lines) == 0 {
		return ""
	}

	var builder strings.Builder

	builder.WriteString(fmt.Sprintf("[ti:%s]\n", trackName))
	builder.WriteString(fmt.Sprintf("[ar:%s]\n", artistName))
	source := strings.TrimSpace(lyrics.Source)
	if source == "" {
		source = strings.TrimSpace(lyrics.Provider)
	}
	credit := "SpotiFLAC-Mobile"
	if lyricsSourceUsesPaxsenix(source) {
		credit = "SpotiFLAC-Mobile via Paxsenix API"
	}
	if source == "" {
		builder.WriteString(fmt.Sprintf("[by:%s]\n", credit))
	} else {
		builder.WriteString(
			fmt.Sprintf("[by:%s %s%s)]\n", credit, lrcSourceMarker, source),
		)
	}
	builder.WriteString("\n")

	if lyrics.SyncType == "LINE_SYNCED" {
		for _, line := range lyrics.Lines {
			if line.Words == "" {
				continue
			}
			timestamp := msToLRCTimestamp(line.StartTimeMs)
			builder.WriteString(timestamp)
			builder.WriteString(line.Words)
			builder.WriteString("\n")
		}
	} else {
		for _, line := range lyrics.Lines {
			if line.Words == "" {
				continue
			}
			builder.WriteString(line.Words)
			builder.WriteString("\n")
		}
	}

	return builder.String()
}

func simplifyTrackName(name string) string {
	patterns := []string{
		`\s*\(feat\..*?\)`,
		`\s*\(ft\..*?\)`,
		`\s*\(featuring.*?\)`,
		`\s*\(with.*?\)`,
		`\s*-\s*Remaster(ed)?.*$`,
		`\s*-\s*\d{4}\s*Remaster.*$`,
		`\s*\(Remaster(ed)?.*?\)`,
		`\s*\(Deluxe.*?\)`,
		`\s*\(Bonus.*?\)`,
		`\s*\(Live.*?\)`,
		`\s*\(Acoustic.*?\)`,
		`\s*\(Radio Edit\)`,
		`\s*\(Single Version\)`,
	}

	result := name
	for _, pattern := range patterns {
		re := regexp.MustCompile("(?i)" + pattern)
		result = re.ReplaceAllString(result, "")
	}
	result = strings.TrimSpace(result)
	if result == "" {
		return result
	}

	if loose := normalizeLooseTitle(result); loose != "" {
		return loose
	}

	return result
}

func normalizeArtistName(name string) string {
	separators := []string{", ", "; ", " & ", " feat. ", " ft. ", " featuring ", " with "}

	result := name
	for _, sep := range separators {
		if idx := strings.Index(strings.ToLower(result), strings.ToLower(sep)); idx > 0 {
			result = result[:idx]
			break
		}
	}

	return strings.TrimSpace(result)
}

func isLikelyInstrumentalTrack(name string) bool {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" {
		return false
	}

	return instrumentalTrackPattern.MatchString(trimmed)
}

func SaveLRCFile(audioFilePath, lrcContent string) (string, error) {
	if lrcContent == "" {
		return "", fmt.Errorf("empty LRC content")
	}

	dir := filepath.Dir(audioFilePath)
	ext := filepath.Ext(audioFilePath)
	baseName := strings.TrimSuffix(filepath.Base(audioFilePath), ext)

	lrcFilePath := filepath.Join(dir, baseName+".lrc")

	if err := os.WriteFile(lrcFilePath, []byte(lrcContent), 0644); err != nil {
		return "", fmt.Errorf("failed to write LRC file: %w", err)
	}

	GoLog("[Lyrics] Saved LRC file: %s\n", lrcFilePath)
	return lrcFilePath, nil
}
