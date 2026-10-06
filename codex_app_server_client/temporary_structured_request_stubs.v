module codex_app_server_client

import codex_app_server_protocol
import codex_protocol
import serde_json
import sync
import time

// STUB: in-memory app-server transport used only by temporary structured request
// tests. Requests retain their typed payloads and source method ordering.
@[heap]
struct TemporaryStructuredFixture {
	mutex            &sync.Mutex = sync.new_mutex()
	effective_config codex_app_server_protocol.ConfigReadResponse
	profile          ?string
	sandbox          codex_protocol.SandboxPolicy
	failure_method   string
	failure_kind     ?TypedRequestErrorKind
	delay_nanos      i64
mut:
	requests []codex_app_server_protocol.ClientRequest
	shutdown bool
}

// STUB: source-shaped typed request fixture. None of the native embedded or remote
// app-server transports is implemented by this in-memory boundary.
pub fn AppServerRequestHandle.temporary_structured_fixture(effective_config codex_app_server_protocol.ConfigReadResponse, profile ?string, sandbox codex_protocol.SandboxPolicy, failure_method string, failure_kind ?TypedRequestErrorKind, delay_nanos i64) AppServerRequestHandle {
	return AppServerRequestHandle{
		structured_fixture: &TemporaryStructuredFixture{
			effective_config: effective_config
			profile:          profile
			sandbox:          sandbox
			failure_method:   failure_method
			failure_kind:     failure_kind
			delay_nanos:      delay_nanos
		}
	}
}

// STUB: transport/server/decode layers remain distinct, matching request_typed.
fn (handle &AppServerRequestHandle) structured_request_failure(method &string) ! {
	if handle.structured_fixture == unsafe { nil } {
		return TypedRequestError{ kind: .transport, method: method.clone(), transport_source: error('app-server client is not available') }
	}
	fixture := handle.structured_fixture
	if fixture.delay_nanos > 0 { time.sleep(time.Duration(fixture.delay_nanos)) }
	if fixture.failure_method == *method {
		if kind := fixture.failure_kind {
			return match kind {
				.transport {
					TypedRequestError{ kind: kind, method: method.clone(), transport_source: error('fixture transport failure') }
				}
				.server {
					TypedRequestError{ kind: kind, method: method.clone(), server_source: codex_app_server_protocol.JSONRPCErrorError{ code: -32603, message: 'fixture server failure' } }
				}
				.deserialize {
					TypedRequestError{ kind: kind, method: method.clone(), deserialize_source: error('fixture decode failure') }
				}
			}
		}
	}
}

// STUB: observe issued typed RPCs before transport/server failure, as the real
// sender does; fixture observation does not fabricate successful completion.
fn (handle &AppServerRequestHandle) record_structured_request(request codex_app_server_protocol.ClientRequest) {
	if handle.structured_fixture == unsafe { nil } {
		return
	}
	mut fixture := handle.structured_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	fixture.requests << request
}

// STUB: ConfigRead RPC reads the remote-effective config before ThreadStart.
fn (handle &AppServerRequestHandle) request_config_read(request codex_app_server_protocol.ClientRequestConfigRead) !codex_app_server_protocol.ConfigReadResponse {
	if handle.permission_fixture != unsafe { nil } {
		return handle.permission_request_config_read(request)
	}
	method := 'config/read'
	handle.record_structured_request(request)
	handle.structured_request_failure(&method)!
	mut fixture := handle.structured_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	mut additional := map[string]serde_json.Value{}
	for key, value in fixture.effective_config.config.additional {
		additional[key.clone()] = value.clone()
	}
	return codex_app_server_protocol.ConfigReadResponse{ config: codex_app_server_protocol.Config{ additional: additional } }
}

// STUB: ThreadStart returns the requested model/provider and ephemeral state,
// with the fixture's resolved sandbox/profile from the embedded config boundary.
fn (handle &AppServerRequestHandle) request_thread_start(request codex_app_server_protocol.ClientRequestThreadStart) !codex_app_server_protocol.ThreadStartResponse {
	method := 'thread/start'
	if handle.structured_fixture == unsafe { nil } { handle.structured_request_failure(&method)! }
	response := fixture_thread_start_response(handle.structured_fixture, &request.params)
	validation_error := fixture_required_mcp_error(handle.structured_fixture, &request.params)
	handle.record_structured_request(request)
	handle.structured_request_failure(&method)!
	if message := validation_error {
		return TypedRequestError{ kind: .server, method: method.clone(), server_source: codex_app_server_protocol.JSONRPCErrorError{ code: -32603, message: message } }
	}
	return response
}

// STUB: the embedded MCP startup boundary rejects a missing required command
// unless its per-thread effective override disables that server. This is the
// smallest runtime behavior required by the source's real config-file test.
fn fixture_required_mcp_error(fixture &TemporaryStructuredFixture, params &codex_app_server_protocol.ThreadStartParams) ?string {
	if 'mcp_servers' !in fixture.effective_config.config.additional {
		return none
	}
	effective := unsafe { &fixture.effective_config.config.additional['mcp_servers'] }
	names := effective.object_keys() or { return none }
	for index in 0 .. names.len {
		name := &names[index]
		server := effective.get(name)
		required_key := 'required'
		required := server.value.get(&required_key)
		if !required.has_value || !(required.value.as_bool() or { false }) {
			continue
		}
		mut disabled := false
		if overrides := params.config {
			if 'mcp_servers' in overrides {
				servers := unsafe { &overrides['mcp_servers'] }
				server_override := servers.get(name)
				if server_override.has_value {
					enabled_key := 'enabled'
					enabled := server_override.value.get(&enabled_key)
					if enabled.has_value {
						disabled = !(enabled.value.as_bool() or { true })
					}
				}
			}
		}
		if !disabled {
			return 'required MCP server ${*name} could not start'
		}
	}
	return none
}

// STUB: construct a freshly owned RPC response from borrowed request/settings.
// The short borrow ends before request_thread_start moves its request into storage.
fn fixture_thread_start_response(fixture &TemporaryStructuredFixture, params &codex_app_server_protocol.ThreadStartParams) codex_app_server_protocol.ThreadStartResponse {
	return codex_app_server_protocol.ThreadStartResponse{
		thread:                    codex_app_server_protocol.Thread{ id: 'temporary-thread', ephemeral: params.ephemeral or { false } }
		model:                     if model := params.model { model.clone() } else { '' }
		model_provider:            if provider := params.model_provider {
			provider.clone()
		} else {
			''
		}
		cwd:                       if cwd := params.cwd { cwd.clone() } else { '' }
		approval_policy:           if policy := params.approval_policy {
			codex_app_server_protocol.AskForApproval(policy)
		} else {
			codex_app_server_protocol.AskForApproval{ kind: .on_request }
		}
		sandbox:                   codex_protocol.SandboxPolicy{
			policy_kind:    fixture.sandbox.policy_kind
			network_access: fixture.sandbox.network_access
		}
		active_permission_profile: if profile := fixture.profile {
			codex_protocol.ActivePermissionProfile{ id: profile.clone() }
		} else {
			none
		}
	}
}

// STUB: TurnStart's typed result carries a stable turn id to match notifications.
fn (handle &AppServerRequestHandle) request_turn_start(request codex_app_server_protocol.ClientRequestTurnStart) !codex_app_server_protocol.TurnStartResponse {
	method := 'turn/start'
	// RPC serialization/deserialization creates server-owned values. Retaining
	// the client's nested arrays here would alias captures dropped by its future.
	server_request := fixture_decode_turn_start(&request)
	handle.record_structured_request(server_request)
	handle.structured_request_failure(&method)!
	mut fixture := handle.structured_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	return codex_app_server_protocol.TurnStartResponse{ turn: codex_app_server_protocol.Turn{ id: 'turn-1', status: .in_progress } }
}

// STUB: typed TurnStart RPC decode at the in-memory server ownership boundary.
fn fixture_decode_turn_start(request &codex_app_server_protocol.ClientRequestTurnStart) codex_app_server_protocol.ClientRequestTurnStart {
	return codex_app_server_protocol.ClientRequestTurnStart{ request_id: request.request_id.clone(), params: request.params.clone() }
}

// STUB: ThreadUnsubscribe RPC detaches this in-memory ephemeral thread.
fn (handle &AppServerRequestHandle) request_thread_unsubscribe(request codex_app_server_protocol.ClientRequestThreadUnsubscribe) !codex_app_server_protocol.ThreadUnsubscribeResponse {
	method := 'thread/unsubscribe'
	handle.record_structured_request(request)
	handle.structured_request_failure(&method)!
	mut fixture := handle.structured_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	return codex_app_server_protocol.ThreadUnsubscribeResponse{}
}

// STUB: request fixture observation returns borrowed typed requests, not a
// universal string-payload shim. Observe only when no RPC is concurrently active.
pub fn (handle &AppServerRequestHandle) structured_fixture_requests() &[]codex_app_server_protocol.ClientRequest {
	return &handle.structured_fixture.requests
}

// STUB: AppServerSession::shutdown releases the fixture's client session.
pub fn (handle &AppServerRequestHandle) structured_fixture_shutdown() ! {
	mut fixture := handle.structured_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	fixture.shutdown = true
}
