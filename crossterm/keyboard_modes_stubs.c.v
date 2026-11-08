module crossterm

import os
import strings

#include <stdio.h>

// STUB: crossterm::execute!'s ordered command queue followed by one stdout flush.
// Command and the single-command execute API remain owned by terminal_title_stubs.c.v.
// Non-stdout writers are untranslated and fail explicitly. Windows retains the
// source queue's pre-WinAPI flush and immediate error propagation.
pub fn execute_commands(mut output os.File, commands []Command) ! {
	if output.fd != 1 {
		return error('crossterm execute stub supports only stdout')
	}
	// Borrow array elements explicitly: V interfaces are ownership-bearing even
	// when each concrete keyboard command contains only Rust Copy data.
	for index in 0 .. commands.len {
		command := &commands[index]
		$if windows {
			if !command.is_ansi_code_supported() {
				if C.fflush(C.stdout) != 0 {
					return os.last_error()
				}
				command.execute_winapi()!
				continue
			}
		}
		mut encoded := strings.new_builder(32)
		command.write_ansi(mut encoded)!
		output.write_string(encoded.str())!
	}
	if C.fflush(C.stdout) != 0 {
		return os.last_error()
	}
}
