module codex_utils_path_uri

import codex_utils_absolute_path
import encoding.base64

// STUB: utils/path-uri/src/api_path_string.rs::LegacyAppPathString's typed owned
// UTF-8 storage. Raw API spellings remain unvalidated, including relative paths.
pub struct LegacyAppPathString {
	path string
}

// STUB: LegacyAppPathString::from_string consumes already-legacy API path text.
pub fn LegacyAppPathString.from_string(path string) LegacyAppPathString {
	return LegacyAppPathString{ path: path }
}

// STUB: LegacyAppPathString::from_abs_path owns the borrowed path's lossy UTF-8 text.
pub fn LegacyAppPathString.from_abs_path(path &codex_utils_absolute_path.AbsolutePathBuf) LegacyAppPathString {
	view := path.as_path()
	return LegacyAppPathString{ path: view.to_string_lossy() }
}

// STUB: From<AbsolutePathBuf> retains the consumed constructor boundary observed by TUI tests.
pub fn LegacyAppPathString.from_absolute(path codex_utils_absolute_path.AbsolutePathBuf) LegacyAppPathString {
	return LegacyAppPathString.from_abs_path(&path)
}

// STUB: LegacyAppPathString::infer_absolute_path_convention preserves foreign-platform grammar.
pub fn (path &LegacyAppPathString) infer_absolute_path_convention() ?PathConvention {
	if path.path.starts_with('\\\\') || (path.path.len >= 3 && path.path[0].is_letter()
		&& path.path[1] == `:` && path.path[2] in [`/`, `\\`]) {
		return .windows
	}
	if path.path.starts_with('/') {
		return .posix
	}
	return none
}

// STUB: LegacyAppPathString::to_inferred_path_uri uses the source-shaped typed parser.
pub fn (path &LegacyAppPathString) to_inferred_path_uri() ?PathUri {
	convention := path.infer_absolute_path_convention() or { return none }
	return PathUri.from_absolute_native_path(&path.path, convention)
}

// STUB: LegacyAppPathString::render_for_ui normalizes absolute paths and preserves raw fallback.
pub fn (path &LegacyAppPathString) render_for_ui() string {
	if uri := path.to_inferred_path_uri() {
		return uri.inferred_native_path_string()
	}
	return path.path.clone()
}

// STUB: PathUri::from_absolute_native_path's lexical path normalization and opaque fallback.
// Native segments retain bytes and trailing separators. WHATWG URL authority validation,
// IDNA and unusual IPv4 host canonicalization remain the untranslated url crate boundary.
pub fn PathUri.from_absolute_native_path(path &string, convention PathConvention) ?PathUri {
	if convention == .posix {
		if !path.starts_with('/') {
			return none
		}
		if path.contains_u8(0) {
			return PathUri{ path: 'file:///%00/bad/path/${base64.url_encode_str(path.clone())}' }
		}
		raw := (*path)[1..]
		native := normalize_legacy_segments(&raw, 0)
		uri := PathUri{ path: 'file:///${encode_native(&native)}' }
		if (uri.infer_path_convention() or { PathConvention.windows }) == .posix {
			return uri
		}
		return PathUri{ path: 'file:///%00/bad/path/${base64.url_encode_str(path.clone())}' }
	}
	mut normalized := path.clone()
	if path.starts_with('\\\\?\\UNC\\') || path.starts_with('\\\\.\\UNC\\') {
		normalized = '\\\\${(*path)[8..]}'
	} else if path.starts_with('\\\\?\\') || path.starts_with('\\\\.\\') {
		rest := (*path)[4..]
		if rest.len >= 3 && rest[0].is_letter() && rest[1] == `:` && rest[2] in [`/`, `\\`] {
			normalized = rest.clone()
		}
	}
	if normalized.contains_u8(0) || (normalized.len >= 4 && normalized[0] in [`/`, `\\`]
		&& normalized[1] in [`/`, `\\`] && normalized[2] in [`?`, `.`]
		&& normalized[3] in [`/`, `\\`]) {
		return legacy_windows_opaque(path)
	}
	if normalized.len >= 3 && normalized[0].is_letter() && normalized[1] == `:`
		&& normalized[2] in [`/`, `\\`] {
		raw := normalized.replace('\\', '/')
		segments := normalize_legacy_segments(&raw, 1)
		mut drive_path := segments.clone()
		// PathUri canonicalizes Windows drive letters to uppercase on every host.
		drive_path = '${rune(drive_path[0]).str().to_upper()}${drive_path[1..]}'
		if drive_path.len == 2 {
			drive_path += '/'
		}
		return PathUri{ path: 'file:///${encode_native(&drive_path)}' }
	}
	if normalized.len >= 2 && normalized[0] in [`/`, `\\`]
		&& normalized[1] in [`/`, `\\`] {
		raw := normalized.replace('\\', '/')
		parts := raw[2..].split('/')
		if parts.len < 2 || parts[0].len == 0 || parts[1].len == 0 {
			return none
		}
		if parts[0] in ['.', '..'] || parts[1] in ['.', '..'] {
			return legacy_windows_opaque(path)
		}
		for byte in parts[0].bytes() {
			if byte >= 0x80 || byte in [`@`, `:`, `?`, `#`, `%`] {
				return legacy_windows_opaque(path)
			}
		}
		host := parts[0].to_lower_ascii()
		if host == 'localhost' {
			return legacy_windows_opaque(path)
		}
		rest := raw[2 + parts[0].len + 1..]
		segments := normalize_legacy_segments(&rest, 1)
		return PathUri{ path: 'file://${host}/${encode_native(&segments)}' }
	}
	return none
}

// STUB: absolute_path_normalization::path_uri_from_segments's anchor/trailing-slash rules.
fn normalize_legacy_segments(path &string, anchor_depth int) string {
	parts := path.split('/')
	mut retained := []string{}
	mut trailing := false
	for index in 0 .. parts.len {
		part := &parts[index]
		if part.len == 0 {
			trailing = true
		} else if *part == '.' {
			trailing = false
		} else if *part == '..' {
			trailing = false
			if retained.len > anchor_depth {
				retained.delete_last()
			}
		} else {
			retained << part.clone()
			trailing = false
		}
	}
	if trailing {
		retained << ''
	}
	return retained.join('/')
}

// STUB: PathUri's Windows opaque fallback retains the original UTF-16LE native spelling.
fn legacy_windows_opaque(path &string) PathUri {
	mut bytes := []u8{}
	for character in path.runes() {
		point := u32(character)
		if point <= 0xffff {
			bytes << u8(point)
			bytes << u8(point >> 8)
		} else {
			value := point - 0x10000
			first := u16(0xd800 | (value >> 10))
			second := u16(0xdc00 | (value & 0x3ff))
			bytes << u8(first)
			bytes << u8(first >> 8)
			bytes << u8(second)
			bytes << u8(second >> 8)
		}
	}
	return PathUri{ path: 'file:///%00/bad/path/${base64.url_encode(bytes)}' }
}

// STUB: LegacyAppPathString::as_str returns an owned V string because V lacks &str returns.
pub fn (path &LegacyAppPathString) as_str() string {
	return path.path.clone()
}
