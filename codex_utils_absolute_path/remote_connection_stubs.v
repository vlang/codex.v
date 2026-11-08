module codex_utils_absolute_path

// STUB: AbsolutePathBuf::display delegates to std::path::Path::display in Rust.
// V string formatting needs an owned string, allocated from the borrowed path.
pub fn (path &AbsolutePathBuf) display() string {
	return path.path.clone()
}
