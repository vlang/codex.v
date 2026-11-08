module style

// STUB: ratatui::style::Color variant tags. ratatui models `Color` as a payload enum; V enums do
// not carry payloads, so the unit variants are tags here and `Rgb`/`Indexed` store their payload
// in the matching `Color` fields.
pub enum ColorKind {
	reset
	black
	red
	green
	yellow
	blue
	magenta
	cyan
	gray
	dark_gray
	light_red
	light_green
	light_yellow
	light_blue
	light_magenta
	light_cyan
	white
	rgb
	indexed
}

// STUB: ratatui::style::Color. `Color{}` is `Color::Reset`, matching ratatui's `Default`
// implementation. The payload fields are zero for every variant except the one that owns them,
// so structural equality matches ratatui's derived `PartialEq`.
pub struct Color {
pub:
	kind  ColorKind
	r     u8
	g     u8
	b     u8
	index u8
}

// STUB: ratatui::style::Color::Rgb(r, g, b).
pub fn Color.rgb(r u8, g u8, b u8) Color {
	return Color{
		kind: .rgb
		r:    r
		g:    g
		b:    b
	}
}

// STUB: ratatui::style::Color::Indexed(index).
pub fn Color.indexed(index u8) Color {
	return Color{
		kind:  .indexed
		index: index
	}
}

// STUB: ratatui::style::Modifier bitflags, declared in ratatui's bit order (BOLD = 1 through
// CROSSED_OUT = 256). The zero value is `Modifier::empty()`.
@[flag]
pub enum Modifier {
	bold
	dim
	italic
	underlined
	slow_blink
	rapid_blink
	reversed
	hidden
	crossed_out
}

// STUB: ratatui::style::Style. `Style{}` is `Style::default()`: no colors and no modifiers.
pub struct Style {
pub mut:
	fg              ?Color
	bg              ?Color
	underline_color ?Color
	add_modifier    Modifier
	sub_modifier    Modifier
}

// STUB: ratatui::style::Style::default().
pub fn Style.default() Style {
	return Style{}
}

// STUB: ratatui::style::Style::new().
pub fn Style.new() Style {
	return Style{}
}

// STUB: ratatui::style::Style::fg.
pub fn (s Style) fg(color Color) Style {
	return Style{
		...s
		fg: color
	}
}

// STUB: ratatui::style::Style::bg.
pub fn (s Style) bg(color Color) Style {
	return Style{
		...s
		bg: color
	}
}

// STUB: ratatui::style::Style::add_modifier. Adding a modifier also cancels a pending removal.
pub fn (s Style) add_modifier(modifier Modifier) Style {
	mut sub_modifier := s.sub_modifier
	sub_modifier.clear(modifier)
	mut add_modifier := s.add_modifier
	add_modifier.set(modifier)
	return Style{
		...s
		add_modifier: add_modifier
		sub_modifier: sub_modifier
	}
}

// STUB: ratatui::style::Style::remove_modifier.
pub fn (s Style) remove_modifier(modifier Modifier) Style {
	mut add_modifier := s.add_modifier
	add_modifier.clear(modifier)
	mut sub_modifier := s.sub_modifier
	sub_modifier.set(modifier)
	return Style{
		...s
		add_modifier: add_modifier
		sub_modifier: sub_modifier
	}
}

// STUB: ratatui::style::Style::patch. Colors from `other` win when set; modifiers are merged.
pub fn (s Style) patch(other Style) Style {
	mut add_modifier := s.add_modifier
	add_modifier.clear(other.sub_modifier)
	add_modifier.set(other.add_modifier)
	mut sub_modifier := s.sub_modifier
	sub_modifier.clear(other.add_modifier)
	sub_modifier.set(other.sub_modifier)
	mut patched := Style{
		fg:              s.fg
		bg:              s.bg
		underline_color: s.underline_color
		add_modifier:    add_modifier
		sub_modifier:    sub_modifier
	}
	if color := other.fg {
		patched.fg = color
	}
	if color := other.bg {
		patched.bg = color
	}
	if color := other.underline_color {
		patched.underline_color = color
	}
	return patched
}

// STUB: ratatui::style::Stylize::bold for `Style`.
pub fn (s Style) bold() Style {
	return s.add_modifier(.bold)
}

// STUB: ratatui::style::Stylize::dim for `Style`.
pub fn (s Style) dim() Style {
	return s.add_modifier(.dim)
}

// STUB: ratatui::style::Stylize::italic for `Style`.
pub fn (s Style) italic() Style {
	return s.add_modifier(.italic)
}

// STUB: ratatui::style::Stylize::underlined for `Style`.
pub fn (s Style) underlined() Style {
	return s.add_modifier(.underlined)
}

// STUB: ratatui::style::Stylize::reversed for `Style`.
pub fn (s Style) reversed() Style {
	return s.add_modifier(.reversed)
}

// STUB: ratatui::style::Stylize::green for `Style`.
pub fn (s Style) green() Style {
	return s.fg(Color{ kind: .green })
}

// STUB: ratatui::style::Stylize::yellow for `Style`.
pub fn (s Style) yellow() Style {
	return s.fg(Color{ kind: .yellow })
}

// STUB: ratatui::style::Stylize::magenta for `Style`.
pub fn (s Style) magenta() Style {
	return s.fg(Color{ kind: .magenta })
}

// STUB: ratatui::style::Stylize::cyan for `Style`.
pub fn (s Style) cyan() Style {
	return s.fg(Color{ kind: .cyan })
}

// STUB: ratatui::style::Stylize::light_red for `Style`.
pub fn (s Style) light_red() Style {
	return s.fg(Color{ kind: .light_red })
}
