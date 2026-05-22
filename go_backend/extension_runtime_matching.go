package gobackend

import (
	"strings"

	"github.com/dop251/goja"
)

func (r *extensionRuntime) matchingCompareStrings(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.vm.ToValue(0.0)
	}

	str1 := strings.ToLower(strings.TrimSpace(call.Arguments[0].String()))
	str2 := strings.ToLower(strings.TrimSpace(call.Arguments[1].String()))

	if str1 == str2 {
		return r.vm.ToValue(1.0)
	}

	similarity := calculateStringSimilarity(str1, str2)
	return r.vm.ToValue(similarity)
}

func (r *extensionRuntime) matchingCompareDuration(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.vm.ToValue(false)
	}

	dur1 := int(call.Arguments[0].ToInteger())
	dur2 := int(call.Arguments[1].ToInteger())

	tolerance := 3000
	if len(call.Arguments) > 2 && !goja.IsUndefined(call.Arguments[2]) {
		tolerance = int(call.Arguments[2].ToInteger())
	}

	diff := dur1 - dur2
	if diff < 0 {
		diff = -diff
	}

	return r.vm.ToValue(diff <= tolerance)
}

func (r *extensionRuntime) matchingNormalizeString(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue("")
	}

	str := call.Arguments[0].String()
	normalized := normalizeStringForMatching(str)
	return r.vm.ToValue(normalized)
}

func calculateStringSimilarity(s1, s2 string) float64 {
	if len(s1) == 0 && len(s2) == 0 {
		return 1.0
	}
	if len(s1) == 0 || len(s2) == 0 {
		return 0.0
	}

	distance := levenshteinDistance(s1, s2)
	maxLen := len(s1)
	if len(s2) > maxLen {
		maxLen = len(s2)
	}

	return 1.0 - float64(distance)/float64(maxLen)
}

func levenshteinDistance(s1, s2 string) int {
	if len(s1) == 0 {
		return len(s2)
	}
	if len(s2) == 0 {
		return len(s1)
	}

	// Two-row rolling array: O(m) space instead of O(n*m).
	// prev holds the previous row, curr the current one; they are swapped
	// each iteration so no extra allocation occurs inside the loop.
	m := len(s2)
	prev := make([]int, m+1)
	curr := make([]int, m+1)

	for j := 0; j <= m; j++ {
		prev[j] = j
	}

	for i := 1; i <= len(s1); i++ {
		curr[0] = i
		for j := 1; j <= m; j++ {
			cost := 1
			if s1[i-1] == s2[j-1] {
				cost = 0
			}
			curr[j] = min(
				prev[j]+1,
				curr[j-1]+1,
				prev[j-1]+cost,
			)
		}
		prev, curr = curr, prev
	}

	return prev[m]
}

// normalizeSuffixes is a package-level var so the slice is allocated once,
// not on every call to normalizeStringForMatching.
var normalizeSuffixes = []string{
	" (remastered)", " (remaster)", " - remastered", " - remaster",
	" (deluxe)", " (deluxe edition)", " - deluxe", " - deluxe edition",
	" (explicit)", " (clean)", " [explicit]", " [clean]",
	" (album version)", " (single version)", " (radio edit)",
	" (feat.", " (ft.", " feat.", " ft.",
}

func normalizeStringForMatching(s string) string {
	s = strings.ToLower(s)

	for _, suffix := range normalizeSuffixes {
		if idx := strings.Index(s, suffix); idx != -1 {
			s = s[:idx]
		}
	}

	var result strings.Builder
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == ' ' {
			result.WriteRune(r)
		}
	}

	s = strings.Join(strings.Fields(result.String()), " ")

	return strings.TrimSpace(s)
}
