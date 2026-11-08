// Update visible terminal-history tails without discarding terminal scrollback.
module tui

import codex_tui.custom_terminal
import codex_tui.insert_history
import codex_tui.terminal_hyperlinks
import ratatui.layout

pub fn (terminal_ui &Tui) pending_history_lines_for_test() []terminal_hyperlinks.HyperlinkLine {
	mut lines := []terminal_hyperlinks.HyperlinkLine{}
	for batch_index in 0 .. terminal_ui.pending_history_lines.len {
		batch := &terminal_ui.pending_history_lines[batch_index]
		for line_index in 0 .. batch.lines.len {
			lines << batch.lines[line_index].clone()
		}
	}
	return lines
}

pub fn (mut terminal_ui Tui) replace_visible_history_tail(previous_lines &[]terminal_hyperlinks.HyperlinkLine, replacement &[]terminal_hyperlinks.HyperlinkLine, wrap_policy insert_history.HistoryLineWrapPolicy) !bool {
	screen_size := terminal_ui.terminal.last_known_screen_size
	Tui.flush_pending_history_lines(mut terminal_ui.terminal, mut terminal_ui.pending_history_lines, terminal_ui.scrollback, screen_size)!
	mode := terminal_ui.scrollback.history_insertion_mode(wrap_policy)
	replaced := replace_visible_terminal_history_tail(mut terminal_ui.terminal, previous_lines, replacement, mode, wrap_policy)!
	if replaced { terminal_ui.frame_requester().schedule_frame() }
	return replaced
}

// The canonical V Terminal fixes the currently translated backend type; Rust's generic
// Backend<Error = io::Error> + Write boundary remains behind that terminal's typed API.
fn replace_visible_terminal_history_tail(mut terminal custom_terminal.Terminal, previous_lines &[]terminal_hyperlinks.HyperlinkLine, replacement &[]terminal_hyperlinks.HyperlinkLine, mode insert_history.InsertHistoryMode, wrap_policy insert_history.HistoryLineWrapPolicy) !bool {
	screen_size := terminal.last_known_screen_size
	mut viewport := terminal.viewport_area
	wrap_width := usize(if viewport.width > 1 {
		viewport.width
	} else { /*other*/
		u16(1)
	})
	_, physical_rows := insert_history.wrap_history_hyperlink_lines(previous_lines, wrap_width, wrap_policy)
	if physical_rows > 65535 {
		return false
	}
	previous_rows := u16(physical_rows)
	if previous_rows == 0 || previous_rows > viewport.y {
		return false
	}
	viewport = layout.Rect{ ...viewport, y: viewport.y - previous_rows }
	terminal.clear_after_position(layout.Position{ /*x*/
		x: 0
		y: viewport.y
	})!
	terminal.set_viewport_area(viewport)
	terminal.invalidate_viewport()
	insert_history.insert_history_hyperlink_lines_with_mode_and_wrap_policy(mut terminal, replacement, mode, wrap_policy, screen_size)!
	return true
}
