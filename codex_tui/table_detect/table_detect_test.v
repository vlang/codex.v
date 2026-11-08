module table_detect

fn test_parse_table_segments_basic() {
	line := '| A | B | C |'
	assert parse_table_segments(&line) or { panic('expected table segments') } == ['A', 'B', 'C']
}

fn test_parse_table_segments_no_outer_pipes() {
	line := 'A | B | C'
	assert parse_table_segments(&line) or { panic('expected table segments') } == ['A', 'B', 'C']
}

fn test_parse_table_segments_no_leading_pipe() {
	line := 'A | B | C |'
	assert parse_table_segments(&line) or { panic('expected table segments') } == ['A', 'B', 'C']
}

fn test_parse_table_segments_no_trailing_pipe() {
	line := '| A | B | C'
	assert parse_table_segments(&line) or { panic('expected table segments') } == ['A', 'B', 'C']
}

fn test_parse_table_segments_single_segment_is_allowed() {
	line := '| only |'
	assert parse_table_segments(&line) or { panic('expected table segments') } == ['only']
}

fn test_parse_table_segments_without_pipe_returns_none() {
	line := 'just text'
	assert parse_table_segments(&line) == none
}

fn test_parse_table_segments_empty_returns_none() {
	empty := ''
	whitespace := '   '
	assert parse_table_segments(&empty) == none
	assert parse_table_segments(&whitespace) == none
}

fn test_parse_table_segments_escaped_pipe() {
	// Escaped pipe should NOT split — stays inside the segment.
	line := r'| A \| B | C |'
	assert parse_table_segments(&line) or { panic('expected table segments') } == [
		r'A \| B',
		'C',
	]
}

fn test_is_table_delimiter_segment_valid() {
	plain := '---'
	leading := ':---'
	trailing := '---:'
	both := ':---:'
	long := ':-------:'
	assert is_table_delimiter_segment(&plain)
	assert is_table_delimiter_segment(&leading)
	assert is_table_delimiter_segment(&trailing)
	assert is_table_delimiter_segment(&both)
	assert is_table_delimiter_segment(&long)
}

fn test_is_table_delimiter_segment_invalid() {
	empty := ''
	short := '--'
	letters := 'abc'
	short_leading := ':--'
	assert !is_table_delimiter_segment(&empty)
	assert !is_table_delimiter_segment(&short)
	assert !is_table_delimiter_segment(&letters)
	assert !is_table_delimiter_segment(&short_leading)
}

fn test_is_table_delimiter_line_valid() {
	plain := '| --- | --- |'
	aligned := '|:---:|---:|'
	no_outer := '--- | --- | ---'
	assert is_table_delimiter_line(&plain)
	assert is_table_delimiter_line(&aligned)
	assert is_table_delimiter_line(&no_outer)
}

fn test_is_table_delimiter_line_invalid() {
	header := '| A | B |'
	short := '| -- | -- |'
	assert !is_table_delimiter_line(&header)
	assert !is_table_delimiter_line(&short)
}

fn test_is_table_header_line_valid() {
	outer := '| A | B |'
	no_outer := 'Name | Value'
	assert is_table_header_line(&outer)
	assert is_table_header_line(&no_outer)
}

fn test_is_table_header_line_all_empty_segments() {
	line := '| | |'
	assert !is_table_header_line(&line)
}

// -----------------------------------------------------------------------
// FenceTracker tests
// -----------------------------------------------------------------------

fn test_fence_tracker_outside_by_default() {
	tracker := new_fence_tracker()
	assert tracker.kind() == .outside
}

fn test_fence_tracker_opens_and_closes_backtick_fence() {
	mut tracker := new_fence_tracker()
	open := '```rust'
	body := 'let x = 1;'
	close := '```'
	tracker.advance(&open)
	assert tracker.kind() == .other

	tracker.advance(&body)
	assert tracker.kind() == .other

	tracker.advance(&close)
	assert tracker.kind() == .outside
}

fn test_fence_tracker_opens_and_closes_tilde_fence() {
	mut tracker := new_fence_tracker()
	open := '~~~python'
	close := '~~~'
	tracker.advance(&open)
	assert tracker.kind() == .other
	tracker.advance(&close)
	assert tracker.kind() == .outside
}

fn test_fence_tracker_markdown_fence() {
	mut tracker := new_fence_tracker()
	open := '```md'
	body := '| A | B |'
	close := '```'
	tracker.advance(&open)
	assert tracker.kind() == .markdown
	tracker.advance(&body)
	assert tracker.kind() == .markdown
	tracker.advance(&close)
	assert tracker.kind() == .outside
}

fn test_fence_tracker_markdown_case_insensitive() {
	mut tracker := new_fence_tracker()
	open := '```Markdown'
	close := '```'
	tracker.advance(&open)
	assert tracker.kind() == .markdown
	tracker.advance(&close)
	assert tracker.kind() == .outside
}

fn test_fence_tracker_nested_shorter_marker_does_not_close() {
	mut tracker := new_fence_tracker()
	open := '````sh'
	short := '```'
	close := '````'
	tracker.advance(&open)
	assert tracker.kind() == .other
	// Shorter marker inside should not close.
	tracker.advance(&short)
	assert tracker.kind() == .other
	// Matching length closes.
	tracker.advance(&close)
	assert tracker.kind() == .outside
}

fn test_fence_tracker_mismatched_char_does_not_close() {
	mut tracker := new_fence_tracker()
	open := '```sh'
	tilde := '~~~'
	close := '```'
	tracker.advance(&open)
	assert tracker.kind() == .other
	// Tilde marker should not close a backtick fence.
	tracker.advance(&tilde)
	assert tracker.kind() == .other
	tracker.advance(&close)
	assert tracker.kind() == .outside
}

fn test_fence_tracker_indented_4_spaces_ignored() {
	mut tracker := new_fence_tracker()
	open := '    ```sh'
	tracker.advance(&open)
	assert tracker.kind() == .outside
}

fn test_fence_tracker_blockquote_prefix_stripped() {
	mut tracker := new_fence_tracker()
	open := '> ```sh'
	close := '> ```'
	tracker.advance(&open)
	assert tracker.kind() == .other
	tracker.advance(&close)
	assert tracker.kind() == .outside
}

fn test_fence_tracker_close_with_trailing_content_does_not_close() {
	mut tracker := new_fence_tracker()
	open := '```sh'
	extra := '``` extra'
	close := '```'
	tracker.advance(&open)
	assert tracker.kind() == .other
	// Trailing content prevents closing.
	tracker.advance(&extra)
	assert tracker.kind() == .other
	tracker.advance(&close)
	assert tracker.kind() == .outside
}

// -----------------------------------------------------------------------
// Fence helper function tests
// -----------------------------------------------------------------------

fn test_parse_fence_marker_backtick() {
	info := '```rust'
	long := '````'
	assert parse_fence_marker(&info) or { panic('expected fence marker') } == FenceMarker{ marker: `\``, len: 3 }
	assert parse_fence_marker(&long) or { panic('expected fence marker') } == FenceMarker{ marker: `\``, len: 4 }
}

fn test_parse_fence_marker_tilde() {
	line := '~~~python'
	assert parse_fence_marker(&line) or { panic('expected fence marker') } == FenceMarker{ marker: `~`, len: 3 }
}

fn test_parse_fence_marker_too_short() {
	backtick := '``'
	tilde := '~~'
	assert parse_fence_marker(&backtick) == none
	assert parse_fence_marker(&tilde) == none
}

fn test_parse_fence_marker_not_fence() {
	text := 'hello'
	empty := ''
	assert parse_fence_marker(&text) == none
	assert parse_fence_marker(&empty) == none
}

fn test_is_markdown_fence_info_basic() {
	short := '```md'
	long := '```markdown'
	uppercase := '```MD'
	other := '```rust'
	empty := '```'
	assert is_markdown_fence_info(&short, /*marker_len*/
		3)
	assert is_markdown_fence_info(&long, /*marker_len*/
		3)
	assert is_markdown_fence_info(&uppercase, /*marker_len*/
		3)
	assert !is_markdown_fence_info(&other, /*marker_len*/
		3)
	assert !is_markdown_fence_info(&empty, /*marker_len*/
		3)
}

fn test_strip_blockquote_prefix_basic() {
	single := '> hello'
	nested := '> > nested'
	without_prefix := 'no prefix'
	assert strip_blockquote_prefix(&single) == 'hello'
	assert strip_blockquote_prefix(&nested) == 'nested'
	assert strip_blockquote_prefix(&without_prefix) == 'no prefix'
}

fn test_unicode_whitespace_and_ascii_only_fence_info() {
	line := '\u00a0|\u2003A\u202f|\u3000B\u0085|\u205f'
	assert parse_table_segments(&line) or { panic('expected table segments') } == ['A', 'B']
	blank := '\u3000\u0085\u00a0'
	assert parse_table_segments(&blank) == none
	delimiter := '\u2003|\u3000:---:\u0085|\u202f---\u00a0|'
	assert is_table_delimiter_line(&delimiter)
	quoted := '\u3000>\u2003>\u00a0text'
	assert strip_blockquote_prefix(&quoted) == 'text'
	info := '```\u0085MARKDOWN\u2003extra'
	assert is_markdown_fence_info(&info, 3)
	unicode_case := '```marKdown'
	assert !is_markdown_fence_info(&unicode_case, 3)
	invisible_separator := '```md\u200bextra'
	assert !is_markdown_fence_info(&invisible_separator, 3)
}

fn test_pipe_escape_pairs_empty_cells_and_unicode() {
	doubled := r'| A \\| B |'
	assert parse_table_segments(&doubled) or { panic('expected table segments') } == [
		r'A \\',
		'B',
	]
	escaped := r'A \| B'
	assert parse_table_segments(&escaped) == none
	lone := '|'
	assert parse_table_segments(&lone) or { panic('expected table segments') } == ['']
	empties := '||'
	assert parse_table_segments(&empties) or { panic('expected table segments') } == ['']
	interior := '| | B | |'
	assert parse_table_segments(&interior) or { panic('expected table segments') } == ['', 'B',
		'']
	unicode := r'| 界\猫 | 🐈 |'
	assert parse_table_segments(&unicode) or { panic('expected table segments') } == [
		r'界\猫',
		'🐈',
	]
	trailing_escape := 'A | B\\'
	assert parse_table_segments(&trailing_escape) or { panic('expected table segments') } == [
		'A',
		'B\\',
	]
}

fn test_fence_tracking_unicode_close_and_indent_boundaries() {
	mut tracker := new_fence_tracker()
	open := '   >\u00a0~~~\u2003md'
	indented_close := '    ~~~'
	close := '> ~~~~\u0085\u3000'
	tracker.advance(&open)
	assert tracker.kind() == .markdown
	tracker.advance(&indented_close)
	assert tracker.kind() == .markdown
	tracker.advance(&close)
	assert tracker.kind() == .outside
}

fn test_borrowed_apis_preserve_string_owners() {
	mut header := '| A \\| B | C |'
	mut delimiter := '| :---: | --- |'
	mut open := '> ```markdown extra'
	mut close := '> ```'
	mut fence := '```md'
	$if ownership ? {
		header = header.to_owned()
		delimiter = delimiter.to_owned()
		open = open.to_owned()
		close = close.to_owned()
		fence = fence.to_owned()
	}
	first := parse_table_segments(&header) or { panic('expected table segments') }
	second := parse_table_segments(&header) or { panic('expected table segments') }
	assert first == [r'A \| B', 'C']
	assert second == [r'A \| B', 'C']
	assert is_table_header_line(&header)
	assert is_table_header_line(&header)
	assert is_table_delimiter_line(&delimiter)
	assert is_table_delimiter_line(&delimiter)
	assert strip_blockquote_prefix(&open) == '```markdown extra'
	assert strip_blockquote_prefix(&open) == '```markdown extra'
	assert parse_fence_marker(&fence) or { panic('expected fence marker') } == FenceMarker{ marker: `\``, len: 3 }
	assert parse_fence_marker(&fence) or { panic('expected fence marker') } == FenceMarker{ marker: `\``, len: 3 }
	assert is_markdown_fence_info(&fence, 3)
	assert is_markdown_fence_info(&fence, 3)
	mut tracker := new_fence_tracker()
	tracker.advance(&open)
	assert tracker.kind() == .markdown
	tracker.advance(&close)
	assert tracker.kind() == .outside
	tracker.advance(&open)
	assert tracker.kind() == .markdown
	tracker.advance(&close)
	assert tracker.kind() == .outside
	assert header == r'| A \| B | C |'
	assert delimiter == '| :---: | --- |'
	assert open == '> ```markdown extra'
	assert close == '> ```'
	assert fence == '```md'
}
