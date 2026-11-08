module terminal_stderr

import os
import std_io

#include "@VMODROOT/codex_tui/tui/terminal_stderr/terminal_stderr_native.h"

fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.codex_terminal_stderr_same_terminal() i32
fn C.codex_terminal_stderr_open_devnull() i32
fn C.codex_terminal_stderr_errno() i32

fn last_os_error() IError {
	$if macos {
		code := C.codex_terminal_stderr_errno()
		kind := match code {
			C.EINTR { std_io.ErrorKind.interrupted }
			C.ENOENT { std_io.ErrorKind.not_found }
			C.EACCES, C.EPERM { std_io.ErrorKind.permission_denied }
			C.EAGAIN { std_io.ErrorKind.would_block }
			C.EINVAL { std_io.ErrorKind.invalid_input }
			C.EPIPE { std_io.ErrorKind.broken_pipe }
			C.EEXIST { std_io.ErrorKind.already_exists }
			else { std_io.ErrorKind.other }
		}
		return std_io.Error.from_native(kind, int(code), os.posix_get_error_msg(int(code)))
	} $else {
		return std_io.Error.new(.unsupported, 'native stderr suppression is only available on macOS')
	}
}
