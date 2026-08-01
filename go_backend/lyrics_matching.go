package gobackend

import (
	"math"
	"regexp"
	"strings"
)

var simplifyTrackNamePatterns = func() []*regexp.Regexp {
	patterns := []string{
		`\s*\(feat\.?.*?\)`,
		`\s*\(ft\.?.*?\)`,
		`\s*\(featuring.*?\)`,
		`\s*\(with.*?\)`,
		`\s*-\s*Remaster(ed)?.*$`,
		`\s*-\s*\d{4}\s*Remaster.*$`,
		`\s*\(Remaster(ed)?.*?\)`,
		`\s*\(Deluxe.*?\)`,
		`\s*\(Bonus.*?\)`,
		`\s*\(Live.*?\)`,
		`\s*\(Acoustic.*?\)`,
		`\s*\(Radio Edit\)`,
		`\s*\(Single Version\)`,
	}
	compiled := make([]*regexp.Regexp, len(patterns))
	for i, pattern := range patterns {
		compiled[i] = regexp.MustCompile("(?i)" + pattern)
	}
	return compiled
}()

func simplifyTrackName(name string) string {
	result := name
	for _, re := range simplifyTrackNamePatterns {
		result = re.ReplaceAllString(result, "")
	}
	result = strings.TrimSpace(result)
	if result == "" {
		return result
	}

	if loose := normalizeLooseTitle(result); loose != "" {
		return loose
	}

	return result
}

func normalizedLyricsSearchTitle(name string) string {
	return strings.ToLower(strings.TrimSpace(simplifyTrackName(name)))
}

func containsWordSequence(value, sequence string) bool {
	valueWords := strings.Fields(value)
	sequenceWords := strings.Fields(sequence)
	if len(valueWords) == 0 || len(sequenceWords) == 0 || len(sequenceWords) > len(valueWords) {
		return false
	}

	for start := 0; start <= len(valueWords)-len(sequenceWords); start++ {
		matches := true
		for offset := range sequenceWords {
			if valueWords[start+offset] != sequenceWords[offset] {
				matches = false
				break
			}
		}
		if matches {
			return true
		}
	}
	return false
}

func lyricsSearchTitlesMatch(candidateTrack, trackName string, allowDecoratedCandidate bool) bool {
	expected := normalizedLyricsSearchTitle(trackName)
	candidate := normalizedLyricsSearchTitle(candidateTrack)
	if expected == "" || candidate == "" {
		return false
	}
	if candidate == expected {
		return true
	}
	return allowDecoratedCandidate && containsWordSequence(candidate, expected)
}

func lyricsSearchArtistsMatch(candidateArtist, artistName string) bool {
	expected := normalizeLooseArtistName(normalizeArtistName(artistName))
	if expected == "" {
		return true
	}
	candidate := normalizeLooseArtistName(normalizeArtistName(candidateArtist))
	if candidate == "" {
		return false
	}
	return candidate == expected || sameWordsUnordered(candidate, expected)
}

func lyricsSearchDurationMatches(candidateDuration, durationSec float64) bool {
	if candidateDuration <= 0 || durationSec <= 0 {
		return true
	}
	return math.Abs(candidateDuration-durationSec) <= durationToleranceSec
}

func lyricsSearchArtistAppearsInTitle(candidateTrack, artistName string) bool {
	expectedArtist := normalizeLooseArtistName(normalizeArtistName(artistName))
	candidateTitle := normalizeLooseArtistName(candidateTrack)
	return expectedArtist != "" &&
		candidateTitle != "" &&
		containsWordSequence(candidateTitle, expectedArtist)
}

func normalizeArtistName(name string) string {
	separators := []string{", ", "; ", " & ", " feat. ", " ft. ", " featuring ", " with "}

	result := name
	for _, sep := range separators {
		if idx := strings.Index(strings.ToLower(result), strings.ToLower(sep)); idx > 0 {
			result = result[:idx]
			break
		}
	}

	return strings.TrimSpace(result)
}

func isLikelyInstrumentalTrack(name string) bool {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" {
		return false
	}

	return instrumentalTrackPattern.MatchString(trimmed)
}
