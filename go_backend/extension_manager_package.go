package gobackend

import (
	"archive/zip"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
)

func compareVersions(v1, v2 string) int {
	parts1 := strings.Split(strings.TrimPrefix(v1, "v"), ".")
	parts2 := strings.Split(strings.TrimPrefix(v2, "v"), ".")

	maxLen := len(parts1)
	if len(parts2) > maxLen {
		maxLen = len(parts2)
	}

	for i := 0; i < maxLen; i++ {
		var n1, n2 int
		if i < len(parts1) {
			n1, _ = strconv.Atoi(parts1[i])
		}
		if i < len(parts2) {
			n2, _ = strconv.Atoi(parts2[i])
		}

		if n1 < n2 {
			return -1
		}
		if n1 > n2 {
			return 1
		}
	}

	return 0
}

func isExtensionPackagePath(filePath string) bool {
	lowerPath := strings.ToLower(filePath)
	return strings.HasSuffix(lowerPath, ".spotiflac-ext") || strings.HasSuffix(lowerPath, ".sflx")
}

func managedExtensionPath(root, extensionID string) (string, error) {
	if root == "" {
		return "", fmt.Errorf("extension directory is not configured")
	}
	if !extensionIDPattern.MatchString(extensionID) {
		return "", fmt.Errorf("invalid extension ID %q", extensionID)
	}
	fullPath := filepath.Join(root, extensionID)
	if !isPathWithinBase(root, fullPath) {
		return "", fmt.Errorf("extension path escapes its managed directory")
	}
	return fullPath, nil
}

func safeExtensionAssetPath(root, assetPath string) (string, bool) {
	if root == "" || assetPath == "" || filepath.IsAbs(assetPath) || strings.Contains(assetPath, `\`) {
		return "", false
	}
	cleaned := path.Clean(assetPath)
	if cleaned == "." || cleaned == ".." || strings.HasPrefix(cleaned, "../") {
		return "", false
	}
	fullPath := filepath.Join(root, filepath.FromSlash(cleaned))
	return fullPath, isPathWithinBase(root, fullPath)
}

const (
	maxExtensionArchiveEntries           = 2048
	maxExtensionArchiveUncompressedBytes = 256 * 1024 * 1024
	maxExtensionManifestBytes            = 1024 * 1024
)

func validateExtensionArchive(files []*zip.File) error {
	if len(files) > maxExtensionArchiveEntries {
		return fmt.Errorf(
			"extension archive contains too many entries (maximum %d)",
			maxExtensionArchiveEntries,
		)
	}

	seenPaths := make(map[string]struct{}, len(files))
	var totalUncompressed uint64
	for _, file := range files {
		if file.FileInfo().Mode()&os.ModeSymlink != 0 || strings.Contains(file.Name, `\`) {
			return fmt.Errorf("unsafe path in extension archive: %s", file.Name)
		}

		relPath := path.Clean(file.Name)
		if relPath == "." || relPath == ".." || strings.HasPrefix(relPath, "../") || path.IsAbs(relPath) {
			return fmt.Errorf("unsafe path in extension archive: %s", file.Name)
		}
		pathKey := strings.ToLower(relPath)
		if _, exists := seenPaths[pathKey]; exists {
			return fmt.Errorf("duplicate path in extension archive: %s", file.Name)
		}
		seenPaths[pathKey] = struct{}{}

		if file.FileInfo().IsDir() {
			continue
		}
		if file.UncompressedSize64 > maxExtensionArchiveUncompressedBytes-totalUncompressed {
			return fmt.Errorf(
				"extension archive exceeds the %d MiB extracted size limit",
				maxExtensionArchiveUncompressedBytes/(1024*1024),
			)
		}
		totalUncompressed += file.UncompressedSize64
	}
	return nil
}

func inspectExtensionPackage(files []*zip.File) (*ExtensionManifest, error) {
	if err := validateExtensionArchive(files); err != nil {
		return nil, err
	}

	var manifestFile *zip.File
	hasIndexJS := false
	for _, file := range files {
		switch path.Clean(file.Name) {
		case "manifest.json":
			manifestFile = file
		case "index.js":
			hasIndexJS = !file.FileInfo().IsDir()
		}
	}

	if manifestFile == nil || manifestFile.FileInfo().IsDir() {
		return nil, fmt.Errorf("invalid extension package: root manifest.json not found")
	}
	if !hasIndexJS {
		return nil, fmt.Errorf("invalid extension package: root index.js not found")
	}
	if manifestFile.UncompressedSize64 > maxExtensionManifestBytes {
		return nil, fmt.Errorf("invalid extension package: manifest.json is too large")
	}

	rc, err := manifestFile.Open()
	if err != nil {
		return nil, fmt.Errorf("failed to open manifest.json: %w", err)
	}
	manifestData, readErr := io.ReadAll(io.LimitReader(rc, maxExtensionManifestBytes+1))
	closeErr := rc.Close()
	if readErr != nil {
		return nil, fmt.Errorf("failed to read manifest.json: %w", readErr)
	}
	if closeErr != nil {
		return nil, fmt.Errorf("failed to close manifest.json: %w", closeErr)
	}
	if len(manifestData) > maxExtensionManifestBytes {
		return nil, fmt.Errorf("invalid extension package: manifest.json is too large")
	}

	manifest, err := ParseManifest(manifestData)
	if err != nil {
		return nil, fmt.Errorf("invalid extension manifest: %w", err)
	}
	return manifest, nil
}

func extractExtensionArchive(zipReader *zip.ReadCloser, destination string) error {
	if err := validateExtensionArchive(zipReader.File); err != nil {
		return err
	}
	for _, file := range zipReader.File {
		if file.FileInfo().IsDir() {
			continue
		}
		if file.FileInfo().Mode()&os.ModeSymlink != 0 || strings.Contains(file.Name, `\`) {
			return fmt.Errorf("unsafe path in extension archive: %s", file.Name)
		}

		relPath := path.Clean(file.Name)
		if relPath == "." || relPath == ".." || strings.HasPrefix(relPath, "../") || path.IsAbs(relPath) {
			return fmt.Errorf("unsafe path in extension archive: %s", file.Name)
		}
		destPath := filepath.Join(destination, filepath.FromSlash(relPath))
		if !isPathWithinBase(destination, destPath) {
			return fmt.Errorf("unsafe path in extension archive: %s", file.Name)
		}

		if err := os.MkdirAll(filepath.Dir(destPath), 0755); err != nil {
			return fmt.Errorf("failed to create extension directory: %w", err)
		}
		destFile, err := os.OpenFile(destPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
		if err != nil {
			return fmt.Errorf("failed to create extension file: %w", err)
		}
		srcFile, err := file.Open()
		if err != nil {
			destFile.Close()
			return fmt.Errorf("failed to open file in archive: %w", err)
		}
		_, copyErr := io.Copy(destFile, srcFile)
		closeSrcErr := srcFile.Close()
		closeDestErr := destFile.Close()
		if copyErr != nil {
			return fmt.Errorf("failed to extract extension file: %w", copyErr)
		}
		if closeSrcErr != nil || closeDestErr != nil {
			return fmt.Errorf("failed to close extracted extension file")
		}
	}
	return nil
}
