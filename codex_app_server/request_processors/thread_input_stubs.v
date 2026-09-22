module request_processors

import codex_core
import codex_protocol

// STUB: public direct-input rejection text is owned by request_processors/thread_input.rs.
pub const direct_input_to_multi_agent_v2_subagent_error = 'direct app-server input is not allowed for multi-agent v2 sub-agents'

// STUB: can_accept_direct_input is owned by request_processors/thread_input.rs. The serialized
// session-source projection used by the core stub names ThreadSpawn sub-agents as
// `sub_agent:thread_spawn`; only parent-owned V2 children reject public direct input.
pub fn can_accept_direct_input(multi_agent_version ?codex_protocol.MultiAgentVersion, session_source &codex_protocol.SessionSource) bool {
	if version := multi_agent_version {
		is_parent_owned_child := session_source.source_kind == .sub_agent
			&& (if subagent := session_source.sub_agent {
				subagent.source_kind == .thread_spawn
			} else {
				false
			})
		return version != .v2 || !is_parent_owned_child
	}
	return true
}

// STUB: ensure_direct_input_allowed is owned by request_processors/thread_input.rs.
pub fn ensure_direct_input_allowed(thread_value &codex_core.CodexThread) ! {
	if !can_accept_direct_input(thread_value.multi_agent_version, &thread_value.config_snapshot.session_source) {
		return error(direct_input_to_multi_agent_v2_subagent_error)
	}
}
