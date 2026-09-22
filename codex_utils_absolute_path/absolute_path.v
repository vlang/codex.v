module codex_utils_absolute_path

import os

// STUB: AbsolutePathBuf is translated here only far enough for protocol ownership and path logic.
pub struct AbsolutePathBuf {
pub:
	path string
}

// STUB: The Rust crate performs stricter platform-aware absolute-path validation.
pub fn from_absolute_path(path &string) !AbsolutePathBuf {
	if !os.is_abs_path(path) {
		return error('path is not absolute: ${path}')
	}
	return AbsolutePathBuf{ path: os.norm_path(path) }
}

// STUB: Preserve the source crate's constructor name for later replacement.
pub fn resolve_path_against_base(path &string, base &string) AbsolutePathBuf {
	return AbsolutePathBuf{ path: os.norm_path(os.join_path(*base, *path)) }
}

// STUB: Borrowed Path conversion belongs to codex-utils-absolute-path.
pub fn (path &AbsolutePathBuf) as_path() string {
	return path.path
}

// STUB: Owned PathBuf conversion belongs to codex-utils-absolute-path.
pub fn (path &AbsolutePathBuf) to_path_buf() string {
	return path.path
}

// STUB: Display formatting belongs to codex-utils-absolute-path.
pub fn (path &AbsolutePathBuf) str() string {
	return path.path
}
