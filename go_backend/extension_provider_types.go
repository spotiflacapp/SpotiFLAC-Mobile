package gobackend

import "strings"

type ExtTrackMetadata struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Artists     string `json:"artists"`
	AlbumName   string `json:"album_name"`
	AlbumArtist string `json:"album_artist,omitempty"`
	AlbumID     string `json:"album_id,omitempty"`
	AlbumURL    string `json:"album_url,omitempty"`
	ArtistID    string `json:"artist_id,omitempty"`
	ArtistURL   string `json:"artist_url,omitempty"`
	ExternalURL string `json:"external_urls,omitempty"`
	DurationMS  int    `json:"duration_ms"`
	CoverURL    string `json:"cover_url,omitempty"`
	PreviewURL  string `json:"preview_url,omitempty"`
	Images      string `json:"images,omitempty"`
	ReleaseDate string `json:"release_date,omitempty"`
	TrackNumber int    `json:"track_number,omitempty"`
	TotalTracks int    `json:"total_tracks,omitempty"`
	DiscNumber  int    `json:"disc_number,omitempty"`
	TotalDiscs  int    `json:"total_discs,omitempty"`
	ISRC        string `json:"isrc,omitempty"`
	ProviderID  string `json:"provider_id"`
	ItemType    string `json:"item_type,omitempty"`
	AlbumType   string `json:"album_type,omitempty"`
	Explicit    bool   `json:"explicit,omitempty"`

	TidalID       string            `json:"tidal_id,omitempty"`
	QobuzID       string            `json:"qobuz_id,omitempty"`
	DeezerID      string            `json:"deezer_id,omitempty"`
	SpotifyID     string            `json:"spotify_id,omitempty"`
	ExternalLinks map[string]string `json:"external_links,omitempty"`

	Label     string `json:"label,omitempty"`
	Copyright string `json:"copyright,omitempty"`
	Genre     string `json:"genre,omitempty"`
	Composer  string `json:"composer,omitempty"`

	AudioQuality string `json:"audio_quality,omitempty"`
	AudioModes   string `json:"audio_modes,omitempty"`
}

func (t *ExtTrackMetadata) ResolvedCoverURL() string {
	if t.CoverURL != "" {
		return t.CoverURL
	}
	return t.Images
}

type ExtAlbumMetadata struct {
	ID          string             `json:"id"`
	Name        string             `json:"name"`
	Artists     string             `json:"artists"`
	ArtistID    string             `json:"artist_id,omitempty"`
	CoverURL    string             `json:"cover_url,omitempty"`
	HeaderImage string             `json:"header_image,omitempty"`
	HeaderVideo string             `json:"header_video,omitempty"`
	ReleaseDate string             `json:"release_date,omitempty"`
	TotalTracks int                `json:"total_tracks"`
	AlbumType   string             `json:"album_type,omitempty"`
	AudioTraits []string           `json:"audio_traits,omitempty"`
	Tracks      []ExtTrackMetadata `json:"tracks"`
	ProviderID  string             `json:"provider_id"`
}

type ExtArtistMetadata struct {
	ID          string             `json:"id"`
	Name        string             `json:"name"`
	ImageURL    string             `json:"image_url,omitempty"`
	HeaderImage string             `json:"header_image,omitempty"`
	HeaderVideo string             `json:"header_video,omitempty"`
	Listeners   int                `json:"listeners,omitempty"`
	Albums      []ExtAlbumMetadata `json:"albums,omitempty"`
	Releases    []ExtAlbumMetadata `json:"releases,omitempty"`
	TopTracks   []ExtTrackMetadata `json:"top_tracks,omitempty"`
	ProviderID  string             `json:"provider_id"`
}

type ExtSearchResult struct {
	Tracks []ExtTrackMetadata `json:"tracks"`
	Total  int                `json:"total"`
}

type ExtAvailabilityResult struct {
	Available    bool   `json:"available"`
	Reason       string `json:"reason,omitempty"`
	TrackID      string `json:"track_id,omitempty"`
	SkipFallback bool   `json:"skip_fallback,omitempty"`
}

type DownloadDecryptionInfo struct {
	Strategy        string         `json:"strategy,omitempty"`
	Key             string         `json:"key,omitempty"`
	IV              string         `json:"iv,omitempty"`
	InputFormat     string         `json:"input_format,omitempty"`
	OutputExtension string         `json:"output_extension,omitempty"`
	Options         map[string]any `json:"options,omitempty"`
}

type ExtDownloadResult struct {
	Success           bool   `json:"success"`
	FilePath          string `json:"file_path,omitempty"`
	AlreadyExists     bool   `json:"already_exists,omitempty"`
	BitDepth          int    `json:"bit_depth,omitempty"`
	SampleRate        int    `json:"sample_rate,omitempty"`
	AudioCodec        string `json:"audio_codec,omitempty"`
	DurationMS        int    `json:"duration_ms,omitempty"`
	ErrorMessage      string `json:"error_message,omitempty"`
	ErrorType         string `json:"error_type,omitempty"`
	RetryAfterSeconds int    `json:"retry_after_seconds,omitempty"`

	Title                       string                  `json:"title,omitempty"`
	Artist                      string                  `json:"artist,omitempty"`
	Album                       string                  `json:"album,omitempty"`
	AlbumArtist                 string                  `json:"album_artist,omitempty"`
	TrackNumber                 int                     `json:"track_number,omitempty"`
	DiscNumber                  int                     `json:"disc_number,omitempty"`
	TotalTracks                 int                     `json:"total_tracks,omitempty"`
	TotalDiscs                  int                     `json:"total_discs,omitempty"`
	ReleaseDate                 string                  `json:"release_date,omitempty"`
	CoverURL                    string                  `json:"cover_url,omitempty"`
	ISRC                        string                  `json:"isrc,omitempty"`
	Genre                       string                  `json:"genre,omitempty"`
	Label                       string                  `json:"label,omitempty"`
	Copyright                   string                  `json:"copyright,omitempty"`
	Composer                    string                  `json:"composer,omitempty"`
	LyricsLRC                   string                  `json:"lyrics_lrc,omitempty"`
	DecryptionKey               string                  `json:"decryption_key,omitempty"`
	Decryption                  *DownloadDecryptionInfo `json:"decryption,omitempty"`
	ActualExtension             string                  `json:"actual_extension,omitempty"`
	OutputExtension             string                  `json:"output_extension,omitempty"`
	ActualContainer             string                  `json:"actual_container,omitempty"`
	RequiresContainerConversion bool                    `json:"requires_container_conversion,omitempty"`
}

const genericFFmpegMOVDecryptionStrategy = "ffmpeg.mov_key"

func cloneDownloadDecryptionInfo(info *DownloadDecryptionInfo) *DownloadDecryptionInfo {
	if info == nil {
		return nil
	}

	cloned := &DownloadDecryptionInfo{
		Strategy:        strings.TrimSpace(info.Strategy),
		Key:             strings.TrimSpace(info.Key),
		IV:              strings.TrimSpace(info.IV),
		InputFormat:     strings.TrimSpace(info.InputFormat),
		OutputExtension: strings.TrimSpace(info.OutputExtension),
	}
	if len(info.Options) > 0 {
		cloned.Options = make(map[string]any, len(info.Options))
		for key, value := range info.Options {
			cloned.Options[key] = value
		}
	}
	return cloned
}

func normalizeDownloadDecryptionStrategy(strategy string) string {
	switch strings.ToLower(strings.TrimSpace(strategy)) {
	case "", "ffmpeg.mov_key", "ffmpeg_mov_key", "mov_decryption_key", "mp4_decryption_key", "ffmpeg.mp4_decryption_key":
		return genericFFmpegMOVDecryptionStrategy
	default:
		return strings.TrimSpace(strategy)
	}
}

func normalizeDownloadDecryptionInfo(info *DownloadDecryptionInfo, legacyKey string) *DownloadDecryptionInfo {
	normalized := cloneDownloadDecryptionInfo(info)
	trimmedLegacyKey := strings.TrimSpace(legacyKey)

	if normalized == nil {
		if trimmedLegacyKey == "" {
			return nil
		}
		return &DownloadDecryptionInfo{
			Strategy:    genericFFmpegMOVDecryptionStrategy,
			Key:         trimmedLegacyKey,
			InputFormat: "mov",
		}
	}

	normalized.Strategy = normalizeDownloadDecryptionStrategy(normalized.Strategy)
	if normalized.Key == "" && trimmedLegacyKey != "" {
		normalized.Key = trimmedLegacyKey
	}
	if normalized.Strategy == "" && normalized.Key != "" {
		normalized.Strategy = genericFFmpegMOVDecryptionStrategy
	}
	if normalized.Strategy == genericFFmpegMOVDecryptionStrategy && normalized.InputFormat == "" {
		normalized.InputFormat = "mov"
	}
	if normalized.Strategy == genericFFmpegMOVDecryptionStrategy && normalized.Key == "" {
		return nil
	}

	return normalized
}

func normalizedDownloadDecryptionKey(info *DownloadDecryptionInfo, legacyKey string) string {
	if normalized := normalizeDownloadDecryptionInfo(info, legacyKey); normalized != nil {
		if normalized.Strategy == genericFFmpegMOVDecryptionStrategy {
			return normalized.Key
		}
	}
	return strings.TrimSpace(legacyKey)
}
