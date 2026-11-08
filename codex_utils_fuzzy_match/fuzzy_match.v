module codex_utils_fuzzy_match

// V adaptation: an optional typed result carries Rust's (Vec<usize>, i32) return tuple.
// V string/array positions use int, and V int has the same 32-bit score range as Rust i32.
pub struct FuzzyMatch {
pub:
	indices []int
	score   int
}

// Simple case-insensitive subsequence matcher used for fuzzy filtering.
//
// Returns the indices (character positions) of the matched characters in the
// ORIGINAL `haystack` string and a score where smaller is better.
//
// Unicode correctness: we perform the match on a lowercased copy of the
// haystack and needle but maintain a mapping from each character in the
// lowercased haystack back to the original character index in `haystack`.
// This ensures the returned indices can be safely used with
// string.runes() consumers for highlighting, even when
// lowercasing expands certain characters (e.g., İ → i̇; ß is not case-folded to ss).
pub fn fuzzy_match(haystack &string, needle &string) ?FuzzyMatch {
	if needle.len == 0 {
		return FuzzyMatch{ indices: []int{}, score: 0x7fffffff }
	}

	mut lowered_chars := []rune{}
	mut lowered_to_orig_char_idx := []int{}
	for orig_idx, ch in haystack.runes() {
		lowercase := lowercase_char(ch)
		for index in 0 .. lowercase.len {
			lowered_chars << lowercase.values[index]
			lowered_to_orig_char_idx << orig_idx
		}
	}

	lowered_needle := lowercase_string(needle)

	mut result_orig_indices := []int{cap: lowered_needle.len}
	mut last_lower_pos := ?int(none)
	mut cur := 0
	for nc in lowered_needle {
		mut found_at := ?int(none)
		for cur < lowered_chars.len {
			if lowered_chars[cur] == nc {
				found_at = cur
				cur++
				break
			}
			cur++
		}
		pos := found_at or { return none }
		result_orig_indices << lowered_to_orig_char_idx[pos]
		last_lower_pos = pos
	}

	mut first_lower_pos := 0
	if result_orig_indices.len > 0 {
		target_orig := result_orig_indices[0]
		for index, orig in lowered_to_orig_char_idx {
			if orig == target_orig {
				first_lower_pos = index
				break
			}
		}
	}
	// last defaults to first for single-hit; score = extra span between first/last hit
	// minus needle len (≥0).
	// Strongly reward prefix matches by subtracting 100 when the first hit is at index 0.
	last := last_lower_pos or { first_lower_pos }
	window := (last - first_lower_pos + 1) - lowered_needle.len
	mut score := if window > 0 { window } else { 0 }
	if first_lower_pos == 0 {
		score -= 100
	}

	result_orig_indices.sort()
	mut unique_len := 0
	for index in 0 .. result_orig_indices.len {
		if unique_len == 0 || result_orig_indices[index] != result_orig_indices[unique_len - 1] {
			result_orig_indices[unique_len] = result_orig_indices[index]
			unique_len++
		}
	}
	result_orig_indices.trim(unique_len)
	return FuzzyMatch{ indices: result_orig_indices, score: score }
}
