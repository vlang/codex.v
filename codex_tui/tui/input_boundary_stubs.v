module tui

import std_io
import sync

// STUB: state behind the source-shaped restore_after_exit API; only deterministic fixtures
// implement results. The real terminal-mode restoration in tui.rs is not translated.
@[heap]
struct InputBoundaryRestoreState {
mut:
	mutex     sync.Mutex
	installed bool
	message   string
	calls     int
}

// STUB: process-local fixture owner for the untranslated terminal restoration API.
const input_boundary_restore_state = &InputBoundaryRestoreState{}

// STUB: crate::tui::restore_after_exit. Runtime restoration is explicitly unsupported until
// restore_common and terminal_stderr::finish are ported. The guard deliberately ignores errors.
pub fn restore_after_exit() ! {
	mut state := input_boundary_restore_state
	state.mutex.lock()
	defer { state.mutex.unlock() }
	state.calls++
	if !state.installed {
		return std_io.Error.new(.unsupported, 'terminal restoration is not translated')
	}
	if state.message.len != 0 {
		return std_io.Error.new(.other, state.message.clone())
	}
}

// STUB: fixture configuration behind restore_after_exit, consuming the owned error message.
// An empty message means restoration succeeds; installation always resets the call count.
pub fn install_input_boundary_restore_fixture(message string) {
	mut state := input_boundary_restore_state
	state.mutex.lock()
	defer { state.mutex.unlock() }
	state.installed = true
	state.message = message
	state.calls = 0
}

// STUB: fixture observation behind restore_after_exit; no test fields are exposed on the guard.
pub fn input_boundary_restore_fixture_calls() int {
	mut state := input_boundary_restore_state
	state.mutex.lock()
	defer { state.mutex.unlock() }
	return state.calls
}

// STUB: fixture cleanup restoring the honest unsupported production behavior.
pub fn clear_input_boundary_restore_fixture() {
	mut state := input_boundary_restore_state
	state.mutex.lock()
	defer { state.mutex.unlock() }
	state.installed = false
	state.message = ''
	state.calls = 0
}
