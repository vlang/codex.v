// Preserve startup terminal input while filtering completed terminal-color replies.
module startup_replay

import codex_tui.terminal_probe

const max_replayed_osc_bytes = 1024

// Preserve input and bracketed paste while omitting completed terminal-color replies.
//
// Keep bounded incomplete OSC prefixes so unread continuations stay parser-framed.
// V has no pub(super), so this helper is public to its eventual parent probe module.
pub fn startup_replay_input(input &[]u8) []u8 {
	paste_start := '\x1b[200~'.bytes()
	paste_end := '\x1b[201~'.bytes()
	osc_start := '\x1b]'.bytes()
	foreground := '\x1b]10;'.bytes()
	background := '\x1b]11;'.bytes()
	mut replay := []u8{cap: input.len}
	mut cursor := 0
	mut inside_paste := false
	for cursor < input.len {
		if inside_paste {
			if has_prefix(input, cursor, &paste_end) {
				replay << paste_end
				cursor += paste_end.len
				inside_paste = false
			} else {
				slot := if has_prefix(input, cursor, &foreground) {
					u8(10)
				} else if has_prefix(input, cursor, &background) {
					u8(11)
				} else {
					u8(0)
				}
				if slot != 0 {
					// SAFETY: the bounds are inside input, and this shared slice is used only
					// synchronously. V's default slice assignment clones borrowed arrays.
					bounded := unsafe { (*input)[cursor + 2..int_min(input.len, cursor + max_replayed_osc_bytes)] }
					if terminator := terminal_probe.osc_payload_end(&bounded) {
						end := cursor + 2 + terminator.offset + terminator.length
						// SAFETY: the terminator was found inside bounded; this view never escapes.
						response := unsafe { (*input)[cursor..end] }
						if !contains_sequence(&response, &paste_end) {
							if _ := terminal_probe.parse_osc_color(&response, slot) {
								cursor = end
								continue
							}
						}
					}
				}
				replay << input[cursor]
				cursor++
			}
			continue
		}

		if has_prefix(input, cursor, &paste_start) {
			replay << paste_start
			cursor += paste_start.len
			inside_paste = true
			continue
		}

		if has_prefix(input, cursor, &osc_start) {
			// SAFETY: matching OSC_START proves cursor + 2 <= input.len. The parser borrows
			// the view for this call and never stores or mutates it.
			rest := unsafe { (*input)[cursor + 2..] }
			if terminator := terminal_probe.osc_payload_end(&rest) {
				cursor += 2 + terminator.offset + terminator.length
				continue
			}
			end := int_min(input.len, cursor + max_replayed_osc_bytes)
			replay << (*input)[cursor..end]
			break
		}

		replay << input[cursor]
		cursor++
	}
	return replay
}

// Borrowed byte comparisons replace Rust's starts_with and windows iterators without
// transferring the input's ownership to V's value-parameter array helpers.
fn has_prefix(input &[]u8, start int, prefix &[]u8) bool {
	if start < 0 || prefix.len > input.len - start {
		return false
	}
	for index in 0 .. prefix.len {
		if input[start + index] != prefix[index] {
			return false
		}
	}
	return true
}

fn contains_sequence(input &[]u8, sequence &[]u8) bool {
	if sequence.len > input.len {
		return false
	}
	for start in 0 .. input.len - sequence.len + 1 {
		if has_prefix(input, start, sequence) {
			return true
		}
	}
	return false
}

fn int_min(left int, right int) int {
	return if left < right { left } else { right }
}
