module session_queue_commands

import codex_app_server_client as client
import codex_app_server_protocol as api
import codex_arg0
import codex_tui
import codex_tui.session_archive_commands as archive
import codex_utils_absolute_path
import codex_utils_home_dir
import color_eyre.eyre
import std_io
import std_path
import strconv
import time
import uuid

struct UnsupportedCase {
	code        i64
	message     string
	unsupported bool
}

// Preserve the sibling Rust test's four server cases and separate transport case.
fn test_recognizes_only_definitively_unsupported_queue_errors() {
	for test_case in [
		UnsupportedCase{ code: jsonrpc_method_not_found, message: 'Method not found', unsupported: true },
		UnsupportedCase{ code: jsonrpc_invalid_request, message: api.experimental_required_message(&thread_queue_add_method), unsupported: true },
		UnsupportedCase{ code: jsonrpc_invalid_request, message: 'Invalid request: unknown variant `thread/queue/add`, expected `thread/list`', unsupported: true },
		UnsupportedCase{ code: jsonrpc_invalid_request, message: 'queue cannot contain more than 100 submissions', unsupported: false },
	] {
		failure := IError(eyre.Report.new(client.TypedRequestError{ kind: .server, method: thread_queue_add_method.clone(), server_source: api.JSONRPCErrorError{ code: int(test_case.code), message: test_case.message, data: api.OptionalJsonValue{} } }))
		assert is_unsupported_queue_error(&failure) == test_case.unsupported
	}
	transport_failure := IError(eyre.Report.new(client.TypedRequestError{ kind: .transport, method: thread_queue_add_method.clone(), transport_source: std_io.Error.new(.timed_out, 'request timed out') }))
	assert !is_unsupported_queue_error(&transport_failure)
}

fn server_failure(method string, code i64, message string) client.TypedRequestError {
	return client.TypedRequestError{ kind: .server, method: method, server_source: api.JSONRPCErrorError{ code: int(code), message: message } }
}

fn fixture_response(id string) api.ThreadQueueAddResponse {
	return api.ThreadQueueAddResponse{ queued_submission: api.QueuedSubmission{ id: id, input: [api.UserInput(api.UserInputText{ text: 'echoed response text' })], client_user_message_id: 'echoed-client-id' } }
}

fn queue_handle(replies []client.SessionQueueReply) client.AppServerRequestHandle {
	return client.AppServerRequestHandle{}.with_session_queue_fixture(replies)
}

fn home() codex_utils_absolute_path.AbsolutePathBuf {
	return codex_utils_absolute_path.AbsolutePathBuf{ path: '/tmp/session-queue-fixture-home' }
}

fn configure_command(handle &client.AppServerRequestHandle, embedded bool) {
	codex_utils_home_dir.configure_session_queue_home(home())
	archive.configure_session_command_startup(codex_tui.AppServerSession.session_queue_transport_fixture(handle.clone(), embedded))
	codex_tui.configure_session_queue_daemon_probe(none)
}

fn remote_options() archive.SessionArchiveCommandOptions {
	return archive.SessionArchiveCommandOptions{ cli: codex_tui.Cli{}, arg0_paths: codex_arg0.Arg0DispatchPaths{ codex_linux_sandbox_exe: '/tmp/owned-sandbox', main_execve_wrapper_exe: '/tmp/owned-wrapper' }, explicit_remote_endpoint: codex_tui.RemoteAppServerEndpoint(client.RemoteAppServerWebSocket{ websocket_url: 'ws://fixture.invalid/queue', auth_token: 'fixture-token' }) }
}

fn test_unsupported_detection_preserves_contexts_and_requires_exact_method_and_code() {
	wrapped := eyre.wrap_err(eyre.wrap_err(server_failure(thread_queue_add_method.clone(), jsonrpc_invalid_request, api.experimental_required_message(&thread_queue_add_method)), 'request context'), 'outer context')
	assert is_unsupported_queue_error(&wrapped)
	assert is_unsupported_queue_error(&wrapped)
	assert wrapped.msg() == 'outer context'
	for failure in [
		server_failure('thread/list', jsonrpc_method_not_found, 'Method not found'),
		server_failure(thread_queue_add_method.clone(), -32603, api.experimental_required_message(&thread_queue_add_method)),
		server_failure(thread_queue_add_method.clone(), jsonrpc_invalid_request, 'thread/queue/add requires experimentalApi capability '),
		server_failure(thread_queue_add_method.clone(), jsonrpc_invalid_request, 'Invalid request: unknown variant `thread/queue/list`, expected `thread/list`'),
		client.TypedRequestError{ kind: .deserialize, method: thread_queue_add_method.clone(), deserialize_source: error('invalid response') },
	] {
		dynamic_failure := IError(failure)
		assert !is_unsupported_queue_error(&dynamic_failure)
	}
	ordinary_error := IError(error('Method not found'))
	assert !is_unsupported_queue_error(&ordinary_error)
}

fn test_uuid_fastpath_preserves_payload_request_ids_responses_and_heap_owners() {
	expected_first := fixture_response('queued-first')
	expected_second := fixture_response('queued-second')
	handle := client.AppServerRequestHandle.named_session_rpc_fixture([]).with_session_queue_fixture([
		client.SessionQueueReply(expected_first.clone()),
		client.SessionQueueReply(expected_second.clone()),
	])
	mut session := codex_tui.AppServerSession.new(handle.clone(), .remote)
	mut target := '{AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE}'
	mut message := 'queue exact bytes\nПривет 🌍'
	mut client_message_id := 'caller-client-id'
	mut home_owner := '/tmp/borrowed-queue-home'
	$if ownership ? {
		target = target.to_owned()
		message = message.to_owned()
		client_message_id = client_message_id.to_owned()
		home_owner = home_owner.to_owned()
	}
	home_path := std_path.Path.new(&home_owner)
	first_id, first_response := run_session_queue_action_with_app_server(mut session, &home_path, &target, &message, &client_message_id) or { panic(err.msg()) }
	second_id, second_response := run_session_queue_action_with_app_server(mut session, &home_path, &target, &message, &client_message_id) or { panic(err.msg()) }
	assert first_id.value == 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
	assert second_id == first_id
	assert first_response == expected_first
	assert second_response == expected_second
	requests := handle.session_queue_fixture_requests()
	assert requests.len == 2
	for index in 0 .. 2 {
		assert requests[index] == api.ClientRequestThreadQueueAdd{ request_id: api.RequestId{ kind: .integer, integer: index + 1 }, params: api.ThreadQueueAddParams{ thread_id: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', input: [api.UserInput(api.UserInputText{ text: message.clone(), text_elements: []api.TextElement{} })], client_user_message_id: client_message_id.clone() } }
	}
	assert target == '{AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE}'
	assert message == 'queue exact bytes\nПривет 🌍'
	assert client_message_id == 'caller-client-id'
	assert home_owner == '/tmp/borrowed-queue-home'
	assert home_path.to_path_buf() == home_owner
	assert handle.named_session_fixture_requests() == []api.ClientRequest{}
	assert handle.session_queue_fixture_requests() == requests
}

fn test_label_lookup_checks_active_noninteractive_and_atlas_filters_without_provider() {
	label := 'Atlas planning'
	id := 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
	listed_thread := api.Thread{ id: id, name: label, preview: 'preview' }
	handle := client.AppServerRequestHandle.named_session_rpc_fixture([
		client.NamedSessionReply(api.ThreadListResponse{}),
		client.NamedSessionReply(api.ThreadListResponse{ data: [listed_thread.clone()] }),
		client.NamedSessionReply(api.ThreadReadResponse{ thread: listed_thread.clone() }),
	]).with_session_queue_fixture([client.SessionQueueReply(fixture_response('atlas-queued'))])
	mut session := codex_tui.AppServerSession.new(handle.clone(), .remote)
	home_owner := home()
	home_path := home_owner.as_path()
	message := 'next step'
	client_message_id := 'atlas-message'
	resolved_id, queued := run_session_queue_action_with_app_server(mut session, &home_path, &label, &message, &client_message_id) or { panic(err.msg()) }
	assert resolved_id.value == id
	assert queued.queued_submission.id == 'atlas-queued'
	requests := handle.named_session_fixture_requests()
	assert requests.len == 3
	for index in 0 .. 2 {
		request := &requests[index]
		assert request is api.ClientRequestThreadList
		if request is api.ClientRequestThreadList {
			assert request.request_id.integer == index + 1
			// Keep optional enum arrays qualified across V3's borrowed unwrap lowering.
			sources := if kinds := request.params.source_kinds {
				kinds
			} else {
				panic('expected explicit sourceKinds')
			}
			assert sources == if index == 0 {
				[codex_app_server_protocol.ThreadSourceKind.cli, .vscode, .exec, .app_server]
			} else {
				[]codex_app_server_protocol.ThreadSourceKind{}
			}
			assert request.params.model_providers == none
			assert (request.params.archived or { panic('expected archived=false') }) == false
			assert (request.params.limit or { panic('expected list limit') }) == u32(100)
		}
	}
	read_request := &requests[2]
	assert read_request is api.ClientRequestThreadRead
	if read_request is api.ClientRequestThreadRead {
		assert read_request.request_id.integer == 3
		assert read_request.params.thread_id == id
		assert read_request.params.include_turns == false
	}
	queue_requests := handle.session_queue_fixture_requests()
	assert queue_requests.len == 1
	assert queue_requests[0].request_id.integer == 4
	assert queue_requests[0].params.thread_id == id
}

fn test_missing_label_returns_exact_error_and_never_issues_queue_add() {
	handle := client.AppServerRequestHandle.named_session_rpc_fixture([
		client.NamedSessionReply(api.ThreadListResponse{}),
		client.NamedSessionReply(api.ThreadListResponse{}),
	]).with_session_queue_fixture([])
	mut session := codex_tui.AppServerSession.new(handle.clone(), .remote)
	home_owner := home()
	home_path := home_owner.as_path()
	target := 'missing label'
	message := 'message'
	client_message_id := 'client-id'
	if _, _ := run_session_queue_action_with_app_server(mut session, &home_path, &target, &message, &client_message_id) {
		assert false
	} else {
		assert err.msg() == "No active session found matching 'missing label'."
	}
	assert handle.session_queue_fixture_requests() == []api.ClientRequestThreadQueueAdd{}
}

fn test_home_failure_precedes_startup_and_preserves_native_error_under_context() {
	handle := queue_handle([])
	configure_command(&handle, false)
	codex_utils_home_dir.configure_session_queue_home(std_io.Error.new(.not_found, 'missing fixture home'))
	if _ := run_session_queue_command('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', 'message', remote_options()) {
		assert false
	} else {
		assert err.msg() == 'failed to find Codex home'
		cause := eyre.root_cause(&err)
		assert cause is std_io.Error
		if cause is std_io.Error {
			assert cause.kind() == .not_found
			assert cause.msg() == 'missing fixture home'
		}
	}
	assert codex_utils_home_dir.session_queue_home_calls() == 1
	assert archive.session_command_startup_calls() == 0
	assert codex_tui.session_queue_daemon_probe_calls() == 0
	assert handle.session_queue_fixture_requests() == []api.ClientRequestThreadQueueAdd{}
}

fn test_startup_failure_propagates_before_probe_or_queue() {
	handle := queue_handle([])
	configure_command(&handle, true)
	archive.configure_session_command_startup(archive.SessionCommandStartupFailure{ cause: error('fixture startup failed') })
	if _ := run_session_queue_command('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', 'message', archive.SessionArchiveCommandOptions{}) {
		assert false
	} else {
		assert err.msg() == 'fixture startup failed'
	}
	assert archive.session_command_startup_calls() == 1
	assert codex_tui.session_queue_daemon_probe_calls() == 0
	assert handle.session_queue_fixture_requests() == []api.ClientRequestThreadQueueAdd{}
}

fn test_embedded_command_refuses_a_running_default_daemon_before_queueing() {
	handle := queue_handle([])
	configure_command(&handle, true)
	codex_tui.configure_session_queue_daemon_probe(codex_utils_absolute_path.AbsolutePathBuf{ path: '/tmp/fixture-daemon.sock' })
	if _ := run_session_queue_command('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', 'message', archive.SessionArchiveCommandOptions{}) {
		assert false
	} else {
		assert err.msg() == 'cannot queue through an embedded app server while a local app-server daemon is running; remove configuration overrides or use --remote'
	}
	assert codex_tui.session_queue_daemon_probe_calls() == 1
	probe_homes := codex_tui.session_queue_daemon_probe_homes()
	assert probe_homes.len == 1
	assert (*probe_homes)[0].as_path().to_path_buf() == '/tmp/session-queue-fixture-home'
	assert archive.session_command_startup_home().as_path().to_path_buf() == '/tmp/session-queue-fixture-home'
	assert handle.session_queue_fixture_requests() == []api.ClientRequestThreadQueueAdd{}
}

fn test_remote_success_preserves_options_exact_message_and_generates_uuid_v7() {
	handle := queue_handle([client.SessionQueueReply(fixture_response('submission-42'))])
	configure_command(&handle, true)
	codex_tui.configure_session_queue_daemon_probe(codex_utils_absolute_path.AbsolutePathBuf{ path: '/tmp/fixture-daemon.sock' })
	before := time.now().unix_milli()
	result := run_session_queue_command('AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE', 'exact top-level text', remote_options()) or { panic(err.msg()) }
	after := time.now().unix_milli()
	assert result == 'Queued message submission-42 for thread aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee.'
	assert codex_tui.session_queue_daemon_probe_calls() == 0
	options := archive.session_command_startup_options()
	assert options.arg0_paths.codex_linux_sandbox_exe == '/tmp/owned-sandbox'
	assert options.arg0_paths.main_execve_wrapper_exe == '/tmp/owned-wrapper'
	if endpoint := options.explicit_remote_endpoint {
		assert endpoint is client.RemoteAppServerWebSocket
		if endpoint is client.RemoteAppServerWebSocket {
			assert endpoint.websocket_url == 'ws://fixture.invalid/queue'
			assert endpoint.auth_token or { '' } == 'fixture-token'
		}
	} else {
		assert false
	}
	requests := handle.session_queue_fixture_requests()
	assert requests.len == 1
	assert requests[0].request_id.integer == 1
	assert requests[0].params.input == [api.UserInput(api.UserInputText{ text: 'exact top-level text' })]
	client_message_id := requests[0].params.client_user_message_id.clone()
	parsed := uuid.Uuid.parse_str(&client_message_id) or { panic(err.msg()) }
	assert parsed.str() == client_message_id
	assert client_message_id[14] == `7`
	assert client_message_id[19] in [`8`, `9`, `a`, `b`]
	timestamp_text := client_message_id[..8] + client_message_id[9..13]
	timestamp := strconv.parse_uint(timestamp_text, 16, 64) or { panic(err.msg()) }
	assert timestamp >= u64(before)
	assert timestamp <= u64(after)
}

fn test_unsupported_command_errors_add_context_only_for_remote_and_daemon() {
	for server_kind in ['embedded', 'daemon', 'remote'] {
		handle := queue_handle([client.SessionQueueReply(server_failure(thread_queue_add_method.clone(), jsonrpc_method_not_found, 'Method not found'))])
		configure_command(&handle, server_kind == 'embedded')
		options := if server_kind == 'remote' {
			remote_options()
		} else {
			archive.SessionArchiveCommandOptions{}
		}
		if _ := run_session_queue_command('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', 'message', options) {
			assert false
		} else {
			expected := match server_kind {
				'embedded' { 'failed to queue session message' }
				'daemon' {
					'the local app-server daemon does not support thread/queue/add; update or restart the local app-server daemon'
				}
				else {
					'the remote app server does not support thread/queue/add; update or restart the remote app server'
				}
			}
			assert err.msg() == expected
			assert is_unsupported_queue_error(&err)
			cause := eyre.root_cause(&err)
			assert cause is client.TypedRequestError
			if cause is client.TypedRequestError {
				assert cause.server_source.message == 'Method not found'
				assert cause.server_source.code == -32601
			}
		}
		assert handle.session_queue_fixture_requests().len == 1
		assert codex_tui.session_queue_daemon_probe_calls() == if server_kind == 'embedded' {
			1
		} else {
			0
		}
	}
}

fn test_other_remote_queue_errors_keep_the_action_context() {
	mut failures := [
		server_failure(thread_queue_add_method.clone(), jsonrpc_invalid_request, 'queue cannot contain more than 100 submissions'),
		server_failure('thread/list', jsonrpc_method_not_found, 'Method not found'),
		client.TypedRequestError{ kind: .transport, method: thread_queue_add_method.clone(), transport_source: std_io.Error.new(.timed_out, 'request timed out') },
	]
	// Consume each error in source order. V's owned for-in inserts an error
	// clone, which cannot retain arbitrary concrete transport error causes.
	failures.reverse_in_place()
	for failures.len > 0 {
		failure := failures.pop()
		handle := queue_handle([client.SessionQueueReply(failure)])
		configure_command(&handle, false)
		if _ := run_session_queue_command('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', 'message', remote_options()) {
			assert false
		} else {
			assert err.msg() == 'failed to queue session message'
			assert !is_unsupported_queue_error(&err)
			cause := eyre.root_cause(&err)
			if cause is client.TypedRequestError {
				if cause.kind == .transport {
					native_cause := &cause.transport_source
					assert native_cause is std_io.Error
					if native_cause is std_io.Error {
						assert native_cause.kind() == .timed_out
						assert native_cause.msg() == 'request timed out'
					}
				}
			} else {
				assert false
			}
		}
	}
}

fn test_embedded_and_daemon_success_follow_their_exact_probe_paths() {
	for embedded in [true, false] {
		handle := queue_handle([client.SessionQueueReply(fixture_response('local-submission'))])
		configure_command(&handle, embedded)
		result := run_session_queue_command('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', 'local message', archive.SessionArchiveCommandOptions{}) or { panic(err.msg()) }
		assert result == 'Queued message local-submission for thread aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee.'
		assert codex_tui.session_queue_daemon_probe_calls() == if embedded { 1 } else { 0 }
		assert handle.session_queue_fixture_requests().len == 1
	}
}

fn test_invalid_listed_session_id_propagates_context_without_queueing() {
	label := 'broken label'
	handle := client.AppServerRequestHandle.named_session_rpc_fixture([
		client.NamedSessionReply(api.ThreadListResponse{ data: [api.Thread{ id: 'invalid-id', name: label }] }),
	]).with_session_queue_fixture([])
	mut session := codex_tui.AppServerSession.new(handle.clone(), .remote)
	home_owner := home()
	home_path := home_owner.as_path()
	message := 'message'
	client_message_id := 'client-id'
	if _, _ := run_session_queue_action_with_app_server(mut session, &home_path, &label, &message, &client_message_id) {
		assert false
	} else {
		assert err.msg() == 'app server returned invalid session id `invalid-id`'
		cause := eyre.root_cause(&err)
		assert cause.msg().contains('invalid UUID')
	}
	assert handle.session_queue_fixture_requests() == []api.ClientRequestThreadQueueAdd{}
}

fn test_label_list_failure_preserves_the_typed_transport_cause() {
	label := 'unavailable label'
	handle := client.AppServerRequestHandle.named_session_rpc_fixture([
		client.NamedSessionReply(client.TypedRequestError{ kind: .transport, method: 'thread/list', transport_source: error('fixture disconnected') }),
	]).with_session_queue_fixture([])
	mut session := codex_tui.AppServerSession.new(handle.clone(), .remote)
	home_owner := home()
	home_path := home_owner.as_path()
	message := 'message'
	client_message_id := 'client-id'
	if _, _ := run_session_queue_action_with_app_server(mut session, &home_path, &label, &message, &client_message_id) {
		assert false
	} else {
		assert err.msg() == 'failed to list sessions while resolving session label'
		cause := eyre.root_cause(&err)
		assert cause is client.TypedRequestError
		if cause is client.TypedRequestError {
			assert cause.kind == .transport
			assert cause.method == 'thread/list'
			transport_cause := &cause.transport_source
			assert transport_cause.msg() == 'fixture disconnected'
		}
	}
	assert handle.session_queue_fixture_requests() == []api.ClientRequestThreadQueueAdd{}
}
