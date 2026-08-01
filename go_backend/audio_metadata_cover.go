package gobackend

import (
	"bytes"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

func extractMP3CoverArt(filePath string) ([]byte, string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, "", err
	}
	defer file.Close()

	header := make([]byte, 10)
	if _, err := io.ReadFull(file, header); err != nil {
		return nil, "", err
	}

	if string(header[0:3]) != "ID3" {
		return nil, "", fmt.Errorf("no ID3v2 header")
	}

	majorVersion := header[3]
	size := int(header[6])<<21 | int(header[7])<<14 | int(header[8])<<7 | int(header[9])

	tagData := make([]byte, size)
	if _, err := io.ReadFull(file, tagData); err != nil {
		return nil, "", err
	}

	pos := 0
	var frameIDLen, headerLen int
	if majorVersion == 2 {
		frameIDLen = 3
		headerLen = 6
	} else {
		frameIDLen = 4
		headerLen = 10
	}

	for pos+headerLen < len(tagData) {
		frameID := string(tagData[pos : pos+frameIDLen])
		if frameID[0] == 0 {
			break
		}

		var frameSize int
		switch majorVersion {
		case 2:
			frameSize = int(tagData[pos+3])<<16 | int(tagData[pos+4])<<8 | int(tagData[pos+5])
		case 4:
			frameSize = int(tagData[pos+4])<<21 | int(tagData[pos+5])<<14 | int(tagData[pos+6])<<7 | int(tagData[pos+7])
		default:
			frameSize = int(tagData[pos+4])<<24 | int(tagData[pos+5])<<16 | int(tagData[pos+6])<<8 | int(tagData[pos+7])
		}

		if frameSize <= 0 || pos+headerLen+frameSize > len(tagData) {
			break
		}

		if (frameIDLen == 4 && frameID == "APIC") || (frameIDLen == 3 && frameID == "PIC") {
			frameData := tagData[pos+headerLen : pos+headerLen+frameSize]
			imageData, mimeType := parseAPICFrame(frameData, majorVersion)
			if len(imageData) > 0 {
				return imageData, mimeType, nil
			}
		}

		pos += headerLen + frameSize
	}

	return nil, "", fmt.Errorf("no cover art found")
}

func parseAPICFrame(data []byte, version byte) ([]byte, string) {
	if len(data) < 4 {
		return nil, ""
	}

	pos := 0
	encoding := data[pos]
	pos++

	var mimeType string
	if version == 2 {
		if pos+3 > len(data) {
			return nil, ""
		}
		format := string(data[pos : pos+3])
		pos += 3
		switch format {
		case "JPG":
			mimeType = "image/jpeg"
		case "PNG":
			mimeType = "image/png"
		default:
			mimeType = "image/jpeg"
		}
	} else {
		end := pos
		for end < len(data) && data[end] != 0 {
			end++
		}
		mimeType = string(data[pos:end])
		pos = end + 1
	}

	if pos >= len(data) {
		return nil, ""
	}

	pos++

	if encoding == 0 || encoding == 3 {
		for pos < len(data) && data[pos] != 0 {
			pos++
		}
		pos++
	} else {
		for pos+1 < len(data) {
			if data[pos] == 0 && data[pos+1] == 0 {
				pos += 2
				break
			}
			pos++
		}
	}

	if pos >= len(data) {
		return nil, ""
	}

	return data[pos:], mimeType
}

func extractOggCoverArt(filePath string) ([]byte, string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, "", err
	}
	defer file.Close()

	packets, err := collectOggPackets(file, 30, 80)
	if err != nil && len(packets) == 0 {
		return nil, "", err
	}

	streamType := detectOggStreamType(packets)
	for _, pkt := range packets {
		var comments []byte
		if streamType == oggStreamOpus {
			if len(pkt) > 8 && string(pkt[0:8]) == "OpusTags" {
				comments = pkt[8:]
			}
		} else {
			if len(pkt) > 7 && pkt[0] == 0x03 && string(pkt[1:7]) == "vorbis" {
				comments = pkt[7:]
			}
		}
		if len(comments) == 0 && streamType == oggStreamUnknown {
			if len(pkt) > 8 && string(pkt[0:8]) == "OpusTags" {
				comments = pkt[8:]
			} else if len(pkt) > 7 && pkt[0] == 0x03 && string(pkt[1:7]) == "vorbis" {
				comments = pkt[7:]
			}
		}

		if len(comments) > 0 {
			imageData, mimeType := extractPictureFromVorbisComments(comments)
			if len(imageData) > 0 {
				return imageData, mimeType, nil
			}
		}
	}

	return nil, "", fmt.Errorf("no cover art found")
}

func extractPictureFromVorbisComments(data []byte) ([]byte, string) {
	if len(data) < 8 {
		return nil, ""
	}

	reader := bytes.NewReader(data)

	var vendorLen uint32
	if err := binary.Read(reader, binary.LittleEndian, &vendorLen); err != nil {
		return nil, ""
	}
	if vendorLen > uint32(len(data)-4) {
		return nil, ""
	}
	reader.Seek(int64(vendorLen), io.SeekCurrent)

	var commentCount uint32
	if err := binary.Read(reader, binary.LittleEndian, &commentCount); err != nil {
		return nil, ""
	}

	for i := uint32(0); i < commentCount && i < 100; i++ {
		var commentLen uint32
		if err := binary.Read(reader, binary.LittleEndian, &commentLen); err != nil {
			break
		}
		if commentLen > 10000000 {
			break
		}

		comment := make([]byte, commentLen)
		if _, err := reader.Read(comment); err != nil {
			break
		}

		key := "METADATA_BLOCK_PICTURE="
		if len(comment) > len(key) && strings.ToUpper(string(comment[:len(key)])) == key {
			cleaned := strings.Map(func(r rune) rune {
				switch r {
				case '\n', '\r', ' ', '\t':
					return -1
				}
				return r
			}, string(comment[len(key):]))
			decoded, err := base64.StdEncoding.DecodeString(cleaned)
			if err != nil {
				decoded, err = base64.RawStdEncoding.DecodeString(cleaned)
			}
			if err != nil {
				continue
			}

			imageData, mimeType := parseFLACPictureBlock(decoded)
			if len(imageData) > 0 {
				return imageData, mimeType
			}
		}
	}

	return nil, ""
}

func parseFLACPictureBlock(data []byte) ([]byte, string) {
	if len(data) < 32 {
		return nil, ""
	}

	reader := bytes.NewReader(data)

	var pictureType uint32
	binary.Read(reader, binary.BigEndian, &pictureType)

	var mimeLen uint32
	binary.Read(reader, binary.BigEndian, &mimeLen)
	if mimeLen > 256 {
		return nil, ""
	}

	mimeBytes := make([]byte, mimeLen)
	reader.Read(mimeBytes)
	mimeType := string(mimeBytes)

	var descLen uint32
	binary.Read(reader, binary.BigEndian, &descLen)
	if descLen > 10000 {
		return nil, ""
	}

	reader.Seek(int64(descLen), io.SeekCurrent)

	reader.Seek(16, io.SeekCurrent)

	var dataLen uint32
	binary.Read(reader, binary.BigEndian, &dataLen)
	if dataLen > 10000000 {
		return nil, ""
	}

	imageData := make([]byte, dataLen)
	reader.Read(imageData)

	return imageData, mimeType
}

func extractAnyCoverArtWithHint(filePath, displayNameHint string) ([]byte, string, error) {
	ext := strings.ToLower(filepath.Ext(filePath))
	if ext == "" {
		ext = strings.ToLower(filepath.Ext(displayNameHint))
	}

	switch ext {
	case ".flac":
		data, err := ExtractCoverArt(filePath)
		if err != nil {
			return nil, "", err
		}
		mimeType := "image/jpeg"
		if len(data) > 8 && string(data[1:4]) == "PNG" {
			mimeType = "image/png"
		}
		return data, mimeType, nil

	case ".mp3":
		return extractMP3CoverArt(filePath)

	case ".opus", ".ogg":
		return extractOggCoverArt(filePath)

	case ".m4a":
		data, err := extractCoverFromM4A(filePath)
		if err != nil {
			return nil, "", err
		}
		mimeType := "image/jpeg"
		if len(data) >= 8 &&
			data[0] == 0x89 &&
			data[1] == 0x50 &&
			data[2] == 0x4E &&
			data[3] == 0x47 {
			mimeType = "image/png"
		}
		return data, mimeType, nil

	case ".wav", ".aiff", ".aif", ".aifc":
		return extractWAVAIFFCover(filePath)

	default:
		return nil, "", fmt.Errorf("unsupported format: %s", ext)
	}
}

func resolveLibraryCoverCacheKey(filePath, explicitKey string) string {
	explicitKey = strings.TrimSpace(explicitKey)
	if explicitKey != "" {
		return explicitKey
	}

	cacheKey := filePath
	if stat, err := os.Stat(filePath); err == nil {
		cacheKey = fmt.Sprintf("%s|%d|%d", filePath, stat.Size(), stat.ModTime().UnixNano())
	}
	return cacheKey
}

func libraryCoverCachePaths(cacheDir, cacheKey string) (string, string) {
	hash := hashString(cacheKey)
	jpgPath := filepath.Join(cacheDir, fmt.Sprintf("cover_%x.jpg", hash))
	pngPath := filepath.Join(cacheDir, fmt.Sprintf("cover_%x.png", hash))
	return jpgPath, pngPath
}

func existingLibraryCoverCachePath(cacheDir, cacheKey string) string {
	jpgPath, pngPath := libraryCoverCachePaths(cacheDir, cacheKey)

	if _, err := os.Stat(jpgPath); err == nil {
		return jpgPath
	}
	if _, err := os.Stat(pngPath); err == nil {
		return pngPath
	}
	return ""
}

func saveLibraryCoverDataToCache(cacheDir, cacheKey string, imageData []byte, mimeType string) (string, error) {
	if existing := existingLibraryCoverCachePath(cacheDir, cacheKey); existing != "" {
		return existing, nil
	}
	if len(imageData) == 0 {
		return "", fmt.Errorf("cover data is empty")
	}
	if err := os.MkdirAll(cacheDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create cache dir: %w", err)
	}

	jpgPath, pngPath := libraryCoverCachePaths(cacheDir, cacheKey)
	cachePath := jpgPath
	if strings.Contains(mimeType, "png") {
		cachePath = pngPath
	}
	if err := os.WriteFile(cachePath, imageData, 0644); err != nil {
		return "", fmt.Errorf("failed to write cover: %w", err)
	}
	return cachePath, nil
}

func SaveCoverToCacheWithHintAndKey(filePath, displayNameHint, cacheDir, coverCacheKey string) (string, error) {
	cacheKey := resolveLibraryCoverCacheKey(filePath, coverCacheKey)
	if existing := existingLibraryCoverCachePath(cacheDir, cacheKey); existing != "" {
		return existing, nil
	}

	imageData, mimeType, err := extractAnyCoverArtWithHint(filePath, displayNameHint)
	if err != nil {
		return "", err
	}
	return saveLibraryCoverDataToCache(cacheDir, cacheKey, imageData, mimeType)
}
