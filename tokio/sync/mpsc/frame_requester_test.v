module mpsc

import std_time
import time

fn test_unbounded_channel_keeps_fifo_order_and_drains_before_closure() {
	sender, mut receiver := unbounded_channel()
	base := std_time.Instant.now()
	for offset in 0 .. 100 {
		sender.send(base.add(std_time.Duration.from_millis(u64(offset)))) or { panic(err) }
	}
	sender.close()
	for offset in 0 .. 100 {
		event := receiver.recv_until(base.add(std_time.Duration.from_secs(1)))
		assert event.kind == .request
		assert event.draw_at == base.add(std_time.Duration.from_millis(u64(offset)))
	}
	assert receiver.recv_until(base.add(std_time.Duration.from_secs(1))).kind == .closed
	receiver.close()
}

fn test_cloned_sender_keeps_receiver_alive_and_receiver_close_rejects_sends() {
	sender, mut receiver := unbounded_channel()
	clone := sender.clone()
	sender.close()
	sender.close()
	clone.send(std_time.Instant.now()) or { panic(err) }
	assert receiver.recv_until(std_time.Instant.now()).kind == .request
	receiver.close()
	if _ := clone.send(std_time.Instant.now()) {
		assert false, 'closed receiving half accepted a request'
	}
	clone.close()
	clone.close()
}

fn test_ready_deadline_event_preserves_native_clock() {
	sender, mut receiver := unbounded_channel()
	defer {
		sender.close()
		receiver.close()
	}
	now := receiver.now()
	assert receiver.recv_until(now).kind == .deadline
	assert receiver.now() >= now
}

fn test_full_queue_receive_fairness_serves_due_deadline() {
	sender, mut receiver := fixture_paused_channel(std_time.Instant.now())
	defer {
		sender.close()
		receiver.close()
	}
	now := sender.now()
	for _ in 0 .. 100 {
		sender.send(now) or { panic(err) }
	}
	// This test is the runtime selector itself, so directly yield the paused channel.
	unsafe {
		mut state := sender.channel
		state.mutex.lock()
		state.drive_revision = state.revision
		state.mutex.unlock()
	}
	for _ in 0 .. 64 {
		assert receiver.recv_until(now).kind == .request
	}
	assert receiver.recv_until(now).kind == .deadline
	assert receiver.recv_until(now).kind == .request
}

fn wake_lifetime(sender &InstantSender) (bool, int) {
	unsafe {
		mut state := sender.channel
		state.mutex.lock()
		defer { state.mutex.unlock() }
		return state.wake_alive, state.receive_calls
	}
}

fn assert_wake_lifetime(sender &InstantSender, alive bool, calls int) {
	actual_alive, actual_calls := wake_lifetime(sender)
	assert actual_alive == alive
	assert actual_calls == calls
}

fn test_native_wake_release_waits_for_receiver_and_all_sender_leases() {
	sender, mut receiver := unbounded_channel()
	clone := sender.clone()
	receiver.close()
	assert_wake_lifetime(&sender, true, 0)
	sender.close()
	assert_wake_lifetime(&sender, true, 0)
	clone.close()
	assert_wake_lifetime(&sender, false, 0)
	// Closed handles can be reused for harmless close/error observations after native release.
	sender.close()
	clone.close()
	receiver.close()
	assert receiver.recv_until(std_time.Instant.now()).kind == .closed
	if _ := clone.send(std_time.Instant.now()) {
		assert false, 'released native wake must not make a closed send succeed'
	}
}

fn close_after_native_receive_starts(sender &InstantSender, receiver &InstantReceiver) {
	until := std_time.Instant.now().add(std_time.Duration.from_secs(5))
	unsafe {
		mut state := sender.channel
		for {
			state.mutex.lock()
			waiting := state.receive_calls == 1 && state.has_sleep_target
			state.mutex.unlock()
			if waiting {
				break
			}
			assert std_time.Instant.now() < until, 'native receiver did not start waiting'
			time.sleep(50 * time.microsecond)
		}
	}
	// Either final close may run while recv_until is between unlocking and native parking.
	sender.close()
	receiver.close()
}

fn test_native_wake_release_keeps_an_in_flight_receive_alive() {
	for _ in 0 .. 64 {
		sender, mut receiver := unbounded_channel()
		closer := spawn close_after_native_receive_starts(&sender, &receiver)
		event := receiver.recv_until(std_time.Instant.now().add(std_time.Duration.from_secs(5)))
		closer.wait()
		assert event.kind == .closed
		assert_wake_lifetime(&sender, false, 0)
		receiver.close()
		sender.close()
	}
}

fn test_native_wake_release_preserves_queued_requests_after_the_last_sender_closes() {
	sender, mut receiver := unbounded_channel()
	now := std_time.Instant.now()
	sender.send(now) or { panic(err) }
	sender.close()
	assert_wake_lifetime(&sender, true, 0)
	assert receiver.recv_until(now).kind == .request
	assert receiver.recv_until(now).kind == .closed
	assert_wake_lifetime(&sender, true, 0)
	receiver.close()
	assert_wake_lifetime(&sender, false, 0)
}

fn owned_channel_scope() &InstantChannel {
	sender, receiver := unbounded_channel()
	state := sender.channel
	$if !ownership ? {
		sender.close()
		receiver.close()
	}
	return state
}

fn test_native_wake_release_runs_after_owned_handle_scope_drop() {
	state := owned_channel_scope()
	// Under -ownership neither explicit close is needed: each nested Drop releases its lease.
	assert !state.wake_alive
	assert state.receive_calls == 0
}
