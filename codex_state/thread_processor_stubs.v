module codex_state

import codex_protocol

// STUB: StateDbHandle is owned by codex-state/state_db.
pub struct StateDbHandle {
pub:
	available bool
}

// STUB: MemoriesDb is the memories-table handle returned by StateDbHandle::memories.
pub struct MemoriesDb {
pub:
	available bool
}

// STUB: StateDbHandle::memories is owned by codex-state/state_db.
pub fn (state_db &StateDbHandle) memories() MemoriesDb {
	return MemoriesDb{ available: state_db.available }
}

// STUB: StateDbHandle::clear_memory_data is the memories-table deletion boundary.
pub fn (state_db &StateDbHandle) clear_memory_data() ! {
	if !state_db.available {
		return error('state db is unavailable')
	}
}

// STUB: MemoriesDb::clear_memory_data is owned by codex-state/runtime/memories.rs.
pub fn (memories &MemoriesDb) clear_memory_data() ! {
	if !memories.available {
		return error('state db is unavailable')
	}
}

// STUB: LogDbLayer is owned by codex-state/log_db.
pub struct LogDbLayer {}

// STUB: ThreadMetadata is owned by codex-state and contains the fields consumed by the legacy
// conversation-summary compatibility response.
pub struct ThreadMetadata {
pub:
	id                 codex_protocol.ThreadId
	rollout_path       string
	first_user_message ?string
	preview            ?string
	created_at         string
	updated_at         string
	model              ?string
	model_provider     string
	reasoning_effort   ?codex_protocol.ReasoningEffortConfig
	cwd                string
	cli_version        string
	source             string
	thread_source      ?codex_protocol.ThreadSource
	agent_nickname     ?string
	agent_role         ?string
	git_sha            ?string
	git_branch         ?string
	git_origin_url     ?string
}

// STUB: OptionalThreadMetadata preserves a successful missing state-db row.
pub struct OptionalThreadMetadata {
pub:
	has_value bool
	value     ThreadMetadata
}

// STUB: StateDbHandle loads persisted metadata for a resumed conversation.
pub fn (state_db &StateDbHandle) get_thread(thread_id codex_protocol.ThreadId) !OptionalThreadMetadata {
	_ = state_db
	_ = thread_id
	return error('loading thread metadata requires translated codex-state')
}
