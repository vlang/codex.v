module models

import codex_protocol.permissions

// STUB: models.rs::ManagedFileSystemPermissions carries both payload variants;
// sandbox-policy projection retains the entries and optional nonzero scan depth.
// Full Serde validation and selected-executor materialization remain unported.
pub struct ManagedFileSystemPermissions {
pub:
	kind                permissions.FileSystemSandboxKind = .restricted
	entries             []permissions.FileSystemSandboxEntry
	glob_scan_max_depth ?usize
}

// STUB: PermissionProfile::Managed's typed construction boundary. The existing
// enforcement tag is Managed's legacy projection; no payload is serialized away.
pub fn PermissionProfile.managed(file_system ManagedFileSystemPermissions, network permissions.NetworkSandboxPolicy) PermissionProfile {
	return PermissionProfile{
		enforcement: .legacy
		file_system: permissions.FileSystemSandboxPolicy{
			kind:                if file_system.kind == .unrestricted {
				'unrestricted'
			} else {
				'restricted'
			}
			entries:             file_system.entries
			glob_scan_max_depth: file_system.glob_scan_max_depth
		}
		network:     network
	}
}

// STUB: PermissionProfile::Disabled owns no sandbox payload in the source.
pub fn PermissionProfile.disabled() PermissionProfile {
	return PermissionProfile{ enforcement: .none, network: permissions.NetworkSandboxPolicy{ kind: 'enabled' } }
}

// STUB: PermissionProfile::External preserves its observed network payload.
pub fn PermissionProfile.external(network permissions.NetworkSandboxPolicy) PermissionProfile {
	return PermissionProfile{ enforcement: .external, network: network }
}

// STUB: PermissionProfile::read_only's symbolic root read grant.
pub fn PermissionProfile.read_only() PermissionProfile {
	return PermissionProfile.managed(ManagedFileSystemPermissions{
		entries: [permissions.FileSystemSandboxEntry{
			path:   permissions.FileSystemPath{ kind: 'special', special: .root }
			access: .read
		}]
	}, permissions.NetworkSandboxPolicy{ kind: 'restricted' })
}

// STUB: PermissionProfile::workspace_write's active workspace-root grant.
// Ambient readable roots and optional temporary roots are outside this boundary.
pub fn PermissionProfile.workspace_write() PermissionProfile {
	return PermissionProfile.managed(ManagedFileSystemPermissions{
		entries: [
			permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'special', special: .root }, access: .read },
			permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'special', special: .workspace_roots }, access: .write },
		]
	}, permissions.NetworkSandboxPolicy{ kind: 'restricted' })
}
