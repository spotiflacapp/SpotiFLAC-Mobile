package gobackend

import (
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

type SpotifyLyricsClient struct {
	httpClient *http.Client
}

type DeezerLyricsClient struct {
	httpClient *http.Client
}

type YouTubeLyricsClient struct {
	httpClient *http.Client
}

type KugouLyricsClient struct {
	httpClient *http.Client
}

type GeniusLyricsClient struct {
	httpClient *http.Client
}

type spotifyLyricsSearchResult struct {
	TrackID    string `json:"trackId"`
	Name       string `json:"name"`
	ArtistName string `json:"artistName"`
	Duration   string `json:"duration"`
}

type youtubeLyricsSearchResult struct {
	VideoID  string `json:"videoId"`
	Title    string `json:"title"`
	Author   string `json:"author"`
	Duration string `json:"duration"`
}

type kugouLyricsSearchResult struct {
	Hash     string  `json:"hash"`
	Title    string  `json:"title"`
	Artist   string  `json:"artist"`
	Duration float64 `json:"duration"`
}

type geniusSearchResponse struct {
	Response struct {
		Sections []struct {
			Hits []struct {
				Type   string `json:"type"`
				Result struct {
					Title              string `json:"title"`
					ArtistNames        string `json:"artist_names"`
					PrimaryArtistNames string `json:"primary_artist_names"`
					URL                string `json:"url"`
				} `json:"result"`
			} `json:"hits"`
		} `json:"sections"`
	} `json:"response"`
}

type paxsenixLyricsObject struct {
	Type        string      `json:"type"`
	Content     []paxLyrics `json:"content"`
	Lyrics      []paxLyrics `json:"lyrics"`
	LyricsText  string      `json:"lyrics_text"`
	PlainLyrics string      `json:"plain_lyrics"`
}

func NewSpotifyLyricsClient() *SpotifyLyricsClient {
	return &SpotifyLyricsClient{httpClient: NewMetadataHTTPClient(15 * time.Second)}
}

func NewDeezerLyricsClient() *DeezerLyricsClient {
	return &DeezerLyricsClient{httpClient: NewMetadataHTTPClient(15 * time.Second)}
}

func NewYouTubeLyricsClient() *YouTubeLyricsClient {
	return &YouTubeLyricsClient{httpClient: NewMetadataHTTPClient(15 * time.Second)}
}

func NewKugouLyricsClient() *KugouLyricsClient {
	return &KugouLyricsClient{httpClient: NewMetadataHTTPClient(15 * time.Second)}
}

func NewGeniusLyricsClient() *GeniusLyricsClient {
	return &GeniusLyricsClient{httpClient: NewMetadataHTTPClient(15 * time.Second)}
}

func fetchPaxsenixBody(httpClient *http.Client, endpoint string, params url.Values) (string, error) {
	fullURL := endpoint
	if len(params) > 0 {
		fullURL += "?" + params.Encode()
	}

	req, err := http.NewRequest("GET", fullURL, nil)
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", appUserAgent())

	resp, err := httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	trimmed := strings.TrimSpace(string(body))
	if resp.StatusCode != http.StatusOK {
		if errMsg, isErrorPayload := detectLyricsErrorPayload(trimmed); isErrorPayload {
			return "", fmt.Errorf("HTTP %d: %s", resp.StatusCode, errMsg)
		}
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	if errMsg, isErrorPayload := detectLyricsErrorPayload(trimmed); isErrorPayload {
		return "", fmt.Errorf("%s", errMsg)
	}
	if trimmed == "" {
		return "", fmt.Errorf("empty response")
	}
	return trimmed, nil
}

func parsePaxsenixLyricsPayload(raw, provider string, multiPersonWordByWord bool) (*LyricsResponse, error) {
	var lrcPayload string
	if err := json.Unmarshal([]byte(raw), &lrcPayload); err == nil {
		lrcPayload = strings.TrimSpace(lrcPayload)
		if lrcPayload == "" {
			return nil, fmt.Errorf("%s returned empty lyrics", provider)
		}
		return lyricsResponseFromText(lrcPayload, provider), nil
	}

	var rawObject map[string]json.RawMessage
	if err := json.Unmarshal([]byte(raw), &rawObject); err == nil {
		for _, key := range []string{"lyrics", "lyric", "lyrics_text", "plain_lyrics"} {
			var value string
			if rawValue, ok := rawObject[key]; ok && json.Unmarshal(rawValue, &value) == nil {
				value = strings.TrimSpace(value)
				if value != "" {
					return lyricsResponseFromText(value, provider), nil
				}
			}
		}
	}

	var payload paxsenixLyricsObject
	if err := json.Unmarshal([]byte(raw), &payload); err == nil {
		switch {
		case strings.TrimSpace(payload.LyricsText) != "":
			return lyricsResponseFromText(payload.LyricsText, provider), nil
		case len(payload.Lyrics) > 0:
			return lyricsResponseFromText(formatPaxContent("Syllable", payload.Lyrics, multiPersonWordByWord, true), provider), nil
		case len(payload.Content) > 0:
			lyricsType := payload.Type
			if lyricsType == "" {
				lyricsType = "Syllable"
			}
			return lyricsResponseFromText(formatPaxContent(lyricsType, payload.Content, multiPersonWordByWord, true), provider), nil
		case strings.TrimSpace(payload.PlainLyrics) != "":
			return lyricsResponseFromText(payload.PlainLyrics, provider), nil
		}
	}

	trimmed := strings.TrimSpace(raw)
	if trimmed != "" && !strings.HasPrefix(trimmed, "{") && !strings.HasPrefix(trimmed, "[") {
		return lyricsResponseFromText(trimmed, provider), nil
	}
	return nil, fmt.Errorf("failed to decode %s lyrics response", provider)
}

func lyricsResponseFromText(text, provider string) *LyricsResponse {
	lines := parseSyncedLyrics(text)
	if len(lines) > 0 {
		return &LyricsResponse{
			Lines:       lines,
			SyncType:    "LINE_SYNCED",
			PlainLyrics: plainLyricsFromTimedLines(lines),
			Provider:    provider,
			Source:      provider,
		}
	}

	plainLines := plainTextLyricsLines(text)
	if len(plainLines) > 0 {
		return &LyricsResponse{
			Lines:       plainLines,
			SyncType:    "UNSYNCED",
			PlainLyrics: text,
			Provider:    provider,
			Source:      provider,
		}
	}

	return &LyricsResponse{Provider: provider, Source: provider}
}

func normalizeSpotifyLyricsID(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" || strings.HasPrefix(strings.ToLower(raw), "deezer:") {
		return ""
	}
	if strings.HasPrefix(strings.ToLower(raw), "spotify:") {
		parts := strings.Split(raw, ":")
		raw = parts[len(parts)-1]
	}
	if strings.Contains(raw, "spotify.com/track/") {
		raw = extractSpotifyIDFromURL(raw)
	}
	raw = strings.TrimSpace(strings.Split(raw, "?")[0])
	if regexpSpotifyTrackID.MatchString(raw) {
		return raw
	}
	return ""
}

var regexpSpotifyTrackID = regexp.MustCompile(`^[A-Za-z0-9]{22}$`)

func (c *SpotifyLyricsClient) SearchSong(trackName, artistName string, durationSec float64) (string, error) {
	query := strings.TrimSpace(trackName + " " + artistName)
	if query == "" {
		return "", fmt.Errorf("empty search query")
	}

	params := url.Values{}
	params.Set("q", query)
	raw, err := fetchPaxsenixBody(c.httpClient, "https://lyrics.paxsenix.org/spotify/search", params)
	if err != nil {
		return "", fmt.Errorf("spotify search failed: %w", err)
	}

	var results []spotifyLyricsSearchResult
	if err := json.Unmarshal([]byte(raw), &results); err != nil {
		return "", fmt.Errorf("failed to decode spotify search: %w", err)
	}
	best := selectBestSpotifyLyricsSearchResult(results, trackName, artistName, durationSec)
	if best == nil || strings.TrimSpace(best.TrackID) == "" {
		return "", fmt.Errorf("no songs found on spotify")
	}
	return strings.TrimSpace(best.TrackID), nil
}

func selectBestSpotifyLyricsSearchResult(results []spotifyLyricsSearchResult, trackName, artistName string, durationSec float64) *spotifyLyricsSearchResult {
	if len(results) == 0 {
		return nil
	}

	bestIndex := 0
	bestScore := -1
	for i := range results {
		result := &results[i]
		score := scoreLyricsSearchCandidate(result.Name, result.ArtistName, parseClockDuration(result.Duration), trackName, artistName, durationSec)
		if score > bestScore {
			bestIndex = i
			bestScore = score
		}
	}
	return &results[bestIndex]
}

func (c *SpotifyLyricsClient) FetchLyricsByID(trackID string) (*LyricsResponse, error) {
	params := url.Values{}
	params.Set("id", trackID)
	raw, err := fetchPaxsenixBody(c.httpClient, "https://lyrics.paxsenix.org/spotify/lyrics", params)
	if err != nil {
		return nil, fmt.Errorf("spotify lyrics fetch failed: %w", err)
	}
	return parsePaxsenixLyricsPayload(raw, "Spotify", false)
}

func (c *SpotifyLyricsClient) FetchLyrics(spotifyID, trackName, artistName string, durationSec float64) (*LyricsResponse, error) {
	trackID := normalizeSpotifyLyricsID(spotifyID)
	if trackID == "" {
		var err error
		trackID, err = c.SearchSong(trackName, artistName, durationSec)
		if err != nil {
			return nil, err
		}
	}
	return c.FetchLyricsByID(trackID)
}

func normalizeDeezerLyricsID(raw string) string {
	raw = strings.TrimSpace(raw)
	if strings.HasPrefix(strings.ToLower(raw), "deezer:") {
		raw = strings.TrimSpace(raw[len("deezer:"):])
	}
	if strings.Contains(raw, "deezer.com/") {
		raw = extractDeezerIDFromURL(raw)
	}
	raw = strings.TrimSpace(strings.Split(raw, "?")[0])
	if _, err := strconv.ParseInt(raw, 10, 64); err == nil {
		return raw
	}
	return ""
}

func (c *DeezerLyricsClient) FetchLyricsByID(trackID string, multiPersonWordByWord bool) (*LyricsResponse, error) {
	params := url.Values{}
	params.Set("id", trackID)
	raw, err := fetchPaxsenixBody(c.httpClient, "https://lyrics.paxsenix.org/deezer/lyrics", params)
	if err != nil {
		return nil, fmt.Errorf("deezer lyrics fetch failed: %w", err)
	}
	return parsePaxsenixLyricsPayload(raw, "Deezer", multiPersonWordByWord)
}

func (c *DeezerLyricsClient) FetchLyrics(spotifyID, trackName, artistName string, durationSec float64) (*LyricsResponse, error) {
	deezerID := normalizeDeezerLyricsID(spotifyID)
	if deezerID == "" {
		spotifyTrackID := normalizeSpotifyLyricsID(spotifyID)
		if spotifyTrackID == "" {
			return nil, fmt.Errorf("deezer provider needs a deezer id or spotify id")
		}
		resolvedID, err := NewSongLinkClient().GetDeezerIDFromSpotify(spotifyTrackID)
		if err != nil {
			return nil, fmt.Errorf("failed to resolve deezer id: %w", err)
		}
		deezerID = normalizeDeezerLyricsID(resolvedID)
	}
	if deezerID == "" {
		return nil, fmt.Errorf("deezer id unavailable")
	}
	return c.FetchLyricsByID(deezerID, true)
}

func (c *YouTubeLyricsClient) SearchSong(trackName, artistName string, durationSec float64) (string, error) {
	query := strings.TrimSpace(trackName + " " + artistName)
	if query == "" {
		return "", fmt.Errorf("empty search query")
	}

	params := url.Values{}
	params.Set("q", query)
	raw, err := fetchPaxsenixBody(c.httpClient, "https://lyrics.paxsenix.org/youtube/search", params)
	if err != nil {
		return "", fmt.Errorf("youtube search failed: %w", err)
	}

	var results []youtubeLyricsSearchResult
	if err := json.Unmarshal([]byte(raw), &results); err != nil {
		return "", fmt.Errorf("failed to decode youtube search: %w", err)
	}
	best := selectBestYouTubeLyricsSearchResult(results, trackName, artistName, durationSec)
	if best == nil || strings.TrimSpace(best.VideoID) == "" {
		return "", fmt.Errorf("no songs found on youtube")
	}
	return strings.TrimSpace(best.VideoID), nil
}

func selectBestYouTubeLyricsSearchResult(results []youtubeLyricsSearchResult, trackName, artistName string, durationSec float64) *youtubeLyricsSearchResult {
	if len(results) == 0 {
		return nil
	}

	bestIndex := 0
	bestScore := -1
	for i := range results {
		result := &results[i]
		score := scoreLyricsSearchCandidate(result.Title, result.Author, parseClockDuration(result.Duration), trackName, artistName, durationSec)
		if score > bestScore {
			bestIndex = i
			bestScore = score
		}
	}
	return &results[bestIndex]
}

func (c *YouTubeLyricsClient) FetchLyrics(trackName, artistName string, durationSec float64) (*LyricsResponse, error) {
	videoID, err := c.SearchSong(trackName, artistName, durationSec)
	if err != nil {
		return nil, err
	}

	params := url.Values{}
	params.Set("id", videoID)
	raw, err := fetchPaxsenixBody(c.httpClient, "https://lyrics.paxsenix.org/youtube/lyrics", params)
	if err != nil {
		return nil, fmt.Errorf("youtube lyrics fetch failed: %w", err)
	}
	return parsePaxsenixLyricsPayload(raw, "YouTube", false)
}

func (c *KugouLyricsClient) SearchSong(trackName, artistName string, durationSec float64) (string, error) {
	query := strings.TrimSpace(trackName + " " + artistName)
	if query == "" {
		return "", fmt.Errorf("empty search query")
	}

	params := url.Values{}
	params.Set("q", query)
	raw, err := fetchPaxsenixBody(c.httpClient, "https://lyrics.paxsenix.org/kugou/search", params)
	if err != nil {
		return "", fmt.Errorf("kugou search failed: %w", err)
	}

	var results []kugouLyricsSearchResult
	if err := json.Unmarshal([]byte(raw), &results); err != nil {
		return "", fmt.Errorf("failed to decode kugou search: %w", err)
	}
	best := selectBestKugouLyricsSearchResult(results, trackName, artistName, durationSec)
	if best == nil || strings.TrimSpace(best.Hash) == "" {
		return "", fmt.Errorf("no songs found on kugou")
	}
	return strings.TrimSpace(best.Hash), nil
}

func selectBestKugouLyricsSearchResult(results []kugouLyricsSearchResult, trackName, artistName string, durationSec float64) *kugouLyricsSearchResult {
	if len(results) == 0 {
		return nil
	}

	bestIndex := 0
	bestScore := -1
	for i := range results {
		result := &results[i]
		score := scoreLyricsSearchCandidate(result.Title, result.Artist, result.Duration, trackName, artistName, durationSec)
		if score > bestScore {
			bestIndex = i
			bestScore = score
		}
	}
	return &results[bestIndex]
}

func (c *KugouLyricsClient) FetchLyrics(trackName, artistName string, durationSec float64) (*LyricsResponse, error) {
	hash, err := c.SearchSong(trackName, artistName, durationSec)
	if err != nil {
		return nil, err
	}

	params := url.Values{}
	params.Set("id", hash)
	raw, err := fetchPaxsenixBody(c.httpClient, "https://lyrics.paxsenix.org/kugou/lyrics", params)
	if err != nil {
		return nil, fmt.Errorf("kugou lyrics fetch failed: %w", err)
	}
	return parsePaxsenixLyricsPayload(raw, "Kugou", false)
}

func (c *GeniusLyricsClient) SearchSong(trackName, artistName string, durationSec float64) (string, error) {
	query := strings.TrimSpace(trackName + " " + artistName)
	if query == "" {
		return "", fmt.Errorf("empty search query")
	}

	params := url.Values{}
	params.Set("q", query)
	params.Set("per_page", "10")
	raw, err := fetchPaxsenixBody(c.httpClient, "https://genius.com/api/search/multi", params)
	if err != nil {
		return "", fmt.Errorf("genius search failed: %w", err)
	}

	var results geniusSearchResponse
	if err := json.Unmarshal([]byte(raw), &results); err != nil {
		return "", fmt.Errorf("failed to decode genius search: %w", err)
	}

	bestURL := ""
	bestScore := -1
	for _, section := range results.Response.Sections {
		for _, hit := range section.Hits {
			if hit.Type != "song" || strings.TrimSpace(hit.Result.URL) == "" {
				continue
			}

			artist := hit.Result.PrimaryArtistNames
			if strings.TrimSpace(artist) == "" {
				artist = hit.Result.ArtistNames
			}
			score := scoreLyricsSearchCandidate(hit.Result.Title, artist, 0, trackName, artistName, durationSec)
			if score > bestScore {
				bestScore = score
				bestURL = strings.TrimSpace(hit.Result.URL)
			}
		}
	}

	if bestURL == "" {
		return "", fmt.Errorf("no songs found on genius")
	}
	return bestURL, nil
}

func (c *GeniusLyricsClient) FetchLyrics(trackName, artistName string, durationSec float64) (*LyricsResponse, error) {
	geniusURL, err := c.SearchSong(trackName, artistName, durationSec)
	if err != nil {
		return nil, err
	}

	params := url.Values{}
	params.Set("url", geniusURL)
	raw, err := fetchPaxsenixBody(c.httpClient, "https://lyrics.paxsenix.org/genius/lyrics", params)
	if err != nil {
		return nil, fmt.Errorf("genius lyrics fetch failed: %w", err)
	}
	return parsePaxsenixLyricsPayload(raw, "Genius", false)
}

func scoreLyricsSearchCandidate(candidateTrack, candidateArtist string, candidateDuration float64, trackName, artistName string, durationSec float64) int {
	normalizedTrack := strings.ToLower(strings.TrimSpace(simplifyTrackName(trackName)))
	normalizedArtist := strings.ToLower(strings.TrimSpace(normalizeArtistName(artistName)))
	candidateTrack = strings.ToLower(strings.TrimSpace(simplifyTrackName(candidateTrack)))
	candidateArtist = strings.ToLower(strings.TrimSpace(normalizeArtistName(candidateArtist)))

	score := 0
	switch {
	case candidateTrack == normalizedTrack:
		score += 50
	case strings.Contains(candidateTrack, normalizedTrack) || strings.Contains(normalizedTrack, candidateTrack):
		score += 25
	}

	switch {
	case candidateArtist == normalizedArtist:
		score += 60
	case strings.Contains(candidateArtist, normalizedArtist) || strings.Contains(normalizedArtist, candidateArtist):
		score += 30
	}

	if durationSec > 0 && candidateDuration > 0 {
		diff := math.Abs(candidateDuration - durationSec)
		if diff <= durationToleranceSec {
			score += 20
		}
	}

	return score
}

func parseClockDuration(value string) float64 {
	value = strings.TrimSpace(value)
	if value == "" {
		return 0
	}

	parts := strings.Split(value, ":")
	total := 0
	for _, part := range parts {
		n, err := strconv.Atoi(strings.TrimSpace(part))
		if err != nil {
			return 0
		}
		total = total*60 + n
	}
	return float64(total)
}
