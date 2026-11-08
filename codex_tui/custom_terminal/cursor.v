// Repair the glyph beneath cursor-style commands on older JediTerm terminals.
//
// This helper issues cursor-style commands only at an owned, non-skipped glyph leader
// with positive width that fits within its row, then redraws it with the same style and
// hyperlink. Without a safe anchor, it omits the command. The caller must restore the
// requested cursor position afterward.
module custom_terminal

import crossterm.cursor
import ratatui.buffer
import ratatui.layout

fn (mut terminal Terminal) set_cursor_style_with_repair(cursor_style cursor.CursorStyle) ! {
	// JediTerm before 3.56 prints DECSCUSR's space intermediate at the cursor.
	// Apply the style over an owned glyph, then repair it even on unchanged frames.
	// https://github.com/JetBrains/jediterm/commit/0c4524f2978bddae65a46c35f264bf89e2ed58fd
	buf := &terminal.buffers[terminal.current]
	mut anchor := ?layout.Position(none)
	mut anchor_cell := buffer.Cell{}
	for row in 0 .. int(buf.area.height) {
		row_start := row * int(buf.area.width)
		mut column := 0
		for column < int(buf.area.width) {
			// Rust Buffer.content maps to the existing ratatui Buffer.cells owner in V.
			cell := &buf.cells[row_start + column]
			width := int(cell.cell_width())
			is_skip := cell.diff_option.kind == .skip
			if !is_skip && width > 0 && column + width <= int(buf.area.width) {
				x, y := buf.pos_of(row_start + column)
				anchor = layout.Position{ x: x, y: y }
				anchor_cell = cell.clone()
				break
			}
			column += if width > 0 { width } else { 1 }
		}
		if anchor != none {
			break
		}
	}
	// Empty and externally owned viewports have no cell we can safely repair.
	if position := anchor {
		terminal.set_cursor_position(position)!
		terminal.set_cursor_style(cursor_style)!
		draw(mut terminal.backend, [DrawCommand{ kind: .put, x: position.x, y: position.y, cell: anchor_cell }])!
	}
}
