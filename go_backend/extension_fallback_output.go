package gobackend

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// buildDownloadFilename renders the sanitized "<name><ext>" filename for req
// from its template/metadata, defaulting to "<artist> - <title>.flac".
func buildDownloadFilename(req DownloadRequest) string {
	metadata := map[string]any{
		"title":             req.TrackName,
		"artist":            req.ArtistName,
		"album":             req.AlbumName,
		"album_artist":      req.AlbumArtist,
		"track":             req.TrackNumber,
		"track_number":      req.TrackNumber,
		"total_tracks":      req.TotalTracks,
		"playlist_position": req.PlaylistPosition,
		"disc":              req.DiscNumber,
		"disc_number":       req.DiscNumber,
		"total_discs":       req.TotalDiscs,
		"year":              extractYear(req.ReleaseDate),
		"date":              req.ReleaseDate,
		"release_date":      req.ReleaseDate,
		"isrc":              req.ISRC,
		"composer":          req.Composer,
		"quality":           req.Quality,
		"quality_variant":   req.QualityVariant,
	}

	filename := buildFilenameFromTemplate(req.FilenameFormat, metadata)
	if strings.TrimSpace(filename) == "" {
		filename = fmt.Sprintf("%s - %s", req.ArtistName, req.TrackName)
	}
	filename = sanitizeFilenamePreservingToken(filename, req.QualityVariant)

	ext := strings.TrimSpace(req.OutputExt)
	if ext == "" {
		ext = ".flac"
	} else if !strings.HasPrefix(ext, ".") {
		ext = "." + ext
	}

	return filename + ext
}

func buildOutputPath(req DownloadRequest) string {
	if strings.TrimSpace(req.OutputPath) != "" {
		return strings.TrimSpace(req.OutputPath)
	}

	outputDir := req.OutputDir
	if strings.TrimSpace(outputDir) == "" {
		outputDir = filepath.Join(os.TempDir(), "spotiflac-downloads")
	}
	os.MkdirAll(outputDir, 0755)
	AddAllowedDownloadDir(outputDir)

	return filepath.Join(outputDir, buildDownloadFilename(req))
}

func buildOutputPathForExtension(req DownloadRequest, ext *loadedExtension) string {
	if strings.TrimSpace(req.OutputPath) != "" {
		outputPath := strings.TrimSpace(req.OutputPath)
		AddAllowedDownloadDir(filepath.Dir(outputPath))
		return outputPath
	}

	// SAF downloads hand extensions a detached output FD owned by the host.
	// Extensions still need a real local temp file so Android can copy it into
	// the target document after provider-specific post-processing completes.
	if !isFDOutput(req.OutputFD) && strings.TrimSpace(req.OutputDir) != "" {
		return buildOutputPath(req)
	}

	tempDir := filepath.Join(ext.DataDir, "downloads")
	os.MkdirAll(tempDir, 0755)
	AddAllowedDownloadDir(tempDir)

	return filepath.Join(tempDir, buildDownloadFilename(req))
}

func shouldReuseExistingOutput(req DownloadRequest, outputPath string) bool {
	if req.AllowQualityVariant || isFDOutput(req.OutputFD) {
		return false
	}
	path := strings.TrimSpace(outputPath)
	if path == "" || strings.HasPrefix(path, "content://") || strings.HasPrefix(path, "/proc/self/fd/") {
		return false
	}
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular() && info.Size() > 0
}

func canEmbedGenreLabel(filePath string) bool {
	path := strings.TrimSpace(filePath)
	if path == "" || strings.HasPrefix(path, "content://") || strings.HasPrefix(path, "/proc/self/fd/") {
		return false
	}
	if strings.ToLower(filepath.Ext(path)) != ".flac" {
		return false
	}
	if !filepath.IsAbs(path) {
		return false
	}
	info, err := os.Stat(path)
	return err == nil && !info.IsDir() && info.Size() > 0
}

func embedExtensionDownloadMetadata(resp DownloadResponse, req DownloadRequest, alreadyExists bool) {
	if alreadyExists || !req.EmbedMetadata {
		return
	}

	filePath := strings.TrimSpace(resp.FilePath)
	if !canEmbedGenreLabel(filePath) {
		if req.Genre != "" || req.Label != "" || resp.CoverURL != "" || req.CoverURL != "" {
			GoLog("[DownloadWithExtensionFallback] Skipping metadata/cover embed for non-local FLAC output path: %q\n", filePath)
		}
		return
	}

	coverURL := firstNonEmptyTrimmed(resp.CoverURL, req.CoverURL)
	var coverData []byte
	if coverURL != "" {
		data, err := downloadCoverToMemory(coverURL, req.EmbedMaxQualityCover)
		if err != nil {
			GoLog("[DownloadWithExtensionFallback] Warning: failed to download cover for metadata embed: %v\n", err)
		} else if len(data) > 0 {
			coverData = data
		}
	}

	metadata := Metadata{
		Title:         firstNonEmptyTrimmed(resp.Title, req.TrackName),
		Artist:        firstNonEmptyTrimmed(resp.Artist, req.ArtistName),
		Album:         firstNonEmptyTrimmed(resp.Album, req.AlbumName),
		AlbumArtist:   firstNonEmptyTrimmed(resp.AlbumArtist, req.AlbumArtist),
		ArtistTagMode: req.ArtistTagMode,
		Date:          firstNonEmptyTrimmed(resp.ReleaseDate, req.ReleaseDate),
		TrackNumber:   firstPositiveInt(resp.TrackNumber, req.TrackNumber),
		TotalTracks:   firstPositiveInt(resp.TotalTracks, req.TotalTracks),
		DiscNumber:    firstPositiveInt(resp.DiscNumber, req.DiscNumber),
		TotalDiscs:    firstPositiveInt(resp.TotalDiscs, req.TotalDiscs),
		ISRC:          firstNonEmptyTrimmed(resp.ISRC, req.ISRC),
		Genre:         firstNonEmptyTrimmed(resp.Genre, req.Genre),
		Label:         firstNonEmptyTrimmed(resp.Label, req.Label),
		Copyright:     firstNonEmptyTrimmed(resp.Copyright, req.Copyright),
		Composer:      firstNonEmptyTrimmed(resp.Composer, req.Composer),
	}
	if req.EmbedLyrics {
		metadata.Lyrics = resp.LyricsLRC
	}

	var err error
	if len(coverData) > 0 {
		err = EmbedMetadataWithCoverData(filePath, metadata, coverData)
	} else {
		err = EmbedMetadata(filePath, metadata, "")
	}
	if err != nil {
		GoLog("[DownloadWithExtensionFallback] Warning: failed to embed metadata/cover: %v\n", err)
		return
	}

	if len(coverData) > 0 {
		GoLog("[DownloadWithExtensionFallback] Embedded metadata and cover from %q\n", coverURL)
	} else {
		GoLog("[DownloadWithExtensionFallback] Embedded metadata without cover\n")
	}
}

func firstPositiveInt(values ...int) int {
	for _, value := range values {
		if value > 0 {
			return value
		}
	}
	return 0
}
