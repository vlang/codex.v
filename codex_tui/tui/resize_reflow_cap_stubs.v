module tui

import os

// STUB: codex_tui::tui::running_in_vscode_terminal delegates to tui/keyboard_modes.rs.
// The directly supplied TERM_PROGRAM path is implemented; the Linux WSL Windows-side environment
// probe and cached system-executable resolution await the keyboard-modes translation.
pub fn running_in_vscode_terminal() bool {
	return os.getenv('TERM_PROGRAM').to_lower() == 'vscode'
}
