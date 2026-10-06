module frame_requester

import std_time
import time
import tokio.sync.broadcast
import tokio.sync.mpsc
import codex_tui.tui.frame_rate_limiter

// Create a frame requester and expose its request channel for deterministic tests.
pub fn FrameRequester.test_channel() (FrameRequester, mpsc.InstantReceiver) {
	tx, rx := mpsc.unbounded_channel()
	return FrameRequester{ frame_schedule_tx: tx }, rx
}

// Tokio's current-thread/start_paused runtime is replaced by an injected channel clock.
// The production FrameScheduler.run actor still runs on a real thread; tests yield/advance
// through the channel runtime boundary, with no copy of the scheduler or limiter logic.
fn paused_requester(draw_tx broadcast.DrawSender) FrameRequester {
	tx, rx := mpsc.fixture_paused_channel(std_time.Instant.now())
	scheduler := FrameScheduler.new(rx, draw_tx)
	spawn scheduler.run()
	return FrameRequester{ frame_schedule_tx: tx }
}

fn advance(requester &FrameRequester, duration std_time.Duration) {
	requester.frame_schedule_tx.fixture_advance(duration)
}

fn recv_timeout(mut receiver broadcast.DrawReceiver, requester &FrameRequester,
	duration std_time.Duration) !broadcast.Draw {
	requester.frame_schedule_tx.fixture_wait_settled()
	mut received := true
	draw := receiver.try_recv() or {
		if err.code() != int(broadcast.ReceiveErrorKind.empty) + 1 { return err }
		received = false
		broadcast.Draw{}
	}
	if received { return draw }
	// Tokio auto-advances paused time to the earliest outstanding timer. A draw before
	// the timeout must be observed; at the exact timeout boundary the timeout wins and
	// a simultaneous draw stays queued for the following receive.
	finish := requester.frame_schedule_tx.now().add(duration)
	for {
		if target := requester.frame_schedule_tx.fixture_sleep_target() {
			if target < finish {
				advance(requester, target.duration_since(requester.frame_schedule_tx.now()))
				next_draw := receiver.try_recv() or {
					if err.code() != int(broadcast.ReceiveErrorKind.empty) + 1 { return err }
					continue
				}
				return next_draw
			}
		}
		break
	}
	advance(requester, finish.duration_since(requester.frame_schedule_tx.now()))
	return error('timed out waiting for draw')
}

fn test_schedule_frame_immediate_triggers_once() {
	draw_tx, mut draw_rx := broadcast.channel(16)
	requester := paused_requester(draw_tx)
	defer {
		requester.close()
		draw_rx.close()
	}
	requester.schedule_frame()
	// Advance time minimally to let the scheduler process and hit the deadline == now.
	advance(&requester, std_time.Duration.from_millis(1))
	// First draw should arrive.
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(50)) or {
		panic('timed out waiting for first draw: ${err}')
	}
	// No second draw should arrive.
	if _ := recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(20)) {
		assert false, 'unexpected extra draw received'
	}
}

fn test_schedule_frame_in_triggers_at_delay() {
	draw_tx, mut draw_rx := broadcast.channel(16)
	requester := paused_requester(draw_tx)
	defer {
		requester.close()
		draw_rx.close()
	}
	requester.schedule_frame_in(std_time.Duration.from_millis(50))
	// Advance less than the delay: no draw yet.
	advance(&requester, std_time.Duration.from_millis(30))
	if _ := recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(10)) {
		assert false, 'draw fired too early'
	}
	// Advance past the deadline: one draw should fire.
	advance(&requester, std_time.Duration.from_millis(25))
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(50)) or {
		panic('timed out waiting for scheduled draw: ${err}')
	}
	// No second draw should arrive.
	if _ := recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(20)) {
		assert false, 'unexpected extra draw received'
	}
}

fn test_coalesces_multiple_requests_into_single_draw() {
	draw_tx, mut draw_rx := broadcast.channel(16)
	requester := paused_requester(draw_tx)
	defer {
		requester.close()
		draw_rx.close()
	}
	// Schedule multiple immediate requests close together.
	requester.schedule_frame()
	requester.schedule_frame()
	requester.schedule_frame()
	// Allow the scheduler to process and hit the coalesced deadline.
	advance(&requester, std_time.Duration.from_millis(1))
	// Expect only a single draw notification despite three requests.
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(50)) or {
		panic('timed out waiting for coalesced draw: ${err}')
	}
	// No additional draw should be sent for the same coalesced batch.
	if _ := recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(20)) {
		assert false, 'unexpected extra draw received'
	}
}

fn test_coalesces_mixed_immediate_and_delayed_requests() {
	draw_tx, mut draw_rx := broadcast.channel(16)
	requester := paused_requester(draw_tx)
	defer {
		requester.close()
		draw_rx.close()
	}
	// Schedule a delayed draw and then an immediate one; should coalesce and fire at the earliest (immediate).
	requester.schedule_frame_in(std_time.Duration.from_millis(100))
	requester.schedule_frame()
	advance(&requester, std_time.Duration.from_millis(1))
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(50)) or {
		panic('timed out waiting for coalesced immediate draw: ${err}')
	}
	// The later delayed request should have been coalesced into the earlier one; no second draw.
	if _ := recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(120)) {
		assert false, 'unexpected extra draw received'
	}
}

fn test_limits_draw_notifications_to_120fps() {
	draw_tx, mut draw_rx := broadcast.channel(16)
	requester := paused_requester(draw_tx)
	defer {
		requester.close()
		draw_rx.close()
	}
	requester.schedule_frame()
	advance(&requester, std_time.Duration.from_millis(1))
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(50)) or {
		panic('timed out waiting for first draw: ${err}')
	}
	requester.schedule_frame()
	advance(&requester, std_time.Duration.from_millis(1))
	if _ := recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(1)) {
		assert false, 'draw fired too early; expected max 120fps (min interval ${frame_rate_limiter.min_frame_interval})'
	}
	advance(&requester, frame_rate_limiter.min_frame_interval)
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(50)) or {
		panic('timed out waiting for second draw: ${err}')
	}
}

fn test_late_draw_still_limits_the_next_frame() {
	draw_tx, mut draw_rx := broadcast.channel(16)
	requester := paused_requester(draw_tx)
	defer {
		requester.close()
		draw_rx.close()
	}
	delayed_deadline := requester.frame_schedule_tx.now().sub(frame_rate_limiter.min_frame_interval.add(frame_rate_limiter.min_frame_interval))
	requester.frame_schedule_tx.send(delayed_deadline) or {
		panic('scheduler should accept the overdue draw: ${err}')
	}
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(50)) or {
		panic('timed out waiting for overdue draw: ${err}')
	}
	requester.schedule_frame()
	if _ := recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(1)) {
		assert false, 'a late draw must not trigger a redraw burst'
	}
	advance(&requester, frame_rate_limiter.min_frame_interval)
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(50)) or {
		panic('timed out waiting for rate-limited draw: ${err}')
	}
}

fn test_rate_limit_clamps_early_delayed_requests() {
	draw_tx, mut draw_rx := broadcast.channel(16)
	requester := paused_requester(draw_tx)
	defer {
		requester.close()
		draw_rx.close()
	}
	requester.schedule_frame()
	advance(&requester, std_time.Duration.from_millis(1))
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(50)) or {
		panic('timed out waiting for first draw: ${err}')
	}
	requester.schedule_frame_in(std_time.Duration.from_millis(1))
	advance(&requester, std_time.Duration.from_nanos(4_166_667))
	if _ := recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(1)) {
		assert false, 'draw fired too early; expected max 120fps (min interval ${frame_rate_limiter.min_frame_interval})'
	}
	advance(&requester, frame_rate_limiter.min_frame_interval)
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(50)) or {
		panic('timed out waiting for clamped draw: ${err}')
	}
}

fn test_rate_limit_does_not_delay_future_draws() {
	draw_tx, mut draw_rx := broadcast.channel(16)
	requester := paused_requester(draw_tx)
	defer {
		requester.close()
		draw_rx.close()
	}
	requester.schedule_frame()
	advance(&requester, std_time.Duration.from_millis(1))
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(50)) or {
		panic('timed out waiting for first draw: ${err}')
	}
	requester.schedule_frame_in(std_time.Duration.from_millis(50))
	advance(&requester, std_time.Duration.from_millis(49))
	if _ := recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(1)) {
		assert false, 'draw fired too early'
	}
	advance(&requester, std_time.Duration.from_millis(1))
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(50)) or {
		panic('timed out waiting for delayed draw: ${err}')
	}
}

fn test_multiple_delayed_requests_coalesce_to_earliest() {
	draw_tx, mut draw_rx := broadcast.channel(16)
	requester := paused_requester(draw_tx)
	defer {
		requester.close()
		draw_rx.close()
	}
	// Schedule multiple delayed draws; they should coalesce to the earliest (10ms).
	requester.schedule_frame_in(std_time.Duration.from_millis(100))
	requester.schedule_frame_in(std_time.Duration.from_millis(20))
	requester.schedule_frame_in(std_time.Duration.from_millis(120))
	// Advance to just before the earliest deadline: no draw yet.
	advance(&requester, std_time.Duration.from_millis(10))
	if _ := recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(10)) {
		assert false, 'draw fired too early'
	}
	// Advance past the earliest deadline: one draw should fire.
	advance(&requester, std_time.Duration.from_millis(20))
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(50)) or {
		panic('timed out waiting for earliest coalesced draw: ${err}')
	}
	// No additional draw should fire for the later delayed requests.
	if _ := recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(120)) {
		assert false, 'unexpected extra draw received'
	}
}

fn test_real_runtime_schedules_and_stops_after_last_clone() {
	draw_tx, mut draw_rx := broadcast.channel(16)
	requester := FrameRequester.new(draw_tx)
	clone := requester.clone()
	requester.close()
	requester.close() // Explicit close plus ownership destruction is idempotent.
	clone.schedule_frame_in(std_time.Duration.from_millis(2))
	until := std_time.Instant.now().add(std_time.Duration.from_secs(2))
	mut received := false
	for std_time.Instant.now() < until {
		if _ := draw_rx.try_recv() {
			received = true
			break
		}
		time.sleep(time.millisecond)
	}
	assert received, 'live clone did not receive a native scheduler draw'
	clone.close()
	mut closed := false
	for std_time.Instant.now() < until {
		mut got_draw := true
		draw_rx.try_recv() or {
			got_draw = false
			if err.code() == int(broadcast.ReceiveErrorKind.closed) + 1 { closed = true }
			broadcast.Draw{}
		}
		assert !got_draw, 'extra native draw'
		if closed { break }
		time.sleep(time.millisecond)
	}
	assert closed, 'last sender closure did not stop the actor'
	draw_rx.close()
}

fn test_request_channel_and_dummy_preserve_source_send_behavior() {
	requester, mut rx := FrameRequester.test_channel()
	requester.schedule_frame()
	event := rx.recv_until(std_time.Instant.now().add(std_time.Duration.from_secs(1)))
	assert event.kind == .request
	requester.schedule_frame_in(std_time.Duration.from_millis(10))
	event2 := rx.recv_until(std_time.Instant.now().add(std_time.Duration.from_secs(1)))
	assert event2.kind == .request
	assert event2.draw_at >= event.draw_at
	requester.close()
	assert rx.recv_until(std_time.Instant.now().add(std_time.Duration.from_secs(1))).kind == .closed
	rx.close()
	dummy := FrameRequester.test_dummy()
	dummy.schedule_frame()
	dummy.schedule_frame_in(std_time.Duration.from_secs(1))
	if _ := dummy.frame_schedule_tx.send(std_time.Instant.now()) {
		assert false, 'dummy receiver must be closed'
	}
	dummy.close()
}

fn test_ready_deadline_is_not_starved_by_a_large_request_batch() {
	draw_tx, mut draw_rx := broadcast.channel(16)
	requester := paused_requester(draw_tx)
	defer {
		requester.close()
		draw_rx.close()
	}
	for _ in 0 .. 4_096 {
		requester.schedule_frame()
	}
	advance(&requester, std_time.Duration.from_millis(1))
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(50)) or {
		panic('ready deadline was starved: ${err}')
	}
	// Remaining requests, if processed after the draw, respect the same minimum interval.
	if _ := recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(1)) {
		assert false, 'a large batch bypassed the frame rate limiter'
	}
}

fn clone_owned_requester(draw_tx broadcast.DrawSender) FrameRequester {
	requester := FrameRequester.new(draw_tx)
	return requester.clone()
}

// V's ownership code generator skips destructor insertion for an anonymous `_` parameter.
// Keep a named owned binding so this helper tests Rust's consuming argument/scope Drop boundary.
fn consume_owned_requester(requester FrameRequester) {}

fn recv_native_timeout(mut receiver broadcast.DrawReceiver, duration std_time.Duration) !broadcast.Draw {
	until := std_time.Instant.now().add(duration)
	for {
		draw := receiver.try_recv() or {
			if err.code() != int(broadcast.ReceiveErrorKind.empty) + 1 { return err }
			if std_time.Instant.now() >= until { return error('timed out waiting for native draw') }
			time.sleep(time.millisecond)
			continue
		}
		return draw
	}
	return error('timed out waiting for native draw')
}

fn test_ownership_scope_drop_closes_only_its_own_sender_lease() {
	$if ownership ? {
		draw_tx, mut draw_rx := broadcast.channel(16)
		// Returning a clone drops the original owned sender at the helper's scope exit.
		requester := clone_owned_requester(draw_tx)
		requester.schedule_frame()
		recv_native_timeout(mut draw_rx, std_time.Duration.from_secs(2)) or {
			panic('clone was closed with original sender: ${err}')
		}
		// Consuming the final owned requester invokes the nested mpsc sender's Drop hook.
		consume_owned_requester(requester)
		mut got_draw := true
		recv_native_timeout(mut draw_rx, std_time.Duration.from_secs(2)) or {
			got_draw = false
			assert err.code() == int(broadcast.ReceiveErrorKind.closed) + 1
			broadcast.Draw{}
		}
		assert !got_draw, 'last owned sender did not shut down the actor'
		draw_rx.close()
	}
}

fn test_paused_timeout_observes_a_draw_before_the_timeout_deadline() {
	draw_tx, mut draw_rx := broadcast.channel(16)
	requester := paused_requester(draw_tx)
	defer {
		requester.close()
		draw_rx.close()
	}
	now := requester.frame_schedule_tx.now()
	requester.schedule_frame_in(std_time.Duration.from_millis(5))
	recv_timeout(mut draw_rx, &requester, std_time.Duration.from_millis(10)) or {
		panic('timeout hid a draw that occurred strictly before its deadline: ${err}')
	}
	assert requester.frame_schedule_tx.now() == now.add(std_time.Duration.from_millis(5))
}
