module test_backend

import ratatui.layout
import ratatui.backend as ratatui_backend
import std_ops
import vt100

// STUB: VT100Backend::with_scrollback retains the real dimensions and scrollback limit.
pub fn VT100Backend.with_scrollback(width u16, height u16, scrollback_len usize) VT100Backend {
	return VT100Backend{ size: layout.Size.new(width, height), parser: vt100.Parser.new(height, width, scrollback_len) }
}

// STUB: Backend::size queries fixture parser dimensions without native stdout probing.
pub fn (backend &VT100Backend) size() !layout.Size {
	return backend.size
}

// STUB: Backend::get_cursor_position retains the parser's real writer cursor position.
pub fn (backend &VT100Backend) get_cursor_position() !layout.Position {
	return backend.parser.screen().cursor_position()
}

// STUB: std::io::Write::write processes the borrowed byte buffer through the ANSI fixture.
// The typed parser fixture also observes SGR and OSC 8 for cursor-repair tests.
pub fn (mut backend VT100Backend) write(data &[]u8) !usize {
	backend.fixture_write_attempts++
	if backend.fixture_write_attempts == backend.fixture_fail_at_write {
		return error('terminal write failed')
	}
	for byte in *data {
		backend.output << byte
	}
	backend.parser.process(data)
	return usize(data.len)
}

// STUB: std::io::Write::flush is immediate for the in-memory parser fixture.
pub fn (mut backend VT100Backend) flush() ! {}

// STUB: Backend::set_cursor_position emits the native ANSI command at the real writer API.
pub fn (mut backend VT100Backend) set_cursor_position(position layout.Position) ! {
	command := '\x1b[${position.y + 1};${position.x + 1}H'.bytes()
	backend.write(&command)!
}

// STUB: Backend::clear_region retains the typed native clear command at the writer boundary.
pub fn (mut backend VT100Backend) clear_region(clear_type ratatui_backend.ClearType) ! {
	command := match clear_type {
		.all { '\x1b[2J' }
		.after_cursor { '\x1b[J' }
		.before_cursor { '\x1b[1J' }
		.current_line { '\x1b[2K' }
		.until_new_line { '\x1b[K' }
	}.bytes()
	backend.write(&command)!
}

// STUB: Backend::scroll_region_up retains its typed exclusive Range<u16> and I/O errors.
pub fn (mut backend VT100Backend) scroll_region_up(region std_ops.Range[u16], scroll_by u16) ! {
	command := '\x1b[${region.start + 1};${region.end}r\x1b[${region.end};1H'.bytes()
	backend.write(&command)!
	for _ in 0 .. scroll_by {
		data := '\r\n'.bytes()
		backend.write(&data)!
	}
	reset := '\x1b[r'.bytes()
	backend.write(&reset)!
}

// STUB: fixture error injection relative to the writer's current attempt count.
pub fn (mut backend VT100Backend) fixture_fail_write_after(successful_writes int) {
	backend.fixture_fail_at_write = backend.fixture_write_attempts + successful_writes + 1
}

// STUB: fixture clear-error recovery keeps the real writer entry usable afterward.
pub fn (mut backend VT100Backend) fixture_allow_writes() {
	backend.fixture_fail_at_write = -1
}
