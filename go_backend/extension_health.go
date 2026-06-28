package gobackend

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	extensionHealthDefaultTimeout = 4 * time.Second
	extensionHealthMaxBodyBytes   = 64 * 1024
	extensionHealthDefaultCache   = 60 * time.Second
	extensionHealthUnknownCache   = 20 * time.Second
)

type ExtensionHealthResult struct {
	ExtensionID string                       `json:"extension_id"`
	Status      string                       `json:"status"`
	CheckedAt   string                       `json:"checked_at"`
	Checks      []ExtensionHealthCheckResult `json:"checks"`
}

type ExtensionHealthCheckResult struct {
	ID         string `json:"id"`
	Label      string `json:"label,omitempty"`
	URL        string `json:"url"`
	Method     string `json:"method"`
	ServiceKey string `json:"service_key,omitempty"`
	Required   bool   `json:"required"`
	Status     string `json:"status"`
	HTTPStatus int    `json:"http_status,omitempty"`
	LatencyMs  int64  `json:"latency_ms"`
	Message    string `json:"message,omitempty"`
	Error      string `json:"error,omitempty"`
	CheckedAt  string `json:"checked_at"`
}

type cachedExtensionHealthResult struct {
	result    ExtensionHealthResult
	expiresAt time.Time
}

var (
	extensionHealthCacheMu sync.Mutex
	extensionHealthCache   = map[string]cachedExtensionHealthResult{}
)

func CheckExtensionHealthJSON(extensionID string) (string, error) {
	manager := getExtensionManager()
	ext, err := manager.GetExtension(extensionID)
	if err != nil {
		return "", err
	}

	result := CheckExtensionHealth(ext)
	cacheExtensionHealthResult(ext, result)
	bytes, err := json.Marshal(result)
	if err != nil {
		return "", err
	}
	return string(bytes), nil
}

func CheckExtensionHealthCached(ext *loadedExtension) ExtensionHealthResult {
	if ext == nil || ext.Manifest == nil || len(ext.Manifest.ServiceHealth) == 0 {
		return CheckExtensionHealth(ext)
	}

	cacheKey := strings.TrimSpace(ext.ID)
	if cacheKey == "" {
		return CheckExtensionHealth(ext)
	}

	now := time.Now()
	extensionHealthCacheMu.Lock()
	cached, ok := extensionHealthCache[cacheKey]
	if ok && now.Before(cached.expiresAt) {
		extensionHealthCacheMu.Unlock()
		return cached.result
	}
	extensionHealthCacheMu.Unlock()

	result := CheckExtensionHealth(ext)
	cacheExtensionHealthResult(ext, result)
	return result
}

func cacheExtensionHealthResult(ext *loadedExtension, result ExtensionHealthResult) {
	if ext == nil || ext.Manifest == nil || len(ext.Manifest.ServiceHealth) == 0 {
		return
	}

	cacheKey := strings.TrimSpace(ext.ID)
	if cacheKey == "" {
		return
	}

	ttl := extensionHealthCacheTTL(ext.Manifest.ServiceHealth)
	if result.Status == "unknown" && ttl > extensionHealthUnknownCache {
		ttl = extensionHealthUnknownCache
	}

	extensionHealthCacheMu.Lock()
	extensionHealthCache[cacheKey] = cachedExtensionHealthResult{
		result:    result,
		expiresAt: time.Now().Add(ttl),
	}
	extensionHealthCacheMu.Unlock()
}

func CheckExtensionHealth(ext *loadedExtension) ExtensionHealthResult {
	now := time.Now().UTC().Format(time.RFC3339)
	result := ExtensionHealthResult{
		ExtensionID: "",
		Status:      "unsupported",
		CheckedAt:   now,
		Checks:      []ExtensionHealthCheckResult{},
	}
	if ext == nil || ext.Manifest == nil {
		result.Status = "offline"
		return result
	}

	result.ExtensionID = ext.ID
	checks := ext.Manifest.ServiceHealth
	if len(checks) == 0 {
		return result
	}

	result.Status = "online"
	for _, check := range checks {
		checkResult := runExtensionHealthCheck(ext.Manifest, check)
		result.Checks = append(result.Checks, checkResult)

		switch checkResult.Status {
		case "offline":
			if check.Required {
				result.Status = "offline"
			} else if result.Status == "online" {
				result.Status = "degraded"
			}
		case "degraded":
			if result.Status == "online" {
				result.Status = "degraded"
			}
		case "unknown":
			if result.Status == "online" {
				result.Status = "unknown"
			}
		}
	}

	return result
}

func extensionHealthCacheTTL(checks []ExtensionHealthCheck) time.Duration {
	ttl := extensionHealthDefaultCache
	for _, check := range checks {
		if check.CacheTTLSeconds <= 0 {
			continue
		}
		checkTTL := time.Duration(check.CacheTTLSeconds) * time.Second
		if checkTTL < ttl {
			ttl = checkTTL
		}
	}
	return ttl
}

func runExtensionHealthCheck(manifest *ExtensionManifest, check ExtensionHealthCheck) ExtensionHealthCheckResult {
	method := strings.ToUpper(strings.TrimSpace(check.Method))
	if method == "" {
		method = http.MethodGet
	}
	now := time.Now().UTC().Format(time.RFC3339)
	result := ExtensionHealthCheckResult{
		ID:         check.ID,
		Label:      check.Label,
		URL:        check.URL,
		Method:     method,
		ServiceKey: strings.TrimSpace(check.ServiceKey),
		Required:   check.Required,
		Status:     "unknown",
		CheckedAt:  now,
	}

	parsed, err := url.Parse(check.URL)
	if err != nil {
		result.Status = "offline"
		result.Error = fmt.Sprintf("invalid health URL: %v", err)
		return result
	}
	if parsed.Scheme != "https" {
		result.Status = "offline"
		result.Error = "health check must use https"
		return result
	}
	host := parsed.Hostname()
	if host == "" {
		result.Status = "offline"
		result.Error = "health check URL hostname is required"
		return result
	}
	if isPrivateIP(host) {
		result.Status = "offline"
		result.Error = "private/local health check host is not allowed"
		return result
	}
	if manifest == nil || !manifest.IsDomainAllowed(host) {
		result.Status = "offline"
		result.Error = fmt.Sprintf("health check host '%s' is not in extension network permissions", host)
		return result
	}
	if method != http.MethodGet && method != http.MethodHead {
		result.Status = "offline"
		result.Error = "health check method must be GET or HEAD"
		return result
	}

	timeout := extensionHealthDefaultTimeout
	if check.TimeoutMs > 0 {
		timeout = time.Duration(check.TimeoutMs) * time.Millisecond
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, method, check.URL, nil)
	if err != nil {
		result.Status = "offline"
		result.Error = err.Error()
		return result
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", userAgentForURL(parsed))

	start := time.Now()
	resp, err := NewMetadataHTTPClient(timeout).Do(req)
	result.LatencyMs = time.Since(start).Milliseconds()
	if err != nil {
		if isTransientExtensionHealthError(err) {
			result.Status = "unknown"
		} else {
			result.Status = "offline"
		}
		result.Error = err.Error()
		return result
	}
	defer resp.Body.Close()

	result.HTTPStatus = resp.StatusCode
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		result.Status = "offline"
		result.Message = resp.Status
		return result
	}

	if method == http.MethodHead {
		result.Status = "online"
		result.Message = resp.Status
		return result
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, extensionHealthMaxBodyBytes))
	if err != nil {
		result.Status = "degraded"
		result.Error = err.Error()
		return result
	}

	status, message := classifyExtensionHealthBody(body, check.ServiceKey)
	result.Status = status
	if message == "" {
		result.Message = resp.Status
	} else {
		result.Message = message
	}
	return result
}

func isTransientExtensionHealthError(err error) bool {
	return isTransientNetworkError(err) || isConnectivityFailure(err)
}

func classifyExtensionHealthBody(body []byte, serviceKey string) (string, string) {
	if len(strings.TrimSpace(string(body))) == 0 {
		return "online", ""
	}

	var payload map[string]interface{}
	if err := json.Unmarshal(body, &payload); err != nil {
		return "online", ""
	}

	serviceKey = strings.TrimSpace(serviceKey)
	if serviceKey != "" {
		if status, message, ok := classifyExtensionHealthService(payload, serviceKey); ok {
			return status, message
		}
	}

	rawStatus, _ := payload["status"].(string)
	normalized := strings.ToLower(strings.TrimSpace(rawStatus))
	switch normalized {
	case "", "ok", "up", "online", "healthy", "operational", "pass", "passing":
		return "online", rawStatus
	case "degraded", "partial", "warning", "warn":
		return "degraded", rawStatus
	case "down", "offline", "error", "failed", "fail", "unhealthy":
		if isTransientHealthStatusMessage(string(body)) {
			return "unknown", rawStatus
		}
		return "offline", rawStatus
	default:
		return "online", rawStatus
	}
}

func classifyExtensionHealthService(payload map[string]interface{}, serviceKey string) (string, string, bool) {
	rawServices, ok := payload["services"]
	if !ok {
		return "", "", false
	}
	services, ok := rawServices.(map[string]interface{})
	if !ok {
		return "", "", false
	}
	rawService, ok := services[serviceKey]
	if !ok {
		return "unknown", fmt.Sprintf("service '%s' not found", serviceKey), true
	}
	service, ok := rawService.(map[string]interface{})
	if !ok {
		return "unknown", fmt.Sprintf("service '%s' has invalid health payload", serviceKey), true
	}

	label, _ := service["label"].(string)
	detail, _ := service["detail"].(string)
	errText, _ := service["error"].(string)
	messageParts := []string{}
	if strings.TrimSpace(label) != "" {
		messageParts = append(messageParts, strings.TrimSpace(label))
	}
	if strings.TrimSpace(detail) != "" {
		messageParts = append(messageParts, strings.TrimSpace(detail))
	}
	if strings.TrimSpace(errText) != "" {
		messageParts = append(messageParts, strings.TrimSpace(errText))
	}

	rawStatus, hasStatus := service["status"]
	okValue, hasOK := service["ok"].(bool)
	joinedMessage := strings.Join(messageParts, ": ")
	transient := isTransientHealthStatusMessage(detail) ||
		isTransientHealthStatusMessage(errText) ||
		isTransientHealthStatusMessage(label)

	if statusCode, ok := healthNumber(rawStatus); ok {
		if statusCode >= 200 && statusCode < 300 {
			return "online", joinedMessage, true
		}
		if statusCode == http.StatusUnauthorized || statusCode == http.StatusForbidden {
			return "degraded", joinedMessage, true
		}
		if statusCode == http.StatusInternalServerError && hasOK && okValue {
			return "online", joinedMessage, true
		}
		if transient || isTransientHealthStatusCode(statusCode) {
			return "unknown", joinedMessage, true
		}
		return "offline", joinedMessage, true
	}

	if isExtensionHealthAuthRequired(detail) {
		return "degraded", joinedMessage, true
	}
	if transient {
		return "unknown", joinedMessage, true
	}
	if hasOK {
		if okValue {
			return "online", joinedMessage, true
		}
		return "offline", joinedMessage, true
	}
	if !hasStatus {
		return "unknown", joinedMessage, true
	}

	statusString := strings.ToLower(strings.TrimSpace(fmt.Sprintf("%v", rawStatus)))
	switch statusString {
	case "ok", "up", "online", "healthy", "operational":
		return "online", joinedMessage, true
	case "degraded", "partial", "warning", "warn":
		return "degraded", joinedMessage, true
	case "down", "offline", "error", "failed", "fail", "unhealthy":
		return "offline", joinedMessage, true
	default:
		return "unknown", joinedMessage, true
	}
}

func isExtensionHealthAuthRequired(detail string) bool {
	switch strings.ToLower(strings.TrimSpace(detail)) {
	case "auth_required", "authorization_required", "login_required", "unauthorized":
		return true
	default:
		return false
	}
}

func isTransientHealthStatusMessage(text string) bool {
	t := strings.ToLower(strings.TrimSpace(text))
	if t == "" {
		return false
	}
	return strings.Contains(t, "context deadline exceeded") ||
		strings.Contains(t, "deadline exceeded") ||
		strings.Contains(t, "timeout") ||
		strings.Contains(t, "timed out") ||
		strings.Contains(t, "temporarily unavailable") ||
		strings.Contains(t, "try again")
}

func isTransientHealthStatusCode(code int) bool {
	switch code {
	case http.StatusRequestTimeout,
		http.StatusTooManyRequests,
		http.StatusBadGateway,
		http.StatusServiceUnavailable,
		http.StatusGatewayTimeout:
		return true
	default:
		return false
	}
}

func healthNumber(value interface{}) (int, bool) {
	switch v := value.(type) {
	case float64:
		return int(v), true
	case int:
		return v, true
	case json.Number:
		n, err := v.Int64()
		return int(n), err == nil
	default:
		return 0, false
	}
}
