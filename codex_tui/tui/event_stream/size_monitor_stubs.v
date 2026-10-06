module event_stream

import crossterm.event
import codex_tui.tui.job_control
import ratatui.layout
import std_sync.atomic as shared_atomic
import tokio.sync.broadcast

// STUB: crate::tui::event_stream::EventSource's pending/ready protocol. A synchronous
// nonblocking poll replaces Rust Pin/Context only at the untranslated stream-runtime boundary.
pub interface EventSource {
mut:
	poll_next() ?event.Event
}

// STUB: crate::tui::event_stream::EventBroker::new with its source-owned optional monitor.
pub fn EventBroker.new() &EventBroker {
	return &EventBroker{}
}

// STUB: crate::tui::event_stream::EventBroker::pause_events. Native stdin source destruction
// remains untranslated; the monitor's actual pause and invalidation happen through its API.
pub fn (broker &EventBroker) pause_events() {
	monitor := broker.size_monitor.as_ref()
	if monitor.is_some { monitor.value.set_active(false) }
	unsafe {
		mut shared := broker
		shared.fixture_mutex.lock()
		defer { shared.fixture_mutex.unlock() }
		shared.fixture_paused = true
	}
}

// STUB: crate::tui::event_stream::EventBroker::resume_events. The fixture polls the shared
// paused state; Tokio watch notifications and native stdin recreation remain untranslated.
pub fn (broker &EventBroker) resume_events() {
	monitor := broker.size_monitor.as_ref()
	if monitor.is_some { monitor.value.set_active(true) }
	unsafe {
		mut shared := broker
		shared.fixture_mutex.lock()
		defer { shared.fixture_mutex.unlock() }
		shared.fixture_paused = false
	}
}

// STUB: explicit final Arc<EventBroker> destruction for V GC builds; the actual monitor
// has its real nonblocking Drop behavior. A stream fixture borrows this broker's lifetime.
pub fn (broker &EventBroker) close() {
	broker.size_monitor.close()
}

// STUB: typed output at crate::tui::event_stream::TuiEventStream's untranslated parent
// TuiEvent boundary. The parent maps it to its canonical TuiEvent without a circular import.
pub struct StreamEvent {
pub:
	kind StreamEventKind
	key  event.KeyEvent
	size layout.Size
}

// STUB: the three event outcomes observed by size_monitor's original integration tests.
pub enum StreamEventKind {
	key
	draw
	resize
}

// STUB: crate::tui::event_stream::TuiEventStream's typed source and broadcast fixture.
// This does not provide the crossterm reader, full event mapping, or Tokio task runtime.
pub struct TuiEventStream {
	broker            &EventBroker
	terminal_focused  shared_atomic.SharedAtomicBool
	suspend_context   job_control.SuspendContext
	alt_screen_active shared_atomic.SharedAtomicBool
mut:
	source          EventSource
	draws           broadcast.DrawReceiver
	poll_draw_first bool
}

// STUB: source-shaped TuiEventStream::new, retaining all owned runtime handles. Rust's
// default generic source construction maps to an explicitly selected V source type.
$if unix && !plan9 {
	pub fn TuiEventStream.new[S](broker &EventBroker, draws broadcast.DrawReceiver, terminal_focused shared_atomic.SharedAtomicBool, suspend_context job_control.SuspendContext, alt_screen_active shared_atomic.SharedAtomicBool) TuiEventStream {
		return TuiEventStream{ broker: broker, draws: draws, source: EventSource(S{}), terminal_focused: terminal_focused, suspend_context: suspend_context, alt_screen_active: alt_screen_active }
	}
} $else {
	// STUB: the source omits suspend/alternate-screen handles on non-Unix targets.
	pub fn TuiEventStream.new[S](broker &EventBroker, draws broadcast.DrawReceiver, terminal_focused shared_atomic.SharedAtomicBool) TuiEventStream {
		return TuiEventStream{ broker: broker, draws: draws, source: EventSource(S{}), terminal_focused: terminal_focused }
	}
}

// STUB: Stream::poll_next preserves the source round-robin choice between keys and draws.
pub fn (mut stream TuiEventStream) poll_next() ?StreamEvent {
	draw_first := stream.poll_draw_first
	stream.poll_draw_first = !stream.poll_draw_first
	if draw_first {
		if draw := stream.poll_draw_event() {
			return draw
		}
		return stream.poll_crossterm_event()
	}
	if input := stream.poll_crossterm_event() {
		return input
	}
	return stream.poll_draw_event()
}

// STUB: poll_crossterm_event forwards typed key events supplied by the fixture source.
fn (mut stream TuiEventStream) poll_crossterm_event() ?StreamEvent {
	unsafe {
		mut broker := stream.broker
		broker.fixture_mutex.lock()
		defer { broker.fixture_mutex.unlock() }
		if broker.fixture_paused {
			return none
		}
		if input := stream.source.poll_next() {
			if input.kind == .key {
				return StreamEvent{ kind: .key, key: input.key }
			}
		}
	}
	return none
}

// STUB: poll_draw_event uses the real monitor's take_resize after a real broadcast
// draw or lag notification, matching the eventual event-stream API's resize recovery.
fn (mut stream TuiEventStream) poll_draw_event() ?StreamEvent {
	stream.draws.try_recv() or {
		if err.code() == int(broadcast.ReceiveErrorKind.lagged) + 1 {
			return stream.recovered_draw()
		}
		return none
	}
	return stream.recovered_draw()
}

// STUB: the Option::and_then(SizeMonitor::take_resize).map_or(Draw, Resize) boundary.
fn (stream &TuiEventStream) recovered_draw() StreamEvent {
	monitor := stream.broker.size_monitor.as_ref()
	if monitor.is_some {
		if size := monitor.value.take_resize() {
			return StreamEvent{ kind: .resize, size: size }
		}
	}
	return StreamEvent{ kind: .draw }
}

// STUB: release only the fixture's owned draw subscription, preserving its borrowed broker.
pub fn (stream &TuiEventStream) close() {
	stream.draws.close()
}
