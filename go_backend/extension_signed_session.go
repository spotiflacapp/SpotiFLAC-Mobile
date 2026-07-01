package gobackend

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/dop251/goja"
)

const signedSessionRefreshSkew = time.Hour

var (
	pendingSignedSessionGrants   = make(map[string]string)
	pendingSignedSessionGrantsMu sync.Mutex
)

type signedSessionRecord struct {
	InstallID     string `json:"install_id"`
	SessionID     string `json:"session_id,omitempty"`
	SessionSecret string `json:"session_secret,omitempty"`
	ExpiresAt     string `json:"expires_at,omitempty"`
	Namespace     string `json:"namespace,omitempty"`
	BaseURL       string `json:"base_url,omitempty"`
	AppVersion    string `json:"app_version,omitempty"`
	Platform      string `json:"platform,omitempty"`
}

type signedSessionExchangeResponse struct {
	SessionID     string `json:"session_id,omitempty"`
	SessionSecret string `json:"session_secret,omitempty"`
	ExpiresAt     string `json:"expires_at,omitempty"`
	ChallengeID   string `json:"challenge_id,omitempty"`
	ChallengeURL  string `json:"challenge_url,omitempty"`
	AuthURL       string `json:"auth_url,omitempty"`
}

func signedSessionConfigWithDefaults(config *SignedSessionConfig) SignedSessionConfig {
	if config == nil {
		return SignedSessionConfig{}
	}
	resolved := *config
	if resolved.AppVersion == "" {
		resolved.AppVersion = "ext-1.0"
	}
	if resolved.Platform == "" {
		resolved.Platform = "extension"
	}
	if resolved.CallbackURL == "" {
		resolved.CallbackURL = "spotiflac://session-grant"
	}
	if resolved.SchemeLabel == "" {
		resolved.SchemeLabel = "SPOTIFLAC-HMAC-V1"
	}
	if resolved.HeaderPrefix == "" {
		resolved.HeaderPrefix = "X-Sig-"
	}
	if resolved.TimeWindowSeconds <= 0 {
		resolved.TimeWindowSeconds = 300
	}
	if resolved.Endpoints.Bootstrap == "" {
		resolved.Endpoints.Bootstrap = "/bootstrap"
	}
	if resolved.Endpoints.Challenge == "" {
		resolved.Endpoints.Challenge = "/challenge"
	}
	if resolved.Endpoints.Exchange == "" {
		resolved.Endpoints.Exchange = "/session/exchange"
	}
	return resolved
}

func (r *extensionRuntime) signedSessionFilePath(config SignedSessionConfig) (string, error) {
	namespace := sanitizeSignedSessionNamespace(config.Namespace)
	if namespace == "" {
		return "", fmt.Errorf("signed session namespace is empty")
	}
	baseDir := filepath.Dir(r.dataDir)
	if baseDir == "." || baseDir == "" {
		baseDir = r.dataDir
	}
	dir := filepath.Join(baseDir, "signed_sessions")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return "", err
	}
	scope := strings.Join([]string{
		namespace,
		strings.TrimSpace(strings.ToLower(config.BaseURL)),
		strings.TrimSpace(strings.ToLower(config.AppVersion)),
		strings.TrimSpace(strings.ToLower(config.Platform)),
	}, "\n")
	sum := sha256.Sum256([]byte(scope))
	return filepath.Join(dir, namespace+"-"+hex.EncodeToString(sum[:])[:16]+".json"), nil
}

func sanitizeSignedSessionNamespace(namespace string) string {
	namespace = strings.TrimSpace(strings.ToLower(namespace))
	var b strings.Builder
	for _, ch := range namespace {
		if (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '_' || ch == '.' {
			b.WriteRune(ch)
		}
	}
	return strings.Trim(b.String(), ".-_")
}

func (r *extensionRuntime) loadSignedSession(config SignedSessionConfig) (*signedSessionRecord, error) {
	path, err := r.signedSessionFilePath(config)
	if err != nil {
		return nil, err
	}
	record := &signedSessionRecord{}
	if data, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(data, record)
	}
	if strings.TrimSpace(record.InstallID) == "" {
		record.InstallID = randomHex(16)
	}
	normalizeSignedSessionRecordScope(config, record)
	if err := r.saveSignedSession(config, record); err != nil {
		return nil, err
	}
	return record, nil
}

func normalizeSignedSessionRecordScope(config SignedSessionConfig, record *signedSessionRecord) {
	namespace := sanitizeSignedSessionNamespace(config.Namespace)
	baseURL := strings.TrimSpace(config.BaseURL)
	appVersion := strings.TrimSpace(config.AppVersion)
	platform := strings.TrimSpace(config.Platform)
	if record.Namespace == "" && record.BaseURL == "" && record.AppVersion == "" && record.Platform == "" {
		record.Namespace = namespace
		record.BaseURL = baseURL
		record.AppVersion = appVersion
		record.Platform = platform
		return
	}
	if record.Namespace != namespace ||
		record.BaseURL != baseURL ||
		record.AppVersion != appVersion ||
		record.Platform != platform {
		record.SessionID = ""
		record.SessionSecret = ""
		record.ExpiresAt = ""
	}
	record.Namespace = namespace
	record.BaseURL = baseURL
	record.AppVersion = appVersion
	record.Platform = platform
}

func (r *extensionRuntime) saveSignedSession(config SignedSessionConfig, record *signedSessionRecord) error {
	path, err := r.signedSessionFilePath(config)
	if err != nil {
		return err
	}
	data, err := json.MarshalIndent(record, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}

func randomHex(bytesLen int) string {
	buf := make([]byte, bytesLen)
	if _, err := rand.Read(buf); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(buf)
}

func parseSignedSessionTime(value string) (time.Time, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return time.Time{}, false
	}
	layouts := []string{
		time.RFC3339Nano,
		time.RFC3339,
		"2006-01-02T15:04:05.000Z",
	}
	for _, layout := range layouts {
		if parsed, err := time.Parse(layout, value); err == nil {
			return parsed, true
		}
	}
	return time.Time{}, false
}

func (r *extensionRuntime) signedSessionStatus(call goja.FunctionCall) goja.Value {
	config := signedSessionConfigWithDefaults(r.manifest.SignedSession)
	if config.Namespace == "" || config.BaseURL == "" {
		return r.vm.ToValue(map[string]interface{}{"authenticated": false, "error": "signedSession is not configured"})
	}
	record, err := r.loadSignedSession(config)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{"authenticated": false, "error": err.Error()})
	}
	authenticated := record.SessionID != "" && record.SessionSecret != ""
	if expiresAt, ok := parseSignedSessionTime(record.ExpiresAt); ok && time.Now().After(expiresAt) {
		authenticated = false
	}
	return r.vm.ToValue(map[string]interface{}{
		"authenticated": authenticated,
		"expires_at":    record.ExpiresAt,
		"install_id":    record.InstallID,
		"session_id":    record.SessionID,
		"app_version":   config.AppVersion,
		"platform":      config.Platform,
	})
}

func (r *extensionRuntime) signedSessionClear(call goja.FunctionCall) goja.Value {
	config := signedSessionConfigWithDefaults(r.manifest.SignedSession)
	record, err := r.loadSignedSession(config)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{"success": false, "error": err.Error()})
	}
	record.SessionID = ""
	record.SessionSecret = ""
	record.ExpiresAt = ""
	if err := r.saveSignedSession(config, record); err != nil {
		return r.vm.ToValue(map[string]interface{}{"success": false, "error": err.Error()})
	}
	ClearPendingAuthRequest(r.extensionID)
	return r.vm.ToValue(map[string]interface{}{"success": true})
}

func (r *extensionRuntime) signedSessionCompleteGrant(call goja.FunctionCall) goja.Value {
	grant := ""
	if len(call.Arguments) > 0 {
		grant = strings.TrimSpace(call.Arguments[0].String())
	}
	if grant == "" {
		pendingSignedSessionGrantsMu.Lock()
		grant = pendingSignedSessionGrants[r.extensionID]
		delete(pendingSignedSessionGrants, r.extensionID)
		pendingSignedSessionGrantsMu.Unlock()
	}
	if grant == "" {
		return r.vm.ToValue(map[string]interface{}{"success": false, "error": "no pending grant"})
	}
	if err := r.exchangeSignedSessionGrant(grant); err != nil {
		return r.vm.ToValue(map[string]interface{}{"success": false, "error": err.Error()})
	}
	ClearPendingAuthRequest(r.extensionID)
	return r.vm.ToValue(map[string]interface{}{"success": true})
}

func (r *extensionRuntime) exchangeSignedSessionGrant(grant string) error {
	config := signedSessionConfigWithDefaults(r.manifest.SignedSession)
	record, err := r.loadSignedSession(config)
	if err != nil {
		return err
	}
	endpoint, err := signedSessionURL(config, config.Endpoints.Exchange)
	if err != nil {
		return err
	}
	payload := map[string]interface{}{
		"grant":       grant,
		"install_id":  record.InstallID,
		"app_version": config.AppVersion,
		"platform":    config.Platform,
	}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "SpotiFLAC-Mobile/"+config.AppVersion)
	resp, err := r.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	respBody, err := readExtensionHTTPResponseBody(resp)
	if err != nil {
		return err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("session exchange failed: HTTP %d", resp.StatusCode)
	}
	var exchanged signedSessionExchangeResponse
	if err := json.Unmarshal(respBody, &exchanged); err != nil {
		return fmt.Errorf("invalid session exchange response: %w", err)
	}
	if exchanged.SessionID == "" || exchanged.SessionSecret == "" || exchanged.ExpiresAt == "" {
		return fmt.Errorf("session exchange response missing session fields")
	}
	record.SessionID = exchanged.SessionID
	record.SessionSecret = exchanged.SessionSecret
	record.ExpiresAt = exchanged.ExpiresAt
	return r.saveSignedSession(config, record)
}

func (r *extensionRuntime) signedSessionFetch(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.vm.ToValue(map[string]interface{}{"ok": false, "error": "method and path are required"})
	}
	config := signedSessionConfigWithDefaults(r.manifest.SignedSession)
	if config.Namespace == "" || config.BaseURL == "" {
		return r.vm.ToValue(map[string]interface{}{"ok": false, "error": "signedSession is not configured"})
	}
	method := strings.ToUpper(strings.TrimSpace(call.Arguments[0].String()))
	requestPath := call.Arguments[1].String()
	body := []byte{}
	if len(call.Arguments) > 2 && !goja.IsUndefined(call.Arguments[2]) && !goja.IsNull(call.Arguments[2]) {
		switch v := call.Arguments[2].Export().(type) {
		case string:
			body = []byte(v)
		case map[string]interface{}, []interface{}:
			encoded, err := json.Marshal(v)
			if err != nil {
				return r.vm.ToValue(map[string]interface{}{"ok": false, "error": err.Error()})
			}
			body = encoded
		default:
			body = []byte(call.Arguments[2].String())
		}
	}
	extraHeaders := map[string]string{}
	if len(call.Arguments) > 3 && !goja.IsUndefined(call.Arguments[3]) && !goja.IsNull(call.Arguments[3]) {
		if h, ok := call.Arguments[3].Export().(map[string]interface{}); ok {
			for k, v := range h {
				extraHeaders[k] = fmt.Sprintf("%v", v)
			}
		}
	}

	record, err := r.ensureSignedSession(config)
	if err != nil {
		if authURL := r.startSignedSessionVerification(config, ""); authURL != "" {
			return r.signedSessionVerificationRequiredValue(authURL)
		}
		return r.vm.ToValue(map[string]interface{}{"ok": false, "error": err.Error()})
	}

	resp, respBody, respHeaders, err := r.doSignedSessionRequest(config, record, method, requestPath, body, extraHeaders)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{"ok": false, "error": err.Error()})
	}
	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusPreconditionRequired {
		record.SessionID = ""
		record.SessionSecret = ""
		record.ExpiresAt = ""
		_ = r.saveSignedSession(config, record)
		if authURL := r.startSignedSessionVerification(config, ""); authURL != "" {
			return r.signedSessionVerificationRequiredValue(authURL)
		}
	}
	return r.vm.ToValue(map[string]interface{}{
		"statusCode":        resp.StatusCode,
		"status":            resp.StatusCode,
		"ok":                resp.StatusCode >= 200 && resp.StatusCode < 300,
		"url":               resp.Request.URL.String(),
		"body":              string(respBody),
		"headers":           respHeaders,
		"retryAfterSeconds": signedSessionRetryAfterSeconds(resp),
	})
}

func (r *extensionRuntime) signedSessionVerificationRequiredValue(authURL string) goja.Value {
	return r.vm.ToValue(map[string]interface{}{
		"ok":                false,
		"needsVerification": true,
		"error":             "VERIFY_REQUIRED",
		"open_auth_url":     authURL,
		"auth_url":          authURL,
	})
}

func (r *extensionRuntime) ensureSignedSession(config SignedSessionConfig) (*signedSessionRecord, error) {
	record, err := r.loadSignedSession(config)
	if err != nil {
		return nil, err
	}
	if record.SessionID == "" || record.SessionSecret == "" {
		return nil, fmt.Errorf("signed session is not authenticated")
	}
	if expiresAt, ok := parseSignedSessionTime(record.ExpiresAt); ok {
		if time.Now().After(expiresAt) {
			record.SessionID = ""
			record.SessionSecret = ""
			record.ExpiresAt = ""
			_ = r.saveSignedSession(config, record)
			return nil, fmt.Errorf("signed session expired")
		}
		if config.Endpoints.Refresh != "" && time.Until(expiresAt) <= signedSessionRefreshSkew {
			_ = r.refreshSignedSession(config, record)
		}
	}
	return record, nil
}

func (r *extensionRuntime) refreshSignedSession(config SignedSessionConfig, record *signedSessionRecord) error {
	body, _ := json.Marshal(map[string]string{"install_id": record.InstallID})
	resp, respBody, _, err := r.doSignedSessionRequest(config, record, http.MethodPost, config.Endpoints.Refresh, body, nil)
	if err != nil {
		return err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("session refresh failed: HTTP %d", resp.StatusCode)
	}
	var refreshed signedSessionExchangeResponse
	if err := json.Unmarshal(respBody, &refreshed); err != nil {
		return err
	}
	changed := false
	if refreshed.SessionID != "" {
		record.SessionID = refreshed.SessionID
		changed = true
	}
	if refreshed.SessionSecret != "" {
		record.SessionSecret = refreshed.SessionSecret
		changed = true
	}
	if refreshed.ExpiresAt != "" && refreshed.ExpiresAt != record.ExpiresAt {
		record.ExpiresAt = refreshed.ExpiresAt
		changed = true
	}
	if changed {
		return r.saveSignedSession(config, record)
	}
	return nil
}

func (r *extensionRuntime) startSignedSessionVerification(config SignedSessionConfig, reason string) string {
	record, err := r.loadSignedSession(config)
	if err != nil {
		return ""
	}
	bootstrapURL, err := signedSessionURL(config, config.Endpoints.Bootstrap)
	if err != nil {
		return ""
	}
	parsed, _ := url.Parse(bootstrapURL)
	query := parsed.Query()
	query.Set("app_version", config.AppVersion)
	query.Set("install_id", record.InstallID)
	parsed.RawQuery = query.Encode()
	req, err := http.NewRequest(http.MethodGet, parsed.String(), nil)
	if err != nil {
		return ""
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "SpotiFLAC-Mobile/"+config.AppVersion)
	resp, err := r.httpClient.Do(req)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxExtensionHTTPResponseBytes))
	if err != nil || resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return ""
	}
	var boot signedSessionExchangeResponse
	if err := json.Unmarshal(body, &boot); err != nil {
		return ""
	}
	if boot.SessionID != "" && boot.SessionSecret != "" && boot.ExpiresAt != "" {
		record.SessionID = boot.SessionID
		record.SessionSecret = boot.SessionSecret
		record.ExpiresAt = boot.ExpiresAt
		_ = r.saveSignedSession(config, record)
		return ""
	}
	authURL := boot.AuthURL
	if authURL == "" && boot.ChallengeURL != "" {
		authURL = boot.ChallengeURL
	}
	if authURL == "" && boot.ChallengeID != "" {
		authURL = r.buildSignedSessionChallengeURL(config, boot.ChallengeID)
	}
	if authURL != "" {
		pendingAuthRequestsMu.Lock()
		pendingAuthRequests[r.extensionID] = &PendingAuthRequest{
			ExtensionID: r.extensionID,
			AuthURL:     authURL,
			CallbackURL: config.CallbackURL,
		}
		pendingAuthRequestsMu.Unlock()
	}
	return authURL
}

func (r *extensionRuntime) buildSignedSessionChallengeURL(config SignedSessionConfig, challengeID string) string {
	challengeURL, err := signedSessionURL(config, config.Endpoints.Challenge)
	if err != nil {
		return ""
	}
	parsed, err := url.Parse(challengeURL)
	if err != nil {
		return ""
	}
	callback, err := url.Parse(config.CallbackURL)
	if err != nil {
		return ""
	}
	q := callback.Query()
	q.Set("cb_version", "v2grant")
	q.Set("state", r.extensionID)
	callback.RawQuery = q.Encode()

	query := parsed.Query()
	query.Set("id", challengeID)
	query.Set("cb", callback.String())
	parsed.RawQuery = query.Encode()
	return parsed.String()
}

func signedSessionURL(config SignedSessionConfig, endpoint string) (string, error) {
	base, err := url.Parse(strings.TrimRight(config.BaseURL, "/") + "/")
	if err != nil || base.Scheme != "https" || base.Host == "" {
		return "", fmt.Errorf("invalid signed session baseUrl")
	}
	endpoint = strings.TrimSpace(endpoint)
	if endpoint == "" {
		return "", fmt.Errorf("signed session endpoint is empty")
	}
	if strings.HasPrefix(endpoint, "https://") {
		return endpoint, nil
	}
	endpoint = strings.TrimLeft(endpoint, "/")
	ref, _ := url.Parse(endpoint)
	return base.ResolveReference(ref).String(), nil
}

func (r *extensionRuntime) doSignedSessionRequest(
	config SignedSessionConfig,
	record *signedSessionRecord,
	method string,
	requestPath string,
	body []byte,
	extraHeaders map[string]string,
) (*http.Response, []byte, map[string]interface{}, error) {
	fullURL, err := signedSessionURL(config, requestPath)
	if err != nil {
		return nil, nil, nil, err
	}
	parsed, err := url.Parse(fullURL)
	if err != nil {
		return nil, nil, nil, err
	}
	ts := time.Now().UTC().Format("2006-01-02T15:04:05.000Z")
	nonce := randomHex(12)
	bodyHashBytes := sha256.Sum256(body)
	bodyHash := hex.EncodeToString(bodyHashBytes[:])
	parsedTs, _ := time.Parse("2006-01-02T15:04:05.000Z", ts)
	window := parsedTs.Unix() / int64(config.TimeWindowSeconds)
	rollingInput := fmt.Sprintf("%d:%s", window, record.SessionID)
	rk := base64.RawURLEncoding.EncodeToString(hmacSHA256Bytes([]byte(record.SessionSecret), []byte(rollingInput)))
	signingInput := strings.Join([]string{
		config.SchemeLabel,
		method,
		parsed.EscapedPath(),
		"",
		bodyHash,
		ts,
		nonce,
		record.SessionID,
		config.AppVersion,
		config.Platform,
	}, "\n")
	sig := base64.RawURLEncoding.EncodeToString(hmacSHA256Bytes([]byte(rk), []byte(signingInput)))

	req, err := http.NewRequest(method, fullURL, bytes.NewReader(body))
	if err != nil {
		return nil, nil, nil, err
	}
	req = r.bindDownloadCancelContext(req)
	req.Header.Set("Accept", "application/json")
	if len(body) > 0 {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("User-Agent", "SpotiFLAC-Mobile/"+config.AppVersion)
	prefix := config.HeaderPrefix
	req.Header.Set(prefix+"Session", record.SessionID)
	req.Header.Set(prefix+"Timestamp", ts)
	req.Header.Set(prefix+"Nonce", nonce)
	req.Header.Set(prefix+"Body-SHA256", bodyHash)
	req.Header.Set(prefix+"Signature", sig)
	req.Header.Set(prefix+"App-Version", config.AppVersion)
	req.Header.Set(prefix+"Platform", config.Platform)
	for k, v := range extraHeaders {
		req.Header.Set(k, v)
	}

	resp, err := r.httpClient.Do(req)
	if err != nil {
		return nil, nil, nil, err
	}
	defer resp.Body.Close()
	respBody, err := readExtensionHTTPResponseBody(resp)
	if err != nil {
		return nil, nil, nil, err
	}
	headers := make(map[string]interface{})
	for k, v := range resp.Header {
		if len(v) == 1 {
			headers[k] = v[0]
		} else {
			headers[k] = v
		}
	}
	return resp, respBody, headers, nil
}

func signedSessionRetryAfterSeconds(resp *http.Response) int {
	if resp == nil {
		return 0
	}
	value := strings.TrimSpace(resp.Header.Get("Retry-After"))
	if value == "" {
		return 0
	}
	if seconds, err := strconv.Atoi(value); err == nil {
		if seconds < 0 {
			return 0
		}
		return seconds
	}
	if retryAt, err := http.ParseTime(value); err == nil {
		seconds := int(time.Until(retryAt).Seconds())
		if seconds < 0 {
			return 0
		}
		return seconds
	}
	return 0
}

func hmacSHA256Bytes(key, message []byte) []byte {
	mac := hmac.New(sha256.New, key)
	mac.Write(message)
	return mac.Sum(nil)
}

func setPendingSignedSessionGrant(extensionID, grant string) {
	extensionID = strings.TrimSpace(extensionID)
	grant = strings.TrimSpace(grant)
	if extensionID == "" || grant == "" {
		return
	}
	pendingSignedSessionGrantsMu.Lock()
	pendingSignedSessionGrants[extensionID] = grant
	pendingSignedSessionGrantsMu.Unlock()
}
