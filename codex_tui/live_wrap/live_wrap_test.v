module live_wrap

fn test_rows_do_not_exceed_width_ascii() {
	mut rb := RowBuilder.new( /* target_width */
	10)
	text := 'hello whirl this is a test'
	rb.push_fragment(&text)
	rows := snapshot_rows(rb.rows())
	assert rows == [Row{ text: 'hello whir', explicit_break: false },
		Row{ text: 'l this is ', explicit_break: false }]
}

fn test_rows_do_not_exceed_width_emoji_cjk() {
	// 😀 is width 2; 你/好 are width 2.
	mut rb := RowBuilder.new( /* target_width */
	6)
	text := '😀😀 你好'
	rb.push_fragment(&text)
	rows := snapshot_rows(rb.rows())
	// At width 6, we expect the first row to fit exactly two emojis and a space
	// (2 + 2 + 1 = 5) plus one more column for the first CJK char (2 would overflow),
	// so only the two emojis and the space fit; the rest remains buffered.
	assert rows == [Row{ text: '😀😀 ', explicit_break: false }]
}

fn test_halfwidth_sound_marks_stay_with_their_grapheme_when_wrapping() {
	text := 'abｶﾞc'
	prefix_three, suffix_three, width_three := take_prefix_by_width(&text, /* max_cols */
		3)
	assert prefix_three == 'ab'
	assert suffix_three == 'ｶﾞc'
	assert width_three == 2
	text_2 := 'abｶﾞc'
	prefix_four, suffix_four, width_four := take_prefix_by_width(&text_2, /* max_cols */
		4)
	assert prefix_four == 'abｶﾞ'
	assert suffix_four == 'c'
	assert width_four == 4
	mut row_builder := RowBuilder.new( /* target_width */
	1)
	text_3 := 'ｶﾞx'
	row_builder.push_fragment(&text_3)
	assert (*row_builder.rows())[0].text == 'ｶﾞ'
}

fn test_fragmentation_invariance_long_token() {
	s := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' // 26 chars
	mut rb_all := RowBuilder.new( /* target_width */
	7)
	rb_all.push_fragment(&s)
	all_rows := snapshot_rows(rb_all.rows())
	mut rb_chunks := RowBuilder.new( /* target_width */
	7)
	for i := 0; i < s.len; i += 3 {
		end := if i + 3 < s.len { i + 3 } else { s.len }
		fragment := s[i..end]
		rb_chunks.push_fragment(&fragment)
	}
	chunk_rows := snapshot_rows(rb_chunks.rows())
	assert all_rows == chunk_rows
}

fn test_newline_splits_rows() {
	mut rb := RowBuilder.new( /* target_width */
	10)
	text := 'hello\nworld'
	rb.push_fragment(&text)
	rows := rb.display_rows()
	assert rows.any(it.explicit_break)
	assert rows[0].text == 'hello'
	// Second row should begin with 'world'
	assert rows.any(it.text.starts_with('world'))
}

fn test_rewrap_on_width_change() {
	mut rb := RowBuilder.new( /* target_width */
	10)
	text := 'abcdefghijK'
	rb.push_fragment(&text)
	assert rb.rows().len != 0
	rb.set_width( /* width */
	5)
	for row in *rb.rows() {
		assert row.width() <= 5
	}
}

fn test_width_clamps_to_one_and_preserves_indivisible_graphemes() {
	mut builder := RowBuilder.new(0)
	text := '😀x'
	builder.push_fragment(&text)
	assert builder.display_rows() == [Row{ text: '😀' }, Row{ text: 'x' }]
	builder.set_width(0)
	assert builder.display_rows() == [Row{ text: '😀' }, Row{ text: 'x' }]
}

fn test_empty_fragments_and_explicit_empty_lines() {
	mut builder := RowBuilder.new(2)
	text := ''
	builder.push_fragment(&text)
	assert builder.display_rows().len == 0
	text_2 := '\n\n'
	builder.push_fragment(&text_2)
	assert builder.display_rows() == [Row{ explicit_break: true }, Row{ explicit_break: true }]
	text_3 := '界\n'
	builder.push_fragment(&text_3)
	assert builder.display_rows() == [Row{ explicit_break: true }, Row{ explicit_break: true },
		Row{ text: '界', explicit_break: true }]
}

fn test_exact_width_line_stays_pending_until_more_input_or_newline() {
	mut builder := RowBuilder.new(2)
	text := 'ab'
	builder.push_fragment(&text)
	assert builder.rows().len == 0
	assert builder.display_rows() == [Row{ text: 'ab' }]
	text_2 := '\n'
	builder.push_fragment(&text_2)
	assert *builder.rows() == [Row{ text: 'ab', explicit_break: true }]
	text_3 := 'abcd\n'
	builder.push_fragment(&text_3)
	assert *builder.rows() == [Row{ text: 'ab', explicit_break: true }, Row{ text: 'ab' },
		Row{ text: 'cd', explicit_break: true }]
}

fn test_rewrap_retains_newlines_and_current_partial_line() {
	mut builder := RowBuilder.new(2)
	text := 'abc\n\ndefg'
	builder.push_fragment(&text)
	builder.set_width(3)
	assert builder.display_rows() == [Row{ text: 'abc', explicit_break: true },
		Row{ explicit_break: true }, Row{ text: 'def' }, Row{ text: 'g' }]
	builder.set_width(10)
	assert builder.display_rows() == [Row{ text: 'abc', explicit_break: true },
		Row{ explicit_break: true }, Row{ text: 'defg' }]
}

fn test_drain_commit_ready_counts_partial_line_and_preserves_order() {
	mut builder := RowBuilder.new(2)
	text := 'abcdefg'
	builder.push_fragment(&text)
	assert builder.drain_commit_ready(4).len == 0
	assert builder.drain_commit_ready(2) == [Row{ text: 'ab' }, Row{ text: 'cd' }]
	assert builder.display_rows() == [Row{ text: 'ef' }, Row{ text: 'g' }]
	assert builder.drain_commit_ready(0) == [Row{ text: 'ef' }]
	assert builder.display_rows() == [Row{ text: 'g' }]
	assert builder.drain_commit_ready(0).len == 0
	text_2 := '\n'
	builder.push_fragment(&text_2)
	assert builder.drain_commit_ready(0) == [Row{ text: 'g', explicit_break: true }]
	assert builder.display_rows().len == 0
}

fn test_prefix_preserves_zero_width_and_grapheme_edges() {
	text := 'a\u200bb'
	prefix, suffix, cols := take_prefix_by_width(&text, 1)
	assert prefix == 'a'
	assert suffix == '\u200bb'
	assert cols == 1
	text_2 := '\u200b'
	zero_prefix, zero_suffix, zero_cols := take_prefix_by_width(&text_2, 1)
	assert zero_prefix == '\u200b'
	assert zero_suffix == ''
	assert zero_cols == 0
	mut builder := RowBuilder.new(1)
	text_3 := '\u200b'
	builder.push_fragment(&text_3)
	assert *builder.rows() == [Row{ text: '\u200b' }]
	assert builder.display_rows() == [Row{ text: '\u200b' }]
	text_4 := 'a\u0301b'
	combining_prefix, combining_suffix, combining_cols := take_prefix_by_width(&text_4, 1)
	assert combining_prefix == 'a\u0301'
	assert combining_suffix == 'b'
	assert combining_cols == 1
}

fn test_prefix_empty_zero_and_maximum_width() {
	for max_cols in [usize(0), 1, ~usize(0)] {
		text := ''
		prefix, suffix, cols := take_prefix_by_width(&text, max_cols)
		assert prefix == ''
		assert suffix == ''
		assert cols == 0
	}
	text_2 := '界abc'
	zero_prefix, zero_suffix, zero_cols := take_prefix_by_width(&text_2, 0)
	assert zero_prefix == ''
	assert zero_suffix == '界abc'
	assert zero_cols == 0
	text_3 := '界abc'
	max_prefix, max_suffix, max_cols := take_prefix_by_width(&text_3, ~usize(0))
	assert max_prefix == '界abc'
	assert max_suffix == ''
	assert max_cols == 5
}

fn test_borrowed_input_and_row_views_remain_reusable() {
	mut input := 'ab😀\nc'
	$if ownership ? {
		input = 'ab😀\nc'.to_owned()
	}
	first_prefix, first_suffix, first_width := take_prefix_by_width(&input, 2)
	second_prefix, second_suffix, second_width := take_prefix_by_width(&input, 2)
	assert first_prefix == second_prefix
	assert first_suffix == second_suffix
	assert first_width == second_width
	assert input == 'ab😀\nc'
	mut builder := RowBuilder.new(2)
	builder.push_fragment(&input)
	first_rows := builder.rows()
	second_rows := builder.rows()
	assert first_rows == second_rows
	assert *first_rows == [Row{ text: 'ab' }, Row{ text: '😀', explicit_break: true }]
	first_display := builder.display_rows()
	second_display := builder.display_rows()
	assert first_display == second_display
	assert input == 'ab😀\nc'
	assert builder.rows().len == 2
	builder.push_fragment(&input)
	assert input == 'ab😀\nc'
	assert builder.display_rows().last() == Row{ text: 'c' }
}

fn test_owned_rows_survive_commit_and_builder_reuse() {
	mut input := 'abcdefg'
	$if ownership ? {
		input = 'abcdefg'.to_owned()
	}
	mut builder := RowBuilder.new(2)
	builder.push_fragment(&input)
	drained := builder.drain_commit_ready(2)
	builder.set_width(3)
	builder.push_fragment(&input)
	assert drained == [Row{ text: 'ab' }, Row{ text: 'cd' }]
	assert builder.display_rows() == [Row{ text: 'efg' }, Row{ text: 'abc' }, Row{ text: 'def' },
		Row{ text: 'g' }]
	assert input == 'abcdefg'
	last_drained := builder.drain_commit_ready(0)
	assert last_drained == [Row{ text: 'efg' }, Row{ text: 'abc' }, Row{ text: 'def' }]
	assert drained == [Row{ text: 'ab' }, Row{ text: 'cd' }]
	assert builder.display_rows() == [Row{ text: 'g' }]
}

// Rust's rows().to_vec() snapshots clone each Row and its owned text.
fn snapshot_rows(rows &[]Row) []Row {
	mut out := []Row{cap: rows.len}
	for i in 0 .. rows.len {
		out << (*rows)[i].clone()
	}
	return out
}
