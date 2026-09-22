module thread_goal_processor

import codex_core
import codex_protocol
import codex_state

// STUB: ThreadGoalRequestProcessor is owned by app-server/thread_goal_processor.rs.
pub struct ThreadGoalRequestProcessor {}

// STUB: PendingResumeGoalState contains the goal-update decision captured for a running resume.
pub struct PendingResumeGoalState {
pub:
	emit_thread_goal_update bool
	thread_goal_state_db    ?codex_state.StateDbHandle
}

// STUB: captures whether the listener should emit a goal update and which state DB it should use.
pub fn (processor &ThreadGoalRequestProcessor) pending_resume_goal_state(thread_value &codex_core.CodexThread) PendingResumeGoalState {
	_ = processor
	config := thread_value.config()
	return PendingResumeGoalState{
		emit_thread_goal_update: config.features.enabled(.goals)
		thread_goal_state_db:    thread_value.state_db()
	}
}

// STUB: flushes source-thread goal progress before a durable fork snapshot is copied.
pub fn (processor &ThreadGoalRequestProcessor) flush_goal_progress_for_fork(source_thread_id codex_protocol.ThreadId) ! {
	_ = processor
	_ = source_thread_id
	return error('goal progress flush requires translated ThreadGoalRequestProcessor')
}

// STUB: emits an inherited goal snapshot after the fork response.
pub fn (processor &ThreadGoalRequestProcessor) emit_thread_goal_snapshot(thread_id codex_protocol.ThreadId) {
	_ = processor
	_ = thread_id
}

// STUB: emits the durable goal snapshot after a successful resume response.
pub fn (processor &ThreadGoalRequestProcessor) emit_resume_goal_snapshot(thread_id codex_protocol.ThreadId) {
	_ = processor
	_ = thread_id
}

// STUB: restores the in-memory runtime for a goal inherited by a fork.
pub fn (processor &ThreadGoalRequestProcessor) restore_inherited_goal_runtime(thread_id codex_protocol.ThreadId) {
	_ = processor
	_ = thread_id
}
