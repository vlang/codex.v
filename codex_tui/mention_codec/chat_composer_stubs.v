module mention_codec

// STUB: crate::mention_codec::LinkedMention.
pub struct LinkedMention {
pub:
	sigil   rune
	mention string
	path    string
}

// STUB: crate::mention_codec::DecodedHistoryText.
pub struct DecodedHistoryText {
pub:
	text                string
	mentions            []LinkedMention
	task_mention_ranges []ByteRange
}

// STUB: std::ops::Range<usize> payload used by decoded task mentions.
pub struct ByteRange {
pub:
	start int
	end   int
}

// STUB: crate::mention_codec::decode_history_mentions_with_at_mentions. This preserves persisted
// tool/plugin links and the special task-link display title representation used by history.
pub fn decode_history_mentions_with_at_mentions(text &string,
	at_mentions_enabled bool) DecodedHistoryText {
	mut output := ''
	mut mentions := []LinkedMention{}
	mut task_ranges := []ByteRange{}
	mut index := 0
	for index < text.len {
		if at_mentions_enabled {
			if task := parse_task_link(text, index) {
				start := output.len
				output += '@${task.name}'
				task_ranges << ByteRange{ start: start, end: output.len }
				mentions << LinkedMention{ sigil: `@`, mention: task.name, path: task.path }
				index = task.end
				continue
			}
		}
		if (*text)[index] == `[` {
			if linked := parse_history_linked_mention(text, index, at_mentions_enabled) {
				output += linked.sigil.str() + linked.name
				mentions << LinkedMention{
					sigil:   linked.sigil
					mention: linked.name
					path:    linked.path
				}
				index = linked.end
				continue
			}
		}
		value := (*text)[index..].runes()[0]
		output += value.str()
		index += value.str().len
	}
	return DecodedHistoryText{ text: output, mentions: mentions, task_mention_ranges: task_ranges }
}

// STUB: private crate::mention_codec task-link parse result.
struct ParsedTaskLink {
	name string
	path string
	end  int
}

// STUB: private crate::mention_codec task-link parser.
fn parse_task_link(text &string, start int) ?ParsedTaskLink {
	if start < 0 || start + 2 > text.len || !(*text)[start..].starts_with('[@') {
		return none
	}
	mut name := ''
	mut index := start + 2
	mut chars := 0
	for index < text.len && chars <= 160 {
		value := (*text)[index..].runes()[0]
		index += value.str().len
		chars++
		if value == `\\` {
			if index >= text.len {
				return none
			}
			escaped := (*text)[index..].runes()[0]
			name += escaped.str()
			index += escaped.str().len
			continue
		}
		if value == `]` {
			if name.len == 0 || index >= text.len || (*text)[index] != `(` {
				return none
			}
			close := (*text)[index + 1..].index(')') or { return none }
			path_end := index + 1 + close
			path := (*text)[index + 1..path_end]
			if valid_thread_path(path) == none {
				return none
			}
			return ParsedTaskLink{ name: name, path: path.clone(), end: path_end + 1 }
		}
		name += value.str()
	}
	return none
}

// STUB: private crate::mention_codec linked-mention parse result.
struct ParsedLinkedMention {
	sigil rune
	name  string
	path  string
	end   int
}

// STUB: private crate::mention_codec persisted mention parser.
fn parse_history_linked_mention(text &string, start int,
	at_mentions_enabled bool) ?ParsedLinkedMention {
	for sigil in [`$`, `@`] {
		linked := parse_linked_tool_mention(text, start, sigil) or { continue }
		if is_common_env_var(&linked.name) {
			continue
		}
		if sigil == `$` && is_tool_path(&linked.path) {
			return linked
		}
		if sigil == `@` && at_mentions_enabled && is_tool_path(&linked.path) {
			return linked
		}
		if sigil == `@` && !at_mentions_enabled && linked.path.starts_with('plugin://') {
			return ParsedLinkedMention{ ...linked, sigil: `$` }
		}
	}
	return none
}

// STUB: crate::mention_codec::parse_linked_tool_mention.
fn parse_linked_tool_mention(text &string, start int, sigil rune) ?ParsedLinkedMention {
	if start < 0 || start + 3 > text.len || (*text)[start] != `[`
		|| (*text)[start + 1] != u8(sigil) {
		return none
	}
	mut name_end := start + 2
	if name_end >= text.len || !is_mention_name_char((*text)[name_end]) {
		return none
	}
	for name_end < text.len && is_mention_name_char((*text)[name_end]) {
		name_end++
	}
	if name_end >= text.len || (*text)[name_end] != `]` {
		return none
	}
	mut path_start := name_end + 1
	for path_start < text.len && (*text)[path_start].is_space() {
		path_start++
	}
	if path_start >= text.len || (*text)[path_start] != `(` {
		return none
	}
	close := (*text)[path_start + 1..].index(')') or { return none }
	path_end := path_start + 1 + close
	path := (*text)[path_start + 1..path_end].trim_space()
	if path.len == 0 {
		return none
	}
	return ParsedLinkedMention{
		sigil: sigil
		name:  (*text)[start + 2..name_end].clone()
		path:  path
		end:   path_end + 1
	}
}

// STUB: private crate::mention_codec mention-name classifier.
fn is_mention_name_char(byte u8) bool {
	return byte.is_alnum() || byte in [`_`, `-`]
}

// STUB: private crate::mention_codec environment-variable exclusion.
fn is_common_env_var(name &string) bool {
	return name.to_upper() in ['PATH', 'HOME', 'USER', 'SHELL', 'PWD', 'TMPDIR', 'TEMP', 'TMP',
		'LANG', 'TERM', 'XDG_CONFIG_HOME']
}

// STUB: private crate::mention_codec tool-path classifier.
fn is_tool_path(path &string) bool {
	return path.starts_with('app://') || path.starts_with('mcp://')
		|| path.starts_with('plugin://') || path.starts_with('skill://')
		|| path.replace('\\', '/').all_after_last('/').to_upper() == 'SKILL.MD'
}

// STUB: private crate::mention_codec task thread-path validator.
fn valid_thread_path(path &string) ?string {
	if !path.starts_with('thread://') {
		return none
	}
	id := (*path)['thread://'.len..]
	if id.len == 0 || id.len > 64 {
		return none
	}
	for byte in id.bytes() {
		if !byte.is_alnum() && byte !in [`_`, `-`] {
			return none
		}
	}
	return id.clone()
}
