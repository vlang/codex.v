// Terminal geometry policy shared by the main app and standalone screens.
module tui

import codex_tui.transcript_reflow
import ratatui.layout
import std_time

// Rust's derived Default sets all three options to None. Size and Instant own no allocations,
// so their optional values preserve Rust Copy semantics under V's ownership checker.
struct ScreenSizePolicy {
mut:
	pending_recheck_at ?std_time.Instant
	pending_draw_size  ?layout.Size
	deferred_size      ?layout.Size
}

// Resolve event geometry while avoiding backend queries on ordinary repaint frames.
pub fn (mut terminal_ui Tui) screen_size_for_event(event &TuiEvent) !layout.Size {
	if event.kind == .resize {
		terminal_ui.schedule_screen_size_recheck(transcript_reflow.transcript_reflow_debounce)
	} else if event.kind == .draw || event.kind == .focus_gained {
		deadline_option := terminal_ui.screen_size.pending_recheck_at
		if deadline := deadline_option {
			now := std_time.Instant.now()
			if now < deadline {
				terminal_ui.frame_requester.schedule_frame_in(deadline.duration_since(now))
			} else {
				return terminal_ui.screen_size_for_event(&TuiEvent{ kind: .resume })
			}
		}
	}

	cached := terminal_ui.terminal.last_known_screen_size
	size := match event.kind {
		.resize {
			terminal_ui.screen_size.deferred_size = none
			event.size
		}
		.resume {
			terminal_ui.screen_size.pending_recheck_at = none
			terminal_ui.screen_size.deferred_size = none
			terminal_ui.terminal.size()!
		}
		.draw, .focus_gained {
			deferred := terminal_ui.screen_size.deferred_size
			terminal_ui.screen_size.deferred_size = none
			deferred or { cached }
		}
		.key, .paste, .focus_lost { cached }
	}
	if event.kind == .resize || event.kind == .resume {
		monitor := terminal_ui.event_broker.size_monitor.as_ref()
		if monitor.is_some {
			monitor.value.observe(size)
		}
	}
	terminal_ui.screen_size.pending_draw_size = if event.kind != .key && event.kind != .paste && event.kind != .focus_lost {
		?layout.Size(size)
	} else {
		none
	}
	return size
}

// Schedule one backend sample after a resize, reflow, or external program.
pub fn (mut terminal_ui Tui) schedule_screen_size_recheck(delay std_time.Duration) {
	terminal_ui.screen_size.pending_recheck_at = std_time.Instant.now().add(delay)
	terminal_ui.frame_requester.schedule_frame_in(delay)
}

pub fn (mut terminal_ui Tui) defer_screen_size(size layout.Size) {
	terminal_ui.screen_size.deferred_size = size
}

fn (mut terminal_ui Tui) take_event_screen_size() !layout.Size {
	pending := terminal_ui.screen_size.pending_draw_size
	terminal_ui.screen_size.pending_draw_size = none
	if size := pending {
		return size
	}
	size := terminal_ui.terminal.size()!
	monitor := terminal_ui.event_broker.size_monitor.as_ref()
	if monitor.is_some {
		monitor.value.observe(size)
	}
	terminal_ui.screen_size.pending_recheck_at = none
	terminal_ui.screen_size.deferred_size = none
	return size
}
