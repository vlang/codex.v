module cwd_prompt

import codex_core
import codex_tui.tui
import std_path
import sync

// STUB: tui/src/cwd_prompt.rs::CwdPromptAction, the Copy prompt context.
pub enum CwdPromptAction {
	resume
	fork
}

// STUB: cwd_prompt.rs::CwdSelection, preserving every selection payload.
pub enum CwdSelection {
	current
	session
	current_and_remember
	session_and_remember
}

// STUB: cwd_prompt.rs::CwdPromptOutcome's payload tag.
pub enum CwdPromptOutcomeKind {
	selection
	exit
}

// STUB: cwd_prompt.rs::CwdPromptOutcome retains the selected Copy enum.
pub struct CwdPromptOutcome {
pub:
	kind      CwdPromptOutcomeKind
	selection CwdSelection
}

// STUB: CwdSelection::selected_cwd borrows the actual selected native path.
pub fn (selection CwdSelection) selected_cwd(current_cwd &std_path.Path, session_cwd &std_path.Path, remembered_current_cwd &std_path.Path) &std_path.Path {
	return match selection {
		.current { current_cwd }
		.current_and_remember { remembered_current_cwd }
		.session, .session_and_remember { session_cwd }
	}
}

// STUB: source-shaped prompt call record for the untranslated interactive runtime.
pub struct SessionResumePromptCall {
pub:
	action                 CwdPromptAction
	current_cwd            std_path.PathBuf
	session_cwd            std_path.PathBuf
	remembered_current_cwd std_path.PathBuf
	allow_remember_current bool
}

// STUB: fixture-only typed outcome at the real interactive prompt boundary.
@[heap]
struct SessionResumePromptFixture {
mut:
	mutex   &sync.Mutex = sync.new_mutex()
	enabled bool
	failed  bool
	error   string
	outcome CwdPromptOutcome
	calls   []SessionResumePromptCall
}

// STUB: the fixture does not initialize a terminal or read input.
const session_resume_prompt_fixture = &SessionResumePromptFixture{}

// STUB: run_cwd_selection_prompt keeps its borrowed inputs and Result shape.
// The real terminal event loop and persistence await cwd_prompt.rs translation.
// No configured test response means failure, rather than an invented selection.
pub fn run_cwd_selection_prompt(mut terminal_ui tui.Tui, config &codex_core.Config, action CwdPromptAction, current_cwd &std_path.Path, session_cwd &std_path.Path, remembered_current_cwd &std_path.Path, allow_remember_current bool) !CwdPromptOutcome {
	_ = &terminal_ui
	_ = config
	mut fixture := unsafe { session_resume_prompt_fixture }
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	fixture.calls << SessionResumePromptCall{
		action:                 action
		current_cwd:            std_path.PathBuf.from(current_cwd.to_path_buf())
		session_cwd:            std_path.PathBuf.from(session_cwd.to_path_buf())
		remembered_current_cwd: std_path.PathBuf.from(remembered_current_cwd.to_path_buf())
		allow_remember_current: allow_remember_current
	}
	if !fixture.enabled {
		return error('interactive cwd selection runtime is not translated')
	}
	if fixture.failed {
		return error(fixture.error.clone())
	}
	return fixture.outcome
}

// STUB: configure a typed prompt outcome without mutating translated target fields.
pub fn session_resume_configure_prompt(outcome CwdPromptOutcome, failure ?string) {
	mut fixture := unsafe { session_resume_prompt_fixture }
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	fixture.enabled = true
	fixture.outcome = outcome
	fixture.failed = failure != none
	fixture.error = failure or { ''.clone() }
	fixture.calls.clear()
}

// STUB: disable fixture responses and clear observed calls between tests.
pub fn session_resume_reset_prompt() {
	mut fixture := unsafe { session_resume_prompt_fixture }
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	fixture.enabled = false
	fixture.failed = false
	fixture.error = ''.clone()
	fixture.calls.clear()
}

// STUB: return independent observations of the prompt's typed API calls.
pub fn session_resume_prompt_calls() []SessionResumePromptCall {
	mut fixture := unsafe { session_resume_prompt_fixture }
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	mut calls := []SessionResumePromptCall{cap: fixture.calls.len}
	for index in 0 .. fixture.calls.len {
		call := &fixture.calls[index]
		calls << SessionResumePromptCall{ action: call.action, current_cwd: call.current_cwd.clone(), session_cwd: call.session_cwd.clone(), remembered_current_cwd: call.remembered_current_cwd.clone(), allow_remember_current: call.allow_remember_current }
	}
	return calls
}
