module terminal_probe

// STUB: terminal_probe.rs::find_subslice finds the first matching borrowed byte window.
// The native terminal probe that owns this helper has not been translated yet.
pub fn find_subslice(haystack &[]u8, needle &[]u8) ?usize {
	// Rust's windows(0) panics; all terminal-probe callers use nonempty markers.
	assert needle.len > 0
	if needle.len > haystack.len {
		return none
	}
	for start in 0 .. haystack.len - needle.len + 1 {
		mut matches := true
		for offset in 0 .. needle.len {
			if haystack[start + offset] != needle[offset] {
				matches = false
				break
			}
		}
		if matches {
			return usize(start)
		}
	}
	return none
}
