module time

// STUB: tokio::time::Instant. The chord matcher only needs a monotonic reading plus a saturating
// difference, so this stub stores nanoseconds since an unspecified origin instead of wrapping the
// Tokio clock. `Instant::now` is not ported yet: `crate::keymap` only ever receives an instant
// from its caller.
pub struct Instant {
pub:
	nanos i64
}

// STUB: construction helper for tokio::time::Instant readings supplied by callers and tests.
pub fn Instant.from_nanos(nanos i64) Instant {
	return Instant{
		nanos: nanos
	}
}

// STUB: tokio::time::Instant::saturating_duration_since. Returns nanoseconds, clamped at zero when
// `earlier` is in the future.
pub fn (instant Instant) saturating_duration_since(earlier Instant) i64 {
	if instant.nanos <= earlier.nanos {
		return 0
	}
	return instant.nanos - earlier.nanos
}
