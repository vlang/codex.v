module app

import codex_protocol
import codex_tui.app.exit_summary
import codex_tui.update_action

// STUB: tui/src/app.rs reexports the canonical exit-summary payloads.
pub type ResumableThread = exit_summary.ResumableThread

// STUB: tui/src/app.rs reexports the canonical exit-summary payloads.
pub type DisconnectInfo = exit_summary.DisconnectInfo

// STUB: tui/src/app.rs::ExitReason's payload variants retain their exact types.
pub enum ExitReasonKind {
	user_requested
	archived
	turn_interrupted
	thread_removed
	fatal
}

// STUB: tui/src/app.rs::ExitReason uses a tag where V cannot express mixed payload variants.
pub struct ExitReason {
pub:
	kind      ExitReasonKind
	thread_id codex_protocol.ThreadId
	message   string
}

// STUB: tui/src/app.rs::AppExitInfo preserves every returned cancellation field.
pub struct AppExitInfo {
pub:
	token_usage     codex_protocol.TokenUsage
	thread_id       ?codex_protocol.ThreadId
	resume_hint     ?ResumableThread
	disconnect_info ?DisconnectInfo
	update_action   ?update_action.UpdateAction
	exit_reason     ExitReason
}
