package gobackend

import (
	"archive/zip"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"

	"github.com/dop251/goja"
)

type loadedExtension struct {
	ID           string             `json:"id"`
	Manifest     *ExtensionManifest `json:"manifest"`
	VM           *goja.Runtime      `json:"-"`
	VMMu         sync.Mutex         `json:"-"`
	runtime      *extensionRuntime
	indexProgram *goja.Program
	initialized  bool
	Enabled      bool   `json:"enabled"`
	Error        string `json:"error,omitempty"`
	DataDir      string `json:"data_dir"`
	SourceDir    string `json:"source_dir"`
	IconPath     string `json:"icon_path"`

	isolatedPoolMu sync.Mutex
	isolatedPool   []*isolatedRuntimeHandle
}

type isolatedRuntimeHandle struct {
	vm      *goja.Runtime
	runtime *extensionRuntime
}

func getExtensionInitSettings(extensionID string) map[string]any {
	settings := GetExtensionSettingsStore().GetAll(extensionID)
	if len(settings) == 0 {
		return settings
	}

	filtered := make(map[string]any, len(settings))
	for key, value := range settings {
		if strings.HasPrefix(key, "_") {
			continue
		}
		filtered[key] = value
	}
	return filtered
}

func ensureRuntimeReadyLocked(ext *loadedExtension, applyStoredSettings bool) error {
	// Gate enabling too, so a package installed with a failed gate cannot be
	// switched on anyway.
	if err := validateManifestGates(ext.Manifest); err != nil {
		ext.Error = err.Error()
		ext.Enabled = false
		return err
	}
	if ext.VM == nil || ext.runtime == nil {
		if err := initializeVMLocked(ext); err != nil {
			ext.Error = err.Error()
			ext.Enabled = false
			return err
		}
	}

	if applyStoredSettings && !ext.initialized {
		settings := getExtensionInitSettings(ext.ID)
		if len(settings) > 0 {
			if err := initializeExtensionWithSettingsLocked(ext, settings); err != nil {
				teardownVMLocked(ext)
				ext.Error = err.Error()
				ext.Enabled = false
				return err
			}
		} else {
			ext.initialized = true
		}
	}

	ext.Error = ""
	return nil
}

func (ext *loadedExtension) ensureRuntimeReady() error {
	ext.VMMu.Lock()
	defer ext.VMMu.Unlock()

	return ensureRuntimeReadyLocked(ext, true)
}

func (ext *loadedExtension) lockReadyVM() (*goja.Runtime, error) {
	ext.VMMu.Lock()
	if err := ensureRuntimeReadyLocked(ext, true); err != nil {
		ext.VMMu.Unlock()
		return nil, err
	}
	return ext.VM, nil
}

type extensionManager struct {
	mu sync.RWMutex
	// mutationMu serializes install/upgrade/remove (heavy FS + goja VM
	// teardown/reload), which are not safe to run concurrently. Acquired before
	// m.mu; "*Locked" helpers assume it is held.
	mutationMu    sync.Mutex
	extensions    map[string]*loadedExtension
	extensionsDir string
	dataDir       string
}

var (
	globalExtManager     *extensionManager
	globalExtManagerOnce sync.Once
)

func getExtensionManager() *extensionManager {
	globalExtManagerOnce.Do(func() {
		globalExtManager = &extensionManager{
			extensions: make(map[string]*loadedExtension),
		}
	})
	return globalExtManager
}

func (m *extensionManager) SetDirectories(extensionsDir, dataDir string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.extensionsDir = extensionsDir
	m.dataDir = dataDir

	if err := os.MkdirAll(extensionsDir, 0755); err != nil {
		return fmt.Errorf("failed to create extensions directory: %w", err)
	}
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return fmt.Errorf("failed to create data directory: %w", err)
	}

	return nil
}

func (m *extensionManager) LoadExtensionFromFile(filePath string) (*loadedExtension, error) {
	m.mutationMu.Lock()
	defer m.mutationMu.Unlock()
	return m.loadExtensionFromFileLocked(filePath)
}

func (m *extensionManager) loadExtensionFromFileLocked(filePath string) (*loadedExtension, error) {
	if !isExtensionPackagePath(filePath) {
		return nil, fmt.Errorf("invalid file format: please select a .spotiflac-ext or .sflx file")
	}

	zipReader, err := zip.OpenReader(filePath)
	if err != nil {
		return nil, fmt.Errorf("cannot open extension file: the file may be corrupted or not a valid extension package")
	}
	defer zipReader.Close()

	manifest, err := inspectExtensionPackage(zipReader.File)
	if err != nil {
		return nil, err
	}

	m.mu.RLock()
	existing, exists := m.extensions[manifest.Name]
	var existingVersion string
	var existingDisplayName string
	if exists {
		existingVersion = existing.Manifest.Version
		existingDisplayName = existing.Manifest.DisplayName
	}
	m.mu.RUnlock()

	if exists {
		versionCompare := compareVersions(manifest.Version, existingVersion)
		if versionCompare > 0 {
			return m.upgradeExtensionLocked(filePath)
		} else if versionCompare == 0 {
			return nil, fmt.Errorf("extension '%s' v%s is already installed", existingDisplayName, existingVersion)
		} else {
			return nil, fmt.Errorf("cannot downgrade '%s' from v%s to v%s", existingDisplayName, existingVersion, manifest.Version)
		}
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	if _, exists := m.extensions[manifest.Name]; exists {
		return nil, fmt.Errorf("extension '%s' was installed by another process", manifest.DisplayName)
	}

	extDir, err := managedExtensionPath(m.extensionsDir, manifest.Name)
	if err != nil {
		return nil, err
	}
	if _, err := os.Lstat(extDir); err == nil {
		return nil, fmt.Errorf("extension directory already exists for %q", manifest.Name)
	} else if !os.IsNotExist(err) {
		return nil, fmt.Errorf("failed to inspect extension directory: %w", err)
	}
	stagingDir, err := os.MkdirTemp(m.extensionsDir, "."+manifest.Name+"-install-*")
	if err != nil {
		return nil, fmt.Errorf("failed to create extension staging directory: %w", err)
	}
	stagingCommitted := false
	defer func() {
		if !stagingCommitted {
			_ = os.RemoveAll(stagingDir)
		}
	}()
	if err := extractExtensionArchive(zipReader, stagingDir); err != nil {
		return nil, err
	}

	extDataDir, err := managedExtensionPath(m.dataDir, manifest.Name)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(extDataDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create extension data directory: %w", err)
	}

	ext := &loadedExtension{
		ID:        manifest.Name,
		Manifest:  manifest,
		Enabled:   false, // New extensions start disabled
		DataDir:   extDataDir,
		SourceDir: stagingDir,
	}

	if err := validateExtensionLoad(ext); err != nil {
		ext.Error = err.Error()
		ext.Enabled = false
		GoLog("[Extension] Failed to validate extension %s: %v\n", manifest.Name, err)
	}
	if err := os.Rename(stagingDir, extDir); err != nil {
		return nil, fmt.Errorf("failed to activate extension: %w", err)
	}
	stagingCommitted = true
	ext.SourceDir = extDir

	m.extensions[manifest.Name] = ext
	GoLog("[Extension] Loaded extension: %s v%s\n", manifest.DisplayName, manifest.Version)

	return ext, nil
}

var supportedRuntimeFeatures = map[string]int{
	"signedSession":  3,
	"sessionRefresh": 1,
	"sessionGrant":   1,
	"globalAction":   1,
	"webviewAuth":    1,
}

// validateManifestGates enforces minAppVersion and requiredRuntimeFeatures
// on every load path (.sflx install, upgrade, directory load); the Store UI
// check alone never covered manual installs. An empty app version (tests,
// dev harnesses) skips the version gate.
func validateManifestGates(manifest *ExtensionManifest) error {
	if manifest == nil {
		return nil
	}
	minVersion := strings.TrimSpace(manifest.MinAppVersion)
	appVersion := strings.TrimSpace(GetAppVersion())
	if minVersion != "" && appVersion != "" && compareVersions(appVersion, minVersion) < 0 {
		return fmt.Errorf("requires app %s or later (installed: %s)", minVersion, appVersion)
	}
	for _, raw := range manifest.RequiredRuntimeFeatures {
		name := strings.TrimSpace(raw)
		if name == "" {
			continue
		}
		wantVersion := 1
		if at := strings.LastIndex(name, "@"); at > 0 {
			if v, err := strconv.Atoi(name[at+1:]); err == nil && v > 0 {
				wantVersion = v
			}
			name = name[:at]
		}
		have, ok := supportedRuntimeFeatures[name]
		if !ok {
			return fmt.Errorf("requires runtime feature %q this app build does not provide", name)
		}
		if have < wantVersion {
			return fmt.Errorf("requires runtime feature %s@%d (app provides @%d)", name, wantVersion, have)
		}
	}
	return nil
}

func validateExtensionLoad(ext *loadedExtension) error {
	if err := validateManifestGates(ext.Manifest); err != nil {
		return err
	}

	ext.VMMu.Lock()
	defer ext.VMMu.Unlock()

	if err := initializeVMLocked(ext); err != nil {
		return err
	}
	teardownVMLocked(ext)
	return nil
}

func teardownExtension(ext *loadedExtension) {
	if ext == nil {
		return
	}
	ext.Enabled = false
	ext.VMMu.Lock()
	teardownVMLocked(ext)
	ext.VMMu.Unlock()
}

func (m *extensionManager) UnloadExtension(extensionID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	ext, exists := m.extensions[extensionID]
	if !exists {
		return fmt.Errorf("extension not found")
	}

	ext.Enabled = false
	ext.VMMu.Lock()
	teardownVMLocked(ext)
	ext.VMMu.Unlock()

	delete(m.extensions, extensionID)
	GoLog("[Extension] Unloaded extension: %s\n", extensionID)

	return nil
}

func (m *extensionManager) GetExtension(extensionID string) (*loadedExtension, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	ext, exists := m.extensions[extensionID]
	if !exists {
		return nil, fmt.Errorf("extension not found")
	}
	return ext, nil
}

func (m *extensionManager) GetAllExtensions() []*loadedExtension {
	m.mu.RLock()
	defer m.mu.RUnlock()

	result := make([]*loadedExtension, 0, len(m.extensions))
	for _, ext := range m.extensions {
		result = append(result, ext)
	}
	return result
}

func (m *extensionManager) SetExtensionEnabled(extensionID string, enabled bool) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	ext, exists := m.extensions[extensionID]
	if !exists {
		return fmt.Errorf("extension not found")
	}

	if enabled {
		ext.Enabled = true
		if err := ext.ensureRuntimeReady(); err != nil {
			store := GetExtensionSettingsStore()
			ext.Enabled = false
			_ = store.Set(extensionID, "_enabled", false)
			return err
		}
	} else {
		ext.Enabled = false
		ext.Error = ""
		ext.VMMu.Lock()
		teardownVMLocked(ext)
		ext.VMMu.Unlock()
	}
	GoLog("[Extension] %s %s\n", extensionID, map[bool]string{true: "enabled", false: "disabled"}[enabled])

	store := GetExtensionSettingsStore()
	if err := store.Set(extensionID, "_enabled", enabled); err != nil {
		GoLog("[Extension] Failed to persist enabled state for %s: %v\n", extensionID, err)
	}

	return nil
}

func (m *extensionManager) LoadExtensionsFromDirectory(dirPath string) ([]string, []error) {
	var loaded []string
	var errors []error

	entries, err := os.ReadDir(dirPath)
	if err != nil {
		if os.IsNotExist(err) {
			return loaded, errors
		}
		return nil, []error{fmt.Errorf("failed to read extensions directory: %w", err)}
	}

	for _, entry := range entries {
		if entry.IsDir() {
			manifestPath := filepath.Join(dirPath, entry.Name(), "manifest.json")
			if _, err := os.Stat(manifestPath); err == nil {
				ext, err := m.loadExtensionFromDirectory(filepath.Join(dirPath, entry.Name()))
				if err != nil {
					GoLog("[Extension] Failed to load %s: %v\n", entry.Name(), err)
					errors = append(errors, fmt.Errorf("%s: %w", entry.Name(), err))
				} else {
					loaded = append(loaded, ext.ID)
				}
			}
		} else if isExtensionPackagePath(entry.Name()) {
			ext, err := m.LoadExtensionFromFile(filepath.Join(dirPath, entry.Name()))
			if err != nil {
				GoLog("[Extension] Failed to load %s: %v\n", entry.Name(), err)
				errors = append(errors, fmt.Errorf("%s: %w", entry.Name(), err))
			} else {
				loaded = append(loaded, ext.ID)
			}
		}
	}

	return loaded, errors
}

func (m *extensionManager) loadExtensionFromDirectory(dirPath string) (*loadedExtension, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	manifestPath := filepath.Join(dirPath, "manifest.json")
	manifestData, err := os.ReadFile(manifestPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read manifest.json: %w", err)
	}

	manifest, err := ParseManifest(manifestData)
	if err != nil {
		return nil, fmt.Errorf("invalid extension manifest: %w", err)
	}

	indexPath := filepath.Join(dirPath, "index.js")
	if _, err := os.Stat(indexPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("extension is missing index.js file")
	}

	if existing, exists := m.extensions[manifest.Name]; exists {
		GoLog("[Extension] Extension '%s' already loaded, skipping\n", manifest.DisplayName)
		return existing, nil
	}

	expectedSourceDir, err := managedExtensionPath(m.extensionsDir, manifest.Name)
	if err != nil || filepath.Clean(dirPath) != filepath.Clean(expectedSourceDir) {
		return nil, fmt.Errorf("extension directory name must match manifest name %q", manifest.Name)
	}
	extDataDir, err := managedExtensionPath(m.dataDir, manifest.Name)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(extDataDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create extension data directory: %w", err)
	}

	ext := &loadedExtension{
		ID:        manifest.Name,
		Manifest:  manifest,
		Enabled:   false, // Will be restored from settings store
		DataDir:   extDataDir,
		SourceDir: dirPath,
	}

	store := GetExtensionSettingsStore()
	if enabledVal, err := store.Get(manifest.Name, "_enabled"); err == nil {
		if enabled, ok := enabledVal.(bool); ok {
			ext.Enabled = enabled
			GoLog("[Extension] Restored enabled state for %s: %v\n", manifest.Name, enabled)
		}
	}

	if err := validateExtensionLoad(ext); err != nil {
		ext.Error = err.Error()
		ext.Enabled = false
		GoLog("[Extension] Failed to validate extension %s: %v\n", manifest.Name, err)
	}

	m.extensions[manifest.Name] = ext
	GoLog("[Extension] Loaded extension: %s v%s\n", manifest.DisplayName, manifest.Version)

	return ext, nil
}

func (m *extensionManager) RemoveExtension(extensionID string) error {
	m.mutationMu.Lock()
	defer m.mutationMu.Unlock()

	ext, err := m.GetExtension(extensionID)
	if err != nil {
		return err
	}

	sourceDir, err := managedExtensionPath(m.extensionsDir, ext.ID)
	if err != nil || !isPathWithinBase(m.extensionsDir, ext.SourceDir) || filepath.Clean(ext.SourceDir) != filepath.Clean(sourceDir) {
		return fmt.Errorf("refusing to remove extension outside the managed source directory")
	}
	dataDir, err := managedExtensionPath(m.dataDir, ext.ID)
	if err != nil || !isPathWithinBase(m.dataDir, ext.DataDir) || filepath.Clean(ext.DataDir) != filepath.Clean(dataDir) {
		return fmt.Errorf("refusing to remove extension outside the managed data directory")
	}

	if err := m.UnloadExtension(extensionID); err != nil {
		return err
	}

	if err := os.RemoveAll(sourceDir); err != nil {
		GoLog("[Extension] Warning: failed to remove source dir: %v\n", err)
	}

	// Uninstall means gone: storage.json and encrypted credentials must not
	// linger on disk after the extension is removed.
	if err := os.RemoveAll(dataDir); err != nil {
		GoLog("[Extension] Warning: failed to remove data dir: %v\n", err)
	}

	return nil
}

// Only allows upgrades (new version > current version), not downgrades
func (m *extensionManager) UpgradeExtension(filePath string) (*loadedExtension, error) {
	m.mutationMu.Lock()
	defer m.mutationMu.Unlock()
	return m.upgradeExtensionLocked(filePath)
}

func (m *extensionManager) upgradeExtensionLocked(filePath string) (*loadedExtension, error) {
	if !isExtensionPackagePath(filePath) {
		return nil, fmt.Errorf("invalid file format: please select a .spotiflac-ext or .sflx file")
	}

	zipReader, err := zip.OpenReader(filePath)
	if err != nil {
		return nil, fmt.Errorf("cannot open extension file: the file may be corrupted or not a valid extension package")
	}
	defer zipReader.Close()

	newManifest, err := inspectExtensionPackage(zipReader.File)
	if err != nil {
		return nil, err
	}

	m.mu.RLock()
	existing, exists := m.extensions[newManifest.Name]
	m.mu.RUnlock()

	if !exists {
		return nil, fmt.Errorf("extension '%s' is not installed; use install instead of upgrade", newManifest.DisplayName)
	}

	versionCompare := compareVersions(newManifest.Version, existing.Manifest.Version)
	if versionCompare < 0 {
		return nil, fmt.Errorf("cannot downgrade extension: current version: %s, new version: %s", existing.Manifest.Version, newManifest.Version)
	}
	if versionCompare == 0 {
		return nil, fmt.Errorf("extension is already at version %s", existing.Manifest.Version)
	}

	GoLog("[Extension] Upgrading %s from v%s to v%s\n", newManifest.DisplayName, existing.Manifest.Version, newManifest.Version)

	extDataDir, err := managedExtensionPath(m.dataDir, newManifest.Name)
	if err != nil || filepath.Clean(existing.DataDir) != filepath.Clean(extDataDir) {
		return nil, fmt.Errorf("installed extension has an invalid data directory")
	}
	extDir, err := managedExtensionPath(m.extensionsDir, newManifest.Name)
	if err != nil || filepath.Clean(existing.SourceDir) != filepath.Clean(extDir) {
		return nil, fmt.Errorf("installed extension has an invalid source directory")
	}
	wasEnabled := existing.Enabled

	stagingDir, err := os.MkdirTemp(m.extensionsDir, "."+newManifest.Name+"-upgrade-*")
	if err != nil {
		return nil, fmt.Errorf("failed to create upgrade staging directory: %w", err)
	}
	stagingActive := true
	defer func() {
		if stagingActive {
			_ = os.RemoveAll(stagingDir)
		}
	}()
	if err := extractExtensionArchive(zipReader, stagingDir); err != nil {
		return nil, err
	}

	ext := &loadedExtension{
		ID:        newManifest.Name,
		Manifest:  newManifest,
		Enabled:   wasEnabled, // Preserve enabled state from before upgrade
		DataDir:   extDataDir,
		SourceDir: stagingDir,
	}

	if wasEnabled {
		if err := ext.ensureRuntimeReady(); err != nil {
			return nil, fmt.Errorf("upgraded extension failed validation: %w", err)
		}
	} else if err := validateExtensionLoad(ext); err != nil {
		return nil, fmt.Errorf("upgraded extension failed validation: %w", err)
	}

	backupDir, err := os.MkdirTemp(m.extensionsDir, "."+newManifest.Name+"-backup-*")
	if err != nil {
		teardownExtension(ext)
		return nil, fmt.Errorf("failed to prepare upgrade backup: %w", err)
	}
	if err := os.Remove(backupDir); err != nil {
		teardownExtension(ext)
		return nil, fmt.Errorf("failed to prepare upgrade backup: %w", err)
	}
	if err := os.Rename(extDir, backupDir); err != nil {
		teardownExtension(ext)
		return nil, fmt.Errorf("failed to preserve current extension: %w", err)
	}
	if err := os.Rename(stagingDir, extDir); err != nil {
		_ = os.Rename(backupDir, extDir)
		teardownExtension(ext)
		return nil, fmt.Errorf("failed to activate upgraded extension: %w", err)
	}
	stagingActive = false
	ext.SourceDir = extDir

	existing.Enabled = false
	if err := m.UnloadExtension(existing.ID); err != nil {
		_ = os.RemoveAll(extDir)
		_ = os.Rename(backupDir, extDir)
		existing.Enabled = wasEnabled
		teardownExtension(ext)
		return nil, fmt.Errorf("failed to unload current extension: %w", err)
	}

	m.mu.Lock()
	m.extensions[newManifest.Name] = ext
	m.mu.Unlock()
	if err := os.RemoveAll(backupDir); err != nil {
		GoLog("[Extension] Warning: failed to remove upgrade backup: %v\n", err)
	}

	GoLog("[Extension] Upgraded extension: %s to v%s\n", newManifest.DisplayName, newManifest.Version)

	return ext, nil
}

type ExtensionUpgradeInfo struct {
	ExtensionID    string `json:"extension_id"`
	CurrentVersion string `json:"current_version"`
	NewVersion     string `json:"new_version"`
	CanUpgrade     bool   `json:"can_upgrade"`
	IsInstalled    bool   `json:"is_installed"`
}

func (m *extensionManager) checkExtensionUpgradeInternal(filePath string) (*ExtensionUpgradeInfo, error) {
	if !isExtensionPackagePath(filePath) {
		return nil, fmt.Errorf("invalid file format: please select a .spotiflac-ext or .sflx file")
	}

	zipReader, err := zip.OpenReader(filePath)

	if err != nil {
		return nil, fmt.Errorf("cannot open extension file")
	}
	defer zipReader.Close()

	newManifest, err := inspectExtensionPackage(zipReader.File)
	if err != nil {
		return nil, err
	}

	m.mu.RLock()
	existing, exists := m.extensions[newManifest.Name]
	m.mu.RUnlock()

	info := &ExtensionUpgradeInfo{
		ExtensionID: newManifest.Name,
		NewVersion:  newManifest.Version,
		IsInstalled: exists,
	}

	if !exists {
		info.CurrentVersion = ""
		info.CanUpgrade = false
	} else {
		info.CurrentVersion = existing.Manifest.Version
		info.CanUpgrade = compareVersions(newManifest.Version, existing.Manifest.Version) > 0
	}

	return info, nil
}

func (m *extensionManager) CheckExtensionUpgradeJSON(filePath string) (string, error) {
	info, err := m.checkExtensionUpgradeInternal(filePath)
	if err != nil {
		return "", err
	}

	jsonBytes, err := json.Marshal(info)
	if err != nil {
		return "", err
	}

	return string(jsonBytes), nil
}

func (m *extensionManager) GetInstalledExtensionsJSON() (string, error) {
	extensions := m.GetAllExtensions()

	type ExtensionInfo struct {
		ID                     string                 `json:"id"`
		Name                   string                 `json:"name"`
		DisplayName            string                 `json:"display_name"`
		Version                string                 `json:"version"`
		Description            string                 `json:"description"`
		Homepage               string                 `json:"homepage,omitempty"`
		IconPath               string                 `json:"icon_path,omitempty"`
		Types                  []ExtensionType        `json:"types"`
		Enabled                bool                   `json:"enabled"`
		Status                 string                 `json:"status"`
		Error                  string                 `json:"error_message,omitempty"`
		Settings               []ExtensionSetting     `json:"settings,omitempty"`
		QualityOptions         []QualityOption        `json:"quality_options,omitempty"`
		Permissions            []string               `json:"permissions"`
		HasMetadataProvider    bool                   `json:"has_metadata_provider"`
		HasDownloadProvider    bool                   `json:"has_download_provider"`
		HasLyricsProvider      bool                   `json:"has_lyrics_provider"`
		SkipMetadataEnrichment bool                   `json:"skip_metadata_enrichment"`
		SkipLyrics             bool                   `json:"skip_lyrics"`
		StopProviderFallback   bool                   `json:"stop_provider_fallback"`
		SearchBehavior         *SearchBehaviorConfig  `json:"search_behavior,omitempty"`
		TrackMatching          *TrackMatchingConfig   `json:"track_matching,omitempty"`
		PostProcessing         *PostProcessingConfig  `json:"post_processing,omitempty"`
		ServiceHealth          []ExtensionHealthCheck `json:"service_health,omitempty"`
		Capabilities           map[string]any         `json:"capabilities,omitempty"`
	}

	infos := make([]ExtensionInfo, len(extensions))
	for i, ext := range extensions {
		permissions := []string{}
		for _, domain := range ext.Manifest.Permissions.Network {
			permissions = append(permissions, "network:"+domain)
		}
		if ext.Manifest.Permissions.Storage {
			permissions = append(permissions, "storage:enabled")
		}
		if ext.Manifest.Permissions.File {
			permissions = append(permissions, "file:enabled")
		}
		if ext.Manifest.Permissions.AllowHTTP {
			permissions = append(permissions, "network:http")
		}
		if ext.Manifest.HasCapability("rawFfmpeg") {
			permissions = append(permissions, "ffmpeg:raw")
		}

		status := "loaded"
		if ext.Error != "" {
			status = "error"
		} else if !ext.Enabled {
			status = "disabled"
		}

		iconPath := ""
		if ext.Manifest.Icon != "" && ext.SourceDir != "" {
			possibleIcon, safe := safeExtensionAssetPath(ext.SourceDir, ext.Manifest.Icon)
			if safe {
				if _, err := os.Stat(possibleIcon); err == nil {
					iconPath = possibleIcon
				}
			}
		}
		if iconPath == "" && ext.SourceDir != "" {
			possibleIcon, safe := safeExtensionAssetPath(ext.SourceDir, "icon.png")
			if safe {
				if _, err := os.Stat(possibleIcon); err == nil {
					iconPath = possibleIcon
				}
			}
		}

		infos[i] = ExtensionInfo{
			ID:                     ext.ID,
			Name:                   ext.Manifest.Name,
			DisplayName:            ext.Manifest.DisplayName,
			Version:                ext.Manifest.Version,
			Description:            ext.Manifest.Description,
			Homepage:               ext.Manifest.Homepage,
			IconPath:               iconPath,
			Types:                  ext.Manifest.Types,
			Enabled:                ext.Enabled,
			Status:                 status,
			Error:                  ext.Error,
			Settings:               ext.Manifest.Settings,
			QualityOptions:         ext.Manifest.QualityOptions,
			Permissions:            permissions,
			HasMetadataProvider:    ext.Manifest.IsMetadataProvider(),
			HasDownloadProvider:    ext.Manifest.IsDownloadProvider(),
			HasLyricsProvider:      ext.Manifest.IsLyricsProvider(),
			SkipMetadataEnrichment: ext.Manifest.SkipMetadataEnrichment,
			SkipLyrics:             ext.Manifest.SkipLyrics,
			StopProviderFallback:   ext.Manifest.StopsProviderFallback(),
			SearchBehavior:         ext.Manifest.SearchBehavior,
			TrackMatching:          ext.Manifest.TrackMatching,
			PostProcessing:         ext.Manifest.PostProcessing,
			ServiceHealth:          ext.Manifest.ServiceHealth,
			Capabilities:           ext.Manifest.Capabilities,
		}
	}

	jsonBytes, err := json.Marshal(infos)
	if err != nil {
		return "", err
	}

	return string(jsonBytes), nil
}

func (m *extensionManager) InitializeExtension(extensionID string, settings map[string]any) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	ext, exists := m.extensions[extensionID]
	if !exists {
		return fmt.Errorf("extension not found")
	}

	ext.VMMu.Lock()
	defer ext.VMMu.Unlock()

	if err := ensureRuntimeReadyLocked(ext, false); err != nil {
		return err
	}
	return initializeExtensionWithSettingsLocked(ext, settings)
}

func (m *extensionManager) CleanupExtension(extensionID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	ext, exists := m.extensions[extensionID]
	if !exists {
		return fmt.Errorf("extension not found")
	}

	if ext.VM == nil {
		return nil
	}
	ext.VMMu.Lock()
	defer ext.VMMu.Unlock()
	if err := runCleanupLocked(ext); err != nil {
		GoLog("[Extension] Cleanup error for %s: %v\n", extensionID, err)
		return err
	}
	GoLog("[Extension] Cleaned up %s\n", extensionID)
	return nil
}

func (m *extensionManager) UnloadAllExtensions() {
	m.mu.Lock()
	extensionIDs := make([]string, 0, len(m.extensions))
	for id := range m.extensions {
		extensionIDs = append(extensionIDs, id)
	}
	m.mu.Unlock()

	for _, id := range extensionIDs {
		m.UnloadExtension(id)
	}

	GoLog("[Extension] All extensions unloaded\n")
}

func (m *extensionManager) InvokeAction(extensionID string, actionName string) (map[string]any, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	ext, exists := m.extensions[extensionID]
	if !exists {
		return nil, fmt.Errorf("extension not found: %s", extensionID)
	}

	if !ext.Enabled {
		return nil, fmt.Errorf("extension is disabled")
	}
	vm, err := ext.lockReadyVM()
	if err != nil {
		return nil, err
	}
	defer ext.VMMu.Unlock()

	// Merge extension return values onto the top-level JSON object so Flutter can read
	// message, open_auth_url, setting_updates without unwrapping a nested "result" key.
	actionNameLiteral := strconv.Quote(actionName)
	script := fmt.Sprintf(`
			(function() {
				var actionName = %s;
				function runAction(fn) {
					try {
						var result = fn();
						if (result && typeof result.then === 'function') {
							return { success: true, pending: true, message: 'Action started' };
						}
					if (result !== null && result !== undefined && typeof result === 'object') {
						var isArr = false;
						if (typeof Array !== 'undefined' && Array.isArray) {
							isArr = Array.isArray(result);
						}
						if (!isArr) {
							var out = { success: true };
							for (var k in result) {
								out[k] = result[k];
							}
							return out;
						}
					}
					return { success: true, result: result };
					} catch (e) {
						return { success: false, error: e.toString() };
					}
				}
				if (typeof extension !== 'undefined' && extension && typeof extension[actionName] === 'function') {
					return runAction(function() { return extension[actionName](); });
				}
				if (actionName === 'completeGrant' && typeof session !== 'undefined' && session && typeof session.completeGrant === 'function') {
					return runAction(function() { return session.completeGrant(); });
				}
				return { success: false, error: 'Action function not found: ' + actionName };
			})()
		`, actionNameLiteral)

	result, err := RunWithTimeoutAndRecover(vm, script, DefaultJSTimeout)
	if err != nil {
		if IsRuntimeUnsafeError(err) {
			quarantineRuntimeLocked(ext, vm)
		}
		GoLog("[Extension] InvokeAction error for %s.%s: %v\n", extensionID, actionName, err)
		return nil, fmt.Errorf("action failed: %v", err)
	}

	if result == nil || goja.IsUndefined(result) {
		return map[string]any{"success": true}, nil
	}

	exported := result.Export()
	if resultMap, ok := exported.(map[string]any); ok {
		GoLog("[Extension] InvokeAction %s.%s result: %v\n", extensionID, actionName, resultMap)
		return resultMap, nil
	}

	return map[string]any{"success": true, "result": exported}, nil
}
