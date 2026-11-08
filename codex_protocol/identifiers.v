module codex_protocol

import codex_protocol.thread_id

// STUB: AgentPath is owned by agent_path.rs and will receive its full validation rules later.
pub struct AgentPath {
pub:
	value string
}

// STUB: Root agent path constructor.
pub fn agent_path_root() AgentPath {
	return AgentPath{ value: '/root' }
}

// STUB: Validated path joining belongs to agent_path.rs.
pub fn (path &AgentPath) join(segment &string) !AgentPath {
	if segment.len == 0 || segment.contains('/') {
		return error('invalid agent path segment `${*segment}`')
	}
	return AgentPath{ value: '${path.value}/${*segment}' }
}

// STUB: Display formatting belongs to agent_path.rs.
pub fn (path &AgentPath) str() string {
	return path.value
}

// STUB: Response item IDs are validated by response_item_id.rs.
pub struct ResponseItemId {
pub:
	value string
}

// STUB: Response item ID constructor.
pub fn response_item_id_with_suffix(prefix string, suffix string) ResponseItemId {
	return ResponseItemId{ value: '${prefix}_${suffix}' }
}

// STUB: SanitizedGitUrl will redact credentials when sanitized_git_url.rs is translated.
pub struct SanitizedGitUrl {
pub:
	value string
}

// STUB: Session IDs are UUID-backed in session_id.rs.
pub struct SessionId {
pub:
	value string
}

// STUB: Display formatting belongs to session_id.rs.
pub fn (id &SessionId) str() string {
	return id.value
}

// STUB: ThreadId is re-exported from its eventual protocol/src/thread_id.rs owner.
pub type ThreadId = thread_id.ThreadId

// STUB: Display formatting belongs to thread_id.rs.
pub fn (id &ThreadId) str() string {
	return id.value.clone()
}

// STUB: Exact upstream response usage metadata belongs to response_usage.rs.
pub struct ResponseUsageMetadata {
pub:
	json string
}
