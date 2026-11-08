module tui

import codex_tui.tui.test_support
import crossterm.event as terminal_event
import ratatui.layout
import std_time

struct EventSizeCase {
	event    TuiEvent
	expected layout.Size
}

fn test_draw_size_policy_refreshes_only_after_resume() {
	mut terminal_ui := test_support.make_test_tui() or { panic('test terminal_ui: ${err}') }
	cached := layout.Size.new( /*width*/
	120, /*height*/
		40)
	resumed := terminal_ui.terminal.size() or { panic('backend size: ${err}') }
	terminal_ui.terminal.last_known_screen_size = cached
	resized := layout.Size.new( /*width*/
	100, /*height*/
		30)
	for item in [
		EventSizeCase{ event: TuiEvent{ kind: .draw }, expected: cached },
		EventSizeCase{ event: TuiEvent{ kind: .resume }, expected: resumed },
		EventSizeCase{ event: TuiEvent{ kind: .resize, size: resized }, expected: resized },
		EventSizeCase{ event: TuiEvent{ kind: .paste, paste: '' }, expected: cached },
		EventSizeCase{ event: TuiEvent{ kind: .draw }, expected: resized },
		EventSizeCase{ event: TuiEvent{ kind: .paste, paste: '' }, expected: cached },
	] {
		assert terminal_ui.screen_size_for_event(&item.event) or { panic('size: ${err}') } == item.expected
		if item.event.kind == .resize {
			terminal_ui.defer_screen_size(resized)
		}
	}
	assert terminal_ui.take_event_screen_size() or { panic('size: ${err}') } == resumed
	assert terminal_ui.screen_size.pending_recheck_at == none
}

fn test_standalone_resize_draw_rechecks_settled_screen_size_once() {
	mut terminal_ui := test_support.make_test_tui() or { panic('test terminal_ui: ${err}') }
	resize_size := layout.Size.new( /*width*/
	120, /*height*/
		40)
	terminal_ui.screen_size_for_event(&TuiEvent{ kind: .resize, size: resize_size }) or {
		panic('resolve resize: ${err}')
	}
	terminal_ui.terminal.resize(resize_size) or { panic('apply resize: ${err}') }
	assert terminal_ui.screen_size_for_event(&TuiEvent{ kind: .draw }) or {
		panic('resolve early draw: ${err}')
	} == resize_size
	terminal_ui.schedule_screen_size_recheck(std_time.duration_zero)
	assert terminal_ui.screen_size_for_event(&TuiEvent{ kind: .draw }) or {
		panic('resolve settled draw: ${err}')
	} == terminal_ui.terminal.size() or { panic('terminal size: ${err}') }
	assert terminal_ui.screen_size.pending_recheck_at == none
}

fn test_entering_alternate_screen_updates_cached_screen_size() {
	mut terminal_ui := test_support.make_test_tui() or { panic('test terminal_ui: ${err}') }
	screen_size := terminal_ui.terminal.size() or { panic('terminal size: ${err}') }
	terminal_ui.terminal.last_known_screen_size = layout.Size.new( /*width*/
	120, /*height*/
		40)
	terminal_ui.enter_alt_screen() or { panic('enter alternate screen: ${err}') }
	assert terminal_ui.terminal.last_known_screen_size == screen_size
	terminal_ui.leave_alt_screen() or { panic('leave alternate screen: ${err}') }
}

fn test_draw_and_focus_before_deadline_preserve_recheck_without_backend_queries() {
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	cached := layout.Size.new(100, 35)
	terminal_ui.terminal.last_known_screen_size = cached
	terminal_ui.schedule_screen_size_recheck(std_time.Duration.from_secs(60))
	deadline := terminal_ui.screen_size.pending_recheck_at or { panic('expected deadline') }
	for kind in [TuiEventKind.draw, .focus_gained, .draw] {
		assert terminal_ui.screen_size_for_event(&TuiEvent{ kind: kind }) or { panic(err) } == cached
		assert terminal_ui.screen_size.pending_recheck_at == ?std_time.Instant(deadline)
	}
	assert terminal_ui.terminal.fixture_size_query_count() == 0
	assert terminal_ui.frame_requester.fixture_request_count() == 4
	requested := terminal_ui.frame_requester.fixture_last_request() or { panic('missing frame request') }
	assert requested >= deadline
}

fn test_expired_focus_samples_backend_once_and_observes_before_pending_draw() {
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	backend := layout.Size.new(90, 28)
	terminal_ui.terminal.fixture_set_backend_size(backend)
	terminal_ui.fixture_install_size_monitor(layout.Size.new(80, 24))
	terminal_ui.defer_screen_size(layout.Size.new(110, 50))
	terminal_ui.schedule_screen_size_recheck(std_time.duration_zero)
	assert terminal_ui.screen_size_for_event(&TuiEvent{ kind: .focus_gained }) or { panic(err) } == backend
	assert terminal_ui.screen_size.pending_recheck_at == none
	assert terminal_ui.screen_size.deferred_size == none
	assert terminal_ui.screen_size.pending_draw_size == ?layout.Size(backend)
	assert terminal_ui.terminal.fixture_size_query_count() == 1
	monitor := terminal_ui.event_broker.size_monitor.as_ref()
	assert monitor.is_some
	assert monitor.value.fixture_observations() == [backend]
	assert terminal_ui.take_event_screen_size() or { panic(err) } == backend
	assert terminal_ui.terminal.fixture_size_query_count() == 1
	assert monitor.value.fixture_observations() == [backend]
}

fn test_resize_replaces_deferred_size_and_schedules_trailing_sample() {
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	terminal_ui.fixture_install_size_monitor(layout.Size.new(80, 24))
	terminal_ui.defer_screen_size(layout.Size.new(100, 30))
	first := layout.Size.new(110, 35)
	second := layout.Size.new(120, 40)
	before := std_time.Instant.now()
	assert terminal_ui.screen_size_for_event(&TuiEvent{ kind: .resize, size: first }) or { panic(err) } == first
	first_deadline := terminal_ui.screen_size.pending_recheck_at or { panic('missing resize deadline') }
	assert first_deadline >= before.add(std_time.Duration.from_millis(75))
	assert terminal_ui.screen_size.deferred_size == none
	assert terminal_ui.screen_size_for_event(&TuiEvent{ kind: .resize, size: second }) or { panic(err) } == second
	second_deadline := terminal_ui.screen_size.pending_recheck_at or { panic('missing trailing deadline') }
	assert second_deadline >= first_deadline
	assert terminal_ui.terminal.fixture_size_query_count() == 0
	assert terminal_ui.frame_requester.fixture_request_count() == 2
	monitor := terminal_ui.event_broker.size_monitor.as_ref()
	assert monitor.value.fixture_observations() == [first, second]
}

fn test_deferred_geometry_is_drained_by_focus_and_draw() {
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	cached := terminal_ui.terminal.last_known_screen_size
	deferred := layout.Size.new(150, 45)
	terminal_ui.defer_screen_size(deferred)
	assert terminal_ui.screen_size_for_event(&TuiEvent{ kind: .focus_gained }) or { panic(err) } == deferred
	assert terminal_ui.screen_size.deferred_size == none
	assert terminal_ui.take_event_screen_size() or { panic(err) } == deferred
	terminal_ui.defer_screen_size(deferred)
	assert terminal_ui.screen_size_for_event(&TuiEvent{ kind: .draw }) or { panic(err) } == deferred
	assert terminal_ui.screen_size_for_event(&TuiEvent{ kind: .draw }) or { panic(err) } == cached
	assert terminal_ui.terminal.fixture_size_query_count() == 0
}

fn test_borrowed_paste_and_key_events_remain_reusable_and_do_not_drain_deferred_geometry() {
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	mut payload := 'reusable pasted text'
	$if ownership ? {
		payload = 'reusable pasted text'.to_owned()
	}
	paste := TuiEvent{ kind: .paste, paste: payload }
	key := TuiEvent{ kind: .key, key: terminal_event.KeyEvent.new(terminal_event.KeyCode.char_key(`x`), terminal_event.KeyModifiers{}) }
	cached := terminal_ui.terminal.last_known_screen_size
	deferred := layout.Size.new(100, 30)
	terminal_ui.schedule_screen_size_recheck(std_time.Duration.from_secs(60))
	deadline := terminal_ui.screen_size.pending_recheck_at
	terminal_ui.defer_screen_size(deferred)
	for _ in 0 .. 2 {
		assert terminal_ui.screen_size_for_event(&paste) or { panic(err) } == cached
		assert terminal_ui.screen_size_for_event(&key) or { panic(err) } == cached
		assert terminal_ui.screen_size_for_event(&TuiEvent{ kind: .focus_lost }) or { panic(err) } == cached
		assert terminal_ui.screen_size.pending_draw_size == none
		assert terminal_ui.screen_size.pending_recheck_at == deadline
		assert terminal_ui.screen_size.deferred_size == ?layout.Size(deferred)
	}
	assert paste.paste == 'reusable pasted text'
	assert key.key.code.ch == `x`
	assert terminal_ui.terminal.fixture_size_query_count() == 0
	assert terminal_ui.screen_size_for_event(&TuiEvent{ kind: .draw }) or { panic(err) } == deferred
}

fn test_resume_failure_clears_recheck_and_deferred_but_preserves_pending_draw() {
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	terminal_ui.fixture_install_size_monitor(layout.Size.new(80, 24))
	pending := layout.Size.new(100, 30)
	terminal_ui.screen_size.pending_draw_size = pending
	terminal_ui.defer_screen_size(layout.Size.new(120, 40))
	terminal_ui.schedule_screen_size_recheck(std_time.Duration.from_secs(60))
	terminal_ui.terminal.fixture_fail_size_query(true)
	if _ := terminal_ui.screen_size_for_event(&TuiEvent{ kind: .resume }) {
		assert false, 'backend failure must propagate'
	} else {
		assert err.msg() == 'terminal size query failed'
	}
	assert terminal_ui.screen_size.pending_recheck_at == none
	assert terminal_ui.screen_size.deferred_size == none
	assert terminal_ui.screen_size.pending_draw_size == ?layout.Size(pending)
	monitor := terminal_ui.event_broker.size_monitor.as_ref()
	assert monitor.value.fixture_observations().len == 0
}

fn test_take_pending_draw_preserves_recheck_and_deferred_without_observing_monitor() {
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	terminal_ui.fixture_install_size_monitor(layout.Size.new(80, 24))
	pending := layout.Size.new(100, 30)
	deferred := layout.Size.new(120, 40)
	terminal_ui.screen_size.pending_draw_size = pending
	terminal_ui.defer_screen_size(deferred)
	terminal_ui.schedule_screen_size_recheck(std_time.Duration.from_secs(60))
	deadline := terminal_ui.screen_size.pending_recheck_at
	assert terminal_ui.take_event_screen_size() or { panic(err) } == pending
	assert terminal_ui.screen_size.pending_draw_size == none
	assert terminal_ui.screen_size.pending_recheck_at == deadline
	assert terminal_ui.screen_size.deferred_size == ?layout.Size(deferred)
	assert terminal_ui.terminal.fixture_size_query_count() == 0
	monitor := terminal_ui.event_broker.size_monitor.as_ref()
	assert monitor.value.fixture_observations().len == 0
}

fn test_take_backend_sample_observes_and_clears_recheck_and_deferred() {
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	terminal_ui.fixture_install_size_monitor(layout.Size.new(80, 24))
	backend := layout.Size.new(90, 28)
	terminal_ui.terminal.fixture_set_backend_size(backend)
	terminal_ui.defer_screen_size(layout.Size.new(120, 40))
	terminal_ui.schedule_screen_size_recheck(std_time.Duration.from_secs(60))
	assert terminal_ui.take_event_screen_size() or { panic(err) } == backend
	assert terminal_ui.screen_size.pending_recheck_at == none
	assert terminal_ui.screen_size.deferred_size == none
	monitor := terminal_ui.event_broker.size_monitor.as_ref()
	assert monitor.value.fixture_observations() == [backend]
}

fn test_take_backend_failure_preserves_recheck_and_deferred_state() {
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	terminal_ui.fixture_install_size_monitor(layout.Size.new(80, 24))
	deferred := layout.Size.new(120, 40)
	terminal_ui.defer_screen_size(deferred)
	terminal_ui.schedule_screen_size_recheck(std_time.Duration.from_secs(60))
	deadline := terminal_ui.screen_size.pending_recheck_at
	terminal_ui.terminal.fixture_fail_size_query(true)
	if _ := terminal_ui.take_event_screen_size() {
		assert false, 'backend failure must propagate'
	} else {
		assert err.msg() == 'terminal size query failed'
	}
	assert terminal_ui.screen_size.pending_draw_size == none
	assert terminal_ui.screen_size.pending_recheck_at == deadline
	assert terminal_ui.screen_size.deferred_size == ?layout.Size(deferred)
	monitor := terminal_ui.event_broker.size_monitor.as_ref()
	assert monitor.value.fixture_observations().len == 0
}
