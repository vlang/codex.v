module codex_utils_string

// STUB: Matches the current coarse byte/token conversion until the utility crate is ported.
pub fn approx_tokens_from_byte_count(bytes usize) i64 {
	return i64((bytes + 3) / 4)
}

// STUB: Matches the current coarse token/byte conversion until the utility crate is ported.
pub fn approx_bytes_for_tokens(tokens usize) usize {
	return tokens * 4
}
