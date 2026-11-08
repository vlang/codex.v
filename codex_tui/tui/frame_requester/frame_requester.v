// Frame draw scheduling utilities for the TUI.
//
// This module exposes FrameRequester, a lightweight handle that widgets and
// background tasks can clone to request future redraws of the TUI.
//
// Internally it spawns a FrameScheduler task that coalesces many requests
// into a single notification on a broadcast channel used by the main TUI event
// loop. This keeps animations and status updates smooth without redrawing more
// often than necessary.
//
// This follows the actor-style design from
// “Actors with Tokio” (https://ryhl.io/blog/actors-with-tokio/), with a
// dedicated scheduler task and lightweight request handles.
module frame_requester

import std_time
import tokio.sync.broadcast
import tokio.sync.mpsc
import codex_tui.tui.frame_rate_limiter

// A requester for scheduling future frame draws on the TUI event loop.
//
// This is the handler side of an actor/handler pair with FrameScheduler, which coalesces
// multiple frame requests into a single draw operation.
//
// Clones of this type can be freely shared across tasks to make it possible to trigger frame draws
// from anywhere in the TUI code.
// V's structural formatting provides Debug; clone explicitly duplicates the channel sender lease.
pub struct FrameRequester {
	frame_schedule_tx mpsc.InstantSender
}

// Create a new FrameRequester and spawn its associated FrameScheduler task.
//
// The provided draw_tx is used to notify the TUI event loop of scheduled draws.
pub fn FrameRequester.new(draw_tx broadcast.DrawSender) FrameRequester {
	tx, rx := mpsc.unbounded_channel()
	scheduler := FrameScheduler.new(rx, draw_tx)
	spawn scheduler.run()
	return FrameRequester{ frame_schedule_tx: tx }
}

// Rust's derived Clone duplicates the request sender, rather than the queue or actor.
pub fn (requester &FrameRequester) clone() FrameRequester {
	return FrameRequester{ frame_schedule_tx: requester.frame_schedule_tx.clone() }
}

// Schedule a frame draw as soon as possible.
pub fn (requester &FrameRequester) schedule_frame() {
	// The runtime clock is native Instant::now in production and paused in deterministic tests.
	requester.frame_schedule_tx.send(requester.frame_schedule_tx.now()) or {}
}

// Schedule a frame draw to occur after the specified duration.
pub fn (requester &FrameRequester) schedule_frame_in(dur std_time.Duration) {
	requester.frame_schedule_tx.send(requester.frame_schedule_tx.now().add(dur)) or {}
}

// Create a no-op frame requester for tests.
// This source test-only helper remains exported for the untranslated TUI test-support boundary.
pub fn FrameRequester.test_dummy() FrameRequester {
	tx, rx := mpsc.unbounded_channel()
	tx.fixture_record_attempts()
	rx.close()
	return FrameRequester{ frame_schedule_tx: tx }
}

// Normal V GC builds have no Rust-style deterministic drop; explicitly release a requester
// when its owner finishes. Under -ownership the sender field's Drop hook runs at scope exit.
pub fn (requester &FrameRequester) close() {
	requester.frame_schedule_tx.close()
}

// A scheduler for coalescing frame draw requests and notifying the TUI event loop.
//
// This type is internal to FrameRequester and is spawned as a task to handle scheduling logic.
//
// To avoid wasted redraw work, draw notifications are clamped to a maximum of 120 FPS (see
// FrameRateLimiter).
struct FrameScheduler {
	draw_tx broadcast.DrawSender
mut:
	receiver     mpsc.InstantReceiver
	rate_limiter frame_rate_limiter.FrameRateLimiter
}

// Create a new FrameScheduler with the provided receiver and draw notification sender.
fn FrameScheduler.new(receiver mpsc.InstantReceiver, draw_tx broadcast.DrawSender) FrameScheduler {
	return FrameScheduler{
		receiver:     receiver
		draw_tx:      draw_tx
		rate_limiter: frame_rate_limiter.FrameRateLimiter.default()
	}
}

// V has no function-local constants; Rust's run-local ONE_YEAR remains private here.
const one_year = std_time.Duration.from_secs(60 * 60 * 24 * 365)

// Run the scheduling loop, coalescing frame requests and notifying the TUI event loop.
//
// This method runs indefinitely until all senders are dropped. A single draw notification
// is sent for multiple requests scheduled before the next draw deadline.
// V runs the actor on a native task; recv_until implements the typed receive/sleep selection.
fn (owned_scheduler FrameScheduler) run() {
	mut scheduler := owned_scheduler
	mut next_deadline := ?std_time.Instant(none)
	defer {
		scheduler.receiver.close()
		scheduler.draw_tx.close()
	}
	for {
		target := next_deadline or { scheduler.receiver.now().add(one_year) }
		event := scheduler.receiver.recv_until(target)
		match event.kind {
			.closed {
				// All senders dropped; exit the scheduler.
				break
			}
			.request {
				draw_at := scheduler.rate_limiter.clamp_deadline(event.draw_at)
				if current := next_deadline {
					next_deadline = if current < draw_at { current } else { draw_at }
				} else {
					next_deadline = draw_at
				}
				// Do not send a draw immediately here. By continuing the loop,
				// we recompute the sleep target so the draw fires once via the
				// sleep branch, coalescing multiple requests into a single draw.
				continue
			}
			.deadline {
				if next_deadline != none {
					next_deadline = none
					scheduler.rate_limiter.mark_emitted(scheduler.receiver.now())
					scheduler.draw_tx.send(broadcast.Draw{}) or {}
				}
			}
		}
	}
}
