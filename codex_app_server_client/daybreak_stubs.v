module codex_app_server_client

import codex_app_server_protocol as api
import sync

// STUB: explicit in-memory auth-status transport. Native app-server IO and server
// token refresh remain untranslated; an unconfigured handle returns an error.
@[heap]
struct DaybreakAuthStatusFixture {
	response             api.GetAuthStatusResponse
	failure              ?TypedRequestErrorKind
	block_until_released bool
	gate                 chan bool
mut:
	mutex    &sync.Mutex = sync.new_mutex()
	requests []api.ClientRequestGetAuthStatus
}

// STUB: installs the typed GetAuthStatus fixture behind the actual request API.
pub fn AppServerRequestHandle.daybreak_auth_status_fixture(response api.GetAuthStatusResponse, failure ?TypedRequestErrorKind, block_until_released bool, gate chan bool) AppServerRequestHandle {
	return AppServerRequestHandle{ daybreak_fixture: &DaybreakAuthStatusFixture{ response: response, failure: failure, block_until_released: block_until_released, gate: gate } }
}

// STUB: GetAuthStatus's typed transport/server/decode result boundary.
fn (handle &AppServerRequestHandle) request_get_auth_status(request api.ClientRequestGetAuthStatus) !api.GetAuthStatusResponse {
	if handle.daybreak_fixture == unsafe { nil } {
		return TypedRequestError{ kind: .transport, method: 'getAuthStatus', transport_source: error('app-server client is not available') }
	}
	mut fixture := handle.daybreak_fixture
	fixture.mutex.lock()
	fixture.requests << api.ClientRequestGetAuthStatus{ request_id: request.request_id, params: request.params }
	fixture.mutex.unlock()
	if fixture.block_until_released {
		_ := <-fixture.gate
	}
	if failure := fixture.failure {
		return match failure {
			.transport {
				TypedRequestError{ kind: failure, method: 'getAuthStatus', transport_source: error('fixture transport failure') }
			}
			.server {
				TypedRequestError{ kind: failure, method: 'getAuthStatus', server_source: api.JSONRPCErrorError{ code: -32603, message: 'fixture server failure' } }
			}
			.deserialize {
				TypedRequestError{ kind: failure, method: 'getAuthStatus', deserialize_source: error('fixture decode failure') }
			}
		}
	}
	return api.GetAuthStatusResponse{
		auth_method:          fixture.response.auth_method
		auth_token:           if token := fixture.response.auth_token {
			token.clone()
		} else {
			none
		}
		requires_openai_auth: fixture.response.requires_openai_auth
	}
}

// STUB: observes fully typed issued requests under the transport's shared lock.
pub fn (handle &AppServerRequestHandle) daybreak_auth_status_requests() []api.ClientRequestGetAuthStatus {
	if handle.daybreak_fixture == unsafe { nil } {
		return []api.ClientRequestGetAuthStatus{}
	}
	fixture := handle.daybreak_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	mut requests := []api.ClientRequestGetAuthStatus{cap: fixture.requests.len}
	for index in 0 .. fixture.requests.len {
		request := &fixture.requests[index]
		requests << api.ClientRequestGetAuthStatus{ request_id: request.request_id.clone(), params: request.params }
	}
	return requests
}
