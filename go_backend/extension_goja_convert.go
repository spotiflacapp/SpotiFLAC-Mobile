package gobackend

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/dop251/goja"
)

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

func gojaObjectInterfaceMap(obj *goja.Object, keys ...string) map[string]any {
	value := gojaObjectValue(obj, keys...)
	if gojaValueIsEmpty(value) {
		return nil
	}

	exported, ok := value.Export().(map[string]any)
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

func gojaObjectStringSlice(obj *goja.Object, keys ...string) []string {
	value := gojaObjectValue(obj, keys...)
	if gojaValueIsEmpty(value) {
		return nil
	}
	exported, ok := value.Export().([]any)
	if !ok || len(exported) == 0 {
		return nil
	}
	result := make([]string, 0, len(exported))
	for _, item := range exported {
		str, ok := item.(string)
		if !ok {
			continue
		}
		str = strings.TrimSpace(str)
		if str != "" {
			result = append(result, str)
		}
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
		AlbumID:       gojaObjectString(obj, "album_id", "albumId"),
		AlbumURL:      gojaObjectString(obj, "album_url", "albumUrl"),
		ArtistID:      gojaObjectString(obj, "artist_id", "artistId"),
		ArtistURL:     gojaObjectString(obj, "artist_url", "artistUrl"),
		ExternalURL:   gojaObjectString(obj, "external_urls", "externalUrls", "external_url", "externalUrl", "url"),
		DurationMS:    gojaObjectInt(obj, "duration_ms", "durationMs"),
		CoverURL:      gojaObjectString(obj, "cover_url", "coverUrl"),
		PreviewURL:    gojaObjectString(obj, "preview_url", "previewUrl"),
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
		Explicit:      gojaObjectBool(obj, "explicit", "is_explicit", "isExplicit"),
		TidalID:       gojaObjectString(obj, "tidal_id", "tidalId"),
		QobuzID:       gojaObjectString(obj, "qobuz_id", "qobuzId"),
		DeezerID:      gojaObjectString(obj, "deezer_id", "deezerId"),
		SpotifyID:     gojaObjectString(obj, "spotify_id", "spotifyId"),
		ExternalLinks: gojaObjectStringMap(vm, obj, "external_links", "externalLinks"),
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
		HeaderImage: gojaObjectString(obj, "header_image", "headerImage"),
		HeaderVideo: gojaObjectString(obj, "header_video", "headerVideo"),
		ReleaseDate: gojaObjectString(obj, "release_date", "releaseDate"),
		TotalTracks: gojaObjectInt(obj, "total_tracks", "totalTracks"),
		AlbumType:   gojaObjectString(obj, "album_type", "albumType"),
		AudioTraits: gojaObjectStringSlice(obj, "audio_traits", "audioTraits"),
		Tracks:      tracks,
		ProviderID:  gojaObjectString(obj, "provider_id", "providerId"),
	}.withTrackFallbacks(), nil
}

// withTrackFallbacks fills the album-level artist and release date from the
// album's tracks when the extension did not provide them at the album level.
// This is a generic mechanism so any extension benefits, without per-extension
// special-casing in the app.
func (a ExtAlbumMetadata) withTrackFallbacks() ExtAlbumMetadata {
	if strings.TrimSpace(a.Artists) == "" {
		a.Artists = albumArtistFromTracks(a.Tracks)
	}
	if strings.TrimSpace(a.ReleaseDate) == "" {
		a.ReleaseDate = albumReleaseDateFromTracks(a.Tracks)
	}
	if len(a.AudioTraits) == 0 {
		a.AudioTraits = albumAudioTraitsFromTracks(a.Tracks)
	}
	return a
}

// albumArtistFromTracks prefers an explicit per-track album artist, then falls
// back to the most common track artist across the album.
func albumArtistFromTracks(tracks []ExtTrackMetadata) string {
	for _, t := range tracks {
		if s := strings.TrimSpace(t.AlbumArtist); s != "" {
			return s
		}
	}
	counts := map[string]int{}
	order := []string{}
	for _, t := range tracks {
		artist := strings.TrimSpace(t.Artists)
		if artist == "" {
			continue
		}
		if _, ok := counts[artist]; !ok {
			order = append(order, artist)
		}
		counts[artist]++
	}
	best := ""
	bestCount := 0
	for _, artist := range order {
		if counts[artist] > bestCount {
			best = artist
			bestCount = counts[artist]
		}
	}
	return best
}

// albumReleaseDateFromTracks returns the first non-empty track release date.
func albumReleaseDateFromTracks(tracks []ExtTrackMetadata) string {
	for _, t := range tracks {
		if s := strings.TrimSpace(t.ReleaseDate); s != "" {
			return s
		}
	}
	return ""
}

// albumAudioTraitsFromTracks derives album-level audio badges (Dolby Atmos,
// Hi-Res Lossless, Lossless) from the per-track audio quality/mode fields that
// extensions like Tidal and Qobuz already provide. Tokens match what the album
// header understands ("dolby_atmos", "hi_res_lossless", "lossless").
func albumAudioTraitsFromTracks(tracks []ExtTrackMetadata) []string {
	atmos := false
	hiRes := false
	lossless := false

	for _, t := range tracks {
		modes := strings.ToUpper(t.AudioModes)
		quality := strings.ToUpper(t.AudioQuality)
		if strings.Contains(modes, "ATMOS") || strings.Contains(quality, "ATMOS") {
			atmos = true
		}
		if strings.Contains(quality, "HI_RES") ||
			strings.Contains(quality, "HIRES") ||
			strings.Contains(quality, "MASTER") ||
			strings.Contains(quality, "MQA") {
			hiRes = true
		}
		if strings.Contains(quality, "LOSSLESS") ||
			strings.Contains(quality, "FLAC") {
			lossless = true
		}
		if bd, sr := parseBitDepthSampleRate(quality); bd > 0 {
			if bd > 16 || sr > 48 {
				hiRes = true
			} else {
				lossless = true
			}
		}
	}

	traits := []string{}
	if atmos {
		traits = append(traits, "dolby_atmos")
	}
	if hiRes {
		traits = append(traits, "hi_res_lossless")
	} else if lossless {
		traits = append(traits, "lossless")
	}
	return traits
}

// parseBitDepthSampleRate extracts a bit depth and sample rate (in kHz) from
// labels such as "24bit/96kHz", "16bit/44.1kHz" or "24bit".
func parseBitDepthSampleRate(quality string) (int, float64) {
	lower := strings.ToLower(quality)
	bitDepth := 0
	sampleRate := 0.0

	if idx := strings.Index(lower, "bit"); idx > 0 {
		j := idx
		for j > 0 && lower[j-1] >= '0' && lower[j-1] <= '9' {
			j--
		}
		if n, err := strconv.Atoi(lower[j:idx]); err == nil {
			bitDepth = n
		}
	}
	if idx := strings.Index(lower, "khz"); idx > 0 {
		j := idx
		for j > 0 && ((lower[j-1] >= '0' && lower[j-1] <= '9') || lower[j-1] == '.') {
			j--
		}
		if f, err := strconv.ParseFloat(lower[j:idx], 64); err == nil {
			sampleRate = f
		}
	}
	return bitDepth, sampleRate
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
		HeaderVideo: gojaObjectString(obj, "header_video", "headerVideo"),
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
		Success:           gojaObjectBool(obj, "success"),
		FilePath:          gojaObjectString(obj, "file_path", "filePath", "path"),
		AlreadyExists:     gojaObjectBool(obj, "already_exists", "alreadyExists"),
		BitDepth:          gojaObjectInt(obj, "bit_depth", "bitDepth"),
		SampleRate:        gojaObjectInt(obj, "sample_rate", "sampleRate"),
		AudioCodec:        gojaObjectString(obj, "audio_codec", "audioCodec", "codec"),
		DurationMS:        gojaObjectInt(obj, "duration_ms", "durationMs"),
		ErrorMessage:      gojaObjectString(obj, "error_message", "errorMessage", "error"),
		ErrorType:         gojaObjectString(obj, "error_type", "errorType"),
		RetryAfterSeconds: gojaObjectInt(obj, "retry_after_seconds", "retryAfterSeconds"),
		Title:             gojaObjectString(obj, "title"),
		Artist:            gojaObjectString(obj, "artist"),
		Album:             gojaObjectString(obj, "album"),
		AlbumArtist:       gojaObjectString(obj, "album_artist", "albumArtist"),
		TrackNumber:       gojaObjectInt(obj, "track_number", "trackNumber"),
		DiscNumber:        gojaObjectInt(obj, "disc_number", "discNumber"),
		TotalTracks:       gojaObjectInt(obj, "total_tracks", "totalTracks"),
		TotalDiscs:        gojaObjectInt(obj, "total_discs", "totalDiscs"),
		ReleaseDate:       gojaObjectString(obj, "release_date", "releaseDate"),
		CoverURL:          gojaObjectString(obj, "cover_url", "coverUrl"),
		ISRC:              gojaObjectString(obj, "isrc"),
		Genre:             gojaObjectString(obj, "genre"),
		Label:             gojaObjectString(obj, "label"),
		Copyright:         gojaObjectString(obj, "copyright"),
		Composer:          gojaObjectString(obj, "composer"),
		LyricsLRC:         gojaObjectString(obj, "lyrics_lrc", "lyricsLrc"),
		DecryptionKey:     gojaObjectString(obj, "decryption_key", "decryptionKey"),
		Decryption:        parseExtensionDownloadDecryptionValue(vm, gojaObjectValue(obj, "decryption")),
		ActualExtension:   gojaObjectString(obj, "actual_extension", "actualExtension"),
		OutputExtension:   gojaObjectString(obj, "output_extension", "outputExtension"),
		ActualContainer:   gojaObjectString(obj, "actual_container", "actualContainer", "container"),
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
		Type:        gojaObjectString(obj, "type"),
		Name:        gojaObjectString(obj, "name"),
		CoverURL:    gojaObjectString(obj, "cover_url", "coverUrl"),
		HeaderImage: gojaObjectString(obj, "header_image", "headerImage"),
		HeaderVideo: gojaObjectString(obj, "header_video", "headerVideo"),
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
