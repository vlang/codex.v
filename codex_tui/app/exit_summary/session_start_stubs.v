module exit_summary

import codex_protocol

// STUB: tui/src/app/exit_summary.rs::ResumableThread, the persisted resume hint.
pub struct ResumableThread {
pub:
	thread_id   codex_protocol.ThreadId
	thread_name ?string
}

// STUB: tui/src/app/exit_summary.rs::DisconnectInfo retains typed reconnect/stop guidance.
pub struct DisconnectInfo {
pub:
	command   []string
	stop_hint string
}
