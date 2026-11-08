// Restore terminal ownership on initialization failures and quarantine protected-screen input.
module input_boundary

import codex_tui.tui
import crossterm.event
import std_io
import std_time

// V recognizes an explicitly implemented Drop interface in ownership builds. Normal builds
// need explicit cleanup at the owning function scope. An explicit defer can call guard.drop()
// then disarm guard.active so ownership builds do not restore twice; automatic-only ownership
// scopes need no defer. A defer inside a conditional block runs when that block ends, before
// initialization has transferred ownership.
// In this compiler, `-ownership` alone does not set the custom `$if ownership ?` flag;
// conditional normal cleanup also needs `-d ownership` in ownership builds. The explicit
// cleanup-and-disarm pattern above works independently of that custom define.
pub interface Drop {
mut:
	drop()
}

// Restores terminal modes when initialization fails before ownership is transferred.
// V lacks pub(super), so the guard and its active field are exported for their parent module.
pub struct TerminalInitializationGuard implements Drop {
pub mut:
	active bool
}

pub fn (mut guard TerminalInitializationGuard) drop() {
	if guard.active {
		tui.restore_after_exit() or {}
	}
}

// Drain decoded and unread input before a screen can accept a security-sensitive decision.
//
// Partial control sequences remain quarantined; an unresolved boundary fails after one second.
pub fn discard_pending_terminal_input() ! {
	mut input := BoundaryInput(NativeBoundaryInput{})
	discard_pending_terminal_input_with(mut input)!
}

// A private typed boundary makes the same production loop executable with deterministic clocks
// and input queues. The production adapter below keeps each source dependency API intact.
interface BoundaryInput {
mut:
	now() std_time.Instant
	discard_buffered_input() !event.InputDiscardStatus
	poll(std_time.Duration) !bool
	read() !event.Event
	terminal_input_is_readable() !bool
}

// V's `unix` flag includes Plan 9; exclude it to preserve Rust's cfg(unix) boundary.
fn discard_pending_terminal_input_with(mut input BoundaryInput) ! {
	$if unix && !plan9 {
		_ := input.discard_buffered_input()!
	}
	deadline := input.now().add(std_time.Duration.from_secs(1)) // secs: 1
	for {
		remaining := deadline.saturating_duration_since(input.now())
		if remaining.is_zero() {
			return std_io.Error.new(.timed_out, 'timed out discarding buffered terminal input')
		}
		poll_duration := if remaining < std_time.Duration.from_millis(10) { // millis: 10
			remaining
		} else {
			std_time.Duration.from_millis(10)
		}
		if input.poll(poll_duration)! {
			_ := input.read()!
			continue
		}
		$if unix && !plan9 {
			if input.discard_buffered_input()! != .complete {
				continue
			}
		}
		$if (unix && !plan9) || windows {
			readable := input.terminal_input_is_readable() or {
				if err is std_io.Error && err.kind() == .interrupted {
					continue
				}
				return err
			}
			if readable {
				continue
			}
		}
		return
	}
}

struct NativeBoundaryInput {}

fn (mut input NativeBoundaryInput) now() std_time.Instant {
	return std_time.Instant.now()
}

fn (mut input NativeBoundaryInput) discard_buffered_input() !event.InputDiscardStatus {
	return event.discard_buffered_input()
}

fn (mut input NativeBoundaryInput) poll(timeout std_time.Duration) !bool {
	return event.poll(timeout)
}

fn (mut input NativeBoundaryInput) read() !event.Event {
	return event.read()
}

fn (mut input NativeBoundaryInput) terminal_input_is_readable() !bool {
	return terminal_input_is_readable()
}

// Check Crossterm's terminal input source without consuming input or changing descriptor flags.
// On Windows, check the same console input queue consumed by Crossterm.
// V has no pub(super) visibility. This native helper is exported for its eventual parent module;
// Windows callers should keep it private as in the Rust source.
pub fn terminal_input_is_readable() !bool {
	$if (unix && !plan9) || windows {
		return native_readability_result(C.codex_input_boundary_terminal_readable())
	} $else {
		return std_io.Error.new(.unsupported, 'native terminal input querying is unavailable on this platform')
	}
}

fn native_readability_result(result C.CodexInputBoundaryReading) !bool {
	match result.error_type {
		0 { return result.readable != 0 }
		1 {
			return std_io.Error.new(.other, 'terminal input poll failed with events 0x${result.events:x}')
		}
		2 {
			return std_io.Error.new(.other, 'terminal input handle is unavailable')
		}
		else {
			// The fixed native buffer lives through this copy. Error messages become owned V
			// strings, preserving io::Error's ownership rather than borrowing strerror storage.
			message := unsafe { (&char(&result.message[0])).vstring() }
			kind := match result.error_kind {
				1 { std_io.ErrorKind.interrupted }
				2 { std_io.ErrorKind.not_found }
				3 { std_io.ErrorKind.permission_denied }
				4 { std_io.ErrorKind.would_block }
				5 { std_io.ErrorKind.invalid_input }
				6 { std_io.ErrorKind.broken_pipe }
				else { std_io.ErrorKind.other }
			}
			// Rust's raw_os_error is signed i32, including Windows codes with the high bit set.
			return std_io.Error.from_native(kind, int(i32(result.error_code)), message)
		}
	}
}
