// Bounded discovery for permission pickers; fixed request IDs bound abandoned RPCs.
// This never applies a profile; the app chooses local or server-owned selection.
module types

import codex_app_server_protocol as api
import codex_core
import codex_utils_approval_presets

// The source-owned value and methods live in this independent child module to
// break V's import cycle between AppEvent and its permission-discovery producer.
// The parent permission_discovery module reexports the type through an alias.
pub struct PermissionDiscovery {
pub:
	profiles              []api.PermissionProfileSummary
	requirements          ?api.ConfigRequirements
	explicit_profile_mode bool
}

pub fn PermissionDiscovery.local(config &codex_core.Config) PermissionDiscovery {
	mut profiles := []api.PermissionProfileSummary{}
	for preset in codex_utils_approval_presets.builtin_approval_presets() {
		profiles << api.PermissionProfileSummary{ id: preset.active_permission_profile.id, description: none, allowed: true }
	}
	for index in 0 .. config.custom_permission_profiles.len {
		profile := &config.custom_permission_profiles[index]
		profiles << api.PermissionProfileSummary{
			id:          profile.id.clone()
			description: if text := profile.description {
				text.clone()
			} else {
				none
			}
			allowed:     profile.allowed
		}
	}
	return PermissionDiscovery{ profiles: profiles, requirements: none, explicit_profile_mode: true }
}

pub fn (discovery &PermissionDiscovery) disabled_reason(id &string, approval ?api.AskForApproval, reviewer ?api.ApprovalsReviewer) ?string {
	mut index := -1
	for i in 0 .. discovery.profiles.len {
		if discovery.profiles[i].id == *id {
			index = i
			break
		}
	}
	if index < 0 {
		return 'Not available on this server.'
	}
	if !discovery.profiles[index].allowed {
		return 'Disabled by requirements.'
	}
	if requirements := discovery.requirements {
		if allowed := requirements.allowed_permission_profiles {
			if !(allowed[*id] or { false }) {
				return 'Disabled by requirements.'
			}
		}
		if allowed := requirements.allowed_approval_policies {
			if value := approval {
				if value !in allowed {
					return 'Disabled by requirements.'
				}
			}
		}
		if allowed := requirements.allowed_approvals_reviewers {
			if value := reviewer {
				mut accepted := false
				for candidate in allowed {
					if candidate.canonical() == value.canonical() {
						accepted = true
						break
					}
				}
				if !accepted {
					return 'Disabled by requirements.'
				}
			}
		}
	}
	return none
}

// V's explicit owned Result<PermissionDiscovery, String> event payload.
pub struct PermissionDiscoveryResult {
pub:
	is_error    bool
	value       PermissionDiscovery
	error_value string
}
