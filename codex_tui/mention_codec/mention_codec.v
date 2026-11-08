module mention_codec

import codex_protocol.user_input
import codex_tui.task_mentions
import codex_utils_plugins.mention_syntax

// Shared tool-mention syntax and history encoding. Callers decide which linked paths to accept.

pub struct LinkedMention {
pub:
	sigil   rune
	mention string
	path    string
}

// Named stand-in for the Rust `std::ops::Range<usize>` byte ranges of decoded task mentions.
pub struct ByteRange {
pub:
	start int
	end   int
}

pub struct DecodedHistoryText {
pub:
	text                string
	mentions            []LinkedMention
	task_mention_ranges []ByteRange
}

pub fn encode_history_mentions(text &string, mentions &[]LinkedMention) string {
	elements := []user_input.TextElement{}
	return encode_history_mentions_at_elements(text, mentions, &elements)
}

pub fn encode_history_mentions_at_elements(text &string, mentions &[]LinkedMention, elements &[]user_input.TextElement) string {
	if mentions.len == 0 || text.len == 0 {
		return text.clone()
	}

	// Rust keys a `HashMap<(char, &str), VecDeque<&str>>` by `(sigil, mention)`. V map keys must
	// be scalars or strings; the sigil is always the single ASCII byte `$` or `@`, so prefixing it
	// to the mention is an unambiguous key. The queue front is index 0.
	mut mentions_by_token := map[string][]string{}
	for mention in mentions {
		if mention.sigil !in [mention_syntax.tool_mention_sigil,
			mention_syntax.plugin_text_mention_sigil] {
			continue
		}
		key := mention_token_key(mention.sigil, &mention.mention)
		mut paths := mentions_by_token[key] or { []string{} }
		paths << mention.path.clone()
		mentions_by_token[key] = paths
	}

	bytes := text.bytes()
	mut out := []u8{cap: text.len}
	mut index := 0

	for index < bytes.len {
		if bytes[index] == u8(mention_syntax.tool_mention_sigil)
			|| bytes[index] == u8(mention_syntax.plugin_text_mention_sigil) {
			sigil := rune(bytes[index])
			if sigil == mention_syntax.plugin_text_mention_sigil {
				if element_end := element_end_starting_at(elements, index) {
					if name := str_get(text, index + 1, element_end) {
						key := mention_token_key(sigil, &name)
						if front_path := queue_front(&mentions_by_token, &key) {
							if task_mentions.valid_thread_path(&front_path) != none {
								if path := pop_front(mut mentions_by_token, &key) {
									out << task_mentions.format_task_link(&name, &path).bytes()
									index += 1 + name.len
									continue
								}
							}
						}
					}
				}
			}
			if sigil == mention_syntax.tool_mention_sigil || starts_plaintext_mention(text, index) {
				name_start := index + 1
				if name_start < bytes.len && is_mention_name_char(bytes[name_start]) {
					mut name_end := name_start + 1
					for name_end < bytes.len && is_mention_name_char(bytes[name_end]) {
						name_end++
					}

					name := (*text)[name_start..name_end]
					if sigil == mention_syntax.tool_mention_sigil
						|| ends_plaintext_mention(&bytes, name_end) {
						key := mention_token_key(sigil, &name)
						if front_path := queue_front(&mentions_by_token, &key) {
							if task_mentions.valid_thread_path(&front_path) == none {
								if path := pop_front(mut mentions_by_token, &key) {
									out << `[`
									out << u8(sigil)
									out << name.bytes()
									out << ']('.bytes()
									out << path.bytes()
									out << `)`
									index = name_end
									continue
								}
							}
						}
					}
				}
			}
		}

		ch_width := utf8_char_len(bytes[index])
		if ch_width <= 0 || index + ch_width > bytes.len {
			break
		}
		out << bytes[index..index + ch_width]
		index += ch_width
	}

	return out.bytestr()
}

pub fn decode_history_mentions_with_at_mentions(text &string, at_mentions_enabled bool) DecodedHistoryText {
	bytes := text.bytes()
	mut out := ''
	mut mentions := []LinkedMention{}
	mut task_mention_ranges := []ByteRange{}
	mut index := 0

	for index < bytes.len {
		if at_mentions_enabled {
			if link := task_mentions.parse_task_link(text, index) {
				start := out.len
				out += '@'
				out += link.title
				task_mention_ranges << ByteRange{
					start: start
					end:   out.len
				}
				mentions << LinkedMention{
					sigil:   `@`
					mention: link.title
					path:    link.path
				}
				index = link.end
				continue
			}
		}
		if bytes[index] == `[` {
			if linked := parse_history_linked_mention(text, index, at_mentions_enabled) {
				out += linked.sigil.str()
				out += linked.name
				mentions << LinkedMention{
					sigil:   linked.sigil
					mention: linked.name.clone()
					path:    linked.path.clone()
				}
				index = linked.end
				continue
			}
		}

		ch_width := utf8_char_len(bytes[index])
		if ch_width <= 0 || index + ch_width > bytes.len {
			break
		}
		out += (*text)[index..index + ch_width]
		index += ch_width
	}

	return DecodedHistoryText{
		text:                out
		mentions:            mentions
		task_mention_ranges: task_mention_ranges
	}
}

// Named stand-in for the Rust `(char, &str, &str, usize)` history-link parse result. V has no
// borrowed string slices, so the name and path are owned copies.
struct HistoryLinkedMention {
	sigil rune
	name  string
	path  string
	end   int
}

fn parse_history_linked_mention(text &string, start int, at_mentions_enabled bool) ?HistoryLinkedMention {
	// TUI historically wrote `$name`, but selected unified `@` mentions should preserve `@` on
	// history round-trip for any canonical tool path.
	if linked := parse_linked_tool_mention(text, start, mention_syntax.tool_mention_sigil) {
		if !is_common_env_var(&linked.name) && is_tool_path(&linked.path) {
			return HistoryLinkedMention{
				sigil: mention_syntax.tool_mention_sigil
				name:  linked.name
				path:  linked.path
				end:   linked.end
			}
		}
	}

	if at_mentions_enabled {
		if linked := parse_linked_tool_mention(text, start, mention_syntax.plugin_text_mention_sigil) {
			if !is_common_env_var(&linked.name) && is_tool_path(&linked.path) {
				return HistoryLinkedMention{
					sigil: mention_syntax.plugin_text_mention_sigil
					name:  linked.name
					path:  linked.path
					end:   linked.end
				}
			}
		}
	} else if linked := parse_linked_tool_mention(text, start, mention_syntax.plugin_text_mention_sigil) {
		if !is_common_env_var(&linked.name) && linked.path.starts_with('plugin://') {
			return HistoryLinkedMention{
				sigil: mention_syntax.tool_mention_sigil
				name:  linked.name
				path:  linked.path
				end:   linked.end
			}
		}
	}

	return none
}

// Named stand-in for the Rust `(&str, &str, usize)` linked-mention parse result: the mention
// name, the trimmed path, and the byte offset just past the closing `)`. V has no borrowed string
// slices, so the name and path are owned copies.
pub struct LinkedToolMention {
pub:
	name string
	path string
	end  int
}

// Parse a linked mention at an opening `[` byte, returning its name, path, and end offset.
pub fn parse_linked_tool_mention(text &string, start int, sigil rune) ?LinkedToolMention {
	text_bytes := text.bytes()
	sigil_index := start + 1
	if sigil_index < 0 || sigil_index >= text_bytes.len || text_bytes[sigil_index] != u8(sigil) {
		return none
	}

	name_start := sigil_index + 1
	if name_start >= text_bytes.len {
		return none
	}
	first_name_byte := text_bytes[name_start]
	if !is_mention_name_char(first_name_byte) {
		return none
	}

	mut name_end := name_start + 1
	for name_end < text_bytes.len && is_mention_name_char(text_bytes[name_end]) {
		name_end++
	}

	if name_end >= text_bytes.len || text_bytes[name_end] != `]` {
		return none
	}

	mut path_start := name_end + 1
	for path_start < text_bytes.len && is_ascii_whitespace(text_bytes[path_start]) {
		path_start++
	}
	if path_start >= text_bytes.len || text_bytes[path_start] != `(` {
		return none
	}

	mut path_end := path_start + 1
	for path_end < text_bytes.len && text_bytes[path_end] != `)` {
		path_end++
	}
	if path_end >= text_bytes.len || text_bytes[path_end] != `)` {
		return none
	}

	path := trim_unicode_whitespace((*text)[path_start + 1..path_end])
	if path.len == 0 {
		return none
	}

	name := (*text)[name_start..name_end]
	return LinkedToolMention{
		name: name
		path: path
		end:  path_end + 1
	}
}

pub fn is_mention_name_char(byte u8) bool {
	return (byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`)
		|| (byte >= `0` && byte <= `9`) || byte == `_` || byte == `-`
}

fn starts_plaintext_mention(text &string, index int) bool {
	if index == 0 {
		return true
	}

	prefix := str_get(text, 0, index) or { return false }
	ch := last_char(&prefix) or { return false }
	return is_rust_unicode_whitespace(ch) || !is_mention_name_char_char(ch)
}

fn ends_plaintext_mention(text_bytes &[]u8, index int) bool {
	if index >= text_bytes.len {
		return true
	}
	byte := (*text_bytes)[index]
	return is_ascii_whitespace(byte) || (byte == `.` && (index + 1 >= text_bytes.len
		|| is_ascii_whitespace((*text_bytes)[index + 1])
		|| (!is_ascii_alphanumeric((*text_bytes)[index + 1]) && (*text_bytes)[index + 1] != `_`
			&& (*text_bytes)[index + 1] != `-`)))
		|| (byte !in [`.`, `/`, `\\`] && !is_ascii_alphanumeric(byte) && byte != `_` && byte != `-`)
}

fn is_mention_name_char_char(ch rune) bool {
	return (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`)
		|| ch == `_` || ch == `-`
}

pub fn is_common_env_var(name &string) bool {
	upper := to_ascii_uppercase(name)
	return upper in ['PATH', 'HOME', 'USER', 'SHELL', 'PWD', 'TMPDIR', 'TEMP', 'TMP', 'LANG', 'TERM',
		'XDG_CONFIG_HOME']
}

fn is_tool_path(path &string) bool {
	if path.starts_with('app://') || path.starts_with('mcp://') || path.starts_with('plugin://')
		|| path.starts_with('skill://') {
		return true
	}
	// Rust takes the first item of `rsplit(['/', '\\'])`: the text after the last separator.
	mut name_start := 0
	for index, byte in path.bytes() {
		if byte == `/` || byte == `\\` {
			name_start = index + 1
		}
	}
	return to_ascii_uppercase((*path)[name_start..]) == 'SKILL.MD'
}

fn mention_token_key(sigil rune, mention &string) string {
	return sigil.str() + *mention
}

// Rust `VecDeque::front` on the queue stored under `key`; V returns an owned copy of the path.
fn queue_front(queues &map[string][]string, key &string) ?string {
	paths := (*queues)[*key] or { return none }
	if paths.len == 0 {
		return none
	}
	return paths[0].clone()
}

// Rust `VecDeque::pop_front` on the queue stored under `key`.
fn pop_front(mut queues map[string][]string, key &string) ?string {
	paths := queues[*key] or { return none }
	if paths.len == 0 {
		return none
	}
	queues[*key] = paths[1..].clone()
	return paths[0].clone()
}

// Rust `elements.iter().find(|element| element.byte_range.start == index)`, reduced to the
// matched element's end offset, which is the only field the encoder reads.
fn element_end_starting_at(elements &[]user_input.TextElement, index int) ?int {
	for element in elements {
		if element.byte_range.start == index {
			return element.byte_range.end
		}
	}
	return none
}

// Rust `str::get(start..end)`: `none` unless both offsets are in bounds, ordered, and on UTF-8
// character boundaries.
fn str_get(text &string, start int, end int) ?string {
	if start < 0 || end < start || end > text.len || !is_char_boundary(text, start)
		|| !is_char_boundary(text, end) {
		return none
	}
	return (*text)[start..end]
}

fn is_char_boundary(text &string, index int) bool {
	return index == 0 || index == text.len
		|| (index > 0 && index < text.len && ((*text)[index] & 0xc0) != 0x80)
}

// Rust `str::chars().next_back()`.
fn last_char(text &string) ?rune {
	if text.len == 0 {
		return none
	}
	mut start := text.len - 1
	for start > 0 && ((*text)[start] & 0xc0) == 0x80 {
		start--
	}
	runes := (*text)[start..].runes()
	if runes.len == 0 {
		return none
	}
	return runes[0]
}

// Rust `u8::is_ascii_whitespace`: space, tab, line feed, form feed, and carriage return. Unlike
// V's `u8.is_space`, it excludes vertical tab.
fn is_ascii_whitespace(byte u8) bool {
	return byte == ` ` || byte == `\t` || byte == `\n` || byte == `\f` || byte == `\r`
}

fn is_ascii_alphanumeric(byte u8) bool {
	return (byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`)
		|| (byte >= `0` && byte <= `9`)
}

// Rust `str::to_ascii_uppercase`: only ASCII letters change.
fn to_ascii_uppercase(text &string) string {
	mut upper := text.bytes()
	for index, byte in upper {
		if byte >= `a` && byte <= `z` {
			upper[index] = byte - 32
		}
	}
	return upper.bytestr()
}

// Rust `str::trim`, which removes Unicode `White_Space` characters rather than only ASCII space.
fn trim_unicode_whitespace(text string) string {
	runes := text.runes()
	mut start := 0
	for start < runes.len && is_rust_unicode_whitespace(runes[start]) {
		start++
	}
	mut end := runes.len
	for end > start && is_rust_unicode_whitespace(runes[end - 1]) {
		end--
	}
	return runes[start..end].string()
}

// Rust `char::is_whitespace`.
fn is_rust_unicode_whitespace(value rune) bool {
	return value in [` `, `\t`, `\n`, `\r`, `\v`, `\f`, `\u0085`, ` `, ` `, ` `, ` `, ` `,
		` `, ` `, ` `, ` `, ` `, ` `, ` `, ` `, ` `, ` `, ` `, ` `, `　`]
}
