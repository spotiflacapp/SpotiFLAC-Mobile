package gobackend

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type NeteaseClient struct {
	httpClient *http.Client
}

type neteaseSearchSong struct {
	Name    string `json:"name"`
	ID      int64  `json:"id"`
	Artists []struct {
		Name string `json:"name"`
	} `json:"artists"`
}

type neteaseSearchResponse struct {
	Result struct {
		Songs     []neteaseSearchSong `json:"songs"`
		SongCount int                 `json:"songCount"`
	} `json:"result"`
	Code    int    `json:"code"`
	Message string `json:"message"`
	Msg     string `json:"msg"`
}

type neteaseLyricsResponse struct {
	LRC     *neteaseLyricField `json:"lrc"`
	TLyric  *neteaseLyricField `json:"tlyric"`
	RomaLRC *neteaseLyricField `json:"romalrc"`
	Code    int                `json:"code"`
}

type neteaseLyricField struct {
	Lyric string `json:"lyric"`
}

var neteaseHeaders = map[string]string{
	"Accept":          "application/json",
	"Accept-Language": "en-US,en;q=0.9",
	"Cache-Control":   "max-age=0",
}

func NewNeteaseClient() *NeteaseClient {
	return &NeteaseClient{
		httpClient: NewMetadataHTTPClient(15 * time.Second),
	}
}

func (c *NeteaseClient) SearchSong(trackName, artistName string) (int64, error) {
	query := trackName + " " + artistName
	if strings.TrimSpace(query) == "" {
		return 0, lyricsNotFoundErrorf("empty search query")
	}

	searchURL := "https://lyrics.paxsenix.org/netease/search"
	params := url.Values{}
	params.Set("q", query)

	fullURL := searchURL + "?" + params.Encode()

	req, err := http.NewRequest("GET", fullURL, nil)
	if err != nil {
		return 0, fmt.Errorf("failed to create request: %w", err)
	}

	for k, v := range neteaseHeaders {
		req.Header.Set(k, v)
	}
	req.Header.Set("User-Agent", appUserAgent())

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return 0, fmt.Errorf("netease search failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return 0, lyricsHTTPStatusError(resp.StatusCode, "netease search returned HTTP %d", resp.StatusCode)
	}

	var searchResp neteaseSearchResponse
	if err := json.NewDecoder(resp.Body).Decode(&searchResp); err != nil {
		return 0, fmt.Errorf("failed to decode netease search: %w", err)
	}

	if searchResp.Code != 0 && searchResp.Code != 200 {
		message := strings.TrimSpace(searchResp.Message)
		if message == "" {
			message = strings.TrimSpace(searchResp.Msg)
		}
		if message == "" {
			message = "unexpected response code"
		}
		return 0, lyricsServiceUnavailableErrorf("netease search unavailable: code %d: %s", searchResp.Code, message)
	}

	if searchResp.Result.SongCount == 0 || len(searchResp.Result.Songs) == 0 {
		return 0, lyricsNotFoundErrorf("no songs found on netease")
	}

	best := selectBestNeteaseSearchResult(searchResp.Result.Songs, trackName, artistName)
	if best == nil || best.ID == 0 {
		return 0, lyricsNotFoundErrorf("no matching songs found on netease")
	}
	return best.ID, nil
}

func selectBestNeteaseSearchResult(results []neteaseSearchSong, trackName, artistName string) *neteaseSearchSong {
	best := selectBestLyricsCandidate(len(results), trackName, artistName, 0, func(i int) (string, string, float64, bool) {
		result := &results[i]
		artists := make([]string, 0, len(result.Artists))
		for _, artist := range result.Artists {
			if name := strings.TrimSpace(artist.Name); name != "" {
				artists = append(artists, name)
			}
		}
		candidateArtist := strings.Join(artists, ", ")
		ok := lyricsSearchTitlesMatch(result.Name, trackName, false) &&
			lyricsSearchArtistsMatch(candidateArtist, artistName)
		return result.Name, candidateArtist, 0, ok
	})
	if best < 0 {
		return nil
	}
	return &results[best]
}

func (c *NeteaseClient) FetchLyricsByID(songID int64, includeTranslation, includeRomanization bool) (string, error) {
	lyricsURL := "https://lyrics.paxsenix.org/netease/lyrics"
	params := url.Values{}
	params.Set("id", fmt.Sprintf("%d", songID))

	fullURL := lyricsURL + "?" + params.Encode()

	req, err := http.NewRequest("GET", fullURL, nil)
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	for k, v := range neteaseHeaders {
		req.Header.Set(k, v)
	}
	req.Header.Set("User-Agent", appUserAgent())

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("netease lyrics fetch failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return "", lyricsHTTPStatusError(resp.StatusCode, "netease lyrics returned HTTP %d", resp.StatusCode)
	}

	var lyricsResp neteaseLyricsResponse
	if err := json.NewDecoder(resp.Body).Decode(&lyricsResp); err != nil {
		return "", fmt.Errorf("failed to decode netease lyrics: %w", err)
	}

	if lyricsResp.LRC == nil || strings.TrimSpace(lyricsResp.LRC.Lyric) == "" {
		return "", lyricsNotFoundErrorf("no lyrics available on netease")
	}

	lyric := lyricsResp.LRC.Lyric

	if includeTranslation && lyricsResp.TLyric != nil && strings.TrimSpace(lyricsResp.TLyric.Lyric) != "" {
		lyric += "\n\n" + lyricsResp.TLyric.Lyric
	}

	if includeRomanization && lyricsResp.RomaLRC != nil && strings.TrimSpace(lyricsResp.RomaLRC.Lyric) != "" {
		lyric += "\n\n" + lyricsResp.RomaLRC.Lyric
	}

	return lyric, nil
}

func (c *NeteaseClient) FetchLyrics(
	trackName,
	artistName string,
	durationSec float64,
	includeTranslation,
	includeRomanization bool,
) (*LyricsResponse, error) {
	songID, err := c.SearchSong(trackName, artistName)
	if err != nil {
		return nil, err
	}

	lrcText, err := c.FetchLyricsByID(songID, includeTranslation, includeRomanization)
	if err != nil {
		return nil, err
	}

	if resp := lyricsResponseFromLRCText(lrcText, "Netease", "Netease"); resp != nil {
		return resp, nil
	}
	return nil, fmt.Errorf("netease returned empty lyrics")
}
