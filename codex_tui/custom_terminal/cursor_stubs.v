module custom_terminal

import codex_tui.test_backend
import crossterm.cursor
import ratatui.buffer
import ratatui.layout
import ratatui.style

// STUB: custom_terminal.rs::DrawCommand's owned payload variants, including ClearToEnd.
enum DrawCommandKind {
	put
	clear_to_end
}

// STUB: custom_terminal.rs::DrawCommand keeps Cell/style/hyperlink typed and owned.
struct DrawCommand {
	kind DrawCommandKind
	x    u16
	y    u16
	cell buffer.Cell
	bg   style.Color
}

// STUB: Frame::set_cursor_position retains allocation-free Option<Position> metadata.
pub fn (mut frame Frame) set_cursor_position(position layout.Position) {
	frame.cursor_position = position
}

// STUB: Frame::set_cursor_style retains the source default and requested DECSCUSR shape.
pub fn (mut frame Frame) set_cursor_style(cursor_style cursor.CursorStyle) {
	frame.cursor_style = cursor_style
}

// STUB: custom_terminal.rs::Terminal::draw queries the typed backend before draw_with_size.
pub fn (mut terminal Terminal) draw(render_callback fn (mut Frame)) ! {
	size := terminal.size()!
	terminal.draw_with_size(size, render_callback)!
}

// STUB: custom_terminal.rs::Terminal::set_cursor_position caches only a successful backend call.
pub fn (mut terminal Terminal) set_cursor_position(position layout.Position) ! {
	terminal.backend.set_cursor_position(position)!
	terminal.last_known_cursor_pos = position
}

// STUB: custom_terminal.rs::Terminal::set_cursor_style writes through the source writer API.
pub fn (mut terminal Terminal) set_cursor_style(cursor_style cursor.CursorStyle) ! {
	terminal.backend.set_cursor_style(cursor_style)!
}

// STUB: custom_terminal.rs::diff_buffers fixture boundary preserves row-major leaders,
// Skip/AlwaysUpdate/ForcedWidth and trailing ClearToEnd calls for executable cursor tests.
// Ratatui's full diff iterator and shrinking-wide invalidation remain untranslated.
fn diff_buffers(previous &buffer.Buffer, next &buffer.Buffer) []DrawCommand {
	mut commands := []DrawCommand{}
	mut puts := []DrawCommand{}
	for row in 0 .. int(next.area.height) {
		row_start := row * int(next.area.width)
		row_end := row_start + int(next.area.width)
		if row_start == row_end {
			continue
		}
		bg := next.cells[row_end - 1].style.bg or { style.Color{} }
		mut last_nonblank := 0
		mut column := 0
		for column < int(next.area.width) {
			cell := &next.cells[row_start + column]
			width := int(cell.cell_width())
			if cell.symbol != ' ' || (cell.style.bg or { style.Color{} }) != bg || int(cell.style.add_modifier) != 0 || cell.diff_option.kind == .always_update {
				last_nonblank = column + if width > 0 { width - 1 } else { 0 }
			}
			column += if width > 0 { width } else { 1 }
		}
		clear_start := last_nonblank + 1
		if clear_start < int(next.area.width) && previous.cells[row_start + clear_start..row_end] != next.cells[row_start + clear_start..row_end] {
			x, y := next.pos_of(row_start + clear_start)
			commands << DrawCommand{ kind: .clear_to_end, x: x, y: y, bg: bg }
		}
		column = 0
		for column < int(next.area.width) {
			index := row_start + column
			cell := &next.cells[index]
			width := int(cell.cell_width())
			if column <= last_nonblank && cell.diff_option.kind != .skip && (*cell != previous.cells[index] || cell.diff_option.kind == .always_update || previous.cells[index].diff_option.kind == .always_update) {
				x, y := next.pos_of(index)
				puts << DrawCommand{ kind: .put, x: x, y: y, cell: cell.clone() }
			}
			column += if width > 0 { width } else { 1 }
		}
	}
	commands << puts
	return commands
}

// STUB: custom_terminal.rs::draw's owned command iterator becomes an owned V array;
// native ANSI writes preserve source ordering, attributes, colors and OSC 8 metadata.
fn draw(mut writer test_backend.VT100Backend, commands []DrawCommand) ! {
	mut fg := style.Color{}
	mut bg := style.Color{}
	mut modifier := unsafe { style.Modifier(0) }
	mut last_pos := ?layout.Position(none)
	mut active_hyperlink := ''
	for i in 0 .. commands.len {
		command := &commands[i]
		mut destination := ''
		mut symbol := ''
		if command.kind == .put {
			if parts := osc8_hyperlink_parts(&command.cell.symbol) {
				destination = parts.destination
				symbol = parts.visible
			} else {
				symbol = command.cell.symbol.clone()
			}
		}
		hyperlink_changed := active_hyperlink != destination
		if hyperlink_changed && active_hyperlink.len > 0 { write_ansi(mut writer, '\x1b]8;;\x07')! }
		position := layout.Position{ x: command.x, y: command.y }
		mut adjacent := false
		if old := last_pos {
			adjacent = command.x == old.x + 1 && command.y == old.y
		}
		if !adjacent { writer.set_cursor_position(position)! }
		last_pos = position
		if command.kind == .put {
			cell := &command.cell
			if cell.style.add_modifier != modifier {
				queue_modifier_diff(mut writer, modifier, cell.style.add_modifier)!
				// Copy-equivalent flags reconstructed explicitly for V's ownership checker.
				modifier = unsafe { style.Modifier(int(cell.style.add_modifier)) }
			}
			cell_fg := cell.style.fg or { style.Color{} }
			cell_bg := cell.style.bg or { style.Color{} }
			if cell_fg != fg || cell_bg != bg {
				write_ansi(mut writer, '\x1b[${color_sgr(cell_fg, true)};${color_sgr(cell_bg, false)}m')!
				fg = cell_fg
				bg = cell_bg
			}
			if hyperlink_changed && destination.len > 0 {
				write_ansi(mut writer, '\x1b]8;;${destination}\a')!
			}
			write_ansi(mut writer, symbol)!
		} else {
			write_ansi(mut writer, '\x1b[0m')!
			modifier = unsafe { style.Modifier(0) }
			write_ansi(mut writer, '\x1b[${color_sgr(command.bg, false)}m')!
			bg = style.Color{ kind: unsafe { style.ColorKind(int(command.bg.kind)) }, r: command.bg.r, g: command.bg.g, b: command.bg.b, index: command.bg.index }
			writer.clear_region(.until_new_line)!
		}
		if hyperlink_changed {
			active_hyperlink = destination
		}
	}
	if active_hyperlink.len > 0 { write_ansi(mut writer, '\x1b]8;;\x07')! }
	write_ansi(mut writer, '\x1b[39m\x1b[49m\x1b[0m')!
}

// STUB: owned ANSI formatting passed to std::io::Write's borrowed byte-slice boundary.
fn write_ansi(mut writer test_backend.VT100Backend, value string) ! {
	data := value.bytes()
	writer.write(&data)!
}

// STUB: custom_terminal.rs::osc8_hyperlink_parts has an optional tuple of shared
// string slices. V requires owned strings for these escaping return values.
struct Osc8HyperlinkParts {
	destination string
	visible     string
}

// STUB: custom_terminal.rs::osc8_hyperlink_parts keeps None for invalid/empty destinations.
fn osc8_hyperlink_parts(symbol &string) ?Osc8HyperlinkParts {
	if symbol.starts_with('\x1b]8;;') && symbol.ends_with('\x1b]8;;\x07') {
		end := symbol.index_after('\x07', 5) or { return none }
		if end == 5 {
			return none
		}
		return Osc8HyperlinkParts{ destination: (*symbol)[5..end].clone(), visible: (*symbol)[end + 1..symbol.len - 6].clone() }
	}
	return none
}

// STUB: ratatui Color::into_crossterm's SGR encoding at the native writer boundary.
fn color_sgr(color style.Color, foreground bool) string {
	base := if foreground { 38 } else { 48 }
	return match color.kind {
		.reset {
			if foreground { '39' } else { '49' }
		}
		.rgb { '${base};2;${color.r};${color.g};${color.b}' }
		.indexed { '${base};5;${color.index}' }
		else {
			index := match color.kind {
				.black { 0 }
				.red { 1 }
				.green { 2 }
				.yellow { 3 }
				.blue { 4 }
				.magenta { 5 }
				.cyan { 6 }
				.gray { 7 }
				.dark_gray { 8 }
				.light_red { 9 }
				.light_green { 10 }
				.light_yellow { 11 }
				.light_blue { 12 }
				.light_magenta { 13 }
				.light_cyan { 14 }
				.white { 15 }
				else { 0 }
			}
			'${base};5;${index}'
		}
	}
}

// STUB: custom_terminal.rs::ModifierDiff preserves removed/added attribute command order.
fn queue_modifier_diff(mut writer test_backend.VT100Backend, from style.Modifier, to style.Modifier) ! {
	for bit, reset in [27, 22, 23, 24, 22, 29, 25, 25] {
		flag := [style.Modifier.reversed, .bold, .italic, .underlined, .dim, .crossed_out, .slow_blink,
			.rapid_blink][bit]
		if from.has(flag) && !to.has(flag) {
			write_ansi(mut writer, '\x1b[${reset}m')!
			if flag == .bold && to.has(.dim) { write_ansi(mut writer, '\x1b[2m')! }
		}
	}
	for bit, code in [7, 1, 3, 4, 2, 9, 5, 6] {
		flag := [style.Modifier.reversed, .bold, .italic, .underlined, .dim, .crossed_out, .slow_blink,
			.rapid_blink][bit]
		if to.has(flag) && !from.has(flag) { write_ansi(mut writer, '\x1b[${code}m')! }
	}
}
