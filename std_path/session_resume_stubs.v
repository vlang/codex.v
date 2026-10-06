module std_path

import encoding.utf8
import std_ffi

// STUB: PathBuf's dereferenced Path::to_str borrows validated native UTF-8.
// The existing Copy-equivalent wrapper adapts Rust Option<&str> without moving
// the path's native-byte owner; invalid native bytes remain rejected.
pub fn (path &PathBuf) to_str() std_ffi.BorrowedUtf8 {
	return std_ffi.BorrowedUtf8{ present: utf8.validate(path.bytes.str, path.bytes.len), value: &path.bytes }
}
