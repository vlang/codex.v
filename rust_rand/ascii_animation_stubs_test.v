module rust_rand

import std_ops

fn test_random_range_single_value_and_reusable_copy_endpoints() {
	mut rng := rust_rand.rng()
	range := std_ops.Range[usize]{ start: 17, end: 18 }
	for _ in 0 .. 8 {
		assert rng.random_range(range) == 17
	}
	assert range == std_ops.Range[usize]{ start: 17, end: 18 }
}

fn test_random_range_preserves_nonzero_start_and_exclusive_end() {
	mut rng := rust_rand.rng()
	range := std_ops.Range[usize]{ start: 97, end: 104 }
	for _ in 0 .. 32 {
		draw := rng.random_range(range)
		assert draw >= 97
		assert draw < 104
	}
}

fn test_random_range_preserves_full_usize_endpoints() {
	mut rng := rust_rand.rng()
	wide := std_ops.Range[usize]{ start: 0, end: ~usize(0) }
	narrow := std_ops.Range[usize]{ start: ~usize(0) - 2, end: ~usize(0) }
	for _ in 0 .. 8 {
		assert rng.random_range(wide) < ~usize(0)
		draw := rng.random_range(narrow)
		assert draw >= ~usize(0) - 2
		assert draw < ~usize(0)
	}
}
