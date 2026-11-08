module codex_app_server_protocol

import codex_protocol
import serde_json

// STUB: app-server-protocol/v2/shared.rs::AskForApproval variant identities.
// on_failure is retained only for the pre-existing legacy override adapter.
pub enum ApprovalPolicyKind {
	untrusted
	on_failure
	on_request
	never
	granular
}

// STUB: AskForApproval's externally tagged API enum. Every granular field uses
// the existing allocation-free core owner; no policy is reduced to a string.
// Rust derives Copy, so this value and Option<this value> remain safe by value.
pub struct ApprovalPolicy {
pub:
	kind     ApprovalPolicyKind
	granular ?codex_protocol.GranularApprovalConfig
}

// STUB: Serde Deserialize for the observed API policy shape. Reflection-based V
// JSON encoding does not implement Rust's external enum tagging; RPC transports
// must use this decoder and to_wire_value rather than encode the backing struct.
pub fn ApprovalPolicy.from_wire_value(value &serde_json.Value) !ApprovalPolicy {
	if value.is_string() {
		name := value.string_owned()!
		return match name {
			'untrusted' { ApprovalPolicy{ kind: .untrusted } }
			'on-request' { ApprovalPolicy{ kind: .on_request } }
			'never' { ApprovalPolicy{ kind: .never } }
			else { error('unknown approval policy `${name}`') }
		}
	}
	keys := value.object_keys() or { return error('approval policy must be a string or tagged object') }
	if keys.len != 1 || keys[0] != 'granular' {
		return error('approval policy must contain exactly the granular variant')
	}
	granular_key := 'granular'
	fields := value.get(&granular_key)
	if !fields.has_value {
		return error('missing granular approval policy')
	}
	_ := fields.value.object_keys() or { return error('granular approval policy must be an object') }
	sandbox_key := 'sandbox_approval'
	rules_key := 'rules'
	skill_key := 'skill_approval'
	permissions_key := 'request_permissions'
	mcp_key := 'mcp_elicitations'
	return ApprovalPolicy{
		kind:     .granular
		granular: codex_protocol.GranularApprovalConfig{
			sandbox_approval:    approval_boolean_field(fields.value, &sandbox_key, true)!
			rules:               approval_boolean_field(fields.value, &rules_key, true)!
			skill_approval:      approval_boolean_field(fields.value, &skill_key, false)!
			request_permissions: approval_boolean_field(fields.value, &permissions_key, false)!
			mcp_elicitations:    approval_boolean_field(fields.value, &mcp_key, true)!
		}
	}
}

// STUB: Serde's required/defaulted boolean fields. Unknown granular fields are
// ignored, matching the source's absence of deny_unknown_fields.
fn approval_boolean_field(fields &serde_json.Value, name &string, required bool) !bool {
	field := fields.get(name)
	if !field.has_value {
		if required {
			return error('missing granular field `${*name}`')
		}
		return false
	}
	return field.value.as_bool() or { return error('granular field `${*name}` must be a boolean') }
}

// STUB: Serde Serialize for v2/shared.rs::AskForApproval. The legacy on_failure
// value is emitted only when an older caller explicitly constructed that kind.
pub fn (policy ApprovalPolicy) to_wire_value() !serde_json.Value {
	if policy.kind != .granular {
		if policy.granular != none {
			return error('non-granular policy cannot contain granular flags')
		}
		name := match policy.kind {
			.untrusted { 'untrusted' }
			.on_failure { 'on-failure' }
			.on_request { 'on-request' }
			.never { 'never' }
			.granular { '' }
		}
		return serde_json.Value.string(name.clone())
	}
	flags := policy.granular or { return error('granular approval policy has no flags') }
	return serde_json.Value.object({
		'granular': serde_json.Value.object({
			'sandbox_approval':    serde_json.Value.boolean(flags.sandbox_approval)
			'rules':               serde_json.Value.boolean(flags.rules)
			'skill_approval':      serde_json.Value.boolean(flags.skill_approval)
			'request_permissions': serde_json.Value.boolean(flags.request_permissions)
			'mcp_elicitations':    serde_json.Value.boolean(flags.mcp_elicitations)
		})
	})
}

// STUB: guardian_subagent is Serde's input alias for the canonical AutoReview
// reviewer. Normalize old typed callers before comparing requirement membership.
pub fn (reviewer ApprovalsReviewer) canonical() ApprovalsReviewer {
	return if reviewer == .guardian_subagent { .auto_review } else { reviewer }
}

// STUB: app-server reviewer Serde wire spelling.
pub fn (reviewer ApprovalsReviewer) wire_value() string {
	return if reviewer.canonical() == .user { 'user'.clone() } else { 'auto_review'.clone() }
}

// STUB: Serde accepts guardian_subagent as an input alias and stores AutoReview.
pub fn ApprovalsReviewer.from_wire_value(value &serde_json.Value) !ApprovalsReviewer {
	name := value.string_owned()!
	return match name {
		'user' { .user }
		'auto_review', 'guardian_subagent' { .auto_review }
		else { error('unknown approvals reviewer `${name}`') }
	}
}
