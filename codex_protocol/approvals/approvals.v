module approvals

// STUB: Approval event payloads are placeholders for the approvals module port.
pub struct ApplyPatchApprovalRequestEvent {
pub:
	id string
}

// STUB: Approval event payloads are placeholders for the approvals module port.
pub struct ExecApprovalRequestEvent {
pub:
	id string
}

// STUB: MCP elicitation payload.
pub struct ElicitationRequestEvent {
pub:
	server_name string
}

// STUB: MCP elicitation action.
pub enum ElicitationAction {
	accept
	decline
	cancel
}

// STUB: Exec-policy amendment payload.
pub struct ExecPolicyAmendment {
pub:
	rule string
}

// STUB: Guardian assessment payload.
pub struct GuardianAssessmentEvent {
pub:
	id string
}

// STUB: Guardian assessment action.
pub enum GuardianAssessmentAction {
	approve
	deny
	ask_user
}

// STUB: Source of a guardian assessment decision.
pub enum GuardianAssessmentDecisionSource {
	model
	policy
	user
}

// STUB: Guardian assessment outcome.
pub enum GuardianAssessmentOutcome {
	approved
	denied
	escalated
}

// STUB: Guardian assessment lifecycle status.
pub enum GuardianAssessmentStatus {
	pending
	completed
	failed
}

// STUB: Source of the guardian-reviewed command.
pub enum GuardianCommandSource {
	agent
	user
}

// STUB: Guardian risk classification.
pub enum GuardianRiskLevel {
	low
	medium
	high
	critical
}

// STUB: User authorization attached to a guardian assessment.
pub struct GuardianUserAuthorization {
pub:
	authorized bool
}

// STUB: Context attached to a network approval.
pub struct NetworkApprovalContext {
pub:
	host string
}

// STUB: Protocol used by a network approval.
pub enum NetworkApprovalProtocol {
	http
	https
	tcp
	udp
}

// STUB: Network policy amendment payload.
pub struct NetworkPolicyAmendment {
pub:
	host   string
	action NetworkPolicyRuleAction
}

// STUB: Network policy rule action.
pub enum NetworkPolicyRuleAction {
	allow
	deny
}
