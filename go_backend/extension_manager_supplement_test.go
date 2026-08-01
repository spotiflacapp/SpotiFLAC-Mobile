package gobackend

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestExtensionManagerPackageLifecycle(t *testing.T) {
	dir := t.TempDir()
	extensionsDir := filepath.Join(dir, "extensions")
	dataDir := filepath.Join(dir, "data")
	manager := &extensionManager{extensions: map[string]*loadedExtension{}}
	if err := manager.SetDirectories(extensionsDir, dataDir); err != nil {
		t.Fatalf("SetDirectories: %v", err)
	}
	if err := GetExtensionSettingsStore().SetDataDir(dataDir); err != nil {
		t.Fatalf("settings data dir: %v", err)
	}

	js := `
var cleaned = false;
registerExtension({
  initialize: function(settings) { this.settings = settings || {}; },
  cleanup: function() { cleaned = true; },
  doAction: function() { return { message: "done", setting_updates: { quality: "lossless" } }; },
  getHomeFeed: function() { return [{ id: "home", title: "Home" }]; },
  getBrowseCategories: function() { return [{ id: "cat", title: "Category" }]; },
  searchTracks: function() { return { tracks: [], total: 0 }; },
  fetchLyrics: function() { return { syncType: "UNSYNCED", lines: [{ words: "hello" }] }; },
  getDownloadUrl: function() { return { url: "https://example.test/a.flac" }; }
});
`
	pkgV1 := filepath.Join(dir, "manager-ext-v1.spotiflac-ext")
	createTestExtensionPackage(t, pkgV1, "manager-ext", "1.0.0", js, nil)
	pkgV2 := filepath.Join(dir, "manager-ext-v2.spotiflac-ext")
	createTestExtensionPackage(t, pkgV2, "manager-ext", "1.1.0", js, nil)
	brokenUpgrade := filepath.Join(dir, "manager-ext-broken.spotiflac-ext")
	createTestExtensionPackage(t, brokenUpgrade, "manager-ext", "1.0.1", `registerExtension({`, nil)
	unsafePkg := filepath.Join(dir, "unsafe.spotiflac-ext")
	createTestExtensionPackage(t, unsafePkg, "manager-ext", "1.0.0", js, map[string]string{"../unsafe.txt": "blocked"})

	if compareVersions("v1.2.0", "1.1.9") <= 0 || compareVersions("1.0.0", "1.0") != 0 || compareVersions("1.0.0", "1.0.1") >= 0 {
		t.Fatal("compareVersions mismatch")
	}
	if _, err := manager.LoadExtensionFromFile(filepath.Join(dir, "bad.txt")); err == nil {
		t.Fatal("expected bad extension suffix error")
	}
	if _, err := manager.LoadExtensionFromFile(filepath.Join(dir, "missing.spotiflac-ext")); err == nil {
		t.Fatal("expected invalid package error")
	}
	if _, err := manager.LoadExtensionFromFile(unsafePkg); err == nil {
		t.Fatal("expected unsafe archive path to reject the package")
	}

	ext, err := manager.LoadExtensionFromFile(pkgV1)
	if err != nil {
		t.Fatalf("LoadExtensionFromFile: %v", err)
	}
	if ext.ID != "manager-ext" || ext.Enabled || ext.SourceDir == "" {
		t.Fatalf("loaded extension = %#v", ext)
	}
	if _, err := manager.LoadExtensionFromFile(pkgV1); err == nil {
		t.Fatal("expected duplicate version error")
	}

	installedJSON, err := manager.GetInstalledExtensionsJSON()
	if err != nil || !strings.Contains(installedJSON, "manager-ext") || !strings.Contains(installedJSON, "icon_path") {
		t.Fatalf("GetInstalledExtensionsJSON = %q/%v", installedJSON, err)
	}
	var installed []map[string]any
	if err := json.Unmarshal([]byte(installedJSON), &installed); err != nil || len(installed) != 1 {
		t.Fatalf("decode installed = %#v/%v", installed, err)
	}

	if err := GetExtensionSettingsStore().Set("manager-ext", "quality", "lossless"); err != nil {
		t.Fatalf("settings Set: %v", err)
	}
	if err := manager.SetExtensionEnabled("manager-ext", true); err != nil {
		t.Fatalf("enable extension: %v", err)
	}
	if !ext.Enabled || ext.VM == nil || !ext.initialized {
		t.Fatalf("enabled extension = %#v", ext)
	}
	if err := manager.InitializeExtension("manager-ext", map[string]any{"quality": "hires"}); err != nil {
		t.Fatalf("InitializeExtension: %v", err)
	}
	action, err := manager.InvokeAction("manager-ext", "doAction")
	if err != nil || action["success"] != true || action["message"] != "done" {
		t.Fatalf("InvokeAction = %#v/%v", action, err)
	}
	if err := manager.CleanupExtension("manager-ext"); err != nil {
		t.Fatalf("CleanupExtension: %v", err)
	}
	if err := manager.SetExtensionEnabled("manager-ext", false); err != nil {
		t.Fatalf("disable extension: %v", err)
	}
	if _, err := manager.UpgradeExtension(brokenUpgrade); err == nil {
		t.Fatal("expected invalid upgrade to be rejected")
	}
	stillInstalled, err := manager.GetExtension("manager-ext")
	if err != nil || stillInstalled.Manifest.Version != "1.0.0" {
		t.Fatalf("failed upgrade replaced the installed version: %#v/%v", stillInstalled, err)
	}
	if _, err := os.Stat(filepath.Join(stillInstalled.SourceDir, "index.js")); err != nil {
		t.Fatalf("failed upgrade removed the working source: %v", err)
	}
	if ext.VM != nil || ext.initialized {
		t.Fatalf("expected VM teardown, got %#v", ext)
	}
	if _, err := manager.InvokeAction("manager-ext", "doAction"); err == nil {
		t.Fatal("expected disabled action error")
	}

	upgradeJSON, err := manager.CheckExtensionUpgradeJSON(pkgV2)
	if err != nil || !strings.Contains(upgradeJSON, `"can_upgrade":true`) {
		t.Fatalf("CheckExtensionUpgradeJSON = %q/%v", upgradeJSON, err)
	}
	upgraded, err := manager.UpgradeExtension(pkgV2)
	if err != nil {
		t.Fatalf("UpgradeExtension: %v", err)
	}
	if upgraded.Manifest.Version != "1.1.0" {
		t.Fatalf("upgraded = %#v", upgraded.Manifest)
	}
	if _, err := manager.UpgradeExtension(pkgV1); err == nil {
		t.Fatal("expected downgrade error")
	}
	if err := manager.RemoveExtension("manager-ext"); err != nil {
		t.Fatalf("RemoveExtension: %v", err)
	}
	if _, err := manager.GetExtension("manager-ext"); err == nil {
		t.Fatal("expected removed extension missing")
	}

	dirExt := filepath.Join(extensionsDir, "dir-ext")
	if err := os.MkdirAll(dirExt, 0755); err != nil {
		t.Fatal(err)
	}
	manifest := `{"name":"dir-ext","displayName":"dir-ext","version":"1.0.0","description":"Directory extension","type":["metadata_provider"],"permissions":{}}`
	if err := os.WriteFile(filepath.Join(dirExt, "manifest.json"), []byte(manifest), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dirExt, "index.js"), []byte(`registerExtension({searchTracks:function(){return {tracks:[], total:0};}});`), 0600); err != nil {
		t.Fatal(err)
	}
	loaded, loadErrs := manager.LoadExtensionsFromDirectory(extensionsDir)
	if len(loadErrs) != 0 || len(loaded) != 1 || loaded[0] != "dir-ext" {
		t.Fatalf("LoadExtensionsFromDirectory = %#v/%#v", loaded, loadErrs)
	}
	manager.UnloadAllExtensions()
	if len(manager.GetAllExtensions()) != 0 {
		t.Fatal("expected all extensions unloaded")
	}
}

func TestValidateManifestGates(t *testing.T) {
	originalVersion := GetAppVersion()
	defer SetAppVersion(originalVersion)
	SetAppVersion("4.5.0")

	if err := validateManifestGates(nil); err != nil {
		t.Fatalf("nil manifest = %v", err)
	}
	if err := validateManifestGates(&ExtensionManifest{MinAppVersion: "4.9.0"}); err == nil {
		t.Fatal("expected minAppVersion gate to fail")
	}
	if err := validateManifestGates(&ExtensionManifest{MinAppVersion: "4.5.0"}); err != nil {
		t.Fatalf("equal version should pass: %v", err)
	}
	SetAppVersion("")
	if err := validateManifestGates(&ExtensionManifest{MinAppVersion: "9.9.9"}); err != nil {
		t.Fatalf("empty app version must skip the gate: %v", err)
	}
	SetAppVersion("4.5.0")

	pass := &ExtensionManifest{
		RequiredRuntimeFeatures: []string{"signedSession@3", "sessionGrant"},
	}
	if err := validateManifestGates(pass); err != nil {
		t.Fatalf("supported features should pass: %v", err)
	}
	if err := validateManifestGates(&ExtensionManifest{
		RequiredRuntimeFeatures: []string{"quantumDecrypt"},
	}); err == nil {
		t.Fatal("unknown feature must fail")
	}
	if err := validateManifestGates(&ExtensionManifest{
		RequiredRuntimeFeatures: []string{"signedSession@99"},
	}); err == nil {
		t.Fatal("future contract version must fail")
	}
}
