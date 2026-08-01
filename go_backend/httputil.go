package gobackend

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

func userAgentForURL(u *url.URL) string {
	if u == nil {
		return getRandomUserAgent()
	}

	host := strings.ToLower(strings.TrimSpace(u.Hostname()))
	if host == "api.zarz.moe" {
		return appUserAgent()
	}

	return getRandomUserAgent()
}

func getRandomUserAgent() string {
	chromeVersion := rand.Intn(26) + 120
	chromeBuild := rand.Intn(1500) + 6000
	chromePatch := rand.Intn(200) + 100

	return fmt.Sprintf(
		"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/%d.0.%d.%d Safari/537.36",
		chromeVersion,
		chromeBuild,
		chromePatch,
	)
}

const (
	DefaultTimeout    = 60 * time.Second
	DownloadTimeout   = 24 * time.Hour
	SongLinkTimeout   = 30 * time.Second
	DefaultMaxRetries = 3
	DefaultRetryDelay = 1 * time.Second
	Second            = time.Second
)

type NetworkCompatibilityOptions struct {
	AllowHTTP   bool
	InsecureTLS bool
}

var (
	networkCompatibilityMu      sync.RWMutex
	networkCompatibilityOptions NetworkCompatibilityOptions
)

var transportDialer = &net.Dialer{
	Timeout:   10 * time.Second,
	KeepAlive: 30 * time.Second,
}

func transportDialContext(ctx context.Context, network, addr string) (net.Conn, error) {
	return dialWithDoHFallback(ctx, transportDialer, network, addr)
}

var sharedTransport = &http.Transport{
	DialContext:         transportDialContext,
	MaxIdleConns:        100,
	MaxIdleConnsPerHost: 10,
	MaxConnsPerHost:     20,
	IdleConnTimeout:     60 * time.Second,
	TLSHandshakeTimeout: 10 * time.Second,
	// Downloads ride this transport; some extension providers prepare the
	// file server-side before the first byte, so give TTFB more headroom
	// than the API/metadata transports. The 60s stall watchdog still bounds
	// dead transfers.
	ResponseHeaderTimeout: 120 * time.Second,
	ExpectContinueTimeout: 1 * time.Second,
	DisableKeepAlives:     false,
	ForceAttemptHTTP2:     true,
	WriteBufferSize:       64 * 1024,
	ReadBufferSize:        64 * 1024,
	DisableCompression:    true,
	TLSClientConfig:       newTLSCompatibilityConfig(false),
}

var extensionAPITransport = &http.Transport{
	DialContext:           transportDialContext,
	MaxIdleConns:          100,
	MaxIdleConnsPerHost:   10,
	MaxConnsPerHost:       20,
	IdleConnTimeout:       60 * time.Second,
	TLSHandshakeTimeout:   10 * time.Second,
	ResponseHeaderTimeout: 45 * time.Second,
	ExpectContinueTimeout: 1 * time.Second,
	DisableKeepAlives:     false,
	ForceAttemptHTTP2:     true,
	WriteBufferSize:       64 * 1024,
	ReadBufferSize:        64 * 1024,
	DisableCompression:    false,
	TLSClientConfig:       newTLSCompatibilityConfig(false),
}

var metadataTransport = &http.Transport{
	DialContext:           transportDialContext,
	MaxIdleConns:          30,
	MaxIdleConnsPerHost:   5,
	MaxConnsPerHost:       10,
	IdleConnTimeout:       60 * time.Second,
	TLSHandshakeTimeout:   10 * time.Second,
	ResponseHeaderTimeout: 45 * time.Second,
	ExpectContinueTimeout: 1 * time.Second,
	DisableKeepAlives:     false,
	ForceAttemptHTTP2:     true,
	WriteBufferSize:       32 * 1024,
	ReadBufferSize:        32 * 1024,
	// Metadata responses are JSON; transparent gzip cuts transfer size several
	// times over. Downloads stay on sharedTransport with compression disabled.
	DisableCompression: false,
	TLSClientConfig:    newTLSCompatibilityConfig(false),
}

var sharedClient = &http.Client{
	Transport: newCompatibilityTransport(sharedTransport),
	Timeout:   DefaultTimeout,
}

func NewHTTPClientWithTimeout(timeout time.Duration) *http.Client {
	return &http.Client{
		Transport: newCompatibilityTransport(sharedTransport),
		Timeout:   timeout,
	}
}

func NewMetadataHTTPClient(timeout time.Duration) *http.Client {
	return &http.Client{
		Transport: newCompatibilityTransport(metadataTransport),
		Timeout:   timeout,
	}
}

func CloseIdleConnections() {
	sharedTransport.CloseIdleConnections()
	extensionAPITransport.CloseIdleConnections()
	metadataTransport.CloseIdleConnections()
	closeUTLSIdleConnections()
}

func SetNetworkCompatibilityOptions(allowHTTP, insecureTLS bool) {
	networkCompatibilityMu.Lock()
	networkCompatibilityOptions = NetworkCompatibilityOptions{
		AllowHTTP:   allowHTTP,
		InsecureTLS: insecureTLS,
	}
	networkCompatibilityMu.Unlock()

	applyTLSCompatibility(sharedTransport, insecureTLS)
	applyTLSCompatibility(extensionAPITransport, insecureTLS)
	applyTLSCompatibility(metadataTransport, insecureTLS)
	CloseIdleConnections()

	GoLog("[HTTP] Network compatibility options updated: allow_http=%v insecure_tls=%v\n", allowHTTP, insecureTLS)
}

func GetNetworkCompatibilityOptions() NetworkCompatibilityOptions {
	networkCompatibilityMu.RLock()
	defer networkCompatibilityMu.RUnlock()
	return networkCompatibilityOptions
}

func applyTLSCompatibility(transport *http.Transport, insecureTLS bool) {
	transport.TLSClientConfig = newTLSCompatibilityConfig(insecureTLS)
}

type compatibilityTransport struct {
	base http.RoundTripper
}

func newCompatibilityTransport(base http.RoundTripper) http.RoundTripper {
	return &compatibilityTransport{base: base}
}

func (t *compatibilityTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	if req == nil || req.URL == nil {
		return t.base.RoundTrip(req)
	}

	opts := GetNetworkCompatibilityOptions()
	if !opts.AllowHTTP || req.URL.Scheme != "https" {
		return t.base.RoundTrip(req)
	}

	// Compatibility mode should prefer HTTPS and only fallback to HTTP on
	// transport-level failures. Forcing HTTP unconditionally can trigger
	// redirect loops (http -> https) on providers that enforce HTTPS.
	resp, err := t.base.RoundTrip(req)
	if err == nil {
		return resp, nil
	}

	if !canFallbackToHTTP(req) {
		return nil, err
	}

	fallbackReq, cloneErr := cloneRequestWithHTTPScheme(req, "http")
	if cloneErr != nil {
		return nil, err
	}

	GoLog("[HTTP] HTTPS request failed for %s, retrying over HTTP: %v\n", req.URL.Host, err)
	return t.base.RoundTrip(fallbackReq)
}

func canFallbackToHTTP(req *http.Request) bool {
	if req == nil {
		return false
	}

	switch strings.ToUpper(req.Method) {
	case http.MethodGet, http.MethodHead, http.MethodOptions, http.MethodDelete:
		return true
	default:
		return req.GetBody != nil
	}
}

func cloneRequestWithHTTPScheme(req *http.Request, scheme string) (*http.Request, error) {
	reqCopy := req.Clone(req.Context())
	if req.Body != nil && req.GetBody != nil {
		bodyCopy, err := req.GetBody()
		if err != nil {
			return nil, err
		}
		reqCopy.Body = bodyCopy
	}

	urlCopy := *req.URL
	urlCopy.Scheme = scheme
	reqCopy.URL = &urlCopy
	return reqCopy, nil
}

func DoRequestWithUserAgent(client *http.Client, req *http.Request) (*http.Response, error) {
	req.Header.Set("User-Agent", userAgentForURL(req.URL))
	resp, err := client.Do(req)
	if err != nil {
		CheckAndLogISPBlocking(err, req.URL.String(), "HTTP")
	}
	return resp, err
}

type RetryConfig struct {
	MaxRetries    int
	InitialDelay  time.Duration
	MaxDelay      time.Duration
	BackoffFactor float64
}

func DefaultRetryConfig() RetryConfig {
	return RetryConfig{
		MaxRetries:    DefaultMaxRetries,
		InitialDelay:  DefaultRetryDelay,
		MaxDelay:      16 * time.Second,
		BackoffFactor: 2.0,
	}
}

func DoRequestWithRetry(client *http.Client, req *http.Request, config RetryConfig) (*http.Response, error) {
	var lastErr error
	delay := config.InitialDelay

	for attempt := 0; attempt <= config.MaxRetries; attempt++ {
		reqCopy := req.Clone(req.Context())
		reqCopy.Header.Set("User-Agent", userAgentForURL(reqCopy.URL))

		resp, err := client.Do(reqCopy)
		if err != nil {
			lastErr = err

			if isHardConnectivityBlock(err) {
				return nil, WrapErrorWithISPCheck(err, reqCopy.URL.String(), "HTTP")
			}

			if attempt < config.MaxRetries {
				GoLog("[HTTP] Request failed (attempt %d/%d): %v, retrying in %v...\n",
					attempt+1, config.MaxRetries+1, err, delay)
				if err := sleepRetry(req.Context(), delay); err != nil {
					return nil, err
				}
				delay = calculateNextDelay(delay, config)
			}
			continue
		}

		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			return resp, nil
		}

		if resp.StatusCode == 429 {
			resp.Body.Close()
			retryAfter := getRetryAfterDuration(resp)
			if retryAfter > 0 {
				delay = retryAfter
			}
			lastErr = fmt.Errorf("rate limited (429)")
			if attempt < config.MaxRetries {
				GoLog("[HTTP] Rate limited, waiting %v before retry...\n", delay)
				if err := sleepRetry(req.Context(), delay); err != nil {
					return nil, err
				}
				delay = calculateNextDelay(delay, config)
			}
			continue
		}

		if resp.StatusCode == 403 || resp.StatusCode == 451 {
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			bodyStr := strings.ToLower(string(body))

			ispBlockingIndicators := []string{
				"blocked", "forbidden", "access denied", "not available in your",
				"restricted", "censored", "unavailable for legal", "blocked by",
			}

			for _, indicator := range ispBlockingIndicators {
				if strings.Contains(bodyStr, indicator) {
					LogError("HTTP", "ISP BLOCKING DETECTED via HTTP %d response", resp.StatusCode)
					LogError("HTTP", "Domain: %s", req.URL.Host)
					LogError("HTTP", "Response contains: %s", indicator)
					LogError("HTTP", "Suggestion: Try using a VPN or changing your DNS to 1.1.1.1 or 8.8.8.8")
					return nil, fmt.Errorf("ISP blocking detected for %s (HTTP %d) - try using VPN or change DNS", req.URL.Host, resp.StatusCode)
				}
			}

			// No blocking marker: hand the caller back a readable body in
			// place of the one consumed by the scan above.
			resp.Body = io.NopCloser(bytes.NewReader(body))
		}

		if resp.StatusCode >= 500 {
			resp.Body.Close()
			if retryAfter := getRetryAfterDuration(resp); retryAfter > 0 {
				delay = retryAfter
			}
			lastErr = fmt.Errorf("server error: HTTP %d", resp.StatusCode)
			if attempt < config.MaxRetries {
				GoLog("[HTTP] Server error %d, retrying in %v...\n", resp.StatusCode, delay)
				if err := sleepRetry(req.Context(), delay); err != nil {
					return nil, err
				}
				delay = calculateNextDelay(delay, config)
			}
			continue
		}

		return resp, nil
	}

	return nil, fmt.Errorf("request failed after %d retries: %w", config.MaxRetries+1, lastErr)
}

// sleepRetry waits out a retry delay, aborting early when the request context
// is cancelled so a cancelled download never sits in a backoff sleep.
func sleepRetry(ctx context.Context, d time.Duration) error {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

// jitterFloat returns a fraction in [0,1); overridable in tests for
// deterministic backoff assertions.
var jitterFloat = rand.Float64

func calculateNextDelay(currentDelay time.Duration, config RetryConfig) time.Duration {
	nextDelay := time.Duration(float64(currentDelay) * config.BackoffFactor)
	capped := min(nextDelay, config.MaxDelay)
	// Full jitter: spread retries between InitialDelay and the capped
	// exponential ceiling to avoid synchronized thundering-herd retries.
	if capped <= config.InitialDelay {
		return capped
	}
	span := capped - config.InitialDelay
	return config.InitialDelay + time.Duration(jitterFloat()*float64(span))
}

// maxRetryAfterDelay caps honored Retry-After values so a hostile or
// misconfigured server cannot park a retry loop for an hour.
const maxRetryAfterDelay = 2 * time.Minute

// Returns 0 if the header is missing or invalid so callers can keep their
// normal exponential backoff instead of stalling for an arbitrary minute.
func getRetryAfterDuration(resp *http.Response) time.Duration {
	retryAfter := resp.Header.Get("Retry-After")
	if retryAfter == "" {
		return 0
	}

	if seconds, err := strconv.Atoi(retryAfter); err == nil {
		return min(time.Duration(seconds)*time.Second, maxRetryAfterDelay)
	}

	if t, err := http.ParseTime(retryAfter); err == nil {
		duration := time.Until(t)
		if duration > 0 {
			return min(duration, maxRetryAfterDelay)
		}
	}

	return 0
}

func ReadResponseBody(resp *http.Response) ([]byte, error) {
	if resp == nil {
		return nil, fmt.Errorf("response is nil")
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	if len(body) == 0 {
		return nil, fmt.Errorf("response body is empty")
	}

	return body, nil
}

type ISPBlockingError struct {
	Domain      string
	Reason      string
	OriginalErr error
}

func (e *ISPBlockingError) Error() string {
	return fmt.Sprintf("ISP blocking detected for %s: %s", e.Domain, e.Reason)
}

// isTransientNetworkError reports retryable transport failures such as
// timeouts and temporary DNS errors. Permanent DNS misses are excluded.
func isTransientNetworkError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
		return true
	}
	var netErr net.Error
	return errors.As(err, &netErr) && (netErr.Timeout() || netErr.Temporary())
}

// isConnectivityFailure reports DNS, dial, timeout, TLS, or truncated transport
// errors. Application-level API messages are excluded.
func isConnectivityFailure(err error) bool {
	return connectivityFailureReason(err) != ""
}

func connectivityFailureReason(err error) string {
	if err == nil {
		return ""
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return "Request timed out - ISP may be throttling"
	}
	if errors.Is(err, io.ErrUnexpectedEOF) {
		return "Connection closed unexpectedly - ISP may be blocking"
	}

	var urlErr *url.Error
	if errors.As(err, &urlErr) {
		if urlErr.Timeout() {
			return "Connection timed out - ISP may be blocking access"
		}
		if urlErr.Err != nil {
			if reason := connectivityFailureReason(urlErr.Err); reason != "" {
				return reason
			}
		}
	}

	var dnsErr *net.DNSError
	if errors.As(err, &dnsErr) {
		if dnsErr.IsNotFound || dnsErr.IsTimeout || dnsErr.IsTemporary {
			return "DNS resolution failed - domain may be blocked by ISP"
		}
	}

	var opErr *net.OpError
	if errors.As(err, &opErr) {
		if opErr.Timeout() {
			return "Connection timed out - ISP may be blocking access"
		}
		var errno syscall.Errno
		if errors.As(opErr.Err, &errno) {
			switch errno {
			case syscall.ECONNREFUSED:
				return "Connection refused - port may be blocked by ISP/firewall"
			case syscall.ECONNRESET:
				return "Connection reset - ISP may be intercepting traffic"
			case syscall.ETIMEDOUT:
				return "Connection timed out - ISP may be blocking access"
			case syscall.ENETUNREACH:
				return "Network unreachable - ISP may be blocking route"
			case syscall.EHOSTUNREACH:
				return "Host unreachable - ISP may be blocking destination"
			}
		}
	}

	var tlsErr *tls.RecordHeaderError
	if errors.As(err, &tlsErr) {
		return "TLS handshake failed - ISP may be intercepting HTTPS traffic"
	}

	var certErr x509.CertificateInvalidError
	if errors.As(err, &certErr) {
		return "Certificate error - ISP may be using MITM proxy"
	}
	var hostnameErr x509.HostnameError
	if errors.As(err, &hostnameErr) {
		return "Certificate error - ISP may be using MITM proxy"
	}
	var unknownAuth x509.UnknownAuthorityError
	if errors.As(err, &unknownAuth) {
		return "Certificate error - ISP may be using MITM proxy"
	}

	return ""
}

// isTLSHandshakeOrResetError reports TLS handshake/cert failures and TCP resets
// that should trigger a Chrome fingerprint retry.
func isTLSHandshakeOrResetError(err error) bool {
	if err == nil {
		return false
	}
	var recordErr *tls.RecordHeaderError
	if errors.As(err, &recordErr) {
		return true
	}
	var certErr x509.CertificateInvalidError
	if errors.As(err, &certErr) {
		return true
	}
	var hostnameErr x509.HostnameError
	if errors.As(err, &hostnameErr) {
		return true
	}
	var unknownAuth x509.UnknownAuthorityError
	if errors.As(err, &unknownAuth) {
		return true
	}
	var opErr *net.OpError
	if errors.As(err, &opErr) {
		var errno syscall.Errno
		if errors.As(opErr.Err, &errno) && errno == syscall.ECONNRESET {
			return true
		}
	}
	return false
}

// isHardConnectivityBlock reports transport failures that signal an active
// block (DNS not found, connection refused/reset, TLS/cert MITM) and should
// abort retries immediately. Timeouts and deadline-exceeded are treated as
// transient and excluded so they fall through to normal retry backoff.
func isHardConnectivityBlock(err error) bool {
	if err == nil {
		return false
	}

	var urlErr *url.Error
	if errors.As(err, &urlErr) && urlErr.Timeout() {
		return false
	}

	var dnsErr *net.DNSError
	if errors.As(err, &dnsErr) {
		return dnsErr.IsNotFound
	}

	var opErr *net.OpError
	if errors.As(err, &opErr) {
		if opErr.Timeout() {
			return false
		}
		var errno syscall.Errno
		if errors.As(opErr.Err, &errno) {
			switch errno {
			case syscall.ECONNREFUSED, syscall.ECONNRESET:
				return true
			}
		}
	}

	return isTLSHandshakeOrResetError(err)
}

func IsISPBlocking(err error, requestURL string) *ISPBlockingError {
	if err == nil {
		return nil
	}
	reason := connectivityFailureReason(err)
	if reason == "" {
		return nil
	}
	return &ISPBlockingError{
		Domain:      extractDomain(requestURL),
		Reason:      reason,
		OriginalErr: err,
	}
}

func CheckAndLogISPBlocking(err error, requestURL string, tag string) bool {
	ispErr := IsISPBlocking(err, requestURL)
	if ispErr != nil {
		LogError(tag, "ISP BLOCKING DETECTED: %s", ispErr.Error())
		LogError(tag, "Domain: %s", ispErr.Domain)
		LogError(tag, "Reason: %s", ispErr.Reason)
		LogError(tag, "Original error: %v", ispErr.OriginalErr)
		LogError(tag, "Suggestion: Try using a VPN or changing your DNS to 1.1.1.1 or 8.8.8.8")
		return true
	}
	return false
}

func extractDomain(rawURL string) string {
	if rawURL == "" {
		return "unknown"
	}

	parsed, err := url.Parse(rawURL)
	if err != nil {
		rawURL = strings.TrimPrefix(rawURL, "https://")
		rawURL = strings.TrimPrefix(rawURL, "http://")
		if idx := strings.Index(rawURL, "/"); idx > 0 {
			return rawURL[:idx]
		}
		return rawURL
	}

	if parsed.Host != "" {
		return parsed.Host
	}
	return "unknown"
}

func WrapErrorWithISPCheck(err error, requestURL string, tag string) error {
	if err == nil {
		return nil
	}

	if CheckAndLogISPBlocking(err, requestURL, tag) {
		domain := extractDomain(requestURL)
		return fmt.Errorf("ISP blocking detected for %s - try using VPN or change DNS to 1.1.1.1/8.8.8.8: %w", domain, err)
	}

	return err
}
