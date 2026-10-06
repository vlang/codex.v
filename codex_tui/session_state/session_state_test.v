module session_state

import codex_app_server_protocol
import codex_protocol
import codex_protocol.config_types
import codex_protocol.models
import codex_protocol.permissions
import codex_utils_absolute_path
import codex_utils_path_uri
import std_path

fn owned_session_text(text string) string {
	$if ownership ? {
		return text.to_owned()
	} $else {
		return text.clone()
	}
}

fn session_test_path(text string) codex_utils_absolute_path.AbsolutePathBuf {
	return codex_utils_absolute_path.AbsolutePathBuf{ path: owned_session_text(text) }
}

fn session_state_fixture() ThreadSessionState {
	file_path := permissions.FileSystemPath{
		kind:    owned_session_text('path')
		path:    owned_session_text('/workspace/private')
		subpath: owned_session_text('nested')
	}
	file_entry := permissions.FileSystemSandboxEntry{
		path:                  file_path
		access:                .write
		missing_path_behavior: owned_session_text('skip')
	}
	entries := [file_entry]
	file_system := permissions.FileSystemSandboxPolicy{
		kind:              owned_session_text('restricted')
		entries:           entries
		platform_defaults: true
	}
	network := permissions.NetworkSandboxPolicy{ kind: owned_session_text('restricted') }
	profile := models.PermissionProfile{
		enforcement: .legacy
		file_system: file_system
		network:     network
	}
	active := codex_protocol.ActivePermissionProfile{
		id:      owned_session_text('named-workspace')
		extends: owned_session_text(':workspace')
	}
	settings := config_types.Settings{
		model:                  owned_session_text('collaboration-model')
		reasoning_effort:       .high
		developer_instructions: owned_session_text('collaborate carefully')
	}
	mode := config_types.CollaborationMode{ mode: .plan, settings: settings }
	proxy := SessionNetworkProxyRuntime{
		http_addr:  owned_session_text('http://127.0.0.1:3128')
		socks_addr: owned_session_text('socks5://127.0.0.1:1080')
	}
	rollout := std_path.PathBuf.from(owned_session_text('/workspace/rollouts/session.jsonl'))
	cwd := session_test_path('/workspace')
	root := session_test_path('/workspace')
	roots := [root]
	uri := codex_utils_path_uri.PathUri{ path: owned_session_text('file:///workspace/AGENTS.md') }
	paths := [uri]
	id := codex_protocol.ThreadId{ value: owned_session_text('0195a572-44fe-7000-8000-000000000001') }
	parent := codex_protocol.ThreadId{ value: owned_session_text('0195a572-44fe-7000-8000-000000000002') }
	policy := codex_app_server_protocol.ApprovalPolicy{
		kind:     .granular
		granular: codex_protocol.GranularApprovalConfig{
			sandbox_approval:    true
			rules:               true
			skill_approval:      false
			request_permissions: true
			mcp_elicitations:    false
		}
	}
	return ThreadSessionState{
		thread_id:                 id
		forked_from_id:            parent
		fork_parent_title:         owned_session_text('Parent thread')
		thread_name:               owned_session_text('Session name')
		model:                     owned_session_text('session-model')
		model_provider_id:         owned_session_text('provider')
		service_tier:              owned_session_text('fast')
		approval_policy:           policy
		approvals_reviewer:        .auto_review
		permission_profile:        profile
		active_permission_profile: active
		cwd:                       cwd
		runtime_workspace_roots:   roots
		instruction_source_paths:  paths
		reasoning_effort:          .medium
		collaboration_mode:        mode
		personality:               .friendly
		message_history:           MessageHistoryMetadata{ log_id: 41, entry_count: 17 }
		network_proxy:             proxy
		rollout_path:              rollout
	}
}

fn workspace_root_texts(roots &[]codex_utils_absolute_path.AbsolutePathBuf) []string {
	mut values := []string{cap: roots.len}
	for index in 0 .. roots.len {
		values << (*roots)[index].path.clone()
	}
	return values
}

fn test_retargeting_replaces_implicit_root_and_preserves_other_session_fields() {
	mut state := session_state_fixture()
	mut expected := state.clone()
	expected.cwd = session_test_path('/new-workspace')
	root := session_test_path('/new-workspace')
	expected.runtime_workspace_roots = [root]
	state.set_cwd_retargeting_implicit_runtime_workspace_root(session_test_path('/new-workspace'))
	assert state.equals(&expected)
	assert expected.equals(&state)
	assert state.cwd.path.str != state.runtime_workspace_roots[0].path.str
}

fn test_retargeting_keeps_explicit_roots_when_previous_cwd_is_absent() {
	mut state := session_state_fixture()
	first := session_test_path('/explicit')
	second := session_test_path('/explicit')
	state.runtime_workspace_roots = [first, second]
	mut expected := state.clone()
	expected.cwd = session_test_path('/new-workspace')
	state.set_cwd_retargeting_implicit_runtime_workspace_root(session_test_path('/new-workspace'))
	assert state.equals(&expected)
	assert workspace_root_texts(&state.runtime_workspace_roots) == ['/explicit', '/explicit']
}

fn test_retargeting_empty_roots_remain_empty() {
	mut state := session_state_fixture()
	state.runtime_workspace_roots = []codex_utils_absolute_path.AbsolutePathBuf{}
	mut expected := state.clone()
	expected.cwd = session_test_path('/new-workspace')
	state.set_cwd_retargeting_implicit_runtime_workspace_root(session_test_path('/new-workspace'))
	assert state.equals(&expected)
}

fn test_retargeting_puts_new_root_first_and_deduplicates_in_original_order() {
	mut state := session_state_fixture()
	first := session_test_path('/first')
	old_first := session_test_path('/workspace')
	new_first := session_test_path('/new-workspace')
	last := session_test_path('/last')
	first_again := session_test_path('/first')
	old_again := session_test_path('/workspace')
	new_again := session_test_path('/new-workspace')
	state.runtime_workspace_roots = [first, old_first, new_first, last, first_again, old_again,
		new_again]
	state.set_cwd_retargeting_implicit_runtime_workspace_root(session_test_path('/new-workspace'))
	assert state.cwd.path == '/new-workspace'
	assert workspace_root_texts(&state.runtime_workspace_roots) == ['/new-workspace', '/first',
		'/last']
	// Retargeting a second time must operate on the previously updated cwd.
	state.set_cwd_retargeting_implicit_runtime_workspace_root(session_test_path('/next-workspace'))
	assert state.cwd.path == '/next-workspace'
	assert workspace_root_texts(&state.runtime_workspace_roots) == ['/next-workspace', '/first',
		'/last']
}

fn test_retargeting_same_cwd_still_deduplicates_roots() {
	mut state := session_state_fixture()
	first := session_test_path('/other')
	old_first := session_test_path('/workspace')
	first_again := session_test_path('/other')
	old_again := session_test_path('/workspace')
	state.runtime_workspace_roots = [first, old_first, first_again, old_again]
	state.set_cwd_retargeting_implicit_runtime_workspace_root(session_test_path('/workspace'))
	assert workspace_root_texts(&state.runtime_workspace_roots) == ['/workspace', '/other']
}

fn test_clone_repeatedly_borrows_heap_state_and_allocates_independent_storage() {
	state := session_state_fixture()
	mut first := state.clone()
	second := state.clone()
	assert first.equals(&state)
	assert second.equals(&state)
	assert state.equals(&first)
	assert state.equals(&second)
	assert first.thread_id.value.str != state.thread_id.value.str
	assert first.model.str != state.model.str
	assert first.model_provider_id.str != state.model_provider_id.str
	assert first.cwd.path.str != state.cwd.path.str
	assert first.runtime_workspace_roots[0].path.str != state.runtime_workspace_roots[0].path.str
	assert first.instruction_source_paths[0].path.str != state.instruction_source_paths[0].path.str
	assert first.permission_profile.file_system.kind.str != state.permission_profile.file_system.kind.str
	assert first.permission_profile.file_system.entries[0].path.path.str != state.permission_profile.file_system.entries[0].path.path.str
	assert first.permission_profile.network.kind.str != state.permission_profile.network.kind.str
	{
		first_ref := &first
		owner_ref := &state
		first_parent := first_ref.forked_from_id or { panic('missing cloned parent') }
		owner_parent := owner_ref.forked_from_id or { panic('missing owner parent') }
		assert first_parent.value.str != owner_parent.value.str
		first_title := first_ref.fork_parent_title or { panic('missing cloned parent title') }
		owner_title := owner_ref.fork_parent_title or { panic('missing owner parent title') }
		assert first_title.str != owner_title.str
		first_name := first_ref.thread_name or { panic('missing cloned name') }
		owner_name := owner_ref.thread_name or { panic('missing owner name') }
		assert first_name.str != owner_name.str
		first_tier := first_ref.service_tier or { panic('missing cloned tier') }
		owner_tier := owner_ref.service_tier or { panic('missing owner tier') }
		assert first_tier.str != owner_tier.str
		first_active := first_ref.active_permission_profile or { panic('missing cloned active profile') }
		owner_active := owner_ref.active_permission_profile or { panic('missing owner active profile') }
		assert first_active.id.str != owner_active.id.str
		first_extends := first_active.extends or { panic('missing cloned profile parent') }
		owner_extends := owner_active.extends or { panic('missing owner profile parent') }
		assert first_extends.str != owner_extends.str
		first_mode := first_ref.collaboration_mode or { panic('missing cloned mode') }
		owner_mode := owner_ref.collaboration_mode or { panic('missing owner mode') }
		assert first_mode.settings.model.str != owner_mode.settings.model.str
		first_instructions := first_mode.settings.developer_instructions or { panic('missing cloned instructions') }
		owner_instructions := owner_mode.settings.developer_instructions or { panic('missing owner instructions') }
		assert first_instructions.str != owner_instructions.str
		first_proxy := first_ref.network_proxy or { panic('missing cloned proxy') }
		owner_proxy := owner_ref.network_proxy or { panic('missing owner proxy') }
		assert first_proxy.http_addr.str != owner_proxy.http_addr.str
		assert first_proxy.socks_addr.str != owner_proxy.socks_addr.str
		first_path := first_ref.rollout_path or { panic('missing cloned rollout path') }
		owner_path := owner_ref.rollout_path or { panic('missing owner rollout path') }
		first_view := first_path.to_str()
		owner_view := owner_path.to_str()
		assert first_view.present && owner_view.present
		assert first_view.value.str != owner_view.value.str
		assert owner_proxy.http_addr == 'http://127.0.0.1:3128'
	}
	first.model += '-changed'
	first.runtime_workspace_roots[0] = session_test_path('/changed-root')
	first.instruction_source_paths[0] = codex_utils_path_uri.PathUri{ path: owned_session_text('file:///changed/AGENTS.md') }
	first.rollout_path = std_path.PathBuf.from(owned_session_text('/changed/rollout.jsonl'))
	assert !first.equals(&state)
	assert state.equals(&second)
	assert state.model == 'session-model'
	assert workspace_root_texts(&state.runtime_workspace_roots) == ['/workspace']
	assert state.instruction_source_paths[0].path == 'file:///workspace/AGENTS.md'
}

fn test_clone_preserves_absent_optional_fields() {
	mut state := session_state_fixture()
	state.forked_from_id = none
	state.fork_parent_title = none
	state.thread_name = none
	state.service_tier = none
	state.active_permission_profile = none
	state.reasoning_effort = none
	state.collaboration_mode = none
	state.personality = none
	state.message_history = none
	state.network_proxy = none
	state.rollout_path = none
	first := state.clone()
	second := state.clone()
	assert first.equals(&state)
	assert second.equals(&state)
	assert state.equals(&first)
}

fn test_state_partial_eq_preserves_path_dependency_semantics() {
	mut state := session_state_fixture()
	state.rollout_path = std_path.PathBuf.from(owned_session_text('/rollouts/session.jsonl'))
	state.instruction_source_paths = [codex_utils_path_uri.PathUri{ path: owned_session_text('file:///C:/Workspace/AGENTS.md') }]
	mut other := state.clone()
	other.rollout_path = std_path.PathBuf.from(owned_session_text('/rollouts/./session.jsonl'))
	other.instruction_source_paths = [codex_utils_path_uri.PathUri{ path: owned_session_text('file:///c:/workspace/%41GENTS.md') }]
	assert state.equals(&other)
	assert other.equals(&state)
	other.instruction_source_paths = [codex_utils_path_uri.PathUri{ path: owned_session_text('file:///c:/workspace/OTHER.md') }]
	assert !state.equals(&other)
}
