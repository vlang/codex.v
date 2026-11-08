module widgets

import ratatui.buffer
import ratatui.layout

// STUB: Widget::render for the owned Paragraph. Source test builder chains consume
// their widget after rendering; shared rendering remains available through render_ref.
pub fn (paragraph Paragraph) render(area layout.Rect, mut buf buffer.Buffer) {
	paragraph.render_ref(area, mut buf)
}
