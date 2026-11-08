module tracing

import codex_tui.streaming.chunking
import sync

// STUB: tracing::trace! metadata for "stream chunking mode transition"; preserve the complete
// typed event, including Rust's optional low-64-bit millisecond cast, for a future subscriber.
pub struct StreamChunkingTransition {
pub:
	prior_mode           chunking.ChunkingMode
	new_mode             chunking.ChunkingMode
	queued_lines         usize
	oldest_queued_age_ms ?u64
	entered_catch_up     bool
}

// STUB: fixture-only tracing subscriber state. Runtime logging/subscribers remain untranslated.
@[heap]
struct CommitTickTraceFixture {
mut:
	mutex   &sync.Mutex = sync.new_mutex()
	enabled bool
	events  []StreamChunkingTransition
}

// STUB: private fixture subscriber handle; capturing is disabled by default.
const commit_tick_trace_fixture = &CommitTickTraceFixture{}

// STUB: external tracing subscriber. Typed transition metadata is captured only when a test
// explicitly enables the fixture subscriber; no production logging destination is invented.
pub fn trace_stream_chunking_transition(event StreamChunkingTransition) {
	unsafe {
		mut fixture := commit_tick_trace_fixture
		fixture.mutex.lock()
		defer { fixture.mutex.unlock() }
		if fixture.enabled { fixture.events << event }
	}
}

// STUB: fixture subscriber activation, clearing previous events under the same lock.
pub fn fixture_begin_commit_tick_trace() {
	unsafe {
		mut fixture := commit_tick_trace_fixture
		fixture.mutex.lock()
		defer { fixture.mutex.unlock() }
		fixture.enabled = true
		fixture.events.clear()
	}
}

// STUB: fixture subscriber shutdown, transferring owned captured events to the caller.
pub fn fixture_take_commit_tick_trace() []StreamChunkingTransition {
	unsafe {
		mut fixture := commit_tick_trace_fixture
		fixture.mutex.lock()
		defer { fixture.mutex.unlock() }
		fixture.enabled = false
		events := fixture.events
		fixture.events = []StreamChunkingTransition{}
		return events
	}
}
