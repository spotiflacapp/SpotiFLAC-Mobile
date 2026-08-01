package gobackend

import (
	"bytes"
	"errors"
	"image"
	"image/color"
	"image/png"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func testPNG(t *testing.T, width, height int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, width, height))
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			img.Set(x, y, color.RGBA{R: uint8(x), G: uint8(y), B: 100, A: 255})
		}
	}
	var buffer bytes.Buffer
	if err := png.Encode(&buffer, img); err != nil {
		t.Fatalf("encode test cover: %v", err)
	}
	return buffer.Bytes()
}

func resetCoverCache() {
	coverMu.Lock()
	coverCache = map[string]*coverCacheEntry{}
	coverInflight = map[string]*coverInflightCall{}
	coverCacheBytes = 0
	coverMu.Unlock()
}

func TestFetchCoverCachedSingleflight(t *testing.T) {
	orig := coverFetch
	defer func() { coverFetch = orig }()
	resetCoverCache()

	var calls int32
	entered := make(chan struct{})
	release := make(chan struct{})
	coverFetch = func(string) ([]byte, error) {
		if atomic.AddInt32(&calls, 1) == 1 {
			close(entered)
		}
		<-release
		return []byte("coverbytes"), nil
	}

	const url = "https://cdn.example/cover_max.jpg"
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		if _, err := fetchCoverCached(url); err != nil {
			t.Errorf("leader fetch error: %v", err)
		}
	}()

	<-entered // leader has registered inflight and is blocked in coverFetch

	wg.Add(1)
	go func() {
		defer wg.Done()
		if _, err := fetchCoverCached(url); err != nil {
			t.Errorf("follower fetch error: %v", err)
		}
	}()

	close(release)
	wg.Wait()

	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Fatalf("expected 1 fetch for concurrent requests, got %d", got)
	}
}

func TestFetchCoverCachedTTLExpiry(t *testing.T) {
	orig := coverFetch
	defer func() { coverFetch = orig }()
	resetCoverCache()

	var calls int32
	coverFetch = func(string) ([]byte, error) {
		atomic.AddInt32(&calls, 1)
		return []byte("data"), nil
	}

	const url = "https://cdn.example/ttl.jpg"
	if _, err := fetchCoverCached(url); err != nil {
		t.Fatalf("first fetch error: %v", err)
	}
	// second call served from cache
	if _, err := fetchCoverCached(url); err != nil {
		t.Fatalf("second fetch error: %v", err)
	}
	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Fatalf("expected cache hit, got %d fetches", got)
	}

	// expire the entry and confirm a refetch
	coverMu.Lock()
	coverCache[url].expiresAt = time.Now().Add(-time.Minute)
	coverMu.Unlock()

	if _, err := fetchCoverCached(url); err != nil {
		t.Fatalf("third fetch error: %v", err)
	}
	if got := atomic.LoadInt32(&calls); got != 2 {
		t.Fatalf("expected refetch after TTL expiry, got %d fetches", got)
	}
}

func TestMaxQualityCoverCandidatesProbe1900And1500(t *testing.T) {
	url := "https://cdn-images.dzcdn.net/images/cover/abc/1000x1000-000000-80-0-0.jpg"
	candidates := maxQualityCoverCandidateURLs(url)
	if len(candidates) != 2 {
		t.Fatalf("expected two candidates, got %#v", candidates)
	}
	if !strings.Contains(candidates[0], "1900x1900") {
		t.Fatalf("first candidate = %q", candidates[0])
	}
	if !strings.Contains(candidates[1], "1500x1500") {
		t.Fatalf("second candidate = %q", candidates[1])
	}
}

func TestDownloadCoverSelectsDecodedDimensionsBeforeByteSize(t *testing.T) {
	orig := coverFetch
	defer func() { coverFetch = orig }()
	resetCoverCache()

	advertised1900ButSmaller := append(testPNG(t, 12, 12), bytes.Repeat([]byte{0}, 4096)...)
	actualLargerDimensions := testPNG(t, 15, 15)
	coverFetch = func(url string) ([]byte, error) {
		switch {
		case strings.Contains(url, "1900x1900"):
			return advertised1900ButSmaller, nil
		case strings.Contains(url, "1500x1500"):
			return actualLargerDimensions, nil
		default:
			return nil, errors.New("unexpected URL")
		}
	}

	url := "https://cdn-images.dzcdn.net/images/cover/abc/1000x1000-000000-80-0-0.jpg"
	got, err := downloadCoverToMemory(url, true)
	if err != nil {
		t.Fatalf("download max cover: %v", err)
	}
	if !bytes.Equal(got, actualLargerDimensions) {
		t.Fatal("expected decoded 15x15 candidate instead of larger-byte 12x12 candidate")
	}
}

func TestBestCoverCandidateUsesByteSizeAsDimensionTiebreaker(t *testing.T) {
	orig := coverFetch
	defer func() { coverFetch = orig }()
	resetCoverCache()

	base := testPNG(t, 10, 10)
	largerFile := append(append([]byte(nil), base...), bytes.Repeat([]byte{0}, 512)...)
	coverFetch = func(url string) ([]byte, error) {
		if strings.Contains(url, "large") {
			return largerFile, nil
		}
		return base, nil
	}

	got, selected, width, height, err := fetchBestCoverCandidate(
		[]string{"https://covers.test/small", "https://covers.test/large"},
	)
	if err != nil {
		t.Fatalf("select cover: %v", err)
	}
	if selected != "https://covers.test/large" || width != 10 || height != 10 {
		t.Fatalf("selected=%q dimensions=%dx%d", selected, width, height)
	}
	if !bytes.Equal(got, largerFile) {
		t.Fatal("expected larger file when decoded dimensions are equal")
	}
}
