module codex_app_server_client

import codex_app_server_protocol
import serde_json
import sync

// STUB: a null JSON-RPC response in the source socket test never completes.
pub struct PermissionNoReply {}

// STUB: strictly typed scripted WebSocket replies at the untranslated transport
// boundary; target code still issues the individual request_typed RPC APIs.
pub type PermissionDiscoveryReply = PermissionNoReply
	| codex_app_server_protocol.ConfigReadResponse
	| codex_app_server_protocol.ConfigRequirementsReadResponse
	| codex_app_server_protocol.PermissionProfileListResponse
	| codex_app_server_protocol.JSONRPCErrorError

// STUB: shared remote request bookkeeping; fixed IDs stay pending when their
// reply is abandoned, so later attempts report the same duplicate-ID failure.
@[heap]
struct PermissionDiscoveryFixture {
	mutex           &sync.Mutex = sync.new_mutex()
	replies         []PermissionDiscoveryReply
	shutdown_signal chan bool = chan bool{cap: 1}
mut:
	requests       []codex_app_server_protocol.ClientRequest
	response_index int
	pending        map[string]bool
	shutdown       bool
}

// STUB: source-shaped shared request transport fixture, retaining owned replies.
pub fn AppServerRequestHandle.permission_discovery_fixture(replies []PermissionDiscoveryReply) AppServerRequestHandle {
	return AppServerRequestHandle{ permission_fixture: &PermissionDiscoveryFixture{ replies: replies } }
}

// STUB: wire serialization creates a fresh server-owned request independent of
// the client worker's captures. Only discovery's actual RPC payloads are accepted.
fn clone_permission_request(request &codex_app_server_protocol.ClientRequest) codex_app_server_protocol.ClientRequest {
	match request {
		codex_app_server_protocol.ClientRequestConfigRead {
			return codex_app_server_protocol.ClientRequestConfigRead{
				request_id: request.request_id.clone()
				params:     codex_app_server_protocol.ConfigReadParams{
					include_layers: request.params.include_layers
					cwd:            if cwd := request.params.cwd {
						cwd.clone()
					} else {
						none
					}
				}
			}
		}
		codex_app_server_protocol.ClientRequestConfigRequirementsRead {
			return codex_app_server_protocol.ClientRequestConfigRequirementsRead{ request_id: request.request_id.clone(), params: request.params }
		}
		codex_app_server_protocol.ClientRequestPermissionProfileList {
			return codex_app_server_protocol.ClientRequestPermissionProfileList{
				request_id: request.request_id.clone()
				params:     codex_app_server_protocol.PermissionProfileListParams{
					cursor: if cursor := request.params.cursor {
						cursor.clone()
					} else {
						none
					}
					limit:  request.params.limit
					cwd:    if cwd := request.params.cwd {
						cwd.clone()
					} else {
						none
					}
				}
			}
		}
		else { panic('unexpected permission fixture request') }
	}
}

// STUB: source-shaped transport completion preserves transport/server/decode
// error distinctions and prevents duplicate IDs from reaching the server.
fn (handle &AppServerRequestHandle) permission_reply(request codex_app_server_protocol.ClientRequest, method &string) !PermissionDiscoveryReply {
	id := permission_request_id(&request).string_value.clone()
	if handle.permission_fixture == unsafe { nil } {
		return TypedRequestError{ kind: .transport, method: method.clone(), transport_source: error('app-server client is not available') }
	}
	mut fixture := handle.permission_fixture
	fixture.mutex.lock()
	if fixture.shutdown {
		fixture.mutex.unlock()
		return TypedRequestError{ kind: .transport, method: method.clone(), transport_source: error('client shutdown') }
	}
	if id in fixture.pending {
		fixture.mutex.unlock()
		return TypedRequestError{ kind: .transport, method: method.clone(), transport_source: error('duplicate request ID') }
	}
	fixture.pending[id.clone()] = true
	fixture.requests << request
	if fixture.response_index >= fixture.replies.len {
		fixture.mutex.unlock()
		return TypedRequestError{ kind: .transport, method: method.clone(), transport_source: error('unexpected discovery request') }
	}
	index := fixture.response_index
	fixture.response_index++
	response := &fixture.replies[index]
	if response is PermissionNoReply {
		fixture.mutex.unlock()
		_ := <-fixture.shutdown_signal
		return TypedRequestError{ kind: .transport, method: method.clone(), transport_source: error('client shutdown') }
	}
	fixture.pending.delete(id)
	fixture.mutex.unlock()
	return match response {
		codex_app_server_protocol.ConfigReadResponse {
			mut additional := map[string]serde_json.Value{}
			for key, value in response.config.additional {
				additional[key.clone()] = value.clone()
			}
			codex_app_server_protocol.ConfigReadResponse{ config: codex_app_server_protocol.Config{ additional: additional } }
		}
		codex_app_server_protocol.ConfigRequirementsReadResponse { response.clone() }
		codex_app_server_protocol.PermissionProfileListResponse {
			mut profiles := []codex_app_server_protocol.PermissionProfileSummary{cap: response.data.len}
			for i in 0 .. response.data.len {
				profiles << (&response.data[i]).clone()
			}
			codex_app_server_protocol.PermissionProfileListResponse{
				data:        profiles
				next_cursor: if cursor := response.next_cursor {
					cursor.clone()
				} else {
					none
				}
			}
		}
		codex_app_server_protocol.JSONRPCErrorError {
			return TypedRequestError{ kind: .server, method: method.clone(), server_source: codex_app_server_protocol.JSONRPCErrorError{ code: response.code, message: response.message.clone(), data: response.data } }
		}
		PermissionNoReply { panic('unreachable no-reply dispatch') }
	}
}

// STUB: config/read RPC, preserving its own typed request and response.
fn (handle &AppServerRequestHandle) permission_request_config_read(request codex_app_server_protocol.ClientRequestConfigRead) !codex_app_server_protocol.ConfigReadResponse {
	method := 'config/read'
	request_value := codex_app_server_protocol.ClientRequest(request)
	server_request := clone_permission_request(&request_value)
	response := handle.permission_reply(server_request, &method)!
	if response is codex_app_server_protocol.ConfigReadResponse {
		return response
	}
	return TypedRequestError{ kind: .deserialize, method: method, deserialize_source: error('invalid config/read response') }
}

// STUB: configRequirements/read RPC, preserving absent params and requirements.
fn (handle &AppServerRequestHandle) request_config_requirements_read(request codex_app_server_protocol.ClientRequestConfigRequirementsRead) !codex_app_server_protocol.ConfigRequirementsReadResponse {
	method := 'configRequirements/read'
	request_value := codex_app_server_protocol.ClientRequest(request)
	server_request := clone_permission_request(&request_value)
	response := handle.permission_reply(server_request, &method)!
	if response is codex_app_server_protocol.ConfigRequirementsReadResponse {
		return response
	}
	return TypedRequestError{ kind: .deserialize, method: method, deserialize_source: error('invalid configRequirements/read response') }
}

// STUB: permissionProfile/list RPC preserves pagination, cwd, and page limits.
fn (handle &AppServerRequestHandle) request_permission_profile_list(request codex_app_server_protocol.ClientRequestPermissionProfileList) !codex_app_server_protocol.PermissionProfileListResponse {
	method := 'permissionProfile/list'
	request_value := codex_app_server_protocol.ClientRequest(request)
	server_request := clone_permission_request(&request_value)
	response := handle.permission_reply(server_request, &method)!
	if response is codex_app_server_protocol.PermissionProfileListResponse {
		return response
	}
	return TypedRequestError{ kind: .deserialize, method: method, deserialize_source: error('invalid permissionProfile/list response') }
}

// STUB: source server task returns all observed owned request payloads on close.
pub fn (handle &AppServerRequestHandle) permission_fixture_requests() []codex_app_server_protocol.ClientRequest {
	fixture := handle.permission_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	mut requests := []codex_app_server_protocol.ClientRequest{cap: fixture.requests.len}
	for i in 0 .. fixture.requests.len {
		requests << clone_permission_request(&fixture.requests[i])
	}
	return requests
}

// STUB: exposes transport kind only for session shutdown dispatch.
pub fn (handle &AppServerRequestHandle) has_permission_fixture() bool {
	return handle.permission_fixture != unsafe { nil }
}

// STUB: session shutdown closes the scripted socket and wakes abandoned RPCs.
pub fn (handle &AppServerRequestHandle) shutdown_permission_fixture_if_present() ! {
	if !handle.has_permission_fixture() {
		return
	}
	mut fixture := handle.permission_fixture
	fixture.mutex.lock()
	if fixture.shutdown {
		fixture.mutex.unlock()
		return
	}
	fixture.shutdown = true
	fixture.mutex.unlock()
	fixture.shutdown_signal <- true
}

// STUB: borrowed fixed JSON-RPC ID lookup ends before request storage consumes it.
fn permission_request_id(request &codex_app_server_protocol.ClientRequest) &codex_app_server_protocol.RequestId {
	match request {
		codex_app_server_protocol.ClientRequestConfigRead { return &request.request_id }
		codex_app_server_protocol.ClientRequestConfigRequirementsRead { return &request.request_id }
		codex_app_server_protocol.ClientRequestPermissionProfileList { return &request.request_id }
		else { panic('unexpected discovery request') }
	}
}
