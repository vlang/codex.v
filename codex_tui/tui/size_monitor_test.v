module tui

import codex_terminal_detection
import codex_tui.custom_terminal
import codex_tui.test_backend
import codex_tui.tui.event_stream
import codex_tui.tui.job_control
import codex_tui.tui.size_monitor
import crossterm.event as terminal_event
import ratatui.layout
import ratatui.widgets
import std_io
import std_sync.atomic as shared_atomic
import time
import tokio.sync.broadcast

struct KeySource {
mut:
	sent bool
}

fn (mut source KeySource) poll_next() ?terminal_event.Event {
	if source.sent {
		return none
	}
	source.sent = true
	return terminal_event.Event{ kind: .key, key: terminal_event.KeyEvent.new(terminal_event.KeyCode.char_key(`x`), terminal_event.key_modifiers_none) }
}

enum QuerySignal {
	started
	closed
}

type SizeSample = layout.Size | std_io.Error

struct BlockingSizeQuery {
	started   chan QuerySignal
	responses chan SizeSample
}

fn (mut query BlockingSizeQuery) query() !layout.Size {
	query.started <- QuerySignal.started
	select {
		sample := <-query.responses {
			return match sample {
				layout.Size { sample }
				std_io.Error { return sample }
			}
		}
		5 * time.second {
			return std_io.Error.new(.other, 'test query was not released')
		}
	}
	return error('unreachable query wait')
}

fn (mut query BlockingSizeQuery) finish() {
	query.started <- QuerySignal.closed
}

struct MonitorHarness {
	broker  &event_stream.EventBroker
	queries chan QuerySignal
	replies chan SizeSample
mut:
	draws broadcast.DrawReceiver
}

// The Rust test uses unbounded Tokio/std channels. These fixture channels carry at most
// one in-flight unit/reply; capacity 16 preserves every source send without blocking.
fn MonitorHarness.new(size layout.Size) MonitorHarness {
	draw_tx, draws := broadcast.channel( /*capacity*/
	1)
	queries := chan QuerySignal{cap: 16}
	replies := chan SizeSample{cap: 16}
	monitor := size_monitor.SizeMonitor.spawn(size, draw_tx, BlockingSizeQuery{ started: queries, responses: replies }) or { panic('monitor: ${err}') }
	mut broker := event_stream.EventBroker.new()
	broker.size_monitor = size_monitor.SizeMonitorOption.some(monitor)
	return MonitorHarness{ broker: broker, queries: queries, replies: replies, draws: draws }
}

fn (harness &MonitorHarness) monitor() &size_monitor.SizeMonitor {
	view := harness.broker.size_monitor.as_ref()
	assert view.is_some
	return view.value
}

fn (mut harness MonitorHarness) next_query() {
	harness.monitor().fixture_unpark()
	signal := monitor_query_timeout(harness.queries, 2 * time.second) or { panic(err) }
	assert signal == .started
}

fn (harness &MonitorHarness) stream() event_stream.TuiEventStream {
	$if unix && !plan9 {
		return event_stream.TuiEventStream.new[KeySource](harness.broker, harness.draws.resubscribe(),
			shared_atomic.SharedAtomicBool.new( /*v*/
			false), job_control.SuspendContext.new(), shared_atomic.SharedAtomicBool.new( /*v*/
			false))
	} $else {
		return event_stream.TuiEventStream.new[KeySource](harness.broker, harness.draws.resubscribe(), shared_atomic.SharedAtomicBool.new( /*v*/
		false))
	}
}

fn (harness &MonitorHarness) close() {
	harness.broker.close()
	// A stopped worker still may be in its sole OS query; release it without joining it.
	harness.replies <- SizeSample(std_io.Error.new(.other, 'harness closed'))
	harness.draws.close()
}

// V cannot nest Result<Option<T>>. The allocation-free closed discriminator represents
// the source receiver's None, while the Result error represents timeout independently.
fn monitor_query_timeout(queries chan QuerySignal, timeout time.Duration) !QuerySignal {
	select {
		signal := <-queries {
			return signal
		}
		timeout {
			return error('query timed out')
		}
	}
	return error('unreachable query timeout')
}

fn monitor_next_event(mut stream event_stream.TuiEventStream, timeout time.Duration) !TuiEvent {
	deadline := time.sys_mono_now() + i64(timeout)
	for time.sys_mono_now() < deadline {
		if event := stream.poll_next() {
			return match event.kind {
				.key { TuiEvent{ kind: .key, key: event.key } }
				.draw { TuiEvent{ kind: .draw } }
				.resize { TuiEvent{ kind: .resize, size: event.size } }
			}
		}
		time.sleep(100 * time.microsecond)
	}
	return error('event timed out')
}

fn monitor_next_draw(mut draws broadcast.DrawReceiver) {
	deadline := time.sys_mono_now() + i64(2 * time.second)
	for time.sys_mono_now() < deadline {
		if _ := draws.try_recv() {
			return
		}
		time.sleep(100 * time.microsecond)
	}
	panic('draw timed out')
}

fn test_missed_resize_recovers_and_slow_query_does_not_block_input() {
	initial := layout.Size.new( /*width*/
	12, /*height*/
		4)
	resized := layout.Size.new( /*width*/
	8, /*height*/
		4)
	mut harness := MonitorHarness.new(initial)
	defer { harness.close() }
	mut stream := harness.stream()
	defer { stream.close() }
	harness.next_query()
	// The worker is blocked waiting for a reply. Input still traverses the typed event stream.
	key := monitor_next_event(mut stream, 100 * time.millisecond) or { panic(err) }
	assert key.kind == .key && key.key.code == terminal_event.KeyCode.char_key(`x`)
	if _ := monitor_query_timeout(harness.queries, size_monitor.check_interval + 50 * time.millisecond) {
		assert false, 'a blocked query started another query'
	}
	harness.replies <- SizeSample(resized)
	event := monitor_next_event(mut stream, 2 * time.second) or { panic(err) }
	assert event.kind == .resize, 'expected recovered resize: ${event}'
	size := event.size
	assert size == resized
	mut terminal := custom_terminal.Terminal.with_screen_size_and_cursor_position_for_test(test_backend.VT100Backend.new(resized.width, resized.height), initial, layout.Position{ x: 0, y: 0 })
	area := layout.Rect.new( /*x*/
	0, /*y*/
		0, size.width, size.height)
	terminal.set_viewport_area(area)
	terminal.draw_with_size(size, fn [area] (mut frame custom_terminal.Frame) {
		paragraph := widgets.Paragraph.new('alpha beta').wrap(widgets.Wrap{ trim: false })
		mut buf := frame.buffer_mut()
		paragraph.render(area, mut buf)
	}) or { panic(err) }
	assert terminal.last_known_screen_size == resized
	assert terminal.backend().vt100().screen().contents() == 'alpha\nbeta'
}

fn test_newer_resize_invalidates_in_flight_and_queued_samples() {
	initial := layout.Size.new( /*width*/
	80, /*height*/
		24)
	newer := layout.Size.new( /*width*/
	100, /*height*/
		30)
	mut harness := MonitorHarness.new(initial)
	defer { harness.close() }
	harness.next_query()
	harness.monitor().observe(newer)
	harness.replies <- SizeSample(initial)
	harness.next_query() // The previous result has been processed.
	assert harness.monitor().take_resize() == none
	if _ := harness.draws.try_recv() {
		assert false
	} else {
		assert err.code() == int(broadcast.ReceiveErrorKind.empty) + 1
	}
	harness.replies <- SizeSample(initial)
	monitor_next_draw(mut harness.draws)
	harness.monitor().observe(newer) // Also discard a result already queued for the UI.
	assert harness.monitor().take_resize() == none
}

fn test_unchanged_invalid_and_failed_samples_do_not_redraw() {
	initial := layout.Size.new( /*width*/
	80, /*height*/
		24)
	mut harness := MonitorHarness.new(initial)
	defer { harness.close() }
	harness.next_query()
	for sample in [SizeSample(initial), SizeSample(layout.Size.new( /*width*/
	0, /*height*/
		0)), SizeSample(std_io.Error.new(.other, 'query failed'))] {
		harness.replies <- sample
		harness.next_query()
		assert harness.monitor().take_resize() == none
		if _ := harness.draws.try_recv() {
			assert false
		} else {
			assert err.code() == int(broadcast.ReceiveErrorKind.empty) + 1
		}
	}
}

fn test_terminal_handoff_pauses_queries_and_discards_old_results() {
	initial := layout.Size.new( /*width*/
	80, /*height*/
		24)
	resized := layout.Size.new( /*width*/
	40, /*height*/
		12)
	mut harness := MonitorHarness.new(initial)
	defer { harness.close() }
	harness.next_query()
	harness.broker.pause_events()
	harness.replies <- SizeSample(resized)
	harness.monitor().fixture_unpark()
	if _ := monitor_query_timeout(harness.queries, 100 * time.millisecond) {
		assert false, 'paused monitor queried geometry'
	}
	assert harness.monitor().take_resize() == none
	harness.broker.resume_events()
	harness.next_query()
	harness.replies <- SizeSample(resized)
	monitor_next_draw(mut harness.draws)
	assert harness.monitor().take_resize() == ?layout.Size(resized)
}

fn test_drop_does_not_wait_for_a_blocked_query_or_start_another() {
	initial := layout.Size.new( /*width*/
	80, /*height*/
		24)
	mut harness := MonitorHarness.new(initial)
	defer { harness.close() }
	harness.next_query()
	state := harness.monitor().fixture_state()
	before := time.sys_mono_now()
	harness.broker.close()
	assert time.sys_mono_now() - before < i64(100 * time.millisecond)
	assert state.snapshot().stopped
	harness.replies <- SizeSample(layout.Size.new( /*width*/
	40, /*height*/
		12))
	assert monitor_query_timeout(harness.queries, 2 * time.second) or { panic(err) } == .closed
	assert state.snapshot().pending == none
}

fn test_monitor_requires_tmux_detection() {
	draw_tx, draws := broadcast.channel( /*capacity*/
	1)
	defer { draws.close() }
	mut info := codex_terminal_detection.TerminalInfo{ name: .ghostty }
	size := layout.Size.new( /*width*/
	80, /*height*/
		24)
	assert size_monitor.SizeMonitor.start(&info, size, draw_tx.clone()) == none
	info = codex_terminal_detection.TerminalInfo{ ...info, multiplexer: codex_terminal_detection.Multiplexer{ kind: .zellij } }
	assert size_monitor.SizeMonitor.start(&info, size, draw_tx.clone()) == none
	info = codex_terminal_detection.TerminalInfo{ ...info, multiplexer: codex_terminal_detection.Multiplexer{ kind: .tmux } }
	monitor := size_monitor.SizeMonitor.start(&info, size, draw_tx)
	$if unix && !plan9 {
		assert monitor != none
	} $else {
		assert monitor == none
	}
	if started := monitor { started.close() }
}

fn test_monitor_repeated_borrow_keeps_heap_terminal_metadata_and_pending_consumes_once() {
	program := $if ownership ? { 'Ghostty'.to_owned() } $else { 'Ghostty'.clone() }
	version := $if ownership ? { '3.4'.to_owned() } $else { '3.4'.clone() }
	info := codex_terminal_detection.TerminalInfo{ name: .ghostty, term_program: program, multiplexer: codex_terminal_detection.Multiplexer{ kind: .zellij, version: version } }
	draw_tx, draws := broadcast.channel(1)
	defer {
		draw_tx.close()
		draws.close()
	}
	for _ in 0 .. 2 {
		assert size_monitor.SizeMonitor.start(&info, layout.Size.new(80, 24), draw_tx.clone()) == none
	}
	assert info.term_program or { panic('missing program') } == 'Ghostty'
	mux := info.multiplexer or { panic('missing mux') }
	assert mux.version or { panic('missing version') } == '3.4'
	mut harness := MonitorHarness.new(layout.Size.new(80, 24))
	defer { harness.close() }
	harness.next_query()
	harness.replies <- SizeSample(layout.Size.new(100, 30))
	monitor_next_draw(mut harness.draws)
	assert harness.monitor().take_resize() == ?layout.Size(layout.Size.new(100, 30))
	assert harness.monitor().take_resize() == none
	assert harness.monitor().fixture_state().snapshot().size == layout.Size.new(100, 30)
}
