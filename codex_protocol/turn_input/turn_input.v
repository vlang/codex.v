module turn_input

// STUB: Cyber access program classification.
pub enum CyberAccessProgram {
	none
	trusted
}

// STUB: Suspended-turn outcome.
pub struct SuspendTurnOutcome {
pub:
	suspended bool
}

// STUB: Turn input routing mode.
pub enum TurnInputMode {
	start
	steer
	follow_up
}

// STUB: Turn input request.
pub struct TurnInputRequest {
pub:
	text string
}

// STUB: Turn input submission result.
pub struct TurnInputSubmission {
pub:
	turn_id string
}

// STUB: Per-turn start options.
pub struct TurnStartOptions {
pub:
	trace_id ?string
}
