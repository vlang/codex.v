module vt100

import ratatui.layout

// STUB: Screen::clone copies each owned screen and scrollback row explicitly.
pub fn (screen &Screen) clone() Screen {
	mut cells := []Cell{cap: screen.cells.len}
	for i in 0 .. screen.cells.len {
		cells << screen.cells[i].clone()
	}
	return Screen{ ...screen, rows: screen.rows.clone(), cells: cells, scrollback: screen.scrollback.clone() }
}

// STUB: Screen::set_scrollback selects the source-style history window, clamped to saved rows.
pub fn (mut screen Screen) set_scrollback(rows usize) {
	screen.scrollback_offset = int(if rows < usize(screen.scrollback.len) {
		rows
	} else {
		usize(screen.scrollback.len)
	})
}

// STUB: Screen::cursor_position is Copy-equivalent fixture cursor geometry.
pub fn (screen &Screen) cursor_position() layout.Position {
	return screen.cursor
}

// STUB: Parser::process interprets the ANSI subset used by history insertion and
// scrollback: CUP, ED, EL, DECSTBM, RI, LF/CR, and cursor save/restore, plus SGR/OSC 8
// and DECSCUSR damage needed by cursor repair. Other VT100 controls remain untranslated.
pub fn (mut parser Parser) process(data &[]u8) {
	mut index := 0
	for index < data.len {
		byte := data[index]
		if byte == 27 && index + 1 < data.len {
			next := data[index + 1]
			if next == `[` {
				start := index + 2
				mut end := start
				for end < data.len && !(data[end] >= 0x40 && data[end] <= 0x7e) {
					end++
				}
				if end >= data.len {
					break
				}
				mut params := ''
				for cursor in start .. end {
					params += data[cursor].ascii_str()
				}
				parser.fixture_csi(&params, data[end])
				index = end + 1
				continue
			} else if next == `]` {
				mut end := index + 2
				for end < data.len && data[end] != 7 {
					end++
				}
				if end >= data.len {
					break
				}
				command := (*data)[index + 2..end].bytestr()
				parser.fixture_osc(&command)
				index = end + 1
				continue
			} else if next == `M` {
				parser.fixture_reverse_index()
			} else if next == `7` {
				parser.current.saved_cursor = parser.current.cursor
			} else if next == `8` {
				parser.current.cursor = parser.current.saved_cursor
			}
			index += 2
			continue
		}
		match byte {
			`\r` { parser.current.cursor = layout.Position{ ...parser.current.cursor, x: 0 } }
			`\n` { parser.fixture_line_feed() }
			else {
				if byte >= 0x20 {
					mut end := index + 1
					for end < data.len && data[end] >= 0x20 && data[end] != 27 {
						end++
					}
					value := (*data)[index..end].bytestr()
					parser.fixture_print_text(&value)
					index = end
					continue
				}
			}
		}
		index++
	}
}

// STUB: ANSI CSI dispatch at the external parser fixture boundary.
fn (mut parser Parser) fixture_csi(params &string, command u8) {
	parts := params.split(';')
	first := if params.len == 0 { 0 } else { parts[0].int() }
	match command {
		`H`, `f` {
			row := if first > 0 { first - 1 } else { 0 }
			col := if parts.len > 1 && parts[1].int() > 0 { parts[1].int() - 1 } else { 0 }
			parser.current.cursor = layout.Position{
				x: u16(if col < int(parser.current.columns) {
					col
				} else {
					int(parser.current.columns) - 1
				})
				y: u16(if row < parser.current.rows.len { row } else { parser.current.rows.len - 1 })
			}
		}
		`r` {
			parser.current.scroll_top = if first > 0 { first - 1 } else { 0 }
			parser.current.scroll_bottom = if parts.len > 1 && parts[1].int() > 0 {
				parts[1].int() - 1
			} else {
				parser.current.rows.len - 1
			}
			parser.current.cursor = layout.Position{}
		}
		`J` {
			if first == 3 {
				parser.current.scrollback.clear()
				parser.current.scrollback_offset = 0
			} else if first == 2 {
				for row in 0 .. parser.current.rows.len {
					parser.current.rows[row] = ''
					parser.fixture_clear_cells(row, 0)
				}
			} else {
				parser.fixture_clear_line()
				for row in int(parser.current.cursor.y) + 1 .. parser.current.rows.len {
					parser.current.rows[row] = ''
					parser.fixture_clear_cells(row, 0)
				}
			}
		}
		`K` { parser.fixture_clear_line() }
		`B` {
			amount := if first > 0 { first } else { 1 }
			parser.current.cursor = layout.Position{
				...parser.current.cursor
				y: u16(if int(parser.current.cursor.y) + amount < parser.current.rows.len {
					int(parser.current.cursor.y) + amount
				} else {
					parser.current.rows.len - 1
				})
			}
		}
		`G` {
			parser.current.cursor = layout.Position{
				...parser.current.cursor
				x: u16(if first > 0 {
					first - 1
				} else {
					0
				})
			}
		}
		`s` { parser.current.saved_cursor = parser.current.cursor }
		`u` { parser.current.cursor = parser.current.saved_cursor }
		`m` { parser.fixture_sgr(&parts) }
		`q` {
			if params.ends_with(' ') && parser.current.jediterm_damage {
				space := ' '
				parser.fixture_print_text(&space)
			}
		}
		else {}
	}
}

// STUB: EL from the cursor through the end of the current fixture row.
fn (mut parser Parser) fixture_clear_line() {
	row := int(parser.current.cursor.y)
	if row >= parser.current.rows.len {
		return
	}
	col := int(parser.current.cursor.x)
	parser.fixture_clear_cells(row, col)
	if col < parser.current.rows[row].len {
		parser.current.rows[row] = parser.current.rows[row][..col].clone()
	}
}

// STUB: native LF scrolling adds rows to scrollback only for a region starting at row zero.
fn (mut parser Parser) fixture_line_feed() {
	row := int(parser.current.cursor.y)
	if row == parser.current.scroll_bottom {
		top := parser.current.scroll_top
		bottom := parser.current.scroll_bottom
		if top == 0 && parser.current.scrollback_capacity > 0 {
			parser.current.scrollback << parser.current.rows[top].clone()
			if usize(parser.current.scrollback.len) > parser.current.scrollback_capacity {
				parser.current.scrollback.delete(0)
			}
		}
		for y in top .. bottom {
			parser.current.rows[y] = parser.current.rows[y + 1].clone()
			parser.fixture_copy_cells(y + 1, y)
		}
		parser.current.rows[bottom] = ''
		parser.fixture_clear_cells(bottom, 0)
	} else if row + 1 < parser.current.rows.len {
		parser.current.cursor = layout.Position{ ...parser.current.cursor, y: u16(row + 1) }
	}
}

// STUB: reverse index moves a partial region down without adding terminal scrollback.
fn (mut parser Parser) fixture_reverse_index() {
	row := int(parser.current.cursor.y)
	if row == parser.current.scroll_top {
		mut y := parser.current.scroll_bottom
		for y > parser.current.scroll_top {
			parser.current.rows[y] = parser.current.rows[y - 1].clone()
			parser.fixture_copy_cells(y - 1, y)
			y--
		}
		parser.current.rows[parser.current.scroll_top] = ''
		parser.fixture_clear_cells(parser.current.scroll_top, 0)
	} else if row > 0 {
		parser.current.cursor = layout.Position{ ...parser.current.cursor, y: u16(row - 1) }
	}
}

// STUB: ASCII cell writes retain delayed character wrapping, as the history-tail fixtures require.
fn (mut parser Parser) fixture_print(byte u8) {
	if parser.current.columns == 0 || parser.current.rows.len == 0 {
		return
	}
	if parser.current.cursor.x >= parser.current.columns {
		parser.current.cursor = layout.Position{ ...parser.current.cursor, x: 0 }
		parser.fixture_line_feed()
	}
	row := int(parser.current.cursor.y)
	col := int(parser.current.cursor.x)
	mut current := parser.current.rows[row].clone()
	for current.len <= col {
		current += ' '
	}
	parser.current.rows[row] = current[..col] + byte.ascii_str() + current[col + 1..]
	parser.current.cursor = layout.Position{ ...parser.current.cursor, x: parser.current.cursor.x + 1 }
}
