module test_backend

import crossterm.cursor

// STUB: CrosstermBackend queues every SetCursorStyle shape through std::io::Write.
pub fn (mut backend VT100Backend) set_cursor_style(cursor_style cursor.CursorStyle) ! {
	code := match cursor_style {
		.default_user_shape { 0 }
		.blinking_block { 1 }
		.steady_block { 2 }
		.blinking_under_score { 3 }
		.steady_under_score { 4 }
		.blinking_bar { 5 }
		.steady_bar { 6 }
	}
	data := '\x1b[${code} q'.bytes()
	backend.write(&data)!
}

// STUB: Backend::show_cursor queues the native visibility control after cursor movement.
pub fn (mut backend VT100Backend) show_cursor() ! {
	data := '\x1b[?25h'.bytes()
	backend.write(&data)!
}

// STUB: Backend::hide_cursor queues the native visibility control after frame flushing.
pub fn (mut backend VT100Backend) hide_cursor() ! {
	data := '\x1b[?25l'.bytes()
	backend.write(&data)!
}

// STUB: CaptureBackend::output returns owned UTF-8 output from the real writer boundary.
pub fn (backend &VT100Backend) output() string {
	return backend.output.bytestr()
}

// STUB: CaptureBackend tests clear captured bytes without changing physical parser state.
pub fn (mut backend VT100Backend) clear_output() {
	backend.output.clear()
}

// STUB: test-only old JediTerm behavior is injected in the typed ANSI parser.
pub fn (mut backend VT100Backend) fixture_enable_jediterm_damage() {
	backend.parser.fixture_enable_jediterm_damage()
}
