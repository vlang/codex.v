// Codex App directives embedded in assistant markdown.
module git_action_directives

import codex_tui.assistant_directives
import std_path

// V uses an explicit tag for Rust's five payload variants. Only the fields belonging
// to the active variant participate in equality, cloning, and hashing.
pub enum GitActionKind {
	stage
	commit
	create_branch
	push
	create_pr
}

pub struct GitActionDirective {
pub:
	kind     GitActionKind
	cwd      string
	branch   string
	url      ?string
	is_draft bool
}

// Rust returns a borrowed string slice. V returns an owned copy while borrowing
// the directive, so the owner can be reused after either optional result.
pub fn (action &GitActionDirective) created_branch_cwd() ?string {
	if action.kind == .create_branch {
		return action.cwd.clone()
	}
	return none
}

// The explicit clone mirrors the source's derived Clone without copying inactive
// payload fields or sharing owned strings with the original directive.
pub fn (action &GitActionDirective) clone() GitActionDirective {
	return match action.kind {
		.stage, .commit {
			GitActionDirective{ kind: action.kind, cwd: action.cwd.clone() }
		}
		.create_branch, .push {
			GitActionDirective{ kind: action.kind, cwd: action.cwd.clone(), branch: action.branch.clone() }
		}
		.create_pr {
			cloned_url := if url := action.url { ?string(url.clone()) } else { ?string(none) }
			GitActionDirective{ kind: action.kind, cwd: action.cwd.clone(), branch: action.branch.clone(), url: cloned_url, is_draft: action.is_draft }
		}
	}
}

pub fn (left &GitActionDirective) == (right &GitActionDirective) bool {
	if left.kind != right.kind || left.cwd != right.cwd {
		return false
	}
	return match left.kind {
		.stage, .commit { true }
		.create_branch, .push { left.branch == right.branch }
		.create_pr {
			left.branch == right.branch && left.url == right.url && left.is_draft == right.is_draft
		}
	}
}

// Rust Hash has no mandated numeric digest. This deterministic digest includes the
// same discriminant and payload as derived Hash; de-duplication also checks equality
// within each hash bucket so hash collisions never discard distinct actions.
pub fn (action &GitActionDirective) hash() u64 {
	mut result := u64(14695981039346656037)
	result = hash_byte(result, u8(action.kind))
	result = hash_string(result, &action.cwd)
	match action.kind {
		.stage, .commit {}
		.create_branch, .push { result = hash_string(result, &action.branch) }
		.create_pr {
			result = hash_string(result, &action.branch)
			if url := action.url {
				result = hash_byte(result, 1)
				result = hash_string(result, &url)
			} else {
				result = hash_byte(result, 0)
			}
			result = hash_byte(result, u8(action.is_draft))
		}
	}
	return result
}

pub struct ParsedAssistantMarkdown {
pub:
	visible_markdown string
	git_actions      []GitActionDirective
}

pub fn (parsed &ParsedAssistantMarkdown) last_created_branch_cwd() ?string {
	mut index := parsed.git_actions.len
	for index > 0 {
		index--
		if cwd := parsed.git_actions[index].created_branch_cwd() {
			return cwd
		}
	}
	return none
}

pub fn parse_assistant_markdown(markdown &string, cwd &std_path.Path) ParsedAssistantMarkdown {
	mut git_actions := []GitActionDirective{}
	mut seen := map[u64][]int{}
	mut visible_lines := []string{}

	for line in rust_lines(markdown) {
		rewritten := rewrite_code_comment_line(&line, cwd) or { strip_line_directives(&line) }
		for action in rewritten.actions {
			digest := action.hash()
			mut already_seen := false
			for index in seen[digest] {
				if git_actions[index] == action {
					already_seen = true
					break
				}
			}
			if !already_seen {
				// Rust stores action.clone() in the HashSet and the owned action in
				// the output. Indices retain the same complete payload for equality.
				seen[digest] << git_actions.len
				git_actions << action
			}
		}
		visible_lines << trim_rust_whitespace(&rewritten.visible, false, true)
	}

	for visible_lines.len > 0 && visible_lines.last().len == 0 {
		visible_lines.pop()
	}
	return ParsedAssistantMarkdown{ visible_markdown: visible_lines.join('\n'), git_actions: git_actions }
}

// A named result preserves the optional Rust (String, Vec<GitActionDirective>)
// return: V cannot express an option wrapping a multiple-return value.
pub struct StrippedLine {
pub:
	visible string
	actions []GitActionDirective
}

fn rewrite_code_comment_line(line &string, cwd &std_path.Path) ?StrippedLine {
	content := (*line).trim_left(' \t')
	indent := (*line)[..line.len - content.len]
	directive := assistant_directives.parse_assistant_directive(&content, .backslash) or { return none }
	if directive.name != 'code-comment' {
		return none
	}
	suffix := content[directive.raw.len..]
	directive_ref := &directive
	title_attribute := directive_ref.attributes['title'] or { return none }
	body_attribute := directive_ref.attributes['body'] or { return none }
	file_attribute := directive_ref.attributes['file'] or { return none }
	title := trim_rust_whitespace(&title_attribute, true, true)
	body := trim_rust_whitespace(&body_attribute, true, true)
	file := trim_rust_whitespace(&file_attribute, true, true)
	if title.len == 0 || body.len == 0 || file.len == 0 {
		return none
	}
	start_key := 'start'
	start_value := directive_integer(&directive, &start_key) or { i64(1) }
	start := if start_value > 1 { start_value } else { i64(1) }
	end_key := 'end'
	end_value := directive_integer(&directive, &end_key) or { start }
	end := if end_value > start { end_value } else { start }
	priority_title := if title_has_priority(&title) {
		title.clone()
	} else {
		priority_key := 'priority'
		priority := directive_integer(&directive, &priority_key) or { i64(-1) }
		if priority >= 0 && priority <= 3 {
			'[P${priority}] ${title}'
		} else {
			title.clone()
		}
	}
	file_path := std_path.Path.new(&file)
	relative_file_path := file_path.strip_prefix(cwd) or { file_path }
	display_file := relative_file_path.to_string_lossy().replace('\\', '/')
	location := if start == end {
		'${display_file}:${start}'
	} else {
		'${display_file}:${start}-${end}'
	}
	stripped_suffix := strip_line_directives(&suffix)
	return StrippedLine{
		visible: '${indent}- ${priority_title} — ${location}\n${indent}  ${body}${stripped_suffix.visible}'
		actions: stripped_suffix.actions
	}
}

pub fn strip_line_directives(line &string) StrippedLine {
	mut visible := ''
	mut actions := []GitActionDirective{}
	mut position := 0
	// Byte offsets preserve the source's borrowed remaining/source slices without
	// allocating an owned copy for every suffix as V would otherwise require.
	for position < line.len {
		remaining := (*line)[position..]
		start := remaining.index('::git-') or { break }
		visible += remaining[..start]
		source := remaining[start..]
		if directive := assistant_directives.parse_assistant_directive(&source, .literal) {
			if action := parse_git_action(&directive) {
				actions << action
			}
			position += start + directive.raw.len
		} else if open := source.index('{') {
			attributes := source[open + 1..]
			if close := attributes.index('}') {
				position += start + open + 1 + close + 1
			} else {
				visible += source
				return StrippedLine{ visible: visible, actions: actions }
			}
		} else {
			visible += source
			return StrippedLine{ visible: visible, actions: actions }
		}
	}
	visible += (*line)[position..]
	return StrippedLine{ visible: visible, actions: actions }
}

fn directive_integer(directive &assistant_directives.AssistantDirective, name &string) ?i64 {
	attribute := directive.attributes[*name] or { return none }
	trimmed := trim_rust_whitespace(&attribute, true, true)
	value := trimmed.trim_left('Pp')
	return parse_i64_decimal(&value)
}

fn title_has_priority(title &string) bool {
	bytes := trim_rust_whitespace(title, true, false)
	return bytes.len >= 4 && bytes[0] == `[` && bytes[1] in [`P`, `p`] && bytes[2].is_digit() && bytes[3] == `]`
}

fn parse_git_action(directive &assistant_directives.AssistantDirective) ?GitActionDirective {
	cwd := directive.attributes['cwd'] or { return none }
	return match directive.name {
		'git-stage' { GitActionDirective{ kind: .stage, cwd: cwd.clone() } }
		'git-commit' { GitActionDirective{ kind: .commit, cwd: cwd.clone() } }
		'git-create-branch', 'git-push' {
			branch := directive.attributes['branch'] or { return none }
			GitActionDirective{
				kind:   if directive.name == 'git-create-branch' { .create_branch } else { .push }
				cwd:    cwd.clone()
				branch: branch.clone()
			}
		}
		'git-create-pr' {
			branch := directive.attributes['branch'] or { return none }
			url := if value := directive.attributes['url'] {
				?string(value.clone())
			} else {
				?string(none)
			}
			GitActionDirective{ kind: .create_pr, cwd: cwd.clone(), branch: branch.clone(), url: url, is_draft: directive.attributes['isDraft'] == 'true' }
		}
		else { return none }
	}
}

// Rust str::lines splits on LF and CRLF, does not strip a bare CR, and omits
// the final empty item for a trailing terminator. Empty input yields no lines.
// V cannot return borrowed string slices in an array, so each returned line owns
// the corresponding copy of the borrowed source.
fn rust_lines(source &string) []string {
	mut lines := []string{}
	mut start := 0
	for index in 0 .. source.len {
		if (*source)[index] == `\n` {
			end := if index > start && (*source)[index - 1] == `\r` { index - 1 } else { index }
			lines << (*source)[start..end].clone()
			start = index + 1
		}
	}
	if start < source.len {
		lines << (*source)[start..].clone()
	}
	return lines
}

// Rust's trim family uses Unicode White_Space, including NEL and NBSP and
// excluding obsolete U+180E. Returned V slices are owned lifetime adaptations.
fn trim_rust_whitespace(source &string, leading bool, trailing bool) string {
	runes := (*source).runes()
	mut start := 0
	mut end := runes.len
	if leading {
		for start < end && rust_whitespace(runes[start]) {
			start++
		}
	}
	if trailing {
		for end > start && rust_whitespace(runes[end - 1]) {
			end--
		}
	}
	return runes[start..end].string()
}

fn rust_whitespace(character rune) bool {
	return character in [`\t`, `\n`, `\v`, `\f`, `\r`, ` `, 0x85, 0xa0, 0x1680, 0x2028, 0x2029,
		0x202f, 0x205f, 0x3000] || (character >= 0x2000 && character <= 0x200a)
}

// Standard V integer parsers accept underscores or clamp overflow. Rust's i64
// parser requires ASCII decimal digits and reports overflow, so accumulate a
// bounded unsigned magnitude and handle i64::MIN separately.
fn parse_i64_decimal(source &string) ?i64 {
	if source.len == 0 {
		return none
	}
	negative := (*source)[0] == `-`
	mut index := if (*source)[0] in [`+`, `-`] { 1 } else { 0 }
	if index == source.len {
		return none
	}
	limit := if negative { u64(9223372036854775808) } else { u64(9223372036854775807) }
	mut value := u64(0)
	for index < source.len {
		character := (*source)[index]
		if !character.is_digit() {
			return none
		}
		digit := u64(character - `0`)
		if value > (limit - digit) / 10 {
			return none
		}
		value = value * 10 + digit
		index++
	}
	if negative && value == u64(9223372036854775808) {
		return -i64(9223372036854775807) - 1
	}
	return if negative { -i64(value) } else { i64(value) }
}

fn hash_byte(result u64, byte u8) u64 {
	return (result ^ u64(byte)) * u64(1099511628211)
}

fn hash_string(initial u64, value &string) u64 {
	mut result := initial
	// A length prefix distinguishes fields containing separators or NUL bytes.
	length := u64(value.len)
	for shift in 0 .. 8 {
		result = hash_byte(result, u8(length >> (shift * 8)))
	}
	for index in 0 .. value.len {
		result = hash_byte(result, (*value)[index])
	}
	return result
}
