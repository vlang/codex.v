module codex_tui

import codex_app_server_client
import codex_app_server_protocol as api
import codex_core
import codex_protocol
import os
import serde_json
import toml

// STUB: tui/src/app_server_session.rs::AppServerSession at the embedded picker
// boundary; the native embedded runtime and SQLite initialization are untranslated.
pub struct AppServerSession {
	session_start_fixture &SessionStartFixture = unsafe { nil }
	handle                codex_app_server_client.AppServerRequestHandle
	params_mode           ThreadParamsMode
	embedded_transport    bool = true
	remote_cwd            string
	has_remote_cwd        bool
mut:
	next_request_id_value i64 = 1
}

// STUB: AppServerSession::request_handle clones the shared request sender.
pub fn (session &AppServerSession) request_handle() codex_app_server_client.AppServerRequestHandle {
	return session.handle.clone()
}

// STUB: AppServerSession::shutdown awaits the fixture transport's release.
pub fn (session AppServerSession) shutdown() ! {
	if session.session_start_fixture != unsafe { nil } {
		session.shutdown_session_start_fixture()!
		return
	}
	if session.handle.has_named_session_fixture() {
		session.handle.named_session_fixture_shutdown()!
		return
	}
	session.handle.shutdown_permission_fixture_if_present()!
	if !session.handle.has_permission_fixture() { session.handle.structured_fixture_shutdown()! }
}

// STUB: tui/src/lib.rs::start_embedded_app_server_for_picker uses an in-memory
// server loaded from the actual temporary config file. The TOML boundary retains
// the effective MCP names and required/command fields plus the named permission
// profile; process launching, SQLite, and model networking remain unavailable.
pub fn start_embedded_app_server_for_picker(config &codex_core.Config) !AppServerSession {
	if os.is_dir(os.join_path(config.codex_home.clone(), 'sessions')) || os.is_dir(os.join_path(config.codex_home.clone(), 'archived_sessions')) {
		return start_session_start_fixture(config)
	}
	path := os.join_path(config.codex_home, 'config.toml')
	doc := toml.parse_file(path)!
	profile := doc.value('default_permissions').string()
	permissions := doc.value('permissions').as_map()
	if profile !in permissions {
		return error('fixture permission profile missing')
	}
	mut servers := map[string]serde_json.Value{}
	for name, server in doc.value('mcp_servers').as_map() {
		values := server.as_map()
		servers[name] = serde_json.Value.object({
			'command':  serde_json.Value.string((values['command'] or { toml.Any('') }).string())
			'required': serde_json.Value.boolean((values['required'] or { toml.Any(false) }).bool())
		})
	}
	return AppServerSession{
		handle: codex_app_server_client.AppServerRequestHandle.temporary_structured_fixture(api.ConfigReadResponse{
			config: api.Config{
				additional: {
					'mcp_servers': serde_json.Value.object(servers)
				}
			}
		}, profile, codex_protocol.SandboxPolicy{ policy_kind: .read_only }, '', none, 0)
	}
}
