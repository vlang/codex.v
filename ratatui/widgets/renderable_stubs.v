module widgets

import math
import ratatui.buffer
import ratatui.layout
import ratatui.style
import ratatui.text
import unicode_segmentation
import unicode_width

// STUB: ratatui::widgets::Widget for a shared widget reference. Consuming Widget
// implementations are outside this boundary; the renderable target invokes Widget for &Line.
pub interface Widget {
	render(area layout.Rect, mut buf buffer.Buffer)
}

// STUB: ratatui::widgets::WidgetRef's shared rendering signature.
pub interface WidgetRef {
	render_ref(area layout.Rect, mut buf buffer.Buffer)
}

// STUB: ratatui::widgets::Widget::render(&widget, area, buffer).
pub fn render(widget &Widget, area layout.Rect, mut buf buffer.Buffer) {
	widget.render(area, mut buf)
}

// STUB: ratatui::widgets::WidgetRef for &str and String. V cannot add builtin methods.
pub fn render_string_ref(value &string, area layout.Rect, mut buf buffer.Buffer) {
	buf.set_stringn(area.x, area.y, value, usize(area.width), style.Style{})
}

// STUB: ratatui::widgets::Wrap, retaining the Copy-equivalent trim flag.
pub struct Wrap {
pub:
	trim bool
}

// STUB: ratatui::widgets::Paragraph observed text/style/wrap/scroll/alignment state.
// Block rendering is outside this boundary; shared rendering borrows the owned text.
pub struct Paragraph {
	lines               []text.Line
	paragraph_style     style.Style
	wrapping            ?Wrap
	vertical_offset     u16
	horizontal_offset   u16
	paragraph_alignment layout.Alignment
}

// STUB: Paragraph::new<T: Into<Text>> for the owned string, Line and Vec<Line> forms.
// Rust Text::raw(String) owns each newline-split line via to_owned; V split does likewise.
pub fn Paragraph.new[T](content T) Paragraph {
	$if T is string {
		return paragraph_from_string(content)
	} $else $if T is text.Line {
		return Paragraph{ lines: [content] }
	} $else $if T is []text.Line {
		return Paragraph{ lines: content }
	} $else {
		$compile_error('Paragraph.new supports owned string, text.Line or []text.Line')
	}
}

// STUB: Text::raw(Cow::Owned) converts Rust's newline-delimited borrowed rows to owned Lines.
fn paragraph_from_string(content string) Paragraph {
	mut lines := []text.Line{}
	if content.len == 0 {
		lines << text.line_from('')
	} else {
		parts := content.split('\n')
		last := if content.ends_with('\n') { parts.len - 1 } else { parts.len }
		for i in 0 .. last {
			part := &parts[i]
			line := if i + 1 < parts.len && part.ends_with('\r') {
				(*part)[..part.len - 1]
			} else {
				*part
			}
			lines << text.line_from(line.clone())
		}
	}
	return Paragraph{ lines: lines }
}

// STUB: Paragraph::style consumes the widget and replaces its allocation-free style.
pub fn (paragraph Paragraph) style(paragraph_style style.Style) Paragraph {
	return Paragraph{ ...paragraph, paragraph_style: paragraph_style }
}

// STUB: Paragraph::wrap consumes the widget and installs the wrapping configuration.
pub fn (paragraph Paragraph) wrap(wrapping Wrap) Paragraph {
	return Paragraph{ ...paragraph, wrapping: wrapping }
}

// STUB: Paragraph::scroll consumes the widget; Rust's tuple is (vertical, horizontal).
pub fn (paragraph Paragraph) scroll(vertical u16, horizontal u16) Paragraph {
	return Paragraph{ ...paragraph, vertical_offset: vertical, horizontal_offset: horizontal }
}

// STUB: Paragraph::alignment consumes the widget and replaces its default alignment.
pub fn (paragraph Paragraph) alignment(alignment layout.Alignment) Paragraph {
	return Paragraph{ ...paragraph, paragraph_alignment: alignment }
}

// STUB: a borrowing StyledGrapheme view using byte offsets into its original Span owner.
struct ParagraphGrapheme {
	source         &string
	start          int
	end            int
	width          u16
	whitespace     bool
	grapheme_style style.Style
}

// STUB: one reflowed Paragraph row; graphemes retain shared references to their text owners.
struct ParagraphRow {
	graphemes []ParagraphGrapheme
	width     u16
	alignment layout.Alignment
}

// STUB: Span::styled_graphemes filtered newline and style-patch boundary.
fn paragraph_graphemes(line &text.Line, base style.Style) []ParagraphGrapheme {
	mut result := []ParagraphGrapheme{}
	for i in 0 .. line.spans.len {
		span := &line.spans[i]
		offsets := unicode_segmentation.grapheme_indices(&span.text, true)
		for j, start in offsets {
			end := if j + 1 < offsets.len { offsets[j + 1] } else { span.text.len }
			symbol := span.text[start..end]
			if symbol == '\n' {
				continue
			}
			runes := symbol.runes()
			result << ParagraphGrapheme{
				source:         &span.text
				start:          start
				end:            end
				width:          u16(unicode_width.width(&symbol))
				whitespace:     (symbol == '\u200b' || (symbol != '\u00a0' && runes.all(paragraph_is_whitespace(it))))
				grapheme_style: base.patch(line.style).patch(span.style)
			}
		}
	}
	return result
}

// STUB: ratatui WordWrapper::process_input packing transitions, without allocation pools.
// Buffer pools affect allocation only; input graphemes remain borrowed in every wrapped row.
fn wrap_paragraph_line(symbols []ParagraphGrapheme, width u16, trim bool, alignment layout.Alignment, mut wrapped_rows []ParagraphRow) {
	initial_row_count := wrapped_rows.len
	mut pending_line := []ParagraphGrapheme{}
	mut pending_word := []ParagraphGrapheme{}
	mut pending_whitespace := []ParagraphGrapheme{}
	mut line_width := u16(0)
	mut word_width := u16(0)
	mut whitespace_width := u16(0)
	mut non_whitespace_previous := false
	for grapheme in symbols {
		is_whitespace := grapheme.whitespace
		symbol_width := grapheme.width
		if symbol_width > width {
			continue
		}
		word_found := non_whitespace_previous && is_whitespace
		trimmed_overflow := pending_line.len == 0 && trim && word_width + symbol_width > width
		whitespace_overflow := pending_line.len == 0 && trim && whitespace_width + symbol_width > width
		untrimmed_overflow := pending_line.len == 0 && !trim && word_width + whitespace_width + symbol_width > width
		if word_found || trimmed_overflow || whitespace_overflow || untrimmed_overflow {
			if pending_line.len > 0 || !trim {
				pending_line << pending_whitespace
				line_width += whitespace_width
			}
			pending_line << pending_word
			line_width += word_width
			pending_word = []ParagraphGrapheme{}
			pending_whitespace = []ParagraphGrapheme{}
			whitespace_width = 0
			word_width = 0
		}
		line_full := line_width >= width
		pending_word_overflow := symbol_width > 0 && line_width + whitespace_width + word_width >= width
		if line_full || pending_word_overflow {
			mut remaining_width := if width > line_width { width - line_width } else { u16(0) }
			wrapped_rows << ParagraphRow{ graphemes: pending_line, width: line_width, alignment: alignment }
			pending_line = []ParagraphGrapheme{}
			line_width = 0
			mut removed := 0
			for removed < pending_whitespace.len {
				w := pending_whitespace[removed].width
				if w > remaining_width {
					break
				}
				whitespace_width -= w
				remaining_width -= w
				removed++
			}
			pending_whitespace.delete_many(0, removed)
			if is_whitespace && pending_whitespace.len == 0 {
				continue
			}
		}
		if is_whitespace {
			whitespace_width += symbol_width
			pending_whitespace << grapheme
		} else {
			word_width += symbol_width
			pending_word << grapheme
		}
		non_whitespace_previous = !is_whitespace
	}
	if pending_line.len == 0 && pending_word.len == 0 && pending_whitespace.len > 0 && trim {
		wrapped_rows << ParagraphRow{ alignment: alignment }
	}
	if pending_line.len > 0 || !trim {
		pending_line << pending_whitespace
		line_width += whitespace_width
	}
	pending_line << pending_word
	line_width += word_width
	if pending_line.len > 0 {
		wrapped_rows << ParagraphRow{ graphemes: pending_line, width: line_width, alignment: alignment }
	}
	if wrapped_rows.len == initial_row_count {
		wrapped_rows << ParagraphRow{ alignment: alignment }
	}
}

// STUB: Paragraph::line_count and rendering share the same WordWrapper/LineTruncator boundary.
fn (paragraph &Paragraph) rows(width u16) []ParagraphRow {
	if width == 0 {
		return []ParagraphRow{}
	}
	lines := &paragraph.lines
	mut rows := []ParagraphRow{}
	for i in 0 .. lines.len {
		line := &(*lines)[i]
		alignment := line.alignment or { paragraph.paragraph_alignment }
		symbols := paragraph_graphemes(line, paragraph.paragraph_style)
		if wrapping := paragraph.wrapping {
			wrap_paragraph_line(symbols, width, wrapping.trim, alignment, mut rows)
		} else {
			mut visible := []ParagraphGrapheme{}
			mut row_width := u16(0)
			mut horizontal_offset := paragraph.horizontal_offset
			for symbol in symbols {
				if symbol.width > width {
					continue
				}
				if row_width + symbol.width > width {
					break
				}
				if alignment == .left && horizontal_offset > 0 {
					if symbol.width <= horizontal_offset {
						horizontal_offset -= symbol.width
						continue
					}
					horizontal_offset = 0
				}
				row_width += symbol.width
				visible << symbol
			}
			rows << ParagraphRow{ graphemes: visible, width: row_width, alignment: alignment }
		}
	}
	return rows
}

// STUB: Paragraph::line_count, including the source's zero-width result.
pub fn (paragraph &Paragraph) line_count(width u16) usize {
	if width == 0 {
		return 0
	}
	if paragraph.wrapping == none {
		return usize(paragraph.lines.len)
	}
	return usize(paragraph.rows(width).len)
}

// STUB: Paragraph::render_ref, keeping styles, wrapping, alignment, scrolling and buffer clipping.
pub fn (paragraph &Paragraph) render_ref(area layout.Rect, mut buf buffer.Buffer) {
	clipped := area.intersection(buf.area)
	buf.set_style(clipped, paragraph.paragraph_style)
	if clipped.is_empty() {
		return
	}
	rows := paragraph.rows(clipped.width)
	mut y := clipped.y
	for i in int(paragraph.vertical_offset) .. rows.len {
		if y >= clipped.bottom() {
			break
		}
		row := &rows[i]
		mut x := clipped.x + match row.alignment {
			.left { u16(0) }
			.center { clipped.width / 2 - math.min(clipped.width / 2, row.width / 2) }
			.right { clipped.width - math.min(clipped.width, row.width) }
		}
		for symbol in row.graphemes {
			if symbol.width == 0 {
				continue
			}
			value := (*symbol.source)[symbol.start..symbol.end]
			buf.put_cell(x, y, value.clone(), symbol.grapheme_style)
			for offset in 1 .. int(symbol.width) {
				buf.put_cell(x + u16(offset), y, ' ', style.Style{})
			}
			x += symbol.width
		}
		y++
	}
}

// STUB: Rust char::is_whitespace's Unicode White_Space property used by WordWrapper.
fn paragraph_is_whitespace(value rune) bool {
	return value in [rune(0x09), 0x0a, 0x0b, 0x0c, 0x0d, 0x20, 0x85, 0xa0, 0x1680, 0x2028, 0x2029,
		0x202f, 0x205f, 0x3000] || (value >= 0x2000 && value <= 0x200a)
}
