module codex_app_server_client

import codex_app_server_protocol
import sync

// STUB: typed buffered command/exec replies at the untranslated app-server transport boundary.
pub type WorkspaceCommandReply = codex_app_server_protocol.CommandExecResponse | TypedRequestError

// STUB: an in-memory command/exec transport fixture. Native embedded and remote IO remain absent.
@[heap]
struct WorkspaceCommandFixture {
mut:
	mutex    &sync.Mutex = sync.new_mutex()
	replies  []WorkspaceCommandReply
	requests []codex_app_server_protocol.ClientRequestOneOffCommandExec
}

// STUB: install individual typed command/exec replies while consuming the handle and preserving
// all previously installed RPC fixtures, like its underlying shared transport would.
pub fn (handle AppServerRequestHandle) with_workspace_command_fixture(replies []WorkspaceCommandReply) AppServerRequestHandle {
	mut fixture := &WorkspaceCommandFixture{ replies: replies }
	fixture.replies.reverse_in_place()
	return AppServerRequestHandle{ ...handle, workspace_command_fixture: fixture }
}

// STUB: concrete command/exec implementation behind AppServerRequestHandle::request_typed.
// Requests are cloned only at RPC serialization; replies move once through the decoded boundary.
fn (handle &AppServerRequestHandle) request_one_off_command_exec(request codex_app_server_protocol.ClientRequestOneOffCommandExec) !codex_app_server_protocol.CommandExecResponse {
	if handle.workspace_command_fixture == unsafe { nil } {
		return TypedRequestError{ kind: .transport, method: 'command/exec', transport_source: error('app-server client is not available') }
	}
	mut fixture := handle.workspace_command_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	fixture.requests << codex_app_server_protocol.ClientRequestOneOffCommandExec{ request_id: request.request_id.clone(), params: request.params.clone() }
	if fixture.replies.len == 0 {
		return TypedRequestError{ kind: .transport, method: 'command/exec', transport_source: error('unexpected command/exec request') }
	}
	reply := fixture.replies.pop()
	return match reply {
		codex_app_server_protocol.CommandExecResponse { reply }
		TypedRequestError { reply }
	}
}

// STUB: owned typed observations of command/exec requests at the fixture wire boundary.
pub fn (handle &AppServerRequestHandle) workspace_command_fixture_requests() []codex_app_server_protocol.ClientRequestOneOffCommandExec {
	if handle.workspace_command_fixture == unsafe { nil } {
		return []codex_app_server_protocol.ClientRequestOneOffCommandExec{}
	}
	fixture := handle.workspace_command_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	mut requests := []codex_app_server_protocol.ClientRequestOneOffCommandExec{cap: fixture.requests.len}
	for index in 0 .. fixture.requests.len {
		request := &fixture.requests[index]
		requests << codex_app_server_protocol.ClientRequestOneOffCommandExec{ request_id: request.request_id.clone(), params: request.params.clone() }
	}
	return requests
}
