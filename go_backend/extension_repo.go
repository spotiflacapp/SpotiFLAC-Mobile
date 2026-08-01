package gobackend

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	CategoryMetadata    = "metadata"
	CategoryDownload    = "download"
	CategoryUtility     = "utility"
	CategoryLyrics      = "lyrics"
	CategoryIntegration = "integration"
)

type repoExtension struct {
	ID               string   `json:"id"`
	Name             string   `json:"name"`
	DisplayName      string   `json:"display_name,omitempty"`
	Version          string   `json:"version"`
	Description      string   `json:"description"`
	DownloadURL      string   `json:"download_url,omitempty"`
	IconURL          string   `json:"icon_url,omitempty"`
	Category         string   `json:"category"`
	Tags             []string `json:"tags,omitempty"`
	Downloads        int      `json:"downloads"`
	UpdatedAt        string   `json:"updated_at"`
	MinAppVersion    string   `json:"min_app_version,omitempty"`
	SHA256           string   `json:"sha256,omitempty"`
	ChecksumSHA256   string   `json:"checksum_sha256,omitempty"`
	DisplayNameAlt   string   `json:"displayName,omitempty"`
	DownloadURLAlt   string   `json:"downloadUrl,omitempty"`
	IconURLAlt       string   `json:"iconUrl,omitempty"`
	MinAppVersionAlt string   `json:"minAppVersion,omitempty"`
	ChecksumAlt      string   `json:"checksumSha256,omitempty"`
}

func (e *repoExtension) getDisplayName() string {
	if e.DisplayName != "" {
		return e.DisplayName
	}
	if e.DisplayNameAlt != "" {
		return e.DisplayNameAlt
	}
	return e.Name
}

func (e *repoExtension) getDownloadURL() string {
	if e.DownloadURL != "" {
		return e.DownloadURL
	}
	return e.DownloadURLAlt
}

func (e *repoExtension) getIconURL() string {
	if e.IconURL != "" {
		return e.IconURL
	}
	return e.IconURLAlt
}

func (e *repoExtension) getMinAppVersion() string {
	if e.MinAppVersion != "" {
		return e.MinAppVersion
	}
	return e.MinAppVersionAlt
}

func (e *repoExtension) getRawSHA256() string {
	return firstNonEmptyTrimmed(e.SHA256, e.ChecksumSHA256, e.ChecksumAlt)
}

func (e *repoExtension) getSHA256() string {
	return normalizeSHA256(e.getRawSHA256())
}

type repoRegistry struct {
	Version    int             `json:"version"`
	UpdatedAt  string          `json:"updated_at"`
	Extensions []repoExtension `json:"extensions"`
}

type repoExtensionResponse struct {
	ID               string   `json:"id"`
	Name             string   `json:"name"`
	DisplayName      string   `json:"display_name"`
	Version          string   `json:"version"`
	Description      string   `json:"description"`
	DownloadURL      string   `json:"download_url"`
	IconURL          string   `json:"icon_url,omitempty"`
	Category         string   `json:"category"`
	Tags             []string `json:"tags,omitempty"`
	Downloads        int      `json:"downloads"`
	UpdatedAt        string   `json:"updated_at"`
	MinAppVersion    string   `json:"min_app_version,omitempty"`
	SHA256           string   `json:"sha256,omitempty"`
	IsInstalled      bool     `json:"is_installed"`
	InstalledVersion string   `json:"installed_version,omitempty"`
	HasUpdate        bool     `json:"has_update"`
}

func (e *repoExtension) toResponse() repoExtensionResponse {
	resp := repoExtensionResponse{
		ID:            e.ID,
		Name:          e.Name,
		DisplayName:   e.getDisplayName(),
		Version:       e.Version,
		Description:   e.Description,
		DownloadURL:   e.getDownloadURL(),
		IconURL:       e.getIconURL(),
		Category:      e.Category,
		Downloads:     e.Downloads,
		UpdatedAt:     e.UpdatedAt,
		MinAppVersion: e.getMinAppVersion(),
		SHA256:        e.getSHA256(),
	}

	if len(e.Tags) > 0 {
		resp.Tags = append([]string(nil), e.Tags...)
	}

	return resp
}

type extensionRepo struct {
	registryURL string
	cacheDir    string
	cache       *repoRegistry
	cacheMu     sync.RWMutex
	cacheTime   time.Time
	cacheTTL    time.Duration
}

var (
	globalExtensionRepo *extensionRepo
	extensionRepoMu     sync.Mutex
)

const (
	cacheTTL      = 30 * time.Minute
	cacheFileName = "store_cache.json"
)

func initExtensionRepo(cacheDir string) *extensionRepo {
	extensionRepoMu.Lock()
	defer extensionRepoMu.Unlock()

	if globalExtensionRepo == nil {
		globalExtensionRepo = &extensionRepo{
			registryURL: "",
			cacheDir:    cacheDir,
			cacheTTL:    cacheTTL,
		}
		globalExtensionRepo.loadDiskCache()
	}
	return globalExtensionRepo
}

func (s *extensionRepo) setRegistryURL(registryURL string) {
	s.cacheMu.Lock()
	defer s.cacheMu.Unlock()

	if s.registryURL == registryURL {
		return
	}

	s.registryURL = registryURL
	s.cache = nil
	s.cacheTime = time.Time{}

	if s.cacheDir != "" {
		cachePath := filepath.Join(s.cacheDir, cacheFileName)
		os.Remove(cachePath)
	}

	LogInfo("ExtensionRepo", "Registry URL updated to: %s", registryURL)
}

func (s *extensionRepo) getRegistryURL() string {
	s.cacheMu.RLock()
	defer s.cacheMu.RUnlock()
	return s.registryURL
}

func getExtensionRepo() *extensionRepo {
	extensionRepoMu.Lock()
	defer extensionRepoMu.Unlock()
	return globalExtensionRepo
}

func (s *extensionRepo) loadDiskCache() {
	if s.cacheDir == "" {
		return
	}

	cachePath := filepath.Join(s.cacheDir, cacheFileName)
	data, err := os.ReadFile(cachePath)
	if err != nil {
		return
	}

	var cacheData struct {
		RegistryURL string       `json:"registry_url"`
		Registry    repoRegistry `json:"registry"`
		CacheTime   int64        `json:"cache_time"`
	}

	if err := json.Unmarshal(data, &cacheData); err != nil {
		return
	}

	s.cache = &cacheData.Registry
	s.cacheTime = time.Unix(cacheData.CacheTime, 0)
	if s.registryURL == "" {
		// Restore the URL that produced this cache so a later setRegistryURL
		// with the same URL keeps the cache instead of wiping it.
		s.registryURL = cacheData.RegistryURL
	}
	LogDebug("ExtensionRepo", "Loaded %d extensions from disk cache", len(s.cache.Extensions))
}

func (s *extensionRepo) saveDiskCache() {
	if s.cacheDir == "" || s.cache == nil {
		return
	}

	cacheData := struct {
		RegistryURL string       `json:"registry_url"`
		Registry    repoRegistry `json:"registry"`
		CacheTime   int64        `json:"cache_time"`
	}{
		RegistryURL: s.registryURL,
		Registry:    *s.cache,
		CacheTime:   s.cacheTime.Unix(),
	}

	data, err := json.Marshal(cacheData)
	if err != nil {
		return
	}

	cachePath := filepath.Join(s.cacheDir, cacheFileName)
	os.WriteFile(cachePath, data, 0644)
}

func (s *extensionRepo) fetchRegistry(forceRefresh bool) (*repoRegistry, error) {
	s.cacheMu.Lock()
	defer s.cacheMu.Unlock()

	if s.registryURL == "" {
		return nil, fmt.Errorf("no registry URL configured. Please add a repository URL first")
	}

	if !forceRefresh && s.cache != nil && time.Since(s.cacheTime) < s.cacheTTL {
		LogDebug("ExtensionRepo", "Using cached registry (%d extensions)", len(s.cache.Extensions))
		return s.cache, nil
	}

	if err := requireHTTPSURL(s.registryURL, "registry"); err != nil {
		return nil, err
	}

	LogInfo("ExtensionRepo", "Fetching registry from %s", s.registryURL)

	client := NewHTTPClientWithTimeout(30 * time.Second)
	req, err := http.NewRequest(http.MethodGet, s.registryURL, nil)
	if err != nil {
		if s.cache != nil {
			LogWarn("ExtensionRepo", "Failed to build registry request, using cached registry: %v", err)
			return s.cache, nil
		}
		return nil, fmt.Errorf("failed to build registry request: %w", err)
	}
	req.Header.Set("Cache-Control", "no-cache")
	req.Header.Set("Pragma", "no-cache")
	resp, err := client.Do(req)
	if err != nil {
		if s.cache != nil {
			LogWarn("ExtensionRepo", "Network error, using cached registry: %v", err)
			return s.cache, nil
		}
		return nil, fmt.Errorf("failed to fetch registry: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		if s.cache != nil {
			LogWarn("ExtensionRepo", "HTTP %d, using cached registry", resp.StatusCode)
			return s.cache, nil
		}
		return nil, fmt.Errorf("registry returned HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read registry: %w", err)
	}

	registry, err := parseRegistryBody(body)
	if err != nil {
		if s.cache != nil {
			LogWarn("ExtensionRepo", "Failed to parse registry, using cached registry: %v", err)
			return s.cache, nil
		}
		return nil, err
	}

	s.cache = registry
	s.cacheTime = time.Now()
	s.saveDiskCache()

	LogInfo("ExtensionRepo", "Fetched %d extensions from registry", len(registry.Extensions))
	return registry, nil
}

func parseRegistryBody(body []byte) (*repoRegistry, error) {
	var registry repoRegistry
	if err := json.Unmarshal(body, &registry); err != nil {
		if strings.HasPrefix(strings.TrimSpace(string(body)), "<") {
			return nil, fmt.Errorf("registry URL returned a web page instead of JSON. Make sure the URL points to a registry.json file or a GitHub repository that contains one")
		}
		return nil, fmt.Errorf("failed to parse registry: %w", err)
	}
	validExtensions := make([]repoExtension, 0, len(registry.Extensions))
	for index := range registry.Extensions {
		ext := &registry.Extensions[index]
		rawChecksum := ext.getRawSHA256()
		if rawChecksum != "" && normalizeSHA256(rawChecksum) == "" {
			LogWarn(
				"ExtensionRepo",
				"Skipping registry extension %q at index %d: invalid SHA-256 checksum",
				ext.ID,
				index,
			)
			continue
		}
		validExtensions = append(validExtensions, *ext)
	}
	registry.Extensions = validExtensions
	return &registry, nil
}

func (s *extensionRepo) getExtensionsWithStatus(forceRefresh bool) ([]repoExtensionResponse, error) {
	registry, err := s.fetchRegistry(forceRefresh)
	if err != nil {
		return nil, err
	}

	manager := getExtensionManager()
	installed := make(map[string]string) // id -> version

	if manager != nil {
		for _, ext := range manager.GetAllExtensions() {
			installed[ext.ID] = ext.Manifest.Version
		}
	}

	LogDebug("ExtensionRepo", "Building store response for %d registry extensions (%d installed)", len(registry.Extensions), len(installed))

	result := make([]repoExtensionResponse, 0, len(registry.Extensions))
	for i := range registry.Extensions {
		ext := &registry.Extensions[i]
		resp := ext.toResponse()
		if installedVersion, ok := installed[ext.ID]; ok {
			resp.IsInstalled = true
			resp.InstalledVersion = installedVersion
			resp.HasUpdate = compareVersions(ext.Version, installedVersion) > 0
		}

		result = append(result, resp)
	}

	LogDebug("ExtensionRepo", "Built store response payload for %d extensions", len(result))
	return result, nil
}

func (s *extensionRepo) findExtension(extensionID string) (*repoExtension, error) {
	registry, err := s.fetchRegistry(false)
	if err != nil {
		return nil, err
	}

	for _, e := range registry.Extensions {
		if e.ID == extensionID {
			ext := e
			return &ext, nil
		}
	}

	return nil, fmt.Errorf("extension %s not found in repo", extensionID)
}

func (s *extensionRepo) downloadExtension(extensionID string, destPath string) error {
	ext, err := s.findExtension(extensionID)
	if err != nil {
		return err
	}

	if err := requireHTTPSURL(ext.getDownloadURL(), "extension download"); err != nil {
		return err
	}

	LogInfo("ExtensionRepo", "Downloading %s from %s", ext.getDisplayName(), ext.getDownloadURL())

	client := NewHTTPClientWithTimeout(5 * time.Minute)
	req, err := http.NewRequest(http.MethodGet, ext.getDownloadURL(), nil)
	if err != nil {
		return fmt.Errorf("failed to build download request: %w", err)
	}
	req.Header.Set("Cache-Control", "no-cache")
	req.Header.Set("Pragma", "no-cache")
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to download: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("download returned HTTP %d", resp.StatusCode)
	}

	if err := writeVerifiedExtensionPackage(
		resp.Body,
		destPath,
		ext.getRawSHA256(),
	); err != nil {
		return err
	}

	LogInfo("ExtensionRepo", "Downloaded %s to %s", ext.getDisplayName(), destPath)
	return nil
}

const maxExtensionPackageBytes int64 = 64 * 1024 * 1024

func normalizeSHA256(value string) string {
	normalized := strings.ToLower(strings.TrimSpace(value))
	normalized = strings.TrimPrefix(normalized, "sha256:")
	if len(normalized) != sha256.Size*2 {
		return ""
	}
	for _, char := range normalized {
		if (char < '0' || char > '9') && (char < 'a' || char > 'f') {
			return ""
		}
	}
	return normalized
}

func writeVerifiedExtensionPackage(
	reader io.Reader,
	destPath string,
	expectedSHA256 string,
) error {
	if err := os.MkdirAll(filepath.Dir(destPath), 0755); err != nil {
		return fmt.Errorf("failed to prepare extension download directory: %w", err)
	}

	tempFile, err := os.CreateTemp(
		filepath.Dir(destPath),
		"."+filepath.Base(destPath)+".download-*",
	)
	if err != nil {
		return fmt.Errorf("failed to create extension download: %w", err)
	}
	tempPath := tempFile.Name()
	committed := false
	defer func() {
		_ = tempFile.Close()
		if !committed {
			_ = os.Remove(tempPath)
		}
	}()

	hasher := sha256.New()
	limited := &io.LimitedReader{R: reader, N: maxExtensionPackageBytes + 1}
	written, copyErr := io.Copy(io.MultiWriter(tempFile, hasher), limited)
	if copyErr != nil {
		return fmt.Errorf("failed to write extension package: %w", copyErr)
	}
	if written > maxExtensionPackageBytes {
		return fmt.Errorf(
			"extension package exceeds the %d MiB size limit",
			maxExtensionPackageBytes/(1024*1024),
		)
	}
	if err := tempFile.Sync(); err != nil {
		return fmt.Errorf("failed to flush extension package: %w", err)
	}
	if err := tempFile.Close(); err != nil {
		return fmt.Errorf("failed to close extension package: %w", err)
	}

	expected := normalizeSHA256(expectedSHA256)
	if strings.TrimSpace(expectedSHA256) != "" && expected == "" {
		return fmt.Errorf("registry contains an invalid extension SHA-256 checksum")
	}
	if expected != "" {
		actual := fmt.Sprintf("%x", hasher.Sum(nil))
		if subtle.ConstantTimeCompare([]byte(actual), []byte(expected)) != 1 {
			return fmt.Errorf(
				"extension package integrity check failed: SHA-256 mismatch",
			)
		}
	} else {
		LogWarn(
			"ExtensionRepo",
			"Registry entry has no SHA-256 checksum; package integrity cannot be verified",
		)
	}

	if err := os.Remove(destPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to replace cached extension package: %w", err)
	}
	if err := os.Rename(tempPath, destPath); err != nil {
		return fmt.Errorf("failed to publish extension package: %w", err)
	}
	committed = true
	return nil
}

func resolveRegistryURL(input string) (string, error) {
	input = strings.TrimSpace(input)
	if input == "" {
		return "", fmt.Errorf("registry URL is empty")
	}

	if strings.Contains(input, "raw.githubusercontent.com") {
		return input, nil
	}

	const ghPrefix = "https://github.com/"
	if !strings.HasPrefix(input, ghPrefix) {
		const ghPrefixHTTP = "http://github.com/"
		if strings.HasPrefix(input, ghPrefixHTTP) {
			input = "https://github.com/" + input[len(ghPrefixHTTP):]
		} else {
			return input, nil
		}
	}

	path := input[len(ghPrefix):]
	parts := strings.SplitN(path, "/", 3) // owner, repo, [rest]
	if len(parts) < 2 || parts[0] == "" || parts[1] == "" {
		return "", fmt.Errorf("invalid GitHub URL: expected github.com/<owner>/<repo>")
	}
	owner := parts[0]
	repo := strings.TrimSuffix(parts[1], ".git")

	branch := resolveGitHubDefaultBranch(owner, repo)

	resolved := fmt.Sprintf("https://raw.githubusercontent.com/%s/%s/%s/registry.json", owner, repo, branch)
	LogInfo("ExtensionRepo", "Resolved %s → %s (branch: %s)", input, resolved, branch)
	return resolved, nil
}

func resolveGitHubDefaultBranch(owner, repo string) string {
	apiURL := fmt.Sprintf("https://api.github.com/repos/%s/%s", owner, repo)
	client := NewHTTPClientWithTimeout(10 * time.Second)

	resp, err := client.Get(apiURL)
	if err != nil {
		LogWarn("ExtensionRepo", "GitHub API request failed for %s/%s: %v – falling back to main", owner, repo, err)
		return "main"
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		LogWarn("ExtensionRepo", "GitHub API returned %d for %s/%s – falling back to main", resp.StatusCode, owner, repo)
		return "main"
	}

	var info struct {
		DefaultBranch string `json:"default_branch"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil || info.DefaultBranch == "" {
		LogWarn("ExtensionRepo", "Could not parse default_branch for %s/%s – falling back to main", owner, repo)
		return "main"
	}

	return info.DefaultBranch
}

func requireHTTPSURL(rawURL string, context string) error {
	if rawURL == "" {
		return fmt.Errorf("%s URL is empty", context)
	}
	parsed, err := url.Parse(rawURL)
	if err != nil || parsed.Host == "" {
		return fmt.Errorf("%s URL is invalid: %s", context, rawURL)
	}
	if parsed.Scheme != "https" {
		return fmt.Errorf("%s URL must use https: %s", context, rawURL)
	}
	return nil
}

func (s *extensionRepo) getCategories() []string {
	return []string{
		CategoryMetadata,
		CategoryDownload,
		CategoryUtility,
		CategoryLyrics,
		CategoryIntegration,
	}
}

func (s *extensionRepo) searchExtensions(query string, category string) ([]repoExtensionResponse, error) {
	extensions, err := s.getExtensionsWithStatus(false)
	if err != nil {
		return nil, err
	}

	if query == "" && category == "" {
		return extensions, nil
	}

	result := make([]repoExtensionResponse, 0, len(extensions))
	queryLower := strings.ToLower(query)

	for _, ext := range extensions {
		if category != "" && ext.Category != category {
			continue
		}

		if query != "" {
			if !strings.Contains(strings.ToLower(ext.Name), queryLower) &&
				!strings.Contains(strings.ToLower(ext.DisplayName), queryLower) &&
				!strings.Contains(strings.ToLower(ext.Description), queryLower) {
				found := false
				for _, tag := range ext.Tags {
					if strings.Contains(strings.ToLower(tag), queryLower) {
						found = true
						break
					}
				}
				if !found {
					continue
				}
			}
		}

		result = append(result, ext)
	}

	return result, nil
}

func (s *extensionRepo) clearCache() {
	s.cacheMu.Lock()
	defer s.cacheMu.Unlock()

	s.cache = nil
	s.cacheTime = time.Time{}

	if s.cacheDir != "" {
		cachePath := filepath.Join(s.cacheDir, cacheFileName)
		os.Remove(cachePath)
	}

	LogInfo("ExtensionRepo", "Cache cleared")
}
