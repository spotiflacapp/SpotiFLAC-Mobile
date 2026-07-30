package gobackend

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/dop251/goja"
)

// shortCleanEOFBodyReader simulates a transport that surfaces a mid-transfer
// connection drop as a normal io.EOF instead of io.ErrUnexpectedEOF (which is
// what a network reset looks like through some custom transports, e.g. the
// uTLS-based client this app uses for TLS-fingerprint spoofing). It sends
// data once and then reports a clean end of stream, even though fewer bytes
// were sent than the response's Content-Length promised.
type shortCleanEOFBodyReader struct {
	data []byte
	sent bool
}

func (f *shortCleanEOFBodyReader) Read(p []byte) (int, error) {
	if !f.sent {
		f.sent = true
		n := copy(p, f.data)
		return n, io.EOF
	}
	return 0, io.EOF
}

func TestFileDownloadShortCleanEOFFailsByDefaultEvenWithValidator(t *testing.T) {
	var attempts int
	runtime := newFileDownloadTestRuntime(t, func(req *http.Request) (*http.Response, error) {
		attempts++
		h := make(http.Header)
		h.Set("ETag", `"v1"`)
		return &http.Response{
			StatusCode:    200,
			Header:        h,
			Body:          io.NopCloser(&shortCleanEOFBodyReader{data: []byte("hello-")}),
			ContentLength: int64(len("hello-world!")),
			Request:       req,
		}, nil
	})

	// Resume is opt-in (see fileDownload's canResume comment), so a short
	// clean EOF must fail and clean up just like a real read error would,
	// not silently resume just because a validator happens to be present.
	result := runtime.fileDownload(goja.FunctionCall{Arguments: []goja.Value{
		runtime.vm.ToValue("https://cdn.example.com/track.flac"),
		runtime.vm.ToValue("out/track.flac"),
	}}).Export().(map[string]any)
	if result["success"] != false {
		t.Fatalf("expected failed download, got %#v", result)
	}
	if attempts != 1 {
		t.Fatalf("attempts = %d, want no automatic resume", attempts)
	}

	finalPath := filepath.Join(runtime.dataDir, "out", "track.flac")
	if _, err := os.Stat(finalPath); !os.IsNotExist(err) {
		t.Fatalf("truncated download was promoted to the final path: %v", err)
	}
	if _, err := os.Stat(stagedDownloadPath(finalPath)); !os.IsNotExist(err) {
		t.Fatalf("staged partial file left behind: %v", err)
	}
}

func TestFileDownloadResumesAfterShortCleanEOFWhenEnabled(t *testing.T) {
	const full = "hello-world!"
	var attempts int
	var resumeRange, resumeIfRange string
	runtime := newFileDownloadTestRuntime(t, func(req *http.Request) (*http.Response, error) {
		attempts++
		if attempts == 1 {
			h := make(http.Header)
			h.Set("ETag", `"v1"`)
			return &http.Response{
				StatusCode:    200,
				Header:        h,
				Body:          io.NopCloser(&shortCleanEOFBodyReader{data: []byte(full[:6])}),
				ContentLength: int64(len(full)),
				Request:       req,
			}, nil
		}
		resumeRange = req.Header.Get("Range")
		resumeIfRange = req.Header.Get("If-Range")
		h := make(http.Header)
		h.Set("Content-Range", fmt.Sprintf("bytes 6-%d/%d", len(full)-1, len(full)))
		return &http.Response{
			StatusCode:    206,
			Header:        h,
			Body:          io.NopCloser(&shortCleanEOFBodyReader{data: []byte(full[6:])}),
			ContentLength: int64(len(full) - 6),
			Request:       req,
		}, nil
	})

	result := runtime.fileDownload(goja.FunctionCall{Arguments: []goja.Value{
		runtime.vm.ToValue("https://cdn.example.com/track.flac"),
		runtime.vm.ToValue("out/track.flac"),
		runtime.vm.ToValue(map[string]any{"resume": true}),
	}}).Export().(map[string]any)
	if result["success"] != true {
		t.Fatalf("download result = %#v", result)
	}
	if attempts != 2 || resumeRange != "bytes=6-" || resumeIfRange != `"v1"` {
		t.Fatalf("attempts=%d range=%q if-range=%q", attempts, resumeRange, resumeIfRange)
	}

	finalPath := filepath.Join(runtime.dataDir, "out", "track.flac")
	data, err := os.ReadFile(finalPath)
	if err != nil || string(data) != full {
		t.Fatalf("final file = %q/%v (a truncated file was silently promoted)", data, err)
	}
}

func TestFileDownloadShortCleanEOFWithoutValidatorFails(t *testing.T) {
	runtime := newFileDownloadTestRuntime(t, func(req *http.Request) (*http.Response, error) {
		// No ETag/Last-Modified, so the download cannot be resumed and must
		// fail outright rather than promote a truncated file.
		return &http.Response{
			StatusCode:    200,
			Header:        make(http.Header),
			Body:          io.NopCloser(&shortCleanEOFBodyReader{data: []byte("partial-aud")}),
			ContentLength: 1 << 20,
			Request:       req,
		}, nil
	})

	result := runtime.fileDownload(goja.FunctionCall{Arguments: []goja.Value{
		runtime.vm.ToValue("https://cdn.example.com/track.flac"),
		runtime.vm.ToValue("out/track.flac"),
	}}).Export().(map[string]any)
	if result["success"] != false {
		t.Fatalf("expected a failed download for a short clean EOF with no validator, got %#v", result)
	}

	finalPath := filepath.Join(runtime.dataDir, "out", "track.flac")
	if _, err := os.Stat(finalPath); !os.IsNotExist(err) {
		t.Fatalf("truncated download was promoted to the final path: %v", err)
	}
	if _, err := os.Stat(stagedDownloadPath(finalPath)); !os.IsNotExist(err) {
		t.Fatalf("staged partial file left behind: %v", err)
	}
}
