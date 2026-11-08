// Markdown text-event merging that preserves parser-decoded contents and source offsets.
module markdown_text_merge

import pulldown_cmark
import std_iter
import std_ops

// V represents Rust's associated (Event, Range<usize>) iterator item as a named pair.
pub struct EventRange {
pub:
	event pulldown_cmark.Event
pub mut:
	range std_ops.Range[usize]
}

// Merges adjacent parsed text events without reconstructing them from the Markdown source.
//
// Markdown extensions can split visually contiguous text around delimiter characters. Keeping the
// decoded event contents together lets downstream consumers recognize tokens that span those
// parser boundaries while the combined source range remains available for offset-aware rendering.
pub struct DecodedTextMerge[I] {
mut:
	iter std_iter.Peekable[I, EventRange]
}

pub fn DecodedTextMerge.new[I](iter I) DecodedTextMerge[I] {
	return DecodedTextMerge[I]{
		iter: std_iter.peekable[I, EventRange](iter)
	}
}

pub fn (mut merge DecodedTextMerge[I]) next[I]() ?EventRange {
	mut item := merge.iter.next() or { return none }
	if item.event.kind != .text {
		return item
	}
	peeked := merge.iter.peek()
	if !peeked.present || peeked.value.event.kind != .text {
		return item
	}

	mut merged := item.event.text.into_string()
	for {
		next_peek := merge.iter.peek()
		if !next_peek.present || next_peek.value.event.kind != .text {
			break
		}
		next_item := merge.iter.next() or { break }
		if next_item.event.kind != .text {
			break
		}
		// V strings are immutable: concatenation replaces Rust String::push_str's mutable buffer.
		// The appended CowStr remains borrowed and the first string moves at into_string above.
		merged += *next_item.event.text.as_str()
		item.range.end = next_item.range.end
	}
	return EventRange{
		event: pulldown_cmark.Event{
			kind: .text
			text: pulldown_cmark.CowStr.from_string(merged)
		}
		range: item.range
	}
}
