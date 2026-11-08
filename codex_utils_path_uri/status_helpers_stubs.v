module codex_utils_path_uri

import codex_utils_absolute_path
import encoding.base64
import os
import std_path

// STUB: utils/path-uri/src/lib.rs::PathConvention retains host-independent grammar.
pub enum PathConvention {
	posix
	windows
}

// STUB: PathConvention::native uses the platform compiling this executable.
pub fn PathConvention.native() PathConvention {
	$if windows {
		return .windows
	} $else {
		return .posix
	}
}

// STUB: PathUri::parse validates the metadata/path boundaries observed by status.
// This shim supports ordinary hierarchical file URIs and opaque fallback payloads;
// the url crate's complete WHATWG host normalization and dot-segment rules await
// translation. Existing raw-native PathUri values remain accepted by the methods.
pub fn PathUri.parse(uri &string) !PathUri {
	if !uri.starts_with('file://') {
		return error('unsupported path URI scheme')
	}
	if uri.contains('?') {
		return error('query parameters are not allowed in path URIs')
	}
	if uri.contains('#') {
		return error('fragments are not allowed in path URIs')
	}
	rest := (*uri)[7..]
	slash := rest.index('/') or { return error('file URI needs an absolute path') }
	host := rest[..slash]
	if host.contains('@') {
		return error('credentials are not allowed in path URIs')
	}
	if host.contains(':') {
		return error('ports are not allowed in path URIs')
	}
	raw_path := rest[slash..]
	decoded := decode_percent(&raw_path)
	if decoded.contains('\x00') && opaque_bytes(uri) == none {
		return error('invalid file URI path')
	}
	return PathUri{ path: local_links_canonical_drive(uri) }
}

// STUB: PathUri::from_abs_path encodes an owned URI from the borrowed native path.
// Opaque Unix bytes remain supported; Windows UTF-8 storage cannot represent lone
// UTF-16 surrogates, matching the current repository's explicit PathBuf adaptation.
pub fn PathUri.from_abs_path(path &codex_utils_absolute_path.AbsolutePathBuf) PathUri {
	mut native := path.path.clone()
	$if windows {
		native = native.replace('\\', '/')
		if native.starts_with('//') {
			return PathUri{ path: 'file:${encode_native(&native)}' }
		}
		return PathUri{ path: 'file:///${encode_native(&native)}' }
	} $else {
		drive_shaped := native.len >= 3 && native[0] == `/` && native[1].is_letter()
			&& native[2] == `:` && (native.len == 3 || native[3] == `/`)
		if native.contains('\x00') || drive_shaped {
			return PathUri{ path: 'file:///%00/bad/path/${base64.url_encode_str(native)}' }
		}
		return PathUri{ path: 'file://${encode_native(&native)}' }
	}
}

// STUB: PathUri::infer_path_convention applies the source's URI spelling heuristic
// and recognizes both Unix-byte and Windows-UTF16LE opaque fallback prefixes.
pub fn (path &PathUri) infer_path_convention() ?PathConvention {
	if path.path.starts_with('file:///%00/bad/path/') {
		bytes := opaque_bytes(&path.path) or { return none }
		if bytes.len > 0 && bytes[0] == `/` {
			return .posix
		}
		if bytes.len >= 4 && bytes.len % 2 == 0 && bytes[1] == 0 && bytes[3] == 0 {
			if (bytes[0].is_letter() && bytes[2] == `:`) || (bytes[0] == `\\` && bytes[2] == `\\`) {
				return .windows
			}
		}
		return none
	}
	if path.path.starts_with('file://') {
		rest := path.path[7..]
		slash := rest.index('/') or { return none }
		host := rest[..slash]
		if host.len > 0 && host != 'localhost' {
			return .windows
		}
		raw := rest[slash + 1..]
		segments := raw.split('/')
		for segment in segments {
			if segment.len == 0 {
				continue
			}
			// The source tests drive spelling before percent decoding.
			if segment[0].is_letter() && ((segment.len == 2 && segment[1] == `:`)
				|| (segment.len == 4 && segment[1] == `%` && segment[2] == `3` && segment[3] in [
					`a`,
					`A`,
				])) {
				return .windows
			}
			return .posix
		}
		return .posix
	}
	// Compatibility with the original repository PathUri's native-text storage.
	if path.path.starts_with('/') {
		return .posix
	}
	if path.path.starts_with('\\\\') || (path.path.len >= 3 && path.path[0].is_letter()
		&& path.path[1] == `:` && path.path[2] in [`/`, `\\`]) {
		return .windows
	}
	return none
}

// STUB: PathUri::inferred_native_path_string retains foreign Windows separators,
// decodes each URI segment exactly once and renders unrepresentable payloads as URI.
pub fn (path &PathUri) inferred_native_path_string() string {
	convention := path.infer_path_convention() or { return path.path.clone() }
	if path.path.starts_with('file:///%00/bad/path/') {
		bytes := opaque_bytes(&path.path) or { return path.path.clone() }
		if convention == .posix {
			raw := bytes.bytestr()
			view := std_path.Path.new(&raw)
			return view.to_string_lossy()
		}
		if bytes.len < 4 || bytes.len % 2 != 0 {
			return path.path.clone()
		}
		mut units := []u16{}
		for i := 0; i < bytes.len; i += 2 {
			units << u16(bytes[i]) | u16(bytes[i + 1]) << 8
		}
		drive := units.len >= 3 && ((units[0] >= `A` && units[0] <= `Z`)
			|| (units[0] >= `a` && units[0] <= `z`)) && units[1] == `:` && units[2] in [
			u16(`/`),
			`\\`,
		]
		unc := units.len >= 2 && units[0] in [u16(`/`), `\\`] && units[1] in [
			u16(`/`),
			`\\`,
		]
		if !drive && !unc {
			return path.path.clone()
		}
		mut result := ''
		for i := 0; i < units.len; i++ {
			unit := units[i]
			if unit >= 0xd800 && unit <= 0xdbff && i + 1 < units.len && units[i + 1] >= 0xdc00 && units[i + 1] <= 0xdfff {
				result += rune(0x10000 + (u32(unit) - 0xd800) * 0x400 + u32(units[i + 1]) - 0xdc00).str()
				i++
			} else if unit >= 0xd800 && unit <= 0xdfff {
				result += '�'
			} else {
				result += rune(unit).str()
			}
		}
		return result
	}
	if !path.path.starts_with('file://') {
		return path.path.clone()
	}
	rest := path.path[7..]
	slash := rest.index('/') or { return path.path.clone() }
	host := rest[..slash]
	raw := rest[slash..]
	if convention == .posix {
		decoded := decode_percent(&raw)
		view := std_path.Path.new(&decoded)
		return view.to_string_lossy()
	}
	segments := raw[1..].split('/')
	if host.len > 0 && host != 'localhost' {
		if segments.len == 0 || segments[0].len == 0 {
			return path.path.clone()
		}
		mut result := '\\\\${host}'
		for segment in segments {
			decoded := decode_percent(&segment)
			view := std_path.Path.new(&decoded)
			result += '\\${view.to_string_lossy()}'
		}
		return result
	}
	if segments.len == 0 {
		return path.path.clone()
	}
	drive := decode_percent(&segments[0])
	if drive.len != 2 || !drive[0].is_letter() || drive[1] != `:` {
		return path.path.clone()
	}
	mut result := drive.clone()
	for segment in segments[1..] {
		decoded := decode_percent(&segment)
		view := std_path.Path.new(&decoded)
		result += '\\${view.to_string_lossy()}'
	}
	if result.len == 2 {
		result += '\\'
	}
	return result
}

// STUB: PathUri::to_abs_path rejects foreign conventions and encoded Windows
// separators, then returns the existing typed absolute-path owner. Windows fallback
// identity round-tripping and host canonicalization remain external limitations.
pub fn (path &PathUri) to_abs_path() !codex_utils_absolute_path.AbsolutePathBuf {
	convention := path.infer_path_convention() or { return error('invalid file URI path') }
	if convention != PathConvention.native() {
		return error('invalid file URI path')
	}
	$if windows {
		if path.path.to_lower_ascii().contains('%2f') || path.path.to_lower_ascii().contains('%5c') {
			return error('invalid file URI path')
		}
	}
	native := $if windows {
		path.inferred_native_path_string()
	} $else {
		if bytes := opaque_bytes(&path.path) {
			bytes.bytestr()
		} else if path.path.starts_with('file://') {
			rest := path.path[7..]
			slash := rest.index('/') or { return error('invalid file URI path') }
			raw := rest[slash..]
			decode_percent(&raw)
		} else {
			path.path.clone()
		}
	}
	{
		view := std_path.Path.new(&native)
		if !view.is_absolute() {
			return error('invalid file URI path')
		}
	}
	candidate := codex_utils_absolute_path.AbsolutePathBuf{ path: os.norm_path(native) }
	$if !windows {
		if path.path.starts_with('file:///%00/bad/path/') {
			// Rust accepts an opaque native path only when reconstructing its URI
			// preserves its identity. An ordinary '/a' encoded as an opaque payload
			// must keep the caller on the full-path display fallback instead.
			reconstructed := PathUri.from_abs_path(&candidate)
			if reconstructed.path != path.path {
				return error('invalid file URI path')
			}
		}
	}
	return candidate
}

// STUB: urlencoding::decode_binary leaves malformed percent escapes literal.
fn decode_percent(raw &string) string {
	mut bytes := []u8{cap: raw.len}
	mut i := 0
	for i < raw.len {
		if (*raw)[i] == `%` && i + 2 < raw.len && (*raw)[i + 1].is_hex_digit() && (*raw)[i + 2].is_hex_digit() {
			bytes << u8(hex_digit((*raw)[i + 1]) * 16 + hex_digit((*raw)[i + 2]))
			i += 3
		} else {
			bytes << (*raw)[i]
			i++
		}
	}
	return bytes.bytestr()
}

// STUB: URI percent-escape nibble decoding used by the observed path conversion.
fn hex_digit(value u8) int {
	if value >= `0` && value <= `9` {
		return int(value - `0`)
	}
	if value >= `A` && value <= `F` {
		return int(value - `A` + 10)
	}
	return int(value - `a` + 10)
}

// STUB: Ordinary file-URI path-byte escaping, keeping separators and drive colons.
fn encode_native(native &string) string {
	mut result := ''
	for byte in native.bytes() {
		if byte.is_letter() || byte.is_digit() || byte in [`/`, `:`, `-`, `_`, `.`, `~`] {
			result += byte.ascii_str()
		} else {
			result += '%${byte:02X}'
		}
	}
	return result
}

// STUB: decode_bad_path_uri validates the canonical URL-safe, unpadded base64
// fallback spelling before calling V's decoder, which assumes valid alphabet bytes.
fn opaque_bytes(uri &string) ?[]u8 {
	if !uri.starts_with('file:///%00/bad/path/') || uri.len <= 21 {
		return none
	}
	encoded := (*uri)[21..]
	if encoded.len % 4 == 1 {
		return none
	}
	for byte in encoded.bytes() {
		if !byte.is_letter() && !byte.is_digit() && byte !in [`-`, `_`] {
			return none
		}
	}
	bytes := base64.url_decode(encoded.clone())
	if base64.url_encode(bytes.clone()) != encoded {
		return none
	}
	return bytes
}
