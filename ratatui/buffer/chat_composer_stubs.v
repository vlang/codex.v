module buffer

import ratatui.layout
import ratatui.style

// STUB: ratatui::buffer::Cell fields needed by the composer renderer. The eventual ratatui port
// owns grapheme-width handling and terminal-cell normalization.
pub struct Cell {
pub mut:
	x         u16
	y         u16
	symbol    string
	style     style.Style
	hyperlink ?string
	// STUB: ratatui::buffer::Cell's native diff policy, shared with cursor repair.
	diff_option CellDiffOption
}

// STUB: logical region metadata retained by the target-specific buffer until widgets are ported.
pub struct Region {
pub:
	name string
	rect layout.Rect
}

// STUB: ratatui::buffer::Buffer. Rendering storage is completed by the future ratatui port.
pub struct Buffer {
pub mut:
	area    layout.Rect
	lines   []string
	cells   []Cell
	regions []Region
}

// STUB: ratatui::buffer::Buffer area-scoped replacement. Rendering one widget must preserve cells
// owned by the rest of the terminal frame.
pub fn (mut buf Buffer) clear_area(rect layout.Rect) {
	buf.cells = buf.cells.filter(it.x < rect.x || it.x >= rect.x + rect.width || it.y < rect.y
		|| it.y >= rect.y + rect.height)
	buf.regions = buf.regions.filter(it.rect.x < rect.x || it.rect.x >= rect.x + rect.width
		|| it.rect.y < rect.y || it.rect.y >= rect.y + rect.height)
}

// STUB: ratatui::buffer::Buffer cell write. The real buffer resolves Unicode display widths.
pub fn (mut buf Buffer) put_cell(x u16, y u16, symbol string, cell_style style.Style) {
	for mut cell in buf.cells {
		if cell.x == x && cell.y == y {
			cell.symbol = symbol
			mut merged := cell_style
			if merged.bg == none {
				merged.bg = cell.style.bg
			}
			cell.style = merged
			return
		}
	}
	buf.cells << Cell{ x: x, y: y, symbol: symbol, style: cell_style }
}

// STUB: ratatui::widgets::Block::style(...).render(...) style application boundary.
pub fn (mut buf Buffer) set_style(rect layout.Rect, cell_style style.Style) {
	for y in rect.y .. rect.y + rect.height {
		for x in rect.x .. rect.x + rect.width {
			mut found := false
			for mut cell in buf.cells {
				if cell.x == x && cell.y == y {
					cell.style = cell_style
					found = true
					break
				}
			}
			if !found {
				buf.cells << Cell{ x: x, y: y, symbol: ' ', style: cell_style }
			}
		}
	}
}

// STUB: ratatui buffer hyperlink metadata. OSC-8 emission belongs to the terminal backend.
pub fn (mut buf Buffer) mark_hyperlink(rect layout.Rect, url string) {
	for mut cell in buf.cells {
		if cell.x >= rect.x && cell.x < rect.x + rect.width && cell.y >= rect.y
			&& cell.y < rect.y + rect.height && cell.symbol.trim_space().len > 0 {
			cell.hyperlink = url.clone()
			cell.style = cell.style.add_modifier(.underlined)
		}
	}
}
