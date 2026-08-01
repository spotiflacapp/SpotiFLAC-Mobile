package gobackend

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func writeTestWAV(t *testing.T, path string) {
	t.Helper()
	var body bytes.Buffer
	body.WriteString("WAVE")

	fmtData := make([]byte, 16)
	binary.LittleEndian.PutUint16(fmtData[0:2], 1)
	binary.LittleEndian.PutUint16(fmtData[2:4], 2)
	binary.LittleEndian.PutUint32(fmtData[4:8], 44100)
	binary.LittleEndian.PutUint32(fmtData[8:12], 44100*2*2)
	binary.LittleEndian.PutUint16(fmtData[12:14], 4)
	binary.LittleEndian.PutUint16(fmtData[14:16], 16)
	writeTestRIFFChunk(&body, "fmt ", fmtData, true)
	writeTestRIFFChunk(&body, "data", []byte{0, 0, 0, 0}, true)

	var out bytes.Buffer
	out.WriteString("RIFF")
	if err := binary.Write(&out, binary.LittleEndian, uint32(body.Len())); err != nil {
		t.Fatal(err)
	}
	out.Write(body.Bytes())
	if err := os.WriteFile(path, out.Bytes(), 0600); err != nil {
		t.Fatal(err)
	}
}

func writeTestAIFF(t *testing.T, path string) {
	t.Helper()
	var body bytes.Buffer
	body.WriteString("AIFF")

	comm := make([]byte, 18)
	binary.BigEndian.PutUint16(comm[0:2], 2)
	binary.BigEndian.PutUint32(comm[2:6], 1)
	binary.BigEndian.PutUint16(comm[6:8], 16)
	copy(comm[8:18], []byte{0x40, 0x0e, 0xac, 0x44, 0, 0, 0, 0, 0, 0})
	writeTestRIFFChunk(&body, "COMM", comm, false)
	writeTestRIFFChunk(&body, "SSND", make([]byte, 12), false)

	var out bytes.Buffer
	out.WriteString("FORM")
	if err := binary.Write(&out, binary.BigEndian, uint32(body.Len())); err != nil {
		t.Fatal(err)
	}
	out.Write(body.Bytes())
	if err := os.WriteFile(path, out.Bytes(), 0600); err != nil {
		t.Fatal(err)
	}
}

func writeTestRIFFChunk(out *bytes.Buffer, id string, data []byte, littleEndian bool) {
	out.WriteString(id)
	if littleEndian {
		_ = binary.Write(out, binary.LittleEndian, uint32(len(data)))
	} else {
		_ = binary.Write(out, binary.BigEndian, uint32(len(data)))
	}
	out.Write(data)
	if len(data)&1 == 1 {
		out.WriteByte(0)
	}
}

func TestWAVAIFFMetadataAndCoverRoundTrip(t *testing.T) {
	cover := []byte{0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4}
	fields := map[string]string{
		"title":                 "Judul Lagu",
		"artist":                "Artis",
		"album":                 "Album",
		"album_artist":          "Album Artis",
		"date":                  "2026-08-01",
		"track_number":          "3",
		"track_total":           "12",
		"disc_number":           "1",
		"disc_total":            "2",
		"genre":                 "Pop",
		"isrc":                  "TEST12345678",
		"lyrics":                "Baris pertama\nBaris kedua",
		"label":                 "Label",
		"copyright":             "Copyright",
		"composer":              "Komposer",
		"comment":               "Komentar",
		"replaygain_track_gain": "-5.00 dB",
		"replaygain_track_peak": "0.987654",
		"replaygain_album_gain": "-4.00 dB",
		"replaygain_album_peak": "0.998877",
	}

	formats := []struct {
		name   string
		ext    string
		write  func(*testing.T, string)
		tags   func(string) (*AudioMetadata, error)
		edit   func(string, map[string]string) error
		method string
	}{
		{name: "WAV", ext: ".wav", write: writeTestWAV, tags: ReadWAVTags, edit: WriteWAVTags, method: "native_wav"},
		{name: "AIFF", ext: ".aiff", write: writeTestAIFF, tags: ReadAIFFTags, edit: WriteAIFFTags, method: "native_aiff"},
	}

	for _, format := range formats {
		format := format
		t.Run(format.name, func(t *testing.T) {
			dir := t.TempDir()
			path := filepath.Join(dir, "track"+format.ext)
			coverPath := filepath.Join(dir, "cover.png")
			format.write(t, path)
			if err := os.WriteFile(coverPath, cover, 0600); err != nil {
				t.Fatal(err)
			}

			writeFields := make(map[string]string, len(fields)+1)
			for key, value := range fields {
				writeFields[key] = value
			}
			writeFields["cover_path"] = coverPath
			metadataJSON, err := json.Marshal(writeFields)
			if err != nil {
				t.Fatal(err)
			}
			responseJSON, err := EditFileMetadata(path, string(metadataJSON))
			if err != nil {
				t.Fatalf("EditFileMetadata: %v", err)
			}
			var response map[string]any
			if err := json.Unmarshal([]byte(responseJSON), &response); err != nil {
				t.Fatalf("decode EditFileMetadata response: %v", err)
			}
			if response["success"] != true || response["method"] != format.method {
				t.Fatalf("EditFileMetadata response = %v", response)
			}

			meta, err := format.tags(path)
			if err != nil {
				t.Fatalf("read tags: %v", err)
			}
			assertWAVAIFFTestMetadata(t, meta)

			extracted, mime, err := extractWAVAIFFCover(path)
			if err != nil {
				t.Fatalf("extract cover: %v", err)
			}
			if mime != "image/png" || !bytes.Equal(extracted, cover) {
				t.Fatalf("cover = %q (%x), want image/png (%x)", mime, extracted, cover)
			}

			outputCover := filepath.Join(dir, "extracted.bin")
			if err := ExtractCoverToFile(path, outputCover); err != nil {
				t.Fatalf("ExtractCoverToFile: %v", err)
			}
			outputBytes, err := os.ReadFile(outputCover)
			if err != nil || !bytes.Equal(outputBytes, cover) {
				t.Fatalf("ExtractCoverToFile bytes = %x, err=%v", outputBytes, err)
			}

			// A partial Edit Metadata update must retain every untouched field and
			// the existing cover instead of rebuilding a sparse tag.
			if err := format.edit(path, map[string]string{"title": "Judul Baru"}); err != nil {
				t.Fatalf("partial edit: %v", err)
			}
			meta, err = format.tags(path)
			if err != nil {
				t.Fatalf("read edited tags: %v", err)
			}
			if meta.Title != "Judul Baru" || meta.Artist != "Artis" || meta.TotalTracks != 12 {
				t.Fatalf("partial edit lost metadata: %+v", meta)
			}
			extracted, _, err = extractWAVAIFFCover(path)
			if err != nil || !bytes.Equal(extracted, cover) {
				t.Fatalf("partial edit lost cover: %x, err=%v", extracted, err)
			}
		})
	}
}

func TestWAVAIFFTagWriteRejectsMissingRequestedCover(t *testing.T) {
	path := filepath.Join(t.TempDir(), "track.wav")
	writeTestWAV(t, path)
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}

	err = WriteWAVTags(path, map[string]string{
		"title":      "Must not be partially written",
		"cover_path": filepath.Join(t.TempDir(), "missing.jpg"),
	})
	if err == nil {
		t.Fatal("WriteWAVTags succeeded with an inaccessible requested cover")
	}
	after, readErr := os.ReadFile(path)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("WAV changed even though requested cover could not be read")
	}
}

func assertWAVAIFFTestMetadata(t *testing.T, meta *AudioMetadata) {
	t.Helper()
	if meta.Title != "Judul Lagu" ||
		meta.Artist != "Artis" ||
		meta.Album != "Album" ||
		meta.AlbumArtist != "Album Artis" ||
		meta.Date != "2026-08-01" ||
		meta.TrackNumber != 3 ||
		meta.TotalTracks != 12 ||
		meta.DiscNumber != 1 ||
		meta.TotalDiscs != 2 ||
		meta.Genre != "Pop" ||
		meta.ISRC != "TEST12345678" ||
		meta.Lyrics != "Baris pertama\nBaris kedua" ||
		meta.Label != "Label" ||
		meta.Copyright != "Copyright" ||
		meta.Composer != "Komposer" ||
		meta.Comment != "Komentar" ||
		meta.ReplayGainTrackGain != "-5.00 dB" ||
		meta.ReplayGainTrackPeak != "0.987654" ||
		meta.ReplayGainAlbumGain != "-4.00 dB" ||
		meta.ReplayGainAlbumPeak != "0.998877" {
		t.Fatalf("metadata did not round-trip: %+v", meta)
	}
}
