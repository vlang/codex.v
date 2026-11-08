module app_event_sender

import codex_tui.app_event

// STUB: crate::app_event_sender::AppEventSender. The eventual channel-backed sender preserves this
// owned event direction; the log lets isolated composer tests observe dispatched events.
pub struct AppEventSender {
pub mut:
	events []app_event.AppEvent
	// STUB: real asynchronous delivery boundary for discovery results.
	channel         chan app_event.AppEvent
	channel_enabled bool
}

// STUB: crate::app_event_sender::AppEventSender::send.
pub fn (sender &AppEventSender) send(event app_event.AppEvent) {
	if sender.channel_enabled {
		sender.channel <- event
		return
	}
	unsafe {
		mut writable := sender
		writable.events << event
	}
}

// STUB: AppEventSender::new retains the shared unbounded-channel sender; V uses
// a caller-sized buffered channel at the missing Tokio boundary.
pub fn AppEventSender.new(channel chan app_event.AppEvent) AppEventSender {
	return AppEventSender{ channel: channel, channel_enabled: true }
}
