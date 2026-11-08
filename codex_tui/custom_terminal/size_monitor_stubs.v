module custom_terminal

import codex_tui.test_backend
import ratatui.buffer
import ratatui.layout
import crossterm.cursor

// STUB: custom_terminal::Frame borrows the source current buffer; native generic
// backend integration remains untranslated at this typed VT100 fixture boundary.
pub struct Frame {
mut:
	buf &buffer.Buffer
	// STUB: source Frame cursor metadata is captured before the mutable buffer borrow ends.
	cursor_position ?layout.Position
	cursor_style    cursor.CursorStyle = .default_user_shape
}

// STUB: Frame::buffer_mut's Rust &mut Buffer becomes a V mut callback argument.
pub fn (mut frame Frame) buffer_mut() &buffer.Buffer {
	return frame.buf
}

// STUB: Terminal::with_screen_size_and_cursor_position_for_test retains the independently
// sized backend, initial screen cache, and source-supplied cursor position.
pub fn Terminal.with_screen_size_and_cursor_position_for_test(backend test_backend.VT100Backend, screen_size layout.Size, cursor_pos layout.Position) Terminal {
	mut owned_backend := backend
	return Terminal{ last_known_screen_size: screen_size, last_known_cursor_pos: cursor_pos, backend: &owned_backend, fixture_cursor: cursor_pos }
}

// STUB: Terminal::set_viewport_area keeps the two source diff buffers in the logical
// rendering region; full Buffer::resize overlap semantics remain untranslated.
pub fn (mut terminal Terminal) set_viewport_area(area layout.Rect) {
	for index in 0 .. 2 {
		if terminal.buffers[index].area != area {
			terminal.buffers[index] = buffer.Buffer.empty(area)
		}
	}
	terminal.viewport_area = area
}

// STUB: Terminal::draw_with_size updates screen geometry before rendering, then flushes the
// source diff/repair/cursor/swap ordering through the typed VT100 native-writer fixture.
// The callback's distinct name avoids V resolving it as widgets.render's interface call.
pub fn (mut terminal Terminal) draw_with_size(screen_size layout.Size, render_callback fn (mut Frame)) ! {
	if terminal.backend == unsafe { nil } {
		return error('custom terminal drawing backend is not translated')
	}
	if screen_size != terminal.last_known_screen_size { terminal.resize(screen_size)! }
	mut cursor_position := ?layout.Position(none)
	mut cursor_style := cursor.CursorStyle.default_user_shape
	{
		mut frame := Frame{ buf: &terminal.buffers[terminal.current] }
		render_callback(mut frame)
		cursor_position = frame.cursor_position
		cursor_style = unsafe { cursor.CursorStyle(int(frame.cursor_style)) }
	}
	// End the mutable buffer borrow before flushing, matching the source Frame lifetime.
	commands := diff_buffers(&terminal.buffers[1 - terminal.current], &terminal.buffers[terminal.current])
	draw(mut terminal.backend, commands)!
	if position := cursor_position {
		terminal.set_cursor_style_with_repair(cursor_style)!
		terminal.set_cursor_position(position)!
		terminal.backend.show_cursor()!
		terminal.hidden_cursor = false
	} else {
		terminal.backend.hide_cursor()!
		terminal.hidden_cursor = true
	}
	terminal.buffers[1 - terminal.current] = buffer.Buffer.empty(terminal.viewport_area)
	terminal.current = 1 - terminal.current
	terminal.backend.flush()!
}

// STUB: Terminal::backend's shared borrow of its typed VT100 test backend.
pub fn (terminal &Terminal) backend() &test_backend.VT100Backend {
	return terminal.backend
}
