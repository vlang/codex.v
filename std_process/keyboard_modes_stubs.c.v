module std_process

import os
import std_io
import std_path

#include "@VMODROOT/std_process/keyboard_modes_native.h"

// STUB: native subprocess bridge for std::process::Command::output. The bridge
// starts the executable directly, inherits the prepared environment, supplies
// null stdin/stderr, captures stdout, and distinguishes spawn errors from status.
fn C.codex_keyboard_process_output(executable &char, argv &&char, envp &&char, stdin_null bool, stderr_null bool, bytes &&u8, length &usize, exit_code &i32) i32

// STUB: the std::process::Stdio modes observed by keyboard_modes.rs.
pub enum Stdio {
	inherit
	null
}

// STUB: std::process::ExitStatus preserves unsuccessful process exits and signals.
pub struct ExitStatus {
	status i32
}

// STUB: std::process::ExitStatus::success.
pub fn (status ExitStatus) success() bool {
	return status.status == 0
}

// STUB: std::process::Output owns captured stdout bytes and the typed exit status.
// No caller observes stderr; it is explicitly configured as Stdio::null.
pub struct Output {
pub:
	status ExitStatus
	stdout string
}

// STUB: std::process::Command's typed builder state for automatic terminal probes.
pub struct Command {
mut:
	executable  string
	arguments   []string
	environment map[string]string
	stdin_mode  Stdio
	stderr_mode Stdio
}

// STUB: std::process::Command::new copies a borrowed native executable into the
// owned Command, matching Rust's AsRef<OsStr> allocation boundary.
pub fn Command.new(executable &std_path.PathBuf) Command {
	view := executable.as_path()
	return Command{ executable: view.to_path_buf() }
}

// STUB: Command::new's owned PathBuf AsRef<OsStr> instantiation. Rust copies
// into Command then drops the supplied path; V names the generic owned overload.
pub fn Command.new_owned(executable std_path.PathBuf) Command {
	return Command.new(&executable)
}

// STUB: std::process::Command::args consumes the caller's argument list.
pub fn (mut command Command) args(arguments []string) {
	command.arguments << arguments
}

// STUB: std::process::Command::env copies borrowed key/value bytes into its override.
pub fn (mut command Command) env(name &string, value &string) {
	command.environment[name.clone()] = value.clone()
}

// STUB: std::process::Command::stdin retains the configured stdio direction.
pub fn (mut command Command) stdin(mode Stdio) {
	command.stdin_mode = mode
}

// STUB: std::process::Command::stderr retains the configured stdio direction.
pub fn (mut command Command) stderr(mode Stdio) {
	command.stderr_mode = mode
}

// STUB: std::process::Command::output runs the native process without a shell and
// returns I/O failures separately from nonzero exit status, as Rust does.
pub fn (mut command Command) output() !Output {
	if command.executable.contains('\x00') {
		return std_io.Error.new(.invalid_input, 'nul byte found in provided data')
	}
	mut argv := []&char{cap: command.arguments.len + 2}
	argv << command.executable.str
	for argument in command.arguments {
		if argument.contains('\x00') {
			return std_io.Error.new(.invalid_input, 'nul byte found in provided data')
		}
		argv << argument.str
	}
	argv << &char(unsafe { nil })
	mut environment := os.environ()
	for name, value in command.environment {
		if name.contains('\x00') || name.contains('=') || value.contains('\x00') {
			return std_io.Error.new(.invalid_input, 'nul byte found in provided data')
		}
		$if windows {
			// Windows env keys are case-insensitive; PATH replaces an inherited Path.
			for inherited_name in environment.keys() {
				if keyboard_environment_key_compare(&inherited_name, &name) == 0 {
					environment.delete(inherited_name)
				}
			}
		}
		environment[name] = value
	}
	mut entries := []string{cap: environment.len}
	for name, value in environment {
		entries << '${name}=${value}'
	}
	$if windows {
		// CreateProcess's custom Unicode environment block requires sorted keys.
		entries.sort_with_compare(fn (left &string, right &string) int {
			left_name := left.all_before('=')
			right_name := right.all_before('=')
			return keyboard_environment_key_compare(&left_name, &right_name)
		})
	}
	mut envp := []&char{cap: entries.len + 1}
	for entry in entries {
		envp << entry.str
	}
	envp << &char(unsafe { nil })
	mut buffer := &u8(unsafe { nil })
	mut length := usize(0)
	mut exit_code := i32(0)
	code := C.codex_keyboard_process_output(command.executable.str, argv.data, envp.data,
		command.stdin_mode == .null, command.stderr_mode == .null, &buffer, &length, &exit_code)
	defer { unsafe { free(buffer) } }
	if code != 0 {
		return std_io.Error.from_native(.other, int(code), 'terminal helper process failed')
	}
	// The native allocation is released above; copy once into the owned Output.
	stdout := if length == 0 { '' } else { unsafe { buffer.vstring_with_len(int(length)).clone() } }
	return Output{ status: ExitStatus{ status: exit_code }, stdout: stdout }
}

// STUB: Rust's Windows EnvKey ordering uses case-insensitive native Unicode
// comparison. UTF-16 conversion adapts V's UTF-8 Windows environment storage.
fn keyboard_environment_key_compare(left &string, right &string) int {
	$if windows {
		wide_left := left.to_wide()
		wide_right := right.to_wide()
		defer {
			unsafe {
				free(wide_left)
				free(wide_right)
			}
		}
		return int(C.CompareStringOrdinal(wide_left, -1, wide_right, -1, true)) - 2
	} $else {
		return left.compare(*right)
	}
}

// STUB: Windows native Unicode environment-key comparison.
fn C.CompareStringOrdinal(left &u16, left_len i32, right &u16, right_len i32, ignore_case bool) i32
