module text_formatting

import os
import codex_tui.width
import serde_json
import unicode_segmentation

pub fn capitalize_first(input &string) string {
	chars := input.runes()
	if chars.len == 0 {
		return ''
	}
	first := chars[0]
	return unicode_segmentation.uppercase(first) + (*input)[first.str().len..]
}

// Truncate a tool result to fit within the given height and width. If the text is valid JSON, we format it in a compact way before truncating.
// This is a best-effort approach that may not work perfectly for text where 1 grapheme is rendered as multiple terminal cells.
pub fn format_and_truncate_tool_result(text &string, max_lines usize, line_width usize) string {
	// Work out the maximum number of graphemes we can display for a result.
	// It's not guaranteed that 1 grapheme = 1 cell, so we subtract 1 per line as a fudge factor.
	// It also won't handle future terminal resizes properly, but it's an OK approximation for now.
	max_graphemes := saturating_sub(max_lines * line_width, max_lines)
	if formatted_json := format_json_compact(text) {
		return truncate_text(&formatted_json, max_graphemes)
	}
	return truncate_text(text, max_graphemes)
}

// Formats JSON on one line with spaces after separators for readability and natural wrap points.
//
// Compact JSON is hard to scan, while pretty-printed JSON consumes unnecessary terminal rows.
// Returns the formatted JSON string for valid input, or `none` otherwise.
//
// Example: `{"a":"b","c":["d","e"]}` becomes `{"a": "b", "c": ["d", "e"]}`.
pub fn format_json_compact(text &string) ?string {
	json := serde_json.from_str(text) or { return none }
	json_pretty := serde_json.to_string_pretty(&json) or { json.to_string() }

	// Convert multi-line pretty JSON to compact single-line format by removing newlines and excess whitespace
	mut result := ''
	chars := json_pretty.runes()
	mut in_string := false
	mut escape_next := false

	// Iterate over the characters in the JSON string, adding spaces after : and , but only when not in a string
	for i, ch in chars {
		if ch == `"` && !escape_next {
			in_string = !in_string
			result += ch.str()
		} else if ch == `\\` && in_string {
			escape_next = !escape_next
			result += ch.str()
		} else if ch in [`\n`, `\r`] && !in_string {
			// Skip newlines when not in a string
		} else if ch in [` `, `\t`] && !in_string {
			// Add a space after : and , but only when not in a string
			if i + 1 < chars.len && result.len > 0
				&& result[result.len - 1] in [`:`, `,`] && chars[i + 1] !in [`}`, `]`] {
				result += ' '
			}
		} else {
			if escape_next && in_string {
				escape_next = false
			}
			result += ch.str()
		}
	}
	return result
}

// Truncate `text` to `max_graphemes` graphemes. Using graphemes to avoid accidentally truncating in the middle of a multi-codepoint character.
pub fn truncate_text(text &string, max_graphemes usize) string {
	graphemes := unicode_segmentation.grapheme_indices(text, true)
	// Check if there's a grapheme at position max_graphemes (meaning there are more than max_graphemes total)
	if max_graphemes < usize(graphemes.len) {
		byte_index := graphemes[int(max_graphemes)]
		// There are more than max_graphemes, so we need to truncate
		if max_graphemes >= 3 {
			// Truncate to max_graphemes - 3 and add "..." to stay within limit
			truncate_graphemes := unicode_segmentation.grapheme_indices(text, true)
			if max_graphemes - 3 < usize(truncate_graphemes.len) {
				truncate_byte_index := truncate_graphemes[int(max_graphemes - 3)]
				return (*text)[..truncate_byte_index] + '...'
			}
			return text.clone()
		}
		// max_graphemes < 3, so just return first max_graphemes without "..."
		return (*text)[..byte_index].clone()
	}
	// There are max_graphemes or fewer graphemes, return original text
	return text.clone()
}

// Rust's local Segment contains a borrowed original slice. V stores its UTF-8 byte range
// into the borrowed path instead, so the original path owner stays reusable.
struct Segment {
	original_start int
	original_end   int
	truncatable    bool
	is_suffix      bool
mut:
	text string
}

struct Combo {
	left  int
	right int
}

struct RawSegment {
	original_start int
	original_end   int
}

// Truncate a path-like string to the given display width, keeping leading and trailing segments
// where possible and inserting a single Unicode ellipsis between them. If an individual segment
// cannot fit, it is front-truncated with an ellipsis.
pub fn center_truncate_path(path &string, max_width usize) string {
	if max_width == 0 {
		return ''
	}
	if width.display_width(path) <= max_width {
		return path.clone()
	}
	// Rust's MAIN_SEPARATOR is a Copy char. Compare its ASCII byte directly so
	// V's value-only starts_with/ends_with APIs do not consume an owned string.
	separator := os.path_separator[0]
	sep := os.path_separator.str()
	has_leading_sep := path.len > 0 && (*path)[0] == separator
	has_trailing_sep := path.len > 0 && (*path)[path.len - 1] == separator
	// Keep original borrowed segment ranges; allocate owned text only at Rust's to_string boundary.
	mut raw_segments := []RawSegment{}
	mut start := 0
	for i in 0 .. path.len {
		if (*path)[i] == separator {
			raw_segments << RawSegment{ original_start: start, original_end: i }
			start = i + 1
		}
	}
	raw_segments << RawSegment{ original_start: start, original_end: path.len }
	if has_leading_sep && raw_segments.len > 0
		&& raw_segments[0].original_start == raw_segments[0].original_end {
		raw_segments.delete(0)
	}
	if has_trailing_sep && raw_segments.len > 0
		&& raw_segments.last().original_start == raw_segments.last().original_end {
		raw_segments.delete_last()
	}
	if raw_segments.len == 0 {
		if has_leading_sep && width.display_width(&sep) <= max_width {
			return sep
		}
		return '…'
	}

	mut combos := []Combo{}
	segment_count := raw_segments.len
	for left in 1 .. segment_count + 1 {
		min_right := if left == segment_count { 0 } else { 1 }
		for right in min_right .. segment_count - left + 1 {
			combos << Combo{ left: left, right: right }
		}
	}
	desired_suffix := if segment_count > 1 { int_min(2, segment_count - 1) } else { 0 }
	mut prioritized := []Combo{}
	mut fallback := []Combo{}
	for combo in combos {
		if combo.right >= desired_suffix {
			prioritized << combo
		} else {
			fallback << combo
		}
	}
	sort_combos(mut prioritized)
	sort_combos(mut fallback)
	prioritized << fallback
	for combo in prioritized {
		mut segments := []Segment{}
		for i in 0 .. combo.left {
			original := raw_segments[i]
			segments << Segment{
				original_start: original.original_start
				original_end:   original.original_end
				text:           (*path)[original.original_start..original.original_end].clone()
				truncatable:    true
			}
		}
		need_ellipsis := combo.left + combo.right < segment_count
		if need_ellipsis {
			segments << Segment{ text: '…' }
		}
		if combo.right > 0 {
			for i in segment_count - combo.right .. segment_count {
				original := raw_segments[i]
				segments << Segment{
					original_start: original.original_start
					original_end:   original.original_end
					text:           (*path)[original.original_start..original.original_end].clone()
					truncatable:    true
					is_suffix:      true
				}
			}
		}
		allow_front_truncate := need_ellipsis || segment_count <= 2
		if candidate := fit_segments(path, max_width, has_leading_sep, segment_count, &sep,
			mut segments, allow_front_truncate) {
			return candidate
		}
	}
	return front_truncate(path, max_width)
}

// Rust local closure lifted to a private helper because V closures cannot safely capture
// mutable arrays under ownership analysis.
fn assemble(leading bool, segments &[]Segment, sep &string) string {
	mut result := ''
	if leading {
		result += *sep
	}
	for segment in segments {
		if result.len > 0 && !result.ends_with(*sep) {
			result += *sep
		}
		result += segment.text
	}
	return result
}

fn front_truncate(original &string, allowed_width usize) string {
	if allowed_width == 0 {
		return ''
	}
	if width.display_width(original) <= allowed_width {
		return original.clone()
	}
	if allowed_width == 1 {
		return '…'
	}
	// is_extended = true: include extended grapheme clusters.
	graphemes := unicode_segmentation.grapheme_indices(original, true)
	mut kept_start := original.len
	mut used_width := usize(1) // reserve space for leading ellipsis
	for i := graphemes.len - 1; i >= 0; i-- {
		end := if i + 1 < graphemes.len { graphemes[i + 1] } else { original.len }
		grapheme := (*original)[graphemes[i]..end]
		grapheme_width := width.display_width(&grapheme)
		if used_width + grapheme_width > allowed_width {
			break
		}
		used_width += grapheme_width
		kept_start = graphemes[i]
	}
	return '…' + (*original)[kept_start..]
}

fn sort_combos(mut items []Combo) {
	items.sort_with_compare(fn (left &Combo, right &Combo) int {
		if left.left != right.left {
			return right.left - left.left
		}
		if left.right != right.right {
			return right.right - left.right
		}
		return right.left + right.right - left.left - left.right
	})
}

fn fit_segments(path &string, max_width usize, leading bool, segment_count int, sep &string,
	mut segments []Segment, allow_front_truncate bool) ?string {
	for {
		candidate := assemble(leading, &segments, sep)
		candidate_width := width.display_width(&candidate)
		if candidate_width <= max_width {
			return candidate
		}
		if !allow_front_truncate {
			return none
		}
		mut indices := []int{}
		for idx := segments.len - 1; idx >= 0; idx-- {
			if segments[idx].truncatable && segments[idx].is_suffix {
				indices << idx
			}
		}
		for idx := segments.len - 1; idx >= 0; idx-- {
			if segments[idx].truncatable && !segments[idx].is_suffix {
				indices << idx
			}
		}
		if indices.len == 0 {
			return none
		}
		mut changed := false
		for idx in indices {
			original := (*path)[segments[idx].original_start..segments[idx].original_end]
			original_width := width.display_width(&original)
			if original_width <= max_width && segment_count > 2 {
				continue
			}
			seg_width := width.display_width(&segments[idx].text)
			other_width := saturating_sub(candidate_width, seg_width)
			allowed_width := usize_max(saturating_sub(max_width, other_width), 1)
			new_text := front_truncate(&original, allowed_width)
			if new_text != segments[idx].text {
				segments[idx].text = new_text
				changed = true
				break
			}
		}
		if !changed {
			return none
		}
	}
	return none
}

// Join a list of strings with proper English punctuation.
// Examples:
// - [] -> ""
// - ["apple"] -> "apple"
// - ["apple", "banana"] -> "apple and banana"
// - ["apple", "banana", "cherry"] -> "apple, banana and cherry"
// V strings cover Rust String and &str; other types implement `as_ref() &string`.
pub fn proper_join[T](items &[]T) string {
	match items.len {
		0 { return '' }
		1 { return string_ref(&(*items)[0]).clone() }
		2 { return '${*string_ref(&(*items)[0])} and ${*string_ref(&(*items)[1])}' }
		else {
			mut result := ''
			for i in 0 .. items.len - 1 {
				if i > 0 {
					result += ', '
				}
				result += *string_ref(&(*items)[i])
			}
			return '${result} and ${*string_ref(&(*items)[items.len - 1])}'
		}
	}
}

// Rust AsRef<str> returns a shared string slice; V borrows the owned string in-place.
fn string_ref[T](item &T) &string {
	$if T is string {
		return item
	} $else {
		return item.as_ref()
	}
}

fn saturating_sub(left usize, right usize) usize {
	return if left >= right { left - right } else { 0 }
}

fn usize_max(left usize, right usize) usize {
	return if left >= right { left } else { right }
}

fn int_min(left int, right int) int {
	return if left <= right { left } else { right }
}
