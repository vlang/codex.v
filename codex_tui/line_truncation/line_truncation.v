module line_truncation

import ratatui.text
import ratatui.style
import unicode_segmentation
import codex_tui.width

pub fn line_width(line &text.Line) usize {
	mut result := usize(0)
	for index in 0 .. line.spans.len {
		result += width.display_width(&line.spans[index].text)
	}
	return result
}

pub fn truncate_line_to_width(line text.Line, max_width usize) text.Line {
	if max_width == 0 {
		return text.line_from_spans([]text.Span{})
	}

	line_style := line.style
	alignment := line.alignment
	mut used := usize(0)
	mut spans_out := []text.Span{cap: line.spans.len}

	for span in line.spans {
		span_width := width.display_width(&span.text)

		if span_width == 0 {
			spans_out << span
			continue
		}

		if used >= max_width {
			break
		}

		if used + span_width <= max_width {
			used += span_width
			spans_out << span
			continue
		}

		span_style := span.style
		content := &span.text
		mut end_idx := 0
		// The shared Unicode dependency returns byte offsets instead of Rust's
		// borrowing iterator. V slices here are temporary owned strings; only
		// the accepted prefix escapes at Rust's to_string() boundary below.
		graphemes := unicode_segmentation.grapheme_indices(content, /* is_extended */
			true)
		for position, idx in graphemes {
			end := if position + 1 < graphemes.len { graphemes[position + 1] } else { content.len }
			grapheme := (*content)[idx..end]
			grapheme_width := width.display_width(&grapheme)
			if used + grapheme_width > max_width {
				break
			}
			end_idx = end
			used += grapheme_width
		}

		if end_idx > 0 {
			spans_out << text.span_styled((*content)[..end_idx], span_style)
		}

		break
	}

	return text.Line{ style: line_style, alignment: alignment, spans: spans_out }
}

// Truncate a styled line to `max_width` and append an ellipsis on overflow.
//
// Intended for short UI rows. This preserves a fast no-overflow path (width
// pre-scan + return original line unchanged) and uses `truncate_line_to_width`
// for the overflow case.
// Performance should be reevaluated if using this method in loops/over larger content in the future.
pub fn truncate_line_with_ellipsis_if_overflow(line text.Line, max_width usize) text.Line {
	if max_width == 0 {
		return text.line_from_spans([]text.Span{})
	}

	if line_width(&line) <= max_width {
		return line
	}

	// Mutate the owned line directly: V forbids a mutable alias of its span array,
	// while Rust destructuring moves that array. No additional clone is needed.
	mut truncated := truncate_line_to_width(line, if max_width > 0 { max_width - 1 } else { 0 })
	ellipsis_style := if truncated.spans.len > 0 {
		truncated.spans.last().style
	} else {
		style.Style{}
	}
	truncated.spans << text.span_styled('…', ellipsis_style)
	return truncated
}
