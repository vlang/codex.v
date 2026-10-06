// Interactive recovery when starting an archived session.
module session_start

import codex_core
import codex_protocol
import codex_tui
import codex_tui.app
import codex_tui.local_settings
import codex_tui.resume_picker
import codex_tui.unarchive_prompt
import color_eyre.eyre
import tracing

// The payloads are Copy enums, so this tagged aggregate preserves Rust's Clone and Copy.
// V has no pub(crate) visibility between the TUI's sibling modules.
pub enum SessionStartActionKind {
	resume
	fork
}

pub struct SessionStartAction {
pub:
	kind                 SessionStartActionKind
	resume_settings      codex_tui.ResumeModelSettings
	fork_permission_mode codex_tui.ForkPermissionMode
}

pub fn SessionStartAction.resume(settings codex_tui.ResumeModelSettings) SessionStartAction {
	return SessionStartAction{ kind: .resume, resume_settings: settings }
}

pub fn SessionStartAction.fork(mode codex_tui.ForkPermissionMode) SessionStartAction {
	return SessionStartAction{ kind: .fork, fork_permission_mode: mode }
}

pub fn (action SessionStartAction) verb() string {
	return match action.kind {
		.resume { 'resume' }
		.fork { 'fork' }
	}
}

// The untranslated app-server APIs use synchronous typed boundaries in V.
fn (action SessionStartAction) start(mut app_server codex_tui.AppServerSession, config &codex_core.Config, target &resume_picker.SessionTarget) !codex_tui.AppServerStartedThread {
	settings := local_settings.LocalSettings.from(config)
	return match action.kind {
		.resume {
			app_server.resume_thread(&settings, config.clone(), target.thread_id, action.resume_settings)!
		}
		.fork {
			app_server.fork_thread_with_permission_mode(&settings, config.clone(), target.thread_id, action.fork_permission_mode)!
		}
	}
}

// V cannot accept a Result<T> parameter or return !?T. These owned representations
// retain Rust's initial Result and successful Some/None outcomes without dropping a payload.
pub struct SessionStartFailure {
pub:
	failure IError
}

pub type SessionStartResult = SessionStartFailure | codex_tui.AppServerStartedThread

pub struct OptionalStartedThread {
pub:
	is_some bool
	value   ?codex_tui.AppServerStartedThread
}

// The owned callable adapts AsyncFnOnce; this function invokes it at most once.
pub fn complete_session_start(mut app_server codex_tui.AppServerSession, config &codex_core.Config, target &resume_picker.SessionTarget, action SessionStartAction, initial_result SessionStartResult, confirm fn () !unarchive_prompt.UnarchiveChoice) !OptionalStartedThread {
	match initial_result {
		codex_tui.AppServerStartedThread {
			return OptionalStartedThread{ is_some: true, value: initial_result }
		}
		SessionStartFailure {
			// Match the requested ID as well as the server's archive guidance: an unrelated
			// startup failure must never cause us to unarchive a session.
			archived_prefix := 'session ${target.thread_id} is archived. '
			guidance := archived_session_guidance(&initial_result.failure)
			matches_target := if message := guidance {
				message.starts_with(archived_prefix)
			} else {
				false
			}
			if !matches_target {
				verb := action.verb()
				return session_start_error(&verb, target, initial_result.failure)
			}
		}
	}
	if confirm()! == .cancel {
		return OptionalStartedThread{}
	}
	app_server.thread_unarchive(target.thread_id) or {
		return eyre.wrap_err(err, 'Failed to unarchive session ${target.thread_id}')
	}
	// Retry by ID, not by the old rollout path, which unarchiving may have moved.
	started := action.start(mut app_server, config, target) or {
		verb := action.verb()
		return session_start_error(&verb, target, err)
	}
	return OptionalStartedThread{ is_some: true, value: started }
}

pub fn cancel_session_start(app_server codex_tui.AppServerSession) app.AppExitInfo {
	app_server.shutdown() or {
		message := 'app-server shutdown failed: ${err}'
		tracing.warn(&message)
	}
	return app.AppExitInfo{
		token_usage:     codex_protocol.TokenUsage{}
		thread_id:       none
		resume_hint:     none
		disconnect_info: none
		update_action:   none
		exit_reason:     app.ExitReason{ kind: .user_requested }
	}
}

fn session_start_error(action &string, target &resume_picker.SessionTarget, failure IError) IError {
	if message := archived_session_guidance(&failure) {
		return error(message)
	}
	label := target.display_label()
	return error('Failed to ${*action} session from ${label}: ${failure.msg()}')
}

fn archived_session_guidance(failure &IError) ?string {
	display := failure.msg()
	start := display.index('session ') or { return none }
	message := display[start..]
	if !message.contains(' is archived. Run `codex unarchive ') {
		return none
	}
	// Rust returns an owned String assembled from borrowed slices; V explicitly owns it too.
	if code := message.index(' (code ') {
		return message[..code].clone()
	}
	return message.clone()
}
