module tui

import codex_tui.custom_terminal
import codex_tui.tui.event_stream
import codex_tui.tui.frame_requester
import codex_tui.tui.size_monitor
import crossterm.event
import ratatui.layout

// STUB: crate::tui::TuiEvent's payload discriminator. Every source variant is retained.
pub enum TuiEventKind {
	key
	paste
	resize
	draw
	resume
	focus_gained
	focus_lost
}

// STUB: crate::tui::TuiEvent. Explicit tagged payloads preserve the owned paste text and Copy
// key/size values; screen_size_for_event always borrows the complete event.
pub struct TuiEvent {
pub:
	kind  TuiEventKind
	key   event.KeyEvent
	paste string
	size  layout.Size
}

// STUB: crate::tui::Tui. Only geometry dependencies are declared here; the terminal renderer,
// application channels, notification handling, suspension, and native alternate screen await porting.
pub struct Tui {
pub mut:
	terminal custom_terminal.Terminal
mut:
	frame_requester frame_requester.FrameRequester
	event_broker    &event_stream.EventBroker = &event_stream.EventBroker{}
	screen_size     ScreenSizePolicy
	// STUB: tui.rs history batches and terminal-specific insertion policy.
	pending_history_lines []PendingHistoryLines
	scrollback            ScrollbackStrategy
}

// STUB: construction boundary used by tui::test_support::make_test_tui. This substitutes for
// Tui::new's untranslated runtime setup while keeping its exact test backend dimensions.
pub fn Tui.screen_size_fixture(size layout.Size) Tui {
	return Tui{ terminal: custom_terminal.Terminal.screen_size_fixture(size), frame_requester: frame_requester.FrameRequester.test_dummy() }
}

// STUB: crate::tui::Tui::enter_alt_screen's geometry side effect. Native terminal commands,
// viewport restoration, and drawing are omitted at this external runtime boundary. A failed size
// sample is ignored, matching the source's if let Ok(size) before cache-changing resize().
pub fn (mut terminal_ui Tui) enter_alt_screen() ! {
	if size := terminal_ui.terminal.size() {
		terminal_ui.terminal.resize(size)!
	}
}

// STUB: crate::tui::Tui::leave_alt_screen. Native screen and viewport restoration are untranslated;
// leaving the alternate screen does not change the source terminal's cached screen dimensions.
pub fn (mut terminal_ui Tui) leave_alt_screen() ! {}

// STUB: fixture boundary installing a SizeMonitor without running its untranslated OS worker.
fn (mut terminal_ui Tui) fixture_install_size_monitor(size layout.Size) {
	terminal_ui.event_broker = &event_stream.EventBroker{ size_monitor: size_monitor.SizeMonitorOption.fixture(size) }
}
