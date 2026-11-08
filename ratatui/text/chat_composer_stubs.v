module text

import ratatui.style
import ratatui.layout

// STUB: ratatui::text::Span without Rust's borrowed lifetime.
pub struct Span {
pub:
	text  string
	style style.Style
}

// STUB: ratatui::text::Line without Rust's borrowed lifetime.
pub struct Line {
pub mut:
	style     style.Style
	alignment ?layout.Alignment
	spans     []Span
}
