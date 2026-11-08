module terminal_stderr

import std_io
import sync

const stderr_state = &StderrState{}

@[heap]
struct StderrState {
mut:
	mutex        &sync.Mutex = sync.new_mutex()
	owner_active bool
	// Option<OwnedFd> is an owning descriptor slot: -1 is None, and clearing a
	// present slot explicitly closes it. No descriptor is copied to another owner.
	saved_stderr i32 = -1
}

fn TerminalStderrGuard.install_suppression() !TerminalStderrGuard {
	$if macos {
		mut state := lock_state()!
		defer { state.mutex.unlock() }
		if state.owner_active {
			return std_io.Error.new(.already_exists,
				'terminal stderr suppression is already active')
		}
		suppress_locked(mut state)!
		state.owner_active = true
		return TerminalStderrGuard{ active: true }
	} $else {
		return TerminalStderrGuard{ active: false }
	}
}

fn lock_state() !&StderrState {
	// A scoped defer at each caller replaces Rust's MutexGuard. V's mutex has no
	// poison state, and V panics abort instead of unwinding a locked guard, so
	// Rust's "terminal stderr suppression lock poisoned" error is unreachable.
	mut state := unsafe { stderr_state }
	state.mutex.lock()
	return state
}

fn stderr_targets_stdout_terminal() bool {
	$if macos {
		return C.codex_terminal_stderr_same_terminal() != 0
	} $else {
		return false
	}
}

fn suppress_locked(mut state StderrState) ! {
	$if macos {
		if state.saved_stderr != -1 {
			return
		}
		// SAFETY: dup returns a newly owned file descriptor on success.
		mut saved_stderr := C.dup(2)
		if saved_stderr == -1 {
			return last_os_error()
		}
		// SAFETY: saved_stderr is a fresh descriptor returned by dup above.
		// This defer is OwnedFd's failure cleanup; transferring it to state disarms it.
		defer {
			if saved_stderr != -1 {
				C.close(saved_stderr)
			}
		}
		devnull := C.codex_terminal_stderr_open_devnull()
		if devnull == -1 {
			return last_os_error()
		}
		defer { C.close(devnull) }
		// SAFETY: both descriptors are valid for the duration of this call.
		if C.dup2(devnull, 2) == -1 {
			return last_os_error()
		}
		state.saved_stderr = saved_stderr
		saved_stderr = -1
	}
}

fn restore_locked(mut state StderrState) ! {
	$if macos {
		if state.saved_stderr == -1 {
			return
		}
		// SAFETY: saved_stderr was duplicated from stderr and remains owned here.
		if C.dup2(state.saved_stderr, 2) == -1 {
			return last_os_error()
		}
		C.close(state.saved_stderr)
		state.saved_stderr = -1
	}
}
