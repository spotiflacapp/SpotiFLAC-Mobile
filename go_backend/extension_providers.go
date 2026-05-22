package gobackend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/dop251/goja"
)

type ExtTrackMetadata struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Artists     string `json:"artists"`
	AlbumName   string `json:"album_name"`
	AlbumArtist string `json:"album_artist,omitempty"`
	DurationMS  int    `json:"duration_ms"`
	CoverURL    string `json:"cover_url,omitempty"`
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

	TidalID       string            `json:"tidal_id,omitempty"`
	QobuzID       string            `json:"qobuz_id,omitempty"`
	DeezerID      string            `json:"deezer_id,omitempty"`
	SpotifyID     string            `json:"spotify_id,omitempty"`
	ExternalLinks map[string]string `json:"external_links,omitempty"`

	AlbumID      string `json:"album_id,omitempty"`
	ArtistID     string `json:"artist_id,omitempty"`
	AlbumURL     string `json:"album_url,omitempty"`
	ExternalURLs string `json:"external_urls,omitempty"`

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
	ReleaseDate string             `json:"release_date,omitempty"`
	TotalTracks int                `json:"total_tracks"`
	AlbumType   string             `json:"album_type,omitempty"`
	Tracks      []ExtTrackMetadata `json:"tracks"`
	ProviderID  string             `json:"provider_id"`
}

type ExtArtistMetadata struct {
	ID          string             `json:"id"`
	Name        string             `json:"name"`
	ImageURL    string             `json:"image_url,omitempty"`
	HeaderImage string             `json:"header_image,omitempty"`
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

type ExtDownloadURLResult struct {
	URL        string `json:"url"`
	Format     string `json:"format"`
	BitDepth   int    `json:"bit_depth,omitempty"`
	SampleRate int    `json:"sample_rate,omitempty"`
}

func manifestCapabilityStringList(manifest *ExtensionManifest, key string) []string {
	if manifest == nil || manifest.Capabilities == nil {
		return nil
	}

	raw, ok := manifest.Capabilities[key]
	if !ok {
		return nil
	}

	values, ok := raw.([]interface{})
	if !ok {
		return nil
	}

	result := make([]string, 0, len(values))
	for _, value := range values {
		str, ok := value.(string)
		if !ok {
			continue
		}
		trimmed := strings.ToLower(strings.TrimSpace(str))
		if trimmed == "" {
			continue
		}
		result = append(result, trimmed)
	}
	return result
}

func extensionReplacesBuiltInProvider(ext *loadedExtension, providerID string) bool {
	if ext == nil {
		return false
	}

	normalized := strings.ToLower(strings.TrimSpace(providerID))
	if normalized == "" {
		return false
	}

	for _, replaced := range manifestCapabilityStringList(ext.Manifest, "replacesBuiltInProviders") {
		if replaced == normalized {
			return true
		}
	}

	return false
}

func trimKnownProviderPrefix(trackID, providerID string) string {
	trimmedID := strings.TrimSpace(trackID)
	normalizedProvider := strings.ToLower(strings.TrimSpace(providerID))
	if trimmedID == "" || normalizedProvider == "" {
		return trimmedID
	}

	prefix := normalizedProvider + ":"
	if strings.HasPrefix(strings.ToLower(trimmedID), prefix) {
		return trimmedID[len(prefix):]
	}

	return trimmedID
}

func resolvePreferredTrackIDForExtension(ext *loadedExtension, req DownloadRequest, explicitTrackID string) string {
	candidates := make([]string, 0, 8)
	appendCandidate := func(value string) {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			return
		}
		for _, existing := range candidates {
			if existing == trimmed {
				return
			}
		}
		candidates = append(candidates, trimmed)
	}

	appendCandidate(explicitTrackID)

	if extensionReplacesBuiltInProvider(ext, "tidal") {
		appendCandidate(req.TidalID)
		appendCandidate(trimKnownProviderPrefix(req.SpotifyID, "tidal"))
	}
	if extensionReplacesBuiltInProvider(ext, "qobuz") {
		appendCandidate(req.QobuzID)
		appendCandidate(trimKnownProviderPrefix(req.SpotifyID, "qobuz"))
	}
	if extensionReplacesBuiltInProvider(ext, "deezer") {
		appendCandidate(req.DeezerID)
		appendCandidate(trimKnownProviderPrefix(req.SpotifyID, "deezer"))
	}
	if extensionReplacesBuiltInProvider(ext, "spotify") {
		appendCandidate(trimKnownProviderPrefix(req.SpotifyID, "spotify"))
		appendCandidate(req.SpotifyID)
	}

	appendCandidate(req.SpotifyID)
	appendCandidate(req.TidalID)
	appendCandidate(req.QobuzID)
	appendCandidate(req.DeezerID)

	if len(candidates) == 0 {
		return ""
	}
	return candidates[0]
}

func normalizeDownloadResultExtension(candidates ...string) string {
	for _, candidate := range candidates {
		ext := strings.TrimSpace(strings.ToLower(candidate))
		if ext == "" {
			continue
		}
		if !strings.HasPrefix(ext, ".") {
			ext = "." + ext
		}
		if ext == ".mp4" {
			return ".m4a"
		}
		return ext
	}
	return ""
}

func normalizeExtensionDownloadResult(result *ExtDownloadResult) (DownloadResult, bool) {
	if result == nil {
		return DownloadResult{}, false
	}

	downloadResult := DownloadResult{
		FilePath:                    strings.TrimSpace(result.FilePath),
		BitDepth:                    result.BitDepth,
		SampleRate:                  result.SampleRate,
		AudioCodec:                  strings.TrimSpace(result.AudioCodec),
		Title:                       result.Title,
		Artist:                      result.Artist,
		Album:                       result.Album,
		ReleaseDate:                 result.ReleaseDate,
		TrackNumber:                 result.TrackNumber,
		TotalTracks:                 result.TotalTracks,
		DiscNumber:                  result.DiscNumber,
		TotalDiscs:                  result.TotalDiscs,
		ISRC:                        result.ISRC,
		CoverURL:                    result.CoverURL,
		Genre:                       result.Genre,
		Label:                       result.Label,
		Copyright:                   result.Copyright,
		Composer:                    result.Composer,
		LyricsLRC:                   result.LyricsLRC,
		DecryptionKey:               result.DecryptionKey,
		Decryption:                  normalizeDownloadDecryptionInfo(result.Decryption, result.DecryptionKey),
		ActualExtension:             normalizeDownloadResultExtension(result.ActualExtension, result.OutputExtension),
		ActualContainer:             strings.TrimSpace(result.ActualContainer),
		RequiresContainerConversion: result.RequiresContainerConversion,
	}

	alreadyExists := result.AlreadyExists
	if strings.HasPrefix(downloadResult.FilePath, "EXISTS:") {
		alreadyExists = true
		downloadResult.FilePath = strings.TrimPrefix(downloadResult.FilePath, "EXISTS:")
	}

	enrichResultQualityFromFile(&downloadResult)
	return downloadResult, alreadyExists
}

func overlayExtensionDownloadMetadata(resp *DownloadResponse, result *ExtDownloadResult) {
	if resp == nil || result == nil {
		return
	}

	if strings.TrimSpace(resp.Title) == "" && result.Title != "" {
		resp.Title = result.Title
	}
	if strings.TrimSpace(resp.Artist) == "" && result.Artist != "" {
		resp.Artist = result.Artist
	}
	if strings.TrimSpace(resp.Album) == "" && result.Album != "" {
		resp.Album = result.Album
	}
	if strings.TrimSpace(resp.AlbumArtist) == "" && result.AlbumArtist != "" {
		resp.AlbumArtist = result.AlbumArtist
	}
	if resp.TrackNumber == 0 && result.TrackNumber > 0 {
		resp.TrackNumber = result.TrackNumber
	}
	if resp.DiscNumber == 0 && result.DiscNumber > 0 {
		resp.DiscNumber = result.DiscNumber
	}
	if resp.TotalTracks == 0 && result.TotalTracks > 0 {
		resp.TotalTracks = result.TotalTracks
	}
	if resp.TotalDiscs == 0 && result.TotalDiscs > 0 {
		resp.TotalDiscs = result.TotalDiscs
	}
	if strings.TrimSpace(resp.ReleaseDate) == "" && result.ReleaseDate != "" {
		resp.ReleaseDate = result.ReleaseDate
	}
	if strings.TrimSpace(resp.CoverURL) == "" && result.CoverURL != "" {
		resp.CoverURL = result.CoverURL
	}
	if strings.TrimSpace(resp.ISRC) == "" && result.ISRC != "" {
		resp.ISRC = result.ISRC
	}
	if strings.TrimSpace(resp.Genre) == "" && result.Genre != "" {
		resp.Genre = result.Genre
	}
	if strings.TrimSpace(resp.Label) == "" && result.Label != "" {
		resp.Label = result.Label
	}
	if strings.TrimSpace(resp.Copyright) == "" && result.Copyright != "" {
		resp.Copyright = result.Copyright
	}
	if strings.TrimSpace(resp.Composer) == "" && result.Composer != "" {
		resp.Composer = result.Composer
	}
	if result.LyricsLRC != "" {
		resp.LyricsLRC = result.LyricsLRC
	}
	if result.DecryptionKey != "" {
		resp.DecryptionKey = result.DecryptionKey
	}
	if normalized := normalizeDownloadDecryptionInfo(result.Decryption, result.DecryptionKey); normalized != nil {
		resp.Decryption = normalized
	}
	if ext := normalizeDownloadResultExtension(result.ActualExtension, result.OutputExtension); ext != "" {
		resp.ActualExtension = ext
	}
	if container := strings.TrimSpace(result.ActualContainer); container != "" {
		resp.ActualContainer = container
	}
	if result.RequiresContainerConversion {
		resp.RequiresContainerConversion = true
	}
}

func applyExtensionRequestFallbacks(resp *DownloadResponse, req DownloadRequest) {
	if resp == nil {
		return
	}

	if req.AlbumName != "" && resp.Album == "" {
		resp.Album = req.AlbumName
	}
	if req.AlbumArtist != "" && resp.AlbumArtist == "" {
		resp.AlbumArtist = req.AlbumArtist
	}
	if req.ReleaseDate != "" && resp.ReleaseDate == "" {
		resp.ReleaseDate = req.ReleaseDate
	}
	if req.ISRC != "" && resp.ISRC == "" {
		resp.ISRC = req.ISRC
	}
	if req.TrackNumber > 0 && resp.TrackNumber == 0 {
		resp.TrackNumber = req.TrackNumber
	}
	if req.TotalTracks > 0 && resp.TotalTracks == 0 {
		resp.TotalTracks = req.TotalTracks
	}
	if req.DiscNumber > 0 && resp.DiscNumber == 0 {
		resp.DiscNumber = req.DiscNumber
	}
	if req.TotalDiscs > 0 && resp.TotalDiscs == 0 {
		resp.TotalDiscs = req.TotalDiscs
	}
	if req.CoverURL != "" && resp.CoverURL == "" {
		resp.CoverURL = req.CoverURL
	}
}

func shouldStopProviderFallback(availability *ExtAvailabilityResult) bool {
	return availability != nil && availability.SkipFallback
}

func resolveExtensionAvailabilityReason(availability *ExtAvailabilityResult, err error) string {
	if availability != nil {
		if reason := strings.TrimSpace(availability.Reason); reason != "" {
			return reason
		}
	}
	if err != nil {
		return err.Error()
	}
	return "extension requested no further fallback"
}

func buildExtensionFallbackStoppedResponse(providerID string, availability *ExtAvailabilityResult, err error) *DownloadResponse {
	reason := resolveExtensionAvailabilityReason(availability, err)
	return &DownloadResponse{
		Success:   false,
		Error:     fmt.Sprintf("Fallback stopped by %s: %s", providerID, reason),
		ErrorType: "extension_error",
		Service:   providerID,
	}
}

func shouldAbortCancelledFallback(itemID string, err error) bool {
	if errors.Is(err, ErrDownloadCancelled) {
		return true
	}
	return itemID != "" && isDownloadCancelled(itemID)
}

type DownloadDecryptionInfo struct {
	Strategy        string                 `json:"strategy,omitempty"`
	Key             string                 `json:"key,omitempty"`
	IV              string                 `json:"iv,omitempty"`
	InputFormat     string                 `json:"input_format,omitempty"`
	OutputExtension string                 `json:"output_extension,omitempty"`
	Options         map[string]interface{} `json:"options,omitempty"`
}

type ExtDownloadResult struct {
	Success       bool   `json:"success"`
	FilePath      string `json:"file_path,omitempty"`
	AlreadyExists bool   `json:"already_exists,omitempty"`
	BitDepth      int    `json:"bit_depth,omitempty"`
	SampleRate    int    `json:"sample_rate,omitempty"`
	AudioCodec    string `json:"audio_codec,omitempty"`
	ErrorMessage  string `json:"error_message,omitempty"`
	ErrorType     string `json:"error_type,omitempty"`

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
		cloned.Options = make(map[string]interface{}, len(info.Options))
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

type extensionProviderWrapper struct {
	extension *loadedExtension
	vm        *goja.Runtime
}

func newExtensionProviderWrapper(ext *loadedExtension) *extensionProviderWrapper {
	return &extensionProviderWrapper{
		extension: ext,
		vm:        ext.VM,
	}
}

func (p *extensionProviderWrapper) lockReadyVM() error {
	vm, err := p.extension.lockReadyVM()
	if err != nil {
		return err
	}
	p.vm = vm
	return nil
}

func (p *extensionProviderWrapper) SearchTracks(query string, limit int) (*ExtSearchResult, error) {
	return p.SearchTracksForItemID(query, limit, "")
}

func gojaValueIsEmpty(value goja.Value) bool {
	return value == nil || goja.IsUndefined(value) || goja.IsNull(value)
}

func gojaObjectString(obj *goja.Object, keys ...string) string {
	for _, key := range keys {
		value := obj.Get(key)
		if gojaValueIsEmpty(value) {
			continue
		}
		if str, ok := value.Export().(string); ok {
			return str
		}
	}
	return ""
}

func gojaObjectValue(obj *goja.Object, keys ...string) goja.Value {
	for _, key := range keys {
		value := obj.Get(key)
		if !gojaValueIsEmpty(value) {
			return value
		}
	}
	return nil
}

func gojaObjectInt(obj *goja.Object, keys ...string) int {
	for _, key := range keys {
		value := obj.Get(key)
		if gojaValueIsEmpty(value) {
			continue
		}
		return int(value.ToInteger())
	}
	return 0
}

func gojaObjectInt64(obj *goja.Object, keys ...string) int64 {
	for _, key := range keys {
		value := obj.Get(key)
		if gojaValueIsEmpty(value) {
			continue
		}
		return value.ToInteger()
	}
	return 0
}

func gojaObjectFloat(obj *goja.Object, keys ...string) float64 {
	for _, key := range keys {
		value := obj.Get(key)
		if gojaValueIsEmpty(value) {
			continue
		}
		return value.ToFloat()
	}
	return 0
}

func gojaObjectBool(obj *goja.Object, keys ...string) bool {
	for _, key := range keys {
		value := obj.Get(key)
		if gojaValueIsEmpty(value) {
			continue
		}
		return value.ToBoolean()
	}
	return false
}

func gojaObjectInterfaceMap(obj *goja.Object, keys ...string) map[string]interface{} {
	value := gojaObjectValue(obj, keys...)
	if gojaValueIsEmpty(value) {
		return nil
	}

	exported, ok := value.Export().(map[string]interface{})
	if !ok || len(exported) == 0 {
		return nil
	}
	return exported
}

func gojaObjectStringMap(vm *goja.Runtime, obj *goja.Object, keys ...string) map[string]string {
	value := gojaObjectValue(obj, keys...)
	if gojaValueIsEmpty(value) {
		return nil
	}

	valueObj := value.ToObject(vm)
	objectKeys := valueObj.Keys()
	if len(objectKeys) == 0 {
		return nil
	}

	result := make(map[string]string, len(objectKeys))
	for _, childKey := range objectKeys {
		childValue := valueObj.Get(childKey)
		if gojaValueIsEmpty(childValue) {
			continue
		}
		result[childKey] = childValue.String()
	}
	if len(result) == 0 {
		return nil
	}
	return result
}

func gojaArrayLength(value goja.Value, vm *goja.Runtime) (int, error) {
	if gojaValueIsEmpty(value) {
		return 0, nil
	}
	lengthValue := value.ToObject(vm).Get("length")
	if gojaValueIsEmpty(lengthValue) {
		return 0, fmt.Errorf("value is not an array")
	}
	length := lengthValue.ToInteger()
	if length <= 0 {
		return 0, nil
	}
	return int(length), nil
}

func parseExtensionTrackValue(vm *goja.Runtime, value goja.Value) ExtTrackMetadata {
	obj := value.ToObject(vm)
	return ExtTrackMetadata{
		ID:            gojaObjectString(obj, "id"),
		Name:          gojaObjectString(obj, "name"),
		Artists:       gojaObjectString(obj, "artists"),
		AlbumName:     gojaObjectString(obj, "album_name", "albumName"),
		AlbumArtist:   gojaObjectString(obj, "album_artist", "albumArtist"),
		DurationMS:    gojaObjectInt(obj, "duration_ms", "durationMs"),
		CoverURL:      gojaObjectString(obj, "cover_url", "coverUrl"),
		Images:        gojaObjectString(obj, "images"),
		ReleaseDate:   gojaObjectString(obj, "release_date", "releaseDate"),
		TrackNumber:   gojaObjectInt(obj, "track_number", "trackNumber"),
		TotalTracks:   gojaObjectInt(obj, "total_tracks", "totalTracks"),
		DiscNumber:    gojaObjectInt(obj, "disc_number", "discNumber"),
		TotalDiscs:    gojaObjectInt(obj, "total_discs", "totalDiscs"),
		ISRC:          gojaObjectString(obj, "isrc"),
		ProviderID:    gojaObjectString(obj, "provider_id", "providerId"),
		ItemType:      gojaObjectString(obj, "item_type", "itemType"),
		AlbumType:     gojaObjectString(obj, "album_type", "albumType"),
		TidalID:       gojaObjectString(obj, "tidal_id", "tidalId"),
		QobuzID:       gojaObjectString(obj, "qobuz_id", "qobuzId"),
		DeezerID:      gojaObjectString(obj, "deezer_id", "deezerId"),
		SpotifyID:     gojaObjectString(obj, "spotify_id", "spotifyId"),
		ExternalLinks: gojaObjectStringMap(vm, obj, "external_links", "externalLinks"),
		AlbumID:       gojaObjectString(obj, "album_id", "albumId"),
		ArtistID:      gojaObjectString(obj, "artist_id", "artistId"),
		AlbumURL:      gojaObjectString(obj, "album_url", "albumUrl"),
		ExternalURLs:  gojaObjectString(obj, "external_urls", "externalUrls"),
		Label:         gojaObjectString(obj, "label"),
		Copyright:     gojaObjectString(obj, "copyright"),
		Genre:         gojaObjectString(obj, "genre"),
		Composer:      gojaObjectString(obj, "composer"),
		AudioQuality:  gojaObjectString(obj, "audio_quality", "audioQuality"),
		AudioModes:    gojaObjectString(obj, "audio_modes", "audioModes"),
	}
}

func parseExtensionTrackArray(vm *goja.Runtime, value goja.Value) ([]ExtTrackMetadata, error) {
	length, err := gojaArrayLength(value, vm)
	if err != nil {
		return nil, err
	}
	if length == 0 {
		return []ExtTrackMetadata{}, nil
	}

	arrayObj := value.ToObject(vm)
	tracks := make([]ExtTrackMetadata, 0, length)
	for i := 0; i < length; i++ {
		trackValue := arrayObj.Get(strconv.Itoa(i))
		if gojaValueIsEmpty(trackValue) {
			continue
		}
		tracks = append(tracks, parseExtensionTrackValue(vm, trackValue))
	}
	return tracks, nil
}

func parseExtensionAlbumValue(vm *goja.Runtime, value goja.Value) (ExtAlbumMetadata, error) {
	if gojaValueIsEmpty(value) {
		return ExtAlbumMetadata{}, nil
	}

	obj := value.ToObject(vm)
	tracks := []ExtTrackMetadata{}
	if tracksValue := gojaObjectValue(obj, "tracks"); !gojaValueIsEmpty(tracksValue) {
		parsedTracks, err := parseExtensionTrackArray(vm, tracksValue)
		if err != nil {
			return ExtAlbumMetadata{}, err
		}
		tracks = parsedTracks
	}

	return ExtAlbumMetadata{
		ID:          gojaObjectString(obj, "id"),
		Name:        gojaObjectString(obj, "name"),
		Artists:     gojaObjectString(obj, "artists"),
		ArtistID:    gojaObjectString(obj, "artist_id", "artistId"),
		CoverURL:    gojaObjectString(obj, "cover_url", "coverUrl", "images"),
		ReleaseDate: gojaObjectString(obj, "release_date", "releaseDate"),
		TotalTracks: gojaObjectInt(obj, "total_tracks", "totalTracks"),
		AlbumType:   gojaObjectString(obj, "album_type", "albumType"),
		Tracks:      tracks,
		ProviderID:  gojaObjectString(obj, "provider_id", "providerId"),
	}, nil
}

func parseExtensionAlbumArray(vm *goja.Runtime, value goja.Value) ([]ExtAlbumMetadata, error) {
	length, err := gojaArrayLength(value, vm)
	if err != nil {
		return nil, err
	}
	if length == 0 {
		return []ExtAlbumMetadata{}, nil
	}

	arrayObj := value.ToObject(vm)
	albums := make([]ExtAlbumMetadata, 0, length)
	for i := 0; i < length; i++ {
		albumValue := arrayObj.Get(strconv.Itoa(i))
		if gojaValueIsEmpty(albumValue) {
			continue
		}
		album, err := parseExtensionAlbumValue(vm, albumValue)
		if err != nil {
			return nil, err
		}
		albums = append(albums, album)
	}
	return albums, nil
}

func parseExtensionArtistValue(vm *goja.Runtime, value goja.Value) (ExtArtistMetadata, error) {
	if gojaValueIsEmpty(value) {
		return ExtArtistMetadata{}, nil
	}

	obj := value.ToObject(vm)
	albums := []ExtAlbumMetadata{}
	if albumsValue := gojaObjectValue(obj, "albums"); !gojaValueIsEmpty(albumsValue) {
		parsedAlbums, err := parseExtensionAlbumArray(vm, albumsValue)
		if err != nil {
			return ExtArtistMetadata{}, err
		}
		albums = parsedAlbums
	}

	releases := []ExtAlbumMetadata{}
	if releasesValue := gojaObjectValue(obj, "releases"); !gojaValueIsEmpty(releasesValue) {
		parsedReleases, err := parseExtensionAlbumArray(vm, releasesValue)
		if err != nil {
			return ExtArtistMetadata{}, err
		}
		releases = parsedReleases
	}

	topTracks := []ExtTrackMetadata{}
	if topTracksValue := gojaObjectValue(obj, "top_tracks", "topTracks"); !gojaValueIsEmpty(topTracksValue) {
		parsedTopTracks, err := parseExtensionTrackArray(vm, topTracksValue)
		if err != nil {
			return ExtArtistMetadata{}, err
		}
		topTracks = parsedTopTracks
	}

	return ExtArtistMetadata{
		ID:          gojaObjectString(obj, "id"),
		Name:        gojaObjectString(obj, "name"),
		ImageURL:    gojaObjectString(obj, "image_url", "imageUrl"),
		HeaderImage: gojaObjectString(obj, "header_image", "headerImage"),
		Listeners:   gojaObjectInt(obj, "listeners"),
		Albums:      albums,
		Releases:    releases,
		TopTracks:   topTracks,
		ProviderID:  gojaObjectString(obj, "provider_id", "providerId"),
	}, nil
}

func parseExtensionAvailabilityValue(vm *goja.Runtime, value goja.Value) ExtAvailabilityResult {
	obj := value.ToObject(vm)
	return ExtAvailabilityResult{
		Available:    gojaObjectBool(obj, "available"),
		Reason:       gojaObjectString(obj, "reason"),
		TrackID:      gojaObjectString(obj, "track_id", "trackId"),
		SkipFallback: gojaObjectBool(obj, "skip_fallback", "skipFallback"),
	}
}

func parseExtensionDownloadURLValue(vm *goja.Runtime, value goja.Value) ExtDownloadURLResult {
	obj := value.ToObject(vm)
	return ExtDownloadURLResult{
		URL:        gojaObjectString(obj, "url"),
		Format:     gojaObjectString(obj, "format"),
		BitDepth:   gojaObjectInt(obj, "bit_depth", "bitDepth"),
		SampleRate: gojaObjectInt(obj, "sample_rate", "sampleRate"),
	}
}

func parseExtensionDownloadDecryptionValue(vm *goja.Runtime, value goja.Value) *DownloadDecryptionInfo {
	if gojaValueIsEmpty(value) {
		return nil
	}

	obj := value.ToObject(vm)
	info := &DownloadDecryptionInfo{
		Strategy:        gojaObjectString(obj, "strategy"),
		Key:             gojaObjectString(obj, "key"),
		IV:              gojaObjectString(obj, "iv"),
		InputFormat:     gojaObjectString(obj, "input_format", "inputFormat"),
		OutputExtension: gojaObjectString(obj, "output_extension", "outputExtension"),
		Options:         gojaObjectInterfaceMap(obj, "options"),
	}
	if info.Strategy == "" && info.Key == "" && info.IV == "" && info.InputFormat == "" && info.OutputExtension == "" && len(info.Options) == 0 {
		return nil
	}
	return info
}

func parseExtensionDownloadResultValue(vm *goja.Runtime, value goja.Value) ExtDownloadResult {
	obj := value.ToObject(vm)
	return ExtDownloadResult{
		Success:         gojaObjectBool(obj, "success"),
		FilePath:        gojaObjectString(obj, "file_path", "filePath", "path"),
		AlreadyExists:   gojaObjectBool(obj, "already_exists", "alreadyExists"),
		BitDepth:        gojaObjectInt(obj, "bit_depth", "bitDepth"),
		SampleRate:      gojaObjectInt(obj, "sample_rate", "sampleRate"),
		AudioCodec:      gojaObjectString(obj, "audio_codec", "audioCodec", "codec"),
		ErrorMessage:    gojaObjectString(obj, "error_message", "errorMessage", "error"),
		ErrorType:       gojaObjectString(obj, "error_type", "errorType"),
		Title:           gojaObjectString(obj, "title"),
		Artist:          gojaObjectString(obj, "artist"),
		Album:           gojaObjectString(obj, "album"),
		AlbumArtist:     gojaObjectString(obj, "album_artist", "albumArtist"),
		TrackNumber:     gojaObjectInt(obj, "track_number", "trackNumber"),
		DiscNumber:      gojaObjectInt(obj, "disc_number", "discNumber"),
		TotalTracks:     gojaObjectInt(obj, "total_tracks", "totalTracks"),
		TotalDiscs:      gojaObjectInt(obj, "total_discs", "totalDiscs"),
		ReleaseDate:     gojaObjectString(obj, "release_date", "releaseDate"),
		CoverURL:        gojaObjectString(obj, "cover_url", "coverUrl"),
		ISRC:            gojaObjectString(obj, "isrc"),
		Genre:           gojaObjectString(obj, "genre"),
		Label:           gojaObjectString(obj, "label"),
		Copyright:       gojaObjectString(obj, "copyright"),
		Composer:        gojaObjectString(obj, "composer"),
		LyricsLRC:       gojaObjectString(obj, "lyrics_lrc", "lyricsLrc"),
		DecryptionKey:   gojaObjectString(obj, "decryption_key", "decryptionKey"),
		Decryption:      parseExtensionDownloadDecryptionValue(vm, gojaObjectValue(obj, "decryption")),
		ActualExtension: gojaObjectString(obj, "actual_extension", "actualExtension"),
		OutputExtension: gojaObjectString(obj, "output_extension", "outputExtension"),
		ActualContainer: gojaObjectString(obj, "actual_container", "actualContainer", "container"),
		RequiresContainerConversion: gojaObjectBool(
			obj,
			"requires_container_conversion",
			"requiresContainerConversion",
		),
	}
}

func parseExtensionURLHandleValue(vm *goja.Runtime, value goja.Value) (ExtURLHandleResult, error) {
	obj := value.ToObject(vm)
	handleResult := ExtURLHandleResult{
		Type:     gojaObjectString(obj, "type"),
		Name:     gojaObjectString(obj, "name"),
		CoverURL: gojaObjectString(obj, "cover_url", "coverUrl"),
	}

	if trackValue := gojaObjectValue(obj, "track"); !gojaValueIsEmpty(trackValue) {
		track := parseExtensionTrackValue(vm, trackValue)
		handleResult.Track = &track
	}
	if tracksValue := gojaObjectValue(obj, "tracks"); !gojaValueIsEmpty(tracksValue) {
		tracks, err := parseExtensionTrackArray(vm, tracksValue)
		if err != nil {
			return ExtURLHandleResult{}, err
		}
		handleResult.Tracks = tracks
	}
	if albumValue := gojaObjectValue(obj, "album"); !gojaValueIsEmpty(albumValue) {
		album, err := parseExtensionAlbumValue(vm, albumValue)
		if err != nil {
			return ExtURLHandleResult{}, err
		}
		handleResult.Album = &album
	}
	if artistValue := gojaObjectValue(obj, "artist"); !gojaValueIsEmpty(artistValue) {
		artist, err := parseExtensionArtistValue(vm, artistValue)
		if err != nil {
			return ExtURLHandleResult{}, err
		}
		handleResult.Artist = &artist
	}

	return handleResult, nil
}

func parseExtensionMatchTrackValue(vm *goja.Runtime, value goja.Value) MatchTrackResult {
	obj := value.ToObject(vm)
	return MatchTrackResult{
		Matched:    gojaObjectBool(obj, "matched"),
		TrackID:    gojaObjectString(obj, "track_id", "trackId"),
		Confidence: gojaObjectFloat(obj, "confidence"),
		Reason:     gojaObjectString(obj, "reason"),
	}
}

func parseExtensionPostProcessValue(vm *goja.Runtime, value goja.Value) PostProcessResult {
	obj := value.ToObject(vm)
	return PostProcessResult{
		Success:     gojaObjectBool(obj, "success"),
		NewFilePath: gojaObjectString(obj, "new_file_path", "newFilePath"),
		NewFileURI:  gojaObjectString(obj, "new_file_uri", "newFileUri"),
		Error:       gojaObjectString(obj, "error"),
		BitDepth:    gojaObjectInt(obj, "bit_depth", "bitDepth"),
		SampleRate:  gojaObjectInt(obj, "sample_rate", "sampleRate"),
	}
}

func parseExtensionLyricsLineArray(vm *goja.Runtime, value goja.Value) ([]ExtLyricsLine, error) {
	length, err := gojaArrayLength(value, vm)
	if err != nil {
		return nil, err
	}
	if length == 0 {
		return []ExtLyricsLine{}, nil
	}

	arrayObj := value.ToObject(vm)
	lines := make([]ExtLyricsLine, 0, length)
	for i := 0; i < length; i++ {
		lineValue := arrayObj.Get(strconv.Itoa(i))
		if gojaValueIsEmpty(lineValue) {
			continue
		}
		lineObj := lineValue.ToObject(vm)
		lines = append(lines, ExtLyricsLine{
			StartTimeMs: gojaObjectInt64(lineObj, "startTimeMs", "start_time_ms"),
			Words:       gojaObjectString(lineObj, "words"),
			EndTimeMs:   gojaObjectInt64(lineObj, "endTimeMs", "end_time_ms"),
		})
	}
	return lines, nil
}

func parseExtensionLyricsValue(vm *goja.Runtime, value goja.Value) (ExtLyricsResult, error) {
	obj := value.ToObject(vm)
	lines := []ExtLyricsLine{}
	if linesValue := gojaObjectValue(obj, "lines"); !gojaValueIsEmpty(linesValue) {
		parsedLines, err := parseExtensionLyricsLineArray(vm, linesValue)
		if err != nil {
			return ExtLyricsResult{}, err
		}
		lines = parsedLines
	}

	return ExtLyricsResult{
		Lines:        lines,
		SyncType:     gojaObjectString(obj, "syncType", "sync_type"),
		Instrumental: gojaObjectBool(obj, "instrumental"),
		PlainLyrics:  gojaObjectString(obj, "plainLyrics", "plain_lyrics"),
		Provider:     gojaObjectString(obj, "provider"),
	}, nil
}

func parseExtensionSearchResult(vm *goja.Runtime, value goja.Value) (ExtSearchResult, error) {
	if gojaValueIsEmpty(value) {
		return ExtSearchResult{}, nil
	}

	resultObj := value.ToObject(vm)
	tracksValue := resultObj.Get("tracks")
	if gojaValueIsEmpty(tracksValue) {
		tracks, err := parseExtensionTrackArray(vm, value)
		if err != nil {
			return ExtSearchResult{}, err
		}
		return ExtSearchResult{
			Tracks: tracks,
			Total:  len(tracks),
		}, nil
	}

	tracks, err := parseExtensionTrackArray(vm, tracksValue)
	if err != nil {
		return ExtSearchResult{}, err
	}
	total := gojaObjectInt(resultObj, "total")
	if total == 0 {
		total = len(tracks)
	}
	return ExtSearchResult{
		Tracks: tracks,
		Total:  total,
	}, nil
}

func (p *extensionProviderWrapper) SearchTracksForItemID(query string, limit int, itemID string) (*ExtSearchResult, error) {
	if !p.extension.Manifest.IsMetadataProvider() {
		return nil, fmt.Errorf("extension '%s' is not a metadata provider", p.extension.ID)
	}

	if !p.extension.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", p.extension.ID)
	}
	perf := newExtensionCallPerf(p.extension.ID, "searchTracks")
	defer perf.finish()
	initStartedAt := time.Now()
	if err := p.lockReadyVM(); err != nil {
		return nil, err
	}
	perf.recordInit(time.Since(initStartedAt))
	defer p.extension.VMMu.Unlock()
	if itemID != "" {
		if p.extension.runtime != nil {
			p.extension.runtime.setActiveDownloadItemID(itemID)
			defer p.extension.runtime.clearActiveDownloadItemID()
		}
		initDownloadCancel(itemID)
		defer clearDownloadCancel(itemID)
		if isDownloadCancelled(itemID) {
			return nil, ErrDownloadCancelled
		}
	}

	script := fmt.Sprintf(`
		(function() {
			if (typeof extension !== 'undefined' && typeof extension.searchTracks === 'function') {
				return extension.searchTracks(%q, %d);
			}
			return null;
		})()
	`, query, limit)

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutAndRecover(p.vm, script, DefaultJSTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		if isDownloadCancelled(itemID) {
			return nil, ErrDownloadCancelled
		}
		if IsTimeoutError(err) {
			return nil, fmt.Errorf("searchTracks timeout: extension took too long to respond")
		}
		return nil, fmt.Errorf("searchTracks failed: %w", err)
	}
	if isDownloadCancelled(itemID) {
		return nil, ErrDownloadCancelled
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return nil, fmt.Errorf("searchTracks returned null")
	}

	parseStartedAt := time.Now()
	searchResult, err := parseExtensionSearchResult(p.vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	if err != nil {
		return nil, fmt.Errorf("failed to parse search result: %w", err)
	}
	perf.setItems(len(searchResult.Tracks))

	for i := range searchResult.Tracks {
		searchResult.Tracks[i].ProviderID = p.extension.ID
	}

	return &searchResult, nil
}

func (p *extensionProviderWrapper) GetTrack(trackID string) (*ExtTrackMetadata, error) {
	if !p.extension.Manifest.IsMetadataProvider() {
		return nil, fmt.Errorf("extension '%s' is not a metadata provider", p.extension.ID)
	}

	if !p.extension.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", p.extension.ID)
	}
	perf := newExtensionCallPerf(p.extension.ID, "getTrack")
	defer perf.finish()
	initStartedAt := time.Now()
	if err := p.lockReadyVM(); err != nil {
		return nil, err
	}
	perf.recordInit(time.Since(initStartedAt))
	defer p.extension.VMMu.Unlock()

	script := fmt.Sprintf(`
		(function() {
			if (typeof extension !== 'undefined' && typeof extension.getTrack === 'function') {
				return extension.getTrack(%q);
			}
			return null;
		})()
	`, trackID)

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutAndRecover(p.vm, script, DefaultJSTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		if IsTimeoutError(err) {
			return nil, fmt.Errorf("getTrack timeout: extension took too long to respond")
		}
		return nil, fmt.Errorf("getTrack failed: %w", err)
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return nil, fmt.Errorf("getTrack returned null")
	}

	parseStartedAt := time.Now()
	track := parseExtensionTrackValue(p.vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	perf.setItems(1)
	track.ProviderID = p.extension.ID
	return &track, nil
}

func (p *extensionProviderWrapper) GetAlbum(albumID string) (*ExtAlbumMetadata, error) {
	if !p.extension.Manifest.IsMetadataProvider() {
		return nil, fmt.Errorf("extension '%s' is not a metadata provider", p.extension.ID)
	}

	if !p.extension.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", p.extension.ID)
	}
	perf := newExtensionCallPerf(p.extension.ID, "getAlbum")
	defer perf.finish()
	initStartedAt := time.Now()
	if err := p.lockReadyVM(); err != nil {
		return nil, err
	}
	perf.recordInit(time.Since(initStartedAt))
	defer p.extension.VMMu.Unlock()

	script := fmt.Sprintf(`
		(function() {
			if (typeof extension !== 'undefined' && typeof extension.getAlbum === 'function') {
				return extension.getAlbum(%q);
			}
			return null;
		})()
	`, albumID)

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutAndRecover(p.vm, script, DefaultJSTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		if IsTimeoutError(err) {
			return nil, fmt.Errorf("getAlbum timeout: extension took too long to respond")
		}
		return nil, fmt.Errorf("getAlbum failed: %w", err)
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return nil, fmt.Errorf("getAlbum returned null")
	}

	parseStartedAt := time.Now()
	album, err := parseExtensionAlbumValue(p.vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	if err != nil {
		return nil, fmt.Errorf("failed to parse album: %w", err)
	}
	perf.setItems(len(album.Tracks))

	album.ProviderID = p.extension.ID
	for i := range album.Tracks {
		album.Tracks[i].ProviderID = p.extension.ID
	}
	return &album, nil
}

func (p *extensionProviderWrapper) GetPlaylist(playlistID string) (*ExtAlbumMetadata, error) {
	if !p.extension.Manifest.IsMetadataProvider() {
		return nil, fmt.Errorf("extension '%s' is not a metadata provider", p.extension.ID)
	}

	if !p.extension.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", p.extension.ID)
	}
	perf := newExtensionCallPerf(p.extension.ID, "getPlaylist")
	defer perf.finish()
	initStartedAt := time.Now()
	if err := p.lockReadyVM(); err != nil {
		return nil, err
	}
	perf.recordInit(time.Since(initStartedAt))
	defer p.extension.VMMu.Unlock()

	script := fmt.Sprintf(`
		(function() {
			if (typeof extension !== 'undefined' && typeof extension.getPlaylist === 'function') {
				return extension.getPlaylist(%q);
			}
			if (typeof extension !== 'undefined' && typeof extension.getAlbum === 'function') {
				return extension.getAlbum(%q);
			}
			return null;
		})()
	`, playlistID, playlistID)

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutAndRecover(p.vm, script, DefaultJSTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		if IsTimeoutError(err) {
			return nil, fmt.Errorf("getPlaylist timeout: extension took too long to respond")
		}
		return nil, fmt.Errorf("getPlaylist failed: %w", err)
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return nil, fmt.Errorf("getPlaylist returned null")
	}

	parseStartedAt := time.Now()
	playlist, err := parseExtensionAlbumValue(p.vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	if err != nil {
		return nil, fmt.Errorf("failed to parse playlist: %w", err)
	}
	perf.setItems(len(playlist.Tracks))

	playlist.ProviderID = p.extension.ID
	for i := range playlist.Tracks {
		playlist.Tracks[i].ProviderID = p.extension.ID
	}
	return &playlist, nil
}

func (p *extensionProviderWrapper) GetArtist(artistID string) (*ExtArtistMetadata, error) {
	if !p.extension.Manifest.IsMetadataProvider() {
		return nil, fmt.Errorf("extension '%s' is not a metadata provider", p.extension.ID)
	}

	if !p.extension.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", p.extension.ID)
	}
	perf := newExtensionCallPerf(p.extension.ID, "getArtist")
	defer perf.finish()
	initStartedAt := time.Now()
	if err := p.lockReadyVM(); err != nil {
		return nil, err
	}
	perf.recordInit(time.Since(initStartedAt))
	defer p.extension.VMMu.Unlock()

	script := fmt.Sprintf(`
		(function() {
			if (typeof extension !== 'undefined' && typeof extension.getArtist === 'function') {
				return extension.getArtist(%q);
			}
			return null;
		})()
	`, artistID)

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutAndRecover(p.vm, script, DefaultJSTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		if IsTimeoutError(err) {
			return nil, fmt.Errorf("getArtist timeout: extension took too long to respond")
		}
		return nil, fmt.Errorf("getArtist failed: %w", err)
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return nil, fmt.Errorf("getArtist returned null")
	}

	parseStartedAt := time.Now()
	artist, err := parseExtensionArtistValue(p.vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	if err != nil {
		return nil, fmt.Errorf("failed to parse artist: %w", err)
	}
	perf.setItems(len(artist.Albums) + len(artist.Releases) + len(artist.TopTracks))

	artist.ProviderID = p.extension.ID
	for i := range artist.Releases {
		artist.Releases[i].ProviderID = p.extension.ID
		for j := range artist.Releases[i].Tracks {
			artist.Releases[i].Tracks[j].ProviderID = p.extension.ID
		}
	}
	return &artist, nil
}

func (p *extensionProviderWrapper) EnrichTrack(track *ExtTrackMetadata) (*ExtTrackMetadata, error) {
	return p.EnrichTrackForItemID(track, "")
}

func (p *extensionProviderWrapper) EnrichTrackForItemID(track *ExtTrackMetadata, itemID string) (*ExtTrackMetadata, error) {
	if !p.extension.Manifest.IsMetadataProvider() {
		return track, nil
	}

	if !p.extension.Enabled {
		return track, nil
	}
	perf := newExtensionCallPerf(p.extension.ID, "enrichTrack")
	defer perf.finish()
	initStartedAt := time.Now()
	if err := p.lockReadyVM(); err != nil {
		GoLog("[Extension] EnrichTrack init error for %s: %v\n", p.extension.ID, err)
		return track, nil
	}
	perf.recordInit(time.Since(initStartedAt))
	defer p.extension.VMMu.Unlock()
	if itemID != "" {
		if p.extension.runtime != nil {
			p.extension.runtime.setActiveDownloadItemID(itemID)
			defer p.extension.runtime.clearActiveDownloadItemID()
		}
		initDownloadCancel(itemID)
		defer clearDownloadCancel(itemID)
		if isDownloadCancelled(itemID) {
			return track, ErrDownloadCancelled
		}
	}

	trackJSON, err := json.Marshal(track)
	if err != nil {
		GoLog("[Extension] EnrichTrack: failed to marshal track: %v\n", err)
		return track, nil
	}

	script := fmt.Sprintf(`
		(function() {
			if (typeof extension !== 'undefined' && typeof extension.enrichTrack === 'function') {
				var track = %s;
				return extension.enrichTrack(track);
			}
			return null;
		})()
	`, string(trackJSON))

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutAndRecover(p.vm, script, DefaultJSTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		if isDownloadCancelled(itemID) {
			return track, ErrDownloadCancelled
		}
		if IsTimeoutError(err) {
			GoLog("[Extension] EnrichTrack timeout for %s\n", p.extension.ID)
		} else {
			GoLog("[Extension] EnrichTrack error for %s: %v\n", p.extension.ID, err)
		}
		return track, nil
	}
	if isDownloadCancelled(itemID) {
		return track, ErrDownloadCancelled
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return track, nil
	}

	parseStartedAt := time.Now()
	enrichedTrack := parseExtensionTrackValue(p.vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	perf.setItems(1)
	enrichedTrack.ProviderID = track.ProviderID

	return &enrichedTrack, nil
}

func (p *extensionProviderWrapper) CheckAvailability(isrc, trackName, artistName, spotifyID, deezerID, tidalID, qobuzID string) (*ExtAvailabilityResult, error) {
	return p.CheckAvailabilityForItemID(isrc, trackName, artistName, spotifyID, deezerID, tidalID, qobuzID, 0, "")
}

func (p *extensionProviderWrapper) CheckAvailabilityForItemID(isrc, trackName, artistName, spotifyID, deezerID, tidalID, qobuzID string, durationMS int, itemID string) (*ExtAvailabilityResult, error) {
	if !p.extension.Manifest.IsDownloadProvider() {
		return nil, fmt.Errorf("extension '%s' is not a download provider", p.extension.ID)
	}

	if !p.extension.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", p.extension.ID)
	}
	perf := newExtensionCallPerf(p.extension.ID, "checkAvailability")
	defer perf.finish()
	initStartedAt := time.Now()
	if err := p.lockReadyVM(); err != nil {
		return nil, err
	}
	perf.recordInit(time.Since(initStartedAt))
	defer p.extension.VMMu.Unlock()
	if itemID != "" {
		if p.extension.runtime != nil {
			p.extension.runtime.setActiveDownloadItemID(itemID)
			defer p.extension.runtime.clearActiveDownloadItemID()
		}
		initDownloadCancel(itemID)
		defer clearDownloadCancel(itemID)
		if isDownloadCancelled(itemID) {
			return nil, ErrDownloadCancelled
		}
	}

	script := fmt.Sprintf(`
		(function() {
			if (typeof extension !== 'undefined' && typeof extension.checkAvailability === 'function') {
				return extension.checkAvailability(%q, %q, %q, {
					spotify_id: %q,
					deezer_id: %q,
					tidal_id: %q,
					qobuz_id: %q,
					duration_ms: %d
				});
			}
			return null;
		})()
	`, isrc, trackName, artistName, spotifyID, deezerID, tidalID, qobuzID, durationMS)

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutAndRecover(p.vm, script, DefaultJSTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		if isDownloadCancelled(itemID) {
			return nil, ErrDownloadCancelled
		}
		if IsTimeoutError(err) {
			return nil, fmt.Errorf("checkAvailability timeout: extension took too long to respond")
		}
		return nil, fmt.Errorf("checkAvailability failed: %w", err)
	}
	if isDownloadCancelled(itemID) {
		return nil, ErrDownloadCancelled
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return &ExtAvailabilityResult{Available: false, Reason: "not implemented"}, nil
	}

	parseStartedAt := time.Now()
	availability := parseExtensionAvailabilityValue(p.vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	perf.setItems(1)
	return &availability, nil
}

func (p *extensionProviderWrapper) GetDownloadURL(trackID, quality string) (*ExtDownloadURLResult, error) {
	if !p.extension.Manifest.IsDownloadProvider() {
		return nil, fmt.Errorf("extension '%s' is not a download provider", p.extension.ID)
	}

	if !p.extension.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", p.extension.ID)
	}
	perf := newExtensionCallPerf(p.extension.ID, "getDownloadUrl")
	defer perf.finish()
	initStartedAt := time.Now()
	if err := p.lockReadyVM(); err != nil {
		return nil, err
	}
	perf.recordInit(time.Since(initStartedAt))
	defer p.extension.VMMu.Unlock()

	script := fmt.Sprintf(`
		(function() {
			if (typeof extension !== 'undefined' && typeof extension.getDownloadUrl === 'function') {
				return extension.getDownloadUrl(%q, %q);
			}
			return null;
		})()
	`, trackID, quality)

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutAndRecover(p.vm, script, DefaultJSTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		if IsTimeoutError(err) {
			return nil, fmt.Errorf("getDownloadUrl timeout: extension took too long to respond")
		}
		return nil, fmt.Errorf("getDownloadUrl failed: %w", err)
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return nil, fmt.Errorf("getDownloadUrl returned null")
	}

	parseStartedAt := time.Now()
	urlResult := parseExtensionDownloadURLValue(p.vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	perf.setItems(1)
	return &urlResult, nil
}

const ExtDownloadTimeout = DownloadTimeout

func (p *extensionProviderWrapper) Download(trackID, quality, outputPath, itemID string, onProgress func(percent int)) (*ExtDownloadResult, error) {
	if !p.extension.Manifest.IsDownloadProvider() {
		return nil, fmt.Errorf("extension '%s' is not a download provider", p.extension.ID)
	}

	if !p.extension.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", p.extension.ID)
	}
	perf := newExtensionCallPerf(p.extension.ID, "download")
	defer perf.finish()
	initStartedAt := time.Now()
	p.extension.VMMu.Lock()
	vm, runtime, err := newIsolatedExtensionRuntime(p.extension)
	p.extension.VMMu.Unlock()
	perf.recordInit(time.Since(initStartedAt))
	if err != nil {
		return &ExtDownloadResult{
			Success:      false,
			ErrorMessage: err.Error(),
			ErrorType:    "init_error",
		}, nil
	}
	defer func() {
		if cleanupErr := runCleanupOnVM(vm); cleanupErr != nil {
			GoLog("[Extension:%s] isolated download cleanup failed: %v\n", p.extension.ID, cleanupErr)
		}
		if runtime != nil {
			if flushErr := runtime.flushStorageNow(); flushErr != nil {
				GoLog("[Extension:%s] isolated download storage flush failed: %v\n", p.extension.ID, flushErr)
			}
			runtime.closeStorageFlusher()
		}
	}()
	if runtime != nil {
		runtime.setActiveDownloadItemID(itemID)
		defer runtime.clearActiveDownloadItemID()
	}
	if itemID != "" {
		initDownloadCancel(itemID)
		defer clearDownloadCancel(itemID)
		SetItemPreparing(itemID)
	}

	vm.Set("__onProgress", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) > 0 {
			percent := int(call.Arguments[0].ToInteger())
			if percent < 0 {
				percent = 0
			}
			if percent > 100 {
				percent = 100
			}
			if onProgress != nil {
				onProgress(percent)
			}
		}
		return goja.Undefined()
	})

	script := fmt.Sprintf(`
		(function() {
			if (typeof extension !== 'undefined' && typeof extension.download === 'function') {
				return extension.download(%q, %q, %q, __onProgress);
			}
			return null;
		})()
	`, trackID, quality, outputPath)

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutAndRecover(vm, script, ExtDownloadTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		errMsg := err.Error()
		errType := "script_error"
		if IsTimeoutError(err) {
			errMsg = "download timeout: extension took too long to complete"
			errType = "timeout"
		}
		return &ExtDownloadResult{
			Success:      false,
			ErrorMessage: errMsg,
			ErrorType:    errType,
		}, nil
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return &ExtDownloadResult{
			Success:      false,
			ErrorMessage: "download returned null",
			ErrorType:    "not_implemented",
		}, nil
	}

	parseStartedAt := time.Now()
	downloadResult := parseExtensionDownloadResultValue(vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	perf.setItems(1)
	downloadResult.Decryption = normalizeDownloadDecryptionInfo(
		downloadResult.Decryption,
		downloadResult.DecryptionKey,
	)
	downloadResult.DecryptionKey = normalizedDownloadDecryptionKey(
		downloadResult.Decryption,
		downloadResult.DecryptionKey,
	)

	return &downloadResult, nil
}

func (m *extensionManager) GetMetadataProviders() []*extensionProviderWrapper {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var providers []*extensionProviderWrapper
	for _, ext := range m.extensions {
		if ext.Enabled && ext.Manifest.IsMetadataProvider() && ext.Error == "" {
			providers = append(providers, newExtensionProviderWrapper(ext))
		}
	}
	return providers
}

func (m *extensionManager) GetDownloadProviders() []*extensionProviderWrapper {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var providers []*extensionProviderWrapper
	for _, ext := range m.extensions {
		if ext.Enabled && ext.Manifest.IsDownloadProvider() && ext.Error == "" {
			providers = append(providers, newExtensionProviderWrapper(ext))
		}
	}
	return providers
}

func (m *extensionManager) SearchTracksWithExtensions(query string, limit int) ([]ExtTrackMetadata, error) {
	providers := m.GetMetadataProviders()
	if len(providers) == 0 {
		return nil, nil
	}

	providerByID := make(map[string]*extensionProviderWrapper, len(providers))
	orderedProviders := make([]*extensionProviderWrapper, 0, len(providers))
	for _, provider := range providers {
		providerByID[provider.extension.ID] = provider
	}
	for _, providerID := range GetMetadataProviderPriority() {
		if provider := providerByID[providerID]; provider != nil {
			orderedProviders = append(orderedProviders, provider)
			delete(providerByID, providerID)
		}
	}
	if len(providerByID) > 0 {
		remainingIDs := make([]string, 0, len(providerByID))
		for providerID := range providerByID {
			remainingIDs = append(remainingIDs, providerID)
		}
		sort.Strings(remainingIDs)
		for _, providerID := range remainingIDs {
			orderedProviders = append(orderedProviders, providerByID[providerID])
		}
	}

	var allTracks []ExtTrackMetadata
	for _, provider := range orderedProviders {
		result, err := provider.SearchTracks(query, limit)
		if err != nil {
			GoLog("[Extension] Search error from %s: %v\n", provider.extension.ID, err)
			continue
		}
		if result != nil {
			allTracks = append(allTracks, result.Tracks...)
		}
	}

	return allTracks, nil
}

var providerPriority []string
var providerPriorityMu sync.RWMutex

var extensionFallbackProviderIDs []string
var extensionFallbackProviderIDsMu sync.RWMutex

var metadataProviderPriority []string
var metadataProviderPriorityMu sync.RWMutex

func SetProviderPriority(providerIDs []string) {
	providerPriorityMu.Lock()
	defer providerPriorityMu.Unlock()
	providerPriority = sanitizeDownloadProviderPriority(providerIDs)
	GoLog("[Extension] Download provider priority set: %v\n", providerPriority)
}

func GetProviderPriority() []string {
	providerPriorityMu.RLock()
	defer providerPriorityMu.RUnlock()

	if len(providerPriority) == 0 {
		return []string{}
	}

	result := make([]string, len(providerPriority))
	copy(result, providerPriority)
	return result
}

func sanitizeDownloadProviderPriority(providerIDs []string) []string {
	sanitized := make([]string, 0, len(providerIDs))
	seen := map[string]struct{}{}

	for _, providerID := range providerIDs {
		providerID = strings.TrimSpace(providerID)
		if providerID == "" {
			continue
		}

		if isRetiredBuiltInDownloadProvider(providerID) {
			continue
		}

		seenKey := strings.ToLower(providerID)
		if _, exists := seen[seenKey]; exists {
			continue
		}
		seen[seenKey] = struct{}{}
		sanitized = append(sanitized, providerID)
	}

	return sanitized
}

func isRetiredBuiltInDownloadProvider(providerID string) bool {
	normalized := strings.ToLower(strings.TrimSpace(providerID))
	if normalized == "" {
		return false
	}
	switch normalized {
	case "deezer", "qobuz", "tidal":
		return true
	default:
		return false
	}
}

func isRetiredBuiltInMetadataProvider(providerID string) bool {
	normalized := strings.ToLower(strings.TrimSpace(providerID))
	if normalized == "" {
		return false
	}
	switch normalized {
	case "deezer", "spotify", "qobuz", "tidal":
		return true
	default:
		return false
	}
}

func SetExtensionFallbackProviderIDs(providerIDs []string) {
	extensionFallbackProviderIDsMu.Lock()
	defer extensionFallbackProviderIDsMu.Unlock()

	if providerIDs == nil {
		extensionFallbackProviderIDs = nil
		GoLog("[Extension] Extension fallback providers reset to default (all enabled download extensions)\n")
		return
	}

	sanitized := make([]string, 0, len(providerIDs))
	seen := map[string]struct{}{}
	for _, providerID := range providerIDs {
		providerID = strings.TrimSpace(providerID)
		if providerID == "" {
			continue
		}
		if _, exists := seen[providerID]; exists {
			continue
		}
		seen[providerID] = struct{}{}
		sanitized = append(sanitized, providerID)
	}

	extensionFallbackProviderIDs = sanitized
	GoLog("[Extension] Extension fallback providers set: %v\n", sanitized)
}

func GetExtensionFallbackProviderIDs() []string {
	extensionFallbackProviderIDsMu.RLock()
	defer extensionFallbackProviderIDsMu.RUnlock()

	if extensionFallbackProviderIDs == nil {
		return nil
	}

	result := make([]string, len(extensionFallbackProviderIDs))
	copy(result, extensionFallbackProviderIDs)
	return result
}

func isExtensionFallbackAllowed(providerID string) bool {
	allowed := GetExtensionFallbackProviderIDs()
	if allowed == nil {
		return true
	}

	for _, allowedProviderID := range allowed {
		if allowedProviderID == providerID {
			return true
		}
	}
	return false
}

func SetMetadataProviderPriority(providerIDs []string) {
	metadataProviderPriorityMu.Lock()
	defer metadataProviderPriorityMu.Unlock()

	sanitized := make([]string, 0, len(providerIDs))
	seen := map[string]struct{}{}
	for _, providerID := range providerIDs {
		providerID = strings.TrimSpace(providerID)
		if providerID == "" || isRetiredBuiltInMetadataProvider(providerID) {
			continue
		}
		if _, exists := seen[providerID]; exists {
			continue
		}
		seen[providerID] = struct{}{}
		sanitized = append(sanitized, providerID)
	}
	metadataProviderPriority = sanitized
	GoLog("[Extension] Metadata provider priority set: %v\n", sanitized)
}

func GetMetadataProviderPriority() []string {
	metadataProviderPriorityMu.RLock()
	defer metadataProviderPriorityMu.RUnlock()

	if len(metadataProviderPriority) == 0 {
		return []string{}
	}

	result := make([]string, len(metadataProviderPriority))
	copy(result, metadataProviderPriority)
	return result
}

func metadataTrackDedupKey(track ExtTrackMetadata) string {
	if isrc := strings.TrimSpace(track.ISRC); isrc != "" {
		return "isrc:" + strings.ToUpper(isrc)
	}
	if spotifyID := strings.TrimSpace(track.SpotifyID); spotifyID != "" {
		return "spotify:" + spotifyID
	}
	if providerID := strings.TrimSpace(track.ProviderID); providerID != "" && strings.TrimSpace(track.ID) != "" {
		return providerID + ":" + strings.TrimSpace(track.ID)
	}
	return strings.TrimSpace(track.Name) + "|" + strings.TrimSpace(track.Artists)
}

func (m *extensionManager) SearchTracksWithMetadataProviders(query string, limit int, includeExtensions bool) ([]ExtTrackMetadata, error) {
	return m.SearchTracksWithMetadataProvidersForItemID(query, limit, includeExtensions, "")
}

func (m *extensionManager) SearchTracksWithMetadataProvidersForItemID(query string, limit int, includeExtensions bool, itemID string) ([]ExtTrackMetadata, error) {
	priority := GetMetadataProviderPriority()
	if limit <= 0 {
		limit = 20
	}

	extensionProviders := make(map[string]*extensionProviderWrapper)
	if includeExtensions {
		for _, provider := range m.GetMetadataProviders() {
			extensionProviders[provider.extension.ID] = provider
		}
	}

	orderedProviderIDs := make([]string, 0, len(priority)+len(extensionProviders))
	seenProviderIDs := make(map[string]struct{}, len(priority)+len(extensionProviders))
	for _, providerID := range priority {
		providerID = strings.TrimSpace(providerID)
		if providerID == "" {
			continue
		}
		orderedProviderIDs = append(orderedProviderIDs, providerID)
		seenProviderIDs[providerID] = struct{}{}
	}
	if includeExtensions {
		remainingIDs := make([]string, 0, len(extensionProviders))
		for providerID := range extensionProviders {
			if _, exists := seenProviderIDs[providerID]; exists {
				continue
			}
			remainingIDs = append(remainingIDs, providerID)
		}
		sort.Strings(remainingIDs)
		orderedProviderIDs = append(orderedProviderIDs, remainingIDs...)
	}

	tracks := make([]ExtTrackMetadata, 0, limit)
	seenTracks := make(map[string]struct{})
	for _, providerID := range orderedProviderIDs {
		if isDownloadCancelled(itemID) {
			return nil, ErrDownloadCancelled
		}

		if !includeExtensions {
			continue
		}
		provider := extensionProviders[providerID]
		if provider == nil {
			continue
		}
		result, err := provider.SearchTracksForItemID(query, limit, itemID)
		providerTracks := []ExtTrackMetadata(nil)
		if result != nil {
			providerTracks = result.Tracks
		}

		if err != nil {
			if errors.Is(err, ErrDownloadCancelled) {
				return nil, ErrDownloadCancelled
			}
			GoLog("[MetadataSearch] Search error from %s: %v\n", providerID, err)
			continue
		}

		for _, track := range providerTracks {
			key := metadataTrackDedupKey(track)
			if key == "" {
				continue
			}
			if _, exists := seenTracks[key]; exists {
				continue
			}
			seenTracks[key] = struct{}{}
			tracks = append(tracks, track)
			if len(tracks) >= limit {
				return tracks, nil
			}
		}
	}

	return tracks, nil
}

func DownloadWithExtensionFallback(req DownloadRequest) (*DownloadResponse, error) {
	priority := GetProviderPriority()
	extManager := getExtensionManager()
	strictMode := !req.UseFallback
	selectedProvider := strings.TrimSpace(req.Service)

	if isDownloadCancelled(req.ItemID) {
		return nil, ErrDownloadCancelled
	}

	if strictMode {
		if selectedProvider == "" {
			selectedProvider = strings.TrimSpace(req.Source)
		}
		if selectedProvider != "" {
			priority = []string{selectedProvider}
			GoLog("[DownloadWithExtensionFallback] Strict mode enabled, provider locked to: %s\n", selectedProvider)
		}
	}

	if !strictMode && req.Service != "" {
		found := false
		for _, p := range priority {
			if strings.EqualFold(p, req.Service) {
				found = true
				break
			}
		}
		newPriority := []string{req.Service}
		for _, p := range priority {
			if !strings.EqualFold(p, req.Service) {
				newPriority = append(newPriority, p)
			}
		}
		priority = newPriority
		if !found {
			GoLog("[DownloadWithExtensionFallback] Extension service '%s' added to priority front\n", req.Service)
		} else {
			GoLog("[DownloadWithExtensionFallback] Extension service '%s' moved to priority front\n", req.Service)
		}
		GoLog("[DownloadWithExtensionFallback] New priority order: %v\n", priority)
	}

	var lastErr error
	var stopProviderFallback bool
	var sourceExtensionLocked bool
	var sourceExtensionAvailability *ExtAvailabilityResult
	var sourceExtensionTrackID string

	if req.Source != "" && selectedProvider != req.Source {
		ext, err := extManager.GetExtension(req.Source)
		if err == nil && ext.Enabled && ext.Error == "" && ext.Manifest.IsDownloadProvider() {
			provider := newExtensionProviderWrapper(ext)
			availability, availErr := provider.CheckAvailabilityForItemID(req.ISRC, req.TrackName, req.ArtistName, req.SpotifyID, req.DeezerID, req.TidalID, req.QobuzID, req.DurationMS, req.ItemID)
			if shouldAbortCancelledFallback(req.ItemID, availErr) {
				return nil, ErrDownloadCancelled
			}
			if availErr != nil {
				GoLog("[DownloadWithExtensionFallback] Source extension %s preflight failed (non-fatal): %v\n", req.Source, availErr)
			} else if shouldStopProviderFallback(availability) {
				sourceExtensionLocked = true
				sourceExtensionAvailability = availability
				sourceExtensionTrackID = strings.TrimSpace(availability.TrackID)
				selectedProvider = req.Source
				GoLog("[DownloadWithExtensionFallback] Source extension %s requested skip_fallback (available=%v), locking download to source extension\n", req.Source, availability.Available)
			}
		}
	}

	if req.Source != "" {
		ext, err := extManager.GetExtension(req.Source)
		if err == nil && ext.Enabled && ext.Error == "" && ext.Manifest.IsMetadataProvider() {
			GoLog("[DownloadWithExtensionFallback] Enriching track from extension '%s'...\n", req.Source)

			provider := newExtensionProviderWrapper(ext)
			trackMeta := &ExtTrackMetadata{
				ID:          req.SpotifyID,
				Name:        req.TrackName,
				Artists:     req.ArtistName,
				AlbumName:   req.AlbumName,
				DurationMS:  req.DurationMS,
				ISRC:        req.ISRC,
				ReleaseDate: req.ReleaseDate,
				TrackNumber: req.TrackNumber,
				TotalTracks: req.TotalTracks,
				DiscNumber:  req.DiscNumber,
				TotalDiscs:  req.TotalDiscs,
				ProviderID:  req.Source,
				Composer:    req.Composer,
			}

			enrichedTrack, err := provider.EnrichTrackForItemID(trackMeta, req.ItemID)
			if shouldAbortCancelledFallback(req.ItemID, err) {
				return nil, ErrDownloadCancelled
			}
			if err == nil && enrichedTrack != nil {
				if enrichedTrack.ISRC != "" && enrichedTrack.ISRC != req.ISRC {
					GoLog("[DownloadWithExtensionFallback] ISRC enriched: %s -> %s\n", req.ISRC, enrichedTrack.ISRC)
					req.ISRC = enrichedTrack.ISRC
				}
				if enrichedTrack.TidalID != "" {
					GoLog("[DownloadWithExtensionFallback] Tidal ID from Odesli: %s\n", enrichedTrack.TidalID)
					req.TidalID = enrichedTrack.TidalID
				}
				if enrichedTrack.QobuzID != "" {
					GoLog("[DownloadWithExtensionFallback] Qobuz ID from Odesli: %s\n", enrichedTrack.QobuzID)
					req.QobuzID = enrichedTrack.QobuzID
				}
				if enrichedTrack.DeezerID != "" {
					GoLog("[DownloadWithExtensionFallback] Deezer ID from Odesli: %s\n", enrichedTrack.DeezerID)
					req.DeezerID = enrichedTrack.DeezerID
				}
				if enrichedTrack.Name != "" {
					req.TrackName = enrichedTrack.Name
				}
				if enrichedTrack.Artists != "" {
					req.ArtistName = enrichedTrack.Artists
				}
				if enrichedTrack.AlbumName != "" && req.AlbumName == "" {
					GoLog("[DownloadWithExtensionFallback] AlbumName from enrichment: %s\n", enrichedTrack.AlbumName)
					req.AlbumName = enrichedTrack.AlbumName
				}
				if enrichedTrack.AlbumArtist != "" && req.AlbumArtist == "" {
					req.AlbumArtist = enrichedTrack.AlbumArtist
				}
				if enrichedTrack.DurationMS > 0 && req.DurationMS == 0 {
					GoLog("[DownloadWithExtensionFallback] DurationMS from enrichment: %d\n", enrichedTrack.DurationMS)
					req.DurationMS = enrichedTrack.DurationMS
				}
				if enrichedTrack.CoverURL != "" && req.CoverURL == "" {
					req.CoverURL = enrichedTrack.CoverURL
				}
				if enrichedTrack.ID != "" && req.SpotifyID == "" {
					GoLog("[DownloadWithExtensionFallback] Track ID from enrichment: %s\n", enrichedTrack.ID)
					req.SpotifyID = enrichedTrack.ID
				}
				if enrichedTrack.Label != "" && req.Label == "" {
					GoLog("[DownloadWithExtensionFallback] Label from enrichment: %s\n", enrichedTrack.Label)
					req.Label = enrichedTrack.Label
				}
				if enrichedTrack.Copyright != "" && req.Copyright == "" {
					GoLog("[DownloadWithExtensionFallback] Copyright from enrichment: %s\n", enrichedTrack.Copyright)
					req.Copyright = enrichedTrack.Copyright
				}
				if enrichedTrack.Genre != "" && req.Genre == "" {
					GoLog("[DownloadWithExtensionFallback] Genre from enrichment: %s\n", enrichedTrack.Genre)
					req.Genre = enrichedTrack.Genre
				}
				if enrichedTrack.ReleaseDate != "" && req.ReleaseDate == "" {
					GoLog("[DownloadWithExtensionFallback] ReleaseDate from enrichment: %s\n", enrichedTrack.ReleaseDate)
					req.ReleaseDate = enrichedTrack.ReleaseDate
				}
				if enrichedTrack.TrackNumber > 0 && req.TrackNumber == 0 {
					GoLog("[DownloadWithExtensionFallback] TrackNumber from enrichment: %d\n", enrichedTrack.TrackNumber)
					req.TrackNumber = enrichedTrack.TrackNumber
				}
				if enrichedTrack.TotalTracks > 0 && req.TotalTracks == 0 {
					GoLog("[DownloadWithExtensionFallback] TotalTracks from enrichment: %d\n", enrichedTrack.TotalTracks)
					req.TotalTracks = enrichedTrack.TotalTracks
				}
				if enrichedTrack.DiscNumber > 0 && req.DiscNumber == 0 {
					GoLog("[DownloadWithExtensionFallback] DiscNumber from enrichment: %d\n", enrichedTrack.DiscNumber)
					req.DiscNumber = enrichedTrack.DiscNumber
				}
				if enrichedTrack.TotalDiscs > 0 && req.TotalDiscs == 0 {
					GoLog("[DownloadWithExtensionFallback] TotalDiscs from enrichment: %d\n", enrichedTrack.TotalDiscs)
					req.TotalDiscs = enrichedTrack.TotalDiscs
				}
				if enrichedTrack.Composer != "" && req.Composer == "" {
					GoLog("[DownloadWithExtensionFallback] Composer from enrichment: %s\n", enrichedTrack.Composer)
					req.Composer = enrichedTrack.Composer
				}
			}
		}
	}

	if req.Source != "" &&
		req.TrackName != "" && req.ArtistName != "" &&
		(req.AlbumName == "" || req.ReleaseDate == "" || req.ISRC == "") {

		searchQuery := req.TrackName + " " + req.ArtistName
		GoLog("[DownloadWithExtensionFallback] Metadata incomplete, searching providers for: %s\n", searchQuery)

		tracks, searchErr := extManager.SearchTracksWithMetadataProvidersForItemID(searchQuery, 5, true, req.ItemID)
		if shouldAbortCancelledFallback(req.ItemID, searchErr) {
			return nil, ErrDownloadCancelled
		}
		if searchErr == nil && len(tracks) > 0 {
			track := tracks[0]
			GoLog("[DownloadWithExtensionFallback] Metadata match (%s): %s - %s (album: %s, date: %s, isrc: %s)\n",
				track.ProviderID, track.Name, track.Artists, track.AlbumName, track.ReleaseDate, track.ISRC)

			if track.AlbumName != "" && req.AlbumName == "" {
				req.AlbumName = track.AlbumName
			}
			if track.AlbumArtist != "" && req.AlbumArtist == "" {
				req.AlbumArtist = track.AlbumArtist
			}
			if track.ReleaseDate != "" && req.ReleaseDate == "" {
				req.ReleaseDate = track.ReleaseDate
			}
			if track.ISRC != "" && req.ISRC == "" {
				req.ISRC = track.ISRC
			}
			if track.TrackNumber > 0 && req.TrackNumber == 0 {
				req.TrackNumber = track.TrackNumber
			}
			if track.TotalTracks > 0 && req.TotalTracks == 0 {
				req.TotalTracks = track.TotalTracks
			}
			if track.DiscNumber > 0 && req.DiscNumber == 0 {
				req.DiscNumber = track.DiscNumber
			}
			if track.TotalDiscs > 0 && req.TotalDiscs == 0 {
				req.TotalDiscs = track.TotalDiscs
			}
			if track.Composer != "" && req.Composer == "" {
				req.Composer = track.Composer
			}
			if track.CoverURL != "" && req.CoverURL == "" {
				req.CoverURL = track.CoverURL
			}
			if track.Genre != "" && req.Genre == "" {
				req.Genre = track.Genre
			}
			if track.Label != "" && req.Label == "" {
				req.Label = track.Label
			}
			if track.Copyright != "" && req.Copyright == "" {
				req.Copyright = track.Copyright
			}
		} else if searchErr != nil {
			GoLog("[DownloadWithExtensionFallback] Metadata provider search failed (non-fatal): %v\n", searchErr)
		}

		if req.ISRC != "" &&
			(req.Genre == "" || req.Label == "" || req.Copyright == "") {
			enrichExtraMetadataByISRC("DownloadWithExtensionFallback", req.ISRC, &req.Genre, &req.Label, &req.Copyright)
			if isDownloadCancelled(req.ItemID) {
				return nil, ErrDownloadCancelled
			}
		}
	}

	if req.Source != "" && selectedProvider == req.Source {
		if isDownloadCancelled(req.ItemID) {
			return nil, ErrDownloadCancelled
		}

		if sourceExtensionLocked && (sourceExtensionAvailability == nil || !sourceExtensionAvailability.Available) {
			GoLog("[DownloadWithExtensionFallback] Source extension %s stopped fallback before download (reason: %s)\n", req.Source, resolveExtensionAvailabilityReason(sourceExtensionAvailability, nil))
			return buildExtensionFallbackStoppedResponse(req.Source, sourceExtensionAvailability, nil), nil
		}

		GoLog("[DownloadWithExtensionFallback] Track source is extension '%s' matching selected provider, trying it first\n", req.Source)

		ext, err := extManager.GetExtension(req.Source)
		if err == nil && ext.Enabled && ext.Error == "" && ext.Manifest.IsDownloadProvider() {
			stopProviderFallback = ext.Manifest.StopsProviderFallback()

			provider := newExtensionProviderWrapper(ext)

			trackID := resolvePreferredTrackIDForExtension(ext, req, sourceExtensionTrackID)

			GoLog("[DownloadWithExtensionFallback] Downloading from source extension with trackID: %s (stopProviderFallback: %v)\n", trackID, stopProviderFallback)

			outputPath := buildOutputPathForExtension(req, ext)
			if req.ItemID != "" {
				StartItemProgress(req.ItemID)
			}

			result, err := provider.Download(trackID, req.Quality, outputPath, req.ItemID, func(percent int) {
				if req.ItemID != "" {
					normalized := float64(percent) / 100.0
					if normalized < 0 {
						normalized = 0
					}
					if normalized > 1 {
						normalized = 1
					}
					SetItemProgress(req.ItemID, normalized, 0, 0)
				}
			})
			if req.ItemID != "" {
				if err == nil && result != nil && result.Success {
					CompleteItemProgress(req.ItemID)
				} else {
					RemoveItemProgress(req.ItemID)
				}
			}
			if shouldAbortCancelledFallback(req.ItemID, err) {
				return nil, ErrDownloadCancelled
			}

			if err == nil && result.Success {
				normalizedResult, alreadyExists := normalizeExtensionDownloadResult(result)
				message := "Downloaded from " + req.Source
				if alreadyExists {
					message = "File already exists"
				}

				resp := buildDownloadSuccessResponse(
					req,
					normalizedResult,
					req.Source,
					message,
					normalizedResult.FilePath,
					alreadyExists,
				)
				overlayExtensionDownloadMetadata(&resp, result)
				if ext.Manifest.SkipMetadataEnrichment {
					resp.SkipMetadataEnrichment = true
				}
				applyExtensionRequestFallbacks(&resp, req)

				if req.TrackName != "" && resp.Title == "" {
					resp.Title = req.TrackName
				}
				if req.ArtistName != "" && resp.Artist == "" {
					resp.Artist = req.ArtistName
				}
				if req.Composer != "" && resp.Composer == "" {
					resp.Composer = req.Composer
				}

				if !alreadyExists && req.EmbedMetadata && (req.Genre != "" || req.Label != "") && canEmbedGenreLabel(normalizedResult.FilePath) {
					if err := EmbedGenreLabel(normalizedResult.FilePath, req.Genre, req.Label); err != nil {
						GoLog("[DownloadWithExtensionFallback] Warning: failed to embed genre/label: %v\n", err)
					} else {
						GoLog("[DownloadWithExtensionFallback] Embedded genre=%q label=%q\n", req.Genre, req.Label)
					}
				} else if !alreadyExists && req.EmbedMetadata && (req.Genre != "" || req.Label != "") {
					GoLog("[DownloadWithExtensionFallback] Skipping genre/label embed for non-local output path: %q\n", normalizedResult.FilePath)
				}

				if !alreadyExists && !isFDOutput(req.OutputFD) && strings.TrimSpace(req.OutputDir) != "" {
					indexISRC := strings.TrimSpace(resp.ISRC)
					if indexISRC == "" {
						indexISRC = strings.TrimSpace(req.ISRC)
					}
					if indexISRC != "" && strings.TrimSpace(resp.FilePath) != "" {
						AddToISRCIndex(req.OutputDir, indexISRC, resp.FilePath)
					}
				}

				return &resp, nil
			}

			if err != nil {
				if errors.Is(err, ErrDownloadCancelled) {
					return &DownloadResponse{
						Success:   false,
						Error:     "Download cancelled",
						ErrorType: "cancelled",
						Service:   req.Source,
					}, nil
				}
				lastErr = err
			} else if result.ErrorMessage != "" {
				lastErr = fmt.Errorf("%s", result.ErrorMessage)
			}
			GoLog("[DownloadWithExtensionFallback] Source extension %s failed: %v\n", req.Source, lastErr)

			if stopProviderFallback || sourceExtensionLocked {
				if sourceExtensionLocked {
					GoLog("[DownloadWithExtensionFallback] Source extension %s requested skip_fallback, not trying other providers\n", req.Source)
					return buildExtensionFallbackStoppedResponse(req.Source, sourceExtensionAvailability, lastErr), nil
				}
				GoLog("[DownloadWithExtensionFallback] stopProviderFallback is true, not trying other providers\n")
				return &DownloadResponse{
					Success:   false,
					Error:     "Download failed: " + lastErr.Error(),
					ErrorType: "extension_error",
					Service:   req.Source,
				}, nil
			}
		} else {
			GoLog("[DownloadWithExtensionFallback] Source extension %s not available or not a download provider\n", req.Source)
		}
	}

	for _, providerID := range priority {
		if isDownloadCancelled(req.ItemID) {
			return nil, ErrDownloadCancelled
		}

		providerID = strings.TrimSpace(providerID)
		if providerID == "" {
			continue
		}
		if providerID == req.Source {
			continue
		}

		if !isExtensionFallbackAllowed(providerID) {
			GoLog("[DownloadWithExtensionFallback] Skipping extension provider %s (not enabled for fallback)\n", providerID)
			continue
		}

		GoLog("[DownloadWithExtensionFallback] Trying provider: %s\n", providerID)

		{
			ext, err := extManager.GetExtension(providerID)
			if err != nil || !ext.Enabled || ext.Error != "" {
				GoLog("[DownloadWithExtensionFallback] Extension %s not available\n", providerID)
				continue
			}

			if !ext.Manifest.IsDownloadProvider() {
				continue
			}

			provider := newExtensionProviderWrapper(ext)

			availability, err := provider.CheckAvailabilityForItemID(req.ISRC, req.TrackName, req.ArtistName, req.SpotifyID, req.DeezerID, req.TidalID, req.QobuzID, req.DurationMS, req.ItemID)
			if shouldAbortCancelledFallback(req.ItemID, err) {
				return nil, ErrDownloadCancelled
			}
			terminalAvailability := shouldStopProviderFallback(availability)
			if err != nil || !availability.Available {
				GoLog("[DownloadWithExtensionFallback] %s: not available\n", providerID)
				if err != nil {
					lastErr = err
				}
				if terminalAvailability {
					GoLog("[DownloadWithExtensionFallback] %s requested skip_fallback after availability check\n", providerID)
					return buildExtensionFallbackStoppedResponse(providerID, availability, err), nil
				}
				continue
			}

			req.OutputExt = ""
			outputPath := buildOutputPathForExtension(req, ext)
			if req.ItemID != "" {
				StartItemProgress(req.ItemID)
			}

			result, err := provider.Download(availability.TrackID, req.Quality, outputPath, req.ItemID, func(percent int) {
				if req.ItemID != "" {
					normalized := float64(percent) / 100.0
					if normalized < 0 {
						normalized = 0
					}
					if normalized > 1 {
						normalized = 1
					}
					SetItemProgress(req.ItemID, normalized, 0, 0)
				}
			})
			if req.ItemID != "" {
				if err == nil && result != nil && result.Success {
					CompleteItemProgress(req.ItemID)
				} else {
					RemoveItemProgress(req.ItemID)
				}
			}
			if shouldAbortCancelledFallback(req.ItemID, err) {
				return nil, ErrDownloadCancelled
			}

			if err == nil && result.Success {
				normalizedResult, alreadyExists := normalizeExtensionDownloadResult(result)
				message := "Downloaded from " + providerID
				if alreadyExists {
					message = "File already exists"
				}

				resp := buildDownloadSuccessResponse(
					req,
					normalizedResult,
					providerID,
					message,
					normalizedResult.FilePath,
					alreadyExists,
				)
				overlayExtensionDownloadMetadata(&resp, result)
				if ext.Manifest.SkipMetadataEnrichment {
					resp.SkipMetadataEnrichment = true
				}
				applyExtensionRequestFallbacks(&resp, req)

				if !alreadyExists && req.EmbedMetadata && (req.Genre != "" || req.Label != "") && canEmbedGenreLabel(normalizedResult.FilePath) {
					if err := EmbedGenreLabel(normalizedResult.FilePath, req.Genre, req.Label); err != nil {
						GoLog("[DownloadWithExtensionFallback] Warning: failed to embed genre/label: %v\n", err)
					} else {
						GoLog("[DownloadWithExtensionFallback] Embedded genre=%q label=%q\n", req.Genre, req.Label)
					}
				} else if !alreadyExists && req.EmbedMetadata && (req.Genre != "" || req.Label != "") {
					GoLog("[DownloadWithExtensionFallback] Skipping genre/label embed for non-local output path: %q\n", normalizedResult.FilePath)
				}

				if !alreadyExists && !isFDOutput(req.OutputFD) && strings.TrimSpace(req.OutputDir) != "" {
					indexISRC := strings.TrimSpace(resp.ISRC)
					if indexISRC == "" {
						indexISRC = strings.TrimSpace(req.ISRC)
					}
					if indexISRC != "" && strings.TrimSpace(resp.FilePath) != "" {
						AddToISRCIndex(req.OutputDir, indexISRC, resp.FilePath)
					}
				}

				return &resp, nil
			}

			if err != nil {
				if errors.Is(err, ErrDownloadCancelled) {
					return &DownloadResponse{
						Success:   false,
						Error:     "Download cancelled",
						ErrorType: "cancelled",
						Service:   providerID,
					}, nil
				}
				lastErr = err
			} else if result.ErrorMessage != "" {
				lastErr = fmt.Errorf("%s", result.ErrorMessage)
			}
			GoLog("[DownloadWithExtensionFallback] %s failed: %v\n", providerID, lastErr)
			if terminalAvailability {
				GoLog("[DownloadWithExtensionFallback] %s requested skip_fallback after download failure\n", providerID)
				return buildExtensionFallbackStoppedResponse(providerID, availability, lastErr), nil
			}
		}
	}

	if lastErr != nil {
		return &DownloadResponse{
			Success:   false,
			Error:     "All providers failed. Last error: " + lastErr.Error(),
			ErrorType: "not_found",
		}, nil
	}

	return &DownloadResponse{
		Success:   false,
		Error:     "No extension download providers available",
		ErrorType: "not_found",
	}, nil
}

func buildOutputPath(req DownloadRequest) string {
	if strings.TrimSpace(req.OutputPath) != "" {
		return strings.TrimSpace(req.OutputPath)
	}

	metadata := map[string]interface{}{
		"title":        req.TrackName,
		"artist":       req.ArtistName,
		"album":        req.AlbumName,
		"album_artist": req.AlbumArtist,
		"track":        req.TrackNumber,
		"track_number": req.TrackNumber,
		"total_tracks": req.TotalTracks,
		"disc":         req.DiscNumber,
		"disc_number":  req.DiscNumber,
		"total_discs":  req.TotalDiscs,
		"year":         extractYear(req.ReleaseDate),
		"date":         req.ReleaseDate,
		"release_date": req.ReleaseDate,
		"isrc":         req.ISRC,
		"composer":     req.Composer,
	}

	filename := buildFilenameFromTemplate(req.FilenameFormat, metadata)
	if filename == "" {
		filename = sanitizeFilename(fmt.Sprintf("%s - %s", req.ArtistName, req.TrackName))
	}

	ext := strings.TrimSpace(req.OutputExt)
	if ext == "" {
		ext = ".flac"
	} else if !strings.HasPrefix(ext, ".") {
		ext = "." + ext
	}

	outputDir := req.OutputDir
	if strings.TrimSpace(outputDir) == "" {
		outputDir = filepath.Join(os.TempDir(), "spotiflac-downloads")
	}
	os.MkdirAll(outputDir, 0755)
	AddAllowedDownloadDir(outputDir)

	return filepath.Join(outputDir, filename+ext)
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

	metadata := map[string]interface{}{
		"title":        req.TrackName,
		"artist":       req.ArtistName,
		"album":        req.AlbumName,
		"album_artist": req.AlbumArtist,
		"track":        req.TrackNumber,
		"track_number": req.TrackNumber,
		"total_tracks": req.TotalTracks,
		"disc":         req.DiscNumber,
		"disc_number":  req.DiscNumber,
		"total_discs":  req.TotalDiscs,
		"year":         extractYear(req.ReleaseDate),
		"date":         req.ReleaseDate,
		"release_date": req.ReleaseDate,
		"isrc":         req.ISRC,
		"composer":     req.Composer,
	}

	filename := buildFilenameFromTemplate(req.FilenameFormat, metadata)
	if filename == "" {
		filename = sanitizeFilename(fmt.Sprintf("%s - %s", req.ArtistName, req.TrackName))
	}

	outputExt := strings.TrimSpace(req.OutputExt)
	if outputExt == "" {
		outputExt = ".flac"
	} else if !strings.HasPrefix(outputExt, ".") {
		outputExt = "." + outputExt
	}

	return filepath.Join(tempDir, filename+outputExt)
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

func (p *extensionProviderWrapper) CustomSearch(query string, options map[string]interface{}) ([]ExtTrackMetadata, error) {
	return p.customSearch(query, options, "", "")
}

func (p *extensionProviderWrapper) CustomSearchForRequestID(query string, options map[string]interface{}, requestID string) ([]ExtTrackMetadata, error) {
	return p.customSearch(query, options, "", requestID)
}

func (p *extensionProviderWrapper) CustomSearchForItemID(query string, options map[string]interface{}, itemID string) ([]ExtTrackMetadata, error) {
	return p.customSearch(query, options, itemID, "")
}

func (p *extensionProviderWrapper) customSearch(query string, options map[string]interface{}, itemID, requestID string) ([]ExtTrackMetadata, error) {
	if !p.extension.Manifest.HasCustomSearch() {
		return nil, fmt.Errorf("extension '%s' does not support custom search", p.extension.ID)
	}

	if !p.extension.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", p.extension.ID)
	}
	perf := newExtensionCallPerf(p.extension.ID, "customSearch")
	defer perf.finish()
	initStartedAt := time.Now()
	if err := p.lockReadyVM(); err != nil {
		return nil, err
	}
	perf.recordInit(time.Since(initStartedAt))
	defer p.extension.VMMu.Unlock()
	if itemID != "" {
		if p.extension.runtime != nil {
			p.extension.runtime.setActiveDownloadItemID(itemID)
			defer p.extension.runtime.clearActiveDownloadItemID()
		}
		initDownloadCancel(itemID)
		defer clearDownloadCancel(itemID)
		if isDownloadCancelled(itemID) {
			return nil, ErrDownloadCancelled
		}
	}
	requestCtx := context.Background()
	if requestID != "" {
		if p.extension.runtime != nil {
			p.extension.runtime.setActiveRequestID(requestID)
			defer p.extension.runtime.clearActiveRequestID()
		}
		requestCtx = initExtensionRequestCancel(requestID)
		defer clearExtensionRequestCancel(requestID)
		if isExtensionRequestCancelled(requestID) {
			return nil, ErrExtensionRequestCancelled
		}
	}

	if options == nil {
		options = map[string]interface{}{}
	}

	// Avoid embedding user input directly into JS source. Some inputs can trigger
	// parser/runtime edge cases on specific devices/Goja builds.
	const queryVar = "__sf_custom_search_query"
	const optionsVar = "__sf_custom_search_options"
	global := p.vm.GlobalObject()
	_ = global.Set(queryVar, query)
	_ = global.Set(optionsVar, options)
	defer func() {
		global.Delete(queryVar)
		global.Delete(optionsVar)
	}()

	const script = `
		(function() {
			if (typeof extension !== 'undefined' && typeof extension.customSearch === 'function') {
				return extension.customSearch(__sf_custom_search_query, __sf_custom_search_options);
			}
			return null;
		})()
	`

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutContextAndRecover(requestCtx, p.vm, script, DefaultJSTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		if isExtensionRequestCancelled(requestID) {
			return nil, ErrExtensionRequestCancelled
		}
		if isDownloadCancelled(itemID) {
			return nil, ErrDownloadCancelled
		}
		if errors.Is(err, ErrExtensionRequestCancelled) {
			return nil, ErrExtensionRequestCancelled
		}
		if IsTimeoutError(err) {
			return nil, fmt.Errorf("customSearch timeout: extension took too long to respond")
		}
		return nil, fmt.Errorf("customSearch failed: %w", err)
	}
	if isDownloadCancelled(itemID) {
		return nil, ErrDownloadCancelled
	}
	if isExtensionRequestCancelled(requestID) {
		return nil, ErrExtensionRequestCancelled
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return []ExtTrackMetadata{}, nil
	}

	parseStartedAt := time.Now()
	tracks, err := parseExtensionTrackArray(p.vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	if err != nil {
		return nil, fmt.Errorf("failed to parse search result: %w", err)
	}
	perf.setItems(len(tracks))

	for i := range tracks {
		tracks[i].ProviderID = p.extension.ID
	}

	return tracks, nil
}

type ExtURLHandleResult struct {
	Type     string             `json:"type"`
	Track    *ExtTrackMetadata  `json:"track,omitempty"`
	Tracks   []ExtTrackMetadata `json:"tracks,omitempty"`
	Album    *ExtAlbumMetadata  `json:"album,omitempty"`
	Artist   *ExtArtistMetadata `json:"artist,omitempty"`
	Name     string             `json:"name,omitempty"`
	CoverURL string             `json:"cover_url,omitempty"`
}

func (p *extensionProviderWrapper) HandleURL(url string) (*ExtURLHandleResult, error) {
	if !p.extension.Manifest.HasURLHandler() {
		return nil, fmt.Errorf("extension '%s' does not support URL handling", p.extension.ID)
	}

	if !p.extension.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", p.extension.ID)
	}
	perf := newExtensionCallPerf(p.extension.ID, "handleUrl")
	defer perf.finish()
	initStartedAt := time.Now()
	if err := p.lockReadyVM(); err != nil {
		return nil, err
	}
	perf.recordInit(time.Since(initStartedAt))
	defer p.extension.VMMu.Unlock()

	script := fmt.Sprintf(`
		(function() {
			if (typeof extension !== 'undefined' && typeof extension.handleUrl === 'function') {
				return extension.handleUrl(%q);
			}
			return null;
		})()
	`, url)

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutAndRecover(p.vm, script, DefaultJSTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		if IsTimeoutError(err) {
			return nil, fmt.Errorf("handleUrl timeout: extension took too long to respond")
		}
		return nil, fmt.Errorf("handleUrl failed: %w", err)
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return nil, fmt.Errorf("handleUrl returned null - URL not recognized")
	}

	parseStartedAt := time.Now()
	handleResult, err := parseExtensionURLHandleValue(p.vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	if err != nil {
		return nil, fmt.Errorf("failed to parse URL handle result: %w", err)
	}
	urlItems := len(handleResult.Tracks)
	if handleResult.Track != nil {
		urlItems++
	}
	if handleResult.Album != nil {
		urlItems += 1 + len(handleResult.Album.Tracks)
	}
	if handleResult.Artist != nil {
		urlItems += 1 + len(handleResult.Artist.Albums) + len(handleResult.Artist.Releases) + len(handleResult.Artist.TopTracks)
	}
	perf.setItems(urlItems)

	if handleResult.Track != nil {
		handleResult.Track.ProviderID = p.extension.ID
	}
	for i := range handleResult.Tracks {
		handleResult.Tracks[i].ProviderID = p.extension.ID
	}
	if handleResult.Album != nil {
		handleResult.Album.ProviderID = p.extension.ID
		for i := range handleResult.Album.Tracks {
			handleResult.Album.Tracks[i].ProviderID = p.extension.ID
		}
	}
	if handleResult.Artist != nil {
		handleResult.Artist.ProviderID = p.extension.ID
		for i := range handleResult.Artist.Albums {
			handleResult.Artist.Albums[i].ProviderID = p.extension.ID
			for j := range handleResult.Artist.Albums[i].Tracks {
				handleResult.Artist.Albums[i].Tracks[j].ProviderID = p.extension.ID
			}
		}
		for i := range handleResult.Artist.Releases {
			handleResult.Artist.Releases[i].ProviderID = p.extension.ID
			for j := range handleResult.Artist.Releases[i].Tracks {
				handleResult.Artist.Releases[i].Tracks[j].ProviderID = p.extension.ID
			}
		}
		for i := range handleResult.Artist.TopTracks {
			handleResult.Artist.TopTracks[i].ProviderID = p.extension.ID
		}
	}

	return &handleResult, nil
}

type MatchTrackResult struct {
	Matched    bool    `json:"matched"`
	TrackID    string  `json:"track_id,omitempty"`
	Confidence float64 `json:"confidence,omitempty"`
	Reason     string  `json:"reason,omitempty"`
}

func (p *extensionProviderWrapper) MatchTrack(sourceTrack map[string]interface{}, candidates []map[string]interface{}) (*MatchTrackResult, error) {
	if !p.extension.Manifest.HasCustomMatching() {
		return nil, fmt.Errorf("extension '%s' does not support custom matching", p.extension.ID)
	}

	if !p.extension.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", p.extension.ID)
	}
	perf := newExtensionCallPerf(p.extension.ID, "matchTrack")
	defer perf.finish()
	initStartedAt := time.Now()
	if err := p.lockReadyVM(); err != nil {
		return nil, err
	}
	perf.recordInit(time.Since(initStartedAt))
	defer p.extension.VMMu.Unlock()

	sourceJSON, _ := json.Marshal(sourceTrack)
	candidatesJSON, _ := json.Marshal(candidates)

	script := fmt.Sprintf(`
		(function() {
			if (typeof extension !== 'undefined' && typeof extension.matchTrack === 'function') {
				return extension.matchTrack(%s, %s);
			}
			return null;
		})()
	`, string(sourceJSON), string(candidatesJSON))

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutAndRecover(p.vm, script, DefaultJSTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		if IsTimeoutError(err) {
			return nil, fmt.Errorf("matchTrack timeout: extension took too long to respond")
		}
		return nil, fmt.Errorf("matchTrack failed: %w", err)
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return &MatchTrackResult{Matched: false, Reason: "not implemented"}, nil
	}

	parseStartedAt := time.Now()
	matchResult := parseExtensionMatchTrackValue(p.vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	perf.setItems(1)
	return &matchResult, nil
}

type PostProcessResult struct {
	Success     bool   `json:"success"`
	NewFilePath string `json:"new_file_path,omitempty"`
	NewFileURI  string `json:"new_file_uri,omitempty"`
	Error       string `json:"error,omitempty"`
	BitDepth    int    `json:"bit_depth,omitempty"`
	SampleRate  int    `json:"sample_rate,omitempty"`
}

type PostProcessInput struct {
	Path     string `json:"path,omitempty"`
	URI      string `json:"uri,omitempty"`
	Name     string `json:"name,omitempty"`
	MimeType string `json:"mime_type,omitempty"`
	Size     int64  `json:"size,omitempty"`
	IsSAF    bool   `json:"is_saf,omitempty"`
}

const PostProcessTimeout = 2 * time.Minute

func (p *extensionProviderWrapper) PostProcess(filePath string, metadata map[string]interface{}, hookID string) (*PostProcessResult, error) {
	if !p.extension.Manifest.HasPostProcessing() {
		return nil, fmt.Errorf("extension '%s' does not support post-processing", p.extension.ID)
	}

	if !p.extension.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", p.extension.ID)
	}
	perf := newExtensionCallPerf(p.extension.ID, "postProcess")
	defer perf.finish()
	initStartedAt := time.Now()
	if err := p.lockReadyVM(); err != nil {
		return &PostProcessResult{Success: false, Error: err.Error()}, nil
	}
	perf.recordInit(time.Since(initStartedAt))
	defer p.extension.VMMu.Unlock()

	metadataJSON, _ := json.Marshal(metadata)

	script := fmt.Sprintf(`
		(function() {
			if (typeof extension !== 'undefined' && typeof extension.postProcess === 'function') {
				return extension.postProcess(%q, %s, %q);
			}
			return null;
		})()
	`, filePath, string(metadataJSON), hookID)

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutAndRecover(p.vm, script, PostProcessTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		errMsg := err.Error()
		if IsTimeoutError(err) {
			errMsg = "postProcess timeout: extension took too long to complete"
		}
		return &PostProcessResult{
			Success: false,
			Error:   errMsg,
		}, nil
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return &PostProcessResult{
			Success: false,
			Error:   "postProcess returned null",
		}, nil
	}

	parseStartedAt := time.Now()
	postResult := parseExtensionPostProcessValue(p.vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	perf.setItems(1)
	return &postResult, nil
}

func (p *extensionProviderWrapper) PostProcessV2(input PostProcessInput, metadata map[string]interface{}, hookID string) (*PostProcessResult, error) {
	if !p.extension.Manifest.HasPostProcessing() {
		return nil, fmt.Errorf("extension '%s' does not support post-processing", p.extension.ID)
	}

	if !p.extension.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", p.extension.ID)
	}
	perf := newExtensionCallPerf(p.extension.ID, "postProcessV2")
	defer perf.finish()
	initStartedAt := time.Now()
	if err := p.lockReadyVM(); err != nil {
		return &PostProcessResult{Success: false, Error: err.Error()}, nil
	}
	perf.recordInit(time.Since(initStartedAt))
	defer p.extension.VMMu.Unlock()

	metadataJSON, _ := json.Marshal(metadata)
	inputJSON, _ := json.Marshal(input)
	filePath := input.Path

	script := fmt.Sprintf(`
		(function() {
			if (typeof extension !== 'undefined') {
				if (typeof extension.postProcessV2 === 'function') {
					return extension.postProcessV2(%s, %s, %q);
				}
				if (typeof extension.postProcess === 'function') {
					return extension.postProcess(%q, %s, %q);
				}
			}
			return null;
		})()
	`, string(inputJSON), string(metadataJSON), hookID, filePath, string(metadataJSON), hookID)

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutAndRecover(p.vm, script, PostProcessTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		errMsg := err.Error()
		if IsTimeoutError(err) {
			errMsg = "postProcess timeout: extension took too long to complete"
		}
		return &PostProcessResult{
			Success: false,
			Error:   errMsg,
		}, nil
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return &PostProcessResult{
			Success: false,
			Error:   "postProcess returned null",
		}, nil
	}

	parseStartedAt := time.Now()
	postResult := parseExtensionPostProcessValue(p.vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	perf.setItems(1)
	return &postResult, nil
}

func (m *extensionManager) GetSearchProviders() []*extensionProviderWrapper {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var providers []*extensionProviderWrapper
	for _, ext := range m.extensions {
		if ext.Enabled && ext.Manifest.HasCustomSearch() && ext.Error == "" {
			providers = append(providers, newExtensionProviderWrapper(ext))
		}
	}
	return providers
}

func (m *extensionManager) GetURLHandlers() []*extensionProviderWrapper {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var providers []*extensionProviderWrapper
	for _, ext := range m.extensions {
		if ext.Enabled && ext.Manifest.HasURLHandler() && ext.Error == "" {
			providers = append(providers, newExtensionProviderWrapper(ext))
		}
	}
	return providers
}

func (m *extensionManager) FindURLHandler(url string) *extensionProviderWrapper {
	m.mu.RLock()
	defer m.mu.RUnlock()

	for _, ext := range m.extensions {
		if ext.Enabled && ext.Manifest.MatchesURL(url) && ext.Error == "" {
			return newExtensionProviderWrapper(ext)
		}
	}
	return nil
}

type ExtURLHandleResultWithExtID struct {
	Result      *ExtURLHandleResult
	ExtensionID string
}

func (m *extensionManager) HandleURLWithExtension(url string) (*ExtURLHandleResultWithExtID, error) {
	handler := m.FindURLHandler(url)
	if handler == nil {
		return nil, fmt.Errorf("no extension found to handle URL: %s", url)
	}

	result, err := handler.HandleURL(url)
	if err != nil {
		return &ExtURLHandleResultWithExtID{
			Result:      nil,
			ExtensionID: handler.extension.ID,
		}, err
	}

	return &ExtURLHandleResultWithExtID{
		Result:      result,
		ExtensionID: handler.extension.ID,
	}, nil
}

func (m *extensionManager) GetPostProcessingProviders() []*extensionProviderWrapper {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var providers []*extensionProviderWrapper
	for _, ext := range m.extensions {
		if ext.Enabled && ext.Manifest.HasPostProcessing() && ext.Error == "" {
			providers = append(providers, newExtensionProviderWrapper(ext))
		}
	}
	return providers
}

func (m *extensionManager) RunPostProcessing(filePath string, metadata map[string]interface{}) (*PostProcessResult, error) {
	providers := m.GetPostProcessingProviders()
	if len(providers) == 0 {
		return &PostProcessResult{Success: true, NewFilePath: filePath}, nil
	}

	currentPath := filePath
	for _, provider := range providers {
		hooks := provider.extension.Manifest.GetPostProcessingHooks()
		for _, hook := range hooks {
			if !hook.DefaultEnabled {
				continue
			}

			ext := strings.ToLower(filepath.Ext(currentPath))
			if len(hook.SupportedFormats) > 0 {
				supported := false
				for _, format := range hook.SupportedFormats {
					if "."+format == ext || format == ext[1:] {
						supported = true
						break
					}
				}
				if !supported {
					continue
				}
			}

			GoLog("[PostProcess] Running hook %s from %s on %s\n", hook.ID, provider.extension.ID, currentPath)

			result, err := provider.PostProcess(currentPath, metadata, hook.ID)
			if err != nil {
				GoLog("[PostProcess] Hook %s failed: %v\n", hook.ID, err)
				continue
			}

			if result.Success && result.NewFilePath != "" {
				currentPath = result.NewFilePath
			}
		}
	}

	return &PostProcessResult{Success: true, NewFilePath: currentPath}, nil
}

func (m *extensionManager) RunPostProcessingV2(input PostProcessInput, metadata map[string]interface{}) (*PostProcessResult, error) {
	providers := m.GetPostProcessingProviders()
	if len(providers) == 0 {
		return &PostProcessResult{Success: true, NewFilePath: input.Path, NewFileURI: input.URI}, nil
	}

	currentInput := input
	for _, provider := range providers {
		hooks := provider.extension.Manifest.GetPostProcessingHooks()
		for _, hook := range hooks {
			if !hook.DefaultEnabled {
				continue
			}

			ext := strings.ToLower(filepath.Ext(currentInput.Path))
			if ext == "" && currentInput.Name != "" {
				ext = strings.ToLower(filepath.Ext(currentInput.Name))
			}
			if len(hook.SupportedFormats) > 0 && ext != "" {
				supported := false
				for _, format := range hook.SupportedFormats {
					if "."+format == ext || format == ext[1:] {
						supported = true
						break
					}
				}
				if !supported {
					continue
				}
			}

			GoLog("[PostProcessV2] Running hook %s from %s on %s\n", hook.ID, provider.extension.ID, currentInput.Path)

			result, err := provider.PostProcessV2(currentInput, metadata, hook.ID)
			if err != nil {
				GoLog("[PostProcessV2] Hook %s failed: %v\n", hook.ID, err)
				continue
			}

			if result.Success && result.NewFilePath != "" {
				currentInput.Path = result.NewFilePath
				if currentInput.Name == "" {
					currentInput.Name = filepath.Base(result.NewFilePath)
				}
			}
			if result.Success && result.NewFileURI != "" {
				currentInput.URI = result.NewFileURI
			}
		}
	}

	return &PostProcessResult{Success: true, NewFilePath: currentInput.Path, NewFileURI: currentInput.URI}, nil
}

type ExtLyricsResult struct {
	Lines        []ExtLyricsLine `json:"lines"`
	SyncType     string          `json:"syncType"`
	Instrumental bool            `json:"instrumental"`
	PlainLyrics  string          `json:"plainLyrics"`
	Provider     string          `json:"provider"`
}

type ExtLyricsLine struct {
	StartTimeMs int64  `json:"startTimeMs"`
	Words       string `json:"words"`
	EndTimeMs   int64  `json:"endTimeMs"`
}

func (p *extensionProviderWrapper) FetchLyrics(trackName, artistName, albumName string, durationSec float64) (*LyricsResponse, error) {
	if !p.extension.Manifest.IsLyricsProvider() {
		return nil, fmt.Errorf("extension '%s' is not a lyrics provider", p.extension.ID)
	}

	if !p.extension.Enabled {
		return nil, fmt.Errorf("extension '%s' is disabled", p.extension.ID)
	}
	perf := newExtensionCallPerf(p.extension.ID, "fetchLyrics")
	defer perf.finish()
	initStartedAt := time.Now()
	if err := p.lockReadyVM(); err != nil {
		return nil, err
	}
	perf.recordInit(time.Since(initStartedAt))
	defer p.extension.VMMu.Unlock()

	// Use global variables to avoid JS injection issues with special characters in track/artist names
	const trackVar = "__sf_lyrics_track"
	const artistVar = "__sf_lyrics_artist"
	const albumVar = "__sf_lyrics_album"
	const durationVar = "__sf_lyrics_duration"
	global := p.vm.GlobalObject()
	_ = global.Set(trackVar, trackName)
	_ = global.Set(artistVar, artistName)
	_ = global.Set(albumVar, albumName)
	_ = global.Set(durationVar, durationSec)
	defer func() {
		global.Delete(trackVar)
		global.Delete(artistVar)
		global.Delete(albumVar)
		global.Delete(durationVar)
	}()

	const script = `
		(function() {
			if (typeof extension !== 'undefined' && typeof extension.fetchLyrics === 'function') {
				return extension.fetchLyrics(__sf_lyrics_track, __sf_lyrics_artist, __sf_lyrics_album, __sf_lyrics_duration);
			}
			return null;
		})()
	`

	jsStartedAt := time.Now()
	result, err := RunWithTimeoutAndRecover(p.vm, script, DefaultJSTimeout)
	perf.recordJS(time.Since(jsStartedAt))
	perf.recordPayload(result)
	if err != nil {
		if IsTimeoutError(err) {
			return nil, fmt.Errorf("fetchLyrics timeout: extension took too long to respond")
		}
		return nil, fmt.Errorf("fetchLyrics failed: %w", err)
	}

	if result == nil || goja.IsUndefined(result) || goja.IsNull(result) {
		return nil, fmt.Errorf("fetchLyrics returned null")
	}

	parseStartedAt := time.Now()
	extResult, err := parseExtensionLyricsValue(p.vm, result)
	perf.recordParse(time.Since(parseStartedAt))
	if err != nil {
		return nil, fmt.Errorf("failed to parse lyrics result: %w", err)
	}
	perf.setItems(len(extResult.Lines))

	response := &LyricsResponse{
		SyncType:     extResult.SyncType,
		Instrumental: extResult.Instrumental,
		PlainLyrics:  extResult.PlainLyrics,
		Provider:     extResult.Provider,
		Source:       "Extension: " + p.extension.ID,
	}

	if response.Provider == "" {
		response.Provider = p.extension.Manifest.DisplayName
	}

	for _, line := range extResult.Lines {
		response.Lines = append(response.Lines, LyricsLine(line))
	}

	if len(response.Lines) == 0 && response.PlainLyrics != "" && !response.Instrumental {
		response.SyncType = "UNSYNCED"
		for _, line := range strings.Split(response.PlainLyrics, "\n") {
			if strings.TrimSpace(line) != "" {
				response.Lines = append(response.Lines, LyricsLine{
					StartTimeMs: 0,
					Words:       line,
					EndTimeMs:   0,
				})
			}
		}
	}

	return response, nil
}

func (m *extensionManager) GetLyricsProviders() []*extensionProviderWrapper {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var providers []*extensionProviderWrapper
	for _, ext := range m.extensions {
		if ext.Enabled && ext.Manifest.IsLyricsProvider() && ext.Error == "" {
			providers = append(providers, newExtensionProviderWrapper(ext))
		}
	}

	sort.Slice(providers, func(i, j int) bool {
		return providers[i].extension.ID < providers[j].extension.ID
	})

	return providers
}
