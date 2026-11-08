module session_archive_commands

import codex_arg0
import codex_tui
import std_path

// STUB: tui/src/session_archive_commands.rs::SessionArchiveCommandOptions,
// preserving the owned CLI, dispatch paths, and optional typed remote endpoint.
pub struct SessionArchiveCommandOptions {
pub:
	cli                      codex_tui.Cli
	arg0_paths               codex_arg0.Arg0DispatchPaths
	explicit_remote_endpoint ?codex_tui.RemoteAppServerEndpoint
}

// STUB: archive startup's error result retains the original typed cause.
pub struct SessionCommandStartupFailure {
pub:
	cause IError
}

// STUB: typed one-shot archive startup response, without a native app-server launch.
pub type SessionCommandStartupReply = codex_tui.AppServerSession | SessionCommandStartupFailure

// STUB: fixture storage retains consumed options and the native owned home path.
@[heap]
struct SessionCommandStartupFixture {
mut:
	ready   bool
	replies []SessionCommandStartupReply
	options SessionArchiveCommandOptions
	home    std_path.PathBuf
	calls   int
}

// STUB: startup owns a fixture result independently of queue/list/read transport.
const session_command_startup_fixture = &SessionCommandStartupFixture{}

// STUB: tui/src/session_archive_commands.rs::start_app_server_for_session_command
// consumes the complete options and PathBuf. Native setup/configuration is absent,
// so an unconfigured call fails explicitly rather than starting a live app server.
pub fn start_app_server_for_session_command(options SessionArchiveCommandOptions, codex_home std_path.PathBuf) !codex_tui.AppServerSession {
	mut fixture := unsafe { session_command_startup_fixture }
	fixture.calls++
	fixture.options = options
	fixture.home = codex_home
	if !fixture.ready {
		return error('session command app-server startup is not translated')
	}
	reply := fixture.replies.pop()
	fixture.ready = false
	return match reply {
		codex_tui.AppServerSession { reply }
		SessionCommandStartupFailure { reply.cause }
	}
}

// STUB: install the owned session or error returned by the next startup call.
pub fn configure_session_command_startup(reply SessionCommandStartupReply) {
	mut fixture := unsafe { session_command_startup_fixture }
	fixture.replies = [reply]
	fixture.ready = true
	fixture.calls = 0
}

// STUB: inspect the actual consumed typed options without inventing queue fields.
pub fn session_command_startup_options() &SessionArchiveCommandOptions {
	return &session_command_startup_fixture.options
}

// STUB: inspect the owned native PathBuf received by archive startup.
pub fn session_command_startup_home() &std_path.PathBuf {
	return &session_command_startup_fixture.home
}

// STUB: observe startup calls separately from home resolution and daemon probing.
pub fn session_command_startup_calls() int {
	return session_command_startup_fixture.calls
}
