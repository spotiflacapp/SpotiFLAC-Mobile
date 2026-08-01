package gobackend

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dop251/goja"
	"github.com/go-flac/flacvorbis/v2"
)

func TestReadFileMetadataAndCueLibraryWrappers(t *testing.T) {
	dir := t.TempDir()
	mp3Path := filepath.Join(dir, "tagged.mp3")
	tag := buildID3v23Tag(
		id3TextFrame("TIT2", "Title"),
		id3TextFrame("TPE1", "Artist"),
		id3TextFrame("TALB", "Album"),
		id3TextFrame("TRCK", "4/12"),
		id3CommentFrame("USLT", "[00:00.00]Lyric"),
	)
	if err := os.WriteFile(mp3Path, append(tag, []byte{0xFF, 0xFB, 0x90, 0x64, 0, 0, 0, 0}...), 0600); err != nil {
		t.Fatal(err)
	}
	if jsonText, err := ReadFileMetadata(mp3Path); err != nil || !strings.Contains(jsonText, `"title":"Title"`) {
		t.Fatalf("ReadFileMetadata mp3 = %q/%v", jsonText, err)
	}

	m4aPath := filepath.Join(dir, "tagged.m4a")
	ilst := buildM4ATextTag("\xa9nam", "M4A Title")
	if err := os.WriteFile(m4aPath, buildM4AFileWithIlst(ilst, true), 0600); err != nil {
		t.Fatal(err)
	}
	if jsonText, err := ReadFileMetadata(m4aPath); err != nil || !strings.Contains(jsonText, "M4A Title") {
		t.Fatalf("ReadFileMetadata m4a = %q/%v", jsonText, err)
	}

	cuePath, _ := writeExportCueFixture(t, dir)
	results, err := ScanCueFileForLibrary(cuePath, time.Now().Format(time.RFC3339))
	if err != nil || len(results) != 1 || results[0].TrackName != "Song" {
		t.Fatalf("ScanCueFileForLibrary = %#v/%v", results, err)
	}
	if _, err := ReadFileMetadata(filepath.Join(dir, "unsupported.txt")); err == nil {
		t.Fatal("expected unsupported metadata format")
	}
}

func TestOutputFDFilePathBranches(t *testing.T) {
	dir := t.TempDir()
	outputPath := filepath.Join(dir, "out.bin")
	file, err := openOutputForWrite(outputPath, 0)
	if err != nil {
		t.Fatalf("openOutputForWrite path: %v", err)
	}
	if _, err := file.Write([]byte("data")); err != nil {
		t.Fatalf("write output: %v", err)
	}
	if err := file.Close(); err != nil {
		t.Fatalf("close output: %v", err)
	}
	if !isFDOutput(1) || isFDOutput(0) {
		t.Fatal("isFDOutput mismatch")
	}
	closeOwnedOutputFD(0)
	fdSource, err := os.OpenFile(outputPath, os.O_RDWR, 0600)
	if err != nil {
		t.Fatalf("open fd source: %v", err)
	}
	dupFD, err := dupOutputFD(int(fdSource.Fd()))
	if err != nil {
		_ = fdSource.Close()
		t.Fatalf("duplicate output fd: %v", err)
	}
	if err := prepareDupFDForWrite(dupFD, int(fdSource.Fd())); err != nil {
		_ = fdSource.Close()
		t.Fatalf("prepareDupFDForWrite: %v", err)
	}
	closeOwnedOutputFD(dupFD)
	if err := fdSource.Close(); err != nil {
		t.Fatalf("close fd source: %v", err)
	}
	cleanupOutputOnError(outputPath, 0)
	if _, err := os.Stat(outputPath); !os.IsNotExist(err) {
		t.Fatalf("cleanup should remove output path, stat err=%v", err)
	}
	cleanupOutputOnError("", 0)
	cleanupOutputOnError("/proc/self/fd/1", 0)
	cleanupOutputOnError(filepath.Join(dir, "kept.bin"), 10)
}

func TestMoreSmallConstructorsRuntimeAndMetadataHelpers(t *testing.T) {
	if cfg := DefaultRetryConfig(); cfg.MaxRetries == 0 || cfg.BackoffFactor <= 1 {
		t.Fatalf("DefaultRetryConfig = %#v", cfg)
	}
	if NewAppleMusicClient().httpClient == nil || NewNeteaseClient().httpClient == nil || NewMusixmatchClient().httpClient == nil || NewQQMusicClient().httpClient == nil {
		t.Fatal("expected lyric provider HTTP clients")
	}
	if NewIDHSClient().client == nil {
		t.Fatal("expected IDHS HTTP client")
	}

	vm := goja.New()
	runtime := &extensionRuntime{extensionID: "misc-runtime", vm: vm, settings: map[string]any{}}
	if parseExtensionTimeoutSeconds(" 42 ") != 42 || parseExtensionTimeoutSeconds("bad") != 0 || parseExtensionTimeoutSeconds(float64(7)) != 7 {
		t.Fatal("parseExtensionTimeoutSeconds mismatch")
	}
	if (&RedirectBlockedError{Domain: "blocked.example"}).Error() == "" || (&RedirectBlockedError{IsPrivate: true}).Error() == "" {
		t.Fatal("RedirectBlockedError Error mismatch")
	}
	runtime.SetSettings(map[string]any{"quality": "lossless"})
	if runtime.settings["quality"] != "lossless" {
		t.Fatal("SetSettings mismatch")
	}
	jar, _ := newSimpleCookieJar()
	cookieURL, _ := url.Parse("https://example.test/")
	jar.SetCookies(cookieURL, []*http.Cookie{{Name: "a", Value: "b"}})
	if cookies := jar.Cookies(cookieURL); len(cookies) != 1 || cookies[0].Value != "b" {
		t.Fatalf("cookies = %#v", cookies)
	}

	if result := runtime.ffmpegExecute(goja.FunctionCall{}).Export().(map[string]any); result["success"] != false {
		t.Fatalf("ffmpegExecute missing args = %#v", result)
	}
	if result := runtime.ffmpegGetInfo(goja.FunctionCall{}).Export().(map[string]any); result["success"] != false {
		t.Fatalf("ffmpegGetInfo missing args = %#v", result)
	}
	if result := runtime.ffmpegGetInfo(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("missing.flac")}}).Export().(map[string]any); result["success"] != false {
		t.Fatalf("ffmpegGetInfo missing file = %#v", result)
	}
	if result := runtime.ffmpegConvert(goja.FunctionCall{}).Export().(map[string]any); result["success"] != false {
		t.Fatalf("ffmpegConvert missing args = %#v", result)
	}

	cmt := flacvorbis.New()
	setComment(cmt, "TITLE", "Song")
	setComment(cmt, "ARTIST", "Artist")
	if getComment(cmt, "TITLE") != "Song" || getJoinedComment(cmt, "ARTIST") != "Artist" {
		t.Fatalf("comments = %#v", cmt.Comments)
	}
	setOrClearComment(cmt, "TITLE", "")
	if getComment(cmt, "TITLE") != "" {
		t.Fatal("setOrClearComment should remove empty value")
	}
	setOrClearArtistComments(cmt, "ARTIST", "A; B", artistTagModeSplitVorbis)
	if joined := getJoinedComment(cmt, "ARTIST"); !strings.Contains(joined, "A") || !strings.Contains(joined, "B") {
		t.Fatalf("split artist comments = %q", joined)
	}
	removeCommentKey(cmt, "ARTIST")
	if getComment(cmt, "ARTIST") != "" {
		t.Fatal("removeCommentKey failed")
	}
	if fileExists(filepath.Join(t.TempDir(), "missing")) {
		t.Fatal("missing file should not exist")
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("cover"))
	}))
	defer server.Close()
	SetNetworkCompatibilityOptions(true, false)
	defer SetNetworkCompatibilityOptions(false, false)
	coverPath := filepath.Join(t.TempDir(), "cover.jpg")
	if err := DownloadCoverToFile(server.URL+"/cover.jpg", coverPath, false); err != nil {
		t.Fatalf("DownloadCoverToFile: %v", err)
	}
	if string(mustReadFile(t, coverPath)) != "cover" {
		t.Fatal("downloaded cover mismatch")
	}
}

func TestExtensionHealthInitializeVMAndCustomSearchWrappers(t *testing.T) {
	dir := t.TempDir()
	extDir := filepath.Join(dir, "ext")
	if err := os.MkdirAll(extDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(extDir, "index.js"), []byte(testExtensionJS), 0600); err != nil {
		t.Fatal(err)
	}
	ext := &loadedExtension{
		ID: "health-ext",
		Manifest: &ExtensionManifest{
			Name:        "health-ext",
			DisplayName: "Health",
			Version:     "1.0.0",
			Description: "Health extension",
			Types:       []ExtensionType{ExtensionTypeMetadataProvider},
			SearchBehavior: &SearchBehaviorConfig{
				Enabled: true,
				Primary: true,
			},
			ServiceHealth: []ExtensionHealthCheck{{
				ID:       "bad",
				URL:      "http://health.example.test/status",
				Required: true,
			}},
		},
		Enabled:   true,
		SourceDir: extDir,
		DataDir:   filepath.Join(dir, "data"),
	}
	manager := getExtensionManager()
	manager.mu.Lock()
	if manager.extensions == nil {
		manager.extensions = map[string]*loadedExtension{}
	}
	manager.extensions[ext.ID] = ext
	manager.mu.Unlock()
	defer func() {
		manager.mu.Lock()
		delete(manager.extensions, ext.ID)
		manager.mu.Unlock()
	}()

	if err := manager.initializeVM(ext); err != nil {
		t.Fatalf("initializeVM: %v", err)
	}
	if ext.VM == nil {
		t.Fatal("expected initialized VM")
	}
	provider := &extensionProviderWrapper{extension: ext}
	if tracks, err := provider.CustomSearch("needle", map[string]any{"type": "track"}); err != nil || len(tracks) == 0 {
		t.Fatalf("CustomSearch = %#v/%v", tracks, err)
	}
	downloadCancels.mu.Lock()
	delete(downloadCancels.entries, "custom-item-unique")
	downloadCancels.mu.Unlock()
	if tracks, err := provider.customSearch("needle", nil, "custom-item-unique", ""); err != nil || len(tracks) == 0 {
		t.Fatalf("customSearch (item ID) = %#v/%v", tracks, err)
	}
	if healthJSON, err := CheckExtensionHealthJSON(ext.ID); err != nil || !strings.Contains(healthJSON, `"status":"offline"`) {
		t.Fatalf("CheckExtensionHealthJSON = %q/%v", healthJSON, err)
	}
	teardownVMLocked(ext)
}

func TestManifestPerfMatchingAndTitleHelpers(t *testing.T) {
	manifest := &ExtensionManifest{
		Name:        "misc-ext",
		DisplayName: "Misc",
		Version:     "1.0.0",
		Description: "Misc extension",
		Types:       []ExtensionType{ExtensionTypeMetadataProvider},
		URLHandler:  &URLHandlerConfig{Enabled: true, Patterns: []string{"example.test"}},
		PostProcessing: &PostProcessingConfig{Hooks: []PostProcessingHook{{
			ID: "hook", Name: "Hook",
		}}},
	}
	data, err := manifest.ToJSON()
	if err != nil || !strings.Contains(string(data), "misc-ext") {
		t.Fatalf("ToJSON = %q/%v", string(data), err)
	}
	if !manifest.HasURLHandler() || !manifest.MatchesURL("https://example.test/track") || len(manifest.GetPostProcessingHooks()) != 1 {
		t.Fatal("manifest helpers mismatch")
	}
	if (&ManifestValidationError{Field: "name", Message: "required"}).Error() == "" {
		t.Fatal("manifest validation error string empty")
	}

	if extensionDurationMs(1500*time.Microsecond) != 1.5 {
		t.Fatal("extensionDurationMs mismatch")
	}
	vm := goja.New()
	value := vm.ToValue(map[string]any{"tracks": []any{1, 2, 3}})
	if countExtensionTopLevelItems(vm, value) != 3 {
		t.Fatal("countExtensionTopLevelItems mismatch")
	}
	if countExtensionTopLevelItems(vm, goja.Undefined()) != 0 {
		t.Fatal("empty top-level item count mismatch")
	}

	if calculateStringSimilarity("", "") != 1 || calculateStringSimilarity("", "x") != 0 || levenshteinDistance("kitten", "sitting") != 3 {
		t.Fatal("string similarity helpers mismatch")
	}
	var b strings.Builder
	writeNormalizedArtistRune(&b, 'ß')
	writeNormalizedArtistRune(&b, 'æ')
	if b.String() != "ssae" {
		t.Fatalf("writeNormalizedArtistRune = %q", b.String())
	}
	if !artistsMatch("Artist feat Guest", "Guest") || !sameWordsUnordered("B A", "A B") || !titlesMatch("Song (Remastered)", "Song") {
		t.Fatal("artist/title matching mismatch")
	}
	if len(splitArtists("A & B, C x D")) != 4 {
		t.Fatal("splitArtists mismatch")
	}
	if isLatinScript("東京") || !isLatinScript("Beyonce") {
		t.Fatal("isLatinScript mismatch")
	}

	req := DownloadRequest{TrackName: "Song", ArtistName: "Artist", DurationMS: 180000}
	if !trackMatchesRequest(req, resolvedTrackInfo{Title: "Song", ArtistName: "Artist", Duration: 181}, "test") {
		t.Fatal("expected matching track")
	}
	if trackMatchesRequest(req, resolvedTrackInfo{Title: "Other", ArtistName: "Other", Duration: 240}, "test") {
		t.Fatal("expected mismatching track")
	}

	var decoded map[string]any
	if err := json.Unmarshal(data, &decoded); err != nil || decoded["name"] != "misc-ext" {
		t.Fatalf("manifest JSON decode = %#v/%v", decoded, err)
	}
}
