module style

import codex_tui.color
import codex_tui.terminal_palette
import ratatui.prelude

// Named stand-in for the Rust `(StatusTone, Color)` expectation tuples.
struct ToneColor {
	tone         StatusTone
	status_color prelude.Color
}

// Named stand-in for the Rust `(StatusTone, Color, Color)` light/dark expectation tuples.
struct ToneLightDark {
	tone  StatusTone
	light prelude.Color
	dark  prelude.Color
}

// Named stand-in for the Rust `((u8, u8, u8), Color)` background expectation tuples.
struct BackgroundColor {
	bg       color.Rgb
	expected prelude.Color
}

fn named(kind prelude.ColorKind) prelude.Color {
	return prelude.Color{
		kind: kind
	}
}

fn test_status_colors_preserve_light_terminal_themes() {
	for level in [terminal_palette.StdoutColorLevel.true_color, .ansi256] {
		for bg in [color.Rgb{255, 255, 255}, color.Rgb{130, 130, 130}, color.Rgb{220, 210, 180}] {
			for expectation in [
				ToneColor{.success, named(.green)},
				ToneColor{.attention, named(.reset)},
				ToneColor{.failure, named(.red)},
			] {
				assert status_style_for(expectation.tone, bg, level) == prelude.Style.default().fg(expectation.status_color).bold()
			}
		}
		for bg in [color.Rgb{0, 0, 0}, color.Rgb{0, 218, 0}] {
			assert status_style_for(.attention, bg, level) == prelude.Style.default().fg(named(.yellow)).bold()
		}
		terminal_bg := ?color.Rgb(none)
		assert status_style_for(.attention, terminal_bg, level) == prelude.Style.default().fg(named(.reset)).bold()
	}
}

fn test_status_colors_preserve_ansi16_and_no_color_fallbacks() {
	for expectation in [
		ToneLightDark{.success, named(.green), named(.green)},
		ToneLightDark{.attention, named(.reset), named(.yellow)},
		ToneLightDark{.failure, named(.red), named(.red)},
	] {
		for background in [
			BackgroundColor{color.Rgb{255, 255, 255}, expectation.light},
			BackgroundColor{color.Rgb{0, 0, 0}, expectation.dark},
		] {
			assert status_style_for(expectation.tone, background.bg, .ansi16) == prelude.Style.default().fg(background.expected).bold()
			assert status_style_for(expectation.tone, background.bg, .unknown) == prelude.Style.default().fg(named(.reset)).bold()
		}
	}
}

fn test_accent_style_uses_darker_cyan_on_light_backgrounds() {
	// V rejects a local named after the enclosing `style` module, so Rust's `style` is `accent`.
	accent := accent_style_for(color.Rgb{255, 255, 255})

	assert accent.fg == ?prelude.Color(terminal_palette.best_color(light_bg_accent_rgb))
	assert accent.add_modifier.has(.bold)
}

fn test_accent_style_uses_cyan_on_dark_or_unknown_backgrounds() {
	expected := prelude.Style.default().fg(named(.cyan)).bold()

	assert accent_style_for(color.Rgb{0, 0, 0}) == expected
	terminal_bg := ?color.Rgb(none)
	assert accent_style_for(terminal_bg) == expected
}

fn test_table_separator_blends_toward_dark_background() {
	separator := table_separator_style_for(color.Rgb{255, 255, 255}, color.Rgb{0, 0, 0}, .true_color)

	assert separator.fg == ?prelude.Color(terminal_palette.rgb_color(color.Rgb{51, 51, 51}))
}

fn test_table_separator_blends_toward_light_background() {
	separator := table_separator_style_for(color.Rgb{0, 0, 0}, color.Rgb{255, 255, 255}, .true_color)

	assert separator.fg == ?prelude.Color(terminal_palette.rgb_color(color.Rgb{204, 204, 204}))
}

fn test_table_separator_dims_when_palette_aware_color_is_unavailable() {
	expected := prelude.Style.default().dim()

	assert table_separator_style_for(color.Rgb{255, 255, 255}, color.Rgb{0, 0, 0}, .ansi16) == expected
	terminal_fg := ?color.Rgb(none)
	assert table_separator_style_for(terminal_fg, color.Rgb{0, 0, 0}, .true_color) == expected
}
