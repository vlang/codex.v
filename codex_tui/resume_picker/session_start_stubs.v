module resume_picker

import codex_app_server_protocol
import codex_protocol
import std_path

// STUB: tui/src/resume_picker.rs::SessionTarget retains all selected metadata.
pub struct SessionTarget {
pub:
	path         ?std_path.PathBuf
	thread_id    codex_protocol.ThreadId
	cwd          ?std_path.PathBuf
	history_mode ?codex_app_server_protocol.ThreadHistoryMode
}

// STUB: SessionTarget::display_label uses Path::display or the exact thread ID fallback.
pub fn (target &SessionTarget) display_label() string {
	if path := target.path { return path.as_path().to_string_lossy() }
	return 'thread ${target.thread_id}'
}
