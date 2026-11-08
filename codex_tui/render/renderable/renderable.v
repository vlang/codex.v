module renderable

import math
import crossterm.cursor
import ratatui.buffer
import ratatui.layout
import ratatui.text
import ratatui.widgets
import codex_tui.render

// V's interfaces have no overridable default methods. Keep the two required methods in
// Renderable and dispatch the three optional methods through structural capability interfaces.
pub interface Renderable {
	render(area layout.Rect, mut buf buffer.Buffer)
	desired_height(width u16) u16
}

interface ScrolledRenderable {
	render(area layout.Rect, mut buf buffer.Buffer)
	desired_height(width u16) u16
	render_scrolled(area layout.Rect, mut buf buffer.Buffer, scroll_offset u16) bool
}

interface CursorRenderable {
	render(area layout.Rect, mut buf buffer.Buffer)
	desired_height(width u16) u16
	cursor_pos(area layout.Rect) ?CursorPosition
}

interface CursorStyledRenderable {
	render(area layout.Rect, mut buf buffer.Buffer)
	desired_height(width u16) u16
	cursor_style(area layout.Rect) cursor.CursorStyle
}

// The Rust (u16, u16) cursor tuple is an allocation-free V value.
pub struct CursorPosition {
pub:
	x u16
	y u16
}

// Renders visible rows after scroll_offset when direct scrolling is supported.
//
// Implementations returning false must leave buf unchanged so callers can use their
// existing full-height rendering fallback. Supporting wrappers must forward this method.
pub fn (child &Renderable) render_scrolled(area layout.Rect, mut buf buffer.Buffer, scroll_offset u16) bool {
	if child is ScrolledRenderable {
		capability := ScrolledRenderable(child)
		return capability.render_scrolled(area, mut buf, scroll_offset)
	}
	return false
}

pub fn (child &Renderable) cursor_pos(area layout.Rect) ?CursorPosition {
	if child is CursorRenderable {
		capability := CursorRenderable(child)
		return capability.cursor_pos(area)
	}
	return none
}

pub fn (child &Renderable) cursor_style(area layout.Rect) cursor.CursorStyle {
	if child is CursorStyledRenderable {
		capability := CursorStyledRenderable(child)
		return capability.cursor_style(area)
	}
	return .default_user_shape
}

pub enum RenderableItemKind {
	owned
	borrowed
}

// The explicit tag preserves Rust's Owned(Box<dyn Renderable>)/Borrowed(&dyn Renderable).
// Owned construction consumes its interface value; borrowed construction retains the owner.
// V does not express Rust lifetime bounds, so a borrowed child's owner must outlive the item.
pub struct RenderableItem {
	kind           RenderableItemKind
	owned_child    Renderable  = UnitRenderable{}
	borrowed_child &Renderable = unsafe { nil }
}

pub fn (item &RenderableItem) render(area layout.Rect, mut buf buffer.Buffer) {
	match item.kind {
		.owned { item.owned_child.render(area, mut buf) }
		.borrowed { item.borrowed_child.render(area, mut buf) }
	}
}

pub fn (item &RenderableItem) desired_height(width u16) u16 {
	return match item.kind {
		.owned { item.owned_child.desired_height(width) }
		.borrowed { item.borrowed_child.desired_height(width) }
	}
}

pub fn (item &RenderableItem) render_scrolled(area layout.Rect, mut buf buffer.Buffer, scroll_offset u16) bool {
	return match item.kind {
		.owned { item.owned_child.render_scrolled(area, mut buf, scroll_offset) }
		.borrowed { item.borrowed_child.render_scrolled(area, mut buf, scroll_offset) }
	}
}

pub fn (item &RenderableItem) cursor_pos(area layout.Rect) ?CursorPosition {
	match item.kind {
		.owned { return item.owned_child.cursor_pos(area) }
		.borrowed { return item.borrowed_child.cursor_pos(area) }
	}
}

pub fn (item &RenderableItem) cursor_style(area layout.Rect) cursor.CursorStyle {
	return match item.kind {
		.owned { item.owned_child.cursor_style(area) }
		.borrowed { item.borrowed_child.cursor_style(area) }
	}
}

// Rust's From<Box<dyn Renderable>> and blanket From<R> for Box<dyn Renderable>
// become one consuming interface constructor: V boxes structural interface values itself.
pub fn RenderableItem.owned(child Renderable) RenderableItem {
	return RenderableItem{ kind: .owned, owned_child: child }
}

pub fn RenderableItem.borrowed(child &Renderable) RenderableItem {
	return RenderableItem{ kind: .borrowed, borrowed_child: child }
}

pub struct UnitRenderable {}

pub fn (child &UnitRenderable) render(_area layout.Rect, mut _buf buffer.Buffer) {}

pub fn (child &UnitRenderable) desired_height(_width u16) u16 {
	return 0
}

// V forbids adding Renderable methods to builtin strings or foreign widget types, so
// explicit adapters implement the Rust trait implementations without changing their owners.
pub struct BorrowedStringRenderable {
	value &string
}

pub fn BorrowedStringRenderable.new(value &string) BorrowedStringRenderable {
	return BorrowedStringRenderable{ value: value }
}

pub fn (child &BorrowedStringRenderable) render(area layout.Rect, mut buf buffer.Buffer) {
	widgets.render_string_ref(child.value, area, mut buf)
}

pub fn (child &BorrowedStringRenderable) desired_height(_width u16) u16 {
	return 1
}

pub struct StringRenderable {
	value string
}

pub fn StringRenderable.new(value string) StringRenderable {
	return StringRenderable{ value: value }
}

pub fn (child &StringRenderable) render(area layout.Rect, mut buf buffer.Buffer) {
	widgets.render_string_ref(&child.value, area, mut buf)
}

pub fn (child &StringRenderable) desired_height(_width u16) u16 {
	return 1
}

pub struct SpanRenderable {
	span text.Span
}

pub fn SpanRenderable.new(span text.Span) SpanRenderable {
	return SpanRenderable{ span: span }
}

pub fn (child &SpanRenderable) render(area layout.Rect, mut buf buffer.Buffer) {
	child.span.render_ref(area, mut buf)
}

pub fn (child &SpanRenderable) desired_height(_width u16) u16 {
	return 1
}

pub struct BorrowedSpanRenderable {
	span &text.Span
}

// V cannot prove the Rust lifetime bound for a returned struct reference. This narrow
// pointer escape preserves borrowing; the documented item lifetime also applies to this view.
pub fn BorrowedSpanRenderable.new(span &text.Span) BorrowedSpanRenderable {
	return BorrowedSpanRenderable{ span: unsafe { span } }
}

pub fn (child &BorrowedSpanRenderable) render(area layout.Rect, mut buf buffer.Buffer) {
	child.span.render_ref(area, mut buf)
}

pub fn (child &BorrowedSpanRenderable) desired_height(_width u16) u16 {
	return 1
}

pub struct LineRenderable {
	line text.Line
}

pub fn LineRenderable.new(line text.Line) LineRenderable {
	return LineRenderable{ line: line }
}

pub fn (child &LineRenderable) render(area layout.Rect, mut buf buffer.Buffer) {
	widgets.render(&child.line, area, mut buf)
}

pub fn (child &LineRenderable) desired_height(_width u16) u16 {
	return 1
}

pub struct BorrowedLineRenderable {
	line &text.Line
}

// V cannot prove the Rust lifetime bound for a returned struct reference. This narrow
// pointer escape preserves borrowing; the documented item lifetime also applies to this view.
pub fn BorrowedLineRenderable.new(line &text.Line) BorrowedLineRenderable {
	return BorrowedLineRenderable{ line: unsafe { line } }
}

pub fn (child &BorrowedLineRenderable) render(area layout.Rect, mut buf buffer.Buffer) {
	widgets.render(child.line, area, mut buf)
}

pub fn (child &BorrowedLineRenderable) desired_height(_width u16) u16 {
	return 1
}

pub struct ParagraphRenderable {
	paragraph widgets.Paragraph
}

pub fn ParagraphRenderable.new(paragraph widgets.Paragraph) ParagraphRenderable {
	return ParagraphRenderable{ paragraph: paragraph }
}

pub fn (child &ParagraphRenderable) render(area layout.Rect, mut buf buffer.Buffer) {
	child.paragraph.render_ref(area, mut buf)
}

pub fn (child &ParagraphRenderable) desired_height(width u16) u16 {
	return u16(child.paragraph.line_count(width))
}

pub struct BorrowedParagraphRenderable {
	paragraph &widgets.Paragraph
}

// V cannot prove the Rust lifetime bound for a returned struct reference. This narrow
// pointer escape preserves borrowing; the documented item lifetime also applies to this view.
pub fn BorrowedParagraphRenderable.new(paragraph &widgets.Paragraph) BorrowedParagraphRenderable {
	return BorrowedParagraphRenderable{ paragraph: unsafe { paragraph } }
}

pub fn (child &BorrowedParagraphRenderable) render(area layout.Rect, mut buf buffer.Buffer) {
	child.paragraph.render_ref(area, mut buf)
}

pub fn (child &BorrowedParagraphRenderable) desired_height(width u16) u16 {
	return u16(child.paragraph.line_count(width))
}

// Avoid &?Renderable and ?&Renderable, which V cannot reliably generate. The explicit
// presence tag preserves Option<R> and never moves its owning child during a shared call.
pub struct OptionRenderable {
	present bool
	child   RenderableItem
}

pub fn OptionRenderable.some(child RenderableItem) OptionRenderable {
	return OptionRenderable{ present: true, child: child }
}

pub fn OptionRenderable.none() OptionRenderable {
	return OptionRenderable{}
}

pub fn (child &OptionRenderable) render(area layout.Rect, mut buf buffer.Buffer) {
	if child.present {
		child.child.render(area, mut buf)
	}
}

pub fn (child &OptionRenderable) desired_height(width u16) u16 {
	return if child.present { child.child.desired_height(width) } else { 0 }
}

pub fn (child &OptionRenderable) cursor_pos(area layout.Rect) ?CursorPosition {
	if child.present {
		return child.child.cursor_pos(area)
	}
	return none
}

pub fn (child &OptionRenderable) cursor_style(area layout.Rect) cursor.CursorStyle {
	return if child.present { child.child.cursor_style(area) } else { .default_user_shape }
}

// Rust Arc's shared object is a GC-managed boxed interface payload in V. Keeping the
// interface handle by value retains that payload without borrowing a constructor-local
// interface slot. Construction consumes the handle; shared render calls borrow it. The source Arc adapter deliberately
// retains Renderable's false render_scrolled default, as does OptionRenderable above.
pub struct ArcRenderable {
	child Renderable
}

pub fn ArcRenderable.new(child Renderable) ArcRenderable {
	return ArcRenderable{ child: child }
}

pub fn (child &ArcRenderable) render(area layout.Rect, mut buf buffer.Buffer) {
	child.child.render(area, mut buf)
}

pub fn (child &ArcRenderable) desired_height(width u16) u16 {
	return child.child.desired_height(width)
}

pub fn (child &ArcRenderable) cursor_pos(area layout.Rect) ?CursorPosition {
	return child.child.cursor_pos(area)
}

pub fn (child &ArcRenderable) cursor_style(area layout.Rect) cursor.CursorStyle {
	return child.child.cursor_style(area)
}

pub struct ColumnRenderable {
mut:
	children []RenderableItem
}

pub fn (column &ColumnRenderable) render(area layout.Rect, mut buf buffer.Buffer) {
	mut y := area.y
	for i in 0 .. column.children.len {
		child := &column.children[i]
		if y >= area.bottom() {
			break
		}
		child_area := layout.Rect.new(area.x, y, area.width, child.desired_height(area.width)).intersection(area)
		if !child_area.is_empty() {
			child.render(child_area, mut buf)
		}
		y += child_area.height
	}
}

pub fn (column &ColumnRenderable) desired_height(width u16) u16 {
	mut height := u16(0)
	for i in 0 .. column.children.len {
		child := &column.children[i]
		height += child.desired_height(width)
	}
	return height
}

// Returns the cursor position of the first child that has a cursor position, offset by the
// child's position in the column.
//
// It is generally assumed that either zero or one child will have a cursor position.
pub fn (column &ColumnRenderable) cursor_pos(area layout.Rect) ?CursorPosition {
	mut y := area.y
	for i in 0 .. column.children.len {
		child := &column.children[i]
		child_area := layout.Rect.new(area.x, y, area.width, child.desired_height(area.width)).intersection(area)
		if !child_area.is_empty() {
			if position := child.cursor_pos(child_area) {
				return position
			}
		}
		y += child_area.height
	}
	return none
}

pub fn (column &ColumnRenderable) cursor_style(area layout.Rect) cursor.CursorStyle {
	mut y := area.y
	for i in 0 .. column.children.len {
		child := &column.children[i]
		child_area := layout.Rect.new(area.x, y, area.width, child.desired_height(area.width)).intersection(area)
		if !child_area.is_empty() {
			if _ := child.cursor_pos(child_area) {
				return child.cursor_style(child_area)
			}
		}
		y += child_area.height
	}
	return .default_user_shape
}

pub fn ColumnRenderable.new() ColumnRenderable {
	return ColumnRenderable{}
}

pub fn ColumnRenderable.with(children []RenderableItem) ColumnRenderable {
	return ColumnRenderable{ children: children }
}

pub fn (mut column ColumnRenderable) push(child Renderable) {
	column.children << RenderableItem.owned(child)
}

// Rust Cell<Option<(u16, u16)>> is represented by a private scalar-only heap cell.
// Its sole mutation uses the same single-threaded interior-mutability boundary as Cell.
struct CachedHeight {
mut:
	present bool
	width   u16
	height  u16
}

fn (cache &CachedHeight) set(width u16, height u16) {
	unsafe {
		mut mutable_cache := cache
		mutable_cache.present = true
		mutable_cache.width = width
		mutable_cache.height = height
	}
}

pub struct FlexChild {
	flex          i32
	child         RenderableItem
	cached_height &CachedHeight
}

pub struct FlexRenderable {
mut:
	children []FlexChild
}

// Lays out children in a column, with the ability to specify a flex factor for each child.
//
// Children with flex factor > 0 will be allocated the remaining space after the non-flex children,
// proportional to the flex factor.
pub fn FlexRenderable.new() FlexRenderable {
	return FlexRenderable{}
}

pub fn (mut flex FlexRenderable) push(factor i32, child RenderableItem) {
	flex.children << FlexChild{ flex: factor, child: child, cached_height: &CachedHeight{} }
}

struct PendingFlexChild {
	index          int
	flex           u16
	desired_height u16
}

// Loosely inspired by Flutter's Flex widget.
//
// Ref https://github.com/flutter/flutter/blob/3fd81edbf1e015221e143c92b2664f4371bdc04a/packages/flutter/lib/src/rendering/flex.dart#L1205-L1209
fn (flex &FlexRenderable) allocate(area layout.Rect) []layout.Rect {
	mut allocated_rects := []layout.Rect{cap: flex.children.len}
	mut child_sizes := []u16{len: flex.children.len}
	mut allocated_size := u16(0)
	mut flex_children := []PendingFlexChild{}

	// 1. Allocate space to non-flex children.
	max_size := area.height
	for i in 0 .. flex.children.len {
		child := &flex.children[i]
		desired_height := if child.cached_height.present && child.cached_height.width == area.width {
			child.cached_height.height
		} else {
			height := child.child.desired_height(area.width)
			child.cached_height.set(area.width, height)
			height
		}
		if child.flex > 0 {
			flex_children << PendingFlexChild{i, u16(child.flex), desired_height}
		} else {
			child_sizes[i] = math.min(desired_height, saturating_sub(max_size, allocated_size))
			allocated_size += child_sizes[i]
		}
	}
	free_space := saturating_sub(max_size, allocated_size)
	// 2. Satisfy flex children that need less than their proportional share so their unused
	// space can be redistributed instead of leaving blank rows.
	mut remaining_space := free_space
	for flex_children.len > 0 {
		mut total_flex := u16(0)
		for child in flex_children {
			total_flex += child.flex
		}
		mut satisfied_any := false
		mut retained := []PendingFlexChild{cap: flex_children.len}
		for child in flex_children {
			proportional_share := u16(u32(remaining_space) * u32(child.flex) / u32(total_flex))
			if child.desired_height <= proportional_share {
				child_sizes[child.index] = child.desired_height
				remaining_space = saturating_sub(remaining_space, child.desired_height)
				satisfied_any = true
			} else {
				retained << child
			}
		}
		// Transfer the newly retained vector; V requires unsafe for this allocation move.
		flex_children = unsafe { retained }
		if !satisfied_any {
			break
		}
	}
	// 3. Divide the remaining space proportionally. The final child absorbs rounding slack.
	mut total_flex := u16(0)
	for child in flex_children {
		total_flex += child.flex
	}
	mut allocated_flex_space := u16(0)
	last_flex_child_idx := if flex_children.len > 0 { flex_children.last().index } else { -1 }
	for child in flex_children {
		max_child_extent := if child.index == last_flex_child_idx {
			saturating_sub(remaining_space, allocated_flex_space)
		} else {
			u16(u32(remaining_space) * u32(child.flex) / u32(total_flex))
		}
		child_size := math.min(child.desired_height, max_child_extent)
		child_sizes[child.index] = child_size
		allocated_flex_space += child_size
	}

	mut y := area.y
	for size in child_sizes {
		child_area := layout.Rect.new(area.x, y, area.width, size)
		allocated_rects << child_area
		y += child_area.height
	}
	return allocated_rects
}

pub fn (flex &FlexRenderable) render(area layout.Rect, mut buf buffer.Buffer) {
	rects := flex.allocate(area)
	for i, rect in rects {
		flex.children[i].child.render(rect, mut buf)
	}
}

pub fn (flex &FlexRenderable) desired_height(width u16) u16 {
	rects := flex.allocate(layout.Rect.new(0, 0, width, 65535))
	return if rects.len > 0 { rects.last().bottom() } else { 0 }
}

pub fn (flex &FlexRenderable) cursor_pos(area layout.Rect) ?CursorPosition {
	rects := flex.allocate(area)
	for i, rect in rects {
		if position := flex.children[i].child.cursor_pos(rect) {
			return position
		}
	}
	return none
}

pub fn (flex &FlexRenderable) cursor_style(area layout.Rect) cursor.CursorStyle {
	rects := flex.allocate(area)
	for i, rect in rects {
		if _ := flex.children[i].child.cursor_pos(rect) {
			return flex.children[i].child.cursor_style(rect)
		}
	}
	return .default_user_shape
}

struct RowChild {
	width u16
	child RenderableItem
}

pub struct RowRenderable {
mut:
	children []RowChild
}

pub fn (row &RowRenderable) render(area layout.Rect, mut buf buffer.Buffer) {
	mut x := area.x
	for i in 0 .. row.children.len {
		child := &row.children[i]
		available_width := saturating_sub(area.width, x - area.x)
		child_area := layout.Rect.new(x, area.y, math.min(child.width, available_width), area.height)
		if child_area.is_empty() {
			break
		}
		child.child.render(child_area, mut buf)
		x = saturating_add(x, child.width)
	}
}

pub fn (row &RowRenderable) desired_height(width u16) u16 {
	mut max_height := u16(0)
	mut width_remaining := width
	for i in 0 .. row.children.len {
		child := &row.children[i]
		w := math.min(child.width, width_remaining)
		if w == 0 {
			break
		}
		height := child.child.desired_height(w)
		if height > max_height {
			max_height = height
		}
		width_remaining = saturating_sub(width_remaining, w)
	}
	return max_height
}

pub fn (row &RowRenderable) cursor_pos(area layout.Rect) ?CursorPosition {
	mut x := area.x
	for i in 0 .. row.children.len {
		child := &row.children[i]
		available_width := saturating_sub(area.width, x - area.x)
		child_area := layout.Rect.new(x, area.y, math.min(child.width, available_width), area.height)
		if !child_area.is_empty() {
			if position := child.child.cursor_pos(child_area) {
				return position
			}
		}
		x = saturating_add(x, child.width)
	}
	return none
}

pub fn (row &RowRenderable) cursor_style(area layout.Rect) cursor.CursorStyle {
	mut x := area.x
	for i in 0 .. row.children.len {
		child := &row.children[i]
		available_width := saturating_sub(area.width, x - area.x)
		child_area := layout.Rect.new(x, area.y, math.min(child.width, available_width), area.height)
		if !child_area.is_empty() {
			if _ := child.child.cursor_pos(child_area) {
				return child.child.cursor_style(child_area)
			}
		}
		x = saturating_add(x, child.width)
	}
	return .default_user_shape
}

pub fn RowRenderable.new() RowRenderable {
	return RowRenderable{}
}

pub fn (mut row RowRenderable) push(width u16, child Renderable) {
	row.children << RowChild{ width: width, child: RenderableItem.owned(child) }
}

pub struct InsetRenderable {
	child  RenderableItem
	insets render.Insets
}

pub fn (inset &InsetRenderable) render(area layout.Rect, mut buf buffer.Buffer) {
	inset.child.render(render.inset(&area, inset.insets), mut buf)
}

pub fn (inset &InsetRenderable) desired_height(width u16) u16 {
	return inset.child.desired_height(width - inset.insets.left - inset.insets.right) + inset.insets.top + inset.insets.bottom
}

// Preserve clipped inset padding while forwarding only visible child rows.
pub fn (inset &InsetRenderable) render_scrolled(area layout.Rect, mut buf buffer.Buffer, scroll_offset u16) bool {
	top_padding := saturating_sub(inset.insets.top, scroll_offset)
	child_width := saturating_sub(area.width, saturating_add(inset.insets.left, inset.insets.right))
	if child_width == 0 || top_padding >= area.height {
		return true
	}

	child_offset := saturating_sub(scroll_offset, inset.insets.top)
	// The fallback applies bottom padding to its clipped scratch buffer, even mid-scroll.
	child_height := math.min(saturating_sub(inset.child.desired_height(child_width), child_offset),
		saturating_sub(saturating_sub(area.height, top_padding), inset.insets.bottom))
	if child_height == 0 {
		return true
	}

	child_area := layout.Rect.new(saturating_add(area.x, inset.insets.left),
		saturating_add(area.y, top_padding), child_width, child_height)
	if child_offset == 0 {
		inset.child.render(child_area, mut buf)
		return true
	}
	return inset.child.render_scrolled(child_area, mut buf, child_offset)
}

pub fn (inset &InsetRenderable) cursor_pos(area layout.Rect) ?CursorPosition {
	return inset.child.cursor_pos(render.inset(&area, inset.insets))
}

pub fn (inset &InsetRenderable) cursor_style(area layout.Rect) cursor.CursorStyle {
	return inset.child.cursor_style(render.inset(&area, inset.insets))
}

pub fn InsetRenderable.new(child RenderableItem, insets render.Insets) InsetRenderable {
	return InsetRenderable{ child: child, insets: insets }
}

// Rust's consuming RenderableExt::inset blanket method is a consuming V function,
// since V cannot add a generic method to every foreign Renderable implementation.
pub fn inset_renderable(child Renderable, insets render.Insets) RenderableItem {
	return RenderableItem.owned(InsetRenderable.new(RenderableItem.owned(child), insets))
}

fn saturating_sub(value u16, amount u16) u16 {
	return if amount > value { 0 } else { value - amount }
}

fn saturating_add(value u16, amount u16) u16 {
	return u16(math.min(u32(value) + u32(amount), u32(65535)))
}
