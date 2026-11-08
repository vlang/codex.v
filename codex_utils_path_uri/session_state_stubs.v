module codex_utils_path_uri

// STUB: utils/path-uri/src/lib.rs::PathUri's derived Clone owns URI storage.
pub fn (path &PathUri) clone() PathUri {
	return PathUri{ path: path.path.clone() }
}

// STUB: utils/path-uri/src/lib.rs::PathUri::eq. Canonical ordinary URI storage
// uses decoded, ASCII-folded Windows identity bytes and exact POSIX spelling.
// URL host normalization remains the existing parse dependency boundary.
pub fn (path &PathUri) equals(other &PathUri) bool {
	if path.path == other.path {
		return true
	}
	left := path.session_state_windows_identity() or { return false }
	right := other.session_state_windows_identity() or { return false }
	left_host := path.session_state_uri_host() or { return false }
	right_host := other.session_state_uri_host() or { return false }
	return left_host == right_host && left == right
}

// STUB: PathUri::windows_identity_path_bytes excludes opaque fallback paths
// and escaped separators before decoding equivalent Windows URI spellings.
fn (path &PathUri) session_state_windows_identity() ?string {
	if path.infer_path_convention() != ?PathConvention(.windows)
		|| opaque_bytes(&path.path) != none || !path.path.starts_with('file://') {
		return none
	}
	rest := path.path[7..]
	slash := rest.index('/') or { return none }
	raw_path := rest[slash..]
	segments := raw_path.split('/')
	for index in 0 .. segments.len {
		decoded := decode_percent(&segments[index])
		if decoded.contains('/') || decoded.contains('\\') {
			return none
		}
	}
	return decode_percent(&raw_path).to_lower_ascii()
}

// STUB: Url::host_str's already-canonical file URI authority view. V cannot
// return &str, so this comparison helper allocates its borrowed host substring.
fn (path &PathUri) session_state_uri_host() ?string {
	if !path.path.starts_with('file://') {
		return none
	}
	rest := path.path[7..]
	slash := rest.index('/') or { return none }
	return rest[..slash].clone()
}
