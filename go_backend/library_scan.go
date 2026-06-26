package gobackend

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

type LibraryScanResult struct {
	ID                   string `json:"id"`
	TrackName            string `json:"trackName"`
	ArtistName           string `json:"artistName"`
	AlbumName            string `json:"albumName"`
	AlbumArtist          string `json:"albumArtist,omitempty"`
	FilePath             string `json:"filePath"`
	CoverPath            string `json:"coverPath,omitempty"`
	ScannedAt            string `json:"scannedAt"`
	FileModTime          int64  `json:"fileModTime,omitempty"` // Unix timestamp in milliseconds
	ISRC                 string `json:"isrc,omitempty"`
	TrackNumber          int    `json:"trackNumber,omitempty"`
	TotalTracks          int    `json:"totalTracks,omitempty"`
	DiscNumber           int    `json:"discNumber,omitempty"`
	TotalDiscs           int    `json:"totalDiscs,omitempty"`
	Duration             int    `json:"duration,omitempty"`
	ReleaseDate          string `json:"releaseDate,omitempty"`
	BitDepth             int    `json:"bitDepth,omitempty"`
	SampleRate           int    `json:"sampleRate,omitempty"`
	Bitrate              int    `json:"bitrate,omitempty"` // kbps, for lossy formats (MP3, Opus, Vorbis)
	Genre                string `json:"genre,omitempty"`
	Composer             string `json:"composer,omitempty"`
	Label                string `json:"label,omitempty"`
	Copyright            string `json:"copyright,omitempty"`
	Format               string `json:"format,omitempty"`
	MetadataFromFilename bool   `json:"metadataFromFilename,omitempty"`
}

type LibraryScanProgress struct {
	TotalFiles   int     `json:"total_files"`
	ScannedFiles int     `json:"scanned_files"`
	CurrentFile  string  `json:"current_file"`
	ErrorCount   int     `json:"error_count"`
	ProgressPct  float64 `json:"progress_pct"`
	IsComplete   bool    `json:"is_complete"`
}

type IncrementalScanResult struct {
	Scanned      []LibraryScanResult `json:"scanned"`      // New or updated files
	DeletedPaths []string            `json:"deletedPaths"` // Files that no longer exist
	SkippedCount int                 `json:"skippedCount"` // Files that were unchanged
	TotalFiles   int                 `json:"totalFiles"`   // Total files in folder
}

var (
	libraryScanProgress   LibraryScanProgress
	libraryScanProgressMu sync.RWMutex
	libraryScanCancel     chan struct{}
	libraryScanCancelMu   sync.Mutex
	libraryCoverCacheDir  string
	libraryCoverCacheMu   sync.RWMutex
)

var supportedAudioFormats = map[string]bool{
	".flac": true,
	".m4a":  true,
	".mp4":  true,
	".aac":  true,
	".mp3":  true,
	".opus": true,
	".ogg":  true,
	".ape":  true,
	".wv":   true,
	".mpc":  true,
	".wav":  true,
	".aiff": true,
	".aif":  true,
	".cue":  true,
}

type libraryAudioFileInfo struct {
	path    string
	modTime int64
}

type scannedCueFileInfo struct {
	sheet     *CueSheet
	audioPath string
}

type libraryScanTask struct {
	index int
	info  libraryAudioFileInfo
}

type libraryScanTaskResult struct {
	index   int
	path    string
	results []LibraryScanResult
	err     error
}

func isLibraryStagingFile(path string) bool {
	name := strings.ToLower(filepath.Base(path))
	if strings.HasSuffix(name, ".partial") {
		return true
	}
	for ext := range supportedAudioFormats {
		if strings.HasSuffix(name, ".partial"+ext) {
			return true
		}
	}
	return false
}

func collectLibraryAudioFiles(folderPath string, cancelCh <-chan struct{}) ([]libraryAudioFileInfo, error) {
	var files []libraryAudioFileInfo

	err := filepath.WalkDir(folderPath, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return nil
		}

		select {
		case <-cancelCh:
			return fmt.Errorf("scan cancelled")
		default:
		}

		if entry.IsDir() {
			return nil
		}
		if isLibraryStagingFile(path) {
			return nil
		}

		ext := strings.ToLower(filepath.Ext(path))
		if !supportedAudioFormats[ext] {
			return nil
		}

		info, err := entry.Info()
		if err != nil {
			return nil
		}

		files = append(files, libraryAudioFileInfo{
			path:    path,
			modTime: info.ModTime().UnixMilli(),
		})
		return nil
	})

	if err != nil {
		return nil, err
	}

	return files, nil
}

func libraryScanWorkerCount(taskCount int) int {
	if taskCount < 16 {
		return 1
	}
	workers := runtime.NumCPU()
	if workers > 4 {
		workers = 4
	}
	if workers < 2 {
		workers = 2
	}
	if workers > taskCount {
		workers = taskCount
	}
	return workers
}

func updateLibraryScanProgress(scannedFiles, totalFiles int, currentPath string) {
	libraryScanProgressMu.Lock()
	libraryScanProgress.ScannedFiles = scannedFiles
	libraryScanProgress.CurrentFile = filepath.Base(currentPath)
	if totalFiles > 0 {
		libraryScanProgress.ProgressPct = float64(scannedFiles) / float64(totalFiles) * 100
	}
	libraryScanProgressMu.Unlock()
}

func scanLibraryAudioTasksParallel(tasks []libraryScanTask, scanTime string, cancelCh <-chan struct{}, totalFiles int, completed *int) (map[int][]LibraryScanResult, int, error) {
	resultsByIndex := make(map[int][]LibraryScanResult, len(tasks))
	if len(tasks) == 0 {
		return resultsByIndex, 0, nil
	}

	workers := libraryScanWorkerCount(len(tasks))
	if workers <= 1 {
		errorCount := 0
		for _, task := range tasks {
			select {
			case <-cancelCh:
				return resultsByIndex, errorCount, fmt.Errorf("scan cancelled")
			default:
			}
			result, err := scanAudioFileWithKnownModTime(task.info.path, scanTime, task.info.modTime)
			*completed++
			updateLibraryScanProgress(*completed, totalFiles, task.info.path)
			if err != nil {
				errorCount++
				GoLog("[LibraryScan] Error scanning %s: %v\n", task.info.path, err)
				continue
			}
			resultsByIndex[task.index] = []LibraryScanResult{*result}
		}
		return resultsByIndex, errorCount, nil
	}

	taskCh := make(chan libraryScanTask)
	resultCh := make(chan libraryScanTaskResult, workers)
	var wg sync.WaitGroup

	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for task := range taskCh {
				select {
				case <-cancelCh:
					return
				default:
				}
				result, err := scanAudioFileWithKnownModTime(task.info.path, scanTime, task.info.modTime)
				taskResult := libraryScanTaskResult{
					index: task.index,
					path:  task.info.path,
					err:   err,
				}
				if err == nil && result != nil {
					taskResult.results = []LibraryScanResult{*result}
				}
				select {
				case <-cancelCh:
					return
				case resultCh <- taskResult:
				}
			}
		}()
	}

	go func() {
		defer close(taskCh)
		for _, task := range tasks {
			select {
			case <-cancelCh:
				return
			case taskCh <- task:
			}
		}
	}()

	go func() {
		wg.Wait()
		close(resultCh)
	}()

	errorCount := 0
	for taskResult := range resultCh {
		*completed++
		updateLibraryScanProgress(*completed, totalFiles, taskResult.path)
		if taskResult.err != nil {
			errorCount++
			GoLog("[LibraryScan] Error scanning %s: %v\n", taskResult.path, taskResult.err)
			continue
		}
		resultsByIndex[taskResult.index] = taskResult.results
	}

	select {
	case <-cancelCh:
		return resultsByIndex, errorCount, fmt.Errorf("scan cancelled")
	default:
	}
	return resultsByIndex, errorCount, nil
}

func SetLibraryCoverCacheDir(cacheDir string) {
	libraryCoverCacheMu.Lock()
	libraryCoverCacheDir = cacheDir
	libraryCoverCacheMu.Unlock()
}

func ScanLibraryFolder(folderPath string) (string, error) {
	if folderPath == "" {
		return "[]", fmt.Errorf("folder path is empty")
	}

	info, err := os.Stat(folderPath)
	if err != nil {
		return "[]", fmt.Errorf("folder not found: %w", err)
	}
	if !info.IsDir() {
		return "[]", fmt.Errorf("path is not a folder: %s", folderPath)
	}

	libraryScanProgressMu.Lock()
	libraryScanProgress = LibraryScanProgress{}
	libraryScanProgressMu.Unlock()

	libraryScanCancelMu.Lock()
	if libraryScanCancel != nil {
		close(libraryScanCancel)
	}
	libraryScanCancel = make(chan struct{})
	cancelCh := libraryScanCancel
	libraryScanCancelMu.Unlock()

	audioFileInfos, err := collectLibraryAudioFiles(folderPath, cancelCh)
	if err != nil {
		return "[]", err
	}

	totalFiles := len(audioFileInfos)
	libraryScanProgressMu.Lock()
	libraryScanProgress.TotalFiles = totalFiles
	libraryScanProgressMu.Unlock()

	if totalFiles == 0 {
		libraryScanProgressMu.Lock()
		libraryScanProgress.IsComplete = true
		libraryScanProgressMu.Unlock()
		return "[]", nil
	}

	GoLog("[LibraryScan] Found %d audio files to scan\n", totalFiles)

	results := make([]LibraryScanResult, 0, totalFiles)
	scanTime := time.Now().UTC().Format(time.RFC3339)
	errorCount := 0

	cueReferencedAudioFiles := make(map[string]bool)
	parsedCueFiles := make(map[string]scannedCueFileInfo)

	for _, fileInfo := range audioFileInfos {
		filePath := fileInfo.path
		ext := strings.ToLower(filepath.Ext(filePath))
		if ext == ".cue" {
			sheet, err := ParseCueFile(filePath)
			if err == nil && sheet.FileName != "" {
				audioPath := ResolveCueAudioPath(filePath, sheet.FileName)
				if audioPath != "" {
					parsedCueFiles[filePath] = scannedCueFileInfo{
						sheet:     sheet,
						audioPath: audioPath,
					}
					cueReferencedAudioFiles[audioPath] = true
				}
			}
		}
	}

	resultsByIndex := make(map[int][]LibraryScanResult, totalFiles)
	audioTasks := make([]libraryScanTask, 0, totalFiles)
	completedFiles := 0

	for i, fileInfo := range audioFileInfos {
		filePath := fileInfo.path
		select {
		case <-cancelCh:
			return "[]", fmt.Errorf("scan cancelled")
		default:
		}

		ext := strings.ToLower(filepath.Ext(filePath))

		if ext == ".cue" {
			var cueResults []LibraryScanResult
			cueInfo, ok := parsedCueFiles[filePath]
			if ok {
				cueResults, err = scanCueSheetForLibrary(
					filePath,
					cueInfo.sheet,
					cueInfo.audioPath,
					"",
					fileInfo.modTime,
					"",
					scanTime,
				)
			} else {
				cueResults, err = ScanCueFileForLibrary(filePath, scanTime)
			}
			if err != nil {
				errorCount++
				GoLog("[LibraryScan] Error scanning cue %s: %v\n", filePath, err)
				completedFiles++
				updateLibraryScanProgress(completedFiles, totalFiles, filePath)
				continue
			}
			resultsByIndex[i] = cueResults
			completedFiles++
			updateLibraryScanProgress(completedFiles, totalFiles, filePath)
			GoLog("[LibraryScan] CUE sheet %s: %d tracks\n", filepath.Base(filePath), len(cueResults))
			continue
		}

		if cueReferencedAudioFiles[filePath] {
			completedFiles++
			updateLibraryScanProgress(completedFiles, totalFiles, filePath)
			GoLog("[LibraryScan] Skipping %s (referenced by .cue sheet)\n", filepath.Base(filePath))
			continue
		}

		audioTasks = append(audioTasks, libraryScanTask{index: i, info: fileInfo})
	}

	audioResults, audioErrors, err := scanLibraryAudioTasksParallel(
		audioTasks,
		scanTime,
		cancelCh,
		totalFiles,
		&completedFiles,
	)
	if err != nil {
		return "[]", err
	}
	errorCount += audioErrors
	for index, scanResults := range audioResults {
		resultsByIndex[index] = scanResults
	}

	for i := range audioFileInfos {
		results = append(results, resultsByIndex[i]...)
	}

	libraryScanProgressMu.Lock()
	libraryScanProgress.ErrorCount = errorCount
	libraryScanProgress.IsComplete = true
	libraryScanProgressMu.Unlock()

	GoLog("[LibraryScan] Scan complete: %d tracks found, %d errors\n", len(results), errorCount)

	jsonBytes, err := json.Marshal(results)
	if err != nil {
		return "[]", fmt.Errorf("failed to marshal results: %w", err)
	}

	return string(jsonBytes), nil
}

func scanAudioFileWithKnownModTime(filePath, scanTime string, knownModTime int64) (*LibraryScanResult, error) {
	return scanAudioFileWithKnownModTimeAndDisplayNameAndCoverCacheKey(filePath, "", "", scanTime, knownModTime)
}

func scanAudioFileWithKnownModTimeAndDisplayNameAndCoverCacheKey(filePath, displayNameHint, coverCacheKey, scanTime string, knownModTime int64) (*LibraryScanResult, error) {
	ext := resolveLibraryAudioExt(filePath, displayNameHint)

	result := &LibraryScanResult{
		ID:        generateLibraryID(filePath),
		FilePath:  filePath,
		ScannedAt: scanTime,
		Format:    strings.TrimPrefix(ext, "."),
	}

	if knownModTime > 0 {
		result.FileModTime = knownModTime
	} else if info, err := os.Stat(filePath); err == nil {
		result.FileModTime = info.ModTime().UnixMilli()
	}

	libraryCoverCacheMu.RLock()
	coverCacheDir := libraryCoverCacheDir
	libraryCoverCacheMu.RUnlock()
	if coverCacheDir != "" {
		coverPath, err := SaveCoverToCacheWithHintAndKey(
			filePath,
			displayNameHint,
			coverCacheDir,
			coverCacheKey,
		)
		if err == nil && coverPath != "" {
			result.CoverPath = coverPath
		}
	}

	switch ext {
	case ".flac":
		return scanFLACFile(filePath, result, displayNameHint)
	case ".m4a", ".mp4", ".aac":
		return scanM4AFile(filePath, result, displayNameHint)
	case ".mp3":
		return scanMP3File(filePath, result, displayNameHint)
	case ".opus", ".ogg":
		return scanOggFile(filePath, result, displayNameHint)
	case ".ape", ".wv", ".mpc":
		return scanAPEFile(filePath, result, displayNameHint)
	case ".wav":
		return scanWAVFile(filePath, result, displayNameHint)
	case ".aiff", ".aif", ".aifc":
		return scanAIFFFile(filePath, result, displayNameHint)
	default:
		return scanFromFilename(filePath, displayNameHint, result)
	}
}

func resolveLibraryAudioExt(filePath, displayNameHint string) string {
	ext := strings.ToLower(filepath.Ext(filePath))
	if ext != "" {
		return ext
	}
	return strings.ToLower(filepath.Ext(displayNameHint))
}

func libraryDisplayNameOrPath(filePath, displayNameHint string) string {
	if displayNameHint != "" {
		return displayNameHint
	}
	return filePath
}

func applyDefaultLibraryMetadata(filePath, displayNameHint string, result *LibraryScanResult) {
	nameSource := libraryDisplayNameOrPath(filePath, displayNameHint)
	if result.TrackName == "" {
		result.TrackName = strings.TrimSuffix(filepath.Base(nameSource), filepath.Ext(nameSource))
	}
	if result.ArtistName == "" {
		result.ArtistName = "Unknown Artist"
	}
	if result.AlbumName == "" {
		result.AlbumName = "Unknown Album"
	}
}

func scanFLACFile(filePath string, result *LibraryScanResult, displayNameHint string) (*LibraryScanResult, error) {
	metadata, err := ReadMetadata(filePath)
	if err != nil {
		return scanFromFilename(filePath, displayNameHint, result)
	}

	result.TrackName = metadata.Title
	result.ArtistName = metadata.Artist
	result.AlbumName = metadata.Album
	result.AlbumArtist = metadata.AlbumArtist
	result.ISRC = metadata.ISRC
	result.TrackNumber = metadata.TrackNumber
	result.TotalTracks = metadata.TotalTracks
	result.DiscNumber = metadata.DiscNumber
	result.TotalDiscs = metadata.TotalDiscs
	result.ReleaseDate = metadata.Date
	result.Genre = metadata.Genre
	result.Composer = metadata.Composer
	result.Label = metadata.Label
	result.Copyright = metadata.Copyright

	quality, err := GetAudioQuality(filePath)
	if err == nil {
		result.BitDepth = quality.BitDepth
		result.SampleRate = quality.SampleRate
		if quality.SampleRate > 0 && quality.TotalSamples > 0 {
			result.Duration = int(quality.TotalSamples / int64(quality.SampleRate))
		}
	}

	applyDefaultLibraryMetadata(filePath, displayNameHint, result)

	return result, nil
}

func scanM4AFile(filePath string, result *LibraryScanResult, displayNameHint string) (*LibraryScanResult, error) {
	metadata, err := ReadM4ATags(filePath)
	if err != nil {
		GoLog("[LibraryScan] M4A read error for %s: %v\n", filePath, err)
	}

	if metadata != nil {
		result.TrackName = metadata.Title
		result.ArtistName = metadata.Artist
		result.AlbumName = metadata.Album
		result.AlbumArtist = metadata.AlbumArtist
		result.ISRC = metadata.ISRC
		result.TrackNumber = metadata.TrackNumber
		result.TotalTracks = metadata.TotalTracks
		result.DiscNumber = metadata.DiscNumber
		result.TotalDiscs = metadata.TotalDiscs
		result.ReleaseDate = metadata.Date
		if result.ReleaseDate == "" {
			result.ReleaseDate = metadata.Year
		}
		result.Genre = metadata.Genre
		result.Composer = metadata.Composer
		result.Label = metadata.Label
		result.Copyright = metadata.Copyright
	}

	quality, err := GetM4AQuality(filePath)
	if err == nil {
		result.BitDepth = quality.BitDepth
		result.SampleRate = quality.SampleRate
		result.Duration = quality.Duration
		if quality.Bitrate > 0 {
			result.Bitrate = quality.Bitrate
		}
		if format := libraryFormatForM4ACodec(quality.Codec); format != "" {
			result.Format = format
			if isLosslessLibraryFormat(format) {
				result.Bitrate = 0
			}
		}
	}

	if metadata == nil {
		return scanFromFilename(filePath, displayNameHint, result)
	}

	applyDefaultLibraryMetadata(filePath, displayNameHint, result)
	return result, nil
}

func libraryFormatForM4ACodec(codec string) string {
	switch strings.ToLower(strings.TrimSpace(codec)) {
	case "flac":
		return "flac"
	case "alac":
		return "alac"
	case "eac3", "ec-3":
		return "eac3"
	case "ac3", "ac-3":
		return "ac3"
	case "ac4", "ac-4":
		return "ac4"
	case "aac", "mp4a":
		return "m4a"
	default:
		return ""
	}
}

func isLosslessLibraryFormat(format string) bool {
	switch strings.ToLower(strings.TrimSpace(format)) {
	case "flac", "alac", "wav", "aiff", "aif", "aifc":
		return true
	default:
		return false
	}
}

func scanMP3File(filePath string, result *LibraryScanResult, displayNameHint string) (*LibraryScanResult, error) {
	metadata, err := ReadID3Tags(filePath)
	if err != nil {
		GoLog("[LibraryScan] ID3 read error for %s: %v\n", filePath, err)
		return scanFromFilename(filePath, displayNameHint, result)
	}

	result.TrackName = metadata.Title
	result.ArtistName = metadata.Artist
	result.AlbumName = metadata.Album
	result.AlbumArtist = metadata.AlbumArtist
	result.TrackNumber = metadata.TrackNumber
	result.TotalTracks = metadata.TotalTracks
	result.DiscNumber = metadata.DiscNumber
	result.TotalDiscs = metadata.TotalDiscs
	result.Genre = metadata.Genre
	if metadata.Date != "" {
		result.ReleaseDate = metadata.Date
	} else {
		result.ReleaseDate = metadata.Year
	}
	result.ISRC = metadata.ISRC
	result.Composer = metadata.Composer
	result.Label = metadata.Label
	result.Copyright = metadata.Copyright

	quality, err := GetMP3Quality(filePath)
	if err == nil {
		result.SampleRate = quality.SampleRate
		result.BitDepth = quality.BitDepth // 0 for lossy
		result.Duration = quality.Duration
		if quality.Bitrate > 0 {
			result.Bitrate = quality.Bitrate / 1000 // convert bps to kbps
		}
	}

	applyDefaultLibraryMetadata(filePath, displayNameHint, result)

	return result, nil
}

func scanOggFile(filePath string, result *LibraryScanResult, displayNameHint string) (*LibraryScanResult, error) {
	metadata, err := ReadOggVorbisComments(filePath)
	if err != nil {
		GoLog("[LibraryScan] Ogg/Opus read error for %s: %v\n", filePath, err)
		return scanFromFilename(filePath, displayNameHint, result)
	}

	result.TrackName = metadata.Title
	result.ArtistName = metadata.Artist
	result.AlbumName = metadata.Album
	result.AlbumArtist = metadata.AlbumArtist
	result.ISRC = metadata.ISRC
	result.TrackNumber = metadata.TrackNumber
	result.TotalTracks = metadata.TotalTracks
	result.DiscNumber = metadata.DiscNumber
	result.TotalDiscs = metadata.TotalDiscs
	result.Genre = metadata.Genre
	result.ReleaseDate = metadata.Date
	result.Composer = metadata.Composer
	result.Label = metadata.Label
	result.Copyright = metadata.Copyright

	quality, err := GetOggQuality(filePath)
	if err == nil {
		result.SampleRate = quality.SampleRate
		result.BitDepth = quality.BitDepth // 0 for lossy
		result.Duration = quality.Duration
		if quality.Bitrate > 0 {
			result.Bitrate = quality.Bitrate / 1000 // convert bps to kbps
		}
	}

	applyDefaultLibraryMetadata(filePath, displayNameHint, result)

	return result, nil
}

func scanAPEFile(filePath string, result *LibraryScanResult, displayNameHint string) (*LibraryScanResult, error) {
	tag, err := ReadAPETags(filePath)
	if err != nil {
		GoLog("[LibraryScan] APE tag read error for %s: %v\n", filePath, err)
		return scanFromFilename(filePath, displayNameHint, result)
	}

	metadata := APETagToAudioMetadata(tag)
	if metadata == nil {
		return scanFromFilename(filePath, displayNameHint, result)
	}

	result.TrackName = metadata.Title
	result.ArtistName = metadata.Artist
	result.AlbumName = metadata.Album
	result.AlbumArtist = metadata.AlbumArtist
	result.ISRC = metadata.ISRC
	result.TrackNumber = metadata.TrackNumber
	result.TotalTracks = metadata.TotalTracks
	result.DiscNumber = metadata.DiscNumber
	result.TotalDiscs = metadata.TotalDiscs
	result.Genre = metadata.Genre
	if metadata.Date != "" {
		result.ReleaseDate = metadata.Date
	} else {
		result.ReleaseDate = metadata.Year
	}
	result.Composer = metadata.Composer
	result.Label = metadata.Label
	result.Copyright = metadata.Copyright

	applyDefaultLibraryMetadata(filePath, displayNameHint, result)

	return result, nil
}

func scanFromFilename(filePath, displayNameHint string, result *LibraryScanResult) (*LibraryScanResult, error) {
	result.MetadataFromFilename = true
	nameSource := libraryDisplayNameOrPath(filePath, displayNameHint)
	filename := strings.TrimSuffix(filepath.Base(nameSource), filepath.Ext(nameSource))

	parts := strings.SplitN(filename, " - ", 2)
	if len(parts) == 2 {
		if len(parts[0]) <= 3 && isNumeric(parts[0]) {
			result.TrackName = parts[1]
			result.ArtistName = "Unknown Artist"
		} else {
			result.ArtistName = parts[0]
			result.TrackName = parts[1]
		}
	} else {
		if len(filename) > 3 && isNumeric(filename[:2]) {
			title := strings.TrimLeft(filename[2:], " .-")
			result.TrackName = title
		} else {
			result.TrackName = filename
		}
		result.ArtistName = "Unknown Artist"
	}

	dir := filepath.Dir(filePath)
	result.AlbumName = filepath.Base(dir)
	if result.AlbumName == "." || result.AlbumName == "" || result.AlbumName == "fd" || result.AlbumName == "self" {
		result.AlbumName = "Unknown Album"
	}

	return result, nil
}

func isNumeric(s string) bool {
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return len(s) > 0
}

func generateLibraryID(filePath string) string {
	return fmt.Sprintf("lib_%x", hashString(filePath))
}

func hashString(s string) uint32 {
	var hash uint32 = 5381
	for _, c := range s {
		hash = ((hash << 5) + hash) + uint32(c)
	}
	return hash
}

func GetLibraryScanProgress() string {
	libraryScanProgressMu.RLock()
	defer libraryScanProgressMu.RUnlock()

	jsonBytes, _ := json.Marshal(libraryScanProgress)
	return string(jsonBytes)
}

func CancelLibraryScan() {
	libraryScanCancelMu.Lock()
	defer libraryScanCancelMu.Unlock()

	if libraryScanCancel != nil {
		close(libraryScanCancel)
		libraryScanCancel = nil
	}
}

func ReadAudioMetadata(filePath string) (string, error) {
	return ReadAudioMetadataWithDisplayName(filePath, "")
}

func ReadAudioMetadataWithDisplayName(filePath, displayNameHint string) (string, error) {
	return ReadAudioMetadataWithDisplayNameAndCoverCacheKey(filePath, displayNameHint, "")
}

func ReadAudioMetadataWithDisplayNameAndCoverCacheKey(filePath, displayNameHint, coverCacheKey string) (string, error) {
	scanTime := time.Now().UTC().Format(time.RFC3339)
	result, err := scanAudioFileWithKnownModTimeAndDisplayNameAndCoverCacheKey(
		filePath,
		displayNameHint,
		coverCacheKey,
		scanTime,
		0,
	)
	if err != nil {
		return "", err
	}

	jsonBytes, err := json.Marshal(result)
	if err != nil {
		return "", fmt.Errorf("failed to marshal result: %w", err)
	}

	return string(jsonBytes), nil
}

func loadExistingFilesSnapshot(snapshotPath string) (map[string]int64, error) {
	existingFiles := make(map[string]int64)
	if snapshotPath == "" {
		return existingFiles, nil
	}

	file, err := os.Open(snapshotPath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) != 2 {
			continue
		}
		modTime, err := strconv.ParseInt(parts[0], 10, 64)
		if err != nil {
			continue
		}
		existingFiles[parts[1]] = modTime
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return existingFiles, nil
}

func scanLibraryFolderIncrementalWithExistingFiles(folderPath string, existingFiles map[string]int64) (string, error) {
	if folderPath == "" {
		return "{}", fmt.Errorf("folder path is empty")
	}

	info, err := os.Stat(folderPath)
	if err != nil {
		return "{}", fmt.Errorf("folder not found: %w", err)
	}
	if !info.IsDir() {
		return "{}", fmt.Errorf("path is not a folder: %s", folderPath)
	}

	GoLog("[LibraryScan] Incremental scan starting, %d existing files in database\n", len(existingFiles))

	libraryScanProgressMu.Lock()
	libraryScanProgress = LibraryScanProgress{}
	libraryScanProgressMu.Unlock()

	libraryScanCancelMu.Lock()
	if libraryScanCancel != nil {
		close(libraryScanCancel)
	}
	libraryScanCancel = make(chan struct{})
	cancelCh := libraryScanCancel
	libraryScanCancelMu.Unlock()

	currentFiles, err := collectLibraryAudioFiles(folderPath, cancelCh)
	if err != nil {
		return "{}", err
	}
	currentPathSet := make(map[string]bool, len(currentFiles))
	for _, fileInfo := range currentFiles {
		currentPathSet[fileInfo.path] = true
	}

	totalFiles := len(currentFiles)
	libraryScanProgressMu.Lock()
	libraryScanProgress.TotalFiles = totalFiles
	libraryScanProgressMu.Unlock()

	var filesToScan []libraryAudioFileInfo
	skippedCount := 0
	existingCueTrackModTimes := make(map[string]int64)
	for existingPath, modTime := range existingFiles {
		if idx := strings.LastIndex(existingPath, "#track"); idx > 0 {
			baseCuePath := existingPath[:idx]
			if _, exists := existingCueTrackModTimes[baseCuePath]; !exists {
				existingCueTrackModTimes[baseCuePath] = modTime
			}
		}
	}

	for _, f := range currentFiles {
		existingModTime, exists := existingFiles[f.path]
		if !exists {
			if strings.ToLower(filepath.Ext(f.path)) == ".cue" {
				if cueTrackModTime, hasCueTracks := existingCueTrackModTimes[f.path]; hasCueTracks {
					if f.modTime == cueTrackModTime {
						skippedCount++
					} else {
						filesToScan = append(filesToScan, f)
					}
					continue
				}
			}
			filesToScan = append(filesToScan, f)
		} else if f.modTime != existingModTime {
			filesToScan = append(filesToScan, f)
		} else {
			skippedCount++
		}
	}

	var deletedPaths []string
	for existingPath := range existingFiles {
		if idx := strings.LastIndex(existingPath, "#track"); idx > 0 {
			baseCuePath := existingPath[:idx]
			if currentPathSet[baseCuePath] {
				continue
			}
			deletedPaths = append(deletedPaths, existingPath)
		} else if !currentPathSet[existingPath] {
			deletedPaths = append(deletedPaths, existingPath)
		}
	}

	GoLog("[LibraryScan] Incremental: %d to scan, %d skipped, %d deleted\n",
		len(filesToScan), skippedCount, len(deletedPaths))

	if len(filesToScan) == 0 {
		libraryScanProgressMu.Lock()
		libraryScanProgress.ScannedFiles = totalFiles
		libraryScanProgress.IsComplete = true
		libraryScanProgress.ProgressPct = 100
		libraryScanProgressMu.Unlock()

		result := IncrementalScanResult{
			Scanned:      []LibraryScanResult{},
			DeletedPaths: deletedPaths,
			SkippedCount: skippedCount,
			TotalFiles:   totalFiles,
		}
		jsonBytes, _ := json.Marshal(result)
		return string(jsonBytes), nil
	}

	results := make([]LibraryScanResult, 0, len(filesToScan))
	scanTime := time.Now().UTC().Format(time.RFC3339)
	errorCount := 0

	cueReferencedAudioFilesInc := make(map[string]bool)
	parsedCueFiles := make(map[string]scannedCueFileInfo)
	for _, f := range filesToScan {
		ext := strings.ToLower(filepath.Ext(f.path))
		if ext == ".cue" {
			sheet, err := ParseCueFile(f.path)
			if err == nil && sheet.FileName != "" {
				audioPath := ResolveCueAudioPath(f.path, sheet.FileName)
				if audioPath != "" {
					parsedCueFiles[f.path] = scannedCueFileInfo{
						sheet:     sheet,
						audioPath: audioPath,
					}
					cueReferencedAudioFilesInc[audioPath] = true
				}
			}
		}
	}

	resultsByIndex := make(map[int][]LibraryScanResult, len(filesToScan))
	audioTasks := make([]libraryScanTask, 0, len(filesToScan))
	completedFiles := skippedCount

	for i, f := range filesToScan {
		select {
		case <-cancelCh:
			return "{}", fmt.Errorf("scan cancelled")
		default:
		}

		ext := strings.ToLower(filepath.Ext(f.path))

		if ext == ".cue" {
			var cueResults []LibraryScanResult
			cueInfo, ok := parsedCueFiles[f.path]
			if ok {
				cueResults, err = scanCueSheetForLibrary(
					f.path,
					cueInfo.sheet,
					cueInfo.audioPath,
					"",
					f.modTime,
					"",
					scanTime,
				)
			} else {
				cueResults, err = ScanCueFileForLibrary(f.path, scanTime)
			}
			if err != nil {
				errorCount++
				GoLog("[LibraryScan] Error scanning cue %s: %v\n", f.path, err)
				completedFiles++
				updateLibraryScanProgress(completedFiles, totalFiles, f.path)
				continue
			}
			resultsByIndex[i] = cueResults
			completedFiles++
			updateLibraryScanProgress(completedFiles, totalFiles, f.path)
			continue
		}

		if cueReferencedAudioFilesInc[f.path] {
			completedFiles++
			updateLibraryScanProgress(completedFiles, totalFiles, f.path)
			continue
		}

		audioTasks = append(audioTasks, libraryScanTask{index: i, info: f})
	}

	audioResults, audioErrors, err := scanLibraryAudioTasksParallel(
		audioTasks,
		scanTime,
		cancelCh,
		totalFiles,
		&completedFiles,
	)
	if err != nil {
		return "{}", err
	}
	errorCount += audioErrors
	for index, scanResults := range audioResults {
		resultsByIndex[index] = scanResults
	}

	for i := range filesToScan {
		results = append(results, resultsByIndex[i]...)
	}

	libraryScanProgressMu.Lock()
	libraryScanProgress.ErrorCount = errorCount
	libraryScanProgress.IsComplete = true
	libraryScanProgress.ScannedFiles = totalFiles
	libraryScanProgress.ProgressPct = 100
	libraryScanProgressMu.Unlock()

	GoLog("[LibraryScan] Incremental scan complete: %d scanned, %d skipped, %d deleted, %d errors\n",
		len(results), skippedCount, len(deletedPaths), errorCount)

	scanResult := IncrementalScanResult{
		Scanned:      results,
		DeletedPaths: deletedPaths,
		SkippedCount: skippedCount,
		TotalFiles:   totalFiles,
	}

	jsonBytes, err := json.Marshal(scanResult)
	if err != nil {
		return "{}", fmt.Errorf("failed to marshal results: %w", err)
	}

	return string(jsonBytes), nil
}

func ScanLibraryFolderIncremental(folderPath, existingFilesJSON string) (string, error) {
	existingFiles := make(map[string]int64)
	if existingFilesJSON != "" && existingFilesJSON != "{}" {
		if err := json.Unmarshal([]byte(existingFilesJSON), &existingFiles); err != nil {
			GoLog("[LibraryScan] Warning: failed to parse existing files JSON: %v\n", err)
		}
	}
	return scanLibraryFolderIncrementalWithExistingFiles(folderPath, existingFiles)
}

func ScanLibraryFolderIncrementalFromSnapshot(folderPath, snapshotPath string) (string, error) {
	existingFiles, err := loadExistingFilesSnapshot(snapshotPath)
	if err != nil {
		return "{}", fmt.Errorf("failed to load incremental snapshot: %w", err)
	}
	return scanLibraryFolderIncrementalWithExistingFiles(folderPath, existingFiles)
}
