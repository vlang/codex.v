module std_time

import math.unsigned

// STUB: std::time::Duration. Keep Rust's entire u64-second/u32-nanosecond range and Copy
// semantics rather than narrowing to V time.Duration's signed 64-bit nanoseconds.
pub struct Duration {
	secs  u64
	nanos u32
}

// STUB: std::time::Duration::ZERO.
pub const duration_zero = Duration{}

// STUB: std::time::Duration::MAX.
pub const duration_max = Duration{
	secs:  ~u64(0)
	nanos: 999_999_999
}

// STUB: std::time::Duration::new, including normalization and a panic on seconds overflow.
pub fn Duration.new(secs u64, nanos u32) Duration {
	carry := u64(nanos / 1_000_000_000)
	if secs > ~u64(0) - carry {
		panic('overflow in Duration::new')
	}
	return Duration{ secs: secs + carry, nanos: nanos % 1_000_000_000 }
}

// STUB: std::time::Duration::from_secs.
pub fn Duration.from_secs(secs u64) Duration {
	return Duration{ secs: secs }
}

// STUB: std::time::Duration::from_millis.
pub fn Duration.from_millis(millis u64) Duration {
	return Duration{ secs: millis / 1_000, nanos: u32(millis % 1_000) * 1_000_000 }
}

// STUB: std::time::Duration::from_micros.
pub fn Duration.from_micros(micros u64) Duration {
	return Duration{ secs: micros / 1_000_000, nanos: u32(micros % 1_000_000) * 1_000 }
}

// STUB: std::time::Duration::from_nanos.
pub fn Duration.from_nanos(nanos u64) Duration {
	return Duration{ secs: nanos / 1_000_000_000, nanos: u32(nanos % 1_000_000_000) }
}

// STUB: std::time::Duration::as_secs.
pub fn (duration Duration) as_secs() u64 {
	return duration.secs
}

// STUB: std::time::Duration::subsec_nanos.
pub fn (duration Duration) subsec_nanos() u32 {
	return duration.nanos
}

// STUB: std::time::Duration::as_millis. V's allocation-free Uint128 preserves Rust's u128
// result; use quo_rem_64/div and mod_64 for source division and remainder operations.
pub fn (duration Duration) as_millis() unsigned.Uint128 {
	return unsigned.uint128_from_64(duration.secs).mul_64(1_000).add_64(u64(duration.nanos / 1_000_000))
}

// STUB: std::time::Duration::as_micros, retaining the complete u128 result.
pub fn (duration Duration) as_micros() unsigned.Uint128 {
	return unsigned.uint128_from_64(duration.secs).mul_64(1_000_000).add_64(u64(duration.nanos / 1_000))
}

// STUB: std::time::Duration::as_nanos, retaining the complete u128 result.
pub fn (duration Duration) as_nanos() unsigned.Uint128 {
	return unsigned.uint128_from_64(duration.secs).mul_64(1_000_000_000).add_64(u64(duration.nanos))
}

// STUB: std::time::Duration::is_zero.
pub fn (duration Duration) is_zero() bool {
	return duration.secs == 0 && duration.nanos == 0
}

// STUB: std::time::Duration's derived ordering, including nanoseconds within a second.
pub fn (duration Duration) < (other Duration) bool {
	return duration.secs < other.secs || (duration.secs == other.secs && duration.nanos < other.nanos)
}

// STUB: std::time::Duration::checked_add, including the nanosecond carry.
pub fn (duration Duration) checked_add(other Duration) ?Duration {
	if duration.secs > ~u64(0) - other.secs {
		return none
	}
	mut secs := duration.secs + other.secs
	mut nanos := duration.nanos + other.nanos
	if nanos >= 1_000_000_000 {
		if secs == ~u64(0) {
			return none
		}
		secs++
		nanos -= 1_000_000_000
	}
	return Duration{ secs: secs, nanos: nanos }
}

// STUB: std::time::Duration::checked_sub, including the nanosecond borrow.
pub fn (duration Duration) checked_sub(other Duration) ?Duration {
	if duration.secs < other.secs {
		return none
	}
	mut secs := duration.secs - other.secs
	mut nanos := i64(duration.nanos) - i64(other.nanos)
	if nanos < 0 {
		if secs == 0 {
			return none
		}
		secs--
		nanos += 1_000_000_000
	}
	return Duration{ secs: secs, nanos: u32(nanos) }
}

// STUB: std::time::Duration + Duration; the named operation preserves Rust's overflow panic.
pub fn (duration Duration) add(other Duration) Duration {
	return duration.checked_add(other) or { panic('overflow when adding durations') }
}

// STUB: std::time::Duration - Duration; the named operation preserves Rust's underflow panic.
pub fn (duration Duration) sub(other Duration) Duration {
	return duration.checked_sub(other) or { panic('overflow when subtracting durations') }
}

// STUB: std::time::Instant's platform representation. Unix uses signed seconds with canonical
// nanoseconds, matching Rust's full Timespec range. Windows uses Duration's full unsigned range.
// Only the current platform's fields participate in arithmetic and ordering. All fields are
// allocation-free, so Instant and Option<Instant> remain Copy-equivalent under V ownership.
pub struct Instant {
	unix_seconds i64
	unix_nanos   u32
	windows_time Duration
}

// STUB: std::time::Instant::now. The native boundary reads CLOCK_UPTIME_RAW on Apple,
// CLOCK_MONOTONIC on other Unix systems, and QueryPerformanceCounter on Windows. No wall clock
// or i64/u64 nanosecond flattening is used. Windows' arbitrary clock origin need not match Rust's.
pub fn Instant.now() Instant {
	reading := C.codex_frame_monotonic_read()
	if reading.ok == 0 {
		panic('failed to get monotonic time')
	}
	$if windows {
		counter := reading.windows_ticks
		frequency := reading.windows_frequency
		fraction, _ := unsigned.uint128_from_64(counter % frequency).mul_64(1_000_000_000).quo_rem_64(frequency)
		return Instant{
			windows_time: Duration.new(counter / frequency, u32(fraction.lo))
		}
	} $else {
		return Instant{ unix_seconds: reading.unix_seconds, unix_nanos: reading.unix_nanos }
	}
}

// STUB: fixture adapter for the greatest representable std::time::Instant on the current
// platform. It provides the otherwise-unreachable checked_add overflow branch without changing
// Instant::now or making the source limiter depend on a test clock.
pub fn Instant.maximum_for_clock() Instant {
	$if windows {
		return Instant{ windows_time: duration_max }
	} $else {
		return Instant{ unix_seconds: 9_223_372_036_854_775_807, unix_nanos: 999_999_999 }
	}
}

// STUB: std::time::Instant's derived ordering.
pub fn (instant Instant) < (other Instant) bool {
	$if windows {
		return instant.windows_time < other.windows_time
	} $else {
		return instant.unix_seconds < other.unix_seconds || (instant.unix_seconds == other.unix_seconds && instant.unix_nanos < other.unix_nanos)
	}
}

// STUB: std::cmp::Ord::max for std::time::Instant.
pub fn (instant Instant) max(other Instant) Instant {
	return if instant < other { other } else { instant }
}

// STUB: std::time::Instant::checked_add, including the platform's representable range.
pub fn (instant Instant) checked_add(duration Duration) ?Instant {
	$if windows {
		return Instant{ windows_time: instant.windows_time.checked_add(duration)? }
	} $else {
		// Unsigned subtraction measures the whole signed range without signed overflow.
		available := u64(9_223_372_036_854_775_807) - u64(instant.unix_seconds)
		if duration.secs > available {
			return none
		}
		mut secs := i64(u64(instant.unix_seconds) + duration.secs)
		mut nanos := instant.unix_nanos + duration.nanos
		if nanos >= 1_000_000_000 {
			if secs == 9_223_372_036_854_775_807 {
				return none
			}
			secs++
			nanos -= 1_000_000_000
		}
		return Instant{ unix_seconds: secs, unix_nanos: nanos }
	}
}

// STUB: std::time::Instant::checked_sub, including the platform's representable range.
pub fn (instant Instant) checked_sub(duration Duration) ?Instant {
	$if windows {
		return Instant{ windows_time: instant.windows_time.checked_sub(duration)? }
	} $else {
		available := u64(instant.unix_seconds) - u64(i64(-9_223_372_036_854_775_807 - 1))
		if duration.secs > available {
			return none
		}
		mut secs := i64(u64(instant.unix_seconds) - duration.secs)
		mut nanos := i64(instant.unix_nanos) - i64(duration.nanos)
		if nanos < 0 {
			if secs == i64(-9_223_372_036_854_775_807 - 1) {
				return none
			}
			secs--
			nanos += 1_000_000_000
		}
		return Instant{ unix_seconds: secs, unix_nanos: u32(nanos) }
	}
}

// STUB: std::time::Instant + Duration. V cannot overload mixed-type +, so use the named operation.
pub fn (instant Instant) add(duration Duration) Instant {
	return instant.checked_add(duration) or { panic('overflow when adding duration to instant') }
}

// STUB: std::time::Instant - Duration. V cannot overload mixed-type -, so use the named operation.
pub fn (instant Instant) sub(duration Duration) Instant {
	return instant.checked_sub(duration) or { panic('overflow when subtracting duration from instant') }
}

// STUB: std::time::Instant::checked_duration_since, preserving a full-width unsigned difference.
// Windows allows a reversed difference of at most one QPC tick, as Rust does for measurement error.
pub fn (instant Instant) checked_duration_since(earlier Instant) ?Duration {
	$if windows {
		if difference := instant.windows_time.checked_sub(earlier.windows_time) {
			return difference
		}
		difference := earlier.windows_time.checked_sub(instant.windows_time) or { return none }
		reading := C.codex_frame_monotonic_read()
		if reading.ok != 0 && difference <= Duration.from_nanos(1_000_000_000 / reading.windows_frequency) {
			return duration_zero
		}
		return none
	} $else {
		if instant < earlier {
			return none
		}
		mut secs := u64(instant.unix_seconds) - u64(earlier.unix_seconds)
		mut nanos := i64(instant.unix_nanos) - i64(earlier.unix_nanos)
		if nanos < 0 {
			secs--
			nanos += 1_000_000_000
		}
		return Duration{ secs: secs, nanos: u32(nanos) }
	}
}

// STUB: std::time::Instant::duration_since currently saturates when earlier is in the future.
pub fn (instant Instant) duration_since(earlier Instant) Duration {
	return instant.checked_duration_since(earlier) or { duration_zero }
}

// STUB: std::time::Instant::saturating_duration_since.
pub fn (instant Instant) saturating_duration_since(earlier Instant) Duration {
	return instant.duration_since(earlier)
}

// STUB: std::time::Instant::elapsed, measured against the same native monotonic clock.
pub fn (instant Instant) elapsed() Duration {
	return Instant.now().duration_since(instant)
}
