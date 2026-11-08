module codex_tui

import codex_app_server_client
import std_path

// STUB: tui/src/app_server_session.rs::ThreadParamsMode.
pub enum ThreadParamsMode {
	embedded
	remote
}

// STUB: safe representation of Rust Option<&Path>; Path itself is a borrowed
// Copy-equivalent byte view, so this optional does not own its underlying path.
pub struct BorrowedPermissionPath {
pub:
	path ?std_path.Path
}

// STUB: AppServerSession::new retains a typed shared request sender; the native
// WebSocket transport remains untranslated and fixtures stand at that boundary.
pub fn AppServerSession.new(handle codex_app_server_client.AppServerRequestHandle, mode ThreadParamsMode) AppServerSession {
	return AppServerSession{ handle: handle, params_mode: mode, embedded_transport: handle.named_session_fixture_is_embedded() }
}

// STUB: source builder owns its optional cwd and consumes the session.
pub fn (session AppServerSession) with_remote_cwd_override(cwd ?string) AppServerSession {
	return AppServerSession{ handle: session.handle, params_mode: session.params_mode, embedded_transport: session.embedded_transport, remote_cwd: cwd or { '' }, has_remote_cwd: cwd != none }
}

// STUB: AppServerSession::thread_params_mode reads the Copy-equivalent enum.
pub fn (session &AppServerSession) thread_params_mode() ThreadParamsMode {
	return session.params_mode
}

// STUB: AppServerSession::remote_cwd_override borrows its stored native path.
pub fn (session &AppServerSession) remote_cwd_override() BorrowedPermissionPath {
	if session.has_remote_cwd {
		return BorrowedPermissionPath{ path: std_path.Path.new(&session.remote_cwd) }
	}
	return BorrowedPermissionPath{}
}

// STUB: in-process transport identity; fixtures default to remote transport.
pub fn (session &AppServerSession) uses_embedded_app_server() bool {
	return session.embedded_transport
}
