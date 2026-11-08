module std_fs

import std_path
import std_io

#include "@VMODROOT/std_path/startup_preflight_native.h"

// STUB: std::fs::Metadata, retaining the file type observed by startup_preflight.rs.
pub struct Metadata {
	directory bool
}

// STUB: std::fs::Metadata::is_dir.
pub fn (metadata &Metadata) is_dir() bool {
	return metadata.directory
}

// STUB: Native stat adapter preserves i32 C integer widths in V3 generation.
fn C.codex_preflight_stat(&char, &i32, &i32) i32

// STUB: std::fs::metadata follows symlinks and preserves NotFound versus ambiguous errors.
pub fn metadata(path &std_path.Path) !Metadata {
	bytes := path.to_path_buf()
	if bytes.contains('\x00') {
		return std_io.Error.new(.invalid_input, 'path contains a NUL byte')
	}
	mut directory := i32(0)
	mut kind := i32(0)
	code := C.codex_preflight_stat(bytes.str, &directory, &kind)
	if code == 0 {
		return Metadata{ directory: directory != 0 }
	}
	error_kind := if kind == 1 {
		std_io.ErrorKind.not_found
	} else if kind == 2 {
		std_io.ErrorKind.invalid_input
	} else if kind == 3 {
		std_io.ErrorKind.permission_denied
	} else {
		std_io.ErrorKind.other
	}
	return std_io.Error.from_native(error_kind, int(code), 'could not inspect path')
}
