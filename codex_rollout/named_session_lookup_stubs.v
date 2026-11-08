module codex_rollout

import os
import std_path

// STUB: rollout/src/lib.rs::SESSIONS_SUBDIR.
pub const sessions_subdir = 'sessions'

// STUB: rollout/src/lib.rs::ARCHIVED_SESSIONS_SUBDIR.
pub const archived_sessions_subdir = 'archived_sessions'

// STUB: rollout/src/compression.rs::existing_rollout_path; native metadata IO is
// synchronous in V. Prefer the plain file, then its .jsonl.zst compressed sibling.
pub fn existing_rollout_path(path &std_path.Path) ?string {
	value := path.to_string_lossy()
	plain := if value.ends_with('.jsonl.zst') {
		value[..value.len - 4].clone()
	} else {
		value.clone()
	}
	if os.is_file(plain.clone()) {
		return plain
	}
	compressed := '${plain}.zst'
	if os.is_file(compressed.clone()) {
		return compressed
	}
	return none
}
