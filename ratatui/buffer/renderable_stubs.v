module buffer

import math
import ratatui.layout
import ratatui.style
import unicode_segmentation
import unicode_width

// STUB: ratatui::buffer::Buffer::empty initializes every cell in its logical rectangle.
pub fn Buffer.empty(area layout.Rect) Buffer {
	mut cells := []Cell{cap: int(area.width) * int(area.height)}
	for y in area.y .. area.bottom() {
		for x in area.x .. area.right() {
			cells << Cell{ x: x, y: y, symbol: ' ' }
		}
	}
	return Buffer{ area: area, cells: cells }
}

// STUB: ratatui::buffer::Buffer::set_stringn shared text input. Unicode grapheme
// segmentation and widths reuse their translated owners; symbol storage owns copied text.
pub fn (mut buf Buffer) set_stringn(x u16, y u16, value &string, max_width usize, cell_style style.Style) (u16, u16) {
	if y < buf.area.y || y >= buf.area.bottom() || x < buf.area.x || x >= buf.area.right() {
		return x, y
	}
	mut current_x := x
	mut remaining := math.min(max_width, usize(buf.area.right() - x))
	offsets := unicode_segmentation.grapheme_indices(value, true)
	for i, start in offsets {
		end := if i + 1 < offsets.len { offsets[i + 1] } else { value.len }
		symbol := (*value)[start..end]
		if symbol.runes().any(it < 0x20 || (it >= 0x7f && it < 0xa0)) {
			continue
		}
		width := unicode_width.width(&symbol)
		if width == 0 {
			continue
		}
		if width > remaining {
			break
		}
		buf.put_cell(current_x, y, symbol.clone(), cell_style)
		for offset in 1 .. int(width) {
			buf.put_cell(current_x + u16(offset), y, ' ', cell_style)
		}
		current_x += u16(width)
		remaining -= width
	}
	return current_x, y
}
