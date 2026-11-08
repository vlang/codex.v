module style

import codex_tui.color
import codex_tui.terminal_palette
// V rejects `import ratatui.style` inside this module because both modules are named `style`
// (an import alias does not lift the restriction), so ratatui's `Color`, `Modifier`, and `Style`
// are named through the `ratatui.prelude` re-exports, as Rust code commonly does.
import ratatui.prelude

const light_bg_accent_rgb = color.Rgb{0, 95, 135}

pub enum StatusTone {
	success
	attention
	failure
}

// Semantic status colors that preserve the terminal's configured palette.
pub fn status_style(tone StatusTone) prelude.Style {
	return status_style_for(tone, terminal_palette.default_bg(), terminal_palette.effective_stdout_color_level())
}

fn status_style_for(tone StatusTone, terminal_bg ?color.Rgb, color_level terminal_palette.StdoutColorLevel) prelude.Style {
	light := if bg := terminal_bg { color.is_light(bg) } else { false }
	status_color := if color_level == .unknown {
		prelude.Color{
			kind: .reset
		}
	} else {
		match tone {
			.success {
				prelude.Color{
					kind: .green
				}
			}
			.failure {
				prelude.Color{
					kind: .red
				}
			}
			.attention {
				// Yellow can disappear on light themes; use it only with a known dark background.
				if light || terminal_bg == none {
					prelude.Color{
						kind: .reset
					}
				} else {
					prelude.Color{
						kind: .yellow
					}
				}
			}
		}
	}
	return prelude.Style.default().fg(status_color).bold()
}

// Decorative table rules should remain visible without competing with cell content.
const table_separator_fg_alpha = f32(0.20)

pub fn user_message_style() prelude.Style {
	return user_message_style_for(terminal_palette.default_bg())
}

pub fn proposed_plan_style() prelude.Style {
	return proposed_plan_style_for(terminal_palette.default_bg())
}

// Returns a low-contrast rule style for separators within markdown tables.
pub fn table_separator_style() prelude.Style {
	return table_separator_style_for(terminal_palette.default_fg(), terminal_palette.default_bg(),
		terminal_palette.stdout_color_level())
}

// Returns the shared accent style for active or selected TUI controls.
pub fn accent_style() prelude.Style {
	return accent_style_for(terminal_palette.default_bg())
}

pub fn footer_hint_key_style() prelude.Style {
	if bg := terminal_palette.default_bg() {
		if color.is_light(bg) {
			return prelude.Style.default().fg(prelude.Color{ kind: .black })
		}
	}
	return prelude.Style.default()
}

pub fn footer_hint_label_style() prelude.Style {
	if bg := terminal_palette.default_bg() {
		if color.is_light(bg) {
			return prelude.Style.default().fg(prelude.Color{ kind: .dark_gray })
		}
	}
	return prelude.Style.default().dim()
}

// Returns the style for a user-authored message using the provided terminal background.
pub fn user_message_style_for(terminal_bg ?color.Rgb) prelude.Style {
	if bg := terminal_bg {
		return prelude.Style.default().bg(user_message_bg(bg))
	}
	return prelude.Style.default()
}

pub fn proposed_plan_style_for(terminal_bg ?color.Rgb) prelude.Style {
	if bg := terminal_bg {
		return prelude.Style.default().bg(proposed_plan_bg(bg))
	}
	return prelude.Style.default()
}

// Returns the shared accent style for the provided terminal background.
pub fn accent_style_for(terminal_bg ?color.Rgb) prelude.Style {
	if bg := terminal_bg {
		if color.is_light(bg) {
			return prelude.Style.default().fg(terminal_palette.best_color(light_bg_accent_rgb)).bold()
		}
	}
	return prelude.Style.default().fg(prelude.Color{ kind: .cyan }).bold()
}

fn table_separator_style_for(terminal_fg ?color.Rgb, terminal_bg ?color.Rgb, color_level terminal_palette.StdoutColorLevel) prelude.Style {
	fg := terminal_fg or { return prelude.Style.default().dim() }
	bg := terminal_bg or { return prelude.Style.default().dim() }
	separator_rgb := color.blend(fg, bg, table_separator_fg_alpha)
	return match color_level {
		.true_color { prelude.Style.default().fg(terminal_palette.rgb_color(separator_rgb)) }
		.ansi256 { prelude.Style.default().fg(terminal_palette.best_color(separator_rgb)) }
		.ansi16, .unknown { prelude.Style.default().dim() }
	}
}

pub fn user_message_bg(terminal_bg color.Rgb) prelude.Color {
	return terminal_palette.best_color(user_message_bg_rgb(terminal_bg))
}

pub fn user_message_bg_rgb(terminal_bg color.Rgb) color.Rgb {
	mut top := color.Rgb{255, 255, 255}
	mut alpha := f32(0.12)
	if color.is_light(terminal_bg) {
		top = color.Rgb{0, 0, 0}
		alpha = f32(0.04)
	}
	return color.blend(top, terminal_bg, alpha)
}

pub fn proposed_plan_bg(terminal_bg color.Rgb) prelude.Color {
	return user_message_bg(terminal_bg)
}
