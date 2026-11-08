module models

import codex_protocol.permissions

// STUB: returns the filesystem policy carried by a managed permission profile.
pub fn (profile &PermissionProfile) file_system_sandbox_policy() permissions.FileSystemSandboxPolicy {
	if profile.enforcement == .none {
		return permissions.FileSystemSandboxPolicy{ kind: 'unrestricted' }
	}
	if profile.enforcement == .external {
		return permissions.FileSystemSandboxPolicy{ kind: 'external_sandbox' }
	}
	return permissions.FileSystemSandboxPolicy{
		kind:                profile.file_system.kind.clone()
		entries:             profile.file_system.entries.clone()
		platform_defaults:   profile.file_system.platform_defaults
		glob_scan_max_depth: profile.file_system.glob_scan_max_depth
	}
}
