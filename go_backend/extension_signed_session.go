package gobackend

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
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

const (
	signedSessionExchangeMaxAttempts = 3
	signedSessionMaxRetryAfter       = 5 * time.Minute
	signedSessionMaxSessionRetries   = 1
	signedSessionMaxProviderRetries  = 2
	signedSessionProviderRetryDelay  = time.Second
)

var (
	pendingSignedSessionGrants   = make(map[string]string)
	pendingSignedSessionGrantsMu sync.Mutex
	signedSessionCoordinators    sync.Map
	signedSessionRetryWait       = time.Sleep
	signedSessionProviderWait    = sleepRetry
	signedSessionRequestNow      = time.Now
)

// signedSessionCoordinator serializes authentication state for every runtime
// that shares one persisted signed-session file. Parallel downloads use
// isolated extension runtimes, so a runtime-local mutex cannot prevent two
// bootstraps or an old 401 response from overwriting a newly exchanged session.
type signedSessionCoordinator struct {
	mu sync.Mutex

	authURL             string
	callbackURL         string
	challengeCreatedAt  time.Time
	pendingExtensionIDs map[string]struct{}
	completedGrantHash  string
	blockedGeneration   string
}

func (r *extensionRuntime) signedSessionCoordinator(config SignedSessionConfig) (*signedSessionCoordinator, error) {
	path, err := r.signedSessionFilePath(config)
	if err != nil {
		return nil, err
	}
	value, _ := signedSessionCoordinators.LoadOrStore(path, &signedSessionCoordinator{})
	return value.(*signedSessionCoordinator), nil
}

func (c *signedSessionCoordinator) clearChallenge() {
	for extensionID := range c.pendingExtensionIDs {
		ClearPendingAuthRequest(extensionID)
	}
	c.authURL = ""
	c.callbackURL = ""
	c.challengeCreatedAt = time.Time{}
	c.pendingExtensionIDs = nil
}

func (c *signedSessionCoordinator) rememberChallenge(extensionID, authURL, callbackURL string) {
	if c.pendingExtensionIDs == nil {
		c.pendingExtensionIDs = make(map[string]struct{})
	}
	c.authURL = authURL
	c.callbackURL = callbackURL
	c.challengeCreatedAt = time.Now()
	c.pendingExtensionIDs[extensionID] = struct{}{}
}

func (c *signedSessionCoordinator) activeChallenge() bool {
	return strings.TrimSpace(c.authURL) != "" &&
		!c.challengeCreatedAt.IsZero() &&
		time.Since(c.challengeCreatedAt) < pendingAuthRequestTTL
}

func signedSessionGeneration(record *signedSessionRecord) string {
	if record == nil || record.SessionID == "" || record.SessionSecret == "" {
		return ""
	}
	sum := sha256.Sum256([]byte(record.SessionID + "\n" + record.SessionSecret))
	return hex.EncodeToString(sum[:])
}

func (c *signedSessionCoordinator) blockGeneration(record *signedSessionRecord) {
	c.blockedGeneration = signedSessionGeneration(record)
}

func (c *signedSessionCoordinator) generationIsBlocked(record *signedSessionRecord) bool {
	generation := signedSessionGeneration(record)
	return generation != "" && generation == c.blockedGeneration
}

func (c *signedSessionCoordinator) clearBlockedGeneration() {
	c.blockedGeneration = ""
}

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

// signedSessionErrorContract is the gateway-owned error envelope. Decisions
// that mutate authentication state must use these fields together with the
// HTTP status; a provider response must never be able to masquerade as a
// gateway session failure merely by returning 401 or 403 upstream.
type signedSessionErrorContract struct {
	Error             string `json:"error,omitempty"`
	Code              string `json:"code,omitempty"`
	Origin            string `json:"origin,omitempty"`
	Action            string `json:"action,omitempty"`
	Retryable         bool   `json:"retryable,omitempty"`
	RetryMode         string `json:"retry_mode,omitempty"`
	RetryAfterSeconds int    `json:"retry_after_seconds,omitempty"`
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
	changed := false
	if strings.TrimSpace(record.InstallID) == "" {
		record.InstallID = randomHex(16)
		changed = true
	}
	if normalizeSignedSessionRecordScope(config, record) {
		changed = true
	}
	// Only rewrite the file when the record actually changed; loads happen on
	// every signed request and preflight.
	if changed {
		if err := r.saveSignedSession(config, record); err != nil {
			return nil, err
		}
	}
	return record, nil
}

// normalizeSignedSessionRecordScope stamps the config scope onto the record,
// resetting the session when the scope changed. Returns whether the record
// was modified.
func normalizeSignedSessionRecordScope(config SignedSessionConfig, record *signedSessionRecord) bool {
	namespace := sanitizeSignedSessionNamespace(config.Namespace)
	baseURL := strings.TrimSpace(config.BaseURL)
	appVersion := strings.TrimSpace(config.AppVersion)
	platform := strings.TrimSpace(config.Platform)
	if record.Namespace == namespace &&
		record.BaseURL == baseURL &&
		record.AppVersion == appVersion &&
		record.Platform == platform {
		return false
	}
	blankScope := record.Namespace == "" && record.BaseURL == "" &&
		record.AppVersion == "" && record.Platform == ""
	if !blankScope {
		record.SessionID = ""
		record.SessionSecret = ""
		record.ExpiresAt = ""
	}
	record.Namespace = namespace
	record.BaseURL = baseURL
	record.AppVersion = appVersion
	record.Platform = platform
	return true
}

func (r *extensionRuntime) saveSignedSession(config SignedSessionConfig, record *signedSessionRecord) error {
	path, err := r.signedSessionFilePath(config)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
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

func signedSessionRecordIsUsable(record *signedSessionRecord) bool {
	if record == nil || strings.TrimSpace(record.SessionID) == "" || strings.TrimSpace(record.SessionSecret) == "" {
		return false
	}
	if expiresAt, ok := parseSignedSessionTime(record.ExpiresAt); ok {
		return time.Now().Before(expiresAt)
	}
	return true
}

func sameSignedSession(a, b *signedSessionRecord) bool {
	return a != nil && b != nil &&
		a.SessionID != "" &&
		a.SessionID == b.SessionID &&
		a.SessionSecret == b.SessionSecret
}

func parseSignedSessionErrorContract(body []byte) (signedSessionErrorContract, bool) {
	var contract signedSessionErrorContract
	if len(body) == 0 || json.Unmarshal(body, &contract) != nil {
		return signedSessionErrorContract{}, false
	}
	contract.Error = strings.TrimSpace(contract.Error)
	contract.Code = strings.ToUpper(strings.TrimSpace(contract.Code))
	contract.Origin = strings.ToLower(strings.TrimSpace(contract.Origin))
	contract.Action = strings.ToLower(strings.TrimSpace(contract.Action))
	contract.RetryMode = strings.ToLower(strings.TrimSpace(contract.RetryMode))
	if contract.RetryAfterSeconds < 0 {
		contract.RetryAfterSeconds = 0
	}
	return contract, contract.Code != "" || contract.Origin != "" || contract.Action != ""
}

func signedSessionGatewayAction(statusCode int, contract signedSessionErrorContract) string {
	if contract.Origin != "gateway" {
		return ""
	}
	switch {
	case statusCode == http.StatusUnauthorized &&
		contract.Code == "SESSION_INVALID" &&
		contract.Action == "bootstrap_session":
		return "bootstrap_session"
	case statusCode == http.StatusPreconditionRequired &&
		contract.Code == "VERIFY_REQUIRED" &&
		contract.Action == "verify":
		return "verify"
	default:
		return ""
	}
}

func signedSessionSameOperationRetry(statusCode int, contract signedSessionErrorContract) bool {
	return statusCode == http.StatusServiceUnavailable &&
		contract.Origin == "provider" &&
		contract.Code == "PROVIDER_UNAVAILABLE" &&
		contract.Retryable &&
		contract.RetryMode == "same_operation"
}

func signedSessionRequestAuthInvalid(statusCode int, contract signedSessionErrorContract) bool {
	return statusCode == http.StatusForbidden &&
		contract.Origin == "gateway" &&
		contract.Code == "REQUEST_AUTH_INVALID" &&
		contract.Action == ""
}

func signedSessionProviderRetryDuration(resp *http.Response, contract signedSessionErrorContract) time.Duration {
	if retryAfter := getRetryAfterDuration(resp); retryAfter > 0 {
		return retryAfter
	}
	if contract.RetryAfterSeconds > 0 {
		maxSeconds := int(maxRetryAfterDelay / time.Second)
		return time.Duration(min(contract.RetryAfterSeconds, maxSeconds)) * time.Second
	}
	return signedSessionProviderRetryDelay
}

// preflightSignedSession prepares a signed session before download metadata
// enrichment starts. A fresh pending challenge is reused, while bootstrap
// responses that can issue a session silently are accepted without prompting
// the user. Bootstrap failures are returned so callers do not continue into
// the provider and accidentally issue the same failing bootstrap repeatedly.
func (r *extensionRuntime) preflightSignedSession() (bool, error) {
	if r == nil || r.manifest == nil || r.manifest.SignedSession == nil {
		return false, nil
	}

	config := signedSessionConfigWithDefaults(r.manifest.SignedSession)
	if config.Namespace == "" || config.BaseURL == "" {
		return false, fmt.Errorf("signedSession is not configured")
	}
	coordinator, err := r.signedSessionCoordinator(config)
	if err != nil {
		return false, err
	}
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()

	record, err := r.loadSignedSession(config)
	if err != nil {
		return false, err
	}
	if signedSessionRecordIsUsable(record) &&
		!coordinator.generationIsBlocked(record) {
		return false, nil
	}

	if authURL, err := r.startSignedSessionVerificationLocked(config, coordinator, "download-preflight"); err != nil {
		return false, err
	} else if authURL != "" {
		return true, nil
	}

	// Bootstrap may provision a session directly instead of returning a
	// challenge. Reload the record before treating the empty URL as a failure.
	record, err = r.loadSignedSession(config)
	if err != nil {
		return false, err
	}
	if signedSessionRecordIsUsable(record) {
		return false, nil
	}

	return false, fmt.Errorf("signed-session bootstrap did not return a session or verification challenge")
}

func (r *extensionRuntime) signedSessionStatus(call goja.FunctionCall) goja.Value {
	config := signedSessionConfigWithDefaults(r.manifest.SignedSession)
	if config.Namespace == "" || config.BaseURL == "" {
		return r.vm.ToValue(map[string]any{"authenticated": false, "error": "signedSession is not configured"})
	}
	coordinator, err := r.signedSessionCoordinator(config)
	if err != nil {
		return r.vm.ToValue(map[string]any{"authenticated": false, "error": err.Error()})
	}
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	record, err := r.loadSignedSession(config)
	if err != nil {
		return r.vm.ToValue(map[string]any{"authenticated": false, "error": err.Error()})
	}
	blocked := coordinator.generationIsBlocked(record)
	authenticated := signedSessionRecordIsUsable(record) && !blocked
	return r.vm.ToValue(map[string]any{
		"authenticated":         authenticated,
		"verification_required": blocked,
		"expires_at":            record.ExpiresAt,
		"install_id":            record.InstallID,
		"session_id":            record.SessionID,
		"app_version":           config.AppVersion,
		"platform":              config.Platform,
	})
}

func (r *extensionRuntime) signedSessionClear(call goja.FunctionCall) goja.Value {
	config := signedSessionConfigWithDefaults(r.manifest.SignedSession)
	coordinator, err := r.signedSessionCoordinator(config)
	if err != nil {
		return r.vm.ToValue(map[string]any{"success": false, "error": err.Error()})
	}
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	record, err := r.loadSignedSession(config)
	if err != nil {
		return r.vm.ToValue(map[string]any{"success": false, "error": err.Error()})
	}
	record.SessionID = ""
	record.SessionSecret = ""
	record.ExpiresAt = ""
	if err := r.saveSignedSession(config, record); err != nil {
		return r.vm.ToValue(map[string]any{"success": false, "error": err.Error()})
	}
	coordinator.clearBlockedGeneration()
	coordinator.clearChallenge()
	ClearPendingAuthRequest(r.extensionID)
	return r.vm.ToValue(map[string]any{"success": true})
}

func (r *extensionRuntime) signedSessionCompleteGrant(call goja.FunctionCall) goja.Value {
	grant := ""
	if len(call.Arguments) > 0 {
		grant = strings.TrimSpace(call.Arguments[0].String())
	}
	if grant != "" {
		setPendingSignedSessionGrant(r.extensionID, grant)
	}
	if grant == "" {
		pendingSignedSessionGrantsMu.Lock()
		grant = pendingSignedSessionGrants[r.extensionID]
		pendingSignedSessionGrantsMu.Unlock()
	}
	if grant == "" {
		return r.vm.ToValue(map[string]any{"success": false, "error": "no pending grant"})
	}
	if err := r.exchangeSignedSessionGrant(grant); err != nil {
		return r.vm.ToValue(map[string]any{"success": false, "error": err.Error()})
	}
	pendingSignedSessionGrantsMu.Lock()
	delete(pendingSignedSessionGrants, r.extensionID)
	pendingSignedSessionGrantsMu.Unlock()
	ClearPendingAuthRequest(r.extensionID)
	return r.vm.ToValue(map[string]any{"success": true})
}

func (r *extensionRuntime) exchangeSignedSessionGrant(grant string) error {
	config := signedSessionConfigWithDefaults(r.manifest.SignedSession)
	coordinator, err := r.signedSessionCoordinator(config)
	if err != nil {
		return err
	}
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	return r.exchangeSignedSessionGrantLocked(config, coordinator, grant)
}

func (r *extensionRuntime) exchangeSignedSessionGrantLocked(
	config SignedSessionConfig,
	coordinator *signedSessionCoordinator,
	grant string,
) error {
	record, err := r.loadSignedSession(config)
	if err != nil {
		return err
	}
	grantHashBytes := sha256.Sum256([]byte(grant))
	grantHash := hex.EncodeToString(grantHashBytes[:])
	// A duplicated callback may arrive after another runtime already exchanged
	// the same one-time grant. Treat that exact shared result as completed
	// instead of consuming the grant again.
	if coordinator.completedGrantHash == grantHash &&
		signedSessionRecordIsUsable(record) {
		coordinator.clearBlockedGeneration()
		coordinator.clearChallenge()
		return nil
	}
	endpoint, err := signedSessionURL(config, config.Endpoints.Exchange)
	if err != nil {
		return err
	}
	payload := map[string]any{
		"grant":       grant,
		"install_id":  record.InstallID,
		"app_version": config.AppVersion,
		"platform":    config.Platform,
	}
	body, _ := json.Marshal(payload)
	var respBody []byte
	for attempt := 1; attempt <= signedSessionExchangeMaxAttempts; attempt++ {
		req, requestErr := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(body))
		if requestErr != nil {
			return requestErr
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Accept", "application/json")
		req.Header.Set("User-Agent", "SpotiFLAC-Mobile/"+config.AppVersion)
		resp, requestErr := r.httpClient.Do(req)
		if requestErr != nil {
			return requestErr
		}
		respBody, requestErr = readExtensionHTTPResponseBody(resp)
		resp.Body.Close()
		if requestErr != nil {
			return requestErr
		}
		if resp.StatusCode == http.StatusTooManyRequests && attempt < signedSessionExchangeMaxAttempts {
			retryAfter := time.Duration(signedSessionRetryAfterSeconds(resp)) * time.Second
			if retryAfter <= 0 {
				retryAfter = time.Second
			}
			if retryAfter > signedSessionMaxRetryAfter {
				retryAfter = signedSessionMaxRetryAfter
			}
			LogWarn(
				"SignedSession",
				"Grant exchange rate limited for extension %s; retrying in %s (attempt %d/%d)",
				r.extensionID,
				retryAfter,
				attempt+1,
				signedSessionExchangeMaxAttempts,
			)
			signedSessionRetryWait(retryAfter)
			continue
		}
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			message := fmt.Sprintf("session exchange failed: HTTP %d", resp.StatusCode)
			if retryAfter := signedSessionRetryAfterSeconds(resp); retryAfter > 0 {
				message += fmt.Sprintf("; retry-after seconds: %d", retryAfter)
			}
			return errors.New(message)
		}
		break
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
	if err := r.saveSignedSession(config, record); err != nil {
		return err
	}
	coordinator.completedGrantHash = grantHash
	coordinator.clearBlockedGeneration()
	coordinator.clearChallenge()
	return nil
}

func (r *extensionRuntime) signedSessionFetch(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.vm.ToValue(map[string]any{"ok": false, "error": "method and path are required"})
	}
	config := signedSessionConfigWithDefaults(r.manifest.SignedSession)
	if config.Namespace == "" || config.BaseURL == "" {
		return r.vm.ToValue(map[string]any{"ok": false, "error": "signedSession is not configured"})
	}
	method := strings.ToUpper(strings.TrimSpace(call.Arguments[0].String()))
	requestPath := call.Arguments[1].String()
	body := []byte{}
	if len(call.Arguments) > 2 && !goja.IsUndefined(call.Arguments[2]) && !goja.IsNull(call.Arguments[2]) {
		switch v := call.Arguments[2].Export().(type) {
		case string:
			body = []byte(v)
		case map[string]any, []any:
			encoded, err := json.Marshal(v)
			if err != nil {
				return r.vm.ToValue(map[string]any{"ok": false, "error": err.Error()})
			}
			body = encoded
		default:
			body = []byte(call.Arguments[2].String())
		}
	}
	extraHeaders := parseGojaHeaders(call.Argument(3).Export())

	coordinator, err := r.signedSessionCoordinator(config)
	if err != nil {
		return r.vm.ToValue(map[string]any{"ok": false, "error": err.Error()})
	}
	coordinator.mu.Lock()
	record, err := r.ensureSignedSession(config)
	if err != nil {
		authURL, verificationErr := r.startSignedSessionVerificationLocked(config, coordinator, "signed-fetch")
		coordinator.mu.Unlock()
		if authURL != "" {
			return r.signedSessionVerificationRequiredValue(authURL)
		} else if verificationErr != nil {
			return r.vm.ToValue(map[string]any{"ok": false, "error": verificationErr.Error()})
		}
		return r.vm.ToValue(map[string]any{"ok": false, "error": err.Error()})
	}
	if coordinator.generationIsBlocked(record) {
		authURL, verificationErr := r.startSignedSessionVerificationLocked(
			config,
			coordinator,
			"signed-fetch-blocked-generation",
		)
		if authURL != "" {
			coordinator.mu.Unlock()
			return r.signedSessionVerificationRequiredValue(authURL)
		}
		if verificationErr != nil {
			coordinator.mu.Unlock()
			return r.vm.ToValue(map[string]any{"ok": false, "error": verificationErr.Error()})
		}
		record, err = r.loadSignedSession(config)
		if err != nil {
			coordinator.mu.Unlock()
			return r.vm.ToValue(map[string]any{"ok": false, "error": err.Error()})
		}
		if !signedSessionRecordIsUsable(record) || coordinator.generationIsBlocked(record) {
			coordinator.mu.Unlock()
			return r.vm.ToValue(map[string]any{
				"ok":    false,
				"error": "verification_required: signed-session generation is blocked",
			})
		}
	}
	coordinator.mu.Unlock()

	// A request that loses a race with a successful grant exchange may return a
	// canonical SESSION_INVALID response for the old secret. Reload and retry
	// with the newer shared session; never let that stale response erase its
	// replacement. Provider retries have an independent, bounded budget.
	sessionRetries := 0
	providerRetries := 0
	requestAuthRetryUsed := false
	for {
		resp, respBody, respHeaders, requestErr := r.doSignedSessionRequest(
			config,
			record,
			method,
			requestPath,
			body,
			extraHeaders,
		)
		if requestErr != nil {
			return r.vm.ToValue(map[string]any{"ok": false, "error": requestErr.Error()})
		}
		contract, _ := parseSignedSessionErrorContract(respBody)

		if signedSessionSameOperationRetry(resp.StatusCode, contract) {
			if providerRetries >= signedSessionMaxProviderRetries {
				return r.signedSessionResponseValue(resp, respBody, respHeaders)
			}
			providerRetries++
			delay := signedSessionProviderRetryDuration(resp, contract)
			LogWarn(
				"SignedSession",
				"Provider temporarily unavailable for extension %s; retrying in %s (attempt %d/%d)",
				r.extensionID,
				delay,
				providerRetries+1,
				signedSessionMaxProviderRetries+1,
			)
			if waitErr := signedSessionProviderWait(resp.Request.Context(), delay); waitErr != nil {
				return r.vm.ToValue(map[string]any{"ok": false, "error": waitErr.Error()})
			}
			continue
		}

		if signedSessionRequestAuthInvalid(resp.StatusCode, contract) {
			coordinator.mu.Lock()
			latest, loadErr := r.loadSignedSession(config)
			if loadErr != nil {
				coordinator.mu.Unlock()
				return r.vm.ToValue(map[string]any{"ok": false, "error": loadErr.Error()})
			}
			if !requestAuthRetryUsed &&
				signedSessionRecordIsUsable(latest) &&
				!sameSignedSession(latest, record) {
				requestAuthRetryUsed = true
				record = latest
				coordinator.mu.Unlock()
				LogDebug(
					"SignedSession",
					"Retrying stale REQUEST_AUTH_INVALID for extension %s with the current session generation",
					r.extensionID,
				)
				continue
			}
			coordinator.mu.Unlock()
			LogWarn(
				"SignedSession",
				"REQUEST_AUTH_INVALID for extension %s on the current session generation; preserving session state",
				r.extensionID,
			)
			return r.signedSessionResponseValue(resp, respBody, respHeaders)
		}

		gatewayAction := signedSessionGatewayAction(resp.StatusCode, contract)
		if gatewayAction == "" {
			return r.signedSessionResponseValue(resp, respBody, respHeaders)
		}

		coordinator.mu.Lock()
		latest, loadErr := r.loadSignedSession(config)
		if loadErr != nil {
			coordinator.mu.Unlock()
			return r.vm.ToValue(map[string]any{"ok": false, "error": loadErr.Error()})
		}
		if signedSessionRecordIsUsable(latest) &&
			!sameSignedSession(latest, record) {
			if sessionRetries >= signedSessionMaxSessionRetries {
				coordinator.mu.Unlock()
				return r.vm.ToValue(map[string]any{"ok": false, "error": "signed-session retry limit reached"})
			}
			sessionRetries++
			record = latest
			coordinator.mu.Unlock()
			LogDebug(
				"SignedSession",
				"Discarding stale %s response for extension %s and retrying with the exchanged session",
				contract.Code,
				r.extensionID,
			)
			continue
		}
		// VERIFY_REQUIRED is an explicit challenge request, not a revocation.
		// Only SESSION_INVALID is allowed to clear the current gateway session.
		if gatewayAction == "bootstrap_session" && sameSignedSession(latest, record) {
			coordinator.clearBlockedGeneration()
			latest.SessionID = ""
			latest.SessionSecret = ""
			latest.ExpiresAt = ""
			if saveErr := r.saveSignedSession(config, latest); saveErr != nil {
				coordinator.mu.Unlock()
				return r.vm.ToValue(map[string]any{"ok": false, "error": saveErr.Error()})
			}
		} else if gatewayAction == "verify" && sameSignedSession(latest, record) {
			// Stop subsequent requests from repeatedly hitting the gateway with
			// a generation that is known to require human verification.
			coordinator.blockGeneration(record)
		}
		authURL, verificationErr := r.startSignedSessionVerificationLocked(
			config,
			coordinator,
			"signed-fetch-"+gatewayAction,
		)
		if authURL != "" {
			coordinator.mu.Unlock()
			return r.signedSessionVerificationRequiredValue(authURL)
		} else if verificationErr != nil {
			coordinator.mu.Unlock()
			return r.vm.ToValue(map[string]any{"ok": false, "error": verificationErr.Error()})
		}

		// Bootstrap may silently issue a replacement session instead of a
		// challenge. Retry the original operation with that generation.
		bootstrapped, loadErr := r.loadSignedSession(config)
		if loadErr != nil {
			coordinator.mu.Unlock()
			return r.vm.ToValue(map[string]any{"ok": false, "error": loadErr.Error()})
		}
		if signedSessionRecordIsUsable(bootstrapped) &&
			!sameSignedSession(bootstrapped, record) &&
			sessionRetries < signedSessionMaxSessionRetries {
			sessionRetries++
			record = bootstrapped
			coordinator.mu.Unlock()
			continue
		}
		coordinator.mu.Unlock()
		return r.signedSessionResponseValue(resp, respBody, respHeaders)
	}
}

func (r *extensionRuntime) signedSessionResponseValue(
	resp *http.Response,
	respBody []byte,
	respHeaders map[string]any,
) goja.Value {
	contract, hasContract := parseSignedSessionErrorContract(respBody)
	retryAfterSeconds := signedSessionRetryAfterSeconds(resp)
	if retryAfterSeconds <= 0 && contract.RetryAfterSeconds > 0 {
		retryAfterSeconds = contract.RetryAfterSeconds
	}
	result := map[string]any{
		"statusCode":        resp.StatusCode,
		"status":            resp.StatusCode,
		"ok":                resp.StatusCode >= 200 && resp.StatusCode < 300,
		"url":               resp.Request.URL.String(),
		"body":              string(respBody),
		"headers":           respHeaders,
		"retryAfterSeconds": retryAfterSeconds,
	}
	if hasContract {
		result["error"] = contract.Error
		result["code"] = contract.Code
		result["origin"] = contract.Origin
		result["action"] = contract.Action
		result["retryable"] = contract.Retryable
		result["retryMode"] = contract.RetryMode
	}
	return r.vm.ToValue(result)
}

func (r *extensionRuntime) signedSessionVerificationRequiredValue(authURL string) goja.Value {
	r.noteVerificationRequired(authURL)
	return r.vm.ToValue(map[string]any{
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

func (r *extensionRuntime) startSignedSessionVerification(config SignedSessionConfig, reason string) (string, error) {
	coordinator, err := r.signedSessionCoordinator(config)
	if err != nil {
		return "", err
	}
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	return r.startSignedSessionVerificationLocked(config, coordinator, reason)
}

func (r *extensionRuntime) startSignedSessionVerificationLocked(
	config SignedSessionConfig,
	coordinator *signedSessionCoordinator,
	reason string,
) (string, error) {
	if coordinator.activeChallenge() {
		pendingAuthRequestsMu.Lock()
		pendingAuthRequests[r.extensionID] = &PendingAuthRequest{
			ExtensionID: r.extensionID,
			AuthURL:     coordinator.authURL,
			CallbackURL: coordinator.callbackURL,
			CreatedAt:   coordinator.challengeCreatedAt,
		}
		pendingAuthRequestsMu.Unlock()
		coordinator.pendingExtensionIDs[r.extensionID] = struct{}{}
		return coordinator.authURL, nil
	}
	if coordinator.authURL != "" {
		coordinator.clearChallenge()
	}
	if pending := GetPendingAuthRequest(r.extensionID); pending != nil {
		if time.Since(pending.CreatedAt) < pendingAuthRequestTTL &&
			strings.TrimSpace(pending.AuthURL) != "" {
			coordinator.rememberChallenge(
				r.extensionID,
				pending.AuthURL,
				pending.CallbackURL,
			)
			return pending.AuthURL, nil
		}
		ClearPendingAuthRequest(r.extensionID)
	}

	record, err := r.loadSignedSession(config)
	if err != nil {
		return "", fmt.Errorf("load signed-session bootstrap state: %w", err)
	}
	bootstrapURL, err := signedSessionURL(config, config.Endpoints.Bootstrap)
	if err != nil {
		return "", fmt.Errorf("build signed-session bootstrap URL: %w", err)
	}
	parsed, err := url.Parse(bootstrapURL)
	if err != nil {
		return "", fmt.Errorf("parse signed-session bootstrap URL: %w", err)
	}
	query := parsed.Query()
	query.Set("app_version", config.AppVersion)
	query.Set("install_id", record.InstallID)
	parsed.RawQuery = query.Encode()
	if r.httpClient == nil {
		return "", fmt.Errorf("signed-session bootstrap HTTP client is unavailable")
	}

	var resp *http.Response
	for attempt := 0; attempt < 2; attempt++ {
		req, requestErr := http.NewRequest(http.MethodGet, parsed.String(), nil)
		if requestErr != nil {
			return "", fmt.Errorf("build signed-session bootstrap request: %w", requestErr)
		}
		req.Header.Set("Accept", "application/json")
		req.Header.Set("User-Agent", "SpotiFLAC-Mobile/"+config.AppVersion)
		resp, err = r.httpClient.Do(req)
		if err == nil {
			break
		}
		if resp != nil && resp.Body != nil {
			resp.Body.Close()
			resp = nil
		}
		if attempt == 0 {
			// Android can retain pooled connections across a Wi-Fi/cellular
			// transition. Rebuild the GET once after dropping those sockets.
			r.httpClient.CloseIdleConnections()
		}
	}
	if err != nil {
		var urlErr *url.Error
		if errors.As(err, &urlErr) && urlErr.Err != nil {
			err = urlErr.Err
		}
		bootstrapErr := fmt.Errorf(
			"signed-session bootstrap network request to %s failed: %v",
			parsed.Host,
			err,
		)
		LogWarn("SignedSession", "Bootstrap failed for extension %s (%s): %v", r.extensionID, reason, bootstrapErr)
		return "", bootstrapErr
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		// Drain a bounded error response so the transport can reuse the
		// connection without exposing response bodies that may contain secrets.
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
		message := fmt.Sprintf("signed-session bootstrap returned HTTP %d", resp.StatusCode)
		if resp.StatusCode >= 500 {
			message = fmt.Sprintf("signed-session bootstrap network request returned HTTP %d", resp.StatusCode)
		}
		if retryAfter := signedSessionRetryAfterSeconds(resp); retryAfter > 0 {
			message += fmt.Sprintf("; retry-after seconds: %d", retryAfter)
		}
		bootstrapErr := errors.New(message)
		LogWarn("SignedSession", "Bootstrap failed for extension %s (%s): %v", r.extensionID, reason, bootstrapErr)
		return "", bootstrapErr
	}
	body, err := readExtensionHTTPResponseBody(resp)
	if err != nil {
		return "", fmt.Errorf("read signed-session bootstrap response: %w", err)
	}
	var boot signedSessionExchangeResponse
	if err := json.Unmarshal(body, &boot); err != nil {
		return "", fmt.Errorf("decode signed-session bootstrap response: %w", err)
	}
	if boot.SessionID != "" && boot.SessionSecret != "" && boot.ExpiresAt != "" {
		record.SessionID = boot.SessionID
		record.SessionSecret = boot.SessionSecret
		record.ExpiresAt = boot.ExpiresAt
		if err := r.saveSignedSession(config, record); err != nil {
			return "", fmt.Errorf("save bootstrapped signed session: %w", err)
		}
		coordinator.clearBlockedGeneration()
		coordinator.clearChallenge()
		return "", nil
	}
	authURL := boot.AuthURL
	if authURL == "" && boot.ChallengeURL != "" {
		authURL = boot.ChallengeURL
	}
	if authURL == "" && boot.ChallengeID != "" {
		authURL = r.buildSignedSessionChallengeURL(config, boot.ChallengeID)
	}
	if authURL == "" {
		return "", fmt.Errorf("signed-session bootstrap did not return a session or verification challenge")
	}
	pendingAuthRequestsMu.Lock()
	pendingAuthRequests[r.extensionID] = &PendingAuthRequest{
		ExtensionID: r.extensionID,
		AuthURL:     authURL,
		CallbackURL: config.CallbackURL,
		CreatedAt:   time.Now(),
	}
	pendingAuthRequestsMu.Unlock()
	coordinator.rememberChallenge(r.extensionID, authURL, config.CallbackURL)
	return authURL, nil
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
) (*http.Response, []byte, map[string]any, error) {
	fullURL, err := signedSessionURL(config, requestPath)
	if err != nil {
		return nil, nil, nil, err
	}
	parsed, err := url.Parse(fullURL)
	if err != nil {
		return nil, nil, nil, err
	}
	ts := signedSessionRequestNow().UTC().Format("2006-01-02T15:04:05.000Z")
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
	headers := make(map[string]any)
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
