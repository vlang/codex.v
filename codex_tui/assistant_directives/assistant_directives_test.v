// Shared directive grammar and caller-specific quote compatibility.
module assistant_directives

fn test_parses_git_receipts_with_unquoted_attributes() {
	raw := r'::git-create-pr{cwd="/repo\" branch="feature/report" isDraft=true}'
	parsed := parse_assistant_directive(&raw, .literal) or { panic('valid git receipt') }
	assert parsed == AssistantDirective{
		name:       'git-create-pr'
		attributes: {
			'branch':  'feature/report'
			'cwd':     r'/repo\'
			'isDraft': 'true'
		}
		raw:        raw.clone()
	}
}

fn test_parses_triple_colon_comments_with_escaped_quotes_and_closing_braces() {
	raw := r':::code-comment{title="Fix class" body="Keep \"px-${size}\" literal." file="C:\Users\me\app.ts" start=10 priority=2}'
	source := '${raw} remaining text'
	parsed := parse_assistant_directive(&source, .backslash) or { panic('valid code comment') }
	assert parsed == AssistantDirective{
		name:       'code-comment'
		attributes: {
			'body':     r'Keep "px-${size}" literal.'
			'file':     r'C:\Users\me\app.ts'
			'priority': '2'
			'start':    '10'
			'title':    'Fix class'
		}
		raw:        raw.clone()
	}
}

fn test_preserves_artifact_metadata_and_single_quoted_values() {
	raw := ":artifact{path='Quarterly Report.xlsx' label='team\\'s report' sheet='Revenue' range='A1:D8'}"
	parsed := parse_assistant_directive(&raw, .backslash) or { panic('valid artifact') }
	assert parsed == AssistantDirective{
		name:       'artifact'
		attributes: {
			'label': "team's report"
			'path':  'Quarterly Report.xlsx'
			'range': 'A1:D8'
			'sheet': 'Revenue'
		}
		raw:        raw.clone()
	}
}

fn test_rejects_ambiguous_or_incomplete_directives() {
	for source in [
		r'::git-push{cwd="/repo" cwd="/other"}',
		r'::git-push{cwd="/repo" branch="feature"',
		'::::code-comment{title=comment}',
		':artifact{path=/tmp/a path=:artifact{path=/tmp/b}}',
		':artifact{invalid:key=:artifact{path=/tmp/a}}',
		':artifact{path=/tmp/a\nnext=value}',
	] {
		assert parse_assistant_directive(&source, .backslash) == none
	}
}

fn test_malformed_retries_exhaust_the_shared_scan_budget() {
	source := 'codex-file-citation ${':a{k='.repeat( /*n*/16_000)} x bad}'
	mut remaining := ScanBudget{ remaining: usize(source.len * 4) }
	mut attempts := 0
	for offset, byte in source {
		if byte != `:` {
			continue
		}
		if remaining.remaining == 0 {
			break
		}
		suffix := source[offset..].clone()
		assert parse_assistant_directive_with_budget(&suffix, .literal, mut remaining) == none
		attempts++
	}
	assert attempts <= 8, 'retried ${attempts} long malformed values'
	assert remaining.remaining == 0
}

fn test_scan_budget_counts_inspected_values_not_the_unread_suffix() {
	tail := 'x'.repeat( /*n*/
	16_000)
	raw := ':artifact{path=report.xlsx}'
	source := '${raw}${tail}'
	mut remaining := ScanBudget{ remaining: usize(64) }
	assert parse_assistant_directive_with_budget(&source, .literal, mut remaining) == parse_assistant_directive(&raw, .literal)
	for malformed in [':artifact{path="${tail}', ':artifact{path=${tail}'] {
		mut malformed_remaining := ScanBudget{ remaining: usize(64) }
		assert parse_assistant_directive_with_budget(&malformed, .literal, mut malformed_remaining) == none
		assert malformed_remaining.remaining == 0
	}
}

fn test_borrowed_directives_preserve_owned_source_and_attributes() {
	mut source := r':::code-comment{zebra=last body="Keep \"雪}\" literal." alpha=first} trailing'
	$if ownership ? {
		source = source.to_owned()
	}
	first := parse_assistant_directive(&source, .backslash) or { panic('first parse') }
	second := parse_assistant_directive(&source, .backslash) or { panic('second parse') }
	assert first == second
	assert first.attributes.keys() == ['alpha', 'body', 'zebra']
	assert first.attributes['body'] == 'Keep "雪}" literal.'
	assert first.raw == r':::code-comment{zebra=last body="Keep \"雪}\" literal." alpha=first}'
	mut remaining := ScanBudget{ remaining: usize(200) }
	third := parse_assistant_directive_with_budget(&source, .backslash, mut remaining) or {
		panic('budgeted parse')
	}
	assert third == first
	assert source == r':::code-comment{zebra=last body="Keep \"雪}\" literal." alpha=first} trailing'
	assert first.attributes['body'] == second.attributes['body']
}

fn test_budget_matches_utf8_scalar_and_zero_budget_boundaries() {
	source := ':a{x="雪"}'
	mut remaining := ScanBudget{ remaining: usize(16) }
	assert parse_assistant_directive_with_budget(&source, .literal, mut remaining) != none
	assert remaining.remaining == 2
	mut insufficient := ScanBudget{ remaining: usize(9) }
	assert parse_assistant_directive_with_budget(&source, .literal, mut insufficient) == none
	assert insufficient.remaining == 0
	mut exhausted := ScanBudget{ remaining: usize(0) }
	assert parse_assistant_directive_with_budget(&source, .literal, mut exhausted) == none
	assert exhausted.remaining == 0
}
