module codex_tui

import codex_app_server_client
import codex_utils_absolute_path
import std_path

// STUB: tui/src/cli.rs::Cli. Queue commands pass this owned value through to the
// untranslated archive startup; no CLI fields are inspected by the queue target.
pub struct Cli {}

// STUB: construct the source AppServerSession transport identity in tests. The
// native client runtime normally supplies this identity to AppServerSession::new.
pub fn AppServerSession.session_queue_transport_fixture(handle codex_app_server_client.AppServerRequestHandle, embedded bool) AppServerSession {
	return AppServerSession{
		handle:             handle
		params_mode:        if embedded {
			ThreadParamsMode.embedded
		} else {
			ThreadParamsMode.remote
		}
		embedded_transport: embedded
	}
}

// STUB: fixture storage for lib.rs::maybe_probe_default_daemon_socket's typed
// optional AbsolutePathBuf return; no native socket is opened or probed.
@[heap]
struct SessionQueueDaemonProbeFixture {
mut:
	present bool
	path    codex_utils_absolute_path.AbsolutePathBuf
	calls   int
	homes   []std_path.PathBuf
}

// STUB: the daemon probe has its own typed fixture, independent of startup RPCs.
const session_queue_daemon_probe_fixture = &SessionQueueDaemonProbeFixture{}

// STUB: lib.rs::maybe_probe_default_daemon_socket. No fixture means no evidence
// of a running daemon; actual native probing is not yet translated.
pub fn maybe_probe_default_daemon_socket(codex_home &std_path.Path) ?codex_utils_absolute_path.AbsolutePathBuf {
	mut fixture := unsafe { session_queue_daemon_probe_fixture }
	fixture.calls++
	fixture.homes << std_path.PathBuf.from(codex_home.to_path_buf())
	if fixture.present {
		return codex_utils_absolute_path.AbsolutePathBuf{ path: fixture.path.path.clone() }
	}
	return none
}

// STUB: reset the optional typed probe result between fixture-only queue tests.
pub fn configure_session_queue_daemon_probe(path ?codex_utils_absolute_path.AbsolutePathBuf) {
	mut fixture := unsafe { session_queue_daemon_probe_fixture }
	fixture.present = false
	fixture.calls = 0
	fixture.homes.clear()
	if value := path {
		fixture.present = true
		fixture.path = value
	}
}

// STUB: observe actual typed daemon probe calls without target mock-field reads.
pub fn session_queue_daemon_probe_calls() int {
	return session_queue_daemon_probe_fixture.calls
}

// STUB: borrow the recorded native paths so their owners remain reusable.
pub fn session_queue_daemon_probe_homes() &[]std_path.PathBuf {
	return &session_queue_daemon_probe_fixture.homes
}
