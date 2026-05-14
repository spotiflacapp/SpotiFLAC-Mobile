package gobackend

import (
	"io"
	"net/http"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLyricsCacheParsingAndLRCLibClient(t *testing.T) {
	SetAppVersion("4.5.0")
	if ua := appUserAgent(); !strings.Contains(ua, "4.5.0") {
		t.Fatalf("user agent = %q", ua)
	}
	SetLyricsProviderOrder([]string{"LRCLIB", "bad", "netease"})
	if providers := GetLyricsProviderOrder(); len(providers) != 2 || providers[0] != LyricsProviderLRCLIB {
		t.Fatalf("providers = %#v", providers)
	}
	SetLyricsProviderOrder(nil)
	SetLyricsFetchOptions(LyricsFetchOptions{MusixmatchLanguage: " EN_us!!too-long-value ", MultiPersonWordByWord: true})
	if opts := GetLyricsFetchOptions(); !strings.HasPrefix(opts.MusixmatchLanguage, "en_us") || len(opts.MusixmatchLanguage) > 16 {
		t.Fatalf("options = %#v", opts)
	}

	cache := &lyricsCache{cache: map[string]*lyricsCacheEntry{}}
	response := &LyricsResponse{PlainLyrics: "Hello", Source: "test"}
	cache.Set(" Artist ", " Song ", 184, response)
	if got, ok := cache.Get("artist", "song", 180); !ok || got.PlainLyrics != "Hello" {
		t.Fatalf("cache get = %#v/%v", got, ok)
	}
	cache.cache["expired"] = &lyricsCacheEntry{response: response, expiresAt: time.Now().Add(-time.Hour)}
	if cleaned := cache.CleanExpired(); cleaned != 1 {
		t.Fatalf("cleaned = %d", cleaned)
	}
	if cache.Size() != 1 || cache.ClearAll() != 1 || cache.Size() != 0 {
		t.Fatalf("cache size after clear = %d", cache.Size())
	}

	lines := parseSyncedLyrics("[00:01.20]Hello\n[bg:Harmony]\n[00:02.300]World\n[00:03.00]\n")
	if len(lines) != 2 || !strings.Contains(lines[0].Words, "[bg:Harmony]") || lines[0].EndTimeMs != lines[1].StartTimeMs {
		t.Fatalf("synced lines = %#v", lines)
	}
	if plain := plainLyricsFromTimedLines(lines); !strings.Contains(plain, "Hello") {
		t.Fatalf("plain = %q", plain)
	}
	if unsynced := plainTextLyricsLines("A\n\n B "); len(unsynced) != 2 {
		t.Fatalf("unsynced = %#v", unsynced)
	}
	if !lyricsHasUsableText(&LyricsResponse{Instrumental: true}) || lyricsHasUsableText(&LyricsResponse{}) {
		t.Fatal("unexpected usable lyrics result")
	}
	if msg, ok := detectLyricsErrorPayload(`{"success":false,"message":"nope"}`); !ok || msg != "nope" {
		t.Fatalf("error payload = %q/%v", msg, ok)
	}
	if lrcTimestampToMs("01", "02", "345") != 62345 || msToLRCTimestamp(62340) != "[01:02.34]" {
		t.Fatal("unexpected LRC timestamp conversion")
	}
	lrc := convertToLRCWithMetadata(&LyricsResponse{SyncType: "LINE_SYNCED", Lines: lines}, "Song", "Artist")
	if !strings.Contains(lrc, "[ti:Song]") || !strings.Contains(lrc, "Hello") {
		t.Fatalf("lrc = %q", lrc)
	}
	if got := simplifyTrackName("Song (feat. Guest) - 2020 Remaster"); got != "song" {
		t.Fatalf("simplified = %q", got)
	}
	if got := normalizeArtistName("Artist feat. Guest"); got != "Artist" {
		t.Fatalf("artist = %q", got)
	}
	if !isLikelyInstrumentalTrack("Song (Instrumental)") || isLikelyInstrumentalTrack("Song") {
		t.Fatal("instrumental heuristic mismatch")
	}

	dir := t.TempDir()
	lrcPath, err := SaveLRCFile(filepath.Join(dir, "song.flac"), lrc)
	if err != nil {
		t.Fatalf("SaveLRCFile: %v", err)
	}
	if !strings.HasSuffix(lrcPath, ".lrc") {
		t.Fatalf("lrc path = %q", lrcPath)
	}
	if _, err := SaveLRCFile(filepath.Join(dir, "empty.flac"), ""); err == nil {
		t.Fatal("expected empty LRC error")
	}

	client := &LyricsClient{httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		switch req.URL.Path {
		case "/api/get":
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"id":1,"trackName":"Song","artistName":"Artist","duration":180,"syncedLyrics":"[00:01.00]Hello"}`)), Request: req}, nil
		case "/api/search":
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`[{"id":2,"duration":180,"plainLyrics":"Plain\nLyric"},{"id":3,"duration":180,"syncedLyrics":"[00:02.00]Synced"}]`)), Request: req}, nil
		default:
			return &http.Response{StatusCode: 404, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{}`)), Request: req}, nil
		}
	})}}
	got, err := client.FetchLyricsWithMetadata("Artist", "Song")
	if err != nil || got.SyncType != "LINE_SYNCED" || len(got.Lines) != 1 {
		t.Fatalf("FetchLyricsWithMetadata = %#v/%v", got, err)
	}
	search, err := client.FetchLyricsFromLRCLibSearch("Artist Song", 180)
	if err != nil || len(search.Lines) == 0 {
		t.Fatalf("FetchLyricsFromLRCLibSearch = %#v/%v", search, err)
	}
	if best := client.findBestMatch([]LRCLibResponse{{Duration: 100, PlainLyrics: "A"}, {Duration: 180, SyncedLyrics: "[00:01.00]B"}}, 180); best == nil || best.SyncedLyrics == "" {
		t.Fatalf("best = %#v", best)
	}
	if !client.durationMatches(181, 180) || client.durationMatches(300, 180) {
		t.Fatal("duration match mismatch")
	}
	parsed := client.parseLRCLibResponse(&LRCLibResponse{PlainLyrics: "A\nB"})
	if parsed.SyncType != "UNSYNCED" || len(parsed.Lines) != 2 {
		t.Fatalf("parsed plain = %#v", parsed)
	}

	allSources := &LyricsClient{httpClient: client.httpClient}
	SetLyricsProviderOrder([]string{LyricsProviderLRCLIB})
	globalLyricsCache.ClearAll()
	all, err := allSources.FetchLyricsAllSources("", "Song (Instrumental)", "Artist", 180)
	if err != nil || !all.Instrumental {
		t.Fatalf("instrumental all sources = %#v/%v", all, err)
	}
	globalLyricsCache.ClearAll()
	all, err = allSources.FetchLyricsAllSources("", "Song", "Artist", 180)
	if err != nil || len(all.Lines) == 0 {
		t.Fatalf("all sources = %#v/%v", all, err)
	}
	cached, err := allSources.FetchLyricsAllSources("", "Song", "Artist", 180)
	if err != nil || !strings.Contains(cached.Source, "cached") {
		t.Fatalf("cached all sources = %#v/%v", cached, err)
	}
}

func TestExternalLyricsProvidersWithFakeHTTP(t *testing.T) {
	paxJSON := `{"type":"Syllable","content":[{"timestamp":1000,"oppositeTurn":true,"background":true,"text":[{"text":"Hel","part":true,"timestamp":1000},{"text":"lo","part":false,"timestamp":1200,"endtime":1500}],"backgroundText":[{"text":"bg","part":false,"timestamp":900}]}]}`
	apple := &AppleMusicClient{httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		switch {
		case strings.Contains(req.URL.Path, "/apple-music/search"):
			if req.URL.Query().Get("q") == "bad" {
				return &http.Response{StatusCode: 500, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`error`)), Request: req}, nil
			}
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`[{"id":"apple-2","songName":"Other","artistName":"Other","duration":1000},{"id":"apple-1","songName":"Song","artistName":"Artist","albumName":"Album","duration":180000}]`)), Request: req}, nil
		case strings.Contains(req.URL.Path, "/apple-music/lyrics"):
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(paxJSON)), Request: req}, nil
		default:
			return &http.Response{StatusCode: 404, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{}`)), Request: req}, nil
		}
	})}}
	if best := selectBestAppleMusicSearchResult([]appleMusicSearchResult{{ID: "1", SongName: "Song", ArtistName: "Artist", Duration: 180000}}, "Song", "Artist", 180); best == nil || best.ID != "1" {
		t.Fatalf("best apple result = %#v", best)
	}
	appleID, err := apple.SearchSong("Song", "Artist", 180)
	if err != nil || appleID != "apple-1" {
		t.Fatalf("apple SearchSong = %q/%v", appleID, err)
	}
	rawApple, err := apple.FetchLyricsByID(appleID)
	if err != nil || !strings.Contains(rawApple, "Syllable") {
		t.Fatalf("apple raw = %q/%v", rawApple, err)
	}
	appleLyrics, err := apple.FetchLyrics("Song", "Artist", 180, true, true)
	if err != nil || appleLyrics.SyncType != "LINE_SYNCED" || appleLyrics.Provider != "Apple Music" {
		t.Fatalf("apple lyrics = %#v/%v", appleLyrics, err)
	}
	if plain, err := formatPaxLyricsToLRC(`[{"timestamp":2000,"text":[{"text":"Plain","part":false}]}]`, false, false); err != nil || !strings.Contains(plain, "Plain") {
		t.Fatalf("direct pax = %q/%v", plain, err)
	}
	lineOnly, err := formatPaxLyricsToLRC(paxJSON, true, false)
	if err != nil {
		t.Fatalf("line-only pax = %v", err)
	}
	if strings.Contains(lineOnly, "<00:") {
		t.Fatalf("line-only pax should not include inline word timing: %q", lineOnly)
	}
	elrc, err := formatPaxLyricsToLRC(paxJSON, true, true)
	if err != nil {
		t.Fatalf("elrc pax = %v", err)
	}
	if !strings.Contains(elrc, "<00:") {
		t.Fatalf("elrc pax should include inline word timing: %q", elrc)
	}
	if _, err := apple.SearchSong("", "", 0); err == nil {
		t.Fatal("expected empty apple search error")
	}

	musixmatch := &MusixmatchClient{
		httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
			lyricsType := req.URL.Query().Get("type")
			lang := req.URL.Query().Get("l")
			if req.URL.Query().Get("t") == "bad" {
				return &http.Response{StatusCode: 429, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"error":"rate limited"}`)), Request: req}, nil
			}
			if lyricsType == "translate" && lang == "id" {
				return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`"[00:01.00]Halo"`)), Request: req}, nil
			}
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`[00:01.00]Hello`)), Request: req}, nil
		})},
		baseURL: "https://lyrics.paxsenix.org/musixmatch/lyrics",
	}
	if localized, err := musixmatch.FetchLyricsInLanguage("Song", "Artist", 180, "id"); err != nil || localized.Source != "Musixmatch (id)" {
		t.Fatalf("localized musixmatch = %#v/%v", localized, err)
	}
	if normal, err := musixmatch.FetchLyrics("Song", "Artist", 180, "xx"); err != nil || normal.Provider != "Musixmatch" {
		t.Fatalf("musixmatch = %#v/%v", normal, err)
	}
	if _, err := musixmatch.FetchLyricsInLanguage("Song", "Artist", 180, " "); err == nil {
		t.Fatal("expected invalid language error")
	}
	if _, err := musixmatch.fetchLyricsPayload("bad", "Artist", 0, "word", ""); err == nil {
		t.Fatal("expected musixmatch proxy error")
	}

	netease := &NeteaseClient{httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		switch {
		case strings.Contains(req.URL.Path, "/netease/search"):
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"code":200,"result":{"songCount":1,"songs":[{"name":"Song","id":123,"artists":[{"name":"Artist"}]}]}}`)), Request: req}, nil
		case strings.Contains(req.URL.Path, "/netease/lyrics"):
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"code":200,"lrc":{"lyric":"[00:01.00]Hello"},"tlyric":{"lyric":"[00:01.00]Halo"},"romalrc":{"lyric":"[00:01.00]Romaji"}}`)), Request: req}, nil
		default:
			return &http.Response{StatusCode: 404, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{}`)), Request: req}, nil
		}
	})}}
	songID, err := netease.SearchSong("Song", "Artist")
	if err != nil || songID != 123 {
		t.Fatalf("netease search = %d/%v", songID, err)
	}
	netLyrics, err := netease.FetchLyrics("Song", "Artist", 180, true, true)
	if err != nil || netLyrics.SyncType != "LINE_SYNCED" {
		t.Fatalf("netease lyrics = %#v/%v", netLyrics, err)
	}
	if _, err := netease.SearchSong("", ""); err == nil {
		t.Fatal("expected empty netease search error")
	}

	qq := &QQMusicClient{httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		if req.Method != http.MethodPost {
			t.Fatalf("unexpected QQ method %s", req.Method)
		}
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"lyrics":[{"timestamp":1000,"text":[{"text":"QQ","part":false,"timestamp":1000}]}]}`)), Request: req}, nil
	})}}
	qqRaw, err := qq.fetchLyricsByMetadata("Song", "Artist", 180)
	if err != nil || !strings.Contains(qqRaw, "lyrics") {
		t.Fatalf("qq raw = %q/%v", qqRaw, err)
	}
	qqLyrics, err := qq.FetchLyrics("Song", "Artist", 180, false)
	if err != nil || qqLyrics.Provider != "QQ Music" {
		t.Fatalf("qq lyrics = %#v/%v", qqLyrics, err)
	}
	if _, err := formatQQLyricsMetadataToLRC(`{"lyrics":[]}`, false); err == nil {
		t.Fatal("expected empty QQ metadata error")
	}

	spotify := &SpotifyLyricsClient{httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		switch {
		case strings.Contains(req.URL.Path, "/spotify/search"):
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`[{"trackId":"spotify-1","name":"Song","artistName":"Artist","duration":"03:00"}]`)), Request: req}, nil
		case strings.Contains(req.URL.Path, "/spotify/lyrics"):
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`"[00:01.00]Spotify"`)), Request: req}, nil
		default:
			return &http.Response{StatusCode: 404, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{}`)), Request: req}, nil
		}
	})}}
	spotifyLyrics, err := spotify.FetchLyrics("", "Song", "Artist", 180)
	if err != nil || spotifyLyrics.Provider != "Spotify" || spotifyLyrics.SyncType != "LINE_SYNCED" {
		t.Fatalf("spotify lyrics = %#v/%v", spotifyLyrics, err)
	}

	deezer := &DeezerLyricsClient{httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"lyrics":[{"timestamp":1000,"text":[{"text":"Deezer","part":false}]}]}`)), Request: req}, nil
	})}}
	deezerLyrics, err := deezer.FetchLyricsByID("123", false)
	if err != nil || deezerLyrics.Provider != "Deezer" || deezerLyrics.SyncType != "LINE_SYNCED" {
		t.Fatalf("deezer lyrics = %#v/%v", deezerLyrics, err)
	}

	youtube := &YouTubeLyricsClient{httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		switch {
		case strings.Contains(req.URL.Path, "/youtube/search"):
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`[{"videoId":"yt-1","title":"Song","author":"Artist","duration":"3:00"}]`)), Request: req}, nil
		case strings.Contains(req.URL.Path, "/youtube/lyrics"):
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`"[00:01.00]YouTube"`)), Request: req}, nil
		default:
			return &http.Response{StatusCode: 404, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{}`)), Request: req}, nil
		}
	})}}
	youtubeLyrics, err := youtube.FetchLyrics("Song", "Artist", 180)
	if err != nil || youtubeLyrics.Provider != "YouTube" || youtubeLyrics.SyncType != "LINE_SYNCED" {
		t.Fatalf("youtube lyrics = %#v/%v", youtubeLyrics, err)
	}

	kugou := &KugouLyricsClient{httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		switch {
		case strings.Contains(req.URL.Path, "/kugou/search"):
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`[{"hash":"kg-1","title":"Song","artist":"Artist","duration":180}]`)), Request: req}, nil
		case strings.Contains(req.URL.Path, "/kugou/lyrics"):
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"lyrics_text":"[00:01.00]Kugou"}`)), Request: req}, nil
		default:
			return &http.Response{StatusCode: 404, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{}`)), Request: req}, nil
		}
	})}}
	kugouLyrics, err := kugou.FetchLyrics("Song", "Artist", 180)
	if err != nil || kugouLyrics.Provider != "Kugou" || kugouLyrics.SyncType != "LINE_SYNCED" {
		t.Fatalf("kugou lyrics = %#v/%v", kugouLyrics, err)
	}

	genius := &GeniusLyricsClient{httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		switch {
		case strings.Contains(req.URL.Path, "/api/search/multi"):
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"response":{"sections":[{"hits":[{"type":"song","result":{"title":"Song","primary_artist_names":"Artist","url":"https://genius.com/artist-song-lyrics"}}]}]}}`)), Request: req}, nil
		case strings.Contains(req.URL.Path, "/genius/lyrics"):
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"error":false,"lyrics":"Genius line"}`)), Request: req}, nil
		default:
			return &http.Response{StatusCode: 404, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{}`)), Request: req}, nil
		}
	})}}
	geniusLyrics, err := genius.FetchLyrics("Song", "Artist", 180)
	if err != nil || geniusLyrics.Provider != "Genius" || geniusLyrics.SyncType != "UNSYNCED" {
		t.Fatalf("genius lyrics = %#v/%v", geniusLyrics, err)
	}
}
