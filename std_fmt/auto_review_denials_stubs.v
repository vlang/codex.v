module std_fmt

import strings

// STUB: std::fmt::Debug for a shared Rust string, specialized from format!("{stdin:?}").
// Rust's escapes differ from JSON: NUL is \0, other controls use \u{lowercase_hex},
// nonspacing grapheme extensions are escaped, and single quotes remain literal.
pub fn debug_string(text &string) string {
	mut output := strings.new_builder(text.len + 2)
	output.write_u8(`"`)
	for character in text.runes() {
		match character {
			`\x00` { output.write_string('\\0') }
			`\t` { output.write_string('\\t') }
			`\r` { output.write_string('\\r') }
			`\n` { output.write_string('\\n') }
			`\\` { output.write_string('\\\\') }
			`"` { output.write_string('\\"') }
			else {
				if debug_scalar_needs_escape(u32(character)) {
					output.write_string('\\u{${u32(character):x}}')
				} else {
					output.write_rune(character)
				}
			}
		}
	}
	output.write_u8(`"`)
	return output.str()
}

// STUB: Rust's Unicode debug-printability/extended-grapheme decision uses a pinned oracle.
fn debug_scalar_needs_escape(point u32) bool {
	mut left := 0
	mut right := debug_escaped_ranges.len / 12
	for left < right {
		middle := left + (right - left) / 2
		start := debug_hex_scalar(middle * 12)
		end := debug_hex_scalar(middle * 12 + 6)
		if point < start {
			right = middle
		} else if point > end {
			left = middle + 1
		} else {
			return true
		}
	}
	return false
}

// STUB: Decode one scalar in the packed standard-library debug oracle.
fn debug_hex_scalar(offset int) u32 {
	mut point := u32(0)
	for index in offset .. offset + 6 {
		byte := debug_escaped_ranges[index]
		point = (point << 4) | u32(if byte <= `9` { byte - `0` } else { byte - `a` + 10 })
	}
	return point
}
