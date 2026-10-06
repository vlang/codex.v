module temporary_structured_request

import codex_app_server_client
import codex_app_server_protocol
import codex_core
import codex_protocol
import codex_protocol.openai_models
import codex_state.sqlite
import codex_tui
import codex_tui.chatwidget.tests as chatwidget_tests
import os
import serde_json
import time
import tokio.sync.mpsc
import tokio.time as tokio_time
import uuid

fn owned(value &string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn agent_message_notification(turn_id &string, text &string) codex_app_server_protocol.ServerNotification {
	return codex_app_server_protocol.ItemCompletedNotification{
		item:            codex_app_server_protocol.ThreadItem{ kind: .agent_message, id: 'message-1', text: text.clone(), phase: none, memory_citation: none, delivery: none, questions: none }
		thread_id:       'thread-1'
		turn_id:         turn_id.clone()
		completed_at_ms: 0
	}
}

fn turn_completed_notification(turn_id &string, status codex_app_server_protocol.TurnStatus) codex_app_server_protocol.ServerNotification {
	return codex_app_server_protocol.TurnCompletedNotification{
		thread_id: 'thread-1'
		turn:      codex_app_server_protocol.Turn{ id: turn_id.clone(), items: []codex_app_server_protocol.ThreadItem{}, items_view: .full, status: status, error: none, started_at: none, completed_at: none, duration_ms: none }
	}
}

fn test_preserves_custom_permissions_and_disables_required_mcp_servers() {
	chat_widget, _, _, _ := chatwidget_tests.make_chatwidget_manual_with_sender()
	mut config := codex_core.clone_config_with_cwd(chat_widget.config_ref(), chat_widget.config_ref().cwd.clone())
	codex_home := os.join_path(os.temp_dir(), 'codex-temporary-structured-${uuid.Uuid.new_v4()}')
	os.mkdir_all(codex_home) or { panic(err) }
	defer { os.rmdir_all(codex_home) or { panic(err) } }
	denied_path := os.join_path(codex_home, 'denied')
	denied_key := serde_json.Value.string(denied_path.clone()).to_string()
	config_text := 'default_permissions = "title-restricted"\n\n[permissions.title-restricted.filesystem]\n":root" = "read"\n${denied_key} = "deny"\n\n[mcp_servers.forbidden]\ncommand = "codex-auto-title-missing-mcp"\nrequired = true\n'
	os.write_file(os.join_path(codex_home, 'config.toml'), config_text) or { panic(err) }
	config.codex_home = os.real_path(codex_home)
	config.sqlite = sqlite.SqliteConfig.new_for_testing(os.real_path(codex_home))
	app_server := codex_tui.start_embedded_app_server_for_picker(&config) or { panic(err) }
	handle := app_server.request_handle()
	response := start_temporary_thread(&handle, TemporaryStructuredThreadOptions{
		model:                     'gpt-5.2'
		model_provider:            config.model_provider_id.clone()
		cwd:                       config.cwd.clone()
		active_permission_profile: 'title-restricted'
		mcp_server_names:          ['forbidden']
	}) or { panic(err) }
	assert response.active_permission_profile?.id == 'title-restricted'
	assert response.model_provider == config.model_provider_id
	assert response.thread.ephemeral
	app_server.shutdown() or { panic(err) }
}

fn test_returns_latest_matching_assistant_message() {
	sender, receiver := mpsc.unbounded_notifications_channel()
	other := 'other-turn'
	turn := 'turn-1'
	ignore := 'ignore me'
	first := 'first'
	final_text := 'final'
	sender.send(agent_message_notification(&other, &ignore)) or { panic('send unrelated assistant message: ${err}') }
	sender.send(turn_completed_notification(&other, .completed)) or { panic('send unrelated completion: ${err}') }
	sender.send(agent_message_notification(&turn, &first)) or { panic('send first assistant message: ${err}') }
	sender.send(agent_message_notification(&turn, &final_text)) or { panic('send final assistant message: ${err}') }
	sender.send(turn_completed_notification(&turn, .completed)) or { panic('send matching completion: ${err}') }
	defer { sender.close() }
	response := collect_structured_response(receiver, &turn) or { panic('collect structured response: ${err}') }
	assert response == 'final'
}

fn test_rejects_failed_turn() {
	sender, receiver := mpsc.unbounded_notifications_channel()
	turn := 'turn-1'
	sender.send(turn_completed_notification(&turn, .failed)) or { panic('send failed completion: ${err}') }
	defer { sender.close() }
	collect_structured_response(receiver, &turn) or {
		assert err.msg() == 'temporary structured turn ended with status Failed'
		return
	}
	assert false, 'failed turn should not produce a response'
}

fn test_rejects_completion_without_assistant_message() {
	sender, receiver := mpsc.unbounded_notifications_channel()
	turn := 'turn-1'
	sender.send(turn_completed_notification(&turn, .completed)) or { panic('send completion: ${err}') }
	defer { sender.close() }
	collect_structured_response(receiver, &turn) or {
		assert err.msg() == 'temporary structured turn completed without a response'
		return
	}
	assert false, 'completion without assistant message should fail'
}

fn test_rejects_closed_notification_channel() {
	sender, receiver := mpsc.unbounded_notifications_channel()
	turn := 'turn-1'
	sender.close()
	collect_structured_response(receiver, &turn) or {
		assert err.msg() == 'temporary structured turn notification channel closed'
		return
	}
	assert false, 'closed notification channel should fail'
}

fn test_rejects_oversized_assistant_message() {
	sender, receiver := mpsc.unbounded_notifications_channel()
	turn := 'turn-1'
	oversized := 'x'.repeat(int(structured_response_max_bytes) + 1)
	sender.send(agent_message_notification(&turn, &oversized)) or { panic('send oversized assistant message: ${err}') }
	sender.send(turn_completed_notification(&turn, .completed)) or { panic('send matching completion: ${err}') }
	defer { sender.close() }
	collect_structured_response(receiver, &turn) or {
		assert err.msg() == 'temporary structured response exceeds 8192 bytes'
		return
	}
	assert false, 'oversized assistant message should be rejected'
}

fn fixture_handle(profile ?string, effective_servers serde_json.Value, failure_method string, failure_kind ?codex_app_server_client.TypedRequestErrorKind) codex_app_server_client.AppServerRequestHandle {
	return codex_app_server_client.AppServerRequestHandle.temporary_structured_fixture(codex_app_server_protocol.ConfigReadResponse{
		config: codex_app_server_protocol.Config{
			additional: {
				'mcp_servers': effective_servers
			}
		}
	}, profile, codex_protocol.SandboxPolicy{ policy_kind: .read_only }, failure_method, failure_kind, 0)
}

fn test_read_only_disables_union_of_visible_and_remote_effective_servers_and_preserves_all_overrides() {
	model_literal := 'owned model'
	model := owned(&model_literal)
	provider_literal := 'owned provider'
	provider := owned(&provider_literal)
	cwd_literal := '/owned/cwd'
	cwd := owned(&cwd_literal)
	handle := fixture_handle(none, serde_json.Value.object({
		'remote':  serde_json.Value.object({})
		'visible': serde_json.Value.object({})
	}), '', none)
	response := start_temporary_thread(&handle, TemporaryStructuredThreadOptions{
		model:                     model
		model_provider:            provider
		cwd:                       cwd
		active_permission_profile: ':read-only'
		mcp_server_names:          ['visible', 'visible', 'local']
	}) or { panic(err) }
	assert response.sandbox.policy_kind == .read_only
	requests := handle.structured_fixture_requests()
	assert requests.len == 2
	assert (*requests)[0] is codex_app_server_protocol.ClientRequestConfigRead
	assert (*requests)[1] is codex_app_server_protocol.ClientRequestThreadStart
	read := (*requests)[0] as codex_app_server_protocol.ClientRequestConfigRead
	assert !read.params.include_layers
	assert read.params.cwd? == '/owned/cwd'
	assert read.request_id.string_value.starts_with('temporary-config-')
	start := (*requests)[1] as codex_app_server_protocol.ClientRequestThreadStart
	params := &start.params
	assert start.request_id.string_value.starts_with('temporary-structured-')
	assert params.model? == 'owned model'
	assert params.model_provider? == 'owned provider'
	assert params.cwd? == '/owned/cwd'
	assert params.approval_policy? == codex_app_server_protocol.AskForApproval{ kind: .never }
	assert params.permissions == none
	assert params.sandbox? == .read_only
	assert params.runtime_workspace_roots?.len == 0
	assert params.environments?.len == 0
	assert params.dynamic_tools?.len == 0
	assert params.selected_capability_roots?.len == 0
	assert params.ephemeral? == true
	assert params.thread_source?.source_kind == .feature
	assert params.thread_source?.feature == 'system'
	if overrides := params.config {
		assert overrides.len == 29
		mut expected_keys := ['features.apps', 'features.code_mode', 'features.code_mode_only',
			'features.context_management', 'features.current_time_reminder',
			'features.deferred_executor', 'features.enable_fanout', 'features.goals', 'features.hooks',
			'features.image_generation', 'features.memories', 'features.multi_agent',
			'features.multi_agent_v2', 'features.plugins', 'features.request_permissions_tool',
			'features.shell_snapshot', 'features.shell_tool', 'features.standalone_web_search',
			'features.token_budget', 'features.tool_suggest', 'features.unified_exec',
			'features.view_image', 'orchestrator.skills.enabled', 'skills.include_instructions',
			'token_budget.use_history_notes_extension', 'tools.experimental_request_user_input.enabled',
			'tools.update_plan.enabled', 'web_search', 'mcp_servers']
		expected_keys.sort()
		mut actual_keys := overrides.keys()
		actual_keys.sort()
		assert actual_keys == expected_keys
		for key, value in overrides {
			if key == 'mcp_servers' {
				assert value.to_string() == '{"local":{"enabled":false},"remote":{"enabled":false},"visible":{"enabled":false}}'
			} else if key == 'web_search' {
				assert value.to_string() == '"disabled"'
			} else {
				assert value.to_string() == 'false'
			}
		}
	} else {
		assert false
	}
}

fn test_config_read_fails_closed_and_keeps_typed_error() {
	handle := fixture_handle(none, serde_json.Value.object({}), 'config/read', .server)
	start_temporary_thread(&handle, TemporaryStructuredThreadOptions{ model: 'gpt-5.2', cwd: '/tmp' }) or {
		assert err is codex_app_server_client.TypedRequestError
		assert err.msg() == 'config/read failed: fixture server failure (code -32603)'
		assert handle.structured_fixture_requests().len == 1
		assert (*handle.structured_fixture_requests())[0] is codex_app_server_protocol.ClientRequestConfigRead
		return
	}
	assert false
}

fn test_custom_profile_and_read_only_postconditions_fail_closed() {
	for profile in ['unexpected', ''] {
		handle := fixture_handle(if profile.len > 0 {
			?string(profile.clone())
		} else {
			?string(none)
		}, serde_json.Value.object({}), '', none)
		start_temporary_thread(&handle, TemporaryStructuredThreadOptions{ active_permission_profile: 'expected' }) or {
			assert err.msg() == 'temporary structured thread did not preserve permission profile expected'
			continue
		}
		assert false
	}
	handle := codex_app_server_client.AppServerRequestHandle.temporary_structured_fixture(codex_app_server_protocol.ConfigReadResponse{}, none, codex_protocol.SandboxPolicy{ policy_kind: .workspace_write }, '', none, 0)
	start_temporary_thread(&handle, TemporaryStructuredThreadOptions{}) or {
		assert err.msg() == 'temporary structured thread did not start with read-only permissions'
		return
	}
	assert false
}

fn test_borrowed_turn_id_helpers_reuse_allocated_owners_and_accept_exact_byte_limit() {
	turn_literal := 'turn-1'
	text_literal := 'owned response'
	turn := owned(&turn_literal)
	text := owned(&text_literal)
	for _ in 0 .. 2 {
		sender, receiver := mpsc.unbounded_notifications_channel()
		sender.send(agent_message_notification(&turn, &text)) or { panic(err) }
		sender.send(turn_completed_notification(&turn, .completed)) or { panic(err) }
		assert collect_structured_response(receiver, &turn) or { panic(err) } == text
		sender.close()
	}
	assert turn == 'turn-1'
	assert text == 'owned response'
	sender, receiver := mpsc.unbounded_notifications_channel()
	limit := '界'.repeat(2730) + 'xx'
	assert limit.len == 8192
	sender.send(agent_message_notification(&turn, &limit)) or { panic(err) }
	sender.send(turn_completed_notification(&turn, .completed)) or { panic(err) }
	assert collect_structured_response(receiver, &turn) or { panic(err) } == limit
	sender.close()
}

fn test_run_preserves_settings_and_unsubscribes_on_success_and_collection_error() {
	for status in [codex_app_server_protocol.TurnStatus.completed,
		codex_app_server_protocol.TurnStatus.failed] {
		handle := fixture_handle(none, serde_json.Value.object({}), '', none)
		observer := handle.clone()
		turn_sender, turn_receiver := mpsc.unbounded_notifications_channel()
		turn := 'turn-1'
		message := 'structured'
		turn_sender.send(agent_message_notification(&turn, &message)) or { panic(err) }
		turn_sender.send(turn_completed_notification(&turn, status)) or { panic(err) }
		schema_text := '{"type":"object"}'
		if value := run_temporary_structured_turn(handle, 'thread-1', 'prompt', serde_json.from_str(&schema_text) or { panic(err) }, openai_models.ReasoningEffort.high, turn_receiver) {
			assert status == .completed
			assert value == message
		} else {
			assert status == .failed
			assert err.msg() == 'temporary structured turn ended with status Failed'
		}
		turn_sender.close()
		requests := observer.structured_fixture_requests()
		assert requests.len == 2
		assert (*requests)[0] is codex_app_server_protocol.ClientRequestTurnStart
		assert (*requests)[1] is codex_app_server_protocol.ClientRequestThreadUnsubscribe
		start := (*requests)[0] as codex_app_server_protocol.ClientRequestTurnStart
		assert start.params.thread_id == 'thread-1'
		assert start.params.effort? == .high
		if schema := start.params.output_schema {
			actual_schema := schema.to_string()
			assert actual_schema == '{"type":"object"}', 'recorded structured schema: ${actual_schema}'
		} else {
			assert false, 'structured schema was omitted'
		}
		assert start.params.model == none
		assert start.params.cwd == none
		assert start.params.permissions == none
		assert start.params.approval_policy == none
		assert start.params.sandbox_policy == none
		input := start.params.input[0] as codex_app_server_protocol.UserInputText
		assert input.text == 'prompt'
		assert input.text_elements.len == 0
		cleanup := (*requests)[1] as codex_app_server_protocol.ClientRequestThreadUnsubscribe
		assert cleanup.params.thread_id == 'thread-1'
	}
}

fn test_owned_timeout_distinguishes_original_error_from_elapsed_and_transfers_owned_payload() {
	value_literal := 'owned payload'
	value := owned(&value_literal)
	assert tokio_time.timeout_owned[string, string](i64(time.second), value, fn (payload string) !string {
		return payload
	}) or { panic(err) } == 'owned payload'
	tokio_time.timeout_owned[string, int](i64(time.second), 0, fn (_ int) !string {
		return error('operation timed out')
	}) or {
		assert !(err is tokio_time.Elapsed)
		assert err.msg() == 'operation timed out'
	}
	completion := chan bool{cap: 1}
	tokio_time.timeout_owned[string, CompletionChannel](i64(20 * time.millisecond), CompletionChannel{ channel: completion }, fn (finished CompletionChannel) !string {
		time.sleep(80 * time.millisecond)
		finished.channel <- true
		return 'late'
	}) or {
		assert err is tokio_time.Elapsed
		assert <-completion
		return
	}
	assert false
}

struct CompletionChannel {
	channel chan bool
}

fn test_run_unsubscribes_after_start_error_and_does_not_replace_success_with_cleanup_error() {
	for failure_method in ['turn/start', 'thread/unsubscribe'] {
		handle := fixture_handle(none, serde_json.Value.object({}), failure_method.clone(), .transport)
		observer := handle.clone()
		cleanup_sender, cleanup_receiver := mpsc.unbounded_notifications_channel()
		turn_id := 'turn-1'
		message := 'result survives cleanup failure'
		cleanup_sender.send(agent_message_notification(&turn_id, &message)) or { panic(err) }
		cleanup_sender.send(turn_completed_notification(&turn_id, .completed)) or { panic(err) }
		if result := run_temporary_structured_turn(handle, 'thread-1', 'prompt', serde_json.Value.object({}), none, cleanup_receiver) {
			assert failure_method == 'thread/unsubscribe'
			assert result == message
		} else {
			assert failure_method == 'turn/start'
			assert err is codex_app_server_client.TypedRequestError
			assert err.msg() == 'turn/start transport error: fixture transport failure'
		}
		requests := observer.structured_fixture_requests()
		assert requests.len == 2
		assert (*requests)[0] is codex_app_server_protocol.ClientRequestTurnStart
		assert (*requests)[1] is codex_app_server_protocol.ClientRequestThreadUnsubscribe
		cleanup_sender.send(turn_completed_notification(&turn_id, .completed)) or {
			assert err.msg() == 'channel closed'
			cleanup_sender.close()
			continue
		}
		assert false, 'the timed future retained its receiver after completion'
	}
}

struct CollectOperation {
	receiver   mpsc.NotificationReceiver
	turn_id    string
	completion chan bool
}

fn timed_collection(operation CollectOperation) !string {
	collect_structured_response(operation.receiver, &operation.turn_id) or {
		operation.completion <- true
		return err
	}
	operation.completion <- true
	return 'unexpected response'
}

fn assert_sender_closed(sender &mpsc.NotificationSender, turn_id &string) {
	// V's nested `or` error binding can retain the outer timeout's error. Keep
	// this independent operation's assertion in its own scope.
	sender.send(turn_completed_notification(turn_id, .completed)) or {
		assert err.msg() == 'channel closed'
		return
	}
	assert false, 'cancellation did not close the receiver'
}

fn test_timeout_cancellation_closes_notification_worker_and_releases_owned_receiver() {
	deadline_sender, deadline_receiver := mpsc.unbounded_notifications_channel()
	cancellation := deadline_receiver.cancellation_handle()
	completion := chan bool{cap: 1}
	turn_id_literal := 'turn-1'
	tokio_time.timeout_owned[string, CollectOperation](i64(20 * time.millisecond), CollectOperation{
		receiver:   deadline_receiver
		turn_id:    owned(&turn_id_literal)
		completion: completion
	}, timed_collection) or {
		assert err is tokio_time.Elapsed
		cancellation.cancel()
		assert <-completion
		assert_sender_closed(&deadline_sender, &turn_id_literal)
		deadline_sender.close()
		return
	}
	assert false, 'the open channel should exceed the bounded receive deadline'
}
