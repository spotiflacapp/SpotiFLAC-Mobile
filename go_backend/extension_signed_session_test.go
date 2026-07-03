package gobackend

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
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
	if perm := info.Mode().Perm(); perm != 0o600 {
		t.Errorf("session file perm = %o, want 0600", perm)
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

	readStatus := func() map[string]interface{} {
		v := runtime.signedSessionStatus(goja.FunctionCall{})
		return v.Export().(map[string]interface{})
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
	clearResult := runtime.signedSessionClear(goja.FunctionCall{}).Export().(map[string]interface{})
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
	result := runtime.signedSessionFetch(call).Export().(map[string]interface{})

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

func TestSignedSessionFetchRevokesSessionOn401(t *testing.T) {
	calls := 0
	transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
		calls++
		switch {
		case strings.Contains(req.URL.Path, "/bootstrap"):
			payload := signedSessionExchangeResponse{AuthURL: "https://auth.example.com/login"}
			body, _ := json.Marshal(payload)
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(string(body))), Request: req}, nil
		default:
			return &http.Response{StatusCode: http.StatusUnauthorized, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{}`)), Request: req}, nil
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
	result := runtime.signedSessionFetch(call).Export().(map[string]interface{})
	if result["ok"] != false || result["needsVerification"] != true {
		t.Fatalf("expected a verification-required response after 401, got %+v", result)
	}

	reloaded, err := runtime.loadSignedSession(resolved)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if reloaded.SessionID != "" || reloaded.SessionSecret != "" {
		t.Fatalf("expected session to be wiped after 401, got %+v", reloaded)
	}
}

func TestExchangeSignedSessionGrant(t *testing.T) {
	t.Run("success stores the exchanged session", func(t *testing.T) {
		transport := roundTripFunc(func(req *http.Request) (*http.Response, error) {
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
		result := runtime.signedSessionCompleteGrant(call).Export().(map[string]interface{})
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

		result := runtime.signedSessionCompleteGrant(goja.FunctionCall{}).Export().(map[string]interface{})
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
		result := runtime.signedSessionCompleteGrant(goja.FunctionCall{}).Export().(map[string]interface{})
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
