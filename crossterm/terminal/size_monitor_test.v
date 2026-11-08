module terminal

$if unix && !plan9 {
	#include "@VMODROOT/crossterm/terminal/size_monitor_test_native.h"
	$if linux {
		#flag -lutil
	}
}

fn C.codex_test_window_size(int, &C.CodexWindowSize, &int) int

fn test_native_window_size_prefers_controlling_tty_and_falls_back_to_stdout() {
	$if unix && !plan9 {
		for mode in [0, 1] {
			mut size := C.CodexWindowSize{}
			mut native_error := 0
			assert C.codex_test_window_size(mode, &size, &native_error) == 0
			assert native_error == 0
			assert WindowSize{ rows: size.rows, columns: size.columns, width: size.width, height: size.height } == WindowSize{ rows: 37, columns: 91, width: 640, height: 480 }
		}
	}
}

fn test_native_window_size_preserves_ioctl_errno_after_fallback() {
	$if unix && !plan9 {
		mut size := C.CodexWindowSize{}
		mut native_error := 0
		assert C.codex_test_window_size(2, &size, &native_error) == 0
		assert native_error == C.EBADF
	}
}
