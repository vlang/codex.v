// Terminal display-width helpers and guards for fixed prefix columns.
//
// Several rendering paths reserve a fixed number of columns for bullets,
// gutters, or labels before laying out content. When the terminal is very
// narrow, those reserved columns can consume the entire width, leaving zero
// or negative space for content.
//
// The display-width helpers match Ratatui's terminal-cell semantics while retaining `usize`
// precision for long lines. The guards centralise subtraction and enforce a strict-positive
// contract: they return an optional `n` where `n > 0`, or `none` when no usable
// content width remains. Callers treat `none` as "render prefix-only
// fallback" rather than attempting wrapped rendering at zero width, which
// would produce empty or unstable output.
module width

import unicode_width

// Returns the display width Ratatui uses for terminal text without its `u16` limit.
pub fn display_width(text &string) usize {
	mut result := unicode_width.width(text)
	for ch in text.runes_iterator() {
		if ch in [rune(0xff9e), 0xff9f] {
			result++
		}
	}
	return result
}

// Returns a scalar's terminal width, treating halfwidth sound marks as visible cells.
pub fn char_width(ch rune) usize {
	if ch in [rune(0xff9e), 0xff9f] {
		return 1
	}
	return unicode_width.char_width(ch) or { 0 }
}

// Returns usable content width after reserving fixed columns.
//
// Guarantees a strict positive width (an optional `n` where `n > 0`) or `none` when
// the reserved columns consume the full width.
//
// Treat `none` as "render prefix-only fallback". Coercing it to `0` and still
// attempting wrapped rendering often produces empty or unstable output at very
// narrow terminal widths.
pub fn usable_content_width(total_width usize, reserved_cols usize) ?usize {
	if total_width <= reserved_cols {
		return none
	}
	return total_width - reserved_cols
}

// `u16` convenience wrapper around `usable_content_width`.
//
// This keeps width math at callsites that receive terminal dimensions as
// `u16` while preserving the same `none` contract for exhausted width.
pub fn usable_content_width_u16(total_width u16, reserved_cols u16) ?usize {
	return usable_content_width(usize(total_width), usize(reserved_cols))
}
