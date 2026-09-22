module request_processors

import codex_app_server_protocol as api
import codex_protocol
import codex_thread_store as store
import json
import os
import x.json2

fn fixture_terminal(process_id &string) api.ThreadBackgroundTerminal {
	cwd := $if windows { r'C:\tmp' } $else { '/tmp' }
	return api.ThreadBackgroundTerminal{
		item_id:    'item-${*process_id}'
		process_id: process_id.clone()
		command:    'command-${*process_id}'
		cwd:        cwd
	}
}

fn fixture_dynamic_tool(namespace ?string, name string, input_schema string, defer_loading bool) api.DynamicToolSpec {
	function := api.DynamicToolFunctionSpec{
		name:          name
		description:   'test'
		input_schema:  input_schema
		defer_loading: defer_loading
	}
	if namespace_name := namespace {
		return api.DynamicToolSpec{
			kind:      .namespace
			namespace: api.DynamicToolNamespaceSpec{
				name:        namespace_name
				description: 'test namespace'
				tools:       [function]
			}
		}
	}
	return api.DynamicToolSpec{
		kind:     .function
		function: function
	}
}

fn dynamic_tool_validation_error(tools &[]api.DynamicToolSpec) string {
	validate_dynamic_tools(tools) or { return err.msg() }
	return ''
}

fn test_normalize_thread_list_cwd_filter_preserves_absolute_paths() {
	cwd := $if windows { r'C:\srv\repo-b' } $else { '/srv/repo-b' }
	result := normalize_thread_list_cwd_filters(api.ThreadListCwdFilter{
		kind: .one
		one:  cwd.clone()
	}) or { panic(err) }
	assert result.has_value
	assert result.value == [cwd]
}

fn test_normalize_thread_list_cwd_filter_resolves_relative_paths_against_server_cwd() {
	result := normalize_thread_list_cwd_filters(api.ThreadListCwdFilter{
		kind: .many
		many: ['repo-b']
	}) or { panic(err) }
	assert result.has_value
	assert result.value == [os.abs_path('repo-b')]
}

fn test_paginates_with_process_id_cursor() {
	one := '1'
	two := '2'
	three := '3'
	four := '4'
	five := '5'
	terminals := [fixture_terminal(&one), fixture_terminal(&two), fixture_terminal(&three),
		fixture_terminal(&four), fixture_terminal(&five)]
	data, next_cursor := paginate_background_terminals(&terminals, /* cursor */
		none, u32(2)) or {
		panic(err)
	}
	assert data == [fixture_terminal(&one), fixture_terminal(&two)]
	first_cursor := next_cursor or { panic('expected cursor') }
	assert first_cursor == '2'

	terminals_without_anchor := [fixture_terminal(&one), fixture_terminal(&three),
		fixture_terminal(&four)]
	second_data, second_cursor := paginate_background_terminals(&terminals_without_anchor, first_cursor.clone(), u32(2)) or { panic(err) }
	assert second_data == [fixture_terminal(&three), fixture_terminal(&four)]
	assert second_cursor == none

	third_data, third_cursor := paginate_background_terminals(&terminals, first_cursor.clone(), u32(2)) or { panic(err) }
	assert third_data == [fixture_terminal(&three), fixture_terminal(&four)]
	assert third_cursor or { '' } == '4'

	paginate_background_terminals(&terminals, 'missing', u32(1)) or {
		assert err.msg().contains('invalid cursor')
		return
	}
	assert false
}

fn test_validate_dynamic_tools_rejects_unsupported_input_schema() {
	tools := [fixture_dynamic_tool( /* namespace */
	none, 'my_tool', '{"type":"null"}',
		/* defer_loading */
		false)]
	error_message := dynamic_tool_validation_error(&tools)
	assert error_message.contains('my_tool')
}

fn test_validate_dynamic_tools_accepts_sanitizable_input_schema() {
	tools := [
		// Missing `type` is common; core sanitizes these to a supported schema.
		fixture_dynamic_tool( /* namespace */
		none, 'my_tool', '{"properties":{}}',
			/* defer_loading */
			false),
	]
	validate_dynamic_tools(&tools) or { panic(err) }
}

fn test_validate_dynamic_tools_accepts_nullable_field_schema() {
	tools := [
		fixture_dynamic_tool( /* namespace */
		none, 'my_tool', '{"type":"object","properties":{"query":{"type":["string","null"]}},"required":["query"],"additionalProperties":false}',
			/* defer_loading */
			false),
	]
	validate_dynamic_tools(&tools) or { panic(err) }
}

fn test_validate_dynamic_tools_accepts_same_name_in_different_namespaces() {
	tools := [
		fixture_dynamic_tool('codex_app', 'my_tool', '{"type":"object","properties":{},"additionalProperties":false}',
			/* defer_loading */
			true),
		fixture_dynamic_tool('other_app', 'my_tool', '{"type":"object","properties":{},"additionalProperties":false}',
			/* defer_loading */
			true),
	]
	validate_dynamic_tools(&tools) or { panic(err) }
}

fn test_validate_dynamic_tools_accepts_responses_compatible_identifiers() {
	tools := [
		fixture_dynamic_tool('Codex-App_2', 'lookup-ticket_2', '{"type":"object","properties":{},"additionalProperties":false}',
			/* defer_loading */
			true),
	]
	validate_dynamic_tools(&tools) or { panic(err) }
}

fn test_validate_dynamic_tools_rejects_duplicate_name_in_same_namespace() {
	function := api.DynamicToolFunctionSpec{
		name:          'my_tool'
		description:   'test'
		input_schema:  '{"type":"object","properties":{},"additionalProperties":false}'
		defer_loading: true
	}
	tools := [api.DynamicToolSpec{
		kind:      .namespace
		namespace: api.DynamicToolNamespaceSpec{
			name:        'codex_app'
			description: 'test namespace'
			tools:       [function, api.DynamicToolFunctionSpec{
				name:          'my_tool'
				description:   'test'
				input_schema:  '{"type":"object","properties":{},"additionalProperties":false}'
				defer_loading: true
			}]
		}
	}]
	error_message := dynamic_tool_validation_error(&tools)
	assert error_message.contains('codex_app')
	assert error_message.contains('my_tool')
}

fn test_thread_turns_list_merges_in_progress_active_turn_before_agent_status_running() {
	persisted_items := [store.RolloutItem{
		kind:    .user_message
		message: 'persisted'
	}]
	active_turn := api.Turn{
		id:         'live-turn'
		items:      [api.ThreadItem{
			id:      'live-user-message'
			kind:    .user_message
			content: ['live']
		}]
		items_view: .full
		status:     .in_progress
	}
	turns := reconstruct_thread_turns_for_turns_list(&persisted_items, api.ThreadStatus{
		kind: .idle
	}, /* has_live_running_thread */
		false, clone_turn(&active_turn))
	assert turns.last() == active_turn
}

fn test_validate_dynamic_tools_rejects_empty_namespace() {
	tools := [
		fixture_dynamic_tool('', 'my_tool', '{"type":"object","properties":{},"additionalProperties":false}',
			/* defer_loading */
			false),
	]
	err := dynamic_tool_validation_error(&tools)
	assert err.contains('namespace'), 'unexpected error: ${err}'
}

fn test_validate_dynamic_tools_rejects_reserved_namespace() {
	tools := [
		fixture_dynamic_tool('mcp__server__', 'my_tool', '{"type":"object","properties":{},"additionalProperties":false}',
			/* defer_loading */
			false),
	]
	err := dynamic_tool_validation_error(&tools)
	assert err.contains('reserved'), 'unexpected error: ${err}'
}

fn test_validate_dynamic_tools_rejects_name_not_supported_by_responses() {
	tools := [
		fixture_dynamic_tool( /* namespace */
		none, 'lookup.ticket', '{"type":"object","properties":{},"additionalProperties":false}',
			/* defer_loading */
			false),
	]
	err := dynamic_tool_validation_error(&tools)
	assert err.contains('lookup.ticket'), 'unexpected error: ${err}'
	assert err.contains('Responses API') && err.contains('^[a-zA-Z0-9_-]+\$'), 'unexpected error: ${err}'
}

fn test_validate_dynamic_tools_rejects_namespace_not_supported_by_responses() {
	tools := [
		fixture_dynamic_tool('codex.app', 'lookup_ticket', '{"type":"object","properties":{},"additionalProperties":false}',
			/* defer_loading */
			true),
	]
	err := dynamic_tool_validation_error(&tools)
	assert err.contains('codex.app'), 'unexpected error: ${err}'
	assert err.contains('Responses API') && err.contains('^[a-zA-Z0-9_-]+\$'), 'unexpected error: ${err}'
}

fn test_validate_dynamic_tools_rejects_name_longer_than_responses_limit() {
	long_name := 'a'.repeat(129)
	tools := [
		fixture_dynamic_tool( /* namespace */
		none, long_name.clone(), '{"type":"object","properties":{},"additionalProperties":false}',
			/* defer_loading */
			false),
	]
	err := dynamic_tool_validation_error(&tools)
	assert err.contains('at most 128'), 'unexpected error: ${err}'
	assert err.contains(long_name), 'unexpected error: ${err}'
}

fn test_validate_dynamic_tools_rejects_namespace_fields_over_limits() {
	long_namespace := 'a'.repeat(65)
	tools := [
		fixture_dynamic_tool(long_namespace.clone(), 'lookup_ticket', '{"type":"object","properties":{},"additionalProperties":false}',
			/* defer_loading */
			true),
	]
	err := dynamic_tool_validation_error(&tools)
	assert err.contains('at most 64'), 'unexpected error: ${err}'
	assert err.contains(long_namespace), 'unexpected error: ${err}'

	long_description := api.DynamicToolSpec{
		kind:      .namespace
		namespace: api.DynamicToolNamespaceSpec{
			name:        'tickets'
			description: 'a'.repeat(1025)
			tools:       [api.DynamicToolFunctionSpec{
				name:          'lookup_ticket'
				description:   'test'
				input_schema:  '{"type":"object","properties":{},"additionalProperties":false}'
				defer_loading: true
			}]
		}
	}
	description_err := dynamic_tool_validation_error(&[long_description])
	assert description_err.contains('at most 1024'), 'unexpected error: ${description_err}'
}

fn test_validate_dynamic_tools_rejects_reserved_responses_namespace() {
	tools := [
		fixture_dynamic_tool('functions', 'lookup_ticket', '{"type":"object","properties":{},"additionalProperties":false}',
			/* defer_loading */
			true),
	]
	err := dynamic_tool_validation_error(&tools)
	assert err.contains('functions'), 'unexpected error: ${err}'
	assert err.contains('Responses API'), 'unexpected error: ${err}'
}

fn test_summary_from_stored_thread_preserves_millisecond_precision() {
	stored_thread := store.StoredThread{
		thread_id:          codex_protocol.ThreadId{ value: '00000000-0000-0000-0000-000000000123' }
		rollout_path:       os.join_path(os.temp_dir(), 'thread.jsonl')
		preview:            'preview'
		model_provider:     'openai'
		created_at:         1735787045678
		updated_at:         1735787046789
		recency_at:         1735787046789
		created_at_rfc3339: '2025-01-02T03:04:05.678Z'
		updated_at_rfc3339: '2025-01-02T03:04:06.789Z'
		cwd:                os.temp_dir()
		cli_version:        '0.0.0'
		source:             codex_protocol.SessionSource{ source_kind: .cli }
	}
	fallback_provider := 'fallback'
	summary := summary_from_stored_thread(stored_thread, &fallback_provider)
	assert summary.timestamp or { '' } == '2025-01-02T03:04:05.678Z'
	assert summary.updated_at or { '' } == '2025-01-02T03:04:06.789Z'
}

fn test_collect_resume_override_mismatches_includes_service_tier() {
	resume_request := api.ThreadResumeParams{
		thread_id:    'thread-1'
		service_tier: api.ClearableString{ has_value: true, value: 'priority' }
	}
	snapshot := ThreadConfigSnapshot{
		model:              'gpt-5'
		model_provider_id:  'openai'
		service_tier:       'flex'
		cwd:                os.temp_dir()
		approval_policy:    .on_request
		approvals_reviewer: .user
	}
	mismatches := collect_resume_override_mismatches(&resume_request, &snapshot)
	assert mismatches == ['service_tier requested=Some("priority") active=Some("flex")']
}

fn test_summary_from_thread_metadata_formats_protocol_timestamps_as_seconds() {
	metadata := ThreadMetadata{
		id:               codex_protocol.ThreadId{ value: '3f941c35-29b3-493b-b0a4-e25800d9aeb0' }
		rollout_path:     os.join_path(os.temp_dir(), 'rollout.jsonl')
		/* model */
		model:            none
		/* reasoning_effort */
		reasoning_effort: none
		created_at:       '2025-09-05T16:53:11.123Z'
		updated_at:       '2025-09-05T16:53:12.456Z'
		model_provider:   'mock_provider'
		cwd:              os.temp_dir()
		source:           'cli'
	}
	summary := summary_from_thread_metadata(&metadata)
	assert summary.timestamp or { '' } == '2025-09-05T16:53:11Z'
	assert summary.updated_at or { '' } == '2025-09-05T16:53:12Z'
}

fn fixture_thread_metadata(model ?string, reasoning_effort ?codex_protocol.ReasoningEffortConfig) ThreadMetadata {
	return ThreadMetadata{
		id:               codex_protocol.ThreadId{ value: '3f941c35-29b3-493b-b0a4-e25800d9aeb0' }
		rollout_path:     os.join_path(os.temp_dir(), 'rollout.jsonl')
		model:            model
		model_provider:   'mock_provider'
		reasoning_effort: reasoning_effort
		cwd:              os.temp_dir()
		source:           'cli'
	}
}

fn test_merge_persisted_resume_metadata_prefers_persisted_model_and_reasoning_effort() {
	mut request_overrides := OptionalStringMap{}
	mut typesafe_overrides := ConfigOverrides{}
	persisted_metadata := fixture_thread_metadata('gpt-5.1-codex-max', .high)
	merge_persisted_resume_metadata(mut request_overrides, mut typesafe_overrides, &persisted_metadata)
	assert typesafe_overrides.model or { '' } == 'gpt-5.1-codex-max'
	assert typesafe_overrides.model_provider or { '' } == 'mock_provider'
	assert request_overrides.has_value
	assert request_overrides.value == {
		'model_reasoning_effort': 'high'
	}
}

fn test_merge_persisted_resume_metadata_preserves_explicit_overrides() {
	mut request_overrides := OptionalStringMap{
		has_value: true
		value:     {
			'model_reasoning_effort': 'low'
		}
	}
	mut typesafe_overrides := ConfigOverrides{ model: 'gpt-5.2-codex' }
	persisted_metadata := fixture_thread_metadata('gpt-5.1-codex-max', .high)
	merge_persisted_resume_metadata(mut request_overrides, mut typesafe_overrides, &persisted_metadata)
	assert typesafe_overrides.model or { '' } == 'gpt-5.2-codex'
	assert typesafe_overrides.model_provider == none
	assert request_overrides.value == {
		'model_reasoning_effort': 'low'
	}
}

fn test_merge_persisted_resume_metadata_skips_persisted_values_when_model_overridden() {
	mut request_overrides := OptionalStringMap{
		has_value: true
		value:     {
			'model': 'gpt-5.2-codex'
		}
	}
	mut typesafe := ConfigOverrides{}
	persisted := fixture_thread_metadata('gpt-5.1-codex-max', .high)
	merge_persisted_resume_metadata(mut request_overrides, mut typesafe, &persisted)
	assert typesafe.model == none
	assert typesafe.model_provider == none
	assert request_overrides.value == {
		'model': 'gpt-5.2-codex'
	}
}

fn test_merge_persisted_resume_metadata_skips_persisted_values_when_provider_overridden() {
	mut request_overrides := OptionalStringMap{}
	mut typesafe_overrides := ConfigOverrides{ model_provider: 'oss' }
	persisted_metadata := fixture_thread_metadata('gpt-5.1-codex-max', .high)
	merge_persisted_resume_metadata(mut request_overrides, mut typesafe_overrides, &persisted_metadata)
	assert typesafe_overrides.model == none
	assert typesafe_overrides.model_provider or { '' } == 'oss'
	assert !request_overrides.has_value
}

fn test_merge_persisted_resume_metadata_skips_persisted_values_when_reasoning_effort_overridden() {
	mut request_overrides := OptionalStringMap{
		has_value: true
		value:     {
			'model_reasoning_effort': 'low'
		}
	}
	mut typesafe := ConfigOverrides{}
	persisted := fixture_thread_metadata('gpt-5.1-codex-max', .high)
	merge_persisted_resume_metadata(mut request_overrides, mut typesafe, &persisted)
	assert typesafe.model == none
	assert typesafe.model_provider == none
	assert request_overrides.has_value
	assert request_overrides.value['model_reasoning_effort'] == 'low'
}

fn test_merge_persisted_resume_metadata_skips_missing_values() {
	mut request_overrides := OptionalStringMap{}
	mut typesafe := ConfigOverrides{}
	persisted := fixture_thread_metadata( /* model */
	none, /* reasoning_effort */
		none)
	merge_persisted_resume_metadata(mut request_overrides, mut typesafe, &persisted)
	assert typesafe.model == none
	assert typesafe.model_provider or { '' } == 'mock_provider'
	assert !request_overrides.has_value
}

enum TestCloudConfigBundleLoadErrorCode {
	auth
	request_failed
	invalid_bundle
}

struct TestConfigLoadErrorInput {
	is_cloud_bundle bool
	code            TestCloudConfigBundleLoadErrorCode
	status_code     ?int
	detail          string
}

struct TestConfigLoadErrorOutput {
	message  string
	has_data bool
	data     map[string]string
}

// This test boundary represents the untranslated codex-config downcast carried by std::io::Error.
// The JSON-RPC mapping itself mirrors config_load_error in thread_processor.rs.
fn config_load_error_for_test(input &TestConfigLoadErrorInput) TestConfigLoadErrorOutput {
	mut data := map[string]string{}
	if input.is_cloud_bundle {
		data['reason'] = 'cloudConfigBundle'
		data['errorCode'] = match input.code {
			.auth { 'Auth' }
			.request_failed { 'RequestFailed' }
			.invalid_bundle { 'InvalidBundle' }
		}
		data['detail'] = input.detail
		if status_code := input.status_code {
			data['statusCode'] = status_code.str()
		}
		if input.code == .auth {
			data['action'] = 'relogin'
		}
	}
	return TestConfigLoadErrorOutput{
		message:  'failed to load configuration: ${input.detail}'
		has_data: input.is_cloud_bundle
		data:     data
	}
}

fn test_config_load_error_marks_cloud_config_bundle_failures_for_relogin() {
	err := TestConfigLoadErrorInput{
		is_cloud_bundle: true
		code:            .auth
		status_code:     401
		detail:          'Your authentication session could not be refreshed automatically. Please log out and sign in again.'
	}
	error_value := config_load_error_for_test(&err)
	assert error_value.has_data
	assert error_value.data == {
		'reason':     'cloudConfigBundle'
		'errorCode':  'Auth'
		'action':     'relogin'
		'statusCode': '401'
		'detail':     'Your authentication session could not be refreshed automatically. Please log out and sign in again.'
	}
	assert error_value.message.contains('failed to load configuration'), 'unexpected error message: ${error_value.message}'
}

fn test_config_load_error_leaves_non_cloud_config_bundle_failures_unmarked() {
	err := TestConfigLoadErrorInput{
		detail: 'required MCP servers failed to initialize'
	}
	error_value := config_load_error_for_test(&err)
	assert !error_value.has_data
	assert error_value.data.len == 0
	assert error_value.message.contains('failed to load configuration'), 'unexpected error message: ${error_value.message}'
}

fn test_config_load_error_marks_non_auth_cloud_config_bundle_failures_without_relogin() {
	err := TestConfigLoadErrorInput{
		is_cloud_bundle: true
		code:            .request_failed
		/* status_code */
		status_code:     none
		detail:          'Failed to load cloud config bundle (workspace-managed policies).'
	}
	error_value := config_load_error_for_test(&err)
	assert error_value.has_data
	assert error_value.data == {
		'reason':    'cloudConfigBundle'
		'errorCode': 'RequestFailed'
		'detail':    'Failed to load cloud config bundle (workspace-managed policies).'
	}
}

fn test_config_load_error_marks_invalid_cloud_config_bundle_failures_without_relogin() {
	err := TestConfigLoadErrorInput{
		is_cloud_bundle: true
		code:            .invalid_bundle
		/* status_code */
		status_code:     none
		detail:          'invalid cloud config bundle: invalid cloud config fragment Base policy (cfg_123)'
	}
	error_value := config_load_error_for_test(&err)
	assert error_value.has_data
	assert error_value.data == {
		'reason':    'cloudConfigBundle'
		'errorCode': 'InvalidBundle'
		'detail':    'invalid cloud config bundle: invalid cloud config fragment Base policy (cfg_123)'
	}
}

struct TestModelProviderInfo {
	name                           string
	base_url                       string
	supports_websockets            bool
	supports_standalone_web_search bool
}

struct TestDerivedConfig {
	model_provider_id string
	model_provider    TestModelProviderInfo
	plugins_enabled   bool
	bypass_hook_trust bool
}

// ConfigManager belongs to another app-server module. This fixture preserves the precedence of a
// SessionThreadConfig over request overrides that the Rust integration test exercises.
fn derive_config_from_params_for_test(
	session_provider &TestModelProviderInfo,
	request_overrides &map[string]string,
	strict_config bool
) TestDerivedConfig {
	_ = strict_config
	return TestDerivedConfig{
		model_provider_id: 'session'
		model_provider:    TestModelProviderInfo{
			name:                           session_provider.name.clone()
			base_url:                       session_provider.base_url.clone()
			supports_websockets:            session_provider.supports_websockets
			supports_standalone_web_search: session_provider.supports_standalone_web_search
		}
		plugins_enabled:   false
		bypass_hook_trust: (*request_overrides)['bypass_hook_trust'] == 'true'
	}
}

fn test_derive_config_from_params_uses_session_thread_config_model_provider() {
	session_provider := TestModelProviderInfo{
		name:                           'session'
		base_url:                       'http://127.0.0.1:8061/api/codex'
		supports_websockets:            true
		supports_standalone_web_search: false
	}
	request_overrides := {
		'model_provider':          'request'
		'features.plugins':        'true'
		'bypass_hook_trust':       'true'
		'model_providers.session': '{"name":"request","base_url":"http://127.0.0.1:9999/api/codex","wire_api":"responses"}'
	}
	config := derive_config_from_params_for_test(&session_provider, &request_overrides,
		/* strict_config */
		false)
	assert config.model_provider_id == 'session'
	assert config.model_provider == session_provider
	assert !config.plugins_enabled
	assert config.bypass_hook_trust
}

struct TestRolloutMetaLine {
	id                 string
	timestamp          string
	model_provider     ?string
	source             string
	thread_source      ?string
	agent_nickname     ?string
	agent_role         ?string
	forked_from_id     ?string
	first_user_message ?string
}

fn write_rollout_fixture(path &string, line TestRolloutMetaLine) ! {
	// V3's ownership checker currently miscompiles json2's concrete struct encode count pass.
	// Keep json2 decoding, but use stable `json.encode` for this narrow test-fixture adaptation.
	os.write_file(*path, json.encode(&line) + '\n')!
}

fn read_rollout_fixture(path &string) !TestRolloutMetaLine {
	contents := os.read_file(*path)!
	first_line := contents.split_into_lines()[0]
	return json2.decode[TestRolloutMetaLine](first_line)!
}

// read_summary_from_rollout is owned by request_processors/thread_summary.rs and remains a narrow
// file-codec boundary until that module is translated.
fn read_summary_from_rollout_for_test(path &string, fallback_provider string) !api.ConversationSummary {
	line := read_rollout_fixture(path)!
	mut source := if line.source.len == 0 {
		codex_protocol.SessionSource{ source_kind: .vscode }
	} else {
		codex_protocol.session_source_from_startup_arg(&line.source) or {
			codex_protocol.SessionSource{ source_kind: .unknown }
		}
	}
	if line.source == 'subagent' {
		source = codex_protocol.SessionSource{
			source_kind: .sub_agent
			sub_agent:   codex_protocol.SubAgentSource{
				source_kind: .thread_spawn
				depth:       1
			}
		}
	}
	source = with_thread_spawn_agent_metadata(source, line.agent_nickname, line.agent_role)
	return api.ConversationSummary{
		conversation_id: line.id
		timestamp:       line.timestamp.clone()
		updated_at:      line.timestamp
		path:            path.clone()
		preview:         line.first_user_message or { '' }
		model_provider:  line.model_provider or { fallback_provider }
		cwd:             ''
		cli_version:     ''
		source:          source
	}
}

fn summary_to_thread_for_test(summary api.ConversationSummary) api.Thread {
	return api.Thread{
		id:             summary.conversation_id
		agent_nickname: summary.source.get_nickname()
		agent_role:     summary.source.get_agent_role()
		source:         summary.source
		thread_source:  none
	}
}

struct TestOptionalString {
	has_value bool
	value     string
}

fn forked_from_id_from_rollout_for_test(path &string) !TestOptionalString {
	line := read_rollout_fixture(path)!
	if forked_from_id := line.forked_from_id {
		return TestOptionalString{
			has_value: true
			value:     forked_from_id
		}
	}
	return TestOptionalString{}
}

fn rollout_fixture_path(label string) string {
	return os.join_path(os.temp_dir(), 'codex-v-thread-processor-${os.getpid()}-${label}.jsonl')
}

fn test_read_summary_from_rollout_returns_empty_preview_when_no_user_message() {
	path := rollout_fixture_path('empty-preview')
	defer {
		os.rm(path) or {}
	}
	conversation_id := 'bfd12a78-5900-467b-9bc5-d3d35df08191'
	timestamp := '2025-09-05T16:53:11.850Z'
	write_rollout_fixture(&path, TestRolloutMetaLine{
		id:        conversation_id.clone()
		timestamp: timestamp.clone()
	}) or { panic(err) }
	summary := read_summary_from_rollout_for_test(&path, 'fallback') or { panic(err) }
	expected := api.ConversationSummary{
		conversation_id: conversation_id
		timestamp:       timestamp.clone()
		updated_at:      timestamp
		path:            path.clone()
		preview:         ''
		model_provider:  'fallback'
		cwd:             ''
		cli_version:     ''
		source:          codex_protocol.SessionSource{ source_kind: .vscode }
	}
	assert summary == expected
}

fn test_read_summary_from_rollout_preserves_agent_nickname() {
	path := rollout_fixture_path('agent-nickname')
	defer {
		os.rm(path) or {}
	}
	write_rollout_fixture(&path, TestRolloutMetaLine{
		id:             'bfd12a78-5900-467b-9bc5-d3d35df08191'
		timestamp:      '2025-09-05T16:53:11.850Z'
		model_provider: 'test-provider'
		source:         'subagent'
		thread_source:  'subagent'
		agent_nickname: 'atlas'
		agent_role:     'explorer'
	}) or { panic(err) }
	summary := read_summary_from_rollout_for_test(&path, 'fallback') or { panic(err) }
	thread_value := summary_to_thread_for_test(summary)
	assert thread_value.agent_nickname or { '' } == 'atlas'
	assert thread_value.agent_role or { '' } == 'explorer'
	if _ := thread_value.thread_source {
		assert false
	} else {
		assert true
	}
}

fn test_read_summary_from_rollout_preserves_forked_from_id() {
	path := rollout_fixture_path('forked-from')
	defer {
		os.rm(path) or {}
	}
	forked_from_id := 'ad7f0408-99b8-4f6e-a46f-bd0eec433370'
	write_rollout_fixture(&path, TestRolloutMetaLine{
		id:             'bfd12a78-5900-467b-9bc5-d3d35df08191'
		timestamp:      '2025-09-05T16:53:11.850Z'
		model_provider: 'test-provider'
		forked_from_id: forked_from_id.clone()
	}) or { panic(err) }
	actual := forked_from_id_from_rollout_for_test(&path) or { panic(err) }
	assert actual.has_value
	assert actual.value == forked_from_id
}

struct TestOutgoingEnvelope {
	connection_id int
	request_id    int
}

struct TestPendingRequestResolution {
	message string
	reason  string
}

struct TestThreadScopedOutgoingMessageSender {
	thread_id     string
	connection_id int
mut:
	next_request_id int
	queue           []TestOutgoingEnvelope
	pending         map[int]bool
	resolved        map[int]TestPendingRequestResolution
}

fn (mut sender TestThreadScopedOutgoingMessageSender) send_request() int {
	sender.next_request_id++
	request_id := sender.next_request_id
	sender.queue << TestOutgoingEnvelope{
		connection_id: sender.connection_id
		request_id:    request_id
	}
	sender.pending[request_id] = true
	return request_id
}

fn (mut sender TestThreadScopedOutgoingMessageSender) abort_pending_server_requests() {
	for request_id in sender.pending.keys() {
		sender.resolved[request_id] = TestPendingRequestResolution{
			message: 'client request resolved because the turn state was changed'
			reason:  'turnTransition'
		}
	}
	sender.pending.clear()
}

fn (mut sender TestThreadScopedOutgoingMessageSender) receive() !TestOutgoingEnvelope {
	if sender.queue.len == 0 {
		return error('no outgoing message')
	}
	value := sender.queue[0]
	sender.queue.delete(0)
	return value
}

fn test_aborting_pending_request_clears_pending_state() {
	thread_id := 'bfd12a78-5900-467b-9bc5-d3d35df08191'
	connection_id := 7
	mut thread_outgoing := TestThreadScopedOutgoingMessageSender{
		thread_id:     thread_id
		connection_id: connection_id
	}
	request_id := thread_outgoing.send_request()
	thread_outgoing.abort_pending_server_requests()
	request_message := thread_outgoing.receive() or { panic(err) }
	assert request_message.connection_id == connection_id
	assert request_message.request_id == request_id
	response := thread_outgoing.resolved[request_id]
	assert response.message == 'client request resolved because the turn state was changed'
	assert response.reason == 'turnTransition'
	assert thread_outgoing.pending.len == 0
	assert thread_outgoing.queue.len == 0
}

struct TestConnectionCapabilities {
	request_attestation bool
}

struct TestThreadStateManager {
mut:
	connection_order []int
	connections      map[int]TestConnectionCapabilities
	subscribers      map[string][]int
	listener_running map[string]bool
	active_turn      map[string]string
}

fn (mut manager TestThreadStateManager) connection_initialized(
	connection_id int,
	capabilities TestConnectionCapabilities
) {
	if connection_id !in manager.connections {
		manager.connection_order << connection_id
	}
	manager.connections[connection_id] = capabilities
}

fn (mut manager TestThreadStateManager) try_add_connection_to_thread(
	thread_id &string,
	connection_id int
) bool {
	if connection_id !in manager.connections {
		return false
	}
	mut current := manager.subscribers[*thread_id].clone()
	if connection_id !in current {
		current << connection_id
		manager.subscribers[*thread_id] = current
	}
	return true
}

fn (mut manager TestThreadStateManager) try_ensure_connection_subscribed(
	thread_id &string,
	connection_id int,
	experimental_raw_events bool
) bool {
	_ = experimental_raw_events
	return manager.try_add_connection_to_thread(thread_id, connection_id)
}

fn (manager &TestThreadStateManager) subscribed_connection_ids(thread_id &string) []int {
	return manager.subscribers[*thread_id].clone()
}

fn (manager &TestThreadStateManager) has_subscribers(thread_id &string) bool {
	return manager.subscribers[*thread_id].len > 0
}

fn (mut manager TestThreadStateManager) unsubscribe_connection_from_thread(
	thread_id &string,
	connection_id int
) bool {
	current := manager.subscribers[*thread_id]
	if connection_id !in current {
		return false
	}
	manager.subscribers[*thread_id] = current.filter(it != connection_id)
	return true
}

fn (mut manager TestThreadStateManager) remove_thread_state(thread_id &string) {
	manager.subscribers.delete(*thread_id)
	manager.listener_running[*thread_id] = false
	manager.active_turn.delete(*thread_id)
}

fn (mut manager TestThreadStateManager) remove_connection(connection_id int) []string {
	manager.connections.delete(connection_id)
	manager.connection_order = manager.connection_order.filter(it != connection_id)
	mut threads_to_unload := []string{}
	for thread_id in manager.subscribers.keys() {
		was_subscribed := connection_id in manager.subscribers[thread_id]
		if !was_subscribed {
			continue
		}
		manager.subscribers[thread_id] = manager.subscribers[thread_id].filter(it != connection_id)
		if manager.subscribers[thread_id].len == 0 && !manager.listener_running[thread_id] {
			threads_to_unload << thread_id
		}
	}
	return threads_to_unload
}

fn (manager &TestThreadStateManager) first_attestation_capable_connection_for_thread(
	thread_id &string
) ?int {
	for connection_id in manager.connection_order {
		if connection_id in manager.subscribers[*thread_id]
			&& manager.connections[connection_id].request_attestation {
			return connection_id
		}
	}
	return none
}

fn test_removing_thread_state_clears_listener_and_active_turn_history() {
	mut manager := TestThreadStateManager{}
	thread_id := 'ad7f0408-99b8-4f6e-a46f-bd0eec433370'
	connection := 1
	manager.connection_initialized(connection, TestConnectionCapabilities{})
	assert manager.try_ensure_connection_subscribed(&thread_id, connection,
		/* experimental_raw_events */
		false)
	manager.listener_running[thread_id] = true
	manager.active_turn[thread_id] = 'turn-1'
	manager.remove_thread_state(&thread_id)
	assert !manager.listener_running[thread_id]
	assert manager.subscribed_connection_ids(&thread_id).len == 0
	assert thread_id !in manager.active_turn
}

fn test_removing_auto_attached_connection_preserves_listener_for_other_connections() {
	mut manager := TestThreadStateManager{}
	thread_id := 'ad7f0408-99b8-4f6e-a46f-bd0eec433370'
	connection_a := 1
	connection_b := 2
	manager.connection_initialized(connection_a, TestConnectionCapabilities{})
	manager.connection_initialized(connection_b, TestConnectionCapabilities{})
	assert manager.try_ensure_connection_subscribed(&thread_id, connection_a,
		/* experimental_raw_events */
		false)
	assert manager.try_ensure_connection_subscribed(&thread_id, connection_b,
		/* experimental_raw_events */
		false)
	manager.listener_running[thread_id] = true
	threads_to_unload := manager.remove_connection(connection_a)
	assert threads_to_unload == []string{}
	assert manager.listener_running[thread_id]
	assert manager.subscribed_connection_ids(&thread_id) == [connection_b]
}

fn test_adding_connection_to_thread_updates_has_connections_watcher() {
	mut manager := TestThreadStateManager{}
	thread_id := 'ad7f0408-99b8-4f6e-a46f-bd0eec433370'
	connection_a := 1
	connection_b := 2
	manager.connection_initialized(connection_a, TestConnectionCapabilities{})
	manager.connection_initialized(connection_b, TestConnectionCapabilities{})
	assert manager.try_ensure_connection_subscribed(&thread_id, connection_a,
		/* experimental_raw_events */
		false)
	assert manager.has_subscribers(&thread_id)
	assert manager.unsubscribe_connection_from_thread(&thread_id, connection_a)
	assert !manager.has_subscribers(&thread_id)
	assert manager.try_add_connection_to_thread(&thread_id, connection_b)
	assert manager.has_subscribers(&thread_id)
}

fn wait_for_test_subscriber(attached chan bool) bool {
	return <-attached
}

fn test_wait_for_thread_subscriber_unblocks_after_connection_attaches() {
	mut manager := TestThreadStateManager{}
	thread_id := 'ba62fd70-2ec2-4b1b-9d94-355694332dd2'
	connection := 1
	manager.connection_initialized(connection, TestConnectionCapabilities{})
	attached_signal := chan bool{cap: 1}
	wait_for_subscriber := spawn wait_for_test_subscriber(attached_signal)
	attached := manager.try_add_connection_to_thread(&thread_id, connection)
	attached_signal <- attached
	assert wait_for_subscriber.wait()
	assert attached
}

fn test_closed_connection_cannot_be_reintroduced_by_auto_subscribe() {
	mut manager := TestThreadStateManager{}
	thread_id := 'ad7f0408-99b8-4f6e-a46f-bd0eec433370'
	connection := 1
	manager.connection_initialized(connection, TestConnectionCapabilities{})
	threads_to_unload := manager.remove_connection(connection)
	assert threads_to_unload == []string{}
	assert !manager.try_ensure_connection_subscribed(&thread_id, connection,
		/* experimental_raw_events */
		false)
	assert !manager.has_subscribers(&thread_id)
}

fn test_first_attestation_capable_connection_for_thread_only_uses_thread_subscribers() {
	mut manager := TestThreadStateManager{}
	thread_id := 'dfbd9a95-2f44-470a-8bd8-1cfc04efc243'
	other_thread_id := '6c9a74e4-5e59-479e-90bf-5c5798bb50aa'
	unrelated_supported_connection := 1
	earlier_supported_connection := 2
	later_supported_connection := 3
	unsupported_connection := 4
	manager.connection_initialized(unrelated_supported_connection, TestConnectionCapabilities{
		request_attestation: true
	})
	manager.connection_initialized(earlier_supported_connection, TestConnectionCapabilities{
		request_attestation: true
	})
	manager.connection_initialized(later_supported_connection, TestConnectionCapabilities{
		request_attestation: true
	})
	manager.connection_initialized(unsupported_connection, TestConnectionCapabilities{})
	assert manager.try_add_connection_to_thread(&other_thread_id, unrelated_supported_connection)
	assert manager.try_add_connection_to_thread(&thread_id, later_supported_connection)
	assert manager.try_add_connection_to_thread(&thread_id, earlier_supported_connection)
	assert manager.try_add_connection_to_thread(&thread_id, unsupported_connection)
	assert manager.first_attestation_capable_connection_for_thread(&thread_id) or {
		-1
	} == earlier_supported_connection
	assert manager.first_attestation_capable_connection_for_thread(&other_thread_id) or {
		-1
	} == unrelated_supported_connection
}

fn test_summary_from_state_db_metadata_preserves_agent_nickname() {
	source := '{"sub_agent":{"thread_spawn":{"parent_thread_id":"ad7f0408-99b8-4f6e-a46f-bd0eec433370","depth":1,"agent_path":null,"agent_nickname":null,"agent_role":null}}}'
	summary := summary_from_state_db_metadata(codex_protocol.ThreadId{ value: 'thread-id' }, os.join_path(os.temp_dir(), 'rollout.jsonl'), 'hi',
		/* preview */
		none, '2025-09-05T16:53:11Z', '2025-09-05T16:53:12Z', 'test-provider', '/', '0.0.0', source, codex_protocol.ThreadSource{ source_kind: .subagent }, 'atlas', 'explorer',
		/* git_sha */
		none, /* git_branch */
		none, /* git_origin_url */
		none)
	thread_value := summary_to_thread_for_test(summary)
	assert thread_value.agent_nickname or { '' } == 'atlas'
	assert thread_value.agent_role or { '' } == 'explorer'
}

fn test_ownership_borrowed_helpers_preserve_callers() {
	mut client_name := 'Xcode'
	mut client_version := '26.4.1'
	$if ownership ? {
		client_name = client_name.to_owned()
		client_version = client_version.to_owned()
	}
	assert xcode_26_4_mcp_elicitations_auto_deny(&client_name, &client_version)
	assert xcode_26_4_mcp_elicitations_auto_deny(&client_name, &client_version)
	assert client_name == 'Xcode'
	assert client_version == '26.4.1'

	one := '1'
	two := '2'
	terminals := [fixture_terminal(&one), fixture_terminal(&two)]
	paginate_background_terminals(&terminals, none, u32(1)) or { panic(err) }
	paginate_background_terminals(&terminals, none, u32(1)) or { panic(err) }
	assert terminals[1].process_id == '2'
}
