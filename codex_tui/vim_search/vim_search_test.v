module vim_search

import std_ops

fn collect_ranges(text &string, query &string) []std_ops.Range[usize] {
	mut result := []std_ops.Range[usize]{}
	mut ranges := matching_ranges(text, query)
	for {
		value := ranges.next() or { break }
		result << value
	}
	return result
}

fn test_direction_reversal_and_query_defaults() {
	assert SearchDirection.default().reversed() == SearchDirection.backward
	assert SearchDirection.backward.reversed() == SearchDirection.forward
	assert SearchDirection.forward.reversed().reversed() == SearchDirection.forward
	assert SearchQuery.default() == SearchQuery{ text: '', direction: .forward }
}

fn test_query_clone_owns_independent_text_and_preserves_direction() {
	mut owned := 'pending'.clone()
	$if ownership ? {
		owned = 'pending'.to_owned()
	}
	mut query := SearchQuery{ text: owned, direction: .backward }
	cloned := query.clone()
	query.text = 'accepted'.clone()
	assert cloned == SearchQuery{ text: 'pending', direction: .backward }
	assert query == SearchQuery{ text: 'accepted', direction: .backward }
}

fn test_empty_query_and_empty_text_have_no_matches() {
	text_1 := 'searchable'
	query_1 := ''
	assert collect_ranges(&text_1, &query_1) == []std_ops.Range[usize]{}
	text_2 := ''
	query_2 := ''
	assert collect_ranges(&text_2, &query_2) == []std_ops.Range[usize]{}
	text_3 := ''
	query_3 := 'needle'
	assert collect_ranges(&text_3, &query_3) == []std_ops.Range[usize]{}
	text_4 := 'searchable'
	query_4 := ''
	mut ranges := matching_ranges(&text_4, &query_4)
	assert ranges.next() == none
	assert ranges.next() == none
	assert !ranges.initialized
	assert ranges.graphemes.len == 0
}

fn test_literal_search_preserves_overlapping_matches() {
	text_5 := 'aaaa'
	query_5 := 'aa'
	assert collect_ranges(&text_5, &query_5) == [
		std_ops.Range[usize]{ start: 0, end: 2 },
		std_ops.Range[usize]{ start: 1, end: 3 },
		std_ops.Range[usize]{ start: 2, end: 4 },
	]
	text_6 := 'a.a aa a.a'
	query_6 := 'a.a'
	assert collect_ranges(&text_6, &query_6) == [
		std_ops.Range[usize]{ start: 0, end: 3 },
		std_ops.Range[usize]{ start: 7, end: 10 },
	]
	text_7 := 'AaA'
	query_7 := 'a'
	assert collect_ranges(&text_7, &query_7) == [std_ops.Range[usize]{ start: 1, end: 2 }]
}

fn test_partial_combining_grapheme_match_extends_to_complete_grapheme() {
	text := 'a\u0301\u0327b a\u0301'
	query_8 := 'a'
	assert collect_ranges(&text, &query_8) == [
		std_ops.Range[usize]{ start: 0, end: 5 },
		std_ops.Range[usize]{ start: 7, end: 10 },
	]
	query_9 := 'a\u0301'
	assert collect_ranges(&text, &query_9) == [
		std_ops.Range[usize]{ start: 0, end: 5 },
		std_ops.Range[usize]{ start: 7, end: 10 },
	]
	query_10 := '\u0301'
	assert collect_ranges(&text, &query_10) == []std_ops.Range[usize]{}
	query_11 := '\u0327b'
	assert collect_ranges(&text, &query_11) == []std_ops.Range[usize]{}
}

fn test_zwj_emoji_match_extends_to_complete_family() {
	text := '👩‍👩‍👧‍👦 👩'
	query_12 := '👩'
	assert collect_ranges(&text, &query_12) == [
		std_ops.Range[usize]{ start: 0, end: 25 },
		std_ops.Range[usize]{ start: 26, end: 30 },
	]
	query_13 := '👩‍'
	assert collect_ranges(&text, &query_13) == [std_ops.Range[usize]{ start: 0, end: 25 }]
	query_14 := '👧'
	assert collect_ranges(&text, &query_14) == []std_ops.Range[usize]{}
}

fn test_matching_ranges_use_utf8_byte_offsets() {
	text_15 := 'é aa 文a'
	query_15 := 'a'
	assert collect_ranges(&text_15, &query_15) == [
		std_ops.Range[usize]{ start: 3, end: 4 },
		std_ops.Range[usize]{ start: 4, end: 5 },
		std_ops.Range[usize]{ start: 9, end: 10 },
	]
	text_16 := 'é aa 文a'
	query_16 := '文a'
	assert collect_ranges(&text_16, &query_16) == [std_ops.Range[usize]{ start: 6, end: 10 }]
}

fn test_crlf_end_and_start_boundaries() {
	text_17 := '\r\n\r\n'
	query_17 := '\r'
	assert collect_ranges(&text_17, &query_17) == [
		std_ops.Range[usize]{ start: 0, end: 2 },
		std_ops.Range[usize]{ start: 2, end: 4 },
	]
	text_18 := '\r\n\r\n'
	query_18 := '\n'
	assert collect_ranges(&text_18, &query_18) == []std_ops.Range[usize]{}
}

fn test_prefix_can_span_several_graphemes_and_partial_last_grapheme() {
	text_19 := 'ab\u0301c ab\u0301'
	query_19 := 'ab'
	assert collect_ranges(&text_19, &query_19) == [
		std_ops.Range[usize]{ start: 0, end: 4 },
		std_ops.Range[usize]{ start: 6, end: 10 },
	]
	text_20 := 'ab\u0301c'
	query_20 := 'ab\u0301c'
	assert collect_ranges(&text_20, &query_20) == [std_ops.Range[usize]{ start: 0, end: 5 }]
	text_21 := 'ab\u0301c'
	query_21 := 'ab\u0301cd'
	assert collect_ranges(&text_21, &query_21) == []std_ops.Range[usize]{}
}

fn test_lazy_iterators_borrow_heap_owners_repeatedly_and_preserve_them() {
	mut text := 'éaaaa'
	mut query := 'aa'
	$if ownership ? {
		text = 'éaaaa'.to_owned()
		query = 'aa'.to_owned()
	}
	{
		mut first := matching_ranges(&text, &query)
		mut second := matching_ranges(&text, &query)
		assert !first.initialized
		assert first.graphemes.len == 0
		assert first.cursor == 0
		assert first.next() or { panic('missing first range') } == std_ops.Range[usize]{ start: 2, end: 4 }
		assert first.cursor == 2
		assert second.next() or { panic('missing independent range') } == std_ops.Range[usize]{ start: 2, end: 4 }
		assert first.next() or { panic('missing second range') } == std_ops.Range[usize]{ start: 3, end: 5 }
		assert second.next() or { panic('missing independent second range') } == std_ops.Range[usize]{ start: 3, end: 5 }
		assert first.next() or { panic('missing final range') } == std_ops.Range[usize]{ start: 4, end: 6 }
		assert first.next() == none
		assert first.next() == none
	}
	assert text == 'éaaaa'
	assert query == 'aa'
	assert collect_ranges(&text, &query) == collect_ranges(&text, &query)
	assert text.len == 6
	assert query.len == 2
}
