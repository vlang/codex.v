module codex_app_server_protocol

// STUB: protocol/v2/permissions.rs::PermissionProfileListParams.
pub struct PermissionProfileListParams {
pub:
	// Opaque pagination cursor returned by a previous call.
	cursor ?string
	// Optional page size; defaults to the full result set.
	limit ?u32
	// Optional working directory to resolve project config layers.
	cwd ?string
}

// STUB: protocol/v2/permissions.rs::PermissionProfileSummary.
pub struct PermissionProfileSummary {
pub:
	// Available permission profile identifier.
	id string
	// Optional user-facing description for display in clients.
	description ?string
	// Whether the effective requirements allow selecting this profile.
	allowed bool
}

// STUB: source-derived Clone at the independent RPC ownership boundary.
pub fn (profile &PermissionProfileSummary) clone() PermissionProfileSummary {
	return PermissionProfileSummary{
		id:          profile.id.clone()
		description: if text := profile.description {
			text.clone()
		} else {
			none
		}
		allowed:     profile.allowed
	}
}

// STUB: protocol/v2/permissions.rs::PermissionProfileListResponse.
pub struct PermissionProfileListResponse {
pub:
	data []PermissionProfileSummary
	// Opaque cursor to pass to the next call to continue after the last item.
	// If None, there are no more items to return.
	next_cursor ?string
}

// STUB: protocol/v2/config.rs::ConfigRequirements; retain the typed permission
// restrictions observed by discovery. Other managed settings await their owners.
pub struct ConfigRequirements {
pub:
	allowed_approval_policies   ?[]AskForApproval
	allowed_approvals_reviewers ?[]ApprovalsReviewer
	allowed_permission_profiles ?map[string]bool
}

// STUB: ConfigRequirements's owned RPC decode/Clone boundary.
pub fn (requirements &ConfigRequirements) clone() ConfigRequirements {
	return ConfigRequirements{
		allowed_approval_policies:   if allowed := requirements.allowed_approval_policies {
			clone_permission_approval_policies(&allowed)
		} else {
			none
		}
		allowed_approvals_reviewers: if allowed := requirements.allowed_approvals_reviewers {
			clone_permission_approval_reviewers(&allowed)
		} else {
			none
		}
		allowed_permission_profiles: if allowed := requirements.allowed_permission_profiles {
			allowed.clone()
		} else {
			none
		}
	}
}

// STUB: Clone constructs an owned array of allocation-free tagged approvals,
// preserving the source's Copy payloads at the RPC decoding boundary.
fn clone_permission_approval_policies(values &[]AskForApproval) []AskForApproval {
	mut result := []AskForApproval{cap: values.len}
	for index in 0 .. values.len {
		result << values[index]
	}
	return result
}

// STUB: Copy reviewer enums share the same explicit owned array clone boundary.
fn clone_permission_approval_reviewers(values &[]ApprovalsReviewer) []ApprovalsReviewer {
	mut result := []ApprovalsReviewer{cap: values.len}
	for index in 0 .. values.len {
		result << values[index]
	}
	return result
}

// STUB: protocol/v2/config.rs::ConfigRequirementsReadResponse.
pub struct ConfigRequirementsReadResponse {
pub:
	// Null if no requirements are configured (e.g. no requirements.toml/MDM entries).
	requirements ?ConfigRequirements
}

// STUB: source-derived Clone keeps the borrowed response reusable while RPC
// deserialization assembles an independent owned optional requirements value.
pub fn (response &ConfigRequirementsReadResponse) clone() ConfigRequirementsReadResponse {
	return ConfigRequirementsReadResponse{
		requirements: if requirements := response.requirements {
			requirements.clone()
		} else {
			none
		}
	}
}

// STUB: protocol/common.rs::ClientRequest::ConfigRequirementsRead.
pub struct ClientRequestConfigRequirementsRead {
pub:
	request_id RequestId
	params     ?PermissionDiscoveryUnit
}

// STUB: Rust's allocation-free unit value in ConfigRequirementsRead::params.
pub struct PermissionDiscoveryUnit {}

// STUB: protocol/common.rs::ClientRequest::PermissionProfileList.
pub struct ClientRequestPermissionProfileList {
pub:
	request_id RequestId
	params     PermissionProfileListParams
}
