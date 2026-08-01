package gobackend

import (
	"bytes"
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"
)

const (
	spotifySize300 = "ab67616d00001e02"
	spotifySize640 = "ab67616d0000b273"
	spotifySizeMax = "ab67616d000082c1"
)

// Square CDN covers using this path shape may return an image whose decoded
// dimensions differ from the dimensions advertised in the URL. Max-quality
// selection therefore probes both useful high-resolution variants and checks
// the image headers instead of trusting the filename.
var squareCoverSizeRegex = regexp.MustCompile(`/(\d+)x(\d+)-\d+-\d+-\d+-\d+\.jpg$`)

var tidalSizeRegex = regexp.MustCompile(`/\d+x\d+\.jpg$`)

var qobuzSizeRegex = regexp.MustCompile(`_\d+\.jpg$`)

func convertSmallToMedium(imageURL string) string {
	if strings.Contains(imageURL, spotifySize300) {
		return strings.Replace(imageURL, spotifySize300, spotifySize640, 1)
	}
	return imageURL
}

func downloadCoverToMemory(coverURL string, maxQuality bool) ([]byte, error) {
	if coverURL == "" {
		return nil, fmt.Errorf("no cover URL provided")
	}

	GoLog("[Cover] Original URL: %s", coverURL)

	downloadURL := convertSmallToMedium(coverURL)
	if downloadURL != coverURL {
		GoLog("[Cover] Upgraded 300x300 → 640x640")
	}

	if !maxQuality {
		GoLog("[Cover] Final URL: %s", downloadURL)
		data, err := fetchCoverCached(downloadURL)
		if err != nil {
			return nil, err
		}
		return append([]byte(nil), data...), nil
	}

	candidates := maxQualityCoverCandidateURLs(downloadURL)
	data, selectedURL, width, height, err := fetchBestCoverCandidate(candidates)
	if err != nil {
		// A CDN can reject an upgraded size while the provider-supplied URL is
		// still valid. Preserve that URL as the final fallback.
		if len(candidates) == 1 && candidates[0] == downloadURL {
			return nil, err
		}
		data, err = fetchCoverCached(downloadURL)
		if err != nil {
			return nil, err
		}
		selectedURL = downloadURL
		width, height = coverDimensions(data)
	}
	GoLog("[Cover] Selected URL: %s (%dx%d, %d KB)", selectedURL, width, height, len(data)/1024)
	// Cached bytes are shared across goroutines and must never be mutated;
	// hand callers their own copy.
	return append([]byte(nil), data...), nil
}

type fetchedCoverCandidate struct {
	url           string
	data          []byte
	width, height int
	err           error
}

func maxQualityCoverCandidateURLs(coverURL string) []string {
	upgraded := upgradeToMaxQuality(coverURL)
	candidates := []string{upgraded}
	// This is deliberately based on the URL capability rather than a provider
	// or extension ID. Any metadata source returning the same square-cover URL
	// shape receives the same verified candidate selection.
	if squareCoverSizeRegex.MatchString(coverURL) {
		candidate1500 := squareCoverSizeRegex.ReplaceAllString(
			coverURL,
			"/1500x1500-000000-80-0-0.jpg",
		)
		if candidate1500 != upgraded {
			candidates = append(candidates, candidate1500)
		}
	}
	return uniqueNonEmptyStrings(candidates)
}

func uniqueNonEmptyStrings(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	return result
}

func fetchBestCoverCandidate(urls []string) ([]byte, string, int, int, error) {
	if len(urls) == 0 {
		return nil, "", 0, 0, fmt.Errorf("no cover candidates available")
	}
	results := make(chan fetchedCoverCandidate, len(urls))
	for _, candidateURL := range urls {
		go func(url string) {
			data, err := fetchCoverCached(url)
			width, height := coverDimensions(data)
			results <- fetchedCoverCandidate{
				url: url, data: data, width: width, height: height, err: err,
			}
		}(candidateURL)
	}

	var best *fetchedCoverCandidate
	var firstErr error
	for range urls {
		candidate := <-results
		if candidate.err != nil || len(candidate.data) == 0 {
			if firstErr == nil {
				firstErr = candidate.err
			}
			continue
		}
		if best == nil || coverCandidateBetter(candidate, *best) {
			copy := candidate
			best = &copy
		}
	}
	if best == nil {
		if firstErr == nil {
			firstErr = fmt.Errorf("cover candidates returned no image data")
		}
		return nil, "", 0, 0, firstErr
	}
	return best.data, best.url, best.width, best.height, nil
}

func coverDimensions(data []byte) (int, int) {
	if len(data) == 0 {
		return 0, 0
	}
	config, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil || config.Width <= 0 || config.Height <= 0 {
		return 0, 0
	}
	return config.Width, config.Height
}

func coverCandidateBetter(candidate, current fetchedCoverCandidate) bool {
	candidatePixels := int64(candidate.width) * int64(candidate.height)
	currentPixels := int64(current.width) * int64(current.height)
	if candidatePixels != currentPixels {
		return candidatePixels > currentPixels
	}
	return len(candidate.data) > len(current.data)
}

const (
	coverCacheMaxBytes = 24 * 1024 * 1024
	coverCacheTTL      = 15 * time.Minute
)

type coverCacheEntry struct {
	data      []byte
	expiresAt time.Time
}

type coverInflightCall struct {
	wg   sync.WaitGroup
	data []byte
	err  error
}

var (
	coverMu         sync.Mutex
	coverCache      = map[string]*coverCacheEntry{}
	coverCacheBytes int
	coverInflight   = map[string]*coverInflightCall{}
	coverFetch      = fetchCoverBytes
)

func clearCoverMemoryCache() {
	coverMu.Lock()
	coverCache = map[string]*coverCacheEntry{}
	coverCacheBytes = 0
	coverMu.Unlock()
}

// fetchCoverCached returns cover bytes for a final URL, collapsing concurrent
// requests for the same URL into a single fetch (singleflight) and caching
// results in memory for the duration of an album batch. The returned slice is
// shared; callers must copy before mutating.
func fetchCoverCached(downloadURL string) ([]byte, error) {
	coverMu.Lock()
	if e, ok := coverCache[downloadURL]; ok {
		if time.Now().Before(e.expiresAt) {
			data := e.data
			coverMu.Unlock()
			return data, nil
		}
		delete(coverCache, downloadURL)
		coverCacheBytes -= len(e.data)
	}
	if call, ok := coverInflight[downloadURL]; ok {
		coverMu.Unlock()
		call.wg.Wait()
		return call.data, call.err
	}
	call := &coverInflightCall{}
	// Default error so a panicking fetch never strands waiters with a
	// (nil, nil) "success"; overwritten on normal completion.
	call.err = fmt.Errorf("cover fetch aborted")
	call.wg.Add(1)
	coverInflight[downloadURL] = call
	coverMu.Unlock()

	defer func() {
		call.wg.Done()
		coverMu.Lock()
		delete(coverInflight, downloadURL)
		coverMu.Unlock()
	}()

	data, err := coverFetch(downloadURL)
	call.data, call.err = data, err
	if err == nil {
		coverCachePut(downloadURL, data)
	}
	return data, err
}

func coverCachePut(downloadURL string, data []byte) {
	if len(data) == 0 || len(data) > coverCacheMaxBytes {
		return
	}
	coverMu.Lock()
	defer coverMu.Unlock()
	if e, ok := coverCache[downloadURL]; ok {
		coverCacheBytes -= len(e.data)
	}
	coverCache[downloadURL] = &coverCacheEntry{data: data, expiresAt: time.Now().Add(coverCacheTTL)}
	coverCacheBytes += len(data)
	for coverCacheBytes > coverCacheMaxBytes && len(coverCache) > 1 {
		var oldestKey string
		var oldest time.Time
		first := true
		for k, e := range coverCache {
			if first || e.expiresAt.Before(oldest) {
				oldest, oldestKey, first = e.expiresAt, k, false
			}
		}
		coverCacheBytes -= len(coverCache[oldestKey].data)
		delete(coverCache, oldestKey)
	}
}

func fetchCoverBytes(downloadURL string) ([]byte, error) {
	client := NewHTTPClientWithTimeout(DefaultTimeout)

	req, err := http.NewRequest("GET", downloadURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := DoRequestWithUserAgent(client, req)
	if err != nil {
		return nil, fmt.Errorf("failed to download cover: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("cover download failed: HTTP %d", resp.StatusCode)
	}

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read cover data: %w", err)
	}

	width, height := coverDimensions(data)
	GoLog("[Cover] Downloaded %d KB (%dx%d)", len(data)/1024, width, height)

	return data, nil
}

func upgradeToMaxQuality(coverURL string) string {
	if strings.Contains(coverURL, spotifySize640) {
		return strings.Replace(coverURL, spotifySize640, spotifySizeMax, 1)
	}

	if squareCoverSizeRegex.MatchString(coverURL) {
		return upgradeSquareCover(coverURL)
	}

	if strings.Contains(coverURL, "resources.tidal.com") {
		return upgradeTidalCover(coverURL)
	}

	if strings.Contains(coverURL, "static.qobuz.com") {
		return upgradeQobuzCover(coverURL)
	}

	return coverURL
}

func upgradeSquareCover(coverURL string) string {
	if !squareCoverSizeRegex.MatchString(coverURL) {
		return coverURL
	}

	upgraded := squareCoverSizeRegex.ReplaceAllString(coverURL, "/1900x1900-000000-80-0-0.jpg")
	if upgraded != coverURL {
		GoLog("[Cover] Square CDN: probing 1900x1900 and 1500x1500")
	}
	return upgraded
}

func upgradeTidalCover(coverURL string) string {
	if !strings.Contains(coverURL, "resources.tidal.com") {
		return coverURL
	}

	upgraded := tidalSizeRegex.ReplaceAllString(coverURL, "/origin.jpg")
	if upgraded != coverURL {
		GoLog("[Cover] Tidal: upgraded to origin resolution")
	}
	return upgraded
}

func upgradeQobuzCover(coverURL string) string {
	if !strings.Contains(coverURL, "static.qobuz.com") {
		return coverURL
	}

	upgraded := qobuzSizeRegex.ReplaceAllString(coverURL, "_max.jpg")
	if upgraded != coverURL {
		GoLog("[Cover] Qobuz: upgraded to max resolution")
	}
	return upgraded
}
