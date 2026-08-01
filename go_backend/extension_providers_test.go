package gobackend

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/dop251/goja"
)

func TestSetMetadataProviderPriorityStripsRetiredBuiltIns(t *testing.T) {
	original := GetMetadataProviderPriority()
	defer SetMetadataProviderPriority(original)

	SetMetadataProviderPriority([]string{"qobuz"})
	got := GetMetadataProviderPriority()
	if len(got) != 0 {
		t.Fatalf("expected retired built-in qobuz to be stripped, got %v", got)
	}
}

func TestSetExtensionFallbackProviderIDsDedupesExtensions(t *testing.T) {
	original := GetExtensionFallbackProviderIDs()
	defer SetExtensionFallbackProviderIDs(original)

	SetExtensionFallbackProviderIDs([]string{"ext-a", "ext-a", " ext-b "})

	got := GetExtensionFallbackProviderIDs()
	want := []string{"ext-a", "ext-b"}
	if len(got) != len(want) {
		t.Fatalf("unexpected fallback provider length: got %v want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("unexpected fallback provider at %d: got %v want %v", i, got, want)
		}
	}
}

func TestIsExtensionFallbackAllowedDefaultsToAllExtensions(t *testing.T) {
	original := GetExtensionFallbackProviderIDs()
	defer SetExtensionFallbackProviderIDs(original)

	SetExtensionFallbackProviderIDs(nil)

	if !isExtensionFallbackAllowed("custom-ext") {
		t.Fatal("expected custom extension to be allowed when no fallback allowlist is configured")
	}
}

func TestIsExtensionFallbackAllowedRespectsAllowlist(t *testing.T) {
	original := GetExtensionFallbackProviderIDs()
	defer SetExtensionFallbackProviderIDs(original)

	SetExtensionFallbackProviderIDs([]string{"allowed-ext"})

	if !isExtensionFallbackAllowed("allowed-ext") {
		t.Fatal("expected explicitly allowed extension to be permitted")
	}
	if isExtensionFallbackAllowed("blocked-ext") {
		t.Fatal("expected extension outside allowlist to be blocked")
	}
	if isExtensionFallbackAllowed("deezer") {
		t.Fatal("expected retired Deezer downloader to respect extension fallback allowlist")
	}
}

func TestSetProviderPriorityRemovesRetiredDeezerDownloader(t *testing.T) {
	original := GetProviderPriority()
	defer SetProviderPriority(original)

	SetProviderPriority([]string{"deezer", "qobuz", "custom-ext"})

	got := GetProviderPriority()
	want := []string{"custom-ext"}
	if len(got) != len(want) {
		t.Fatalf("unexpected priority length: got %v want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("unexpected priority at %d: got %v want %v", i, got, want)
		}
	}
}

func TestSetProviderPriorityKeepsExtensionNamedLikeRetiredDownloader(t *testing.T) {
	original := GetProviderPriority()
	defer SetProviderPriority(original)

	manager := getExtensionManager()
	ext := newTestLoadedExtension(t, ExtensionTypeDownloadProvider)
	ext.ID = "deezer"
	ext.Manifest.Name = "deezer"

	manager.mu.Lock()
	previous, hadPrevious := manager.extensions[ext.ID]
	manager.extensions[ext.ID] = ext
	manager.mu.Unlock()
	defer func() {
		manager.mu.Lock()
		if hadPrevious {
			manager.extensions[ext.ID] = previous
		} else {
			delete(manager.extensions, ext.ID)
		}
		manager.mu.Unlock()
	}()

	SetProviderPriority([]string{"deezer", "custom-ext"})

	got := GetProviderPriority()
	want := []string{"deezer", "custom-ext"}
	if len(got) != len(want) {
		t.Fatalf("unexpected priority length: got %v want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("unexpected priority at %d: got %v want %v", i, got, want)
		}
	}
}

func TestPrioritizeFallbackProvidersByHealthPrefersOnlineAndSkipsOffline(t *testing.T) {
	manager := getExtensionManager()
	amazon := newTestLoadedExtension(t, ExtensionTypeDownloadProvider)
	amazon.ID = "amazon"
	amazon.Manifest.Name = "amazon"
	amazon.Manifest.ServiceHealth = []ExtensionHealthCheck{{
		ID:       "main",
		URL:      "://bad",
		Required: true,
	}}

	plain := newTestLoadedExtension(t, ExtensionTypeDownloadProvider)
	plain.ID = "plain"
	plain.Manifest.Name = "plain"

	deezer := newTestLoadedExtension(t, ExtensionTypeDownloadProvider)
	deezer.ID = "deezer"
	deezer.Manifest.Name = "deezer"
	deezer.Manifest.ServiceHealth = []ExtensionHealthCheck{{
		ID:  "main",
		URL: "https://example.test/health",
	}}

	manager.mu.Lock()
	previousAmazon, hadAmazon := manager.extensions[amazon.ID]
	previousPlain, hadPlain := manager.extensions[plain.ID]
	previousDeezer, hadDeezer := manager.extensions[deezer.ID]
	manager.extensions[amazon.ID] = amazon
	manager.extensions[plain.ID] = plain
	manager.extensions[deezer.ID] = deezer
	manager.mu.Unlock()
	defer func() {
		manager.mu.Lock()
		if hadAmazon {
			manager.extensions[amazon.ID] = previousAmazon
		} else {
			delete(manager.extensions, amazon.ID)
		}
		if hadPlain {
			manager.extensions[plain.ID] = previousPlain
		} else {
			delete(manager.extensions, plain.ID)
		}
		if hadDeezer {
			manager.extensions[deezer.ID] = previousDeezer
		} else {
			delete(manager.extensions, deezer.ID)
		}
		manager.mu.Unlock()

		extensionHealthCacheMu.Lock()
		delete(extensionHealthCache, deezer.ID)
		extensionHealthCacheMu.Unlock()
	}()

	extensionHealthCacheMu.Lock()
	extensionHealthCache[deezer.ID] = cachedExtensionHealthResult{
		result: ExtensionHealthResult{
			ExtensionID: deezer.ID,
			Status:      "online",
			CheckedAt:   time.Now().UTC().Format(time.RFC3339),
		},
		expiresAt: time.Now().Add(time.Minute),
	}
	extensionHealthCacheMu.Unlock()

	got := prioritizeFallbackProvidersByHealth(
		[]string{"amazon", "plain", "deezer"},
		manager,
		"",
	)
	want := []string{"deezer", "plain"}
	if len(got) != len(want) {
		t.Fatalf("unexpected provider order length: got %v want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("unexpected provider order at %d: got %v want %v", i, got, want)
		}
	}
}

func TestNormalizeDownloadDecryptionInfoPromotesLegacyKey(t *testing.T) {
	normalized := normalizeDownloadDecryptionInfo(nil, " 001122 ")
	if normalized == nil {
		t.Fatal("expected legacy decryption key to produce normalized descriptor")
	}
	if normalized.Strategy != genericFFmpegMOVDecryptionStrategy {
		t.Fatalf("strategy = %q", normalized.Strategy)
	}
	if normalized.Key != "001122" {
		t.Fatalf("key = %q", normalized.Key)
	}
	if normalized.InputFormat != "mov" {
		t.Fatalf("input format = %q", normalized.InputFormat)
	}
}

func TestNormalizeDownloadDecryptionInfoCanonicalizesMovAliases(t *testing.T) {
	normalized := normalizeDownloadDecryptionInfo(&DownloadDecryptionInfo{
		Strategy:    "mp4_decryption_key",
		Key:         "abcd",
		InputFormat: "",
	}, "")
	if normalized == nil {
		t.Fatal("expected descriptor to remain available")
	}
	if normalized.Strategy != genericFFmpegMOVDecryptionStrategy {
		t.Fatalf("strategy = %q", normalized.Strategy)
	}
	if normalized.InputFormat != "mov" {
		t.Fatalf("input format = %q", normalized.InputFormat)
	}
}

func TestExtensionDownloadUsesIsolatedRuntimeForConcurrentCalls(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(500 * time.Millisecond)
		_, _ = w.Write([]byte("ok"))
	}))
	defer server.Close()
	setPrivateIPCache("download.test", false, time.Minute)

	originalTransport := sharedTransport
	testTransport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, network, server.Listener.Addr().String())
		},
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	sharedTransport = testTransport
	defer func() {
		testTransport.CloseIdleConnections()
		sharedTransport = originalTransport
	}()

	extDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(extDir, "index.js"), []byte(`
		registerExtension({
			download: function(trackID, quality, outputPath, onProgress) {
				var result = file.download('https://download.test/' + trackID, outputPath, {
					onProgress: function(written, total) {
						if (onProgress) onProgress(50);
					}
				});
				if (!result || !result.success) {
					return {
						success: false,
						error_message: result && result.error ? result.error : 'download failed',
						error_type: 'download_error'
					};
				}
				if (onProgress) onProgress(100);
				return { success: true, file_path: result.path };
			}
		});
	`), 0600); err != nil {
		t.Fatalf("write extension index: %v", err)
	}

	outputDir := t.TempDir()
	SetAllowedDownloadDirs([]string{outputDir})
	defer SetAllowedDownloadDirs(nil)

	ext := &loadedExtension{
		ID: "concurrent-download",
		Manifest: &ExtensionManifest{
			Name:        "concurrent-download",
			Description: "Concurrent download test",
			Version:     "1.0.0",
			Types:       []ExtensionType{ExtensionTypeDownloadProvider},
			Permissions: ExtensionPermissions{
				Network: []string{"download.test"},
				File:    true,
			},
		},
		Enabled:   true,
		SourceDir: extDir,
		DataDir:   t.TempDir(),
	}
	provider := newExtensionProviderWrapper(ext)

	start := time.Now()
	var wg sync.WaitGroup
	errs := make(chan error, 2)
	for i := 0; i < 2; i++ {
		i := i
		wg.Add(1)
		go func() {
			defer wg.Done()
			result, err := provider.Download(
				fmt.Sprintf("track-%d", i),
				"LOSSLESS",
				filepath.Join(outputDir, fmt.Sprintf("track-%d.flac", i)),
				"",
				nil,
			)
			if err != nil {
				errs <- err
				return
			}
			if result == nil || !result.Success {
				errs <- fmt.Errorf("download failed: %#v", result)
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}

	if elapsed := time.Since(start); elapsed >= 850*time.Millisecond {
		t.Fatalf("expected same-extension downloads to overlap, elapsed %s", elapsed)
	}
}

func TestBuildOutputPathAddsExplicitOutputDirToAllowedDirs(t *testing.T) {
	SetAllowedDownloadDirs(nil)

	outputDir := t.TempDir()
	outputPath := buildOutputPath(DownloadRequest{
		TrackName:      "Song",
		ArtistName:     "Artist",
		OutputDir:      outputDir,
		OutputExt:      ".flac",
		FilenameFormat: "",
	})

	if !isPathInAllowedDirs(outputPath) {
		t.Fatalf("expected output path %q to be allowed", outputPath)
	}
}

func TestBuildOutputPathForExtensionAddsExplicitOutputPathDirToAllowedDirs(t *testing.T) {
	SetAllowedDownloadDirs(nil)

	outputDir := t.TempDir()
	outputPath := filepath.Join(outputDir, "custom.flac")
	ext := &loadedExtension{DataDir: t.TempDir()}

	resolved := buildOutputPathForExtension(DownloadRequest{
		OutputPath: outputPath,
	}, ext)

	if resolved != outputPath {
		t.Fatalf("resolved output path = %q", resolved)
	}
	if !isPathInAllowedDirs(outputPath) {
		t.Fatalf("expected output path %q to be allowed", outputPath)
	}
}

func TestBuildOutputPathForExtensionUsesTempDirForFDOutput(t *testing.T) {
	SetAllowedDownloadDirs(nil)

	ext := &loadedExtension{DataDir: t.TempDir()}
	resolved := buildOutputPathForExtension(DownloadRequest{
		TrackName:  "Song",
		ArtistName: "Artist",
		OutputDir:  filepath.Join("Artist", "Album"),
		OutputFD:   123,
		OutputExt:  ".flac",
	}, ext)

	expectedBase := filepath.Join(ext.DataDir, "downloads")
	if !isPathWithinBase(expectedBase, resolved) {
		t.Fatalf("expected SAF extension output under %q, got %q", expectedBase, resolved)
	}
	if !isPathInAllowedDirs(resolved) {
		t.Fatalf("expected resolved output path %q to be allowed", resolved)
	}
}

func TestBuildOutputPathSanitizesTemplateFilename(t *testing.T) {
	SetAllowedDownloadDirs(nil)

	outputDir := t.TempDir()
	outputPath := buildOutputPath(DownloadRequest{
		TrackName:      `Gehra Hua (From "Dhurandhar")`,
		ArtistName:     "Artist",
		OutputDir:      outputDir,
		OutputExt:      ".flac",
		FilenameFormat: "{artist} - {title}",
	})

	base := filepath.Base(outputPath)
	if strings.ContainsAny(base, `<>:"/\|?*`) {
		t.Fatalf("output filename still contains illegal characters: %q", base)
	}
	if strings.Contains(base, `"`) {
		t.Fatalf("output filename still contains straight double quote: %q", base)
	}
}

func TestBuildOutputPathForExtensionSanitizesTemplateFilename(t *testing.T) {
	SetAllowedDownloadDirs(nil)

	ext := &loadedExtension{DataDir: t.TempDir()}
	resolved := buildOutputPathForExtension(DownloadRequest{
		TrackName:      `Gehra Hua (From "Dhurandhar")`,
		ArtistName:     "Artist",
		OutputFD:       123,
		OutputExt:      ".flac",
		FilenameFormat: "{artist} - {title}",
	}, ext)

	base := filepath.Base(resolved)
	if strings.ContainsAny(base, `<>:"/\|?*`) {
		t.Fatalf("extension output filename still contains illegal characters: %q", base)
	}
}

func TestShouldStopProviderFallback(t *testing.T) {
	if shouldStopProviderFallback(nil) {
		t.Fatal("nil availability should not stop fallback")
	}
	if shouldStopProviderFallback(&ExtAvailabilityResult{Available: false}) {
		t.Fatal("availability without skip_fallback should not stop fallback")
	}
	if !shouldStopProviderFallback(&ExtAvailabilityResult{Available: false, SkipFallback: true}) {
		t.Fatal("skip_fallback availability should stop fallback")
	}
}

func TestMoveProviderToFrontPreservesExplicitSelection(t *testing.T) {
	priority := []string{"qobuz-web", "amazon-web", "tidal-web"}
	got := moveProviderToFront(priority, "AMAZON-WEB")
	want := []string{"amazon-web", "qobuz-web", "tidal-web"}

	if !reflect.DeepEqual(got, want) {
		t.Fatalf("moveProviderToFront() = %#v, want %#v", got, want)
	}
	if !reflect.DeepEqual(priority, []string{"qobuz-web", "amazon-web", "tidal-web"}) {
		t.Fatalf("moveProviderToFront mutated input: %#v", priority)
	}
}

func TestDiscardRejectedExtensionOutputStaysInsideRequestedDirectory(t *testing.T) {
	outputDir := t.TempDir()
	requestedPath := filepath.Join(outputDir, "Artist - Song.flac")
	rejectedPath := filepath.Join(outputDir, "Artist - Song.m4a")
	outsidePath := filepath.Join(t.TempDir(), "keep.flac")
	if err := os.WriteFile(rejectedPath, []byte("wrong audio"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(outsidePath, []byte("keep"), 0o600); err != nil {
		t.Fatal(err)
	}

	discardRejectedExtensionOutput(&ExtDownloadResult{FilePath: rejectedPath}, requestedPath)
	if _, err := os.Stat(rejectedPath); !os.IsNotExist(err) {
		t.Fatalf("rejected output was not removed: %v", err)
	}

	discardRejectedExtensionOutput(&ExtDownloadResult{FilePath: outsidePath}, requestedPath)
	if _, err := os.Stat(outsidePath); err != nil {
		t.Fatalf("output outside requested directory was removed: %v", err)
	}
}

func TestDiscardRejectedExtensionOutputPreservesExistingLibraryHit(t *testing.T) {
	outputDir := t.TempDir()
	path := filepath.Join(outputDir, "existing.flac")
	if err := os.WriteFile(path, []byte("existing audio"), 0o600); err != nil {
		t.Fatal(err)
	}

	discardRejectedExtensionOutput(&ExtDownloadResult{
		FilePath:      path,
		AlreadyExists: true,
	}, filepath.Join(outputDir, "requested.flac"))
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("existing library file was removed: %v", err)
	}
}

func TestBuildExtensionFallbackStoppedResponsePrefersAvailabilityReason(t *testing.T) {
	resp := buildExtensionFallbackStoppedResponse("soundcloud", &ExtAvailabilityResult{
		Reason:       "direct SoundCloud track ID",
		SkipFallback: true,
	}, errors.New("ignored"))

	if resp.Service != "soundcloud" {
		t.Fatalf("service = %q", resp.Service)
	}
	if resp.Error != "Fallback stopped by soundcloud: direct SoundCloud track ID" {
		t.Fatalf("unexpected error message: %q", resp.Error)
	}
	if resp.ErrorType != "extension_error" {
		t.Fatalf("error type = %q", resp.ErrorType)
	}
}

func TestBuildExtensionFallbackStoppedResponseFallsBackToError(t *testing.T) {
	resp := buildExtensionFallbackStoppedResponse("soundcloud", &ExtAvailabilityResult{
		SkipFallback: true,
	}, errors.New("lookup failed"))

	if resp.Error != "Fallback stopped by soundcloud: lookup failed" {
		t.Fatalf("unexpected error message: %q", resp.Error)
	}
}

func TestShouldAbortCancelledFallbackWithCancelledError(t *testing.T) {
	if !shouldAbortCancelledFallback("", ErrDownloadCancelled) {
		t.Fatal("expected cancelled error to abort fallback")
	}
}

func TestShouldAbortCancelledFallbackWithCancelledItemState(t *testing.T) {
	const itemID = "cancelled-item"
	initDownloadCancel(itemID)
	defer clearDownloadCancel(itemID)

	cancelDownload(itemID)

	if !shouldAbortCancelledFallback(itemID, errors.New("generic failure")) {
		t.Fatal("expected cancelled item state to abort fallback even for generic errors")
	}
}

func TestCanEmbedGenreLabelRequiresExistingAbsoluteLocalFile(t *testing.T) {
	tempFile := filepath.Join(t.TempDir(), "track.flac")
	if err := os.WriteFile(tempFile, []byte("fLaC"), 0644); err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	tempM4A := filepath.Join(t.TempDir(), "track.m4a")
	if err := os.WriteFile(tempM4A, []byte("not-flac"), 0644); err != nil {
		t.Fatalf("failed to create temp m4a file: %v", err)
	}

	if canEmbedGenreLabel("relative.flac") {
		t.Fatal("expected relative path to be rejected")
	}
	if canEmbedGenreLabel("content://example") {
		t.Fatal("expected content URI to be rejected")
	}
	if canEmbedGenreLabel(filepath.Join(t.TempDir(), "missing.flac")) {
		t.Fatal("expected missing file to be rejected")
	}
	if canEmbedGenreLabel(tempM4A) {
		t.Fatalf("expected non-FLAC file %q to be rejected", tempM4A)
	}
	if !canEmbedGenreLabel(tempFile) {
		t.Fatalf("expected existing absolute file %q to be accepted", tempFile)
	}
}

func TestSearchTracksWithMetadataProvidersIgnoresRetiredBuiltIns(t *testing.T) {
	originalPriority := GetMetadataProviderPriority()
	defer func() {
		SetMetadataProviderPriority(originalPriority)
	}()

	SetMetadataProviderPriority([]string{"qobuz"})

	manager := getExtensionManager()
	tracks, err := manager.SearchTracksWithMetadataProviders("query", 3, false)
	if err != nil {
		t.Fatalf("SearchTracksWithMetadataProviders returned error: %v", err)
	}
	if len(tracks) != 0 {
		t.Fatalf("expected no tracks from retired built-in provider, got %+v", tracks)
	}
}

func TestParseExtensionSearchResultAcceptsObjectAndArrayShapes(t *testing.T) {
	vm := goja.New()
	value, err := vm.RunString(`({
		tracks: [{
			id: "track-1",
			name: "Song",
			artists: "Artist",
			album_name: "Album",
			duration_ms: 123000,
			cover_url: "https://img.test/cover.jpg",
			external_links: { spotify: "spotify:track:1" },
			audio_quality: "LOSSLESS"
		}],
		total: 9
	})`)
	if err != nil {
		t.Fatalf("build object search result: %v", err)
	}

	result, err := parseExtensionSearchResult(vm, value)
	if err != nil {
		t.Fatalf("parse object search result: %v", err)
	}
	if result.Total != 9 || len(result.Tracks) != 1 {
		t.Fatalf("unexpected object result: %+v", result)
	}
	track := result.Tracks[0]
	if track.ID != "track-1" ||
		track.AlbumName != "Album" ||
		track.DurationMS != 123000 ||
		track.CoverURL != "https://img.test/cover.jpg" ||
		track.ExternalLinks["spotify"] != "spotify:track:1" ||
		track.AudioQuality != "LOSSLESS" {
		t.Fatalf("unexpected parsed track: %+v", track)
	}

	arrayValue, err := vm.RunString(`[
		{id: "track-2", name: "Other Song", artists: "Other Artist", albumName: "Other Album", durationMs: 456000}
	]`)
	if err != nil {
		t.Fatalf("build array search result: %v", err)
	}

	arrayResult, err := parseExtensionSearchResult(vm, arrayValue)
	if err != nil {
		t.Fatalf("parse array search result: %v", err)
	}
	if arrayResult.Total != 1 ||
		len(arrayResult.Tracks) != 1 ||
		arrayResult.Tracks[0].AlbumName != "Other Album" ||
		arrayResult.Tracks[0].DurationMS != 456000 {
		t.Fatalf("unexpected array result: %+v", arrayResult)
	}
}

func TestParseExtensionMetadataAndDownloadResults(t *testing.T) {
	vm := goja.New()
	value, err := vm.RunString(`({
		id: "album-1",
		name: "Album",
		artists: "Artist",
		artistId: "artist-1",
		coverUrl: "https://img.test/album.jpg",
		releaseDate: "2024-02-03",
		totalTracks: 2,
		albumType: "album",
		tracks: [
			{id: "track-1", name: "Song 1", artists: "Artist", durationMs: 180000},
			{id: "track-2", name: "Song 2", artists: "Artist", duration_ms: 181000}
		]
	})`)
	if err != nil {
		t.Fatalf("build album value: %v", err)
	}

	album, err := parseExtensionAlbumValue(vm, value)
	if err != nil {
		t.Fatalf("parse album: %v", err)
	}
	if album.ID != "album-1" ||
		album.ArtistID != "artist-1" ||
		album.CoverURL != "https://img.test/album.jpg" ||
		album.TotalTracks != 2 ||
		len(album.Tracks) != 2 ||
		album.Tracks[0].DurationMS != 180000 ||
		album.Tracks[1].DurationMS != 181000 {
		t.Fatalf("unexpected album: %+v", album)
	}

	artistValue, err := vm.RunString(`({
		id: "artist-1",
		name: "Artist",
		imageUrl: "https://img.test/artist.jpg",
		headerImage: "https://img.test/header.jpg",
		listeners: 1234,
		albums: [{id: "album-1", name: "Album", tracks: [{id: "track-1", name: "Song"}]}],
		releases: [{id: "single-1", name: "Single"}],
		topTracks: [{id: "top-1", name: "Top Song"}]
	})`)
	if err != nil {
		t.Fatalf("build artist value: %v", err)
	}

	artist, err := parseExtensionArtistValue(vm, artistValue)
	if err != nil {
		t.Fatalf("parse artist: %v", err)
	}
	if artist.ID != "artist-1" ||
		artist.ImageURL != "https://img.test/artist.jpg" ||
		artist.HeaderImage != "https://img.test/header.jpg" ||
		artist.Listeners != 1234 ||
		len(artist.Albums) != 1 ||
		len(artist.Albums[0].Tracks) != 1 ||
		len(artist.Releases) != 1 ||
		len(artist.TopTracks) != 1 {
		t.Fatalf("unexpected artist: %+v", artist)
	}

	downloadValue, err := vm.RunString(`({
		success: true,
		filePath: "/tmp/song.flac",
		alreadyExists: true,
		bitDepth: 24,
		sampleRate: 96000,
		durationMs: 181000,
		title: "Song",
		albumArtist: "Album Artist",
		lyricsLrc: "[00:00.00]Line",
		decryptionKey: "001122",
		decryption: {
			strategy: "mp4_decryption_key",
			key: "001122",
			inputFormat: "m4a",
			options: { map: "0:a" }
		}
	})`)
	if err != nil {
		t.Fatalf("build download value: %v", err)
	}

	download := parseExtensionDownloadResultValue(vm, downloadValue)
	if !download.Success ||
		download.FilePath != "/tmp/song.flac" ||
		!download.AlreadyExists ||
		download.BitDepth != 24 ||
		download.SampleRate != 96000 ||
		download.DurationMS != 181000 ||
		download.AlbumArtist != "Album Artist" ||
		download.LyricsLRC != "[00:00.00]Line" ||
		download.Decryption == nil ||
		download.Decryption.InputFormat != "m4a" ||
		download.Decryption.Options["map"] != "0:a" {
		t.Fatalf("unexpected download result: %+v", download)
	}

	availabilityValue, err := vm.RunString(`({ available: true, trackId: "track-1", skipFallback: true, reason: "direct" })`)
	if err != nil {
		t.Fatalf("build availability value: %v", err)
	}
	availability := parseExtensionAvailabilityValue(vm, availabilityValue)
	if !availability.Available || availability.TrackID != "track-1" || !availability.SkipFallback || availability.Reason != "direct" {
		t.Fatalf("unexpected availability: %+v", availability)
	}
}

func TestParseExtensionURLHandleResult(t *testing.T) {
	vm := goja.New()
	value, err := vm.RunString(`({
		type: "album",
		name: "Shared Album",
		coverUrl: "https://img.test/shared.jpg",
		track: { id: "track-1", name: "Song" },
		tracks: [{ id: "track-2", name: "Song 2" }],
		album: { id: "album-1", name: "Album", tracks: [{ id: "track-3", name: "Song 3" }] },
		artist: { id: "artist-1", name: "Artist", topTracks: [{ id: "track-4", name: "Song 4" }] }
	})`)
	if err != nil {
		t.Fatalf("build URL handle value: %v", err)
	}

	result, err := parseExtensionURLHandleValue(vm, value)
	if err != nil {
		t.Fatalf("parse URL handle: %v", err)
	}
	if result.Type != "album" ||
		result.CoverURL != "https://img.test/shared.jpg" ||
		result.Track == nil ||
		result.Track.ID != "track-1" ||
		len(result.Tracks) != 1 ||
		result.Album == nil ||
		len(result.Album.Tracks) != 1 ||
		result.Artist == nil ||
		len(result.Artist.TopTracks) != 1 {
		t.Fatalf("unexpected URL handle result: %+v", result)
	}
}

func TestParseExtensionAuxiliaryResults(t *testing.T) {
	vm := goja.New()

	postValue, err := vm.RunString(`({ success: true, newFilePath: "/tmp/new.flac", newFileUri: "content://new", bitDepth: 24, sampleRate: 96000 })`)
	if err != nil {
		t.Fatalf("build post-process value: %v", err)
	}
	post := parseExtensionPostProcessValue(vm, postValue)
	if !post.Success || post.NewFilePath != "/tmp/new.flac" || post.NewFileURI != "content://new" || post.BitDepth != 24 || post.SampleRate != 96000 {
		t.Fatalf("unexpected post-process result: %+v", post)
	}

	lyricsValue, err := vm.RunString(`({
		syncType: "LINE_SYNCED",
		instrumental: false,
		plainLyrics: "Line",
		provider: "Lyrics Provider",
		lines: [{ startTimeMs: 1000, words: "Line", endTimeMs: 2000 }]
	})`)
	if err != nil {
		t.Fatalf("build lyrics value: %v", err)
	}
	lyrics, err := parseExtensionLyricsValue(vm, lyricsValue)
	if err != nil {
		t.Fatalf("parse lyrics: %v", err)
	}
	if lyrics.SyncType != "LINE_SYNCED" ||
		lyrics.PlainLyrics != "Line" ||
		lyrics.Provider != "Lyrics Provider" ||
		len(lyrics.Lines) != 1 ||
		lyrics.Lines[0].StartTimeMs != 1000 ||
		lyrics.Lines[0].EndTimeMs != 2000 {
		t.Fatalf("unexpected lyrics result: %+v", lyrics)
	}
}

func TestMatchesURLHostAnchored(t *testing.T) {
	manifest := &ExtensionManifest{
		URLHandler: &URLHandlerConfig{
			Enabled:  true,
			Patterns: []string{"spotify.com", "deezer.page.link", "spotify:"},
		},
	}

	for _, urlStr := range []string{
		"https://open.spotify.com/track/abc",
		"https://spotify.com/track/abc",
		"HTTPS://OPEN.SPOTIFY.COM/track/ABC",
		"https://deezer.page.link/xyz",
		"spotify:track:abc123",
	} {
		if !manifest.MatchesURL(urlStr) {
			t.Fatalf("expected match for %q", urlStr)
		}
	}

	for _, urlStr := range []string{
		// The old substring matching accepted all of these.
		"https://evil.example/?next=https://spotify.com/track/abc",
		"https://notspotify.com/track/abc",
		"https://spotify.com.evil.example/track/abc",
		"https://example.com/spotify.com",
		"not a url at all",
	} {
		if manifest.MatchesURL(urlStr) {
			t.Fatalf("expected no match for %q", urlStr)
		}
	}

	withPath := &ExtensionManifest{
		URLHandler: &URLHandlerConfig{
			Enabled:  true,
			Patterns: []string{"youtube.com/watch"},
		},
	}
	if !withPath.MatchesURL("https://www.youtube.com/watch?v=abc") {
		t.Fatal("expected host+path prefix to match")
	}
	if withPath.MatchesURL("https://www.youtube.com/playlist?list=abc") {
		t.Fatal("expected different path to not match")
	}
}
