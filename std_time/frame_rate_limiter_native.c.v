module std_time

#include "@VMODROOT/std_time/frame_rate_limiter_native.h"

// STUB: native readings underlying std::time::Instant::now. These are full-width clock
// components, never wall-clock timestamps or flattened nanosecond counters.
@[typedef]
struct C.CodexFrameMonotonicReading {
	unix_seconds      i64
	unix_nanos        u32
	windows_ticks     u64
	windows_frequency u64
	ok                u8
}

// STUB: native platform clock boundary for std::time::Instant::now.
fn C.codex_frame_monotonic_read() C.CodexFrameMonotonicReading
