module table_holdback

import codex_tui.table_detect

// A source line annotated with whether it falls inside a fenced code block.
// Rust borrows each text slice; V owns the copied line to keep it valid after
// the caller reuses or drops its source string.
struct ParsedLine {
	text          string
	fence_context table_detect.FenceKind
	source_start  usize
}

// Parse source into lines tagged with fenced-code context for table scanning.
fn parse_lines_with_fence_state(source &string) []ParsedLine {
	mut tracker := table_detect.new_fence_tracker()
	mut lines := []ParsedLine{}
	mut source_start := usize(0)

	for raw_line in source.split('\n') {
		lines << ParsedLine{
			text:          raw_line.clone()
			fence_context: tracker.kind()
			source_start:  source_start
		}

		tracker.advance(&raw_line)
		source_start = saturating_add(saturating_add(source_start, usize(raw_line.len)), 1)
	}
	return lines
}

// Scan source for pipe-table patterns outside of non-markdown fenced code
// blocks.
fn table_holdback_state(source &string) TableHoldbackState {
	lines := parse_lines_with_fence_state(source)
	for index := 0; index + 1 < lines.len; index++ {
		header_line := &lines[index]
		delimiter_line := &lines[index + 1]
		if header_line.fence_context == .other || delimiter_line.fence_context == .other {
			continue
		}

		header_text := table_candidate_text(&header_line.text) or { continue }
		delimiter_text := table_candidate_text(&delimiter_line.text) or { continue }
		if table_detect.is_table_header_line(&header_text)
			&& table_detect.is_table_delimiter_line(&delimiter_text) {
			return TableHoldbackState{ kind: .confirmed, table_start: header_line.source_start }
		}
	}

	mut index := lines.len
	for index > 0 {
		index--
		line := &lines[index]
		if line.text.trim(unicode_whitespace).len == 0 {
			continue
		}
		if line.fence_context != .other {
			if text := table_candidate_text(&line.text) {
				if table_detect.is_table_header_line(&text) {
					return TableHoldbackState{ kind: .pending_header, header_start: line.source_start }
				}
			}
		}
		break
	}
	return TableHoldbackState{ kind: .none }
}

// These seven source tests live in streaming/controller.rs alongside the caller.
fn test_table_holdback_state_detects_header_plus_delimiter() {
	source := '| Key | Description |\n| --- | --- |\n'
	assert table_holdback_state(&source).kind == .confirmed
}

fn test_table_holdback_state_detects_single_column_header_plus_delimiter() {
	source := '| Only |\n| --- |\n'
	assert table_holdback_state(&source).kind == .confirmed
}

fn test_table_holdback_state_ignores_table_like_lines_inside_unclosed_long_fence() {
	source := '````sh\n```cmd\n| Key | Description |\n| --- | --- |\n````\n'
	assert table_holdback_state(&source).kind == .none, 'table holdback should ignore pipe lines inside an open non-markdown fence'
}

fn test_table_holdback_state_treats_indented_fence_text_as_plain_content() {
	source := '    ```sh\n| Key | Description |\n| --- | --- |\n'
	assert table_holdback_state(&source).kind == .confirmed, 'indented fence-like text should not open a fence and should not block table detection'
}

fn test_table_holdback_state_ignores_table_like_lines_inside_blockquoted_other_fence() {
	source := '> ```sh\n> | Key | Value |\n> | --- | --- |\n> ```\n'
	assert table_holdback_state(&source).kind == .none, 'table holdback should ignore pipe lines inside non-markdown blockquoted fences'
}

fn test_incremental_holdback_matches_stateless_scan_per_chunk() {
	chunks := [
		'status | owner\n',
		'\n',
		'> ```sh\n',
		'> | A | B |\n',
		'> | --- | --- |\n',
		'> ```\n',
		'> | Key | Value |\n',
		'> | --- | --- |\n',
	]

	mut scanner := TableHoldbackScanner.new()
	mut source := ''
	for chunk in chunks {
		source += chunk
		scanner.push_source_chunk(&chunk)
		assert scanner.state() == table_holdback_state(&source), 'scanner mismatch after chunk: ${chunk}\nsource:\n${source}'
	}
}

fn test_incremental_holdback_detects_header_delimiter_across_chunk_boundary() {
	mut scanner := TableHoldbackScanner.new()
	chunk_1 := '| A | B |\n'
	scanner.push_source_chunk(&chunk_1)
	assert scanner.state() == TableHoldbackState{ kind: .pending_header, header_start: 0 }
	chunk_2 := '| --- | --- |\n'
	scanner.push_source_chunk(&chunk_2)
	assert scanner.state() == TableHoldbackState{ kind: .confirmed, table_start: 0 }
}

fn test_incremental_blank_lines_preserve_pending_but_break_header_lookbehind() {
	mut scanner := TableHoldbackScanner.new()
	chunk_3 := 'intro\n| A | B |\n\n'
	scanner.push_source_chunk(&chunk_3)
	assert scanner.state() == TableHoldbackState{ kind: .pending_header, header_start: 6 }
	chunk_4 := '| --- | --- |\n'
	scanner.push_source_chunk(&chunk_4)
	assert scanner.state() == TableHoldbackState{ kind: .pending_header, header_start: 17 }
	chunk_5 := 'plain text\n'
	scanner.push_source_chunk(&chunk_5)
	assert scanner.state().kind == .none
}

fn test_first_confirmed_table_remains_mutable_until_reset() {
	mut scanner := TableHoldbackScanner.new()
	chunk_6 := 'intro\n| A | B |\n| --- | --- |\n'
	scanner.push_source_chunk(&chunk_6)
	confirmed := TableHoldbackState{ kind: .confirmed, table_start: 6 }
	assert scanner.state() == confirmed
	chunk_7 := 'plain text\n```rust\n| A | B |\n| --- | --- |\n```\n'
	scanner.push_source_chunk(&chunk_7)
	assert scanner.state() == confirmed
	chunk_8 := '| C | D |\n| --- | --- |\n'
	scanner.push_source_chunk(&chunk_8)
	assert scanner.state() == confirmed
	scanner.reset()
	assert scanner.state().kind == .none
	chunk_9 := '| Only |\n| --- |\n'
	scanner.push_source_chunk(&chunk_9)
	assert scanner.state() == TableHoldbackState{ kind: .confirmed, table_start: 0 }
}

fn test_incremental_offsets_are_utf8_bytes_and_crlf_remains_trimmed() {
	source := 'é🦀\r\n> > | 名前 | 値 |\r\n> > | --- | --- |\r\n'
	mut scanner := TableHoldbackScanner.new()
	scanner.push_source_chunk(&source)
	assert scanner.state() == TableHoldbackState{ kind: .confirmed, table_start: 8 }
	assert scanner.state() == table_holdback_state(&source)
	assert scanner.source_offset == usize(source.len)
}

fn test_markdown_fence_table_works_but_nonmarkdown_fence_resets_pending() {
	mut scanner := TableHoldbackScanner.new()
	chunk_10 := '```Markdown\n> | A | B |\n'
	scanner.push_source_chunk(&chunk_10)
	assert scanner.state() == TableHoldbackState{ kind: .pending_header, header_start: 12 }
	chunk_11 := '> | --- | --- |\n```\n'
	scanner.push_source_chunk(&chunk_11)
	assert scanner.state() == TableHoldbackState{ kind: .confirmed, table_start: 12 }
	scanner.reset()
	chunk_12 := '| A | B |\n```rust\n'
	scanner.push_source_chunk(&chunk_12)
	assert scanner.state().kind == .none
	chunk_13 := '| --- | --- |\n'
	scanner.push_source_chunk(&chunk_13)
	assert scanner.state().kind == .none
}

fn test_borrowed_sources_reusable_and_unicode_blank_tail_keeps_pending() {
	mut source := 'préface\n> | A | B |\n\u0085\u00a0\u3000\n'
	$if ownership ? {
		source = source.to_owned()
	}
	expected := TableHoldbackState{ kind: .pending_header, header_start: 9 }
	assert table_holdback_state(&source) == expected
	assert table_holdback_state(&source) == expected
	mut scanner := TableHoldbackScanner.new()
	scanner.push_source_chunk(&source)
	assert scanner.state() == expected
	scanner.reset()
	scanner.push_source_chunk(&source)
	assert scanner.state() == expected
	assert source.starts_with('préface')
	assert source.ends_with('\u3000\n')
}

fn test_empty_chunk_is_noop_and_nonterminated_line_is_included() {
	mut scanner := TableHoldbackScanner.new()
	chunk_14 := ''
	scanner.push_source_chunk(&chunk_14)
	assert scanner.previous_line == none
	chunk_15 := '| A | B |'
	scanner.push_source_chunk(&chunk_15)
	pending := scanner.state()
	assert pending == TableHoldbackState{ kind: .pending_header, header_start: 0 }
	chunk_16 := ''
	scanner.push_source_chunk(&chunk_16)
	assert scanner.state() == pending
	assert scanner.source_offset == 9
}

fn test_source_offset_saturates_without_wrapping() {
	mut scanner := TableHoldbackScanner.new()
	scanner.source_offset = ~usize(0) - 2
	chunk_17 := 'intro\n'
	scanner.push_source_chunk(&chunk_17)
	assert scanner.source_offset == ~usize(0)
	chunk_18 := '| A | B |\n| --- | --- |\n'
	scanner.push_source_chunk(&chunk_18)
	assert scanner.state() == TableHoldbackState{ kind: .confirmed, table_start: ~usize(0) }
	assert scanner.source_offset == ~usize(0)
}

fn test_parsed_lines_preserve_trailing_empty_line_and_fence_context() {
	source := 'é\n```sh\n| x |\n```\n'
	lines := parse_lines_with_fence_state(&source)
	assert lines == [
		ParsedLine{ text: 'é', fence_context: .outside, source_start: 0 },
		ParsedLine{ text: '```sh', fence_context: .outside, source_start: 3 },
		ParsedLine{ text: '| x |', fence_context: .other, source_start: 9 },
		ParsedLine{ text: '```', fence_context: .other, source_start: 15 },
		ParsedLine{ text: '', fence_context: .outside, source_start: 19 },
	]
}

fn test_state_copy_clone_equality_uses_only_active_payload() {
	pending := TableHoldbackState{ kind: .pending_header, header_start: 23, table_start: 91 }
	assert pending.clone() == TableHoldbackState{ kind: .pending_header, header_start: 23 }
	assert pending.str() == 'PendingHeader { header_start: 23 }'
	confirmed := TableHoldbackState{ kind: .confirmed, header_start: 91, table_start: 23 }
	assert confirmed.clone() == TableHoldbackState{ kind: .confirmed, table_start: 23 }
	assert confirmed.str() == 'Confirmed { table_start: 23 }'
	assert TableHoldbackState{ kind: .none, header_start: 4 }.str() == 'None'
}
