// Identify terminal-color replies without changing unrelated Windows console input.
module windows_replay

import codex_tui.color
import codex_tui.terminal_probe
import std_ops

const max_terminal_color_response_bytes = 1024
const paste_start = '\x1b[200~'.bytes()
const paste_end = '\x1b[201~'.bytes()

// Return the byte ranges occupied by complete, valid OSC 10/11 color responses.
//
// The Windows probe maps these byte ranges back to their original INPUT_RECORDs so keyboard
// modifiers, UTF-16 input, mouse events, and focus changes can be replayed without reconstruction.
// V has no pub(super); these functions are public for the eventual parent probe module.
pub fn terminal_color_response_ranges(input &[]u8) []std_ops.Range[usize] {
	osc_start := '\x1b]'.bytes()
	foreground_prefix := '\x1b]10;'.bytes()
	background_prefix := '\x1b]11;'.bytes()
	mut ranges := []std_ops.Range[usize]{}
	mut cursor := 0

	for cursor < input.len {
		if has_prefix(input, cursor, &paste_start) {
			payload_start := cursor + paste_start.len
			// SAFETY: the complete paste prefix proves the lower bound is inside input.
			// This shared view is used synchronously and never escapes; unsafe prevents
			// V's implicit owned-array clone when assigning a borrowed slice.
			payload := unsafe { (*input)[payload_start..] }
			payload_end := terminal_probe.find_subslice(&payload, &paste_end) or { break }
			cursor = payload_start + int(payload_end) + paste_end.len
			continue
		}
		if !has_prefix(input, cursor, &osc_start) {
			cursor++
			continue
		}

		start := cursor
		slot, prefix_length := if has_prefix(input, start, &foreground_prefix) {
			u8(10), foreground_prefix.len
		} else if has_prefix(input, start, &background_prefix) {
			u8(11), background_prefix.len
		} else {
			cursor = start + osc_start.len
			continue
		}

		payload_start := start + prefix_length
		// Subtract before adding to preserve Rust's saturating bound without overflowing
		// V's signed array index. The complete prefix is shorter than the response limit.
		bounded_end := if input.len - start < max_terminal_color_response_bytes {
			input.len
		} else {
			start + max_terminal_color_response_bytes
		}
		// SAFETY: both bounds are inside input, and the parser only borrows this local view.
		bounded := unsafe { (*input)[payload_start..bounded_end] }
		terminator := terminal_probe.osc_payload_end(&bounded) or {
			cursor = payload_start
			continue
		}
		end := payload_start + terminator.offset + terminator.length
		// SAFETY: the terminator came from bounded, so this shared response is within input.
		response := unsafe { (*input)[start..end] }
		if _ := terminal_probe.parse_osc_color(&response, slot) {
			ranges << std_ops.Range[usize]{ start: usize(start), end: usize(end) }
		}
		cursor = end
	}

	return ranges
}

// Parse only real probe replies, never OSC-looking content inside a bracketed paste.
pub fn terminal_default_colors(input &[]u8) ?terminal_probe.DefaultColors {
	mut foreground := ?color.Rgb(none)
	mut background := ?color.Rgb(none)

	for response_range in terminal_color_response_ranges(input) {
		// SAFETY: each returned half-open range was validated inside input; the parser
		// borrows the view only for these calls and the view never escapes.
		response := unsafe { (*input)[int(response_range.start)..int(response_range.end)] }
		if foreground == none {
			foreground = terminal_probe.parse_osc_color(&response, /*slot*/
				10)
		}
		if background == none {
			background = terminal_probe.parse_osc_color(&response, /*slot*/
				11)
		}
	}

	return terminal_probe.DefaultColors{
		fg: foreground or { return none }
		bg: background or { return none }
	}
}

// Compare the shared byte buffer directly for Rust's borrowed starts_with operation.
fn has_prefix(input &[]u8, start int, prefix &[]u8) bool {
	if start < 0 || start > input.len || prefix.len > input.len - start {
		return false
	}
	for index in 0 .. prefix.len {
		if input[start + index] != prefix[index] {
			return false
		}
	}
	return true
}
