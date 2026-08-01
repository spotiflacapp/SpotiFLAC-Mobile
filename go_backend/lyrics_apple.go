package gobackend

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"
)

var errAppleMusicUnauthorized = errors.New("apple music catalog search unauthorized")

type AppleMusicClient struct {
	httpClient *http.Client
}

const appleMusicCatalogBaseURL = "https://amp-api.music.apple.com/v1/catalog/us"

type appleMusicSearchResult struct {
	ID         string `json:"id"`
	SongName   string `json:"songName"`
	ArtistName string `json:"artistName"`
	AlbumName  string `json:"albumName"`
	Duration   int    `json:"duration"`
}

type appleMusicCatalogSearchResponse struct {
	Results struct {
		Songs *struct {
			Data []struct {
				ID string `json:"id"`
			} `json:"data"`
		} `json:"songs"`
	} `json:"results"`
	Resources *struct {
		Songs map[string]struct {
			Attributes struct {
				Name             string `json:"name"`
				ArtistName       string `json:"artistName"`
				AlbumName        string `json:"albumName"`
				DurationInMillis int    `json:"durationInMillis"`
			} `json:"attributes"`
		} `json:"songs"`
	} `json:"resources"`
}

type paxResponse struct {
	Type            string      `json:"type"` // "Syllable" or "Line"
	Content         []paxLyrics `json:"content"`
	ELRC            string      `json:"elrc"`
	ELRCMultiPerson string      `json:"elrcMultiPerson"`
	Plain           string      `json:"plain"`
	TTMLContent     string      `json:"ttmlContent"`
}

type paxLyrics struct {
	Text           []paxLyricDetail `json:"text"`
	Timestamp      int              `json:"timestamp"`
	OppositeTurn   bool             `json:"oppositeTurn"`
	Background     bool             `json:"background"`
	BackgroundText []paxLyricDetail `json:"backgroundText"`
	EndTime        int              `json:"endtime"`
}

type paxLyricDetail struct {
	Text      string `json:"text"`
	Part      bool   `json:"part"`
	Timestamp *int   `json:"timestamp"`
	EndTime   *int   `json:"endtime"`
}

var (
	appleMusicTokenMu     sync.Mutex
	appleMusicCachedToken string
)

func NewAppleMusicClient() *AppleMusicClient {
	return &AppleMusicClient{
		httpClient: NewMetadataHTTPClient(20 * time.Second),
	}
}

func appleMusicSearchResultMatches(result appleMusicSearchResult, trackName, artistName string, durationSec float64) bool {
	if !lyricsSearchTitlesMatch(result.SongName, trackName, false) {
		return false
	}
	if !lyricsSearchArtistsMatch(result.ArtistName, artistName) {
		return false
	}
	if !lyricsSearchDurationMatches(float64(result.Duration)/1000.0, durationSec) {
		return false
	}
	return true
}

func selectBestAppleMusicSearchResult(results []appleMusicSearchResult, trackName, artistName string, durationSec float64) *appleMusicSearchResult {
	best := selectBestLyricsCandidate(len(results), trackName, artistName, durationSec, func(i int) (string, string, float64, bool) {
		result := &results[i]
		ok := appleMusicSearchResultMatches(*result, trackName, artistName, durationSec)
		return result.SongName, result.ArtistName, float64(result.Duration) / 1000.0, ok
	})
	if best < 0 {
		return nil
	}
	return &results[best]
}

func (c *AppleMusicClient) getAppleMusicToken() (string, error) {
	appleMusicTokenMu.Lock()
	defer appleMusicTokenMu.Unlock()

	if appleMusicCachedToken != "" {
		return appleMusicCachedToken, nil
	}

	req, err := http.NewRequest("GET", "https://beta.music.apple.com", nil)
	if err != nil {
		return "", fmt.Errorf("failed to create apple music page request: %w", err)
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to fetch apple music page: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", lyricsHTTPStatusError(resp.StatusCode, "apple music page returned HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read apple music page: %w", err)
	}

	indexPath := regexp.MustCompile(`/assets/index~[^"' <]+\.js`).FindString(string(body))
	if indexPath == "" {
		return "", fmt.Errorf("apple music index script not found")
	}

	jsReq, err := http.NewRequest("GET", "https://beta.music.apple.com"+indexPath, nil)
	if err != nil {
		return "", fmt.Errorf("failed to create apple music script request: %w", err)
	}
	jsReq.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

	jsResp, err := c.httpClient.Do(jsReq)
	if err != nil {
		return "", fmt.Errorf("failed to fetch apple music script: %w", err)
	}
	defer jsResp.Body.Close()

	if jsResp.StatusCode != http.StatusOK {
		return "", lyricsHTTPStatusError(jsResp.StatusCode, "apple music script returned HTTP %d", jsResp.StatusCode)
	}

	jsBody, err := io.ReadAll(jsResp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read apple music script: %w", err)
	}

	token := regexp.MustCompile(`eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`).FindString(string(jsBody))
	if token == "" {
		return "", fmt.Errorf("apple music token not found")
	}

	appleMusicCachedToken = token
	return token, nil
}

func clearAppleMusicToken() {
	appleMusicTokenMu.Lock()
	defer appleMusicTokenMu.Unlock()
	appleMusicCachedToken = ""
}

func (c *AppleMusicClient) searchSongWithToken(token, query string) ([]appleMusicSearchResult, error) {
	params := url.Values{}
	params.Set("term", query)
	params.Set("types", "songs")
	params.Set("limit", "25")
	params.Set("l", "en-US")
	params.Set("platform", "web")
	params.Set("format[resources]", "map")
	params.Set("include[songs]", "artists")
	params.Set("extend", "artistUrl")

	searchURL := appleMusicCatalogBaseURL + "/search?" + params.Encode()
	req, err := http.NewRequest("GET", searchURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create apple music catalog request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Origin", "https://music.apple.com")
	req.Header.Set("Referer", "https://music.apple.com/")
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:95.0) Gecko/20100101 Firefox/95.0")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Accept-Language", "en-US,en;q=0.5")
	req.Header.Set("x-apple-renewal", "true")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("apple music catalog search failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusUnauthorized {
		return nil, errAppleMusicUnauthorized
	}
	if resp.StatusCode != http.StatusOK {
		return nil, lyricsHTTPStatusError(resp.StatusCode, "apple music catalog search returned HTTP %d", resp.StatusCode)
	}

	var searchResp appleMusicCatalogSearchResponse
	if err := json.NewDecoder(resp.Body).Decode(&searchResp); err != nil {
		return nil, fmt.Errorf("failed to decode apple music catalog response: %w", err)
	}

	if searchResp.Results.Songs == nil || searchResp.Resources == nil {
		return nil, nil
	}

	results := make([]appleMusicSearchResult, 0, len(searchResp.Results.Songs.Data))
	for _, item := range searchResp.Results.Songs.Data {
		detail, ok := searchResp.Resources.Songs[item.ID]
		if !ok {
			continue
		}
		attr := detail.Attributes
		results = append(results, appleMusicSearchResult{
			ID:         item.ID,
			SongName:   attr.Name,
			ArtistName: attr.ArtistName,
			AlbumName:  attr.AlbumName,
			Duration:   attr.DurationInMillis,
		})
	}

	return results, nil
}

func (c *AppleMusicClient) SearchSong(trackName, artistName string, durationSec float64) (string, error) {
	query := trackName + " " + artistName
	if strings.TrimSpace(query) == "" {
		return "", lyricsNotFoundErrorf("empty search query")
	}

	token, err := c.getAppleMusicToken()
	if err != nil {
		return "", err
	}

	searchResp, err := c.searchSongWithToken(token, strings.TrimSpace(query))
	if errors.Is(err, errAppleMusicUnauthorized) {
		clearAppleMusicToken()
		token, tokenErr := c.getAppleMusicToken()
		if tokenErr != nil {
			return "", tokenErr
		}
		searchResp, err = c.searchSongWithToken(token, strings.TrimSpace(query))
	}
	if err != nil {
		return "", err
	}

	best := selectBestAppleMusicSearchResult(searchResp, trackName, artistName, durationSec)
	if best == nil || strings.TrimSpace(best.ID) == "" {
		return "", lyricsNotFoundErrorf("no songs found on apple music")
	}

	return strings.TrimSpace(best.ID), nil
}

func (c *AppleMusicClient) FetchLyricsByID(songID string) (string, error) {
	lyricsURL := fmt.Sprintf("https://lyrics.paxsenix.org/apple-music/lyrics?id=%s", songID)

	req, err := http.NewRequest("GET", lyricsURL, nil)
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("User-Agent", appUserAgent())
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("apple music lyrics fetch failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return "", lyricsHTTPStatusError(resp.StatusCode, "apple music lyrics proxy returned HTTP %d", resp.StatusCode)
	}

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read lyrics response: %w", err)
	}

	bodyStr := strings.TrimSpace(string(bodyBytes))
	if bodyStr == "" {
		return "", fmt.Errorf("empty lyrics response from apple music")
	}

	return bodyStr, nil
}

func formatPaxLyricsToLRC(rawJSON string, multiPersonWordByWord bool, preserveWordTiming bool) (string, error) {
	var stringPayload string
	if err := json.Unmarshal([]byte(rawJSON), &stringPayload); err == nil {
		stringPayload = strings.TrimSpace(stringPayload)
		if stringPayload != "" {
			return stringPayload, nil
		}
	}

	var paxResp paxResponse
	if err := json.Unmarshal([]byte(rawJSON), &paxResp); err == nil &&
		(paxResp.Content != nil ||
			strings.TrimSpace(paxResp.ELRCMultiPerson) != "" ||
			strings.TrimSpace(paxResp.ELRC) != "" ||
			strings.TrimSpace(paxResp.Plain) != "" ||
			strings.TrimSpace(paxResp.TTMLContent) != "") {
		if preserveWordTiming && multiPersonWordByWord && strings.TrimSpace(paxResp.ELRCMultiPerson) != "" {
			return strings.TrimSpace(paxResp.ELRCMultiPerson), nil
		}
		if preserveWordTiming && strings.TrimSpace(paxResp.ELRC) != "" {
			return strings.TrimSpace(paxResp.ELRC), nil
		}
		if strings.TrimSpace(paxResp.Plain) != "" && len(paxResp.Content) == 0 {
			return strings.TrimSpace(paxResp.Plain), nil
		}
		if len(paxResp.Content) == 0 {
			return "", fmt.Errorf("unsupported apple music lyrics payload")
		}
		return formatPaxContent(paxResp.Type, paxResp.Content, multiPersonWordByWord, preserveWordTiming), nil
	}

	var directLyrics []paxLyrics
	if err := json.Unmarshal([]byte(rawJSON), &directLyrics); err == nil && len(directLyrics) > 0 {
		return formatPaxContent("Syllable", directLyrics, multiPersonWordByWord, preserveWordTiming), nil
	}

	return "", fmt.Errorf("failed to parse pax lyrics response")
}

func appendPaxLyricDetail(builder *strings.Builder, details []paxLyricDetail, preserveWordTiming bool) {
	lastStart := ""

	for _, syllable := range details {
		if preserveWordTiming && syllable.Timestamp != nil {
			start := fmt.Sprintf("<%s>", msToLRCTimestampInline(int64(*syllable.Timestamp)))
			if start != lastStart {
				builder.WriteString(start)
				lastStart = start
			}
		}

		builder.WriteString(syllable.Text)
		if !syllable.Part {
			builder.WriteString(" ")
		}

		if preserveWordTiming && syllable.EndTime != nil {
			builder.WriteString(fmt.Sprintf("<%s>", msToLRCTimestampInline(int64(*syllable.EndTime))))
		}
	}
}

func formatPaxContent(lyricsType string, content []paxLyrics, multiPersonWordByWord bool, preserveWordTiming bool) string {
	var sb strings.Builder

	for i, line := range content {
		if i > 0 {
			sb.WriteString("\n")
		}

		timestamp := msToLRCTimestamp(int64(line.Timestamp))

		if strings.EqualFold(lyricsType, "Syllable") {
			sb.WriteString(timestamp)
			if multiPersonWordByWord {
				if line.OppositeTurn {
					sb.WriteString("v2:")
				} else {
					sb.WriteString("v1:")
				}
			}

			appendPaxLyricDetail(&sb, line.Text, preserveWordTiming)

			if line.Background && multiPersonWordByWord && len(line.BackgroundText) > 0 {
				sb.WriteString("\n[bg:")
				appendPaxLyricDetail(&sb, line.BackgroundText, preserveWordTiming)
				sb.WriteString("]")
			}
		} else {
			if len(line.Text) > 0 {
				sb.WriteString(timestamp)
				sb.WriteString(line.Text[0].Text)
			}
		}
	}

	return strings.TrimSpace(sb.String())
}

func (c *AppleMusicClient) FetchLyrics(
	trackName,
	artistName string,
	durationSec float64,
	multiPersonWordByWord bool,
	preserveWordTiming bool,
) (*LyricsResponse, error) {
	songID, err := c.SearchSong(trackName, artistName, durationSec)
	if err != nil {
		return nil, err
	}

	rawLyrics, err := c.FetchLyricsByID(songID)
	if err != nil {
		return nil, err
	}
	if errMsg, isErrorPayload := detectLyricsErrorPayload(rawLyrics); isErrorPayload {
		return nil, classifyLyricsPayloadError(0, errMsg, "apple music proxy returned non-lyric payload: %s", errMsg)
	}

	lrcText, err := formatPaxLyricsToLRC(rawLyrics, multiPersonWordByWord, preserveWordTiming)
	if err != nil {
		trimmedRaw := strings.TrimSpace(rawLyrics)
		if strings.HasPrefix(trimmedRaw, "{") || strings.HasPrefix(trimmedRaw, "[") {
			return nil, err
		}
		lrcText = rawLyrics
	}

	if resp := lyricsResponseFromLRCText(lrcText, "Apple Music", "Apple Music"); resp != nil {
		return resp, nil
	}
	return nil, lyricsNotFoundErrorf("no lyrics found on apple music")
}
