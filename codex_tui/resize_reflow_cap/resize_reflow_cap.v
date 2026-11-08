// Terminal-specific row caps for resize reflow.
//
// The auto cap mirrors documented scrollback defaults for terminals we can identify. Console Host
// does not expose its configured screen buffer through terminal metadata, so it usually lands in
// the fallback bucket.
//
// These caps are deliberately conservative: Codex is rebuilding normal terminal scrollback, not an
// internal virtual transcript. Replaying more rows than the terminal retains wastes work and can
// make interactive resize feel worse without giving the user more usable history.
module resize_reflow_cap

import codex_config.types
import codex_core.config
import codex_terminal_detection
import codex_tui.tui

const vscode_resize_reflow_max_rows = usize(1_000)
const windows_terminal_resize_reflow_max_rows = usize(9_001)
const wezterm_resize_reflow_max_rows = usize(3_500)
const alacritty_resize_reflow_max_rows = usize(10_000)

// Resolve the configured row cap for resize and initial replay.
//
// `Auto` uses terminal detection plus the VS Code environment probe because VS Code can run shells
// whose terminal-name metadata points at the host shell rather than VS Code itself. Returning
// `none` means the user explicitly disabled row limiting with `max_rows = 0`.
pub fn resize_reflow_max_rows(config_value config.TerminalResizeReflowConfig) ?usize {
	// V requires a named owner to borrow the metadata returned by terminal_info().
	terminal := codex_terminal_detection.terminal_info()
	return resize_reflow_max_rows_for(config_value, &terminal,
		tui.running_in_vscode_terminal())
}

fn resize_reflow_max_rows_for(config_value config.TerminalResizeReflowConfig, terminal &codex_terminal_detection.TerminalInfo, running_in_vscode_terminal bool) ?usize {
	return match config_value.max_rows.kind {
		.auto {
			auto_resize_reflow_max_rows(terminal.name, running_in_vscode_terminal)
		}
		.disabled {
			none
		}
		.limit {
			config_value.max_rows.limit
		}
	}
}

fn auto_resize_reflow_max_rows(terminal_name codex_terminal_detection.TerminalName, running_in_vscode_terminal bool) usize {
	if running_in_vscode_terminal {
		return vscode_resize_reflow_max_rows
	}
	return match terminal_name {
		.vs_code { vscode_resize_reflow_max_rows }
		.windows_terminal { windows_terminal_resize_reflow_max_rows }
		.wez_term { wezterm_resize_reflow_max_rows }
		.alacritty { alacritty_resize_reflow_max_rows }
		.apple_terminal, .ghostty, .iterm2, .warp_terminal, .kitty, .konsole, .gnome_terminal,
		.vte, .dumb, .unknown {
			types.default_terminal_resize_reflow_fallback_max_rows
		}
	}
}
