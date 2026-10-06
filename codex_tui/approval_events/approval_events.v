// TUI-owned approval request models used while rendering and queueing prompts.
//
// These structs normalize app-server request params into the shape the TUI
// needs while an approval may be deferred behind streaming output. Exec
// approvals keep app-server decision and permission types; patch approvals add
// the file-change display model collected from nearby thread items.
module approval_events

import codex_app_server_protocol as api
import codex_tui.diff_model
import codex_utils_absolute_path
import serde_json
import std_collections
import std_path

// Tagged owned options preserve None versus Some(empty) for composite payloads.
// V3 cannot safely unwrap a borrowed ?T for every resource-owning T; accessing a
// tagged payload by reference keeps Rust's owned fields and shared borrows intact.
pub struct OptionalValue[T] {
pub:
	has_value bool
	value     T
}

// Rust Option<&T>/Option<&[T]> is a non-owning view. The referenced owner must
// outlive the call; absent views never dereference their nil payload.
pub struct BorrowedValue[T] {
pub:
	has_value bool
	value     &T = unsafe { nil }
}

// V has no pub(crate) visibility; public declarations allow sibling TUI modules.
// Generated formatting supplies Debug; explicit methods below implement serde/Clone.
pub struct ExecApprovalRequestEvent {
pub:
	kind                               api.CommandExecutionApprovalKind = .command
	call_id                            string
	approval_id                        ?string
	turn_id                            string
	environment_id                     ?string
	command                            []string
	cwd                                codex_utils_absolute_path.AbsolutePathBuf
	reason                             ?string
	proposed_execpolicy_amendment      OptionalValue[api.ExecPolicyAmendment]
	proposed_network_policy_amendments OptionalValue[[]api.NetworkPolicyAmendment]
	available_decisions                OptionalValue[[]api.CommandExecutionApprovalDecision]
	network_approval_context           OptionalValue[api.NetworkApprovalContext]
	additional_permissions             OptionalValue[api.AdditionalPermissionProfile]
}

pub fn (event &ExecApprovalRequestEvent) effective_approval_id() string {
	if approval := event.approval_id { return approval.clone() }
	return event.call_id.clone()
}

pub fn (event &ExecApprovalRequestEvent) effective_available_decisions() []api.CommandExecutionApprovalDecision {
	if event.available_decisions.has_value {
		mut decisions := []api.CommandExecutionApprovalDecision{cap: event.available_decisions.value.len}
		for index in 0 .. event.available_decisions.value.len {
			decisions << event.available_decisions.value[index].clone()
		}
		return decisions
	}
	return ExecApprovalRequestEvent.default_available_decisions(
		BorrowedValue[api.NetworkApprovalContext]{ has_value: event.network_approval_context.has_value, value: &event.network_approval_context.value },
		BorrowedValue[api.ExecPolicyAmendment]{ has_value: event.proposed_execpolicy_amendment.has_value, value: &event.proposed_execpolicy_amendment.value },
		BorrowedValue[[]api.NetworkPolicyAmendment]{ has_value: event.proposed_network_policy_amendments.has_value, value: &event.proposed_network_policy_amendments.value },
		BorrowedValue[api.AdditionalPermissionProfile]{ has_value: event.additional_permissions.has_value, value: &event.additional_permissions.value },
	)
}

pub fn ExecApprovalRequestEvent.default_available_decisions(network_approval_context BorrowedValue[api.NetworkApprovalContext], proposed_execpolicy_amendment BorrowedValue[api.ExecPolicyAmendment], proposed_network_policy_amendments BorrowedValue[[]api.NetworkPolicyAmendment], additional_permissions BorrowedValue[api.AdditionalPermissionProfile]) []api.CommandExecutionApprovalDecision {
	if network_approval_context.has_value {
		mut decisions := [api.CommandExecutionApprovalDecision{ kind: .accept },
			api.CommandExecutionApprovalDecision{ kind: .accept_for_session }]
		if proposed_network_policy_amendments.has_value {
			for amendment in *proposed_network_policy_amendments.value {
				if amendment.action == .allow {
					decisions << api.CommandExecutionApprovalDecision{ kind: .apply_network_policy_amendment, network_policy_amendment: amendment.clone() }
					break
				}
			}
		}
		decisions << api.CommandExecutionApprovalDecision{ kind: .cancel }
		return decisions
	}
	if additional_permissions.has_value {
		return [api.CommandExecutionApprovalDecision{ kind: .accept },
			api.CommandExecutionApprovalDecision{ kind: .cancel }]
	}
	mut decisions := [api.CommandExecutionApprovalDecision{ kind: .accept }]
	if proposed_execpolicy_amendment.has_value {
		decisions << api.CommandExecutionApprovalDecision{ kind: .accept_with_execpolicy_amendment, execpolicy_amendment: proposed_execpolicy_amendment.value.clone() }
	}
	decisions << api.CommandExecutionApprovalDecision{ kind: .cancel }
	return decisions
}

pub struct ApplyPatchApprovalRequestEvent {
pub:
	call_id    string
	turn_id    string
	changes    std_collections.HashMap[std_path.PathBuf, diff_model.FileChange]
	reason     ?string
	grant_root ?std_path.PathBuf
}

// Rust's derived Clone creates independent owners for every resource field.
pub fn (event &ExecApprovalRequestEvent) clone() ExecApprovalRequestEvent {
	mut amendments := OptionalValue[[]api.NetworkPolicyAmendment]{}
	if event.proposed_network_policy_amendments.has_value {
		mut copied := []api.NetworkPolicyAmendment{cap: event.proposed_network_policy_amendments.value.len}
		for index in 0 .. event.proposed_network_policy_amendments.value.len {
			copied << event.proposed_network_policy_amendments.value[index].clone()
		}
		amendments = OptionalValue[[]api.NetworkPolicyAmendment]{ has_value: true, value: copied }
	}
	return ExecApprovalRequestEvent{
		kind:                               event.kind
		call_id:                            event.call_id.clone()
		approval_id:                        if value := event.approval_id {
			value.clone()
		} else {
			none
		}
		turn_id:                            event.turn_id.clone()
		environment_id:                     if value := event.environment_id {
			value.clone()
		} else {
			none
		}
		command:                            api.approval_events_clone_strings(&event.command)
		cwd:                                event.cwd.clone()
		reason:                             if value := event.reason { value.clone() } else { none }
		proposed_execpolicy_amendment:      if event.proposed_execpolicy_amendment.has_value {
			OptionalValue[api.ExecPolicyAmendment]{ has_value: true, value: event.proposed_execpolicy_amendment.value.clone() }
		} else {
			OptionalValue[api.ExecPolicyAmendment]{}
		}
		proposed_network_policy_amendments: amendments
		available_decisions:                if event.available_decisions.has_value {
			OptionalValue[[]api.CommandExecutionApprovalDecision]{ has_value: true, value: event.effective_available_decisions() }
		} else {
			OptionalValue[[]api.CommandExecutionApprovalDecision]{}
		}
		network_approval_context:           if event.network_approval_context.has_value {
			OptionalValue[api.NetworkApprovalContext]{ has_value: true, value: event.network_approval_context.value.clone() }
		} else {
			OptionalValue[api.NetworkApprovalContext]{}
		}
		additional_permissions:             if event.additional_permissions.has_value {
			OptionalValue[api.AdditionalPermissionProfile]{ has_value: true, value: event.additional_permissions.value.clone() }
		} else {
			OptionalValue[api.AdditionalPermissionProfile]{}
		}
	}
}

pub fn (event &ApplyPatchApprovalRequestEvent) clone() ApplyPatchApprovalRequestEvent {
	mut changes := std_collections.HashMap[std_path.PathBuf, diff_model.FileChange]{}
	for key in event.changes.keys() {
		change := event.changes.get(key)
		changes.insert(key.clone(), change.value.clone())
	}
	return ApplyPatchApprovalRequestEvent{
		call_id:    event.call_id.clone()
		turn_id:    event.turn_id.clone()
		changes:    changes
		reason:     if value := event.reason {
			value.clone()
		} else {
			none
		}
		grant_root: if path := event.grant_root { path.clone() } else { none }
	}
}

// Serde serializes kind/turn_id defaults, reason and available_decisions as null,
// and omits only fields annotated skip_serializing_if = "Option::is_none".
pub fn (event &ExecApprovalRequestEvent) serialize_json() !string {
	mut fields := ['"kind":' + event.kind.serialize_json(),
		'"call_id":' + serde_json.quote_string(&event.call_id)]
	if value := event.approval_id { fields << '"approval_id":' + serde_json.quote_string(&value) }
	fields << '"turn_id":' + serde_json.quote_string(&event.turn_id)
	if value := event.environment_id {
		fields << '"environment_id":' + serde_json.quote_string(&value)
	}
	fields << '"command":' + api.approval_events_strings_json(&event.command)
	fields << '"cwd":' + event.cwd.serialize_json()!
	fields << '"reason":' + if value := event.reason {
		serde_json.quote_string(&value)
	} else {
		'null'
	}
	if event.proposed_execpolicy_amendment.has_value {
		fields << '"proposed_execpolicy_amendment":' + event.proposed_execpolicy_amendment.value.serialize_json()
	}
	if event.proposed_network_policy_amendments.has_value {
		mut values := []string{cap: event.proposed_network_policy_amendments.value.len}
		for index in 0 .. event.proposed_network_policy_amendments.value.len {
			values << event.proposed_network_policy_amendments.value[index].serialize_json()
		}
		fields << '"proposed_network_policy_amendments":[' + values.join(',') + ']'
	}
	mut available := 'null'
	if event.available_decisions.has_value {
		mut values := []string{cap: event.available_decisions.value.len}
		for index in 0 .. event.available_decisions.value.len {
			values << event.available_decisions.value[index].serialize_json()
		}
		available = '[' + values.join(',') + ']'
	}
	fields << '"available_decisions":' + available
	if event.network_approval_context.has_value {
		fields << '"network_approval_context":' + event.network_approval_context.value.serialize_json()
	}
	if event.additional_permissions.has_value {
		fields << '"additional_permissions":' + event.additional_permissions.value.serialize_json()!
	}
	return '{' + fields.join(',') + '}'
}

pub fn (event &ApplyPatchApprovalRequestEvent) serialize_json() !string {
	mut pairs := []string{cap: event.changes.len()}
	for key in event.changes.keys() {
		change := event.changes.get(key)
		pairs << key.serialize_json()! + ':' + change.value.serialize_json()!
	}
	mut fields := ['"call_id":' + serde_json.quote_string(&event.call_id),
		'"turn_id":' + serde_json.quote_string(&event.turn_id), '"changes":{' + pairs.join(',') + '}']
	if value := event.reason { fields << '"reason":' + serde_json.quote_string(&value) }
	if value := event.grant_root { fields << '"grant_root":' + value.serialize_json()! }
	return '{' + fields.join(',') + '}'
}

// Derived Deserialize accepts maps or positional sequences. Defaults apply only
// where Rust annotates them; map-absent Option fields still become None. Known
// duplicate fields error even when their first value was null; unknowns are ignored.
// Conditional guards avoid V3's incorrect cleanup of function-scope mutable
// owners on a loop continue while preserving serde's ordered field visitation.
pub fn ExecApprovalRequestEvent.deserialize_json(text &string) !ExecApprovalRequestEvent {
	names := ['kind', 'call_id', 'approval_id', 'turn_id', 'environment_id', 'command', 'cwd',
		'reason', 'proposed_execpolicy_amendment', 'proposed_network_policy_amendments',
		'available_decisions', 'network_approval_context', 'additional_permissions']
	mut seen := map[string]bool{}
	mut kind := api.CommandExecutionApprovalKind.command
	mut call_id := ?string(none)
	mut approval_id := ?string(none)
	mut turn_id := ''.clone()
	mut environment_id := ?string(none)
	mut command := ?[]string(none)
	mut cwd := ?codex_utils_absolute_path.AbsolutePathBuf(none)
	mut reason := ?string(none)
	mut execpolicy := OptionalValue[api.ExecPolicyAmendment]{}
	mut network_amendments := OptionalValue[[]api.NetworkPolicyAmendment]{}
	mut decisions := OptionalValue[[]api.CommandExecutionApprovalDecision]{}
	mut network := OptionalValue[api.NetworkApprovalContext]{}
	mut permissions := OptionalValue[api.AdditionalPermissionProfile]{}
	input := api.approval_events_struct_fields(text, &names)!
	for field in input.fields {
		if field.name in names { api.approval_events_check_duplicate(mut seen, &field.name)! }
		is_null := field.value.text == 'null'
		match field.name {
			'kind' { kind = api.CommandExecutionApprovalKind.deserialize_json(&field.value.text)! }
			'call_id' { call_id = field.value.string_owned()! }
			'approval_id' {
				if !is_null { approval_id = field.value.string_owned()! }
			}
			'turn_id' { turn_id = field.value.string_owned()! }
			'environment_id' {
				if !is_null { environment_id = field.value.string_owned()! }
			}
			'command' { command = api.approval_events_strings(&field.value.text)! }
			'cwd' {
				cwd = codex_utils_absolute_path.AbsolutePathBuf.deserialize_json(&field.value.text)!
			}
			'reason' {
				if !is_null { reason = field.value.string_owned()! }
			}
			'proposed_execpolicy_amendment' {
				if !is_null {
					execpolicy = OptionalValue[api.ExecPolicyAmendment]{ has_value: true, value: api.ExecPolicyAmendment.deserialize_json(&field.value.text)! }
				}
			}
			'proposed_network_policy_amendments' {
				if !is_null {
					mut values := []api.NetworkPolicyAmendment{}
					for item in field.value.sequence_values()! {
						values << api.NetworkPolicyAmendment.deserialize_json(&item.text)!
					}
					network_amendments = OptionalValue[[]api.NetworkPolicyAmendment]{ has_value: true, value: values }
				}
			}
			'available_decisions' {
				if !is_null {
					mut values := []api.CommandExecutionApprovalDecision{}
					for item in field.value.sequence_values()! {
						values << api.CommandExecutionApprovalDecision.deserialize_json(&item.text)!
					}
					decisions = OptionalValue[[]api.CommandExecutionApprovalDecision]{ has_value: true, value: values }
				}
			}
			'network_approval_context' {
				if !is_null {
					network = OptionalValue[api.NetworkApprovalContext]{ has_value: true, value: api.NetworkApprovalContext.deserialize_json(&field.value.text)! }
				}
			}
			'additional_permissions' {
				if !is_null {
					permissions = OptionalValue[api.AdditionalPermissionProfile]{ has_value: true, value: api.AdditionalPermissionProfile.deserialize_json(&field.value.text)! }
				}
			}
			else {}
		}
	}
	input.validate_length(8, names.len)!
	return ExecApprovalRequestEvent{ kind: kind, call_id: call_id or { return error('missing field `call_id`') }, approval_id: approval_id, turn_id: turn_id, environment_id: environment_id, command: command or { return error('missing field `command`') }, cwd: cwd or { return error('missing field `cwd`') }, reason: reason, proposed_execpolicy_amendment: execpolicy, proposed_network_policy_amendments: network_amendments, available_decisions: decisions, network_approval_context: network, additional_permissions: permissions }
}

pub fn ApplyPatchApprovalRequestEvent.deserialize_json(text &string) !ApplyPatchApprovalRequestEvent {
	names := ['call_id', 'turn_id', 'changes', 'reason', 'grant_root']
	mut seen := map[string]bool{}
	mut call_id := ?string(none)
	mut turn_id := ''.clone()
	mut changes := std_collections.HashMap[std_path.PathBuf, diff_model.FileChange]{}
	mut reason := ?string(none)
	mut root := ?std_path.PathBuf(none)
	input := api.approval_events_struct_fields(text, &names)!
	for field in input.fields {
		if field.name in names { api.approval_events_check_duplicate(mut seen, &field.name)! }
		match field.name {
			'call_id' { call_id = field.value.string_owned()! }
			'turn_id' { turn_id = field.value.string_owned()! }
			'changes' {
				for entry in field.value.object_fields()! {
					changes.insert(std_path.PathBuf.from(entry.name.clone()), diff_model.FileChange.deserialize_json(&entry.value.text)!)
				}
			}
			'reason' {
				if field.value.text != 'null' { reason = field.value.string_owned()! }
			}
			'grant_root' {
				if field.value.text != 'null' {
					root = std_path.PathBuf.from(field.value.string_owned()!)
				}
			}
			else {}
		}
	}
	input.validate_length(3, names.len)!
	owned_call_id := call_id or { return error('missing field `call_id`') }
	if 'changes' !in seen { return error('missing field `changes`') }
	return ApplyPatchApprovalRequestEvent{ call_id: owned_call_id, turn_id: turn_id, changes: changes, reason: reason, grant_root: root }
}
