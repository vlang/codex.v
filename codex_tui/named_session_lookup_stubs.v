module codex_tui

import codex_app_server_client
import codex_app_server_protocol as api
import codex_core
import codex_protocol
import codex_state.runtime
import color_eyre.eyre

// STUB: AppServerSession::uses_remote_workspace uses mode, independently of the
// transport identity used by uses_embedded_app_server.
pub fn (session &AppServerSession) uses_remote_workspace() bool {
	return session.params_mode == .remote
}

// STUB: AppServerSession::next_request_id increments its session-owned integer ID.
pub fn (mut session AppServerSession) next_request_id() api.RequestId {
	id := session.next_request_id_value
	session.next_request_id_value++
	return api.RequestId{ kind: .integer, integer: id }
}

// STUB: AppServerSession::thread_list retains the source-shaped typed RPC boundary.
// Named lookup always supplies cwd=None; legacy multi-CWD retry remains untranslated.
pub fn (mut session AppServerSession) thread_list(params api.ThreadListParams) !api.ThreadListResponse {
	request_id := session.next_request_id()
	return session.handle.request_typed[api.ThreadListResponse](api.ClientRequestThreadList{ request_id: request_id, params: params }) or { return eyre.wrap_err(err, 'thread/list failed during TUI session lookup') }
}

// STUB: AppServerSession::thread_read issues a read-only ThreadRead request.
// include_turns=true's history fallback remains untranslated.
pub fn (mut session AppServerSession) thread_read(id codex_protocol.ThreadId, include_turns bool) !api.Thread {
	if session.session_start_fixture != unsafe { nil } {
		return session.session_start_thread_read(id, include_turns)
	}
	request_id := session.next_request_id()
	response := session.handle.request_typed[api.ThreadReadResponse](api.ClientRequestThreadRead{ request_id: request_id, params: api.ThreadReadParams{ thread_id: id.value, include_turns: include_turns } }) or { return eyre.wrap_err(err, 'thread/read failed during TUI session lookup') }
	return response.thread
}

// STUB: tui/src/tests.rs::start_test_embedded_app_server uses the actual metadata
// inserted through StateRuntime::upsert_thread. The fixture replaces SQLite and
// native server transport, retaining typed list/read RPCs and rollout validation.
pub fn start_test_embedded_app_server(config codex_core.Config) !codex_app_server_client.AppServerRequestHandle {
	state := runtime.named_session_fixture_state(&config.codex_home)!
	return codex_app_server_client.AppServerRequestHandle.named_session_state_fixture(state.named_session_fixture_threads(), config.model_provider_id, true)
}

// STUB: tui/src/lib.rs::resume_source_kinds preserves the user-resumable sources.
pub fn resume_source_kinds(include_non_interactive bool) []api.ThreadSourceKind {
	mut source_kinds := [api.ThreadSourceKind.cli, .vscode]
	if include_non_interactive {
		// `thread/list` treats omitted and empty `sourceKinds` as interactive-only,
		// so include-non-interactive has to name the user-resumable non-interactive
		// sources explicitly until the API grows an unfiltered request.
		source_kinds << [api.ThreadSourceKind.exec, .app_server]
	}
	return source_kinds
}
