module slash_input

import codex_protocol.user_input

// STUB: `bottom_pane::prompt_args::parse_slash_name`. V returns owned strings because it has no
// borrowed string-slice return equivalent to Rust's `(&str, &str, usize)`.
pub fn parse_slash_name(line &string) ?(string, string, int) {
	if !line.starts_with('/') {
		return none
	}
	stripped := (*line)[1..]
	mut name_end := stripped.len
	mut byte_offset := 0
	for character in stripped.runes() {
		if rune_is_space(character) {
			name_end = byte_offset
			break
		}
		byte_offset += character.str().len
	}
	if name_end == 0 {
		return none
	}
	name := stripped[..name_end].clone()
	rest_untrimmed := stripped[name_end..]
	rest := rest_untrimmed.trim_left(' \t\n\r\v\f  ')
	rest_offset := name_end + (rest_untrimmed.len - rest.len) + 1
	return name, rest, rest_offset
}

// STUB: `bottom_pane::chat_composer::slash_input::prepared_args`. The returned text is owned as
// the V lifetime adaptation for Rust's borrowed `&str` result.
pub fn prepared_args(prepared_text &string) ?(string, int) {
	_, prepared_rest, prepared_rest_offset := parse_slash_name(prepared_text) or { return none }
	return prepared_rest, prepared_rest_offset
}

// STUB: `bottom_pane::chat_composer::slash_input::args_elements`; translates full-text element
// byte ranges into command-argument-relative ranges.
pub fn args_elements(rest &string, rest_offset int,
	text_elements &[]user_input.TextElement) []user_input.TextElement {
	if rest.len == 0 || text_elements.len == 0 {
		return []
	}
	mut result := []user_input.TextElement{}
	for element in *text_elements {
		if element.byte_range.end <= rest_offset {
			continue
		}
		start := max_int(element.byte_range.start - rest_offset, 0)
		end := min_int(max_int(element.byte_range.end - rest_offset, 0), rest.len)
		if start >= rest.len || start >= end {
			continue
		}
		result << user_input.TextElement.new(user_input.ByteRange{
			start: start
			end:   end
		}, element.not_hidden_placeholder_for_conversion_only())
	}
	return result
}

// STUB: local saturating-range helper for the untranslated slash-input owner.
fn min_int(a int, b int) int {
	return if a < b { a } else { b }
}

// STUB: local saturating-range helper for the untranslated slash-input owner.
fn max_int(a int, b int) int {
	return if a > b { a } else { b }
}

// STUB: Rust `char::is_whitespace` set used by prompt-argument parsing.
fn rune_is_space(value rune) bool {
	return value in [` `, `\t`, `\n`, `\r`, `\v`, `\f`, `\u0085`, `\u00a0`, `\u1680`, `\u2000`,
		`\u2001`, `\u2002`, `\u2003`, `\u2004`, `\u2005`, `\u2006`, `\u2007`, `\u2008`, `\u2009`,
		`\u200a`, `\u2028`, `\u2029`, `\u202f`, `\u205f`, `\u3000`]
}
