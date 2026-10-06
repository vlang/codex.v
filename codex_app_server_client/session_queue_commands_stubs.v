module codex_app_server_client

import codex_app_server_protocol
import sync

// STUB: individual typed queue replies at the untranslated app-server transport.
pub type SessionQueueReply = codex_app_server_protocol.ThreadQueueAddResponse | TypedRequestError

// STUB: shared source-shaped thread/queue/add fixture, preserving typed requests
// and response/error layers without delivering any live queue submission.
@[heap]
struct SessionQueueFixture {
mut:
	mutex    &sync.Mutex = sync.new_mutex()
	replies  []SessionQueueReply
	requests []codex_app_server_protocol.ClientRequestThreadQueueAdd
}

// STUB: configure the individual queue RPC while preserving all previously
// installed fixtures on the consumed handle, including named-session list/read.
pub fn (handle AppServerRequestHandle) with_session_queue_fixture(replies []SessionQueueReply) AppServerRequestHandle {
	mut fixture := &SessionQueueFixture{ replies: replies }
	fixture.replies.reverse_in_place()
	return AppServerRequestHandle{ collaboration_fixture: handle.collaboration_fixture, structured_fixture: handle.structured_fixture, permission_fixture: handle.permission_fixture, named_session_fixture: handle.named_session_fixture, daybreak_fixture: handle.daybreak_fixture, session_queue_fixture: fixture, workspace_command_fixture: handle.workspace_command_fixture, config_update_fixture: handle.config_update_fixture }
}

// STUB: AppServerRequestHandle::request_typed for the concrete ThreadQueueAdd
// RPC. Absent native transport remains explicitly unavailable.
fn (handle &AppServerRequestHandle) request_thread_queue_add(request codex_app_server_protocol.ClientRequestThreadQueueAdd) !codex_app_server_protocol.ThreadQueueAddResponse {
	if handle.session_queue_fixture == unsafe { nil } {
		return TypedRequestError{ kind: .transport, method: 'thread/queue/add', transport_source: error('app-server client is not available') }
	}
	mut fixture := handle.session_queue_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	fixture.requests << codex_app_server_protocol.ClientRequestThreadQueueAdd{ request_id: request.request_id.clone(), params: request.params.clone() }
	if fixture.replies.len == 0 {
		return TypedRequestError{ kind: .transport, method: 'thread/queue/add', transport_source: error('unexpected thread/queue/add request') }
	}
	// Move each owned reply exactly once so transport error causes retain their
	// concrete type instead of reconstructing them from display strings.
	reply := fixture.replies.pop()
	return match reply {
		codex_app_server_protocol.ThreadQueueAddResponse { reply }
		TypedRequestError { reply }
	}
}

// STUB: owned observations clone each typed request at the fixture wire boundary.
pub fn (handle &AppServerRequestHandle) session_queue_fixture_requests() []codex_app_server_protocol.ClientRequestThreadQueueAdd {
	if handle.session_queue_fixture == unsafe { nil } {
		return []codex_app_server_protocol.ClientRequestThreadQueueAdd{}
	}
	fixture := handle.session_queue_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	mut requests := []codex_app_server_protocol.ClientRequestThreadQueueAdd{cap: fixture.requests.len}
	for index in 0 .. fixture.requests.len {
		request := &fixture.requests[index]
		requests << codex_app_server_protocol.ClientRequestThreadQueueAdd{ request_id: request.request_id.clone(), params: request.params.clone() }
	}
	return requests
}
