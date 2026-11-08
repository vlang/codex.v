module ascii_animation

import math.unsigned
import std_ops
import std_time
import codex_tui.frames
import codex_tui.tui.frame_requester

fn test_frame_tick_must_be_nonzero() {
	assert frames.frame_tick_default.as_millis() > unsigned.uint128_zero
}

fn test_new_borrows_default_variants_and_owns_requester() {
	requester := frame_requester.FrameRequester.test_dummy()
	observer := requester.clone()
	animation := AsciiAnimation.new(requester)
	defer {
		animation.close()
		observer.close()
	}
	assert animation.variants == frames.all_variants
	assert animation.variant_idx == 0
	assert animation.frame_tick == frames.frame_tick_default
	assert animation.frames() == frames.frames_default
	animation.schedule_next_frame()
	assert observer.fixture_request_count() == 1
	assert animation.frames().len == 36
}

fn test_with_variants_clamps_index_including_usize_max() {
	variants := &[&['a'], &['b'], &['c']]
	for index in [usize(0), usize(1), usize(2), usize(3), ~usize(0)] {
		animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
			variants, index)
		defer { animation.close() }
		expected := if index < 2 { index } else { usize(2) }
		assert animation.variant_idx == expected
		assert animation.frames() == (*variants)[expected]
	}
	assert variants.len == 3
	assert (*(*variants)[0])[0] == 'a'
}

fn test_empty_variant_returns_empty_frame() {
	variants := &[&[]string{}]
	animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 0)
	defer { animation.close() }
	assert animation.current_frame() == ''
	assert animation.current_frame() == ''
	assert animation.frames().len == 0
	assert variants.len == 1
}

fn test_zero_and_sub_millisecond_ticks_return_first_frame_and_schedule_now() {
	variants := &[&['first', 'second']]
	mut animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 0)
	defer { animation.close() }
	for tick in [std_time.duration_zero, std_time.Duration.from_nanos(999_999)] {
		animation.frame_tick = tick
		assert animation.current_frame() == 'first'
		before := std_time.Instant.now()
		animation.schedule_next_frame()
		after := std_time.Instant.now()
		deadline := animation.request_frame.fixture_last_request() or { panic('missing request') }
		assert deadline >= before
		assert deadline <= after
	}
	assert animation.request_frame.fixture_request_count() == 2
	assert (*(*variants)[0])[1] == 'second'
}

fn test_current_frame_divides_elapsed_and_wraps_in_order() {
	variants := &[&['zero', 'one', 'two']]
	mut animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 0)
	defer { animation.close() }
	animation.frame_tick = std_time.Duration.from_secs(1_000)
	for index in 0 .. 9 {
		animation.start = std_time.Instant.now().sub(std_time.Duration.from_secs(u64(index) * 1_000 + 1))
		assert animation.current_frame() == (*(*variants)[0])[index % 3]
	}
	assert animation.request_frame.fixture_request_count() == 0
}

fn test_regressed_start_saturates_to_first_frame() {
	variants := &[&['first', 'second']]
	mut animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 0)
	defer { animation.close() }
	animation.start = std_time.Instant.now().add(std_time.Duration.from_secs(10_000))
	assert animation.current_frame() == 'first'
}

fn test_schedule_next_frame_uses_future_delay() {
	variants := &[&['frame']]
	mut animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 0)
	defer { animation.close() }
	animation.frame_tick = std_time.Duration.from_secs(10)
	animation.start = std_time.Instant.now()
	before := std_time.Instant.now()
	animation.schedule_next_frame()
	after := std_time.Instant.now()
	deadline := animation.request_frame.fixture_last_request() or { panic('missing request') }
	assert deadline > after
	assert deadline <= after.add(animation.frame_tick)
	assert deadline >= before.add(std_time.Duration.from_secs(9))
	assert animation.request_frame.fixture_request_count() == 1
}

fn test_schedule_remainder_waits_full_tick_at_exact_boundary() {
	variants := &[&['frame']]
	animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 0)
	defer { animation.close() }
	tick := unsigned.uint128_from_64(80)
	for elapsed in [u64(0), u64(80), u64(800), ~u64(0) - 15] {
		before := std_time.Instant.now()
		animation.schedule_after_elapsed(tick, unsigned.uint128_from_64(elapsed))
		after := std_time.Instant.now()
		deadline := animation.request_frame.fixture_last_request() or { panic('missing request') }
		assert deadline >= before.add(std_time.Duration.from_millis(80))
		assert deadline <= after.add(std_time.Duration.from_millis(80))
	}
	assert animation.request_frame.fixture_request_count() == 4
}

fn test_schedule_remainder_waits_only_until_next_tick() {
	variants := &[&['frame']]
	animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 0)
	defer { animation.close() }
	for elapsed in [u64(1), u64(79), u64(81), u64(159)] {
		before := std_time.Instant.now()
		animation.schedule_after_elapsed(unsigned.uint128_from_64(80), unsigned.uint128_from_64(elapsed))
		after := std_time.Instant.now()
		deadline := animation.request_frame.fixture_last_request() or { panic('missing request') }
		delay := std_time.Duration.from_millis(80 - elapsed % 80)
		assert deadline >= before.add(delay)
		assert deadline <= after.add(delay)
	}
}

fn test_schedule_full_width_delay_overflow_falls_back_to_immediate() {
	variants := &[&['frame']]
	animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 0)
	defer { animation.close() }
	tick := std_time.duration_max.as_millis()
	assert tick.hi != 0
	for elapsed in [unsigned.uint128_zero, unsigned.uint128_from_64(1), tick] {
		before := std_time.Instant.now()
		animation.schedule_after_elapsed(tick, elapsed)
		after := std_time.Instant.now()
		deadline := animation.request_frame.fixture_last_request() or { panic('missing request') }
		assert deadline >= before
		assert deadline <= after
	}
	assert animation.request_frame.fixture_request_count() == 3
}

fn test_schedule_large_tick_can_still_produce_small_checked_delay() {
	variants := &[&['frame']]
	animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 0)
	defer { animation.close() }
	tick := std_time.duration_max.as_millis()
	before := std_time.Instant.now()
	animation.schedule_after_elapsed(tick, tick.sub_64(7))
	after := std_time.Instant.now()
	deadline := animation.request_frame.fixture_last_request() or { panic('missing request') }
	assert deadline >= before.add(std_time.Duration.from_millis(7))
	assert deadline <= after.add(std_time.Duration.from_millis(7))
}

fn test_schedule_checked_delay_accepts_u64_max_but_rejects_next_millisecond() {
	variants := &[&['frame']]
	animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 0)
	defer { animation.close() }
	maximum := unsigned.uint128_from_64(~u64(0))
	before := std_time.Instant.now()
	animation.schedule_after_elapsed(maximum, unsigned.uint128_zero)
	after := std_time.Instant.now()
	deadline := animation.request_frame.fixture_last_request() or { panic('missing request') }
	delay := std_time.Duration.from_millis(~u64(0))
	assert deadline >= before.add(delay)
	assert deadline <= after.add(delay)
	before_immediate := std_time.Instant.now()
	animation.schedule_after_elapsed(maximum.add_64(1), unsigned.uint128_zero)
	after_immediate := std_time.Instant.now()
	immediate := animation.request_frame.fixture_last_request() or { panic('missing request') }
	assert immediate >= before_immediate
	assert immediate <= after_immediate
	assert animation.request_frame.fixture_request_count() == 2
}

fn test_frame_index_retains_full_u128_quotient_and_remainder() {
	elapsed := std_time.duration_max.as_millis()
	assert elapsed.hi != 0
	// (u64::MAX * 1000 + 999) / 80, modulo 36 is 19; narrowing to u64 first gives 27.
	assert frame_index(elapsed, unsigned.uint128_from_64(80), 36) == 19
	assert frame_index(elapsed, elapsed, 36) == 1
	assert frame_index(elapsed.sub_64(1), elapsed, 36) == 0
	assert frame_index(elapsed, unsigned.uint128_from_64(1), 1) == 0
}

type Draws = []usize

struct ScriptedRng {
	draws &Draws
mut:
	next_draw int
}

fn (mut rng ScriptedRng) random_range(range std_ops.Range[usize]) usize {
	assert range == std_ops.Range[usize]{ start: 0, end: 3 }
	assert rng.next_draw < rng.draws.len
	draw := (*rng.draws)[rng.next_draw]
	rng.next_draw++
	assert draw >= range.start && draw < range.end
	return draw
}

fn test_random_variant_rejects_current_draws_then_schedules_exactly_once() {
	variants := &[&['a'], &['b'], &['c']]
	mut animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 1)
	defer { animation.close() }
	start := animation.start
	tick := animation.frame_tick
	mut rng := ScriptedRng{ draws: &[usize(1), usize(1), usize(1), usize(2)] }
	assert animation.pick_random_variant_with_rng(mut rng)
	assert animation.variant_idx == 2
	assert rng.next_draw == 4
	assert animation.request_frame.fixture_request_count() == 1
	assert (*animation.frames())[0] == 'c'
	assert animation.start == start
	assert animation.frame_tick == tick
	assert (*(*variants)[1])[0] == 'b'
}

fn test_single_variant_does_not_schedule_or_change_timing() {
	variants := &[&['one']]
	mut animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 99)
	defer { animation.close() }
	start := animation.start
	assert !animation.pick_random_variant()
	assert !animation.pick_random_variant()
	assert animation.variant_idx == 0
	assert animation.request_frame.fixture_request_count() == 0
	assert animation.start == start
}

fn test_production_random_selection_always_changes_variant() {
	variants := &[&['a'], &['b'], &['c']]
	mut animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 0)
	defer { animation.close() }
	start := animation.start
	for _ in 0 .. 32 {
		previous := animation.variant_idx
		assert animation.pick_random_variant()
		assert animation.variant_idx != previous
		assert animation.variant_idx < usize(variants.len)
		assert (*animation.frames())[0] == (*(*variants)[animation.variant_idx])[0]
	}
	assert animation.request_frame.fixture_request_count() == 32
	assert animation.start == start
}

fn test_borrowed_dynamic_frame_owners_and_owned_results_survive_repeated_calls() {
	mut first := 'dynamic first Ω'
	mut second := 'dynamic second 🦀'
	$if ownership ? {
		first = first.to_owned()
		second = second.to_owned()
	}
	variant := &[first, second]
	variants := &[variant]
	mut animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 0)
	defer { animation.close() }
	animation.frame_tick = std_time.duration_zero
	first_result := animation.current_frame()
	second_result := animation.current_frame()
	assert first_result == 'dynamic first Ω'
	assert second_result == first_result
	assert animation.frames() == variant
	assert (*animation.frames())[1] == 'dynamic second 🦀'
	assert (*variant)[0] == first_result
	assert (*variant)[1] == 'dynamic second 🦀'
	assert (*variants)[0] == variant
	animation.schedule_next_frame()
	assert animation.current_frame() == first_result
	assert first_result == second_result
}

fn render_temporary_frames() string {
	mut frame := 'temporary animation Ω'
	$if ownership ? {
		frame = frame.to_owned()
	}
	variant := &[frame]
	variants := &[variant]
	mut animation := AsciiAnimation.with_variants(frame_requester.FrameRequester.test_dummy(),
		variants, 0)
	defer { animation.close() }
	animation.frame_tick = std_time.duration_zero
	return animation.current_frame()
}

fn test_owned_current_frame_survives_animation_and_borrowed_storage_teardown() {
	first := render_temporary_frames()
	second := render_temporary_frames()
	assert first == 'temporary animation Ω'
	assert second == first
}
