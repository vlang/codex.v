module std_time

// STUB: std::time::Duration::as_secs_f32, retaining Rust's f32 rounding at both
// conversions and the fractional-second addition.
pub fn (duration Duration) as_secs_f32() f32 {
	return f32(duration.as_secs()) + f32(duration.subsec_nanos()) / f32(1_000_000_000)
}
