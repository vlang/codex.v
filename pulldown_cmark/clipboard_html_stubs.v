module pulldown_cmark

import strings

// STUB: the two pulldown-cmark Options flags observed by clipboard_html.rs.
@[flag]
pub enum Options {
	enable_strikethrough
	enable_tables
}

// STUB: pulldown-cmark's Parser is backed by self-contained CommonMark MD4C.
// The native callback data is copied into owned events, because V cannot express
// the source parser's borrowed event lifetime. No fixture or Rust checkout is
// consulted at runtime. Extensions other than these two flags are unavailable.
// Reference-link IDs and the exact inline/reference/autolink LinkType distinction
// are not exposed by MD4C; this boundary retains the resolved URL and title that
// clipboard_html observes. Native email autolinks carry their mailto: URL, so
// the web-link policy still rejects them while preserving the visible target.
pub struct Parser {
mut:
	events []Event
	index  int
}

// STUB: Parser::new_ext preserves the shared Markdown input and extension flags.
pub fn Parser.new_ext(source &string, options Options) Parser {
	mut native_flags := u32(0)
	if options.has(.enable_tables) {
		native_flags |= 0x100
	}
	if options.has(.enable_strikethrough) {
		native_flags |= 0x200
	}
	native := C.codex_clipboard_parser_new(source.str, usize(source.len), native_flags)
	if isnil(native) { panic('CommonMark parser allocation or input-size failure') }
	defer { C.codex_clipboard_parser_free(native) }
	mut events := []Event{cap: int(native.count)}
	for index in 0 .. int(native.count) {
		item := unsafe { &native.events[index] }
		kind := if item.kind == 12 { EventKind.text } else { unsafe { EventKind(item.kind) } }
		if kind == .start {
			tag_kind := unsafe { TagKind(item.tag) }
			mut alignments := []Alignment{cap: int(item.alignment_count)}
			for column in 0 .. int(item.alignment_count) {
				alignments << unsafe { Alignment(item.alignments[column]) }
			}
			info := clipboard_native_string(item.text, item.text_length)
			destination := clipboard_native_string(item.destination, item.destination_length)
			title := clipboard_native_string(item.title, item.title_length)
			events << Event{
				kind: .start
				tag:  Tag{
					kind:       tag_kind
					level:      if item.level == 0 {
						HeadingLevel.h1
					} else {
						unsafe { HeadingLevel(item.level) }
					}
					code_block: CodeBlockKind{
						kind:     if item.code_kind != 0 {
							.fenced
						} else {
							.indented
						}
						language: CowStr.from_string(clipboard_decode_entities(&info, item.text_entity_starts))
					}
					list_start: if item.ordered != 0 { ?u64(item.list_start) } else { none }
					alignments: alignments
					dest_url:   CowStr.from_string(clipboard_decode_entities(&destination, item.destination_entity_starts))
					title:      CowStr.from_string(clipboard_decode_entities(&title, item.title_entity_starts))
				}
			}
		} else if kind == .end {
			events << Event{
				kind:    .end
				tag_end: TagEnd{
					kind:    unsafe { TagKind(item.tag) }
					level:   if item.level == 0 {
						HeadingLevel.h1
					} else {
						unsafe { HeadingLevel(item.level) }
					}
					ordered: item.ordered != 0
				}
			}
		} else {
			text := clipboard_native_string(item.text, item.text_length)
			events << Event{
				kind: kind
				text: CowStr.from_string(if item.kind == 12 {
					clipboard_decode_entities(&text, unsafe { nil })
				} else {
					text
				})
			}
		}
	}
	return Parser{ events: events }
}

// STUB: Parser's owned Iterator::next removes each event from its backing slot.
pub fn (mut parser Parser) next() ?Event {
	if parser.index >= parser.events.len {
		return none
	}
	index := parser.index
	parser.index++
	event := parser.events[index]
	parser.events[index] = Event{}
	return event
}

// STUB: Iterator::filter_map carries the original closure's mutable state as a
// named V value. The event and parser remain consumed; the mapper borrows state.
pub struct FilterMap[S] {
mut:
	parser Parser
	state  S
	mapper fn (Event, mut S) ?Event = unsafe { nil }
}

// STUB: Iterator::filter_map's owned adapter, avoiding mutable closure captures.
pub fn (parser Parser) filter_map[S](state S, mapper fn (Event, mut S) ?Event) FilterMap[S] {
	return FilterMap[S]{ parser: parser, state: state, mapper: mapper }
}

// STUB: FilterMap's Iterator::next filters until a mapper emits an owned event.
pub fn (mut iterator FilterMap[S]) next[S]() ?Event {
	for {
		event := iterator.parser.next() or { return none }
		if mapped := iterator.mapper(event, mut iterator.state) {
			return mapped
		}
	}
	return none
}

// STUB: moving a Tag through a link destination update preserves every payload,
// including its source link type, title, and reference identifier.
pub fn (tag Tag) with_link_destination(destination CowStr) Tag {
	return Tag{
		kind:           tag.kind
		level:          tag.level
		id:             tag.id
		classes:        tag.classes
		attrs:          tag.attrs
		code_block:     tag.code_block
		list_start:     tag.list_start
		footnote_label: tag.footnote_label
		alignments:     tag.alignments
		link_type:      tag.link_type
		dest_url:       destination
		title:          tag.title
		link_id:        tag.link_id
		metadata_kind:  tag.metadata_kind
	}
}

// STUB: native callback strings must be copied before their scratch owner drops.
fn clipboard_native_string(data &char, length usize) string {
	if length == 0 {
		return ''.clone()
	}
	return unsafe { data.vstring_literal_with_len(int(length)).clone() }
}

// STUB: CommonMark entity decoding uses pulldown-cmark's complete HTML5 named
// entity table, including two-scalar entities; numeric references are Unicode
// scalars with U+FFFD for zero, surrogates, and out-of-range values.
fn clipboard_decode_entities(input &string, entity_starts &u8) string {
	mut out := strings.new_builder(input.len)
	mut position := 0
	for position < input.len {
		if (*input)[position] == 0 {
			out.write_string('\uFFFD')
			position++
			continue
		}
		if (*input)[position] != `&` || (!isnil(entity_starts) && unsafe { entity_starts[position] } == 0) {
			out.write_u8((*input)[position])
			position++
			continue
		}
		mut end := position + 1
		for end < input.len && end - position <= 50 && (*input)[end] != `;` && (*input)[end] != `&` {
			end++
		}
		if end >= input.len || (*input)[end] != `;` {
			out.write_u8(`&`)
			position++
			continue
		}
		name := (*input)[position + 1..end]
		mut decoded := false
		if name.starts_with('#') {
			mut index := 1
			mut radix := u32(10)
			if index < name.len && name[index] in [`x`, `X`] {
				radix = 16
				index++
			}
			start := index
			mut value := u32(0)
			mut valid := true
			for index < name.len {
				ch := name[index]
				digit := if ch >= `0` && ch <= `9` {
					int(ch - `0`)
				} else if ch >= `a` && ch <= `f` {
					int(ch - `a`) + 10
				} else if ch >= `A` && ch <= `F` {
					int(ch - `A`) + 10
				} else {
					-1
				}
				if digit < 0 || u32(digit) >= radix {
					valid = false
					break
				}
				if value <= 0x110000 {
					value = value * radix + u32(digit)
				}
				index++
			}
			if valid && index > start && index - start <= (if radix == 16 { 6 } else { 7 }) {
				if value == 0 || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff) {
					value = 0xfffd
				}
				out.write_string(rune(value).str())
				decoded = true
			}
		} else {
			mut length := usize(0)
			data := C.codex_clipboard_entity_lookup(name.str, usize(name.len), &length)
			if !isnil(data) {
				out.write_string(clipboard_native_string(data, length))
				decoded = true
			}
		}
		if !decoded { out.write_string((*input)[position..end + 1]) }
		position = end + 1
	}
	return out.str()
}
