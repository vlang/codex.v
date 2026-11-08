module codex_app_server_protocol

import codex_protocol

// STUB: app-server-protocol/src/protocol/v2/thread.rs converts this scalar API
// enum from the identical core ThreadGoalStatus variants. Reuse that translated
// enum until the API protocol owner supplies its independent wire enum.
pub type ThreadGoalStatus = codex_protocol.ThreadGoalStatus

// STUB: app-server-protocol/src/protocol/v2/thread.rs API ThreadGoal. Unlike the
// core type, its thread_id is a string; all source API fields are retained.
pub struct ThreadGoal {
pub:
	thread_id         string @[json: 'threadId']
	objective         string
	status            ThreadGoalStatus
	token_budget      ?i64 @[json: 'tokenBudget']
	tokens_used       i64  @[json: 'tokensUsed']
	time_used_seconds i64  @[json: 'timeUsedSeconds']
	created_at        i64  @[json: 'createdAt']
	updated_at        i64  @[json: 'updatedAt']
}
