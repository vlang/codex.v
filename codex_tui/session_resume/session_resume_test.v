module session_resume

import codex_app_server_client
import codex_app_server_protocol as api
import codex_config.types
import codex_core
import codex_protocol.thread_id
import codex_tui
import codex_tui.cwd_prompt
import codex_tui.tui.test_support
import os
import std_path
import time

fn resume_owned(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

// TempDir's local filesystem setup and cleanup, with no Rust checkout dependency.
fn resume_temp_home() string {
	directory := os.join_path(os.temp_dir(), 'codex-v-session-resume-${os.getpid()}-${time.now().unix_nano()}')
	os.mkdir_all(directory.clone()) or { panic(err) }
	return directory
}

fn test_configured_resume_cwd_skips_prompt() {
	temp_dir := resume_temp_home()
	defer { os.rmdir_all(temp_dir.clone()) or { panic(err) } }
	session_cwd := std_path.PathBuf.from(os.join_path(temp_dir.clone(), 'session'))
	builder := codex_core.ConfigBuilder.default()
	home_builder := builder.codex_home(temp_dir.clone())
	config := home_builder.build() or { panic(err) }
	// Config's existing dependency stores the validated AbsolutePathBuf as string.
	current_cwd := std_path.PathBuf.from(config.cwd.clone())
	current_path := current_cwd.as_path()
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	cwd_prompt.session_resume_reset_prompt()
	for mode in [types.ResumeCwdMode.current, .session] {
		expected_cwd := if mode == .current { current_cwd.clone() } else { session_cwd.clone() }
		outcome := resolve_cwd_for_resume_or_fork(mut terminal_ui, &config, session_cwd.clone(),
			.fork, ResumeCwdContext{
				current_cwd:            &current_path
				remembered_current_cwd: &current_path
				allow_remember_current: true
				mode:                   mode
			}) or { panic(err) }
		expected := ResolveCwdOutcome{ kind: .continue_, cwd: expected_cwd }
		assert outcome.equals(&expected)
	}
	assert cwd_prompt.session_resume_prompt_calls().len == 0
}

fn test_matching_resume_cwd_skips_prompt_without_configured_mode() {
	temp_dir := resume_temp_home()
	defer { os.rmdir_all(temp_dir.clone()) or { panic(err) } }
	builder := codex_core.ConfigBuilder.default()
	home_builder := builder.codex_home(temp_dir.clone())
	config := home_builder.build() or { panic(err) }
	current_cwd := std_path.PathBuf.from(config.cwd.clone())
	current_path := current_cwd.as_path()
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	cwd_prompt.session_resume_reset_prompt()
	outcome := resolve_cwd_for_resume_or_fork(mut terminal_ui, &config, current_cwd.clone(),
		.resume, ResumeCwdContext{
			current_cwd:            &current_path
			remembered_current_cwd: &current_path
			allow_remember_current: true
			mode:                   none
		}) or { panic(err) }
	expected := ResolveCwdOutcome{ kind: .continue_, cwd: current_cwd }
	assert outcome.equals(&expected)
	assert cwd_prompt.session_resume_prompt_calls().len == 0
}

fn test_configured_session_cwd_rejects_missing_metadata() {
	temp_dir := resume_temp_home()
	defer { os.rmdir_all(temp_dir.clone()) or { panic(err) } }
	builder := codex_core.ConfigBuilder.default()
	home_builder := builder.codex_home(temp_dir.clone())
	config := home_builder.build() or { panic(err) }
	current_cwd := std_path.PathBuf.from(config.cwd.clone())
	current_path := current_cwd.as_path()
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	cwd_prompt.session_resume_reset_prompt()
	resolve_cwd_for_resume_or_fork(mut terminal_ui, &config, /*history_cwd*/
		none,
		.resume, ResumeCwdContext{
			current_cwd:            &current_path
			remembered_current_cwd: &current_path
			allow_remember_current: true
			mode:                   .session
		}) or {
		assert err.msg() == 'failed to determine the working directory recorded for the selected session'
		assert cwd_prompt.session_resume_prompt_calls().len == 0
		return
	}
	assert false, 'session mode should reject unavailable metadata'
}

fn test_current_mode_uses_remembered_directory_even_without_history() {
	current := resume_owned('/tmp/codex-current-session-resume')
	remembered := resume_owned('/tmp/codex-remembered-session-resume')
	current_path := std_path.Path.new(&current)
	remembered_path := std_path.Path.new(&remembered)
	config := codex_core.Config{}
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	cwd_prompt.session_resume_reset_prompt()
	for _ in 0 .. 2 {
		outcome := resolve_cwd_for_resume_or_fork(mut terminal_ui, &config, none, .resume,
			ResumeCwdContext{
				current_cwd:            &current_path
				remembered_current_cwd: &remembered_path
				mode:                   .current
			}) or { panic(err) }
		expected := ResolveCwdOutcome{ kind: .continue_, cwd: std_path.PathBuf.from(remembered.clone()) }
		assert outcome.equals(&expected)
	}
	assert cwd_prompt.session_resume_prompt_calls().len == 0
	assert current == '/tmp/codex-current-session-resume'
	assert remembered == '/tmp/codex-remembered-session-resume'
}

fn test_missing_history_without_configured_mode_continues_without_prompt() {
	current := resume_owned('/tmp/codex-no-history-session-resume')
	path := std_path.Path.new(&current)
	config := codex_core.Config{}
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	cwd_prompt.session_resume_reset_prompt()
	outcome := resolve_cwd_for_resume_or_fork(mut terminal_ui, &config, none, .fork,
		ResumeCwdContext{ current_cwd: &path, remembered_current_cwd: &path }) or { panic(err) }
	assert outcome.kind == .continue_
	assert outcome.cwd == none
	assert cwd_prompt.session_resume_prompt_calls().len == 0
}

struct ResumeModeCase {
	mode ?types.ResumeCwdMode
}

fn test_cwd_override_borrows_paths_and_forces_current_mode() {
	owner := resume_owned('/tmp/codex-cwd-override-session-resume')
	path := std_path.Path.new(&owner)
	for _ in 0 .. 2 {
		for entry in [ResumeModeCase{}, ResumeModeCase{ mode: .current },
			ResumeModeCase{ mode: .session }] {
			configured := entry.mode
			assert effective_resume_cwd_mode(configured, BorrowedPath{}) == configured
			selected := effective_resume_cwd_mode(configured, BorrowedPath{ path: path }) or { panic('missing current mode') }
			assert selected == .current
		}
	}
	assert owner == '/tmp/codex-cwd-override-session-resume'
	assert path.to_path_buf() == owner
}

fn test_prompt_selection_preserves_context_and_returns_owned_selected_path() {
	current := resume_owned('/codex-session-resume-missing/current')
	session := resume_owned('/codex-session-resume-missing/session')
	remembered := resume_owned('/codex-session-resume-missing/launched')
	current_path := std_path.Path.new(&current)
	remembered_path := std_path.Path.new(&remembered)
	config := codex_core.Config{ cwd: resume_owned('/tmp/config-cwd') }
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	defer { cwd_prompt.session_resume_reset_prompt() }
	for selection in [cwd_prompt.CwdSelection.current, .session, .current_and_remember,
		.session_and_remember] {
		allow_remember := selection in [.current_and_remember, .session_and_remember]
		cwd_prompt.session_resume_configure_prompt(cwd_prompt.CwdPromptOutcome{
			kind:      .selection
			selection: selection
		}, none)
		for _ in 0 .. 2 {
			outcome := resolve_cwd_for_resume_or_fork(mut terminal_ui, &config,
				std_path.PathBuf.from(session.clone()), .fork, ResumeCwdContext{
					current_cwd:            &current_path
					remembered_current_cwd: &remembered_path
					allow_remember_current: allow_remember
				}) or { panic(err) }
			selected := match selection {
				.current { current.clone() }
				.current_and_remember { remembered.clone() }
				.session, .session_and_remember { session.clone() }
			}
			expected := ResolveCwdOutcome{ kind: .continue_after_prompt, cwd: std_path.PathBuf.from(selected) }
			assert outcome.equals(&expected)
		}
		calls := cwd_prompt.session_resume_prompt_calls()
		assert calls.len == 2
		for index in 0 .. calls.len {
			call := &calls[index]
			assert call.action == .fork
			assert call.allow_remember_current == allow_remember
			assert call.current_cwd.as_path().equals(&current_path)
			assert call.remembered_current_cwd.as_path().equals(&remembered_path)
			session_path := std_path.Path.new(&session)
			assert call.session_cwd.as_path().equals(&session_path)
		}
	}
	assert current.ends_with('/current')
	assert session.ends_with('/session')
	assert remembered.ends_with('/launched')
	assert config.cwd == '/tmp/config-cwd'
}

fn test_prompt_exit_and_error_propagate() {
	current := resume_owned('/codex-session-resume-missing/a')
	other := resume_owned('/codex-session-resume-missing/b')
	current_path := std_path.Path.new(&current)
	config := codex_core.Config{}
	mut terminal_ui := test_support.make_test_tui() or { panic(err) }
	defer { cwd_prompt.session_resume_reset_prompt() }
	cwd_prompt.session_resume_configure_prompt(cwd_prompt.CwdPromptOutcome{ kind: .exit }, none)
	outcome := resolve_cwd_for_resume_or_fork(mut terminal_ui, &config,
		std_path.PathBuf.from(other.clone()), .resume, ResumeCwdContext{
			current_cwd:            &current_path
			remembered_current_cwd: &current_path
		}) or { panic(err) }
	assert outcome.kind == .exit
	assert outcome.cwd == none
	cwd_prompt.session_resume_configure_prompt(cwd_prompt.CwdPromptOutcome{}, resume_owned('prompt input failed'))
	resolve_cwd_for_resume_or_fork(mut terminal_ui, &config,
		std_path.PathBuf.from(other.clone()), .resume, ResumeCwdContext{
			current_cwd:            &current_path
			remembered_current_cwd: &current_path
		}) or {
		assert err.msg() == 'prompt input failed'
		assert current.ends_with('/a')
		assert other.ends_with('/b')
		return
	}
	assert false, 'prompt failure should propagate'
}

fn test_path_normalization_handles_symlinks_and_missing_paths_without_consuming_owners() {
	temp_dir := resume_temp_home()
	defer { os.rmdir_all(temp_dir.clone()) or { panic(err) } }
	directory := os.join_path(temp_dir.clone(), 'session')
	os.mkdir(directory.clone()) or { panic(err) }
	lexical := resume_owned(directory + '/./')
	directory_path := std_path.Path.new(&directory)
	lexical_path := std_path.Path.new(&lexical)
	for _ in 0 .. 2 {
		assert !cwds_differ(&directory_path, &lexical_path)
	}
	$if !windows {
		link := os.join_path(temp_dir.clone(), 'alias')
		os.symlink(directory.clone(), link.clone()) or { panic(err) }
		link_path := std_path.Path.new(&link)
		assert !cwds_differ(&directory_path, &link_path)
	}
	missing := resume_owned(directory + '/missing')
	missing_lexical := resume_owned(directory + '/./missing/')
	missing_path := std_path.Path.new(&missing)
	missing_lexical_path := std_path.Path.new(&missing_lexical)
	assert !cwds_differ(&missing_path, &missing_lexical_path)
	assert cwds_differ(&directory_path, &missing_path)
	invalid := resume_owned(directory + '\x00/unreadable')
	invalid_path := std_path.Path.new(&invalid)
	assert cwds_differ(&directory_path, &invalid_path)
	assert directory.ends_with('/session') || directory.ends_with('\\session')
	assert lexical.ends_with('/./')
	assert missing.ends_with('/missing')
}

fn test_session_cwd_read_uses_metadata_only_and_returns_none_on_transport_failure() {
	id_text := resume_owned('00000000-0000-0000-0000-000000000123')
	id := thread_id.from_string(&id_text) or { panic(err) }
	cwd := resume_owned('/tmp/codex-session-resume-server-cwd')
	handle := codex_app_server_client.AppServerRequestHandle.named_session_rpc_fixture([
		codex_app_server_client.NamedSessionReply(api.ThreadReadResponse{
			thread: api.Thread{ id: id_text.clone(), cwd: cwd.clone() }
		}),
		codex_app_server_client.NamedSessionReply(codex_app_server_client.TypedRequestError{
			kind:             .transport
			method:           resume_owned('thread/read')
			transport_source: error(resume_owned('connection closed'))
		}),
	])
	mut app_server := codex_tui.AppServerSession.new(handle.clone(), .remote)
	first := read_session_cwd(mut app_server, id) or { panic('missing cwd') }
	assert first.as_path().to_path_buf() == cwd
	second_id := thread_id.from_string(&id_text) or { panic(err) }
	assert read_session_cwd(mut app_server, second_id) == none
	requests := handle.named_session_fixture_requests()
	assert requests.len == 2
	for index in 0 .. requests.len {
		request := &requests[index]
		assert request is api.ClientRequestThreadRead
		if request is api.ClientRequestThreadRead {
			assert request.params.thread_id == id_text
			assert !request.params.include_turns
		}
	}
	assert id_text.ends_with('0123')
	assert cwd == '/tmp/codex-session-resume-server-cwd'
}
