module codex_app_server_protocol

import codex_protocol
import serde_json

fn policy_test_owned(value &string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_approval_wire_values_and_granular_flags_round_trip_as_copy_values() {
	for name in ['untrusted', 'on-request', 'never'] {
		input := serde_json.Value.string(name.clone())
		policy := ApprovalPolicy.from_wire_value(&input) or { panic(err) }
		first := policy.to_wire_value() or { panic(err) }
		second := policy.to_wire_value() or { panic(err) }
		assert first.equals(&input)
		assert second.equals(&input)
		assert input.string_owned() or { panic(err) } == name
	}
	for mask in 0 .. 32 {
		flags := codex_protocol.GranularApprovalConfig{
			sandbox_approval:    mask & 1 != 0
			rules:               mask & 2 != 0
			skill_approval:      mask & 4 != 0
			request_permissions: mask & 8 != 0
			mcp_elicitations:    mask & 16 != 0
		}
		policy := ApprovalPolicy{ kind: .granular, granular: flags }
		encoded := policy.to_wire_value() or { panic(err) }
		decoded := ApprovalPolicy.from_wire_value(&encoded) or { panic(err) }
		assert decoded == policy
		assert ApprovalPolicy.from_wire_value(&encoded) or { panic(err) } == policy
		assert policy.granular or { panic('flags moved') } == flags
	}
}

fn test_granular_decode_defaults_only_the_source_defaulted_fields() {
	fixture := '{"granular":{"sandbox_approval":true,"rules":false,"mcp_elicitations":true,"future":123}}'
	text := policy_test_owned(&fixture)
	value := serde_json.from_str(&text) or { panic(err) }
	expected := ApprovalPolicy{
		kind:     .granular
		granular: codex_protocol.GranularApprovalConfig{ sandbox_approval: true, mcp_elicitations: true }
	}
	assert ApprovalPolicy.from_wire_value(&value) or { panic(err) } == expected
	assert ApprovalPolicy.from_wire_value(&value) or { panic(err) } == expected
	assert value.to_string() == text
	assert text.contains('"future":123')
}

fn test_approval_decode_rejects_missing_wrong_and_unknown_policy_values() {
	for raw in [
		'"on-failure"',
		'"on_request"',
		'"unknown"',
		'null',
		'true',
		'{}',
		'{"granular":null}',
		'{"granular":{},"never":null}',
		'{"granular":{"rules":true,"mcp_elicitations":true}}',
		'{"granular":{"sandbox_approval":true,"mcp_elicitations":true}}',
		'{"granular":{"sandbox_approval":true,"rules":true}}',
		'{"granular":{"sandbox_approval":true,"rules":true,"mcp_elicitations":true,"skill_approval":null}}',
		'{"granular":{"sandbox_approval":true,"rules":true,"mcp_elicitations":true,"request_permissions":"false"}}',
	] {
		value := serde_json.from_str(&raw) or { panic(err) }
		if decoded := ApprovalPolicy.from_wire_value(&value) {
			assert false, 'unexpected policy ${decoded}'
		}
	}
	for invalid in [
		ApprovalPolicy{ kind: .granular },
		ApprovalPolicy{ kind: .never, granular: codex_protocol.GranularApprovalConfig{} },
	] {
		if encoded := invalid.to_wire_value() {
			assert false, 'unexpected wire value ${encoded.to_string()}'
		}
	}
}

fn test_reviewer_legacy_alias_decodes_and_serializes_canonically() {
	for name in ['auto_review', 'guardian_subagent'] {
		input := serde_json.Value.string(name.clone())
		assert ApprovalsReviewer.from_wire_value(&input) or { panic(err) } == .auto_review
		assert ApprovalsReviewer.from_wire_value(&input) or { panic(err) } == .auto_review
		assert input.string_owned() or { panic(err) } == name
	}
	assert ApprovalsReviewer.guardian_subagent.canonical() == .auto_review
	assert ApprovalsReviewer.guardian_subagent.wire_value() == 'auto_review'
	assert ApprovalsReviewer.auto_review.wire_value() == 'auto_review'
	assert ApprovalsReviewer.user.wire_value() == 'user'
}
