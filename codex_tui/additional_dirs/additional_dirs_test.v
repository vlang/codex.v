module additional_dirs

import codex_protocol.models
import codex_protocol.permissions
import std_path

fn test_returns_none_for_workspace_write() {
	profile := models.PermissionProfile.workspace_write()
	text := '/tmp/example'
	dirs := [std_path.PathBuf.from(text.clone())]
	cwd_text := '/tmp/project'
	cwd := std_path.Path.new(&cwd_text)
	assert add_dir_warning_message(&dirs, &profile, &cwd) == none
}

fn test_returns_none_for_danger_full_access() {
	profile := models.PermissionProfile.disabled()
	dirs := [std_path.PathBuf.from('/tmp/example'.clone())]
	cwd_text := '/tmp/project'
	cwd := std_path.Path.new(&cwd_text)
	assert add_dir_warning_message(&dirs, &profile, &cwd) == none
}

fn test_returns_none_for_external_sandbox() {
	profile := models.PermissionProfile.external(permissions.NetworkSandboxPolicy{ kind: 'enabled' })
	dirs := [std_path.PathBuf.from('/tmp/example'.clone())]
	cwd_text := '/tmp/project'
	cwd := std_path.Path.new(&cwd_text)
	assert add_dir_warning_message(&dirs, &profile, &cwd) == none
}

fn test_warns_for_read_only() {
	profile := models.PermissionProfile.read_only()
	dirs := [std_path.PathBuf.from('relative'.clone()), std_path.PathBuf.from('/abs'.clone())]
	cwd_text := '/tmp/project'
	cwd := std_path.Path.new(&cwd_text)
	message := add_dir_warning_message(&dirs, &profile, &cwd) or { panic('expected warning for read-only sandbox') }
	assert message == 'Ignoring --add-dir (relative, /abs) because the effective permissions do not allow additional writable roots. Switch to workspace-write or danger-full-access to allow them.'
}

fn test_warns_when_profile_can_write_elsewhere_but_not_cwd() {
	profile := models.PermissionProfile.managed(models.ManagedFileSystemPermissions{
		entries:             [
			permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'special', special: .root }, access: .read },
			permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'path', path: '/tmp/writable' }, access: .write },
		]
		glob_scan_max_depth: none
	}, permissions.NetworkSandboxPolicy{ kind: 'restricted' })
	dirs := [std_path.PathBuf.from('/tmp/extra'.clone())]
	cwd_text := '/tmp/project'
	cwd := std_path.Path.new(&cwd_text)
	assert add_dir_warning_message(&dirs, &profile, &cwd) == ?string('Ignoring --add-dir (/tmp/extra) because the effective permissions do not allow additional writable roots. Switch to workspace-write or danger-full-access to allow them.')
}

fn test_returns_none_when_no_additional_dirs() {
	profile := models.PermissionProfile.read_only()
	dirs := []std_path.PathBuf{}
	cwd_text := '/tmp/project'
	cwd := std_path.Path.new(&cwd_text)
	assert add_dir_warning_message(&dirs, &profile, &cwd) == none
}

fn owned_additional_dirs_text(text &string) string {
	$if ownership ? {
		return text.to_owned()
	}
	return text.clone()
}

fn test_warning_reuses_heap_owned_paths_and_profile_and_returns_independent_text() {
	text := '/tmp/project'
	cwd_text := owned_additional_dirs_text(&text)
	path_text := 'relative'
	dirs := [std_path.PathBuf.from(owned_additional_dirs_text(&path_text))]
	profile := models.PermissionProfile.read_only()
	cwd := std_path.Path.new(&cwd_text)
	first := add_dir_warning_message(&dirs, &profile, &cwd) or { panic('expected warning') }
	second := add_dir_warning_message(&dirs, &profile, &cwd) or { panic('expected warning') }
	assert first == second
	assert first.str != second.str
	assert cwd_text == '/tmp/project'
	path := dirs[0].as_path()
	assert path.to_string_lossy() == 'relative'
	assert profile.file_system.entries[0].access == .read
}

fn test_warning_uses_native_lossy_path_display_in_source_order() {
	invalid := [u8(`a`), 0xff, `b`].bytestr()
	dirs := [std_path.PathBuf.from(invalid), std_path.PathBuf.from('next'.clone())]
	profile := models.PermissionProfile.read_only()
	cwd_text := '/tmp/project'
	cwd := std_path.Path.new(&cwd_text)
	message := add_dir_warning_message(&dirs, &profile, &cwd) or { panic('expected warning') }
	assert message.starts_with('Ignoring --add-dir (a\uFFFDb, next)')
}

fn test_restricted_root_write_respects_narrowing_and_same_target_precedence() {
	cwd_text := '/tmp/project'
	cwd := std_path.Path.new(&cwd_text)
	dirs := [std_path.PathBuf.from('/tmp/extra'.clone())]
	for narrowed in [permissions.FileSystemAccessMode.read, .deny] {
		profile := models.PermissionProfile.managed(models.ManagedFileSystemPermissions{
			entries: [
				permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'special', special: .root }, access: .write },
				permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'path', path: cwd_text.clone() }, access: narrowed },
			]
		}, permissions.NetworkSandboxPolicy{ kind: 'restricted' })
		assert !profile.file_system.has_full_disk_write_access()
		assert add_dir_warning_message(&dirs, &profile, &cwd) != none
	}
	profile := models.PermissionProfile.managed(models.ManagedFileSystemPermissions{
		entries: [
			permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'special', special: .root }, access: .write },
			permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'path', path: cwd_text.clone() }, access: .read },
			permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'path', path: cwd_text.clone() }, access: .write },
		]
	}, permissions.NetworkSandboxPolicy{ kind: 'restricted' })
	assert profile.file_system.has_full_disk_write_access()
	assert add_dir_warning_message(&dirs, &profile, &cwd) == none
}

fn test_metadata_is_protected_unless_explicit_write_root_grants_it_back() {
	cwd_text := '/tmp/project'
	cwd := std_path.Path.new(&cwd_text)
	metadata_text := '/tmp/project/.git/config'
	metadata := std_path.Path.new(&metadata_text)
	profile := models.PermissionProfile.workspace_write()
	assert !profile.file_system.can_write_local_path_with_cwd(&metadata, &cwd)
	grant := models.PermissionProfile.managed(models.ManagedFileSystemPermissions{
		entries: [permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'path', path: '/tmp/project/.git' }, access: .write }]
	}, permissions.NetworkSandboxPolicy{ kind: 'restricted' })
	assert grant.file_system.can_write_local_path_with_cwd(&metadata, &cwd)
}

fn test_profile_projection_and_clone_preserve_scan_depth_and_unrestricted_variant() {
	profile := models.PermissionProfile.managed(models.ManagedFileSystemPermissions{
		entries:             [permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'path', path: '/tmp/project'.clone() }, access: .write }]
		glob_scan_max_depth: usize(3)
	}, permissions.NetworkSandboxPolicy{ kind: 'restricted' })
	first := profile.clone()
	second := profile.file_system_sandbox_policy()
	assert first.file_system.glob_scan_max_depth == ?usize(3)
	assert second.glob_scan_max_depth == ?usize(3)
	assert profile.file_system.entries[0].path.path == '/tmp/project'
	unrestricted := models.PermissionProfile.managed(models.ManagedFileSystemPermissions{ kind: .unrestricted }, permissions.NetworkSandboxPolicy{ kind: 'restricted' })
	dirs := [std_path.PathBuf.from('/tmp/extra'.clone())]
	cwd_text := '/tmp/project'
	cwd := std_path.Path.new(&cwd_text)
	assert add_dir_warning_message(&dirs, &unrestricted, &cwd) == none
}

fn test_symbolic_and_literal_native_root_share_target_without_narrowing() {
	$if windows {
		return
	}
	profile := models.PermissionProfile.managed(models.ManagedFileSystemPermissions{
		entries: [
			permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'special', special: .root }, access: .write },
			permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'path', path: '/'.clone() }, access: .read },
		]
	}, permissions.NetworkSandboxPolicy{ kind: 'restricted' })
	assert profile.file_system.has_full_disk_write_access()
	dirs := [std_path.PathBuf.from('/tmp/extra'.clone())]
	cwd_text := '/tmp/project/.git'
	cwd := std_path.Path.new(&cwd_text)
	assert add_dir_warning_message(&dirs, &profile, &cwd) == none
}

fn test_explicit_metadata_root_grant_preserves_source_first_match_order() {
	profile := models.PermissionProfile.managed(models.ManagedFileSystemPermissions{
		entries: [
			permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'path', path: '/tmp/project'.clone() }, access: .write },
			permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'path', path: '/tmp/project/.git'.clone() }, access: .write },
		]
	}, permissions.NetworkSandboxPolicy{ kind: 'restricted' })
	cwd_text := '/tmp/project/.git/.git'
	cwd := std_path.Path.new(&cwd_text)
	dirs := [std_path.PathBuf.from('/tmp/extra'.clone())]
	assert profile.file_system.can_write_local_path_with_cwd(&cwd, &cwd)
	assert add_dir_warning_message(&dirs, &profile, &cwd) == none
}

fn test_permission_query_preserves_distinct_non_unicode_native_paths() {
	$if windows {
		return
	}
	invalid_name := [u8(`/`), `t`, `m`, `p`, `/`, `p`, 0xff].bytestr()
	cwd := std_path.Path.new(&invalid_name)
	other_path := '/tmp/p\uFFFD'
	dirs := [std_path.PathBuf.from('/tmp/extra'.clone())]
	other_grant := models.PermissionProfile.managed(models.ManagedFileSystemPermissions{
		entries: [permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'path', path: other_path.clone() }, access: .write }]
	}, permissions.NetworkSandboxPolicy{ kind: 'restricted' })
	assert add_dir_warning_message(&dirs, &other_grant, &cwd) != none
	exact_grant := models.PermissionProfile.managed(models.ManagedFileSystemPermissions{
		entries: [permissions.FileSystemSandboxEntry{ path: permissions.FileSystemPath{ kind: 'path', path: invalid_name.clone() }, access: .write }]
	}, permissions.NetworkSandboxPolicy{ kind: 'restricted' })
	assert add_dir_warning_message(&dirs, &exact_grant, &cwd) == none
	assert cwd.to_path_buf().bytes() == invalid_name.bytes()
}
