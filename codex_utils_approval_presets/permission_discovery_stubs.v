module codex_utils_approval_presets

import codex_protocol

// STUB: utils/approval-presets/src/lib.rs::ApprovalPreset; discovery observes
// active profile IDs only. Applying approval policies/presets awaits that owner.
pub struct ApprovalPreset {
pub:
	active_permission_profile codex_protocol.ActivePermissionProfile
}

// STUB: builtin_approval_presets's exact ordered canonical profile IDs.
pub fn builtin_approval_presets() []ApprovalPreset {
	return [
		ApprovalPreset{ active_permission_profile: codex_protocol.ActivePermissionProfile{ id: ':read-only' } },
		ApprovalPreset{ active_permission_profile: codex_protocol.ActivePermissionProfile{ id: ':workspace' } },
		ApprovalPreset{ active_permission_profile: codex_protocol.ActivePermissionProfile{ id: ':danger-full-access' } },
	]
}
