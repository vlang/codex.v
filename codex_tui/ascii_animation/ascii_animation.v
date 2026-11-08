module ascii_animation

import math.unsigned
import std_time
import std_ops
import rust_rand as rand
import codex_tui.frames
import codex_tui.tui.frame_requester

// An alias permits a reference-valued struct field without V's &[] field ban.
// The underlying array and its static frame-slice references are still borrowed.
type VariantSlices = []&[]string

// Drives ASCII art animations shared across popups and onboarding widgets.
pub struct AsciiAnimation {
	request_frame frame_requester.FrameRequester
	// V array references preserve Rust's shared static slices. The referenced
	// variant/frame storage must remain immutable and outlive the animation.
	variants &VariantSlices
mut:
	variant_idx usize
	frame_tick  std_time.Duration
	start       std_time.Instant
}

pub fn AsciiAnimation.new(request_frame frame_requester.FrameRequester) AsciiAnimation {
	return AsciiAnimation.with_variants(request_frame, frames.all_variants, /* variant_idx */
		0)
}

pub fn AsciiAnimation.with_variants(request_frame frame_requester.FrameRequester,
	variants &[]&[]string, variant_idx usize) AsciiAnimation {
	assert variants.len != 0, 'AsciiAnimation requires at least one animation variant'
	clamped_idx := if variant_idx < usize(variants.len - 1) {
		variant_idx
	} else {
		usize(variants.len - 1)
	}
	return AsciiAnimation{
		request_frame: request_frame
		variants:      variants
		variant_idx:   clamped_idx
		frame_tick:    frames.frame_tick_default
		start:         std_time.Instant.now()
	}
}

pub fn (animation &AsciiAnimation) schedule_next_frame() {
	tick_ms := animation.frame_tick.as_millis()
	if tick_ms.is_zero() {
		animation.request_frame.schedule_frame()
		return
	}
	elapsed_ms := animation.start.elapsed().as_millis()
	animation.schedule_after_elapsed(tick_ms, elapsed_ms)
}

// The clock-independent remainder calculation is shared with deterministic tests.
// Both operands retain Rust's full u128 range; conversion to u64 is checked only
// after subtracting the elapsed remainder, at the source TryFrom boundary.
fn (animation &AsciiAnimation) schedule_after_elapsed(tick_ms unsigned.Uint128,
	elapsed_ms unsigned.Uint128) {
	rem_ms := elapsed_ms.mod(tick_ms)
	delay_ms := if rem_ms.is_zero() { tick_ms } else { tick_ms.sub(rem_ms) }
	if delay_ms.hi == 0 {
		animation.request_frame.schedule_frame_in(std_time.Duration.from_millis(delay_ms.lo))
	} else {
		animation.request_frame.schedule_frame()
	}
}

// V has no borrowed string-slice return equivalent to Rust's &'static str. Borrow
// the animation/frame storage and clone just the selected string for this owned return.
pub fn (animation &AsciiAnimation) current_frame() string {
	variant_frames := animation.frames()
	if variant_frames.len == 0 {
		return ''
	}
	tick_ms := animation.frame_tick.as_millis()
	if tick_ms.is_zero() {
		return (*variant_frames)[0].clone()
	}
	elapsed_ms := animation.start.elapsed().as_millis()
	idx := frame_index(elapsed_ms, tick_ms, usize(variant_frames.len))
	return (*variant_frames)[idx].clone()
}

// Keep division and remainder at u128 width until the index is below frames.len.
fn frame_index(elapsed_ms unsigned.Uint128, tick_ms unsigned.Uint128, len usize) usize {
	return usize(elapsed_ms.div(tick_ms).mod_64(u64(len)))
}

pub fn (mut animation AsciiAnimation) pick_random_variant() bool {
	if animation.variants.len <= 1 {
		return false
	}
	mut rng := rand.rng()
	return animation.pick_random_variant_with_rng(mut rng)
}

// Normal V GC builds require explicit requester release. Under -ownership the
// owned requester's sender Drop hook releases its lease at animation scope exit.
pub fn (animation &AsciiAnimation) close() {
	animation.request_frame.close()
}

// Rust's RNG trait is passed through a private helper so tests can exercise the
// same rejection loop with deterministic draws, without changing global randomness.
fn (mut animation AsciiAnimation) pick_random_variant_with_rng(mut rng rand.Rng) bool {
	mut next := animation.variant_idx
	for next == animation.variant_idx {
		next = rng.random_range(std_ops.Range[usize]{ start: 0, end: usize(animation.variants.len) })
	}
	animation.variant_idx = next
	animation.request_frame.schedule_frame()
	return true
}

fn (animation &AsciiAnimation) frames() &[]string {
	return (*animation.variants)[animation.variant_idx]
}
