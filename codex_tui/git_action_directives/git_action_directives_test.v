module git_action_directives

import codex_tui.assistant_directives
import std_path

fn test_strips_and_parses_git_action_directives() {
	markdown := 'Done\n\n::git-stage{cwd="/repo"} ::git-push{cwd="/repo" branch="feat/x"} ::git-stage{cwd="C:\\repo\\"} ::git-create-branch{cwd="/tmp/repo\\" branch="feat"}'
	cwd_text := '/repo'
	cwd := std_path.Path.new(&cwd_text)
	parsed := parse_assistant_markdown(&markdown, &cwd)
	assert parsed.visible_markdown == 'Done'
	assert parsed.git_actions == [
		GitActionDirective{ kind: .stage, cwd: '/repo' },
		GitActionDirective{ kind: .push, cwd: '/repo', branch: 'feat/x' },
		GitActionDirective{ kind: .stage, cwd: 'C:\\repo\\' },
		GitActionDirective{ kind: .create_branch, cwd: '/tmp/repo\\', branch: 'feat' },
	]
}

fn test_hides_malformed_directives_without_materializing_rows() {
	markdown := 'Done ::git-push{cwd="/repo"}'
	cwd_text := '/repo'
	cwd := std_path.Path.new(&cwd_text)
	parsed := parse_assistant_markdown(&markdown, &cwd)
	assert parsed.visible_markdown == 'Done'
	assert parsed.git_actions.len == 0
}

fn test_parses_unquoted_git_flags_and_quoted_closing_braces() {
	cwd_text := '/repo'
	cwd := std_path.Path.new(&cwd_text)
	markdown := r'Done ::git-create-pr{cwd="C:\repo" branch="feature/{rollout}" isDraft=true}'
	parsed := parse_assistant_markdown(&markdown, &cwd)
	assert parsed.visible_markdown == 'Done'
	assert parsed.git_actions == [GitActionDirective{
		kind:     .create_pr
		cwd:      r'C:\repo'
		branch:   'feature/{rollout}'
		url:      none
		is_draft: true
	}]
}

fn test_renders_code_comment_directives_as_markdown() {
	markdown := 'Found two issues.\n\n' +
		r'::code-comment{title="Fix body= parsing" body="C:\temp says \"foo\" here; keep role=\"tab\", ::git-stage{cwd=/tmp}, file=, and \n literal." file="/repo/src/app.ts" start=10 end=12 priority="P2"} ::git-stage{cwd="/repo"}' +
		'\n\n' +
		r":::code-comment{title='[P1] Clamp the range' body='The line range should match the App.' file='codex/src/range.ts' start=8 end=2 priority=3}"
	cwd_text := '/repo'
	cwd := std_path.Path.new(&cwd_text)
	parsed := parse_assistant_markdown(&markdown, &cwd)
	snapshot := $embed_file('fixtures/code_comment_directive_fallback.snap').to_string()
	snapshot_lines := snapshot.split_into_lines()
	assert parsed.visible_markdown == snapshot_lines[4..].join('\n')
	assert parsed.git_actions == [GitActionDirective{ kind: .stage, cwd: '/repo' }]
}

fn test_preserves_non_directive_and_malformed_code_comment_text() {
	markdown := 'Mention `::code-comment{title="Example"}` and `::git-push}` inline.\n::code-comment{title="Missing body" file="/repo/src/app.ts"}'
	cwd_text := '/repo'
	cwd := std_path.Path.new(&cwd_text)
	parsed := parse_assistant_markdown(&markdown, &cwd)
	assert parsed.visible_markdown == markdown
}

fn test_last_created_branch_cwd_uses_the_last_matching_directive() {
	markdown := '::git-create-branch{cwd="/first" branch="first"}\n::git-push{cwd="/repo" branch="first"}\n::git-create-branch{cwd="/second" branch="second"}'
	cwd_text := '/repo'
	cwd := std_path.Path.new(&cwd_text)
	parsed := parse_assistant_markdown(&markdown, &cwd)
	assert parsed.last_created_branch_cwd() == ?string('/second')
}

fn test_deduplicates_full_payload_in_first_occurrence_order() {
	markdown := '::git-stage{cwd="/repo"} ::git-stage{cwd="/repo"}\n' +
		'::git-commit{cwd="/repo"} ::git-create-branch{cwd="/repo" branch="one"} ::git-create-branch{cwd="/repo" branch="two"}\n' +
		'::git-create-pr{cwd="/repo" branch="one"} ::git-create-pr{cwd="/repo" branch="one" url=""} ::git-create-pr{cwd="/repo" branch="one" isDraft=true}\n' +
		'::git-create-pr{cwd="/repo" branch="one" url="https://example.test/pr/1"} ::git-create-pr{cwd="/repo" branch="one" isDraft=false}'
	cwd_text := '/repo'
	cwd := std_path.Path.new(&cwd_text)
	parsed := parse_assistant_markdown(&markdown, &cwd)
	assert parsed == ParsedAssistantMarkdown{
		visible_markdown: ''
		git_actions:      [
			GitActionDirective{ kind: .stage, cwd: '/repo' },
			GitActionDirective{ kind: .commit, cwd: '/repo' },
			GitActionDirective{ kind: .create_branch, cwd: '/repo', branch: 'one' },
			GitActionDirective{ kind: .create_branch, cwd: '/repo', branch: 'two' },
			GitActionDirective{ kind: .create_pr, cwd: '/repo', branch: 'one' },
			GitActionDirective{ kind: .create_pr, cwd: '/repo', branch: 'one', url: '' },
			GitActionDirective{ kind: .create_pr, cwd: '/repo', branch: 'one', is_draft: true },
			GitActionDirective{ kind: .create_pr, cwd: '/repo', branch: 'one', url: 'https://example.test/pr/1' },
		]
	}
	for action in parsed.git_actions {
		cloned := action.clone()
		assert cloned == action
		assert cloned.hash() == action.hash()
	}
}

fn test_lines_unicode_whitespace_and_trailing_empty_semantics() {
	empty_source := ''
	assert rust_lines(&empty_source) == []string{}
	terminated_source := 'first\r\nsecond\n\n'
	assert rust_lines(&terminated_source) == ['first', 'second', '']
	bare_cr_source := 'first\rsecond\r'
	assert rust_lines(&bare_cr_source) == ['first\rsecond\r']
	cwd_text := '/repo'
	cwd := std_path.Path.new(&cwd_text)
	markdown := '\u00a0Leading\u0085\r\n\t\r\nTrailing\u3000\n\u202f\n\n'
	assert parse_assistant_markdown(&markdown, &cwd).visible_markdown == '\u00a0Leading\n\nTrailing'
	obsolete_space_source := '\u180evalue\u180e'
	assert trim_rust_whitespace(&obsolete_space_source, true, true) == '\u180evalue\u180e'
}

fn test_strips_unknown_and_malformed_directives_but_keeps_unclosed_text() {
	line := 'a::git-unknown{cwd=/repo}b::git-push{cwd=/repo missing}c::git-stage{cwd=/repo}d'
	assert strip_line_directives(&line) == StrippedLine{
		visible: 'abcd'
		actions: [GitActionDirective{ kind: .stage, cwd: '/repo' }]
	}
	unclosed_source := 'a::git-push{cwd=/repo'
	assert strip_line_directives(&unclosed_source).visible == 'a::git-push{cwd=/repo'
	no_brace_source := 'a::git-push} trailing'
	assert strip_line_directives(&no_brace_source).visible == 'a::git-push} trailing'
}

fn test_strict_i64_numbers_priority_detection_and_range_clamping() {
	for source in ['9223372036854775808', '-9223372036854775809', '1_0', '+', '-', '', ' 1', '1 ',
		'١'] {
		assert parse_i64_decimal(&source) == none
	}
	max_source := '9223372036854775807'
	assert parse_i64_decimal(&max_source) == ?i64(9223372036854775807)
	min_source := '-9223372036854775808'
	assert parse_i64_decimal(&min_source) == ?i64(-i64(9223372036854775807) - 1)
	signed_source := '+001'
	assert parse_i64_decimal(&signed_source) == ?i64(1)
	priority_source := '\u00a0[p9] text'
	assert title_has_priority(&priority_source)
	long_priority_source := '[P12] text'
	assert !title_has_priority(&long_priority_source)
	directive_source := '::code-comment{title="Test" body="Body" file="src/a" start=-9223372036854775808 end=9223372036854775808 priority="pPP+2"}'
	directive := assistant_directives.parse_assistant_directive(&directive_source, .backslash) or { panic('directive parse failed') }
	priority_key := 'priority'
	assert directive_integer(&directive, &priority_key) == ?i64(2)
	cwd_text := '/repo'
	cwd := std_path.Path.new(&cwd_text)
	assert parse_assistant_markdown(&directive_source, &cwd).visible_markdown == '- [P2] Test — src/a:1\n  Body'
	existing_priority := '::code-comment{title="[p9] Existing" body="Body" file="src/a" start=5 end=3 priority=0}'
	assert parse_assistant_markdown(&existing_priority, &cwd).visible_markdown == '- [p9] Existing — src/a:5\n  Body'
}

fn test_code_comment_uses_path_components_not_string_prefix() {
	cwd_text := '/repo/.'
	cwd := std_path.Path.new(&cwd_text)
	normalized := '  \t::code-comment{title="Title" body="Body" file="/repo//src/./a.ts/"}'
	assert parse_assistant_markdown(&normalized, &cwd).visible_markdown == '  \t- Title — src/./a.ts:1\n  \t  Body'
	sibling := '::code-comment{title="Title" body="Body" file="/repository/a.ts"}'
	assert parse_assistant_markdown(&sibling, &cwd).visible_markdown == '- Title — /repository/a.ts:1\n  Body'
	parent := '::code-comment{title="Title" body="Body" file="/repo/../a.ts"}'
	assert parse_assistant_markdown(&parent, &cwd).visible_markdown == '- Title — ../a.ts:1\n  Body'
}

fn test_borrowed_markdown_directives_and_paths_remain_reusable() {
	mut markdown := '::git-create-branch{cwd="/repo" branch="feat"}\n::code-comment{title="Title" body="Body" file="/repo/src/a"}'
	mut cwd_text := '/repo'
	$if ownership ? {
		markdown = markdown.to_owned()
		cwd_text = cwd_text.to_owned()
	}
	cwd := std_path.Path.new(&cwd_text)
	first := parse_assistant_markdown(&markdown, &cwd)
	second := parse_assistant_markdown(&markdown, &cwd)
	assert first == second
	assert first.last_created_branch_cwd() == ?string('/repo')
	assert first.last_created_branch_cwd() == ?string('/repo')
	assert first.git_actions[0].created_branch_cwd() == ?string('/repo')
	assert first.git_actions[0].created_branch_cwd() == ?string('/repo')
	assert first.git_actions[0].cwd == '/repo'
	assert strip_line_directives(&markdown) == strip_line_directives(&markdown)
	assert cwd.to_string_lossy() == '/repo'
	assert cwd.to_string_lossy() == '/repo'
	assert cwd_text == '/repo'
	assert markdown.contains('branch="feat"')
}
