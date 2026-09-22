module style

// STUB: ratatui::style::Color variants observed by the composer.
pub enum Color {
	default_color
	green
	magenta
	cyan
	light_red
	yellow
}

// STUB: ratatui::style::Color::Rgb payload used by terminal palette backgrounds.
pub struct RgbColor {
pub:
	r u8
	g u8
	b u8
}

// STUB: ratatui::style::Style fields observed by the composer.
pub struct Style {
pub mut:
	foreground Color
	background ?RgbColor
	bold       bool
	dim        bool
	reversed   bool
	underlined bool
}
