module text

import ratatui.style

// STUB: ratatui::text::Line::from(Vec<Span>), consuming the owned span collection.
pub fn line_from_spans(spans []Span) Line {
	return Line{ spans: spans }
}

// STUB: ratatui::text::Span::styled(String, Style), consuming the owned text.
pub fn span_styled(content string, span_style style.Style) Span {
	return Span{ text: content, style: span_style }
}

// STUB: ratatui::text::Span::clone; V has owned strings in place of Cow<str>.
pub fn (span &Span) clone() Span {
	return Span{ text: span.text.clone(), style: span.style }
}

// STUB: ratatui::text::Line::clone; clone each owned span at Rust's explicit clone boundary.
pub fn (line &Line) clone() Line {
	mut spans := []Span{cap: line.spans.len}
	for index in 0 .. line.spans.len {
		spans << line.spans[index].clone()
	}
	return Line{ style: line.style, alignment: line.alignment, spans: spans }
}
