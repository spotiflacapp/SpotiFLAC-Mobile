package gobackend

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

type AudioMetadata struct {
	Title       string
	Artist      string
	Album       string
	AlbumArtist string
	Genre       string
	Year        string
	Date        string
	TrackNumber int
	TotalTracks int
	DiscNumber  int
	TotalDiscs  int
	ISRC        string
	Lyrics      string
	Label       string
	Copyright   string
	Composer    string
	Comment     string
	// ReplayGain fields (text values, e.g. "-6.50 dB", "0.988831")
	ReplayGainTrackGain string
	ReplayGainTrackPeak string
	ReplayGainAlbumGain string
	ReplayGainAlbumPeak string
}

type MP3Quality struct {
	SampleRate int
	BitDepth   int
	Duration   int
	Bitrate    int
}

type OggQuality struct {
	SampleRate int
	BitDepth   int
	Duration   int
	Bitrate    int // estimated bitrate in bps
}

func ReadID3Tags(filePath string) (*AudioMetadata, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	metadata := &AudioMetadata{}

	id3v2, err := readID3v2(file)
	if err == nil && id3v2 != nil {
		metadata = id3v2
	}

	if metadata.Title == "" || metadata.Artist == "" {
		id3v1, err := readID3v1(file)
		if err == nil && id3v1 != nil {
			if metadata.Title == "" {
				metadata.Title = id3v1.Title
			}
			if metadata.Artist == "" {
				metadata.Artist = id3v1.Artist
			}
			if metadata.Album == "" {
				metadata.Album = id3v1.Album
			}
			if metadata.Year == "" {
				metadata.Year = id3v1.Year
			}
			if metadata.Genre == "" {
				metadata.Genre = id3v1.Genre
			}
		}
	}

	if metadata.Title == "" && metadata.Artist == "" {
		return nil, fmt.Errorf("no ID3 tags found")
	}

	return metadata, nil
}

func readID3v2(file *os.File) (*AudioMetadata, error) {
	file.Seek(0, io.SeekStart)

	header := make([]byte, 10)
	if _, err := io.ReadFull(file, header); err != nil {
		return nil, err
	}

	if string(header[0:3]) != "ID3" {
		return nil, fmt.Errorf("no ID3v2 header")
	}

	majorVersion := header[3]
	flags := header[5]
	unsync := (flags & 0x80) != 0
	extendedHeader := (flags & 0x40) != 0
	footerPresent := (flags & 0x10) != 0

	size := int(header[6])<<21 | int(header[7])<<14 | int(header[8])<<7 | int(header[9])

	tagData := make([]byte, size)
	if _, err := io.ReadFull(file, tagData); err != nil {
		return nil, err
	}

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

func parseID3v22Frames(data []byte, metadata *AudioMetadata, tagUnsync bool) {
	pos := 0
	for pos+6 < len(data) {
		frameID := string(data[pos : pos+3])
		if frameID[0] == 0 {
			break
		}

		frameSize := int(data[pos+3])<<16 | int(data[pos+4])<<8 | int(data[pos+5])
		if frameSize <= 0 || pos+6+frameSize > len(data) {
			break
		}

		frameData := data[pos+6 : pos+6+frameSize]
		if tagUnsync {
			frameData = removeUnsync(frameData)
		}
		value := firstTextValue(extractTextFrame(frameData))

		switch frameID {
		case "TT2":
			metadata.Title = value
		case "TP1":
			metadata.Artist = value
		case "TP2":
			metadata.AlbumArtist = value
		case "TAL":
			metadata.Album = value
		case "TYE":
			metadata.Year = value
		case "TCO":
			metadata.Genre = cleanGenre(value)
		case "TRK":
			metadata.TrackNumber, metadata.TotalTracks = parseIndexPair(value)
		case "TPA":
			metadata.DiscNumber, metadata.TotalDiscs = parseIndexPair(value)
		case "TCM":
			metadata.Composer = value
		case "TPB":
			metadata.Label = value
		case "TCR":
			metadata.Copyright = value
		case "ULT":
			if v := extractLangTextFrame(frameData); v != "" && metadata.Lyrics == "" {
				metadata.Lyrics = v
			}
		case "TXX":
			desc, userValue := extractUserTextFrame(frameData)
			if isLyricsDescription(desc) && userValue != "" && metadata.Lyrics == "" {
				metadata.Lyrics = userValue
			}
		}

		pos += 6 + frameSize
	}
}

func parseID3v23Frames(data []byte, metadata *AudioMetadata, version byte, tagUnsync bool) {
	pos := 0
	for pos+10 < len(data) {
		frameID := string(data[pos : pos+4])
		if frameID[0] == 0 {
			break
		}

		var frameSize int
		if version == 4 {
			frameSize = int(data[pos+4])<<21 | int(data[pos+5])<<14 | int(data[pos+6])<<7 | int(data[pos+7])
		} else {
			frameSize = int(data[pos+4])<<24 | int(data[pos+5])<<16 | int(data[pos+6])<<8 | int(data[pos+7])
		}

		if frameSize <= 0 || pos+10+frameSize > len(data) {
			break
		}

		frameData := data[pos+10 : pos+10+frameSize]

		statusFlags := data[pos+8]
		_ = statusFlags
		formatFlags := data[pos+9]

		if version == 3 {
			const (
				id3v23FlagCompression = 0x80
				id3v23FlagEncryption  = 0x40
				id3v23FlagGrouping    = 0x20
			)
			if formatFlags&(id3v23FlagCompression|id3v23FlagEncryption) != 0 {
				pos += 10 + frameSize
				continue
			}
			if formatFlags&id3v23FlagGrouping != 0 {
				if len(frameData) < 1 {
					pos += 10 + frameSize
					continue
				}
				frameData = frameData[1:]
			}
			if tagUnsync {
				frameData = removeUnsync(frameData)
			}
		} else if version == 4 {
			const (
				id3v24FlagGrouping    = 0x40
				id3v24FlagCompression = 0x08
				id3v24FlagEncryption  = 0x04
				id3v24FlagUnsync      = 0x02
				id3v24FlagDataLen     = 0x01
			)
			if formatFlags&id3v24FlagGrouping != 0 {
				if len(frameData) < 1 {
					pos += 10 + frameSize
					continue
				}
				frameData = frameData[1:]
			}
			if formatFlags&id3v24FlagDataLen != 0 {
				if len(frameData) < 4 {
					pos += 10 + frameSize
					continue
				}
				frameData = frameData[4:]
			}
			if formatFlags&id3v24FlagUnsync != 0 || tagUnsync {
				frameData = removeUnsync(frameData)
			}
			if formatFlags&(id3v24FlagCompression|id3v24FlagEncryption) != 0 {
				pos += 10 + frameSize
				continue
			}
		}

		value := firstTextValue(extractTextFrame(frameData))

		switch frameID {
		case "TIT2":
			metadata.Title = value
		case "TPE1":
			metadata.Artist = value
		case "TPE2":
			metadata.AlbumArtist = value
		case "TALB":
			metadata.Album = value
		case "TYER", "TDRC":
			metadata.Year = value
			if len(value) >= 4 {
				metadata.Date = value
			}
		case "TCON":
			metadata.Genre = cleanGenre(value)
		case "TRCK":
			metadata.TrackNumber, metadata.TotalTracks = parseIndexPair(value)
		case "TPOS":
			metadata.DiscNumber, metadata.TotalDiscs = parseIndexPair(value)
		case "TSRC":
			metadata.ISRC = value
		case "TCOM":
			metadata.Composer = value
		case "TPUB":
			metadata.Label = value
		case "TCOP":
			metadata.Copyright = value
		case "COMM":
			if v := extractLangTextFrame(frameData); v != "" {
				metadata.Comment = v
			}
		case "USLT":
			if v := extractLangTextFrame(frameData); v != "" && metadata.Lyrics == "" {
				metadata.Lyrics = v
			}
		case "TXXX":
			desc, userValue := extractUserTextFrame(frameData)
			if isLyricsDescription(desc) && userValue != "" && metadata.Lyrics == "" {
				metadata.Lyrics = userValue
			}
			upperDesc := strings.ToUpper(desc)
			switch upperDesc {
			case "REPLAYGAIN_TRACK_GAIN":
				metadata.ReplayGainTrackGain = userValue
			case "REPLAYGAIN_TRACK_PEAK":
				metadata.ReplayGainTrackPeak = userValue
			case "REPLAYGAIN_ALBUM_GAIN":
				metadata.ReplayGainAlbumGain = userValue
			case "REPLAYGAIN_ALBUM_PEAK":
				metadata.ReplayGainAlbumPeak = userValue
			}
		}

		pos += 10 + frameSize
	}
}

func readID3v1(file *os.File) (*AudioMetadata, error) {
	if _, err := file.Seek(-128, io.SeekEnd); err != nil {
		return nil, err
	}

	tag := make([]byte, 128)
	if _, err := io.ReadFull(file, tag); err != nil {
		return nil, err
	}

	if string(tag[0:3]) != "TAG" {
		return nil, fmt.Errorf("no ID3v1 tag")
	}

	metadata := &AudioMetadata{
		Title:  strings.TrimRight(string(tag[3:33]), " \x00"),
		Artist: strings.TrimRight(string(tag[33:63]), " \x00"),
		Album:  strings.TrimRight(string(tag[63:93]), " \x00"),
		Year:   strings.TrimRight(string(tag[93:97]), " \x00"),
	}

	if tag[125] == 0 && tag[126] != 0 {
		metadata.TrackNumber = int(tag[126])
	}

	genreIndex := int(tag[127])
	if genreIndex < len(id3v1Genres) {
		metadata.Genre = id3v1Genres[genreIndex]
	}

	return metadata, nil
}

func extractTextFrame(data []byte) string {
	if len(data) == 0 {
		return ""
	}

	encoding := data[0]
	text := data[1:]

	switch encoding {
	case 0: // ISO-8859-1
		return strings.TrimRight(string(text), "\x00")
	case 1: // UTF-16 with BOM
		return decodeUTF16(text)
	case 2: // UTF-16BE
		return decodeUTF16BE(text)
	case 3: // UTF-8
		return strings.TrimRight(string(text), "\x00")
	default:
		return strings.TrimRight(string(text), "\x00")
	}
}

// extractLangTextFrame decodes ID3 frames with an encoding byte, 3-byte
// language code, and null-terminated descriptor before the text (COMM, USLT).
func extractLangTextFrame(data []byte) string {
	if len(data) < 5 {
		return ""
	}
	encoding := data[0]
	rest := data[4:]

	var text []byte
	switch encoding {
	case 1, 2:
		for i := 0; i+1 < len(rest); i += 2 {
			if rest[i] == 0 && rest[i+1] == 0 {
				text = rest[i+2:]
				break
			}
		}
	default:
		idx := bytes.IndexByte(rest, 0)
		if idx >= 0 && idx+1 < len(rest) {
			text = rest[idx+1:]
		} else {
			text = rest
		}
	}

	if len(text) == 0 {
		return ""
	}

	framed := make([]byte, 1+len(text))
	framed[0] = encoding
	copy(framed[1:], text)
	return extractTextFrame(framed)
}

func extractUserTextFrame(data []byte) (string, string) {
	if len(data) < 2 {
		return "", ""
	}

	encoding := data[0]
	payload := data[1:]

	var descRaw, valueRaw []byte
	switch encoding {
	case 1, 2:
		for i := 0; i+1 < len(payload); i += 2 {
			if payload[i] == 0 && payload[i+1] == 0 {
				descRaw = payload[:i]
				valueRaw = payload[i+2:]
				break
			}
		}
	default:
		idx := bytes.IndexByte(payload, 0)
		if idx >= 0 {
			descRaw = payload[:idx]
			if idx+1 <= len(payload) {
				valueRaw = payload[idx+1:]
			}
		}
	}

	if len(valueRaw) == 0 {
		return "", ""
	}

	descFramed := make([]byte, 1+len(descRaw))
	descFramed[0] = encoding
	copy(descFramed[1:], descRaw)

	valueFramed := make([]byte, 1+len(valueRaw))
	valueFramed[0] = encoding
	copy(valueFramed[1:], valueRaw)

	return strings.TrimSpace(extractTextFrame(descFramed)), strings.TrimSpace(extractTextFrame(valueFramed))
}

func isLyricsDescription(description string) bool {
	switch strings.ToLower(strings.TrimSpace(description)) {
	case
		"lyrics",
		"lyric",
		"unsyncedlyrics",
		"unsynced lyrics",
		"uslt",
		"lrc":
		return true
	default:
		return false
	}
}

func decodeUTF16(data []byte) string {
	if len(data) < 2 {
		return ""
	}

	var littleEndian bool
	if data[0] == 0xFF && data[1] == 0xFE {
		littleEndian = true
		data = data[2:]
	} else if data[0] == 0xFE && data[1] == 0xFF {
		littleEndian = false
		data = data[2:]
	}

	return decodeUTF16Data(data, littleEndian)
}

func decodeUTF16BE(data []byte) string {
	return decodeUTF16Data(data, false)
}

func decodeUTF16Data(data []byte, littleEndian bool) string {
	if len(data) < 2 {
		return ""
	}

	var runes []rune
	for i := 0; i+1 < len(data); i += 2 {
		var r uint16
		if littleEndian {
			r = uint16(data[i]) | uint16(data[i+1])<<8
		} else {
			r = uint16(data[i])<<8 | uint16(data[i+1])
		}
		if r == 0 {
			break
		}
		runes = append(runes, rune(r))
	}
	return string(runes)
}

func cleanGenre(genre string) string {
	if len(genre) == 0 {
		return ""
	}

	if genre[0] == '(' {
		end := strings.Index(genre, ")")
		if end > 0 {
			numStr := genre[1:end]
			if num, err := strconv.Atoi(numStr); err == nil && num < len(id3v1Genres) {
				if end+1 < len(genre) {
					return genre[end+1:]
				}
				return id3v1Genres[num]
			}
		}
	}
	return genre
}

func parseIndexPair(s string) (int, int) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, 0
	}

	first := s
	second := ""
	if idx := strings.Index(s, "/"); idx > 0 {
		first = s[:idx]
		second = s[idx+1:]
	}

	num, _ := strconv.Atoi(strings.TrimSpace(first))
	total, _ := strconv.Atoi(strings.TrimSpace(second))
	return num, total
}

func removeUnsync(data []byte) []byte {
	if len(data) == 0 {
		return data
	}
	out := make([]byte, 0, len(data))
	for i := 0; i < len(data); i++ {
		b := data[i]
		out = append(out, b)
		if b == 0xFF && i+1 < len(data) && data[i+1] == 0x00 {
			i++
		}
	}
	return out
}

func extendedHeaderSize(data []byte, version byte) int {
	if len(data) < 4 {
		return 0
	}
	var size int
	switch version {
	case 3:
		size = int(binary.BigEndian.Uint32(data[:4]))
	case 4:
		size = syncsafeToInt(data[:4])
	default:
		return 0
	}
	if size <= 0 {
		return 0
	}
	total := size + 4
	if total <= len(data) {
		return total
	}
	if size <= len(data) {
		return size
	}
	return 0
}

func syncsafeToInt(b []byte) int {
	if len(b) < 4 {
		return 0
	}
	return int(b[0])<<21 | int(b[1])<<14 | int(b[2])<<7 | int(b[3])
}

func firstTextValue(s string) string {
	if idx := strings.IndexByte(s, 0); idx >= 0 {
		return s[:idx]
	}
	return s
}

func GetMP3Quality(filePath string) (*MP3Quality, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	quality := &MP3Quality{}

	stat, err := file.Stat()
	if err != nil {
		return nil, err
	}
	fileSize := stat.Size()

	header := make([]byte, 10)
	if _, err := io.ReadFull(file, header); err != nil {
		return nil, err
	}

	var audioStart int64 = 0
	if string(header[0:3]) == "ID3" {
		tagSize := int64(header[6])<<21 | int64(header[7])<<14 | int64(header[8])<<7 | int64(header[9])
		audioStart = 10 + tagSize
	}

	file.Seek(audioStart, io.SeekStart)

	frameHeader := make([]byte, 4)
	var frameStart int64 = -1
	for i := 0; i < 10000; i++ {
		if _, err := io.ReadFull(file, frameHeader); err != nil {
			break
		}

		if frameHeader[0] == 0xFF && (frameHeader[1]&0xE0) == 0xE0 {
			pos, _ := file.Seek(0, io.SeekCurrent)
			frameStart = pos - 4
			break
		}

		file.Seek(-3, io.SeekCurrent)
	}

	if frameStart < 0 {
		return quality, nil
	}

	version := (frameHeader[1] >> 3) & 0x03
	layer := (frameHeader[1] >> 1) & 0x03
	bitrateIdx := (frameHeader[2] >> 4) & 0x0F
	sampleRateIdx := (frameHeader[2] >> 2) & 0x03
	channelMode := (frameHeader[3] >> 6) & 0x03

	sampleRates := [][]int{
		{11025, 12000, 8000},
		{0, 0, 0},
		{22050, 24000, 16000},
		{44100, 48000, 32000},
	}
	if version < 4 && sampleRateIdx < 3 {
		quality.SampleRate = sampleRates[version][sampleRateIdx]
	}

	if version == 3 && layer == 1 {
		bitrates := []int{0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0}
		if bitrateIdx < 16 {
			quality.Bitrate = bitrates[bitrateIdx] * 1000
		}
	}
	if (version == 0 || version == 2) && layer == 1 {
		bitrates := []int{0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0}
		if bitrateIdx < 16 {
			quality.Bitrate = bitrates[bitrateIdx] * 1000
		}
	}

	samplesPerFrame := 1152 // MPEG1 Layer III
	if version == 0 || version == 2 {
		samplesPerFrame = 576 // MPEG2/2.5 Layer III
	}

	var xingOffset int
	if version == 3 { // MPEG1
		if channelMode == 3 { // Mono
			xingOffset = 17
		} else {
			xingOffset = 32
		}
	} else { // MPEG2/2.5
		if channelMode == 3 {
			xingOffset = 9
		} else {
			xingOffset = 17
		}
	}

	xingBuf := make([]byte, 200)
	file.Seek(frameStart+4, io.SeekStart)
	n, _ := io.ReadFull(file, xingBuf)
	xingBuf = xingBuf[:n]

	vbrFrames := 0
	vbrBytes := int64(0)
	isVBR := false

	if xingOffset+8 <= n {
		tag := string(xingBuf[xingOffset : xingOffset+4])
		if tag == "Xing" || tag == "Info" {
			flags := binary.BigEndian.Uint32(xingBuf[xingOffset+4 : xingOffset+8])
			off := xingOffset + 8
			if flags&0x01 != 0 && off+4 <= n { // Frames flag
				vbrFrames = int(binary.BigEndian.Uint32(xingBuf[off : off+4]))
				off += 4
			}
			if flags&0x02 != 0 && off+4 <= n { // Bytes flag
				vbrBytes = int64(binary.BigEndian.Uint32(xingBuf[off : off+4]))
			}
			if vbrFrames > 0 {
				isVBR = true
			}
		}
	}

	if !isVBR && 36+26 <= n {
		if string(xingBuf[32:36]) == "VBRI" {
			vbrBytes = int64(binary.BigEndian.Uint32(xingBuf[36+6 : 36+10]))
			vbrFrames = int(binary.BigEndian.Uint32(xingBuf[36+10 : 36+14]))
			if vbrFrames > 0 {
				isVBR = true
			}
		}
	}

	if isVBR && vbrFrames > 0 && quality.SampleRate > 0 {
		totalSamples := int64(vbrFrames) * int64(samplesPerFrame)
		quality.Duration = int(totalSamples / int64(quality.SampleRate))

		if vbrBytes > 0 && quality.Duration > 0 {
			quality.Bitrate = int(vbrBytes * 8 / int64(quality.Duration))
		} else if quality.Duration > 0 {
			audioSize := fileSize - audioStart
			quality.Bitrate = int(audioSize * 8 / int64(quality.Duration))
		}
	} else if quality.Bitrate > 0 {
		audioSize := fileSize - audioStart - 128 // subtract possible ID3v1 tag
		if audioSize > 0 {
			quality.Duration = int(audioSize * 8 / int64(quality.Bitrate))
		}
	}

	return quality, nil
}

var id3v1Genres = []string{
	"Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge",
	"Hip-Hop", "Jazz", "Metal", "New Age", "Oldies", "Other", "Pop", "R&B",
	"Rap", "Reggae", "Rock", "Techno", "Industrial", "Alternative", "Ska",
	"Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient",
	"Trip-Hop", "Vocal", "Jazz+Funk", "Fusion", "Trance", "Classical",
	"Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel",
	"Noise", "AlternRock", "Bass", "Soul", "Punk", "Space", "Meditative",
	"Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic",
	"Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk", "Eurodance",
	"Dream", "Southern Rock", "Comedy", "Cult", "Gangsta", "Top 40",
	"Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret",
	"New Wave", "Psychedelic", "Rave", "Showtunes", "Trailer", "Lo-Fi",
	"Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical",
	"Rock & Roll", "Hard Rock", "Folk", "Folk-Rock", "National Folk",
	"Swing", "Fast Fusion", "Bebop", "Latin", "Revival", "Celtic",
	"Bluegrass", "Avantgarde", "Gothic Rock", "Progressive Rock",
	"Psychedelic Rock", "Symphonic Rock", "Slow Rock", "Big Band",
	"Chorus", "Easy Listening", "Acoustic", "Humour", "Speech", "Chanson",
	"Opera", "Chamber Music", "Sonata", "Symphony", "Booty Bass", "Primus",
	"Porn Groove", "Satire", "Slow Jam", "Club", "Tango", "Samba",
	"Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle",
	"Duet", "Punk Rock", "Drum Solo", "A capella", "Euro-House",
	"Dance Hall", "Goa", "Drum & Bass", "Club-House", "Hardcore",
	"Terror", "Indie", "BritPop", "Negerpunk", "Polsk Punk", "Beat",
	"Christian Gangsta Rap", "Heavy Metal", "Black Metal", "Crossover",
	"Contemporary Christian", "Christian Rock", "Merengue", "Salsa",
	"Thrash Metal", "Anime", "J-Pop", "Synthpop",
}
