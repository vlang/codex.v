module custom_terminal

import ratatui.layout
import ratatui.buffer
import codex_tui.test_backend
import sync

// STUB: fixture state for custom_terminal::Terminal's untranslated backend. Query accounting
// and injected failures stay behind size(), never in the translated geometry policy.
@[heap]
struct ScreenSizeBackend {
mut:
	mutex   &sync.Mutex = sync.new_mutex()
	size    layout.Size
	queries int
	fail    bool
}

// STUB: crate::custom_terminal::Terminal. Native backend drawing is not translated. The optional
// override has the same role as screen_size_override in the Rust test terminal.
@[heap]
pub struct Terminal {
pub mut:
	last_known_screen_size layout.Size
	// STUB: source-owned viewport observed by terminal geometry and rendering tests.
	viewport_area layout.Rect
	// STUB: source cursor cache observed by insert_history's cursor-neutral writer.
	last_known_cursor_pos layout.Position
mut:
	// STUB: custom_terminal.rs owns both source diff buffers and their current index.
	buffers [2]buffer.Buffer
	current int
	// STUB: custom_terminal.rs tracks visible cursor state after backend operations.
	hidden_cursor   bool
	fixture_backend &ScreenSizeBackend = unsafe { nil }
	// STUB: VT100 drawing fixture until the full native backend is translated.
	backend        &test_backend.VT100Backend = unsafe { nil }
	fixture_cursor layout.Position
	// STUB: native diff-buffer invalidation and visible-history accounting observation.
	fixture_invalidations        int
	fixture_visible_history_rows u16
}

// STUB: in-memory boundary for Terminal::with_screen_size_and_cursor_position_for_test. It
// preserves the supplied backend-size override and initial cached geometry without native I/O.
pub fn Terminal.screen_size_fixture(size layout.Size) Terminal {
	return Terminal{ last_known_screen_size: size, fixture_backend: &ScreenSizeBackend{ size: size } }
}

// STUB: crate::custom_terminal::Terminal::size. Until the backend is translated, only the
// explicitly constructed test terminal can return geometry; ordinary terminals return an error.
pub fn (terminal &Terminal) size() !layout.Size {
	if terminal.backend != unsafe { nil } {
		return terminal.backend.size()
	}
	if terminal.fixture_backend == unsafe { nil } {
		return error('custom terminal backend is not translated')
	}
	unsafe {
		mut backend := terminal.fixture_backend
		backend.mutex.lock()
		defer { backend.mutex.unlock() }
		backend.queries++
		if backend.fail {
			return error('terminal size query failed')
		}
		return backend.size
	}
}

// STUB: crate::custom_terminal::Terminal::resize updates the cache, not the backend-size override.
pub fn (mut terminal Terminal) resize(size layout.Size) ! {
	terminal.last_known_screen_size = size
}

// STUB: fixture adapter for changing the independently sampled backend geometry.
pub fn (terminal &Terminal) fixture_set_backend_size(size layout.Size) {
	unsafe {
		mut backend := terminal.fixture_backend
		backend.mutex.lock()
		defer { backend.mutex.unlock() }
		backend.size = size
	}
}

// STUB: fixture adapter for backend I/O errors returned through Terminal::size.
pub fn (terminal &Terminal) fixture_fail_size_query(fail bool) {
	unsafe {
		mut backend := terminal.fixture_backend
		backend.mutex.lock()
		defer { backend.mutex.unlock() }
		backend.fail = fail
	}
}

// STUB: fixture observation of Terminal::size backend queries.
pub fn (terminal &Terminal) fixture_size_query_count() int {
	unsafe {
		mut backend := terminal.fixture_backend
		backend.mutex.lock()
		defer { backend.mutex.unlock() }
		return backend.queries
	}
}
