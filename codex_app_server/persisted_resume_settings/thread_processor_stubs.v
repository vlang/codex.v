module persisted_resume_settings

import codex_app_server_protocol as api
import codex_protocol
import codex_thread_store

// STUB: PersistedResumeSettings is owned by app-server/persisted_resume_settings.rs.
pub struct PersistedResumeSettings {
pub:
	approval_policy           api.AskForApproval
	approvals_reviewer        ?api.ApprovalsReviewer
	active_permission_profile ?codex_protocol.ActivePermissionProfile
}

// STUB: OptionalPersistedResumeSettings retains the no-TurnContext result without borrowing an
// owner; the full type is owned by app-server/persisted_resume_settings.rs.
pub struct OptionalPersistedResumeSettings {
pub:
	has_value bool
	value     PersistedResumeSettings
}

// STUB: latest_persisted_resume_settings is owned by persisted_resume_settings.rs. The temporary
// rollout representation exposes the exact settings fields needed to scan backwards.
pub fn latest_persisted_resume_settings(items &[]codex_thread_store.RolloutItem) OptionalPersistedResumeSettings {
	for reverse_index in 0 .. items.len {
		index := items.len - 1 - reverse_index
		item := items[index]
		if approval_policy := item.approval_policy {
			return OptionalPersistedResumeSettings{
				has_value: true
				value:     PersistedResumeSettings{
					approval_policy:           approval_policy
					approvals_reviewer:        item.approvals_reviewer
					active_permission_profile: item.active_permission_profile
				}
			}
		}
	}
	return OptionalPersistedResumeSettings{}
}
