// Resolve saved-session state needed before resuming or forking a thread.
//
// The app-server API owns thread metadata. This module coordinates the TUI-specific
// cwd prompt using the cwd reported by the selected thread.
module session_resume

import codex_config.types
import codex_core
import codex_protocol
import codex_tui
import codex_tui.cwd_prompt
import codex_tui.tui
import codex_utils_path as path_utils
import std_path
import tracing

// V has no pub(crate) visibility between TUI submodules. The explicit tag keeps
// Continue(None), Continue(Some(path)), and Exit distinct without nested options.
pub enum ResolveCwdOutcomeKind {
	continue_
	// An interactive prompt was shown, so previously cached authentication may be stale.
	continue_after_prompt
	exit
}

pub struct ResolveCwdOutcome {
pub:
	kind ResolveCwdOutcomeKind
	cwd  ?std_path.PathBuf
}

// Rust derives PartialEq/Eq; its PathBuf equality compares lexical components.
pub fn (outcome &ResolveCwdOutcome) equals(other &ResolveCwdOutcome) bool {
	if outcome.kind != other.kind {
		return false
	}
	if outcome.kind == .exit {
		return true
	}
	if path := outcome.cwd {
		if other_path := other.cwd {
			return path.equals(&other_path)
		}
		return false
	}
	return other.cwd == none
}

pub struct ResumeCwdContext {
pub:
	current_cwd            &std_path.Path
	remembered_current_cwd &std_path.Path
	allow_remember_current bool
	mode                   ?types.ResumeCwdMode
}

// Path is an allocation-free borrowed view, so its optional wrapper safely
// adapts Rust Option<&Path> without transferring the underlying string owner.
pub struct BorrowedPath {
pub:
	path ?std_path.Path
}

pub fn effective_resume_cwd_mode(configured_mode ?types.ResumeCwdMode, cwd_override BorrowedPath) ?types.ResumeCwdMode {
	if cwd_override.path != none {
		return types.ResumeCwdMode.current
	}
	return configured_mode
}

// Async app-server awaits use the existing synchronous typed transport boundary.
pub fn read_session_cwd(mut app_server codex_tui.AppServerSession, thread_id codex_protocol.ThreadId) ?std_path.PathBuf {
	// Rust's UUID-based ThreadId is Copy; this dependency owns a V string.
	// Retain its display before consuming the request ID so a failure can log it.
	id_display := thread_id.str()
	listed_thread := app_server.thread_read(thread_id, /*include_turns*/
		false) or {
		message := 'Failed to read session cwd from app server: thread_id=${id_display}, error=${err}'
		tracing.warn(&message)
		return none
	}
	// The shared Thread dependency currently stores AbsolutePathBuf as native
	// string bytes. Restore the owned PathBuf at Rust's to_path_buf boundary.
	return std_path.PathBuf.from(listed_thread.cwd.clone())
}

pub fn resolve_cwd_for_resume_or_fork(mut terminal_ui tui.Tui, config &codex_core.Config, history_cwd ?std_path.PathBuf, action cwd_prompt.CwdPromptAction, cwd_context ResumeCwdContext) !ResolveCwdOutcome {
	if mode := cwd_context.mode {
		if mode == .current {
			return ResolveCwdOutcome{ kind: .continue_, cwd: std_path.PathBuf.from(cwd_context.remembered_current_cwd.to_path_buf()) }
		}
	}
	history := history_cwd or {
		if mode := cwd_context.mode {
			if mode == .session {
				return error('failed to determine the working directory recorded for the selected session')
			}
		}
		return ResolveCwdOutcome{ kind: .continue_ }
	}
	if mode := cwd_context.mode {
		match mode {
			.session { return ResolveCwdOutcome{ kind: .continue_, cwd: history } }
			.current {}
		}
	}
	history_path := history.as_path()
	if cwds_differ(cwd_context.current_cwd, &history_path) {
		selection_outcome := cwd_prompt.run_cwd_selection_prompt(mut terminal_ui, config,
			action, cwd_context.current_cwd, &history_path, cwd_context.remembered_current_cwd,
			cwd_context.allow_remember_current)!
		return match selection_outcome.kind {
			.selection {
				selected := selection_outcome.selection.selected_cwd(cwd_context.current_cwd,
					&history_path, cwd_context.remembered_current_cwd)
				ResolveCwdOutcome{ kind: .continue_after_prompt, cwd: std_path.PathBuf.from(selected.to_path_buf()) }
			}
			.exit { ResolveCwdOutcome{ kind: .exit } }
		}
	}
	return ResolveCwdOutcome{ kind: .continue_, cwd: history }
}

pub fn cwds_differ(current_cwd &std_path.Path, session_cwd &std_path.Path) bool {
	return !path_utils.paths_match_after_normalization(current_cwd, session_cwd)
}
