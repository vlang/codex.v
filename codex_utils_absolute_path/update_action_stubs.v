module codex_utils_absolute_path

// STUB: AbsolutePathBuf's derived Clone creates an independent owned path.
pub fn (path &AbsolutePathBuf) clone() AbsolutePathBuf {
	return AbsolutePathBuf{ path: path.path.clone() }
}

// STUB: AbsolutePathBuf::join's borrowed AsRef<Path> boundary, using the
// existing path-normalization stub until codex-utils-absolute-path is ported.
pub fn (path &AbsolutePathBuf) join(child &string) AbsolutePathBuf {
	return resolve_path_against_base(child, &path.path)
}
