package gobackend

import (
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	lyricsCacheTTL       = 24 * time.Hour
	durationToleranceSec = 10.0
)

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

func lrclibTrackName(response *LRCLibResponse) string {
	if response == nil {
		return ""
	}
	if trackName := strings.TrimSpace(response.TrackName); trackName != "" {
		return trackName
	}
	return strings.TrimSpace(response.Name)
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

// lrclibGet performs a GET against lrclib.net and decodes the JSON body into
// dst. 404 is reported as a typed lyrics-not-found error.
func (c *LyricsClient) lrclibGet(path string, params url.Values, dst any) error {
	req, err := http.NewRequest("GET", "https://lrclib.net"+path+"?"+params.Encode(), nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("User-Agent", getRandomUserAgent())

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to fetch lyrics: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == 404 {
		return lyricsNotFoundErrorf("lyrics not found")
	}
	if resp.StatusCode != 200 {
		return lyricsHTTPStatusError(resp.StatusCode, "unexpected status code: %d", resp.StatusCode)
	}

	if err := json.NewDecoder(resp.Body).Decode(dst); err != nil {
		return fmt.Errorf("failed to decode response: %w", err)
	}
	return nil
}

func (c *LyricsClient) FetchLyricsWithMetadata(artist, track string) (*LyricsResponse, error) {
	params := url.Values{}
	params.Set("artist_name", artist)
	params.Set("track_name", track)

	var lrcResp LRCLibResponse
	if err := c.lrclibGet("/api/get", params, &lrcResp); err != nil {
		return nil, err
	}
	if !lyricsSearchTitlesMatch(lrclibTrackName(&lrcResp), track, false) ||
		!lyricsSearchArtistsMatch(lrcResp.ArtistName, artist) {
		return nil, lyricsNotFoundErrorf("LRCLIB returned mismatched track metadata")
	}

	return c.parseLRCLibResponse(&lrcResp), nil
}

func (c *LyricsClient) fetchLyricsFromLRCLibSearch(query, trackName, artistName string, durationSec float64) (*LyricsResponse, error) {
	params := url.Values{}
	params.Set("q", query)

	var results []LRCLibResponse
	if err := c.lrclibGet("/api/search", params, &results); err != nil {
		return nil, err
	}

	if len(results) == 0 {
		return nil, lyricsNotFoundErrorf("no lyrics found")
	}

	bestMatch := c.findBestLRCLibSearchMatch(results, query, trackName, artistName, durationSec)
	if bestMatch != nil {
		return c.parseLRCLibResponse(bestMatch), nil
	}

	return nil, lyricsNotFoundErrorf("no matching lyrics found")
}

func lrclibSearchResultMatches(result *LRCLibResponse, query, trackName, artistName string, durationSec float64) bool {
	if result == nil || !lyricsSearchDurationMatches(result.Duration, durationSec) {
		return false
	}

	candidateTrack := lrclibTrackName(result)
	if strings.TrimSpace(trackName) != "" || strings.TrimSpace(artistName) != "" {
		return lyricsSearchTitlesMatch(candidateTrack, trackName, false) &&
			lyricsSearchArtistsMatch(result.ArtistName, artistName)
	}

	normalizedQuery := normalizeLooseArtistName(query)
	normalizedTrack := normalizeLooseArtistName(simplifyTrackName(candidateTrack))
	normalizedArtist := normalizeLooseArtistName(normalizeArtistName(result.ArtistName))
	return normalizedQuery != "" &&
		normalizedTrack != "" &&
		normalizedArtist != "" &&
		containsWordSequence(normalizedQuery, normalizedTrack) &&
		containsWordSequence(normalizedQuery, normalizedArtist)
}

func (c *LyricsClient) findBestLRCLibSearchMatch(results []LRCLibResponse, query, trackName, artistName string, targetDurationSec float64) *LRCLibResponse {
	var bestSynced *LRCLibResponse
	var bestPlain *LRCLibResponse

	for i := range results {
		result := &results[i]
		if !lrclibSearchResultMatches(result, query, trackName, artistName, targetDurationSec) {
			continue
		}
		if result.SyncedLyrics != "" && bestSynced == nil {
			bestSynced = result
		} else if result.PlainLyrics != "" && bestPlain == nil {
			bestPlain = result
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
	lyrics, err = c.fetchLyricsFromLRCLibSearch(query, trackName, primaryArtist, durationSec)
	if err == nil && lyrics != nil && (len(lyrics.Lines) > 0 || lyrics.Instrumental) {
		lyrics.Source = "LRCLIB Search"
		return lyrics, nil
	}
	if isLyricsProviderUnavailableError(err) {
		return nil, err
	}

	if simplifiedTrack != trackName {
		query = primaryArtist + " " + simplifiedTrack
		lyrics, err = c.fetchLyricsFromLRCLibSearch(query, simplifiedTrack, primaryArtist, durationSec)
		if err == nil && lyrics != nil && (len(lyrics.Lines) > 0 || lyrics.Instrumental) {
			lyrics.Source = "LRCLIB Search (simplified)"
			return lyrics, nil
		}
		if isLyricsProviderUnavailableError(err) {
			return nil, err
		}
	}

	return nil, lyricsNotFoundErrorf("LRCLIB: no lyrics found")
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
