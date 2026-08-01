package gobackend

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

var lrcLinePattern = regexp.MustCompile(`\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)`)

var (
	rawLyricsMetadataLinePattern = regexp.MustCompile(`(?i)^\[[a-z][a-z0-9_]*:.*\]$`)
	rawLyricsBackgroundPattern   = regexp.MustCompile(`(?i)^\[bg:(.*)\]$`)
	rawLyricsTimestampPattern    = regexp.MustCompile(`^\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]`)
	rawLyricsInlineTimePattern   = regexp.MustCompile(`<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>`)
)

func isInstrumentalLyricsMarker(raw string) bool {
	return strings.EqualFold(strings.TrimSpace(raw), "[instrumental:true]")
}

// rawLyricsHasUsableContent rejects LRC payloads that contain only metadata
// headers. Those payloads are common in partially tagged files and must not be
// exposed as a blank "Embedded" lyrics result.
func rawLyricsHasUsableContent(raw string) bool {
	if isInstrumentalLyricsMarker(raw) {
		return true
	}

	for _, line := range strings.Split(raw, "\n") {
		cleaned := strings.TrimSpace(line)
		if cleaned == "" {
			continue
		}

		if match := rawLyricsBackgroundPattern.FindStringSubmatch(cleaned); len(match) == 2 {
			cleaned = strings.TrimSpace(match[1])
		} else if rawLyricsMetadataLinePattern.MatchString(cleaned) {
			continue
		}

		for rawLyricsTimestampPattern.MatchString(cleaned) {
			cleaned = strings.TrimSpace(rawLyricsTimestampPattern.ReplaceAllString(cleaned, ""))
		}
		cleaned = strings.TrimSpace(rawLyricsInlineTimePattern.ReplaceAllString(cleaned, ""))
		lower := strings.ToLower(cleaned)
		if strings.HasPrefix(lower, "v1:") || strings.HasPrefix(lower, "v2:") {
			cleaned = strings.TrimSpace(cleaned[3:])
		}
		if cleaned != "" {
			return true
		}
	}

	return false
}

func parseSyncedLyrics(syncedLyrics string) []LyricsLine {
	var lines []LyricsLine

	for _, line := range strings.Split(syncedLyrics, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Preserve Apple/QQ background vocal tags by attaching them to
		// the previous timed line. This keeps [bg:...] in final exported LRC.
		if strings.HasPrefix(line, "[bg:") && len(lines) > 0 {
			lines[len(lines)-1].Words = strings.TrimSpace(lines[len(lines)-1].Words + "\n" + line)
			continue
		}

		matches := lrcLinePattern.FindStringSubmatch(line)
		if len(matches) == 5 {
			startMs := lrcTimestampToMs(matches[1], matches[2], matches[3])
			words := strings.TrimSpace(matches[4])
			if words == "" {
				continue
			}

			lines = append(lines, LyricsLine{
				StartTimeMs: startMs,
				Words:       words,
				EndTimeMs:   0,
			})
		}
	}

	for i := 0; i < len(lines)-1; i++ {
		lines[i].EndTimeMs = lines[i+1].StartTimeMs
	}

	if len(lines) > 0 {
		lines[len(lines)-1].EndTimeMs = lines[len(lines)-1].StartTimeMs + 5000
	}

	return lines
}

func plainTextLyricsLines(rawLyrics string) []LyricsLine {
	var lines []LyricsLine
	for _, line := range strings.Split(rawLyrics, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		lines = append(lines, LyricsLine{
			StartTimeMs: 0,
			Words:       trimmed,
			EndTimeMs:   0,
		})
	}
	return lines
}

func lyricsHasUsableText(lyrics *LyricsResponse) bool {
	if lyrics == nil {
		return false
	}
	if lyrics.Instrumental {
		return true
	}
	if strings.TrimSpace(lyrics.PlainLyrics) != "" {
		return true
	}
	for _, line := range lyrics.Lines {
		if strings.TrimSpace(line.Words) != "" {
			return true
		}
	}
	return false
}

func detectLyricsErrorPayload(raw string) (string, bool) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" || !strings.HasPrefix(trimmed, "{") {
		return "", false
	}

	var payload map[string]any
	if err := json.Unmarshal([]byte(trimmed), &payload); err != nil {
		return "", false
	}

	lyricsKeys := []string{"lyrics", "lyric", "lrc", "content", "lines", "syncedLyrics", "unsyncedLyrics"}
	hasLyricsKey := false
	for _, key := range lyricsKeys {
		if _, ok := payload[key]; ok {
			hasLyricsKey = true
			break
		}
	}

	errorKeys := []string{"message", "error", "detail", "reason"}
	for _, key := range errorKeys {
		if msg, ok := payload[key].(string); ok {
			msg = strings.TrimSpace(msg)
			if msg != "" && !hasLyricsKey {
				return msg, true
			}
		}
	}

	if success, ok := payload["success"].(bool); ok && !success && !hasLyricsKey {
		return "request unsuccessful", true
	}
	if isError, ok := payload["isError"].(bool); ok && isError && !hasLyricsKey {
		return "request unsuccessful", true
	}
	if code, ok := payload["code"].(float64); ok && code != 0 && code != 200 && !hasLyricsKey {
		if msg, ok := payload["message"].(string); ok && strings.TrimSpace(msg) != "" {
			return strings.TrimSpace(msg), true
		}
		if msg, ok := payload["msg"].(string); ok && strings.TrimSpace(msg) != "" {
			return strings.TrimSpace(msg), true
		}
		return fmt.Sprintf("unexpected response code %.0f", code), true
	}

	return "", false
}

func lrcTimestampToMs(minutes, seconds, centiseconds string) int64 {
	min, _ := strconv.ParseInt(minutes, 10, 64)
	sec, _ := strconv.ParseInt(seconds, 10, 64)
	cs, _ := strconv.ParseInt(centiseconds, 10, 64)

	if len(centiseconds) == 2 {
		cs *= 10
	}

	return min*60*1000 + sec*1000 + cs
}

func msToLRCTimestamp(ms int64) string {
	return fmt.Sprintf("[%s]", msToLRCTimestampInline(ms))
}

func msToLRCTimestampInline(ms int64) string {
	totalSeconds := ms / 1000
	minutes := totalSeconds / 60
	seconds := totalSeconds % 60
	centiseconds := (ms % 1000) / 10

	return fmt.Sprintf("%02d:%02d.%02d", minutes, seconds, centiseconds)
}

// extractLyricsSourceFromLRC reads the provider recorded in the LRC [by:] tag,
// e.g. "[by:SpotiFLAC-Mobile (source: LRCLIB)]". Returns "" when absent.
const lrcSourceMarker = "(source: "

func lyricsSourceUsesPaxsenix(source string) bool {
	s := strings.ToLower(strings.TrimSpace(source))
	if s == "" {
		return false
	}
	if strings.HasPrefix(s, "lrclib") ||
		strings.HasPrefix(s, "extension:") ||
		strings.HasPrefix(s, "heuristic") {
		return false
	}
	return true
}

func extractLyricsSourceFromLRC(lrc string) string {
	for _, line := range strings.Split(lrc, "\n") {
		trimmed := strings.TrimSpace(line)
		if !strings.HasPrefix(strings.ToLower(trimmed), "[by:") {
			continue
		}
		idx := strings.Index(trimmed, lrcSourceMarker)
		if idx < 0 {
			return ""
		}
		rest := strings.TrimSpace(trimmed[idx+len(lrcSourceMarker):])
		rest = strings.TrimSuffix(rest, "]")
		rest = strings.TrimSuffix(rest, ")")
		return strings.TrimSpace(rest)
	}
	return ""
}

func convertToLRCWithMetadata(lyrics *LyricsResponse, trackName, artistName string) string {
	if lyrics == nil || len(lyrics.Lines) == 0 {
		return ""
	}

	var builder strings.Builder

	builder.WriteString(fmt.Sprintf("[ti:%s]\n", trackName))
	builder.WriteString(fmt.Sprintf("[ar:%s]\n", artistName))
	source := strings.TrimSpace(lyrics.Source)
	if source == "" {
		source = strings.TrimSpace(lyrics.Provider)
	}
	credit := "SpotiFLAC-Mobile"
	if lyricsSourceUsesPaxsenix(source) {
		credit = "SpotiFLAC-Mobile via Paxsenix API"
	}
	if source == "" {
		builder.WriteString(fmt.Sprintf("[by:%s]\n", credit))
	} else {
		builder.WriteString(
			fmt.Sprintf("[by:%s %s%s)]\n", credit, lrcSourceMarker, source),
		)
	}
	builder.WriteString("\n")

	if lyrics.SyncType == "LINE_SYNCED" {
		for _, line := range lyrics.Lines {
			if line.Words == "" {
				continue
			}
			timestamp := msToLRCTimestamp(line.StartTimeMs)
			builder.WriteString(timestamp)
			builder.WriteString(line.Words)
			builder.WriteString("\n")
		}
	} else {
		for _, line := range lyrics.Lines {
			if line.Words == "" {
				continue
			}
			builder.WriteString(line.Words)
			builder.WriteString("\n")
		}
	}

	return builder.String()
}

func SaveLRCFile(audioFilePath, lrcContent string) (string, error) {
	if lrcContent == "" {
		return "", fmt.Errorf("empty LRC content")
	}

	dir := filepath.Dir(audioFilePath)
	ext := filepath.Ext(audioFilePath)
	baseName := strings.TrimSuffix(filepath.Base(audioFilePath), ext)

	lrcFilePath := filepath.Join(dir, baseName+".lrc")

	if err := os.WriteFile(lrcFilePath, []byte(lrcContent), 0644); err != nil {
		return "", fmt.Errorf("failed to write LRC file: %w", err)
	}

	GoLog("[Lyrics] Saved LRC file: %s\n", lrcFilePath)
	return lrcFilePath, nil
}
