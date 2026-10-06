module models

import codex_protocol.permissions
import codex_utils_path_uri

// STUB: protocol/src/models.rs::PermissionProfile's derived Clone for the
// existing canonical permission projection. Full Managed/Disabled/External
// runtime construction remains owned by the untranslated dependency.
pub fn (profile &PermissionProfile) clone() PermissionProfile {
	mut entries := []permissions.FileSystemSandboxEntry{cap: profile.file_system.entries.len}
	for index in 0 .. profile.file_system.entries.len {
		entry := &profile.file_system.entries[index]
		entries << permissions.FileSystemSandboxEntry{
			path:                  permissions.FileSystemPath{
				kind:         entry.path.kind.clone()
				path:         entry.path.path.clone()
				special:      entry.path.special
				subpath:      if value := entry.path.subpath { value.clone() } else { none }
				uri:          if entry.path.uri.has_value {
					permissions.FileSystemPathUri.some(codex_utils_path_uri.PathUri{ path: entry.path.uri.value.path.clone() })
				} else {
					permissions.FileSystemPathUri{}
				}
				pattern:      entry.path.pattern.clone()
				unknown_path: entry.path.unknown_path.clone()
			}
			access:                entry.access
			missing_path_behavior: if value := entry.missing_path_behavior {
				value.clone()
			} else {
				none
			}
		}
	}
	return PermissionProfile{
		enforcement: profile.enforcement
		file_system: permissions.FileSystemSandboxPolicy{
			kind:                profile.file_system.kind.clone()
			entries:             entries
			platform_defaults:   profile.file_system.platform_defaults
			glob_scan_max_depth: profile.file_system.glob_scan_max_depth
		}
		network:     permissions.NetworkSandboxPolicy{ kind: profile.network.kind.clone() }
	}
}

// STUB: protocol/src/models.rs::ActivePermissionProfile's derived Clone.
pub fn (profile &ActivePermissionProfile) clone() ActivePermissionProfile {
	return ActivePermissionProfile{
		id:      profile.id.clone()
		extends: if value := profile.extends { value.clone() } else { none }
	}
}
