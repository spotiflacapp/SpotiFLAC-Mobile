package gobackend

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	goruntime "runtime"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/dop251/goja"
)

func TestSanitizeSignedSessionNamespace(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"lowercases", "MyExt", "myext"},
		{"trims whitespace", "  my-ext  ", "my-ext"},
		{"keeps allowed punctuation", "my-ext_v1.2", "my-ext_v1.2"},
		{"strips spaces and slashes but keeps dots", "my ext/../v1", "myext..v1"},
		{"strips leading and trailing punctuation", "..--my-ext__..", "my-ext"},
		{"empty stays empty", "", ""},
		{"only punctuation collapses to empty", "...", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := sanitizeSignedSessionNamespace(tc.in); got != tc.want {
				t.Errorf("sanitizeSignedSessionNamespace(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

func TestSignedSessionConfigWithDefaults(t *testing.T) {
	t.Run("nil config yields zero value", func(t *testing.T) {
		got := signedSessionConfigWithDefaults(nil)
		if got != (SignedSessionConfig{}) {
			t.Errorf("expected zero value config, got %+v", got)
		}
	})

	t.Run("fills in defaults without a namespace or baseUrl", func(t *testing.T) {
		got := signedSessionConfigWithDefaults(&SignedSessionConfig{})
		if got.AppVersion != "ext-1.0" {
			t.Errorf("AppVersion = %q, want ext-1.0", got.AppVersion)
		}
		if got.Platform != "extension" {
			t.Errorf("Platform = %q, want extension", got.Platform)
		}
		if got.CallbackURL != "spotiflac://session-grant" {
			t.Errorf("CallbackURL = %q", got.CallbackURL)
		}
		if got.SchemeLabel != "SPOTIFLAC-HMAC-V1" {
			t.Errorf("SchemeLabel = %q", got.SchemeLabel)
		}
		if got.HeaderPrefix != "X-Sig-" {
			t.Errorf("HeaderPrefix = %q", got.HeaderPrefix)
		}
		if got.TimeWindowSeconds != 300 {
			t.Errorf("TimeWindowSeconds = %d, want 300", got.TimeWindowSeconds)
		}
		if got.Endpoints.Bootstrap != "/bootstrap" || got.Endpoints.Challenge != "/challenge" || got.Endpoints.Exchange != "/session/exchange" {
			t.Errorf("Endpoints defaults = %+v", got.Endpoints)
		}
	})

	t.Run("preserves values the manifest already set", func(t *testing.T) {
		custom := &SignedSessionConfig{
			Namespace:         "tidal",
			BaseURL:           "https://auth.example.com",
			AppVersion:        "5.0",
			Platform:          "mobile",
			TimeWindowSeconds: 60,
			Endpoints:         SignedSessionEndpoints{Exchange: "/custom/exchange"},
		}
		got := signedSessionConfigWithDefaults(custom)
		if got.Namespace != "tidal" || got.BaseURL != "https://auth.example.com" {
			t.Errorf("namespace/baseUrl were overwritten: %+v", got)
		}
		if got.AppVersion != "5.0" || got.Platform != "mobile" || got.TimeWindowSeconds != 60 {
			t.Errorf("existing scalars were overwritten: %+v", got)
		}
		if got.Endpoints.Exchange != "/custom/exchange" {
			t.Errorf("Endpoints.Exchange overwritten: %q", got.Endpoints.Exchange)
		}
		// Untouched endpoints still get their defaults filled in.
		if got.Endpoints.Bootstrap != "/bootstrap" {
			t.Errorf("Endpoints.Bootstrap = %q, want default", got.Endpoints.Bootstrap)
		}
	})
}

func TestParseSignedSessionTime(t *testing.T) {
	cases := []struct {
		name    string
		in      string
		wantOK  bool
		wantUTC string
	}{
		{"RFC3339Nano", "2026-05-04T10:00:00.123456789Z", true, "2026-05-04T10:00:00Z"},
		{"RFC3339", "2026-05-04T10:00:00Z", true, "2026-05-04T10:00:00Z"},
		{"millisecond layout", "2026-05-04T10:00:00.000Z", true, "2026-05-04T10:00:00Z"},
		{"empty", "", false, ""},
		{"garbage", "not-a-time", false, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := parseSignedSessionTime(tc.in)
			if ok != tc.wantOK {
				t.Fatalf("parseSignedSessionTime(%q) ok = %v, want %v", tc.in, ok, tc.wantOK)
			}
			if ok && got.UTC().Format(time.RFC3339) != tc.wantUTC {
				t.Errorf("parseSignedSessionTime(%q) = %v, want %v", tc.in, got.UTC().Format(time.RFC3339), tc.wantUTC)
			}
		})
	}
}

func TestPreflightSignedSession(t *testing.T) {
	t.Run("reuses a valid session without network", func(t *testing.T) {
		calls := 0
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			calls++
			return nil, fmt.Errorf("unexpected request: %s", req.URL)
		})
		runtime := newSignedSessionTestRuntime(t, "preflight-valid", transport)
		runtime.manifest.SignedSession = &SignedSessionConfig{
			Namespace: "preflight-valid",
			BaseURL:   "https://auth.example.com",
		}
		config := signedSessionConfigWithDefaults(runtime.manifest.SignedSession)
		record, err := runtime.loadSignedSession(config)
		if err != nil {
			t.Fatalf("load session: %v", err)
		}
		record.SessionID = "session"
		record.SessionSecret = "secret"
		record.ExpiresAt = time.Now().Add(time.Hour).UTC().Format(time.RFC3339)
		if err := runtime.saveSignedSession(config, record); err != nil {
			t.Fatalf("save session: %v", err)
		}

		verificationRequired, err := runtime.preflightSignedSession()
		if err != nil || verificationRequired {
			t.Fatalf("preflight = verification:%v error:%v", verificationRequired, err)
		}
		if calls != 0 {
			t.Fatalf("valid session made %d network request(s)", calls)
		}
	})

	t.Run("reuses a fresh pending challenge", func(t *testing.T) {
		runtime := newSignedSessionTestRuntime(t, "preflight-pending", roundTripFunc(func(req *http.Request) (*http.Response, error) {
			return nil, fmt.Errorf("unexpected request: %s", req.URL)
		}))
		runtime.manifest.SignedSession = &SignedSessionConfig{
			Namespace: "preflight-pending",
			BaseURL:   "https://auth.example.com",
		}
		pendingAuthRequestsMu.Lock()
		pendingAuthRequests[runtime.extensionID] = &PendingAuthRequest{
			ExtensionID: runtime.extensionID,
			AuthURL:     "https://auth.example.com/challenge",
			CreatedAt:   time.Now(),
		}
		pendingAuthRequestsMu.Unlock()
		t.Cleanup(func() { ClearPendingAuthRequest(runtime.extensionID) })

		verificationRequired, err := runtime.preflightSignedSession()
		if err != nil || !verificationRequired {
			t.Fatalf("preflight = verification:%v error:%v", verificationRequired, err)
		}
	})

	t.Run("bootstraps a challenge for an unauthenticated session", func(t *testing.T) {
		calls := 0
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			calls++
			payload, _ := json.Marshal(signedSessionExchangeResponse{
				ChallengeURL: "https://auth.example.com/challenge",
			})
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(string(payload))),
				Request:    req,
			}, nil
		})
		runtime := newSignedSessionTestRuntime(t, "preflight-challenge", transport)
		runtime.manifest.SignedSession = &SignedSessionConfig{
			Namespace: "preflight-challenge",
			BaseURL:   "https://auth.example.com",
		}
		t.Cleanup(func() { ClearPendingAuthRequest(runtime.extensionID) })

		verificationRequired, err := runtime.preflightSignedSession()
		if err != nil || !verificationRequired {
			t.Fatalf("preflight = verification:%v error:%v", verificationRequired, err)
		}
		if calls != 1 {
			t.Fatalf("bootstrap calls = %d, want 1", calls)
		}
		if pending := GetPendingAuthRequest(runtime.extensionID); pending == nil || pending.AuthURL == "" {
			t.Fatalf("pending challenge = %#v", pending)
		}
	})

	t.Run("accepts a session issued directly by bootstrap", func(t *testing.T) {
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			payload, _ := json.Marshal(signedSessionExchangeResponse{
				SessionID:     "boot-session",
				SessionSecret: "boot-secret",
				ExpiresAt:     time.Now().Add(time.Hour).UTC().Format(time.RFC3339),
			})
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(string(payload))),
				Request:    req,
			}, nil
		})
		runtime := newSignedSessionTestRuntime(t, "preflight-direct", transport)
		runtime.manifest.SignedSession = &SignedSessionConfig{
			Namespace: "preflight-direct",
			BaseURL:   "https://auth.example.com",
		}

		verificationRequired, err := runtime.preflightSignedSession()
		if err != nil || verificationRequired {
			t.Fatalf("preflight = verification:%v error:%v", verificationRequired, err)
		}
		config := signedSessionConfigWithDefaults(runtime.manifest.SignedSession)
		record, err := runtime.loadSignedSession(config)
		if err != nil || record.SessionID != "boot-session" {
			t.Fatalf("bootstrapped session = %#v error:%v", record, err)
		}
	})

	t.Run("retries a transport failure once and surfaces the cause", func(t *testing.T) {
		calls := 0
		runtime := newSignedSessionTestRuntime(t, "preflight-network", roundTripFunc(func(req *http.Request) (*http.Response, error) {
			calls++
			return nil, fmt.Errorf("dial tcp: Wi-Fi route unavailable")
		}))
		runtime.manifest.SignedSession = &SignedSessionConfig{
			Namespace: "preflight-network",
			BaseURL:   "https://auth.example.com",
		}

		verificationRequired, err := runtime.preflightSignedSession()
		if err == nil || verificationRequired {
			t.Fatalf("preflight = verification:%v error:%v", verificationRequired, err)
		}
		if calls != 2 {
			t.Fatalf("bootstrap calls = %d, want one initial attempt and one retry", calls)
		}
		if !strings.Contains(err.Error(), "network request") || !strings.Contains(err.Error(), "Wi-Fi route unavailable") {
			t.Fatalf("bootstrap error did not preserve the transport cause: %v", err)
		}
		if strings.Contains(err.Error(), "install_id=") {
			t.Fatalf("bootstrap error leaked the install identifier: %v", err)
		}
	})

	t.Run("surfaces HTTP status and retry-after without inventing a challenge", func(t *testing.T) {
		calls := 0
		runtime := newSignedSessionTestRuntime(t, "preflight-rate-limit", roundTripFunc(func(req *http.Request) (*http.Response, error) {
			calls++
			return &http.Response{
				StatusCode: http.StatusTooManyRequests,
				Header:     http.Header{"Retry-After": []string{"17"}},
				Body:       io.NopCloser(strings.NewReader(`{"error":"limited"}`)),
				Request:    req,
			}, nil
		}))
		runtime.manifest.SignedSession = &SignedSessionConfig{
			Namespace: "preflight-rate-limit",
			BaseURL:   "https://auth.example.com",
		}

		verificationRequired, err := runtime.preflightSignedSession()
		if err == nil || verificationRequired {
			t.Fatalf("preflight = verification:%v error:%v", verificationRequired, err)
		}
		if calls != 1 {
			t.Fatalf("rate-limited bootstrap calls = %d, want 1", calls)
		}
		if !strings.Contains(err.Error(), "HTTP 429") || !strings.Contains(err.Error(), "retry-after seconds: 17") {
			t.Fatalf("rate-limit details missing from bootstrap error: %v", err)
		}
	})
}

func TestDownloadWithExtensionsPreflightsBeforeMetadataEnrichment(t *testing.T) {
	extensionID := "preflight-download"
	itemID := "preflight-item"
	RemoveItemProgress(itemID)
	t.Cleanup(func() { RemoveItemProgress(itemID) })
	transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
		payload, _ := json.Marshal(signedSessionExchangeResponse{
			ChallengeURL: "https://auth.example.com/challenge",
		})
		return &http.Response{
			StatusCode: http.StatusOK,
			Header:     make(http.Header),
			Body:       io.NopCloser(strings.NewReader(string(payload))),
			Request:    req,
		}, nil
	})
	runtime := newSignedSessionTestRuntime(t, extensionID, transport)
	manifest := &ExtensionManifest{
		Name:  extensionID,
		Types: []ExtensionType{ExtensionTypeDownloadProvider},
		SignedSession: &SignedSessionConfig{
			Namespace: extensionID,
			BaseURL:   "https://auth.example.com",
		},
	}
	runtime.manifest = manifest
	ext := &loadedExtension{
		ID:          extensionID,
		Manifest:    manifest,
		VM:          runtime.vm,
		runtime:     runtime,
		initialized: true,
		Enabled:     true,
		DataDir:     runtime.dataDir,
	}

	manager := getExtensionManager()
	manager.mu.Lock()
	previous, hadPrevious := manager.extensions[extensionID]
	manager.extensions[extensionID] = ext
	manager.mu.Unlock()
	t.Cleanup(func() {
		ClearPendingAuthRequest(extensionID)
		manager.mu.Lock()
		if hadPrevious {
			manager.extensions[extensionID] = previous
		} else {
			delete(manager.extensions, extensionID)
		}
		manager.mu.Unlock()
	})

	// Metadata may originate from another extension, but the explicitly chosen
	// download provider owns the signed-session namespace and verification.
	requestJSON := `{"source":"spotify-metadata","service":"preflight-download","item_id":"preflight-item","isrc":"USRC17607839"}`
	responseJSON, err := DownloadWithExtensionsJSON(requestJSON)
	if err != nil {
		t.Fatalf("DownloadWithExtensionsJSON: %v", err)
	}
	var response DownloadResponse
	if err := json.Unmarshal([]byte(responseJSON), &response); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if response.ErrorType != "verification_required" || response.Service != extensionID {
		t.Fatalf("response = %#v", response)
	}
	if got := GetItemProgress(itemID); got != "{}" {
		t.Fatalf("verification response left stale progress: %s", got)
	}
}

func TestParallelSignedSessionPreflightSharesOneBootstrap(t *testing.T) {
	var calls atomic.Int32
	transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
		calls.Add(1)
		// Keep the first bootstrap in flight long enough for the second runtime
		// to contend on the shared session coordinator.
		time.Sleep(20 * time.Millisecond)
		payload, _ := json.Marshal(signedSessionExchangeResponse{
			ChallengeURL: "https://auth.example.com/challenge",
		})
		return &http.Response{
			StatusCode: http.StatusOK,
			Header:     make(http.Header),
			Body:       io.NopCloser(strings.NewReader(string(payload))),
			Request:    req,
		}, nil
	})

	root := t.TempDir()
	config := &SignedSessionConfig{
		Namespace: "shared-download-session",
		BaseURL:   "https://auth.example.com",
	}
	newRuntime := func(extensionID string) *extensionRuntime {
		return &extensionRuntime{
			extensionID: extensionID,
			manifest: &ExtensionManifest{
				Name:          extensionID,
				SignedSession: config,
			},
			dataDir:    filepath.Join(root, extensionID),
			vm:         goja.New(),
			httpClient: &http.Client{Transport: transport},
		}
	}
	runtimeA := newRuntime("provider-a")
	runtimeB := newRuntime("provider-b")
	t.Cleanup(func() {
		ClearPendingAuthRequest("provider-a")
		ClearPendingAuthRequest("provider-b")
	})

	results := make(chan error, 2)
	for _, runtime := range []*extensionRuntime{runtimeA, runtimeB} {
		go func(runtime *extensionRuntime) {
			verificationRequired, err := runtime.preflightSignedSession()
			if err == nil && !verificationRequired {
				err = fmt.Errorf("verification was not requested")
			}
			results <- err
		}(runtime)
	}
	for range 2 {
		if err := <-results; err != nil {
			t.Fatal(err)
		}
	}
	if got := calls.Load(); got != 1 {
		t.Fatalf("parallel preflight bootstrap calls = %d, want 1", got)
	}
}

func TestDownloadWithExtensionsStopsAfterFailedSignedSessionPreflight(t *testing.T) {
	extensionID := "preflight-network-failure"
	itemID := "preflight-network-item"
	RemoveItemProgress(itemID)
	t.Cleanup(func() { RemoveItemProgress(itemID) })

	calls := 0
	runtime := newSignedSessionTestRuntime(t, extensionID, roundTripFunc(func(req *http.Request) (*http.Response, error) {
		calls++
		return nil, fmt.Errorf("dial tcp: Wi-Fi route unavailable")
	}))
	manifest := &ExtensionManifest{
		Name:  extensionID,
		Types: []ExtensionType{ExtensionTypeDownloadProvider},
		SignedSession: &SignedSessionConfig{
			Namespace: extensionID,
			BaseURL:   "https://auth.example.com",
		},
	}
	runtime.manifest = manifest
	ext := &loadedExtension{
		ID:          extensionID,
		Manifest:    manifest,
		VM:          runtime.vm,
		runtime:     runtime,
		initialized: true,
		Enabled:     true,
		DataDir:     runtime.dataDir,
	}

	manager := getExtensionManager()
	manager.mu.Lock()
	previous, hadPrevious := manager.extensions[extensionID]
	manager.extensions[extensionID] = ext
	manager.mu.Unlock()
	t.Cleanup(func() {
		manager.mu.Lock()
		if hadPrevious {
			manager.extensions[extensionID] = previous
		} else {
			delete(manager.extensions, extensionID)
		}
		manager.mu.Unlock()
	})

	requestJSON := `{"service":"preflight-network-failure","item_id":"preflight-network-item","isrc":"USRC17607839"}`
	responseJSON, err := DownloadWithExtensionsJSON(requestJSON)
	if err != nil {
		t.Fatalf("DownloadWithExtensionsJSON: %v", err)
	}
	var response DownloadResponse
	if err := json.Unmarshal([]byte(responseJSON), &response); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if response.ErrorType != "network" || response.Service != extensionID || !strings.Contains(response.Error, "Could not start verification") {
		t.Fatalf("response = %#v", response)
	}
	if calls != 2 {
		t.Fatalf("bootstrap calls = %d, want only the initial attempt and its transport retry", calls)
	}
	if got := GetItemProgress(itemID); got != "{}" {
		t.Fatalf("failed preflight left stale progress: %s", got)
	}
}

func TestSignedSessionURL(t *testing.T) {
	base := SignedSessionConfig{BaseURL: "https://auth.example.com/api"}

	t.Run("joins a relative endpoint onto the base", func(t *testing.T) {
		got, err := signedSessionURL(base, "/session/exchange")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		want := "https://auth.example.com/api/session/exchange"
		if got != want {
			t.Errorf("signedSessionURL = %q, want %q", got, want)
		}
	})

	t.Run("passes an absolute https endpoint through unchanged", func(t *testing.T) {
		got, err := signedSessionURL(base, "https://other.example.com/challenge")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "https://other.example.com/challenge" {
			t.Errorf("signedSessionURL = %q", got)
		}
	})

	t.Run("rejects an empty endpoint", func(t *testing.T) {
		if _, err := signedSessionURL(base, ""); err == nil {
			t.Error("expected error for empty endpoint")
		}
	})

	t.Run("rejects a non-https base URL", func(t *testing.T) {
		if _, err := signedSessionURL(SignedSessionConfig{BaseURL: "http://auth.example.com"}, "/x"); err == nil {
			t.Error("expected error for http:// base URL")
		}
	})

	t.Run("rejects a base URL with no host", func(t *testing.T) {
		if _, err := signedSessionURL(SignedSessionConfig{BaseURL: "https:///no-host"}, "/x"); err == nil {
			t.Error("expected error for base URL without a host")
		}
	})
}

func TestSignedSessionRetryAfterSeconds(t *testing.T) {
	t.Run("nil response", func(t *testing.T) {
		if got := signedSessionRetryAfterSeconds(nil); got != 0 {
			t.Errorf("got %d, want 0", got)
		}
	})

	t.Run("numeric seconds", func(t *testing.T) {
		resp := &http.Response{Header: http.Header{"Retry-After": []string{"30"}}}
		if got := signedSessionRetryAfterSeconds(resp); got != 30 {
			t.Errorf("got %d, want 30", got)
		}
	})

	t.Run("negative numeric seconds clamp to zero", func(t *testing.T) {
		resp := &http.Response{Header: http.Header{"Retry-After": []string{"-5"}}}
		if got := signedSessionRetryAfterSeconds(resp); got != 0 {
			t.Errorf("got %d, want 0", got)
		}
	})

	t.Run("HTTP-date in the future", func(t *testing.T) {
		future := time.Now().Add(2 * time.Minute).UTC()
		resp := &http.Response{Header: http.Header{"Retry-After": []string{future.Format(http.TimeFormat)}}}
		got := signedSessionRetryAfterSeconds(resp)
		if got <= 0 || got > 120 {
			t.Errorf("got %d, want roughly 120", got)
		}
	})

	t.Run("missing header", func(t *testing.T) {
		resp := &http.Response{Header: http.Header{}}
		if got := signedSessionRetryAfterSeconds(resp); got != 0 {
			t.Errorf("got %d, want 0", got)
		}
	})
}

func TestSignedSessionProviderRetryDuration(t *testing.T) {
	t.Run("header is authoritative", func(t *testing.T) {
		resp := &http.Response{Header: http.Header{"Retry-After": []string{"10"}}}
		contract := signedSessionErrorContract{RetryAfterSeconds: 30}
		if got := signedSessionProviderRetryDuration(resp, contract); got != 10*time.Second {
			t.Fatalf("retry duration = %s, want 10s", got)
		}
	})

	t.Run("body fallback is bounded", func(t *testing.T) {
		resp := &http.Response{Header: make(http.Header)}
		contract := signedSessionErrorContract{RetryAfterSeconds: int(^uint(0) >> 1)}
		if got := signedSessionProviderRetryDuration(resp, contract); got != maxRetryAfterDelay {
			t.Fatalf("retry duration = %s, want cap %s", got, maxRetryAfterDelay)
		}
	})
}

func TestNormalizeSignedSessionRecordScope(t *testing.T) {
	config := SignedSessionConfig{Namespace: "Tidal", BaseURL: "https://a.example.com", AppVersion: "1.0", Platform: "mobile"}

	t.Run("first save just stamps the scope", func(t *testing.T) {
		record := &signedSessionRecord{SessionID: "s1", SessionSecret: "secret"}
		normalizeSignedSessionRecordScope(config, record)
		if record.Namespace != "tidal" || record.BaseURL != config.BaseURL {
			t.Errorf("scope not stamped: %+v", record)
		}
		if record.SessionID != "s1" || record.SessionSecret != "secret" {
			t.Errorf("session fields should survive first stamp: %+v", record)
		}
	})

	t.Run("same scope preserves the session", func(t *testing.T) {
		record := &signedSessionRecord{
			Namespace: "tidal", BaseURL: config.BaseURL, AppVersion: config.AppVersion, Platform: config.Platform,
			SessionID: "s1", SessionSecret: "secret", ExpiresAt: "later",
		}
		normalizeSignedSessionRecordScope(config, record)
		if record.SessionID != "s1" || record.SessionSecret != "secret" || record.ExpiresAt != "later" {
			t.Errorf("unexpected wipe on matching scope: %+v", record)
		}
	})

	t.Run("changed scope wipes the session secret", func(t *testing.T) {
		record := &signedSessionRecord{
			Namespace: "tidal", BaseURL: "https://old.example.com", AppVersion: config.AppVersion, Platform: config.Platform,
			SessionID: "s1", SessionSecret: "secret", ExpiresAt: "later",
		}
		normalizeSignedSessionRecordScope(config, record)
		if record.SessionID != "" || record.SessionSecret != "" || record.ExpiresAt != "" {
			t.Errorf("expected session fields to be wiped after scope change: %+v", record)
		}
		if record.BaseURL != config.BaseURL {
			t.Errorf("BaseURL not updated to new scope: %q", record.BaseURL)
		}
	})
}

func newSignedSessionTestRuntime(t *testing.T, extensionID string, transport roundTripFunc) *extensionRuntime {
	t.Helper()
	dataDir := t.TempDir()
	return &extensionRuntime{
		extensionID: extensionID,
		manifest:    &ExtensionManifest{Name: extensionID},
		dataDir:     dataDir,
		vm:          goja.New(),
		httpClient:  &http.Client{Transport: transport},
	}
}

func saveUsableSignedSession(
	t *testing.T,
	runtime *extensionRuntime,
	config SignedSessionConfig,
	sessionID string,
) SignedSessionConfig {
	t.Helper()
	resolved := signedSessionConfigWithDefaults(&config)
	record, err := runtime.loadSignedSession(resolved)
	if err != nil {
		t.Fatal(err)
	}
	record.SessionID = sessionID
	record.SessionSecret = "secret-" + sessionID
	record.ExpiresAt = time.Now().Add(time.Hour).UTC().Format(time.RFC3339)
	if err := runtime.saveSignedSession(resolved, record); err != nil {
		t.Fatal(err)
	}
	return resolved
}

func TestSignedSessionFilePathDeterminism(t *testing.T) {
	runtime := newSignedSessionTestRuntime(t, "tidal-ext", nil)

	configA := SignedSessionConfig{Namespace: "tidal", BaseURL: "https://a.example.com"}
	configB := SignedSessionConfig{Namespace: "tidal", BaseURL: "https://b.example.com"}

	pathA1, err := runtime.signedSessionFilePath(configA)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	pathA2, err := runtime.signedSessionFilePath(configA)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if pathA1 != pathA2 {
		t.Errorf("same config produced different paths: %q vs %q", pathA1, pathA2)
	}

	pathB, err := runtime.signedSessionFilePath(configB)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if pathA1 == pathB {
		t.Errorf("different baseUrl scopes collided on the same file: %q", pathA1)
	}

	if _, err := runtime.signedSessionFilePath(SignedSessionConfig{Namespace: ""}); err == nil {
		t.Error("expected error for empty namespace")
	}
}

func TestLoadAndSaveSignedSessionRoundTrip(t *testing.T) {
	runtime := newSignedSessionTestRuntime(t, "tidal-ext", nil)
	config := SignedSessionConfig{Namespace: "tidal", BaseURL: "https://auth.example.com"}

	record, err := runtime.loadSignedSession(config)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if record.InstallID == "" {
		t.Fatal("expected a generated install_id on first load")
	}

	path, err := runtime.signedSessionFilePath(config)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("expected session file to be persisted: %v", err)
	}
	// Windows does not preserve Unix permission bits, so only assert on POSIX.
	if goruntime.GOOS != "windows" {
		if perm := info.Mode().Perm(); perm != 0o600 {
			t.Errorf("session file perm = %o, want 0600", perm)
		}
	}

	record.SessionID = "sess-1"
	record.SessionSecret = "top-secret"
	record.ExpiresAt = "2030-01-01T00:00:00Z"
	if err := runtime.saveSignedSession(config, record); err != nil {
		t.Fatalf("unexpected error saving: %v", err)
	}

	reloaded, err := runtime.loadSignedSession(config)
	if err != nil {
		t.Fatalf("unexpected error reloading: %v", err)
	}
	if reloaded.InstallID != record.InstallID {
		t.Errorf("install_id changed across reload: %q vs %q", reloaded.InstallID, record.InstallID)
	}
	if reloaded.SessionID != "sess-1" || reloaded.SessionSecret != "top-secret" || reloaded.ExpiresAt != "2030-01-01T00:00:00Z" {
		t.Errorf("session fields did not round-trip: %+v", reloaded)
	}
}

func TestSignedSessionStatusAndClear(t *testing.T) {
	runtime := newSignedSessionTestRuntime(t, "tidal-ext", nil)
	runtime.manifest.SignedSession = &SignedSessionConfig{Namespace: "tidal", BaseURL: "https://auth.example.com"}

	readStatus := func() map[string]any {
		v := runtime.signedSessionStatus(goja.FunctionCall{})
		return v.Export().(map[string]any)
	}

	if status := readStatus(); status["authenticated"] != false {
		t.Fatalf("expected unauthenticated before any grant, got %+v", status)
	}

	config := signedSessionConfigWithDefaults(runtime.manifest.SignedSession)
	record, err := runtime.loadSignedSession(config)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	record.SessionID = "sess-1"
	record.SessionSecret = "secret"
	record.ExpiresAt = time.Now().Add(time.Hour).UTC().Format("2006-01-02T15:04:05.000Z")
	if err := runtime.saveSignedSession(config, record); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if status := readStatus(); status["authenticated"] != true {
		t.Fatalf("expected authenticated after saving a live session, got %+v", status)
	}

	record.ExpiresAt = time.Now().Add(-time.Hour).UTC().Format("2006-01-02T15:04:05.000Z")
	if err := runtime.saveSignedSession(config, record); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status := readStatus(); status["authenticated"] != false {
		t.Fatalf("expected expired session to report unauthenticated, got %+v", status)
	}

	// Restore a live session, then confirm clear() wipes it.
	record.ExpiresAt = time.Now().Add(time.Hour).UTC().Format("2006-01-02T15:04:05.000Z")
	if err := runtime.saveSignedSession(config, record); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	clearResult := runtime.signedSessionClear(goja.FunctionCall{}).Export().(map[string]any)
	if clearResult["success"] != true {
		t.Fatalf("expected clear to succeed, got %+v", clearResult)
	}
	if status := readStatus(); status["authenticated"] != false {
		t.Fatalf("expected unauthenticated after clear, got %+v", status)
	}
}

// TestDoSignedSessionRequestSignature is the highest-value test in this file:
// it recomputes the HMAC-SHA256 rolling-key signature server-side from the
// headers the client actually sent, the same way a real backend would, to
// guard against silent regressions in the signing scheme (field order,
// rolling-key derivation, or header names).
func TestDoSignedSessionRequestSignature(t *testing.T) {
	const sessionSecret = "shhh-its-a-secret"
	const sessionID = "sess-42"

	var capturedErr string
	transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
		config := signedSessionConfigWithDefaults(&SignedSessionConfig{Namespace: "tidal", BaseURL: "https://auth.example.com"})
		prefix := config.HeaderPrefix

		ts := req.Header.Get(prefix + "Timestamp")
		nonce := req.Header.Get(prefix + "Nonce")
		bodyHash := req.Header.Get(prefix + "Body-SHA256")
		gotSig := req.Header.Get(prefix + "Signature")
		gotSession := req.Header.Get(prefix + "Session")

		if gotSession != sessionID {
			capturedErr = "unexpected session id header: " + gotSession
		}

		bodyBytes, _ := io.ReadAll(req.Body)
		wantBodyHashBytes := sha256.Sum256(bodyBytes)
		wantBodyHash := hex.EncodeToString(wantBodyHashBytes[:])
		if bodyHash != wantBodyHash {
			capturedErr = "body hash mismatch"
		}

		parsedTs, err := time.Parse("2006-01-02T15:04:05.000Z", ts)
		if err != nil {
			capturedErr = "bad timestamp: " + err.Error()
		}
		window := parsedTs.Unix() / int64(config.TimeWindowSeconds)
		rollingInput := fmt.Sprintf("%d:%s", window, sessionID)
		rk := base64.RawURLEncoding.EncodeToString(hmacSHA256Bytes([]byte(sessionSecret), []byte(rollingInput)))
		signingInput := strings.Join([]string{
			config.SchemeLabel,
			req.Method,
			req.URL.EscapedPath(),
			"",
			bodyHash,
			ts,
			nonce,
			sessionID,
			config.AppVersion,
			config.Platform,
		}, "\n")
		wantSig := base64.RawURLEncoding.EncodeToString(hmacSHA256Bytes([]byte(rk), []byte(signingInput)))

		if !hmac.Equal([]byte(gotSig), []byte(wantSig)) {
			capturedErr = "signature mismatch: got " + gotSig + " want " + wantSig
		}

		return &http.Response{
			StatusCode: 200,
			Header:     make(http.Header),
			Body:       io.NopCloser(strings.NewReader(`{"ok":true}`)),
			Request:    req,
		}, nil
	})

	runtime := newSignedSessionTestRuntime(t, "tidal-ext", transport)
	config := signedSessionConfigWithDefaults(&SignedSessionConfig{Namespace: "tidal", BaseURL: "https://auth.example.com"})
	record := &signedSessionRecord{InstallID: "install-1", SessionID: sessionID, SessionSecret: sessionSecret}

	resp, body, _, err := runtime.doSignedSessionRequest(config, record, http.MethodPost, "/tracks/search", []byte(`{"q":"test"}`), nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if capturedErr != "" {
		t.Fatalf("signature verification failed: %s", capturedErr)
	}
	if resp.StatusCode != 200 {
		t.Errorf("status = %d, want 200", resp.StatusCode)
	}
	if string(body) != `{"ok":true}` {
		t.Errorf("body = %q", body)
	}
}

func TestSignedSessionFetchUnauthenticatedTriggersVerification(t *testing.T) {
	transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
		if strings.Contains(req.URL.Path, "/bootstrap") {
			payload := signedSessionExchangeResponse{AuthURL: "https://auth.example.com/login?state=abc"}
			body, _ := json.Marshal(payload)
			return &http.Response{
				StatusCode: 200,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(string(body))),
				Request:    req,
			}, nil
		}
		t.Fatalf("unexpected request to %s", req.URL.String())
		return nil, nil
	})

	runtime := newSignedSessionTestRuntime(t, "tidal-ext", transport)
	runtime.manifest.SignedSession = &SignedSessionConfig{Namespace: "tidal", BaseURL: "https://auth.example.com"}

	call := goja.FunctionCall{Arguments: []goja.Value{runtime.vm.ToValue("GET"), runtime.vm.ToValue("/tracks/search")}}
	result := runtime.signedSessionFetch(call).Export().(map[string]any)

	if result["ok"] != false {
		t.Fatalf("expected ok=false when unauthenticated, got %+v", result)
	}
	if result["needsVerification"] != true {
		t.Fatalf("expected needsVerification=true, got %+v", result)
	}
	if result["auth_url"] != "https://auth.example.com/login?state=abc" {
		t.Fatalf("unexpected auth_url: %+v", result)
	}
}

func TestSignedSessionFetchRevokesSessionOnCanonicalSessionInvalid(t *testing.T) {
	calls := 0
	transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
		calls++
		switch {
		case strings.Contains(req.URL.Path, "/bootstrap"):
			payload := signedSessionExchangeResponse{AuthURL: "https://auth.example.com/login"}
			body, _ := json.Marshal(payload)
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(string(body))), Request: req}, nil
		default:
			return &http.Response{
				StatusCode: http.StatusUnauthorized,
				Header:     make(http.Header),
				Body: io.NopCloser(strings.NewReader(
					`{"error":"Unauthorized","code":"SESSION_INVALID","origin":"gateway","action":"bootstrap_session"}`,
				)),
				Request: req,
			}, nil
		}
	})

	runtime := newSignedSessionTestRuntime(t, "tidal-ext", transport)
	config := SignedSessionConfig{Namespace: "tidal", BaseURL: "https://auth.example.com"}
	runtime.manifest.SignedSession = &config

	resolved := signedSessionConfigWithDefaults(&config)
	record, err := runtime.loadSignedSession(resolved)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	record.SessionID = "sess-1"
	record.SessionSecret = "secret"
	record.ExpiresAt = time.Now().Add(time.Hour).UTC().Format("2006-01-02T15:04:05.000Z")
	if err := runtime.saveSignedSession(resolved, record); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	call := goja.FunctionCall{Arguments: []goja.Value{runtime.vm.ToValue("GET"), runtime.vm.ToValue("/tracks/search")}}
	result := runtime.signedSessionFetch(call).Export().(map[string]any)
	if result["ok"] != false || result["needsVerification"] != true {
		t.Fatalf("expected verification after canonical SESSION_INVALID, got %+v", result)
	}

	reloaded, err := runtime.loadSignedSession(resolved)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if reloaded.SessionID != "" || reloaded.SessionSecret != "" {
		t.Fatalf("expected session to be wiped after SESSION_INVALID, got %+v", reloaded)
	}
}

func TestSignedSessionFetchRetriesAfterSilentSessionBootstrap(t *testing.T) {
	calls := 0
	transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
		calls++
		switch {
		case strings.Contains(req.URL.Path, "/bootstrap"):
			payload, _ := json.Marshal(signedSessionExchangeResponse{
				SessionID:     "sess-replacement",
				SessionSecret: "secret-replacement",
				ExpiresAt:     time.Now().Add(time.Hour).UTC().Format(time.RFC3339),
			})
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(string(payload))),
				Request:    req,
			}, nil
		case req.Header.Get("X-Sig-Session") == "sess-replacement":
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(`{"ticket_id":"fresh"}`)),
				Request:    req,
			}, nil
		default:
			return &http.Response{
				StatusCode: http.StatusUnauthorized,
				Header:     make(http.Header),
				Body: io.NopCloser(strings.NewReader(
					`{"error":"Unauthorized","code":"SESSION_INVALID","origin":"gateway","action":"bootstrap_session"}`,
				)),
				Request: req,
			}, nil
		}
	})
	runtime := newSignedSessionTestRuntime(t, "silent-bootstrap", transport)
	config := SignedSessionConfig{Namespace: "silent-bootstrap", BaseURL: "https://auth.example.com"}
	runtime.manifest.SignedSession = &config
	resolved := saveUsableSignedSession(t, runtime, config, "sess-old")

	call := goja.FunctionCall{Arguments: []goja.Value{
		runtime.vm.ToValue("POST"),
		runtime.vm.ToValue("/tickets"),
	}}
	result := runtime.signedSessionFetch(call).Export().(map[string]any)
	if result["ok"] != true || calls != 3 {
		t.Fatalf("signed request was not retried after silent bootstrap: calls=%d result=%+v", calls, result)
	}
	reloaded, err := runtime.loadSignedSession(resolved)
	if err != nil {
		t.Fatal(err)
	}
	if reloaded.SessionID != "sess-replacement" || reloaded.SessionSecret != "secret-replacement" {
		t.Fatalf("replacement session was not persisted: %+v", reloaded)
	}
}

func TestSignedSessionFetchDoesNotMutateSessionForNonCanonicalAuthStatus(t *testing.T) {
	tests := []struct {
		name       string
		statusCode int
		body       string
	}{
		{
			name:       "bare 401",
			statusCode: http.StatusUnauthorized,
			body:       `{}`,
		},
		{
			name:       "provider-origin 401",
			statusCode: http.StatusUnauthorized,
			body:       `{"error":"Unauthorized","code":"PROVIDER_AUTH_FAILED","origin":"provider"}`,
		},
		{
			name:       "gateway 401 missing action",
			statusCode: http.StatusUnauthorized,
			body:       `{"error":"Unauthorized","code":"SESSION_INVALID","origin":"gateway"}`,
		},
		{
			name:       "bare 428",
			statusCode: http.StatusPreconditionRequired,
			body:       `{"error":"VERIFY_REQUIRED"}`,
		},
		{
			name:       "request auth 403 with forbidden action",
			statusCode: http.StatusForbidden,
			body:       `{"error":"Forbidden","code":"REQUEST_AUTH_INVALID","origin":"gateway","action":"bootstrap_session"}`,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			calls := 0
			transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
				calls++
				return &http.Response{
					StatusCode: tc.statusCode,
					Header:     make(http.Header),
					Body:       io.NopCloser(strings.NewReader(tc.body)),
					Request:    req,
				}, nil
			})
			runtime := newSignedSessionTestRuntime(t, "strict-contract-"+strings.ReplaceAll(tc.name, " ", "-"), transport)
			config := SignedSessionConfig{Namespace: runtime.extensionID, BaseURL: "https://auth.example.com"}
			runtime.manifest.SignedSession = &config
			resolved := saveUsableSignedSession(t, runtime, config, "sess-safe")

			call := goja.FunctionCall{Arguments: []goja.Value{
				runtime.vm.ToValue("GET"),
				runtime.vm.ToValue("/tracks/search"),
			}}
			result := runtime.signedSessionFetch(call).Export().(map[string]any)
			if result["needsVerification"] == true {
				t.Fatalf("non-canonical response triggered verification: %+v", result)
			}
			if calls != 1 {
				t.Fatalf("network calls = %d, want no bootstrap or retry", calls)
			}
			reloaded, err := runtime.loadSignedSession(resolved)
			if err != nil {
				t.Fatal(err)
			}
			if reloaded.SessionID != "sess-safe" || reloaded.SessionSecret != "secret-sess-safe" {
				t.Fatalf("non-canonical response mutated the session: %+v", reloaded)
			}
		})
	}
}

func TestSignedSessionFetchCanonicalVerifyDoesNotClearSession(t *testing.T) {
	calls := 0
	transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
		calls++
		switch {
		case strings.Contains(req.URL.Path, "/bootstrap"):
			payload, _ := json.Marshal(signedSessionExchangeResponse{
				AuthURL: "https://auth.example.com/verify",
			})
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(string(payload))),
				Request:    req,
			}, nil
		case strings.Contains(req.URL.Path, "/session/exchange"):
			payload, _ := json.Marshal(signedSessionExchangeResponse{
				SessionID:     "sess-after-verify",
				SessionSecret: "secret-after-verify",
				ExpiresAt:     time.Now().Add(time.Hour).UTC().Format(time.RFC3339),
			})
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(string(payload))),
				Request:    req,
			}, nil
		case req.Header.Get("X-Sig-Session") == "sess-after-verify":
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(`{"ok":true}`)),
				Request:    req,
			}, nil
		}
		return &http.Response{
			StatusCode: http.StatusPreconditionRequired,
			Header:     make(http.Header),
			Body: io.NopCloser(strings.NewReader(
				`{"error":"VERIFY_REQUIRED","code":"VERIFY_REQUIRED","origin":"gateway","action":"verify"}`,
			)),
			Request: req,
		}, nil
	})
	runtime := newSignedSessionTestRuntime(t, "canonical-verify", transport)
	config := SignedSessionConfig{Namespace: "canonical-verify", BaseURL: "https://auth.example.com"}
	runtime.manifest.SignedSession = &config
	resolved := saveUsableSignedSession(t, runtime, config, "sess-verified")

	call := goja.FunctionCall{Arguments: []goja.Value{
		runtime.vm.ToValue("GET"),
		runtime.vm.ToValue("/tracks/search"),
	}}
	result := runtime.signedSessionFetch(call).Export().(map[string]any)
	if result["needsVerification"] != true || result["auth_url"] != "https://auth.example.com/verify" {
		t.Fatalf("canonical VERIFY_REQUIRED did not open verification: %+v", result)
	}
	if calls != 2 {
		t.Fatalf("network calls = %d, want signed request plus bootstrap", calls)
	}
	reloaded, err := runtime.loadSignedSession(resolved)
	if err != nil {
		t.Fatal(err)
	}
	if reloaded.SessionID != "sess-verified" || reloaded.SessionSecret != "secret-sess-verified" {
		t.Fatalf("VERIFY_REQUIRED cleared the valid gateway session: %+v", reloaded)
	}

	blockedResult := runtime.signedSessionFetch(call).Export().(map[string]any)
	if blockedResult["needsVerification"] != true {
		t.Fatalf("blocked generation did not join verification: %+v", blockedResult)
	}
	if calls != 2 {
		t.Fatalf("blocked generation reached the gateway again: calls=%d", calls)
	}
	verificationRequired, err := runtime.preflightSignedSession()
	if err != nil || !verificationRequired {
		t.Fatalf("preflight did not preserve the blocked verification state: required=%v err=%v", verificationRequired, err)
	}
	if calls != 2 {
		t.Fatalf("blocked preflight reached the gateway again: calls=%d", calls)
	}
	status := runtime.signedSessionStatus(goja.FunctionCall{}).Export().(map[string]any)
	if status["authenticated"] != false || status["verification_required"] != true {
		t.Fatalf("blocked generation status is incorrect: %+v", status)
	}

	if err := runtime.exchangeSignedSessionGrant("grant-after-verify"); err != nil {
		t.Fatalf("exchange grant: %v", err)
	}
	afterVerification := runtime.signedSessionFetch(call).Export().(map[string]any)
	if afterVerification["ok"] != true {
		t.Fatalf("new verified generation remained blocked: %+v", afterVerification)
	}
	if calls != 4 {
		t.Fatalf("network calls = %d, want 428, bootstrap, exchange, success", calls)
	}
}

func TestSignedSessionFetchRequestAuthInvalidPreservesSession(t *testing.T) {
	t.Run("current generation returns the error without bootstrap", func(t *testing.T) {
		calls := 0
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			calls++
			return &http.Response{
				StatusCode: http.StatusForbidden,
				Header:     make(http.Header),
				Body: io.NopCloser(strings.NewReader(
					`{"error":"Forbidden","code":"REQUEST_AUTH_INVALID","origin":"gateway","retryable":false}`,
				)),
				Request: req,
			}, nil
		})
		runtime := newSignedSessionTestRuntime(t, "request-auth-current", transport)
		config := SignedSessionConfig{Namespace: "request-auth-current", BaseURL: "https://auth.example.com"}
		runtime.manifest.SignedSession = &config
		resolved := saveUsableSignedSession(t, runtime, config, "sess-request-auth")

		call := goja.FunctionCall{Arguments: []goja.Value{
			runtime.vm.ToValue("POST"),
			runtime.vm.ToValue("/tickets"),
		}}
		result := runtime.signedSessionFetch(call).Export().(map[string]any)
		if result["code"] != "REQUEST_AUTH_INVALID" || result["needsVerification"] == true {
			t.Fatalf("REQUEST_AUTH_INVALID was not returned as a non-verification error: %+v", result)
		}
		if calls != 1 {
			t.Fatalf("current generation request was retried or bootstrapped: calls=%d", calls)
		}
		reloaded, err := runtime.loadSignedSession(resolved)
		if err != nil {
			t.Fatal(err)
		}
		if reloaded.SessionID != "sess-request-auth" || reloaded.SessionSecret != "secret-sess-request-auth" {
			t.Fatalf("REQUEST_AUTH_INVALID mutated the current session: %+v", reloaded)
		}
	})

	t.Run("stale generation retries once with the current session", func(t *testing.T) {
		oldRequestStarted := make(chan struct{})
		releaseOldRequest := make(chan struct{})
		var requestCalls atomic.Int32

		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			switch {
			case strings.HasSuffix(req.URL.Path, "/session/exchange"):
				payload, _ := json.Marshal(signedSessionExchangeResponse{
					SessionID:     "sess-request-new",
					SessionSecret: "secret-request-new",
					ExpiresAt:     time.Now().Add(time.Hour).UTC().Format(time.RFC3339),
				})
				return &http.Response{
					StatusCode: http.StatusOK,
					Header:     make(http.Header),
					Body:       io.NopCloser(strings.NewReader(string(payload))),
					Request:    req,
				}, nil
			case strings.HasSuffix(req.URL.Path, "/tickets"):
				requestCalls.Add(1)
				if req.Header.Get("X-Sig-Session") == "sess-request-old" {
					close(oldRequestStarted)
					<-releaseOldRequest
					return &http.Response{
						StatusCode: http.StatusForbidden,
						Header:     make(http.Header),
						Body: io.NopCloser(strings.NewReader(
							`{"error":"Forbidden","code":"REQUEST_AUTH_INVALID","origin":"gateway","retryable":false}`,
						)),
						Request: req,
					}, nil
				}
				return &http.Response{
					StatusCode: http.StatusOK,
					Header:     make(http.Header),
					Body:       io.NopCloser(strings.NewReader(`{"ticket_id":"fresh"}`)),
					Request:    req,
				}, nil
			default:
				t.Fatalf("unexpected request: %s", req.URL.String())
				return nil, nil
			}
		})

		root := t.TempDir()
		config := &SignedSessionConfig{Namespace: "request-auth-shared", BaseURL: "https://auth.example.com"}
		newRuntime := func(extensionID string) *extensionRuntime {
			return &extensionRuntime{
				extensionID: extensionID,
				manifest: &ExtensionManifest{
					Name:          extensionID,
					SignedSession: config,
				},
				dataDir:    filepath.Join(root, extensionID),
				vm:         goja.New(),
				httpClient: &http.Client{Transport: transport},
			}
		}
		runtimeA := newRuntime("request-auth-a")
		runtimeB := newRuntime("request-auth-b")
		resolved := saveUsableSignedSession(t, runtimeA, *config, "sess-request-old")

		resultCh := make(chan map[string]any, 1)
		go func() {
			call := goja.FunctionCall{Arguments: []goja.Value{
				runtimeA.vm.ToValue("POST"),
				runtimeA.vm.ToValue("/tickets"),
			}}
			resultCh <- runtimeA.signedSessionFetch(call).Export().(map[string]any)
		}()
		<-oldRequestStarted
		if err := runtimeB.exchangeSignedSessionGrant("grant-request-auth"); err != nil {
			t.Fatalf("exchange grant: %v", err)
		}
		close(releaseOldRequest)

		result := <-resultCh
		if result["ok"] != true || requestCalls.Load() != 2 {
			t.Fatalf("stale request was not rebuilt once: calls=%d result=%+v", requestCalls.Load(), result)
		}
		reloaded, err := runtimeA.loadSignedSession(resolved)
		if err != nil {
			t.Fatal(err)
		}
		if reloaded.SessionID != "sess-request-new" || reloaded.SessionSecret != "secret-request-new" {
			t.Fatalf("stale REQUEST_AUTH_INVALID changed the new session: %+v", reloaded)
		}
	})
}

func TestSignedSessionFetchProviderContractsNeverClearSession(t *testing.T) {
	t.Run("provider authentication failure passes through without retry", func(t *testing.T) {
		calls := 0
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			calls++
			return &http.Response{
				StatusCode: http.StatusBadGateway,
				Header:     make(http.Header),
				Body: io.NopCloser(strings.NewReader(
					`{"error":"Provider authentication failed","code":"PROVIDER_AUTH_FAILED","origin":"provider","retryable":false,"retry_mode":"none"}`,
				)),
				Request: req,
			}, nil
		})
		runtime := newSignedSessionTestRuntime(t, "provider-auth-failed", transport)
		config := SignedSessionConfig{Namespace: "provider-auth-failed", BaseURL: "https://auth.example.com"}
		runtime.manifest.SignedSession = &config
		resolved := saveUsableSignedSession(t, runtime, config, "sess-provider-auth")

		call := goja.FunctionCall{Arguments: []goja.Value{
			runtime.vm.ToValue("POST"),
			runtime.vm.ToValue("/tickets"),
		}}
		result := runtime.signedSessionFetch(call).Export().(map[string]any)
		if result["code"] != "PROVIDER_AUTH_FAILED" ||
			result["origin"] != "provider" ||
			result["retryMode"] != "none" {
			t.Fatalf("provider contract was not exposed to the extension: %+v", result)
		}
		if result["needsVerification"] == true || calls != 1 {
			t.Fatalf("provider auth failure triggered verification or retry: calls=%d result=%+v", calls, result)
		}
		reloaded, err := runtime.loadSignedSession(resolved)
		if err != nil {
			t.Fatal(err)
		}
		if reloaded.SessionID != "sess-provider-auth" {
			t.Fatalf("provider auth failure cleared the gateway session: %+v", reloaded)
		}
	})

	t.Run("non-replay retry modes fail closed", func(t *testing.T) {
		previousWait := signedSessionProviderWait
		waitCalls := 0
		signedSessionProviderWait = func(context.Context, time.Duration) error {
			waitCalls++
			return nil
		}
		t.Cleanup(func() { signedSessionProviderWait = previousWait })

		tests := []struct {
			name     string
			modeJSON string
			wantMode string
		}{
			{name: "missing mode"},
			{name: "none", modeJSON: `,"retry_mode":"none"`, wantMode: "none"},
			{name: "new ticket", modeJSON: `,"retry_mode":"new_ticket"`, wantMode: "new_ticket"},
			{name: "poll existing", modeJSON: `,"retry_mode":"poll_existing"`, wantMode: "poll_existing"},
			{name: "unknown", modeJSON: `,"retry_mode":"future_mode"`, wantMode: "future_mode"},
		}
		for _, tc := range tests {
			t.Run(tc.name, func(t *testing.T) {
				calls := 0
				transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
					calls++
					body := fmt.Sprintf(
						`{"error":"Provider temporarily unavailable","code":"PROVIDER_UNAVAILABLE","origin":"provider","retryable":true%s,"retry_after_seconds":10}`,
						tc.modeJSON,
					)
					return &http.Response{
						StatusCode: http.StatusServiceUnavailable,
						Header:     http.Header{"Retry-After": []string{"10"}},
						Body:       io.NopCloser(strings.NewReader(body)),
						Request:    req,
					}, nil
				})
				runtime := newSignedSessionTestRuntime(t, "retry-mode-"+strings.ReplaceAll(tc.name, " ", "-"), transport)
				config := SignedSessionConfig{Namespace: runtime.extensionID, BaseURL: "https://auth.example.com"}
				runtime.manifest.SignedSession = &config
				resolved := saveUsableSignedSession(t, runtime, config, "sess-retry-mode")
				waitsBefore := waitCalls

				call := goja.FunctionCall{Arguments: []goja.Value{
					runtime.vm.ToValue("POST"),
					runtime.vm.ToValue("/tickets"),
				}}
				result := runtime.signedSessionFetch(call).Export().(map[string]any)
				if calls != 1 || waitCalls != waitsBefore {
					t.Fatalf("mode %q was replayed: calls=%d waits=%d", tc.wantMode, calls, waitCalls-waitsBefore)
				}
				if result["retryMode"] != tc.wantMode {
					t.Fatalf("retryMode = %v, want %q: %+v", result["retryMode"], tc.wantMode, result)
				}
				reloaded, err := runtime.loadSignedSession(resolved)
				if err != nil {
					t.Fatal(err)
				}
				if reloaded.SessionID != "sess-retry-mode" {
					t.Fatalf("mode %q changed gateway session: %+v", tc.wantMode, reloaded)
				}
			})
		}
	})

	t.Run("temporary provider failure retries with Retry-After", func(t *testing.T) {
		previousWait := signedSessionProviderWait
		previousNow := signedSessionRequestNow
		var waits []time.Duration
		signedSessionProviderWait = func(_ context.Context, delay time.Duration) error {
			waits = append(waits, delay)
			return nil
		}
		nextRequestTime := time.Date(2026, time.July, 30, 12, 0, 0, 0, time.UTC)
		signedSessionRequestNow = func() time.Time {
			current := nextRequestTime
			nextRequestTime = nextRequestTime.Add(time.Second)
			return current
		}
		t.Cleanup(func() {
			signedSessionProviderWait = previousWait
			signedSessionRequestNow = previousNow
		})

		calls := 0
		nonces := make(map[string]struct{})
		timestamps := make(map[string]struct{})
		signatures := make(map[string]struct{})
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			calls++
			nonces[req.Header.Get("X-Sig-Nonce")] = struct{}{}
			timestamps[req.Header.Get("X-Sig-Timestamp")] = struct{}{}
			signatures[req.Header.Get("X-Sig-Signature")] = struct{}{}
			if calls <= signedSessionMaxProviderRetries {
				return &http.Response{
					StatusCode: http.StatusServiceUnavailable,
					Header:     http.Header{"Retry-After": []string{"10"}},
					Body: io.NopCloser(strings.NewReader(
						`{"error":"Provider temporarily unavailable","code":"PROVIDER_UNAVAILABLE","origin":"provider","retryable":true,"retry_mode":"same_operation","retry_after_seconds":30}`,
					)),
					Request: req,
				}, nil
			}
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(`{"ok":true}`)),
				Request:    req,
			}, nil
		})
		runtime := newSignedSessionTestRuntime(t, "provider-unavailable", transport)
		config := SignedSessionConfig{Namespace: "provider-unavailable", BaseURL: "https://auth.example.com"}
		runtime.manifest.SignedSession = &config
		resolved := saveUsableSignedSession(t, runtime, config, "sess-provider-retry")

		call := goja.FunctionCall{Arguments: []goja.Value{
			runtime.vm.ToValue("POST"),
			runtime.vm.ToValue("/tickets"),
		}}
		result := runtime.signedSessionFetch(call).Export().(map[string]any)
		if result["ok"] != true || calls != signedSessionMaxProviderRetries+1 {
			t.Fatalf("provider retry did not recover: calls=%d result=%+v", calls, result)
		}
		if len(waits) != signedSessionMaxProviderRetries {
			t.Fatalf("provider retry waits = %v", waits)
		}
		for _, delay := range waits {
			if delay != 10*time.Second {
				t.Fatalf("Retry-After header was not authoritative: waits=%v", waits)
			}
		}
		wantSignedAttempts := signedSessionMaxProviderRetries + 1
		if len(nonces) != wantSignedAttempts ||
			len(timestamps) != wantSignedAttempts ||
			len(signatures) != wantSignedAttempts {
			t.Fatalf(
				"provider retries reused signed request headers: nonces=%d timestamps=%d signatures=%d want=%d",
				len(nonces),
				len(timestamps),
				len(signatures),
				wantSignedAttempts,
			)
		}
		reloaded, err := runtime.loadSignedSession(resolved)
		if err != nil {
			t.Fatal(err)
		}
		if reloaded.SessionID != "sess-provider-retry" {
			t.Fatalf("provider retry changed the gateway session: %+v", reloaded)
		}
	})

	t.Run("temporary provider retry budget is bounded", func(t *testing.T) {
		previousWait := signedSessionProviderWait
		signedSessionProviderWait = func(context.Context, time.Duration) error { return nil }
		t.Cleanup(func() { signedSessionProviderWait = previousWait })

		calls := 0
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			calls++
			return &http.Response{
				StatusCode: http.StatusServiceUnavailable,
				Header:     http.Header{"Retry-After": []string{"1"}},
				Body: io.NopCloser(strings.NewReader(
					`{"error":"Provider temporarily unavailable","code":"PROVIDER_UNAVAILABLE","origin":"provider","retryable":true,"retry_mode":"same_operation","retry_after_seconds":1}`,
				)),
				Request: req,
			}, nil
		})
		runtime := newSignedSessionTestRuntime(t, "provider-unavailable-bounded", transport)
		config := SignedSessionConfig{Namespace: "provider-unavailable-bounded", BaseURL: "https://auth.example.com"}
		runtime.manifest.SignedSession = &config
		resolved := saveUsableSignedSession(t, runtime, config, "sess-provider-bounded")

		call := goja.FunctionCall{Arguments: []goja.Value{
			runtime.vm.ToValue("POST"),
			runtime.vm.ToValue("/tickets"),
		}}
		result := runtime.signedSessionFetch(call).Export().(map[string]any)
		if calls != signedSessionMaxProviderRetries+1 {
			t.Fatalf("provider attempts = %d, want %d", calls, signedSessionMaxProviderRetries+1)
		}
		if result["code"] != "PROVIDER_UNAVAILABLE" || result["retryable"] != true {
			t.Fatalf("final provider failure was not returned intact: %+v", result)
		}
		reloaded, err := runtime.loadSignedSession(resolved)
		if err != nil {
			t.Fatal(err)
		}
		if reloaded.SessionID != "sess-provider-bounded" {
			t.Fatalf("exhausted provider retries changed the gateway session: %+v", reloaded)
		}
	})
}

func TestStaleSignedSession401RetriesWithoutClearingExchangedSession(t *testing.T) {
	oldRequestStarted := make(chan struct{})
	releaseOldRequest := make(chan struct{})
	var searchCalls atomic.Int32

	transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
		switch {
		case strings.HasSuffix(req.URL.Path, "/session/exchange"):
			payload, _ := json.Marshal(signedSessionExchangeResponse{
				SessionID:     "sess-new",
				SessionSecret: "secret-new",
				ExpiresAt:     time.Now().Add(time.Hour).UTC().Format(time.RFC3339),
			})
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(string(payload))),
				Request:    req,
			}, nil
		case strings.HasSuffix(req.URL.Path, "/tracks/search"):
			searchCalls.Add(1)
			if req.Header.Get("X-Sig-Session") == "sess-old" {
				close(oldRequestStarted)
				<-releaseOldRequest
				return &http.Response{
					StatusCode: http.StatusUnauthorized,
					Header:     make(http.Header),
					Body: io.NopCloser(strings.NewReader(
						`{"error":"Unauthorized","code":"SESSION_INVALID","origin":"gateway","action":"bootstrap_session"}`,
					)),
					Request: req,
				}, nil
			}
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(`{"ok":true}`)),
				Request:    req,
			}, nil
		default:
			t.Fatalf("unexpected request: %s", req.URL.String())
			return nil, nil
		}
	})

	root := t.TempDir()
	config := &SignedSessionConfig{
		Namespace: "shared-stale-session",
		BaseURL:   "https://auth.example.com",
	}
	newRuntime := func(extensionID string) *extensionRuntime {
		return &extensionRuntime{
			extensionID: extensionID,
			manifest: &ExtensionManifest{
				Name:          extensionID,
				SignedSession: config,
			},
			dataDir:    filepath.Join(root, extensionID),
			vm:         goja.New(),
			httpClient: &http.Client{Transport: transport},
		}
	}
	runtimeA := newRuntime("download-a")
	runtimeB := newRuntime("download-b")
	resolved := signedSessionConfigWithDefaults(config)
	record, err := runtimeA.loadSignedSession(resolved)
	if err != nil {
		t.Fatal(err)
	}
	record.SessionID = "sess-old"
	record.SessionSecret = "secret-old"
	record.ExpiresAt = time.Now().Add(time.Hour).UTC().Format(time.RFC3339)
	if err := runtimeA.saveSignedSession(resolved, record); err != nil {
		t.Fatal(err)
	}

	resultCh := make(chan map[string]any, 1)
	go func() {
		call := goja.FunctionCall{Arguments: []goja.Value{
			runtimeA.vm.ToValue("GET"),
			runtimeA.vm.ToValue("/tracks/search"),
		}}
		resultCh <- runtimeA.signedSessionFetch(call).Export().(map[string]any)
	}()
	<-oldRequestStarted
	if err := runtimeB.exchangeSignedSessionGrant("grant-new"); err != nil {
		t.Fatalf("exchange grant: %v", err)
	}
	close(releaseOldRequest)

	result := <-resultCh
	if result["ok"] != true {
		t.Fatalf("stale request was not retried with the new session: %+v", result)
	}
	if got := searchCalls.Load(); got != 2 {
		t.Fatalf("signed search calls = %d, want stale request plus one retry", got)
	}
	reloaded, err := runtimeA.loadSignedSession(resolved)
	if err != nil {
		t.Fatal(err)
	}
	if reloaded.SessionID != "sess-new" || reloaded.SessionSecret != "secret-new" {
		t.Fatalf("stale 401 overwrote exchanged session: %+v", reloaded)
	}
}

func TestExchangeSignedSessionGrant(t *testing.T) {
	t.Run("success stores the exchanged session", func(t *testing.T) {
		calls := 0
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			calls++
			if !strings.HasSuffix(req.URL.Path, "/session/exchange") {
				t.Fatalf("unexpected path: %s", req.URL.Path)
			}
			payload := signedSessionExchangeResponse{SessionID: "sess-9", SessionSecret: "secret-9", ExpiresAt: "2030-01-01T00:00:00Z"}
			body, _ := json.Marshal(payload)
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(string(body))), Request: req}, nil
		})
		runtime := newSignedSessionTestRuntime(t, "tidal-ext", transport)
		runtime.manifest.SignedSession = &SignedSessionConfig{Namespace: "tidal", BaseURL: "https://auth.example.com"}

		if err := runtime.exchangeSignedSessionGrant("grant-token"); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if err := runtime.exchangeSignedSessionGrant("grant-token"); err != nil {
			t.Fatalf("duplicate callback was not idempotent: %v", err)
		}
		if calls != 1 {
			t.Fatalf("duplicate grant exchange calls = %d, want 1", calls)
		}

		config := signedSessionConfigWithDefaults(runtime.manifest.SignedSession)
		record, err := runtime.loadSignedSession(config)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if record.SessionID != "sess-9" || record.SessionSecret != "secret-9" {
			t.Fatalf("session was not persisted after exchange: %+v", record)
		}
	})

	t.Run("non-2xx response is surfaced as an error", func(t *testing.T) {
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: 400, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{}`)), Request: req}, nil
		})
		runtime := newSignedSessionTestRuntime(t, "tidal-ext", transport)
		runtime.manifest.SignedSession = &SignedSessionConfig{Namespace: "tidal", BaseURL: "https://auth.example.com"}

		if err := runtime.exchangeSignedSessionGrant("bad-grant"); err == nil {
			t.Fatal("expected an error for a non-2xx exchange response")
		}
	})

	t.Run("429 preserves the grant and retries after the server delay", func(t *testing.T) {
		pendingSignedSessionGrantsMu.Lock()
		pendingSignedSessionGrants = make(map[string]string)
		pendingSignedSessionGrantsMu.Unlock()
		previousWait := signedSessionRetryWait
		var waits []time.Duration
		signedSessionRetryWait = func(delay time.Duration) {
			waits = append(waits, delay)
		}
		t.Cleanup(func() { signedSessionRetryWait = previousWait })

		calls := 0
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			calls++
			if calls == 1 {
				return &http.Response{
					StatusCode: http.StatusTooManyRequests,
					Header:     http.Header{"Retry-After": []string{"7"}},
					Body:       io.NopCloser(strings.NewReader(`{}`)),
					Request:    req,
				}, nil
			}
			payload, _ := json.Marshal(signedSessionExchangeResponse{
				SessionID:     "sess-after-429",
				SessionSecret: "secret-after-429",
				ExpiresAt:     "2030-01-01T00:00:00Z",
			})
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(string(payload))),
				Request:    req,
			}, nil
		})
		runtime := newSignedSessionTestRuntime(t, "tidal-rate-limit", transport)
		runtime.manifest.SignedSession = &SignedSessionConfig{
			Namespace: "tidal-rate-limit",
			BaseURL:   "https://auth.example.com",
		}
		setPendingSignedSessionGrant(runtime.extensionID, "grant-preserved")

		result := runtime.signedSessionCompleteGrant(goja.FunctionCall{}).Export().(map[string]any)
		if result["success"] != true {
			t.Fatalf("grant exchange did not recover from 429: %+v", result)
		}
		if calls != 2 {
			t.Fatalf("exchange calls = %d, want 2", calls)
		}
		if len(waits) != 1 || waits[0] != 7*time.Second {
			t.Fatalf("exchange retry waits = %v, want [7s]", waits)
		}
		pendingSignedSessionGrantsMu.Lock()
		_, stillPending := pendingSignedSessionGrants[runtime.extensionID]
		pendingSignedSessionGrantsMu.Unlock()
		if stillPending {
			t.Fatal("grant was not cleared after successful retry")
		}
	})

	t.Run("exhausted 429 retries keep the grant for a later retry", func(t *testing.T) {
		pendingSignedSessionGrantsMu.Lock()
		pendingSignedSessionGrants = make(map[string]string)
		pendingSignedSessionGrantsMu.Unlock()
		previousWait := signedSessionRetryWait
		signedSessionRetryWait = func(time.Duration) {}
		t.Cleanup(func() { signedSessionRetryWait = previousWait })

		calls := 0
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			calls++
			return &http.Response{
				StatusCode: http.StatusTooManyRequests,
				Header:     http.Header{"Retry-After": []string{"3"}},
				Body:       io.NopCloser(strings.NewReader(`{}`)),
				Request:    req,
			}, nil
		})
		runtime := newSignedSessionTestRuntime(t, "tidal-rate-limit-exhausted", transport)
		runtime.manifest.SignedSession = &SignedSessionConfig{
			Namespace: "tidal-rate-limit-exhausted",
			BaseURL:   "https://auth.example.com",
		}
		setPendingSignedSessionGrant(runtime.extensionID, "grant-retry-later")

		result := runtime.signedSessionCompleteGrant(goja.FunctionCall{}).Export().(map[string]any)
		if result["success"] != false {
			t.Fatalf("exhausted rate limit unexpectedly succeeded: %+v", result)
		}
		if calls != signedSessionExchangeMaxAttempts {
			t.Fatalf("exchange calls = %d, want %d", calls, signedSessionExchangeMaxAttempts)
		}
		pendingSignedSessionGrantsMu.Lock()
		pendingGrant := pendingSignedSessionGrants[runtime.extensionID]
		pendingSignedSessionGrantsMu.Unlock()
		if pendingGrant != "grant-retry-later" {
			t.Fatalf("pending grant = %q, want it preserved for retry", pendingGrant)
		}
	})
}

func TestSetPendingSignedSessionGrant(t *testing.T) {
	pendingSignedSessionGrantsMu.Lock()
	pendingSignedSessionGrants = make(map[string]string)
	pendingSignedSessionGrantsMu.Unlock()

	setPendingSignedSessionGrant("  ext-a  ", "  grant-1  ")

	pendingSignedSessionGrantsMu.Lock()
	got := pendingSignedSessionGrants["ext-a"]
	pendingSignedSessionGrantsMu.Unlock()

	if got != "grant-1" {
		t.Fatalf("expected trimmed grant to be stored, got %q", got)
	}

	setPendingSignedSessionGrant("", "grant-2")
	setPendingSignedSessionGrant("ext-b", "")

	pendingSignedSessionGrantsMu.Lock()
	_, hasEmptyExt := pendingSignedSessionGrants[""]
	_, hasEmptyGrant := pendingSignedSessionGrants["ext-b"]
	pendingSignedSessionGrantsMu.Unlock()

	if hasEmptyExt || hasEmptyGrant {
		t.Fatal("expected empty extensionID/grant pairs to be ignored")
	}
}

func TestRefreshSignedSession(t *testing.T) {
	t.Run("updates changed fields and persists them", func(t *testing.T) {
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			if !strings.HasSuffix(req.URL.Path, "/session/refresh") {
				t.Fatalf("unexpected path: %s", req.URL.Path)
			}
			payload := signedSessionExchangeResponse{SessionSecret: "rotated-secret", ExpiresAt: "2031-01-01T00:00:00Z"}
			body, _ := json.Marshal(payload)
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(string(body))), Request: req}, nil
		})
		runtime := newSignedSessionTestRuntime(t, "tidal-ext", transport)
		config := signedSessionConfigWithDefaults(&SignedSessionConfig{
			Namespace: "tidal", BaseURL: "https://auth.example.com",
			Endpoints: SignedSessionEndpoints{Refresh: "/session/refresh"},
		})
		record := &signedSessionRecord{InstallID: "install-1", SessionID: "sess-1", SessionSecret: "old-secret", ExpiresAt: "2030-01-01T00:00:00Z"}

		if err := runtime.refreshSignedSession(config, record); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if record.SessionSecret != "rotated-secret" || record.ExpiresAt != "2031-01-01T00:00:00Z" {
			t.Fatalf("refreshed fields not applied in-memory: %+v", record)
		}
		if record.SessionID != "sess-1" {
			t.Fatalf("session id should be untouched when the response omits it: %q", record.SessionID)
		}

		reloaded, err := runtime.loadSignedSession(config)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if reloaded.SessionSecret != "rotated-secret" {
			t.Fatalf("refresh was not persisted to disk: %+v", reloaded)
		}
	})

	t.Run("non-2xx response is surfaced as an error", func(t *testing.T) {
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: 500, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{}`)), Request: req}, nil
		})
		runtime := newSignedSessionTestRuntime(t, "tidal-ext", transport)
		config := signedSessionConfigWithDefaults(&SignedSessionConfig{
			Namespace: "tidal", BaseURL: "https://auth.example.com",
			Endpoints: SignedSessionEndpoints{Refresh: "/session/refresh"},
		})
		record := &signedSessionRecord{InstallID: "install-1", SessionID: "sess-1", SessionSecret: "old-secret"}

		if err := runtime.refreshSignedSession(config, record); err == nil {
			t.Fatal("expected an error for a non-2xx refresh response")
		}
	})
}

func TestSignedSessionCompleteGrant(t *testing.T) {
	t.Run("uses the grant argument when provided", func(t *testing.T) {
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			payload := signedSessionExchangeResponse{SessionID: "sess-arg", SessionSecret: "secret-arg", ExpiresAt: "2030-01-01T00:00:00Z"}
			body, _ := json.Marshal(payload)
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(string(body))), Request: req}, nil
		})
		runtime := newSignedSessionTestRuntime(t, "tidal-ext", transport)
		runtime.manifest.SignedSession = &SignedSessionConfig{Namespace: "tidal", BaseURL: "https://auth.example.com"}

		call := goja.FunctionCall{Arguments: []goja.Value{runtime.vm.ToValue("grant-from-arg")}}
		result := runtime.signedSessionCompleteGrant(call).Export().(map[string]any)
		if result["success"] != true {
			t.Fatalf("expected success, got %+v", result)
		}
	})

	t.Run("falls back to a pending grant registered out of band", func(t *testing.T) {
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
			payload := signedSessionExchangeResponse{SessionID: "sess-pending", SessionSecret: "secret-pending", ExpiresAt: "2030-01-01T00:00:00Z"}
			body, _ := json.Marshal(payload)
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(string(body))), Request: req}, nil
		})
		runtime := newSignedSessionTestRuntime(t, "tidal-ext-pending", transport)
		runtime.manifest.SignedSession = &SignedSessionConfig{Namespace: "tidal", BaseURL: "https://auth.example.com"}
		setPendingSignedSessionGrant(runtime.extensionID, "pending-grant")

		result := runtime.signedSessionCompleteGrant(goja.FunctionCall{}).Export().(map[string]any)
		if result["success"] != true {
			t.Fatalf("expected success, got %+v", result)
		}

		pendingSignedSessionGrantsMu.Lock()
		_, stillPending := pendingSignedSessionGrants[runtime.extensionID]
		pendingSignedSessionGrantsMu.Unlock()
		if stillPending {
			t.Fatal("expected the pending grant to be consumed after use")
		}
	})

	t.Run("no grant available reports failure", func(t *testing.T) {
		runtime := newSignedSessionTestRuntime(t, "tidal-ext-none", nil)
		result := runtime.signedSessionCompleteGrant(goja.FunctionCall{}).Export().(map[string]any)
		if result["success"] != false {
			t.Fatalf("expected failure without a grant, got %+v", result)
		}
	})
}

func TestBuildSignedSessionChallengeURL(t *testing.T) {
	config := signedSessionConfigWithDefaults(&SignedSessionConfig{
		Namespace:   "tidal",
		BaseURL:     "https://auth.example.com",
		CallbackURL: "spotiflac://session-grant",
	})
	runtime := newSignedSessionTestRuntime(t, "tidal-ext", nil)

	got := runtime.buildSignedSessionChallengeURL(config, "chal-123")

	if !strings.HasPrefix(got, "https://auth.example.com/challenge?") {
		t.Fatalf("unexpected base URL: %q", got)
	}
	if !strings.Contains(got, "id=chal-123") {
		t.Fatalf("expected challenge id in query: %q", got)
	}
	if !strings.Contains(got, "cb=spotiflac%3A%2F%2Fsession-grant") {
		t.Fatalf("expected encoded callback URL in query: %q", got)
	}
}
