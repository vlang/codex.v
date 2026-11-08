// Choose terminal-safe strategies for growing the viewport and inserting history.
module tui

import codex_terminal_detection
import codex_tui.custom_terminal
import codex_tui.insert_history
import crossterm
import crossterm.cursor
import crossterm.style
import os
import ratatui.layout
import std_ops

enum ScrollbackStrategy {
	standard
	zellij
	full_screen
}

fn ScrollbackStrategy.detect(terminal &codex_terminal_detection.TerminalInfo) ScrollbackStrategy {
	return ScrollbackStrategy.detect_with_windows_terminal_session(terminal, scrollback_windows_terminal_session)
}

fn (strategy ScrollbackStrategy) history_insertion_mode(wrap_policy insert_history.HistoryLineWrapPolicy) insert_history.InsertHistoryMode {
	return match strategy {
		.full_screen { .full_screen }
		.zellij {
			if wrap_policy == .terminal {
				insert_history.InsertHistoryMode.full_screen
			} else {
				.standard
			}
		}
		.standard { .standard }
	}
}

// Terminal's generic native writer remains behind its canonical typed backend fixture.
fn (strategy ScrollbackStrategy) grow_viewport(mut terminal custom_terminal.Terminal, viewport_top u16, screen_size layout.Size, scroll_by u16) ! {
	match strategy {
		.full_screen {
			// Partial DEC scroll regions can discard rows instead of moving them into Windows
			// Terminal's scrollback. Clear the stale composer, then scroll the entire screen.
			terminal.clear_after_position(layout.Position{ /*x*/
				x: 0
				y: viewport_top
			})!
			mut writer := terminal.backend_mut()
			last_row := if screen_size.height > 0 {
				screen_size.height - /*rhs*/
				1
			} else {
				u16(0)
			}
			crossterm.queue_move_to(mut writer, cursor.MoveTo{ /*x*/
				x: 0
				y: last_row
			})!
			for _ in 0 .. scroll_by {
				newline := '\r\n'
				command := style.Print{ text: &newline }
				crossterm.queue_print(mut writer, &command)!
			}
		}
		.standard, .zellij {
			mut writer := terminal.backend_mut()
			writer.scroll_region_up(std_ops.Range[u16]{ start: 0, end: viewport_top }, scroll_by)!
		}
	}
}

// Preserve std::env::var_os presence semantics, including empty and non-Unicode Unix values.
// Reading one variable through the local environment API avoids copying the entire environment.
fn scrollback_windows_terminal_session() ?string {
	return os.getenv_opt('WT_SESSION')
}

// The injected environment read keeps branch tests deterministic without changing process state.
// Separate branches retain Rust's short-circuit order: Zellij, terminal name, then WT_SESSION.
fn ScrollbackStrategy.detect_with_windows_terminal_session(terminal &codex_terminal_detection.TerminalInfo, wt_session fn () ?string) ScrollbackStrategy {
	if terminal.is_zellij() {
		return .zellij
	} else if terminal.name == .windows_terminal {
		return .full_screen
	} else if _ := wt_session() {
		return .full_screen
	} else {
		return .standard
	}
}
