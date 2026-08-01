package gobackend

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDownloadErrorClassificationPrioritizesRateLimit(t *testing.T) {
	got := classifyDownloadErrorType("All providers failed. Last error: HTTP status 429: too many requests")
	if got != "rate_limit" {
		t.Fatalf("expected rate_limit, got %q", got)
	}

	responseJSON, err := errorResponse("All services failed. Last error: rate limit exceeded")
	if err != nil {
		t.Fatalf("errorResponse returned error: %v", err)
	}

	var response DownloadResponse
	if err := json.Unmarshal([]byte(responseJSON), &response); err != nil {
		t.Fatalf("invalid response JSON: %v", err)
	}
	if response.ErrorType != "rate_limit" {
		t.Fatalf("expected rate_limit response, got %q", response.ErrorType)
	}
}

func TestDownloadErrorClassificationDetectsVerificationRequired(t *testing.T) {
	cases := []string{
		"verification_required: canonical gateway challenge",
		"signed session expired",
	}
	for _, tc := range cases {
		if got := classifyDownloadErrorType(tc); got != "verification_required" {
			t.Fatalf("classifyDownloadErrorType(%q) = %q, want verification_required", tc, got)
		}
	}
}

func TestDownloadErrorClassificationDoesNotInferVerificationFromHTTPStatus(t *testing.T) {
	cases := []string{
		"HTTP 401 for /tickets",
		"HTTP 403 forbidden",
		"HTTP status 428: precondition required",
		"Provider returned unauthorized",
		"VERIFY_REQUIRED without canonical origin and action",
		"Verification required without a typed contract",
	}
	for _, tc := range cases {
		if got := classifyDownloadErrorType(tc); got == "verification_required" {
			t.Fatalf("classifyDownloadErrorType(%q) inferred verification from an ambiguous status", tc)
		}
	}
}

func TestDownloadErrorClassificationPreservesProviderContracts(t *testing.T) {
	tests := map[string]string{
		"PROVIDER_AUTH_FAILED":                 "provider_auth_failed",
		"PROVIDER_UNAVAILABLE":                 "provider_unavailable",
		"REQUEST_AUTH_INVALID":                 "request_auth_invalid",
		"BYOA_PROVIDER_REAUTH_REQUIRED action": "provider_reauth_required",
	}
	for message, want := range tests {
		if got := classifyDownloadErrorType(message); got != want {
			t.Fatalf("classifyDownloadErrorType(%q) = %q, want %q", message, got, want)
		}
	}
}

func TestOutputStorageWriteFailureDetection(t *testing.T) {
	cases := []struct {
		name      string
		errorType string
		message   string
		want      bool
	}{
		{
			name:      "typed permission failure",
			errorType: "permission",
			message:   "backend omitted details",
			want:      true,
		},
		{
			name:    "android operation not permitted",
			message: "failed to create file: open /storage/song.partial: operation not permitted",
			want:    true,
		},
		{
			name:    "read only destination",
			message: "open /music/song.flac: read-only file system",
			want:    true,
		},
		{
			name:      "provider API error",
			errorType: "api_error",
			message:   "HTTP 404 for /download",
			want:      false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isOutputStorageWriteFailure(tc.errorType, tc.message); got != tc.want {
				t.Fatalf("isOutputStorageWriteFailure(%q, %q) = %v, want %v", tc.errorType, tc.message, got, tc.want)
			}
		})
	}
}

func TestGetProviderMetadataPrefersEnabledDeezerExtension(t *testing.T) {
	dir := t.TempDir()
	if err := InitExtensionSystem(filepath.Join(dir, "extensions"), filepath.Join(dir, "data")); err != nil {
		t.Fatalf("InitExtensionSystem: %v", err)
	}
	CleanupExtensions()
	defer CleanupExtensions()

	ext := newTestLoadedExtension(t, ExtensionTypeMetadataProvider)
	ext.ID = "deezer"
	ext.Manifest.Name = "deezer"
	manager := getExtensionManager()
	manager.mu.Lock()
	manager.extensions = map[string]*loadedExtension{ext.ID: ext}
	manager.mu.Unlock()

	jsonText, err := GetProviderMetadataJSON("deezer", "album", "201")
	if err != nil {
		t.Fatalf("GetProviderMetadataJSON deezer album: %v", err)
	}
	if !strings.Contains(jsonText, "album-track") {
		t.Fatalf("expected enabled deezer extension metadata, got %s", jsonText)
	}
}

func TestExtensionTrackExportsPreserveExplicitFlag(t *testing.T) {
	dir := t.TempDir()
	if err := InitExtensionSystem(filepath.Join(dir, "extensions"), filepath.Join(dir, "data")); err != nil {
		t.Fatalf("InitExtensionSystem: %v", err)
	}

	ext := newTestLoadedExtension(t, ExtensionTypeMetadataProvider)
	manager := getExtensionManager()
	manager.mu.Lock()
	manager.extensions = map[string]*loadedExtension{ext.ID: ext}
	manager.mu.Unlock()
	defer CleanupExtensions()

	assertExplicit := func(name, jsonText string, err error) {
		t.Helper()
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if !strings.Contains(jsonText, `"explicit":true`) {
			t.Fatalf("%s dropped explicit flag: %s", name, jsonText)
		}
	}

	jsonText, err := CustomSearchWithExtensionJSON(ext.ID, "needle", `{"filter":"tracks"}`)
	assertExplicit("custom search", jsonText, err)

	for _, resourceType := range []string{"track", "album", "playlist", "artist"} {
		jsonText, err = GetProviderMetadataJSON(ext.ID, resourceType, resourceType+"-1")
		assertExplicit("provider metadata "+resourceType, jsonText, err)
	}

	jsonText, err = HandleURLWithExtensionJSON("https://example.test/track/1")
	assertExplicit("URL handler", jsonText, err)
}

func TestSearchTracksWithMetadataProviderUsesOnlySelectedExtension(t *testing.T) {
	dir := t.TempDir()
	if err := InitExtensionSystem(filepath.Join(dir, "extensions"), filepath.Join(dir, "data")); err != nil {
		t.Fatalf("InitExtensionSystem: %v", err)
	}

	selected := newTestLoadedExtension(t, ExtensionTypeMetadataProvider)
	selected.ID = "selected-metadata"
	selected.Manifest.Name = selected.ID
	other := newTestLoadedExtension(t, ExtensionTypeMetadataProvider)
	other.ID = "other-metadata"
	other.Manifest.Name = other.ID

	manager := getExtensionManager()
	manager.mu.Lock()
	manager.extensions = map[string]*loadedExtension{
		selected.ID: selected,
		other.ID:    other,
	}
	manager.mu.Unlock()
	defer CleanupExtensions()

	jsonText, err := SearchTracksWithMetadataProviderJSON(selected.ID, "needle", 5)
	if err != nil {
		t.Fatalf("SearchTracksWithMetadataProviderJSON: %v", err)
	}
	if !strings.Contains(jsonText, `"provider_id":"selected-metadata"`) {
		t.Fatalf("expected selected provider attribution, got %s", jsonText)
	}
	if strings.Contains(jsonText, `"provider_id":"other-metadata"`) {
		t.Fatalf("unexpected fallback to another provider: %s", jsonText)
	}
}

func TestExportsJSONWrappersAndExtensionManagerSurface(t *testing.T) {
	dir := t.TempDir()
	dataDir := filepath.Join(dir, "data")
	extensionsDir := filepath.Join(dir, "extensions")
	if err := InitExtensionSystem(extensionsDir, dataDir); err != nil {
		t.Fatalf("InitExtensionSystem: %v", err)
	}

	ext := newTestLoadedExtension(t, ExtensionTypeMetadataProvider, ExtensionTypeDownloadProvider, ExtensionTypeLyricsProvider)
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

	if response, err := DownloadByStrategy(`not-json`); err != nil || !strings.Contains(response, "Invalid request") {
		t.Fatalf("DownloadByStrategy invalid = %q/%v", response, err)
	}
	if response, err := DownloadByStrategy(`{"use_extensions":false}`); err != nil || !strings.Contains(response, "disabled") {
		t.Fatalf("DownloadByStrategy disabled = %q/%v", response, err)
	}

	InitItemProgress("item-1")
	ClearItemProgress("item-1")
	CancelDownload("item-1")
	if GetAllDownloadProgress() == "" || GetAllDownloadProgressDelta(0) == "" {
		t.Fatal("expected progress JSON")
	}
	CleanupConnections()

	cuePath, audioPath := writeExportCueFixture(t, dir)
	if jsonText, err := ParseCueSheet(cuePath, ""); err != nil {
		t.Fatalf("ParseCueSheet = %q/%v", jsonText, err)
	} else {
		var parsed CueSplitInfo
		if err := json.Unmarshal([]byte(jsonText), &parsed); err != nil {
			t.Fatalf("decode ParseCueSheet: %v", err)
		}
		if parsed.AudioPath != audioPath {
			t.Fatalf("ParseCueSheet audio path = %q want %q", parsed.AudioPath, audioPath)
		}
	}
	if jsonText, err := ScanCueSheetForLibrary(cuePath, "", "virtual.cue", 111); err != nil || !strings.Contains(jsonText, "cue+wav") {
		t.Fatalf("ScanCueSheetForLibrary = %q/%v", jsonText, err)
	}
	if jsonText, err := ScanCueSheetForLibraryWithCoverCacheKey(cuePath, "", "virtual.cue", 111, "cover-key"); err != nil || !strings.Contains(jsonText, "cue+wav") {
		t.Fatalf("ScanCueSheetForLibraryWithCoverCacheKey = %q/%v", jsonText, err)
	}

	apePath := filepath.Join(dir, "edit.ape")
	if err := os.WriteFile(apePath, []byte("audio"), 0600); err != nil {
		t.Fatal(err)
	}
	editJSON := `{"title":"Edited","artist":"Artist","track_number":"1","track_total":"2","disc_number":"1","disc_total":"1"}`
	if response, err := EditFileMetadata(apePath, editJSON); err != nil || !strings.Contains(response, "native_ape") {
		t.Fatalf("EditFileMetadata ape = %q/%v", response, err)
	}
	if response, err := EditFileMetadata(filepath.Join(dir, "edit.mp3"), editJSON); err != nil || !strings.Contains(response, "ffmpeg") {
		t.Fatalf("EditFileMetadata ffmpeg = %q/%v", response, err)
	}
	misnamedM4APath := filepath.Join(dir, "misnamed.flac")
	if err := os.WriteFile(misnamedM4APath, buildM4AFileWithIlst(buildM4ATextTag("\xa9nam", "Misnamed"), true), 0600); err != nil {
		t.Fatal(err)
	}
	replayGainJSON := `{"replaygain_track_gain":"-1 dB","replaygain_track_peak":"0.9"}`
	if response, err := EditFileMetadata(misnamedM4APath, replayGainJSON); err != nil || !strings.Contains(response, "native_m4a_replaygain") {
		t.Fatalf("EditFileMetadata misnamed m4a replaygain = %q/%v", response, err)
	}
	if _, err := EditFileMetadata(apePath, `not-json`); err == nil {
		t.Fatal("expected invalid metadata JSON")
	}
	if !hasOnlyM4AReplayGainFields(map[string]string{"replaygain_track_gain": "-1 dB"}) {
		t.Fatal("expected replaygain-only fields")
	}
	if hasOnlyM4AReplayGainFields(map[string]string{"title": "Song"}) {
		t.Fatal("expected non-replaygain field rejection")
	}

	AllowDownloadDir(dir)
	if err := SetDownloadDirectory(dir); err != nil {
		t.Fatalf("SetDownloadDirectory: %v", err)
	}
	if batchJSON, err := CheckDuplicatesBatch(dir, `[{"isrc":"","track_name":"Song","artist_name":"Artist"}]`); err != nil || !strings.Contains(batchJSON, "Song") {
		t.Fatalf("CheckDuplicatesBatch = %q/%v", batchJSON, err)
	}
	_ = PreBuildDuplicateIndex(dir)
	InvalidateDuplicateIndex(dir)
	if filename, err := BuildFilename("{artist} - {title}", `{"artist":"A/B","title":"Song?"}`); err != nil || filename == "" {
		t.Fatalf("BuildFilename = %q/%v", filename, err)
	}
	if _, err := BuildFilename("{title}", `not-json`); err == nil {
		t.Fatal("expected BuildFilename JSON error")
	}
	if got := SanitizeFilename(`A/B:C*D?`); strings.ContainsAny(got, `/:*?`) {
		t.Fatalf("SanitizeFilename = %q", got)
	}

	if GetTrackCacheSize() != 0 {
		t.Fatal("expected empty track cache")
	}
	ClearTrackIDCache()

	if err := SetLyricsProvidersJSON(`["lrclib","apple_music"]`); err != nil {
		t.Fatalf("SetLyricsProvidersJSON: %v", err)
	}
	if providers, err := GetLyricsProvidersJSON(); err != nil || !strings.Contains(providers, "lrclib") {
		t.Fatalf("GetLyricsProvidersJSON = %q/%v", providers, err)
	}
	if available, err := GetAvailableLyricsProvidersJSON(); err != nil || available == "" {
		t.Fatalf("GetAvailableLyricsProvidersJSON = %q/%v", available, err)
	}
	if err := SetLyricsFetchOptionsJSON(`{"include_translation_netease":true}`); err != nil {
		t.Fatalf("SetLyricsFetchOptionsJSON: %v", err)
	}
	if opts, err := GetLyricsFetchOptionsJSON(); err != nil || opts == "" {
		t.Fatalf("GetLyricsFetchOptionsJSON = %q/%v", opts, err)
	}

	if err := SetProviderPriorityJSON(`["coverage-ext"]`); err != nil {
		t.Fatalf("SetProviderPriorityJSON: %v", err)
	}
	if jsonText, err := GetProviderPriorityJSON(); err != nil || !strings.Contains(jsonText, "coverage-ext") {
		t.Fatalf("GetProviderPriorityJSON = %q/%v", jsonText, err)
	}
	if err := SetExtensionFallbackProviderIDsJSON(`["coverage-ext"]`); err != nil {
		t.Fatalf("SetExtensionFallbackProviderIDsJSON: %v", err)
	}
	if err := SetExtensionFallbackProviderIDsJSON(""); err != nil {
		t.Fatalf("reset extension fallback IDs: %v", err)
	}
	if err := SetMetadataProviderPriorityJSON(`["coverage-ext"]`); err != nil {
		t.Fatalf("SetMetadataProviderPriorityJSON: %v", err)
	}
	if jsonText, err := GetMetadataProviderPriorityJSON(); err != nil || !strings.Contains(jsonText, "coverage-ext") {
		t.Fatalf("GetMetadataProviderPriorityJSON = %q/%v", jsonText, err)
	}

	if err := SetExtensionSettingsJSON(ext.ID, `{"quality":"lossless","_secret":"hidden"}`); err != nil {
		t.Fatalf("SetExtensionSettingsJSON: %v", err)
	}
	if settingsJSON, err := GetExtensionSettingsJSON(ext.ID); err != nil || !strings.Contains(settingsJSON, "quality") {
		t.Fatalf("GetExtensionSettingsJSON = %q/%v", settingsJSON, err)
	}
	if err := SetExtensionSettingsJSON(ext.ID, `not-json`); err == nil {
		t.Fatal("expected settings JSON error")
	}

	if jsonText, err := SearchTracksWithMetadataProvidersJSON("song", 5, true); err != nil || !strings.Contains(jsonText, "search-1") {
		t.Fatalf("SearchTracksWithMetadataProvidersJSON = %q/%v", jsonText, err)
	}
	if jsonText, err := GetProviderMetadataJSON(ext.ID, "track", "track-1"); err != nil || !strings.Contains(jsonText, "Track track-1") {
		t.Fatalf("GetProviderMetadataJSON track = %q/%v", jsonText, err)
	}
	for _, resourceType := range []string{"album", "playlist", "artist"} {
		if jsonText, err := GetProviderMetadataJSON(ext.ID, resourceType, resourceType+"-1"); err != nil || jsonText == "" {
			t.Fatalf("GetProviderMetadataJSON %s = %q/%v", resourceType, jsonText, err)
		}
	}
	if _, err := GetProviderMetadataJSON("", "track", "id"); err == nil {
		t.Fatal("expected empty provider ID error")
	}
	if _, err := GetProviderMetadataJSON(ext.ID, "unsupported", "id"); err == nil {
		t.Fatal("expected unsupported provider type")
	}
	if firstNonEmptyTrimmed(" ", " value ") != "value" {
		t.Fatal("expected first trimmed value")
	}
	requestJSON := `{"use_extensions":true,"use_fallback":false,"service":"coverage-ext","source":"coverage-ext","track_name":"Song","artist_name":"Artist","album_name":"Album","output_dir":"` + escapeJSONPath(dir) + `","output_ext":".flac","quality":"LOSSLESS"}`
	if jsonText, err := DownloadWithExtensionsJSON(requestJSON); err != nil || !strings.Contains(jsonText, "coverage-ext") {
		t.Fatalf("DownloadWithExtensionsJSON = %q/%v", jsonText, err)
	}
	if _, err := DownloadWithExtensionsJSON(`not-json`); err == nil {
		t.Fatal("expected DownloadWithExtensionsJSON JSON error")
	}

	SetExtensionAuthCodeByID(ext.ID, "code")
	SetExtensionTokensByID(ext.ID, "access", "refresh", 60)
	if !IsExtensionAuthenticatedByID(ext.ID) {
		t.Fatal("expected authenticated extension")
	}
	if pending, err := GetExtensionPendingAuthJSON(ext.ID); err != nil || pending != "" {
		t.Fatalf("GetExtensionPendingAuthJSON = %q/%v", pending, err)
	}
	ClearExtensionPendingAuthByID(ext.ID)
	if all, err := GetAllPendingAuthRequestsJSON(); err != nil || all == "" {
		t.Fatalf("GetAllPendingAuthRequestsJSON = %q/%v", all, err)
	}

	ffmpegCommandsMu.Lock()
	ffmpegCommands["cmd-1"] = &FFmpegCommand{ExtensionID: ext.ID, Command: "ffmpeg -version", InputPath: "in", OutputPath: "out"}
	ffmpegCommandsMu.Unlock()
	if cmdJSON, err := GetPendingFFmpegCommandJSON("cmd-1"); err != nil || !strings.Contains(cmdJSON, "cmd-1") {
		t.Fatalf("GetPendingFFmpegCommandJSON = %q/%v", cmdJSON, err)
	}
	if all, err := GetAllPendingFFmpegCommandsJSON(); err != nil || !strings.Contains(all, "cmd-1") {
		t.Fatalf("GetAllPendingFFmpegCommandsJSON = %q/%v", all, err)
	}
	SetFFmpegCommandResultByID("cmd-1", true, "ok", "")
	ClearFFmpegCommand("cmd-1")
	if empty, err := GetPendingFFmpegCommandJSON("missing"); err != nil || empty != "" {
		t.Fatalf("missing ffmpeg = %q/%v", empty, err)
	}

	enrichedJSON, err := EnrichTrackWithExtensionJSON(ext.ID, `{"id":"track-1","name":"Old","artists":"Artist"}`)
	if err != nil || !strings.Contains(enrichedJSON, "Enriched") {
		t.Fatalf("EnrichTrackWithExtensionJSON = %q/%v", enrichedJSON, err)
	}
	if sameJSON, err := EnrichTrackWithExtensionJSON("missing", `{"name":"Old"}`); err != nil || !strings.Contains(sameJSON, "Old") {
		t.Fatalf("missing EnrichTrackWithExtensionJSON = %q/%v", sameJSON, err)
	}

	deezerClient = &DeezerClient{
		httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
			body := fakeDeezerResponse(req.URL.Path, req.URL.RawQuery)
			status := http.StatusOK
			if body == "" {
				status = http.StatusNotFound
				body = `{"error":"missing"}`
			}
			return &http.Response{StatusCode: status, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body)), Request: req}, nil
		})},
		searchCache:          map[string]*cacheEntry{},
		albumCache:           map[string]*cacheEntry{},
		artistCache:          map[string]*cacheEntry{},
		isrcCache:            map[string]string{},
		cacheCleanupInterval: time.Hour,
	}
	deezerClientOnce.Do(func() {})
	for _, item := range []struct {
		typ string
		id  string
	}{
		{"track", "101"},
		{"album", "201"},
		{"artist", "301"},
		{"playlist", "401"},
	} {
		if jsonText, err := GetDeezerMetadata(item.typ, item.id); err != nil || jsonText == "" {
			t.Fatalf("GetDeezerMetadata %s = %q/%v", item.typ, jsonText, err)
		}
	}
	if _, err := GetDeezerMetadata("bad", "1"); err == nil {
		t.Fatal("expected unsupported Deezer metadata type")
	}
	if jsonText, err := GetDeezerExtendedMetadata("101"); err != nil || !strings.Contains(jsonText, "Label") {
		t.Fatalf("GetDeezerExtendedMetadata = %q/%v", jsonText, err)
	}
	if _, err := GetDeezerExtendedMetadata(""); err == nil {
		t.Fatal("expected empty Deezer metadata ID error")
	}
	if jsonText, err := SearchDeezerByISRC("USRC17607839"); err != nil || !strings.Contains(jsonText, "deezer:101") {
		t.Fatalf("SearchDeezerByISRC = %q/%v", jsonText, err)
	}
	if jsonText, err := SearchDeezerByISRCForItemID("USRC17607839", "item-isrc"); err != nil || !strings.Contains(jsonText, "deezer:101") {
		t.Fatalf("SearchDeezerByISRCForItemID = %q/%v", jsonText, err)
	}

	customJSON, err := CustomSearchWithExtensionJSON(ext.ID, "needle", `{"filter":"tracks"}`)
	if err != nil || !strings.Contains(customJSON, "Custom needle") {
		t.Fatalf("CustomSearchWithExtensionJSON = %q/%v", customJSON, err)
	}
	if customJSON, err := CustomSearchWithExtensionJSONWithRequestID(ext.ID, "needle", `not-json`, "req-custom"); err != nil || !strings.Contains(customJSON, "custom-1") {
		t.Fatalf("CustomSearchWithExtensionJSONWithRequestID = %q/%v", customJSON, err)
	}
	if found := FindURLHandlerJSON("https://example.test/track/1"); found != ext.ID {
		t.Fatalf("FindURLHandlerJSON = %q", found)
	}
	if handledJSON, err := HandleURLWithExtensionJSON("https://example.test/track/1"); err != nil || !strings.Contains(handledJSON, "url-track") {
		t.Fatalf("HandleURLWithExtensionJSON = %q/%v", handledJSON, err)
	}
	v2Input := `{"path":"` + escapeJSONPath(filepath.Join(dir, "song.flac")) + `","uri":"content://song","name":"song.flac","mime_type":"audio/flac","size":10}`
	if postJSON, err := RunPostProcessingV2JSON(v2Input, `not-json`); err != nil || !strings.Contains(postJSON, "success") {
		t.Fatalf("RunPostProcessingV2JSON = %q/%v", postJSON, err)
	}
	if feedJSON, err := GetExtensionHomeFeedJSON(ext.ID); err != nil || !strings.Contains(feedJSON, "home-1") {
		t.Fatalf("GetExtensionHomeFeedJSON = %q/%v", feedJSON, err)
	}
	if feedJSON, err := GetExtensionHomeFeedJSONWithRequestID(ext.ID, "req-home"); err != nil || !strings.Contains(feedJSON, "home-1") {
		t.Fatalf("GetExtensionHomeFeedJSONWithRequestID = %q/%v", feedJSON, err)
	}
	CancelExtensionRequestJSON("req-home")

	storeDir := filepath.Join(dir, "store")
	if err := InitExtensionRepoJSON(storeDir); err != nil {
		t.Fatalf("InitExtensionRepoJSON: %v", err)
	}
	if err := SetRepoRegistryURLJSON("https://registry.example.com/index.json"); err != nil {
		t.Fatalf("SetRepoRegistryURLJSON: %v", err)
	}
	store := getExtensionRepo()
	store.cache = &repoRegistry{Extensions: []repoExtension{{
		ID:          "coverage-ext",
		Name:        "coverage-ext",
		Version:     "1.0.0",
		Description: "Coverage",
		Category:    CategoryMetadata,
		Tags:        []string{"metadata"},
		DownloadURL: "https://registry.example.com/coverage.spotiflac-ext",
	}}}
	store.cacheTime = time.Now()
	if registryURL, err := GetRepoRegistryURLJSON(); err != nil || registryURL == "" {
		t.Fatalf("GetRepoRegistryURLJSON = %q/%v", registryURL, err)
	}
	if storeJSON, err := GetRepoExtensionsJSON(false); err != nil || !strings.Contains(storeJSON, "coverage-ext") {
		t.Fatalf("GetRepoExtensionsJSON = %q/%v", storeJSON, err)
	}
	if storeJSON, err := SearchRepoExtensionsJSON("coverage", CategoryMetadata); err != nil || !strings.Contains(storeJSON, "coverage-ext") {
		t.Fatalf("SearchRepoExtensionsJSON = %q/%v", storeJSON, err)
	}
	if catsJSON, err := GetRepoCategoriesJSON(); err != nil || !strings.Contains(catsJSON, "metadata") {
		t.Fatalf("GetRepoCategoriesJSON = %q/%v", catsJSON, err)
	}
	if dest, err := buildRepoExtensionDestPath(
		dir,
		"coverage/ext",
		"https://registry.example.com/coverage.spotiflac-ext",
	); err != nil || !strings.HasSuffix(dest, ".spotiflac-ext") {
		t.Fatalf("buildRepoExtensionDestPath = %q/%v", dest, err)
	}
	if dest, err := buildRepoExtensionDestPath(
		dir,
		"coverage/ext",
		"https://registry.example.com/coverage.sflx",
	); err != nil || !strings.HasSuffix(dest, ".sflx") {
		t.Fatalf("buildRepoExtensionDestPath sflx = %q/%v", dest, err)
	}
	if _, err := buildRepoExtensionDestPath(
		dir,
		" ",
		"https://registry.example.com/coverage.sflx",
	); err == nil {
		t.Fatal("expected invalid extension id")
	}
	if err := ClearRepoCacheJSON(); err != nil {
		t.Fatalf("ClearRepoCacheJSON: %v", err)
	}
	if err := ClearRepoRegistryURLJSON(); err != nil {
		t.Fatalf("ClearRepoRegistryURLJSON: %v", err)
	}

	SetLibraryCoverCacheDirJSON(filepath.Join(dir, "covers"))
	libraryDir := filepath.Join(dir, "library")
	if err := os.MkdirAll(libraryDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(libraryDir, "Artist - Song.mp3"), []byte("not mp3"), 0600); err != nil {
		t.Fatal(err)
	}
	if scanJSON, err := ScanLibraryFolderJSON(libraryDir); err != nil || !strings.Contains(scanJSON, "Song") {
		t.Fatalf("ScanLibraryFolderJSON = %q/%v", scanJSON, err)
	}
	if scanJSON, err := ScanLibraryFolderIncrementalJSON(libraryDir, `[]`); err != nil || !strings.Contains(scanJSON, "Song") {
		t.Fatalf("ScanLibraryFolderIncrementalJSON = %q/%v", scanJSON, err)
	}
	snapshotPath := filepath.Join(dir, "snapshot.json")
	if err := os.WriteFile(snapshotPath, []byte(`[]`), 0600); err != nil {
		t.Fatal(err)
	}
	if scanJSON, err := ScanLibraryFolderIncrementalFromSnapshotJSON(libraryDir, snapshotPath); err != nil || !strings.Contains(scanJSON, "Song") {
		t.Fatalf("ScanLibraryFolderIncrementalFromSnapshotJSON = %q/%v", scanJSON, err)
	}
	if GetLibraryScanProgressJSON() == "" {
		t.Fatal("expected scan progress JSON")
	}
	CancelLibraryScanJSON()
	if metadataJSON, err := ReadAudioMetadataJSON(filepath.Join(libraryDir, "missing.mp3")); err != nil || metadataJSON == "" {
		t.Fatalf("ReadAudioMetadataJSON = %q/%v", metadataJSON, err)
	}
	if metadataJSON, err := ReadAudioMetadataWithHintAndCoverCacheKeyJSON(filepath.Join(libraryDir, "missing.mp3"), "Missing", "key"); err != nil || metadataJSON == "" {
		t.Fatalf("ReadAudioMetadataWithHintAndCoverCacheKeyJSON = %q/%v", metadataJSON, err)
	}
}
