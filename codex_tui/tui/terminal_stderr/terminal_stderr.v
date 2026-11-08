// Protect the inline viewport from unmanaged macOS writes to stderr.
//
// Some macOS frameworks and runtime diagnostics write directly to file
// descriptor 2. While the inline TUI is active, those writes paint into the
// same terminal region as the composer without going through the renderer.
// Keep them off the terminal until the TUI releases terminal ownership.
module terminal_stderr

// V's ownership checker recognizes this Drop implementation. Normal GC builds
// must defer guard.drop() at the owning scope; drop disarms the guard so an
// explicit defer and automatic ownership cleanup can safely coexist.
interface Drop {
mut:
	drop()
}

// Keeps unmanaged stderr output away from the terminal while the TUI owns it.
// V has no pub(crate)/pub(super); export the parent module's guard API.
pub struct TerminalStderrGuard implements Drop {
mut:
	active bool
}

pub fn TerminalStderrGuard.install() !TerminalStderrGuard {
	$if macos {
		if stderr_targets_stdout_terminal() {
			return TerminalStderrGuard.install_suppression()
		}
	}
	return TerminalStderrGuard{ active: false }
}

// Reclaim stderr after a caught panic temporarily restored terminal ownership.
pub fn (mut guard TerminalStderrGuard) recover_after_caught_panic() ! {
	if !guard.active {
		return
	}
	$if macos {
		mut state := lock_state()!
		defer { state.mutex.unlock() }
		if !state.owner_active {
			suppress_locked(mut state)!
			state.owner_active = true
		}
	}
}

pub fn (mut guard TerminalStderrGuard) drop() {
	if guard.active {
		finish() or {}
		guard.active = false
	}
}

// Restores stderr while terminal ownership is temporarily released.
pub fn pause() ! {
	$if macos {
		mut state := lock_state()!
		defer { state.mutex.unlock() }
		if state.owner_active {
			restore_locked(mut state)!
		}
	}
}

// Suppresses stderr again when terminal ownership returns to the TUI.
pub fn resume() ! {
	$if macos {
		mut state := lock_state()!
		defer { state.mutex.unlock() }
		if state.owner_active {
			suppress_locked(mut state)!
		}
	}
}

// Restores stderr permanently when the TUI session ends.
pub fn finish() ! {
	$if macos {
		mut state := lock_state()!
		defer { state.mutex.unlock() }
		if state.owner_active {
			restore_locked(mut state)!
			state.owner_active = false
		}
	}
}
