module pulldown_cmark

#include "@VMODROOT/pulldown_cmark/clipboard_html_native.h"

// STUB: native typed event storage copied into pulldown-cmark Event values.
struct C.CodexClipboardNativeEvent {
	kind                      int
	tag                       int
	level                     int
	ordered                   int
	code_kind                 int
	list_start                u64
	text                      &char
	destination               &char
	title                     &char
	text_entity_starts        &u8
	destination_entity_starts &u8
	title_entity_starts       &u8
	text_length               usize
	destination_length        usize
	title_length              usize
	alignments                &int
	alignment_count           usize
}

// STUB: opaque native parser state exposes only its event vector for copying.
struct C.CodexClipboardNativeParser {
	events &C.CodexClipboardNativeEvent
	count  usize
}

// STUB: native CommonMark parser borrows source only for the duration of this call.
fn C.codex_clipboard_parser_new(source &char, length usize, flags u32) &C.CodexClipboardNativeParser
// STUB: release all temporary native event strings and parser storage.
fn C.codex_clipboard_parser_free(parser &C.CodexClipboardNativeParser)
// STUB: complete pulldown-cmark HTML5 named entity lookup; result is static data.
fn C.codex_clipboard_entity_lookup(name &char, length usize, output_length &usize) &char
