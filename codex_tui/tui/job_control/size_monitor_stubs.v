module job_control

import sync

// STUB: crate::tui::job_control::ResumeAction's Copy-equivalent resume intent.
enum ResumeAction {
	realign_inline
	restore_alt
}

// STUB: owned shared pending-resume/cursor state for SuspendContext::new. Native
// suspension, signal delivery and screen restoration remain untranslated.
@[heap]
struct SuspendState {
mut:
	mutex            &sync.Mutex = sync.new_mutex()
	resume_pending   ?ResumeAction
	suspend_cursor_y u16
}

// STUB: crate::tui::job_control::SuspendContext. Its constructor preserves shared
// resources initialized to None/zero; size-monitor tests never request suspension.
pub struct SuspendContext {
	state &SuspendState = unsafe { nil }
}

// STUB: SuspendContext::new initializes the source's default pending action/cursor row.
pub fn SuspendContext.new() SuspendContext {
	return SuspendContext{ state: &SuspendState{} }
}
