package gobackend

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/go-flac/flacpicture/v2"
	"github.com/go-flac/flacvorbis/v2"
	flac "github.com/go-flac/go-flac/v2"
)

func writeSinglePassTestFlac(t testing.TB, path string, cover []byte) {
	t.Helper()
	streamInfo := make([]byte, 34)
	const sampleRate = 44100
	const bitDepth = 16
	const totalSamples = int64(441000)
	streamInfo[10] = byte((sampleRate >> 12) & 0xff)
	streamInfo[11] = byte((sampleRate >> 4) & 0xff)
	streamInfo[12] = byte((sampleRate&0x0f)<<4 | ((bitDepth - 1) >> 4))
	streamInfo[13] = byte(((bitDepth-1)&0x0f)<<4) | byte(totalSamples>>32)
	streamInfo[14] = byte((totalSamples >> 24) & 0xff)
	streamInfo[15] = byte((totalSamples >> 16) & 0xff)
	streamInfo[16] = byte((totalSamples >> 8) & 0xff)
	streamInfo[17] = byte(totalSamples & 0xff)
	streamBlock := flac.MetaDataBlock{Type: flac.StreamInfo, Data: streamInfo}

	comments := flacvorbis.New()
	setComment(comments, "TITLE", "Single Pass")
	setComment(comments, "ARTIST", "Artist")
	commentBlock := comments.Marshal()
	pictureBlock := (&flacpicture.MetadataBlockPicture{
		PictureType: flacpicture.PictureTypeFrontCover,
		MIME:        "image/png",
		Width:       1,
		Height:      1,
		ColorDepth:  24,
		ImageData:   cover,
	}).Marshal()

	data := append([]byte("fLaC"), streamBlock.Marshal(false)...)
	data = append(data, commentBlock.Marshal(false)...)
	data = append(data, pictureBlock.Marshal(true)...)
	data = append(data, 0xff, 0xf8)
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestScanFLACSinglePassReadsMetadataQualityAndCover(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "track.flac")
	cover := []byte{0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3}
	writeSinglePassTestFlac(t, path, cover)

	result := &LibraryScanResult{FilePath: path, Format: "flac"}
	result, err := scanFLACFileWithCoverCache(path, result, "", filepath.Join(dir, "covers"), "stable-key")
	if err != nil {
		t.Fatal(err)
	}
	if result.TrackName != "Single Pass" || result.ArtistName != "Artist" || result.SampleRate != 44100 || result.BitDepth != 16 || result.Duration != 10 {
		t.Fatalf("scan result = %#v", result)
	}
	if result.CoverPath == "" {
		t.Fatal("cover was not cached")
	}
	gotCover, err := os.ReadFile(result.CoverPath)
	if err != nil || !bytes.Equal(gotCover, cover) {
		t.Fatalf("cached cover = %x, %v", gotCover, err)
	}
}

func TestScanFLACPersistsAverageBitrate(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "bitrate.flac")
	writeSinglePassTestFlac(t, path, nil)

	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.Write(make([]byte, 2_000_000)); err != nil {
		f.Close()
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}

	result := &LibraryScanResult{FilePath: path, Format: "flac"}
	result, err = scanFLACFile(path, result, "")
	if err != nil {
		t.Fatal(err)
	}
	if result.Bitrate < 1_590 || result.Bitrate > 1_610 {
		t.Fatalf("average bitrate = %d kbps", result.Bitrate)
	}
}

func TestScanM4ASingleOpenReadsMetadataAndCover(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "track.m4a")
	cover := []byte{0xff, 0xd8, 0xff, 1, 2, 3}
	ilst := append(buildM4ATextAtom("\xa9nam", "Single Open"), buildM4ACoverAtom(cover)...)
	data, _ := buildTestM4A(t, ilst, []byte("audio"))
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}

	result := &LibraryScanResult{FilePath: path, Format: "m4a"}
	result, err := scanM4AFileWithCoverCache(path, result, "", filepath.Join(dir, "covers"), "stable-key")
	if err != nil {
		t.Fatal(err)
	}
	if result.TrackName != "Single Open" || result.CoverPath == "" {
		t.Fatalf("scan result = %#v", result)
	}
	gotCover, err := os.ReadFile(result.CoverPath)
	if err != nil || !bytes.Equal(gotCover, cover) {
		t.Fatalf("cached cover = %x, %v", gotCover, err)
	}
}

func TestAudioQualityFromParsedFlacRejectsMissingStreamInfo(t *testing.T) {
	if _, err := audioQualityFromParsedFlac(&flac.File{}); err == nil {
		t.Fatal("missing STREAMINFO was accepted")
	}
}

func TestLibraryAudioCoverCacheKeyIncludesFileIdentity(t *testing.T) {
	info := libraryAudioFileInfo{path: "track.flac", size: 123, modTime: 456}
	if got := libraryAudioCoverCacheKey(info); got != "track.flac|123|456" {
		t.Fatalf("cache key = %q", got)
	}
}
