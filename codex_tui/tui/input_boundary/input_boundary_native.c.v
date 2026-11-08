module input_boundary

#include "@VMODROOT/codex_tui/tui/input_boundary/input_boundary_native.h"

@[typedef]
struct C.CodexInputBoundaryReading {
	readable   int
	error_type int
	error_kind int
	error_code u32
	events     u16
	message    [1024]char
}

fn C.codex_input_boundary_terminal_readable() C.CodexInputBoundaryReading

fn C.codex_input_boundary_poll_descriptor(int) C.CodexInputBoundaryReading

fn C.codex_input_boundary_read_poll_events(int, u16) C.CodexInputBoundaryReading

fn C.codex_input_boundary_open_readonly(&char) int

fn C.codex_input_boundary_last_os_error() C.CodexInputBoundaryReading
