module codex_utils_path_uri

import os

// STUB: PathUri::join's executor-independent lexical path boundary. The URL
// parser/authority normalization remains the existing PathUri dependency shim.
pub fn (base &PathUri) join(path &string) !PathUri {
	if path.contains_u8(0) { return config_update_invalid_path(path) }
	if path.len == 0 { return base.clone() }
	convention := base.infer_path_convention() or { return config_update_invalid_path(&base.path) }
	if absolute := PathUri.from_absolute_native_path(path, convention) { return absolute }
	mut relative := path.clone()
	if convention == .windows && path.len >= 2 && (*path)[0].is_letter() && (*path)[1] == `:` {
		native := base.inferred_native_path_string()
		if native.len < 2 || native[1] != `:` || (native[0] | u8(32)) != ((*path)[0] | u8(32)) {
			return config_update_invalid_path(path)
		}
		relative = (*path)[2..].clone()
	}
	if opaque_bytes(&base.path) != none { return config_update_invalid_path(&relative) }
	if !base.path.starts_with('file://') { return config_update_invalid_path(&base.path) }
	rest := base.path[7..]
	slash := rest.index('/') or { return config_update_invalid_path(&base.path) }
	host := rest[..slash]
	raw := rest[slash + 1..]
	mut segments := []string{}
	for segment in raw.split('/') { if segment.len > 0 { segments << segment.clone() } }
	anchor_depth := if convention == .windows { 1 } else { 0 }
	if convention == .windows && relative.len > 0 && relative[0] in [`/`, `\\`]
		&& (relative.len < 2 || relative[1] !in [`/`, `\\`]) {
		for segments.len > anchor_depth { segments.delete_last() }
	}
	if convention == .windows { relative = relative.replace('\\', '/') }
	parts := relative.split('/')
	for index in 0 .. parts.len {
		component := &parts[index]
		match *component {
			'', '.' {}
			'..' {
				if segments.len > anchor_depth { segments.delete_last() }
			}
			else { segments << config_update_encode_component(component) }
		}
	}
	uri := 'file://${host}/${segments.join('/')}'
	return PathUri.parse(&uri)
}

// STUB: PathUriParseError::InvalidFileUriPath preserves the displayed cause.
fn config_update_invalid_path(path &string) IError {
	return error("'${*path}' is invalid on '${os.user_os()}'")
}

// STUB: url::PathSegmentsMut::push encodes each native filename component.
fn config_update_encode_component(component &string) string {
	mut result := ''
	for byte in component.bytes() {
		if byte.is_letter() || byte.is_digit() || byte in [`:`, `-`, `_`, `.`, `~`] {
			result += byte.ascii_str()
		} else {
			result += '%${byte:02X}'
		}
	}
	return result
}

// STUB: PathUri::starts_with compares decoded lexical segments using the
// inferred path convention, rejecting opaque or encoded-separator ambiguity.
pub fn (path &PathUri) starts_with(base &PathUri) bool {
	if path.equals(base) { return true }
	if opaque_bytes(&path.path) != none || opaque_bytes(&base.path) != none { return false }
	if path.session_state_uri_host() != base.session_state_uri_host() { return false }
	convention := path.infer_path_convention() or { PathConvention.posix }
	if path.infer_path_convention() != base.infer_path_convention() { return false }
	left := config_update_containment_segments(path, convention) or { return false }
	right := config_update_containment_segments(base, convention) or { return false }
	if left.len < right.len { return false }
	for index in 0 .. right.len {
		if convention == .windows {
			if left[index].to_lower_ascii() != right[index].to_lower_ascii() { return false }
		} else if left[index] != right[index] {
			return false
		}
	}
	return true
}

// STUB: containment_path_segments decodes component bytes while failing closed
// when decoding would introduce a native path separator.
fn config_update_containment_segments(path &PathUri, convention PathConvention) ?[]string {
	if !path.path.starts_with('file://') { return none }
	rest := path.path[7..]
	slash := rest.index('/') or { return none }
	raw := rest[slash..]
	parts := raw.split('/')
	mut result := []string{}
	for index in 0 .. parts.len {
		if parts[index].len == 0 { continue }
		decoded := decode_percent(&parts[index])
		if decoded.contains('/') || (convention == .windows && decoded.contains('\\')) {
			return none
		}
		result << decoded
	}
	return result
}
