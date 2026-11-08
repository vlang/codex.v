module std_path

// STUB: std::path::Path::parent returns a borrowed lexical parent. The existing
// component scanner preserves leading '.', root, prefix and '..' semantics.
pub fn (path &Path) parent() ?Path {
	components := path_components(path)
	if components.len == 0 || components.last().kind in [.root, .prefix] {
		return none
	}
	if components.len == 1 {
		return Path{ source: path.source, start: path.start, end: path.start }
	}
	return Path{ source: path.source, start: path.start, end: components[components.len - 2].end }
}

// STUB: std::path::Path::file_name returns borrowed OsStr. V returns an owned,
// lossy UTF-8 string at the caller's source to_string_lossy().to_string() boundary.
pub fn (path &Path) file_name() ?string {
	components := path_components(path)
	if components.len == 0 || components.last().kind != .normal {
		return none
	}
	component := components.last()
	view := Path{ source: path.source, start: component.start, end: component.end }
	return view.to_string_lossy()
}

// STUB: Rust Path equality compares normalized lexical components, not the
// raw repeated separators or non-leading '.' retained in path byte storage.
pub fn (path &Path) equals(other &Path) bool {
	left := path_components(path)
	right := path_components(other)
	if left.len != right.len {
		return false
	}
	for i in 0 .. left.len {
		if left[i].kind != right[i].kind {
			return false
		}
		if left[i].kind == .root {
			continue
		}
		$if windows {
			if left[i].kind == .prefix {
				if !windows_prefix_equal(path, &left[i].prefix, other, &right[i].prefix) {
					return false
				}
				continue
			}
		}
		if (*path.source)[left[i].start..left[i].end] != (*other.source)[right[i].start..right[i].end] {
			return false
		}
	}
	return true
}
