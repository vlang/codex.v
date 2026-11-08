module slash_input

import codex_protocol.user_input
import codex_tui.bottom_pane.prompt_args

// STUB: `bottom_pane::chat_composer::slash_input::prepared_args`. The returned text is owned as
// the V lifetime adaptation for Rust's borrowed `&str` result.
pub fn prepared_args(prepared_text &string) ?(string, int) {
	_, prepared_rest, prepared_rest_offset := prompt_args.parse_slash_name(prepared_text) or { return none }
	// Existing TextElement ranges use V's signed string indices.
	return prepared_rest, int(prepared_rest_offset)
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
