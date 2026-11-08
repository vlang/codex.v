module render

import ratatui.layout

// Rust's highlight, line_utils, and renderable module declarations map to the
// sibling V submodule directories.

// V cannot express Rust's visibility of private parent-module fields to child
// modules. These allocation-free fields are public so renderable can read them.
// Value copies, generated debug formatting, and equality preserve the
// corresponding Rust derives.
pub struct Insets {
pub:
	left   u16
	top    u16
	right  u16
	bottom u16
}

// Rust derives Clone; V needs an explicit method for this allocation-free copy.
pub fn (insets &Insets) clone() Insets {
	return Insets{
		left:   insets.left
		top:    insets.top
		right:  insets.right
		bottom: insets.bottom
	}
}

pub fn Insets.tlbr(top u16, left u16, bottom u16, right u16) Insets {
	return Insets{
		top:    top
		left:   left
		bottom: bottom
		right:  right
	}
}

pub fn Insets.vh(v u16, h u16) Insets {
	return Insets{
		top:    v
		left:   h
		bottom: v
		right:  h
	}
}

// V cannot attach an extension-trait method to an imported Rect. The Rust
// RectExt trait and its Rect implementation are expressed as this source-owned
// function, retaining the borrowed rectangle and Copy-equivalent Insets value.
pub fn inset(area &layout.Rect, insets Insets) layout.Rect {
	horizontal_sum := u32(insets.left) + u32(insets.right)
	vertical_sum := u32(insets.top) + u32(insets.bottom)
	horizontal := if horizontal_sum > 65535 { u16(65535) } else { u16(horizontal_sum) }
	vertical := if vertical_sum > 65535 { u16(65535) } else { u16(vertical_sum) }
	x_sum := u32(area.x) + u32(insets.left)
	y_sum := u32(area.y) + u32(insets.top)
	return layout.Rect{
		x:      if x_sum > 65535 { u16(65535) } else { u16(x_sum) }
		y:      if y_sum > 65535 { u16(65535) } else { u16(y_sum) }
		width:  if area.width >= horizontal { area.width - horizontal } else { u16(0) }
		height: if area.height >= vertical { area.height - vertical } else { u16(0) }
	}
}
