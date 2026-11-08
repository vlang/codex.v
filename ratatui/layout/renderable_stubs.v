module layout

import math

// STUB: ratatui::layout::Rect::new clamps dimensions to the u16 coordinate domain.
pub fn Rect.new(x u16, y u16, width u16, height u16) Rect {
	return Rect{ x: x, y: y, width: math.min(width, u16(65535) - x), height: math.min(height, u16(65535) - y) }
}

// STUB: ratatui::layout::Rect::right; Rect is allocation-free/Copy-equivalent.
pub fn (area Rect) right() u16 {
	return u16(math.min(u32(area.x) + u32(area.width), u32(65535)))
}

// STUB: ratatui::layout::Rect::bottom.
pub fn (area Rect) bottom() u16 {
	return u16(math.min(u32(area.y) + u32(area.height), u32(65535)))
}

// STUB: ratatui::layout::Rect::is_empty.
pub fn (area Rect) is_empty() bool {
	return area.width == 0 || area.height == 0
}

// STUB: ratatui::layout::Rect::intersection, preserving non-overlap coordinates.
pub fn (area Rect) intersection(other Rect) Rect {
	x := math.max(area.x, other.x)
	y := math.max(area.y, other.y)
	right := math.min(area.right(), other.right())
	bottom := math.min(area.bottom(), other.bottom())
	return Rect{
		x:      x
		y:      y
		width:  if right > x { right - x } else { 0 }
		height: if bottom > y {
			bottom - y
		} else {
			0
		}
	}
}
