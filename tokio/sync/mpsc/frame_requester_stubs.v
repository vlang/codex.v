module mpsc

import std_time
import sync
import time

// STUB: Tokio's Drop ownership contract; V ownership builds call drop automatically.
interface Drop {
mut:
	drop()
}

// STUB: Tokio's unbounded Instant channel, implemented with a native monotonic wake and mutex.
// Only this payload specialization is translated; unrelated Tokio channel APIs remain absent.
@[heap]
struct InstantChannel {
mut:
	mutex            &sync.Mutex = sync.new_mutex()
	wake             FrameWake   = FrameWake.new()
	requests         []std_time.Instant
	senders          int  = 1
	receiver_alive   bool = true
	receive_calls    int
	wake_alive       bool = true
	paused           bool
	clock            std_time.Instant
	revision         u64
	settled          u64
	drive_revision   u64
	ready_receives   int
	sleep_target     std_time.Instant
	has_sleep_target bool
	record_attempts  bool
	attempts         []std_time.Instant
}

// STUB: one owned sender lease; clone creates a distinct lease on the same channel.
@[heap]
struct SenderLease {
mut:
	active bool = true
}

// STUB: tokio::sync::mpsc::UnboundedSender<Instant>.
pub struct InstantSender implements Drop {
	channel &InstantChannel
	lease   &SenderLease = &SenderLease{}
}

// STUB: tokio::sync::mpsc::UnboundedReceiver<Instant>.
pub struct InstantReceiver implements Drop {
	channel &InstantChannel
}

// STUB: the typed outcomes of selecting a receive against sleep_until.
pub enum ReceiveKind {
	request
	deadline
	closed
}

// STUB: a request's Instant is Copy-equivalent and exists only for the request outcome.
pub struct ReceiveEvent {
pub:
	kind    ReceiveKind
	draw_at std_time.Instant
}

// STUB: tokio::sync::mpsc::unbounded_channel specialized for Instant.
pub fn unbounded_channel() (InstantSender, InstantReceiver) {
	channel := &InstantChannel{}
	return InstantSender{ channel: channel }, InstantReceiver{ channel: channel }
}

// STUB: Tokio's start_paused runtime boundary for deterministic scheduler tests.
pub fn fixture_paused_channel(initial std_time.Instant) (InstantSender, InstantReceiver) {
	channel := &InstantChannel{ paused: true, clock: initial }
	return InstantSender{ channel: channel }, InstantReceiver{ channel: channel }
}

// STUB: UnboundedSender::clone shares the queue and increments its live sender count.
pub fn (sender &InstantSender) clone() InstantSender {
	unsafe {
		mut channel := sender.channel
		channel.mutex.lock()
		defer { channel.mutex.unlock() }
		assert sender.lease.active
		channel.senders++
		return InstantSender{ channel: channel }
	}
}

// STUB: Instant::now in the current Tokio runtime; production reads the native clock.
pub fn (sender &InstantSender) now() std_time.Instant {
	unsafe {
		mut channel := sender.channel
		channel.mutex.lock()
		defer { channel.mutex.unlock() }
		return if channel.paused { channel.clock } else { std_time.Instant.now() }
	}
}

// STUB: UnboundedSender::send never blocks; it fails when the receiving half is closed.
pub fn (sender &InstantSender) send(draw_at std_time.Instant) ! {
	unsafe {
		mut channel := sender.channel
		channel.mutex.lock()
		defer { channel.mutex.unlock() }
		if channel.record_attempts {
			channel.attempts << draw_at
		}
		if !sender.lease.active || !channel.receiver_alive {
			return error('channel closed')
		}
		channel.requests << draw_at
		channel.revision++
		channel.wake.post()
	}
}

// STUB: Tokio sender destruction. Normal GC builds need explicit close because V has no
// deterministic scope destructor there; -ownership invokes the Drop hook at scope exit.
pub fn (sender &InstantSender) close() {
	unsafe {
		mut channel := sender.channel
		channel.mutex.lock()
		defer { channel.mutex.unlock() }
		mut lease := sender.lease
		if lease.active {
			lease.active = false
			channel.senders--
			channel.revision++
			channel.wake.post()
			channel.release_wake_if_closed()
		}
	}
}

// STUB: Tokio owns and releases the channel's wake state with its last use. V's GC can
// reclaim the backing allocation, but native mutex/condition resources need explicit release.
// All callers hold channel.mutex. A receive pins the wake across the unlock/wait boundary,
// so closing both halves concurrently cannot destroy synchronization a parked actor still uses.
fn (mut channel InstantChannel) release_wake_if_closed() {
	if channel.wake_alive && channel.senders == 0 && !channel.receiver_alive && channel.receive_calls == 0 {
		channel.wake.destroy()
		channel.wake_alive = false
	}
}

// STUB: ownership destructor for the sender lease.
pub fn (mut sender InstantSender) drop() {
	sender.close()
}

// STUB: UnboundedReceiver destruction closes the channel to future sends.
pub fn (receiver &InstantReceiver) close() {
	unsafe {
		mut channel := receiver.channel
		channel.mutex.lock()
		defer { channel.mutex.unlock() }
		if channel.receiver_alive {
			channel.receiver_alive = false
			channel.requests.clear()
			channel.wake.post()
			channel.release_wake_if_closed()
		}
	}
}

// STUB: ownership destructor for the receiver half.
pub fn (mut receiver InstantReceiver) drop() {
	receiver.close()
}

// STUB: tokio::select! of receiver.recv() and sleep_until(target). A queued Instant wins
// before a ready deadline, retaining coalescing of a submitted batch. Closure drains queued
// requests before returning None, as Tokio's unbounded receiver does.
pub fn (mut receiver InstantReceiver) recv_until(target std_time.Instant) ReceiveEvent {
	unsafe {
		mut channel := receiver.channel
		channel.mutex.lock()
		if !channel.receiver_alive {
			channel.mutex.unlock()
			return ReceiveEvent{ kind: .closed }
		}
		channel.receive_calls++
		channel.mutex.unlock()
		defer {
			channel.mutex.lock()
			channel.receive_calls--
			channel.release_wake_if_closed()
			channel.mutex.unlock()
		}
		for {
			channel.mutex.lock()
			if !channel.receiver_alive {
				channel.mutex.unlock()
				return ReceiveEvent{ kind: .closed }
			}
			// Tokio's current-thread paused runtime polls tasks only after yielding.
			// Gate fixture sends until advance/recv explicitly yields the actor.
			if channel.paused && channel.revision > channel.drive_revision && channel.senders > 0 {
				channel.mutex.unlock()
				channel.wake.wait()
				continue
			}
			now := if channel.paused { channel.clock } else { std_time.Instant.now() }
			// Tokio select is fair between ready branches. Bound receive bursts so a
			// continuously replenished queue cannot starve an already-ready draw.
			if target <= now && channel.ready_receives >= 64 && channel.senders > 0 {
				channel.ready_receives = 0
				channel.mutex.unlock()
				return ReceiveEvent{ kind: .deadline }
			}
			if channel.requests.len > 0 {
				if target <= now {
					channel.ready_receives++
				}
				draw_at := channel.requests[0]
				channel.requests.delete(0)
				channel.mutex.unlock()
				return ReceiveEvent{ kind: .request, draw_at: draw_at }
			}
			if channel.senders == 0 || !channel.receiver_alive {
				channel.mutex.unlock()
				return ReceiveEvent{ kind: .closed }
			}
			if target <= now {
				channel.ready_receives = 0
				channel.mutex.unlock()
				return ReceiveEvent{ kind: .deadline }
			}
			channel.sleep_target = target
			channel.has_sleep_target = true
			channel.settled = channel.revision
			paused := channel.paused
			channel.mutex.unlock()
			if paused {
				channel.wake.wait()
			} else {
				duration := target.duration_since(now)
				// Only the native wait API narrows to i64 nanoseconds. Longer deadlines wait
				// in bounded pieces and recompute the full-width monotonic target afterward.
				wait_nanos := if duration.as_secs() > 9_223_372_036 || (duration.as_secs() == 9_223_372_036 && duration.subsec_nanos() > 854_775_807) {
					i64(9_223_372_036_854_775_807)
				} else {
					i64(duration.as_secs() * 1_000_000_000 + duration.subsec_nanos())
				}
				channel.wake.timed_wait(wait_nanos)
			}
		}
	}
	return ReceiveEvent{ kind: .closed }
}

// STUB: runtime-clock lookup from the receiver side.
pub fn (receiver &InstantReceiver) now() std_time.Instant {
	unsafe {
		mut channel := receiver.channel
		channel.mutex.lock()
		defer { channel.mutex.unlock() }
		return if channel.paused { channel.clock } else { std_time.Instant.now() }
	}
}

// STUB: test-runtime time::advance wakes the real scheduler task, then waits for it to
// finish every ready receive/deadline branch and return to sleep. No scheduler logic is mocked.
pub fn (sender &InstantSender) fixture_advance(duration std_time.Duration) {
	unsafe {
		mut channel := sender.channel
		channel.mutex.lock()
		assert channel.paused
		channel.clock = channel.clock.add(duration)
		channel.revision++
		channel.drive_revision = channel.revision
		if channel.wake_alive {
			channel.wake.post()
		}
		channel.mutex.unlock()
	}
	sender.fixture_wait_settled()
}

// STUB: a paused-runtime synchronization barrier, analogous to yielding to Tokio's task.
pub fn (sender &InstantSender) fixture_wait_settled() {
	until := std_time.Instant.now().add(std_time.Duration.from_secs(5))
	unsafe {
		mut channel := sender.channel
		channel.mutex.lock()
		channel.drive_revision = channel.revision
		if channel.wake_alive {
			channel.wake.post()
		}
		channel.mutex.unlock()
		for {
			channel.mutex.lock()
			settled := channel.settled >= channel.revision || !channel.receiver_alive
			channel.mutex.unlock()
			if settled {
				return
			}
			assert std_time.Instant.now() < until, 'paused scheduler did not become idle'
			time.sleep(50 * time.microsecond)
		}
	}
}

// STUB: Tokio's paused timer driver observes the actual scheduler sleep target. This lets
// timeout awaits advance to an earlier draw instead of silently discarding it at timeout.
pub fn (sender &InstantSender) fixture_sleep_target() ?std_time.Instant {
	unsafe {
		mut channel := sender.channel
		channel.mutex.lock()
		defer { channel.mutex.unlock() }
		assert channel.paused
		if !channel.has_sleep_target || !channel.receiver_alive {
			return none
		}
		return channel.sleep_target
	}
}

// STUB: record scheduling attempts only for the screen-size no-op fixture.
pub fn (sender &InstantSender) fixture_record_attempts() {
	unsafe {
		mut channel := sender.channel
		channel.mutex.lock()
		defer { channel.mutex.unlock() }
		channel.record_attempts = true
	}
}

// STUB: screen-size observation; production channels do not retain this history.
pub fn (sender &InstantSender) fixture_request_count() int {
	unsafe {
		mut channel := sender.channel
		channel.mutex.lock()
		defer { channel.mutex.unlock() }
		return channel.attempts.len
	}
}

// STUB: last source-shaped attempted deadline for the screen-size fixture.
pub fn (sender &InstantSender) fixture_last_request() ?std_time.Instant {
	unsafe {
		mut channel := sender.channel
		channel.mutex.lock()
		defer { channel.mutex.unlock() }
		if channel.attempts.len == 0 {
			return none
		}
		return channel.attempts[channel.attempts.len - 1]
	}
}
