module tui

import codex_tui.custom_terminal
import codex_tui.insert_history
import codex_tui.terminal_hyperlinks
import codex_tui.tui.frame_requester
import ratatui.layout

// STUB: tui.rs::PendingHistoryLines's owned batches and per-batch wrapping policy.
struct PendingHistoryLines {
	lines       []terminal_hyperlinks.HyperlinkLine
	wrap_policy insert_history.HistoryLineWrapPolicy
}

// STUB: tui.rs::Tui::flush_pending_history_lines preserves insertion order, per-batch
// modes, error propagation and clearing only after all batches have been written.
fn Tui.flush_pending_history_lines(mut terminal custom_terminal.Terminal, mut pending_history_lines []PendingHistoryLines, scrollback ScrollbackStrategy, screen_size layout.Size) ! {
	if pending_history_lines.len == 0 {
		return
	}
	for index in 0 .. pending_history_lines.len {
		batch := unsafe { &pending_history_lines[index] }
		mode := scrollback.history_insertion_mode(batch.wrap_policy)
		insert_history.insert_history_hyperlink_lines_with_mode_and_wrap_policy(mut terminal, &batch.lines, mode, batch.wrap_policy, screen_size)!
	}
	pending_history_lines.clear()
}

// STUB: tui.rs::Tui::frame_requester retains Rust's explicit clone boundary.
pub fn (terminal_ui &Tui) frame_requester() frame_requester.FrameRequester {
	return terminal_ui.frame_requester.clone()
}
