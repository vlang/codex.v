module vt100

import ratatui.buffer
import ratatui.layout
import ratatui.style
import strings

// STUB: vt100::Parser's screen owner at the cell-based test fixture boundary. Full ANSI
// decoding, cursor modes and scrollback remain untranslated.
pub struct Parser {
mut:
	current Screen
}

// STUB: vt100::Screen's rendered contents, retaining only the observed logical cells.
pub struct Screen {
mut:
	rows []string
	// STUB: vt100 cells observe SGR/OSC8 damage and repair at the ANSI fixture boundary.
	cells            []Cell
	active_style     style.Style
	active_hyperlink string
	jediterm_damage  bool
	// STUB: history-tail ANSI fixture state; full VT100 mode/style parsing is untranslated.
	columns             u16
	cursor              layout.Position
	saved_cursor        layout.Position
	scroll_top          int
	scroll_bottom       int
	scrollback          []string
	scrollback_capacity usize
	scrollback_offset   int
}

// STUB: vt100::Parser::new retains dimensions and scrollback capacity for the test fixture.
pub fn Parser.new(rows u16, columns u16, scrollback_len usize) Parser {
	return Parser{ current: Screen{ rows: []string{len: int(rows)}, cells: []Cell{len: int(rows) * int(columns)}, columns: columns, scroll_bottom: int(rows) - 1, scrollback_capacity: scrollback_len } }
}

// STUB: apply a faithfully rendered ratatui buffer to the in-memory fixture screen.
pub fn (mut parser Parser) render_buffer(buf &buffer.Buffer, size layout.Size) {
	mut rows := []string{cap: int(size.height)}
	for y in 0 .. size.height {
		mut row := strings.new_builder(int(size.width))
		for x in 0 .. size.width {
			mut present := false
			for i in 0 .. buf.cells.len {
				cell := &buf.cells[i]
				if cell.x == x && cell.y == y {
					row.write_string(cell.symbol)
					present = true
					break
				}
			}
			if !present { row.write_u8(` `) }
		}
		rows << row.str().trim_right(' ')
	}
	parser.current.rows = rows
}

// STUB: vt100::Parser::screen retains a shared borrow of the current screen owner.
pub fn (parser &Parser) screen() &Screen {
	return &parser.current
}

// STUB: vt100::Screen::contents omits trailing blank rows and spaces, as the source snapshot
// API does; returns an owned V string because borrowed string slices cannot escape in V.
pub fn (screen &Screen) contents() string {
	if screen.scrollback_offset > 0 {
		mut visible := []string{cap: screen.rows.len}
		start := screen.scrollback.len - screen.scrollback_offset
		for index in start .. start + screen.rows.len {
			if index < screen.scrollback.len {
				visible << screen.scrollback[index].clone()
			} else {
				visible << screen.rows[index - screen.scrollback.len].clone()
			}
		}
		mut end := visible.len
		for end > 0 && visible[end - 1].len == 0 {
			end--
		}
		return visible[..end].join('\n')
	}
	mut end := screen.rows.len
	for end > 0 && screen.rows[end - 1].len == 0 {
		end--
	}
	return screen.rows[..end].join('\n')
}
