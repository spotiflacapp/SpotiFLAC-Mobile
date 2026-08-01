package gobackend

import (
	"bytes"
	"fmt"
	stdimage "image"
	_ "image/gif"
	"image/jpeg"
	_ "image/png"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/go-flac/flacpicture/v2"
	"github.com/go-flac/flacvorbis/v2"
	"github.com/go-flac/go-flac/v2"
)

const artistTagModeSplitVorbis = "split_vorbis"

var artistTagSplitPattern = regexp.MustCompile(`\s*(?:,|&|\bx\b)\s*|\s+\b(?:feat(?:uring)?|ft|with)\.?\s*`)

func detectCoverMIME(coverPath string, coverData []byte) string {
	// Prefer magic-byte detection over file extension.
	// Some providers return non-JPEG data behind .jpg URLs.
	if len(coverData) >= 8 &&
		coverData[0] == 0x89 &&
		coverData[1] == 0x50 &&
		coverData[2] == 0x4E &&
		coverData[3] == 0x47 &&
		coverData[4] == 0x0D &&
		coverData[5] == 0x0A &&
		coverData[6] == 0x1A &&
		coverData[7] == 0x0A {
		return "image/png"
	}
	if len(coverData) >= 3 &&
		coverData[0] == 0xFF &&
		coverData[1] == 0xD8 &&
		coverData[2] == 0xFF {
		return "image/jpeg"
	}
	if len(coverData) >= 6 {
		header := string(coverData[:6])
		if header == "GIF87a" || header == "GIF89a" {
			return "image/gif"
		}
	}
	if len(coverData) >= 12 &&
		string(coverData[:4]) == "RIFF" &&
		string(coverData[8:12]) == "WEBP" {
		return "image/webp"
	}

	switch strings.ToLower(filepath.Ext(strings.TrimSpace(coverPath))) {
	case ".png":
		return "image/png"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".webp":
		return "image/webp"
	case ".gif":
		return "image/gif"
	}

	return "image/jpeg"
}

// maxFlacPictureBytes keeps cover art below the 24-bit length field of a FLAC
// metadata block; go-flac silently truncates oversized blocks into a corrupt file.
const maxFlacPictureBytes = 16 * 1000 * 1000

// fitCoverForFlac returns cover bytes that fit inside a FLAC PICTURE block,
// re-encoding and downscaling when needed. Returns false if the data cannot be
// decoded as an image.
func fitCoverForFlac(coverData []byte) ([]byte, bool) {
	if len(coverData) <= maxFlacPictureBytes {
		return coverData, true
	}

	img, _, err := stdimage.Decode(bytes.NewReader(coverData))
	if err != nil {
		return nil, false
	}

	for _, quality := range []int{90, 80, 70, 60} {
		if encoded, ok := encodeJPEGUnder(img, quality, maxFlacPictureBytes); ok {
			return encoded, true
		}
	}

	for _, maxDim := range []int{1500, 1200, 1000, 800} {
		scaled := downscaleImage(img, maxDim)
		if encoded, ok := encodeJPEGUnder(scaled, 85, maxFlacPictureBytes); ok {
			return encoded, true
		}
	}

	return nil, false
}

func encodeJPEGUnder(img stdimage.Image, quality, limit int) ([]byte, bool) {
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: quality}); err != nil {
		return nil, false
	}
	if buf.Len() > limit {
		return nil, false
	}
	return buf.Bytes(), true
}

func downscaleImage(img stdimage.Image, maxDim int) stdimage.Image {
	bounds := img.Bounds()
	width, height := bounds.Dx(), bounds.Dy()
	if width <= maxDim && height <= maxDim {
		return img
	}

	scale := float64(maxDim) / float64(max(width, height))
	newWidth := max(1, int(float64(width)*scale))
	newHeight := max(1, int(float64(height)*scale))

	dst := stdimage.NewRGBA(stdimage.Rect(0, 0, newWidth, newHeight))
	for y := 0; y < newHeight; y++ {
		srcY := bounds.Min.Y + int(float64(y)/scale)
		for x := 0; x < newWidth; x++ {
			srcX := bounds.Min.X + int(float64(x)/scale)
			dst.Set(x, y, img.At(srcX, srcY))
		}
	}
	return dst
}

func buildPictureBlock(coverPath string, coverData []byte) (flac.MetaDataBlock, error) {
	if len(coverData) == 0 {
		return flac.MetaDataBlock{}, fmt.Errorf("empty cover data")
	}

	fitted, ok := fitCoverForFlac(coverData)
	if !ok {
		return flac.MetaDataBlock{}, fmt.Errorf("cover too large for FLAC picture block and could not be resized")
	}
	coverData = fitted

	mime := detectCoverMIME(coverPath, coverData)
	picture := &flacpicture.MetadataBlockPicture{
		PictureType: flacpicture.PictureTypeFrontCover,
		MIME:        mime,
		Description: "Front Cover",
		ImageData:   coverData,
	}

	// Width/height/depth are optional in practice; keep zero when decode fails.
	if cfg, format, err := stdimage.DecodeConfig(bytes.NewReader(coverData)); err == nil {
		picture.Width = uint32(cfg.Width)
		picture.Height = uint32(cfg.Height)
		switch format {
		case "png":
			picture.ColorDepth = 32
		case "jpeg":
			picture.ColorDepth = 24
		default:
			picture.ColorDepth = 0
		}
	}

	return picture.Marshal(), nil
}

type Metadata struct {
	Title         string
	Artist        string
	Album         string
	AlbumArtist   string
	ArtistTagMode string
	Date          string
	TrackNumber   int
	TotalTracks   int
	DiscNumber    int
	TotalDiscs    int
	ISRC          string
	Description   string
	Lyrics        string
	Genre         string
	Label         string
	Copyright     string
	Composer      string
	Comment       string

	// ReplayGain fields (stored as Vorbis Comments in FLAC)
	ReplayGainTrackGain string // e.g. "-6.50 dB"
	ReplayGainTrackPeak string // e.g. "0.988831"
	ReplayGainAlbumGain string // e.g. "-7.20 dB"
	ReplayGainAlbumPeak string // e.g. "1.000000"
}

// parseFlacFile wraps flac.ParseFile but closes the file handle when parsing
// fails. flac.ParseFile leaks the *os.File on parse errors (no reference is
// returned to close it), which on Windows keeps the file locked until GC.
// Callers must Close() the returned file when done reading; File.Save also
// closes the underlying handle, and a second Close afterwards is harmless.
func parseFlacFile(filePath string) (*flac.File, error) {
	handle, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	f, err := flac.ParseBytes(flac.NewBufIOWithInner(handle))
	if err != nil {
		handle.Close()
		return nil, err
	}
	return f, nil
}

// updateFlacVorbis parses a FLAC file, hands the parsed file and its Vorbis
// comment block (created if absent) to mutate, then marshals the block back
// into the file and saves it. Shared scaffold for all FLAC tag writers.
func updateFlacVorbis(filePath string, mutate func(f *flac.File, cmt *flacvorbis.MetaDataBlockVorbisComment) error) error {
	f, err := parseFlacFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to parse FLAC file: %w", err)
	}
	defer f.Close()

	var cmt *flacvorbis.MetaDataBlockVorbisComment
	for _, meta := range f.Meta {
		if meta.Type == flac.VorbisComment {
			cmt, err = flacvorbis.ParseFromMetaDataBlock(*meta)
			if err != nil {
				return fmt.Errorf("failed to parse vorbis comment: %w", err)
			}
			break
		}
	}
	if cmt == nil {
		cmt = flacvorbis.New()
	}

	if err := mutate(f, cmt); err != nil {
		return err
	}

	// Re-scan for the block index: mutate may have removed blocks.
	cmtBlock := cmt.Marshal()
	replaced := false
	for idx, meta := range f.Meta {
		if meta.Type == flac.VorbisComment {
			f.Meta[idx] = &cmtBlock
			replaced = true
			break
		}
	}
	if !replaced {
		f.Meta = append(f.Meta, &cmtBlock)
	}

	return saveFlacFile(f, filePath)
}

// replaceFlacPictures strips all Picture blocks and appends a new front cover
// built from coverData. On error the pictures stay removed and no cover is added.
func replaceFlacPictures(f *flac.File, coverPath string, coverData []byte) error {
	for i := len(f.Meta) - 1; i >= 0; i-- {
		if f.Meta[i].Type == flac.Picture {
			f.Meta = append(f.Meta[:i], f.Meta[i+1:]...)
		}
	}

	picBlock, err := buildPictureBlock(coverPath, coverData)
	if err != nil {
		return err
	}
	f.Meta = append(f.Meta, &picBlock)
	return nil
}

func EmbedMetadata(filePath string, metadata Metadata, coverPath string) error {
	return updateFlacVorbis(filePath, func(f *flac.File, cmt *flacvorbis.MetaDataBlockVorbisComment) error {
		writeVorbisMetadata(cmt, metadata)

		if coverPath != "" {
			if fileExists(coverPath) {
				coverData, err := os.ReadFile(coverPath)
				if err != nil {
					fmt.Printf("[Metadata] Warning: Failed to read cover file %s: %v\n", coverPath, err)
				} else if err := replaceFlacPictures(f, coverPath, coverData); err != nil {
					fmt.Printf("[Metadata] Warning: skipping cover art: %v\n", err)
				} else {
					fmt.Printf("[Metadata] Cover art embedded successfully (%d bytes)\n", len(coverData))
				}
			} else {
				fmt.Printf("[Metadata] Warning: Cover file does not exist: %s\n", coverPath)
			}
		}
		return nil
	})
}

func EmbedMetadataWithCoverData(filePath string, metadata Metadata, coverData []byte) error {
	return updateFlacVorbis(filePath, func(f *flac.File, cmt *flacvorbis.MetaDataBlockVorbisComment) error {
		writeVorbisMetadata(cmt, metadata)

		if len(coverData) > 0 {
			if err := replaceFlacPictures(f, "", coverData); err != nil {
				fmt.Printf("[Metadata] Warning: skipping cover art: %v\n", err)
			} else {
				fmt.Printf("[Metadata] Cover art embedded successfully (%d bytes)\n", len(coverData))
			}
		}
		return nil
	})
}

func ReadMetadata(filePath string) (*Metadata, error) {
	f, err := parseFlacFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to parse FLAC file: %w", err)
	}
	defer f.Close()
	return metadataFromParsedFlac(f), nil
}

func metadataFromParsedFlac(f *flac.File) *Metadata {
	metadata := &Metadata{}

	for _, meta := range f.Meta {
		if meta.Type == flac.VorbisComment {
			cmt, err := flacvorbis.ParseFromMetaDataBlock(*meta)
			if err != nil {
				continue
			}

			metadata.Title = getComment(cmt, "TITLE")
			metadata.Artist = getJoinedComment(cmt, "ARTIST")
			metadata.Album = getComment(cmt, "ALBUM")
			metadata.AlbumArtist = getJoinedComment(cmt, "ALBUMARTIST")
			if metadata.AlbumArtist == "" {
				metadata.AlbumArtist = getJoinedComment(cmt, "ALBUM ARTIST")
			}
			if metadata.AlbumArtist == "" {
				metadata.AlbumArtist = getJoinedComment(cmt, "ALBUM_ARTIST")
			}
			metadata.Date = getComment(cmt, "DATE")
			metadata.ISRC = getComment(cmt, "ISRC")
			metadata.Description = getComment(cmt, "DESCRIPTION")

			metadata.Lyrics = getComment(cmt, "LYRICS")
			if metadata.Lyrics == "" {
				metadata.Lyrics = getComment(cmt, "UNSYNCEDLYRICS")
			}

			trackNum := getComment(cmt, "TRACKNUMBER")
			if trackNum != "" {
				metadata.TrackNumber, metadata.TotalTracks = parseIndexPair(trackNum)
			}
			if metadata.TrackNumber == 0 {
				trackNum = getComment(cmt, "TRACK")
				if trackNum != "" {
					metadata.TrackNumber, metadata.TotalTracks = parseIndexPair(trackNum)
				}
			}

			discNum := getComment(cmt, "DISCNUMBER")
			if discNum != "" {
				metadata.DiscNumber, metadata.TotalDiscs = parseIndexPair(discNum)
			}
			if metadata.DiscNumber == 0 {
				discNum = getComment(cmt, "DISC")
				if discNum != "" {
					metadata.DiscNumber, metadata.TotalDiscs = parseIndexPair(discNum)
				}
			}

			if metadata.Date == "" {
				metadata.Date = getComment(cmt, "YEAR")
			}

			metadata.Genre = getComment(cmt, "GENRE")
			metadata.Label = getComment(cmt, "ORGANIZATION")
			if metadata.Label == "" {
				metadata.Label = getComment(cmt, "LABEL")
			}
			if metadata.Label == "" {
				metadata.Label = getComment(cmt, "PUBLISHER")
			}
			metadata.Copyright = getComment(cmt, "COPYRIGHT")
			metadata.Composer = getComment(cmt, "COMPOSER")
			metadata.Comment = getComment(cmt, "COMMENT")

			metadata.ReplayGainTrackGain = getComment(cmt, "REPLAYGAIN_TRACK_GAIN")
			metadata.ReplayGainTrackPeak = getComment(cmt, "REPLAYGAIN_TRACK_PEAK")
			metadata.ReplayGainAlbumGain = getComment(cmt, "REPLAYGAIN_ALBUM_GAIN")
			metadata.ReplayGainAlbumPeak = getComment(cmt, "REPLAYGAIN_ALBUM_PEAK")

			break
		}
	}

	return metadata
}

// EditFlacFields opens a FLAC file and updates only the Vorbis Comment keys
// that are explicitly present in the fields map.  Keys present with a non-empty
// value are set; keys present with an empty value are removed (cleared).  Keys
// absent from the map are left untouched.  This is the correct function for
// partial edits (e.g. writing only ReplayGain tags) and full editor saves alike.
func EditFlacFields(filePath string, fields map[string]string) error {
	return updateFlacVorbis(filePath, func(f *flac.File, cmt *flacvorbis.MetaDataBlockVorbisComment) error {
		applyVorbisFieldEdits(cmt, fields)

		coverPath := strings.TrimSpace(fields["cover_path"])
		if coverPath != "" && fileExists(coverPath) {
			if coverData, err := os.ReadFile(coverPath); err == nil && len(coverData) > 0 {
				_ = replaceFlacPictures(f, "", coverData)
			}
		}
		return nil
	})
}

// applyVorbisFieldEdits applies the editor's set-or-clear field semantics to a
// Vorbis comment block. Shared by the FLAC and Ogg/Opus editors so both
// formats interpret the fields map identically.
func applyVorbisFieldEdits(cmt *flacvorbis.MetaDataBlockVorbisComment, fields map[string]string) {
	artistMode := fields["artist_tag_mode"]

	// Mapping from fields-map key → one or more Vorbis Comment keys.
	// Each entry is handled with set-or-clear semantics.
	simpleKeys := map[string]string{
		"title":                 "TITLE",
		"album":                 "ALBUM",
		"date":                  "DATE",
		"isrc":                  "ISRC",
		"genre":                 "GENRE",
		"label":                 "ORGANIZATION",
		"copyright":             "COPYRIGHT",
		"composer":              "COMPOSER",
		"comment":               "COMMENT",
		"replaygain_track_gain": "REPLAYGAIN_TRACK_GAIN",
		"replaygain_track_peak": "REPLAYGAIN_TRACK_PEAK",
		"replaygain_album_gain": "REPLAYGAIN_ALBUM_GAIN",
		"replaygain_album_peak": "REPLAYGAIN_ALBUM_PEAK",
	}

	for fieldKey, vorbisKey := range simpleKeys {
		if v, ok := fields[fieldKey]; ok {
			setOrClearComment(cmt, vorbisKey, v)
		}
	}

	// Remove known aliases for fields that were just written/cleared, so that
	// tags from other taggers (e.g. LABEL, PUBLISHER, ALBUM ARTIST) don't
	// conflict with the canonical keys we use.
	aliasCleanup := map[string][]string{
		"label":     {"LABEL", "PUBLISHER"}, // canonical: ORGANIZATION
		"date":      {"YEAR"},               // canonical: DATE
		"genre":     {},                     // no common aliases
		"copyright": {},
	}
	for fieldKey, aliases := range aliasCleanup {
		if _, ok := fields[fieldKey]; ok {
			for _, alias := range aliases {
				removeCommentKey(cmt, alias)
			}
		}
	}

	// Artist fields: use split-artist logic when mode is set.
	if v, ok := fields["artist"]; ok {
		setOrClearArtistComments(cmt, "ARTIST", v, artistMode)
	}
	if v, ok := fields["album_artist"]; ok {
		setOrClearArtistComments(cmt, "ALBUMARTIST", v, artistMode)
		// Remove aliases from other taggers.
		removeCommentKey(cmt, "ALBUM ARTIST")
		removeCommentKey(cmt, "ALBUM_ARTIST")
	}

	// Track/disc numbers: present + empty → clear; when only totals are edited,
	// preserve the current index number and rewrite the combined value.
	if _, ok := fields["track_number"]; ok || fields["track_total"] != "" || hasMapKey(fields, "track_total") {
		currentTrackNum, currentTotalTracks := parseIndexPair(getComment(cmt, "TRACKNUMBER"))
		if currentTrackNum == 0 && currentTotalTracks == 0 {
			currentTrackNum, currentTotalTracks = parseIndexPair(getComment(cmt, "TRACK"))
		}
		if v, ok := fields["track_number"]; ok {
			currentTrackNum = parsePositiveInt(v)
		}
		if v, ok := fields["track_total"]; ok {
			currentTotalTracks = parsePositiveInt(v)
		}
		if currentTrackNum > 0 {
			setOrClearComment(cmt, "TRACKNUMBER", formatIndexValue(currentTrackNum, currentTotalTracks))
		} else {
			removeCommentKey(cmt, "TRACKNUMBER")
		}
		removeCommentKey(cmt, "TRACK") // alias
	}
	if _, ok := fields["disc_number"]; ok || fields["disc_total"] != "" || hasMapKey(fields, "disc_total") {
		currentDiscNum, currentTotalDiscs := parseIndexPair(getComment(cmt, "DISCNUMBER"))
		if currentDiscNum == 0 && currentTotalDiscs == 0 {
			currentDiscNum, currentTotalDiscs = parseIndexPair(getComment(cmt, "DISC"))
		}
		if v, ok := fields["disc_number"]; ok {
			currentDiscNum = parsePositiveInt(v)
		}
		if v, ok := fields["disc_total"]; ok {
			currentTotalDiscs = parsePositiveInt(v)
		}
		if currentDiscNum > 0 {
			setOrClearComment(cmt, "DISCNUMBER", formatIndexValue(currentDiscNum, currentTotalDiscs))
		} else {
			removeCommentKey(cmt, "DISCNUMBER")
		}
		removeCommentKey(cmt, "DISC") // alias
	}

	// Lyrics: set both LYRICS + UNSYNCEDLYRICS, or clear both.
	if v, ok := fields["lyrics"]; ok {
		if v != "" {
			setOrClearComment(cmt, "LYRICS", v)
			setOrClearComment(cmt, "UNSYNCEDLYRICS", v)
		} else {
			removeCommentKey(cmt, "LYRICS")
			removeCommentKey(cmt, "UNSYNCEDLYRICS")
		}
	}
}

// writeVorbisMetadata writes all metadata fields to a Vorbis Comment block.
// Empty/zero values are simply skipped (not written, not cleared).  This is
// used by the download embedding path where absent fields should preserve any
// existing values.  The editor path uses EditFlacFields() instead.
func writeVorbisMetadata(cmt *flacvorbis.MetaDataBlockVorbisComment, metadata Metadata) {
	setComment(cmt, "TITLE", metadata.Title)
	setArtistComments(cmt, "ARTIST", metadata.Artist, metadata.ArtistTagMode)
	setComment(cmt, "ALBUM", metadata.Album)
	setArtistComments(cmt, "ALBUMARTIST", metadata.AlbumArtist, metadata.ArtistTagMode)
	setComment(cmt, "DATE", metadata.Date)

	if metadata.TrackNumber > 0 {
		setComment(cmt, "TRACKNUMBER", formatIndexValue(metadata.TrackNumber, metadata.TotalTracks))
	}

	if metadata.DiscNumber > 0 {
		setComment(cmt, "DISCNUMBER", formatIndexValue(metadata.DiscNumber, metadata.TotalDiscs))
	}

	if metadata.ISRC != "" {
		setComment(cmt, "ISRC", metadata.ISRC)
	}

	if metadata.Description != "" {
		setComment(cmt, "DESCRIPTION", metadata.Description)
	}

	if metadata.Lyrics != "" {
		setComment(cmt, "LYRICS", metadata.Lyrics)
		setComment(cmt, "UNSYNCEDLYRICS", metadata.Lyrics)
	}

	if metadata.Genre != "" {
		setComment(cmt, "GENRE", metadata.Genre)
	}

	if metadata.Label != "" {
		setComment(cmt, "ORGANIZATION", metadata.Label)
	}

	if metadata.Copyright != "" {
		setComment(cmt, "COPYRIGHT", metadata.Copyright)
	}

	if metadata.Composer != "" {
		setComment(cmt, "COMPOSER", metadata.Composer)
	}

	if metadata.Comment != "" {
		setComment(cmt, "COMMENT", metadata.Comment)
	}

	setComment(cmt, "REPLAYGAIN_TRACK_GAIN", metadata.ReplayGainTrackGain)
	setComment(cmt, "REPLAYGAIN_TRACK_PEAK", metadata.ReplayGainTrackPeak)
	setComment(cmt, "REPLAYGAIN_ALBUM_GAIN", metadata.ReplayGainAlbumGain)
	setComment(cmt, "REPLAYGAIN_ALBUM_PEAK", metadata.ReplayGainAlbumPeak)
}

func setComment(cmt *flacvorbis.MetaDataBlockVorbisComment, key, value string) {
	if value == "" {
		return
	}
	removeCommentKey(cmt, key)
	cmt.Comments = append(cmt.Comments, key+"="+value)
}

// setOrClearComment writes a Vorbis Comment, or removes the key if value is
// empty.  Used by the metadata editor path where empty means "delete this tag".
func setOrClearComment(cmt *flacvorbis.MetaDataBlockVorbisComment, key, value string) {
	if value == "" {
		removeCommentKey(cmt, key)
		return
	}
	removeCommentKey(cmt, key)
	cmt.Comments = append(cmt.Comments, key+"="+value)
}

func setArtistComments(cmt *flacvorbis.MetaDataBlockVorbisComment, key, value, mode string) {
	if value == "" {
		return
	}
	values := []string{value}
	if shouldSplitVorbisArtistTags(mode) {
		values = splitArtistTagValues(value)
	}
	if len(values) == 0 {
		return
	}
	removeCommentKey(cmt, key)
	for _, artist := range values {
		if strings.TrimSpace(artist) == "" {
			continue
		}
		cmt.Comments = append(cmt.Comments, key+"="+artist)
	}
}

// setOrClearArtistComments writes artist Vorbis Comments, or removes the key
// if value is empty.  Used by the metadata editor path.
func setOrClearArtistComments(cmt *flacvorbis.MetaDataBlockVorbisComment, key, value, mode string) {
	if value == "" {
		removeCommentKey(cmt, key)
		return
	}
	values := []string{value}
	if shouldSplitVorbisArtistTags(mode) {
		values = splitArtistTagValues(value)
	}
	if len(values) == 0 {
		removeCommentKey(cmt, key)
		return
	}
	removeCommentKey(cmt, key)
	for _, artist := range values {
		if strings.TrimSpace(artist) == "" {
			continue
		}
		cmt.Comments = append(cmt.Comments, key+"="+artist)
	}
}

// RewriteSplitArtistTags opens a FLAC file and rewrites the ARTIST and
// ALBUMARTIST Vorbis comments as multiple separate entries (one per artist).
// This is needed because FFmpeg's -metadata flag deduplicates keys, so only
// the last value survives when multiple -metadata ARTIST=X flags are used.
// The native go-flac writer correctly handles multiple Vorbis comments.
func RewriteSplitArtistTags(filePath, artist, albumArtist string) error {
	return updateFlacVorbis(filePath, func(_ *flac.File, cmt *flacvorbis.MetaDataBlockVorbisComment) error {
		setArtistComments(cmt, "ARTIST", artist, artistTagModeSplitVorbis)
		setArtistComments(cmt, "ALBUMARTIST", albumArtist, artistTagModeSplitVorbis)
		return nil
	})
}

func removeCommentKey(cmt *flacvorbis.MetaDataBlockVorbisComment, key string) {
	keyUpper := strings.ToUpper(key)
	for i := len(cmt.Comments) - 1; i >= 0; i-- {
		comment := cmt.Comments[i]
		eqIdx := strings.Index(comment, "=")
		if eqIdx > 0 {
			existingKey := strings.ToUpper(comment[:eqIdx])
			if existingKey == keyUpper {
				cmt.Comments = append(cmt.Comments[:i], cmt.Comments[i+1:]...)
			}
		}
	}
}

func getComment(cmt *flacvorbis.MetaDataBlockVorbisComment, key string) string {
	values := getCommentValues(cmt, key)
	if len(values) == 0 {
		return ""
	}
	return values[0]
}

func getJoinedComment(cmt *flacvorbis.MetaDataBlockVorbisComment, key string) string {
	return joinVorbisCommentValues(getCommentValues(cmt, key))
}

func getCommentValues(cmt *flacvorbis.MetaDataBlockVorbisComment, key string) []string {
	keyUpper := strings.ToUpper(key) + "="
	values := make([]string, 0, 1)
	for _, comment := range cmt.Comments {
		if len(comment) > len(key) {
			commentUpper := strings.ToUpper(comment[:len(key)+1])
			if commentUpper == keyUpper {
				values = append(values, comment[len(key)+1:])
			}
		}
	}
	return values
}

func shouldSplitVorbisArtistTags(mode string) bool {
	return strings.EqualFold(strings.TrimSpace(mode), artistTagModeSplitVorbis)
}

func splitArtistTagValues(rawArtists string) []string {
	trimmed := strings.TrimSpace(rawArtists)
	if trimmed == "" {
		return nil
	}

	parts := artistTagSplitPattern.Split(trimmed, -1)
	values := make([]string, 0, len(parts))
	seen := make(map[string]struct{}, len(parts))
	for _, part := range parts {
		artist := strings.TrimSpace(part)
		if artist == "" {
			continue
		}
		key := strings.ToLower(artist)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		values = append(values, artist)
	}
	if len(values) > 0 {
		return values
	}
	return []string{trimmed}
}

func joinVorbisCommentValues(values []string) string {
	if len(values) == 0 {
		return ""
	}

	joined := make([]string, 0, len(values))
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		key := strings.ToLower(trimmed)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		joined = append(joined, trimmed)
	}
	return strings.Join(joined, ", ")
}

func fileExists(path string) bool {
	return CheckFileExists(path)
}

func ExtractCoverArt(filePath string) ([]byte, error) {
	f, err := parseFlacFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to parse FLAC file: %w", err)
	}
	defer f.Close()
	return coverArtFromParsedFlac(f)
}

func coverArtFromParsedFlac(f *flac.File) ([]byte, error) {
	for _, meta := range f.Meta {
		if meta.Type == flac.Picture {
			pic, err := flacpicture.ParseFromMetaDataBlock(*meta)
			if err != nil {
				continue
			}
			if pic.PictureType == flacpicture.PictureTypeFrontCover && len(pic.ImageData) > 0 {
				return pic.ImageData, nil
			}
		}
	}

	for _, meta := range f.Meta {
		if meta.Type == flac.Picture {
			pic, err := flacpicture.ParseFromMetaDataBlock(*meta)
			if err != nil {
				continue
			}
			if len(pic.ImageData) > 0 {
				return pic.ImageData, nil
			}
		}
	}

	return nil, fmt.Errorf("no cover art found in file")
}

func EmbedLyrics(filePath string, lyrics string) error {
	return updateFlacVorbis(filePath, func(_ *flac.File, cmt *flacvorbis.MetaDataBlockVorbisComment) error {
		setComment(cmt, "LYRICS", lyrics)
		setComment(cmt, "UNSYNCEDLYRICS", lyrics)
		return nil
	})
}

func ExtractLyrics(filePath string) (string, error) {
	lower := strings.ToLower(filePath)

	if strings.HasSuffix(lower, ".flac") {
		lyrics, err := extractLyricsFromFlac(filePath)
		if err == nil && strings.TrimSpace(lyrics) != "" {
			return lyrics, nil
		}
		return extractLyricsFromSidecarLRC(filePath)
	}

	if strings.HasSuffix(lower, ".m4a") || strings.HasSuffix(lower, ".mp4") || strings.HasSuffix(lower, ".aac") {
		lyrics, err := extractLyricsFromM4A(filePath)
		if err == nil && strings.TrimSpace(lyrics) != "" {
			return lyrics, nil
		}
		return extractLyricsFromSidecarLRC(filePath)
	}

	if strings.HasSuffix(lower, ".mp3") {
		meta, err := ReadID3Tags(filePath)
		if err == nil && meta != nil {
			if strings.TrimSpace(meta.Lyrics) != "" {
				return meta.Lyrics, nil
			}
			if looksLikeEmbeddedLyrics(meta.Comment) {
				return meta.Comment, nil
			}
		}
		return extractLyricsFromSidecarLRC(filePath)
	}

	if strings.HasSuffix(lower, ".opus") || strings.HasSuffix(lower, ".ogg") {
		meta, err := ReadOggVorbisComments(filePath)
		if err == nil && meta != nil {
			if strings.TrimSpace(meta.Lyrics) != "" {
				return meta.Lyrics, nil
			}
			if looksLikeEmbeddedLyrics(meta.Comment) {
				return meta.Comment, nil
			}
		}
		return extractLyricsFromSidecarLRC(filePath)
	}

	if strings.HasSuffix(lower, ".wav") {
		meta, err := ReadWAVTags(filePath)
		if err == nil && meta != nil {
			if strings.TrimSpace(meta.Lyrics) != "" {
				return meta.Lyrics, nil
			}
			if looksLikeEmbeddedLyrics(meta.Comment) {
				return meta.Comment, nil
			}
		}
		return extractLyricsFromSidecarLRC(filePath)
	}

	if strings.HasSuffix(lower, ".aiff") || strings.HasSuffix(lower, ".aif") || strings.HasSuffix(lower, ".aifc") {
		meta, err := ReadAIFFTags(filePath)
		if err == nil && meta != nil {
			if strings.TrimSpace(meta.Lyrics) != "" {
				return meta.Lyrics, nil
			}
			if looksLikeEmbeddedLyrics(meta.Comment) {
				return meta.Comment, nil
			}
		}
		return extractLyricsFromSidecarLRC(filePath)
	}

	return extractLyricsFromSidecarLRC(filePath)
}

func extractLyricsFromSidecarLRC(filePath string) (string, error) {
	ext := filepath.Ext(filePath)
	base := strings.TrimSuffix(filePath, ext)
	if strings.TrimSpace(base) == "" {
		return "", fmt.Errorf("no lyrics found in file")
	}

	lrcPath := base + ".lrc"
	data, err := os.ReadFile(lrcPath)
	if err != nil {
		return "", fmt.Errorf("no lyrics found in file")
	}

	lyrics := strings.TrimSpace(string(data))
	if lyrics == "" {
		return "", fmt.Errorf("no lyrics found in file")
	}
	return lyrics, nil
}

func extractLyricsFromFlac(filePath string) (string, error) {
	f, err := parseFlacFile(filePath)
	if err != nil {
		return "", fmt.Errorf("failed to parse FLAC file: %w", err)
	}
	defer f.Close()

	for _, meta := range f.Meta {
		if meta.Type != flac.VorbisComment {
			continue
		}

		cmt, err := flacvorbis.ParseFromMetaDataBlock(*meta)
		if err != nil {
			continue
		}

		lyrics, err := cmt.Get("LYRICS")
		if err == nil && len(lyrics) > 0 && strings.TrimSpace(lyrics[0]) != "" {
			return lyrics[0], nil
		}

		lyrics, err = cmt.Get("UNSYNCEDLYRICS")
		if err == nil && len(lyrics) > 0 && strings.TrimSpace(lyrics[0]) != "" {
			return lyrics[0], nil
		}
	}

	return "", fmt.Errorf("no lyrics found in file")
}

func looksLikeEmbeddedLyrics(value string) bool {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return false
	}

	lower := strings.ToLower(trimmed)
	if strings.Contains(lower, "[ar:") || strings.Contains(lower, "[ti:") {
		return true
	}

	if strings.Contains(trimmed, "\n") && strings.Contains(trimmed, "[") && strings.Contains(trimmed, "]") {
		return true
	}

	return false
}

type AudioQuality struct {
	BitDepth     int    `json:"bit_depth"`
	SampleRate   int    `json:"sample_rate"`
	TotalSamples int64  `json:"total_samples"`
	Duration     int    `json:"duration"`
	Bitrate      int    `json:"bitrate,omitempty"` // kbps, estimated for compressed MP4-family streams
	Codec        string `json:"codec,omitempty"`
}

func flacAudioQualityFromStreamInfo(streamInfo []byte) AudioQuality {
	bitDepth, sampleRate, totalSamples := parseFLACStreamInfoQuality(streamInfo)
	duration := 0
	if sampleRate > 0 && totalSamples > 0 {
		duration = int(totalSamples / int64(sampleRate))
	}
	return AudioQuality{
		BitDepth:     bitDepth,
		SampleRate:   sampleRate,
		TotalSamples: totalSamples,
		Duration:     duration,
		Codec:        "flac",
	}
}

func audioQualityFromParsedFlac(f *flac.File) (AudioQuality, error) {
	for _, meta := range f.Meta {
		if meta.Type != flac.StreamInfo || len(meta.Data) < 18 {
			continue
		}
		return flacAudioQualityFromStreamInfo(meta.Data), nil
	}
	return AudioQuality{}, fmt.Errorf("FLAC STREAMINFO block not found")
}

func GetAudioQuality(filePath string) (AudioQuality, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return AudioQuality{}, fmt.Errorf("failed to open file: %w", err)
	}
	defer file.Close()

	marker := make([]byte, 4)
	if _, err := file.Read(marker); err != nil {
		return AudioQuality{}, fmt.Errorf("failed to read marker: %w", err)
	}

	if string(marker) == "fLaC" {
		header := make([]byte, 4)
		if _, err := file.Read(header); err != nil {
			return AudioQuality{}, fmt.Errorf("failed to read header: %w", err)
		}

		blockType := header[0] & 0x7F
		if blockType != 0 {
			return AudioQuality{}, fmt.Errorf("first block is not STREAMINFO")
		}

		streamInfo := make([]byte, 34)
		if _, err := file.Read(streamInfo); err != nil {
			return AudioQuality{}, fmt.Errorf("failed to read STREAMINFO: %w", err)
		}

		return flacAudioQualityFromStreamInfo(streamInfo), nil
	}

	file.Seek(0, 0)
	header8 := make([]byte, 8)
	if _, err := file.Read(header8); err != nil {
		return AudioQuality{}, fmt.Errorf("failed to read header: %w", err)
	}

	if string(header8[4:8]) == "ftyp" {
		file.Close()
		return GetM4AQuality(filePath)
	}

	return AudioQuality{}, fmt.Errorf("unsupported file format (not FLAC or M4A)")
}
