package gobackend

import (
	"context"
	"encoding/json"
	"strings"
	"time"
)

type DownloadRequest struct {
	ContractVersion             int    `json:"contract_version,omitempty"`
	ISRC                        string `json:"isrc"`
	Service                     string `json:"service"`
	SpotifyID                   string `json:"spotify_id"`
	TrackName                   string `json:"track_name"`
	ArtistName                  string `json:"artist_name"`
	AlbumName                   string `json:"album_name"`
	AlbumArtist                 string `json:"album_artist"`
	CoverURL                    string `json:"cover_url"`
	OutputDir                   string `json:"output_dir"`
	OutputPath                  string `json:"output_path,omitempty"`
	OutputFD                    int    `json:"output_fd,omitempty"`
	OutputExt                   string `json:"output_ext,omitempty"`
	FilenameFormat              string `json:"filename_format"`
	Quality                     string `json:"quality"`
	EmbedMetadata               bool   `json:"embed_metadata"`
	ArtistTagMode               string `json:"artist_tag_mode,omitempty"`
	EmbedLyrics                 bool   `json:"embed_lyrics"`
	EmbedMaxQualityCover        bool   `json:"embed_max_quality_cover"`
	EmbedReplayGain             bool   `json:"embed_replaygain,omitempty"`
	PostProcessingEnabled       bool   `json:"post_processing_enabled,omitempty"`
	TidalHighFormat             string `json:"tidal_high_format,omitempty"`
	TrackNumber                 int    `json:"track_number"`
	PlaylistPosition            int    `json:"playlist_position,omitempty"`
	DiscNumber                  int    `json:"disc_number"`
	TotalTracks                 int    `json:"total_tracks"`
	TotalDiscs                  int    `json:"total_discs,omitempty"`
	ReleaseDate                 string `json:"release_date"`
	ItemID                      string `json:"item_id"`
	DurationMS                  int    `json:"duration_ms"`
	Source                      string `json:"source"`
	Genre                       string `json:"genre,omitempty"`
	Label                       string `json:"label,omitempty"`
	Copyright                   string `json:"copyright,omitempty"`
	Composer                    string `json:"composer,omitempty"`
	TidalID                     string `json:"tidal_id,omitempty"`
	QobuzID                     string `json:"qobuz_id,omitempty"`
	DeezerID                    string `json:"deezer_id,omitempty"`
	LyricsMode                  string `json:"lyrics_mode,omitempty"`
	UseExtensions               bool   `json:"use_extensions,omitempty"`
	UseFallback                 bool   `json:"use_fallback,omitempty"`
	RequiresContainerConversion bool   `json:"requires_container_conversion,omitempty"`
	AllowQualityVariant         bool   `json:"allow_quality_variant,omitempty"`
	QualityVariant              string `json:"quality_variant,omitempty"`
	SongLinkRegion              string `json:"songlink_region,omitempty"`
}

type DownloadResponse struct {
	Success                     bool                    `json:"success"`
	Message                     string                  `json:"message"`
	FilePath                    string                  `json:"file_path,omitempty"`
	Error                       string                  `json:"error,omitempty"`
	ErrorType                   string                  `json:"error_type,omitempty"`
	RetryAfterSeconds           int                     `json:"retry_after_seconds,omitempty"`
	AlreadyExists               bool                    `json:"already_exists,omitempty"`
	ActualBitDepth              int                     `json:"actual_bit_depth,omitempty"`
	ActualSampleRate            int                     `json:"actual_sample_rate,omitempty"`
	AudioCodec                  string                  `json:"audio_codec,omitempty"`
	ActualExtension             string                  `json:"actual_extension,omitempty"`
	ActualContainer             string                  `json:"actual_container,omitempty"`
	RequiresContainerConversion bool                    `json:"requires_container_conversion,omitempty"`
	Service                     string                  `json:"service,omitempty"`
	Title                       string                  `json:"title,omitempty"`
	Artist                      string                  `json:"artist,omitempty"`
	Album                       string                  `json:"album,omitempty"`
	AlbumArtist                 string                  `json:"album_artist,omitempty"`
	ReleaseDate                 string                  `json:"release_date,omitempty"`
	TrackNumber                 int                     `json:"track_number,omitempty"`
	DiscNumber                  int                     `json:"disc_number,omitempty"`
	TotalTracks                 int                     `json:"total_tracks,omitempty"`
	TotalDiscs                  int                     `json:"total_discs,omitempty"`
	ISRC                        string                  `json:"isrc,omitempty"`
	CoverURL                    string                  `json:"cover_url,omitempty"`
	Genre                       string                  `json:"genre,omitempty"`
	Label                       string                  `json:"label,omitempty"`
	Copyright                   string                  `json:"copyright,omitempty"`
	Composer                    string                  `json:"composer,omitempty"`
	SkipMetadataEnrichment      bool                    `json:"skip_metadata_enrichment,omitempty"`
	LyricsLRC                   string                  `json:"lyrics_lrc,omitempty"`
	DecryptionKey               string                  `json:"decryption_key,omitempty"`
	Decryption                  *DownloadDecryptionInfo `json:"decryption,omitempty"`
}

type DownloadResult struct {
	FilePath                    string
	BitDepth                    int
	SampleRate                  int
	AudioCodec                  string
	Title                       string
	Artist                      string
	Album                       string
	ReleaseDate                 string
	TrackNumber                 int
	TotalTracks                 int
	DiscNumber                  int
	TotalDiscs                  int
	ISRC                        string
	CoverURL                    string
	Genre                       string
	Label                       string
	Copyright                   string
	Composer                    string
	LyricsLRC                   string
	DecryptionKey               string
	Decryption                  *DownloadDecryptionInfo
	ActualExtension             string
	ActualContainer             string
	RequiresContainerConversion bool
}

func buildDownloadSuccessResponse(
	req DownloadRequest,
	result DownloadResult,
	service string,
	message string,
	filePath string,
	alreadyExists bool,
) DownloadResponse {
	title := result.Title
	if title == "" {
		title = req.TrackName
	}

	artist := result.Artist
	if artist == "" {
		artist = req.ArtistName
	}

	// Preserve requested release metadata when available so mixed-provider
	// fallback downloads from the same source album do not get split into
	// different albums just because Tidal/Qobuz report variant titles/dates.
	album, releaseDate, trackNumber, discNumber := preferredReleaseMetadata(
		req,
		result.Album,
		result.ReleaseDate,
		result.TrackNumber,
		result.DiscNumber,
	)

	isrc := result.ISRC
	if isrc == "" {
		isrc = req.ISRC
	}

	genre := result.Genre
	if genre == "" {
		genre = req.Genre
	}

	label := result.Label
	if label == "" {
		label = req.Label
	}

	copyright := result.Copyright
	if copyright == "" {
		copyright = req.Copyright
	}

	composer := result.Composer
	if composer == "" {
		composer = req.Composer
	}

	coverURL := strings.TrimSpace(result.CoverURL)
	if coverURL == "" {
		coverURL = strings.TrimSpace(req.CoverURL)
	}

	return DownloadResponse{
		Success:                     true,
		Message:                     message,
		FilePath:                    filePath,
		AlreadyExists:               alreadyExists,
		ActualBitDepth:              result.BitDepth,
		ActualSampleRate:            result.SampleRate,
		AudioCodec:                  result.AudioCodec,
		ActualExtension:             result.ActualExtension,
		ActualContainer:             result.ActualContainer,
		RequiresContainerConversion: result.RequiresContainerConversion,
		Service:                     service,
		Title:                       title,
		Artist:                      artist,
		Album:                       album,
		AlbumArtist:                 req.AlbumArtist,
		ReleaseDate:                 releaseDate,
		TrackNumber:                 trackNumber,
		TotalTracks:                 req.TotalTracks,
		DiscNumber:                  discNumber,
		TotalDiscs:                  req.TotalDiscs,
		ISRC:                        isrc,
		CoverURL:                    coverURL,
		Genre:                       genre,
		Label:                       label,
		Copyright:                   copyright,
		Composer:                    composer,
		LyricsLRC:                   result.LyricsLRC,
		DecryptionKey:               result.DecryptionKey,
		Decryption:                  normalizeDownloadDecryptionInfo(result.Decryption, result.DecryptionKey),
	}
}

func shouldSkipQualityProbe(filePath string) bool {
	path := strings.TrimSpace(filePath)
	if path == "" {
		return true
	}
	if strings.HasPrefix(path, "/proc/self/fd/") {
		return true
	}
	// Content URI and other non-filesystem schemes cannot be read directly by os.Open.
	if strings.Contains(path, "://") {
		return true
	}
	return false
}

func enrichResultQualityFromFile(result *DownloadResult) {
	if result == nil {
		return
	}

	path := strings.TrimSpace(result.FilePath)
	if shouldSkipQualityProbe(path) {
		if strings.HasPrefix(path, "/proc/self/fd/") {
			LogDebug("Download", "Skipping quality probe for ephemeral SAF FD output: %s", path)
		}
		return
	}

	quality, qErr := GetAudioQuality(path)
	if qErr == nil {
		result.BitDepth = quality.BitDepth
		result.SampleRate = quality.SampleRate
		result.AudioCodec = quality.Codec
		if quality.Codec != "" {
			GoLog("[Download] Actual quality from file: %s %d-bit/%dHz\n", quality.Codec, quality.BitDepth, quality.SampleRate)
		} else {
			GoLog("[Download] Actual quality from file: %d-bit/%dHz\n", quality.BitDepth, quality.SampleRate)
		}
		return
	}

	LogDebug("Download", "Post-download quality probe unavailable for %s: %v", path, qErr)
}

func applyExtendedMetadataFields(
	genre *string,
	label *string,
	copyright *string,
	extMeta *AlbumExtendedMetadata,
) {
	if extMeta == nil {
		return
	}

	if genre != nil && *genre == "" && extMeta.Genre != "" {
		*genre = extMeta.Genre
	}
	if label != nil && *label == "" && extMeta.Label != "" {
		*label = extMeta.Label
	}
	if copyright != nil && *copyright == "" && extMeta.Copyright != "" {
		*copyright = extMeta.Copyright
	}
}

func enrichExtraMetadataByISRC(
	logPrefix string,
	isrc string,
	genre *string,
	label *string,
	copyright *string,
) {
	normalizedISRC := strings.TrimSpace(isrc)
	if normalizedISRC == "" {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	extMeta, err := fetchDeezerExtendedMetadataByISRC(ctx, normalizedISRC)
	if err != nil {
		GoLog("[%s] Failed to get extended metadata from Deezer: %v\n", logPrefix, err)
	}
	applyExtendedMetadataFields(genre, label, copyright, extMeta)

	if genre != nil && *genre == "" {
		musicBrainzGenre, err := fetchMusicBrainzGenreByISRC(normalizedISRC)
		if err != nil {
			GoLog("[%s] Failed to get genre from MusicBrainz: %v\n", logPrefix, err)
		} else if musicBrainzGenre != "" {
			*genre = musicBrainzGenre
			GoLog("[%s] Genre fallback from MusicBrainz: %s\n", logPrefix, *genre)
		}
	}

	currentGenre := ""
	currentLabel := ""
	currentCopyright := ""
	if genre != nil {
		currentGenre = *genre
	}
	if label != nil {
		currentLabel = *label
	}
	if copyright != nil {
		currentCopyright = *copyright
	}
	if currentGenre != "" || currentLabel != "" || currentCopyright != "" {
		GoLog("[%s] Extended metadata ready: genre=%s, label=%s, copyright=%s\n", logPrefix, currentGenre, currentLabel, currentCopyright)
	}
}

func enrichRequestExtendedMetadata(req *DownloadRequest) {
	if req == nil {
		return
	}

	if req.ISRC == "" {
		return
	}

	if strings.TrimSpace(req.AlbumArtist) == "" {
		albumArtist, err := fetchMusicBrainzAlbumArtistByISRC(req.ISRC, req.AlbumName)
		if err != nil {
			GoLog("[DownloadWithFallback] Failed to get album artist from MusicBrainz: %v\n", err)
		} else if strings.TrimSpace(albumArtist) != "" {
			req.AlbumArtist = strings.TrimSpace(albumArtist)
			GoLog("[DownloadWithFallback] Album artist fallback from MusicBrainz: %s\n", req.AlbumArtist)
		}
	}

	if req.Genre == "" || req.Label == "" || req.Copyright == "" {
		enrichExtraMetadataByISRC(
			"DownloadWithFallback",
			req.ISRC,
			&req.Genre,
			&req.Label,
			&req.Copyright,
		)
	}
}

func applySongLinkRegionFromRequest(req *DownloadRequest) {
	if req == nil {
		return
	}
	SetSongLinkRegion(req.SongLinkRegion)
}

// DownloadByStrategy routes all download requests through extension providers.
func DownloadByStrategy(requestJSON string) (string, error) {
	var req DownloadRequest
	if err := json.Unmarshal([]byte(requestJSON), &req); err != nil {
		return errorResponse("Invalid request: " + err.Error())
	}
	normalizedBytes, err := json.Marshal(req)
	if err != nil {
		return errorResponse("Invalid request: " + err.Error())
	}
	normalizedJSON := string(normalizedBytes)

	if req.UseExtensions {
		resp, err := DownloadWithExtensionsJSON(normalizedJSON)
		if err != nil {
			return errorResponse(err.Error())
		}
		return resp, nil
	}

	return errorResponse("Extension providers are disabled; built-in download providers have been retired")
}

func GetAllDownloadProgress() string {
	return GetMultiProgress()
}

func GetAllDownloadProgressDelta(sinceSeq int64) string {
	return GetMultiProgressDelta(sinceSeq)
}

func InitItemProgress(itemID string) {
	StartItemProgress(itemID)
}

func ClearItemProgress(itemID string) {
	RemoveItemProgress(itemID)
}

func CancelDownload(itemID string) {
	cancelDownload(itemID)
}

// ResetDownloadCancel drops a pre-registered cancellation flag for an item
// with no active download, so a user-initiated retry does not consume a stale
// cancel and abort instantly. Entries with live references are left alone.
func ResetDownloadCancel(itemID string) {
	resetDownloadCancel(itemID)
}

func CleanupConnections() {
	CloseIdleConnections()
}

func errorResponse(msg string) (string, error) {
	errorType := classifyDownloadErrorType(msg)

	resp := DownloadResponse{
		Success:   false,
		Error:     msg,
		ErrorType: errorType,
	}
	s, _ := marshalJSONString(resp)
	return s, nil
}

func classifyDownloadErrorType(msg string) string {
	lowerMsg := strings.ToLower(msg)

	if strings.Contains(lowerMsg, "isp blocking") ||
		strings.Contains(lowerMsg, "try using vpn") ||
		strings.Contains(lowerMsg, "change dns") {
		return "isp_blocked"
	} else if strings.Contains(lowerMsg, "cancel") {
		return "cancelled"
	} else if strings.Contains(lowerMsg, "verification_required") ||
		strings.Contains(lowerMsg, "session is not authenticated") ||
		strings.Contains(lowerMsg, "signed session is not authenticated") ||
		strings.Contains(lowerMsg, "signed session expired") {
		return "verification_required"
	} else if strings.Contains(lowerMsg, "byoa_provider_reauth_required") ||
		strings.Contains(lowerMsg, "reauth_provider") {
		return "provider_reauth_required"
	} else if strings.Contains(lowerMsg, "request_auth_invalid") {
		return "request_auth_invalid"
	} else if strings.Contains(lowerMsg, "provider_auth_failed") {
		return "provider_auth_failed"
	} else if strings.Contains(lowerMsg, "provider_unavailable") {
		return "provider_unavailable"
	} else if strings.Contains(lowerMsg, "rate limit") ||
		messageHasHTTPStatusCode(lowerMsg, "429") ||
		strings.Contains(lowerMsg, "too many requests") {
		return "rate_limit"
	} else if strings.Contains(lowerMsg, "permission") ||
		strings.Contains(lowerMsg, "operation not permitted") ||
		strings.Contains(lowerMsg, "access denied") ||
		strings.Contains(lowerMsg, "failed to create file") ||
		strings.Contains(lowerMsg, "failed to create directory") {
		return "permission"
	} else if strings.Contains(lowerMsg, "not found") ||
		strings.Contains(lowerMsg, "not available") ||
		strings.Contains(lowerMsg, "no results") ||
		strings.Contains(lowerMsg, "track not found") ||
		strings.Contains(lowerMsg, "all services failed") {
		return "not_found"
	} else if strings.Contains(lowerMsg, "network") ||
		strings.Contains(lowerMsg, "connection") ||
		strings.Contains(lowerMsg, "timeout") ||
		strings.Contains(lowerMsg, "dial") {
		return "network"
	}

	return "unknown"
}

// isOutputStorageWriteFailure distinguishes an unwritable destination from a
// provider-specific failure. Provider fallback cannot repair the former: all
// providers receive the same output path, so continuing only delays the
// storage fallback and can replace the useful permission error with an
// unrelated error from the last provider.
func isOutputStorageWriteFailure(errorType, message string) bool {
	if strings.EqualFold(strings.TrimSpace(errorType), "permission") {
		return true
	}
	lowerMsg := strings.ToLower(strings.TrimSpace(message))
	if lowerMsg == "" {
		return false
	}
	return strings.Contains(lowerMsg, "operation not permitted") ||
		strings.Contains(lowerMsg, "permission denied") ||
		strings.Contains(lowerMsg, "read-only file system") ||
		strings.Contains(lowerMsg, "failed to create file") ||
		strings.Contains(lowerMsg, "failed to create directory")
}

func messageHasHTTPStatusCode(lowerMsg, code string) bool {
	return strings.Contains(lowerMsg, "http "+code) ||
		strings.Contains(lowerMsg, "http status "+code) ||
		strings.Contains(lowerMsg, "status "+code) ||
		strings.Contains(lowerMsg, code+" for ") ||
		strings.Contains(lowerMsg, code+":") ||
		strings.Contains(lowerMsg, code+";")
}
