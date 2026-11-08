// Canonical TUI session state shared across app-server routing, chat display, and status UI.
//
// The app-server API is the boundary for session lifecycle events. Once those responses enter
// TUI, this module holds the small internal state shape used by app orchestration and widgets.
module session_state

import codex_app_server_protocol
import codex_protocol
import codex_protocol.config_types
import codex_protocol.models
import codex_protocol.openai_models
import codex_utils_absolute_path
import codex_utils_path_uri
import std_path

// Crate visibility is public across the V submodules belonging to codex_tui.
// V supplies Debug and structural PartialEq; Clone below owns both strings.
pub struct SessionNetworkProxyRuntime {
pub mut:
	http_addr  string @[required]
	socks_addr string @[required]
}

pub fn (proxy &SessionNetworkProxyRuntime) clone() SessionNetworkProxyRuntime {
	return SessionNetworkProxyRuntime{
		http_addr:  proxy.http_addr.clone()
		socks_addr: proxy.socks_addr.clone()
	}
}

// These scalar fields retain the Rust Copy, Default (both zero), and Eq behavior.
pub struct MessageHistoryMetadata {
pub mut:
	log_id      u64
	entry_count usize
}

pub fn (history &MessageHistoryMetadata) clone() MessageHistoryMetadata {
	return MessageHistoryMetadata{ log_id: history.log_id, entry_count: history.entry_count }
}

pub struct ThreadSessionState {
pub mut:
	thread_id          codex_protocol.ThreadId @[required]
	forked_from_id     ?codex_protocol.ThreadId
	fork_parent_title  ?string
	thread_name        ?string
	model              string @[required]
	model_provider_id  string @[required]
	service_tier       ?string
	approval_policy    codex_app_server_protocol.AskForApproval @[required]
	approvals_reviewer config_types.ApprovalsReviewer           @[required]
	// Permission snapshot used by TUI display surfaces. Legacy app-server
	// responses are converted to a profile at ingestion time using the
	// response cwd so cached sessions do not reinterpret cwd-bound grants.
	// Turn requests must not treat this snapshot as a local permission
	// override unless the user explicitly changed permissions in the TUI.
	permission_profile models.PermissionProfile @[required]
	// Named or implicit built-in profile that produced `permission_profile`,
	// when the server knows it.
	active_permission_profile ?codex_protocol.ActivePermissionProfile
	cwd                       codex_utils_absolute_path.AbsolutePathBuf   @[required]
	runtime_workspace_roots   []codex_utils_absolute_path.AbsolutePathBuf @[required]
	instruction_source_paths  []codex_utils_path_uri.PathUri              @[required]
	reasoning_effort          ?openai_models.ReasoningEffort
	// Rust's owned Box is an owned V aggregate; the optional payload is cloned
	// independently and never exposed as a shared mutable pointer.
	collaboration_mode ?config_types.CollaborationMode
	personality        ?config_types.Personality
	message_history    ?MessageHistoryMetadata
	network_proxy      ?SessionNetworkProxyRuntime
	rollout_path       ?std_path.PathBuf
}

pub fn (mut state ThreadSessionState) set_cwd_retargeting_implicit_runtime_workspace_root(cwd codex_utils_absolute_path.AbsolutePathBuf) {
	previous_cwd := state.cwd
	state.cwd = cwd.clone()
	if !workspace_roots_contain(&state.runtime_workspace_roots, &previous_cwd) {
		return
	}

	previous_roots := state.runtime_workspace_roots
	state.runtime_workspace_roots = []codex_utils_absolute_path.AbsolutePathBuf{}
	state.runtime_workspace_roots << cwd
	for root in previous_roots {
		if !absolute_paths_equal(&root, &previous_cwd)
			&& !workspace_roots_contain(&state.runtime_workspace_roots, &root) {
			state.runtime_workspace_roots << root
		}
	}
}

// The source's contains and equality operations borrow normalized native paths.
fn workspace_roots_contain(roots &[]codex_utils_absolute_path.AbsolutePathBuf, root &codex_utils_absolute_path.AbsolutePathBuf) bool {
	for index in 0 .. roots.len {
		if absolute_paths_equal(&(*roots)[index], root) {
			return true
		}
	}
	return false
}

fn absolute_paths_equal(left &codex_utils_absolute_path.AbsolutePathBuf, right &codex_utils_absolute_path.AbsolutePathBuf) bool {
	left_path := left.as_path()
	right_path := right.as_path()
	return left_path.equals(&right_path)
}

// Rust's derived Clone copies each owned field independently. ThreadId is Copy
// in Rust, but the existing UUID string dependency requires an owned copy in V.
pub fn (state &ThreadSessionState) clone() ThreadSessionState {
	mut roots := []codex_utils_absolute_path.AbsolutePathBuf{cap: state.runtime_workspace_roots.len}
	for index in 0 .. state.runtime_workspace_roots.len {
		roots << (&state.runtime_workspace_roots[index]).clone()
	}
	mut paths := []codex_utils_path_uri.PathUri{cap: state.instruction_source_paths.len}
	for index in 0 .. state.instruction_source_paths.len {
		paths << (&state.instruction_source_paths[index]).clone()
	}
	return ThreadSessionState{
		thread_id:                 codex_protocol.ThreadId{ value: state.thread_id.value.clone() }
		forked_from_id:            if id := state.forked_from_id {
			codex_protocol.ThreadId{ value: id.value.clone() }
		} else {
			none
		}
		fork_parent_title:         if value := state.fork_parent_title {
			value.clone()
		} else {
			none
		}
		thread_name:               if value := state.thread_name { value.clone() } else { none }
		model:                     state.model.clone()
		model_provider_id:         state.model_provider_id.clone()
		service_tier:              if value := state.service_tier { value.clone() } else { none }
		approval_policy:           state.approval_policy
		approvals_reviewer:        state.approvals_reviewer
		permission_profile:        state.permission_profile.clone()
		active_permission_profile: if profile := state.active_permission_profile {
			codex_protocol.ActivePermissionProfile(profile.clone())
		} else {
			none
		}
		cwd:                       state.cwd.clone()
		runtime_workspace_roots:   roots
		instruction_source_paths:  paths
		reasoning_effort:          state.reasoning_effort
		collaboration_mode:        if mode := state.collaboration_mode {
			mode.clone()
		} else {
			none
		}
		personality:               state.personality
		message_history:           state.message_history
		network_proxy:             if proxy := state.network_proxy { proxy.clone() } else { none }
		rollout_path:              if path := state.rollout_path { path.clone() } else { none }
	}
}

// Derived PartialEq retains each dependency's own equality: PathBuf compares
// lexical components and PathUri folds only ordinary Windows identity bytes.
pub fn (state &ThreadSessionState) equals(other &ThreadSessionState) bool {
	if state.thread_id != other.thread_id || state.forked_from_id != other.forked_from_id
		|| state.fork_parent_title != other.fork_parent_title || state.thread_name != other.thread_name
		|| state.model != other.model || state.model_provider_id != other.model_provider_id
		|| state.service_tier != other.service_tier || state.approval_policy != other.approval_policy
		|| state.approvals_reviewer != other.approvals_reviewer
		|| state.permission_profile != other.permission_profile
		|| state.active_permission_profile != other.active_permission_profile
		|| !absolute_paths_equal(&state.cwd, &other.cwd)
		|| state.runtime_workspace_roots.len != other.runtime_workspace_roots.len
		|| state.instruction_source_paths.len != other.instruction_source_paths.len
		|| state.reasoning_effort != other.reasoning_effort
		|| state.collaboration_mode != other.collaboration_mode || state.personality != other.personality
		|| state.message_history != other.message_history || state.network_proxy != other.network_proxy {
		return false
	}
	for index in 0 .. state.runtime_workspace_roots.len {
		if !absolute_paths_equal(&state.runtime_workspace_roots[index], &other.runtime_workspace_roots[index]) {
			return false
		}
	}
	for index in 0 .. state.instruction_source_paths.len {
		if !(&state.instruction_source_paths[index]).equals(&other.instruction_source_paths[index]) {
			return false
		}
	}
	if path := state.rollout_path {
		if other_path := other.rollout_path {
			return path.equals(&other_path)
		}
		return false
	}
	return other.rollout_path == none
}
