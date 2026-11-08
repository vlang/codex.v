module std_fs

import os
import encoding.utf8
import std_path

// STUB: std::fs::read_to_string reads real files and rejects non-UTF-8 contents.
// PathBuf is an owned string at V's existing native-path boundary.
pub fn read_to_string(path &std_path.Path) !string {
	path_buf := path.to_path_buf()
	if path_buf.contains('\x00') {
		return error('path contains a NUL byte')
	}
	contents := os.read_file(path_buf)!
	if !utf8.validate(contents.str, contents.len) {
		return error('stream did not contain valid UTF-8')
	}
	return contents
}
