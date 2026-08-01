package gobackend

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func applyAudioMetadataToResult(result map[string]any, meta *AudioMetadata) {
	result["title"] = meta.Title
	result["artist"] = meta.Artist
	result["album"] = meta.Album
	result["album_artist"] = meta.AlbumArtist
	result["date"] = meta.Date
	if meta.Date == "" {
		result["date"] = meta.Year
	}
	result["track_number"] = meta.TrackNumber
	result["total_tracks"] = meta.TotalTracks
	result["disc_number"] = meta.DiscNumber
	result["total_discs"] = meta.TotalDiscs
	result["isrc"] = meta.ISRC
	result["lyrics"] = meta.Lyrics
	result["genre"] = meta.Genre
	result["label"] = meta.Label
	result["copyright"] = meta.Copyright
	result["composer"] = meta.Composer
	result["comment"] = meta.Comment
	result["replaygain_track_gain"] = meta.ReplayGainTrackGain
	result["replaygain_track_peak"] = meta.ReplayGainTrackPeak
	result["replaygain_album_gain"] = meta.ReplayGainAlbumGain
	result["replaygain_album_peak"] = meta.ReplayGainAlbumPeak
}

func successMethodJSON(method string) (string, error) {
	return marshalJSONString(map[string]any{"success": true, "method": method})
}

func ReadFileMetadata(filePath string) (string, error) {
	lower := strings.ToLower(filePath)
	isFlac := strings.HasSuffix(lower, ".flac")
	isM4A := strings.HasSuffix(lower, ".m4a") || strings.HasSuffix(lower, ".mp4") || strings.HasSuffix(lower, ".aac")
	isMp3 := strings.HasSuffix(lower, ".mp3")
	isOgg := strings.HasSuffix(lower, ".opus") || strings.HasSuffix(lower, ".ogg")
	isApe := strings.HasSuffix(lower, ".ape")
	isWv := strings.HasSuffix(lower, ".wv")
	isMpc := strings.HasSuffix(lower, ".mpc")
	isWav := strings.HasSuffix(lower, ".wav")
	isAiff := strings.HasSuffix(lower, ".aiff") || strings.HasSuffix(lower, ".aif") || strings.HasSuffix(lower, ".aifc")

	result := map[string]any{
		"title":        "",
		"artist":       "",
		"album":        "",
		"album_artist": "",
		"date":         "",
		"track_number": 0,
		"total_tracks": 0,
		"disc_number":  0,
		"total_discs":  0,
		"isrc":         "",
		"lyrics":       "",
		"genre":        "",
		"label":        "",
		"copyright":    "",
		"composer":     "",
		"comment":      "",
		"duration":     0,
		"format":       "",
		"audio_codec":  "",
	}

	if isFlac {
		result["format"] = "flac"
		result["audio_codec"] = "flac"
		metadata, err := ReadMetadata(filePath)
		if err != nil {
			// File may have wrong extension (e.g. opus saved as .flac).
			// Try Ogg/Opus parser as fallback before giving up.
			GoLog("[ReadFileMetadata] FLAC parse failed for %s, trying Ogg fallback: %v\n", filePath, err)
			oggMeta, oggErr := ReadOggVorbisComments(filePath)
			if oggErr == nil && oggMeta != nil {
				result["title"] = oggMeta.Title
				result["artist"] = oggMeta.Artist
				result["album"] = oggMeta.Album
				result["album_artist"] = oggMeta.AlbumArtist
				result["date"] = oggMeta.Date
				if oggMeta.Date == "" {
					result["date"] = oggMeta.Year
				}
				result["track_number"] = oggMeta.TrackNumber
				result["total_tracks"] = oggMeta.TotalTracks
				result["disc_number"] = oggMeta.DiscNumber
				result["total_discs"] = oggMeta.TotalDiscs
				result["isrc"] = oggMeta.ISRC
				result["lyrics"] = oggMeta.Lyrics
				result["genre"] = oggMeta.Genre
				result["composer"] = oggMeta.Composer
				result["comment"] = oggMeta.Comment
				quality, qualityErr := GetOggQuality(filePath)
				if qualityErr == nil {
					result["sample_rate"] = quality.SampleRate
					result["duration"] = quality.Duration
					if quality.Bitrate > 0 {
						result["bitrate"] = quality.Bitrate / 1000
					}
				}
				result["format"] = "opus"
				result["audio_codec"] = "opus"
			} else {
				return "", fmt.Errorf("failed to read metadata: %w", err)
			}
		} else {
			result["title"] = metadata.Title
			result["artist"] = metadata.Artist
			result["album"] = metadata.Album
			result["album_artist"] = metadata.AlbumArtist
			result["date"] = metadata.Date
			result["track_number"] = metadata.TrackNumber
			result["total_tracks"] = metadata.TotalTracks
			result["disc_number"] = metadata.DiscNumber
			result["total_discs"] = metadata.TotalDiscs
			result["isrc"] = metadata.ISRC
			result["lyrics"] = metadata.Lyrics
			result["genre"] = metadata.Genre
			result["label"] = metadata.Label
			result["copyright"] = metadata.Copyright
			result["composer"] = metadata.Composer
			result["comment"] = metadata.Comment
			result["replaygain_track_gain"] = metadata.ReplayGainTrackGain
			result["replaygain_track_peak"] = metadata.ReplayGainTrackPeak
			result["replaygain_album_gain"] = metadata.ReplayGainAlbumGain
			result["replaygain_album_peak"] = metadata.ReplayGainAlbumPeak

			quality, qualityErr := GetAudioQuality(filePath)
			if qualityErr == nil {
				result["bit_depth"] = quality.BitDepth
				result["sample_rate"] = quality.SampleRate
				if quality.Codec != "" {
					result["audio_codec"] = quality.Codec
				}
				if quality.SampleRate > 0 && quality.TotalSamples > 0 {
					result["duration"] = int(quality.TotalSamples / int64(quality.SampleRate))
					// Average bitrate from file size: helps spot lossy audio
					// repackaged as "24-bit" FLAC (real hi-res sits well above
					// ~1500 kbps, upconverted files far below).
					durationSec := float64(quality.TotalSamples) / float64(quality.SampleRate)
					if info, statErr := os.Stat(filePath); statErr == nil && info.Size() > 0 && durationSec > 0 {
						result["bitrate"] = int(float64(info.Size()) * 8 / durationSec / 1000)
					}
				}
			}
		}
	} else if isM4A {
		result["format"] = "m4a"
		meta, err := ReadM4ATags(filePath)
		if err == nil && meta != nil {
			applyAudioMetadataToResult(result, meta)
		}
		quality, qualityErr := GetM4AQuality(filePath)
		if qualityErr == nil {
			result["bit_depth"] = quality.BitDepth
			result["sample_rate"] = quality.SampleRate
			result["duration"] = quality.Duration
			result["audio_codec"] = quality.Codec
			if format := libraryFormatForM4ACodec(quality.Codec); format != "" {
				result["format"] = format
			}
			if quality.Bitrate > 0 && !isLosslessLibraryFormat(fmt.Sprint(result["format"])) {
				result["bitrate"] = quality.Bitrate
			} else if quality.Duration > 0 {
				if info, statErr := os.Stat(filePath); statErr == nil && info.Size() > 0 {
					result["bitrate"] = int(float64(info.Size()) * 8 / float64(quality.Duration) / 1000)
				}
			}
		}
	} else if isMp3 {
		result["format"] = "mp3"
		result["audio_codec"] = "mp3"
		meta, err := ReadID3Tags(filePath)
		if err == nil && meta != nil {
			applyAudioMetadataToResult(result, meta)
		}
		quality, qualityErr := GetMP3Quality(filePath)
		if qualityErr == nil {
			result["bit_depth"] = quality.BitDepth
			result["sample_rate"] = quality.SampleRate
			result["duration"] = quality.Duration
			if quality.Bitrate > 0 {
				result["bitrate"] = quality.Bitrate / 1000
			}
		}
	} else if isOgg {
		result["format"] = "opus"
		result["audio_codec"] = "opus"
		meta, err := ReadOggVorbisComments(filePath)
		if err == nil && meta != nil {
			applyAudioMetadataToResult(result, meta)
		}
		quality, qualityErr := GetOggQuality(filePath)
		if qualityErr == nil {
			result["sample_rate"] = quality.SampleRate
			result["duration"] = quality.Duration
			if quality.Bitrate > 0 {
				result["bitrate"] = quality.Bitrate / 1000
			}
		}
	} else if isApe || isWv || isMpc {
		result["format"] = strings.TrimPrefix(filepath.Ext(filePath), ".")
		result["audio_codec"] = result["format"]
		apeTag, apeErr := ReadAPETags(filePath)
		if apeErr == nil && apeTag != nil {
			meta := APETagToAudioMetadata(apeTag)
			if meta != nil {
				applyAudioMetadataToResult(result, meta)
			}
		}
	} else if isWav || isAiff {
		var meta *AudioMetadata
		var quality *WAVQuality
		var qualityErr error
		if isAiff {
			result["format"] = "aiff"
			result["audio_codec"] = "pcm"
			meta, _ = ReadAIFFTags(filePath)
			quality, qualityErr = GetAIFFQuality(filePath)
		} else {
			result["format"] = "wav"
			result["audio_codec"] = "pcm"
			meta, _ = ReadWAVTags(filePath)
			quality, qualityErr = GetWAVQuality(filePath)
		}
		if meta != nil {
			applyAudioMetadataToResult(result, meta)
		}
		if qualityErr == nil && quality != nil {
			result["bit_depth"] = quality.BitDepth
			result["sample_rate"] = quality.SampleRate
			result["duration"] = quality.Duration
		}
	} else {
		return "", fmt.Errorf("unsupported file format: %s", filePath)
	}

	return marshalJSONString(result)
}

// ParseCueSheet is called from Dart to get track listing and timing data for CUE splitting.
// audioDir, if non-empty, overrides the directory used for resolving the
// referenced audio file (useful for SAF temp file scenarios).
func ParseCueSheet(cuePath string, audioDir string) (string, error) {
	return ParseCueFileJSON(cuePath, audioDir)
}

// ScanCueSheetForLibrary parses a .cue file and returns a JSON array of
// LibraryScanResult entries (one per track). This is the SAF-friendly variant:
//   - audioDir overrides where the referenced audio file is resolved
//   - virtualPathPrefix replaces cuePath in filePath / id fields (e.g. a content:// URI)
//   - fileModTime is stamped on every result (pass 0 to stat cuePath instead)
func ScanCueSheetForLibrary(cuePath, audioDir, virtualPathPrefix string, fileModTime int64) (string, error) {
	scanTime := time.Now().UTC().Format(time.RFC3339)
	results, err := ScanCueFileForLibraryExt(cuePath, audioDir, virtualPathPrefix, fileModTime, scanTime)
	if err != nil {
		return "[]", err
	}
	jsonBytes, err := json.Marshal(results)
	if err != nil {
		return "[]", fmt.Errorf("failed to marshal cue scan results: %w", err)
	}
	return string(jsonBytes), nil
}

func ScanCueSheetForLibraryWithCoverCacheKey(cuePath, audioDir, virtualPathPrefix string, fileModTime int64, coverCacheKey string) (string, error) {
	scanTime := time.Now().UTC().Format(time.RFC3339)
	results, err := ScanCueFileForLibraryExtWithCoverCacheKey(
		cuePath,
		audioDir,
		virtualPathPrefix,
		fileModTime,
		coverCacheKey,
		scanTime,
	)
	if err != nil {
		return "[]", err
	}
	jsonBytes, err := json.Marshal(results)
	if err != nil {
		return "[]", fmt.Errorf("failed to marshal cue scan results: %w", err)
	}
	return string(jsonBytes), nil
}

// WriteM4AFreeformTags writes ISRC and label into an M4A/MP4 file as iTunes
// freeform atoms. FFmpeg's MP4 muxer ignores these keys, so they must be
// written natively after the FFmpeg metadata pass for the values to persist.
// Only keys present in the JSON are touched; an empty value clears the tag.
func WriteM4AFreeformTags(filePath, metadataJSON string) (string, error) {
	var fields map[string]string
	if err := json.Unmarshal([]byte(metadataJSON), &fields); err != nil {
		return "", fmt.Errorf("invalid metadata JSON: %w", err)
	}

	if err := EditM4AFreeformText(filePath, fields); err != nil {
		return "", fmt.Errorf("failed to write M4A freeform tags: %w", err)
	}

	return successMethodJSON("native_m4a_freeform")
}

// EnsureAC4Config normalizes a decrypted AC-4 file to a standards-compliant ISO
// MP4 and injects the dac4 configuration box copied from sourcePath. No-op when
// the file is not AC-4.
func EnsureAC4Config(filePath, sourcePath string) (string, error) {
	if err := EnsureAC4ConfigBox(filePath, sourcePath); err != nil {
		return "", fmt.Errorf("failed to finalize AC-4 container: %w", err)
	}
	return `{"success":true}`, nil
}

// WriteAC4Metadata writes iTunes-style metadata into an AC-4 MP4. The JSON
// "handled" field reports whether the file was AC-4 (true) so the caller can
// skip the FFmpeg metadata pass that would re-wrap it as QuickTime.
func WriteAC4Metadata(filePath, metadataJSON, coverPath string) (string, error) {
	handled, err := WriteAC4MetadataIfApplicable(filePath, metadataJSON, coverPath)
	if err != nil {
		return "", fmt.Errorf("failed to write AC-4 metadata: %w", err)
	}
	resp := map[string]any{"success": true, "handled": handled}
	s, _ := marshalJSONString(resp)
	return s, nil
}

// EditFileMetadata writes audio file tags: FLAC via native Go library, MP3/Opus returns map for Dart/FFmpeg.
func EditFileMetadata(filePath, metadataJSON string) (string, error) {
	var fields map[string]string
	if err := json.Unmarshal([]byte(metadataJSON), &fields); err != nil {
		return "", fmt.Errorf("invalid metadata JSON: %w", err)
	}

	lower := strings.ToLower(filePath)
	isFlac := strings.HasSuffix(lower, ".flac")
	isApeFile := strings.HasSuffix(lower, ".ape") || strings.HasSuffix(lower, ".wv") || strings.HasSuffix(lower, ".mpc")
	isM4AFile := strings.HasSuffix(lower, ".m4a") || strings.HasSuffix(lower, ".mp4") || strings.HasSuffix(lower, ".m4b")
	isWavFile := strings.HasSuffix(lower, ".wav")
	isAiffFile := strings.HasSuffix(lower, ".aiff") || strings.HasSuffix(lower, ".aif") || strings.HasSuffix(lower, ".aifc")
	coverPath := strings.TrimSpace(fields["cover_path"])

	if hasOnlyM4AReplayGainFields(fields) && (isM4AFile || isMP4ContainerFile(filePath)) {
		if err := EditM4AReplayGain(filePath, fields); err != nil {
			return "", fmt.Errorf("failed to write M4A metadata: %w", err)
		}

		return successMethodJSON("native_m4a_replaygain")
	}

	if isFlac {
		// A .flac name does not guarantee FLAC content: providers sometimes
		// deliver an MP4/M4A stream that ends up under the requested name.
		// The FLAC writer would fail "fLaC head incorrect" on every attempt,
		// so detect the mismatch up front and say what is actually wrong.
		if isMP4ContainerFile(filePath) {
			return "", fmt.Errorf(
				"failed to write FLAC metadata: file is an MP4/M4A stream under a .flac name; rename it to .m4a",
			)
		}
		if err := EditFlacFields(filePath, fields); err != nil {
			return "", fmt.Errorf("failed to write FLAC metadata: %w", err)
		}

		return successMethodJSON("native")
	}

	// WAV / AIFF: write tags into an embedded ID3v2.4 chunk natively.
	if isWavFile {
		if err := WriteWAVTags(filePath, fields); err != nil {
			return "", fmt.Errorf("failed to write WAV metadata: %w", err)
		}
		return successMethodJSON("native_wav")
	}
	if isAiffFile {
		if err := WriteAIFFTags(filePath, fields); err != nil {
			return "", fmt.Errorf("failed to write AIFF metadata: %w", err)
		}
		return successMethodJSON("native_aiff")
	}

	if isApeFile {
		meta := audioMetadataFromEditFields(fields)

		newItems := AudioMetadataToAPEItems(meta)

		// If a cover image was provided, embed it as a binary APE item.
		// APEv2 cover format: "cover.jpg\0<binary image data>", flagged binary.
		if coverPath != "" {
			coverData, coverErr := os.ReadFile(coverPath)
			if coverErr == nil && len(coverData) > 0 {
				// The value is "filename\0" + raw bytes.  We store the
				// description as the Value field, but since the item is
				// flagged binary, the writer serializes it verbatim.
				desc := "cover.jpg\x00"
				binaryValue := desc + string(coverData)
				newItems = append(newItems, APETagItem{
					Key:   "Cover Art (Front)",
					Value: binaryValue,
					Flags: apeItemFlagBinary,
				})
			}
		}

		// Build the set of APE keys that the edit explicitly controls.
		// Even if the value is empty (user cleared the field), the old
		// value must be removed during merge.
		overrideKeys := apeKeysFromFields(fields)
		if coverPath != "" {
			overrideKeys["COVER ART (FRONT)"] = struct{}{}
		}

		// Read existing tags so we can merge rather than replace.
		// This preserves cover art and custom items not in the edit set.
		existingTag, _ := ReadAPETags(filePath)
		var finalItems []APETagItem
		if existingTag != nil && len(existingTag.Items) > 0 {
			finalItems = MergeAPEItems(existingTag.Items, newItems, overrideKeys)
		} else {
			finalItems = newItems
		}

		tag := &APETag{
			Version: apeTagVersion2,
			Items:   finalItems,
		}

		if err := WriteAPETags(filePath, tag); err != nil {
			return "", fmt.Errorf("failed to write APE tags: %w", err)
		}

		return successMethodJSON("native_ape")
	}

	// MP3, Ogg/Opus, and M4A have native editors that preserve foreign
	// tags and skip the ffmpeg remux. Any failure falls back to the ffmpeg
	// response so callers keep the old behavior for exotic files.
	isMp3 := strings.HasSuffix(lower, ".mp3")
	isOggFile := strings.HasSuffix(lower, ".opus") || strings.HasSuffix(lower, ".ogg")

	if isMp3 {
		if err := EditMP3Fields(filePath, fields); err != nil {
			GoLog("[Metadata] Native MP3 edit failed, falling back to ffmpeg: %v\n", err)
		} else {
			return successMethodJSON("native_mp3")
		}
	}
	if isOggFile {
		if err := EditOggFields(filePath, fields); err != nil {
			GoLog("[Metadata] Native Ogg edit failed, falling back to ffmpeg: %v\n", err)
		} else {
			return successMethodJSON("native_ogg")
		}
	}
	if isM4AFile || isMP4ContainerFile(filePath) {
		if err := EditM4AFields(filePath, fields); err != nil {
			GoLog("[Metadata] Native M4A edit failed, falling back to ffmpeg: %v\n", err)
		} else {
			return successMethodJSON("native_m4a")
		}
	}

	resp := map[string]any{
		"success": true,
		"method":  "ffmpeg",
		"fields":  fields,
	}
	s, _ := marshalJSONString(resp)
	return s, nil
}

func isMP4ContainerFile(filePath string) bool {
	f, err := os.Open(filePath)
	if err != nil {
		return false
	}
	defer f.Close()

	header := make([]byte, 12)
	n, err := f.Read(header)
	if err != nil || n < 8 {
		return false
	}
	return string(header[4:8]) == "ftyp"
}

func hasOnlyM4AReplayGainFields(fields map[string]string) bool {
	allowed := map[string]struct{}{
		"replaygain_track_gain": {},
		"replaygain_track_peak": {},
		"replaygain_album_gain": {},
		"replaygain_album_peak": {},
	}

	hasReplayGain := false
	for key, value := range fields {
		if strings.TrimSpace(value) == "" {
			continue
		}
		if _, ok := allowed[strings.ToLower(strings.TrimSpace(key))]; ok {
			hasReplayGain = true
			continue
		}
		return false
	}

	return hasReplayGain
}

// RewriteSplitArtistTagsExport rewrites ARTIST and ALBUMARTIST Vorbis
// comments in a FLAC file as multiple separate entries (one per artist).
// Call this after FFmpeg metadata embedding to fix split artist tags,
// since FFmpeg deduplicates -metadata keys and only keeps the last value.
func RewriteSplitArtistTagsExport(filePath, artist, albumArtist string) (string, error) {
	err := RewriteSplitArtistTags(filePath, artist, albumArtist)
	if err != nil {
		return errorResponse("Failed to rewrite artist tags: " + err.Error())
	}

	resp := map[string]any{
		"success": true,
		"message": "Split artist tags written successfully",
	}

	s, _ := marshalJSONString(resp)
	return s, nil
}

func DownloadCoverToFile(coverURL string, outputPath string, maxQuality bool) error {
	if coverURL == "" {
		return fmt.Errorf("no cover URL provided")
	}

	data, err := downloadCoverToMemory(coverURL, maxQuality)
	if err != nil {
		return fmt.Errorf("failed to download cover: %w", err)
	}

	if err := os.WriteFile(outputPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write cover file: %w", err)
	}

	GoLog("[Cover] Downloaded cover to: %s (%d KB)\n", outputPath, len(data)/1024)
	return nil
}

func ExtractCoverToFile(audioPath string, outputPath string) error {
	lower := strings.ToLower(audioPath)

	var coverData []byte
	var err error

	if strings.HasSuffix(lower, ".flac") {
		coverData, err = ExtractCoverArt(audioPath)
	} else if strings.HasSuffix(lower, ".m4a") || strings.HasSuffix(lower, ".aac") {
		coverData, err = extractCoverFromM4A(audioPath)
	} else if strings.HasSuffix(lower, ".mp3") {
		coverData, _, err = extractMP3CoverArt(audioPath)
	} else if strings.HasSuffix(lower, ".opus") || strings.HasSuffix(lower, ".ogg") {
		coverData, _, err = extractOggCoverArt(audioPath)
	} else if strings.HasSuffix(lower, ".wav") ||
		strings.HasSuffix(lower, ".aiff") ||
		strings.HasSuffix(lower, ".aif") ||
		strings.HasSuffix(lower, ".aifc") {
		coverData, _, err = extractWAVAIFFCover(audioPath)
	} else {
		return fmt.Errorf("unsupported audio format for cover extraction")
	}

	if err != nil {
		return fmt.Errorf("failed to extract cover: %w", err)
	}

	if err := os.WriteFile(outputPath, coverData, 0644); err != nil {
		return fmt.Errorf("failed to write cover file: %w", err)
	}

	GoLog("[Cover] Extracted cover art to: %s (%d KB)\n", outputPath, len(coverData)/1024)
	return nil
}
