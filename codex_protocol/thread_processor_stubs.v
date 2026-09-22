module codex_protocol

// STUB: ClientMcpExtensions is owned by codex-protocol/mcp.
pub struct ClientMcpExtensions {}

// STUB: clones the client MCP extension map at owned retry/task boundaries.
pub fn clone_client_mcp_extensions(value &ClientMcpExtensions) ClientMcpExtensions {
	_ = value
	return ClientMcpExtensions{}
}

// STUB: ThreadId::from_string is owned by thread_id.rs. V uses a free constructor until associated
// functions on imported types can be replaced together with the complete identifier translation.
pub fn thread_id_from_string(value &string) !ThreadId {
	trimmed := value.trim_space()
	if trimmed.len == 0 {
		return error('thread id must not be empty')
	}
	return ThreadId{ value: trimmed.clone() }
}

// STUB: SanitizedGitUrl::try_from is owned by sanitized_git_url.rs.
pub fn sanitized_git_url_from_string(value string) !SanitizedGitUrl {
	if !value.contains('://') && !value.starts_with('git@') {
		return error('invalid Git remote')
	}
	return SanitizedGitUrl{ value: value }
}

// STUB: V ownership adaptation for Rust's derived `Clone` on SessionSource.
pub fn clone_session_source(source &SessionSource) SessionSource {
	return SessionSource{
		source_kind: source.source_kind
		custom:      source.custom.clone()
		internal:    source.internal
		sub_agent:   if subagent := source.sub_agent {
			SubAgentSource{
				source_kind:      subagent.source_kind
				parent_thread_id: if id := subagent.parent_thread_id {
					ThreadId{ value: id.value.clone() }
				} else {
					none
				}
				depth:            subagent.depth
				agent_path:       if path := subagent.agent_path {
					AgentPath{ value: path.value.clone() }
				} else {
					none
				}
				agent_nickname:   if value := subagent.agent_nickname {
					value.clone()
				} else {
					none
				}
				agent_role:       if value := subagent.agent_role { value.clone() } else { none }
				other:            subagent.other.clone()
			}
		} else {
			none
		}
	}
}

// STUB: V ownership adaptation for Rust's derived `Clone` on Option<SessionSource>.
pub fn clone_optional_session_source(source ?SessionSource) ?SessionSource {
	if value := source {
		return clone_session_source(&value)
	}
	return none
}

// STUB: V ownership adaptation for Rust's derived `Clone` on Option<ActivePermissionProfile>.
pub fn clone_optional_active_permission_profile(profile ?ActivePermissionProfile) ?ActivePermissionProfile {
	if value := profile {
		return ActivePermissionProfile{
			id:      value.id.clone()
			extends: if parent := value.extends { parent.clone() } else { none }
		}
	}
	return none
}
