module buffer

import ratatui.layout
import ratatui.style
import unicode_width

// STUB: ratatui::buffer::CellDiffOption's payload variants require a tagged V value.
pub enum CellDiffOptionKind {
	none
	skip
	always_update
	forced_width
}

// STUB: ForcedWidth carries the source NonZeroU16, validated by forced_width().
pub struct CellDiffOption {
pub:
	kind  CellDiffOptionKind
	width u16
}

// STUB: ratatui::buffer::CellDiffOption::ForcedWidth's nonzero payload boundary.
pub fn CellDiffOption.forced_width(width u16) !CellDiffOption {
	if width == 0 {
		return error('cell width must be nonzero')
	}
	return CellDiffOption{ kind: .forced_width, width: width }
}

// STUB: ratatui::buffer::CellWidth preserves forced-width symbols (including OSC 8).
pub fn (cell &Cell) cell_width() u16 {
	if cell.diff_option.kind == .forced_width {
		return cell.diff_option.width
	}
	return u16(unicode_width.width(&cell.symbol))
}

// STUB: ratatui::buffer::Cell::clone owns the symbol and hyperlink at Rust's clone boundary.
pub fn (cell &Cell) clone() Cell {
	mut result := Cell{ ...cell, symbol: cell.symbol.clone(), hyperlink: none }
	if url := cell.hyperlink {
		result.hyperlink = url.clone()
	}
	return result
}

// STUB: ratatui::buffer::Cell::set_symbol borrows its text and stores an owned copy.
pub fn (mut cell Cell) set_symbol(symbol &string) {
	cell.symbol = symbol.clone()
}

// STUB: ratatui::buffer::Buffer::pos_of's row-major coordinate mapping.
pub fn (buf &Buffer) pos_of(index int) (u16, u16) {
	return buf.area.x + u16(index % int(buf.area.width)), buf.area.y + u16(index / int(buf.area.width))
}

// STUB: ratatui::buffer::Buffer::cell_mut returns the existing canonical cell storage.
pub fn (mut buf Buffer) cell_mut(position layout.Position) !&Cell {
	for i in 0 .. buf.cells.len {
		if buf.cells[i].x == position.x && buf.cells[i].y == position.y {
			return &buf.cells[i]
		}
	}
	return error('cell outside buffer')
}

// STUB: ratatui::buffer::Buffer::set_string's borrowed text and allocation-free Style.
pub fn (mut buf Buffer) set_string(x u16, y u16, value &string, cell_style style.Style) (u16, u16) {
	return buf.set_stringn(x, y, value, usize(65535), cell_style)
}
