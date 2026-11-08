module text

import ratatui.layout
import ratatui.style

// STUB: ratatui::text::Span<'a> with Cow::Borrowed content. The existing Span stores
// an owned string, so this distinct view preserves shared borrowing without changing
// that type or cloning its text. Its owner must outlive the view, as in Rust.
pub struct BorrowedSpan {
pub:
	text  &string
	style style.Style
}

// STUB: ratatui::text::Line<'a> whose spans borrow their content. The span array is
// owned by the view, matching Rust's newly collected Vec; content references still
// point into the original owner. V does not express Rust's lifetime parameter.
pub struct BorrowedLine {
pub:
	style     style.Style
	alignment ?layout.Alignment
	spans     []BorrowedSpan
}

// STUB: ratatui::text::Line::style, consuming the line and replacing its line style.
pub fn (line Line) style(line_style style.Style) Line {
	return Line{
		style:     line_style
		alignment: line.alignment
		spans:     line.spans
	}
}
