module models

import codex_protocol.permissions

// STUB: returns the filesystem policy carried by a managed permission profile.
pub fn (profile &PermissionProfile) file_system_sandbox_policy() permissions.FileSystemSandboxPolicy {
	return permissions.FileSystemSandboxPolicy{
		kind:              profile.file_system.kind.clone()
		entries:           profile.file_system.entries.clone()
		platform_defaults: profile.file_system.platform_defaults
	}
}
