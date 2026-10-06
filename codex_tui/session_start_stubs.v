module codex_tui

import codex_app_server_protocol
import codex_core
import codex_protocol
import codex_protocol.thread_id
import codex_tui.local_settings
import codex_tui.session_state
import codex_utils_absolute_path
import codex_utils_path_uri
import color_eyre.eyre
import os
import serde_json
import std_path

// STUB: tui/src/app_server_session.rs::ResumeModelSettings is Copy and keeps all variants.
pub enum ResumeModelSettings {
	override_from_current_config
	restore_from_thread
	preserve_existing_thread
}

// STUB: tui/src/app_server_session.rs::ForkPermissionMode is Copy and keeps both variants.
pub enum ForkPermissionMode {
	inherit_saved
	override_from_current_config
}

// STUB: tui/src/app_server_session.rs::AppServerStartedThread uses canonical session and turn owners.
pub struct AppServerStartedThread {
pub:
	session              session_state.ThreadSessionState
	turns                []codex_app_server_protocol.Turn
	blocks_direct_input  bool
	task_tools_available bool
}

// STUB: typed lifecycle calls observed at the untranslated app-server fixture boundary.
pub enum SessionStartFixtureCallKind {
	resume
	fork
	unarchive
	read
	shutdown
}

// STUB: typed observations retain action payloads, session ID, and source config clone state.
pub struct SessionStartFixtureCall {
pub:
	kind            SessionStartFixtureCallKind
	thread_id       codex_protocol.ThreadId
	model_settings  ResumeModelSettings
	permission_mode ForkPermissionMode
	config_home     string
	config_cwd      string
	local_home      string
	include_turns   bool
}

// STUB: explicit per-API fixture failures; native runtime execution remains untranslated.
pub struct SessionStartFixtureOverrides {
pub:
	resume_failure    ?string
	fork_failure      ?string
	unarchive_failure ?string
	shutdown_failure  ?string
}

// STUB: borrow configured resume diagnostics and assemble a new owned error message.
// A separate immutable receiver prevents V ownership from taking the fixture's option.
fn (overrides &SessionStartFixtureOverrides) resume_failure_text() ?string {
	if value := overrides.resume_failure { return value.clone() }
	return none
}

// STUB: borrow configured fork diagnostics without consuming the reusable fixture option.
fn (overrides &SessionStartFixtureOverrides) fork_failure_text() ?string {
	if value := overrides.fork_failure { return value.clone() }
	return none
}

// STUB: borrow configured unarchive diagnostics and return independently owned text.
fn (overrides &SessionStartFixtureOverrides) unarchive_failure_text() ?string {
	if value := overrides.unarchive_failure { return value.clone() }
	return none
}

// STUB: borrow configured shutdown diagnostics before consuming the session handle.
fn (overrides &SessionStartFixtureOverrides) shutdown_failure_text() ?string {
	if value := overrides.shutdown_failure { return value.clone() }
	return none
}

// STUB: embedded lifecycle fixture reads actual JSONL metadata and moves actual rollout files.
// SQLite, model networking, history hydration, and permission resolution remain unavailable.
@[heap]
struct SessionStartFixture {
	home      string
	overrides SessionStartFixtureOverrides
mut:
	calls    []SessionStartFixtureCall
	threads  map[string]codex_app_server_protocol.Thread
	shutdown bool
}

// STUB: explicitly select the typed lifecycle fixture for focused transport/error tests.
pub fn AppServerSession.session_start_fixture(config &codex_core.Config, overrides SessionStartFixtureOverrides) AppServerSession {
	return AppServerSession{ session_start_fixture: &SessionStartFixture{ home: config.codex_home.clone(), overrides: overrides } }
}

// STUB: picker startup retains the source integration's real on-disk rollout setup.
fn start_session_start_fixture(config &codex_core.Config) AppServerSession {
	return AppServerSession.session_start_fixture(config, SessionStartFixtureOverrides{})
}

// STUB: independent owned observations of the lifecycle requests issued by the target.
pub fn (session &AppServerSession) session_start_fixture_calls() []SessionStartFixtureCall {
	if session.session_start_fixture == unsafe { nil } { return []SessionStartFixtureCall{} }
	mut result := []SessionStartFixtureCall{}
	for index in 0 .. session.session_start_fixture.calls.len {
		call := &session.session_start_fixture.calls[index]
		result << SessionStartFixtureCall{ kind: call.kind, thread_id: codex_protocol.ThreadId{ value: call.thread_id.value.clone() }, model_settings: call.model_settings, permission_mode: call.permission_mode, config_home: call.config_home.clone(), config_cwd: call.config_cwd.clone(), local_home: call.local_home.clone(), include_turns: call.include_turns }
	}
	return result
}

// STUB: borrowed shutdown observation for cancellation tests of the shared fixture state.
pub fn (session &AppServerSession) session_start_fixture_is_shutdown() bool {
	return session.session_start_fixture != unsafe { nil } && session.session_start_fixture.shutdown
}

// STUB: clone only the shared fixture handle, representing the existing transport's shared state.
pub fn (session &AppServerSession) session_start_fixture_observer() AppServerSession {
	return AppServerSession{ session_start_fixture: session.session_start_fixture }
}

// STUB: AppServerSession::resume_thread preserves the owned Config and Copy action payload.
pub fn (mut session AppServerSession) resume_thread(settings &local_settings.LocalSettings, config codex_core.Config, id codex_protocol.ThreadId, mode ResumeModelSettings) !AppServerStartedThread {
	if session.session_start_fixture == unsafe { nil } {
		return error('untranslated app-server resume transport')
	}
	mut fixture := session.session_start_fixture
	fixture.calls << SessionStartFixtureCall{ kind: .resume, thread_id: codex_protocol.ThreadId{ value: id.value.clone() }, model_settings: mode, config_home: config.codex_home.clone(), config_cwd: config.cwd.clone(), local_home: settings.codex_home.path.clone() }
	overrides := &fixture.overrides
	if failure := overrides.resume_failure_text() { return error(failure) }
	loaded := fixture.session_start_load_thread(&id, 'resume')!
	return session_start_started_thread(&loaded, &config)
}

// STUB: AppServerSession::fork_thread_with_permission_mode preserves the owned Config and mode.
pub fn (mut session AppServerSession) fork_thread_with_permission_mode(settings &local_settings.LocalSettings, config codex_core.Config, id codex_protocol.ThreadId, mode ForkPermissionMode) !AppServerStartedThread {
	if session.session_start_fixture == unsafe { nil } {
		return error('untranslated app-server fork transport')
	}
	mut fixture := session.session_start_fixture
	fixture.calls << SessionStartFixtureCall{ kind: .fork, thread_id: codex_protocol.ThreadId{ value: id.value.clone() }, permission_mode: mode, config_home: config.codex_home.clone(), config_cwd: config.cwd.clone(), local_home: settings.codex_home.path.clone() }
	overrides := &fixture.overrides
	if failure := overrides.fork_failure_text() { return error(failure) }
	parent := fixture.session_start_load_thread(&id, 'fork')!
	fork_id := thread_id.new()
	loaded := codex_app_server_protocol.Thread{ ...parent, id: fork_id.value, forked_from_id: id.value }
	fixture.threads[loaded.id.clone()] = loaded.clone()
	return session_start_started_thread(&loaded, &config)
}

// STUB: AppServerSession::thread_unarchive moves the saved rollout and retains its ID.
pub fn (mut session AppServerSession) thread_unarchive(id codex_protocol.ThreadId) !codex_app_server_protocol.Thread {
	if session.session_start_fixture == unsafe { nil } {
		return error('untranslated app-server unarchive transport')
	}
	mut fixture := session.session_start_fixture
	fixture.calls << SessionStartFixtureCall{ kind: .unarchive, thread_id: codex_protocol.ThreadId{ value: id.value.clone() } }
	overrides := &fixture.overrides
	if failure := overrides.unarchive_failure_text() {
		return eyre.wrap_err(error(failure), 'failed to unarchive session')
	}
	archived := fixture.session_start_find_rollout(&id, true) or { return eyre.wrap_err(err, 'failed to unarchive session') }
	name := os.file_name(archived.clone())
	parts := name.split('-')
	if parts.len < 4 {
		return eyre.wrap_err(error('invalid archived rollout filename'), 'failed to unarchive session')
	}
	active_dir := os.join_path(fixture.home.clone(), 'sessions', parts[1], parts[2], parts[3][..2])
	os.mkdir_all(active_dir.clone()) or { return eyre.wrap_err(err, 'failed to unarchive session') }
	os.rename(archived, os.join_path(active_dir, name)) or { return eyre.wrap_err(err, 'failed to unarchive session') }
	return fixture.session_start_load_thread(&id, 'read') or { return eyre.wrap_err(err, 'failed to unarchive session') }
}

// STUB: picker thread/read returns the real fork-parent relationship from fixture state.
fn (mut session AppServerSession) session_start_thread_read(id codex_protocol.ThreadId, include_turns bool) !codex_app_server_protocol.Thread {
	mut fixture := session.session_start_fixture
	fixture.calls << SessionStartFixtureCall{ kind: .read, thread_id: codex_protocol.ThreadId{ value: id.value.clone() }, include_turns: include_turns }
	if loaded := fixture.threads[id.value] { return loaded.clone() }
	return fixture.session_start_load_thread(&id, 'read')
}

// STUB: AppServerSession::shutdown releases the lifecycle fixture and returns transport failure.
fn (session AppServerSession) shutdown_session_start_fixture() ! {
	mut fixture := session.session_start_fixture
	fixture.calls << SessionStartFixtureCall{ kind: .shutdown }
	fixture.shutdown = true
	overrides := &fixture.overrides
	if failure := overrides.shutdown_failure_text() { return error(failure) }
}

// STUB: find rollout by metadata ID, retaining the server's archive/missing distinction.
fn (fixture &SessionStartFixture) session_start_find_rollout(id &codex_protocol.ThreadId, archived bool) !string {
	directory := os.join_path(fixture.home.clone(), if archived {
		'archived_sessions'
	} else {
		'sessions'
	})
	if !os.is_dir(directory.clone()) { return error('session ${id.value} not found') }
	for path in os.walk_ext(directory, '.jsonl') {
		contents := os.read_file(path.clone())!
		lines := contents.split_into_lines()
		if lines.len == 0 { continue }
		header := serde_json.from_str(&lines[0])!
		payload_key := 'payload'
		id_key := 'id'
		payload := header.get(&payload_key)
		stored_id := payload.value.get(&id_key)
		if stored_id.has_value {
			text := stored_id.value.as_str()
			if text.has_value && *text.value == id.value { return path }
		}
	}
	return error('session ${id.value} not found')
}

// STUB: typed metadata lookup returns source-shaped bootstrap errors and archive guidance.
fn (fixture &SessionStartFixture) session_start_load_thread(id &codex_protocol.ThreadId, action string) !codex_app_server_protocol.Thread {
	path := fixture.session_start_find_rollout(id, false) or {
		if _ := fixture.session_start_find_rollout(id, true) {
			return error('thread/${action} failed during TUI bootstrap: thread/${action} failed: session ${id.value} is archived. Run `codex unarchive ${id.value}` to unarchive it first. (code -32600)')
		}
		return error('thread/${action} failed during TUI bootstrap: session ${id.value} not found')
	}
	return codex_app_server_protocol.Thread{ id: id.value.clone(), session_id: id.value.clone(), path: path, cwd: os.getwd(), history_mode: .legacy }
}

// STUB: source started_thread_from_* constructs the canonical session snapshot from typed data.
fn session_start_started_thread(loaded &codex_app_server_protocol.Thread, config &codex_core.Config) AppServerStartedThread {
	return AppServerStartedThread{
		session: session_state.ThreadSessionState{
			thread_id:                codex_protocol.ThreadId{ value: loaded.id.clone() }
			forked_from_id:           if parent := loaded.forked_from_id {
				codex_protocol.ThreadId{ value: parent.clone() }
			} else {
				none
			}
			model:                    if model := config.model { model.clone() } else { '' }
			model_provider_id:        config.model_provider_id.clone()
			approval_policy:          codex_app_server_protocol.AskForApproval{}
			approvals_reviewer:       .user
			permission_profile:       config.permissions.effective_permission_profile()
			cwd:                      codex_utils_absolute_path.AbsolutePathBuf{ path: config.cwd.clone() }
			runtime_workspace_roots:  []codex_utils_absolute_path.AbsolutePathBuf{}
			instruction_source_paths: []codex_utils_path_uri.PathUri{}
			rollout_path:             if path := loaded.path {
				std_path.PathBuf.from(path.clone())
			} else {
				none
			}
		}
	}
}
