package gobackend

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dop251/goja"
)

func TestExtensionRuntimeAuthAndPolyfills(t *testing.T) {
	vm := goja.New()
	runtime := &extensionRuntime{
		extensionID: "auth-ext",
		manifest: &ExtensionManifest{
			Name:        "auth-ext",
			Description: "Auth extension",
			Version:     "1.0.0",
			Permissions: ExtensionPermissions{
				Network: []string{"auth.example.com", "token.example.com", "api.example.com"},
			},
		},
		settings: map[string]any{},
		httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
			switch req.URL.Host {
			case "token.example.com":
				return &http.Response{
					StatusCode: 200,
					Header:     make(http.Header),
					Body:       io.NopCloser(strings.NewReader(`{"access_token":"access","refresh_token":"refresh","expires_in":3600}`)),
					Request:    req,
				}, nil
			case "api.example.com":
				return &http.Response{
					StatusCode: 200,
					Header:     http.Header{"X-Test": []string{"yes"}},
					Body:       io.NopCloser(strings.NewReader(`{"ok":true,"items":[1,2]}`)),
					Request:    req,
				}, nil
			default:
				return &http.Response{StatusCode: 404, Body: io.NopCloser(strings.NewReader(`{}`)), Request: req}, nil
			}
		})},
		vm: vm,
	}

	if err := validateExtensionAuthURL("https://user:pass@auth.example.com/login"); err == nil {
		t.Fatal("expected embedded credential error")
	}
	if err := validateExtensionAuthURL("http://auth.example.com/login"); err == nil {
		t.Fatal("expected non-https auth URL error")
	}
	if got := summarizeURLForLog("https://auth.example.com/login?token=secret"); got != "https://auth.example.com/login" {
		t.Fatalf("summary = %q", got)
	}

	openResult := runtime.authOpenUrl(goja.FunctionCall{Arguments: []goja.Value{
		vm.ToValue("https://auth.example.com/login"),
		vm.ToValue("app://callback"),
	}}).Export().(map[string]any)
	if openResult["success"] != true {
		t.Fatalf("authOpenUrl = %#v", openResult)
	}
	if pending := GetPendingAuthRequest("auth-ext"); pending == nil || pending.AuthURL == "" {
		t.Fatalf("pending auth = %#v", pending)
	}
	if code := runtime.authGetCode(goja.FunctionCall{}); !goja.IsUndefined(code) {
		t.Fatalf("expected undefined code, got %v", code)
	}
	if ok := runtime.authSetCode(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue(map[string]any{"code": "abc", "access_token": "access", "refresh_token": "refresh", "expires_in": float64(60)})}}); !ok.ToBoolean() {
		t.Fatal("authSetCode returned false")
	}
	if code := runtime.authGetCode(goja.FunctionCall{}).String(); code != "abc" {
		t.Fatalf("code = %q", code)
	}
	if !runtime.authIsAuthenticated(goja.FunctionCall{}).ToBoolean() {
		t.Fatal("expected authenticated runtime")
	}
	tokens := runtime.authGetTokens(goja.FunctionCall{}).Export().(map[string]any)
	if tokens["access_token"] != "access" {
		t.Fatalf("tokens = %#v", tokens)
	}

	pkce := runtime.authGeneratePKCE(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue(float64(50))}}).Export().(map[string]any)
	if pkce["method"] != "S256" || pkce["verifier"] == "" || pkce["challenge"] == "" {
		t.Fatalf("pkce = %#v", pkce)
	}
	if current := runtime.authGetPKCE(goja.FunctionCall{}).Export().(map[string]any); current["verifier"] == "" {
		t.Fatalf("current pkce = %#v", current)
	}
	oauthConfig := map[string]any{
		"authUrl":     "https://auth.example.com/oauth",
		"clientId":    "client",
		"redirectUri": "app://callback",
		"scope":       "read",
		"extraParams": map[string]any{"prompt": "login"},
	}
	oauth := runtime.authStartOAuthWithPKCE(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue(oauthConfig)}}).Export().(map[string]any)
	if oauth["success"] != true || !strings.Contains(oauth["authUrl"].(string), "code_challenge") {
		t.Fatalf("oauth = %#v", oauth)
	}
	tokenConfig := map[string]any{
		"tokenUrl":    "https://token.example.com/token",
		"clientId":    "client",
		"redirectUri": "app://callback",
		"code":        "abc",
	}
	token := runtime.authExchangeCodeWithPKCE(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue(tokenConfig)}}).Export().(map[string]any)
	if token["success"] != true || token["access_token"] != "access" {
		t.Fatalf("token = %#v", token)
	}

	runtime.registerTextEncoderDecoder(vm)
	runtime.registerURLClass(vm)
	runtime.registerJSONGlobal(vm)
	vm.Set("fetch", func(call goja.FunctionCall) goja.Value {
		return runtime.fetchPolyfill(call)
	})
	vm.Set("atob", func(call goja.FunctionCall) goja.Value {
		return runtime.atobPolyfill(call)
	})
	vm.Set("btoa", func(call goja.FunctionCall) goja.Value {
		return runtime.btoaPolyfill(call)
	})

	value, err := vm.RunString(`
		var encoded = btoa("hello");
		var decoded = atob(encoded);
		var te = new TextEncoder();
		var bytes = te.encode("hi");
		var into = te.encodeInto("hi", []);
		var td = new TextDecoder();
		var text = td.decode(bytes);
		var url = new URL("/path?a=1&a=2#frag", "https://api.example.com/base");
		var params = new URLSearchParams("?x=1");
		params.append("x", "2");
		params.set("y", "3");
		var response = fetch("https://api.example.com/data", {method: "POST", body: {q: "x"}, headers: {"X-Client": "test"}});
		JSON.stringify({
			encoded: encoded,
			decoded: decoded,
			text: text,
			read: into.read,
			host: url.hostname,
			first: url.searchParams.get("a"),
			all: url.searchParams.getAll("a").length,
			params: params.toString(),
			ok: response.ok,
			status: response.status,
			jsonOk: response.json().ok,
			bufferLen: response.arrayBuffer().length
		});
	`)
	if err != nil {
		t.Fatalf("polyfill script: %v", err)
	}
	var result map[string]any
	if err := json.Unmarshal([]byte(value.String()), &result); err != nil {
		t.Fatalf("decode polyfill result: %v", err)
	}
	if result["decoded"] != "hello" || result["host"] != "api.example.com" || result["ok"] != true {
		t.Fatalf("polyfill result = %#v", result)
	}

	blocked := runtime.fetchPolyfill(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("https://blocked.example.com")}}).ToObject(vm)
	if blocked.Get("ok").ToBoolean() {
		t.Fatal("expected blocked fetch")
	}
	runtime.authClear(goja.FunctionCall{})
	if runtime.authIsAuthenticated(goja.FunctionCall{}).ToBoolean() {
		t.Fatal("expected auth cleared")
	}
}

type failingBodyReader struct {
	data []byte
	sent bool
}

func (f *failingBodyReader) Read(p []byte) (int, error) {
	if !f.sent {
		f.sent = true
		n := copy(p, f.data)
		return n, nil
	}
	return 0, fmt.Errorf("connection reset")
}

func newFileDownloadTestRuntime(t *testing.T, transport roundTripFunc) *extensionRuntime {
	t.Helper()
	return &extensionRuntime{
		extensionID: "dl-ext",
		manifest: &ExtensionManifest{
			Name:    "dl-ext",
			Version: "1.0.0",
			Permissions: ExtensionPermissions{
				File:    true,
				Network: []string{"cdn.example.com"},
			},
		},
		dataDir:    t.TempDir(),
		vm:         goja.New(),
		httpClient: &http.Client{Transport: transport},
	}
}

func TestFileDownloadStagesAndPromotes(t *testing.T) {
	runtime := newFileDownloadTestRuntime(t, func(req *http.Request) (*http.Response, error) {
		return &http.Response{
			StatusCode:    200,
			Header:        make(http.Header),
			Body:          io.NopCloser(strings.NewReader("audio-bytes")),
			ContentLength: int64(len("audio-bytes")),
			Request:       req,
		}, nil
	})

	result := runtime.fileDownload(goja.FunctionCall{Arguments: []goja.Value{
		runtime.vm.ToValue("https://cdn.example.com/track.flac"),
		runtime.vm.ToValue("out/track.flac"),
	}}).Export().(map[string]any)
	if result["success"] != true {
		t.Fatalf("download result = %#v", result)
	}

	finalPath := filepath.Join(runtime.dataDir, "out", "track.flac")
	data, err := os.ReadFile(finalPath)
	if err != nil || string(data) != "audio-bytes" {
		t.Fatalf("final file = %q/%v", data, err)
	}
	if _, err := os.Stat(stagedDownloadPath(finalPath)); !os.IsNotExist(err) {
		t.Fatalf("staged file left behind: %v", err)
	}
}

func TestFileDownloadFailureLeavesNoFinalFile(t *testing.T) {
	runtime := newFileDownloadTestRuntime(t, func(req *http.Request) (*http.Response, error) {
		return &http.Response{
			StatusCode:    200,
			Header:        make(http.Header),
			Body:          io.NopCloser(&failingBodyReader{data: []byte("partial-aud")}),
			ContentLength: 1 << 20,
			Request:       req,
		}, nil
	})

	result := runtime.fileDownload(goja.FunctionCall{Arguments: []goja.Value{
		runtime.vm.ToValue("https://cdn.example.com/track.flac"),
		runtime.vm.ToValue("out/track.flac"),
	}}).Export().(map[string]any)
	if result["success"] != false {
		t.Fatalf("expected failed download, got %#v", result)
	}

	finalPath := filepath.Join(runtime.dataDir, "out", "track.flac")
	if _, err := os.Stat(finalPath); !os.IsNotExist(err) {
		t.Fatalf("partial download visible at final path: %v", err)
	}
	if _, err := os.Stat(stagedDownloadPath(finalPath)); !os.IsNotExist(err) {
		t.Fatalf("staged file left behind: %v", err)
	}
}

func TestFileDownloadDoesNotResumeMidBodyCutByDefault(t *testing.T) {
	const full = "hello-world!"
	var attempts int
	runtime := newFileDownloadTestRuntime(t, func(req *http.Request) (*http.Response, error) {
		attempts++
		h := make(http.Header)
		h.Set("ETag", `"v1"`)
		return &http.Response{
			StatusCode:    200,
			Header:        h,
			Body:          io.NopCloser(&failingBodyReader{data: []byte(full[:6])}),
			ContentLength: int64(len(full)),
			Request:       req,
		}, nil
	})

	result := runtime.fileDownload(goja.FunctionCall{Arguments: []goja.Value{
		runtime.vm.ToValue("https://cdn.example.com/track.flac"),
		runtime.vm.ToValue("out/track.flac"),
	}}).Export().(map[string]any)
	if result["success"] != false {
		t.Fatalf("expected failed download, got %#v", result)
	}
	if attempts != 1 {
		t.Fatalf("attempts = %d, want no automatic resume", attempts)
	}
	finalPath := filepath.Join(runtime.dataDir, "out", "track.flac")
	if _, err := os.Stat(finalPath); !os.IsNotExist(err) {
		t.Fatalf("partial download visible at final path: %v", err)
	}
	if _, err := os.Stat(stagedDownloadPath(finalPath)); !os.IsNotExist(err) {
		t.Fatalf("staged file left behind: %v", err)
	}
}

func TestFileDownloadResumesAfterMidBodyCutWhenEnabled(t *testing.T) {
	const full = "hello-world!"
	var attempts int
	var resumeRange, resumeIfRange string
	runtime := newFileDownloadTestRuntime(t, func(req *http.Request) (*http.Response, error) {
		attempts++
		if attempts == 1 {
			h := make(http.Header)
			h.Set("ETag", `"v1"`)
			return &http.Response{
				StatusCode:    200,
				Header:        h,
				Body:          io.NopCloser(&failingBodyReader{data: []byte(full[:6])}),
				ContentLength: int64(len(full)),
				Request:       req,
			}, nil
		}
		resumeRange = req.Header.Get("Range")
		resumeIfRange = req.Header.Get("If-Range")
		h := make(http.Header)
		h.Set("Content-Range", fmt.Sprintf("bytes 6-%d/%d", len(full)-1, len(full)))
		return &http.Response{
			StatusCode:    206,
			Header:        h,
			Body:          io.NopCloser(strings.NewReader(full[6:])),
			ContentLength: int64(len(full) - 6),
			Request:       req,
		}, nil
	})

	result := runtime.fileDownload(goja.FunctionCall{Arguments: []goja.Value{
		runtime.vm.ToValue("https://cdn.example.com/track.flac"),
		runtime.vm.ToValue("out/track.flac"),
		runtime.vm.ToValue(map[string]any{"resume": true}),
	}}).Export().(map[string]any)
	if result["success"] != true {
		t.Fatalf("download result = %#v", result)
	}
	if attempts != 2 || resumeRange != "bytes=6-" || resumeIfRange != `"v1"` {
		t.Fatalf("attempts=%d range=%q if-range=%q", attempts, resumeRange, resumeIfRange)
	}
	data, err := os.ReadFile(filepath.Join(runtime.dataDir, "out", "track.flac"))
	if err != nil || string(data) != full {
		t.Fatalf("final file = %q/%v", data, err)
	}
}

func TestFileDownloadResumeRestartsWhenRangeIgnored(t *testing.T) {
	const full = "hello-world!"
	var attempts int
	runtime := newFileDownloadTestRuntime(t, func(req *http.Request) (*http.Response, error) {
		attempts++
		h := make(http.Header)
		h.Set("ETag", `"v1"`)
		if attempts == 1 {
			return &http.Response{
				StatusCode:    200,
				Header:        h,
				Body:          io.NopCloser(&failingBodyReader{data: []byte(full[:6])}),
				ContentLength: int64(len(full)),
				Request:       req,
			}, nil
		}
		// Server ignores the Range header and replays the full body.
		return &http.Response{
			StatusCode:    200,
			Header:        h,
			Body:          io.NopCloser(strings.NewReader(full)),
			ContentLength: int64(len(full)),
			Request:       req,
		}, nil
	})

	result := runtime.fileDownload(goja.FunctionCall{Arguments: []goja.Value{
		runtime.vm.ToValue("https://cdn.example.com/track.flac"),
		runtime.vm.ToValue("out/track.flac"),
		runtime.vm.ToValue(map[string]any{"resume": true}),
	}}).Export().(map[string]any)
	if result["success"] != true {
		t.Fatalf("download result = %#v", result)
	}
	if attempts != 2 {
		t.Fatalf("attempts = %d, want 2", attempts)
	}
	data, err := os.ReadFile(filepath.Join(runtime.dataDir, "out", "track.flac"))
	if err != nil || string(data) != full {
		t.Fatalf("final file = %q/%v", data, err)
	}
}

func TestResetDownloadCancelDropsStaleFlag(t *testing.T) {
	const itemID = "reset-cancel-item"

	// A cancel issued while nothing is downloading pre-registers a flag that
	// the next attempt would consume and abort; reset must drop it.
	cancelDownload(itemID)
	if !isDownloadCancelled(itemID) {
		t.Fatal("expected pre-registered cancel flag")
	}
	resetDownloadCancel(itemID)
	if isDownloadCancelled(itemID) {
		t.Fatal("expected stale cancel flag to be dropped")
	}

	// A cancel attached to an active download must survive reset.
	ctx := initDownloadCancel(itemID)
	cancelDownload(itemID)
	resetDownloadCancel(itemID)
	if !isDownloadCancelled(itemID) {
		t.Fatal("expected active cancel to survive reset")
	}
	select {
	case <-ctx.Done():
	default:
		t.Fatal("expected cancelled context")
	}
	clearDownloadCancel(itemID)
}

func TestParseExtensionTrackValueExplicit(t *testing.T) {
	vm := goja.New()

	value, err := vm.RunString(`({name: "Song", explicit: true})`)
	if err != nil {
		t.Fatalf("RunString: %v", err)
	}
	if track := parseExtensionTrackValue(vm, value); !track.Explicit {
		t.Fatalf("expected explicit track, got %#v", track)
	}

	value, err = vm.RunString(`({name: "Song", isExplicit: true})`)
	if err != nil {
		t.Fatalf("RunString: %v", err)
	}
	if track := parseExtensionTrackValue(vm, value); !track.Explicit {
		t.Fatalf("expected explicit track via isExplicit, got %#v", track)
	}

	value, err = vm.RunString(`({name: "Song"})`)
	if err != nil {
		t.Fatalf("RunString: %v", err)
	}
	if track := parseExtensionTrackValue(vm, value); track.Explicit {
		t.Fatalf("expected clean track, got %#v", track)
	}
}

func TestDeezerTrackIsExplicit(t *testing.T) {
	if deezerTrackIsExplicit(deezerTrack{}) {
		t.Fatal("expected clean track by default")
	}
	if !deezerTrackIsExplicit(deezerTrack{ExplicitLyrics: true}) {
		t.Fatal("expected explicit via explicit_lyrics")
	}
	if !deezerTrackIsExplicit(deezerTrack{ExplicitContentLyrics: 1}) {
		t.Fatal("expected explicit via explicit_content_lyrics == 1")
	}
	if deezerTrackIsExplicit(deezerTrack{ExplicitContentLyrics: 2}) {
		t.Fatal("expected unknown (2) to be treated as clean")
	}
}

func TestExtensionStoreDiskCacheSurvivesRestart(t *testing.T) {
	dir := t.TempDir()
	registryURL := "https://registry.example.com/registry.json"
	store := &extensionRepo{
		registryURL: registryURL,
		cacheDir:    dir,
		cacheTTL:    time.Hour,
		cache: &repoRegistry{
			Version:    1,
			Extensions: []repoExtension{{ID: "ext", Name: "ext", Version: "1.0.0"}},
		},
		cacheTime: time.Now(),
	}
	store.saveDiskCache()

	// Simulates an app restart: a fresh store loads the disk cache, then the
	// Dart layer re-applies the same registry URL.
	restarted := &extensionRepo{cacheDir: dir, cacheTTL: time.Hour}
	restarted.loadDiskCache()
	if restarted.getRegistryURL() != registryURL {
		t.Fatalf("registry URL after restart = %q", restarted.getRegistryURL())
	}
	restarted.setRegistryURL(registryURL)
	if restarted.cache == nil || len(restarted.cache.Extensions) != 1 {
		t.Fatalf("expected cache to survive re-applying the same registry URL, got %#v", restarted.cache)
	}

	restarted.setRegistryURL("https://other.example.com/registry.json")
	if restarted.cache != nil {
		t.Fatal("expected cache reset after registry URL change")
	}
}

func TestParseRegistryBody(t *testing.T) {
	registry, err := parseRegistryBody([]byte(`{"version":1,"extensions":[{"id":"ext","name":"ext","version":"1.0.0"}]}`))
	if err != nil || len(registry.Extensions) != 1 {
		t.Fatalf("parseRegistryBody = %#v/%v", registry, err)
	}

	if _, err := parseRegistryBody([]byte("<!DOCTYPE html><html></html>")); err == nil || !strings.Contains(err.Error(), "web page") {
		t.Fatalf("expected web page error, got %v", err)
	}

	if _, err := parseRegistryBody([]byte("not json")); err == nil || !strings.Contains(err.Error(), "failed to parse registry") {
		t.Fatalf("expected parse error, got %v", err)
	}
}

func TestExtensionStoreSettingsAndRuntimeStorage(t *testing.T) {
	dir := t.TempDir()
	store := &extensionRepo{
		registryURL: "https://registry.example.com/registry.json",
		cacheDir:    dir,
		cacheTTL:    time.Hour,
		cache: &repoRegistry{
			Version:   1,
			UpdatedAt: "2026-05-04",
			Extensions: []repoExtension{
				{
					ID:               "coverage-ext",
					Name:             "coverage-ext",
					DisplayNameAlt:   "Coverage Extension",
					Version:          "2.0.0",
					Description:      "Metadata and lyrics provider",
					DownloadURLAlt:   "https://registry.example.com/coverage.spotiflac-ext",
					IconURLAlt:       "https://registry.example.com/icon.png",
					Category:         CategoryMetadata,
					Tags:             []string{"metadata", "lyrics"},
					Downloads:        10,
					UpdatedAt:        "2026-05-04",
					MinAppVersionAlt: "4.5.0",
				},
				{
					ID:          "utility-ext",
					Name:        "utility-ext",
					Version:     "1.0.0",
					Description: "Utility",
					DownloadURL: "https://registry.example.com/utility.spotiflac-ext",
					Category:    CategoryUtility,
					UpdatedAt:   "2026-05-04",
				},
			},
		},
		cacheTime: time.Now(),
	}
	store.saveDiskCache()
	loadedStore := &extensionRepo{cacheDir: dir}
	loadedStore.loadDiskCache()
	if loadedStore.cache == nil || len(loadedStore.cache.Extensions) != 2 {
		t.Fatalf("loaded cache = %#v", loadedStore.cache)
	}
	if got := store.getRegistryURL(); got != "https://registry.example.com/registry.json" {
		t.Fatalf("registry URL = %q", got)
	}
	store.setRegistryURL("https://registry.example.com/new.json")
	if store.cache != nil {
		t.Fatal("expected cache reset after registry URL change")
	}
	store.cache = loadedStore.cache
	store.cacheTime = time.Now()

	manager := getExtensionManager()
	manager.mu.Lock()
	if manager.extensions == nil {
		manager.extensions = map[string]*loadedExtension{}
	}
	manager.extensions["coverage-ext"] = &loadedExtension{
		ID: "coverage-ext",
		Manifest: &ExtensionManifest{
			Name:        "coverage-ext",
			DisplayName: "Coverage Extension",
			Version:     "1.0.0",
			Description: "Installed",
			Types:       []ExtensionType{ExtensionTypeMetadataProvider},
		},
		Enabled: true,
	}
	manager.mu.Unlock()
	defer func() {
		manager.mu.Lock()
		delete(manager.extensions, "coverage-ext")
		manager.mu.Unlock()
	}()

	extensions, err := store.getExtensionsWithStatus(false)
	if err != nil {
		t.Fatalf("getExtensionsWithStatus: %v", err)
	}
	if len(extensions) != 2 || !extensions[0].IsInstalled || !extensions[0].HasUpdate {
		t.Fatalf("extensions = %#v", extensions)
	}
	found, err := store.searchExtensions("lyrics", CategoryMetadata)
	if err != nil || len(found) != 1 || found[0].ID != "coverage-ext" {
		t.Fatalf("search = %#v/%v", found, err)
	}
	all, err := store.searchExtensions("", "")
	if err != nil || len(all) != 2 {
		t.Fatalf("all search = %#v/%v", all, err)
	}
	if cats := store.getCategories(); len(cats) != 5 {
		t.Fatalf("categories = %#v", cats)
	}
	if err := requireHTTPSURL("http://example.com", "registry"); err == nil {
		t.Fatal("expected HTTPS validation error")
	}
	if _, err := resolveRegistryURL(""); err == nil {
		t.Fatal("expected empty registry URL error")
	}
	if resolved, err := resolveRegistryURL("http://github.com/owner/repo"); err != nil || !strings.Contains(resolved, "raw.githubusercontent.com/owner/repo") {
		t.Fatalf("resolved registry = %q/%v", resolved, err)
	}
	store.clearCache()
	if store.cache != nil {
		t.Fatal("expected cleared store cache")
	}

	settingsStore := &ExtensionSettingsStore{settings: map[string]map[string]any{}}
	if err := settingsStore.SetDataDir(filepath.Join(dir, "settings")); err != nil {
		t.Fatalf("SetDataDir: %v", err)
	}
	if err := settingsStore.Set("ext", "quality", "lossless"); err != nil {
		t.Fatalf("settings Set: %v", err)
	}
	if value, err := settingsStore.Get("ext", "quality"); err != nil || value != "lossless" {
		t.Fatalf("settings Get = %#v/%v", value, err)
	}
	if _, err := settingsStore.Get("ext", "missing"); err == nil {
		t.Fatal("expected missing setting error")
	}
	if err := settingsStore.SetAll("ext", map[string]any{"a": float64(1), "_secret": "hidden"}); err != nil {
		t.Fatalf("settings SetAll: %v", err)
	}
	if all := settingsStore.GetAll("ext"); all["a"] != float64(1) {
		t.Fatalf("settings all = %#v", all)
	}
	if err := settingsStore.Remove("ext", "a"); err != nil {
		t.Fatalf("settings Remove: %v", err)
	}
	if err := settingsStore.RemoveAll("ext"); err != nil {
		t.Fatalf("settings RemoveAll: %v", err)
	}
	if jsonText, err := settingsStore.GetAllExtensionSettingsJSON(); err != nil || jsonText == "" {
		t.Fatalf("settings JSON = %q/%v", jsonText, err)
	}
	reloaded := &ExtensionSettingsStore{settings: map[string]map[string]any{}}
	if err := reloaded.SetDataDir(settingsStore.dataDir); err != nil {
		t.Fatalf("reload settings: %v", err)
	}

	vm := goja.New()
	runtime := &extensionRuntime{
		extensionID: "storage-ext",
		dataDir:     filepath.Join(dir, "runtime"),
		vm:          vm,
	}
	if err := os.MkdirAll(runtime.dataDir, 0755); err != nil {
		t.Fatal(err)
	}
	if got := runtime.storageGet(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("missing"), vm.ToValue("fallback")}}).String(); got != "fallback" {
		t.Fatalf("storage fallback = %q", got)
	}
	if ok := runtime.storageSet(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("key"), vm.ToValue(map[string]any{"nested": "value"})}}); !ok.ToBoolean() {
		t.Fatal("storageSet false")
	}
	if ok := runtime.storageSet(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("key"), vm.ToValue(map[string]any{"nested": "value"})}}); !ok.ToBoolean() {
		t.Fatal("storageSet equal false")
	}
	if err := runtime.flushStorageNow(); err != nil {
		t.Fatalf("flushStorageNow: %v", err)
	}
	if ok := runtime.storageRemove(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("key")}}); !ok.ToBoolean() {
		t.Fatal("storageRemove false")
	}
	runtime.closeStorageFlusher()
	if ok := runtime.storageSet(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("after_close"), vm.ToValue("x")}}); ok.ToBoolean() {
		t.Fatal("expected storageSet false after close")
	}

	credRuntime := &extensionRuntime{
		extensionID: "cred-ext",
		dataDir:     filepath.Join(dir, "creds"),
		vm:          vm,
	}
	if err := os.MkdirAll(credRuntime.dataDir, 0755); err != nil {
		t.Fatal(err)
	}
	if result := credRuntime.credentialsStore(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("token"), vm.ToValue("secret")}}).Export().(map[string]any); result["success"] != true {
		t.Fatalf("credentialsStore = %#v", result)
	}
	if got := credRuntime.credentialsGet(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("token")}}).String(); got != "secret" {
		t.Fatalf("credential = %q", got)
	}
	if !credRuntime.credentialsHas(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("token")}}).ToBoolean() {
		t.Fatal("expected credential")
	}
	if ok := credRuntime.credentialsRemove(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("token")}}); !ok.ToBoolean() {
		t.Fatal("credentialsRemove false")
	}
	if credRuntime.credentialsHas(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("token")}}).ToBoolean() {
		t.Fatal("expected credential removed")
	}
	key, err := credRuntime.getEncryptionKey()
	if err != nil {
		t.Fatalf("getEncryptionKey: %v", err)
	}
	encrypted, err := encryptAES([]byte("plain"), key)
	if err != nil {
		t.Fatalf("encryptAES: %v", err)
	}
	decrypted, err := decryptAES(encrypted, key)
	if err != nil || string(decrypted) != "plain" {
		t.Fatalf("decryptAES = %q/%v", decrypted, err)
	}
	if _, err := decryptAES([]byte("short"), key); err == nil {
		t.Fatal("expected short ciphertext error")
	}
}

func TestExtensionRuntimeHTTPMatchingAndMetadataHelpers(t *testing.T) {
	vm := goja.New()
	jar, _ := newSimpleCookieJar()
	runtime := &extensionRuntime{
		extensionID: "http-ext",
		manifest: &ExtensionManifest{
			Name:        "http-ext",
			Description: "HTTP extension",
			Version:     "1.0.0",
			Permissions: ExtensionPermissions{
				Network: []string{"api.example.com"},
			},
		},
		vm:        vm,
		cookieJar: jar,
		httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
			var body []byte
			if req.Body != nil {
				body, _ = io.ReadAll(req.Body)
			}
			header := make(http.Header)
			header.Set("X-Method", req.Method)
			if req.URL.Path == "/huge" {
				return &http.Response{StatusCode: 200, Header: header, Body: io.NopCloser(io.LimitReader(strings.NewReader(strings.Repeat("x", maxExtensionHTTPResponseBytes+2)), maxExtensionHTTPResponseBytes+2)), Request: req}, nil
			}
			return &http.Response{
				StatusCode: 201,
				Header:     header,
				Body:       io.NopCloser(strings.NewReader(req.Method + ":" + string(body))),
				Request:    req,
			}, nil
		})},
	}

	if err := runtime.validateDomain("https://api.example.com/path"); err != nil {
		t.Fatalf("validateDomain allowed: %v", err)
	}
	for _, rawURL := range []string{"notaurl", "http://api.example.com", "https://user:pass@api.example.com", "https://127.0.0.1/x", "https://blocked.example.com/x"} {
		if err := runtime.validateDomain(rawURL); err == nil {
			t.Fatalf("expected domain validation error for %s", rawURL)
		}
	}
	if got := runtime.httpGet(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("https://api.example.com/get"), vm.ToValue(map[string]any{"X-Test": "yes"})}}).Export().(map[string]any); got["status"] != 201 || !strings.Contains(got["body"].(string), "GET") {
		t.Fatalf("httpGet = %#v", got)
	}
	if got := runtime.httpPost(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("https://api.example.com/post"), vm.ToValue(map[string]any{"a": "b"})}}).Export().(map[string]any); !strings.Contains(got["body"].(string), "POST") {
		t.Fatalf("httpPost = %#v", got)
	}
	requestOptions := map[string]any{"method": "patch", "body": []any{"x"}, "headers": map[string]any{"X-Req": "1"}}
	if got := runtime.httpRequest(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("https://api.example.com/request"), vm.ToValue(requestOptions)}}).Export().(map[string]any); !strings.Contains(got["body"].(string), "PATCH") {
		t.Fatalf("httpRequest = %#v", got)
	}
	for _, method := range []struct {
		name string
		call func(goja.FunctionCall) goja.Value
		args []goja.Value
	}{
		{name: "PUT", call: runtime.httpPut, args: []goja.Value{vm.ToValue("https://api.example.com/put"), vm.ToValue("body")}},
		{name: "DELETE", call: runtime.httpDelete, args: []goja.Value{vm.ToValue("https://api.example.com/delete"), vm.ToValue(map[string]any{"X-Delete": "1"})}},
		{name: "PATCH", call: runtime.httpPatch, args: []goja.Value{vm.ToValue("https://api.example.com/patch"), vm.ToValue(map[string]any{"p": "q"})}},
	} {
		if got := method.call(goja.FunctionCall{Arguments: method.args}).Export().(map[string]any); !strings.Contains(got["body"].(string), method.name) {
			t.Fatalf("%s = %#v", method.name, got)
		}
	}
	if got := runtime.httpGet(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("https://api.example.com/huge")}}).Export().(map[string]any); !strings.Contains(got["error"].(string), "exceeds") {
		t.Fatalf("huge response = %#v", got)
	}
	if !runtime.httpClearCookies(goja.FunctionCall{}).ToBoolean() {
		t.Fatal("expected cookies cleared")
	}

	if runtime.matchingCompareStrings(goja.FunctionCall{}).ToFloat() != 0 {
		t.Fatal("missing string compare args should be zero")
	}
	if runtime.matchingCompareStrings(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("Song"), vm.ToValue("song")}}).ToFloat() != 1 {
		t.Fatal("expected exact string similarity")
	}
	if runtime.matchingCompareDuration(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue(180000), vm.ToValue(182000)}}).ToBoolean() != true {
		t.Fatal("expected duration match")
	}
	if runtime.matchingNormalizeString(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("Song (Remastered) feat. Guest!")}}).String() != "song" {
		t.Fatalf("normalized = %q", runtime.matchingNormalizeString(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("Song (Remastered) feat. Guest!")}}).String())
	}

	if formatMusicBrainzGenre([]musicBrainzTag{{Count: 1, Name: "rock"}, {Count: 5, Name: "electronic"}, {Count: 10, Name: "rock"}}) != "Electronic" {
		t.Fatal("unexpected genre selection")
	}
	credits := []musicBrainzArtistCredit{{Name: "A", JoinPhrase: " & "}, {Name: "B"}}
	if formatMusicBrainzArtistCredit(credits) != "A & B" {
		t.Fatal("artist credit format mismatch")
	}
	releases := []musicBrainzRelease{
		{Title: "Other", ArtistCredit: []musicBrainzArtistCredit{{Name: "Fallback"}}},
		{Title: "Album", ArtistCredit: credits},
	}
	if selectMusicBrainzAlbumArtist(releases, "Album") != "A & B" || selectMusicBrainzAlbumArtist(releases, "") != "Fallback" {
		t.Fatal("album artist selection mismatch")
	}
}

func TestExtensionRuntimeFileAPIs(t *testing.T) {
	vm := goja.New()
	dir := t.TempDir()
	SetAllowedDownloadDirs(nil)
	defer SetAllowedDownloadDirs(nil)

	fileBody := "chunk"
	runtime := &extensionRuntime{
		extensionID: "file-ext",
		manifest: &ExtensionManifest{
			Name:        "file-ext",
			Description: "File extension",
			Version:     "1.0.0",
			Permissions: ExtensionPermissions{
				File:    true,
				Network: []string{"files.example.com"},
			},
		},
		dataDir: dir,
		vm:      vm,
		httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
			if req.Header.Get("Range") == "" {
				body := "downloaded"
				return &http.Response{
					StatusCode:    200,
					Header:        make(http.Header),
					Body:          io.NopCloser(strings.NewReader(body)),
					ContentLength: int64(len(body)),
					Request:       req,
				}, nil
			}
			rangeHeader := req.Header.Get("Range")
			start, end := 0, len(fileBody)-1
			if _, err := fmt.Sscanf(rangeHeader, "bytes=%d-%d", &start, &end); err != nil {
				start, end = 0, 1
			}
			if start < 0 {
				start = 0
			}
			if end >= len(fileBody) {
				end = len(fileBody) - 1
			}
			if start > len(fileBody) {
				start = len(fileBody)
			}
			body := fileBody[start : end+1]
			header := http.Header{"Content-Range": []string{fmt.Sprintf("bytes %d-%d/%d", start, end, len(fileBody))}}
			return &http.Response{StatusCode: 206, Header: header, Body: io.NopCloser(strings.NewReader(body)), Request: req}, nil
		})},
	}
	runtime.downloadClient = runtime.httpClient

	if _, err := (&extensionRuntime{manifest: &ExtensionManifest{}}).validatePath("x"); err == nil {
		t.Fatal("expected file permission error")
	}
	if _, err := runtime.validatePath("../escape.txt"); err == nil {
		t.Fatal("expected sandbox escape error")
	}
	AddAllowedDownloadDir(dir)
	absolutePath := filepath.Join(dir, "allowed.txt")
	if got, err := runtime.validatePath(absolutePath); err != nil || got != absolutePath {
		t.Fatalf("absolute validatePath = %q/%v", got, err)
	}

	write := runtime.fileWrite(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("nested/a.txt"), vm.ToValue("hello")}}).Export().(map[string]any)
	if write["success"] != true {
		t.Fatalf("fileWrite = %#v", write)
	}
	if !runtime.fileExists(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("nested/a.txt")}}).ToBoolean() {
		t.Fatal("expected written file to exist")
	}
	read := runtime.fileRead(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("nested/a.txt")}}).Export().(map[string]any)
	if read["data"] != "hello" {
		t.Fatalf("fileRead = %#v", read)
	}

	writeBytes := runtime.fileWriteBytes(goja.FunctionCall{Arguments: []goja.Value{
		vm.ToValue("nested/bytes.bin"),
		vm.ToValue("4869"),
		vm.ToValue(map[string]any{"encoding": "hex", "truncate": true}),
	}}).Export().(map[string]any)
	if writeBytes["success"] != true {
		t.Fatalf("fileWriteBytes = %#v", writeBytes)
	}
	appendBytes := runtime.fileWriteBytes(goja.FunctionCall{Arguments: []goja.Value{
		vm.ToValue("nested/bytes.bin"),
		vm.ToValue([]any{float64('!')}),
		vm.ToValue(map[string]any{"append": true}),
	}}).Export().(map[string]any)
	if appendBytes["success"] != true {
		t.Fatalf("append fileWriteBytes = %#v", appendBytes)
	}
	readBytes := runtime.fileReadBytes(goja.FunctionCall{Arguments: []goja.Value{
		vm.ToValue("nested/bytes.bin"),
		vm.ToValue(map[string]any{"encoding": "text", "offset": float64(1), "length": float64(2)}),
	}}).Export().(map[string]any)
	if readBytes["data"] != "i!" || readBytes["bytes_read"] != 2 {
		t.Fatalf("fileReadBytes = %#v", readBytes)
	}
	if bad := runtime.fileWriteBytes(goja.FunctionCall{Arguments: []goja.Value{
		vm.ToValue("nested/bad.bin"),
		vm.ToValue("x"),
		vm.ToValue(map[string]any{"append": true, "offset": float64(1)}),
	}}).Export().(map[string]any); bad["success"] != false {
		t.Fatalf("expected append+offset failure, got %#v", bad)
	}
	if bad := runtime.fileReadBytes(goja.FunctionCall{Arguments: []goja.Value{
		vm.ToValue("nested/bytes.bin"),
		vm.ToValue(map[string]any{"encoding": "bad"}),
	}}).Export().(map[string]any); bad["success"] != false {
		t.Fatalf("expected bad encoding failure, got %#v", bad)
	}

	copyResult := runtime.fileCopy(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("nested/bytes.bin"), vm.ToValue("nested/copy.bin")}}).Export().(map[string]any)
	if copyResult["success"] != true {
		t.Fatalf("fileCopy = %#v", copyResult)
	}
	moveResult := runtime.fileMove(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("nested/copy.bin"), vm.ToValue("nested/moved.bin")}}).Export().(map[string]any)
	if moveResult["success"] != true {
		t.Fatalf("fileMove = %#v", moveResult)
	}
	sizeResult := runtime.fileGetSize(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("nested/moved.bin")}}).Export().(map[string]any)
	if sizeResult["success"] != true || sizeResult["size"] != int64(3) {
		t.Fatalf("fileGetSize = %#v", sizeResult)
	}
	deleteResult := runtime.fileDelete(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("nested/moved.bin")}}).Export().(map[string]any)
	if deleteResult["success"] != true {
		t.Fatalf("fileDelete = %#v", deleteResult)
	}

	download := runtime.fileDownload(goja.FunctionCall{Arguments: []goja.Value{
		vm.ToValue("https://files.example.com/file"),
		vm.ToValue("downloads/file.bin"),
	}}).Export().(map[string]any)
	if download["success"] != true {
		t.Fatalf("fileDownload = %#v", download)
	}
	if data, err := os.ReadFile(filepath.Join(dir, "downloads/file.bin")); err != nil || string(data) != "downloaded" {
		t.Fatalf("downloaded data = %q/%v", data, err)
	}

	chunked := runtime.fileDownload(goja.FunctionCall{Arguments: []goja.Value{
		vm.ToValue("https://files.example.com/chunk"),
		vm.ToValue("downloads/chunk.bin"),
		vm.ToValue(map[string]any{"chunked": float64(2), "headers": map[string]any{"X-Test": "yes"}}),
	}}).Export().(map[string]any)
	if chunked["success"] != true {
		t.Fatalf("chunked fileDownload = %#v", chunked)
	}
	if data, err := os.ReadFile(filepath.Join(dir, "downloads/chunk.bin")); err != nil || string(data) != fileBody {
		t.Fatalf("chunked data = %q/%v", data, err)
	}

	if missing := runtime.fileDownload(goja.FunctionCall{}).Export().(map[string]any); missing["success"] != false {
		t.Fatalf("expected missing download args error, got %#v", missing)
	}
}

func TestExtensionRuntimeUtilityAPIs(t *testing.T) {
	vm := goja.New()
	runtime := &extensionRuntime{extensionID: "utils-ext", vm: vm}

	if runtime.sha256Hash(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("abc")}}).String() == "" {
		t.Fatal("expected sha256")
	}
	if runtime.hmacSHA256(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("msg"), vm.ToValue("key")}}).String() == "" {
		t.Fatal("expected hmac sha256")
	}
	if runtime.hmacSHA256Base64(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("msg"), vm.ToValue("key")}}).String() == "" {
		t.Fatal("expected hmac sha256 base64")
	}
	if value := runtime.hmacSHA1(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue([]any{float64(1), float64(2)}), vm.ToValue([]any{float64(3)})}}); len(value.Export().([]any)) == 0 {
		t.Fatal("expected hmac sha1 bytes")
	}
	if !goja.IsUndefined(runtime.parseJSON(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue(`{bad`)}})) {
		t.Fatal("expected invalid JSON to return undefined")
	}
	parsed := runtime.parseJSON(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue(`{"ok":true}`)}}).Export().(map[string]any)
	if parsed["ok"] != true {
		t.Fatalf("parseJSON = %#v", parsed)
	}
	if text := runtime.stringifyJSON(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue(map[string]any{"ok": true})}}).String(); !strings.Contains(text, "ok") {
		t.Fatalf("stringifyJSON = %q", text)
	}
	encrypted := runtime.cryptoEncrypt(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("plain"), vm.ToValue("secret")}}).Export().(map[string]any)
	if encrypted["success"] != true || encrypted["data"] == "" {
		t.Fatalf("cryptoEncrypt = %#v", encrypted)
	}
	decrypted := runtime.cryptoDecrypt(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue(encrypted["data"]), vm.ToValue("secret")}}).Export().(map[string]any)
	if decrypted["success"] != true || decrypted["data"] != "plain" {
		t.Fatalf("cryptoDecrypt = %#v", decrypted)
	}
	if bad := runtime.cryptoDecrypt(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("bad"), vm.ToValue("secret")}}).Export().(map[string]any); bad["success"] != false {
		t.Fatalf("expected bad decrypt failure, got %#v", bad)
	}
	key := runtime.cryptoGenerateKey(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue(float64(8))}}).Export().(map[string]any)
	if key["success"] != true || key["key"] == "" || key["hex"] == "" {
		t.Fatalf("cryptoGenerateKey = %#v", key)
	}
	if runtime.randomUserAgent(goja.FunctionCall{}).String() == "" || runtime.appUserAgent(goja.FunctionCall{}).String() == "" {
		t.Fatal("expected user agents")
	}
	SetAppVersion("9.9.9")
	if runtime.appVersion(goja.FunctionCall{}).String() != "9.9.9" {
		t.Fatal("appVersion mismatch")
	}
	if !runtime.sleep(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue(float64(0))}}).ToBoolean() {
		t.Fatal("zero sleep should succeed")
	}

	itemID := "utils-item"
	runtime.setActiveDownloadItemID(itemID)
	initDownloadCancel(itemID)
	if runtime.isDownloadCancelled(goja.FunctionCall{}).ToBoolean() {
		t.Fatal("item should not be cancelled yet")
	}
	runtime.setDownloadStatus(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue(itemProgressStatusDownloading)}})
	cancelDownload(itemID)
	if !runtime.isDownloadCancelled(goja.FunctionCall{}).ToBoolean() {
		t.Fatal("item should be cancelled")
	}
	clearDownloadCancel(itemID)
	runtime.clearActiveDownloadItemID()

	requestID := "utils-request"
	runtime.setActiveRequestID(requestID)
	initExtensionRequestCancel(requestID)
	if runtime.isRequestCancelled(goja.FunctionCall{}).ToBoolean() {
		t.Fatal("request should not be cancelled yet")
	}
	cancelExtensionRequest(requestID)
	if !runtime.isRequestCancelled(goja.FunctionCall{}).ToBoolean() {
		t.Fatal("request should be cancelled")
	}
	clearExtensionRequestCancel(requestID)
	runtime.clearActiveRequestID()

	if msg := runtime.formatLogArgs([]goja.Value{vm.ToValue("a"), vm.ToValue(1)}); msg != "a 1" {
		t.Fatalf("formatLogArgs = %q", msg)
	}
	runtime.logDebug(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("debug")}})
	runtime.logInfo(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("info")}})
	runtime.logWarn(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("warn")}})
	runtime.logError(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("error")}})
	if clean := runtime.sanitizeFilenameWrapper(goja.FunctionCall{Arguments: []goja.Value{vm.ToValue("A/B?")}}).String(); strings.ContainsAny(clean, "/?") {
		t.Fatalf("sanitize wrapper = %q", clean)
	}
}

func TestClassifySignedSessionExpiredAsVerification(t *testing.T) {
	got := classifyDownloadErrorType("Failed to resolve Deezer download: signed session expired")
	if got != "verification_required" {
		t.Fatalf("expected verification_required, got %q", got)
	}
}

func TestVerificationRequiredNoteConsume(t *testing.T) {
	r := &extensionRuntime{}
	if got := r.consumeVerificationRequired(); got != "" {
		t.Fatalf("expected empty before note, got %q", got)
	}
	r.noteVerificationRequired("")
	if got := r.consumeVerificationRequired(); got != "pending" {
		t.Fatalf("expected pending sentinel, got %q", got)
	}
	if got := r.consumeVerificationRequired(); got != "" {
		t.Fatalf("expected cleared after consume, got %q", got)
	}
	r.noteVerificationRequired("https://x/auth")
	if got := r.consumeVerificationRequired(); got != "https://x/auth" {
		t.Fatalf("expected auth url, got %q", got)
	}
}
