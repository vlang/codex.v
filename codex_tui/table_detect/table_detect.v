// Canonical pipe-table structure detection and fenced-code-block tracking for
// raw markdown source.
//
// Both the streaming controller (streaming/controller.v) and the
// markdown-fence unwrapper (markdown.v) need to identify pipe-table
// structure and fenced code blocks in raw markdown source. This module
// provides the canonical implementations so fixes only need to happen in one
// place.
//
// Concepts
//
// A GFM pipe table is a sequence of lines where:
// - A header line contains pipe-separated segments with at least one
//   non-empty cell.
// - A delimiter line immediately follows the header and contains only
//   alignment markers (`---`, `:---`, `---:`, `:---:`), each with at least
//   three dashes.
// - Body rows follow the delimiter.
//
// A fenced code block starts with 3+ backticks or tildes and ends with a
// matching close marker. FenceTracker classifies each line as
// FenceKind.outside, FenceKind.markdown, or FenceKind.other
// so callers can skip pipe characters that appear inside non-markdown fences.
//
// The table functions operate on single lines and do not maintain cross-line
// state. Callers (the streaming controller and fence unwrapper) are
// responsible for pairing consecutive lines to confirm a table.
module table_detect

// Rust str::trim uses Unicode White_Space; V's trim_space covers only ASCII.
const unicode_whitespace = '\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000'

// Split a pipe-delimited line into trimmed segments.
//
// Returns none if the line is empty or has no unescaped separator marker.
// Leading/trailing pipes are stripped before splitting.
//
// This is intentionally a structural parser, not a renderer. It preserves
// escaped pipes inside the returned segments because callers only care about
// whether the line can participate in a table, not how the cell text should
// finally be displayed.
// V has no borrowed string-slice return: input is borrowed, and each returned
// segment owns its text instead of sharing the source line's lifetime.
pub fn parse_table_segments(line &string) ?[]string {
	trimmed := line.trim(unicode_whitespace)
	if trimmed.len == 0 {
		return none
	}

	has_outer_pipe := trimmed.starts_with('|') || trimmed.ends_with('|')
	mut start := 0
	mut end := trimmed.len
	if trimmed.starts_with('|') {
		start++
	}
	if end > start && trimmed.ends_with('|') {
		end--
	}
	content := trimmed[start..end]
	raw_segments := split_unescaped_pipe(&content)
	if !has_outer_pipe && raw_segments.len <= 1 {
		return none
	}

	mut segments := []string{cap: raw_segments.len}
	for index in 0 .. raw_segments.len {
		segment := &raw_segments[index]
		segments << segment.trim(unicode_whitespace)
	}
	if segments.len == 0 {
		return none
	}
	return segments
}

// Split content on unescaped `|` characters.
//
// A pipe preceded by `\` is treated as literal text, not a column separator.
// The backslash remains in the segment (this is structure detection, not
// rendering).
// Returned strings own their contents because V cannot return Rust's &str slices.
fn split_unescaped_pipe(content &string) []string {
	mut segments := []string{cap: 8}
	mut start := 0
	mut i := 0
	for i < content.len {
		if (*content)[i] == `\\` {
			// Skip the escaped character.
			i += 2
		} else if (*content)[i] == `|` {
			segments << (*content)[start..i]
			start = i + 1
			i++
		} else {
			i++
		}
	}
	segments << (*content)[start..]
	return segments
}

// Small table-detection helpers inlined for the streaming hot path — they are
// called on every source line during incremental holdback scanning.

// Whether line looks like a table header row (has pipe-separated
// segments with at least one non-empty cell).
@[inline]
pub fn is_table_header_line(line &string) bool {
	segments := parse_table_segments(line) or { return false }
	for index in 0 .. segments.len {
		if segments[index].len != 0 {
			return true
		}
	}
	return false
}

// Whether a single segment matches the `---`, `:---`, `---:`, or `:---:`
// alignment-colon syntax used in markdown table delimiter rows.
@[inline]
fn is_table_delimiter_segment(segment &string) bool {
	trimmed := segment.trim(unicode_whitespace)
	if trimmed.len == 0 {
		return false
	}
	mut start := 0
	mut end := trimmed.len
	if trimmed.starts_with(':') {
		start++
	}
	if end > start && trimmed.ends_with(':') {
		end--
	}
	if end - start < 3 {
		return false
	}
	for i in start .. end {
		if trimmed[i] != `-` {
			return false
		}
	}
	return true
}

// Whether line is a valid table delimiter row (every segment passes
// is_table_delimiter_segment).
@[inline]
pub fn is_table_delimiter_line(line &string) bool {
	segments := parse_table_segments(line) or { return false }
	for index in 0 .. segments.len {
		if !is_table_delimiter_segment(&segments[index]) {
			return false
		}
	}
	return true
}

// ---------------------------------------------------------------------------
// Fenced code block tracking
// ---------------------------------------------------------------------------

// Where a source line sits relative to fenced code blocks.
//
// Table holdback only applies to lines that are outside or inside a
// markdown fence. Lines inside other fences (e.g. sh, rust) are
// ignored by the table scanner because their pipe characters are code, not
// table syntax.
pub enum FenceKind {
	// Not inside any fenced code block.
	outside
	// Inside a ```md or ```markdown fence.
	markdown
	// Inside a fence with a non-markdown info string.
	other
}

// V uses named allocation-free fields for Rust's (char, usize) marker tuple.
pub struct FenceMarker {
pub:
	marker rune
	len    usize
}

// V uses named allocation-free fields for Rust's (char, usize, FenceKind) state tuple.
struct FenceState {
	marker rune
	len    usize
	kind   FenceKind
}

// Incremental tracker for fenced-code-block open/close transitions.
//
// Feed lines one at a time via advance; query the current
// context with kind. The tracker handles leading-whitespace
// limits (>3 spaces → not a fence), blockquote prefix stripping, and
// backtick/tilde marker matching.
//
// The tracker reports the fence context that applies to the current line
// before that line mutates the state. Callers rely on that when deciding
// whether the current raw line can open or continue a table.
pub struct FenceTracker {
mut:
	state ?FenceState
}

// Rust FenceTracker::new is a module constructor in V.
@[inline]
pub fn new_fence_tracker() FenceTracker {
	return FenceTracker{ state: none }
}

// Process one raw source line and update fence state.
//
// Lines with >3 leading spaces are ignored (indented code blocks, not
// fences). Blockquote prefixes (`>`) are stripped before scanning.
pub fn (mut tracker FenceTracker) advance(raw_line &string) {
	mut leading_spaces := 0
	for leading_spaces < raw_line.len && (*raw_line)[leading_spaces] == ` ` {
		leading_spaces++
	}
	if leading_spaces > 3 {
		return
	}

	trimmed := (*raw_line)[leading_spaces..]
	fence_scan_text := strip_blockquote_prefix(&trimmed)
	if marker := parse_fence_marker(&fence_scan_text) {
		open_state := tracker.state
		if open := open_state {
			// Close the current fence if the marker matches.
			tail := fence_scan_text[int(marker.len)..]
			if marker.marker == open.marker && marker.len >= open.len
				&& tail.trim(unicode_whitespace).len == 0 {
				tracker.state = none
			}
		} else {
			// Opening a new fence.
			kind := if is_markdown_fence_info(&fence_scan_text, marker.len) {
				FenceKind.markdown
			} else {
				FenceKind.other
			}
			tracker.state = FenceState{ marker: marker.marker, len: marker.len, kind: kind }
		}
	}
}

// Current fence context for the most-recently-advanced line.
@[inline]
pub fn (tracker &FenceTracker) kind() FenceKind {
	if state := tracker.state {
		return state.kind
	}
	return .outside
}

// Return fence marker character and run length for a potential fence line.
//
// Recognises backtick and tilde fences with a minimum run of 3.
// The input should already have leading whitespace and blockquote prefixes
// stripped.
@[inline]
pub fn parse_fence_marker(line &string) ?FenceMarker {
	if line.len == 0 {
		return none
	}
	first := (*line)[0]
	if first != `\`` && first != `~` {
		return none
	}
	mut len := 0
	for len < line.len && (*line)[len] == first {
		len++
	}
	if len < 3 {
		return none
	}
	return FenceMarker{ marker: rune(first), len: usize(len) }
}

// Whether the info string after a fence marker indicates markdown content.
//
// Matches md and markdown (case-insensitive).
@[inline]
pub fn is_markdown_fence_info(trimmed_line &string, marker_len usize) bool {
	suffix := (*trimmed_line)[int(marker_len)..]
	// Scan Rust's first split_whitespace token without allocating it. Only ASCII
	// letters are folded, matching eq_ignore_ascii_case rather than Unicode folding.
	mut length := 0
	mut matches_md := true
	mut matches_markdown := true
	for ch in suffix.runes_iterator() {
		if is_unicode_whitespace(ch) {
			if length > 0 {
				break
			}
			continue
		}
		folded := if ch >= `A` && ch <= `Z` { ch + 32 } else { ch }
		if length >= 2 || folded != rune('md'[length]) {
			matches_md = false
		}
		if length >= 8 || folded != rune('markdown'[length]) {
			matches_markdown = false
		}
		length++
	}
	return (length == 2 && matches_md) || (length == 8 && matches_markdown)
}

// Peel all leading `>` blockquote markers from a line.
//
// Tables can appear inside blockquotes (`> | A | B |`), so the holdback
// scanner must strip these markers before checking for table syntax.
// V returns an owned string for Rust's borrowed &str result; the line owner
// remains reusable after this call.
@[inline]
pub fn strip_blockquote_prefix(line &string) string {
	mut rest := line.trim_left(unicode_whitespace)
	for {
		if !rest.starts_with('>') {
			return rest
		}
		stripped := rest[1..]
		without_space := if stripped.starts_with(' ') { stripped[1..] } else { stripped.clone() }
		rest = without_space.trim_left(unicode_whitespace)
	}
	return rest
}

// Rust str::split_whitespace uses this exact Unicode White_Space scalar set.
@[inline]
fn is_unicode_whitespace(ch rune) bool {
	return ch in [rune(0x09), 0x0a, 0x0b, 0x0c, 0x0d, 0x20, 0x85, 0xa0, 0x1680, 0x2028, 0x2029,
		0x202f, 0x205f, 0x3000] || (ch >= 0x2000 && ch <= 0x200a)
}
