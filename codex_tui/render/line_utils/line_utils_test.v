module line_utils

import ratatui.layout
import ratatui.style
import ratatui.text

fn fixture_text(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn fixture_line() text.Line {
	return text.Line{
		style:     style.Style.new().bg(style.Color.rgb(12, 34, 56)).bold()
		alignment: layout.Alignment.right
		spans:     [
			text.Span{ text: fixture_text('é👩‍💻'), style: style.Style.new().green() },
			text.Span{ text: fixture_text(''), style: style.Style.new().dim() },
			text.Span{ text: fixture_text(' tail\n'), style: style.Style.new().underlined() },
		]
	}
}

fn test_line_to_borrowed_preserves_all_fields_and_references_content() {
	owner := fixture_line()
	for _ in 0 .. 4 {
		view := line_to_borrowed(&owner)
		assert view.style == owner.style
		assert view.alignment == owner.alignment
		assert view.spans.len == owner.spans.len
		for index in 0 .. owner.spans.len {
			assert view.spans[index].style == owner.spans[index].style
			assert *view.spans[index].text == owner.spans[index].text
			assert view.spans[index].text == &owner.spans[index].text
		}
		assert owner.spans[0].text == 'é👩‍💻'
	}
	assert owner == fixture_line()
}

fn test_line_to_borrowed_empty_line_retains_style_and_alignment() {
	owner := text.Line{
		style:     style.Style.new().italic()
		alignment: layout.Alignment.center
	}
	view := line_to_borrowed(&owner)
	assert view.style == owner.style
	assert view.alignment == owner.alignment
	assert view.spans == []text.BorrowedSpan{}
}

fn reborrow_past_first_view(owner &text.Line) text.BorrowedLine {
	first := line_to_borrowed(owner)
	return line_to_borrowed(&first)
}

fn test_reborrow_points_into_original_owner_after_first_view_drops() {
	owner := fixture_line()
	second := reborrow_past_first_view(&owner)
	for index in 0 .. owner.spans.len {
		assert second.spans[index].text == &owner.spans[index].text
		assert *second.spans[index].text == owner.spans[index].text
	}
	assert line_to_static(&second) == owner
	assert owner.spans[2].text == ' tail\n'
}

fn test_line_to_static_clones_owned_text_and_preserves_metadata() {
	owner := fixture_line()
	for _ in 0 .. 4 {
		copy := line_to_static(&owner)
		assert copy == owner
		// Distinct nonempty buffers prove ownership at the source's to_string boundary.
		assert copy.spans[0].text.str != owner.spans[0].text.str
		assert copy.spans[2].text.str != owner.spans[2].text.str
	}
	assert owner == fixture_line()
}

fn test_line_to_static_clones_borrowed_content_without_consuming_view_or_owner() {
	owner := fixture_line()
	view := line_to_borrowed(&owner)
	for _ in 0 .. 4 {
		copy := line_to_static(&view)
		assert copy == owner
		assert copy.spans[0].text.str != owner.spans[0].text.str
		assert *view.spans[0].text == 'é👩‍💻'
	}
	assert owner.spans[2].text == ' tail\n'
}

fn owned_copy_after_owner_drop() text.Line {
	owner := fixture_line()
	view := line_to_borrowed(&owner)
	return line_to_static(&view)
}

fn test_static_copy_remains_valid_after_original_owner_and_view_drop() {
	copy := owned_copy_after_owner_drop()
	assert copy == fixture_line()
}

fn test_line_to_static_empty_line_preserves_metadata() {
	owner := text.Line{ style: style.Style.new().dim(), alignment: layout.Alignment.left }
	assert line_to_static(&owner) == owner
	view := line_to_borrowed(&owner)
	assert line_to_static(&view) == owner
}

fn test_push_owned_lines_appends_in_order_and_keeps_borrowed_source_reusable() {
	first := fixture_line()
	second := text.Line{ spans: [text.Span{ text: fixture_text('second') }] }
	source := [line_to_borrowed(&first), line_to_borrowed(&second)]
	mut output := [text.Line{ spans: [text.Span{ text: fixture_text('existing') }] }]
	push_owned_lines(&source, mut output)
	push_owned_lines(&source, mut output)
	assert output.len == 5
	assert output[0].spans[0].text == 'existing'
	assert output[1] == first
	assert output[2] == second
	assert output[3] == first
	assert output[4] == second
	assert output[1].spans[0].text.str != output[3].spans[0].text.str
	assert *source[0].spans[0].text == 'é👩‍💻'
	assert second.spans[0].text == 'second'
}

fn test_push_owned_lines_accepts_owned_source_and_empty_source() {
	source := [fixture_line()]
	mut output := []text.Line{}
	push_owned_lines(&source, mut output)
	assert output[0] == source[0]
	empty := []text.Line{}
	push_owned_lines(&empty, mut output)
	assert output.len == 1
	assert source[0].spans[0].text == 'é👩‍💻'
}

fn test_is_blank_line_accepts_only_empty_or_ascii_spaces() {
	assert is_blank_line_spaces_only(&text.Line{})
	for content in ['', ' ', '    '] {
		line := text.Line{ spans: [text.Span{ text: content.clone() }] }
		assert is_blank_line_spaces_only(&line)
		view := line_to_borrowed(&line)
		assert is_blank_line_spaces_only(&view)
	}
	for content in ['\t', '\n', '\r', '\r\n', '\u00a0', '\u2003', '  x  ', 'é', '👩‍💻'] {
		line := text.Line{ spans: [text.Span{ text: content.clone() }] }
		assert !is_blank_line_spaces_only(&line)
		view := line_to_borrowed(&line)
		assert !is_blank_line_spaces_only(&view)
	}
}

fn test_is_blank_line_checks_all_spans_and_preserves_owned_content() {
	line := text.Line{
		style:     style.Style.new().bold()
		alignment: layout.Alignment.right
		spans:     [
			text.Span{ text: fixture_text('') },
			text.Span{ text: fixture_text('  ') },
			text.Span{ text: fixture_text('\t') },
		]
	}
	view := line_to_borrowed(&line)
	for _ in 0 .. 4 {
		assert !is_blank_line_spaces_only(&line)
		assert !is_blank_line_spaces_only(&view)
	}
	assert line.spans[1].text == '  '
	assert line.spans[2].text == '\t'
}

fn test_prefix_lines_empty_input_returns_no_lines() {
	assert prefix_lines([]text.Line{}, text.Span{ text: fixture_text('first ') }, text.Span{
		text: fixture_text('next ')
	}) == []text.Line{}
}

fn test_prefix_lines_preserves_styles_order_and_content_but_rebuilds_alignment() {
	first := fixture_line()
	second := text.Line{
		style:     style.Style.new().italic()
		alignment: layout.Alignment.center
		spans:     [text.Span{ text: fixture_text('second'), style: style.Style.new().yellow() }]
	}
	third := text.Line{ alignment: layout.Alignment.left }
	first_style := first.style
	second_style := second.style
	initial_style := style.Style.new().cyan()
	next_style := style.Style.new().dim()
	result := prefix_lines([first, second, third], text.Span{
		text:  fixture_text('I ')
		style: initial_style
	}, text.Span{ text: fixture_text('N '), style: next_style })
	assert result == [
		text.Line{
			style: first_style
			spans: [
				text.Span{ text: 'I ', style: initial_style },
				text.Span{ text: 'é👩‍💻', style: style.Style.new().green() },
				text.Span{ text: '', style: style.Style.new().dim() },
				text.Span{ text: ' tail\n', style: style.Style.new().underlined() },
			]
		},
		text.Line{
			style: second_style
			spans: [
				text.Span{ text: 'N ', style: next_style },
				text.Span{ text: 'second', style: style.Style.new().yellow() },
			]
		},
		text.Line{ spans: [text.Span{ text: 'N ', style: next_style }] },
	]
	// Rust constructs a new Line::from(spans), retaining style and discarding alignment.
	assert result[0].alignment == none
	assert result[1].alignment == none
	assert result[2].alignment == none
	// Each requested prefix is cloned, even when the following prefixes are equal.
	assert result[1].spans[0].text.str != result[2].spans[0].text.str
}

fn test_prefix_lines_moves_existing_span_text_and_keeps_empty_prefix_span() {
	line := fixture_line()
	// The addresses are compared only, never dereferenced after the ownership transfer.
	first_buffer := usize(line.spans[0].text.str)
	last_buffer := usize(line.spans[2].text.str)
	result := prefix_lines([line], text.Span{}, text.Span{ text: fixture_text('unused') })
	assert result.len == 1
	assert result[0].spans.len == 4
	assert result[0].spans[0] == text.Span{}
	assert usize(result[0].spans[1].text.str) == first_buffer
	assert usize(result[0].spans[3].text.str) == last_buffer
	assert result[0].spans[1].text == 'é👩‍💻'
	assert result[0].spans[3].text == ' tail\n'
}
