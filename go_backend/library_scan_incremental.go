package gobackend

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

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
