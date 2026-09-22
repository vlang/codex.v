module app_event_sender

import codex_tui.app_event

// STUB: crate::app_event_sender::AppEventSender. The eventual channel-backed sender preserves this
// owned event direction; the log lets isolated composer tests observe dispatched events.
pub struct AppEventSender {
pub mut:
	events []app_event.AppEvent
}

// STUB: crate::app_event_sender::AppEventSender::send.
pub fn (sender &AppEventSender) send(event app_event.AppEvent) {
	unsafe {
		mut writable := sender
		writable.events << event
	}
}
