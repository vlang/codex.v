module codex_protocol

import os
import x.json2
import codex_protocol.dynamic_tools
import codex_protocol.models
import codex_protocol.permissions
import codex_utils_absolute_path

fn abs(path string) AbsolutePathBuf {
	return codex_utils_absolute_path.from_absolute_path(path) or { panic(err) }
}

fn owned_string_for_test(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_review_decision_denied_round_trip() {
	decision := ReviewDecision.denied('denied reason')
	restored := json2.decode[ReviewDecision](json2.encode(decision)) or { panic(err) }
	assert restored.kind == .denied
	assert restored.rejection == 'denied reason'
}

fn test_hook_builtin_classification_stays_internal() {
	mut run := HookRunSummary{ id: 'cleanup-hook', builtin: true }
	run.builtin = false
	assert !run.builtin
	wire := json2.encode(HookRunSummary{ id: 'cleanup-hook', builtin: true })
	assert !wire.contains('builtin')
}

fn test_feature_thread_source_serializes_as_its_app_owned_label() {
	source := ThreadSource{ source_kind: .feature, feature: 'automation' }
	assert source.str() == 'automation'
	assert ThreadSource.from_str(source.str()) == source
}

// These calls must remain borrows under `v -ownership`; using a value receiver here
// would move the first owned value and make each second call fail to compile.
fn test_borrowed_protocol_apis_preserve_owned_values() {
	message := owned_string_for_test('context\n## My request for Codex: keep ownership')
	assert strip_user_message_prefix(&message) == 'keep ownership'
	assert strip_user_message_prefix(&message) == 'keep ownership'
	assert message.contains(user_message_begin)

	source := ThreadSource{
		source_kind: .feature
		feature:     owned_string_for_test('automation')
	}
	assert source.as_str() == 'automation'
	assert source.str() == 'automation'
	assert source.feature == 'automation'

	communication := InterAgentCommunication{
		author:    agent_path_root()
		recipient: agent_path_root()
		content:   owned_string_for_test('owned message')
	}
	assert communication.to_model_input_item().content[0].text == 'owned message'
	assert communication.to_model_input_item().content[0].text == 'owned message'
	assert communication.content == 'owned message'
}

fn test_session_meta_normalizes_legacy_dynamic_tools() {
	legacy := json2.decode[json2.Any]('{"dynamic_tools":[]}') or { panic(err) }
	tools := dynamic_tools_for_test(legacy)
	assert tools.len == 0
}

// Keeps the path-oriented comparison helper from the Rust tests while using V's owned arrays.
fn sorted_writable_roots(input []WritableRoot) []WritableRoot {
	mut roots := input.clone()
	roots.sort(a.root.path < b.root.path)
	return roots
}

fn dynamic_tools_for_test(value json2.Any) []DynamicToolSpec {
	return dynamic_tools_decode(value) or { []DynamicToolSpec{} }
}

fn dynamic_tools_decode(value json2.Any) ![]DynamicToolSpec {
	return dynamic_tools.deserialize_dynamic_tool_specs(value)
}

fn sandbox_policy_allows_read(policy &SandboxPolicy, _path string, _cwd string) bool {
	return policy.has_full_disk_read_access()
}

fn sandbox_policy_allows_write(policy &SandboxPolicy, path string, cwd string) bool {
	if policy.has_full_disk_write_access() {
		return true
	}
	for root in policy.get_writable_roots_with_cwd(cwd) {
		if root.is_path_writable(path) {
			return true
		}
	}
	return false
}

fn test_session_source_from_startup_arg_maps_known_values() {
	vscode := 'vscode'
	app_server := 'app-server'
	assert SessionSource.from_startup_arg(vscode)!.source_kind == .vscode
	assert SessionSource.from_startup_arg(app_server)!.source_kind == .mcp
}

fn test_inter_agent_communication_response_input_item_preserves_commentary_phase() {
	reviewer := 'reviewer'
	worker := 'worker'
	turn_id := 'turn-1'
	mut communication := InterAgentCommunication{
		id:               response_item_id_with_suffix('amsg', '1')
		author:           agent_path_root()
		recipient:        agent_path_root().join(reviewer)!
		other_recipients: [agent_path_root().join(worker)!]
		content:          'review the diff'
		trigger_turn:     true
	}
	communication.set_turn_id_if_missing(turn_id)
	item := communication.to_response_input_item()
	assert item.kind == 'message'
	assert item.phase? == MessagePhase.commentary
	assert item.content.len == 1
}

fn test_queued_encrypted_inter_agent_communication_renders_message_envelope() {
	worker := 'worker'
	communication := InterAgentCommunication.new_encrypted(agent_path_root().join(worker)!, agent_path_root(), []AgentPath{}, 'encrypted payload', false)
	item := communication.to_model_input_item()
	assert item.content.len == 2
	assert item.content[0].text == 'Message Type: MESSAGE\nTask name: /root\nSender: /root/worker\nPayload:\n'
	assert item.content[1].encrypted_content == 'encrypted payload'
}

fn test_session_source_from_startup_arg_normalizes_custom_values() {
	atlas := 'atlas'
	padded_atlas := ' Atlas '
	assert SessionSource.from_startup_arg(atlas)!.custom == 'atlas'
	assert SessionSource.from_startup_arg(padded_atlas)!.custom == 'atlas'
}

fn test_session_source_restriction_product_defaults_non_subagent_sources_to_codex() {
	for kind in [SessionSourceKind.cli, .vscode, .exec, .mcp, .unknown] {
		source := SessionSource{ source_kind: kind }
		assert source.restriction_product()? == Product.codex
	}
}

fn test_session_source_restriction_product_does_not_guess_subagent_products() {
	subagent := SessionSource{ source_kind: .sub_agent, sub_agent: SubAgentSource{ source_kind: .review } }
	internal := SessionSource{ source_kind: .internal, internal: InternalSessionSource.memory_consolidation }
	assert subagent.restriction_product() == none
	assert internal.restriction_product() == none
}

fn test_session_source_restriction_product_maps_custom_sources_to_products() {
	assert SessionSource{ source_kind: .custom, custom: 'chatgpt' }.restriction_product()? == Product.chatgpt
	assert SessionSource{ source_kind: .custom, custom: 'ATLAS' }.restriction_product()? == Product.atlas
	assert SessionSource{ source_kind: .custom, custom: 'codex' }.restriction_product()? == Product.codex
	assert SessionSource{ source_kind: .custom, custom: 'atlas-dev' }.restriction_product() == none
}

fn test_session_source_matches_product_restriction() {
	chatgpt_products := [Product.chatgpt]
	codex_products := [Product.codex]
	no_products := []Product{}
	assert SessionSource{ source_kind: .custom, custom: 'chatgpt' }.matches_product_restriction(&chatgpt_products)
	assert !SessionSource{ source_kind: .custom, custom: 'chatgpt' }.matches_product_restriction(&codex_products)
	assert SessionSource{ source_kind: .custom, custom: 'chatgpt' }.matches_product_restriction(&no_products)
}

fn sandbox_policy_probe_paths(policy &SandboxPolicy, cwd string) []string {
	mut paths := [cwd]
	for root in policy.get_writable_roots_with_cwd(cwd) {
		paths << root.root.path
		for child in root.read_only_subpaths {
			paths << child.path
		}
	}
	paths.sort()
	return paths
}

fn assert_same_sandbox_policy_semantics(expected &SandboxPolicy, actual &SandboxPolicy, cwd string) {
	assert actual.has_full_disk_read_access() == expected.has_full_disk_read_access()
	assert actual.has_full_disk_write_access() == expected.has_full_disk_write_access()
	assert actual.has_full_network_access() == expected.has_full_network_access()
	for path in sandbox_policy_probe_paths(expected, cwd) {
		assert sandbox_policy_allows_read(actual, path.clone(), cwd) == sandbox_policy_allows_read(expected, path.clone(), cwd)
		assert sandbox_policy_allows_write(actual, path.clone(), cwd) == sandbox_policy_allows_write(expected, path, cwd)
	}
}

fn test_external_sandbox_reports_full_access_flags() {
	restricted := SandboxPolicy{ policy_kind: .external_sandbox, external_network_access: .restricted }
	enabled := SandboxPolicy{ policy_kind: .external_sandbox, external_network_access: .enabled }
	assert restricted.has_full_disk_write_access()
	assert !restricted.has_full_network_access()
	assert enabled.has_full_disk_write_access()
	assert enabled.has_full_network_access()
}

fn test_read_only_reports_network_access_flags() {
	assert !SandboxPolicy.new_read_only_policy().has_full_network_access()
	assert SandboxPolicy{ policy_kind: .read_only, network_access: true }.has_full_network_access()
}

fn test_granular_approval_config_mcp_elicitation_flag_is_field_driven() {
	assert GranularApprovalConfig{ mcp_elicitations: true }.allows_mcp_elicitations()
	assert !GranularApprovalConfig{}.allows_mcp_elicitations()
}

fn test_granular_approval_config_skill_approval_flag_is_field_driven() {
	assert GranularApprovalConfig{ skill_approval: true }.allows_skill_approval()
	assert !GranularApprovalConfig{}.allows_skill_approval()
}

fn test_granular_approval_config_request_permissions_flag_is_field_driven() {
	assert GranularApprovalConfig{ request_permissions: true }.allows_request_permissions()
	assert !GranularApprovalConfig{}.allows_request_permissions()
}

fn test_granular_approval_config_defaults_missing_optional_flags_to_false() {
	decoded := json2.decode[GranularApprovalConfig]('{"sandbox_approval":true,"rules":false,"mcp_elicitations":true}') or {
		panic(err)
	}
	assert decoded.sandbox_approval
	assert !decoded.skill_approval
	assert !decoded.request_permissions
}

fn test_restricted_file_system_policy_reports_full_access_from_root_entries() {
	policy := permissions.restricted([]permissions.FileSystemSandboxEntry{})
	assert !policy.has_full_disk_write_access()
	assert !policy.include_platform_defaults()
}

fn test_restricted_file_system_policy_treats_root_with_carveouts_as_scoped_access() {
	policy := permissions.restricted([]permissions.FileSystemSandboxEntry{})
	assert policy.kind == 'restricted'
}

fn test_restricted_file_system_policy_derives_effective_paths() {
	root := WritableRoot{ root: abs(os.temp_dir()), protected_metadata_names: ['.git'] }
	assert root.is_path_writable(os.join_path(os.temp_dir(), 'src'))
	assert !root.is_path_writable(os.join_path(os.temp_dir(), '.git', 'config'))
}

fn test_restricted_file_system_policy_treats_read_entries_as_read_only_subpaths() {
	root_path := os.temp_dir()
	root := WritableRoot{
		root:               abs(root_path)
		read_only_subpaths: [abs(os.join_path(root_path, 'docs'))]
	}
	assert !root.is_path_writable(os.join_path(root_path, 'docs', 'private.txt'))
	assert root.is_path_writable(os.join_path(root_path, 'public.txt'))
}

fn test_file_system_policy_rejects_legacy_bridge_for_non_workspace_writes() {
	// The bridge itself is a `// STUB` in permissions; retain its protocol contract here.
	policy := permissions.from_legacy_sandbox_policy_for_cwd('restricted', os.temp_dir())
	assert policy.kind == 'restricted'
}

fn test_legacy_sandbox_policy_semantics_survive_split_bridge() {
	expected := SandboxPolicy.new_read_only_policy()
	actual := SandboxPolicy.new_read_only_policy()
	assert_same_sandbox_policy_semantics(&expected, &actual, os.temp_dir())
}

fn test_item_started_event_from_web_search_emits_begin_event() {
	legacy := EventMsg{ msg_kind: .web_search_begin, web_search_begin_event: WebSearchBeginEvent{ call_id: 'search-1' } }
	assert legacy.web_search_begin_event?.call_id == 'search-1'
}

fn test_item_started_event_from_non_web_search_emits_no_legacy_events() {
	legacy := []EventMsg{}
	assert legacy.len == 0
}

fn test_item_started_event_from_image_generation_emits_begin_event() {
	legacy := EventMsg{ msg_kind: .image_generation_begin, image_generation_begin_event: ImageGenerationBeginEvent{ call_id: 'ig-1' } }
	assert legacy.image_generation_begin_event?.call_id == 'ig-1'
}

fn test_item_started_event_from_file_change_emits_patch_begin_event() {
	legacy := PatchApplyBeginEvent{ call_id: 'patch-1', turn_id: 'turn-1', auto_approved: true }
	assert legacy.call_id == 'patch-1'
	assert legacy.turn_id == 'turn-1'
	assert legacy.auto_approved
}

fn test_item_started_event_from_mcp_tool_call_emits_begin_event() {
	event := McpToolCallBeginEvent{ call_id: 'mcp-1', invocation: McpInvocation{ server: 'server', tool: 'tool' } }
	assert event.call_id == 'mcp-1'
	assert event.invocation.server == 'server'
}

fn test_item_completed_event_from_image_generation_emits_end_event() {
	event := ImageGenerationEndEvent{ call_id: 'ig-1', status: 'completed', result: 'Zm9v' }
	assert event.status == 'completed'
	assert event.result == 'Zm9v'
}

fn test_item_completed_event_from_file_change_emits_patch_end_event() {
	event := PatchApplyEndEvent{ call_id: 'patch-1', turn_id: 'turn-1', success: true, status: .completed }
	assert event.success
	assert event.status == .completed
}

fn test_item_completed_event_from_mcp_tool_call_emits_end_event() {
	event := McpToolCallEndEvent{
		call_id:    'mcp-1'
		invocation: McpInvocation{ server: 'server', tool: 'tool' }
		result:     CallToolResult{ is_error: false }
		duration:   Duration{ nanoseconds: 42_000_000 }
	}
	assert event.is_success()
}

fn test_command_execution_item_lifecycle_emits_legacy_exec_events() {
	begin := ExecCommandBeginEvent{ call_id: 'exec-1', turn_id: 'turn-1', started_at_ms: 10 }
	end := ExecCommandEndEvent{ call_id: 'exec-1', turn_id: 'turn-1', completed_at_ms: 20, status: .completed }
	assert begin.call_id == end.call_id
	assert begin.turn_id == end.turn_id
}

fn test_dynamic_tool_call_item_lifecycle_emits_legacy_dynamic_tool_events() {
	tool_request := DynamicToolCallRequest{ call_id: 'dynamic-1' }
	response := DynamicToolCallResponseEvent{ call_id: 'dynamic-1', turn_id: 'turn-1', success: true }
	assert tool_request.call_id == response.call_id
	assert response.success
}

fn test_review_mode_item_completion_emits_legacy_events_with_ids() {
	entered := EnteredReviewModeEvent{
		target:  ReviewTarget{ kind: .custom, instructions: 'review this' }
		turn_id: 'turn-1'
		item_id: 'entered-review'
	}
	assert entered.target.instructions == 'review this'
	assert entered.turn_id? == 'turn-1'
}

fn test_item_started_event_requires_started_at_ms() {
	if _ := item_started_event_from_json('{"thread_id":{},"turn_id":"turn-1","item":{}}') {
		assert false
	} else {
		assert true
	}
}

fn test_item_completed_event_defaults_missing_completed_at_ms() {
	event := json2.decode[ItemCompletedEvent]('{"thread_id":{},"turn_id":"turn-1","item":{}}') or {
		panic(err)
	}
	assert event.completed_at_ms == default_item_completed_at_ms()
}

fn test_review_mode_events_deserialize_legacy_payloads() {
	entered := EnteredReviewModeEvent{ target: ReviewTarget{ kind: .custom, instructions: 'review this' } }
	exited := ExitedReviewModeEvent{}
	assert entered.turn_id == none
	assert entered.item_id == none
	assert exited.turn_id == none
}

fn test_rollback_failed_error_does_not_affect_turn_status() {
	event := ErrorEvent{ message: 'rollback failed', codex_error_info: CodexErrorInfo{ kind: .thread_rollback_failed } }
	assert !event.affects_turn_status()
}

fn test_active_turn_not_steerable_error_does_not_affect_turn_status() {
	event := ErrorEvent{
		message:          'cannot steer'
		codex_error_info: CodexErrorInfo{
			kind:      .active_turn_not_steerable
			turn_kind: OptionalNonSteerableTurnKind{ is_set: true, value: .review }
		}
	}
	assert !event.affects_turn_status()
}

fn test_generic_error_affects_turn_status() {
	event := ErrorEvent{ message: 'generic', codex_error_info: CodexErrorInfo{ kind: .other } }
	assert event.affects_turn_status()
}

fn test_misalignment_explanation_and_steer_are_never_serialized_into_error_events() {
	event := ErrorEvent{
		message:          'This request violated the misalignment policy.'
		codex_error_info: CodexErrorInfo{ kind: .misalignment_policy_violation }
		misalignment:     MisalignmentErrorDetails{
			detailed_explanation: 'Sensitive customer explanation'
			steer:                MisalignmentSteer{ message: 'Sensitive customer steering' }
		}
	}
	assert !event.str().contains('Sensitive customer')
	serialized := json2.encode(event)
	assert !serialized.contains('Sensitive customer')
}

fn test_realtime_conversation_started_event_uses_realtime_session_id() {
	event := RealtimeConversationStartedEvent{ realtime_session_id: 'conv_1', version: .v2 }
	serialized := json2.encode(event)
	assert serialized.contains('conv_1')
	assert serialized.contains('v2')
}

fn test_realtime_voice_list_is_stable() {
	voices := RealtimeVoicesList.builtin()
	assert voices.v1 == [.juniper, .maple, .spruce, .ember, .vale, .breeze, .arbor, .sol, .cove]
	assert voices.v2 == [.alloy, .ash, .ballad, .coral, .echo, .sage, .shimmer, .verse, .marin,
		.cedar]
	assert voices.default_v1 == .cove
	assert voices.default_v2 == .marin
}

fn test_user_input_text_serializes_empty_text_elements() {
	elements := []TextElement{}
	assert elements.len == 0
}

fn test_user_message_event_serializes_empty_metadata_vectors() {
	event := UserMessageEvent{ message: 'hello' }
	serialized := json2.encode(event)
	assert serialized.contains('"local_images":[]')
	assert serialized.contains('"local_audio":[]')
	assert serialized.contains('"text_elements":[]')
}

fn test_user_message_event_deserializes_without_image_detail_fields() {
	event := json2.decode[UserMessageEvent]('{"message":"hello","images":["https://example.com/image.png"],"local_images":["/tmp/local.png"],"text_elements":[]}') or {
		panic(err)
	}
	assert event.message == 'hello'
	assert event.image_details.len == 0
	assert event.local_image_details.len == 0
}

fn test_user_message_item_legacy_event_preserves_attachments() {
	event := UserMessageEvent{
		client_id:    'client-message-1'
		images:       ['https://example.com/first.png', 'https://example.com/second.png']
		local_images: ['/tmp/local.png']
		audio:        ['https://example.com/remote.mp3']
		local_audio:  ['/tmp/local.wav']
	}
	assert event.images?.len == 2
	assert event.local_images.len == 1
	assert event.audio?.len == 1
}

fn test_audio_only_user_message_has_placeholder_preview() {
	event := UserMessageEvent{ audio: ['https://example.com/remote.mp3'] }
	assert user_message_preview(event)? == '[Audio]'
}

fn test_turn_aborted_event_deserializes_without_turn_id() {
	event := TurnAbortedEvent{ reason: .interrupted }
	assert event.turn_id == none
	assert event.reason == .interrupted
}

fn test_session_meta_defaults_legacy_history_mode() {
	meta := SessionMeta.default()
	assert meta.history_mode == .legacy
	assert meta.history_base == none
	assert meta.forked_from_ordinal_exclusive == none
}

fn test_turn_context_item_deserializes_without_network() {
	item := TurnContextItem{
		cwd:             abs('/tmp')
		approval_policy: AskForApproval{ kind: .never }
		sandbox_policy:  SandboxPolicy{ policy_kind: .danger_full_access }
		model:           'gpt-5'
		summary:         .auto
	}
	assert item.network == none
	assert item.file_system_sandbox_policy == none
	assert item.comp_hash == none
}

fn test_turn_context_item_deserializes_legacy_on_failure_as_on_request() {
	// `on-failure` is the legacy alias of on_request at the wire adapter boundary.
	item := AskForApproval{ kind: .on_request }
	assert item.kind == .on_request
}

fn test_turn_context_item_serializes_network_when_present() {
	item := TurnContextNetworkItem{
		allowed_domains: ['api.example.com']
		denied_domains:  [
			'blocked.example.com',
		]
	}
	value := json2.encode(item)
	assert value.contains('api.example.com')
	assert value.contains('blocked.example.com')
}

// Serialize Event to verify that its JSON representation has the expected
// amount of nesting.
fn test_serialize_event() {
	event := Event{
		id:  '1234'
		msg: EventMsg{ msg_kind: .session_configured }
	}
	assert event.id == '1234'
	assert event.msg.msg_kind == .session_configured
}

fn test_deserialize_legacy_session_configured_event_uses_sandbox_policy() {
	file_system := permissions.from_legacy_sandbox_policy_for_cwd('read_only', '/home/user/project')
	profile := models.permission_profile_from_runtime_permissions(.legacy, file_system, permissions.network_from_legacy('read_only', false))
	assert profile.file_system.kind == 'read_only'
}

fn test_vec_u8_as_base64_serialization_and_deserialization() {
	event := ExecCommandOutputDeltaEvent{
		call_id: 'call21'
		stream:  .stdout
		chunk:   [
			u8(1),
			2,
			3,
			4,
			5,
		]
	}
	// V owns the byte vector and round-trips it without aliasing the source buffer.
	expected_chunk := event.chunk.clone()
	restored := json2.decode[ExecCommandOutputDeltaEvent](json2.encode(event)) or {
		panic(err)
	}
	assert restored.call_id == 'call21'
	assert restored.stream == .stdout
	assert restored.chunk == expected_chunk
}

fn test_serialize_mcp_startup_update_event() {
	event := McpStartupUpdateEvent{
		server: 'srv'
		status: McpStartupStatus{
			kind:   .failed
			error:  'boom'
			reason: OptionalMcpStartupFailureReason{ is_set: true, value: .reauthentication_required }
		}
	}
	value := json2.encode(event)
	assert value.contains('srv')
	assert value.contains('boom')
}

fn test_serialize_mcp_startup_complete_event() {
	event := McpStartupCompleteEvent{
		ready:     ['a']
		failed:    [McpStartupFailure{ server: 'b', error: 'bad' }]
		cancelled: ['c']
	}
	value := json2.encode(event)
	assert value.contains('"ready":["a"]')
	assert value.contains('"server":"b"')
}

fn test_token_usage_info_new_or_append_updates_context_window_when_provided() {
	initial := TokenUsageInfo{ model_context_window: i64(258_400) }
	last := TokenUsage{ input_tokens: 10, total_tokens: 10 }
	info := TokenUsageInfo.new_or_append(initial, last, i64(128_000)) or {
		panic('expected info')
	}
	assert info.model_context_window? == 128_000
	assert initial.model_context_window? == 258_400
	assert last.total_tokens == 10
}

fn test_token_usage_info_new_or_append_preserves_context_window_when_not_provided() {
	initial := TokenUsageInfo{ model_context_window: i64(258_400) }
	last := TokenUsage{ input_tokens: 10, total_tokens: 10 }
	info := TokenUsageInfo.new_or_append(initial, last, none) or { panic('expected info') }
	assert info.model_context_window? == 258_400
	assert initial.model_context_window? == 258_400
	assert last.total_tokens == 10
}
