module code_fence

import codex_tui.render.highlight
import ratatui.style
import ratatui.text

fn test_detects_only_source_preserving_open_fences() {
	for source in [
		'```rust,no_run\nfn main() {}\n',
		'~~~~python title=demo\nvalue = 1\n',
		'```\u000brust\u000c\nfn main() {}\n',
		'```unknown-language\ntext\n',
	] {
		fence := OpenCodeFence.detect(&source, usize(source.len), highlight.syntax_theme_revision()) or {
			panic(source)
		}
		assert fence.highlighter == none
	}
	for source in [
		' ```rust\ncode\n',
		'```\ncode\n',
		'```rust\r\ncode\r\n',
		"```rust\n'\x00'\n",
		'```r&#117;st\ncode\n',
		'```rust\\,no_run\ncode\n',
		'```rust\npartial',
	] {
		assert OpenCodeFence.detect(&source, usize(source.len), highlight.syntax_theme_revision()) == none
	}
	source := '```' + 'x'.repeat(int(highlight.max_highlight_line_bytes) + 1) + '\n'
	assert OpenCodeFence.detect(&source, usize(source.len), highlight.syntax_theme_revision()) == none
}

fn test_every_possible_closer_returns_to_the_canonical_parser() {
	opening := '~~~~rust\n'
	possible_closers := '~~~\n```\n'
	assert !has_possible_closing_line(&possible_closers, /* marker */
		`~`, /* marker_len */
		4)
	for line in [
		'~~~~\n',
		'   ~~~~~~  \n',
		'~~~~\t\n',
		'~~~~\u00a0\n',
		'\t~~~~\n',
		'    ~~~~\n',
		'~~~~ trailing text\n',
	] {
		source := '${opening}${line}'
		assert OpenCodeFence.detect(&source, usize(source.len), highlight.syntax_theme_revision()) == none
	}
}

fn test_lazy_initialization_rejects_a_changed_theme() {
	source := '```rust\nfn first() {}\n'
	mut fence := OpenCodeFence.detect(&source, usize(source.len), highlight.syntax_theme_revision()) or {
		panic('expected open fence')
	}
	fence.theme_revision = if fence.theme_revision == 0 {
		~u64(0)
	} else {
		fence.theme_revision - 1
	}
	appended := 'fn second() {}\n'
	raw_source := '${source}${appended}'
	assert fence.append(&raw_source, &appended) == none
}

fn test_detect_preserves_suffix_anchor_and_exact_info_token() {
	source := '~~~~\tpython,no_run title=demo\t\nvalue = 1\n'
	fence := OpenCodeFence.detect(&source, 1000, highlight.syntax_theme_revision()) or {
		panic('expected open fence')
	}
	assert fence.marker == `~`
	assert fence.marker_len == 4
	assert fence.language == 'python'
	assert fence.source_len == 1000
	assert fence.content_start == 1000 - usize('value = 1\n'.len)
	assert fence.highlighter == none
}

fn test_detect_checks_empty_opening_bounds_and_info_normalization() {
	for source in ['', '```rust', '``rust\n', '~~~\t,python\n', '```r`ust\n', '```\u00a0\n'] {
		if source == '```\u00a0\n' {
			fence := OpenCodeFence.detect(&source, usize(source.len), 0) or {
				panic('non-ASCII whitespace remains a language token')
			}
			assert fence.language == '\u00a0'
		} else {
			assert OpenCodeFence.detect(&source, usize(source.len), 0) == none
		}
	}
	source := '```rust\n123\n'
	assert OpenCodeFence.detect(&source, 3, 0) == none
	assert OpenCodeFence.detect(&source, usize(source.len), 1) == none
	bounded_source := '```' + 'x'.repeat(int(highlight.max_highlight_line_bytes)) + '\n'
	fence := OpenCodeFence.detect(&bounded_source, usize(bounded_source.len), 0) or {
		panic('language at the limit is accepted')
	}
	assert usize(fence.language.len) == highlight.max_highlight_line_bytes
}

fn test_possible_closer_scans_lines_and_only_ascii_indent() {
	for source in ['prefix\n~~~\n', '~~~', '\t  ~~~~stuff', '\r~~~', '\u00a0~~~'] {
		expected := !source.starts_with('\r') && !source.starts_with('\u00a0')
		assert has_possible_closing_line(&source, `~`, 3) == expected
	}
	source := 'prefix\n~~\n~~\n'
	assert !has_possible_closing_line(&source, `~`, 3)
	empty := ''
	assert !has_possible_closing_line(&empty, `~`, 0)
	newline := '\n'
	assert has_possible_closing_line(&newline, `~`, 0)
	crlf := '\r\n~~~\r\n'
	assert has_possible_closing_line(&crlf, `~`, 3)
	assert has_possible_closing_line(&crlf, `~`, 0)
	trailing_lf := '~~\n'
	assert !has_possible_closing_line(&trailing_lf, `~`, 3)
}

fn test_lazy_replay_uses_only_anchored_code_and_then_reuses_state() {
	highlight.code_fence_fixture_clear()
	defer { highlight.code_fence_fixture_clear() }
	prefix := 'earlier Markdown\n\n'
	suffix := '```rust\nlet first = 1;\n'
	previous := '${prefix}${suffix}'
	first_append := 'let second = 2;\n'
	second_append := 'let third = 3;\n\n'
	highlight.code_fence_fixture_install('let first = 1;\n', 'rust', 0, [
		highlight.CodeFenceFixtureBatch{
			appended: first_append.clone()
			lines:    [text.line_from_spans([
				text.span_styled('let ', style.Style.default().add_modifier(.bold)),
				text.span_styled('second = 2;', style.Style.default()),
			])]
		},
		highlight.CodeFenceFixtureBatch{
			appended: second_append.clone()
			lines:    [text.line_from_spans([text.Span{ text: 'let third = 3;' }]), text.Line{}]
		},
	])
	fence := OpenCodeFence.detect(&suffix, usize(previous.len), 0) or { panic('expected fence') }
	assert highlight.code_fence_fixture_new_calls() == 0
	first_raw := '${previous}${first_append}'
	next, first_lines := fence.append(&first_raw, &first_append) or { panic('expected first append') }
	assert next.source_len == usize(first_raw.len)
	assert next.highlighter != none
	assert highlight.code_fence_fixture_new_calls() == 1
	assert first_lines.len == 1
	assert first_lines[0].hyperlinks.len == 0
	assert first_lines[0].line == text.line_from_spans([
		text.Span{},
		text.span_styled('let ', style.Style.default().add_modifier(.bold)),
		text.Span{ text: 'second = 2;' },
	])
	second_raw := '${first_raw}${second_append}'
	final_fence, second_lines := next.append(&second_raw, &second_append) or { panic('expected second append') }
	assert final_fence.source_len == usize(second_raw.len)
	assert final_fence.language == 'rust'
	assert final_fence.content_start == usize(prefix.len + '```rust\n'.len)
	assert final_fence.highlighter != none
	assert highlight.code_fence_fixture_new_calls() == 1
	assert second_lines.len == 2
	assert second_lines[0].line == text.line_from_spans([text.Span{},
		text.Span{ text: 'let third = 3;' }])
	assert second_lines[1].line == text.line_from_spans([text.Span{}])
}

fn test_append_rejects_invalid_extension_before_highlighter_replay() {
	highlight.code_fence_fixture_clear()
	defer { highlight.code_fence_fixture_clear() }
	source := '```rust\nfirst\n'
	for appended in ['~~~\n', '``` trailing\n', 'second\r\n', 'second\x00\n'] {
		fence := OpenCodeFence.detect(&source, usize(source.len), 0) or { panic('expected fence') }
		raw := '${source}${appended}'
		if appended == '~~~\n' {
			// A different marker is a valid extension and reaches the unavailable highlighter.
			assert fence.append(&raw, &appended) == none
			assert highlight.code_fence_fixture_new_calls() == 1
			highlight.code_fence_fixture_clear()
		} else {
			assert fence.append(&raw, &appended) == none
			assert highlight.code_fence_fixture_new_calls() == 0
		}
	}
	appended := 'second\n'
	for raw in ['${source}${appended}extra', 'x'.repeat(source.len) + 'wrong!!'] {
		fence := OpenCodeFence.detect(&source, usize(source.len), 0) or { panic('expected fence') }
		assert fence.append(&raw, &appended) == none
		assert highlight.code_fence_fixture_new_calls() == 0
	}
	mut fence := OpenCodeFence.detect(&source, usize(source.len), 0) or { panic('expected fence') }
	fence.source_len = ~usize(0)
	raw := '${source}${appended}'
	assert fence.append(&raw, &appended) == none
	assert highlight.code_fence_fixture_new_calls() == 0
}

fn test_highlighter_failure_discards_retained_fence_and_partial_lines_reject() {
	highlight.code_fence_fixture_clear()
	defer { highlight.code_fence_fixture_clear() }
	source := '```rust\nfirst\n'
	for appended in ['second\n', 'partial', ''] {
		highlight.code_fence_fixture_install('first\n', 'rust', 0, [
			highlight.CodeFenceFixtureBatch{ appended: appended.clone(), fails: true },
		])
		fence := OpenCodeFence.detect(&source, usize(source.len), 0) or { panic('expected fence') }
		raw := '${source}${appended}'
		assert fence.append(&raw, &appended) == none
		assert highlight.code_fence_fixture_new_calls() == 1
	}
}

fn test_detect_and_append_borrowed_owners_remain_reusable() {
	highlight.code_fence_fixture_clear()
	defer { highlight.code_fence_fixture_clear() }
	mut source := '```rust\nowned first\n'
	mut appended := 'owned next\n'
	$if ownership ? {
		source = source.to_owned()
		appended = appended.to_owned()
	}
	first := OpenCodeFence.detect(&source, usize(source.len), 0) or { panic('expected fence') }
	second := OpenCodeFence.detect(&source, usize(source.len), 0) or { panic('expected fence') }
	mut raw := '${source}${appended}'
	$if ownership ? {
		raw = raw.to_owned()
	}
	assert first.append(&raw, &appended) == none
	highlight.code_fence_fixture_install('owned first\n', 'rust', 0, [
		highlight.CodeFenceFixtureBatch{
			appended: appended.clone()
			lines:    [text.line_from_spans([text.Span{ text: 'owned next'.clone() }])]
		},
	])
	retained, rendered := second.append(&raw, &appended) or { panic('expected fixture append') }
	assert retained.source_len == usize(raw.len)
	assert rendered[0].line.spans[1].text == 'owned next'
	assert has_possible_closing_line(&source, `~`, 3) == false
	assert has_possible_closing_line(&appended, `~`, 3) == false
	assert source == '```rust\nowned first\n'
	assert appended == 'owned next\n'
	assert raw == '```rust\nowned first\nowned next\n'
}
