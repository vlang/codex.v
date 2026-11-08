module highlight

import ratatui.text
import sync

// STUB: render/highlight.rs MAX_HIGHLIGHT_LINE_BYTES; individual-line safety limit.
pub const max_highlight_line_bytes = usize(4 * 1024)

// STUB: render/highlight.rs syntax_theme_revision. Theme loading and swapping are absent;
// the untranslated theme therefore remains at Rust's initial revision zero.
pub fn syntax_theme_revision() u64 {
	return 0
}

// STUB: render/highlight_streaming.rs StreamingCodeHighlighter. The fixture is an
// explicit in-memory oracle for API ordering; production syntax highlighting is unsupported.
pub struct StreamingCodeHighlighter {
mut:
	fixture    bool
	batches    []CodeFenceFixtureBatch
	next_batch int
}

// STUB: a typed fixture for one StreamingCodeHighlighter::append call, not syntax coloring.
pub struct CodeFenceFixtureBatch {
pub:
	appended string
	lines    []text.Line
	fails    bool
}

// STUB: isolated in-memory replay expectations behind StreamingCodeHighlighter::new.
@[heap]
struct CodeFenceFixtureReplay {
mut:
	mutex          &sync.Mutex = sync.new_mutex()
	configured     bool
	code           string
	language       string
	theme_revision u64
	batches        []CodeFenceFixtureBatch
	new_calls      usize
}

// STUB: fixture storage; a production caller has no configured replay and receives none.
const code_fence_fixture_replay = &CodeFenceFixtureReplay{}

// STUB: install a one-shot typed replay oracle for a test of the source-shaped new API.
pub fn code_fence_fixture_install(code string, language string, theme_revision u64,
	batches []CodeFenceFixtureBatch) {
	mut replay := unsafe { code_fence_fixture_replay }
	replay.mutex.lock()
	replay.configured = true
	replay.code = code
	replay.language = language
	replay.theme_revision = theme_revision
	replay.batches = []CodeFenceFixtureBatch{cap: batches.len}
	for batch in batches {
		replay.batches << batch
	}
	replay.new_calls = 0
	replay.mutex.unlock()
}

// STUB: observe fixture replay count without accessing dependency fields at the target call site.
pub fn code_fence_fixture_new_calls() usize {
	mut replay := unsafe { code_fence_fixture_replay }
	replay.mutex.lock()
	count := replay.new_calls
	replay.mutex.unlock()
	return count
}

// STUB: clear an in-memory test oracle; the production fallback is always unsupported.
pub fn code_fence_fixture_clear() {
	mut replay := unsafe { code_fence_fixture_replay }
	replay.mutex.lock()
	replay.configured = false
	replay.code = ''
	replay.language = ''
	replay.batches = []CodeFenceFixtureBatch{}
	replay.new_calls = 0
	replay.mutex.unlock()
}

// STUB: render/highlight_streaming.rs StreamingCodeHighlighter::new. No Syntect
// replay is implemented; only an explicitly installed matching test oracle can succeed.
pub fn StreamingCodeHighlighter.new(code &string, language &string, theme_revision u64) ?StreamingCodeHighlighter {
	mut replay := unsafe { code_fence_fixture_replay }
	replay.mutex.lock()
	replay.new_calls++
	if !replay.configured || *code != replay.code || *language != replay.language
		|| theme_revision != replay.theme_revision || theme_revision != syntax_theme_revision() {
		replay.mutex.unlock()
		return none
	}
	replay.configured = false
	batches := replay.batches
	replay.batches = []CodeFenceFixtureBatch{}
	replay.mutex.unlock()
	return StreamingCodeHighlighter{ fixture: true, batches: batches }
}

// STUB: render/highlight_streaming.rs consuming append API. Fixture lines are
// moved from the exact expected call; actual syntax parsing/coloring remains unsupported.
pub fn (state StreamingCodeHighlighter) append(appended &string) ?(StreamingCodeHighlighter, []text.Line) {
	if !state.fixture || !appended.ends_with('\n')
		|| state.next_batch >= state.batches.len {
		return none
	}
	if *appended != state.batches[state.next_batch].appended || state.batches[state.next_batch].fails {
		return none
	}
	// Reassemble the consumed fixture collection rather than aliasing its immutable
	// incoming array. No source/highlighted text is cloned by this ownership adaptation.
	mut batches := []CodeFenceFixtureBatch{cap: state.batches.len}
	mut lines := []text.Line{}
	for index, batch in state.batches {
		if index == state.next_batch {
			lines = batch.lines
			batches << CodeFenceFixtureBatch{}
		} else {
			batches << batch
		}
	}
	return StreamingCodeHighlighter{
		fixture:    true
		batches:    batches
		next_batch: state.next_batch + 1
	}, lines
}
