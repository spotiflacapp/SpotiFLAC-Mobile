package gobackend

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"golang.org/x/text/cases"
	"golang.org/x/text/language"
)

const musicBrainzAPIBase = "https://musicbrainz.org/ws/2"

// MusicBrainz lookups run in the per-track finalize stage and album batches
// repeat the same ISRC-adjacent questions; each miss costs up to 3 attempts
// with 2s sleeps. Positive results are stable (6h TTL); misses/errors expire
// quickly (10min) so a manual re-enrich can retry soon.
const (
	musicBrainzCachePositiveTTL = 6 * time.Hour
	musicBrainzCacheNegativeTTL = 10 * time.Minute
	musicBrainzCacheMaxEntries  = 256
)

type musicBrainzCacheEntry struct {
	value     string
	err       error
	expiresAt time.Time
}

var (
	musicBrainzCacheMu sync.Mutex
	musicBrainzCache   = make(map[string]musicBrainzCacheEntry)
)

func musicBrainzCached(key string, fetch func() (string, error)) (string, error) {
	musicBrainzCacheMu.Lock()
	if entry, ok := musicBrainzCache[key]; ok && time.Now().Before(entry.expiresAt) {
		musicBrainzCacheMu.Unlock()
		return entry.value, entry.err
	}
	musicBrainzCacheMu.Unlock()

	value, err := fetch()

	ttl := musicBrainzCachePositiveTTL
	if err != nil || value == "" {
		ttl = musicBrainzCacheNegativeTTL
	}
	musicBrainzCacheMu.Lock()
	if len(musicBrainzCache) >= musicBrainzCacheMaxEntries {
		now := time.Now()
		for k, e := range musicBrainzCache {
			if now.After(e.expiresAt) {
				delete(musicBrainzCache, k)
			}
		}
		if len(musicBrainzCache) >= musicBrainzCacheMaxEntries {
			musicBrainzCache = make(map[string]musicBrainzCacheEntry)
		}
	}
	musicBrainzCache[key] = musicBrainzCacheEntry{
		value:     value,
		err:       err,
		expiresAt: time.Now().Add(ttl),
	}
	musicBrainzCacheMu.Unlock()
	return value, err
}

type musicBrainzTag struct {
	Count int    `json:"count"`
	Name  string `json:"name"`
}

type musicBrainzRecordingResponse struct {
	Recordings []struct {
		Tags []musicBrainzTag `json:"tags"`
	} `json:"recordings"`
}

type musicBrainzArtistCredit struct {
	Name       string `json:"name"`
	JoinPhrase string `json:"joinphrase"`
}

type musicBrainzRelease struct {
	Title        string                    `json:"title"`
	ArtistCredit []musicBrainzArtistCredit `json:"artist-credit"`
}

type musicBrainzAlbumArtistResponse struct {
	Recordings []struct {
		Releases []musicBrainzRelease `json:"releases"`
	} `json:"recordings"`
}

func formatMusicBrainzGenre(tags []musicBrainzTag) string {
	if len(tags) == 0 {
		return ""
	}

	caser := cases.Title(language.English)
	seen := make(map[string]struct{}, len(tags))
	maxCount := -1
	bestTag := ""

	for _, tag := range tags {
		name := strings.TrimSpace(tag.Name)
		if name == "" {
			continue
		}

		key := strings.ToLower(name)
		if _, exists := seen[key]; exists {
			continue
		}
		seen[key] = struct{}{}

		formatted := caser.String(name)
		if tag.Count > maxCount {
			maxCount = tag.Count
			bestTag = formatted
		}
	}

	return bestTag
}

func formatMusicBrainzArtistCredit(credits []musicBrainzArtistCredit) string {
	var builder strings.Builder
	for _, credit := range credits {
		name := strings.TrimSpace(credit.Name)
		if name == "" {
			continue
		}
		builder.WriteString(name)
		builder.WriteString(credit.JoinPhrase)
	}
	return strings.TrimSpace(builder.String())
}

func selectMusicBrainzAlbumArtist(releases []musicBrainzRelease, albumName string) string {
	if len(releases) == 0 {
		return ""
	}

	normalizedAlbum := strings.ToLower(strings.TrimSpace(albumName))
	if normalizedAlbum != "" {
		for _, release := range releases {
			if strings.ToLower(strings.TrimSpace(release.Title)) != normalizedAlbum {
				continue
			}
			if albumArtist := formatMusicBrainzArtistCredit(release.ArtistCredit); albumArtist != "" {
				return albumArtist
			}
		}
	}

	for _, release := range releases {
		if albumArtist := formatMusicBrainzArtistCredit(release.ArtistCredit); albumArtist != "" {
			return albumArtist
		}
	}

	return ""
}

// fetchMusicBrainzRecordingByISRC queries the MusicBrainz recording endpoint
// for the given ISRC with the supplied inc= parameter, retrying up to 3 times,
// and decodes the JSON response into payload. It returns the normalized ISRC.
func fetchMusicBrainzRecordingByISRC(isrc string, inc string, payload any) (string, error) {
	normalizedISRC := strings.ToUpper(strings.TrimSpace(isrc))
	if normalizedISRC == "" {
		return "", fmt.Errorf("no ISRC provided")
	}

	client := NewMetadataHTTPClient(10 * time.Second)
	query := fmt.Sprintf("isrc:%s", normalizedISRC)
	reqURL := fmt.Sprintf(
		"%s/recording?query=%s&fmt=json&inc=%s",
		musicBrainzAPIBase,
		url.QueryEscape(query),
		inc,
	)

	req, err := http.NewRequest(http.MethodGet, reqURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", getRandomUserAgent())

	var resp *http.Response
	var lastErr error
	for attempt := 0; attempt < 3; attempt++ {
		resp, lastErr = client.Do(req)
		if lastErr == nil && resp.StatusCode == http.StatusOK {
			break
		}
		if resp != nil {
			resp.Body.Close()
		}
		if attempt < 2 {
			time.Sleep(2 * time.Second)
		}
	}

	if lastErr != nil {
		return "", lastErr
	}
	if resp == nil {
		return "", fmt.Errorf("MusicBrainz request failed without response")
	}
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return "", fmt.Errorf("MusicBrainz API returned status: %d", resp.StatusCode)
	}
	defer resp.Body.Close()

	if err := json.NewDecoder(resp.Body).Decode(payload); err != nil {
		return "", err
	}
	return normalizedISRC, nil
}

func FetchMusicBrainzAlbumArtistByISRC(isrc string, albumName string) (string, error) {
	key := "albumartist\x00" + strings.ToUpper(strings.TrimSpace(isrc)) +
		"\x00" + strings.ToLower(strings.TrimSpace(albumName))
	return musicBrainzCached(key, func() (string, error) {
		var payload musicBrainzAlbumArtistResponse
		normalizedISRC, err := fetchMusicBrainzRecordingByISRC(isrc, "releases+artist-credits", &payload)
		if err != nil {
			return "", err
		}
		for _, recording := range payload.Recordings {
			if albumArtist := selectMusicBrainzAlbumArtist(recording.Releases, albumName); albumArtist != "" {
				return albumArtist, nil
			}
		}

		return "", fmt.Errorf("no MusicBrainz album artist found for ISRC: %s", normalizedISRC)
	})
}

func FetchMusicBrainzGenreByISRC(isrc string) (string, error) {
	key := "genre\x00" + strings.ToUpper(strings.TrimSpace(isrc))
	return musicBrainzCached(key, func() (string, error) {
		var payload musicBrainzRecordingResponse
		normalizedISRC, err := fetchMusicBrainzRecordingByISRC(isrc, "tags", &payload)
		if err != nil {
			return "", err
		}
		if len(payload.Recordings) == 0 {
			return "", fmt.Errorf("no recordings found for ISRC: %s", normalizedISRC)
		}

		genre := formatMusicBrainzGenre(payload.Recordings[0].Tags)
		if genre == "" {
			return "", fmt.Errorf("no MusicBrainz genre tags found for ISRC: %s", normalizedISRC)
		}
		return genre, nil
	})
}
