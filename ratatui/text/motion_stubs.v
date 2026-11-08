module text

// STUB: ratatui::style::Stylize::dim for Span. The receiver owns its text, matching
// Rust's consuming Stylize operation; only the allocation-free style is copied.
pub fn (span Span) dim() Span {
	return Span{ text: span.text, style: span.style.dim() }
}
