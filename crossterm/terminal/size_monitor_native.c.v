module terminal

import std_io

#include "@VMODROOT/crossterm/terminal/size_monitor_native.h"

// STUB: Copy C geometry output for the eventual Crossterm Unix ioctl adapter.
@[typedef]
struct C.CodexWindowSize {
mut:
	rows    u16
	columns u16
	width   u16
	height  u16
}

// STUB: the source's /dev/tty open with stdout fallback and TIOCGWINSZ result.
fn C.codex_window_size(&C.CodexWindowSize) int

// STUB: copy errno's diagnostic before another OS operation changes it.
fn C.codex_window_size_error(int) &char

// STUB: allocation-free native geometry adapter.
type NativeWindowSize = C.CodexWindowSize

// STUB: platform-shaped window_size call; never invokes tput.
fn native_window_size(mut sampled NativeWindowSize) int {
	return C.codex_window_size(&sampled)
}

// STUB: std::io::Error::last_os_error's owned native diagnostic.
fn native_window_size_error(code int) string {
	return unsafe { cstring_to_vstring(C.codex_window_size_error(code)) }
}

// STUB: std::io::Error::last_os_error classifies the observed Unix error categories.
fn native_window_size_error_kind(code int) std_io.ErrorKind {
	$if unix {
		return match code {
			C.EINTR { .interrupted }
			C.ENOENT { .not_found }
			C.EACCES, C.EPERM { .permission_denied }
			C.EAGAIN { .would_block }
			C.EINVAL { .invalid_input }
			C.EPIPE { .broken_pipe }
			C.EEXIST { .already_exists }
			else { .other }
		}
	} $else {
		return .unsupported
	}
}
