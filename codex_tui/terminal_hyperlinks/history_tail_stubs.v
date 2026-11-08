module terminal_hyperlinks

import ratatui.text
import codex_tui.width

// STUB: terminal_hyperlinks::plain_hyperlink_lines consumes source-owned plain lines.
pub fn plain_hyperlink_lines(lines []text.Line) []HyperlinkLine {
	mut consumed := HistoryTailConsumedLines{ values: lines }
	consumed.values.reverse_in_place()
	mut result := []HyperlinkLine{cap: consumed.values.len}
	count := consumed.values.len
	for _ in 0 .. count {
		result << HyperlinkLine.new(consumed.values.pop())
	}
	return result
}

// STUB: owned iterator storage at the external plain_hyperlink_lines boundary.
struct HistoryTailConsumedLines {
mut:
	values []text.Line
}

// STUB: HyperlinkLine::width uses the canonical display-width implementation.
pub fn (line &HyperlinkLine) width() usize {
	mut columns := usize(0)
	for index in 0 .. line.line.spans.len {
		columns += width.display_width(&line.line.spans[index].text)
	}
	return columns
}

// STUB: HyperlinkLine::clone copies text and every semantic hyperlink at Rust's clone boundary.
pub fn (line &HyperlinkLine) clone() HyperlinkLine {
	mut links := []TerminalHyperlink{cap: line.hyperlinks.len}
	for index in 0 .. line.hyperlinks.len {
		link := &line.hyperlinks[index]
		links << TerminalHyperlink{ columns: link.columns, destination: link.destination.clone(), destination_kind: link.destination_kind }
	}
	return HyperlinkLine{ line: line.line.clone(), hyperlinks: links }
}
