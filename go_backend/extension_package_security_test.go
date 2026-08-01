package gobackend

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWriteVerifiedExtensionPackageAcceptsMatchingSHA256(t *testing.T) {
	dir := t.TempDir()
	dest := filepath.Join(dir, "verified.spotiflac-ext")
	payload := []byte("extension package")
	checksum := fmt.Sprintf("%x", sha256.Sum256(payload))

	if err := writeVerifiedExtensionPackage(bytes.NewReader(payload), dest, checksum); err != nil {
		t.Fatalf("writeVerifiedExtensionPackage: %v", err)
	}
	got, err := os.ReadFile(dest)
	if err != nil {
		t.Fatalf("read verified package: %v", err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatalf("verified package = %q, want %q", got, payload)
	}
}

func TestWriteVerifiedExtensionPackageRejectsMismatchBeforeReplace(t *testing.T) {
	dir := t.TempDir()
	dest := filepath.Join(dir, "cached.spotiflac-ext")
	if err := os.WriteFile(dest, []byte("existing"), 0600); err != nil {
		t.Fatal(err)
	}

	err := writeVerifiedExtensionPackage(
		bytes.NewReader([]byte("tampered")),
		dest,
		strings.Repeat("0", sha256.Size*2),
	)
	if err == nil || !strings.Contains(err.Error(), "SHA-256 mismatch") {
		t.Fatalf("expected checksum mismatch, got %v", err)
	}
	got, readErr := os.ReadFile(dest)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if string(got) != "existing" {
		t.Fatalf("checksum failure replaced existing package with %q", got)
	}
}

func TestRegistrySkipsOnlyExtensionWithMalformedChecksum(t *testing.T) {
	checksum := strings.Repeat("a", sha256.Size*2)
	registry, err := parseRegistryBody([]byte(
		`{"version":1,"extensions":[` +
			`{"id":"bad","name":"bad","version":"1.0.0","sha256":"not-a-hash"},` +
			`{"id":"verified","name":"verified","version":"1.0.0","checksumSha256":"sha256:` +
			checksum +
			`"},` +
			`{"id":"legacy","name":"legacy","version":"1.0.0"}` +
			`]}`,
	))
	if err != nil {
		t.Fatalf("parse registry: %v", err)
	}
	if len(registry.Extensions) != 2 {
		t.Fatalf("registry extensions = %#v, want valid entries only", registry.Extensions)
	}
	if registry.Extensions[0].ID != "verified" || registry.Extensions[1].ID != "legacy" {
		t.Fatalf("registry extension order = %#v", registry.Extensions)
	}
	if got := registry.Extensions[0].getSHA256(); got != checksum {
		t.Fatalf("normalized checksum = %q, want %q", got, checksum)
	}
}

func TestExtensionPackageRequiresUniqueRootEntrypoints(t *testing.T) {
	dir := t.TempDir()
	duplicate := filepath.Join(dir, "duplicate.spotiflac-ext")
	createTestExtensionPackage(
		t,
		duplicate,
		"duplicate-ext",
		"1.0.0",
		`registerExtension({});`,
		map[string]string{"MANIFEST.JSON": "{}"},
	)

	reader, err := zip.OpenReader(duplicate)
	if err != nil {
		t.Fatal(err)
	}
	_, inspectErr := inspectExtensionPackage(reader.File)
	_ = reader.Close()
	if inspectErr == nil || !strings.Contains(inspectErr.Error(), "duplicate path") {
		t.Fatalf("expected duplicate archive path error, got %v", inspectErr)
	}

	nested := filepath.Join(dir, "nested.spotiflac-ext")
	writeTestZip(t, nested, map[string]string{
		"nested/manifest.json": validSecurityTestManifest("nested-ext"),
		"nested/index.js":      `registerExtension({});`,
	})
	reader, err = zip.OpenReader(nested)
	if err != nil {
		t.Fatal(err)
	}
	_, inspectErr = inspectExtensionPackage(reader.File)
	_ = reader.Close()
	if inspectErr == nil || !strings.Contains(inspectErr.Error(), "root manifest.json") {
		t.Fatalf("expected root entrypoint error, got %v", inspectErr)
	}
}

func TestExtensionPackageRejectsUnsafeAndOversizedEntries(t *testing.T) {
	for _, unsafePath := range []string{
		"../outside.js",
		`nested\outside.js`,
		"/absolute.js",
	} {
		t.Run(unsafePath, func(t *testing.T) {
			archivePath := filepath.Join(t.TempDir(), "unsafe.spotiflac-ext")
			writeTestZip(t, archivePath, map[string]string{
				"manifest.json": validSecurityTestManifest("unsafe-ext"),
				"index.js":      `registerExtension({});`,
				unsafePath:      "unsafe",
			})
			reader, err := zip.OpenReader(archivePath)
			if err != nil {
				t.Fatal(err)
			}
			_, inspectErr := inspectExtensionPackage(reader.File)
			_ = reader.Close()
			if inspectErr == nil || !strings.Contains(inspectErr.Error(), "unsafe path") {
				t.Fatalf("expected unsafe archive path error, got %v", inspectErr)
			}
		})
	}

	oversized := &zip.File{FileHeader: zip.FileHeader{
		Name:               "payload.bin",
		UncompressedSize64: maxExtensionArchiveUncompressedBytes + 1,
	}}
	if err := validateExtensionArchive([]*zip.File{oversized}); err == nil ||
		!strings.Contains(err.Error(), "extracted size limit") {
		t.Fatalf("expected extracted size error, got %v", err)
	}
}

func validSecurityTestManifest(name string) string {
	return fmt.Sprintf(
		`{"name":%q,"displayName":%q,"version":"1.0.0","description":"test","type":["metadata_provider"],"permissions":{}}`,
		name,
		name,
	)
}

func writeTestZip(t *testing.T, filePath string, files map[string]string) {
	t.Helper()
	output, err := os.Create(filePath)
	if err != nil {
		t.Fatal(err)
	}
	archive := zip.NewWriter(output)
	for name, content := range files {
		writer, createErr := archive.Create(name)
		if createErr != nil {
			t.Fatal(createErr)
		}
		if _, writeErr := writer.Write([]byte(content)); writeErr != nil {
			t.Fatal(writeErr)
		}
	}
	if err := archive.Close(); err != nil {
		t.Fatal(err)
	}
	if err := output.Close(); err != nil {
		t.Fatal(err)
	}
}
