package gobackend

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestCueParserEndToEnd(t *testing.T) {
	dir := t.TempDir()
	audioPath := filepath.Join(dir, "album.wav")
	if err := os.WriteFile(audioPath, []byte("audio"), 0600); err != nil {
		t.Fatalf("write audio: %v", err)
	}
	cuePath := filepath.Join(dir, "album.cue")
	cue := "\ufeffREM GENRE \"Pop\"\n" +
		"REM DATE 2026\n" +
		"REM COMMENT \"comment\"\n" +
		"REM COMPOSER \"Album Composer\"\n" +
		"PERFORMER \"Album Artist\"\n" +
		"TITLE \"Album Title\"\n" +
		"FILE \"album.wav\" WAVE\n" +
		"  TRACK 01 AUDIO\n" +
		"    TITLE \"First\"\n" +
		"    PERFORMER \"Track Artist\"\n" +
		"    ISRC USRC17607839\n" +
		"    INDEX 01 00:00:00\n" +
		"  TRACK 02 AUDIO\n" +
		"    TITLE \"Second\"\n" +
		"    SONGWRITER \"Track Composer\"\n" +
		"    INDEX 00 03:00:00\n" +
		"    INDEX 01 03:05:00\n"
	if err := os.WriteFile(cuePath, []byte(cue), 0600); err != nil {
		t.Fatalf("write cue: %v", err)
	}

	sheet, err := ParseCueFile(cuePath)
	if err != nil {
		t.Fatalf("ParseCueFile: %v", err)
	}
	if sheet.Performer != "Album Artist" || sheet.Title != "Album Title" || len(sheet.Tracks) != 2 {
		t.Fatalf("sheet = %#v", sheet)
	}
	if got := parseCueTimestamp("01:02:37"); got <= 62 || got >= 63 {
		t.Fatalf("timestamp = %f", got)
	}
	if got := formatCueTimestamp(3723.5); got != "01:02:03.500" {
		t.Fatalf("format timestamp = %q", got)
	}
	if got := unquoteCue("  \"quoted\"  "); got != "quoted" {
		t.Fatalf("unquote = %q", got)
	}
	fileName, fileType := parseCueFileLine("unquoted album.flac FLAC")
	if fileName != "unquoted album.flac" || fileType != "FLAC" {
		t.Fatalf("file line = %q/%q", fileName, fileType)
	}

	if resolved := ResolveCueAudioPath(cuePath, "album.flac"); resolved != audioPath {
		t.Fatalf("resolved = %q want %q", resolved, audioPath)
	}
	info, err := BuildCueSplitInfo(cuePath, sheet, "")
	if err != nil {
		t.Fatalf("BuildCueSplitInfo: %v", err)
	}
	if info.Tracks[0].EndSec != 180 || info.Tracks[1].Composer != "Track Composer" {
		t.Fatalf("split info = %#v", info.Tracks)
	}

	jsonText, err := ParseCueFileJSON(cuePath, "")
	if err != nil {
		t.Fatalf("ParseCueFileJSON: %v", err)
	}
	var decoded CueSplitInfo
	if err := json.Unmarshal([]byte(jsonText), &decoded); err != nil {
		t.Fatalf("decode cue json: %v", err)
	}
	if decoded.AudioPath != audioPath {
		t.Fatalf("decoded audio path = %q", decoded.AudioPath)
	}

	results, err := ScanCueFileForLibraryExt(cuePath, "", "virtual/album.cue", 1234, "scan-time")
	if err != nil {
		t.Fatalf("ScanCueFileForLibraryExt: %v", err)
	}
	if len(results) != 2 || results[0].TrackName != "First" || results[0].Duration != 180 {
		t.Fatalf("scan results = %#v", results)
	}
	if results[0].FilePath != "virtual/album.cue#track01" || results[0].Format != "cue+wav" {
		t.Fatalf("scan path/format = %q/%q", results[0].FilePath, results[0].Format)
	}

	if _, err := ParseCueFile(filepath.Join(dir, "missing.cue")); err == nil {
		t.Fatal("expected missing cue error")
	}
	emptyCue := filepath.Join(dir, "empty.cue")
	if err := os.WriteFile(emptyCue, []byte("TITLE \"No tracks\""), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := ParseCueFile(emptyCue); err == nil {
		t.Fatal("expected no tracks error")
	}
	missingDir := t.TempDir()
	missingCuePath := filepath.Join(missingDir, "missing.cue")
	if err := os.WriteFile(missingCuePath, []byte(cue), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := BuildCueSplitInfo(missingCuePath, &CueSheet{FileName: "missing.wav"}, ""); err == nil {
		t.Fatal("expected missing audio error")
	}
	if _, err := resolveCueAudioPathForLibrary(cuePath, nil, ""); err == nil {
		t.Fatal("expected nil sheet error")
	}
	if _, err := scanCueSheetForLibrary(cuePath, nil, audioPath, "", 0, "", ""); err == nil {
		t.Fatal("expected nil scan sheet error")
	}
}

func writeTestFlacWithISRC(t *testing.T, path, isrc string) {
	t.Helper()
	le32 := func(v int) []byte {
		return []byte{byte(v), byte(v >> 8), byte(v >> 16), byte(v >> 24)}
	}
	vendor := "test-vendor"
	comments := [][]byte{
		[]byte("TITLE=Song"),
		[]byte("ISRC=" + isrc),
	}
	var vorbis []byte
	vorbis = append(vorbis, le32(len(vendor))...)
	vorbis = append(vorbis, vendor...)
	vorbis = append(vorbis, le32(len(comments))...)
	for _, comment := range comments {
		vorbis = append(vorbis, le32(len(comment))...)
		vorbis = append(vorbis, comment...)
	}

	blockHeader := func(last bool, blockType byte, length int) []byte {
		first := blockType
		if last {
			first |= 0x80
		}
		return []byte{first, byte(length >> 16), byte(length >> 8), byte(length)}
	}

	var data []byte
	data = append(data, "fLaC"...)
	data = append(data, blockHeader(false, 0, 34)...) // STREAMINFO
	data = append(data, make([]byte, 34)...)
	picture := make([]byte, 4096) // stands in for embedded cover art
	data = append(data, blockHeader(false, 6, len(picture))...)
	data = append(data, picture...)
	data = append(data, blockHeader(true, 4, len(vorbis))...)
	data = append(data, vorbis...)

	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
}

func TestISRCIndexCoversNonFlacFormats(t *testing.T) {
	dir := t.TempDir()
	flacPath := filepath.Join(dir, "a.flac")
	mp3Path := filepath.Join(dir, "b.mp3")
	writeTestFlacWithISRC(t, flacPath, "USAA00000011")
	mp3Data := buildID3v23Tag(
		id3TextFrame("TIT2", "Song"),
		id3TextFrame("TSRC", "usbb00000022"),
	)
	if err := os.WriteFile(mp3Path, mp3Data, 0600); err != nil {
		t.Fatal(err)
	}
	// Unsupported/untagged formats must stay invisible to the index.
	if err := os.WriteFile(filepath.Join(dir, "c.wav"), []byte("RIFF"), 0600); err != nil {
		t.Fatal(err)
	}
	defer InvalidateISRCCache(dir)

	if got := readFileISRC(mp3Path); got != "usbb00000022" {
		t.Fatalf("readFileISRC mp3 = %q", got)
	}
	if got := readFileISRC(filepath.Join(dir, "c.wav")); got != "" {
		t.Fatalf("readFileISRC wav = %q", got)
	}

	idx := buildISRCIndex(dir)
	if path, ok := idx.lookup("USAA00000011"); !ok || path != flacPath {
		t.Fatalf("flac lookup = %q/%v", path, ok)
	}
	if path, ok := idx.lookup("USBB00000022"); !ok || path != mp3Path {
		t.Fatalf("mp3 lookup = %q/%v", path, ok)
	}
}

func TestISRCIndexIncrementalRebuild(t *testing.T) {
	dir := t.TempDir()
	trackA := filepath.Join(dir, "a.flac")
	trackB := filepath.Join(dir, "b.flac")
	writeTestFlacWithISRC(t, trackA, "USAA00000001")
	writeTestFlacWithISRC(t, trackB, "USBB00000002")
	defer InvalidateISRCCache(dir)

	if got := readFlacISRC(trackA); got != "USAA00000001" {
		t.Fatalf("readFlacISRC = %q", got)
	}
	if got := readFlacISRC(filepath.Join(dir, "missing.flac")); got != "" {
		t.Fatalf("expected empty ISRC for missing file, got %q", got)
	}

	idx := buildISRCIndex(dir)
	if path, ok := idx.lookup("usaa00000001"); !ok || path != trackA {
		t.Fatalf("lookup A = %q/%v", path, ok)
	}
	if path, ok := idx.lookup("USBB00000002"); !ok || path != trackB {
		t.Fatalf("lookup B = %q/%v", path, ok)
	}

	// Change one file's tag (and mtime); an incremental rebuild must pick up
	// the change while adopting the untouched file from the cache.
	writeTestFlacWithISRC(t, trackB, "USBB00000099")
	future := time.Now().Add(2 * time.Second)
	if err := os.Chtimes(trackB, future, future); err != nil {
		t.Fatal(err)
	}
	rebuilt := buildISRCIndex(dir)
	if _, ok := rebuilt.lookup("USBB00000002"); ok {
		t.Fatal("expected stale ISRC to disappear after rebuild")
	}
	if path, ok := rebuilt.lookup("USBB00000099"); !ok || path != trackB {
		t.Fatalf("rebuilt lookup = %q/%v", path, ok)
	}
	if path, ok := rebuilt.lookup("USAA00000001"); !ok || path != trackA {
		t.Fatalf("cached entry lost on rebuild: %q/%v", path, ok)
	}

	// Add() keeps the index fresh so the TTL never forces a rebuild while
	// downloads are actively maintaining it.
	rebuilt.buildTime.Store(time.Now().Add(-isrcIndexTTL - time.Minute).UnixNano())
	if rebuilt.isFresh() {
		t.Fatal("expected stale index")
	}
	rebuilt.Add("USCC00000003", trackA)
	if !rebuilt.isFresh() {
		t.Fatal("expected Add to refresh the index timestamp")
	}
}

func TestDuplicateIndexAndParallelExistence(t *testing.T) {
	dir := t.TempDir()
	filePath := filepath.Join(dir, "song.flac")
	if err := os.WriteFile(filePath, []byte("audio"), 0600); err != nil {
		t.Fatal(err)
	}

	idx := &ISRCIndex{index: map[string]string{}, outputDir: dir}
	idx.buildTime.Store(time.Now().UnixNano())
	idx.Add("usrc17607839", filePath)
	if got, ok := idx.lookup("USRC17607839"); !ok || got != filePath {
		t.Fatalf("lookup = %q/%v", got, ok)
	}
	if got, err := idx.Lookup("usrc17607839"); err != nil || got != filePath {
		t.Fatalf("Lookup = %q/%v", got, err)
	}
	idx.remove("usrc17607839")
	if _, ok := idx.lookup("usrc17607839"); ok {
		t.Fatal("expected removed ISRC")
	}

	isrcIndexCacheMu.Lock()
	isrcIndexCache[dir] = idx
	isrcIndexCacheMu.Unlock()
	defer InvalidateISRCCache(dir)

	AddToISRCIndex(dir, "USRC17607839", filePath)
	if found, err := CheckISRCExists(dir, "USRC17607839"); err != nil || found != filePath {
		t.Fatalf("CheckISRCExists = %q/%v", found, err)
	}
	if !CheckFileExists(filePath) || CheckFileExists(dir) || CheckFileExists(filepath.Join(dir, "missing.flac")) {
		t.Fatal("unexpected file existence result")
	}

	tracksJSON := `[{"isrc":"USRC17607839","track_name":"Song","artist_name":"Artist"},{"isrc":"MISSING","track_name":"Other","artist_name":"Artist"}]`
	resultJSON, err := CheckFilesExistParallel(dir, tracksJSON)
	if err != nil {
		t.Fatalf("CheckFilesExistParallel: %v", err)
	}
	var results []FileExistenceResult
	if err := json.Unmarshal([]byte(resultJSON), &results); err != nil {
		t.Fatalf("decode results: %v", err)
	}
	if !results[0].Exists || results[0].FilePath != filePath || results[1].Exists {
		t.Fatalf("results = %#v", results)
	}
	if _, err := CheckFilesExistParallel(dir, `not-json`); err == nil {
		t.Fatal("expected invalid json error")
	}
	if err := PreBuildISRCIndex(""); err == nil {
		t.Fatal("expected empty dir error")
	}
}
