module terminal

import std_io

// STUB: crossterm::terminal::WindowSize. All Copy geometry fields retain their source widths.
pub struct WindowSize {
pub:
	rows    u16
	columns u16
	width   u16
	height  u16
}

// STUB: crossterm::terminal::window_size's Unix ioctl boundary from the pinned
// Crossterm revision 45fecb9508105988f42fe6ff0441783ed3717f92. Other terminal
// operations and native Windows geometry remain untranslated.
pub fn window_size() !WindowSize {
	$if unix && !plan9 {
		mut sampled := NativeWindowSize{}
		code := native_window_size(mut sampled)
		if code != 0 {
			return std_io.Error.from_native(native_window_size_error_kind(code), code, native_window_size_error(code))
		}
		return WindowSize{ rows: sampled.rows, columns: sampled.columns, width: sampled.width, height: sampled.height }
	} $else {
		return std_io.Error.new(.unsupported, 'crossterm window-size query is not translated on this platform')
	}
}
