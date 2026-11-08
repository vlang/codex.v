module terminal_palette

import codex_terminal_detection
import codex_tui.color
import codex_tui.terminal_probe
import ratatui.style

fn test_best_color_uses_truecolor_without_quantization() {
	assert best_color_for_color_level(color.Rgb{12, 34, 56}, .true_color) == rgb_color(color.Rgb{12, 34, 56})
}

fn test_best_color_resets_for_ansi16() {
	assert best_color_for_color_level(color.Rgb{12, 34, 56}, .ansi16) == style.Color{
		kind: .reset
	}
}

fn test_windows_terminal_wt_session_promotes_to_truecolor() {
	has_wt_session := true
	has_force_color_override := false
	assert stdout_color_level_for_terminal(.ansi16, codex_terminal_detection.TerminalName.unknown,
		has_wt_session, has_force_color_override) == .true_color
}

fn test_windows_terminal_name_promotes_ansi16_to_truecolor() {
	has_wt_session := false
	has_force_color_override := false
	assert stdout_color_level_for_terminal(.ansi16, codex_terminal_detection.TerminalName.windows_terminal,
		has_wt_session, has_force_color_override) == .true_color
}

fn test_force_color_keeps_reported_stdout_level() {
	has_wt_session := true
	has_force_color_override := true
	assert stdout_color_level_for_terminal(.ansi16, codex_terminal_detection.TerminalName.windows_terminal,
		has_wt_session, has_force_color_override) == .ansi16
}

// V-specific coverage: the 256-color search skips the theme-dependent system colors and returns
// the first exact fixed-palette match, and the test palette override is scoped to its callback.
fn test_ansi256_quantization_and_test_palette_override_scope() {
	assert best_color_for_level(color.Rgb{0, 95, 135}, .ansi256) == indexed_color(24)
	assert best_color_for_level(color.Rgb{255, 255, 255}, .ansi256) == indexed_color(231)
	assert default_colors() == none
	colors := terminal_probe.DefaultColors{
		fg: color.Rgb{0x55, 0x57, 0x53}
		bg: color.Rgb{0xff, 0xff, 0xff}
	}
	level := with_test_default_colors(colors, fn () StdoutColorLevel {
		assert default_fg() or { panic('test fg') } == color.Rgb{0x55, 0x57, 0x53}
		assert default_bg() or { panic('test bg') } == color.Rgb{0xff, 0xff, 0xff}
		return effective_stdout_color_level()
	})
	assert level == .true_color
	assert default_colors() == none
	assert default_bg() == none
}
