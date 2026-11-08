module std_path

// STUB: Borrowed std::path::Path view for directive rendering and shell path helpers.
// UTF-8 byte offsets retain Rust's borrowed substring semantics without allocation.
// Unix paths preserve arbitrary bytes; Windows uses UTF-8 rather than WTF-16.
pub struct Path {
	source &string
	start  int
	end    int
}

// STUB: std::path::Path::new borrows its string; this Copy-equivalent view does too.
pub fn Path.new(source &string) Path {
	return Path{ source: source, end: source.len }
}

// STUB: AsRef<Path> returns the same borrowed view in V's Copy-equivalent wrapper.
pub fn (path &Path) as_ref() Path {
	return *path
}

// STUB: std::path::Path::strip_prefix compares normalized components without
// resolving '..'. The returned view preserves internal separators in the remainder.
pub fn (path &Path) strip_prefix(prefix &Path) !Path {
	components := path_components(path)
	prefix_components := path_components(prefix)
	if prefix_components.len > components.len {
		return error('prefix not found')
	}
	for index in 0 .. prefix_components.len {
		left := components[index]
		right := prefix_components[index]
		if left.kind != right.kind {
			return error('prefix not found')
		}
		if left.kind == .root {
			continue
		}
		mut equal := (*path.source)[left.start..left.end] == (*prefix.source)[right.start..right.end]
		$if windows {
			if left.kind == .prefix {
				equal = windows_prefix_equal(path, &left.prefix, prefix, &right.prefix)
			}
		}
		if !equal {
			return error('prefix not found')
		}
	}
	if prefix_components.len == components.len {
		return Path{ source: path.source, start: path.end, end: path.end }
	}
	return Path{ source: path.source, start: components[prefix_components.len].start, end: components.last().end }
}

// STUB: std::path::Path::to_string_lossy returns Cow<str>. V returns an owned
// string; replacing invalid UTF-8 preserves the observed lossy conversion API.
pub fn (path &Path) to_string_lossy() string {
	mut result := []u8{}
	mut index := path.start
	for index < path.end {
		first := (*path.source)[index]
		if first < 0x80 {
			result << first
			index++
			continue
		}
		width := if first >= 0xc2 && first <= 0xdf {
			2
		} else if first >= 0xe0 && first <= 0xef {
			3
		} else if first >= 0xf0 && first <= 0xf4 {
			4
		} else {
			0
		}
		if width == 0 {
			result << [u8(0xef), 0xbf, 0xbd]
			index++
			continue
		}
		mut valid := 1
		for valid < width && index + valid < path.end {
			next := (*path.source)[index + valid]
			if next < 0x80 || next > 0xbf || (valid == 1 && ((first == 0xe0 && next < 0xa0) || (first == 0xed && next >= 0xa0) || (first == 0xf0 && next < 0x90) || (first == 0xf4 && next > 0x8f))) {
				break
			}
			valid++
		}
		if valid == width {
			for offset in 0 .. width {
				result << (*path.source)[index + offset]
			}
		} else {
			result << [u8(0xef), 0xbf, 0xbd]
		}
		index += valid
	}
	return result.bytestr()
}

// STUB: Component discriminants observed by std::path::Path::strip_prefix.
enum PathComponentKind {
	prefix
	root
	cur_dir
	parent_dir
	normal
}

// STUB: Borrowed component offsets retain the original path's separator spelling.
struct PathComponent {
	kind   PathComponentKind
	start  int
	end    int
	prefix WindowsPrefix
}

// STUB: std's platform-specific separator predicate, including verbatim Windows paths.
fn path_is_separator(character u8, verbatim bool) bool {
	$if windows {
		return character == `\\` || (character == `/` && !verbatim)
	} $else {
		return character == `/`
	}
}

// STUB: std::path::Path::components ignores repeated separators and nonleading '.',
// retains a leading '.', and does not resolve '..'. Verbatim Windows paths retain '.'.
fn path_components(path &Path) []PathComponent {
	mut components := []PathComponent{}
	mut index := path.start
	mut verbatim := false
	mut implicit_root := false
	$if windows {
		parsed := parse_windows_prefix(path)
		verbatim = parsed.kind in [.verbatim, .verbatim_unc, .verbatim_disk]
		implicit_root = parsed.kind != .none && parsed.kind != .disk
		if parsed.length > 0 {
			components << PathComponent{ kind: .prefix, start: index, end: index + parsed.length, prefix: parsed }
			index += parsed.length
		}
	}
	// Rust determines a physical root with either Windows separator before
	// switching the body scanner to verbatim separators.
	physical_root := index < path.end && path_is_separator((*path.source)[index], false)
	if physical_root {
		components << PathComponent{ kind: .root, start: index, end: index + 1 }
		index++
	} else if implicit_root && !verbatim {
		components << PathComponent{ kind: .root, start: index, end: index }
	}
	body_start := index
	for index < path.end {
		if path_is_separator((*path.source)[index], verbatim) {
			index++
			continue
		}
		start := index
		for index < path.end && !path_is_separator((*path.source)[index], verbatim) {
			index++
		}
		component := (*path.source)[start..index]
		leading_cur_dir := start == body_start && !physical_root && !implicit_root
		if component == '.' && !leading_cur_dir && !verbatim {
			continue
		}
		kind := if component == '.' {
			PathComponentKind.cur_dir
		} else if component == '..' {
			PathComponentKind.parent_dir
		} else {
			PathComponentKind.normal
		}
		components << PathComponent{ kind: kind, start: start, end: index }
	}
	return components
}

// STUB: std's Windows Prefix discriminants preserve semantic prefix equality,
// including slash spelling differences in non-verbatim UNC and device prefixes.
enum WindowsPrefixKind {
	none
	disk
	verbatim
	verbatim_unc
	verbatim_disk
	unc
	device
}

// STUB: std::path::Prefix borrows server/share/device slices. Offsets are into
// the original source; length is relative to the borrowed Path view.
struct WindowsPrefix {
	kind         WindowsPrefixKind
	length       int
	first_start  int
	first_end    int
	second_start int
	second_end   int
}

// STUB: std's Windows prefix parser distinguishes drive, UNC, device, and verbatim
// prefixes and reports implicit roots. Offsets are relative to the supplied view.
fn windows_prefix(path &Path) (int, bool, bool) {
	parsed := parse_windows_prefix(path)
	return parsed.length, parsed.kind != .none && parsed.kind != .disk, parsed.kind in [
		.verbatim,
		.verbatim_unc,
		.verbatim_disk,
	]
}

// STUB: std's Windows prefix equality compares parsed fields, folding ASCII drive
// letters only. Marker slash spelling is immaterial for UNC and device prefixes.
fn windows_prefix_equal(left_path &Path, left &WindowsPrefix, right_path &Path, right &WindowsPrefix) bool {
	if left.kind != right.kind {
		return false
	}
	left_first := (*left_path.source)[left.first_start..left.first_end]
	right_first := (*right_path.source)[right.first_start..right.first_end]
	if left.kind in [.disk, .verbatim_disk] {
		return (left_first[0] & u8(0xdf)) == (right_first[0] & u8(0xdf))
	}
	return left_first == right_first
		&& (*left_path.source)[left.second_start..left.second_end] == (*right_path.source)[right.second_start..right.second_end]
}

// STUB: Windows std::path parses normalized marker bytes while requiring the
// verbatim marker itself to contain backslashes. A verbatim drive prefix must
// end at the drive colon or be followed by a backslash, not arbitrary text.
fn parse_windows_prefix(path &Path) WindowsPrefix {
	length := path.end - path.start
	if length >= 2 && path_is_separator((*path.source)[path.start], false) && path_is_separator((*path.source)[path.start + 1], false) {
		if length >= 4 && (*path.source)[path.start..path.start + 4] == '\\\\?\\' {
			if length >= 8 && (*path.source)[path.start + 4..path.start + 8] == 'UNC\\' {
				return windows_unc_prefix(path, 8, true)
			}
			if length >= 6 && (*path.source)[path.start + 4].is_letter() && (*path.source)[path.start + 5] == `:` && (length == 6 || (*path.source)[path.start + 6] == `\\`) {
				return WindowsPrefix{ kind: .verbatim_disk, length: 6, first_start: path.start + 4, first_end: path.start + 5 }
			}
			first_end := windows_next_component_end(path, path.start + 4, true)
			return WindowsPrefix{ kind: .verbatim, length: first_end - path.start, first_start: path.start + 4, first_end: first_end }
		}
		if length >= 4 && (*path.source)[path.start + 2] == `.` && path_is_separator((*path.source)[path.start + 3], false) {
			first_end := windows_next_component_end(path, path.start + 4, false)
			return WindowsPrefix{ kind: .device, length: first_end - path.start, first_start: path.start + 4, first_end: first_end }
		}
		return windows_unc_prefix(path, 2, false)
	}
	if length >= 2 && (*path.source)[path.start + 1] == `:` && (*path.source)[path.start].is_letter() {
		return WindowsPrefix{ kind: .disk, length: 2, first_start: path.start, first_end: path.start + 1 }
	}
	return WindowsPrefix{}
}

// STUB: std's UNC prefixes borrow a server and share. Non-verbatim prefixes
// require both fields; verbatim UNC retains empty fields and its exact prefix length.
fn windows_unc_prefix(path &Path, relative_start int, verbatim bool) WindowsPrefix {
	first_start := path.start + relative_start
	first_end := windows_next_component_end(path, first_start, verbatim)
	second_start := if first_end < path.end { first_end + 1 } else { first_end }
	second_end := windows_next_component_end(path, second_start, verbatim)
	if !verbatim && (first_end == first_start || second_end == second_start) {
		return WindowsPrefix{}
	}
	prefix_length := relative_start + first_end - first_start +
		if second_end > second_start { 1 + second_end - second_start } else { 0 }
	return WindowsPrefix{
		kind:         if verbatim { .verbatim_unc } else { .unc }
		length:       prefix_length
		first_start:  first_start
		first_end:    first_end
		second_start: second_start
		second_end:   second_end
	}
}

// STUB: std's Windows next-component scan uses backslashes alone for verbatim
// prefixes and either separator otherwise; it does not skip repeated separators.
fn windows_next_component_end(path &Path, start int, verbatim bool) int {
	mut index := start
	for index < path.end && !path_is_separator((*path.source)[index], verbatim) {
		index++
	}
	return index
}
