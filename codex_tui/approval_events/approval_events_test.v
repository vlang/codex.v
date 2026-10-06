module approval_events

import codex_app_server_protocol as api
import codex_tui.diff_model
import std_collections
import std_path

fn heap(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn decisions_json(values &[]api.CommandExecutionApprovalDecision) string {
	mut result := []string{cap: values.len}
	for index in 0 .. values.len { result << values[index].serialize_json() }
	return '[' + result.join(',') + ']'
}

fn test_exec_defaults_and_null_omission_contract() {
	input := heap('{"call_id":"call","command":["cargo","test"],"cwd":"/repo"}')
	event := ExecApprovalRequestEvent.deserialize_json(&input)!
	assert event.effective_approval_id() == 'call'
	assert event.serialize_json()! == '{"kind":"command","call_id":"call","turn_id":"","command":["cargo","test"],"cwd":"/repo","reason":null,"available_decisions":null}'
	decisions := event.effective_available_decisions()
	assert decisions_json(&decisions) == '["accept","cancel"]'
	assert !event.available_decisions.has_value
	assert event.turn_id == ''
}

fn test_effective_id_retains_present_empty_id() {
	call := heap('call')
	event := ExecApprovalRequestEvent{ call_id: call.clone(), approval_id: heap('') }
	assert event.effective_approval_id() == ''
	assert event.effective_approval_id() == ''
	assert event.call_id == 'call'
	assert call == 'call'
}

fn test_network_default_decisions_precedence_and_first_allow() {
	context := api.NetworkApprovalContext{ host: heap('network.example'), protocol: .https }
	prefix := api.ExecPolicyAmendment{ command: [heap('curl')] }
	permissions := api.AdditionalPermissionProfile{}
	amendments := [api.NetworkPolicyAmendment{ host: heap('denied'), action: .deny },
		api.NetworkPolicyAmendment{ host: heap('first'), action: .allow },
		api.NetworkPolicyAmendment{ host: heap('second'), action: .allow }]
	for _ in 0 .. 2 {
		decisions := ExecApprovalRequestEvent.default_available_decisions(BorrowedValue[api.NetworkApprovalContext]{ has_value: true, value: &context }, BorrowedValue[api.ExecPolicyAmendment]{ has_value: true, value: &prefix }, BorrowedValue[[]api.NetworkPolicyAmendment]{ has_value: true, value: &amendments }, BorrowedValue[api.AdditionalPermissionProfile]{ has_value: true, value: &permissions })
		assert decisions_json(&decisions) == '["accept","acceptForSession",{"applyNetworkPolicyAmendment":{"network_policy_amendment":{"host":"first","action":"allow"}}},"cancel"]'
		assert decisions[2].network_policy_amendment.host.str != amendments[1].host.str
	}
	assert amendments[0].host == 'denied'
	assert amendments[1].host == 'first'
	assert amendments[2].host == 'second'
	assert context.host == 'network.example'
	assert prefix.command == ['curl']
}

fn test_network_with_no_allow_and_present_empty_amendments() {
	context := api.NetworkApprovalContext{ host: heap('host'), protocol: .socks5_tcp }
	for amendments in [([]api.NetworkPolicyAmendment{}),
		[api.NetworkPolicyAmendment{ host: heap('denied'), action: .deny }]] {
		decisions := ExecApprovalRequestEvent.default_available_decisions(BorrowedValue[api.NetworkApprovalContext]{ has_value: true, value: &context }, BorrowedValue[api.ExecPolicyAmendment]{}, BorrowedValue[[]api.NetworkPolicyAmendment]{ has_value: true, value: &amendments }, BorrowedValue[api.AdditionalPermissionProfile]{})
		assert decisions_json(&decisions) == '["accept","acceptForSession","cancel"]'
	}
}

fn test_additional_permissions_and_execpolicy_default_branches() {
	permissions := api.AdditionalPermissionProfile{}
	prefix := api.ExecPolicyAmendment{ command: [heap('cargo'), heap('test')] }
	with_permissions := ExecApprovalRequestEvent.default_available_decisions(BorrowedValue[api.NetworkApprovalContext]{}, BorrowedValue[api.ExecPolicyAmendment]{ has_value: true, value: &prefix }, BorrowedValue[[]api.NetworkPolicyAmendment]{}, BorrowedValue[api.AdditionalPermissionProfile]{ has_value: true, value: &permissions })
	assert decisions_json(&with_permissions) == '["accept","cancel"]'
	for _ in 0 .. 2 {
		with_prefix := ExecApprovalRequestEvent.default_available_decisions(BorrowedValue[api.NetworkApprovalContext]{}, BorrowedValue[api.ExecPolicyAmendment]{ has_value: true, value: &prefix }, BorrowedValue[[]api.NetworkPolicyAmendment]{}, BorrowedValue[api.AdditionalPermissionProfile]{})
		assert decisions_json(&with_prefix) == '["accept",{"acceptWithExecpolicyAmendment":{"execpolicy_amendment":["cargo","test"]}},"cancel"]'
		assert with_prefix[1].execpolicy_amendment.command[0].str != prefix.command[0].str
	}
	assert prefix.command == ['cargo', 'test']
}

fn test_explicit_decisions_preserve_empty_order_and_payloads() {
	for wire in ['[]',
		'["decline",{"applyNetworkPolicyAmendment":{"network_policy_amendment":{"host":"denied","action":"deny"}}},"acceptForSession"]'] {
		input := heap('{"call_id":"call","command":[],"cwd":"/repo","available_decisions":' + wire + ',"network_approval_context":{"host":"host","protocol":"https"}}')
		event := ExecApprovalRequestEvent.deserialize_json(&input)!
		for _ in 0 .. 2 {
			decisions := event.effective_available_decisions()
			assert decisions_json(&decisions) == wire
		}
		assert event.available_decisions.has_value
		assert event.network_approval_context.value.host == 'host'
	}
}

const full_wire = '{"kind":"writeStdin","call_id":"call","approval_id":"approval","turn_id":"turn","environment_id":"remote","command":["curl","quoted\\\""],"cwd":"/repo","reason":"network","proposed_execpolicy_amendment":["curl"],"proposed_network_policy_amendments":[{"host":"host","action":"allow"}],"available_decisions":["accept",{"acceptWithExecpolicyAmendment":{"execpolicy_amendment":["curl"]}},{"applyNetworkPolicyAmendment":{"network_policy_amendment":{"host":"host","action":"deny"}}},"cancel"],"network_approval_context":{"host":"host","protocol":"socks5Udp"},"additional_permissions":{"network":{"enabled":true},"fileSystem":{"read":["relative"],"write":[],"globScanMaxDepth":3,"entries":[{"path":{"type":"path","path":"/read"},"access":"read"},{"path":{"type":"glob_pattern","pattern":"/repo/**/*.txt"},"access":"deny"},{"path":{"type":"special","value":{"kind":"unknown","path":"future","subpath":"nested"}},"access":"write"}]}}}'

fn test_all_exec_fields_clone_and_wire_round_trip() {
	// An ignored field after owned permission buffers must preserve every owner.
	input := heap(full_wire[..full_wire.len - 1] + ',"ignored":true}')
	event := ExecApprovalRequestEvent.deserialize_json(&input)!
	for _ in 0 .. 2 {
		copy := event.clone()
		assert copy.serialize_json()! == full_wire
		assert event.serialize_json()! == full_wire
		assert copy.call_id.str != event.call_id.str
		assert copy.command[0].str != event.command[0].str
		assert copy.proposed_execpolicy_amendment.value.command[0].str != event.proposed_execpolicy_amendment.value.command[0].str
		assert copy.network_approval_context.value.host.str != event.network_approval_context.value.host.str
		assert copy.available_decisions.value[1].execpolicy_amendment.command[0].str != event.available_decisions.value[1].execpolicy_amendment.command[0].str
		assert event.effective_approval_id() == 'approval'
	}
	assert event.call_id == 'call'
	assert input == full_wire[..full_wire.len - 1] + ',"ignored":true}'
}

fn test_exec_serde_defaults_sequences_unknowns_and_duplicates() {
	sequence := heap('["command","call",null,"",null,[],"/repo",null]')
	event := ExecApprovalRequestEvent.deserialize_json(&sequence)!
	assert event.serialize_json()! == '{"kind":"command","call_id":"call","turn_id":"","command":[],"cwd":"/repo","reason":null,"available_decisions":null}'
	unknown := heap('{"unknown":1e400,"call_id":"call","command":[],"cwd":"/repo"}')
	assert ExecApprovalRequestEvent.deserialize_json(&unknown)!.serialize_json()! == event.serialize_json()!
	for input in ['{}', '{"call_id":"call","command":null,"cwd":"/repo"}',
		'{"call_id":"call","command":[null],"cwd":"/repo"}',
		'{"kind":null,"call_id":"call","command":[],"cwd":"/repo"}',
		'{"call_id":"call","command":[],"cwd":"relative"}',
		'{"call_id":"call","command":[],"cwd":"/repo","reason":null,"reason":null}',
		'["command","call",null,"",null,[],"/repo"]',
		'["command","call",null,"",null,[],"/repo",null,null,null,null,null,null,null]'] {
		_ := ExecApprovalRequestEvent.deserialize_json(&input) or { continue }
		assert false, 'invalid exec input must fail: ${input}'
	}
}

fn test_nested_permission_defaults_aliases_and_validation() {
	// Unknown and nullable fields follow resources at each visitor level; the
	// filesystem overlay precedes network so later visits cannot discard it.
	input := heap('{"call_id":"call","command":[],"cwd":"/repo","additional_permissions":{"fileSystem":{"entries":[{"path":{"type":"special","value":{"kind":"current_working_directory","ignored":true},"ignored":true},"access":"read","ignored":true}],"read":null,"ignored":true},"ignored":true,"network":{"enabled":null,"ignored":true}},"ignored":true}')
	event := ExecApprovalRequestEvent.deserialize_json(&input)!
	assert event.serialize_json()! == '{"kind":"command","call_id":"call","turn_id":"","command":[],"cwd":"/repo","reason":null,"available_decisions":null,"additional_permissions":{"network":{"enabled":null},"fileSystem":{"read":null,"write":null,"entries":[{"path":{"type":"special","value":{"kind":"project_roots","subpath":null}},"access":"read"}]}}}'
	for depth in ['0', '-1', '1.0', '18446744073709551616'] {
		bad := '{"call_id":"call","command":[],"cwd":"/repo","additional_permissions":{"fileSystem":{"globScanMaxDepth":' + depth + '}}}'
		_ := ExecApprovalRequestEvent.deserialize_json(&bad) or { continue }
		assert false, 'invalid NonZeroUsize must fail'
	}
}

fn test_struct_visitors_validate_values_before_sequence_length() {
	for input in ['["command",7]',
		'["command",7,null,"",null,[],"/repo",null,null,null,null,null,null,null]'] {
		_ := ExecApprovalRequestEvent.deserialize_json(&input) or {
			assert err.msg() == 'invalid type: integer `7`, expected a string'
			continue
		}
		assert false, 'earlier invalid exec value must fail before length validation'
	}
	for input in ['[7]', '[7,"",{},null,null,null]'] {
		_ := ApplyPatchApprovalRequestEvent.deserialize_json(&input) or {
			assert err.msg() == 'invalid type: integer `7`, expected a string'
			continue
		}
		assert false, 'earlier invalid patch value must fail before length validation'
	}
	missing := heap('{}')
	_ := ApplyPatchApprovalRequestEvent.deserialize_json(&missing) or {
		assert err.msg() == 'missing field `call_id`'
		return
	}
	assert false, 'required fields must fail in declaration order'
}

fn test_patch_serde_clone_and_all_file_changes() {
	input := heap('{"call_id":"patch","turn_id":"turn","changes":{"add.txt":{"type":"add","content":"new"},"delete.txt":{"type":"delete","content":"old"},"update.txt":{"type":"update","unified_diff":"@@","move_path":"renamed.txt"}},"reason":"edit","grant_root":"relative/root","ignored":true}')
	event := ApplyPatchApprovalRequestEvent.deserialize_json(&input)!
	for _ in 0 .. 2 {
		copy := event.clone()
		assert copy.changes.equals(&event.changes)
		assert copy.serialize_json()! == event.serialize_json()!
		assert copy.call_id.str != event.call_id.str
		original_key := event.changes.keys()[0]
		copied_key := copy.changes.keys()[0]
		original_text := original_key.to_str()
		copied_text := copied_key.to_str()
		assert original_text.value.str != copied_text.value.str
	}
	assert event.changes.len() == 3
	assert event.call_id == 'patch'
	assert input.contains('renamed.txt')
}

fn test_patch_defaults_duplicate_native_paths_and_required_fields() {
	input := heap('{"call_id":"patch","changes":{"a//b":{"type":"add","content":"first"},"a/b/.":{"type":"delete","content":"last"}}}')
	event := ApplyPatchApprovalRequestEvent.deserialize_json(&input)!
	assert event.changes.len() == 1
	assert event.serialize_json()! == '{"call_id":"patch","turn_id":"","changes":{"a//b":{"type":"delete","content":"last"}}}'
	sequence := heap('["patch","",{}]')
	assert ApplyPatchApprovalRequestEvent.deserialize_json(&sequence)!.serialize_json()! == '{"call_id":"patch","turn_id":"","changes":{}}'
	for invalid in ['{"call_id":"patch"}', '{"changes":{}}', '{"call_id":"patch","changes":null}',
		'{"call_id":"patch","changes":{},"reason":null,"reason":null}', '["patch",""]',
		'["patch","",{},null,null,null]'] {
		_ := ApplyPatchApprovalRequestEvent.deserialize_json(&invalid) or { continue }
		assert false, 'invalid patch must fail'
	}
}

fn test_patch_native_path_serialization_failure() {
	$if !windows {
		bad_path := std_path.PathBuf.from([u8(0xff), `x`].bytestr())
		mut changes := std_collections.HashMap[std_path.PathBuf, diff_model.FileChange]{}
		changes.insert(bad_path, diff_model.FileChange(diff_model.Add{ content: heap('content') }))
		event := ApplyPatchApprovalRequestEvent{ call_id: heap('call'), changes: changes }
		_ := event.serialize_json() or {
			assert err.msg() == 'path contains invalid UTF-8 characters'
			return
		}
		assert false, 'invalid native key must fail serialization'
	}
}

fn test_external_decision_payloads_and_unit_enum_validation() {
	for input in ['{"accept":null}', '"accept"', '{"acceptWithExecpolicyAmendment":[["cargo","test"]]}',
		'{"applyNetworkPolicyAmendment":{"network_policy_amendment":["host","deny"]}}'] {
		decision := api.CommandExecutionApprovalDecision.deserialize_json(&input)!
		encoded := decision.serialize_json()
		copy := api.CommandExecutionApprovalDecision.deserialize_json(&encoded)!
		assert copy.serialize_json() == encoded
	}
	for input in ['{"accept":{}}', '{"acceptWithExecpolicyAmendment":{}}',
		'{"applyNetworkPolicyAmendment":{"network_policy_amendment":{"host":"host","action":"unknown"}}}',
		'"unknown"', '{"accept":null,"cancel":null}'] {
		_ := api.CommandExecutionApprovalDecision.deserialize_json(&input) or { continue }
		assert false, 'invalid decision must fail'
	}
}

fn test_external_decision_visits_first_variant_before_extra_entries() {
	inputs := ['{"accept":{},"cancel":null}', '{"unknown":null,"accept":null}',
		'{"acceptWithExecpolicyAmendment":{},"cancel":null}',
		'{"acceptWithExecpolicyAmendment":{"execpolicy_amendment":[7]},"cancel":null}',
		'{"accept":null,"cancel":null}',
		'{"acceptWithExecpolicyAmendment":{"execpolicy_amendment":[]},"cancel":null}']
	expected := ['expected unit variant', 'unknown approval decision: unknown',
		'missing field `execpolicy_amendment`', 'invalid type: integer `7`, expected a string',
		'expected externally tagged enum with one entry',
		'expected externally tagged enum with one entry']
	for index, fixture in inputs {
		input := heap(fixture.clone())
		for _ in 0 .. 2 {
			_ := api.CommandExecutionApprovalDecision.deserialize_json(&input) or {
				assert err.msg() == expected[index]
				continue
			}
			assert false, 'the enum must reject ${fixture}'
		}
		assert input == fixture
	}
}

fn test_other_enum_visitors_finish_after_tag_and_payload_validation() {
	for input in ['{"command":null,"writeStdin":null}', '{"command":{},"writeStdin":null}'] {
		_ := api.CommandExecutionApprovalKind.deserialize_json(&input) or {
			assert err.msg() == if input.contains('{}') {
				'expected unit variant'
			} else {
				'expected externally tagged enum with one entry'
			}
			continue
		}
		assert false, 'kind enum with a second entry must fail'
	}
	for input in ['{"host":"host","protocol":{"unknown":null,"https":null}}',
		'{"host":"host","protocol":{"http":null,"https":null}}'] {
		_ := api.NetworkApprovalContext.deserialize_json(&input) or {
			assert err.msg() == if input.contains('unknown') {
				'unknown network approval protocol: unknown'
			} else {
				'expected externally tagged enum with one entry'
			}
			continue
		}
		assert false, 'protocol enum with a second entry must fail'
	}
	for action in ['{"allow":{},"deny":null}', '{"allow":null,"deny":null}'] {
		input := '{"host":"host","action":' + action + '}'
		_ := api.NetworkPolicyAmendment.deserialize_json(&input) or {
			assert err.msg() == if action.contains('{}') {
				'expected unit variant'
			} else {
				'expected externally tagged enum with one entry'
			}
			continue
		}
		assert false, 'action enum with a second entry must fail'
	}
	for access in ['{"read":{},"write":null}', '{"read":null,"write":null}'] {
		input := '{"path":{"type":"path","path":"/read"},"access":' + access + '}'
		_ := api.FileSystemSandboxEntry.deserialize_json(&input) or {
			assert err.msg() == if access.contains('{}') {
				'expected unit variant'
			} else {
				'expected externally tagged enum with one entry'
			}
			continue
		}
		assert false, 'access enum with a second entry must fail'
	}
}
