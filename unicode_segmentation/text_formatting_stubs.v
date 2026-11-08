module unicode_segmentation

// STUB: unicode-segmentation::UnicodeSegmentation::grapheme_indices for contiguous
// UTF-8 text. Returns byte offsets rather than a borrowing iterator; Unicode 16
// extended and legacy boundaries follow the upstream GB3–GB999 rules.
pub fn grapheme_indices(text &string, is_extended bool) []int {
	runes := text.runes()
	if runes.len == 0 {
		return []int{}
	}
	mut offsets := []int{cap: runes.len}
	mut categories := []u32{cap: runes.len}
	mut byte_offset := 0
	for value in runes {
		offsets << byte_offset
		categories << category(value)
		byte_offset += value.str().len
	}
	mut result := [0]
	for i in 1 .. runes.len {
		before := categories[i - 1]
		after := categories[i]
		mut should_break := true
		if before == 1 && after == 7 { // GB3: CR × LF
			should_break = false
		} else if before in [u32(1), 2, 7] || after in [u32(1), 2, 7] { // GB4, GB5
			should_break = true
		} else if before == 6 && after in [u32(6), 14, 8, 9] { // GB6
			should_break = false
		} else if before in [u32(8), 14] && after in [u32(14), 13] { // GB7
			should_break = false
		} else if before in [u32(9), 13] && after == 13 { // GB8
			should_break = false
		} else if after in [u32(3), 15] { // GB9
			should_break = false
		} else if (after == 12 || before == 10) && is_extended { // GB9a, GB9b
			should_break = false
		} else if after == 5 && is_extended { // GB9c: Indic conjuncts
			mut linker_seen := false
			for j := i - 1; j >= 0; j-- {
				if runes[j] in [rune(0x94d), 0x9cd, 0xacd, 0xb4d, 0xc4d, 0xd4d] {
					linker_seen = true
				} else if in_ranges(runes[j], &incb_extends, 12, false) != 0 {
					continue
				} else {
					should_break = !(linker_seen && categories[j] == 5)
					break
				}
			}
		} else if before == 15 && after == 4 { // GB11: pictograph Extend* ZWJ × pictograph
			mut j := i - 2
			for j >= 0 && categories[j] == 3 {
				j--
			}
			should_break = !(j >= 0 && categories[j] == 4)
		} else if before == 11 && after == 11 { // GB12, GB13: paired regional indicators
			mut count := 0
			for j := i - 1; j >= 0 && categories[j] == 11; j-- {
				count++
			}
			should_break = count % 2 == 0
		}
		if should_break {
			result << offsets[i]
		}
	}
	return result
}

// STUB: Rust char::to_uppercase, including expansions into up to three scalars.
// Generated mappings retain the compiler's Unicode 17.0.0 case data without a runtime Rust dependency.
pub fn uppercase(value rune) string {
	mut lo := 0
	mut hi := uppercase_mappings.len / 24
	for lo < hi {
		mid := lo + (hi - lo) / 2
		start := mid * 24
		cp := hex_value(&uppercase_mappings, start, 6)
		if u32(value) < cp {
			hi = mid
		} else if u32(value) > cp {
			lo = mid + 1
		} else {
			mut result := ''
			for i in 1 .. 4 {
				mapped := hex_value(&uppercase_mappings, start + i * 6, 6)
				if mapped > 0 {
					result += rune(mapped).str()
				}
			}
			return result
		}
	}
	return value.str()
}

// STUB: upstream grapheme category query backed by generated Unicode 16 ranges.
fn category(value rune) u32 {
	return in_ranges(value, &grapheme_categories, 14, true)
}

// STUB: generated Unicode property-table range lookup.
fn in_ranges(value rune, records &string, record_len int, has_value bool) u32 {
	mut lo := 0
	mut hi := records.len / record_len
	for lo < hi {
		mid := lo + (hi - lo) / 2
		start := mid * record_len
		lower := hex_value(records, start, 6)
		upper := hex_value(records, start + 6, 6)
		if u32(value) < lower {
			hi = mid
		} else if u32(value) > upper {
			lo = mid + 1
		} else {
			return if has_value { hex_value(records, start + 12, 2) } else { 1 }
		}
	}
	return 0
}

// STUB: decoding helper for vendored compact Unicode tables.
fn hex_value(value &string, start int, count int) u32 {
	mut result := u32(0)
	for i in start .. start + count {
		ch := (*value)[i]
		result = result << 4 | u32(if ch <= `9` { ch - `0` } else { ch - `a` + 10 })
	}
	return result
}
