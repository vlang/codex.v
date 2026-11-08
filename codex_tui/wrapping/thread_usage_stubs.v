module wrapping

import codex_tui.width as tui_width
import ratatui.text
import ratatui.style
import unicode_segmentation

// STUB: tui/src/wrapping.rs::RtOptions, the width observed by thread_usage.rs.
// RtOptions::new defaults to LF, empty indents, FirstFit, the default word
// separator, HyphenSplitter, and break_words=true. Other option builders and
// adaptive/URL wrapping belong to the untranslated wrapping owner.
pub struct RtOptions {
pub:
	width usize
}

// STUB: tui/src/wrapping.rs::RtOptions::new for the default options above.
pub fn RtOptions.new(width usize) RtOptions {
	return RtOptions{ width: width }
}

// STUB: tui/src/wrapping.rs::word_wrap_lines, consuming styled billing lines.
// This boundary supplies FirstFit's ASCII-space/hyphen words, display-width
// breaks, source-span styles and LF handling. Full Unicode line-break property
// tables and nondefault options await the actual wrapping module translation.
pub fn word_wrap_lines(lines []text.Line, options RtOptions) []text.Line {
	mut input := ThreadUsageConsumedLines{ values: lines }
	input.values.reverse_in_place()
	count := input.values.len
	mut out := []text.Line{}
	for _ in 0 .. count {
		line := input.values.pop()
		mut flat := ''
		mut bounds := []ThreadUsageSpanBounds{}
		for index in 0 .. line.spans.len {
			span := &line.spans[index]
			start := flat.len
			flat += span.text
			bounds << ThreadUsageSpanBounds{ start: start, end: flat.len, style: span.style }
		}
		available := if options.width > 0 { options.width } else { usize(1) }
		ranges := thread_usage_wrap_ranges(&flat, available)
		for range in ranges {
			mut spans := []text.Span{}
			for bound in bounds {
				start := if range.start > bound.start { range.start } else { bound.start }
				end := if range.end < bound.end { range.end } else { bound.end }
				if end > start {
					content := flat[start..end].clone()
					spans << text.span_styled(content, bound.style.patch(line.style))
				}
			}
			out << text.Line{ style: line.style, spans: spans }
		}
	}
	return out
}

// STUB: private owned-iterator storage for word_wrap_lines's external boundary.
struct ThreadUsageConsumedLines {
mut:
	values []text.Line
}

// STUB: flattened source-span ranges from tui/src/wrapping.rs::flatten_line.
struct ThreadUsageSpanBounds {
	start int
	end   int
	style style.Style
}

// STUB: the byte ranges observed by word_wrap_line's slicing boundary.
struct ThreadUsageWrapRange {
	start int
	end   int
}

// STUB: textwrap default word fragments used by FirstFit for billing text.
struct ThreadUsageWord {
	start   int
	end     int
	next    int
	columns usize
}

// STUB: default textwrap FirstFit source ranges, with LF and long-word breaking.
fn thread_usage_wrap_ranges(value &string, columns usize) []ThreadUsageWrapRange {
	mut ranges := []ThreadUsageWrapRange{}
	mut base := 0
	mut first := true
	for segment in value.split('\n') {
		mut words := []ThreadUsageWord{}
		mut cursor := 0
		for cursor < segment.len {
			start := cursor
			for cursor < segment.len && segment[cursor] != ` ` {
				cursor++
			}
			end := cursor
			for cursor < segment.len && segment[cursor] == ` ` {
				cursor++
			}
			next := cursor
			content := segment[start..end]
			mut splits := [0]
			offsets := unicode_segmentation.grapheme_indices(&content, true)
			mut used := usize(0)
			for i, offset in offsets {
				finish := if i + 1 < offsets.len { offsets[i + 1] } else { content.len }
				grapheme := content[offset..finish]
				count := tui_width.display_width(&grapheme)
				if used > 0 && used + count > columns {
					splits << offset
					used = 0
				}
				used += count
				if grapheme == '-' && i > 0 && i + 1 < offsets.len {
					before := content[offsets[i - 1]..offset]
					after_end := if i + 2 < offsets.len { offsets[i + 2] } else { content.len }
					after := content[offsets[i + 1]..after_end]
					if thread_usage_ascii_alphanumeric(&before) && thread_usage_ascii_alphanumeric(&after) {
						splits << finish
						used = 0
					}
				}
			}
			if splits.last() != content.len { splits << content.len }
			if content.len == 0 {
				words << ThreadUsageWord{ start: start, end: end, next: next }
			} else {
				for i in 0 .. splits.len - 1 {
					begin := start + splits[i]
					finish := start + splits[i + 1]
					piece := segment[begin..finish]
					words << ThreadUsageWord{
						start:   begin
						end:     finish
						next:    if i + 1 == splits.len - 1 {
							next
						} else {
							finish
						}
						columns: tui_width.display_width(&piece)
					}
				}
			}
		}
		if words.len == 0 {
			if first {
				ranges << ThreadUsageWrapRange{ start: base, end: base }
				first = false
			}
		} else {
			mut begin := words[0].start
			mut end := begin
			mut used := usize(0)
			mut pending_spaces := usize(0)
			mut has_word := false
			for word in words {
				if has_word && used + pending_spaces + word.columns > columns {
					if end > begin || first {
						ranges << ThreadUsageWrapRange{ start: base + begin, end: base + end }
						first = false
					}
					begin = word.start
					used = 0
					pending_spaces = 0
					has_word = false
				}
				used += pending_spaces + word.columns
				end = word.end
				pending_spaces = usize(word.next - word.end)
				has_word = true
			}
			if end > begin || first {
				ranges << ThreadUsageWrapRange{ start: base + begin, end: base + end }
				first = false
			}
		}
		base += segment.len + 1
	}
	return ranges
}

// STUB: HyphenSplitter's ASCII alphanumeric boundary for generated billing labels.
fn thread_usage_ascii_alphanumeric(value &string) bool {
	if value.len != 1 {
		return false
	}
	character := (*value)[0]
	return (character >= `0` && character <= `9`) || (character >= `A` && character <= `Z`) || (character >= `a` && character <= `z`)
}
