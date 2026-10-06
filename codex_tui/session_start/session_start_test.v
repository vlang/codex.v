module session_start

import codex_config
import codex_core
import codex_protocol
import codex_protocol.thread_id
import codex_tui
import codex_tui.app_test_support
import codex_tui.resume_picker
import codex_tui.unarchive_prompt
import color_eyre.eyre
import os
import std_ffi
import std_path
import uuid

// Cell's shared interior mutation is confined to this test counter.
@[heap]
struct PromptCount {
mut:
	value int
}

fn (count &PromptCount) increment() {
	unsafe {
		mut cell := count
		cell.value++
	}
}

fn (count &PromptCount) get() int {
	return count.value
}

fn owned(value &string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn start_session(mut app_server codex_tui.AppServerSession, config &codex_core.Config, target &resume_picker.SessionTarget, action SessionStartAction, confirm fn () !unarchive_prompt.UnarchiveChoice) !OptionalStartedThread {
	initial := action.start(mut app_server, config, target) or {
		return complete_session_start(mut app_server, config, target, action, SessionStartFailure{ failure: err }, confirm)
	}
	return complete_session_start(mut app_server, config, target, action, initial, confirm)
}

fn test_archived_session_requires_confirmation_before_resume_or_fork() {
	for action in [SessionStartAction.resume(.restore_from_thread),
		SessionStartAction.fork(.inherit_saved)] {
		codex_home := os.join_path(os.temp_dir(), 'codex-session-start-${uuid.Uuid.new_v4()}')
		os.mkdir_all(codex_home.clone()) or { panic(err) }
		defer { os.rmdir_all(codex_home.clone()) or { panic(err) } }
		config := codex_core.ConfigBuilder.default().codex_home(codex_home.clone()).loader_overrides(codex_config.LoaderOverrides.without_managed_config_for_tests()).build() or { panic(err) }
		home := std_path.PathBuf.from(codex_home.clone())
		timestamp := '2025-01-05T12-00-00'
		metadata_timestamp := '2025-01-05T12:00:00Z'
		preview := 'Archived saved user message'
		id := app_test_support.create_fake_rollout(home.as_path(), &timestamp, &metadata_timestamp, &preview, std_ffi.BorrowedUtf8{ present: true, value: &config.model_provider_id }, /*git_info*/
			none) or { panic('create source rollout: ${err}') }
		active_path := app_test_support.rollout_path(home.as_path(), &timestamp, &id)
		archived_dir := os.join_path(codex_home.clone(), 'archived_sessions')
		os.mkdir_all(archived_dir.clone()) or { panic(err) }
		archived_path := std_path.PathBuf.from(os.join_path(archived_dir, os.file_name(active_path.as_path().to_path_buf())))
		os.rename(active_path.as_path().to_path_buf(), archived_path.as_path().to_path_buf()) or { panic(err) }
		target := resume_picker.SessionTarget{ path: archived_path.clone(), thread_id: thread_id.from_string(&id) or { panic(err) }, cwd: none, history_mode: none }
		mut app_server := codex_tui.start_embedded_app_server_for_picker(&config) or { panic(err) }
		prompts := &PromptCount{}
		cancelled := start_session(mut app_server, &config, &target, action, fn [prompts] () !unarchive_prompt.UnarchiveChoice {
			prompts.increment()
			return .cancel
		}) or { panic(err) }
		assert !cancelled.is_some
		assert prompts.get() == 1 && os.exists(archived_path.as_path().to_path_buf()) && !os.exists(active_path.as_path().to_path_buf())
		confirmed := start_session(mut app_server, &config, &target, action, fn [prompts] () !unarchive_prompt.UnarchiveChoice {
			prompts.increment()
			return .unarchive
		}) or { panic(err) }
		started := confirmed.value or { panic('confirmed session should start') }
		assert prompts.get() == 2 && !os.exists(archived_path.as_path().to_path_buf()) && os.exists(active_path.as_path().to_path_buf())
		match action.kind {
			.resume {
				assert started.session.thread_id == target.thread_id
			}
			.fork {
				assert started.session.thread_id != target.thread_id
				read := app_server.thread_read(started.session.thread_id, /*include_turns*/
					false) or { panic(err) }
				parent := read.forked_from_id or { panic('fork should retain parent') }
				assert parent == id
			}
		}
		resumed_option := start_session(mut app_server, &config, &target, SessionStartAction.resume(.restore_from_thread), fn () !unarchive_prompt.UnarchiveChoice {
			panic('active sessions must not prompt')
		}) or { panic(err) }
		resumed := resumed_option.value or { panic('active session should start') }
		assert resumed.session.thread_id == target.thread_id
		calls_before_missing := app_server.session_start_fixture_calls()
		assert calls_before_missing[0].kind == action_call_kind(action)
		assert calls_before_missing[1].kind == action_call_kind(action)
		assert calls_before_missing[2].kind == .unarchive
		assert calls_before_missing[3].kind == action_call_kind(action)
		assert calls_before_missing[3].thread_id == target.thread_id
		assert calls_before_missing.last().kind == .resume
		// The initial successful result must return without prompting or making another call.
		completed := complete_session_start(mut app_server, &config, &target, action, resumed, fn () !unarchive_prompt.UnarchiveChoice {
			panic('initial success must not prompt')
		}) or { panic(err) }
		assert completed.is_some
		completed_value := completed.value or { panic('initial success should remain present') }
		assert completed_value.session.thread_id == target.thread_id
		assert app_server.session_start_fixture_calls().len == calls_before_missing.len
		missing := resume_picker.SessionTarget{ path: none, thread_id: thread_id.new(), cwd: none, history_mode: none }
		mut failure := ''
		start_session(mut app_server, &config, &missing, action, fn () !unarchive_prompt.UnarchiveChoice {
			panic('unrelated failures must not prompt')
		}) or { failure = err.msg() }
		assert failure.starts_with('Failed to ${action.verb()} session')
		app_server.shutdown() or { panic(err) }
	}
}

fn action_call_kind(action SessionStartAction) codex_tui.SessionStartFixtureCallKind {
	return if action.kind == .resume { .resume } else { .fork }
}

fn test_session_start_error_surfaces_archived_guidance_without_rollout_path() {
	id_text := '019e72f4-e09a-70f2-b2c2-a153a57b8cc0'
	id := thread_id.from_string(&id_text) or { panic('thread id: ${err}') }
	// Rust ThreadId is Copy; the canonical V UUID owner needs an explicit copy here.
	target_session := resume_picker.SessionTarget{ path: std_path.PathBuf.from('/Users/me/.codex/archived_sessions/rollout.jsonl'), thread_id: codex_protocol.ThreadId{ value: id.value.clone() }, cwd: none, history_mode: none }
	expected := 'session ${id} is archived. Run `codex unarchive ${id}` to unarchive it first.'
	for action in ['resume', 'fork'] {
		failure := error('thread/${action} failed during TUI bootstrap: thread/${action} failed: ${expected} (code -32600)')
		assert session_start_error(&action, &target_session, failure).msg() == expected
	}
}

fn test_guidance_borrows_heap_errors_and_targets_repeatedly() {
	id_literal := '019e72f4-e09a-70f2-b2c2-a153a57b8cc0'
	path_literal := '/owned/archived/rollout.jsonl'
	id := owned(&id_literal)
	path := owned(&path_literal)
	target := resume_picker.SessionTarget{ path: std_path.PathBuf.from(path), thread_id: thread_id.from_string(&id) or { panic(err) } }
	message_literal := 'prefix: session ${id} is archived. Run `codex unarchive ${id}` now. (code -32600) tail'
	message := owned(&message_literal)
	failure := IError(error(message))
	for _ in 0 .. 2 {
		guidance := archived_session_guidance(&failure) or { panic('expected guidance') }
		assert guidance == 'session ${id} is archived. Run `codex unarchive ${id}` now.'
		assert target.display_label() == path_literal
	}
	assert failure.msg() == message_literal
	assert target.thread_id.value == id_literal
	assert target.path?.as_path().to_path_buf() == path_literal
}

fn focused_config() codex_core.Config {
	return codex_core.ConfigBuilder.default().codex_home(os.join_path(os.temp_dir(), 'codex-session-start-focused-${uuid.Uuid.new_v4()}')).loader_overrides(codex_config.LoaderOverrides.without_managed_config_for_tests()).build() or { panic(err) }
}

fn test_nonmatching_failures_never_prompt_or_unarchive() {
	config := focused_config()
	mut server := codex_tui.AppServerSession.session_start_fixture(&config, codex_tui.SessionStartFixtureOverrides{})
	id := thread_id.new()
	target := resume_picker.SessionTarget{ thread_id: codex_protocol.ThreadId{ value: id.value.clone() } }
	other := thread_id.new()
	inputs := ['network failure', 'session ${id} is archived.',
		'session ${other} is archived. Run `codex unarchive ${other}` first.']
	expected := ['Failed to resume session from thread ${id}: network failure',
		'Failed to resume session from thread ${id}: session ${id} is archived.', inputs[2].clone()]
	for index, text in inputs {
		mut failure := ''
		complete_session_start(mut server, &config, &target, SessionStartAction.resume(.preserve_existing_thread), SessionStartFailure{ failure: error(text.clone()) }, fn () !unarchive_prompt.UnarchiveChoice {
			panic('nonmatching failures must not prompt')
		}) or { failure = err.msg() }
		assert failure == expected[index]
	}
	assert server.session_start_fixture_calls().len == 0
	assert target.thread_id == id
}

fn test_guidance_preserves_first_session_and_first_code_boundaries() {
	for text in ['no session marker', 'session example is archived.',
		'session example is archived. Run codex unarchive example'] {
		failure := IError(error(text.clone()))
		present := if _ := archived_session_guidance(&failure) { true } else { false }
		assert !present
	}
	text := 'bootstrap session earlier: session example is archived. Run `codex unarchive example` first. (code -32600) later (code -1)'
	failure := IError(error(text))
	actual := archived_session_guidance(&failure) or { panic('archive guidance should be preserved') }
	assert actual == 'session earlier: session example is archived. Run `codex unarchive example` first.'
	assert failure.msg() == text
}

fn test_confirmation_and_unarchive_failures_preserve_error_boundaries() {
	config := focused_config()
	id := thread_id.new()
	target := resume_picker.SessionTarget{ thread_id: codex_protocol.ThreadId{ value: id.value.clone() } }
	mut server := codex_tui.AppServerSession.session_start_fixture(&config, codex_tui.SessionStartFixtureOverrides{ unarchive_failure: 'denied' })
	guidance := 'session ${id} is archived. Run `codex unarchive ${id}` first.'
	mut confirmation_failure := ''
	complete_session_start(mut server, &config, &target, SessionStartAction.fork(.override_from_current_config), SessionStartFailure{ failure: error(guidance.clone()) }, fn () !unarchive_prompt.UnarchiveChoice {
		return error('prompt failed')
	}) or { confirmation_failure = err.msg() }
	assert confirmation_failure == 'prompt failed'
	assert server.session_start_fixture_calls().len == 0
	prompts := &PromptCount{}
	mut unarchive_failure := ''
	mut chain := ''
	complete_session_start(mut server, &config, &target, SessionStartAction.fork(.override_from_current_config), SessionStartFailure{ failure: error(guidance) }, fn [prompts] () !unarchive_prompt.UnarchiveChoice {
		prompts.increment()
		return .unarchive
	}) or {
		unarchive_failure = err.msg()
		chain = eyre.alternate_display(&err)
	}
	assert unarchive_failure == 'Failed to unarchive session ${id}'
	assert chain == 'Failed to unarchive session ${id}: failed to unarchive session: denied'
	assert prompts.get() == 1
	calls := server.session_start_fixture_calls()
	assert calls.len == 1 && calls[0].kind == .unarchive && calls[0].thread_id == id
}

fn test_cancel_shuts_down_and_returns_complete_user_exit_on_failure() {
	config := focused_config()
	server := codex_tui.AppServerSession.session_start_fixture(&config, codex_tui.SessionStartFixtureOverrides{ shutdown_failure: 'transport closed' })
	observer := server.session_start_fixture_observer()
	info := cancel_session_start(server)
	assert info.token_usage == codex_protocol.TokenUsage{}
	assert info.thread_id == none && info.resume_hint == none && info.disconnect_info == none && info.update_action == none
	assert info.exit_reason.kind == .user_requested
	assert observer.session_start_fixture_is_shutdown()
	calls := observer.session_start_fixture_calls()
	assert calls.len == 1 && calls[0].kind == .shutdown
}

fn test_action_payloads_and_config_borrows_survive_repeated_starts() {
	mut config := focused_config()
	provider_literal := 'owned-provider'
	home_literal := config.codex_home.clone()
	cwd_literal := config.cwd.clone()
	config.model_provider_id = owned(&provider_literal)
	config.codex_home = owned(&home_literal)
	config.cwd = owned(&cwd_literal)
	mut server := codex_tui.AppServerSession.session_start_fixture(&config, codex_tui.SessionStartFixtureOverrides{ resume_failure: 'resume unavailable', fork_failure: 'fork unavailable' })
	id_literal := '019e72f4-e09a-70f2-b2c2-a153a57b8cc0'
	id := owned(&id_literal)
	target := resume_picker.SessionTarget{ thread_id: thread_id.from_string(&id) or { panic(err) } }
	actions := [SessionStartAction.resume(.override_from_current_config),
		SessionStartAction.resume(.restore_from_thread),
		SessionStartAction.resume(.preserve_existing_thread), SessionStartAction.fork(.inherit_saved),
		SessionStartAction.fork(.override_from_current_config)]
	for action in actions {
		for _ in 0 .. 2 {
			mut failure := ''
			action.start(mut server, &config, &target) or { failure = err.msg() }
			assert failure == '${action.verb()} unavailable'
		}
	}
	for _ in 0 .. 2 {
		calls := server.session_start_fixture_calls()
		assert calls.len == 10
		for index, action in actions {
			call := &calls[index * 2]
			assert call.kind == action_call_kind(action)
			assert call.model_settings == action.resume_settings
			assert call.permission_mode == action.fork_permission_mode
			assert call.thread_id.value == id_literal
			assert call.config_home == home_literal && call.local_home == home_literal
			assert call.config_cwd == cwd_literal
		}
	}
	assert config.model_provider_id == provider_literal
	assert config.codex_home == home_literal && config.cwd == cwd_literal
	assert target.thread_id.value == id_literal
	assert id == id_literal
}

fn test_retry_failure_occurs_after_one_unarchive_and_keeps_the_requested_id() {
	for action in [SessionStartAction.resume(.override_from_current_config),
		SessionStartAction.fork(.override_from_current_config)] {
		home_text := os.join_path(os.temp_dir(), 'codex-session-start-retry-${uuid.Uuid.new_v4()}')
		os.mkdir_all(home_text.clone()) or { panic(err) }
		defer { os.rmdir_all(home_text.clone()) or { panic(err) } }
		config := codex_core.ConfigBuilder.default().codex_home(home_text.clone()).loader_overrides(codex_config.LoaderOverrides.without_managed_config_for_tests()).build() or { panic(err) }
		home := std_path.PathBuf.from(home_text.clone())
		timestamp := '2025-01-05T12-00-00'
		metadata := '2025-01-05T12:00:00Z'
		preview := 'Retry failure source message'
		id := app_test_support.create_fake_rollout(home.as_path(), &timestamp, &metadata, &preview, std_ffi.BorrowedUtf8{}, none) or { panic(err) }
		active := app_test_support.rollout_path(home.as_path(), &timestamp, &id)
		archived_dir := os.join_path(home_text, 'archived_sessions')
		os.mkdir_all(archived_dir.clone()) or { panic(err) }
		archived := std_path.PathBuf.from(os.join_path(archived_dir, os.file_name(active.as_path().to_path_buf())))
		os.rename(active.as_path().to_path_buf(), archived.as_path().to_path_buf()) or { panic(err) }
		target := resume_picker.SessionTarget{ path: archived.clone(), thread_id: thread_id.from_string(&id) or { panic(err) } }
		mut server := codex_tui.AppServerSession.session_start_fixture(&config, codex_tui.SessionStartFixtureOverrides{ resume_failure: 'retry unavailable', fork_failure: 'retry unavailable' })
		guidance := 'session ${id} is archived. Run `codex unarchive ${id}` first.'
		prompts := &PromptCount{}
		mut failure := ''
		complete_session_start(mut server, &config, &target, action, SessionStartFailure{ failure: error(guidance) }, fn [prompts] () !unarchive_prompt.UnarchiveChoice {
			prompts.increment()
			return .unarchive
		}) or { failure = err.msg() }
		assert failure == 'Failed to ${action.verb()} session from ${archived.as_path().to_string_lossy()}: retry unavailable'
		assert prompts.get() == 1 && os.exists(active.as_path().to_path_buf()) && !os.exists(archived.as_path().to_path_buf())
		calls := server.session_start_fixture_calls()
		assert calls.len == 2 && calls[0].kind == .unarchive && calls[1].kind == action_call_kind(action)
		assert calls[0].thread_id == target.thread_id && calls[1].thread_id == target.thread_id
	}
}
