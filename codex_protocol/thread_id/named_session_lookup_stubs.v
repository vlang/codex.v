module thread_id

import uuid

// STUB: protocol/src/thread_id.rs::ThreadId::new, UUID generation for source tests.
pub fn new() ThreadId {
	return ThreadId{ value: uuid.Uuid.now_v7().str() }
}
