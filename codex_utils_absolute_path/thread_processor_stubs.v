module codex_utils_absolute_path

import os

// STUB: AbsolutePathBuf::relative_to_current_dir is owned by codex-utils-absolute-path.
pub fn AbsolutePathBuf.relative_to_current_dir(path string) !AbsolutePathBuf {
	resolved := if os.is_abs_path(path.clone()) {
		os.norm_path(path)
	} else {
		os.abs_path(path)
	}
	if !os.is_abs_path(resolved.clone()) {
		return error('path is not absolute after resolving against the current directory: ${path}')
	}
	return AbsolutePathBuf{ path: resolved }
}
