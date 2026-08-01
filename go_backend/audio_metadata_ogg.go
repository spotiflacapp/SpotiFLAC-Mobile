package gobackend

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"math"
	"os"
	"strconv"
	"strings"
)

func ReadOggVorbisComments(filePath string) (*AudioMetadata, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	metadata := &AudioMetadata{}

	packets, err := collectOggPackets(file, 30, 80)
	if err != nil && len(packets) == 0 {
		return nil, err
	}

	streamType := detectOggStreamType(packets)
	for _, pkt := range packets {
		if streamType == oggStreamOpus {
			if len(pkt) > 8 && string(pkt[0:8]) == "OpusTags" {
				parseVorbisComments(pkt[8:], metadata)
				break
			}
			continue
		}
		if streamType == oggStreamVorbis || streamType == oggStreamUnknown {
			if len(pkt) > 7 && pkt[0] == 0x03 && string(pkt[1:7]) == "vorbis" {
				parseVorbisComments(pkt[7:], metadata)
				break
			}
		}
		if streamType == oggStreamUnknown {
			if len(pkt) > 8 && string(pkt[0:8]) == "OpusTags" {
				parseVorbisComments(pkt[8:], metadata)
				break
			}
		}
	}

	if metadata.Title == "" && metadata.Artist == "" {
		return nil, fmt.Errorf("no Vorbis comments found")
	}

	return metadata, nil
}

type oggPage struct {
	headerType   byte
	segmentTable []byte
	data         []byte
}

func readOggPageWithHeader(file *os.File) (*oggPage, error) {
	header := make([]byte, 27)
	if _, err := io.ReadFull(file, header); err != nil {
		return nil, err
	}

	if string(header[0:4]) != "OggS" {
		return nil, fmt.Errorf("not an Ogg page")
	}

	headerType := header[5]
	numSegments := int(header[26])

	segmentTable := make([]byte, numSegments)
	if _, err := io.ReadFull(file, segmentTable); err != nil {
		return nil, err
	}

	var pageSize int
	for _, seg := range segmentTable {
		pageSize += int(seg)
	}

	pageData := make([]byte, pageSize)
	if _, err := io.ReadFull(file, pageData); err != nil {
		return nil, err
	}

	return &oggPage{
		headerType:   headerType,
		segmentTable: segmentTable,
		data:         pageData,
	}, nil
}

func collectOggPackets(file *os.File, maxPackets, maxPages int) ([][]byte, error) {
	const maxPacketSize = 10 * 1024 * 1024
	var packets [][]byte
	var cur []byte
	skipPacket := false

	for pageNum := 0; pageNum < maxPages && len(packets) < maxPackets; pageNum++ {
		page, err := readOggPageWithHeader(file)
		if err != nil {
			if len(packets) > 0 {
				return packets, nil
			}
			return nil, err
		}

		if page.headerType&0x01 == 0 && len(cur) > 0 {
			cur = nil
			skipPacket = false
		}

		offset := 0
		for _, seg := range page.segmentTable {
			segLen := int(seg)
			if offset+segLen > len(page.data) {
				return packets, fmt.Errorf("invalid ogg segment size")
			}

			if skipPacket {
				offset += segLen
				if segLen < 255 {
					skipPacket = false
				}
				continue
			}

			if len(cur)+segLen > maxPacketSize {
				cur = nil
				skipPacket = true
				offset += segLen
				if segLen < 255 {
					skipPacket = false
				}
				continue
			}

			cur = append(cur, page.data[offset:offset+segLen]...)
			offset += segLen

			if segLen < 255 {
				if len(cur) > 0 {
					packets = append(packets, cur)
				}
				cur = nil
				if len(packets) >= maxPackets {
					return packets, nil
				}
			}
		}
	}

	return packets, nil
}

type oggStreamType int

const (
	oggStreamUnknown oggStreamType = iota
	oggStreamOpus
	oggStreamVorbis
)

func detectOggStreamType(packets [][]byte) oggStreamType {
	for _, p := range packets {
		if len(p) >= 8 && string(p[0:8]) == "OpusHead" {
			return oggStreamOpus
		}
		if len(p) > 7 && p[0] == 0x01 && string(p[1:7]) == "vorbis" {
			return oggStreamVorbis
		}
	}
	return oggStreamUnknown
}

func parseVorbisComments(data []byte, metadata *AudioMetadata) {
	if len(data) < 4 {
		return
	}

	reader := bytes.NewReader(data)
	artistValues := make([]string, 0, 1)
	albumArtistValues := make([]string, 0, 1)

	var vendorLen uint32
	if err := binary.Read(reader, binary.LittleEndian, &vendorLen); err != nil {
		return
	}

	if vendorLen > uint32(len(data)-4) {
		return
	}
	vendor := make([]byte, vendorLen)
	if _, err := reader.Read(vendor); err != nil {
		return
	}

	var commentCount uint32
	if err := binary.Read(reader, binary.LittleEndian, &commentCount); err != nil {
		return
	}

	for i := uint32(0); i < commentCount && i < 100; i++ {
		var commentLen uint32
		if err := binary.Read(reader, binary.LittleEndian, &commentLen); err != nil {
			break
		}

		remaining := uint32(reader.Len())
		if commentLen > remaining {
			break
		}
		if commentLen > 512*1024 {
			reader.Seek(int64(commentLen), io.SeekCurrent)
			continue
		}

		comment := make([]byte, commentLen)
		if _, err := reader.Read(comment); err != nil {
			break
		}

		parts := strings.SplitN(string(comment), "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.ToUpper(parts[0])
		value := parts[1]

		switch key {
		case "TITLE":
			metadata.Title = value
		case "ARTIST":
			artistValues = append(artistValues, value)
		case "ALBUMARTIST", "ALBUM_ARTIST", "ALBUM ARTIST":
			albumArtistValues = append(albumArtistValues, value)
		case "ALBUM":
			metadata.Album = value
		case "DATE", "YEAR":
			metadata.Date = value
			if len(value) >= 4 {
				metadata.Year = value[:4]
			}
		case "GENRE":
			metadata.Genre = value
		case "TRACKNUMBER", "TRACK":
			metadata.TrackNumber, metadata.TotalTracks = parseIndexPair(value)
		case "DISCNUMBER", "DISC":
			metadata.DiscNumber, metadata.TotalDiscs = parseIndexPair(value)
		case "ISRC":
			metadata.ISRC = value
		case "COMPOSER":
			metadata.Composer = value
		case "COMMENT", "DESCRIPTION":
			metadata.Comment = value
		case "LYRICS", "UNSYNCEDLYRICS":
			if metadata.Lyrics == "" {
				metadata.Lyrics = value
			}
		case "ORGANIZATION", "LABEL", "PUBLISHER":
			metadata.Label = value
		case "COPYRIGHT":
			metadata.Copyright = value
		case "REPLAYGAIN_TRACK_GAIN":
			metadata.ReplayGainTrackGain = value
		case "REPLAYGAIN_TRACK_PEAK":
			metadata.ReplayGainTrackPeak = value
		case "REPLAYGAIN_ALBUM_GAIN":
			metadata.ReplayGainAlbumGain = value
		case "REPLAYGAIN_ALBUM_PEAK":
			metadata.ReplayGainAlbumPeak = value
		// Opus gain tags (RFC 7845): Q7.8 fixed point on the R128 -23 LUFS
		// reference. Exposed as ReplayGain 2 dB (-18 LUFS reference) so
		// consumers see one representation; explicit REPLAYGAIN_* wins.
		case "R128_TRACK_GAIN":
			if metadata.ReplayGainTrackGain == "" {
				if db, ok := r128ToReplayGainDb(value); ok {
					metadata.ReplayGainTrackGain = db
				}
			}
		case "R128_ALBUM_GAIN":
			if metadata.ReplayGainAlbumGain == "" {
				if db, ok := r128ToReplayGainDb(value); ok {
					metadata.ReplayGainAlbumGain = db
				}
			}
		}
	}

	if len(artistValues) > 0 {
		metadata.Artist = joinVorbisCommentValues(artistValues)
	}
	if len(albumArtistValues) > 0 {
		metadata.AlbumArtist = joinVorbisCommentValues(albumArtistValues)
	}
}

// r128ToReplayGainDb converts an R128_*_GAIN value (integer, 1/256 dB steps,
// -23 LUFS reference) to a ReplayGain 2 dB string (-18 LUFS reference):
// rg = q/256 + 5. Inverse of the writer's replayGainDbToR128.
func r128ToReplayGainDb(raw string) (string, bool) {
	q, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil {
		return "", false
	}
	return fmt.Sprintf("%.2f dB", float64(q)/256.0+5.0), true
}

func GetOggQuality(filePath string) (*OggQuality, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	quality := &OggQuality{}

	packets, err := collectOggPackets(file, 5, 10)
	if err != nil && len(packets) == 0 {
		return nil, err
	}

	streamType := detectOggStreamType(packets)
	if streamType == oggStreamUnknown {
		if strings.HasSuffix(strings.ToLower(filePath), ".opus") {
			streamType = oggStreamOpus
		} else {
			streamType = oggStreamVorbis
		}
	}

	isOpus := streamType == oggStreamOpus
	var preSkip int

	if isOpus {
		for _, pkt := range packets {
			if len(pkt) >= 19 && string(pkt[0:8]) == "OpusHead" {
				quality.SampleRate = int(binary.LittleEndian.Uint32(pkt[12:16]))
				if quality.SampleRate == 0 {
					quality.SampleRate = 48000
				}
				preSkip = int(binary.LittleEndian.Uint16(pkt[10:12]))
				break
			}
		}
	} else {
		for _, pkt := range packets {
			if len(pkt) > 29 && pkt[0] == 0x01 && string(pkt[1:7]) == "vorbis" {
				quality.SampleRate = int(binary.LittleEndian.Uint32(pkt[12:16]))
				break
			}
		}
	}

	stat, err := file.Stat()
	if err != nil {
		return quality, nil
	}
	fileSize := stat.Size()

	granule := readLastOggGranulePosition(file, fileSize)
	if granule > 0 {
		if isOpus {
			totalSamples := granule - int64(preSkip)
			if totalSamples > 0 {
				durationSec := float64(totalSamples) / 48000.0
				if durationSec > 0 {
					quality.Duration = int(math.Round(durationSec))
					quality.Bitrate = int(float64(fileSize*8) / durationSec)
				}
			}
		} else if quality.SampleRate > 0 {
			durationSec := float64(granule) / float64(quality.SampleRate)
			if durationSec > 0 {
				quality.Duration = int(math.Round(durationSec))
				quality.Bitrate = int(float64(fileSize*8) / durationSec)
			}
		}
	}

	if quality.Bitrate <= 0 && quality.Duration > 0 {
		quality.Bitrate = int(fileSize * 8 / int64(quality.Duration))
	}
	if quality.Duration > 24*60*60 {
		quality.Duration = 0
		quality.Bitrate = 0
	}
	if quality.Bitrate > 0 && quality.Bitrate < 8000 {
		quality.Bitrate = 0
	}

	return quality, nil
}

func readLastOggGranulePosition(file *os.File, fileSize int64) int64 {
	searchSize := int64(65536)
	if searchSize > fileSize {
		searchSize = fileSize
	}

	buf := make([]byte, searchSize)
	offset := fileSize - searchSize
	if offset < 0 {
		offset = 0
	}
	n, err := file.ReadAt(buf, offset)
	if err != nil && n == 0 {
		return 0
	}
	buf = buf[:n]

	for i := n - 4; i >= 0; i-- {
		if buf[i] != 'O' || buf[i+1] != 'g' || buf[i+2] != 'g' || buf[i+3] != 'S' {
			continue
		}
		if i+27 > n {
			continue
		}
		version := buf[i+4]
		headerType := buf[i+5]
		if version != 0 || headerType > 0x07 {
			continue
		}
		segmentCount := int(buf[i+26])
		headerLen := 27 + segmentCount
		if i+headerLen > n {
			continue
		}
		payloadLen := 0
		for s := 0; s < segmentCount; s++ {
			payloadLen += int(buf[i+27+s])
		}
		if i+headerLen+payloadLen > n {
			continue
		}
		return int64(binary.LittleEndian.Uint64(buf[i+6 : i+14]))
	}
	return 0
}
