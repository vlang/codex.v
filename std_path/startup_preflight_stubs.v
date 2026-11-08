module std_path

import std_io

#include "@VMODROOT/std_path/startup_preflight_native.h"

// STUB: Native stat adapter preserves i32 C integer widths in V3 generation.
fn C.codex_preflight_stat(&char, &i32, &i32) i32

// STUB: Path::try_exists follows links and returns false only for NotFound.
pub fn (path &Path) try_exists() !bool {
	bytes := path.to_path_buf()
	if bytes.contains('\x00') {
		return std_io.Error.new(.invalid_input, 'path contains a NUL byte')
	}
	mut directory := i32(0)
	mut kind := i32(0)
	code := C.codex_preflight_stat(bytes.str, &directory, &kind)
	if code == 0 {
		return true
	}
	if kind == 1 {
		return false
	}
	error_kind := if kind == 2 {
		std_io.ErrorKind.invalid_input
	} else if kind == 3 {
		std_io.ErrorKind.permission_denied
	} else {
		std_io.ErrorKind.other
	}
	return std_io.Error.from_native(error_kind, int(code), 'could not inspect path')
}
