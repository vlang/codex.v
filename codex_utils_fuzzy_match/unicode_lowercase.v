module codex_utils_fuzzy_match

// V's one-scalar lowercase conversion cannot express Rust char::to_lowercase expansions.
// The fixed-size result represents Rust's small lowercase iterator without allocating per char.
struct LowercaseScalars {
	values [3]rune
	len    int
}

fn lowercase_char(value rune) LowercaseScalars {
	mut lo := 0
	mut hi := lowercase_mappings.len / 24
	for lo < hi {
		mid := lo + (hi - lo) / 2
		start := mid * 24
		original := unicode_hex_value(&lowercase_mappings, start, 6)
		if u32(value) < original {
			hi = mid
		} else if u32(value) > original {
			lo = mid + 1
		} else {
			mut values := [3]rune{}
			mut count := 0
			for index in 0 .. 3 {
				mapped := unicode_hex_value(&lowercase_mappings, start + (index + 1) * 6, 6)
				if mapped > 0 {
					values[count] = rune(mapped)
					count++
				}
			}
			return LowercaseScalars{ values: values, len: count }
		}
	}
	return LowercaseScalars{ values: [value, rune(0), rune(0)]!, len: 1 }
}

// Rust str::to_lowercase additionally applies the language-independent Final_Sigma rule.
// It skips case-ignorable scalars on both sides, then emits final sigma when preceded by a
// cased scalar and followed by no cased scalar. The haystack deliberately uses char lowercase.
pub fn lowercase_string(value &string) []rune {
	chars := value.runes()
	mut lowered := []rune{cap: chars.len}
	for index, ch in chars {
		if ch == `Σ` && sigma_is_word_final(&chars, index) {
			lowered << `ς`
		} else {
			lowercase := lowercase_char(ch)
			for lower_index in 0 .. lowercase.len {
				lowered << lowercase.values[lower_index]
			}
		}
	}
	return lowered
}

fn sigma_is_word_final(chars &[]rune, index int) bool {
	mut before_cased := false
	for before := index - 1; before >= 0; before-- {
		if !unicode_in_ranges((*chars)[before], &case_ignorable_ranges) {
			before_cased = unicode_in_ranges((*chars)[before], &non_ignorable_cased_ranges)
			break
		}
	}
	if !before_cased {
		return false
	}
	for after in index + 1 .. chars.len {
		if !unicode_in_ranges((*chars)[after], &case_ignorable_ranges) {
			return !unicode_in_ranges((*chars)[after], &non_ignorable_cased_ranges)
		}
	}
	return true
}

fn unicode_in_ranges(value rune, ranges &string) bool {
	mut lo := 0
	mut hi := ranges.len / 12
	for lo < hi {
		mid := lo + (hi - lo) / 2
		start := mid * 12
		lower := unicode_hex_value(ranges, start, 6)
		upper := unicode_hex_value(ranges, start + 6, 6)
		if u32(value) < lower {
			hi = mid
		} else if u32(value) > upper {
			lo = mid + 1
		} else {
			return true
		}
	}
	return false
}

fn unicode_hex_value(value &string, start int, count int) u32 {
	mut result := u32(0)
	for index in start .. start + count {
		ch := (*value)[index]
		result = result << 4 | u32(if ch <= `9` { ch - `0` } else { ch - `a` + 10 })
	}
	return result
}
