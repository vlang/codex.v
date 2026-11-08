module text

// STUB: ratatui::text::Line::from(String), moving owned content into one raw span.
pub fn line_from(content string) Line {
	return Line{
		spans: [Span{ text: content }]
	}
}
