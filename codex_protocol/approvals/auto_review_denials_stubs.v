module approvals

import codex_protocol.request_permissions
import codex_utils_absolute_path
import codex_utils_path_uri

// STUB: protocol/src/approvals.rs::GuardianAssessmentAction's seven payload variants.
// Typed V variants retain each field and its owner. Rust's serde `type` discriminator
// uses command/execve/write_stdin/apply_patch/network_access/mcp_tool_call/request_permissions;
// the complete approvals serializer/schema port remains untranslated. V's default
// sum-type JSON discriminator is not the Rust wire representation.
pub type GuardianAssessmentAction = GuardianCommandAction
	| GuardianExecveAction
	| GuardianWriteStdinAction
	| GuardianApplyPatchAction
	| GuardianNetworkAccessAction
	| GuardianMcpToolCallAction
	| GuardianRequestPermissionsAction

// STUB: GuardianAssessmentAction::Command, serialized with type="command" in Rust.
pub struct GuardianCommandAction {
pub:
	source  GuardianCommandSource
	command string
	cwd     codex_utils_path_uri.LegacyAppPathString
}

// STUB: GuardianAssessmentAction::Execve, serialized with type="execve" in Rust.
pub struct GuardianExecveAction {
pub:
	source  GuardianCommandSource
	program string
	argv    []string
	cwd     codex_utils_absolute_path.AbsolutePathBuf
}

// STUB: GuardianAssessmentAction::WriteStdin, serialized with type="write_stdin" in Rust.
// A child approval for input to an existing command execution item.
pub struct GuardianWriteStdinAction {
pub:
	approval_id string
	process_id  string
	stdin       string
	// Launch directory of the existing terminal, not its current working directory.
	cwd codex_utils_path_uri.PathUri
}

// STUB: GuardianAssessmentAction::ApplyPatch, serialized with type="apply_patch" in Rust.
pub struct GuardianApplyPatchAction {
pub:
	cwd   codex_utils_path_uri.LegacyAppPathString
	files []codex_utils_path_uri.LegacyAppPathString
}

// STUB: GuardianAssessmentAction::NetworkAccess, serialized with type="network_access" in Rust.
pub struct GuardianNetworkAccessAction {
pub:
	target   string
	host     string
	protocol NetworkApprovalProtocol
	port     u16
}

// STUB: GuardianAssessmentAction::McpToolCall, serialized with type="mcp_tool_call" in Rust.
pub struct GuardianMcpToolCallAction {
pub:
	server         string
	tool_name      string
	connector_id   ?string
	connector_name ?string
	tool_title     ?string
}

// STUB: GuardianAssessmentAction::RequestPermissions, type="request_permissions" in Rust.
pub struct GuardianRequestPermissionsAction {
pub:
	reason      ?string
	permissions request_permissions.RequestPermissionProfile
}

// STUB: protocol/src/approvals.rs::GuardianReviewReason's source-shaped variants;
// serde's fallback of unknown wire variants to Unknown awaits the serializer port.
// Why this approval needs a fresh Guardian assessment.
pub enum GuardianReviewReason {
	policy
	fresh_required
	missing_score
	stale_score
	invalid_score
	incompatible_compaction
	elevated_risk
	scoring_failure
	authorization_changed
	unknown
}

// STUB: protocol/src/approvals.rs::GuardianAssessmentEvent; retains all lifecycle metadata.
// Optional fields preserve Rust defaults/omission names. Its action's Rust-tagged JSON
// conversion remains part of the untranslated approvals serializer, described above.
pub struct GuardianAssessmentEvent {
pub mut:
	// Request-scoped trigger; absent in events recorded by older clients.
	review_reason ?GuardianReviewReason @[omitempty]
	// Stable identifier for this guardian review lifecycle.
	id string
	// Thread item being reviewed, when the review maps to a concrete item.
	target_item_id ?string @[omitempty]
	// Trusted plugin attribution for command items synthesized from this review.
	plugin_id ?string @[omitempty]
	// Safe plugin-relative path for command items synthesized from this review.
	script_path ?string @[omitempty]
	// Turn ID that this assessment belongs to.
	// Defaults to empty for backwards compatibility, as Rust's serde(default).
	turn_id         string
	started_at_ms   i64
	completed_at_ms ?i64 @[omitempty]
	status          GuardianAssessmentStatus
	// Coarse risk label. Omitted while the assessment is in progress.
	risk_level ?GuardianRiskLevel @[omitempty]
	// How directly the transcript authorizes the reviewed action.
	user_authorization ?GuardianUserAuthorization @[omitempty]
	// Human-readable explanation of the final assessment. Omitted while in progress.
	rationale ?string @[omitempty]
	// Source that produced the terminal assessment decision.
	decision_source ?GuardianAssessmentDecisionSource @[omitempty]
	// Canonical action payload that was reviewed.
	action GuardianAssessmentAction
}
