module codex_utils_path

import std_path

// STUB: path-utils/src/lib.rs::normalize_for_path_comparison reuses the existing
// fallible native canonicalizer. It preserves native Unix bytes and rejects NUL
// instead of allowing the C API to normalize only a truncated path prefix.
pub fn normalize_for_path_comparison(path &std_path.Path) !std_path.PathBuf {
	bytes := path.to_path_buf()
	if bytes.contains('\x00') {
		return error('path contains a NUL byte')
	}
	canonical := keyboard_canonicalize(&bytes) or { return error('could not canonicalize path') }
	return session_resume_normalize_for_wsl(std_path.PathBuf.from(canonical))
}

// STUB: path-utils/src/lib.rs::paths_match_after_normalization normalizes both
// sides, falling back to native lexical path equality when either fails.
pub fn paths_match_after_normalization(left &std_path.Path, right &std_path.Path) bool {
	left_result := normalize_for_path_comparison(left) or {
		// Rust evaluates both tuple elements even when the first one fails.
		normalize_for_path_comparison(right) or {}
		return left.equals(right)
	}
	right_result := normalize_for_path_comparison(right) or { return left.equals(right) }
	return left_result.equals(&right_result)
}

// STUB: path-utils/src/lib.rs::normalize_for_wsl folds ASCII only for canonical
// /mnt/<drive> paths on WSL. The native path owner is consumed, as in Rust.
fn session_resume_normalize_for_wsl(path std_path.PathBuf) std_path.PathBuf {
	$if linux {
		if keyboard_path_utils_is_wsl() {
			view := path.as_path()
			bytes := view.to_path_buf()
			parts := bytes.split('/')
			if parts.len >= 3 && parts[0] == '' && parts[1].to_lower() == 'mnt'
				&& parts[2].len == 1 && ((parts[2][0] >= `a` && parts[2][0] <= `z`)
				|| (parts[2][0] >= `A` && parts[2][0] <= `Z`)) {
				mut lower := []u8{cap: bytes.len}
				for item in bytes.bytes() {
					lower << if item >= `A` && item <= `Z` { item + u8(32) } else { item }
				}
				return std_path.PathBuf.from(lower.bytestr())
			}
		}
	}
	return path
}
