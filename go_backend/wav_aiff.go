package gobackend

// WAV (RIFF) and AIFF/AIFC support: quality probing, tag reading/writing, and
// cover-art extraction. These containers are not handled by go-flac, so chunks
// are parsed/written by hand here.
//
// Tags are stored as an embedded ID3v2.4 tag (UTF-8): WAV uses a lowercase
// "id3 " chunk, AIFF uses an uppercase "ID3 " chunk. ID3v2.4 is chosen because
// the existing ID3 reader (parseID3v23Frames with version=4) reads synchsafe
// frame sizes and UTF-8 text, so anything we write is read back losslessly.
//
// Reading also recognises a WAV "LIST"/"INFO" block as a fallback for files
// that carry only RIFF INFO tags (common from other taggers).

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// WAVQuality / AIFFQuality mirror the other GetXQuality result shapes.
type WAVQuality struct {
	SampleRate int
	BitDepth   int
	Channels   int
	Duration   int
}

const (
	wavMaxMetaChunk = 16 * 1024 * 1024 // safety cap for buffering a metadata chunk
	id3ChunkWAV     = "id3 "
	id3ChunkAIFF    = "ID3 "
	// Other format tags for reference: 0x0001 PCM, 0x0003 IEEE float.
	wavFormatExtensn = 0xFFFE
)

func putUint32(dst []byte, le bool, v uint32) {
	if le {
		binary.LittleEndian.PutUint32(dst, v)
	} else {
		binary.BigEndian.PutUint32(dst, v)
	}
}

func readUint32(b []byte, le bool) uint32 {
	if le {
		return binary.LittleEndian.Uint32(b)
	}
	return binary.BigEndian.Uint32(b)
}

func synchsafeEncode(n int) []byte {
	return []byte{
		byte((n >> 21) & 0x7f),
		byte((n >> 14) & 0x7f),
		byte((n >> 7) & 0x7f),
		byte(n & 0x7f),
	}
}

func synchsafeDecode(b []byte) int {
	if len(b) < 4 {
		return 0
	}
	return int(b[0])<<21 | int(b[1])<<14 | int(b[2])<<7 | int(b[3])
}

// parseExtendedFloat80 decodes an 80-bit IEEE 754 extended float (used by the
// AIFF COMM chunk for the sample rate).
func parseExtendedFloat80(b []byte) float64 {
	if len(b) < 10 {
		return 0
	}
	sign := 1.0
	if b[0]&0x80 != 0 {
		sign = -1.0
	}
	exponent := int(b[0]&0x7f)<<8 | int(b[1])
	var mantissa uint64
	for i := 2; i < 10; i++ {
		mantissa = mantissa<<8 | uint64(b[i])
	}
	if exponent == 0 && mantissa == 0 {
		return 0
	}
	return sign * float64(mantissa) * math.Pow(2, float64(exponent-16383-63))
}

type wavProbe struct {
	sampleRate int
	bitDepth   int
	channels   int
	byteRate   int
	dataSize   int64
	id3        []byte
	info       map[string]string
}

// streamProbeWAV walks the top-level RIFF chunks, buffering only the small
// metadata chunks (fmt/id3/LIST) and skipping the large data chunk.
func streamProbeWAV(f *os.File) (*wavProbe, error) {
	header := make([]byte, 12)
	if _, err := io.ReadFull(f, header); err != nil {
		return nil, err
	}
	if string(header[0:4]) != "RIFF" || string(header[8:12]) != "WAVE" {
		return nil, fmt.Errorf("not a WAVE file")
	}

	p := &wavProbe{info: map[string]string{}}
	hdr := make([]byte, 8)
	for {
		if _, err := io.ReadFull(f, hdr); err != nil {
			break
		}
		id := string(hdr[0:4])
		size := readUint32(hdr[4:8], true)
		pad := int64(size) & 1

		switch id {
		case "fmt ":
			buf := make([]byte, size)
			if _, err := io.ReadFull(f, buf); err != nil {
				return p, nil
			}
			if len(buf) >= 16 {
				format := binary.LittleEndian.Uint16(buf[0:2])
				p.channels = int(binary.LittleEndian.Uint16(buf[2:4]))
				p.sampleRate = int(binary.LittleEndian.Uint32(buf[4:8]))
				p.byteRate = int(binary.LittleEndian.Uint32(buf[8:12]))
				p.bitDepth = int(binary.LittleEndian.Uint16(buf[14:16]))
				if format == wavFormatExtensn && len(buf) >= 26 {
					// Valid bits per sample lives in the extension; the real
					// PCM format tag is in the GUID, but bitDepth from the
					// container field is sufficient for display.
					if vb := int(binary.LittleEndian.Uint16(buf[18:20])); vb > 0 {
						p.bitDepth = vb
					}
				}
			}
			if pad == 1 {
				f.Seek(pad, io.SeekCurrent)
			}
		case "data":
			p.dataSize = int64(size)
			f.Seek(int64(size)+pad, io.SeekCurrent)
		case id3ChunkWAV, "ID3 ":
			if size > 0 && size <= wavMaxMetaChunk {
				buf := make([]byte, size)
				if _, err := io.ReadFull(f, buf); err == nil {
					p.id3 = buf
				}
				if pad == 1 {
					f.Seek(pad, io.SeekCurrent)
				}
			} else {
				f.Seek(int64(size)+pad, io.SeekCurrent)
			}
		case "LIST":
			if size > 0 && size <= wavMaxMetaChunk {
				buf := make([]byte, size)
				if _, err := io.ReadFull(f, buf); err == nil {
					parseRIFFInfo(buf, p.info)
				}
				if pad == 1 {
					f.Seek(pad, io.SeekCurrent)
				}
			} else {
				f.Seek(int64(size)+pad, io.SeekCurrent)
			}
		default:
			f.Seek(int64(size)+pad, io.SeekCurrent)
		}
	}
	return p, nil
}

// parseRIFFInfo reads a LIST/INFO block ("INFO" + sub-chunks like INAM, IART).
func parseRIFFInfo(buf []byte, out map[string]string) {
	if len(buf) < 4 || string(buf[0:4]) != "INFO" {
		return
	}
	pos := 4
	for pos+8 <= len(buf) {
		id := string(buf[pos : pos+4])
		size := int(binary.LittleEndian.Uint32(buf[pos+4 : pos+8]))
		pos += 8
		if size <= 0 || pos+size > len(buf) {
			break
		}
		val := strings.TrimRight(string(buf[pos:pos+size]), "\x00")
		out[id] = strings.TrimSpace(val)
		pos += size
		if size&1 == 1 {
			pos++
		}
	}
}

func wavMetadataFromProbe(p *wavProbe) *AudioMetadata {
	if p == nil {
		return nil
	}
	if len(p.id3) > 0 {
		if meta, err := readID3v2FromBytes(p.id3); err == nil && meta != nil &&
			(meta.Title != "" || meta.Artist != "" || meta.Album != "") {
			return meta
		}
	}
	if len(p.info) > 0 {
		meta := &AudioMetadata{
			Title:     p.info["INAM"],
			Artist:    p.info["IART"],
			Album:     p.info["IPRD"],
			Genre:     cleanGenre(p.info["IGNR"]),
			Date:      p.info["ICRD"],
			Comment:   p.info["ICMT"],
			Copyright: p.info["ICOP"],
			Composer:  p.info["IMUS"],
		}
		if n, err := strconv.Atoi(strings.TrimSpace(p.info["ITRK"])); err == nil {
			meta.TrackNumber = n
		}
		if meta.Date != "" && len(meta.Date) >= 4 {
			meta.Year = meta.Date[:4]
		}
		if meta.Title != "" || meta.Artist != "" || meta.Album != "" {
			return meta
		}
	}
	return nil
}

// GetWAVQuality probes PCM parameters and computes duration from the data size.
func GetWAVQuality(filePath string) (*WAVQuality, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	p, err := streamProbeWAV(f)
	if err != nil {
		return nil, err
	}
	q := &WAVQuality{
		SampleRate: p.sampleRate,
		BitDepth:   p.bitDepth,
		Channels:   p.channels,
	}
	if p.byteRate > 0 && p.dataSize > 0 {
		q.Duration = int(p.dataSize / int64(p.byteRate))
	} else if p.sampleRate > 0 && p.channels > 0 && p.bitDepth > 0 && p.dataSize > 0 {
		bytesPerSec := int64(p.sampleRate * p.channels * p.bitDepth / 8)
		if bytesPerSec > 0 {
			q.Duration = int(p.dataSize / bytesPerSec)
		}
	}
	return q, nil
}

// ReadWAVTags reads tags from a WAV file (ID3 chunk preferred, RIFF INFO fallback).
func ReadWAVTags(filePath string) (*AudioMetadata, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	p, err := streamProbeWAV(f)
	if err != nil {
		return nil, err
	}
	meta := wavMetadataFromProbe(p)
	if meta == nil {
		return nil, fmt.Errorf("no WAV tags found")
	}
	return meta, nil
}

type aiffProbe struct {
	sampleRate     int
	bitDepth       int
	channels       int
	numFrames      int64
	id3            []byte
	nameChunk      string
	authChunk      string
	annoChunk      string
	copyrightChunk string
}

func streamProbeAIFF(f *os.File) (*aiffProbe, error) {
	header := make([]byte, 12)
	if _, err := io.ReadFull(f, header); err != nil {
		return nil, err
	}
	form := string(header[8:12])
	if string(header[0:4]) != "FORM" || (form != "AIFF" && form != "AIFC") {
		return nil, fmt.Errorf("not an AIFF file")
	}

	p := &aiffProbe{}
	hdr := make([]byte, 8)
	for {
		if _, err := io.ReadFull(f, hdr); err != nil {
			break
		}
		id := string(hdr[0:4])
		size := readUint32(hdr[4:8], false)
		pad := int64(size) & 1

		switch id {
		case "COMM":
			buf := make([]byte, size)
			if _, err := io.ReadFull(f, buf); err != nil {
				return p, nil
			}
			if len(buf) >= 18 {
				p.channels = int(binary.BigEndian.Uint16(buf[0:2]))
				p.numFrames = int64(binary.BigEndian.Uint32(buf[2:6]))
				p.bitDepth = int(binary.BigEndian.Uint16(buf[6:8]))
				p.sampleRate = int(parseExtendedFloat80(buf[8:18]) + 0.5)
			}
			if pad == 1 {
				f.Seek(pad, io.SeekCurrent)
			}
		case id3ChunkAIFF, "id3 ":
			if size > 0 && size <= wavMaxMetaChunk {
				buf := make([]byte, size)
				if _, err := io.ReadFull(f, buf); err == nil {
					p.id3 = buf
				}
				if pad == 1 {
					f.Seek(pad, io.SeekCurrent)
				}
			} else {
				f.Seek(int64(size)+pad, io.SeekCurrent)
			}
		case "NAME", "AUTH", "ANNO", "(c) ":
			if size > 0 && size <= wavMaxMetaChunk {
				buf := make([]byte, size)
				if _, err := io.ReadFull(f, buf); err == nil {
					val := strings.TrimRight(strings.TrimSpace(string(buf)), "\x00")
					switch id {
					case "NAME":
						p.nameChunk = val
					case "AUTH":
						p.authChunk = val
					case "ANNO":
						p.annoChunk = val
					case "(c) ":
						p.copyrightChunk = val
					}
				}
				if pad == 1 {
					f.Seek(pad, io.SeekCurrent)
				}
			} else {
				f.Seek(int64(size)+pad, io.SeekCurrent)
			}
		default:
			f.Seek(int64(size)+pad, io.SeekCurrent)
		}
	}
	return p, nil
}

func aiffMetadataFromProbe(p *aiffProbe) *AudioMetadata {
	if p == nil {
		return nil
	}
	if len(p.id3) > 0 {
		if meta, err := readID3v2FromBytes(p.id3); err == nil && meta != nil &&
			(meta.Title != "" || meta.Artist != "" || meta.Album != "") {
			return meta
		}
	}
	if p.nameChunk != "" || p.authChunk != "" {
		meta := &AudioMetadata{
			Title:     p.nameChunk,
			Artist:    p.authChunk,
			Comment:   p.annoChunk,
			Copyright: p.copyrightChunk,
		}
		return meta
	}
	return nil
}

// GetAIFFQuality probes PCM parameters and computes duration from frame count.
func GetAIFFQuality(filePath string) (*WAVQuality, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	p, err := streamProbeAIFF(f)
	if err != nil {
		return nil, err
	}
	q := &WAVQuality{
		SampleRate: p.sampleRate,
		BitDepth:   p.bitDepth,
		Channels:   p.channels,
	}
	if p.sampleRate > 0 && p.numFrames > 0 {
		q.Duration = int(p.numFrames / int64(p.sampleRate))
	}
	return q, nil
}

// ReadAIFFTags reads tags from an AIFF file (ID3 chunk preferred, AIFF text chunks fallback).
func ReadAIFFTags(filePath string) (*AudioMetadata, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	p, err := streamProbeAIFF(f)
	if err != nil {
		return nil, err
	}
	meta := aiffMetadataFromProbe(p)
	if meta == nil {
		return nil, fmt.Errorf("no AIFF tags found")
	}
	return meta, nil
}

// readID3v2FromBytes parses an in-memory ID3v2 tag (the contents of a WAV "id3 "
// or AIFF "ID3 " chunk) by reusing the existing frame parsers.
func readID3v2FromBytes(data []byte) (*AudioMetadata, error) {
	if len(data) < 10 || string(data[0:3]) != "ID3" {
		return nil, fmt.Errorf("no ID3v2 header")
	}
	majorVersion := data[3]
	flags := data[5]
	unsync := (flags & 0x80) != 0
	extendedHeader := (flags & 0x40) != 0
	footerPresent := (flags & 0x10) != 0

	size := synchsafeDecode(data[6:10])
	if size <= 0 || 10+size > len(data) {
		size = len(data) - 10
	}
	tagData := data[10 : 10+size]

	if footerPresent && len(tagData) >= 10 {
		footerStart := len(tagData) - 10
		if footerStart >= 0 && string(tagData[footerStart:footerStart+3]) == "3DI" {
			tagData = tagData[:footerStart]
		}
	}
	if extendedHeader {
		if skip := extendedHeaderSize(tagData, majorVersion); skip > 0 && skip < len(tagData) {
			tagData = tagData[skip:]
		}
	}

	metadata := &AudioMetadata{}
	if majorVersion == 2 {
		parseID3v22Frames(tagData, metadata, unsync)
	} else {
		parseID3v23Frames(tagData, metadata, majorVersion, unsync)
	}
	return metadata, nil
}

// extractAPICFromID3 returns the first embedded picture (APIC/PIC) and its MIME.
func extractAPICFromID3(tag []byte) ([]byte, string) {
	if len(tag) < 10 || string(tag[0:3]) != "ID3" {
		return nil, ""
	}
	ver := tag[3]
	size := synchsafeDecode(tag[6:10])
	if size <= 0 || 10+size > len(tag) {
		size = len(tag) - 10
	}
	data := tag[10 : 10+size]

	pos := 0
	for {
		if ver == 2 {
			if pos+6 > len(data) || data[pos] == 0 {
				break
			}
			id := string(data[pos : pos+3])
			fsz := int(data[pos+3])<<16 | int(data[pos+4])<<8 | int(data[pos+5])
			if fsz <= 0 || pos+6+fsz > len(data) {
				break
			}
			if id == "PIC" {
				return parseAPICFrame(data[pos+6:pos+6+fsz], ver)
			}
			pos += 6 + fsz
			continue
		}

		if pos+10 > len(data) || data[pos] == 0 {
			break
		}
		id := string(data[pos : pos+4])
		var fsz int
		if ver == 4 {
			fsz = synchsafeDecode(data[pos+4 : pos+8])
		} else {
			fsz = int(binary.BigEndian.Uint32(data[pos+4 : pos+8]))
		}
		if fsz <= 0 || pos+10+fsz > len(data) {
			break
		}
		if id == "APIC" {
			return parseAPICFrame(data[pos+10:pos+10+fsz], ver)
		}
		pos += 10 + fsz
	}
	return nil, ""
}

// buildID3v24Tag builds a UTF-8 ID3v2.4 tag from metadata plus optional cover.
func buildID3v24Tag(meta *AudioMetadata, coverData []byte, coverMIME string) []byte {
	var frames bytes.Buffer

	writeFrame := func(id string, payload []byte) {
		frames.WriteString(id)
		frames.Write(synchsafeEncode(len(payload)))
		frames.Write([]byte{0, 0})
		frames.Write(payload)
	}
	writeText := func(id, val string) {
		if strings.TrimSpace(val) == "" {
			return
		}
		payload := append([]byte{0x03}, []byte(val)...)
		writeFrame(id, payload)
	}

	writeText("TIT2", meta.Title)
	writeText("TPE1", meta.Artist)
	writeText("TALB", meta.Album)
	writeText("TPE2", meta.AlbumArtist)
	writeText("TCON", meta.Genre)
	writeText("TCOM", meta.Composer)
	writeText("TPUB", meta.Label)
	writeText("TCOP", meta.Copyright)
	writeText("TSRC", meta.ISRC)

	date := meta.Date
	if date == "" {
		date = meta.Year
	}
	writeText("TDRC", date)

	if meta.TrackNumber > 0 {
		if meta.TotalTracks > 0 {
			writeText("TRCK", fmt.Sprintf("%d/%d", meta.TrackNumber, meta.TotalTracks))
		} else {
			writeText("TRCK", strconv.Itoa(meta.TrackNumber))
		}
	}
	if meta.DiscNumber > 0 {
		if meta.TotalDiscs > 0 {
			writeText("TPOS", fmt.Sprintf("%d/%d", meta.DiscNumber, meta.TotalDiscs))
		} else {
			writeText("TPOS", strconv.Itoa(meta.DiscNumber))
		}
	}

	if strings.TrimSpace(meta.Comment) != "" {
		// COMM: encoding + language(3) + short desc(null) + text
		payload := []byte{0x03}
		payload = append(payload, []byte("eng")...)
		payload = append(payload, 0x00) // empty description
		payload = append(payload, []byte(meta.Comment)...)
		writeFrame("COMM", payload)
	}
	if strings.TrimSpace(meta.Lyrics) != "" {
		payload := []byte{0x03}
		payload = append(payload, []byte("eng")...)
		payload = append(payload, 0x00)
		payload = append(payload, []byte(meta.Lyrics)...)
		writeFrame("USLT", payload)
	}

	// ReplayGain as TXXX (description\0value), UTF-8.
	writeTXXX := func(desc, val string) {
		if strings.TrimSpace(val) == "" {
			return
		}
		payload := []byte{0x03}
		payload = append(payload, []byte(desc)...)
		payload = append(payload, 0x00)
		payload = append(payload, []byte(val)...)
		writeFrame("TXXX", payload)
	}
	writeTXXX("REPLAYGAIN_TRACK_GAIN", meta.ReplayGainTrackGain)
	writeTXXX("REPLAYGAIN_TRACK_PEAK", meta.ReplayGainTrackPeak)
	writeTXXX("REPLAYGAIN_ALBUM_GAIN", meta.ReplayGainAlbumGain)
	writeTXXX("REPLAYGAIN_ALBUM_PEAK", meta.ReplayGainAlbumPeak)

	if len(coverData) > 0 {
		if strings.TrimSpace(coverMIME) == "" {
			coverMIME = "image/jpeg"
		}
		// APIC: encoding + mime(null) + picture-type(0x03 front) + desc(null) + data
		payload := []byte{0x03}
		payload = append(payload, []byte(coverMIME)...)
		payload = append(payload, 0x00)
		payload = append(payload, 0x03)
		payload = append(payload, 0x00)
		payload = append(payload, coverData...)
		writeFrame("APIC", payload)
	}

	body := frames.Bytes()
	var out bytes.Buffer
	out.WriteString("ID3")
	out.Write([]byte{0x04, 0x00}) // v2.4.0
	out.WriteByte(0x00)           // flags
	out.Write(synchsafeEncode(len(body)))
	out.Write(body)
	return out.Bytes()
}

// writeID3Chunk rewrites filePath, replacing any existing tag chunk (chunkID,
// matched case-insensitively) with a fresh ID3v2.4 chunk appended at the end.
// The audio data and all other chunks are preserved; container size is patched.
func writeID3Chunk(filePath, expectMagic, chunkID string, le bool, id3 []byte) error {
	in, err := os.Open(filePath)
	if err != nil {
		return err
	}
	defer in.Close()

	header := make([]byte, 12)
	if _, err := io.ReadFull(in, header); err != nil {
		return err
	}
	if string(header[0:4]) != expectMagic {
		return fmt.Errorf("unexpected container magic %q", string(header[0:4]))
	}

	tmpPath := filePath + ".tagtmp"
	out, err := os.Create(tmpPath)
	if err != nil {
		return err
	}
	cleanup := func() {
		out.Close()
		os.Remove(tmpPath)
	}

	if _, err := out.Write(header); err != nil {
		cleanup()
		return err
	}

	var bodyLen int64 = 4 // the 4-byte form type after the size field
	hdr := make([]byte, 8)
	for {
		n, rerr := io.ReadFull(in, hdr)
		if n < 8 {
			break
		}
		if rerr != nil {
			break
		}
		id := string(hdr[0:4])
		size := readUint32(hdr[4:8], le)
		pad := int64(size) & 1

		if strings.EqualFold(id, chunkID) {
			if _, err := in.Seek(int64(size)+pad, io.SeekCurrent); err != nil {
				cleanup()
				return err
			}
			continue
		}

		if _, err := out.Write(hdr); err != nil {
			cleanup()
			return err
		}
		if _, err := io.CopyN(out, in, int64(size)+pad); err != nil {
			cleanup()
			return err
		}
		bodyLen += 8 + int64(size) + pad
	}

	newSize := len(id3)
	chunkHdr := make([]byte, 8)
	copy(chunkHdr[0:4], chunkID)
	putUint32(chunkHdr[4:8], le, uint32(newSize))
	if _, err := out.Write(chunkHdr); err != nil {
		cleanup()
		return err
	}
	if _, err := out.Write(id3); err != nil {
		cleanup()
		return err
	}
	if newSize&1 == 1 {
		if _, err := out.Write([]byte{0}); err != nil {
			cleanup()
			return err
		}
	}
	bodyLen += 8 + int64(newSize) + int64(newSize&1)

	// Patch the container size field (bytes 4..8).
	sizeBuf := make([]byte, 4)
	putUint32(sizeBuf, le, uint32(bodyLen))
	if _, err := out.WriteAt(sizeBuf, 4); err != nil {
		cleanup()
		return err
	}

	if err := out.Sync(); err != nil {
		out.Close()
		os.Remove(tmpPath)
		return err
	}
	if err := out.Close(); err != nil {
		os.Remove(tmpPath)
		return err
	}
	in.Close()

	if err := os.Rename(tmpPath, filePath); err != nil {
		os.Remove(tmpPath)
		return err
	}
	syncDir(filepath.Dir(filePath))
	return nil
}

func loadCoverForTag(fields map[string]string) ([]byte, string, error) {
	coverPath := strings.TrimSpace(fields["cover_path"])
	if coverPath == "" {
		return nil, "", nil
	}
	data, err := os.ReadFile(coverPath)
	if err != nil {
		return nil, "", fmt.Errorf("read cover art: %w", err)
	}
	if len(data) == 0 {
		return nil, "", fmt.Errorf("cover art is empty")
	}
	mime := "image/jpeg"
	switch {
	case len(data) >= 8 && data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47:
		mime = "image/png"
	case len(data) >= 12 && string(data[0:4]) == "RIFF" && string(data[8:12]) == "WEBP":
		mime = "image/webp"
	case len(data) >= 6 && (string(data[0:6]) == "GIF87a" || string(data[0:6]) == "GIF89a"):
		mime = "image/gif"
	default:
		switch strings.ToLower(filepath.Ext(coverPath)) {
		case ".png":
			mime = "image/png"
		case ".webp":
			mime = "image/webp"
		case ".gif":
			mime = "image/gif"
		}
	}
	return data, mime, nil
}

func audioMetadataFromEditFields(fields map[string]string) *AudioMetadata {
	atoi := func(k string) int {
		n := 0
		if v, ok := fields[k]; ok && strings.TrimSpace(v) != "" {
			fmt.Sscanf(strings.TrimSpace(v), "%d", &n)
		}
		return n
	}
	return &AudioMetadata{
		Title:               fields["title"],
		Artist:              fields["artist"],
		Album:               fields["album"],
		AlbumArtist:         fields["album_artist"],
		Date:                fields["date"],
		TrackNumber:         atoi("track_number"),
		TotalTracks:         atoi("track_total"),
		DiscNumber:          atoi("disc_number"),
		TotalDiscs:          atoi("disc_total"),
		ISRC:                fields["isrc"],
		Lyrics:              fields["lyrics"],
		Genre:               fields["genre"],
		Label:               fields["label"],
		Copyright:           fields["copyright"],
		Composer:            fields["composer"],
		Comment:             fields["comment"],
		ReplayGainTrackGain: fields["replaygain_track_gain"],
		ReplayGainTrackPeak: fields["replaygain_track_peak"],
		ReplayGainAlbumGain: fields["replaygain_album_gain"],
		ReplayGainAlbumPeak: fields["replaygain_album_peak"],
	}
}

// mergeWAVEditFields merges edit fields onto existing tags so untouched fields
// (and cover art, when no new cover is provided) are preserved.
func mergeEditFieldsOntoExisting(existing *AudioMetadata, fields map[string]string) *AudioMetadata {
	meta := audioMetadataFromEditFields(fields)
	if existing == nil {
		return meta
	}
	// Only overwrite fields that are present as keys in the edit set; otherwise
	// keep the existing value. An empty value with the key present clears it.
	keep := func(key, newVal, oldVal string) string {
		if _, ok := fields[key]; ok {
			return newVal
		}
		return oldVal
	}
	meta.Title = keep("title", meta.Title, existing.Title)
	meta.Artist = keep("artist", meta.Artist, existing.Artist)
	meta.Album = keep("album", meta.Album, existing.Album)
	meta.AlbumArtist = keep("album_artist", meta.AlbumArtist, existing.AlbumArtist)
	meta.Genre = keep("genre", meta.Genre, existing.Genre)
	meta.Composer = keep("composer", meta.Composer, existing.Composer)
	meta.Label = keep("label", meta.Label, existing.Label)
	meta.Copyright = keep("copyright", meta.Copyright, existing.Copyright)
	meta.ISRC = keep("isrc", meta.ISRC, existing.ISRC)
	meta.Lyrics = keep("lyrics", meta.Lyrics, existing.Lyrics)
	meta.Comment = keep("comment", meta.Comment, existing.Comment)
	meta.Date = keep("date", meta.Date, existing.Date)
	if _, ok := fields["track_number"]; !ok {
		meta.TrackNumber = existing.TrackNumber
	}
	if _, ok := fields["track_total"]; !ok {
		meta.TotalTracks = existing.TotalTracks
	}
	if _, ok := fields["disc_number"]; !ok {
		meta.DiscNumber = existing.DiscNumber
	}
	if _, ok := fields["disc_total"]; !ok {
		meta.TotalDiscs = existing.TotalDiscs
	}
	if _, ok := fields["replaygain_track_gain"]; !ok {
		meta.ReplayGainTrackGain = existing.ReplayGainTrackGain
	}
	if _, ok := fields["replaygain_track_peak"]; !ok {
		meta.ReplayGainTrackPeak = existing.ReplayGainTrackPeak
	}
	if _, ok := fields["replaygain_album_gain"]; !ok {
		meta.ReplayGainAlbumGain = existing.ReplayGainAlbumGain
	}
	if _, ok := fields["replaygain_album_peak"]; !ok {
		meta.ReplayGainAlbumPeak = existing.ReplayGainAlbumPeak
	}
	return meta
}

// WriteWAVTags writes/merges tags into a WAV file's "id3 " chunk.
func WriteWAVTags(filePath string, fields map[string]string) error {
	existing, _ := ReadWAVTags(filePath)
	meta := mergeEditFieldsOntoExisting(existing, fields)

	coverData, coverMIME, err := loadCoverForTag(fields)
	if err != nil {
		return err
	}
	if coverData == nil {
		// Preserve an existing embedded cover when no new one is supplied.
		if f, err := os.Open(filePath); err == nil {
			if p, perr := streamProbeWAV(f); perr == nil && len(p.id3) > 0 {
				coverData, coverMIME = extractAPICFromID3(p.id3)
			}
			f.Close()
		}
	}

	tag := buildID3v24Tag(meta, coverData, coverMIME)
	return writeID3Chunk(filePath, "RIFF", id3ChunkWAV, true, tag)
}

// WriteAIFFTags writes/merges tags into an AIFF file's "ID3 " chunk.
func WriteAIFFTags(filePath string, fields map[string]string) error {
	existing, _ := ReadAIFFTags(filePath)
	meta := mergeEditFieldsOntoExisting(existing, fields)

	coverData, coverMIME, err := loadCoverForTag(fields)
	if err != nil {
		return err
	}
	if coverData == nil {
		if f, err := os.Open(filePath); err == nil {
			if p, perr := streamProbeAIFF(f); perr == nil && len(p.id3) > 0 {
				coverData, coverMIME = extractAPICFromID3(p.id3)
			}
			f.Close()
		}
	}

	tag := buildID3v24Tag(meta, coverData, coverMIME)
	return writeID3Chunk(filePath, "FORM", id3ChunkAIFF, false, tag)
}

func scanWAVFile(filePath string, result *LibraryScanResult, displayNameHint string) (*LibraryScanResult, error) {
	if metadata, err := ReadWAVTags(filePath); err == nil && metadata != nil {
		applyAudioMetadataToScan(metadata, result)
	}
	if quality, err := GetWAVQuality(filePath); err == nil && quality != nil {
		result.BitDepth = quality.BitDepth
		result.SampleRate = quality.SampleRate
		result.Duration = quality.Duration
	}
	result.Bitrate = 0 // lossless PCM
	result.Format = "wav"
	applyDefaultLibraryMetadata(filePath, displayNameHint, result)
	return result, nil
}

func scanAIFFFile(filePath string, result *LibraryScanResult, displayNameHint string) (*LibraryScanResult, error) {
	if metadata, err := ReadAIFFTags(filePath); err == nil && metadata != nil {
		applyAudioMetadataToScan(metadata, result)
	}
	if quality, err := GetAIFFQuality(filePath); err == nil && quality != nil {
		result.BitDepth = quality.BitDepth
		result.SampleRate = quality.SampleRate
		result.Duration = quality.Duration
	}
	result.Bitrate = 0 // lossless PCM
	result.Format = "aiff"
	applyDefaultLibraryMetadata(filePath, displayNameHint, result)
	return result, nil
}

func applyAudioMetadataToScan(metadata *AudioMetadata, result *LibraryScanResult) {
	result.TrackName = metadata.Title
	result.ArtistName = metadata.Artist
	result.AlbumName = metadata.Album
	result.AlbumArtist = metadata.AlbumArtist
	result.ISRC = metadata.ISRC
	result.TrackNumber = metadata.TrackNumber
	result.TotalTracks = metadata.TotalTracks
	result.DiscNumber = metadata.DiscNumber
	result.TotalDiscs = metadata.TotalDiscs
	if metadata.Date != "" {
		result.ReleaseDate = metadata.Date
	} else {
		result.ReleaseDate = metadata.Year
	}
	result.Genre = metadata.Genre
	result.Composer = metadata.Composer
	result.Label = metadata.Label
	result.Copyright = metadata.Copyright
}

// extractWAVAIFFCover returns embedded cover art (from the ID3 chunk) for a
// WAV or AIFF file, or an error when none is present.
func extractWAVAIFFCover(filePath string) ([]byte, string, error) {
	ext := strings.ToLower(filepath.Ext(filePath))
	f, err := os.Open(filePath)
	if err != nil {
		return nil, "", err
	}
	defer f.Close()

	var id3 []byte
	switch ext {
	case ".aiff", ".aif", ".aifc":
		if p, perr := streamProbeAIFF(f); perr == nil {
			id3 = p.id3
		}
	default:
		if p, perr := streamProbeWAV(f); perr == nil {
			id3 = p.id3
		}
	}
	if len(id3) == 0 {
		return nil, "", fmt.Errorf("no embedded cover")
	}
	data, mime := extractAPICFromID3(id3)
	if len(data) == 0 {
		return nil, "", fmt.Errorf("no embedded cover")
	}
	return data, mime, nil
}
