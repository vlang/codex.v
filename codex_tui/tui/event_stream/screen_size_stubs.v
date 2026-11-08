module event_stream

import codex_tui.tui.size_monitor
import sync

// STUB: crate::tui::event_stream::EventBroker. Its shared optional monitor is the only field
// observed by screen_size.rs; terminal event streams and pause/resume are untranslated.
@[heap]
pub struct EventBroker {
pub mut:
	size_monitor size_monitor.SizeMonitorOption
mut:
	fixture_mutex  &sync.Mutex = sync.new_mutex()
	fixture_paused bool
}
