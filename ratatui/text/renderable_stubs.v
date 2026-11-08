module text

import ratatui.buffer
import ratatui.layout
import ratatui.style
import unicode_segmentation
import unicode_width

// STUB: ratatui::text::Span::render_ref, pending full terminal-cell normalization.
// Shared text stays owned by the Span; each symbol stored in Buffer is an owned copy.
pub fn (span &Span) render_ref(area layout.Rect, mut buf buffer.Buffer) {
	clipped := area.intersection(buf.area)
	if clipped.is_empty() {
		return
	}
	mut x := clipped.x
	offsets := unicode_segmentation.grapheme_indices(&span.text, true)
	for i, start in offsets {
		end := if i + 1 < offsets.len { offsets[i + 1] } else { span.text.len }
		symbol := span.text[start..end]
		if symbol == '\n' {
			continue
		}
		width := u16(unicode_width.width(&symbol))
		if u32(x) + u32(width) > u32(clipped.right()) {
			break
		}
		if width == 0 {
			previous_x := if x == clipped.x { x } else { x - 1 }
			for mut cell in buf.cells {
				if cell.x == previous_x && cell.y == clipped.y {
					cell.symbol += symbol
					cell.style = cell.style.patch(span.style)
					break
				}
			}
		} else {
			buf.put_cell(x, clipped.y, symbol.clone(), span.style)
			for offset in 1 .. int(width) {
				buf.put_cell(x + u16(offset), clipped.y, ' ', style.Style{})
			}
		}
		x += width
	}
}

// STUB: ratatui::text::Line::Widget::render(&Line). This shared receiver is the Rust
// Widget implementation for a reference, so rendering never consumes the owned span array.
pub fn (line &Line) render(area layout.Rect, mut buf buffer.Buffer) {
	clipped := area.intersection(buf.area)
	if clipped.is_empty() {
		return
	}
	mut total_width := usize(0)
	for span_index in 0 .. line.spans.len {
		span := &line.spans[span_index]
		total_width += unicode_width.width(&span.text)
	}
	if total_width == 0 {
		return
	}
	line_area := layout.Rect.new(clipped.x, clipped.y, clipped.width, 1)
	buf.set_style(line_area, line.style)
	alignment := line.alignment or { layout.Alignment.left }
	mut x := line_area.x
	mut skip_width := usize(0)
	if total_width <= usize(line_area.width) {
		x += match alignment {
			.left { u16(0) }
			.center { u16((usize(line_area.width) - total_width) / 2) }
			.right { u16(usize(line_area.width) - total_width) }
		}
	} else {
		skip_width = match alignment {
			.left { usize(0) }
			.center { (total_width - usize(line_area.width)) / 2 }
			.right { total_width - usize(line_area.width) }
		}
	}
	for span_index in 0 .. line.spans.len {
		span := &line.spans[span_index]
		offsets := unicode_segmentation.grapheme_indices(&span.text, true)
		for i, start in offsets {
			end := if i + 1 < offsets.len { offsets[i + 1] } else { span.text.len }
			symbol := span.text[start..end]
			if symbol == '\n' {
				continue
			}
			width := unicode_width.width(&symbol)
			if skip_width >= width && width > 0 {
				skip_width -= width
				continue
			}
			if skip_width > 0 {
				x += u16(width - skip_width)
				skip_width = 0
				continue
			}
			if usize(x) + width > usize(line_area.right()) {
				return
			}
			if width == 0 {
				continue
			}
			buf.put_cell(x, line_area.y, symbol.clone(), line.style.patch(span.style))
			for offset in 1 .. int(width) {
				buf.put_cell(x + u16(offset), line_area.y, ' ', style.Style{})
			}
			x += u16(width)
		}
	}
}
