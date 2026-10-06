module codex_app_server_client

import codex_app_server_protocol as api
import sync
import time

// STUB: the distinct app-server-client::TypedRequestError layers, for fixture failures.
pub enum TypedRequestErrorKind {
	transport
	server
	deserialize
}

// STUB: app-server-client::TypedRequestError's tagged payloads. V IError retains
// native IO/serde error boundaries until their Rust equivalents are ported; the
// existing typed JSON-RPC error owner preserves server message, code, and data.
pub struct TypedRequestError {
pub:
	kind               TypedRequestErrorKind
	method             string
	transport_source   IError = error('')
	server_source      api.JSONRPCErrorError
	deserialize_source IError = error('')
}

// STUB: TypedRequestError's Display operation at the typed request boundary.
pub fn (failure &TypedRequestError) msg() string {
	return match failure.kind {
		.transport { '${failure.method} transport error: ${failure.transport_source.msg()}' }
		.server {
			message := '${failure.method} failed: ${failure.server_source.message} (code ${failure.server_source.code})'
			if failure.server_source.data.has_value {
				'${message}, data: ${failure.server_source.data.value.json_str()}'
			} else {
				message
			}
		}
		.deserialize {
			'${failure.method} response decode error: ${failure.deserialize_source.msg()}'
		}
	}
}

// STUB: V IError compatibility for app-server-client::TypedRequestError.
pub fn (failure &TypedRequestError) code() int {
	return int(failure.kind)
}

// STUB: an in-memory typed response boundary behind AppServerRequestHandle's real
// request_typed API. Mutex storage emulates the shared request handle, not a transport.
@[heap]
struct CollaborationModeFixture {
	mutex       &sync.Mutex = sync.new_mutex()
	response    api.CollaborationModeListResponse
	delay_nanos i64
	failure     ?TypedRequestErrorKind
mut:
	request_ids []string
	completed   int
}

// STUB: injectable collaboration-list transport fixture. No native transport is
// implied; the default handle continues to report unavailable transport.
pub fn AppServerRequestHandle.collaboration_modes_fixture(response api.CollaborationModeListResponse, delay_nanos i64, failure ?TypedRequestErrorKind) AppServerRequestHandle {
	return AppServerRequestHandle{
		collaboration_fixture: &CollaborationModeFixture{
			response:    response
			delay_nanos: delay_nanos
			failure:     failure
		}
	}
}

// STUB: the request handle's derived Clone shares its underlying sender/state,
// as Rust's in-process and remote request handle variants both do.
pub fn (handle &AppServerRequestHandle) clone() AppServerRequestHandle {
	return AppServerRequestHandle{ collaboration_fixture: handle.collaboration_fixture, structured_fixture: handle.structured_fixture, permission_fixture: handle.permission_fixture, named_session_fixture: handle.named_session_fixture, daybreak_fixture: handle.daybreak_fixture, session_queue_fixture: handle.session_queue_fixture, workspace_command_fixture: handle.workspace_command_fixture, config_update_fixture: handle.config_update_fixture }
}

// STUB: typed collaborationMode/list request execution behind request_typed.
// The request is consumed, its ID recorded, and each RPC produces an owned response.
fn (handle &AppServerRequestHandle) request_collaboration_mode_list(request api.ClientRequestCollaborationModeList) !api.CollaborationModeListResponse {
	if handle.collaboration_fixture == unsafe { nil } {
		return TypedRequestError{ kind: .transport, method: 'collaborationMode/list', transport_source: error('app-server client is not available') }
	}
	mut fixture := handle.collaboration_fixture
	fixture.mutex.lock()
	fixture.request_ids << request.request_id.string_value
	fixture.mutex.unlock()
	if fixture.delay_nanos > 0 {
		time.sleep(time.Duration(fixture.delay_nanos))
	}
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	fixture.completed++
	if failure := fixture.failure {
		return match failure {
			.transport {
				TypedRequestError{ kind: failure, method: 'collaborationMode/list', transport_source: error('fixture transport failure') }
			}
			.server {
				TypedRequestError{ kind: failure, method: 'collaborationMode/list', server_source: api.JSONRPCErrorError{ code: -32603, message: 'fixture server failure' } }
			}
			.deserialize {
				TypedRequestError{ kind: failure, method: 'collaborationMode/list', deserialize_source: error('fixture decode failure') }
			}
		}
	}
	mut data := []api.CollaborationModeMask{cap: fixture.response.data.len}
	for index in 0 .. fixture.response.data.len {
		data << (&fixture.response.data[index]).clone()
	}
	return api.CollaborationModeListResponse{ data: data }
}

// STUB: fixture observation of issued IDs without exposing test-only public state.
pub fn (handle &AppServerRequestHandle) collaboration_fixture_request_ids() []string {
	if handle.collaboration_fixture == unsafe { nil } {
		return []string{}
	}
	fixture := handle.collaboration_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	return fixture.request_ids.clone()
}

// STUB: fixture observation of finished requests, including workers after timeout.
pub fn (handle &AppServerRequestHandle) collaboration_fixture_completed_requests() int {
	if handle.collaboration_fixture == unsafe { nil } {
		return 0
	}
	fixture := handle.collaboration_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	return fixture.completed
}
