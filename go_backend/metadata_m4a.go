package gobackend

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"math"
	"os"
	"regexp"
	"strconv"
	"strings"
)

func ReadM4ATags(filePath string) (*AudioMetadata, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	fi, err := f.Stat()
	if err != nil {
		return nil, err
	}

	ilst, err := findM4AIlstAtom(f, fi.Size())
	if err != nil {
		return nil, err
	}
	return readM4ATagsFromIlst(f, fi.Size(), ilst)
}

func readM4ATagsFromIlst(f *os.File, fileSize int64, ilst atomHeader) (*AudioMetadata, error) {
	metadata := &AudioMetadata{}
	start := ilst.offset + ilst.headerSize
	end := ilst.offset + ilst.size
	for pos := start; pos+8 <= end; {
		header, err := readAtomHeaderAt(f, pos, fileSize)
		if err != nil {
			return nil, err
		}
		if header.size == 0 {
			header.size = end - pos
		}
		if header.size < header.headerSize {
			return nil, fmt.Errorf("invalid atom size for %s", header.typ)
		}

		switch header.typ {
		case "\xa9nam":
			metadata.Title, _ = readM4ATextValue(f, header, fileSize)
		case "\xa9ART":
			metadata.Artist, _ = readM4ATextValue(f, header, fileSize)
		case "\xa9alb":
			metadata.Album, _ = readM4ATextValue(f, header, fileSize)
		case "aART":
			metadata.AlbumArtist, _ = readM4ATextValue(f, header, fileSize)
		case "\xa9day":
			metadata.Date, _ = readM4ATextValue(f, header, fileSize)
			metadata.Year = metadata.Date
		case "\xa9gen":
			metadata.Genre, _ = readM4ATextValue(f, header, fileSize)
		case "\xa9wrt":
			metadata.Composer, _ = readM4ATextValue(f, header, fileSize)
		case "\xa9cmt":
			metadata.Comment, _ = readM4ATextValue(f, header, fileSize)
		case "cprt":
			metadata.Copyright, _ = readM4ATextValue(f, header, fileSize)
		case "\xa9lyr":
			metadata.Lyrics, _ = readM4ATextValue(f, header, fileSize)
		case "trkn":
			metadata.TrackNumber, metadata.TotalTracks, _ = readM4AIndexPair(f, header, fileSize)
		case "disk":
			metadata.DiscNumber, metadata.TotalDiscs, _ = readM4AIndexPair(f, header, fileSize)
		case "----":
			name, value, freeformErr := readM4AFreeformValue(f, header, fileSize)
			if freeformErr == nil {
				switch strings.ToUpper(strings.TrimSpace(name)) {
				case "ISRC":
					metadata.ISRC = value
				case "LABEL", "ORGANIZATION":
					metadata.Label = value
				case "COMMENT":
					if metadata.Comment == "" {
						metadata.Comment = value
					}
				case "COMPOSER":
					if metadata.Composer == "" {
						metadata.Composer = value
					}
				case "COPYRIGHT":
					if metadata.Copyright == "" {
						metadata.Copyright = value
					}
				case "LYRICS", "UNSYNCEDLYRICS":
					if metadata.Lyrics == "" {
						metadata.Lyrics = value
					}
				case "REPLAYGAIN_TRACK_GAIN":
					metadata.ReplayGainTrackGain = value
				case "REPLAYGAIN_TRACK_PEAK":
					metadata.ReplayGainTrackPeak = value
				case "REPLAYGAIN_ALBUM_GAIN":
					metadata.ReplayGainAlbumGain = value
				case "REPLAYGAIN_ALBUM_PEAK":
					metadata.ReplayGainAlbumPeak = value
				}
			}
		}

		pos += header.size
	}

	if metadata.Title == "" &&
		metadata.Artist == "" &&
		metadata.Album == "" &&
		metadata.AlbumArtist == "" &&
		metadata.Lyrics == "" &&
		metadata.TrackNumber == 0 &&
		metadata.DiscNumber == 0 {
		return nil, fmt.Errorf("no M4A tags found")
	}

	return metadata, nil
}

func extractLyricsFromM4A(filePath string) (string, error) {
	metadata, err := ReadM4ATags(filePath)
	if err != nil {
		return "", err
	}
	if metadata == nil || strings.TrimSpace(metadata.Lyrics) == "" {
		return "", fmt.Errorf("no lyrics found in file")
	}
	return metadata.Lyrics, nil
}

func extractCoverFromM4A(filePath string) ([]byte, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	fi, err := f.Stat()
	if err != nil {
		return nil, err
	}
	fileSize := fi.Size()

	ilst, err := findM4AIlstAtom(f, fileSize)
	if err != nil {
		return nil, err
	}
	return extractCoverFromM4AIlst(f, fileSize, ilst)
}

func extractCoverFromM4AIlst(f *os.File, fileSize int64, ilst atomHeader) ([]byte, error) {
	bodyStart := ilst.offset + ilst.headerSize
	bodySize := ilst.size - ilst.headerSize

	covr, found, err := findAtomInRange(f, bodyStart, bodySize, "covr", fileSize)
	if err != nil || !found {
		return nil, fmt.Errorf("cover atom not found")
	}

	dataStart := covr.offset + covr.headerSize
	dataSize := covr.size - covr.headerSize

	dataAtom, found, err := findAtomInRange(f, dataStart, dataSize, "data", fileSize)
	if err != nil || !found {
		return nil, fmt.Errorf("data atom not found in cover")
	}

	// data atom: header + 4 bytes type indicator + 4 bytes locale
	imgStart := dataAtom.offset + dataAtom.headerSize + 8
	imgLen := dataAtom.size - dataAtom.headerSize - 8
	if imgLen <= 0 {
		return nil, fmt.Errorf("empty cover data")
	}

	buf := make([]byte, imgLen)
	if _, err := f.ReadAt(buf, imgStart); err != nil {
		return nil, err
	}

	return buf, nil
}

// findM4AIlstAtom locates the ilst atom that holds all iTunes-style tags.
// It tries two common layouts:
//  1. moov > udta > meta > ilst  (iTunes, FFmpeg default)
//  2. moov > meta > ilst         (some encoders omit the udta wrapper)
func findM4AIlstAtom(f *os.File, fileSize int64) (atomHeader, error) {
	moov, found, err := findAtomInRange(f, 0, fileSize, "moov", fileSize)
	if err != nil || !found {
		return atomHeader{}, fmt.Errorf("moov not found")
	}

	moovBodyStart := moov.offset + moov.headerSize
	moovBodySize := moov.size - moov.headerSize

	// Path 1: moov > udta > meta > ilst
	if udta, ok, _ := findAtomInRange(f, moovBodyStart, moovBodySize, "udta", fileSize); ok {
		udtaBodyStart := udta.offset + udta.headerSize
		udtaBodySize := udta.size - udta.headerSize
		if meta, ok2, _ := findAtomInRange(f, udtaBodyStart, udtaBodySize, "meta", fileSize); ok2 {
			if ilst, ok3 := findIlstInMeta(f, meta, fileSize); ok3 {
				return ilst, nil
			}
		}
	}

	// Path 2: moov > meta > ilst (no udta wrapper)
	if meta, ok, _ := findAtomInRange(f, moovBodyStart, moovBodySize, "meta", fileSize); ok {
		if ilst, ok2 := findIlstInMeta(f, meta, fileSize); ok2 {
			return ilst, nil
		}
	}

	return atomHeader{}, fmt.Errorf("ilst not found (tried moov>udta>meta>ilst and moov>meta>ilst)")
}

// findIlstInMeta locates the ilst atom inside a meta atom, handling both
// layouts: ISO-BMFF (4-byte version/flags before the child atoms, written by
// FFmpeg's mp4 muxer) and QuickTime (no version/flags, written by the mov muxer
// used for AC-4 passthrough).
func findIlstInMeta(f *os.File, meta atomHeader, fileSize int64) (atomHeader, bool) {
	// ISO-BMFF: skip the 4-byte version/flags that precede the child atoms.
	isoStart := meta.offset + meta.headerSize + 4
	isoSize := meta.size - meta.headerSize - 4
	if ilst, ok, _ := findAtomInRange(f, isoStart, isoSize, "ilst", fileSize); ok {
		return ilst, true
	}
	// QuickTime: child atoms begin immediately after the meta header.
	qtStart := meta.offset + meta.headerSize
	qtSize := meta.size - meta.headerSize
	if ilst, ok, _ := findAtomInRange(f, qtStart, qtSize, "ilst", fileSize); ok {
		return ilst, true
	}
	return atomHeader{}, false
}

func readM4ADataAtomPayload(f *os.File, dataAtom atomHeader) ([]byte, error) {
	payloadStart := dataAtom.offset + dataAtom.headerSize + 8
	payloadLen := dataAtom.size - dataAtom.headerSize - 8
	if payloadLen <= 0 {
		return nil, fmt.Errorf("empty data atom in %s", dataAtom.typ)
	}

	buf := make([]byte, payloadLen)
	if _, err := f.ReadAt(buf, payloadStart); err != nil {
		return nil, err
	}
	return buf, nil
}

func readM4ADataPayload(f *os.File, parent atomHeader, fileSize int64) ([]byte, error) {
	dataStart := parent.offset + parent.headerSize
	dataSize := parent.size - parent.headerSize

	dataAtom, found, err := findAtomInRange(f, dataStart, dataSize, "data", fileSize)
	if err != nil || !found {
		return nil, fmt.Errorf("data atom not found in %s", parent.typ)
	}
	return readM4ADataAtomPayload(f, dataAtom)
}

func readM4ATextValue(f *os.File, parent atomHeader, fileSize int64) (string, error) {
	payload, err := readM4ADataPayload(f, parent, fileSize)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(strings.TrimRight(string(payload), "\x00")), nil
}

func readM4AIndexPair(f *os.File, parent atomHeader, fileSize int64) (int, int, error) {
	payload, err := readM4ADataPayload(f, parent, fileSize)
	if err != nil {
		return 0, 0, err
	}
	if len(payload) < 6 {
		return 0, 0, fmt.Errorf("index payload too short in %s", parent.typ)
	}
	return int(binary.BigEndian.Uint16(payload[2:4])), int(binary.BigEndian.Uint16(payload[4:6])), nil
}

func parsePositiveInt(value string) int {
	value = strings.TrimSpace(value)
	if value == "" {
		return 0
	}
	n, _ := strconv.Atoi(value)
	return n
}

func formatIndexValue(number, total int) string {
	if number <= 0 {
		return ""
	}
	if total > 0 {
		return fmt.Sprintf("%d/%d", number, total)
	}
	return strconv.Itoa(number)
}

func hasMapKey(fields map[string]string, key string) bool {
	_, ok := fields[key]
	return ok
}

func readM4AFreeformValue(f *os.File, parent atomHeader, fileSize int64) (string, string, error) {
	start := parent.offset + parent.headerSize
	end := parent.offset + parent.size

	var nameValue string
	var dataValue string
	for pos := start; pos+8 <= end; {
		header, err := readAtomHeaderAt(f, pos, fileSize)
		if err != nil {
			return "", "", err
		}
		if header.size == 0 {
			header.size = end - pos
		}
		if header.size < header.headerSize {
			return "", "", fmt.Errorf("invalid atom size for %s", header.typ)
		}

		switch header.typ {
		case "mean":
			// Domain qualifier (e.g. "com.apple.iTunes") — not needed, skip.
		case "name":
			// The "name" atom payload is: 4-byte version/flags, then raw UTF-8 text.
			// It does NOT contain a nested "data" atom, so read the payload directly.
			payloadStart := header.offset + header.headerSize + 4
			payloadLen := header.size - header.headerSize - 4
			if payloadLen > 0 {
				buf := make([]byte, payloadLen)
				if _, readErr := f.ReadAt(buf, payloadStart); readErr == nil {
					nameValue = strings.TrimSpace(strings.TrimRight(string(buf), "\x00"))
				}
			}
		case "data":
			payload, payloadErr := readM4ADataAtomPayload(f, header)
			if payloadErr == nil {
				dataValue = strings.TrimSpace(strings.TrimRight(string(payload), "\x00"))
			}
		}

		pos += header.size
	}

	if nameValue == "" || dataValue == "" {
		return "", "", fmt.Errorf("freeform M4A tag incomplete")
	}

	return nameValue, dataValue, nil
}

type m4aMetadataPath struct {
	moov atomHeader
	udta *atomHeader
	meta atomHeader
	ilst atomHeader
}

func findM4AMetadataPath(f *os.File, fileSize int64) (m4aMetadataPath, error) {
	moov, found, err := findAtomInRange(f, 0, fileSize, "moov", fileSize)
	if err != nil || !found {
		return m4aMetadataPath{}, fmt.Errorf("moov not found")
	}

	moovBodyStart := moov.offset + moov.headerSize
	moovBodySize := moov.size - moov.headerSize

	if udta, ok, _ := findAtomInRange(f, moovBodyStart, moovBodySize, "udta", fileSize); ok {
		udtaBodyStart := udta.offset + udta.headerSize
		udtaBodySize := udta.size - udta.headerSize
		if meta, ok2, _ := findAtomInRange(f, udtaBodyStart, udtaBodySize, "meta", fileSize); ok2 {
			if ilst, ok3 := findIlstInMeta(f, meta, fileSize); ok3 {
				udtaCopy := udta
				return m4aMetadataPath{
					moov: moov,
					udta: &udtaCopy,
					meta: meta,
					ilst: ilst,
				}, nil
			}
		}
	}

	if meta, ok, _ := findAtomInRange(f, moovBodyStart, moovBodySize, "meta", fileSize); ok {
		if ilst, ok2 := findIlstInMeta(f, meta, fileSize); ok2 {
			return m4aMetadataPath{
				moov: moov,
				meta: meta,
				ilst: ilst,
			}, nil
		}
	}

	return m4aMetadataPath{}, fmt.Errorf("ilst not found (tried moov>udta>meta>ilst and moov>meta>ilst)")
}

func buildM4AAtom(typ string, payload []byte) []byte {
	size := int64(8 + len(payload))
	buf := make([]byte, 8+len(payload))
	binary.BigEndian.PutUint32(buf[0:4], uint32(size))
	copy(buf[4:8], []byte(typ))
	copy(buf[8:], payload)
	return buf
}

func buildM4AFreeformAtom(name, value string) []byte {
	meanPayload := append([]byte{0, 0, 0, 0}, []byte("com.apple.iTunes")...)
	namePayload := append([]byte{0, 0, 0, 0}, []byte(name)...)
	dataPayload := make([]byte, 8+len(value))
	binary.BigEndian.PutUint32(dataPayload[0:4], 1) // UTF-8 text
	copy(dataPayload[8:], []byte(value))

	payload := append([]byte{}, buildM4AAtom("mean", meanPayload)...)
	payload = append(payload, buildM4AAtom("name", namePayload)...)
	payload = append(payload, buildM4AAtom("data", dataPayload)...)
	return buildM4AAtom("----", payload)
}

func buildITunNORMTag(trackGain, trackPeak string) string {
	gainDb, ok := parseReplayGainDb(trackGain)
	if !ok {
		return ""
	}
	peakLinear, ok := parseReplayGainPeak(trackPeak)
	if !ok {
		return ""
	}

	clamp := func(v int64) int64 {
		if v < 0 {
			return 0
		}
		if v > 65534 {
			return 65534
		}
		return v
	}

	g1 := clamp(int64(math.Round(math.Pow(10, gainDb/-10.0) * 1000.0)))
	g2 := clamp(int64(math.Round(math.Pow(10, gainDb/-10.0) * 2500.0)))
	peak := clamp(int64(math.Round(peakLinear * 32768.0)))
	values := []int64{g1, g1, g2, g2, 0, 0, peak, peak, 0, 0}
	parts := make([]string, 0, len(values))
	for _, value := range values {
		parts = append(parts, strings.ToUpper(fmt.Sprintf("%08x", value)))
	}
	return strings.Join(parts, " ")
}

var replayGainNumberPattern = regexp.MustCompile(`([+-]?\d+(?:\.\d+)?)`)

func parseReplayGainDb(value string) (float64, bool) {
	match := replayGainNumberPattern.FindStringSubmatch(strings.TrimSpace(value))
	if len(match) < 2 {
		return 0, false
	}
	parsed, err := strconv.ParseFloat(match[1], 64)
	if err != nil {
		return 0, false
	}
	return parsed, true
}

func parseReplayGainPeak(value string) (float64, bool) {
	parsed, err := strconv.ParseFloat(strings.TrimSpace(value), 64)
	if err != nil || parsed <= 0 {
		return 0, false
	}
	return parsed, true
}

func collectM4AReplayGainFields(fields map[string]string) map[string]string {
	result := map[string]string{}
	if value := strings.TrimSpace(fields["replaygain_track_gain"]); value != "" {
		result["replaygain_track_gain"] = value
	}
	if value := strings.TrimSpace(fields["replaygain_track_peak"]); value != "" {
		result["replaygain_track_peak"] = value
	}
	if value := strings.TrimSpace(fields["replaygain_album_gain"]); value != "" {
		result["replaygain_album_gain"] = value
	}
	if value := strings.TrimSpace(fields["replaygain_album_peak"]); value != "" {
		result["replaygain_album_peak"] = value
	}

	if norm := buildITunNORMTag(result["replaygain_track_gain"], result["replaygain_track_peak"]); norm != "" {
		result["iTunNORM"] = norm
	}

	return result
}

func writeAtomSize(buf []byte, header atomHeader, newSize int64) error {
	if newSize <= 0 {
		return fmt.Errorf("invalid size for %s", header.typ)
	}
	if header.headerSize == 16 {
		if int(header.offset)+16 > len(buf) {
			return io.ErrUnexpectedEOF
		}
		binary.BigEndian.PutUint32(buf[header.offset:header.offset+4], 1)
		binary.BigEndian.PutUint64(buf[header.offset+8:header.offset+16], uint64(newSize))
		return nil
	}
	if newSize > math.MaxUint32 {
		return fmt.Errorf("atom %s too large for 32-bit header", header.typ)
	}
	if int(header.offset)+8 > len(buf) {
		return io.ErrUnexpectedEOF
	}
	binary.BigEndian.PutUint32(buf[header.offset:header.offset+4], uint32(newSize))
	return nil
}

func EditM4AReplayGain(filePath string, fields map[string]string) error {
	replayGainFields := collectM4AReplayGainFields(fields)
	if len(replayGainFields) == 0 {
		return nil
	}

	remove := map[string]struct{}{
		"REPLAYGAIN_TRACK_GAIN": {},
		"REPLAYGAIN_TRACK_PEAK": {},
		"REPLAYGAIN_ALBUM_GAIN": {},
		"REPLAYGAIN_ALBUM_PEAK": {},
		"ITUNNORM":              {},
	}

	order := []string{
		"replaygain_track_gain",
		"replaygain_track_peak",
		"replaygain_album_gain",
		"replaygain_album_peak",
		"iTunNORM",
	}
	tags := make([]m4aFreeformTag, 0, len(order))
	for _, key := range order {
		value := strings.TrimSpace(replayGainFields[key])
		if value == "" {
			continue
		}
		name := key
		if key != "iTunNORM" {
			name = strings.ToLower(key)
		}
		tags = append(tags, m4aFreeformTag{name: name, value: value})
	}

	return writeM4AFreeformTags(filePath, remove, tags)
}

type m4aFreeformTag struct {
	name  string
	value string
}

// writeM4AFreeformTags rewrites the ilst atom in place: it drops every existing
// freeform ("----") atom whose uppercased name is in `remove`, then appends the
// supplied tags (empty values are skipped, which effectively clears the field).
// Atom sizes are fixed up along the ilst -> meta -> udta -> moov chain.
//
// FFmpeg's MP4 muxer only writes a fixed set of recognized keys to the ilst, so
// fields like ISRC and LABEL are silently dropped when written via -metadata.
// Writing them as iTunes freeform atoms natively is the only way they persist.
func writeM4AFreeformTags(filePath string, remove map[string]struct{}, tags []m4aFreeformTag) error {
	f, err := os.Open(filePath)
	if err != nil {
		return err
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		return err
	}

	path, err := findM4AMetadataPath(f, info.Size())
	if err != nil {
		// MOV-style containers (e.g. AC-4 passthrough) store tags as QuickTime
		// atoms under udta with no iTunes meta>ilst structure. There is nowhere
		// to write freeform tags, so skip gracefully instead of failing.
		if strings.Contains(err.Error(), "ilst not found") {
			GoLog("[Metadata] No iTunes ilst container; skipping freeform tags")
			return nil
		}
		return err
	}

	// Only the moov box is buffered; the audio bulk is streamed on write.
	base := path.moov.offset
	moovBuf := make([]byte, path.moov.size)
	if _, err := f.ReadAt(moovBuf, base); err != nil {
		return err
	}

	bodyStart := path.ilst.offset + path.ilst.headerSize
	bodyEnd := path.ilst.offset + path.ilst.size
	newBody := make([]byte, 0, int(path.ilst.size))

	for pos := bodyStart; pos+8 <= bodyEnd; {
		header, readErr := readAtomHeaderAt(f, pos, info.Size())
		if readErr != nil {
			return readErr
		}
		if header.size == 0 {
			header.size = bodyEnd - pos
		}
		if header.size < header.headerSize {
			return fmt.Errorf("invalid atom size for %s", header.typ)
		}

		keep := true
		if header.typ == "----" {
			name, _, freeformErr := readM4AFreeformValue(f, header, info.Size())
			if freeformErr == nil {
				if _, ok := remove[strings.ToUpper(strings.TrimSpace(name))]; ok {
					keep = false
				}
			}
		}
		if keep {
			newBody = append(newBody, moovBuf[pos-base:pos-base+header.size]...)
		}

		pos += header.size
	}

	for _, tag := range tags {
		if strings.TrimSpace(tag.value) == "" {
			continue
		}
		newBody = append(newBody, buildM4AFreeformAtom(tag.name, tag.value)...)
	}

	newIlst := buildM4AAtom("ilst", newBody)
	ilstRel := path.ilst.offset - base
	updated := append([]byte{}, moovBuf[:ilstRel]...)
	updated = append(updated, newIlst...)
	updated = append(updated, moovBuf[ilstRel+path.ilst.size:]...)

	// The path headers carry absolute file offsets; rebase them onto the
	// moov-rooted buffer before patching sizes.
	rel := func(h atomHeader) atomHeader {
		h.offset -= base
		return h
	}
	delta := int64(len(newIlst)) - path.ilst.size
	if err := writeAtomSize(updated, rel(path.ilst), path.ilst.size+delta); err != nil {
		return err
	}
	if err := writeAtomSize(updated, rel(path.meta), path.meta.size+delta); err != nil {
		return err
	}
	if path.udta != nil {
		if err := writeAtomSize(updated, rel(*path.udta), path.udta.size+delta); err != nil {
			return err
		}
	}
	if err := writeAtomSize(updated, rel(path.moov), path.moov.size+delta); err != nil {
		return err
	}
	// Keep sample pointers valid when moov precedes mdat: every stco/co64
	// entry at or beyond the resized ilst must shift with it. Entries hold
	// absolute file offsets, so compare against the absolute ilst position.
	if delta != 0 {
		if moov, ok := findChildMP4(updated, 0, int64(len(updated)), "moov"); ok {
			shiftChunkOffsets(updated, moov, path.ilst.offset, delta)
		}
	}

	// Release the read handle before replacing the file (required on Windows).
	f.Close()
	return replaceFileSectionsStreaming(filePath, []fileSection{
		{start: base, end: base + path.moov.size, data: updated},
	})
}

// EditM4AFreeformText writes ISRC and label tags into an M4A/MP4 file as iTunes
// freeform atoms. These keys are not part of FFmpeg's MP4 metadata key set, so
// they must be written natively for the values to actually persist. An empty
// value clears the corresponding tag. Other (recognized) tags are left intact.
func EditM4AFreeformText(filePath string, fields map[string]string) error {
	_, hasISRC := fields["isrc"]
	_, hasLabel := fields["label"]
	if !hasISRC && !hasLabel {
		return nil
	}

	remove := map[string]struct{}{}
	tags := make([]m4aFreeformTag, 0, 2)
	if hasISRC {
		remove["ISRC"] = struct{}{}
		tags = append(tags, m4aFreeformTag{name: "ISRC", value: strings.TrimSpace(fields["isrc"])})
	}
	if hasLabel {
		remove["LABEL"] = struct{}{}
		remove["ORGANIZATION"] = struct{}{}
		tags = append(tags, m4aFreeformTag{name: "LABEL", value: strings.TrimSpace(fields["label"])})
	}

	return writeM4AFreeformTags(filePath, remove, tags)
}

func GetM4AQuality(filePath string) (AudioQuality, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return AudioQuality{}, fmt.Errorf("failed to open M4A file: %w", err)
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		return AudioQuality{}, fmt.Errorf("failed to stat M4A file: %w", err)
	}
	fileSize := info.Size()
	return m4aQualityFromFile(f, fileSize)
}

func m4aQualityFromFile(f *os.File, fileSize int64) (AudioQuality, error) {
	moovHeader, moovFound, err := findAtomInRange(f, 0, fileSize, "moov", fileSize)
	if err != nil {
		return AudioQuality{}, fmt.Errorf("failed to find moov atom: %w", err)
	}
	if !moovFound {
		return AudioQuality{}, fmt.Errorf("moov atom not found")
	}

	moovStart := moovHeader.offset
	moovEnd := moovHeader.offset + moovHeader.size
	duration := readM4ADurationSeconds(f, moovHeader, fileSize)

	sampleOffset, atomType, err := findAudioSampleEntry(f, moovStart, moovEnd, fileSize)
	if err != nil {
		return AudioQuality{}, err
	}

	buf := make([]byte, 32)
	if _, err := f.ReadAt(buf, sampleOffset); err != nil {
		return AudioQuality{}, fmt.Errorf("failed to read audio sample entry: %w", err)
	}

	// AudioSampleEntry layout from the box type field:
	//   [0:4]   type ("mp4a"/"alac")
	//   [4:10]  SampleEntry.reserved
	//   [10:12] data_reference_index
	//   [12:20] reserved[8]
	//   [20:22] channelcount
	//   [22:24] samplesize (bit depth)
	//   [24:26] pre_defined
	//   [26:28] reserved
	//   [28:32] samplerate (16.16 fixed-point)
	sampleRate := int(buf[28])<<8 | int(buf[29])
	bitDepth := 0
	codec := normalizeM4AAudioCodec(atomType)

	switch atomType {
	case "alac":
		bitDepth = int(buf[22])<<8 | int(buf[23])
		if alacBitDepth, alacSampleRate, ok := readALACSpecificConfig(f, sampleOffset, fileSize); ok {
			if alacBitDepth > 0 {
				bitDepth = alacBitDepth
			}
			if alacSampleRate > 0 {
				sampleRate = alacSampleRate
			}
		}
	case "fLaC":
		bitDepth = int(buf[22])<<8 | int(buf[23])
		if flacBitDepth, flacSampleRate, flacTotalSamples, ok := readMP4FLACSpecificConfig(f, sampleOffset, fileSize); ok {
			if flacBitDepth > 0 {
				bitDepth = flacBitDepth
			}
			if flacSampleRate > 0 {
				sampleRate = flacSampleRate
			}
			if flacTotalSamples > 0 && sampleRate > 0 && duration <= 0 {
				duration = int(flacTotalSamples / int64(sampleRate))
			}
		}
	}

	bitrate := estimateAudioBitrateKbps(fileSize, duration)
	if bitrate > 0 && bitrate < 16 {
		bitrate = 0
	}
	return AudioQuality{
		BitDepth:   bitDepth,
		SampleRate: sampleRate,
		Duration:   duration,
		Bitrate:    bitrate,
		Codec:      codec,
	}, nil
}

func normalizeM4AAudioCodec(atomType string) string {
	switch atomType {
	case "mp4a":
		return "aac"
	case "alac":
		return "alac"
	case "fLaC":
		return "flac"
	case "ec-3":
		return "eac3"
	case "ac-3":
		return "ac3"
	case "ac-4":
		return "ac4"
	default:
		return strings.TrimSpace(atomType)
	}
}

func estimateAudioBitrateKbps(fileSize int64, durationSeconds int) int {
	if fileSize <= 0 || durationSeconds <= 0 {
		return 0
	}
	return int(math.Round(float64(fileSize*8) / float64(durationSeconds) / 1000.0))
}

func readM4ADurationSeconds(f *os.File, moovHeader atomHeader, fileSize int64) int {
	childStart := moovHeader.offset + moovHeader.headerSize
	childSize := moovHeader.size - moovHeader.headerSize
	mvhdHeader, found, err := findAtomInRange(f, childStart, childSize, "mvhd", fileSize)
	if err == nil && found {
		if duration := readMP4DurationAtomSeconds(f, mvhdHeader, fileSize); duration > 0 {
			return duration
		}
	}

	return readM4ATrackDurationSeconds(f, moovHeader, fileSize)
}

func readMP4DurationAtomSeconds(f *os.File, header atomHeader, _ int64) int {
	payloadOffset := header.offset + header.headerSize
	versionBuf := make([]byte, 1)
	if _, err := f.ReadAt(versionBuf, payloadOffset); err != nil {
		return 0
	}

	if versionBuf[0] == 1 {
		buf := make([]byte, 32)
		if _, err := f.ReadAt(buf, payloadOffset); err != nil {
			return 0
		}
		timescale := binary.BigEndian.Uint32(buf[20:24])
		duration := binary.BigEndian.Uint64(buf[24:32])
		if timescale == 0 || duration == 0 {
			return 0
		}
		return int(math.Round(float64(duration) / float64(timescale)))
	}

	buf := make([]byte, 20)
	if _, err := f.ReadAt(buf, payloadOffset); err != nil {
		return 0
	}
	timescale := binary.BigEndian.Uint32(buf[12:16])
	duration := binary.BigEndian.Uint32(buf[16:20])
	if timescale == 0 || duration == 0 {
		return 0
	}
	return int(math.Round(float64(duration) / float64(timescale)))
}

func readM4ATrackDurationSeconds(f *os.File, moovHeader atomHeader, fileSize int64) int {
	childStart := moovHeader.offset + moovHeader.headerSize
	childSize := moovHeader.size - moovHeader.headerSize
	bestDuration := 0
	_ = walkMP4AtomsInRange(f, childStart, childSize, fileSize, func(header atomHeader) bool {
		if header.typ == "mdhd" {
			if duration := readMP4DurationAtomSeconds(f, header, fileSize); duration > bestDuration {
				bestDuration = duration
			}
			return false
		}
		return header.typ == "trak" || header.typ == "mdia"
	})
	return bestDuration
}

func walkMP4AtomsInRange(f *os.File, start, size, fileSize int64, visit func(atomHeader) bool) error {
	if size <= 0 {
		return nil
	}

	end := start + size
	for pos := start; pos+8 <= end; {
		header, err := readAtomHeaderAt(f, pos, fileSize)
		if err != nil {
			return err
		}
		atomSize := header.size
		if atomSize == 0 {
			atomSize = end - pos
		}
		if atomSize < header.headerSize {
			return fmt.Errorf("invalid atom size for %s", header.typ)
		}
		header.size = atomSize
		if visit(header) {
			childStart := header.offset + header.headerSize
			childSize := header.size - header.headerSize
			if err := walkMP4AtomsInRange(f, childStart, childSize, fileSize, visit); err != nil {
				return err
			}
		}
		pos += atomSize
	}
	return nil
}

func readALACSpecificConfig(f *os.File, sampleOffset, fileSize int64) (int, int, bool) {
	if sampleOffset < 4 {
		return 0, 0, false
	}

	sampleEntryHeader, err := readAtomHeaderAt(f, sampleOffset-4, fileSize)
	if err != nil {
		return 0, 0, false
	}

	childStart := sampleOffset + 32
	childEnd := sampleEntryHeader.offset + sampleEntryHeader.size
	if childStart >= childEnd {
		return 0, 0, false
	}

	configHeader, found, err := findAtomInRange(f, childStart, childEnd-childStart, "alac", fileSize)
	if err != nil || !found {
		return 0, 0, false
	}

	payloadSize := configHeader.size - configHeader.headerSize
	if payloadSize <= 0 {
		return 0, 0, false
	}

	payload := make([]byte, payloadSize)
	if _, err := f.ReadAt(payload, configHeader.offset+configHeader.headerSize); err != nil {
		return 0, 0, false
	}

	return parseALACSpecificConfig(payload)
}

func readMP4FLACSpecificConfig(f *os.File, sampleOffset, fileSize int64) (int, int, int64, bool) {
	if sampleOffset < 4 {
		return 0, 0, 0, false
	}

	sampleEntryHeader, err := readAtomHeaderAt(f, sampleOffset-4, fileSize)
	if err != nil {
		return 0, 0, 0, false
	}

	childStart := sampleOffset + 32
	childEnd := sampleEntryHeader.offset + sampleEntryHeader.size
	if childStart >= childEnd {
		return 0, 0, 0, false
	}

	configHeader, found, err := findAtomInRange(f, childStart, childEnd-childStart, "dfLa", fileSize)
	if err != nil || !found {
		return 0, 0, 0, false
	}

	payloadSize := configHeader.size - configHeader.headerSize
	if payloadSize <= 0 {
		return 0, 0, 0, false
	}

	payload := make([]byte, payloadSize)
	if _, err := f.ReadAt(payload, configHeader.offset+configHeader.headerSize); err != nil {
		return 0, 0, 0, false
	}

	return parseMP4FLACSpecificConfig(payload)
}

func parseMP4FLACSpecificConfig(payload []byte) (int, int, int64, bool) {
	if len(payload) >= 4 && string(payload[:4]) == "fLaC" {
		payload = payload[4:]
	} else if len(payload) >= 4 {
		// FLACSpecificBox starts with a full-box version/flags field.
		payload = payload[4:]
	}

	for len(payload) >= 4 {
		blockType := payload[0] & 0x7F
		blockLen := int(payload[1])<<16 | int(payload[2])<<8 | int(payload[3])
		if blockLen < 0 || len(payload) < 4+blockLen {
			return 0, 0, 0, false
		}
		block := payload[4 : 4+blockLen]
		if blockType == 0 && len(block) >= 34 {
			bitDepth, sampleRate, totalSamples := parseFLACStreamInfoQuality(block[:34])
			return bitDepth, sampleRate, totalSamples, bitDepth > 0 || sampleRate > 0
		}
		payload = payload[4+blockLen:]
	}

	return 0, 0, 0, false
}

func parseFLACStreamInfoQuality(streamInfo []byte) (int, int, int64) {
	if len(streamInfo) < 18 {
		return 0, 0, 0
	}
	sampleRate := (int(streamInfo[10]) << 12) | (int(streamInfo[11]) << 4) | (int(streamInfo[12]) >> 4)
	bitsPerSample := (((int(streamInfo[12]) & 0x01) << 4) | (int(streamInfo[13]) >> 4)) + 1
	totalSamples := int64(streamInfo[13]&0x0F)<<32 |
		int64(streamInfo[14])<<24 |
		int64(streamInfo[15])<<16 |
		int64(streamInfo[16])<<8 |
		int64(streamInfo[17])
	return bitsPerSample, sampleRate, totalSamples
}

func parseALACSpecificConfig(payload []byte) (int, int, bool) {
	if len(payload) < 24 {
		return 0, 0, false
	}

	bitDepth := int(payload[5])
	sampleRate := int(binary.BigEndian.Uint32(payload[20:24]))
	if bitDepth > 0 && sampleRate > 0 {
		return bitDepth, sampleRate, true
	}

	// Some encoders prepend 4 bytes before the ALACSpecificConfig payload.
	if len(payload) >= 28 {
		bitDepth = int(payload[9])
		sampleRate = int(binary.BigEndian.Uint32(payload[24:28]))
		if bitDepth > 0 && sampleRate > 0 {
			return bitDepth, sampleRate, true
		}
	}

	return 0, 0, false
}

type atomHeader struct {
	offset     int64
	size       int64
	headerSize int64
	typ        string
}

func readAtomHeaderAt(f *os.File, offset, fileSize int64) (atomHeader, error) {
	if offset+8 > fileSize {
		return atomHeader{}, io.ErrUnexpectedEOF
	}

	headerBuf := make([]byte, 8)
	if _, err := f.ReadAt(headerBuf, offset); err != nil {
		return atomHeader{}, err
	}

	size32 := binary.BigEndian.Uint32(headerBuf[0:4])
	typ := string(headerBuf[4:8])

	if size32 == 1 {
		if offset+16 > fileSize {
			return atomHeader{}, io.ErrUnexpectedEOF
		}
		extBuf := make([]byte, 8)
		if _, err := f.ReadAt(extBuf, offset+8); err != nil {
			return atomHeader{}, err
		}
		size64 := binary.BigEndian.Uint64(extBuf)
		return atomHeader{offset: offset, size: int64(size64), headerSize: 16, typ: typ}, nil
	}

	return atomHeader{offset: offset, size: int64(size32), headerSize: 8, typ: typ}, nil
}

func findAtomInRange(f *os.File, start, size int64, target string, fileSize int64) (atomHeader, bool, error) {
	if size <= 0 {
		return atomHeader{}, false, nil
	}

	end := start + size
	pos := start

	for pos+8 <= end {
		header, err := readAtomHeaderAt(f, pos, fileSize)
		if err != nil {
			return atomHeader{}, false, err
		}

		atomSize := header.size
		if atomSize == 0 {
			atomSize = end - pos
		}

		if atomSize < header.headerSize {
			return atomHeader{}, false, fmt.Errorf("invalid atom size for %s", header.typ)
		}

		header.size = atomSize
		if header.typ == target {
			return header, true, nil
		}

		pos += atomSize
	}

	return atomHeader{}, false, nil
}

func findAudioSampleEntry(f *os.File, start, end, fileSize int64) (int64, string, error) {
	const chunkSize = 64 * 1024
	patterns := [][]byte{
		[]byte("mp4a"),
		[]byte("alac"),
		[]byte("fLaC"),
		[]byte("ec-3"),
		[]byte("ac-3"),
		[]byte("ac-4"),
	}

	var tail []byte
	readPos := start

	for readPos < end {
		toRead := end - readPos
		if toRead > chunkSize {
			toRead = chunkSize
		}

		buf := make([]byte, toRead)
		n, err := f.ReadAt(buf, readPos)
		if err != nil && err != io.EOF {
			return 0, "", fmt.Errorf("failed to read M4A atom data: %w", err)
		}
		if n == 0 {
			break
		}

		data := append(tail, buf[:n]...)
		bestIdx := -1
		bestType := ""
		for _, pattern := range patterns {
			idx := bytes.Index(data, pattern)
			if idx >= 0 && (bestIdx < 0 || idx < bestIdx) {
				bestIdx = idx
				bestType = string(pattern)
			}
		}

		if bestIdx >= 0 {
			absolute := readPos - int64(len(tail)) + int64(bestIdx)
			if absolute+32 > fileSize {
				return 0, "", fmt.Errorf("audio info not found in M4A file")
			}
			return absolute, bestType, nil
		}

		if len(data) >= 3 {
			tail = append([]byte{}, data[len(data)-3:]...)
		} else {
			tail = append([]byte{}, data...)
		}

		readPos += int64(n)
	}

	return 0, "", fmt.Errorf("audio info not found in M4A file")
}
