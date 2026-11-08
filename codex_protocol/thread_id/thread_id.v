module thread_id

import uuid

// STUB: ThreadId is UUID-backed in protocol/src/thread_id.rs. The translated protocol currently
// retains its canonical string form until that source owner is ported.
pub struct ThreadId {
pub:
	value string
}

// STUB: from_string mirrors ThreadId::from_string in protocol/src/thread_id.rs
// through the canonical UUID parser, then owns its lowercase Display spelling.
pub fn from_string(value &string) !ThreadId {
	parsed := uuid.Uuid.parse_str(value)!
	return ThreadId{
		value: parsed.str()
	}
}

// STUB: owned Display formatting belongs to protocol/src/thread_id.rs. V cannot
// return Rust's borrowed format view, so this string allocates independent storage.
pub fn (id &ThreadId) str() string {
	return id.value.clone()
}
