module terminal_stderr

import std_io
import sync

$if macos {
	#include <stdio.h>
	#include <unistd.h>
	#include "@VMODROOT/codex_tui/tui/terminal_stderr/terminal_stderr_test_native.h"
}

fn C.tmpfile() &C.FILE
fn C.write(i32, voidptr, usize) isize

@[typedef]
struct C.CodexStderrTestPty {
	master i32
	slave  i32
}

fn C.codex_stderr_test_open_pty() C.CodexStderrTestPty
fn C.codex_stderr_test_pty_read(i32, &u8, usize, i32) isize

// Rust's serial_test annotations serialize tests that mutate descriptor 2.
const capture_mutex = sync.new_mutex()
const write_mutex = sync.new_mutex()

struct CapturedStderr implements Drop {
mut:
	saved_stderr i32 = -1
}

fn CapturedStderr.start(file &C.FILE) !CapturedStderr {
	$if macos {
		// SAFETY: dup returns a newly owned file descriptor on success.
		mut saved_stderr := C.dup(2)
		if saved_stderr == -1 {
			return last_os_error()
		}
		// SAFETY: saved_stderr is a fresh descriptor returned by dup above.
		defer {
			if saved_stderr != -1 {
				C.close(saved_stderr)
			}
		}
		// SAFETY: both descriptors are valid for the duration of this call.
		if C.dup2(C.fileno(file), 2) == -1 {
			return last_os_error()
		}
		capture := CapturedStderr{ saved_stderr: saved_stderr }
		saved_stderr = -1
		return capture
	} $else {
		return CapturedStderr{}
	}
}

fn (mut capture CapturedStderr) drop() {
	$if macos {
		if capture.saved_stderr != -1 {
			// SAFETY: saved_stderr remains owned for the duration of this call.
			C.dup2(capture.saved_stderr, 2)
			C.close(capture.saved_stderr)
			capture.saved_stderr = -1
		}
	}
}

fn write_stderr(message &string) ! {
	$if macos {
		mut mutex := unsafe { write_mutex }
		mutex.lock()
		defer { mutex.unlock() }
		mut written := 0
		for written < message.len {
			count := unsafe { C.write(2, message.str + written, usize(message.len - written)) }
			if count == -1 {
				if C.codex_terminal_stderr_errno() == C.EINTR {
					continue
				}
				return last_os_error()
			}
			if count == 0 {
				return error('failed to write the whole stderr buffer')
			}
			written += int(count)
		}
		// Rust Stderr is unbuffered. Direct descriptor writes likewise need no flush.
	}
}

fn capture_file() !&C.FILE {
	$if macos {
		file := C.tmpfile()
		if file == unsafe { nil } {
			return last_os_error()
		}
		return file
	} $else {
		return error('these descriptor capture tests require macOS')
	}
}

fn rewind_and_read(file &C.FILE) string {
	$if macos {
		assert C.fseek(file, 0, C.SEEK_SET) == 0
		mut bytes := []u8{len: 65536}
		length := C.fread(bytes.data, 1, usize(bytes.len), file)
		assert C.ferror(file) == 0
		return bytes[..int(length)].bytestr()
	} $else {
		return ''
	}
}

fn test_suppresses_stderr_only_while_terminal_is_owned() {
	$if macos {
		mut mutex := unsafe { capture_mutex }
		mutex.lock()
		defer { mutex.unlock() }
		output := capture_file() or { panic(err.msg()) }
		defer { C.fclose(output) }
		mut capture := CapturedStderr.start(output) or { panic(err.msg()) }
		defer { capture.drop() }
		mut guard := TerminalStderrGuard.install_suppression() or { panic(err.msg()) }
		defer { guard.drop() }
		active_message := 'hidden while active\n'
		write_stderr(&active_message) or { panic(err.msg()) }
		pause() or { panic(err.msg()) }
		paused_message := 'visible while paused\n'
		write_stderr(&paused_message) or { panic(err.msg()) }
		resume() or { panic(err.msg()) }
		resumed_message := 'hidden after resume\n'
		write_stderr(&resumed_message) or { panic(err.msg()) }
		finish() or { panic(err.msg()) }
		finished_message := 'visible after finish\n'
		write_stderr(&finished_message) or { panic(err.msg()) }
		guard.recover_after_caught_panic() or { panic(err.msg()) }
		panic_message := 'hidden after caught panic\n'
		write_stderr(&panic_message) or { panic(err.msg()) }
		finish() or { panic(err.msg()) }
		recovered_message := 'visible after recovered ownership\n'
		write_stderr(&recovered_message) or { panic(err.msg()) }
		capture.drop()
		captured := rewind_and_read(output)
		assert captured == 'visible while paused\nvisible after finish\nvisible after recovered ownership\n'
	}
}

fn test_preserves_stderr_when_already_redirected() {
	$if macos {
		mut mutex := unsafe { capture_mutex }
		mutex.lock()
		defer { mutex.unlock() }
		output := capture_file() or { panic(err.msg()) }
		defer { C.fclose(output) }
		mut capture := CapturedStderr.start(output) or { panic(err.msg()) }
		defer { capture.drop() }
		mut guard := TerminalStderrGuard.install() or { panic(err.msg()) }
		defer { guard.drop() }
		message := 'visible while redirected\n'
		write_stderr(&message) or { panic(err.msg()) }
		capture.drop()
		captured := rewind_and_read(output)
		assert captured == 'visible while redirected\n'
	}
}

struct StateSnapshot {
	owner_active bool
	stderr_saved bool
}

fn state_snapshot() StateSnapshot {
	$if macos {
		mut state := lock_state() or { panic(err.msg()) }
		defer { state.mutex.unlock() }
		return StateSnapshot{ owner_active: state.owner_active, stderr_saved: state.saved_stderr != -1 }
	} $else {
		return StateSnapshot{}
	}
}

fn test_duplicate_install_and_repeated_phase_calls_preserve_the_owner() {
	$if macos {
		mut mutex := unsafe { capture_mutex }
		mutex.lock()
		defer { mutex.unlock() }
		output := capture_file() or { panic(err.msg()) }
		defer { C.fclose(output) }
		mut capture := CapturedStderr.start(output) or { panic(err.msg()) }
		defer { capture.drop() }
		mut guard := TerminalStderrGuard.install_suppression() or { panic(err.msg()) }
		defer { guard.drop() }
		mut rejected := false
		TerminalStderrGuard.install_suppression() or {
			assert err is std_io.Error
			if err is std_io.Error {
				assert err.kind() == .already_exists
			}
			assert err.msg() == 'terminal stderr suppression is already active'
			rejected = true
			TerminalStderrGuard{}
		}
		assert rejected
		assert state_snapshot() == StateSnapshot{ owner_active: true, stderr_saved: true }
		pause() or { panic(err.msg()) }
		pause() or { panic(err.msg()) }
		assert state_snapshot() == StateSnapshot{ owner_active: true, stderr_saved: false }
		resume() or { panic(err.msg()) }
		resume() or { panic(err.msg()) }
		assert state_snapshot() == StateSnapshot{ owner_active: true, stderr_saved: true }
		finish() or { panic(err.msg()) }
		finish() or { panic(err.msg()) }
		pause() or { panic(err.msg()) }
		resume() or { panic(err.msg()) }
		assert state_snapshot() == StateSnapshot{}
		guard.drop()
		guard.drop()
		assert !guard.active
		message := 'visible after idempotent cleanup\n'
		write_stderr(&message) or { panic(err.msg()) }
		assert rewind_and_read(output) == message
	}
}

fn transfer_guard(guard TerminalStderrGuard) TerminalStderrGuard {
	return guard
}

fn test_owned_guard_transfer_and_drop_restore_actual_stderr() {
	$if macos {
		mut mutex := unsafe { capture_mutex }
		mutex.lock()
		defer { mutex.unlock() }
		output := capture_file() or { panic(err.msg()) }
		defer { C.fclose(output) }
		mut capture := CapturedStderr.start(output) or { panic(err.msg()) }
		defer { capture.drop() }
		mut guard := transfer_guard(TerminalStderrGuard.install_suppression() or { panic(err.msg()) })
		defer { guard.drop() }
		assert state_snapshot() == StateSnapshot{ owner_active: true, stderr_saved: true }
		mut message := 'heap-owned stderr message remains reusable\n'
		$if ownership ? {
			message = message.to_owned()
		}
		write_stderr(&message) or { panic(err.msg()) }
		write_stderr(&message) or { panic(err.msg()) }
		assert rewind_and_read(output) == ''
		guard.drop()
		write_stderr(&message) or { panic(err.msg()) }
		write_stderr(&message) or { panic(err.msg()) }
		assert rewind_and_read(output) == message + message
		assert message == 'heap-owned stderr message remains reusable\n'
		assert state_snapshot() == StateSnapshot{}
	}
}

fn active_guard_scope(fail bool) ! {
	$if macos {
		guard := TerminalStderrGuard.install_suppression()!
		assert guard.active
		if fail {
			return error('scope exited through an error')
		}
	}
}

fn test_ownership_scope_drop_restores_stderr_on_success_and_error() {
	$if macos && ownership ? {
		mut mutex := unsafe { capture_mutex }
		mutex.lock()
		defer { mutex.unlock() }
		output := capture_file() or { panic(err.msg()) }
		defer { C.fclose(output) }
		mut capture := CapturedStderr.start(output) or { panic(err.msg()) }
		defer { capture.drop() }
		active_guard_scope(false) or { panic(err.msg()) }
		assert state_snapshot() == StateSnapshot{}
		mut failed := false
		active_guard_scope(true) or {
			assert err.msg() == 'scope exited through an error'
			failed = true
		}
		assert failed
		assert state_snapshot() == StateSnapshot{}
		message := 'visible after automatic ownership cleanup\n'
		write_stderr(&message) or { panic(err.msg()) }
		assert rewind_and_read(output) == message
	}
}

fn test_inactive_guard_recovery_keeps_redirected_stderr_visible() {
	$if macos {
		mut mutex := unsafe { capture_mutex }
		mutex.lock()
		defer { mutex.unlock() }
		output := capture_file() or { panic(err.msg()) }
		defer { C.fclose(output) }
		mut capture := CapturedStderr.start(output) or { panic(err.msg()) }
		defer { capture.drop() }
		mut guard := TerminalStderrGuard.install() or { panic(err.msg()) }
		defer { guard.drop() }
		guard.recover_after_caught_panic() or { panic(err.msg()) }
		guard.recover_after_caught_panic() or { panic(err.msg()) }
		assert !guard.active
		assert state_snapshot() == StateSnapshot{}
		message := 'visible after inactive recovery\n'
		write_stderr(&message) or { panic(err.msg()) }
		assert rewind_and_read(output) == message
	}
}

fn test_failed_dup_preserves_the_native_error_and_unclaimed_state() {
	$if macos {
		mut mutex := unsafe { capture_mutex }
		mutex.lock()
		defer { mutex.unlock() }
		saved := C.dup(2)
		assert saved >= 0
		defer {
			C.dup2(saved, 2)
			C.close(saved)
		}
		assert C.close(2) == 0
		mut failed := false
		TerminalStderrGuard.install_suppression() or {
			assert err is std_io.Error
			assert err.code() == C.EBADF
			bad_fd := int(C.EBADF)
			assert err.msg().ends_with('(os error ${bad_fd})')
			failed = true
			TerminalStderrGuard{}
		}
		assert failed
		assert state_snapshot() == StateSnapshot{}
	}
}

fn test_installs_only_when_stdout_and_stderr_share_the_same_real_terminal() {
	$if macos {
		mut mutex := unsafe { capture_mutex }
		mutex.lock()
		defer { mutex.unlock() }
		first := C.codex_stderr_test_open_pty()
		assert first.master >= 0 && first.slave >= 0
		defer {
			C.close(first.master)
			C.close(first.slave)
		}
		second := C.codex_stderr_test_open_pty()
		assert second.master >= 0 && second.slave >= 0
		defer {
			C.close(second.master)
			C.close(second.slave)
		}
		C.fflush(C.stdout)
		saved_stdout := C.dup(1)
		saved_stderr := C.dup(2)
		assert saved_stdout >= 0 && saved_stderr >= 0
		defer {
			C.fflush(C.stdout)
			C.dup2(saved_stdout, 1)
			C.dup2(saved_stderr, 2)
			C.close(saved_stdout)
			C.close(saved_stderr)
		}
		assert C.dup2(first.slave, 1) >= 0
		assert C.dup2(second.slave, 2) >= 0
		assert !stderr_targets_stdout_terminal()
		mut separate_guard := TerminalStderrGuard.install() or { panic(err.msg()) }
		defer { separate_guard.drop() }
		assert !separate_guard.active
		assert state_snapshot() == StateSnapshot{}
		assert C.dup2(first.slave, 2) >= 0
		assert stderr_targets_stdout_terminal()
		mut shared_guard := TerminalStderrGuard.install() or { panic(err.msg()) }
		defer { shared_guard.drop() }
		assert shared_guard.active
		assert state_snapshot() == StateSnapshot{ owner_active: true, stderr_saved: true }
		hidden := 'suppressed framework diagnostic'
		write_stderr(&hidden) or { panic(err.msg()) }
		mut bytes := []u8{len: 128}
		assert C.codex_stderr_test_pty_read(first.master, bytes.data, usize(bytes.len), 0) == 0
		pause() or { panic(err.msg()) }
		visible := 'diagnostic while terminal released'
		write_stderr(&visible) or { panic(err.msg()) }
		count := C.codex_stderr_test_pty_read(first.master, bytes.data, usize(bytes.len), 1000)
		assert count == visible.len
		assert bytes[..int(count)].bytestr() == visible
		resume() or { panic(err.msg()) }
		write_stderr(&hidden) or { panic(err.msg()) }
		assert C.codex_stderr_test_pty_read(first.master, bytes.data, usize(bytes.len), 0) == 0
		shared_guard.drop()
		assert state_snapshot() == StateSnapshot{}
		assert stderr_targets_stdout_terminal()
	}
}

fn test_non_macos_lifecycle_remains_a_no_op() {
	$if !macos {
		mut guard := TerminalStderrGuard.install() or { panic(err.msg()) }
		defer { guard.drop() }
		assert !guard.active
		pause() or { panic(err.msg()) }
		resume() or { panic(err.msg()) }
		finish() or { panic(err.msg()) }
		guard.recover_after_caught_panic() or { panic(err.msg()) }
		assert !guard.active
	}
}
