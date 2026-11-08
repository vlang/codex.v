module additional_dirs

import codex_protocol.models
import std_path

// Returns a warning describing why --add-dir entries will be ignored for the
// resolved permission profile. The caller is responsible for presenting the
// warning to the user (for example, printing to stderr).
pub fn add_dir_warning_message(paths_to_add &[]std_path.PathBuf, permission_profile &models.PermissionProfile, cwd &std_path.Path) ?string {
	if paths_to_add.len == 0 {
		return none
	}

	// The existing explicit profile tag maps none/legacy/external to Rust's
	// Disabled/Managed/External variants, retaining the canonical owner.
	if permission_profile.enforcement in [.none, .external] {
		return none
	}

	file_system_policy := permission_profile.file_system_sandbox_policy()
	if file_system_policy.has_full_disk_write_access() {
		return none
	}
	if file_system_policy.can_write_local_path_with_cwd(cwd, cwd) {
		return none
	}
	return format_warning(paths_to_add)
}

fn format_warning(paths_to_add &[]std_path.PathBuf) string {
	mut paths := []string{cap: paths_to_add.len}
	for index in 0 .. paths_to_add.len {
		path := (*paths_to_add)[index].as_path()
		paths << path.to_string_lossy()
	}
	joined_paths := paths.join(', ')
	return 'Ignoring --add-dir (${joined_paths}) because the effective permissions do not allow additional writable roots. Switch to workspace-write or danger-full-access to allow them.'
}
