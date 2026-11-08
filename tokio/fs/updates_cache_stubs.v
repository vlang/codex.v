module fs

import os
import std_path

// STUB: tokio::fs::create_dir_all preserves actual recursive filesystem effects.
// V awaits this operation synchronously; Tokio's blocking-pool scheduling is absent.
pub fn create_dir_all(path &std_path.Path) ! {
	path_buf := path.to_path_buf()
	if path_buf.contains('\x00') {
		return error('path contains a NUL byte')
	}
	if path_buf.len == 0 || os.is_dir(path_buf.clone()) {
		return
	}
	if parent := path.parent() {
		create_dir_all(&parent)!
	}
	os.mkdir(path_buf.clone()) or {
		if os.is_dir(path_buf.clone()) {
			return
		}
		return err
	}
}

// STUB: tokio::fs::write consumes its PathBuf and String arguments, performs the
// real create/truncate/write, and propagates errors. Scheduling is synchronous.
pub fn write(path string, contents string) ! {
	if path.contains('\x00') {
		return error('path contains a NUL byte')
	}
	os.write_file(path, contents)!
}
