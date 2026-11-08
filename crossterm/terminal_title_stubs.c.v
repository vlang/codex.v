module crossterm

import os
import strings

#include <stdio.h>

// STUB: crossterm::Command. The untranslated dependency's ANSI formatter maps
// fmt::Write to strings.Builder; write_ansi keeps its fallible result shape.
pub interface Command {
	write_ansi(mut output strings.Builder) !
	execute_winapi() !
	is_ansi_code_supported() bool
}

// STUB: crossterm::execute!, scoped to the stdout ANSI write/flush boundary used
// by terminal_title.rs. Other writers and the wider queue/WinAPI runtime are
// untranslated; reject unsupported writers instead of claiming to flush them.
pub fn execute(mut output os.File, command &Command) ! {
	if output.fd != 1 {
		return error('crossterm execute stub supports only stdout')
	}
	mut encoded := strings.new_builder(256)
	command.write_ansi(mut encoded)!
	output.write_string(encoded.str())!
	if C.fflush(C.stdout) != 0 {
		return os.last_error()
	}
}
