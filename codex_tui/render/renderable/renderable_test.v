module renderable

import crossterm.cursor
import ratatui.buffer
import ratatui.layout
import ratatui.style
import ratatui.text
import ratatui.widgets
import codex_tui.render

struct HeightRenderable {
	height u16
}

fn HeightRenderable.with_height(height u16) HeightRenderable {
	return HeightRenderable{ height: height }
}

fn (child &HeightRenderable) render(_area layout.Rect, mut _buf buffer.Buffer) {}

fn (child &HeightRenderable) desired_height(_width u16) u16 {
	return child.height
}

fn test_flex_redistributes_space_unused_by_short_children() {
	mut flex := FlexRenderable.new()
	flex.push( /*flex*/
	1, RenderableItem.owned(HeightRenderable.with_height( /*height*/
	20)))
	flex.push( /*flex*/
	1, RenderableItem.owned(HeightRenderable.with_height( /*height*/
	2)))

	allocated := flex.allocate(layout.Rect.new( /*x*/
	0, /*y*/
		0, /*width*/
		80, /*height*/
		10))

	assert allocated.map(it.height) == [u16(8), 2]
}

fn test_flex_reserves_non_flex_space_before_flexible_children() {
	mut flex := FlexRenderable.new()
	flex.push( /*flex*/
	1, RenderableItem.owned(HeightRenderable.with_height( /*height*/
	20)))
	flex.push( /*flex*/
	0, RenderableItem.owned(HeightRenderable.with_height( /*height*/
	2)))
	flex.push( /*flex*/
	1, RenderableItem.owned(HeightRenderable.with_height( /*height*/
	20)))

	allocated := flex.allocate(layout.Rect.new( /*x*/
	0, /*y*/
		0, /*width*/
		80, /*height*/
		10))

	assert allocated.map(it.height) == [u16(4), 2, 4]
}

// Rust's local Cell<usize> is an allocation-free counter with the same single-threaded
// interior-mutability boundary as the target's height cache.
@[heap]
struct CallCell {
mut:
	count usize
}

fn (cell &CallCell) increment() {
	unsafe {
		mut mutable_cell := cell
		mutable_cell.count++
	}
}

struct CountingRenderable {
	calls &CallCell
}

fn (child &CountingRenderable) render(_area layout.Rect, mut _buf buffer.Buffer) {}

fn (child &CountingRenderable) desired_height(_width u16) u16 {
	child.calls.increment()
	return 1
}

fn (child &CountingRenderable) cursor_pos(area layout.Rect) ?CursorPosition {
	return CursorPosition{ x: area.x, y: area.y }
}

fn test_flex_caches_child_height_across_frame_passes() {
	calls := &CallCell{}
	child := Renderable(CountingRenderable{ calls: calls })
	mut flex := FlexRenderable.new()
	flex.push( /*flex*/
	1, RenderableItem.borrowed(&child))
	area := layout.Rect.new( /*x*/
	0, /*y*/
		0, /*width*/
		80, /*height*/
		10)
	mut buf := buffer.Buffer.empty(area)

	assert flex.desired_height(area.width) == 1
	flex.render(area, mut buf)
	assert flex.cursor_pos(area)? == CursorPosition{ x: 0, y: 0 }
	assert flex.cursor_style(area) == cursor.CursorStyle.default_user_shape
	assert calls.count == 1

	assert flex.desired_height( /*width*/
	100) == 1
	assert calls.count == 2
}

@[heap]
struct RenderCalls {
mut:
	areas   []layout.Rect
	offsets []u16
	widths  []u16
}

struct ProbeRenderable {
	height       u16
	cursor       bool
	cursor_shape cursor.CursorStyle
	calls        &RenderCalls
}

fn (child &ProbeRenderable) render(area layout.Rect, mut _buf buffer.Buffer) {
	unsafe {
		mut calls := child.calls
		calls.areas << area
	}
}

fn (child &ProbeRenderable) desired_height(width u16) u16 {
	unsafe {
		mut calls := child.calls
		calls.widths << width
	}
	return child.height
}

fn (child &ProbeRenderable) cursor_pos(area layout.Rect) ?CursorPosition {
	if child.cursor {
		return CursorPosition{ x: area.x, y: area.y }
	}
	return none
}

fn (child &ProbeRenderable) cursor_style(_area layout.Rect) cursor.CursorStyle {
	return child.cursor_shape
}

struct ScrollingProbe {
	height u16
	calls  &RenderCalls
}

fn (child &ScrollingProbe) render(area layout.Rect, mut buf buffer.Buffer) {
	unsafe {
		mut calls := child.calls
		calls.areas << area
		calls.offsets << u16(0)
	}
	buf.put_cell(area.x, area.y, 'R', style.Style{})
}

fn (child &ScrollingProbe) desired_height(_width u16) u16 {
	return child.height
}

fn (child &ScrollingProbe) render_scrolled(area layout.Rect, mut buf buffer.Buffer, offset u16) bool {
	unsafe {
		mut calls := child.calls
		calls.areas << area
		calls.offsets << offset
	}
	buf.put_cell(area.x, area.y, 'S', style.Style{})
	return true
}

fn (child &ScrollingProbe) cursor_pos(area layout.Rect) ?CursorPosition {
	return CursorPosition{ x: area.x, y: area.y }
}

fn (child &ScrollingProbe) cursor_style(_area layout.Rect) cursor.CursorStyle {
	return .steady_bar
}

fn test_default_scrolled_and_cursor_methods_keep_buffer_unchanged() {
	area := layout.Rect.new(1, 2, 3, 4)
	mut buf := buffer.Buffer.empty(area)
	buf.put_cell(2, 3, 'sentinel', style.Style{}.bold())
	before := buf.cells.clone()
	child := Renderable(StringRenderable.new('plain'))
	assert !child.render_scrolled(area, mut buf, 3)
	assert buf.cells == before
	assert child.cursor_pos(area) == none
	assert child.cursor_style(area) == .default_user_shape
	unit := Renderable(UnitRenderable{})
	assert unit.desired_height(0) == 0
	unit.render(area, mut buf)
	assert buf.cells == before
}

fn test_owned_and_borrowed_items_forward_all_methods() {
	area := layout.Rect.new(4, 5, 6, 7)
	owned_calls := &RenderCalls{}
	borrowed_calls := &RenderCalls{}
	owned := RenderableItem.owned(ScrollingProbe{ height: 12, calls: owned_calls })
	borrowed_owner := Renderable(ScrollingProbe{ height: 13, calls: borrowed_calls })
	borrowed := RenderableItem.borrowed(&borrowed_owner)
	mut buf := buffer.Buffer.empty(area)
	owned.render(area, mut buf)
	borrowed.render(area, mut buf)
	assert owned.desired_height(6) == 12
	assert borrowed.desired_height(6) == 13
	assert owned.render_scrolled(area, mut buf, 2)
	assert borrowed.render_scrolled(area, mut buf, 3)
	assert owned_calls.areas == [area, area]
	assert borrowed_calls.areas == [area, area]
	assert owned_calls.offsets == [u16(0), 2]
	assert borrowed_calls.offsets == [u16(0), 3]
	assert owned.cursor_pos(area)? == CursorPosition{ x: 4, y: 5 }
	assert borrowed.cursor_pos(area)? == CursorPosition{ x: 4, y: 5 }
	assert owned.cursor_style(area) == .steady_bar
	assert borrowed.cursor_style(area) == .steady_bar
	assert borrowed_owner.desired_height(6) == 13
}

fn test_option_and_arc_forward_cursor_but_retain_false_scroll_default() {
	area := layout.Rect.new(0, 0, 4, 5)
	option_calls := &RenderCalls{}
	arc_calls := &RenderCalls{}
	option := Renderable(OptionRenderable.some(RenderableItem.owned(ScrollingProbe{ height: 7, calls: option_calls })))
	arc := Renderable(ArcRenderable.new(ScrollingProbe{ height: 8, calls: arc_calls }))
	absent := Renderable(OptionRenderable.none())
	mut buf := buffer.Buffer.empty(area)
	before := buf.cells.clone()
	assert !option.render_scrolled(area, mut buf, 2)
	assert !arc.render_scrolled(area, mut buf, 2)
	assert !absent.render_scrolled(area, mut buf, 2)
	assert buf.cells == before
	assert option_calls.areas.len == 0
	assert arc_calls.areas.len == 0
	assert option.desired_height(4) == 7
	assert arc.desired_height(4) == 8
	assert absent.desired_height(4) == 0
	assert option.cursor_pos(area)? == CursorPosition{}
	assert arc.cursor_pos(area)? == CursorPosition{}
	assert option.cursor_style(area) == .steady_bar
	assert arc.cursor_style(area) == .steady_bar
	assert absent.cursor_pos(area) == none
	assert absent.cursor_style(area) == .default_user_shape
	absent.render(area, mut buf)
	assert buf.cells == before
	option.render(area, mut buf)
	arc.render(area, mut buf)
	assert option_calls.areas == [area]
	assert arc_calls.areas == [area]
}

fn test_column_clips_children_and_selects_first_visible_cursor() {
	area := layout.Rect.new(3, 4, 8, 4)
	first_calls := &RenderCalls{}
	second_calls := &RenderCalls{}
	third_calls := &RenderCalls{}
	mut column := ColumnRenderable.new()
	column.push(ProbeRenderable{ height: 2, calls: first_calls })
	column.push(ProbeRenderable{ height: 4, cursor: true, cursor_shape: .steady_bar, calls: second_calls })
	column.push(ProbeRenderable{ height: 1, cursor: true, calls: third_calls })
	mut buf := buffer.Buffer.empty(area)
	assert column.desired_height(8) == 7
	column.render(area, mut buf)
	assert first_calls.areas == [layout.Rect.new(3, 4, 8, 2)]
	assert second_calls.areas == [layout.Rect.new(3, 6, 8, 2)]
	assert third_calls.areas.len == 0
	assert column.cursor_pos(area)? == CursorPosition{ x: 3, y: 6 }
	assert column.cursor_style(area) == .steady_bar
	assert column.cursor_pos(layout.Rect.new(3, 4, 8, 2)) == none
	assert column.cursor_style(layout.Rect.new(3, 4, 8, 2)) == .default_user_shape
}

fn test_column_with_moves_items_and_borrowed_owner_remains_reusable() {
	mut value := 'owned heap text'
	$if ownership ? {
		value = value.to_owned()
	}
	owner := Renderable(StringRenderable.new(value))
	column := ColumnRenderable.with([RenderableItem.borrowed(&owner),
		RenderableItem.owned(UnitRenderable{})])
	area := layout.Rect.new(0, 0, 20, 1)
	mut buf := buffer.Buffer.empty(area)
	column.render(area, mut buf)
	column.render(area, mut buf)
	assert column.desired_height(20) == 1
	assert owner.desired_height(20) == 1
	owner.render(area, mut buf)
	assert buf.cells[0].symbol == 'o'
}

fn test_flex_weighted_rounding_zero_space_and_short_children() {
	mut flex := FlexRenderable.new()
	flex.push(1, RenderableItem.owned(HeightRenderable.with_height(20)))
	flex.push(2, RenderableItem.owned(HeightRenderable.with_height(20)))
	flex.push(1, RenderableItem.owned(HeightRenderable.with_height(20)))
	assert flex.allocate(layout.Rect.new(2, 3, 8, 11)) == [
		layout.Rect.new(2, 3, 8, 2),
		layout.Rect.new(2, 5, 8, 5),
		layout.Rect.new(2, 10, 8, 4),
	]
	assert flex.allocate(layout.Rect.new(2, 3, 8, 0)).map(it.height) == [u16(0), 0, 0]
	assert flex.desired_height(8) == 60
	mut short := FlexRenderable.new()
	short.push(1, RenderableItem.owned(HeightRenderable.with_height(1)))
	short.push(2, RenderableItem.owned(HeightRenderable.with_height(2)))
	assert short.allocate(layout.Rect.new(0, 0, 8, 20)).map(it.height) == [u16(1), 2]
	mut overflow := FlexRenderable.new()
	overflow.push(-1, RenderableItem.owned(HeightRenderable.with_height(10)))
	overflow.push(0, RenderableItem.owned(HeightRenderable.with_height(2)))
	overflow.push(1, RenderableItem.owned(HeightRenderable.with_height(4)))
	assert overflow.allocate(layout.Rect.new(0, 0, 8, 3)).map(it.height) == [u16(3), 0, 0]
	assert FlexRenderable.new().desired_height(8) == 0
}

fn test_flex_renders_allocations_and_offsets_first_cursor() {
	first_calls := &RenderCalls{}
	second_calls := &RenderCalls{}
	mut flex := FlexRenderable.new()
	flex.push(0, RenderableItem.owned(ProbeRenderable{ height: 2, calls: first_calls }))
	flex.push(1, RenderableItem.owned(ProbeRenderable{ height: 10, cursor: true, cursor_shape: .steady_bar, calls: second_calls }))
	area := layout.Rect.new(5, 6, 9, 7)
	mut buf := buffer.Buffer.empty(area)
	flex.render(area, mut buf)
	assert first_calls.areas == [layout.Rect.new(5, 6, 9, 2)]
	assert second_calls.areas == [layout.Rect.new(5, 8, 9, 5)]
	assert flex.cursor_pos(area)? == CursorPosition{ x: 5, y: 8 }
	assert flex.cursor_style(area) == .steady_bar
	assert first_calls.widths == [u16(9)]
	assert second_calls.widths == [u16(9)]
}

fn test_row_clips_widths_uses_child_width_for_height_and_forwards_cursor() {
	first_calls := &RenderCalls{}
	second_calls := &RenderCalls{}
	third_calls := &RenderCalls{}
	mut row := RowRenderable.new()
	row.push(3, ProbeRenderable{ height: 1, calls: first_calls })
	row.push(65535, ProbeRenderable{ height: 4, cursor: true, cursor_shape: .steady_bar, calls: second_calls })
	row.push(2, ProbeRenderable{ height: 7, cursor: true, calls: third_calls })
	area := layout.Rect.new(2, 3, 8, 5)
	mut buf := buffer.Buffer.empty(area)
	assert row.desired_height(8) == 4
	assert first_calls.widths == [u16(3)]
	assert second_calls.widths == [u16(5)]
	assert third_calls.widths.len == 0
	row.render(area, mut buf)
	assert first_calls.areas == [layout.Rect.new(2, 3, 3, 5)]
	assert second_calls.areas == [layout.Rect.new(5, 3, 5, 5)]
	assert third_calls.areas.len == 0
	assert row.cursor_pos(area)? == CursorPosition{ x: 5, y: 3 }
	assert row.cursor_style(area) == .steady_bar
	assert row.cursor_pos(layout.Rect.new(2, 3, 3, 5)) == none
	assert row.cursor_style(layout.Rect.new(2, 3, 3, 5)) == .default_user_shape
	assert row.desired_height(0) == 0
}

fn test_row_render_breaks_on_zero_width_but_cursor_search_can_continue() {
	first_calls := &RenderCalls{}
	second_calls := &RenderCalls{}
	mut row := RowRenderable.new()
	row.push(0, ProbeRenderable{ height: 7, calls: first_calls })
	row.push(3, ProbeRenderable{ height: 1, cursor: true, cursor_shape: .steady_bar, calls: second_calls })
	area := layout.Rect.new(0, 0, 3, 2)
	mut buf := buffer.Buffer.empty(area)
	row.render(area, mut buf)
	assert first_calls.areas.len == 0
	assert second_calls.areas.len == 0
	assert row.desired_height(3) == 0
	assert row.cursor_pos(area)? == CursorPosition{}
	assert row.cursor_style(area) == .steady_bar
}

fn test_inset_normal_render_height_and_cursor_use_inset_child_area() {
	calls := &RenderCalls{}
	child := InsetRenderable.new(RenderableItem.owned(ProbeRenderable{ height: 3, cursor: true, cursor_shape: .steady_bar, calls: calls }), render.Insets.tlbr(1, 2, 3, 4))
	area := layout.Rect.new(5, 6, 20, 10)
	mut buf := buffer.Buffer.empty(area)
	assert child.desired_height(20) == 7
	assert calls.widths == [u16(14)]
	child.render(area, mut buf)
	assert calls.areas == [layout.Rect.new(7, 7, 14, 6)]
	assert child.cursor_pos(area)? == CursorPosition{ x: 7, y: 7 }
	assert child.cursor_style(area) == .steady_bar
}

fn test_inset_scrolling_preserves_clipped_padding_and_forwards_visible_rows() {
	area := layout.Rect.new(5, 6, 10, 7)
	calls := &RenderCalls{}
	child := InsetRenderable.new(RenderableItem.owned(ScrollingProbe{ height: 10, calls: calls }), render.Insets.tlbr(2, 1, 1, 2))
	mut buf := buffer.Buffer.empty(area)
	assert child.render_scrolled(area, mut buf, 0)
	assert calls.areas == [layout.Rect.new(6, 8, 7, 4)]
	assert calls.offsets == [u16(0)]
	assert child.render_scrolled(area, mut buf, 1)
	assert calls.areas[1] == layout.Rect.new(6, 7, 7, 5)
	assert calls.offsets[1] == 0
	assert child.render_scrolled(area, mut buf, 5)
	assert calls.areas[2] == layout.Rect.new(6, 6, 7, 6)
	assert calls.offsets[2] == 3
}

fn test_inset_empty_visible_children_succeed_without_buffer_writes() {
	area := layout.Rect.new(2, 3, 4, 2)
	mut buf := buffer.Buffer.empty(area)
	before := buf.cells.clone()
	for insets in [render.Insets.tlbr(0, 3, 0, 3), render.Insets.tlbr(2, 0, 0, 0),
		render.Insets.tlbr(0, 0, 2, 0)] {
		child := InsetRenderable.new(RenderableItem.owned(StringRenderable.new('unused')), insets)
		assert child.render_scrolled(area, mut buf, 0)
		assert buf.cells == before
	}
	child := InsetRenderable.new(RenderableItem.owned(StringRenderable.new('unused')), render.Insets{})
	assert child.render_scrolled(area, mut buf, 10)
	assert buf.cells == before
}

fn test_inset_unsupported_scrolling_keeps_entire_buffer_unchanged() {
	area := layout.Rect.new(2, 3, 7, 4)
	mut buf := buffer.Buffer.empty(area)
	buf.put_cell(2, 3, 'top', style.Style{}.cyan())
	buf.put_cell(3, 4, 'child', style.Style{}.dim())
	before := buf.cells.clone()
	child := InsetRenderable.new(RenderableItem.owned(ParagraphRenderable.new(widgets.Paragraph.new('one\ntwo\nthree\nfour'))), render.Insets.tlbr(1, 1, 1, 1))
	assert !child.render_scrolled(area, mut buf, 2)
	assert buf.cells == before
}

fn test_owned_text_adapters_and_consuming_inset_keep_heap_content() {
	mut value := 'heap owned'
	$if ownership ? {
		value = value.to_owned()
	}
	child := inset_renderable(StringRenderable.new(value), render.Insets.vh(1, 1))
	area := layout.Rect.new(0, 0, 12, 3)
	mut buf := buffer.Buffer.empty(area)
	child.render(area, mut buf)
	child.render(area, mut buf)
	assert child.desired_height(12) == 3
	assert buf.cells[13].symbol == 'h'
	span := SpanRenderable.new(text.span_styled('span', style.Style{}.cyan()))
	line := LineRenderable.new(text.line_from_spans([text.span_styled('line', style.Style{}.bold())]))
	paragraph := ParagraphRenderable.new(widgets.Paragraph.new('first\nsecond'))
	assert span.desired_height(0) == 1
	assert line.desired_height(0) == 1
	assert paragraph.desired_height(0) == 0
	assert paragraph.desired_height(1) == 2
	span.render(area, mut buf)
	line.render(area, mut buf)
	paragraph.render(area, mut buf)
	assert buf.cells[0].symbol == 'f'
	assert buf.cells[12].symbol == 's'
}

fn test_borrowed_heap_string_and_widget_adapters_leave_owners_reusable() {
	mut content := 'borrowed heap'
	mut span_content := 'span heap'
	mut line_content := 'line heap'
	mut paragraph_content := 'paragraph heap'
	$if ownership ? {
		content = content.to_owned()
		span_content = span_content.to_owned()
		line_content = line_content.to_owned()
		paragraph_content = paragraph_content.to_owned()
	}
	span_owner := text.span_styled(span_content, style.Style{}.cyan())
	line_owner := text.line_from(line_content)
	paragraph_owner := widgets.Paragraph.new(paragraph_content)
	string_view := BorrowedStringRenderable.new(&content)
	span_view := BorrowedSpanRenderable.new(&span_owner)
	line_view := BorrowedLineRenderable.new(&line_owner)
	paragraph_view := BorrowedParagraphRenderable.new(&paragraph_owner)
	area := layout.Rect.new(0, 0, 20, 2)
	mut buf := buffer.Buffer.empty(area)
	for _ in 0 .. 2 {
		string_view.render(area, mut buf)
		span_view.render(area, mut buf)
		line_view.render(area, mut buf)
		paragraph_view.render(area, mut buf)
		assert string_view.desired_height(20) == 1
		assert span_view.desired_height(20) == 1
		assert line_view.desired_height(20) == 1
		assert paragraph_view.desired_height(20) == 1
	}
	assert content == 'borrowed heap'
	assert span_owner.text == 'span heap'
	assert line_owner.spans[0].text == 'line heap'
	assert paragraph_owner.line_count(20) == 1
	paragraph_owner.render_ref(area, mut buf)
	assert buf.cells[0].symbol == 'p'
}

fn test_paragraph_adapter_uses_width_dependent_wrapped_line_count_and_style() {
	child := ParagraphRenderable.new(widgets.Paragraph.new('abc defghi').style(style.Style{}.cyan()).wrap(widgets.Wrap{ trim: false }))
	assert child.desired_height(10) == 1
	assert child.desired_height(6) == 2
	assert child.desired_height(3) == 3
	area := layout.Rect.new(0, 0, 3, 3)
	mut buf := buffer.Buffer.empty(area)
	child.render(area, mut buf)
	assert buf.cells.map(it.symbol).join('') == 'abcdefghi'
	assert buf.cells[0].style.fg? == style.Color{ kind: .cyan }
}

fn arc_from_owned_heap_text() ArcRenderable {
	mut text_owner := 'Arc constructor heap owner'
	$if ownership ? {
		text_owner = text_owner.to_owned()
	}
	return ArcRenderable.new(StringRenderable.new(text_owner))
}

fn test_arc_owned_payload_survives_constructor_return_and_stack_churn() {
	arc := arc_from_owned_heap_text()
	mut churn := []string{cap: 256}
	for i in 0 .. 256 {
		churn << 'constructor stack churn ${i}'
	}
	area := layout.Rect.new(0, 0, 26, 1)
	mut buf := buffer.Buffer.empty(area)
	arc.render(area, mut buf)
	arc.render(area, mut buf)
	assert arc.desired_height(26) == 1
	assert buf.cells.map(it.symbol).join('') == 'Arc constructor heap owner'
	assert churn[255] == 'constructor stack churn 255'
}

fn test_owned_children_transfer_heap_string_without_clone() {
	mut content := 'move the allocation'
	$if ownership ? {
		content = content.to_owned()
	} $else {
		content = content.clone()
	}
	allocation := unsafe { content.str }
	child := StringRenderable.new(content)
	assert unsafe { child.value.str == allocation }
	item := RenderableItem.owned(child)
	assert unsafe { owned_string_allocation(&item) == allocation }
	mut items := []RenderableItem{}
	items << item
	column := ColumnRenderable.with(items)
	area := layout.Rect.new(0, 0, 19, 1)
	mut buf := buffer.Buffer.empty(area)
	column.render(area, mut buf)
	column.render(area, mut buf)
	assert buf.cells.map(it.symbol).join('') == 'move the allocation'
}

fn owned_string_allocation(item &RenderableItem) &u8 {
	if item.owned_child is StringRenderable {
		return unsafe { item.owned_child.value.str }
	}
	return unsafe { nil }
}
