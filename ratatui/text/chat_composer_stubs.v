module text

import ratatui.style

// STUB: typed re-export of `ratatui::style::Style` for translated modules that also depend on a
// separate crate-local module named `style`. The current V compiler resolves both imports by their
// terminal module component even when aliases are used.
pub type SpanStyle = style.Style

// STUB: ratatui::text::Span without Rust's borrowed lifetime.
pub struct Span {
pub:
	text  string
	style style.Style
}

// STUB: ratatui::text::Line without Rust's borrowed lifetime.
pub struct Line {
pub:
	spans []Span
}
