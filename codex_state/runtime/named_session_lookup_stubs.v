module runtime

import codex_state.model
import sync
import sqlx

// STUB: SQLite sharing across independently started in-process app servers. Tests
// explicitly register their runtime; normal StateRuntime::init behavior is unchanged.
@[heap]
struct NamedSessionRuntimeRegistry {
mut:
	mutex  &sync.Mutex = sync.new_mutex()
	states map[string]&StateRuntime
}

// STUB: fixture-only registry replacing the source tests' shared SQLite directory.
const named_session_runtime_registry = &NamedSessionRuntimeRegistry{}

// STUB: register the test runtime at its native SQLite home for embedded startup.
pub fn (state &StateRuntime) register_named_session_fixture() {
	unsafe {
		mut registry := named_session_runtime_registry
		registry.mutex.lock()
		defer { registry.mutex.unlock() }
		registry.states[state.sqlite.sqlite_home.clone()] = state
	}
}

// STUB: open the registered state runtime instead of untranslated SQLite IO.
pub fn named_session_fixture_state(home &string) !&StateRuntime {
	registry := named_session_runtime_registry
	registry.mutex.lock()
	defer { registry.mutex.unlock() }
	return registry.states[*home] or { return error('named-session test runtime is not registered') }
}

// STUB: StateRuntime::mark_backfill_complete's test watermark boundary. Backfill
// is absent in the in-memory backend, and all rows were inserted explicitly.
pub fn (state &StateRuntime) mark_backfill_complete(last_watermark ?string) ! {
	// V3's C generator needs an explicit reachable specialization for the
	// existing runtime's !OptionalScalar[i64] method signatures.
	_ = sqlx.OptionalScalar[i64]{}
	_ = state
	_ = last_watermark
}

// STUB: owned metadata snapshots replace thread-store list queries at the typed
// app-server fixture; metadata remains canonical and each RPC applies its filters.
pub fn (state &StateRuntime) named_session_fixture_threads() []model.ThreadMetadata {
	mut rows := []model.ThreadMetadata{cap: state.pool.threads.len}
	for _, row in state.pool.threads {
		rows << model.clone_thread_metadata(&row.metadata)
	}
	return rows
}
