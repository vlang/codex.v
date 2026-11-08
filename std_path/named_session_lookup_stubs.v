module std_path

// STUB: std::path::Path::starts_with compares lexical path components, so a
// sibling such as sessions-old cannot match the sessions directory prefix.
pub fn (path &Path) starts_with(base &Path) bool {
	left := path_components(path)
	right := path_components(base)
	if left.len < right.len {
		return false
	}
	for index in 0 .. right.len {
		if left[index].kind != right[index].kind {
			return false
		}
		if left[index].kind == .root {
			continue
		}
		$if windows {
			if left[index].kind == .prefix {
				if !windows_prefix_equal(path, &left[index].prefix, base, &right[index].prefix) {
					return false
				}
				continue
			}
		}
		if (*path.source)[left[index].start..left[index].end] != (*base.source)[right[index].start..right[index].end] {
			return false
		}
	}
	return true
}
