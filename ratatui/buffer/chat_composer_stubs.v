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
	lines   []string
	cells   []Cell
	regions []Region
}

// STUB: ratatui::buffer::Buffer area-scoped replacement. Rendering one widget must preserve cells
// owned by the rest of the terminal frame.
pub fn (mut buffer Buffer) clear_area(rect layout.Rect) {
	buffer.cells = buffer.cells.filter(it.x < rect.x || it.x >= rect.x + rect.width || it.y < rect.y
		|| it.y >= rect.y + rect.height)
	buffer.regions = buffer.regions.filter(it.rect.x < rect.x || it.rect.x >= rect.x + rect.width
		|| it.rect.y < rect.y || it.rect.y >= rect.y + rect.height)
}

// STUB: ratatui::buffer::Buffer cell write. The real buffer resolves Unicode display widths.
pub fn (mut buffer Buffer) put_cell(x u16, y u16, symbol string, cell_style style.Style) {
	for mut cell in buffer.cells {
		if cell.x == x && cell.y == y {
			cell.symbol = symbol
			mut merged := cell_style
			if merged.background == none {
				merged.background = cell.style.background
			}
			cell.style = merged
			return
		}
	}
	buffer.cells << Cell{ x: x, y: y, symbol: symbol, style: cell_style }
}

// STUB: ratatui::widgets::Block::style(...).render(...) style application boundary.
pub fn (mut buffer Buffer) set_style(rect layout.Rect, cell_style style.Style) {
	for y in rect.y .. rect.y + rect.height {
		for x in rect.x .. rect.x + rect.width {
			mut found := false
			for mut cell in buffer.cells {
				if cell.x == x && cell.y == y {
					cell.style = cell_style
					found = true
					break
				}
			}
			if !found {
				buffer.cells << Cell{ x: x, y: y, symbol: ' ', style: cell_style }
			}
		}
	}
}

// STUB: ratatui buffer hyperlink metadata. OSC-8 emission belongs to the terminal backend.
pub fn (mut buffer Buffer) mark_hyperlink(rect layout.Rect, url string) {
	for mut cell in buffer.cells {
		if cell.x >= rect.x && cell.x < rect.x + rect.width && cell.y >= rect.y
			&& cell.y < rect.y + rect.height && cell.symbol.trim_space().len > 0 {
			cell.hyperlink = url.clone()
			cell.style.underlined = true
		}
	}
}
