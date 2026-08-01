package gobackend

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// isrcFileEntry caches the parse result for one file so index rebuilds only
// re-read files whose size or mtime changed.
type isrcFileEntry struct {
	size    int64
	modTime int64  // UnixNano
	isrc    string // uppercase; empty when the file carries no ISRC tag
}

type ISRCIndex struct {
	index     map[string]string        // ISRC (uppercase) -> file path
	files     map[string]isrcFileEntry // file path -> cached parse result
	outputDir string
	buildTime atomic.Int64 // UnixNano of the last build or write
	mu        sync.RWMutex
}

var (
	isrcIndexCache   = make(map[string]*ISRCIndex)
	isrcIndexCacheMu sync.RWMutex
	isrcBuildingMu   sync.Map // Per-directory build lock to prevent concurrent builds
	isrcIndexTTL     = 5 * time.Minute

	isrcIndexBuildWorkers = 4
)

func (idx *ISRCIndex) isFresh() bool {
	return time.Since(time.Unix(0, idx.buildTime.Load())) < isrcIndexTTL
}

func GetISRCIndex(outputDir string) *ISRCIndex {
	isrcIndexCacheMu.RLock()
	idx, exists := isrcIndexCache[outputDir]
	isrcIndexCacheMu.RUnlock()

	if exists && idx.isFresh() {
		return idx
	}

	buildLock, _ := isrcBuildingMu.LoadOrStore(outputDir, &sync.Mutex{})
	mu := buildLock.(*sync.Mutex)
	mu.Lock()
	defer mu.Unlock()

	isrcIndexCacheMu.RLock()
	idx, exists = isrcIndexCache[outputDir]
	isrcIndexCacheMu.RUnlock()

	if exists && idx.isFresh() {
		return idx
	}

	return buildISRCIndex(outputDir)
}

func buildISRCIndex(outputDir string) *ISRCIndex {
	idx := &ISRCIndex{
		index:     make(map[string]string),
		files:     make(map[string]isrcFileEntry),
		outputDir: outputDir,
	}
	idx.buildTime.Store(time.Now().UnixNano())

	if outputDir == "" {
		return idx
	}

	// Reuse the previous build's per-file cache: files whose size and mtime
	// are unchanged are adopted without touching their content, so a rebuild
	// is normally just a stat walk.
	prevFiles := map[string]isrcFileEntry{}
	isrcIndexCacheMu.RLock()
	if prev, ok := isrcIndexCache[outputDir]; ok {
		prev.mu.RLock()
		for path, entry := range prev.files {
			prevFiles[path] = entry
		}
		prev.mu.RUnlock()
	}
	isrcIndexCacheMu.RUnlock()

	startTime := time.Now()
	type parseTask struct {
		path    string
		size    int64
		modTime int64
	}
	var toParse []parseTask
	reused := 0

	filepath.Walk(outputDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}

		ext := strings.ToLower(filepath.Ext(path))
		if !isrcIndexExts[ext] {
			return nil
		}

		size := info.Size()
		modTime := info.ModTime().UnixNano()
		if entry, ok := prevFiles[path]; ok && entry.size == size && entry.modTime == modTime {
			idx.files[path] = entry
			if entry.isrc != "" {
				idx.index[entry.isrc] = path
			}
			reused++
			return nil
		}
		toParse = append(toParse, parseTask{path: path, size: size, modTime: modTime})
		return nil
	})

	if len(toParse) > 0 {
		// New/changed files: read only their Vorbis comment block, in
		// parallel. Embedded cover art (megabytes per file) is never loaded.
		isrcs := make([]string, len(toParse))
		workerCount := isrcIndexBuildWorkers
		if len(toParse) < workerCount {
			workerCount = len(toParse)
		}
		tasks := make(chan int)
		var wg sync.WaitGroup
		for w := 0; w < workerCount; w++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				for i := range tasks {
					isrcs[i] = strings.ToUpper(readFileISRC(toParse[i].path))
				}
			}()
		}
		for i := range toParse {
			tasks <- i
		}
		close(tasks)
		wg.Wait()

		for i, task := range toParse {
			entry := isrcFileEntry{size: task.size, modTime: task.modTime, isrc: isrcs[i]}
			idx.files[task.path] = entry
			if entry.isrc != "" {
				idx.index[entry.isrc] = task.path
			}
		}
	}

	fmt.Printf("[ISRCIndex] Built index for %s: %d files (%d parsed, %d cached) in %v\n",
		outputDir, len(idx.files), len(toParse), reused, time.Since(startTime).Round(time.Millisecond))

	isrcIndexCacheMu.Lock()
	isrcIndexCache[outputDir] = idx
	isrcIndexCacheMu.Unlock()

	return idx
}

// isrcIndexExts are the formats the download pipeline can produce; each has
// a native tag reader that stops at the metadata blocks.
var isrcIndexExts = map[string]bool{
	".flac": true,
	".mp3":  true,
	".m4a":  true,
	".ogg":  true,
	".opus": true,
}

// readFileISRC reads the ISRC tag using the native reader for the format.
// Returns "" for unsupported formats, unreadable files, or missing tags.
func readFileISRC(path string) string {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".flac":
		return readFlacISRC(path)
	case ".mp3":
		if meta, err := ReadID3Tags(path); err == nil && meta != nil {
			return strings.TrimSpace(meta.ISRC)
		}
	case ".m4a":
		if meta, err := ReadM4ATags(path); err == nil && meta != nil {
			return strings.TrimSpace(meta.ISRC)
		}
	case ".ogg", ".opus":
		if meta, err := ReadOggVorbisComments(path); err == nil && meta != nil {
			return strings.TrimSpace(meta.ISRC)
		}
	}
	return ""
}

// readFlacISRC extracts the ISRC Vorbis comment from a FLAC file by walking
// the metadata block headers and reading only the VORBIS_COMMENT payload;
// picture and padding blocks are seeked past, never loaded. Returns "" when
// the file is not FLAC or carries no ISRC tag.
func readFlacISRC(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	magic := make([]byte, 4)
	if _, err := io.ReadFull(f, magic); err != nil || string(magic) != "fLaC" {
		return ""
	}

	header := make([]byte, 4)
	for {
		if _, err := io.ReadFull(f, header); err != nil {
			return ""
		}
		last := header[0]&0x80 != 0
		blockType := header[0] & 0x7F
		length := int64(header[1])<<16 | int64(header[2])<<8 | int64(header[3])
		if blockType == 4 { // VORBIS_COMMENT
			if length > 16<<20 {
				return ""
			}
			payload := make([]byte, length)
			if _, err := io.ReadFull(f, payload); err != nil {
				return ""
			}
			return vorbisCommentISRC(payload)
		}
		if last {
			return ""
		}
		if _, err := f.Seek(length, io.SeekCurrent); err != nil {
			return ""
		}
	}
}

func vorbisCommentISRC(payload []byte) string {
	if len(payload) < 8 {
		return ""
	}
	offset := int(binary.LittleEndian.Uint32(payload[0:4])) + 4
	if offset < 4 || offset+4 > len(payload) {
		return ""
	}
	count := int(binary.LittleEndian.Uint32(payload[offset : offset+4]))
	offset += 4
	for i := 0; i < count; i++ {
		if offset+4 > len(payload) {
			return ""
		}
		commentLen := int(binary.LittleEndian.Uint32(payload[offset : offset+4]))
		offset += 4
		if commentLen < 0 || offset+commentLen > len(payload) {
			return ""
		}
		comment := payload[offset : offset+commentLen]
		offset += commentLen
		eq := strings.IndexByte(string(comment), '=')
		if eq > 0 && strings.EqualFold(string(comment[:eq]), "ISRC") {
			return strings.TrimSpace(string(comment[eq+1:]))
		}
	}
	return ""
}

func (idx *ISRCIndex) lookup(isrc string) (string, bool) {
	if isrc == "" {
		return "", false
	}

	idx.mu.RLock()
	defer idx.mu.RUnlock()

	path, exists := idx.index[strings.ToUpper(isrc)]
	return path, exists
}

func (idx *ISRCIndex) remove(isrc string) {
	if isrc == "" {
		return
	}

	idx.mu.Lock()
	defer idx.mu.Unlock()

	delete(idx.index, strings.ToUpper(isrc))
}

func (idx *ISRCIndex) Lookup(isrc string) (string, error) {
	path, _ := idx.lookup(isrc)
	return path, nil
}

func (idx *ISRCIndex) Add(isrc, filePath string) {
	if isrc == "" || filePath == "" {
		return
	}

	upper := strings.ToUpper(isrc)
	var entry *isrcFileEntry
	if info, err := os.Stat(filePath); err == nil {
		entry = &isrcFileEntry{
			size:    info.Size(),
			modTime: info.ModTime().UnixNano(),
			isrc:    upper,
		}
	}

	idx.mu.Lock()
	idx.index[upper] = filePath
	if entry != nil {
		if idx.files == nil {
			idx.files = make(map[string]isrcFileEntry)
		}
		idx.files[filePath] = *entry
	}
	idx.mu.Unlock()

	// The index is write-maintained after every successful download;
	// refreshing the timestamp keeps the TTL from forcing a full rebuild in
	// the middle of the exact workload the index exists to serve.
	idx.buildTime.Store(time.Now().UnixNano())
}

func InvalidateISRCCache(outputDir string) {
	isrcIndexCacheMu.Lock()
	delete(isrcIndexCache, outputDir)
	isrcIndexCacheMu.Unlock()
}

func checkISRCExistsInternal(outputDir, isrc string) (string, bool) {
	if isrc == "" || outputDir == "" {
		return "", false
	}

	idx := GetISRCIndex(outputDir)
	filePath, exists := idx.lookup(isrc)
	if !exists {
		return "", false
	}

	if !CheckFileExists(filePath) {
		// Stale index entry; remove it and return not found.
		idx.remove(isrc)
		return "", false
	}

	return filePath, true
}

func CheckISRCExists(outputDir, isrc string) (string, error) {
	filepath, _ := checkISRCExistsInternal(outputDir, isrc)
	return filepath, nil
}

func CheckFileExists(filePath string) bool {
	info, err := os.Stat(filePath)
	if err != nil {
		return false
	}
	return !info.IsDir() && info.Size() > 0
}

type FileExistenceResult struct {
	ISRC       string `json:"isrc"`
	Exists     bool   `json:"exists"`
	FilePath   string `json:"file_path,omitempty"`
	TrackName  string `json:"track_name,omitempty"`
	ArtistName string `json:"artist_name,omitempty"`
}

func CheckFilesExistParallel(outputDir string, tracksJSON string) (string, error) {
	var tracks []struct {
		ISRC       string `json:"isrc"`
		TrackName  string `json:"track_name"`
		ArtistName string `json:"artist_name"`
	}
	if err := json.Unmarshal([]byte(tracksJSON), &tracks); err != nil {
		return "", fmt.Errorf("failed to parse tracks JSON: %w", err)
	}

	results := make([]FileExistenceResult, len(tracks))

	isrcIdx := GetISRCIndex(outputDir)

	// A lookup is a single map read. Holding one read lock for the batch avoids
	// one goroutine and one lock/unlock pair per track, which was slower and
	// could create thousands of goroutines for large playlists.
	isrcIdx.mu.RLock()
	for i, track := range tracks {
		result := FileExistenceResult{
			ISRC:       track.ISRC,
			TrackName:  track.TrackName,
			ArtistName: track.ArtistName,
		}
		if track.ISRC != "" {
			if filePath, exists := isrcIdx.index[strings.ToUpper(track.ISRC)]; exists {
				result.Exists = true
				result.FilePath = filePath
			}
		}
		results[i] = result
	}
	isrcIdx.mu.RUnlock()

	resultJSON, err := json.Marshal(results)
	if err != nil {
		return "", fmt.Errorf("failed to marshal results: %w", err)
	}

	return string(resultJSON), nil
}

func PreBuildISRCIndex(outputDir string) error {
	if outputDir == "" {
		return fmt.Errorf("output directory is required")
	}

	buildISRCIndex(outputDir)
	return nil
}

func AddToISRCIndex(outputDir, isrc, filePath string) {
	if outputDir == "" || isrc == "" || filePath == "" {
		return
	}

	isrcIndexCacheMu.RLock()
	idx, exists := isrcIndexCache[outputDir]
	isrcIndexCacheMu.RUnlock()

	if exists {
		idx.Add(isrc, filePath)
	}
}
