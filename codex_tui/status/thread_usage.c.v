module status

#include "@VMODROOT/codex_tui/status/thread_usage_native.h"

fn C.codex_status_thread_usage_store(&u32)
fn C.codex_status_thread_usage_load(&u32) u32

// AtomicBool::store/load with Ordering::Relaxed; the flag owns no allocation.
fn thread_usage_store_reserved(value &u32) {
	C.codex_status_thread_usage_store(value)
}

fn thread_usage_load_reserved(value &u32) bool {
	return C.codex_status_thread_usage_load(value) != 0
}
