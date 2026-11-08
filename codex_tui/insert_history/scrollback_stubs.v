module insert_history

import codex_tui.custom_terminal
import codex_tui.terminal_hyperlinks
import ratatui.text

// STUB: insert_history::insert_history_lines_with_mode_and_wrap_policy retains its owned
// Vec<Line>, mode and wrapping policy through the canonical borrowed hyperlink API.
// V lines are already owned static text, so Rust's line_to_static adaptation is unnecessary.
pub fn insert_history_lines_with_mode_and_wrap_policy(mut terminal custom_terminal.Terminal, lines []text.Line, mode InsertHistoryMode, wrap_policy HistoryLineWrapPolicy) ! {
	screen_size := terminal.last_known_screen_size
	plain := terminal_hyperlinks.plain_hyperlink_lines(lines)
	insert_history_hyperlink_lines_with_mode_and_wrap_policy(mut terminal, &plain, mode, wrap_policy, screen_size)!
}
