module frame_rate_limiter

import std_time

fn test_default_does_not_clamp() {
	t0 := std_time.Instant.now()
	limiter := FrameRateLimiter.default()
	assert limiter.clamp_deadline(t0) == t0
}

fn test_clamps_to_min_interval_since_last_emit() {
	t0 := std_time.Instant.now()
	mut limiter := FrameRateLimiter.default()

	assert limiter.clamp_deadline(t0) == t0
	limiter.mark_emitted(t0)

	too_soon := t0.add(std_time.Duration.from_millis(1))
	assert limiter.clamp_deadline(too_soon) == t0.add(min_frame_interval)
}

fn test_at_and_after_the_minimum_deadline_remain_unchanged() {
	t0 := std_time.Instant.now()
	mut limiter := FrameRateLimiter.default()
	limiter.mark_emitted(t0)
	boundary := t0.add(min_frame_interval)
	later := t0.add(std_time.Duration.from_millis(20))
	assert limiter.clamp_deadline(boundary) == boundary
	assert limiter.clamp_deadline(later) == later
	assert limiter.clamp_deadline(t0) == boundary
}

fn test_mark_emitted_replaces_the_previous_draw_and_copy_values_remain_reusable() {
	t0 := std_time.Instant.now()
	mut limiter := FrameRateLimiter.default()
	limiter.mark_emitted(t0)
	next := t0.add(std_time.Duration.from_millis(30))
	limiter.mark_emitted(next)
	assert limiter.clamp_deadline(t0) == next.add(min_frame_interval)
	assert limiter.clamp_deadline(t0) == next.add(min_frame_interval)
	assert t0.add(std_time.Duration.from_millis(30)) == next
}

fn test_checked_add_overflow_falls_back_to_the_last_emitted_instant() {
	last := std_time.Instant.maximum_for_clock()
	assert last.checked_add(min_frame_interval) == none
	mut limiter := FrameRateLimiter.default()
	limiter.mark_emitted(last)
	assert limiter.clamp_deadline(last.sub(std_time.Duration.from_millis(1))) == last
	assert limiter.clamp_deadline(last) == last
}
