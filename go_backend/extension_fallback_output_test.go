package gobackend

import (
	"os"
	"path/filepath"
	"testing"
)

func TestShouldReuseExistingOutputProtectsCompletedFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "Artist - Track.flac")
	if err := os.WriteFile(path, []byte("existing audio"), 0o644); err != nil {
		t.Fatalf("write existing output: %v", err)
	}

	if !shouldReuseExistingOutput(DownloadRequest{}, path) {
		t.Fatal("expected completed output to be reused when variants are disabled")
	}
	if shouldReuseExistingOutput(
		DownloadRequest{AllowQualityVariant: true},
		path,
	) {
		t.Fatal("quality-variant staging output must remain independently writable")
	}
}

func TestShouldReuseExistingOutputIgnoresEmptyStagingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native_saf_work.flac")
	if err := os.WriteFile(path, nil, 0o644); err != nil {
		t.Fatalf("write staging output: %v", err)
	}

	if shouldReuseExistingOutput(DownloadRequest{}, path) {
		t.Fatal("empty staging output must not be treated as a completed download")
	}
}
