module text

import ratatui.style

// STUB: ratatui::text::Span::styled consumes its owned content and Copy style.
pub fn Span.styled(content string, span_style style.Style) Span {
	return Span{ text: content, style: span_style }
}
