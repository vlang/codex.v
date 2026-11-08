module clipboard_paste

import os

// STUB: crate::clipboard_paste::EncodedImageFormat.
pub enum EncodedImageFormat {
	png
	jpeg
	other
}

// STUB: crate::clipboard_paste::EncodedImageFormat::label.
pub fn (format EncodedImageFormat) label() string {
	return match format {
		.png { 'PNG' }
		.jpeg { 'JPEG' }
		.other { 'IMG' }
	}
}

// STUB: crate::clipboard_paste::pasted_image_format infers the encoded format from the final
// extension, including Windows-style paths which V's os helpers do not split on Unix.
pub fn pasted_image_format(path &string) EncodedImageFormat {
	filename := (*path).replace('\\', '/')
	separator := filename.last_index('.') or { return .other }
	extension := filename[separator + 1..].to_lower()
	return match extension {
		'png' { .png }
		'jpg', 'jpeg' { .jpeg }
		else { .other }
	}
}

// STUB: crate::clipboard_paste::is_probably_wsl checks the same kernel marker and environment
// fallbacks as the Rust owner. This API is called only from Linux compile-time branches.
pub fn is_probably_wsl() bool {
	version := os.read_file('/proc/version') or { '' }
	lower := version.to_lower()
	return lower.contains('microsoft') || lower.contains('wsl')
		|| os.getenv_opt('WSL_DISTRO_NAME') != none || os.getenv_opt('WSL_INTEROP') != none
}

// STUB: crate::clipboard_paste::normalize_pasted_path. It recognizes the path shapes consumed by
// ChatComposer: quoted paths, file URLs, unquoted Windows/UNC paths, and one shell-escaped path.
pub fn normalize_pasted_path(pasted &string) ?string {
	trimmed := pasted.trim_space()
	if trimmed.len == 0 {
		return none
	}
	mut unquoted := trimmed
	if trimmed.len >= 2
		&& ((trimmed.starts_with('"') && trimmed.ends_with('"'))
			|| (trimmed.starts_with("'") && trimmed.ends_with("'"))) {
		unquoted = trimmed[1..trimmed.len - 1]
	}
	if unquoted.starts_with('file://') {
		mut path := unquoted['file://'.len..]
		if path.starts_with('localhost/') {
			path = path['localhost'.len..]
		} else if path.len > 0 && !path.starts_with('/') {
			path = '//${path}'
		}
		return percent_decode_path(path)
	}
	if looks_like_windows_path(&unquoted) {
		return unquoted
	}
	parts := split_shell_path(trimmed) or { return none }
	if looks_like_windows_path(&parts) {
		return parts
	}
	return parts
}

// STUB: private helper owned by `crate::clipboard_paste`; recognizes drive and UNC paths.
fn looks_like_windows_path(path &string) bool {
	return path.starts_with('\\\\')
		|| (path.len >= 3 && (*path)[0].ascii_str().to_lower() >= 'a'
			&& (*path)[0].ascii_str().to_lower() <= 'z' && (*path)[1] == `:`
			&& (*path)[2] in [`\\`, `/`])
}

// STUB: private helper owned by `crate::clipboard_paste`; decodes exactly one shell path.
fn split_shell_path(input string) ?string {
	mut result := []u8{cap: input.len}
	mut quote := u8(0)
	mut escaped := false
	for byte in input.bytes() {
		if escaped {
			result << byte
			escaped = false
			continue
		}
		if byte == `\\` && quote != `'` {
			escaped = true
			continue
		}
		if byte in [`'`, `"`] {
			if quote == 0 {
				quote = byte
				continue
			}
			if quote == byte {
				quote = 0
				continue
			}
		}
		if (byte == ` ` || byte == `\t` || byte == `\n`) && quote == 0 {
			return none
		}
		result << byte
	}
	if quote != 0 || escaped {
		return none
	}
	return result.bytestr()
}

// STUB: private helper owned by `crate::clipboard_paste`; decodes file-URL percent escapes.
fn percent_decode_path(input string) string {
	mut result := []u8{cap: input.len}
	mut index := 0
	for index < input.len {
		if input[index] == `%` && index + 2 < input.len {
			high := hex_nibble(input[index + 1])
			low := hex_nibble(input[index + 2])
			if high >= 0 && low >= 0 {
				result << u8(high * 16 + low)
				index += 3
				continue
			}
		}
		result << input[index]
		index++
	}
	return result.bytestr()
}

// STUB: private helper owned by `crate::clipboard_paste`; returns one hexadecimal nibble.
fn hex_nibble(byte u8) int {
	return if byte >= `0` && byte <= `9` {
		int(byte - `0`)
	} else if byte >= `a` && byte <= `f` {
		int(byte - `a`) + 10
	} else if byte >= `A` && byte <= `F` {
		int(byte - `A`) + 10
	} else {
		-1
	}
}
