module line_truncation

import ratatui.text
import ratatui.style
import ratatui.layout

fn test_halfwidth_sound_marks_stay_with_their_grapheme_when_truncated() {
	line := text.line_from('abｶﾞc')

	assert line_width(&line) == 5
	assert truncate_line_to_width(line.clone(), /* max_width */
		3) == text.line_from('ab')
	assert truncate_line_to_width(line, /* max_width */
		4) == text.line_from('abｶﾞ')
}

fn test_truncation_preserves_line_and_partial_span_styles_and_alignment() {
	line_style := style.Style{}.bg(style.Color{ kind: .blue })
	first_style := style.Style{}.green()
	last_style := style.Style{}.magenta().bold()
	line := text.Line{
		style:     line_style
		alignment: layout.Alignment.right
		spans:     [text.span_styled('ab', first_style), text.span_styled('cd界', last_style)]
	}
	assert truncate_line_to_width(line, 5) == text.Line{
		style:     line_style
		alignment: layout.Alignment.right
		spans:     [text.span_styled('ab', first_style), text.span_styled('cd', last_style)]
	}
}

fn test_zero_width_spans_survive_full_budget_until_first_nonzero_span() {
	red := style.Style{}.fg(style.Color{ kind: .red })
	line := text.Line{
		spans: [text.line_from('ab').spans[0], text.span_styled('\u0301', red),
			text.line_from('c').spans[0], text.line_from('').spans[0]]
	}
	assert truncate_line_to_width(line, 2) == text.Line{
		spans: [text.line_from('ab').spans[0], text.span_styled('\u0301', red)]
	}
}

fn test_grapheme_clusters_are_never_split() {
	assert truncate_line_to_width(text.line_from('a👩‍💻b'), 2) == text.line_from('a')
	assert truncate_line_to_width(text.line_from('a👩‍💻b'), 3) == text.line_from('a👩‍💻')
	assert truncate_line_to_width(text.line_from('a🇯🇵b'), 2) == text.line_from('a')
	assert truncate_line_to_width(text.line_from('a🇯🇵b'), 3) == text.line_from('a🇯🇵')
	assert truncate_line_to_width(text.line_from('e\u0301x'), 1) == text.line_from('e\u0301')
}

fn test_zero_width_returns_default_empty_line() {
	line := text.Line{
		style:     style.Style{}.bold()
		alignment: layout.Alignment.center
		spans:     [text.span_styled('abc', style.Style{}.green())]
	}
	assert truncate_line_to_width(line.clone(), 0) == text.Line{}
	assert truncate_line_with_ellipsis_if_overflow(line, 0) == text.Line{}
}

fn test_ellipsis_uses_last_kept_span_style_and_preserves_line_attributes() {
	line_style := style.Style{}.bg(style.Color{ kind: .blue })
	green := style.Style{}.green()
	red := style.Style{}.fg(style.Color{ kind: .red })
	line := text.Line{
		style:     line_style
		alignment: layout.Alignment.left
		spans:     [text.span_styled('ab', green), text.span_styled('cd', red)]
	}
	assert truncate_line_with_ellipsis_if_overflow(line, 3) == text.Line{
		style:     line_style
		alignment: layout.Alignment.left
		spans:     [text.span_styled('ab', green), text.span_styled('…', green)]
	}
}

fn test_one_column_overflow_uses_default_ellipsis_line() {
	line := text.Line{
		style:     style.Style{}.bold()
		alignment: layout.Alignment.right
		spans:     [text.span_styled('界', style.Style{}.green())]
	}
	assert truncate_line_with_ellipsis_if_overflow(line, 1) == text.Line{
		spans: [text.span_styled('…', style.Style{})]
	}
}

fn test_no_overflow_returns_same_span_allocation() {
	owner := $if ownership ? { 'ab界'.to_owned() } $else { 'ab界'.clone() }
	line := text.Line{
		style:     style.Style{}.bold()
		alignment: layout.Alignment.center
		spans:     [text.span_styled(owner, style.Style{}.green())]
	}
	span_storage := line.spans.data
	string_storage := unsafe { line.spans[0].text.str }
	result := truncate_line_with_ellipsis_if_overflow(line, 4)
	assert result.spans.data == span_storage
	assert unsafe { result.spans[0].text.str == string_storage }
	assert result == text.Line{
		style:     style.Style{}.bold()
		alignment: layout.Alignment.center
		spans:     [text.span_styled('ab界', style.Style{}.green())]
	}
}

fn test_line_width_reuses_borrowed_owned_line_and_clone_is_independent() {
	owner := $if ownership ? { 'abｶﾞ界'.to_owned() } $else { 'abｶﾞ界'.clone() }
	line := text.Line{
		style:     style.Style{}.bold()
		alignment: layout.Alignment.center
		spans:     [text.span_styled(owner, style.Style{}.green())]
	}
	assert line_width(&line) == 6
	assert line_width(&line) == 6
	assert truncate_line_to_width(line.clone(), 3) == text.Line{
		style:     style.Style{}.bold()
		alignment: layout.Alignment.center
		spans:     [text.span_styled('ab', style.Style{}.green())]
	}
	assert line.spans[0].text == 'abｶﾞ界'
	assert line_width(&line) == 6
}
