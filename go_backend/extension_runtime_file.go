package gobackend

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/dop251/goja"
)

var (
	allowedDownloadDirs   []string
	allowedDownloadDirsMu sync.RWMutex
)

func AddAllowedDownloadDir(dir string) {
	allowedDownloadDirsMu.Lock()
	defer allowedDownloadDirsMu.Unlock()
	absDir, err := filepath.Abs(dir)
	if err == nil {
		allowedDownloadDirs = append(allowedDownloadDirs, absDir)
	}
}

// SetAllowedDownloadDirs replaces the whole allow-list in one call (passing nil
// clears it). Used by tests to reset the sandbox between cases; production code
// appends via AddAllowedDownloadDir.
func SetAllowedDownloadDirs(dirs []string) {
	allowedDownloadDirsMu.Lock()
	defer allowedDownloadDirsMu.Unlock()
	allowedDownloadDirs = dirs
}

func isPathInAllowedDirs(absPath string) bool {
	allowedDownloadDirsMu.RLock()
	defer allowedDownloadDirsMu.RUnlock()

	for _, allowedDir := range allowedDownloadDirs {
		if isPathWithinBase(allowedDir, absPath) {
			return true
		}
	}
	return false
}

func isPathWithinBase(baseDir, targetPath string) bool {
	baseAbs, err := filepath.Abs(baseDir)
	if err != nil {
		return false
	}
	targetAbs, err := filepath.Abs(targetPath)
	if err != nil {
		return false
	}

	rel, err := filepath.Rel(baseAbs, targetAbs)
	if err != nil {
		return false
	}
	rel = filepath.Clean(rel)
	if rel == "." {
		return true
	}

	prefix := ".." + string(filepath.Separator)
	if rel == ".." || strings.HasPrefix(rel, prefix) {
		return false
	}
	return true
}

func (r *extensionRuntime) validatePath(path string) (string, error) {
	if !r.manifest.Permissions.File {
		return "", fmt.Errorf("file access denied: extension does not have 'file' permission")
	}

	cleanPath := filepath.Clean(path)

	if filepath.IsAbs(cleanPath) {
		absPath, err := filepath.Abs(cleanPath)
		if err != nil {
			return "", fmt.Errorf("invalid path: %w", err)
		}

		if isPathInAllowedDirs(absPath) {
			return absPath, nil
		}

		return "", fmt.Errorf("file access denied: absolute paths are not allowed. Use relative paths within extension sandbox")
	}

	fullPath := filepath.Join(r.dataDir, cleanPath)

	absPath, err := filepath.Abs(fullPath)
	if err != nil {
		return "", fmt.Errorf("invalid path: %w", err)
	}

	absDataDir, _ := filepath.Abs(r.dataDir)
	if !isPathWithinBase(absDataDir, absPath) {
		return "", fmt.Errorf("file access denied: path '%s' is outside sandbox", path)
	}

	return absPath, nil
}

func (r *extensionRuntime) fileDownload(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.jsError("URL and output path are required")
	}

	urlStr := call.Arguments[0].String()
	outputPath := call.Arguments[1].String()

	if err := r.validateDomain(urlStr); err != nil {
		return r.jsError("%s", err.Error())
	}

	fullPath, err := r.validatePath(outputPath)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	var onProgress goja.Callable
	var headers map[string]string
	var chunkedDownload bool
	var resumeDownload bool
	trackItemBytes := true
	var chunkSize int64
	if len(call.Arguments) > 2 && !goja.IsUndefined(call.Arguments[2]) && !goja.IsNull(call.Arguments[2]) {
		optionsObj := call.Arguments[2].Export()
		if opts, ok := optionsObj.(map[string]any); ok {
			if h, ok := opts["headers"].(map[string]any); ok {
				headers = make(map[string]string)
				for k, v := range h {
					headers[k] = fmt.Sprintf("%v", v)
				}
			}
			if progressVal, ok := opts["onProgress"]; ok {
				if callable, ok := goja.AssertFunction(r.vm.ToValue(progressVal)); ok {
					onProgress = callable
				}
			}
			if trackBytes, ok := opts["trackItemBytes"]; ok {
				if v, ok := trackBytes.(bool); ok {
					trackItemBytes = v
				}
			} else if trackBytes, ok := opts["track_item_bytes"]; ok {
				if v, ok := trackBytes.(bool); ok {
					trackItemBytes = v
				}
			}
			if chunked, ok := opts["chunked"]; ok {
				switch v := chunked.(type) {
				case bool:
					chunkedDownload = v
				case int64:
					if v > 0 {
						chunkedDownload = true
						chunkSize = v
					}
				case float64:
					if v > 0 {
						chunkedDownload = true
						chunkSize = int64(v)
					}
				}
			}
			if resume, ok := opts["resume"]; ok {
				if v, ok := resume.(bool); ok {
					resumeDownload = v
				}
			}
		}
	}

	// Default chunk size: 1MB (YouTube CDN max without poToken)
	if chunkedDownload && chunkSize <= 0 {
		chunkSize = 1024 * 1024
	}

	dir := filepath.Dir(fullPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return r.jsError("failed to create directory: %v", err)
	}

	client := r.downloadClient
	if client == nil {
		client = r.httpClient
	}

	ua := appUserAgent()
	if h, ok := headers["User-Agent"]; ok && h != "" {
		ua = h
	}

	if chunkedDownload {
		return r.fileDownloadChunked(client, urlStr, fullPath, headers, ua, chunkSize, onProgress, trackItemBytes)
	}

	unlock := lockDownloadOutputPath(fullPath)
	defer unlock()

	buildReq := func(rangeFrom int64, validator string) (*http.Request, *stallWatchdog, error) {
		req, err := http.NewRequest("GET", urlStr, nil)
		if err != nil {
			return nil, nil, err
		}
		req = r.bindDownloadCancelContext(req)
		req, wd := bindStallWatchdog(req, downloadStallTimeout)
		for k, v := range headers {
			req.Header.Set(k, v)
		}
		if req.Header.Get("User-Agent") == "" {
			req.Header.Set("User-Agent", appUserAgent())
		}
		if rangeFrom > 0 {
			req.Header.Set("Range", fmt.Sprintf("bytes=%d-", rangeFrom))
			req.Header.Set("If-Range", validator)
		}
		return req, wd, nil
	}

	req, wd, err := buildReq(0, "")
	if err != nil {
		return r.jsError("%s", err.Error())
	}
	defer func() { wd.stop() }()

	resp, err := client.Do(req)
	if err != nil {
		if wd.stalled.Load() {
			return r.stallError()
		}
		return r.jsError("%s", err.Error())
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		resp.Body.Close()
		return r.jsError("HTTP error: %d", resp.StatusCode)
	}

	// Stream into a staged sibling and promote via rename on success so a
	// killed process can never leave a partial file under the final name
	// (the duplicate check would then accept it as complete forever).
	stagedPath := stagedDownloadPath(fullPath)
	os.Remove(stagedPath)
	out, err := os.Create(stagedPath)
	if err != nil {
		resp.Body.Close()
		return r.jsError("failed to create file: %v", err)
	}
	promoted := false
	defer func() {
		out.Close()
		if !promoted {
			os.Remove(stagedPath)
		}
	}()

	activeItemID := r.getActiveDownloadItemID()
	if activeItemID != "" {
		SetItemDownloading(activeItemID)
	}

	contentLength := resp.ContentLength
	shouldTrackItemBytes := activeItemID != "" && trackItemBytes
	if shouldTrackItemBytes && contentLength > 0 {
		SetItemBytesTotal(activeItemID, contentLength)
	}

	makeProgressWriter := func() interface{ Write([]byte) (int, error) } {
		if shouldTrackItemBytes {
			return NewItemProgressWriter(out, activeItemID)
		}
		return out
	}
	progressWriter := makeProgressWriter()

	// resumeValidator picks a validator usable with If-Range: a strong ETag or
	// Last-Modified. Weak ETags (W/...) are not valid for If-Range.
	resumeValidator := func(h http.Header) string {
		if etag := h.Get("ETag"); etag != "" && !strings.HasPrefix(etag, "W/") {
			return etag
		}
		return h.Get("Last-Modified")
	}

	var written int64
	var lastProgressNotify int64
	buf := make([]byte, 32*1024)

	// copyBody streams resp into progressWriter. fatal is a terminal JS error
	// (write failure or user cancel); readErr is a network error eligible for
	// a Range resume.
	copyBody := func(resp *http.Response) (fatal goja.Value, readErr error) {
		defer resp.Body.Close()
		for {
			nr, er := resp.Body.Read(buf)
			if nr > 0 {
				wd.reset()
				nw, ew := progressWriter.Write(buf[0:nr])
				if nw < 0 || nr < nw {
					nw = 0
					if ew == nil {
						ew = fmt.Errorf("invalid write result")
					}
				}
				written += int64(nw)
				if ew != nil {
					if ew == ErrDownloadCancelled {
						return r.jsError("download cancelled"), nil
					}
					return r.jsError("failed to write file: %v", ew), nil
				}
				if nr != nw {
					return r.jsError("short write"), nil
				}

				// Throttle the JS callback like the native progress writer:
				// per-read invocation is interpreter work inside the copy loop.
				if onProgress != nil && contentLength > 0 &&
					(written-lastProgressNotify >= progressUpdateThreshold || written >= contentLength) {
					lastProgressNotify = written
					_, _ = onProgress(goja.Undefined(), r.vm.ToValue(written), r.vm.ToValue(contentLength))
				}
			}
			if er != nil {
				if er != io.EOF {
					return nil, er
				}
				return nil, nil
			}
		}
	}

	// Mid-body resume is opt-in because switching networks can route a stable
	// URL to a different CDN object even when its validator is unchanged. The
	// safe default is to fail and delete the staged partial file. Extensions
	// that know their origin supports byte-identical Range resumes can request
	// it explicitly with { resume: true }.
	validator := resumeValidator(resp.Header)
	_, callerSetRange := headers["Range"]
	canResume := resumeDownload && validator != "" && !callerSetRange

	const maxResumes = 3
	resumes := 0
	for {
		fatal, readErr := copyBody(resp)
		if fatal != nil {
			return fatal
		}
		if readErr == nil {
			break
		}

		stalled := wd.stalled.Load()
		if !canResume || resumes >= maxResumes ||
			(activeItemID != "" && isDownloadCancelled(activeItemID)) {
			if stalled {
				return r.stallError()
			}
			return r.jsError("failed to read response: %v", readErr)
		}
		resumes++
		GoLog("[Extension:%s] Download interrupted at %d bytes (%v), resuming (attempt %d/%d)\n",
			r.extensionID, written, readErr, resumes, maxResumes)

		wd.stop()
		var resumeReq *http.Request
		resumeReq, wd, err = buildReq(written, validator)
		if err != nil {
			return r.jsError("%s", err.Error())
		}
		resp, err = client.Do(resumeReq)
		if err != nil {
			if wd.stalled.Load() {
				return r.stallError()
			}
			return r.jsError("resume failed at %d bytes: %v", written, err)
		}

		switch resp.StatusCode {
		case http.StatusPartialContent:
			if written > 0 && !strings.HasPrefix(resp.Header.Get("Content-Range"), fmt.Sprintf("bytes %d-", written)) {
				cr := resp.Header.Get("Content-Range")
				resp.Body.Close()
				return r.jsError("resume failed: unexpected Content-Range %q at %d bytes", cr, written)
			}
		case http.StatusOK:
			// Range ignored or file changed under If-Range: restart from zero
			// on the same staged file.
			if err := out.Truncate(0); err != nil {
				resp.Body.Close()
				return r.jsError("failed to restart download: %v", err)
			}
			if _, err := out.Seek(0, io.SeekStart); err != nil {
				resp.Body.Close()
				return r.jsError("failed to restart download: %v", err)
			}
			written = 0
			progressWriter = makeProgressWriter()
			if resp.ContentLength > 0 {
				contentLength = resp.ContentLength
				if shouldTrackItemBytes {
					SetItemBytesTotal(activeItemID, contentLength)
				}
			}
			validator = resumeValidator(resp.Header)
			canResume = resumeDownload && validator != ""
		default:
			code := resp.StatusCode
			resp.Body.Close()
			return r.jsError("resume failed: HTTP %d at %d bytes", code, written)
		}
	}

	if shouldTrackItemBytes {
		if contentLength > 0 {
			SetItemProgress(activeItemID, float64(written)/float64(contentLength), written, contentLength)
		} else if written > 0 {
			SetItemBytesReceived(activeItemID, written)
		}
	}

	// Sync before the promote rename so a power loss right after the rename
	// cannot leave a truncated file under the final name.
	if err := out.Sync(); err != nil {
		return r.jsError("failed to sync file: %v", err)
	}
	if err := out.Close(); err != nil {
		return r.jsError("failed to finalize file: %v", err)
	}
	if err := os.Rename(stagedPath, fullPath); err != nil {
		return r.jsError("failed to publish file: %v", err)
	}
	promoted = true
	syncDir(filepath.Dir(fullPath))

	GoLog("[Extension:%s] Downloaded %d bytes to %s\n", r.extensionID, written, fullPath)

	return r.jsSuccess(map[string]any{
		"path": fullPath,
		"size": written,
	})
}

// fileDownloadChunked downloads a URL using sequential Range requests.
// This is needed for servers (like YouTube's googlevideo CDN) that reject
// non-ranged or large-range requests with 403 and require small chunk downloads.
func (r *extensionRuntime) fileDownloadChunked(client *http.Client, urlStr, fullPath string, headers map[string]string, ua string, chunkSize int64, onProgress goja.Callable, trackItemBytes bool) goja.Value {
	unlock := lockDownloadOutputPath(fullPath)
	defer unlock()

	// First, get the total content length with a small probe request
	probeReq, err := http.NewRequest("GET", urlStr, nil)
	if err != nil {
		return r.jsError("chunked: probe request error: %v", err)
	}
	probeReq = r.bindDownloadCancelContext(probeReq)
	probeReq, wd := bindStallWatchdog(probeReq, downloadStallTimeout)
	defer wd.stop()
	stallCtx := probeReq.Context()
	probeReq.Header.Set("User-Agent", ua)
	for k, v := range headers {
		if k != "Range" { // Don't copy any existing Range header
			probeReq.Header.Set(k, v)
		}
	}
	probeReq.Header.Set("Range", "bytes=0-1")

	probeResp, err := client.Do(probeReq)
	if err != nil {
		if wd.stalled.Load() {
			return r.stallError()
		}
		return r.jsError("chunked: probe error: %v", err)
	}
	io.Copy(io.Discard, probeResp.Body)
	probeResp.Body.Close()

	if probeResp.StatusCode != 206 && probeResp.StatusCode != 200 {
		return r.jsError("chunked: probe HTTP %d", probeResp.StatusCode)
	}

	// Parse Content-Range to get total size: "bytes 0-1/TOTAL"
	var totalSize int64
	contentRange := probeResp.Header.Get("Content-Range")
	if contentRange != "" {
		if idx := strings.LastIndex(contentRange, "/"); idx >= 0 {
			sizeStr := contentRange[idx+1:]
			if sizeStr != "*" {
				fmt.Sscanf(sizeStr, "%d", &totalSize)
			}
		}
	}

	if totalSize <= 0 {
		// Fallback: try Content-Length from a HEAD-like approach
		// If we can't determine size, download with unknown size
		GoLog("[Extension:%s] Chunked download: unknown total size, will download until server says done\n", r.extensionID)
	} else {
		GoLog("[Extension:%s] Chunked download: total size %d bytes, chunk size %d\n", r.extensionID, totalSize, chunkSize)
	}

	// Same staged-write-then-promote protocol as fileDownload: never leave a
	// partial file under the final name.
	stagedPath := stagedDownloadPath(fullPath)
	os.Remove(stagedPath)
	out, err := os.Create(stagedPath)
	if err != nil {
		return r.jsError("failed to create file: %v", err)
	}
	promoted := false
	defer func() {
		out.Close()
		if !promoted {
			os.Remove(stagedPath)
		}
	}()

	activeItemID := r.getActiveDownloadItemID()
	if activeItemID != "" {
		SetItemDownloading(activeItemID)
	}

	shouldTrackItemBytes := activeItemID != "" && trackItemBytes
	if shouldTrackItemBytes && totalSize > 0 {
		SetItemBytesTotal(activeItemID, totalSize)
	}

	var progressWriter interface{ Write([]byte) (int, error) } = out
	if shouldTrackItemBytes {
		progressWriter = NewItemProgressWriter(out, activeItemID)
	}

	var totalWritten int64
	var lastProgressNotify int64
	buf := make([]byte, 32*1024)
	maxRetries := 3

	for offset := int64(0); totalSize <= 0 || offset < totalSize; {
		end := offset + chunkSize - 1
		if totalSize > 0 && end >= totalSize {
			end = totalSize - 1
		}

		var chunkResp *http.Response
		var chunkErr error

		for retry := 0; retry < maxRetries; retry++ {
			chunkReq, err := http.NewRequest("GET", urlStr, nil)
			if err != nil {
				return r.jsError("chunked: request error at offset %d: %v", offset, err)
			}
			chunkReq = chunkReq.WithContext(stallCtx)
			chunkReq.Header.Set("User-Agent", ua)
			for k, v := range headers {
				if k != "Range" {
					chunkReq.Header.Set(k, v)
				}
			}
			chunkReq.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", offset, end))

			chunkResp, chunkErr = client.Do(chunkReq)
			if chunkErr != nil {
				if wd.stalled.Load() {
					return r.stallError()
				}
				if retry < maxRetries-1 {
					time.Sleep(time.Duration(retry+1) * time.Second)
					continue
				}
				return r.jsError("chunked: error at offset %d after %d retries: %v", offset, maxRetries, chunkErr)
			}

			if chunkResp.StatusCode == 206 || chunkResp.StatusCode == 200 {
				break // Success
			}

			io.Copy(io.Discard, chunkResp.Body)
			chunkResp.Body.Close()

			if chunkResp.StatusCode == 403 || chunkResp.StatusCode == 429 {
				if retry < maxRetries-1 {
					time.Sleep(time.Duration(retry+1) * 2 * time.Second)
					continue
				}
			}

			return r.jsError("chunked: HTTP %d at offset %d", chunkResp.StatusCode, offset)
		}

		chunkWritten := int64(0)
		for {
			nr, er := chunkResp.Body.Read(buf)
			if nr > 0 {
				wd.reset()
				nw, ew := progressWriter.Write(buf[0:nr])
				if nw < 0 || nr < nw {
					nw = 0
					if ew == nil {
						ew = fmt.Errorf("invalid write result")
					}
				}
				chunkWritten += int64(nw)
				totalWritten += int64(nw)
				if ew != nil {
					chunkResp.Body.Close()
					if ew == ErrDownloadCancelled {
						return r.jsError("download cancelled")
					}
					return r.jsError("failed to write file: %v", ew)
				}
				if nr != nw {
					chunkResp.Body.Close()
					return r.jsError("short write")
				}

				if onProgress != nil && totalSize > 0 &&
					(totalWritten-lastProgressNotify >= progressUpdateThreshold || totalWritten >= totalSize) {
					lastProgressNotify = totalWritten
					_, _ = onProgress(goja.Undefined(), r.vm.ToValue(totalWritten), r.vm.ToValue(totalSize))
				}
			}
			if er != nil {
				if er != io.EOF {
					chunkResp.Body.Close()
					if wd.stalled.Load() {
						return r.stallError()
					}
					return r.jsError("failed to read chunk at offset %d: %v", offset, er)
				}
				break
			}
		}
		chunkResp.Body.Close()

		offset += chunkWritten

		// If server returned 200 (full content) instead of 206, we're done
		if chunkResp.StatusCode == 200 {
			break
		}

		// If we got less data than expected and we know total size, check if done
		if totalSize > 0 && offset >= totalSize {
			break
		}

		// Unknown size: if we got less than chunk size, assume done
		if totalSize <= 0 && chunkWritten < chunkSize {
			break
		}
	}

	if shouldTrackItemBytes {
		if totalSize > 0 {
			SetItemProgress(activeItemID, float64(totalWritten)/float64(totalSize), totalWritten, totalSize)
		} else if totalWritten > 0 {
			SetItemBytesReceived(activeItemID, totalWritten)
		}
	}

	// Sync before the promote rename so a power loss right after the rename
	// cannot leave a truncated file under the final name.
	if err := out.Sync(); err != nil {
		return r.jsError("failed to sync file: %v", err)
	}
	if err := out.Close(); err != nil {
		return r.jsError("failed to finalize file: %v", err)
	}
	if err := os.Rename(stagedPath, fullPath); err != nil {
		return r.jsError("failed to publish file: %v", err)
	}
	promoted = true
	syncDir(filepath.Dir(fullPath))

	GoLog("[Extension:%s] Chunked download complete: %d bytes to %s\n", r.extensionID, totalWritten, fullPath)

	return r.jsSuccess(map[string]any{
		"path": fullPath,
		"size": totalWritten,
	})
}

func (r *extensionRuntime) fileExists(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(false)
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.vm.ToValue(false)
	}

	_, err = os.Stat(fullPath)
	return r.vm.ToValue(err == nil)
}

func (r *extensionRuntime) fileDelete(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.jsError("path is required")
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	if err := os.Remove(fullPath); err != nil {
		return r.jsError("%s", err.Error())
	}

	return r.jsSuccess(nil)
}

func (r *extensionRuntime) fileRead(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.jsError("path is required")
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	file, err := os.Open(fullPath)
	if err != nil {
		return r.jsError("%s", err.Error())
	}
	defer file.Close()

	data, err := io.ReadAll(io.LimitReader(file, maxExtensionFileReadBytes+1))
	if err != nil {
		return r.jsError("%s", err.Error())
	}
	if int64(len(data)) > maxExtensionFileReadBytes {
		return r.jsError(extensionFileReadLimitError)
	}

	return r.jsSuccess(map[string]any{
		"data": string(data),
	})
}

const (
	maxExtensionFileReadBytes   = int64(16 << 20)
	extensionFileReadLimitError = "file read exceeds 16 MiB limit; use file.readBytes with offset and length to read it in chunks"
)

func extensionFileReadLength(size, offset, requested int64) (int64, error) {
	remaining := size - offset
	if remaining < 0 {
		remaining = 0
	}

	if requested < 0 {
		if remaining > maxExtensionFileReadBytes {
			return 0, fmt.Errorf("%s", extensionFileReadLimitError)
		}
		return remaining, nil
	}
	if requested > maxExtensionFileReadBytes {
		return 0, fmt.Errorf("%s", extensionFileReadLimitError)
	}
	return min(requested, remaining), nil
}

func (r *extensionRuntime) fileReadBytes(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.jsError("path is required")
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	options := parseRuntimeOptionsArgument(call, 1)
	offset := runtimeOptionInt64(options, "offset", 0)
	length := runtimeOptionInt64(options, "length", -1)
	encoding := runtimeOptionString(options, "encoding", "base64")
	if offset < 0 {
		return r.jsError("offset must be >= 0")
	}
	file, err := os.Open(fullPath)
	if err != nil {
		return r.jsError("%s", err.Error())
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	size := info.Size()
	if offset > size {
		offset = size
	}
	if _, err := file.Seek(offset, io.SeekStart); err != nil {
		return r.jsError("failed to seek file: %v", err)
	}

	readLength, err := extensionFileReadLength(size, offset, length)
	if err != nil {
		return r.jsError("%s", err.Error())
	}
	data := make([]byte, int(readLength))
	if readLength > 0 {
		n, readErr := io.ReadFull(file, data)
		if readErr != nil && readErr != io.EOF && readErr != io.ErrUnexpectedEOF {
			return r.jsError("failed to read file: %v", readErr)
		}
		data = data[:n]
	}

	if strings.EqualFold(strings.TrimSpace(encoding), "bytes") ||
		strings.EqualFold(strings.TrimSpace(encoding), "raw") {
		// Return raw bytes as an ArrayBuffer to avoid base64 encode/decode of
		// large payloads under the goja interpreter.
		return r.jsSuccess(map[string]any{
			"data":       r.vm.NewArrayBuffer(data),
			"bytes_read": len(data),
			"offset":     offset,
			"size":       size,
			"eof":        offset+int64(len(data)) >= size,
		})
	}

	encoded, err := encodeRuntimeBytes(data, encoding)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	return r.jsSuccess(map[string]any{
		"data":       encoded,
		"bytes_read": len(data),
		"offset":     offset,
		"size":       size,
		"eof":        offset+int64(len(data)) >= size,
	})
}
func (r *extensionRuntime) fileWrite(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.jsError("path and data are required")
	}

	path := call.Arguments[0].String()
	data := call.Arguments[1].String()

	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	dir := filepath.Dir(fullPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return r.jsError("failed to create directory: %v", err)
	}

	// Full-content write: stage and rename so a kill mid-write cannot leave
	// a truncated file under the final name.
	stagedPath := stagedDownloadPath(fullPath)
	if err := os.WriteFile(stagedPath, []byte(data), 0644); err != nil {
		os.Remove(stagedPath)
		return r.jsError("%s", err.Error())
	}
	if err := os.Rename(stagedPath, fullPath); err != nil {
		os.Remove(stagedPath)
		return r.jsError("%s", err.Error())
	}

	return r.jsSuccess(map[string]any{
		"path": fullPath,
	})
}

func (r *extensionRuntime) fileWriteBytes(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.jsError("path and data are required")
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	options := parseRuntimeOptionsArgument(call, 2)
	appendMode := runtimeOptionBool(options, "append", false)
	truncate := runtimeOptionBool(options, "truncate", false)
	hasOffset := runtimeOptionHasKey(options, "offset")
	offset := runtimeOptionInt64(options, "offset", 0)
	encoding := runtimeOptionString(options, "encoding", "base64")

	if appendMode && hasOffset {
		return r.jsError("append and offset cannot be used together")
	}
	if offset < 0 {
		return r.jsError("offset must be >= 0")
	}

	data, err := decodeRuntimeBytesValue(call.Arguments[1].Export(), encoding)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	dir := filepath.Dir(fullPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return r.jsError("failed to create directory: %v", err)
	}

	flags := os.O_CREATE | os.O_WRONLY
	if appendMode {
		flags |= os.O_APPEND
	}
	if truncate {
		flags |= os.O_TRUNC
	}

	file, err := os.OpenFile(fullPath, flags, 0644)
	if err != nil {
		return r.jsError("%s", err.Error())
	}
	defer file.Close()

	if hasOffset && !appendMode {
		if _, err := file.Seek(offset, io.SeekStart); err != nil {
			return r.jsError("failed to seek file: %v", err)
		}
	}

	written, err := file.Write(data)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	info, statErr := file.Stat()
	size := int64(0)
	if statErr == nil {
		size = info.Size()
	}

	return r.jsSuccess(map[string]any{
		"path":          fullPath,
		"bytes_written": written,
		"size":          size,
	})
}

func (r *extensionRuntime) fileCopy(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.jsError("source and destination paths are required")
	}

	srcPath := call.Arguments[0].String()
	dstPath := call.Arguments[1].String()

	fullSrc, err := r.validatePath(srcPath)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	fullDst, err := r.validatePath(dstPath)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	srcFile, err := os.Open(fullSrc)
	if err != nil {
		return r.jsError("failed to read source: %v", err)
	}
	defer srcFile.Close()

	dir := filepath.Dir(fullDst)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return r.jsError("failed to create directory: %v", err)
	}

	dstFile, err := os.OpenFile(fullDst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		return r.jsError("failed to open destination: %v", err)
	}

	if _, err := io.Copy(dstFile, srcFile); err != nil {
		_ = dstFile.Close()
		return r.jsError("failed to copy file: %v", err)
	}

	if err := dstFile.Close(); err != nil {
		return r.jsError("failed to finalize destination: %v", err)
	}

	return r.jsSuccess(map[string]any{
		"path": fullDst,
	})
}

func (r *extensionRuntime) fileMove(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.jsError("source and destination paths are required")
	}

	srcPath := call.Arguments[0].String()
	dstPath := call.Arguments[1].String()

	fullSrc, err := r.validatePath(srcPath)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	fullDst, err := r.validatePath(dstPath)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	dir := filepath.Dir(fullDst)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return r.jsError("failed to create directory: %v", err)
	}

	if err := os.Rename(fullSrc, fullDst); err != nil {
		return r.jsError("failed to move file: %v", err)
	}

	return r.jsSuccess(map[string]any{
		"path": fullDst,
	})
}

func (r *extensionRuntime) fileGetSize(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.jsError("path is required")
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	info, err := os.Stat(fullPath)
	if err != nil {
		return r.jsError("%s", err.Error())
	}

	return r.jsSuccess(map[string]any{
		"size": info.Size(),
	})
}
