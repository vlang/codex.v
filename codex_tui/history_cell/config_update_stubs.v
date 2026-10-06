module history_cell

import codex_tui.wrapping
import ratatui.text
import ratatui.style

// STUB: history_cell/base.rs::PrefixedWrappedHistoryCell's warning payload.
// The complete history trait and adaptive renderer await their source owners.
pub struct PrefixedWrappedHistoryCell {
	message string
}

// STUB: history_cell/notices.rs::new_warning_event retains its distinct warning
// cell type and yellow presentation rather than relabeling it as an info event.
pub fn new_warning_event(message string) PrefixedWrappedHistoryCell {
	return PrefixedWrappedHistoryCell{ message: message }
}

// STUB: PrefixedWrappedHistoryCell::display_lines supplies the source warning
// paragraph and two-column prefixes through the existing typed wrap boundary.
pub fn (cell &PrefixedWrappedHistoryCell) display_lines(width u16) []text.Line {
	if width == 0 { return []text.Line{} }
	yellow := style.Style{}.yellow()
	lines := wrapping.word_wrap_lines([text.line_from_spans([text.span_styled(cell.message.clone(), yellow)])], wrapping.RtOptions.new(if width > 2 {
		usize(width - 2)
	} else {
		usize(1)
	}))
	mut result := []text.Line{cap: lines.len}
	for index in 0 .. lines.len {
		mut spans := []text.Span{}
		spans << text.span_styled(if index == 0 { '⚠ ' } else { '  ' }, yellow)
		for span_index in 0 .. lines[index].spans.len {
			span := &lines[index].spans[span_index]
			spans << text.span_styled(span.text.clone(), span.style)
		}
		result << text.line_from_spans(spans)
	}
	return result
}
