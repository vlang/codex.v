module mpsc

#include "@VMODROOT/tokio/sync/mpsc/frame_requester_native.h"

// STUB: platform-shaped native wake state. V allocates it with its active GC/ownership
// allocator; the C boundary initializes the mutex/condition and never hides a C allocation.
@[typedef]
struct C.CodexFrameWake {}

// STUB: native initialization for Tokio's task wake boundary.
fn C.codex_frame_wake_init(&C.CodexFrameWake)

// STUB: release native synchronization resources after the shared channel's last use.
fn C.codex_frame_wake_destroy(&C.CodexFrameWake)

// STUB: native notification for Tokio's task wake boundary.
fn C.codex_frame_wake_post(&C.CodexFrameWake)

// STUB: native monotonic wait for Tokio's task wake boundary.
fn C.codex_frame_wake_wait(&C.CodexFrameWake, i64)

// STUB: native wait handle for the specialized unbounded Instant channel.
struct FrameWake {
	native &C.CodexFrameWake
}

// STUB: construct the native task wake handle.
fn FrameWake.new() FrameWake {
	native := &C.CodexFrameWake{}
	C.codex_frame_wake_init(native)
	return FrameWake{ native: native }
}

// STUB: Tokio task wake cleanup. Channel leases and in-flight receives protect this call;
// the native backing allocation itself remains owned by V's GC/ownership allocator.
fn (wake &FrameWake) destroy() {
	C.codex_frame_wake_destroy(wake.native)
}

// STUB: native Tokio task notification.
fn (wake &FrameWake) post() {
	C.codex_frame_wake_post(wake.native)
}

// STUB: indefinite Tokio task parking for the paused runtime.
fn (wake &FrameWake) wait() {
	C.codex_frame_wake_wait(wake.native, -1)
}

// STUB: monotonic relative Tokio task parking for a scheduled deadline.
fn (wake &FrameWake) timed_wait(nanos i64) {
	C.codex_frame_wake_wait(wake.native, nanos)
}
