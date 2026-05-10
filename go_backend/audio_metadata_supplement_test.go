package gobackend

import (
	"bytes"
	"encoding/base64"
	"encoding/binary"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAudioMetadataID3ParsingBranches(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "tagged.mp3")
	tag := buildID3v23Tag(
		id3TextFrame("TIT2", "Title"),
		id3TextFrame("TPE1", "Artist"),
		id3TextFrame("TPE2", "Album Artist"),
		id3TextFrame("TALB", "Album"),
		id3TextFrame("TDRC", "2026-05-04"),
		id3TextFrame("TCON", "(13)Pop"),
		id3TextFrame("TRCK", "4/12"),
		id3TextFrame("TPOS", "1/2"),
		id3TextFrame("TSRC", "USRC17607839"),
		id3TextFrame("TCOM", "Composer"),
		id3TextFrame("TPUB", "Label"),
		id3TextFrame("TCOP", "Copyright"),
		id3CommentFrame("COMM", "Comment"),
		id3CommentFrame("USLT", "Lyrics"),
		id3UserTextFrame("TXXX", "REPLAYGAIN_TRACK_GAIN", "-6.50 dB"),
		id3UserTextFrame("TXXX", "REPLAYGAIN_TRACK_PEAK", "0.98"),
	)
	if err := os.WriteFile(path, append(tag, []byte("audio")...), 0600); err != nil {
		t.Fatalf("write ID3v2: %v", err)
	}

	meta, err := ReadID3Tags(path)
	if err != nil {
		t.Fatalf("ReadID3Tags: %v", err)
	}
	if meta.Title != "Title" || meta.TrackNumber != 4 || meta.TotalTracks != 12 || meta.Genre != "Pop" {
		t.Fatalf("metadata = %#v", meta)
	}
	if meta.Comment != "Comment" || meta.Lyrics != "Lyrics" || meta.ReplayGainTrackGain == "" {
		t.Fatalf("metadata comments/lyrics/replaygain = %#v", meta)
	}

	id3v1Path := filepath.Join(dir, "id3v1.mp3")
	if err := os.WriteFile(id3v1Path, append([]byte("audio"), buildID3v1Tag("V1 Title", "V1 Artist", "V1 Album", "1999", 7, 13)...), 0600); err != nil {
		t.Fatalf("write ID3v1: %v", err)
	}
	v1, err := ReadID3Tags(id3v1Path)
	if err != nil {
		t.Fatalf("ReadID3Tags v1: %v", err)
	}
	if v1.Title != "V1 Title" || v1.Artist != "V1 Artist" || v1.Genre == "" {
		t.Fatalf("v1 = %#v", v1)
	}

	v22Path := filepath.Join(dir, "id3v22.mp3")
	v22 := buildID3v22Tag(
		id3v22TextFrame("TT2", "V22 Title"),
		id3v22TextFrame("TP1", "V22 Artist"),
		id3v22TextFrame("TRK", "2/5"),
		id3v22CommentFrame("ULT", "V22 Lyrics"),
	)
	if err := os.WriteFile(v22Path, append(v22, []byte("audio")...), 0600); err != nil {
		t.Fatalf("write ID3v2.2: %v", err)
	}
	v22Meta, err := ReadID3Tags(v22Path)
	if err != nil {
		t.Fatalf("ReadID3Tags v2.2: %v", err)
	}
	if v22Meta.Title != "V22 Title" || v22Meta.Artist != "V22 Artist" || v22Meta.Lyrics != "V22 Lyrics" {
		t.Fatalf("v22 = %#v", v22Meta)
	}

	if got := decodeUTF16([]byte{0xff, 0xfe, 'H', 0, 'i', 0}); got != "Hi" {
		t.Fatalf("decodeUTF16 = %q", got)
	}
	if got := decodeUTF16BE([]byte{0, 'O', 0, 'K'}); got != "OK" {
		t.Fatalf("decodeUTF16BE = %q", got)
	}
	if n, total := parseIndexPair(" 8 / 10 "); n != 8 || total != 10 {
		t.Fatalf("parseIndexPair = %d/%d", n, total)
	}
	if got := parseTrackNumber("9/11"); got != 9 {
		t.Fatalf("parseTrackNumber = %d", got)
	}
	if got := removeUnsync([]byte{0xff, 0x00, 0xe0}); !bytes.Equal(got, []byte{0xff, 0xe0}) {
		t.Fatalf("removeUnsync = %#v", got)
	}
	if got := extendedHeaderSize([]byte{0, 0, 0, 6, 0, 0, 0, 0, 0, 0}, 3); got != 10 {
		t.Fatalf("extendedHeaderSize = %d", got)
	}
	if got := syncsafeToInt([]byte{0, 0, 2, 0}); got != 256 {
		t.Fatalf("syncsafe = %d", got)
	}
}

func TestAudioMetadataCoverAndQualityHelpers(t *testing.T) {
	png := []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0}
	if detectCoverMIME("cover.jpg", png) != "image/png" || detectCoverMIME("cover.webp", []byte("RIFFxxxxWEBPdata")) != "image/webp" {
		t.Fatal("cover MIME detection mismatch")
	}
	if _, err := buildPictureBlock("", nil); err == nil {
		t.Fatal("expected empty picture block error")
	}

	apic := append([]byte{3}, []byte("image/png\x00")...)
	apic = append(apic, 3, 0)
	apic = append(apic, png...)
	image, mime := parseAPICFrame(apic, 3)
	if mime != "image/png" || !bytes.Equal(image, png) {
		t.Fatalf("APIC = %s/%v", mime, image)
	}
	pic := append([]byte{0}, []byte("PNG")...)
	pic = append(pic, 3, 0)
	pic = append(pic, png...)
	image, mime = parseAPICFrame(pic, 2)
	if mime != "image/png" || !bytes.Equal(image, png) {
		t.Fatalf("PIC = %s/%v", mime, image)
	}

	frame := make([]byte, 10)
	copy(frame[:4], "APIC")
	binary.BigEndian.PutUint32(frame[4:8], uint32(len(apic)))
	tag := append(frame, apic...)
	header := []byte{'I', 'D', '3', 3, 0, 0, byte(len(tag) >> 21), byte(len(tag) >> 14), byte(len(tag) >> 7), byte(len(tag))}
	mp3CoverPath := filepath.Join(t.TempDir(), "cover.mp3")
	if err := os.WriteFile(mp3CoverPath, append(append(header, tag...), []byte("audio")...), 0600); err != nil {
		t.Fatal(err)
	}
	extracted, extractedMIME, err := extractMP3CoverArt(mp3CoverPath)
	if err != nil || extractedMIME != "image/png" || !bytes.Equal(extracted, png) {
		t.Fatalf("extractMP3CoverArt = %s/%v/%v", extractedMIME, extracted, err)
	}

	var picture bytes.Buffer
	binary.Write(&picture, binary.BigEndian, uint32(3))
	binary.Write(&picture, binary.BigEndian, uint32(len("image/png")))
	picture.WriteString("image/png")
	binary.Write(&picture, binary.BigEndian, uint32(0))
	binary.Write(&picture, binary.BigEndian, uint32(1))
	binary.Write(&picture, binary.BigEndian, uint32(1))
	binary.Write(&picture, binary.BigEndian, uint32(32))
	binary.Write(&picture, binary.BigEndian, uint32(0))
	binary.Write(&picture, binary.BigEndian, uint32(len(png)))
	picture.Write(png)
	flacImage, flacMIME := parseFLACPictureBlock(picture.Bytes())
	if flacMIME != "image/png" || !bytes.Equal(flacImage, png) {
		t.Fatalf("FLAC picture = %s/%v", flacMIME, flacImage)
	}

	comment := "METADATA_BLOCK_PICTURE=" + base64.StdEncoding.EncodeToString(picture.Bytes())
	var vorbis bytes.Buffer
	binary.Write(&vorbis, binary.LittleEndian, uint32(6))
	vorbis.WriteString("vendor")
	binary.Write(&vorbis, binary.LittleEndian, uint32(1))
	binary.Write(&vorbis, binary.LittleEndian, uint32(len(comment)))
	vorbis.WriteString(comment)
	commentImage, commentMIME := extractPictureFromVorbisComments(vorbis.Bytes())
	if commentMIME != "image/png" || !bytes.Equal(commentImage, png) {
		t.Fatalf("vorbis picture = %s/%v", commentMIME, commentImage)
	}
	decoded := make([]byte, base64StdDecodeLen(len("SGV sbG8="))+4)
	n, err := base64StdDecode(decoded, []byte("SGV sbG8="))
	if err != nil || strings.TrimRight(string(decoded[:n]), "\x00") != "Hello" {
		t.Fatalf("base64 decode = %q/%v", decoded[:n], err)
	}

	if detectOggStreamType([][]byte{[]byte("OpusHeadxxxx")}) != oggStreamOpus {
		t.Fatal("expected opus stream")
	}
	if detectOggStreamType([][]byte{append([]byte{1}, []byte("vorbisxxxx")...)}) != oggStreamVorbis {
		t.Fatal("expected vorbis stream")
	}

	mp3Path := filepath.Join(t.TempDir(), "quality.mp3")
	audio := append([]byte{0xFF, 0xFB, 0x90, 0x64}, bytes.Repeat([]byte{0}, 2000)...)
	if err := os.WriteFile(mp3Path, audio, 0600); err != nil {
		t.Fatal(err)
	}
	quality, err := GetMP3Quality(mp3Path)
	if err != nil || quality.SampleRate != 44100 || quality.Bitrate != 128000 {
		t.Fatalf("MP3 quality = %#v/%v", quality, err)
	}
	if _, _, err := extractMP3CoverArt(filepath.Join(t.TempDir(), "missing.mp3")); err == nil {
		t.Fatal("expected missing MP3 cover error")
	}
}

func TestM4AMetadataAtomHelpers(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "tagged.m4a")
	cover := []byte{0xFF, 0xD8, 0xFF, 0x00}
	ilstPayload := []byte{}
	ilstPayload = append(ilstPayload, buildM4ATextTag("\xa9nam", "M4A Title")...)
	ilstPayload = append(ilstPayload, buildM4ATextTag("\xa9ART", "M4A Artist")...)
	ilstPayload = append(ilstPayload, buildM4ATextTag("\xa9alb", "M4A Album")...)
	ilstPayload = append(ilstPayload, buildM4ATextTag("aART", "Album Artist")...)
	ilstPayload = append(ilstPayload, buildM4ATextTag("\xa9day", "2026")...)
	ilstPayload = append(ilstPayload, buildM4ATextTag("\xa9gen", "Pop")...)
	ilstPayload = append(ilstPayload, buildM4ATextTag("\xa9wrt", "Composer")...)
	ilstPayload = append(ilstPayload, buildM4ATextTag("\xa9cmt", "[ti:Comment Lyrics]")...)
	ilstPayload = append(ilstPayload, buildM4ATextTag("cprt", "Copyright")...)
	ilstPayload = append(ilstPayload, buildM4ATextTag("\xa9lyr", "[00:00.00]M4A Lyrics")...)
	ilstPayload = append(ilstPayload, buildM4AIndexTag("trkn", 3, 12)...)
	ilstPayload = append(ilstPayload, buildM4AIndexTag("disk", 1, 2)...)
	ilstPayload = append(ilstPayload, buildM4AFreeformAtom("ISRC", "USRC17607839")...)
	ilstPayload = append(ilstPayload, buildM4AFreeformAtom("LABEL", "Label")...)
	ilstPayload = append(ilstPayload, buildM4AFreeformAtom("REPLAYGAIN_TRACK_GAIN", "-6.50 dB")...)
	ilstPayload = append(ilstPayload, buildM4AAtom("covr", buildM4AAtom("data", append([]byte{0, 0, 0, 13, 0, 0, 0, 0}, cover...)))...)
	fileData := buildM4AFileWithIlst(ilstPayload, true)
	if err := os.WriteFile(path, fileData, 0600); err != nil {
		t.Fatal(err)
	}

	meta, err := ReadM4ATags(path)
	if err != nil {
		t.Fatalf("ReadM4ATags: %v", err)
	}
	if meta.Title != "M4A Title" || meta.Artist != "M4A Artist" || meta.TrackNumber != 3 || meta.TotalTracks != 12 || meta.ISRC != "USRC17607839" {
		t.Fatalf("M4A metadata = %#v", meta)
	}
	if lyrics, err := extractLyricsFromM4A(path); err != nil || !strings.Contains(lyrics, "M4A Lyrics") {
		t.Fatalf("extractLyricsFromM4A = %q/%v", lyrics, err)
	}
	if image, err := extractCoverFromM4A(path); err != nil || !bytes.Equal(image, cover) {
		t.Fatalf("extractCoverFromM4A = %#v/%v", image, err)
	}
	if pathInfo, err := func() (m4aMetadataPath, error) {
		f, err := os.Open(path)
		if err != nil {
			return m4aMetadataPath{}, err
		}
		defer f.Close()
		info, _ := f.Stat()
		return findM4AMetadataPath(f, info.Size())
	}(); err != nil || pathInfo.udta == nil {
		t.Fatalf("findM4AMetadataPath = %#v/%v", pathInfo, err)
	}
	if err := EditM4AReplayGain(path, map[string]string{"replaygain_track_gain": "-5.00 dB", "replaygain_track_peak": "0.98"}); err != nil {
		t.Fatalf("EditM4AReplayGain: %v", err)
	}
	edited, err := ReadM4ATags(path)
	if err != nil || edited.ReplayGainTrackGain != "-5.00 dB" || edited.ReplayGainTrackPeak != "0.98" {
		t.Fatalf("edited M4A = %#v/%v", edited, err)
	}

	noUdtaPath := filepath.Join(dir, "noudta.m4a")
	if err := os.WriteFile(noUdtaPath, buildM4AFileWithIlst(buildM4ATextTag("\xa9nam", "No Udta"), false), 0600); err != nil {
		t.Fatal(err)
	}
	if meta, err := ReadM4ATags(noUdtaPath); err != nil || meta.Title != "No Udta" {
		t.Fatalf("ReadM4ATags no udta = %#v/%v", meta, err)
	}
	if _, err := ReadM4ATags(filepath.Join(dir, "missing.m4a")); err == nil {
		t.Fatal("expected missing M4A error")
	}
	emptyM4A := filepath.Join(dir, "empty.m4a")
	if err := os.WriteFile(emptyM4A, buildM4AFileWithIlst(nil, true), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadM4ATags(emptyM4A); err == nil {
		t.Fatal("expected empty M4A tags error")
	}
	if _, err := extractCoverFromM4A(emptyM4A); err == nil {
		t.Fatal("expected missing M4A cover error")
	}
	if _, err := extractLyricsFromM4A(emptyM4A); err == nil {
		t.Fatal("expected missing M4A lyrics error")
	}

	sidecarAudio := filepath.Join(dir, "sidecar.mp3")
	if err := os.WriteFile(sidecarAudio, []byte("audio"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "sidecar.lrc"), []byte(" [00:00.00]Sidecar "), 0600); err != nil {
		t.Fatal(err)
	}
	if lyrics, err := extractLyricsFromSidecarLRC(sidecarAudio); err != nil || !strings.Contains(lyrics, "Sidecar") {
		t.Fatalf("sidecar lyrics = %q/%v", lyrics, err)
	}
	if !looksLikeEmbeddedLyrics("[ti:Song]") || !looksLikeEmbeddedLyrics("[00:00.00]Line\n[00:01.00]Next") || looksLikeEmbeddedLyrics("plain") {
		t.Fatal("embedded lyric heuristic mismatch")
	}
	if formatIndexValue(3, 12) != "3/12" || formatIndexValue(3, 0) != "3" || formatIndexValue(0, 12) != "" {
		t.Fatal("formatIndexValue mismatch")
	}
	if parsePositiveInt(" 42 ") != 42 || parsePositiveInt("bad") != 0 {
		t.Fatal("parsePositiveInt mismatch")
	}
	if !hasMapKey(map[string]string{"x": "y"}, "x") {
		t.Fatal("expected map key")
	}
	if _, ok := parseReplayGainDb("-6.50 dB"); !ok {
		t.Fatal("expected ReplayGain dB parse")
	}
	if _, ok := parseReplayGainPeak("0.98"); !ok {
		t.Fatal("expected ReplayGain peak parse")
	}
	if norm := buildITunNORMTag("-6.50 dB", "0.98"); norm == "" {
		t.Fatal("expected iTunNORM")
	}
	if fields := collectM4AReplayGainFields(map[string]string{"replaygain_track_gain": "-6 dB", "replaygain_track_peak": "0.9"}); fields["iTunNORM"] == "" {
		t.Fatalf("ReplayGain fields = %#v", fields)
	}

	qualityPath := filepath.Join(dir, "quality-alac.m4a")
	mvhd := make([]byte, 20)
	binary.BigEndian.PutUint32(mvhd[12:16], 1000)
	binary.BigEndian.PutUint32(mvhd[16:20], 180000)
	sampleEntry := make([]byte, 32)
	copy(sampleEntry[0:4], "alac")
	binary.BigEndian.PutUint16(sampleEntry[22:24], 24)
	sampleEntry[28] = 0xAC
	sampleEntry[29] = 0x44
	alacConfig := make([]byte, 24)
	alacConfig[5] = 24
	binary.BigEndian.PutUint32(alacConfig[20:24], 44100)
	alacEntryPayload := append(append([]byte{}, sampleEntry[4:]...), buildM4AAtom("alac", alacConfig)...)
	qualityFile := append(buildM4AAtom("ftyp", []byte("M4A \x00\x00\x00\x00")), buildM4AAtom("moov", append(buildM4AAtom("mvhd", mvhd), buildM4AAtom("alac", alacEntryPayload)...))...)
	if err := os.WriteFile(qualityPath, qualityFile, 0600); err != nil {
		t.Fatal(err)
	}
	if quality, err := GetM4AQuality(qualityPath); err != nil || quality.BitDepth != 24 || quality.SampleRate != 44100 || quality.Duration != 180 {
		t.Fatalf("GetM4AQuality = %#v/%v", quality, err)
	}
	if quality, err := GetAudioQuality(qualityPath); err != nil || quality.SampleRate != 44100 {
		t.Fatalf("GetAudioQuality M4A = %#v/%v", quality, err)
	}
	aacQualityPath := filepath.Join(dir, "quality-aac.m4a")
	copy(sampleEntry[0:4], "mp4a")
	aacQualityFile := append(buildM4AAtom("ftyp", []byte("M4A \x00\x00\x00\x00")), buildM4AAtom("moov", append(buildM4AAtom("mvhd", mvhd), sampleEntry...))...)
	if err := os.WriteFile(aacQualityPath, aacQualityFile, 0600); err != nil {
		t.Fatal(err)
	}
	if quality, err := GetM4AQuality(aacQualityPath); err != nil || quality.BitDepth != 0 || quality.SampleRate != 44100 || quality.Duration != 180 {
		t.Fatalf("GetM4AQuality AAC = %#v/%v", quality, err)
	}
	eac3QualityPath := filepath.Join(dir, "quality-eac3.m4a")
	zeroMvhd := make([]byte, 20)
	eac3SampleEntry := make([]byte, 32)
	copy(eac3SampleEntry[0:4], "ec-3")
	eac3SampleEntry[28] = 0xBB
	eac3SampleEntry[29] = 0x80
	mdhd := make([]byte, 20)
	binary.BigEndian.PutUint32(mdhd[12:16], 48000)
	binary.BigEndian.PutUint32(mdhd[16:20], 48000*123)
	eac3QualityFile := append(
		buildM4AAtom("ftyp", []byte("M4A \x00\x00\x00\x00")),
		buildM4AAtom("moov", append(
			append(buildM4AAtom("mvhd", zeroMvhd), buildM4AAtom("trak", buildM4AAtom("mdia", buildM4AAtom("mdhd", mdhd)))...),
			eac3SampleEntry...,
		))...,
	)
	if err := os.WriteFile(eac3QualityPath, eac3QualityFile, 0600); err != nil {
		t.Fatal(err)
	}
	if quality, err := GetM4AQuality(eac3QualityPath); err != nil || quality.Codec != "eac3" || quality.Duration != 123 {
		t.Fatalf("GetM4AQuality EAC3 mdhd fallback = %#v/%v", quality, err)
	}
	if _, _, ok := parseALACSpecificConfig(make([]byte, 4)); ok {
		t.Fatal("short ALAC config should not parse")
	}
	alac := make([]byte, 24)
	alac[5] = 16
	binary.BigEndian.PutUint32(alac[20:24], 48000)
	if depth, rate, ok := parseALACSpecificConfig(alac); !ok || depth != 16 || rate != 48000 {
		t.Fatalf("ALAC config = %d/%d/%v", depth, rate, ok)
	}
}

func TestOggMetadataQualityAndCoverHelpers(t *testing.T) {
	dir := t.TempDir()
	opusHead := make([]byte, 19)
	copy(opusHead[0:8], "OpusHead")
	binary.LittleEndian.PutUint16(opusHead[10:12], 312)
	binary.LittleEndian.PutUint32(opusHead[12:16], 48000)

	var comments bytes.Buffer
	binary.Write(&comments, binary.LittleEndian, uint32(6))
	comments.WriteString("vendor")
	entries := []string{
		"TITLE=Ogg Title",
		"ARTIST=Artist",
		"ALBUMARTIST=Album Artist",
		"TRACKNUMBER=2/9",
		"DISCNUMBER=1/2",
		"LYRICS=[00:00.00]Ogg Lyrics",
	}
	binary.Write(&comments, binary.LittleEndian, uint32(len(entries)))
	for _, entry := range entries {
		binary.Write(&comments, binary.LittleEndian, uint32(len(entry)))
		comments.WriteString(entry)
	}
	opusTags := append([]byte("OpusTags"), comments.Bytes()...)
	oggPath := filepath.Join(dir, "tagged.opus")
	oggData := append(buildOggPage(0x02, 0, opusHead), buildOggPage(0x00, 48000+312, opusTags)...)
	if err := os.WriteFile(oggPath, oggData, 0600); err != nil {
		t.Fatal(err)
	}
	quality, err := GetOggQuality(oggPath)
	if err != nil || quality.SampleRate != 48000 || quality.Duration != 1 {
		t.Fatalf("GetOggQuality = %#v/%v", quality, err)
	}
	meta, err := ReadOggVorbisComments(oggPath)
	if err != nil || meta.Title != "Ogg Title" || meta.TrackNumber != 2 || meta.TotalTracks != 9 {
		t.Fatalf("ReadOggVorbisComments = %#v/%v", meta, err)
	}

	picture := buildTestFLACPictureBlock([]byte{0x89, 0x50, 0x4E, 0x47}, "image/png")
	pictureComment := "METADATA_BLOCK_PICTURE=" + base64.StdEncoding.EncodeToString(picture)
	var coverComments bytes.Buffer
	binary.Write(&coverComments, binary.LittleEndian, uint32(6))
	coverComments.WriteString("vendor")
	binary.Write(&coverComments, binary.LittleEndian, uint32(1))
	binary.Write(&coverComments, binary.LittleEndian, uint32(len(pictureComment)))
	coverComments.WriteString(pictureComment)
	coverPath := filepath.Join(dir, "cover.opus")
	coverData := append(buildOggPage(0x02, 0, opusHead), buildOggPage(0x00, 48000+312, append([]byte("OpusTags"), coverComments.Bytes()...))...)
	if err := os.WriteFile(coverPath, coverData, 0600); err != nil {
		t.Fatal(err)
	}
	if image, mime, err := extractOggCoverArt(coverPath); err != nil || mime != "image/png" || len(image) == 0 {
		t.Fatalf("extractOggCoverArt = %s/%#v/%v", mime, image, err)
	}
	if image, mime, err := extractAnyCoverArtWithHint(coverPath, "cover.opus"); err != nil || mime != "image/png" || len(image) == 0 {
		t.Fatalf("extractAnyCoverArtWithHint = %s/%#v/%v", mime, image, err)
	}
	if image, mime, err := extractAnyCoverArt(coverPath); err != nil || mime != "image/png" || len(image) == 0 {
		t.Fatalf("extractAnyCoverArt = %s/%#v/%v", mime, image, err)
	}
	extractedCoverPath := filepath.Join(dir, "extracted.png")
	if err := ExtractCoverToFile(coverPath, extractedCoverPath); err != nil {
		t.Fatalf("ExtractCoverToFile = %v", err)
	}
	if data := mustReadFile(t, extractedCoverPath); len(data) == 0 {
		t.Fatal("expected extracted cover data")
	}
	cachePath, err := SaveCoverToCacheWithHintAndKey(coverPath, "cover.opus", dir, "key")
	if err != nil || cachePath == "" {
		t.Fatalf("SaveCoverToCacheWithHintAndKey = %q/%v", cachePath, err)
	}
	cacheDir := filepath.Join(dir, "cache")
	if path, err := SaveCoverToCache(coverPath, cacheDir); err != nil || !strings.HasSuffix(path, ".png") {
		t.Fatalf("SaveCoverToCache = %q/%v", path, err)
	}
	if path, err := SaveCoverToCacheWithHint(coverPath, "cover.opus", cacheDir); err != nil || path == "" {
		t.Fatalf("SaveCoverToCacheWithHint = %q/%v", path, err)
	}
	hitPath, err := SaveCoverToCache(coverPath, cacheDir)
	if err != nil || hitPath == "" {
		t.Fatalf("SaveCoverToCache cache hit = %q/%v", hitPath, err)
	}
	if _, err := SaveCoverToCacheWithHintAndKey(filepath.Join(dir, "missing.opus"), "missing.opus", dir, "missing"); err == nil {
		t.Fatal("expected missing cover cache error")
	}

	badPath := filepath.Join(dir, "bad.ogg")
	if err := os.WriteFile(badPath, []byte("bad"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := GetOggQuality(badPath); err == nil {
		t.Fatal("expected invalid Ogg quality error")
	}
}

func buildM4ADataPayload(payload []byte) []byte {
	return append([]byte{0, 0, 0, 1, 0, 0, 0, 0}, payload...)
}

func buildM4ATextTag(atomType, value string) []byte {
	return buildM4AAtom(atomType, buildM4AAtom("data", buildM4ADataPayload([]byte(value))))
}

func buildM4AIndexTag(atomType string, number, total int) []byte {
	payload := []byte{0, 0, 0, byte(number), 0, byte(total), 0, 0}
	return buildM4AAtom(atomType, buildM4AAtom("data", buildM4ADataPayload(payload)))
}

func buildM4AFileWithIlst(ilstPayload []byte, withUdta bool) []byte {
	ilst := buildM4AAtom("ilst", ilstPayload)
	meta := buildM4AAtom("meta", append([]byte{0, 0, 0, 0}, ilst...))
	moovPayload := meta
	if withUdta {
		moovPayload = buildM4AAtom("udta", meta)
	}
	return append(buildM4AAtom("ftyp", []byte("M4A \x00\x00\x00\x00")), buildM4AAtom("moov", moovPayload)...)
}

func buildOggPage(headerType byte, granule uint64, packet []byte) []byte {
	header := make([]byte, 27)
	copy(header[0:4], "OggS")
	header[4] = 0
	header[5] = headerType
	binary.LittleEndian.PutUint64(header[6:14], granule)
	header[26] = 1
	return append(append(header, byte(len(packet))), packet...)
}

func buildTestFLACPictureBlock(image []byte, mime string) []byte {
	var picture bytes.Buffer
	binary.Write(&picture, binary.BigEndian, uint32(3))
	binary.Write(&picture, binary.BigEndian, uint32(len(mime)))
	picture.WriteString(mime)
	binary.Write(&picture, binary.BigEndian, uint32(0))
	binary.Write(&picture, binary.BigEndian, uint32(1))
	binary.Write(&picture, binary.BigEndian, uint32(1))
	binary.Write(&picture, binary.BigEndian, uint32(32))
	binary.Write(&picture, binary.BigEndian, uint32(0))
	binary.Write(&picture, binary.BigEndian, uint32(len(image)))
	picture.Write(image)
	return picture.Bytes()
}
