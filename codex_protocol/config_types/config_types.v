module config_types

// STUB: Approval routing configuration.
pub enum ApprovalsReviewer {
	user
	guardian
}

// STUB: Collaboration preset configuration.
pub struct CollaborationMode {
pub:
	mode string
}

// STUB: Effective collaboration mode kind.
pub enum ModeKind {
	default_mode
	plan
	pair_programming
	execute
}

// STUB: Multi-agent mode configuration.
pub enum MultiAgentMode {
	disabled
	v1
	v2
}

// STUB: Assistant personality configuration.
pub enum Personality {
	none
	friendly
	pragmatic
}

// STUB: Reasoning-summary preference.
pub enum ReasoningSummary {
	auto
	concise
	detailed
	none
}

// STUB: Windows sandbox configuration.
pub enum WindowsSandboxLevel {
	disabled
	restricted_token
	elevated
}
