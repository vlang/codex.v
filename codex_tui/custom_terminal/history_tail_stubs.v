module custom_terminal

import codex_tui.test_backend
import ratatui.backend as ratatui_backend
import ratatui.layout

// STUB: custom_terminal::Terminal::with_options owns the typed fixture backend,
// sampling its dimensions and cursor position; native runtime setup is untranslated.
pub fn Terminal.with_options(backend test_backend.VT100Backend) !Terminal {
	screen_size := backend.size()!
	cursor_pos := backend.get_cursor_position() or { layout.Position{} }
	mut owned_backend := backend
	return Terminal{ last_known_screen_size: screen_size, last_known_cursor_pos: cursor_pos, viewport_area: layout.Rect.new(0, cursor_pos.y, 0, 0), backend: &owned_backend }
}

// STUB: custom_terminal::Terminal::backend_mut retains the source's mutable writer API.
pub fn (mut terminal Terminal) backend_mut() &test_backend.VT100Backend {
	return terminal.backend
}

// STUB: custom_terminal::Terminal::clear_after_position emits source-shaped cursor/ED
// commands through the backend; native previous-buffer reset is represented by invalidation.
pub fn (mut terminal Terminal) clear_after_position(position layout.Position) ! {
	if terminal.backend == unsafe { nil } {
		return error('custom terminal drawing backend is not translated')
	}
	mut backend := terminal.backend_mut()
	backend.set_cursor_position(position)!
	backend.clear_region(ratatui_backend.ClearType.after_cursor)!
}

// STUB: custom_terminal::Terminal::invalidate_viewport's next-draw requirement.
pub fn (mut terminal Terminal) invalidate_viewport() {
	terminal.fixture_invalidations++
}

// STUB: custom_terminal::Terminal::note_history_rows_inserted's saturating counter.
pub fn (mut terminal Terminal) note_history_rows_inserted(inserted_rows u16) {
	count := u32(terminal.fixture_visible_history_rows) + u32(inserted_rows)
	terminal.fixture_visible_history_rows = u16(if count < u32(terminal.viewport_area.y) {
		count
	} else {
		u32(terminal.viewport_area.y)
	})
}

// STUB: fixture observation of the source viewport invalidation after raw history writes.
pub fn (terminal &Terminal) fixture_viewport_invalidation_count() int {
	return terminal.fixture_invalidations
}
