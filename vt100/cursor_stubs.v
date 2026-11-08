module vt100

import ratatui.layout
import ratatui.style
import unicode_segmentation
import unicode_width

// STUB: vt100::Cell's observed glyph, SGR attributes, and OSC 8 destination.
pub struct Cell {
mut:
	symbol     string
	cell_style style.Style
	hyperlink  string
}

// STUB: vt100::Cell::clone owns symbol/hyperlink strings at native row-copy boundaries.
pub fn (cell &Cell) clone() Cell {
	return Cell{ symbol: cell.symbol.clone(), cell_style: cell.cell_style, hyperlink: cell.hyperlink.clone() }
}

// STUB: vt100::Cell::bgcolor's typed native color boundary.
pub fn (cell &Cell) bgcolor() style.Color {
	return cell.cell_style.bg or { style.Color{} }
}

// STUB: vt100::Cell::bold preserves the native SGR bold flag.
pub fn (cell &Cell) bold() bool {
	return cell.cell_style.add_modifier.has(.bold)
}

// STUB: vt100 cell observation for old JediTerm corruption/repair tests.
pub fn (cell &Cell) contents() string {
	return cell.symbol.clone()
}

// STUB: OSC 8 metadata observation at the native parser fixture boundary.
pub fn (cell &Cell) hyperlink_destination() string {
	return cell.hyperlink.clone()
}

// STUB: vt100::Screen::cell's borrowed cell result; V uses !&Cell instead of Option<&Cell>.
pub fn (screen &Screen) cell(row u16, column u16) !&Cell {
	if int(row) >= screen.rows.len || column >= screen.columns {
		return error('cell outside screen')
	}
	return &screen.cells[int(row) * int(screen.columns) + int(column)]
}

// STUB: vt100::Parser::screen_mut preserves the source's mutable screen borrow.
pub fn (mut parser Parser) screen_mut() &Screen {
	return &parser.current
}

// STUB: vt100::Screen::scrollback reports the selected history-window offset.
pub fn (screen &Screen) scrollback() usize {
	return usize(screen.scrollback_offset)
}

// STUB: deterministic reproduction of JediTerm before 3.56 printing DECSCUSR's space.
pub fn (mut parser Parser) fixture_enable_jediterm_damage() {
	parser.current.jediterm_damage = true
}

// STUB: CSI clear and scrolling update the same native cell metadata as printable writes.
fn (mut parser Parser) fixture_clear_cells(row int, column int) {
	for col in column .. int(parser.current.columns) {
		parser.current.cells[row * int(parser.current.columns) + col] = Cell{}
	}
}

// STUB: native scrolling moves owned glyph/style/hyperlink metadata between fixture rows.
fn (mut parser Parser) fixture_copy_cells(source int, destination int) {
	for column in 0 .. int(parser.current.columns) {
		copied := parser.current.cells[source * int(parser.current.columns) + column].clone()
		parser.current.cells[destination * int(parser.current.columns) + column] = copied
	}
}

// STUB: vt100 OSC 8 opening/closing controls update the actual writer's active destination.
fn (mut parser Parser) fixture_osc(command &string) {
	if command.starts_with('8;;') {
		parser.current.active_hyperlink = (*command)[3..].clone()
	}
}

// STUB: vt100 SGR parsing for native foreground/background RGB/indexed colors and all modifiers.
fn (mut parser Parser) fixture_sgr(parts &[]string) {
	mut index := 0
	for index < parts.len {
		code := (*parts)[index].int()
		match code {
			0 { parser.current.active_style = style.Style{} }
			1 { parser.current.active_style = parser.current.active_style.add_modifier(.bold) }
			2 { parser.current.active_style = parser.current.active_style.add_modifier(.dim) }
			3 { parser.current.active_style = parser.current.active_style.add_modifier(.italic) }
			4 {
				parser.current.active_style = parser.current.active_style.add_modifier(.underlined)
			}
			5 {
				parser.current.active_style = parser.current.active_style.add_modifier(.slow_blink)
			}
			6 {
				parser.current.active_style = parser.current.active_style.add_modifier(.rapid_blink)
			}
			7 { parser.current.active_style = parser.current.active_style.add_modifier(.reversed) }
			9 {
				parser.current.active_style = parser.current.active_style.add_modifier(.crossed_out)
			}
			22 {
				parser.current.active_style.add_modifier.clear(.bold)
				parser.current.active_style.add_modifier.clear(.dim)
			}
			23 { parser.current.active_style.add_modifier.clear(.italic) }
			24 { parser.current.active_style.add_modifier.clear(.underlined) }
			25 {
				parser.current.active_style.add_modifier.clear(.slow_blink)
				parser.current.active_style.add_modifier.clear(.rapid_blink)
			}
			27 { parser.current.active_style.add_modifier.clear(.reversed) }
			29 { parser.current.active_style.add_modifier.clear(.crossed_out) }
			39 { parser.current.active_style.fg = none }
			49 { parser.current.active_style.bg = none }
			38, 48 {
				mut color := style.Color{}
				if index + 4 < parts.len && (*parts)[index + 1] == '2' {
					color = style.Color.rgb(u8((*parts)[index + 2].int()), u8((*parts)[index + 3].int()), u8((*parts)[index + 4].int()))
					index += 4
				} else if index + 2 < parts.len && (*parts)[index + 1] == '5' {
					color = style.Color.indexed(u8((*parts)[index + 2].int()))
					index += 2
				}
				if code == 38 {
					parser.current.active_style.fg = color
				} else {
					parser.current.active_style.bg = color
				}
			}
			else {}
		}
		index++
	}
}

// STUB: Unicode glyph writes preserve leaders/continuations and delayed wrapping.
// Printable runs are segmented by the translated grapheme owner before cell updates.
fn (mut parser Parser) fixture_print_text(value &string) {
	offsets := unicode_segmentation.grapheme_indices(value, true)
	for i, start in offsets {
		end := if i + 1 < offsets.len { offsets[i + 1] } else { value.len }
		symbol := (*value)[start..end]
		width := int(unicode_width.width(&symbol))
		if width <= 0 || width > int(parser.current.columns) || parser.current.rows.len == 0 {
			continue
		}
		if int(parser.current.cursor.x) + width > int(parser.current.columns) {
			parser.current.cursor = layout.Position{ ...parser.current.cursor, x: 0 }
			parser.fixture_line_feed()
		}
		row := int(parser.current.cursor.y)
		col := int(parser.current.cursor.x)
		index := row * int(parser.current.columns) + col
		// A write on a wide leader erases its continuation before replacing the glyph.
		previous_width := int(unicode_width.width(&parser.current.cells[index].symbol))
		for offset in 1 .. previous_width {
			if col + offset < int(parser.current.columns) {
				parser.current.cells[index + offset] = Cell{}
			}
		}
		parser.current.cells[index] = Cell{ symbol: symbol.clone(), cell_style: parser.current.active_style, hyperlink: parser.current.active_hyperlink.clone() }
		for offset in 1 .. width {
			parser.current.cells[index + offset] = Cell{ cell_style: parser.current.active_style, hyperlink: parser.current.active_hyperlink.clone() }
		}
		mut last := int(parser.current.columns)
		for last > 0 {
			cell := &parser.current.cells[row * int(parser.current.columns) + last - 1]
			if cell.symbol.len > 0 || cell.cell_style.bg != none {
				break
			}
			last--
		}
		mut rendered := ''
		mut column := 0
		for column < last {
			cell := &parser.current.cells[row * int(parser.current.columns) + column]
			if cell.symbol.len == 0 {
				rendered += ' '
				column++
			} else {
				rendered += cell.symbol
				cell_width := int(unicode_width.width(&cell.symbol))
				column += if cell_width > 0 { cell_width } else { 1 }
			}
		}
		parser.current.rows[row] = rendered
		parser.current.cursor = layout.Position{ ...parser.current.cursor, x: u16(col + width) }
	}
}
