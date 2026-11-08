module markdown

import codex_tui.table_detect
import strings

// STUB: markdown.rs::unwrap_markdown_fences, with its full source state machine.
// The rest of markdown.rs's ratatui rendering APIs remain untranslated. Rust's
// Cow<str> is an owned V string; input is borrowed and even the fast path copies.
pub fn unwrap_markdown_fences(markdown_source &string) string {
	// Zero-copy in Rust: most messages contain no fences at all. V must return
	// owned storage because it cannot express the borrowed Cow lifetime.
	if !markdown_source.contains('```') && !markdown_source.contains('~~~') {
		return markdown_source.clone()
	}
	mut out := strings.new_builder(markdown_source.len)
	mut active := ClipboardActiveFence{}
	mut source_offset := 0
	for source_offset < markdown_source.len {
		line_start := source_offset
		mut end := source_offset
		for end < markdown_source.len && (*markdown_source)[end] != `\n` {
			end++
		}
		if end < markdown_source.len { end++ }
		source_offset = end
		line := (*markdown_source)[line_start..end]
		line_range := ClipboardSourceRange{ start: line_start, end: end }
		if active.present {
			if !active.markdown_candidate {
				closes := clipboard_is_close_fence(&line, active.fence)
				out.write_string(line)
				if closes {
					active.present = false
				}
			} else if clipboard_is_close_fence(&line, active.fence) {
				content := clipboard_content_from_ranges(markdown_source, &active.content_ranges)
				if clipboard_markdown_fence_contains_table(&content, active.fence.is_blockquoted) {
					out.write_string(content)
				} else {
					out.write_string((*markdown_source)[active.opening_range.start..active.opening_range.end])
					out.write_string(content)
					out.write_string(line)
				}
				active.present = false
				active.content_ranges.clear()
			} else {
				active.content_ranges << line_range
			}
			continue
		}
		if opening := clipboard_parse_open_fence(&line) {
			active = ClipboardActiveFence{ present: true, fence: opening.fence, markdown_candidate: opening.is_markdown, opening_range: line_range }
			if !opening.is_markdown { out.write_string(line) }
			continue
		}
		out.write_string(line)
	}
	if active.present && active.markdown_candidate {
		out.write_string((*markdown_source)[active.opening_range.start..active.opening_range.end])
		out.write_string(clipboard_content_from_ranges(markdown_source, &active.content_ranges))
	}
	return out.str()
}

// STUB: allocation-free markdown.rs local Fence metadata.
struct ClipboardFence {
	marker         rune
	len            usize
	is_blockquoted bool
}

// STUB: safe allocation-free (Fence,bool) open-fence tuple representation.
struct ClipboardOpenFence {
	fence       ClipboardFence
	is_markdown bool
}

// STUB: source byte range used by MarkdownCandidateData.
struct ClipboardSourceRange {
	start int
	end   int
}

// STUB: MarkdownCandidateData/ActiveFence's two variants are explicit tagged
// storage. Rust boxes the large candidate to keep ActiveFence pointer-sized.
struct ClipboardActiveFence {
mut:
	present            bool
	markdown_candidate bool
	fence              ClipboardFence
	opening_range      ClipboardSourceRange
	content_ranges     []ClipboardSourceRange
}

// STUB: strip a trailing newline and up to 3 leading spaces, returning a byte
// offset. Four or more indentation columns denote CommonMark indented code.
// A Copy offset keeps the original shared line reusable under ownership.
fn clipboard_strip_line_indent(line &string) ?int {
	mut byte_idx := 0
	mut column := 0
	for byte_idx < line.len {
		if (*line)[byte_idx] == ` ` {
			byte_idx++
			column++
		} else if (*line)[byte_idx] == `\t` {
			byte_idx++
			column += 4
		} else {
			break
		}
		if column >= 4 {
			return none
		}
	}
	return byte_idx
}

// STUB: parse opening fence metadata and whether its info string is Markdown.
fn clipboard_parse_open_fence(line &string) ?ClipboardOpenFence {
	start := clipboard_strip_line_indent(line) or { return none }
	end := if line.ends_with('\n') { line.len - 1 } else { line.len }
	trimmed := (*line)[start..end]
	is_blockquoted := trimmed.trim_left('\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000').starts_with('>')
	fence_scan_text := table_detect.strip_blockquote_prefix(&trimmed)
	marker := table_detect.parse_fence_marker(&fence_scan_text) or { return none }
	return ClipboardOpenFence{ fence: ClipboardFence{ marker: marker.marker, len: marker.len, is_blockquoted: is_blockquoted }, is_markdown: table_detect.is_markdown_fence_info(&fence_scan_text, marker.len) }
}

// STUB: closing fence requires the same marker, enough repeats, and no info.
fn clipboard_is_close_fence(line &string, fence ClipboardFence) bool {
	start := clipboard_strip_line_indent(line) or { return false }
	end := if line.ends_with('\n') { line.len - 1 } else { line.len }
	trimmed := (*line)[start..end]
	if fence.is_blockquoted && !trimmed.trim_left('\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000').starts_with('>') {
		return false
	}
	fence_scan_text := if fence.is_blockquoted {
		table_detect.strip_blockquote_prefix(&trimmed)
	} else {
		trimmed.clone()
	}
	if marker := table_detect.parse_fence_marker(&fence_scan_text) {
		return marker.marker == fence.marker && marker.len >= fence.len && fence_scan_text[int(marker.len)..].trim('\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000').len == 0
	}
	return false
}

// STUB: a Markdown candidate unwraps only an adjacent header/delimiter pair;
// blank lines reset the pair and quotes are stripped only for quoted fences.
fn clipboard_markdown_fence_contains_table(content &string, is_blockquoted_fence bool) bool {
	lines := content.split_into_lines()
	mut previous := ''.clone()
	mut previous_present := false
	for index in 0 .. lines.len {
		line := &lines[index]
		text := if is_blockquoted_fence {
			table_detect.strip_blockquote_prefix(line)
		} else {
			line.clone()
		}
		trimmed := text.trim('\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000')
		if trimmed.len == 0 {
			previous_present = false
			continue
		}
		if previous_present && table_detect.is_table_header_line(&previous) && !table_detect.is_table_delimiter_line(&previous) && table_detect.is_table_delimiter_line(&trimmed) {
			return true
		}
		previous = trimmed
		previous_present = true
	}
	return false
}

// STUB: concatenate the exact source ranges in candidate order.
fn clipboard_content_from_ranges(source &string, ranges &[]ClipboardSourceRange) string {
	mut total_len := 0
	for index in 0 .. ranges.len {
		total_len += (*ranges)[index].end - (*ranges)[index].start
	}
	mut content := strings.new_builder(total_len)
	for index in 0 .. ranges.len {
		range := (*ranges)[index]
		content.write_string((*source)[range.start..range.end])
	}
	return content.str()
}
