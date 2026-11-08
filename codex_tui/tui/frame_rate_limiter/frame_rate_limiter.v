// Limits how frequently frame draw notifications may be emitted.
//
// Widgets sometimes call `FrameRequester.schedule_frame()` more frequently than a user can
// perceive. This limiter clamps draw notifications to a maximum of 120 FPS to avoid wasted work.
//
// This is intentionally a small, pure helper so it can be unit-tested in isolation and used by
// the async frame scheduler without adding complexity to the app/event loop.
module frame_rate_limiter

import std_time

// A 120 FPS minimum frame interval (≈8.33ms).
pub const min_frame_interval = std_time.Duration.from_nanos(8_333_334)

// Remembers the most recent emitted draw, allowing deadlines to be clamped forward.
// V's structural formatting supplies Debug; this scalar-only value defaults to no previous draw.
pub struct FrameRateLimiter {
mut:
	last_emitted_at ?std_time.Instant
}

pub fn FrameRateLimiter.default() FrameRateLimiter {
	return FrameRateLimiter{}
}

// Returns `requested`, clamped forward if it would exceed the maximum frame rate.
pub fn (limiter &FrameRateLimiter) clamp_deadline(requested std_time.Instant) std_time.Instant {
	last_emitted_at := limiter.last_emitted_at or { return requested }
	min_allowed := last_emitted_at.checked_add(min_frame_interval) or { last_emitted_at }
	return requested.max(min_allowed)
}

// Records that a draw notification was emitted at `emitted_at`.
pub fn (mut limiter FrameRateLimiter) mark_emitted(emitted_at std_time.Instant) {
	limiter.last_emitted_at = emitted_at
}
