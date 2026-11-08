module size_monitor

import std_io
import os

#include "@VMODROOT/codex_tui/tui/size_monitor/size_monitor_native.h"

@[typedef]
struct C.CodexSizeMonitorWorker {}

fn C.codex_size_monitor_init(&C.CodexSizeMonitorWorker) int
fn C.codex_size_monitor_start(&C.CodexSizeMonitorWorker, fn (voidptr) voidptr, voidptr) int
fn C.codex_size_monitor_park(&C.CodexSizeMonitorWorker, i64)
fn C.codex_size_monitor_unpark(&C.CodexSizeMonitorWorker)
fn C.codex_size_monitor_destroy(&C.CodexSizeMonitorWorker)

struct MonitorWorker {
	native &C.CodexSizeMonitorWorker = unsafe { nil }
}

fn MonitorWorker.new() !MonitorWorker {
	native := &C.CodexSizeMonitorWorker{}
	code := C.codex_size_monitor_init(native)
	if code != 0 {
		return monitor_io_error(code)
	}
	return MonitorWorker{ native: native }
}

fn (worker &MonitorWorker) start(context &WorkerContext) ! {
	code := C.codex_size_monitor_start(worker.native, run_size_monitor, context)
	if code != 0 {
		return monitor_io_error(code)
	}
}

fn (worker &MonitorWorker) park_timeout(nanos i64) {
	C.codex_size_monitor_park(worker.native, nanos)
}

fn (worker &MonitorWorker) unpark() {
	if worker.native != unsafe { nil } { C.codex_size_monitor_unpark(worker.native) }
}

fn (worker &MonitorWorker) destroy() {
	if worker.native != unsafe { nil } { C.codex_size_monitor_destroy(worker.native) }
}

// std::thread::Builder::spawn returns the native io::Error, including its diagnostic
// and errno. The same boundary handles the native parking primitive's construction.
fn monitor_io_error(code int) std_io.Error {
	$if unix && !plan9 {
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
		return std_io.Error.from_native(kind, code, os.get_error_msg(code))
	} $else {
		return std_io.Error.from_native(.other, code, os.get_error_msg(code))
	}
}
