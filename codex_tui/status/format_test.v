module status

import ratatui.layout
import ratatui.style
import ratatui.text
import std_collections
import std_iter

struct FormatStringLike {
	text            string
	expected_buffer usize
}

fn (label &FormatStringLike) as_ref() &string {
	if label.expected_buffer != 0 {
		actual_buffer := usize(label.text.str)
		matches_buffer := actual_buffer == label.expected_buffer
		assert matches_buffer
	}
	return &label.text
}

@[heap]
struct FormatIterationProbe {
mut:
	pulls int
}

struct FormatScriptedLabels {
	probe &FormatIterationProbe
}

struct FormatScriptedIterator {
mut:
	probe &FormatIterationProbe
}

fn (labels FormatScriptedLabels) into_iter() FormatScriptedIterator {
	return FormatScriptedIterator{ probe: labels.probe }
}

fn (mut iter FormatScriptedIterator) next() ?FormatStringLike {
	index := iter.probe.pulls
	iter.probe.pulls++
	if index == 2 {
		return none
	}
	if index == 0 {
		return FormatStringLike{ text: 'short'.clone() }
	}
	return FormatStringLike{ text: 'a longer label'.clone() }
}

fn test_field_formatter_consumes_generic_iterator_only_until_first_none() {
	probe := &FormatIterationProbe{}
	formatter := FieldFormatter.from_labels(FormatScriptedLabels{ probe: probe })
	assert probe.pulls == 3
	assert formatter.value_width(30) == 11
}

fn test_field_formatter_aligns_unicode_labels_and_preserves_value_styles() {
	formatter := FieldFormatter.from_labels(std_iter.owned_array(['x', '界', 'ｶﾞ']))
	label := 'x'
	value := formatter.line(&label, [text.span_styled('value'.clone(), style.Style{}.bold())])
	assert value == text.Line{
		spans: [text.Span{ text: ' x:    ', style: style.Style{}.dim() },
			text.Span{ text: 'value', style: style.Style{}.bold() }]
	}
	wide := '界'
	assert formatter.full_spans(&wide, []text.Span{}) == [text.Span{
		text:  ' 界:   '
		style: style.Style{}.dim()
	}]
	assert formatter.continuation([text.Span{ text: 'wrapped'.clone() }]) == text.Line{
		spans: [text.Span{ text: '       ', style: style.Style{}.dim() }, text.Span{ text: 'wrapped' }]
	}
	assert formatter.value_width(10) == 3
}

fn test_field_formatter_empty_labels_and_saturating_widths() {
	formatter := FieldFormatter.from_labels(std_iter.owned_array([]string{}))
	assert formatter.value_width(0) == 0
	assert formatter.value_width(4) == 0
	assert formatter.value_width(5) == 0
	assert formatter.value_width(6) == 1
	label := 'longer'
	assert formatter.full_spans(&label, []text.Span{}) == [text.Span{
		text:  ' longer:   '
		style: style.Style{}.dim()
	}]
}

fn test_field_formatter_borrows_dynamic_label_owners_more_than_once() {
	mut owner := ['one', '界界']
	mut label := 'one'
	$if ownership ? {
		owner = ['one'.to_owned(), '界界'.to_owned()]
		label = label.to_owned()
	}
	first := FieldFormatter.from_labels(std_iter.borrowed_slice(&owner))
	second := FieldFormatter.from_labels(std_iter.borrowed_slice(&owner))
	assert first.value_width(20) == 11
	assert second.value_width(20) == 11
	assert first.full_spans(&label, []text.Span{}) == [text.Span{
		text:  ' one:    '
		style: style.Style{}.dim()
	}]
	assert second.full_spans(&label, []text.Span{}) == first.full_spans(&label, []text.Span{})
	assert owner == ['one', '界界']
	assert label == 'one'
}

fn test_field_formatter_accepts_shared_string_reference_items() {
	mut owner := 'shared label'
	$if ownership ? {
		owner = owner.to_owned()
	}
	formatter := FieldFormatter.from_labels(std_iter.owned_array([&owner]))
	assert formatter.value_width(30) == 13
	refs := [&owner]
	borrowed := FieldFormatter.from_labels(std_iter.borrowed_slice(&refs))
	assert borrowed.value_width(30) == 13
	assert formatter.line(&owner, []text.Span{}) == text.Line{
		spans: [text.Span{ text: ' shared label:   ', style: style.Style{}.dim() }]
	}
	assert owner == 'shared label'
}

fn test_field_formatter_reborrows_custom_as_ref_item_owners() {
	mut content := 'wide 界'
	$if ownership ? {
		content = content.to_owned()
	}
	buffer := usize(content.str)
	owner := [FormatStringLike{ text: content, expected_buffer: buffer }]
	first := FieldFormatter.from_labels(std_iter.borrowed_slice(&owner))
	second := FieldFormatter.from_labels(std_iter.borrowed_slice(&owner))
	assert first.value_width(20) == 8
	assert second.value_width(20) == 8
	assert owner[0].text == 'wide 界'
}

fn test_field_formatter_consumes_owned_as_ref_items() {
	mut first := 'ab'
	mut second := '👩‍👩‍👧‍👦'
	$if ownership ? {
		first = first.to_owned()
		second = second.to_owned()
	}
	first_buffer := usize(first.str)
	second_buffer := usize(second.str)
	items := [FormatStringLike{ text: first, expected_buffer: first_buffer },
		FormatStringLike{ text: second, expected_buffer: second_buffer }]
	formatter := FieldFormatter.from_labels(std_iter.owned_array(items))
	assert formatter.value_width(20) == 13
}

fn test_field_formatter_clone_retains_owned_indent_after_original_scope_ends() {
	formatter := cloned_formatter_fixture()
	assert formatter.continuation([text.Span{ text: 'later'.clone() }]) == text.Line{
		spans: [text.Span{ text: '          ', style: style.Style{}.dim() },
			text.Span{ text: 'later' }]
	}
}

fn cloned_formatter_fixture() FieldFormatter {
	formatter := FieldFormatter.from_labels(std_iter.owned_array(['label'.clone()]))
	cloned := formatter.clone()
	assert formatter.value_indent.str != cloned.value_indent.str
	return cloned
}

fn test_push_label_preserves_discovery_order_and_clones_set_keys() {
	mut first := 'zeta'
	mut second := 'alpha'
	$if ownership ? {
		first = first.to_owned()
		second = second.to_owned()
	}
	mut labels := []string{}
	mut seen := std_collections.BTreeSet[string]{}
	push_label(mut labels, mut seen, &first)
	push_label(mut labels, mut seen, &second)
	push_label(mut labels, mut seen, &first)
	assert labels == ['zeta', 'alpha']
	assert first == 'zeta'
	assert second == 'alpha'
	labels[0] = 'changed'.clone()
	assert seen.contains(&first)
	push_label(mut labels, mut seen, &first)
	assert labels == ['changed', 'alpha']
}

fn test_truncate_line_zero_width_discards_all_text_and_line_metadata() {
	line := text.Line{
		style:     style.Style{}.bold()
		alignment: layout.Alignment.right
		spans:     [text.Span{ text: 'present'.clone() }, text.Span{ text: '\u0301'.clone() }]
	}
	assert truncate_line_to_width(line, 0) == text.Line{}
}

fn test_truncate_line_moves_owned_spans_and_rebuilds_line_metadata() {
	line := owned_format_line_fixture()
	first_buffer := usize(line.spans[0].text.str)
	truncated := truncate_line_to_width(line, 6)
	assert usize(truncated.spans[0].text.str) == first_buffer
	assert truncated == text.Line{
		spans: [text.Span{ text: 'abc', style: style.Style{}.bold() },
			text.Span{ text: '界x', style: style.Style{}.italic() }]
	}
}

fn test_formatter_line_full_spans_and_continuation_move_value_buffers() {
	formatter := FieldFormatter.from_labels(std_iter.owned_array(['x'.clone()]))
	label := 'x'
	first := text.Span{ text: 'first'.clone(), style: style.Style{}.bold() }
	first_buffer := usize(first.text.str)
	line := formatter.line(&label, [first])
	assert usize(line.spans[1].text.str) == first_buffer
	assert line.spans[1].text == 'first'
	second := text.Span{ text: 'second'.clone() }
	second_buffer := usize(second.text.str)
	spans := formatter.full_spans(&label, [second])
	assert usize(spans[1].text.str) == second_buffer
	assert spans[1].text == 'second'
	third := text.Span{ text: 'third'.clone() }
	third_buffer := usize(third.text.str)
	continuation := formatter.continuation([third])
	assert usize(continuation.spans[1].text.str) == third_buffer
	assert continuation.spans[1].text == 'third'
}

fn owned_format_line_fixture() text.Line {
	mut first := 'abc'
	mut second := '界xyz'
	$if ownership ? {
		first = first.to_owned()
		second = second.to_owned()
	}
	return text.Line{
		style:     style.Style{}.dim()
		alignment: layout.Alignment.center
		spans:     [text.Span{ text: first, style: style.Style{}.bold() },
			text.Span{ text: second, style: style.Style{}.italic() }]
	}
}

fn test_truncate_line_keeps_extended_clusters_and_stops_after_partial_span() {
	mut content := 'e\u0301👩‍👩‍👧‍👦界tail'
	$if ownership ? {
		content = content.to_owned()
	}
	line := text.Line{
		spans: [text.Span{ text: content, style: style.Style{}.underlined() },
			text.Span{ text: '\u0301'.clone() }]
	}
	assert truncate_line_to_width(line, 3) == text.Line{
		spans: [text.Span{ text: 'e\u0301👩‍👩‍👧‍👦', style: style.Style{}.underlined() }]
	}
}

fn test_truncate_line_retains_zero_width_spans_at_budget_until_visible_overflow() {
	line := text.Line{
		spans: [text.Span{ text: 'a'.clone() },
			text.Span{ text: '\u0301'.clone(), style: style.Style{}.italic() }, text.Span{},
			text.Span{ text: 'b'.clone() }, text.Span{ text: '\u0302'.clone() }]
	}
	assert truncate_line_to_width(line, 1) == text.Line{
		spans: [text.Span{ text: 'a' }, text.Span{ text: '\u0301', style: style.Style{}.italic() },
			text.Span{}]
	}
}

fn test_truncate_line_accepts_zero_width_grapheme_before_unfittable_wide_glyph() {
	line := text.Line{
		spans: [text.Span{ text: '\u0301界a'.clone(), style: style.Style{}.bold() }]
	}
	assert truncate_line_to_width(line, 1) == text.Line{
		spans: [text.Span{ text: '\u0301', style: style.Style{}.bold() }]
	}
}

fn test_truncate_line_full_width_fit_preserves_span_styles_but_resets_line_style() {
	line := text.Line{
		style:     style.Style{}.dim()
		alignment: layout.Alignment.center
		spans:     [text.Span{ text: 'ｶﾞ'.clone(), style: style.Style{}.bold() }]
	}
	assert truncate_line_to_width(line, 2) == text.Line{
		spans: [text.Span{ text: 'ｶﾞ', style: style.Style{}.bold() }]
	}
}
