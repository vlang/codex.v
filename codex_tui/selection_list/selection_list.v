module selection_list

import codex_tui.render.renderable
import ratatui.style
import ratatui.text
import ratatui.widgets
import unicode_width

// V module exports use pub for Rust pub(crate). A structural interface owns the
// returned row, matching the consuming Box<dyn Renderable> conversion.
pub fn selection_option_row(index usize, label string, is_selected bool) renderable.Renderable {
	return selection_option_row_with_dim(index, label, is_selected, /*dim*/
		false)
}

pub fn selection_option_row_with_dim(index usize, label string, is_selected bool, dim bool) renderable.Renderable {
	prefix := if is_selected { '› ${index + 1}. ' } else { '  ${index + 1}. ' }
	row_style := if is_selected {
		style.Style{}.cyan()
	} else if dim {
		style.Style{}.dim()
	} else {
		style.Style{}
	}
	prefix_width := u16(unicode_width.width(&prefix))
	mut row := renderable.RowRenderable.new()
	row.push(prefix_width, renderable.SpanRenderable.new(text.span_styled(prefix, row_style)))
	paragraph := widgets.Paragraph.new(label)
	styled_paragraph := paragraph.style(row_style)
	wrapped_paragraph := styled_paragraph.wrap(widgets.Wrap{ trim: false })
	row.push(u16(65535), renderable.ParagraphRenderable.new(wrapped_paragraph))
	return row
}
