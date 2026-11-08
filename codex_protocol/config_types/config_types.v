module config_types

import codex_protocol.openai_models

// STUB: Approval routing configuration.
pub enum ApprovalsReviewer {
	user
	auto_review
}

// STUB: Collaboration preset configuration.
pub struct CollaborationMode {
pub:
	mode     ModeKind
	settings Settings
}

// STUB: protocol/src/config_types.rs::Settings owns a collaboration mode's
// model, effort and optional developer instructions. ReasoningEffort retains
// its existing dependency representation until that source owner is ported.
pub struct Settings {
pub:
	model                  string
	reasoning_effort       ?openai_models.ReasoningEffort
	developer_instructions ?string
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
