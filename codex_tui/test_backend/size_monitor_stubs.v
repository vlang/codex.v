module test_backend

import ratatui.buffer
import ratatui.layout
import vt100

// STUB: test_backend::VT100Backend, preserving its typed parser owner. This fixture
// accepts rendered cells; the CrosstermBackend ANSI writer and scrolling are untranslated.
@[heap]
pub struct VT100Backend {
	size layout.Size
mut:
	parser vt100.Parser
	// STUB: CaptureBackend's source test byte capture shares the typed VT100 writer.
	output []u8
	// STUB: I/O error injection at the native writer dependency boundary.
	fixture_write_attempts int
	fixture_fail_at_write  int = -1
}

// STUB: VT100Backend::new's width/height and zero-scrollback setup.
pub fn VT100Backend.new(width u16, height u16) VT100Backend {
	return VT100Backend{ size: layout.Size.new(width, height), parser: vt100.Parser.new(height, width, 0) }
}

// STUB: VT100Backend::vt100 returns a shared parser borrow, matching the Rust API.
pub fn (backend &VT100Backend) vt100() &vt100.Parser {
	return &backend.parser
}

// STUB: Backend::draw's observed Buffer-cell boundary; native output escaping is absent.
pub fn (mut backend VT100Backend) draw(buf &buffer.Buffer) ! {
	backend.parser.render_buffer(buf, backend.size)
}
