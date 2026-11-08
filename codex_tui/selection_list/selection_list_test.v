module selection_list

import crossterm.cursor
import ratatui.buffer
import ratatui.layout
import ratatui.style
import strings

fn rendered_rows(buf &buffer.Buffer) []string {
	mut rows := []string{cap: int(buf.area.height)}
	for y in 0 .. int(buf.area.height) {
		mut row := strings.new_builder(int(buf.area.width))
		for x in 0 .. int(buf.area.width) {
			cell := &buf.cells[y * int(buf.area.width) + x]
			row.write_string(cell.symbol)
		}
		rows << row.str()
	}
	return rows
}

fn test_selected_row_formats_number_and_applies_cyan() {
	row := selection_option_row(9, 'Pick', true)
	area := layout.Rect.new(2, 3, 10, 1)
	mut buf := buffer.Buffer.empty(area)
	assert row.desired_height(area.width) == 1
	row.render(area, mut buf)
	assert rendered_rows(&buf) == ['› 10. Pick']
	for i in 0 .. buf.cells.len {
		assert buf.cells[i].style == style.Style{}.cyan()
	}
	assert row.cursor_pos(area) == none
	assert row.cursor_style(area) == cursor.CursorStyle.default_user_shape
}

fn test_unselected_row_formats_number_and_dims_label_and_prefix() {
	row := selection_option_row_with_dim(1, 'Later', false, true)
	area := layout.Rect.new(0, 0, 10, 1)
	mut buf := buffer.Buffer.empty(area)
	row.render(area, mut buf)
	assert rendered_rows(&buf) == ['  2. Later']
	for i in 0 .. buf.cells.len {
		assert buf.cells[i].style == style.Style{}.dim()
	}
}

fn test_selected_cyan_takes_precedence_over_dim() {
	row := selection_option_row_with_dim(0, 'Chosen', true, true)
	area := layout.Rect.new(0, 0, 11, 1)
	mut buf := buffer.Buffer.empty(area)
	row.render(area, mut buf)
	assert rendered_rows(&buf) == ['› 1. Chosen']
	for i in 0 .. buf.cells.len {
		assert buf.cells[i].style == style.Style{}.cyan()
	}
}

fn test_default_constructor_matches_explicit_undimmed_row() {
	default_row := selection_option_row(2, 'Ready', false)
	explicit_row := selection_option_row_with_dim(2, 'Ready', false, false)
	area := layout.Rect.new(0, 0, 10, 1)
	mut default_buf := buffer.Buffer.empty(area)
	mut explicit_buf := buffer.Buffer.empty(area)
	default_row.render(area, mut default_buf)
	explicit_row.render(area, mut explicit_buf)
	assert default_buf.cells == explicit_buf.cells
	assert rendered_rows(&default_buf) == ['  3. Ready']
	for i in 0 .. default_buf.cells.len {
		assert default_buf.cells[i].style == style.Style{}
	}
}

fn test_wrapping_aligns_label_below_prefix() {
	row := selection_option_row(0, 'abc defghi', false)
	area := layout.Rect.new(0, 0, 11, 2)
	assert row.desired_height(15) == 1
	assert row.desired_height(area.width) == 2
	mut buf := buffer.Buffer.empty(area)
	row.render(area, mut buf)
	assert rendered_rows(&buf) == ['  1. abc   ', '     defghi']
	assert row.desired_height(8) == 3
}

fn test_leading_whitespace_and_newlines_are_preserved() {
	row := selection_option_row(0, '  alpha\n beta', true)
	area := layout.Rect.new(0, 0, 12, 2)
	mut buf := buffer.Buffer.empty(area)
	assert row.desired_height(area.width) == 2
	row.render(area, mut buf)
	assert rendered_rows(&buf) == ['› 1.   alpha', '      beta  ']
}

fn test_multibyte_label_uses_display_columns() {
	row := selection_option_row(0, '界e\u0301🙂', true)
	area := layout.Rect.new(0, 0, 10, 1)
	mut buf := buffer.Buffer.empty(area)
	assert row.desired_height(area.width) == 1
	row.render(area, mut buf)
	assert buf.cells.map(it.symbol) == ['›', ' ', '1', '.', ' ', '界', ' ', 'e\u0301', '🙂',
		' ']
	// ratatui-widgets 0.3.2 WordWrapper with trim=false emits ["界", "é🙂"] here.
	// Its final pending segment exceeds the two-column label width; line_count is still two.
	assert row.desired_height(7) == 2
}

fn test_zero_and_prefix_only_widths_clip_without_rendering_label() {
	row := selection_option_row(0, 'ab', true)
	assert row.desired_height(0) == 0
	assert row.desired_height(3) == 1
	assert row.desired_height(5) == 1
	assert row.desired_height(6) == 2
	area := layout.Rect.new(0, 0, 3, 1)
	mut buf := buffer.Buffer.empty(area)
	row.render(area, mut buf)
	assert rendered_rows(&buf) == ['› 1']
	before := buf.cells.clone()
	row.render(layout.Rect.new(0, 0, 0, 1), mut buf)
	row.render(layout.Rect.new(0, 0, 3, 0), mut buf)
	assert buf.cells == before
}

fn test_owned_heap_label_survives_returned_row_and_repeated_shared_calls() {
	mut label := 'heap label'
	mut default_label := 'default heap'
	$if ownership ? {
		label = label.to_owned()
		default_label = default_label.to_owned()
	}
	row := selection_option_row_with_dim(0, label, false, true)
	default_row := selection_option_row(1, default_label, false)
	area := layout.Rect.new(0, 0, 15, 1)
	default_area := layout.Rect.new(0, 0, 17, 1)
	mut buf := buffer.Buffer.empty(area)
	mut default_buf := buffer.Buffer.empty(default_area)
	for _ in 0 .. 2 {
		assert row.desired_height(area.width) == 1
		row.render(area, mut buf)
		assert rendered_rows(&buf) == ['  1. heap label']
		assert default_row.desired_height(default_area.width) == 1
		default_row.render(default_area, mut default_buf)
		assert rendered_rows(&default_buf) == ['  2. default heap']
	}
	assert row.desired_height(10) == 2
	assert default_row.desired_height(12) == 2
}
