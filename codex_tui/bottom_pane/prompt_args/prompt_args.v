module prompt_args

// Parse a first-line slash command of the form `/name <rest>`.
// Returns `(name, rest_after_name, rest_offset)` if the line begins with `/`
// and contains a non-empty name; otherwise returns `none`.
//
// `rest_offset` is the byte index into the original line where `rest_after_name`
// starts after trimming leading whitespace (so `line[rest_offset..] == rest_after_name`).
//
// V cannot return Rust's borrowed string slices: the input stays borrowed, and
// only the returned name and rest are allocated as owned strings. Scanning the
// original UTF-8 bytes avoids allocating the intermediate stripped/rest slices.
pub fn parse_slash_name(line &string) ?(string, string, usize) {
	if line.len == 0 || (*line)[0] != `/` {
		return none
	}
	mut name_end := line.len
	mut rest_offset := line.len
	mut byte_offset := 0
	mut found_name_end := false
	for character in line.runes_iterator() {
		if byte_offset == 0 {
			byte_offset = 1
			continue
		}
		if !found_name_end {
			if is_rust_whitespace(character) {
				name_end = byte_offset
				found_name_end = true
			}
		} else if !is_rust_whitespace(character) {
			rest_offset = byte_offset
			break
		}
		byte_offset += character.length_in_bytes()
	}
	if name_end == 1 {
		return none
	}
	return (*line)[1..name_end], (*line)[rest_offset..], usize(rest_offset)
}

// Rust char::is_whitespace uses Unicode White_Space. Keep its exact set here:
// the current V utf8.is_space implementation incorrectly rejects U+3000.
fn is_rust_whitespace(character rune) bool {
	return character in [`\t`, `\n`, `\v`, `\f`, `\r`, ` `, `\u0085`, `\u00a0`, `\u1680`, `\u2028`,
		`\u2029`, `\u202f`, `\u205f`, `\u3000`]
		|| (character >= `\u2000` && character <= `\u200a`)
}
