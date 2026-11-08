module rust_rand

import crypto.rand
import std_ops

// STUB: rand::Rng's observed random_range API for a half-open usize range.
// The Rust crate maps to rust_rand because V's standard library already owns rand.
pub interface Rng {
	// STUB: rand::Rng::random_range's observed mutable-borrow call signature.
mut:
	random_range(range std_ops.Range[usize]) usize
}

// STUB: rand::rngs::ThreadRng. Rust's thread-local reseeding ChaCha generator
// is untranslated; this adapter obtains fresh OS entropy instead, while preserving
// the observed unbiased range sampling and panic when randomness is unavailable.
pub struct ThreadRng {}

// STUB: rand::rng, providing the source-shaped random-number-generator handle.
pub fn rng() ThreadRng {
	return ThreadRng{}
}

// STUB: rand::Rng::random_range for the observed usize range. Rejection sampling
// avoids modulo bias, and the endpoint check preserves Rust's empty-range panic.
pub fn (mut rng ThreadRng) random_range(range std_ops.Range[usize]) usize {
	assert range.start < range.end, 'cannot sample empty range'
	width := u64(range.end - range.start)
	threshold := (~u64(0) - width + 1) % width
	for {
		bytes := rand.bytes(8) or { panic('could not obtain random entropy: ${err}') }
		mut draw := u64(0)
		for index in 0 .. 8 {
			draw |= u64(bytes[index]) << (8 * index)
		}
		if draw >= threshold {
			return range.start + usize(draw % width)
		}
	}
	return range.start
}
