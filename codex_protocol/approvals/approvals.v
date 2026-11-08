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

// STUB: Source of a guardian assessment decision.
pub enum GuardianAssessmentDecisionSource {
	agent
}

// STUB: Guardian assessment outcome.
pub enum GuardianAssessmentOutcome {
	allow
	deny
}

// STUB: Guardian assessment lifecycle status.
pub enum GuardianAssessmentStatus {
	in_progress
	approved
	denied
	timed_out
	aborted
}

// STUB: Source of the guardian-reviewed command.
pub enum GuardianCommandSource {
	shell
	unified_exec
}

// STUB: Guardian risk classification.
pub enum GuardianRiskLevel {
	low
	medium
	high
	critical
}

// STUB: User authorization attached to a guardian assessment.
pub enum GuardianUserAuthorization {
	unknown
	low
	medium
	high
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
	socks5_tcp
	socks5_udp
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
