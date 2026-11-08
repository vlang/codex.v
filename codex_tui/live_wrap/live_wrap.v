module live_wrap

import codex_tui.width as terminal_width
import unicode_segmentation

// A single visual row produced by RowBuilder.
pub struct Row {
pub:
	text string
	// True if this row ends with an explicit line break (as opposed to a hard wrap).
	explicit_break bool
}

pub fn (row &Row) width() usize {
	return terminal_width.display_width(&row.text)
}

// Rust's derived Clone copies the owned row text at an explicit clone boundary.
pub fn (row &Row) clone() Row {
	return Row{ text: row.text.clone(), explicit_break: row.explicit_break }
}

// Incrementally wraps input text into visual rows of at most `width` cells.
//
// Step 1: plain-text only. ANSI-carry and styled spans will be added later.
pub struct RowBuilder {
mut:
	target_width usize
	// Buffer for the current logical line (until a '\n' is seen).
	current_line string
	// Output rows built so far for the current logical line and previous ones.
	built_rows []Row
}

pub fn RowBuilder.new(target_width usize) RowBuilder {
	return RowBuilder{ target_width: if target_width > 0 { target_width } else { 1 } }
}

pub fn (mut builder RowBuilder) set_width(width usize) {
	builder.target_width = if width > 0 { width } else { 1 }
	// Rewrap everything we have (simple approach for Step 1).
	mut all := ''
	old_rows := builder.built_rows
	builder.built_rows = []Row{}
	for row in old_rows {
		all += row.text
		if row.explicit_break {
			all += '\n'
		}
	}
	all += builder.current_line
	builder.current_line = ''
	builder.push_fragment(&all)
}

// Push an input fragment. May contain newlines.
pub fn (mut builder RowBuilder) push_fragment(fragment &string) {
	if fragment.len == 0 {
		return
	}
	mut start := 0
	// Newline is a single ASCII byte and cannot appear inside another UTF-8 scalar.
	// Scanning its byte indices therefore preserves Rust's char_indices offsets.
	for i in 0 .. fragment.len {
		if (*fragment)[i] == `\n` {
			// Flush anything pending before the newline.
			if start < i {
				builder.current_line += (*fragment)[start..i]
			}
			builder.flush_current_line( /* explicit_break */
			true)
			start = i + 1
		}
	}
	if start < fragment.len {
		builder.current_line += (*fragment)[start..]
		builder.wrap_current_line()
	}
}

// Return a snapshot of produced rows (non-draining).
// The returned array reference borrows the builder's stored rows without cloning.
// As with Rust's slice, callers must finish using it before mutating the builder.
pub fn (builder &RowBuilder) rows() &[]Row {
	return &builder.built_rows
}

// Rows suitable for display, including the current partial line if any.
pub fn (builder &RowBuilder) display_rows() []Row {
	mut out := []Row{cap: builder.built_rows.len + if builder.current_line.len == 0 { 0 } else { 1 }}
	for i in 0 .. builder.built_rows.len {
		out << builder.built_rows[i].clone()
	}
	if builder.current_line.len != 0 {
		out << Row{ text: builder.current_line.clone(), explicit_break: false }
	}
	return out
}

// Drain the oldest rows that exceed `max_keep` display rows (including the
// current partial line, if any). Returns the drained rows in order.
pub fn (mut builder RowBuilder) drain_commit_ready(max_keep usize) []Row {
	display_count := usize(builder.built_rows.len) + if builder.current_line.len == 0 {
		usize(0)
	} else {
		usize(1)
	}
	if display_count <= max_keep {
		return []Row{}
	}
	to_commit := display_count - max_keep
	commit_count := if to_commit < usize(builder.built_rows.len) {
		int(to_commit)
	} else {
		builder.built_rows.len
	}
	mut drained := []Row{cap: commit_count}
	for _ in 0 .. commit_count {
		row := builder.built_rows[0]
		builder.built_rows.delete(0)
		drained << row
	}
	return drained
}

fn (mut builder RowBuilder) flush_current_line(explicit_break bool) {
	// Wrap any remaining content in the current line and then finalize with explicit_break.
	builder.wrap_current_line()
	// If the current line ended exactly on a width boundary and is non-empty, represent
	// the explicit break as an empty explicit row so that fragmentation invariance holds.
	if explicit_break {
		if builder.current_line.len == 0 {
			// We ended on a boundary previously; add an empty explicit row.
			builder.built_rows << Row{ text: '', explicit_break: true }
		} else {
			// There is leftover content that did not wrap yet; push it now with the explicit flag.
			text := builder.current_line
			builder.current_line = ''
			builder.built_rows << Row{ text: text, explicit_break: true }
		}
	}
	// Reset current line buffer for next logical line.
	builder.current_line = ''
}

fn (mut builder RowBuilder) wrap_current_line() {
	// While the current_line exceeds width, cut a prefix.
	for {
		if builder.current_line.len == 0 {
			break
		}
		prefix, suffix, taken := take_prefix_by_width(&builder.current_line, builder.target_width)
		if taken == 0 {
			// Avoid an infinite loop on an indivisible grapheme wider than the target.
			graphemes := unicode_segmentation.grapheme_indices(&builder.current_line, /* is_extended */
				true)
			if graphemes.len > 0 {
				len := if graphemes.len > 1 { graphemes[1] } else { builder.current_line.len }
				p := builder.current_line[..len]
				builder.built_rows << Row{ text: p, explicit_break: false }
				builder.current_line = builder.current_line[len..]
				continue
			}
			break
		}
		if suffix.len == 0 {
			// Fits entirely; keep in buffer (do not push yet) so we can append more later.
			break
		} else {
			// Emit wrapped prefix as a non-explicit row and continue with the remainder.
			builder.built_rows << Row{ text: prefix, explicit_break: false }
			builder.current_line = suffix
		}
	}
}

// Take a prefix of `text` whose visible width is at most `max_cols`.
// Returns (prefix, suffix, prefix_width).
// V has no borrowed string-slice return: suffix is an owned UTF-8 substring.
// The input remains borrowed, and wrap_current_line moves that suffix into its
// buffer at the same point where Rust calls suffix.to_string(). Grapheme iteration
// uses the shared dependency's byte offsets and temporary owned string slices.
pub fn take_prefix_by_width(text &string, max_cols usize) (string, string, usize) {
	if max_cols == 0 || text.len == 0 {
		return '', text.clone(), 0
	}
	mut cols := usize(0)
	mut end_idx := 0
	graphemes := unicode_segmentation.grapheme_indices(text, /* is_extended */
		true)
	for position, i in graphemes {
		end := if position + 1 < graphemes.len { graphemes[position + 1] } else { text.len }
		grapheme := (*text)[i..end]
		grapheme_width := terminal_width.display_width(&grapheme)
		// This overflow guard is equivalent to Rust usize::saturating_add.
		max_usize := ~usize(0)
		combined := if grapheme_width > max_usize - cols {
			max_usize
		} else {
			cols + grapheme_width
		}
		if combined > max_cols {
			break
		}
		cols += grapheme_width
		end_idx = end
		if cols == max_cols {
			break
		}
	}
	prefix := (*text)[..end_idx]
	suffix := (*text)[end_idx..]
	return prefix, suffix, cols
}
