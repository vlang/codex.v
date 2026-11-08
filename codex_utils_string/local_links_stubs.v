module codex_utils_string

// STUB: utils/string/src/lib.rs converts a markdown-style #L.. suffix into a
// terminal-friendly :line[:column][-line[:column]] suffix. Validation belongs to
// the caller, matching the source utility's deliberately permissive grammar.
pub fn normalize_markdown_hash_location_suffix(suffix &string) ?string {
	if !suffix.starts_with('#') {
		return none
	}
	fragment := (*suffix)[1..]
	range := fragment.index('-') or { fragment.len }
	start := fragment[..range]
	start_point := local_links_location_point(&start) or { return none }
	mut normalized := ':${start_point.line}'
	if column := start_point.column {
		normalized += ':${column}'
	}
	if range < fragment.len {
		end := fragment[range + 1..]
		end_point := local_links_location_point(&end) or { return none }
		normalized += '-${end_point.line}'
		if column := end_point.column {
			normalized += ':${column}'
		}
	}
	return normalized
}

// STUB: V-owned counterpart of the source helper's borrowed location tuple.
struct LocalLinksLocationPoint {
	line   string
	column ?string
}

// STUB: utils/string/src/lib.rs::parse_markdown_hash_location_point splits only
// the first C; V allocates owned slices because borrowed slice returns are absent.
fn local_links_location_point(point &string) ?LocalLinksLocationPoint {
	if !point.starts_with('L') {
		return none
	}
	text := (*point)[1..]
	column := text.index('C') or { return LocalLinksLocationPoint{ line: text.clone() } }
	return LocalLinksLocationPoint{ line: text[..column].clone(), column: text[column + 1..].clone() }
}
