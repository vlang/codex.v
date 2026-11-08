module layout

// STUB: ratatui::layout::Size. Both dimensions are u16 and this value remains Copy-equivalent.
pub struct Size {
pub:
	width  u16
	height u16
}

// STUB: ratatui::layout::Size::new.
pub fn Size.new(width u16, height u16) Size {
	return Size{ width: width, height: height }
}
