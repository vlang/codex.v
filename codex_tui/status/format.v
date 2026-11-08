module status

import codex_tui.width
import ratatui.text
import std_collections
import unicode_segmentation

// V has no associated constants; this is FieldFormatter::INDENT.
pub const field_formatter_indent = ' '

pub struct FieldFormatter {
	indent       &string = &field_formatter_indent
	label_width  usize
	value_offset usize
	value_indent string
}

// Rust's IntoIterator/AsRef<str> bounds are supplied by into_iter() and as_ref()
// methods. I is consumed, while each item's shared string is borrowed only for
// computing its width. std_iter supplies owned-array and borrowed-slice adapters.
pub fn FieldFormatter.from_labels[I](labels I) FieldFormatter {
	mut label_width := usize(0)
	mut iter := labels.into_iter()
	for {
		label := iter.next() or { break }
		current_width := width.display_width(label_string_ref(&label))
		if current_width > label_width {
			label_width = current_width
		}
	}
	indent_width := width.display_width(&field_formatter_indent)
	value_offset := indent_width + label_width + 1 + 3
	return FieldFormatter{
		indent:       &field_formatter_indent
		label_width:  label_width
		value_offset: value_offset
		value_indent: ' '.repeat(int(value_offset))
	}
}

// Rust's derived Clone duplicates the owned indentation and copies the static
// indentation reference and scalar widths.
pub fn (formatter &FieldFormatter) clone() FieldFormatter {
	return FieldFormatter{
		indent:       formatter.indent
		label_width:  formatter.label_width
		value_offset: formatter.value_offset
		value_indent: formatter.value_indent.clone()
	}
}

pub fn (formatter &FieldFormatter) line(label &string, value_spans []text.Span) text.Line {
	value := FormatConsumedSpans{ values: value_spans }
	spans := formatter.full_spans(label, value.values)
	return text.line_from_spans(spans)
}

pub fn (formatter &FieldFormatter) continuation(spans []text.Span) text.Line {
	mut all_spans := []text.Span{cap: spans.len + 1}
	indent := text.Span{ text: formatter.value_indent.clone() }
	dim_indent := indent.dim()
	all_spans << dim_indent
	mut remaining := FormatConsumedSpans{ values: spans }
	remaining.values.reverse_in_place()
	span_count := remaining.values.len
	for _ in 0 .. span_count {
		all_spans << remaining.values.pop()
	}
	return text.line_from_spans(all_spans)
}

pub fn (formatter &FieldFormatter) value_width(available_inner_width usize) usize {
	return if available_inner_width >= formatter.value_offset {
		available_inner_width - formatter.value_offset
	} else {
		0
	}
}

pub fn (formatter &FieldFormatter) full_spans(label &string, value_spans []text.Span) []text.Span {
	mut spans := []text.Span{cap: value_spans.len + 1}
	spans << formatter.label_span(label)
	mut remaining := FormatConsumedSpans{ values: value_spans }
	remaining.values.reverse_in_place()
	span_count := remaining.values.len
	for _ in 0 .. span_count {
		spans << remaining.values.pop()
	}
	return spans
}

fn (formatter &FieldFormatter) label_span(label &string) text.Span {
	// V strings are immutable; concatenation assembles the owned buffer at the
	// same boundary as Rust String::push_str without moving the borrowed label.
	mut buf := '${*formatter.indent}${*label}:'
	label_width := width.display_width(label)
	padding := 3 + if formatter.label_width >= label_width {
		formatter.label_width - label_width
	} else {
		0
	}
	for _ in 0 .. padding {
		buf += ' '
	}
	return text.Span{ text: buf }.dim()
}

pub fn push_label(mut labels []string, mut seen std_collections.BTreeSet[string], label &string) {
	if seen.contains(label) {
		return
	}
	owned := label.clone()
	seen.insert(owned.clone())
	labels << owned
}

// A local consumed container makes an immutable owned span-array parameter
// mutable without constructing a borrowed alias of its collection.
struct FormatConsumedSpans {
mut:
	values []text.Span
}

pub fn truncate_line_to_width(line text.Line, max_width usize) text.Line {
	if max_width == 0 {
		return text.line_from_spans([]text.Span{})
	}
	mut used := usize(0)
	mut spans_out := []text.Span{}
	// V's value iteration clones resource-owning spans. Reverse the consumed
	// collection in place and pop to keep Rust's forward consuming traversal.
	mut remaining := FormatConsumedSpans{ values: line.spans }
	remaining.values.reverse_in_place()
	span_count := remaining.values.len
	for _ in 0 .. span_count {
		span := remaining.values.pop()
		// Span stores owned V text in place of Cow<str>; consuming it corresponds
		// to Cow::into_owned and does not require another allocation or clone.
		content := span.text
		span_style := span.style
		span_width := width.display_width(&content)
		if span_width == 0 {
			spans_out << text.span_styled(content, span_style)
			continue
		}
		if used >= max_width {
			break
		}
		if used + span_width <= max_width {
			used += span_width
			spans_out << text.span_styled(content, span_style)
			continue
		}
		mut truncated := ''
		// The shared segmentation API returns offsets rather than Rust's borrowed
		// grapheme iterator. Temporary V slices remain within the owned text's life.
		graphemes := unicode_segmentation.grapheme_indices(&content, /* is_extended */
			true)
		for position, start in graphemes {
			end := if position + 1 < graphemes.len { graphemes[position + 1] } else { content.len }
			grapheme := content[start..end]
			grapheme_width := width.display_width(&grapheme)
			if used + grapheme_width > max_width {
				break
			}
			truncated += grapheme
			used += grapheme_width
		}
		if truncated.len > 0 {
			spans_out << text.span_styled(truncated, span_style)
		}
		break
	}
	return text.line_from_spans(spans_out)
}

// Rust AsRef<str> supplies a shared slice. V strings and string references cover
// String/&str; custom item types retain their source-shaped as_ref() operation.
fn label_string_ref[T](label &T) &string {
	$if T is string {
		return label
	} $else $if T is &string {
		return *label
	} $else {
		return label.as_ref()
	}
}
