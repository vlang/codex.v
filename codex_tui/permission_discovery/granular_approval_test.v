module permission_discovery

import codex_app_server_protocol as api
import codex_protocol
import codex_tui.permission_discovery.types

fn test_granular_requirements_compare_each_permission_flag_and_reviewer_alias() {
	mut id := 'custom'
	$if ownership ? {
		id = id.to_owned()
	}
	allowed := api.AskForApproval{
		kind:     .granular
		granular: codex_protocol.GranularApprovalConfig{
			sandbox_approval:    true
			rules:               true
			skill_approval:      true
			request_permissions: true
			mcp_elicitations:    true
		}
	}
	discovery := types.PermissionDiscovery{
		profiles:              [api.PermissionProfileSummary{ id: id.clone(), allowed: true }]
		requirements:          api.ConfigRequirements{
			allowed_approval_policies:   [allowed]
			allowed_approvals_reviewers: [api.ApprovalsReviewer.auto_review]
		}
		explicit_profile_mode: true
	}
	for reviewer in [api.ApprovalsReviewer.auto_review, .guardian_subagent] {
		assert discovery.disabled_reason(&id, allowed, reviewer) == none
		for bit in 0 .. 5 {
			different := api.AskForApproval{
				kind:     .granular
				granular: codex_protocol.GranularApprovalConfig{
					sandbox_approval:    bit != 0
					rules:               bit != 1
					skill_approval:      bit != 2
					request_permissions: bit != 3
					mcp_elicitations:    bit != 4
				}
			}
			assert discovery.disabled_reason(&id, different, reviewer) == ?string('Disabled by requirements.')
		}
	}
	assert discovery.disabled_reason(&id, allowed, .user) == ?string('Disabled by requirements.')
	assert discovery.disabled_reason(&id, allowed, .auto_review) == none
	assert allowed.granular or { panic('policy moved') }.request_permissions
	assert id == 'custom'
}
