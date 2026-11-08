module resize_reflow_cap

import codex_config.types
import codex_core.config
import codex_terminal_detection

// Rust's test_terminal helper is renamed because V reserves test_* for executable tests.
fn make_terminal(name codex_terminal_detection.TerminalName) codex_terminal_detection.TerminalInfo {
	return codex_terminal_detection.TerminalInfo{
		name:         name
		term_program: none
		version:      none
		term:         none
		multiplexer:  none
	}
}

fn test_auto_resize_reflow_max_rows_uses_terminal_defaults() {
	cases := [
		TerminalCapCase{.vs_code, vscode_resize_reflow_max_rows},
		TerminalCapCase{.windows_terminal, windows_terminal_resize_reflow_max_rows},
		TerminalCapCase{.wez_term, wezterm_resize_reflow_max_rows},
		TerminalCapCase{.alacritty, alacritty_resize_reflow_max_rows},
		TerminalCapCase{.ghostty, types.default_terminal_resize_reflow_fallback_max_rows},
		TerminalCapCase{.unknown, types.default_terminal_resize_reflow_fallback_max_rows},
	]
	for entry in cases {
		assert auto_resize_reflow_max_rows(entry.name, /* running_in_vscode_terminal */
			false) == entry.rows
	}
}

fn test_auto_resize_reflow_max_rows_prefers_vscode_probe() {
	assert auto_resize_reflow_max_rows(.windows_terminal, /* running_in_vscode_terminal */
		true) == vscode_resize_reflow_max_rows
}

fn test_configured_resize_reflow_max_rows_overrides_auto_detection() {
	terminal := make_terminal(.vs_code)
	config_value := config.TerminalResizeReflowConfig{
		max_rows: config.TerminalResizeReflowMaxRows{ kind: .limit, limit: 42 }
	}
	assert resize_reflow_max_rows_for(config_value, &terminal, /* running_in_vscode_terminal */
		false) == ?usize(42)
}

fn test_disabled_resize_reflow_max_rows_keeps_all_rows() {
	terminal := make_terminal(.vs_code)
	config_value := config.TerminalResizeReflowConfig{
		max_rows: config.TerminalResizeReflowMaxRows{ kind: .disabled }
	}
	assert resize_reflow_max_rows_for(config_value, &terminal, /* running_in_vscode_terminal */
		false) == none
}

fn test_unknown_terminal_uses_fallback_even_under_multiplexer() {
	terminal := codex_terminal_detection.TerminalInfo{
		name:         .unknown
		term_program: none
		version:      none
		term:         'xterm-256color'
		multiplexer:  codex_terminal_detection.Multiplexer{ kind: .tmux, version: none }
	}
	config_value := config.TerminalResizeReflowConfig{}
	assert resize_reflow_max_rows_for(config_value, &terminal, /* running_in_vscode_terminal */
		false) == ?usize(types.default_terminal_resize_reflow_fallback_max_rows)
}

// Named adaptation of the source test's (TerminalName, usize) tuples.
struct TerminalCapCase {
	name codex_terminal_detection.TerminalName
	rows usize
}

fn test_all_terminal_categories_and_vscode_override() {
	fallback_names := [codex_terminal_detection.TerminalName.apple_terminal, .ghostty, .iterm2,
		.warp_terminal, .kitty, .konsole, .gnome_terminal, .vte, .dumb, .unknown]
	for name in fallback_names {
		assert auto_resize_reflow_max_rows(name, false) == types.default_terminal_resize_reflow_fallback_max_rows
		assert auto_resize_reflow_max_rows(name, true) == vscode_resize_reflow_max_rows
	}
	assert auto_resize_reflow_max_rows(.wez_term, true) == vscode_resize_reflow_max_rows
	assert auto_resize_reflow_max_rows(.alacritty, true) == vscode_resize_reflow_max_rows
}

fn test_borrowed_terminal_metadata_and_copy_config_remain_reusable() {
	program := $if ownership ? { 'WezTerm'.to_owned() } $else { 'WezTerm' }
	version := $if ownership ? { '2026.10'.to_owned() } $else { '2026.10' }
	term := $if ownership ? { 'xterm-256color'.to_owned() } $else { 'xterm-256color' }
	mux_version := $if ownership ? { '3.5'.to_owned() } $else { '3.5' }
	terminal := codex_terminal_detection.TerminalInfo{
		name:         .wez_term
		term_program: program
		version:      version
		term:         term
		multiplexer:  codex_terminal_detection.Multiplexer{ kind: .tmux, version: mux_version }
	}
	configs := [
		config.TerminalResizeReflowConfig{},
		config.TerminalResizeReflowConfig{ max_rows: config.TerminalResizeReflowMaxRows{ kind: .disabled } },
		config.TerminalResizeReflowConfig{ max_rows: config.TerminalResizeReflowMaxRows{ kind: .limit, limit: 42 } },
	]
	for config_value in configs {
		first := resize_reflow_max_rows_for(config_value, &terminal, false)
		second := resize_reflow_max_rows_for(config_value, &terminal, false)
		assert first == second
		assert config_value.max_rows.kind in [.auto, .disabled, .limit]
		assert resize_reflow_max_rows_for(config_value, &terminal, true) == match config_value.max_rows.kind {
			.auto { ?usize(vscode_resize_reflow_max_rows) }
			.disabled { none }
			.limit { ?usize(42) }
		}
	}
	assert terminal.term_program == ?string('WezTerm')
	assert terminal.version == ?string('2026.10')
	assert terminal.term == ?string('xterm-256color')
	assert terminal.multiplexer == ?codex_terminal_detection.Multiplexer(codex_terminal_detection.Multiplexer{ kind: .tmux, version: '3.5' })
}

fn test_explicit_limits_preserve_zero_and_usize_max() {
	terminal := make_terminal(.windows_terminal)
	for rows in [usize(0), usize(1), ~usize(0)] {
		config_value := config.TerminalResizeReflowConfig{
			max_rows: config.TerminalResizeReflowMaxRows{ kind: .limit, limit: rows }
		}
		assert resize_reflow_max_rows_for(config_value, &terminal, true) == ?usize(rows)
	}
}

fn test_public_resolution_preserves_explicit_configuration() {
	configured := config.TerminalResizeReflowConfig{
		max_rows: config.TerminalResizeReflowMaxRows{ kind: .limit, limit: 42 }
	}
	disabled := config.TerminalResizeReflowConfig{
		max_rows: config.TerminalResizeReflowMaxRows{ kind: .disabled }
	}
	assert resize_reflow_max_rows(configured) == ?usize(42)
	assert resize_reflow_max_rows(configured) == ?usize(42)
	assert resize_reflow_max_rows(disabled) == none
}
