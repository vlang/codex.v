module codex_app_server_client

import codex_app_server_protocol
import codex_protocol
import codex_state.model
import json2
import os
import serde_json
import sync

// STUB: strictly typed server replies used where the Rust tests launch a legacy
// WebSocket server. Transport, decode, and server failures retain distinct types.
pub type NamedSessionReply = codex_app_server_protocol.ThreadListResponse
	| codex_app_server_protocol.ThreadReadResponse
	| TypedRequestError

// STUB: TypedRequestError's owned clone at the fixture server/client boundary.
pub fn (failure &TypedRequestError) clone() TypedRequestError {
	return TypedRequestError{ kind: failure.kind, method: failure.method.clone(), transport_source: error(failure.transport_source.msg()), server_source: codex_app_server_protocol.JSONRPCErrorError{ code: failure.server_source.code, message: failure.server_source.message.clone(), data: codex_app_server_protocol.OptionalJsonValue{ has_value: failure.server_source.data.has_value, value: clone_named_session_json(&failure.server_source.data.value) } }, deserialize_source: error(failure.deserialize_source.msg()) }
}

// STUB: server recency sorting unwraps the optional timestamp without ownership.
fn named_session_recency_compare(left &codex_app_server_protocol.Thread, right &codex_app_server_protocol.Thread) int {
	left_time := left.recency_at or { left.updated_at }
	right_time := right.recency_at or { right.updated_at }
	return if left_time > right_time {
		-1
	} else if left_time < right_time {
		1
	} else {
		0
	}
}

// STUB: derived clone of structured JSON-RPC error data preserves its real tree.
fn clone_named_session_json(value &json2.Any) json2.Any {
	match value {
		string { return value.clone() }
		[]json2.Any {
			mut result := []json2.Any{cap: value.len}
			for index in 0 .. value.len {
				result << clone_named_session_json(&value[index])
			}
			return result
		}
		map[string]json2.Any {
			mut result := map[string]json2.Any{}
			for key, item in value {
				result[key.clone()] = clone_named_session_json(&item)
			}
			return result
		}
		else { return *value }
	}
}

// STUB: shared typed list/read fixture; live WebSocket and embedded server runtimes
// are untranslated. Every RPC keeps its complete params and integer request ID.
@[heap]
struct NamedSessionFixture {
	embedded          bool
	default_provider  string
	metadata          []model.ThreadMetadata
	replies           []NamedSessionReply
	scripted          bool
	initialize_result serde_json.Value
mut:
	mutex      &sync.Mutex = sync.new_mutex()
	requests   []codex_app_server_protocol.ClientRequest
	next_reply int
	shutdown   bool
}

// STUB: embedded fixture uses real metadata rows upserted by the source-shaped tests.
pub fn AppServerRequestHandle.named_session_state_fixture(metadata []model.ThreadMetadata, default_provider string, embedded bool) AppServerRequestHandle {
	return AppServerRequestHandle{ named_session_fixture: &NamedSessionFixture{ metadata: metadata, default_provider: default_provider, embedded: embedded } }
}

// STUB: scripted legacy server replaces socket IO while retaining actual replies.
pub fn AppServerRequestHandle.named_session_rpc_fixture(replies []NamedSessionReply) AppServerRequestHandle {
	return AppServerRequestHandle{ named_session_fixture: &NamedSessionFixture{ replies: replies, scripted: true } }
}

// STUB: the source legacy socket's raw initialize result is retained separately
// from its typed thread/list and thread/read replies, as the remote client does.
pub fn AppServerRequestHandle.named_session_remote_rpc_fixture(initialize_result serde_json.Value, replies []NamedSessionReply) AppServerRequestHandle {
	return AppServerRequestHandle{ named_session_fixture: &NamedSessionFixture{ initialize_result: initialize_result, replies: replies, scripted: true } }
}

// STUB: clone individual list/read request payloads as wire serialization does.
fn clone_named_session_request(request &codex_app_server_protocol.ClientRequest) codex_app_server_protocol.ClientRequest {
	match request {
		codex_app_server_protocol.ClientRequestThreadList {
			return codex_app_server_protocol.ClientRequestThreadList{ request_id: request.request_id.clone(), params: request.params.clone() }
		}
		codex_app_server_protocol.ClientRequestThreadRead {
			return codex_app_server_protocol.ClientRequestThreadRead{ request_id: request.request_id.clone(), params: codex_app_server_protocol.ThreadReadParams{ thread_id: request.params.thread_id.clone(), include_turns: request.params.include_turns } }
		}
		else { panic('unexpected named-session fixture request') }
	}
}

// STUB: owned thread projection of the canonical state model for server listing.
fn named_session_listed_thread(metadata &model.ThreadMetadata) codex_app_server_protocol.Thread {
	return codex_app_server_protocol.Thread{
		id:             metadata.id.value.clone()
		session_id:     metadata.id.value.clone()
		name:           metadata.title.clone()
		preview:        if metadata.preview.has_value {
			metadata.preview.value.clone()
		} else {
			''
		}
		history_mode:   if metadata.history_mode == .legacy { .legacy } else { .paginated }
		model_provider: metadata.model_provider.clone()
		created_at:     metadata.created_at.unix()
		updated_at:     metadata.updated_at.unix()
		recency_at:     metadata.recency_at.unix()
		path:           metadata.rollout_path.clone()
		cwd:            metadata.cwd.clone()
		cli_version:    metadata.cli_version.clone()
		source:         codex_protocol.SessionSource{
			source_kind: match metadata.source {
				'cli' { .cli }
				'vscode' { .vscode }
				'exec' { .exec }
				else { .custom }
			}
			custom:      if metadata.source !in ['cli', 'vscode', 'exec'] {
				metadata.source.clone()
			} else {
				''
			}
		}
	}
}

// STUB: typed source-kind projection used only by the server list filter boundary.
fn named_session_source_kind(source &string) codex_app_server_protocol.ThreadSourceKind {
	return match *source {
		'cli' { .cli }
		'vscode' { .vscode }
		'exec' { .exec }
		'app-server' { .app_server }
		else { .unknown }
	}
}

// STUB: thread/list fixture filters providers and sources, archives, and sorts
// before pagination. The omitted provider retains the server config's default.
fn (handle &AppServerRequestHandle) request_named_thread_list(request codex_app_server_protocol.ClientRequestThreadList) !codex_app_server_protocol.ThreadListResponse {
	if handle.named_session_fixture == unsafe { nil } {
		return TypedRequestError{ kind: .transport, method: 'thread/list', transport_source: error('app-server client is not available') }
	}
	mut fixture := handle.named_session_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	if fixture.shutdown {
		return TypedRequestError{ kind: .transport, method: 'thread/list', transport_source: error('client shutdown') }
	}
	request_value := codex_app_server_protocol.ClientRequest(codex_app_server_protocol.ClientRequestThreadList{ request_id: request.request_id.clone(), params: request.params.clone() })
	fixture.requests << clone_named_session_request(&request_value)
	if fixture.scripted {
		if fixture.next_reply >= fixture.replies.len {
			return error('unexpected thread/list request')
		}
		response := &fixture.replies[fixture.next_reply]
		fixture.next_reply++
		if response is TypedRequestError {
			return response.clone()
		}
		if response is codex_app_server_protocol.ThreadListResponse {
			mut data := []codex_app_server_protocol.Thread{cap: response.data.len}
			for index in 0 .. response.data.len {
				data << (&response.data[index]).clone()
			}
			return codex_app_server_protocol.ThreadListResponse{
				data:             data
				next_cursor:      if cursor := response.next_cursor {
					cursor.clone()
				} else {
					none
				}
				backwards_cursor: if cursor := response.backwards_cursor {
					cursor.clone()
				} else {
					none
				}
			}
		}
		return TypedRequestError{ kind: .deserialize, method: 'thread/list', deserialize_source: error('invalid thread/list response') }
	}
	params := &request.params
	mut rows := []codex_app_server_protocol.Thread{}
	for index in 0 .. fixture.metadata.len {
		metadata := &fixture.metadata[index]
		if metadata.archived_at.has_value != (params.archived or { false }) {
			continue
		}
		if providers := params.model_providers {
			if providers.len > 0 && metadata.model_provider !in providers {
				continue
			}
		} else if metadata.model_provider != fixture.default_provider {
			continue
		}
		kind := named_session_source_kind(&metadata.source)
		if sources := params.source_kinds {
			if (sources.len > 0 && kind !in sources) || (sources.len == 0 && kind !in [
				.cli,
				.vscode,
			]) {
				continue
			}
		} else if kind !in [.cli, .vscode] {
			continue
		}
		rows << named_session_listed_thread(metadata)
	}
	key := if sort_key := params.sort_key {
		sort_key
	} else {
		codex_app_server_protocol.ThreadSortKey.created_at
	}
	if key == .recency_at {
		rows.sort_with_compare(named_session_recency_compare)
	} else if key == .updated_at {
		rows.sort(a.updated_at > b.updated_at)
	} else {
		rows.sort(a.created_at > b.created_at)
	}
	direction := if sort_direction := params.sort_direction {
		sort_direction
	} else {
		codex_app_server_protocol.SortDirection.desc
	}
	if direction == codex_app_server_protocol.SortDirection.asc {
		rows.reverse_in_place()
	}
	start := if cursor := params.cursor { cursor.int() } else { 0 }
	limit := int(params.limit or { u32(100) })
	end := if start + limit < rows.len { start + limit } else { rows.len }
	mut data := []codex_app_server_protocol.Thread{cap: end - start}
	for index in start .. end {
		data << unsafe { (&rows[index]).clone() }
	}
	return codex_app_server_protocol.ThreadListResponse{
		data:        data
		next_cursor: if end < rows.len {
			?string(end.str())
		} else {
			?string(none)
		}
	}
}

// STUB: thread/read fixture validates the persisted session header against its
// listed ID, matching stale/corrupt/mismatched error messages used by lookup.
fn (handle &AppServerRequestHandle) request_named_thread_read(request codex_app_server_protocol.ClientRequestThreadRead) !codex_app_server_protocol.ThreadReadResponse {
	if handle.named_session_fixture == unsafe { nil } {
		return TypedRequestError{ kind: .transport, method: 'thread/read', transport_source: error('app-server client is not available') }
	}
	mut fixture := handle.named_session_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	if fixture.shutdown {
		return TypedRequestError{ kind: .transport, method: 'thread/read', transport_source: error('client shutdown') }
	}
	id := request.params.thread_id.clone()
	fixture.requests << codex_app_server_protocol.ClientRequestThreadRead{ request_id: request.request_id, params: request.params }
	if fixture.scripted {
		if fixture.next_reply >= fixture.replies.len {
			return error('unexpected thread/read request')
		}
		response := &fixture.replies[fixture.next_reply]
		fixture.next_reply++
		if response is TypedRequestError {
			return response.clone()
		}
		if response is codex_app_server_protocol.ThreadReadResponse {
			return codex_app_server_protocol.ThreadReadResponse{ thread: response.thread.clone() }
		}
		return TypedRequestError{ kind: .deserialize, method: 'thread/read', deserialize_source: error('invalid thread/read response') }
	}
	for index in 0 .. fixture.metadata.len {
		metadata := &fixture.metadata[index]
		if metadata.id.value != id {
			continue
		}
		contents := os.read_file(metadata.rollout_path) or { return TypedRequestError{ kind: .server, method: 'thread/read', server_source: codex_app_server_protocol.JSONRPCErrorError{ code: -32603, message: 'failed to read thread: thread-store internal error: failed to read session metadata ${metadata.rollout_path}: ${err.msg()}' } } }
		header := json2.decode[json2.Any](contents.split_into_lines()[0]) or { return TypedRequestError{ kind: .server, method: 'thread/read', server_source: codex_app_server_protocol.JSONRPCErrorError{ code: -32603, message: 'failed to read thread: thread-store internal error: failed to read session metadata ${metadata.rollout_path}: ${err.msg()}' } } }
		payload := header.as_map()['payload'] or { json2.Any(map[string]json2.Any{}) }
		actual_id := (payload.as_map()['id'] or { json2.Any('') }).str()
		if actual_id != id {
			return TypedRequestError{ kind: .server, method: 'thread/read', server_source: codex_app_server_protocol.JSONRPCErrorError{ code: -32603, message: 'failed to read thread: thread-store internal error: session metadata ${metadata.rollout_path} belongs to thread ${actual_id}, expected ${id}' } }
		}
		return codex_app_server_protocol.ThreadReadResponse{ thread: named_session_listed_thread(metadata) }
	}
	return TypedRequestError{ kind: .server, method: 'thread/read', server_source: codex_app_server_protocol.JSONRPCErrorError{ code: -32603, message: 'thread not loaded: ${id}' } }
}

// STUB: observe complete requests without exposing mutable fixture fields.
pub fn (handle &AppServerRequestHandle) named_session_fixture_requests() []codex_app_server_protocol.ClientRequest {
	fixture := handle.named_session_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	mut requests := []codex_app_server_protocol.ClientRequest{cap: fixture.requests.len}
	for index in 0 .. fixture.requests.len {
		requests << clone_named_session_request(&fixture.requests[index])
	}
	return requests
}

// STUB: transport identity required by AppServerSession::uses_embedded_app_server.
pub fn (handle &AppServerRequestHandle) named_session_fixture_is_embedded() bool {
	return handle.named_session_fixture != unsafe { nil } && handle.named_session_fixture.embedded
}

// STUB: fixture dispatch predicate for canonical session shutdown.
pub fn (handle &AppServerRequestHandle) has_named_session_fixture() bool {
	return handle.named_session_fixture != unsafe { nil }
}

// STUB: AppServerClient::shutdown closes the shared fixture transport.
pub fn (handle &AppServerRequestHandle) named_session_fixture_shutdown() ! {
	mut fixture := handle.named_session_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	fixture.shutdown = true
}

// STUB: app-server-client/src/remote.rs::RemoteAppServerConnectArgs.
pub struct RemoteAppServerConnectArgs {
pub:
	endpoint                           RemoteAppServerEndpoint
	client_name                        string
	client_version                     string
	experimental_api                   bool
	mcp_server_openai_form_elicitation bool
	opt_out_notification_methods       []string
	channel_capacity                   usize
}

// STUB: remote client owns a shared request handle; native WebSocket handshake,
// initialization, and transport threads remain outside this typed fixture boundary.
pub struct RemoteAppServerClient {
	handle AppServerRequestHandle
}

// STUB: remote endpoint binding is a fixture-only replacement for the source
// test's localhost listener and server task. initialize is completed on connect.
@[heap]
struct NamedSessionEndpointRegistry {
mut:
	mutex     &sync.Mutex = sync.new_mutex()
	endpoints map[string]AppServerRequestHandle
}

// STUB: remote test endpoints, isolated by each test's generated URL.
const named_session_endpoint_registry = &NamedSessionEndpointRegistry{}

// STUB: bind the source test's typed legacy replies to its temporary endpoint.
pub fn bind_named_session_fixture_endpoint(url string, handle AppServerRequestHandle) {
	unsafe {
		mut registry := named_session_endpoint_registry
		registry.mutex.lock()
		defer { registry.mutex.unlock() }
		registry.endpoints[url] = handle
	}
}

// STUB: RemoteAppServerClient::connect validates and consumes all source connect
// args while connecting only explicitly registered test endpoints.
pub fn RemoteAppServerClient.connect(args RemoteAppServerConnectArgs) !RemoteAppServerClient {
	if args.client_name != 'legacy-test' || args.client_version != '0.0.0' || !args.experimental_api || args.mcp_server_openai_form_elicitation || args.opt_out_notification_methods.len != 0 || args.channel_capacity != 8 {
		return error('invalid legacy fixture initialize params')
	}
	if args.endpoint is RemoteAppServerWebSocket {
		if args.endpoint.auth_token != none {
			return error('legacy fixture does not use auth')
		}
		registry := named_session_endpoint_registry
		registry.mutex.lock()
		defer { registry.mutex.unlock() }
		handle := registry.endpoints[args.endpoint.websocket_url] or { return error('native WebSocket transport is untranslated') }
		user_agent_key := 'userAgent'
		user_agent := handle.named_session_fixture.initialize_result.get(&user_agent_key)
		if !user_agent.has_value || !user_agent.value.is_string() {
			return error('invalid legacy fixture initialize result')
		}
		return RemoteAppServerClient{ handle: handle.clone() }
	}
	return error('native remote transport is untranslated')
}

// STUB: remote client request_handle clones the shared request sender.
pub fn (client &RemoteAppServerClient) request_handle() AppServerRequestHandle {
	return client.handle.clone()
}
