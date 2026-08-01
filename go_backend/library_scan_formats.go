package gobackend

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

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
	if ext == ".flac" {
		return scanFLACFileWithCoverCache(filePath, result, displayNameHint, coverCacheDir, coverCacheKey)
	}
	if ext == ".m4a" || ext == ".mp4" || ext == ".aac" {
		return scanM4AFileWithCoverCache(filePath, result, displayNameHint, coverCacheDir, coverCacheKey)
	}
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

func embeddedCoverMIME(data []byte) string {
	if len(data) >= 8 &&
		data[0] == 0x89 &&
		data[1] == 0x50 &&
		data[2] == 0x4e &&
		data[3] == 0x47 {
		return "image/png"
	}
	return "image/jpeg"
}

func cacheScannedCover(filePath, cacheDir, coverCacheKey string, coverData []byte) string {
	if cacheDir == "" || len(coverData) == 0 {
		return ""
	}
	cacheKey := resolveLibraryCoverCacheKey(filePath, coverCacheKey)
	path, err := saveLibraryCoverDataToCache(cacheDir, cacheKey, coverData, embeddedCoverMIME(coverData))
	if err != nil {
		return ""
	}
	return path
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
	return scanFLACFileWithCoverCache(filePath, result, displayNameHint, "", "")
}

func scanFLACFileWithCoverCache(filePath string, result *LibraryScanResult, displayNameHint, coverCacheDir, coverCacheKey string) (*LibraryScanResult, error) {
	f, err := parseFlacFile(filePath)
	if err != nil {
		return scanFromFilename(filePath, displayNameHint, result)
	}
	defer f.Close()
	metadata := metadataFromParsedFlac(f)

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

	quality, err := audioQualityFromParsedFlac(f)
	if err == nil {
		result.BitDepth = quality.BitDepth
		result.SampleRate = quality.SampleRate
		if quality.SampleRate > 0 && quality.TotalSamples > 0 {
			durationSeconds := float64(quality.TotalSamples) / float64(quality.SampleRate)
			result.Duration = int(durationSeconds)
			if info, statErr := os.Stat(filePath); statErr == nil && info.Size() > 0 {
				result.Bitrate = int(float64(info.Size()) * 8 / durationSeconds / 1000)
			}
		}
	}
	if coverCacheDir != "" {
		cacheKey := resolveLibraryCoverCacheKey(filePath, coverCacheKey)
		if existing := existingLibraryCoverCachePath(coverCacheDir, cacheKey); existing != "" {
			result.CoverPath = existing
		} else if coverData, coverErr := coverArtFromParsedFlac(f); coverErr == nil {
			result.CoverPath = cacheScannedCover(filePath, coverCacheDir, cacheKey, coverData)
		}
	}

	applyDefaultLibraryMetadata(filePath, displayNameHint, result)

	return result, nil
}

func scanM4AFile(filePath string, result *LibraryScanResult, displayNameHint string) (*LibraryScanResult, error) {
	return scanM4AFileWithCoverCache(filePath, result, displayNameHint, "", "")
}

func scanM4AFileWithCoverCache(filePath string, result *LibraryScanResult, displayNameHint, coverCacheDir, coverCacheKey string) (*LibraryScanResult, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return scanFromFilename(filePath, displayNameHint, result)
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return scanFromFilename(filePath, displayNameHint, result)
	}
	fileSize := info.Size()

	var metadata *AudioMetadata
	ilst, ilstErr := findM4AIlstAtom(f, fileSize)
	if ilstErr == nil {
		metadata, err = readM4ATagsFromIlst(f, fileSize, ilst)
	} else {
		err = ilstErr
	}
	if err != nil {
		GoLog("[LibraryScan] M4A read error for %s: %v\n", filePath, err)
	}

	if metadata != nil {
		applyAudioMetadataToScan(metadata, result)
	}

	quality, err := m4aQualityFromFile(f, fileSize)
	if err == nil {
		result.BitDepth = quality.BitDepth
		result.SampleRate = quality.SampleRate
		result.Duration = quality.Duration
		if quality.Bitrate > 0 {
			result.Bitrate = quality.Bitrate
		}
		if format := libraryFormatForM4ACodec(quality.Codec); format != "" {
			result.Format = format
		}
	}
	if coverCacheDir != "" {
		cacheKey := resolveLibraryCoverCacheKey(filePath, coverCacheKey)
		if existing := existingLibraryCoverCachePath(coverCacheDir, cacheKey); existing != "" {
			result.CoverPath = existing
		} else if ilstErr == nil {
			if coverData, coverErr := extractCoverFromM4AIlst(f, fileSize, ilst); coverErr == nil {
				result.CoverPath = cacheScannedCover(filePath, coverCacheDir, cacheKey, coverData)
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

	applyAudioMetadataToScan(metadata, result)

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

	applyAudioMetadataToScan(metadata, result)

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
