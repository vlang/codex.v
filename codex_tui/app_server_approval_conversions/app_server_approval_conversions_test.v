module app_server_approval_conversions

import codex_app_server_protocol as api
import codex_protocol.models
import codex_protocol.permissions
import codex_protocol.request_permissions
import codex_tui.diff_model
import codex_utils_absolute_path
import codex_utils_path_uri
import std_collections
import std_path
import std_io

fn absolute_path(path &string) codex_utils_absolute_path.AbsolutePathBuf {
	return codex_utils_absolute_path.from_absolute_path(path) or { panic('path must be absolute: ${err}') }
}

// Rust's owned String and PathBuf fixture constructors allocate their literal
// text. Keep that allocation boundary visible when ownership drops map keys.
fn test_converts_file_update_changes_to_display() {
	converted := file_update_changes_to_display([api.FileUpdateChange{
		path: 'foo.txt'.clone()
		kind: api.PatchChangeKind{ kind: .add }
		diff: 'hello\n'.clone()
	}])
	mut expected := std_collections.HashMap[std_path.PathBuf, diff_model.FileChange]{}
	expected.insert(std_path.PathBuf.from('foo.txt'.clone()), diff_model.FileChange(diff_model.Add{ content: 'hello\n'.clone() }))
	assert converted.equals(&expected)
}

fn test_converts_request_permissions_into_granted_permissions() {
	read_path := '/tmp/read-only'
	write_path := '/tmp/write'
	request := api.RequestPermissionProfile{
		network:     api.AdditionalNetworkPermissions{ enabled: true }
		file_system: api.AdditionalFileSystemPermissions{
			read:                [codex_utils_path_uri.LegacyAppPathString.from_absolute(absolute_path(&read_path))]
			write:               [codex_utils_path_uri.LegacyAppPathString.from_absolute(absolute_path(&write_path))]
			glob_scan_max_depth: none
			entries:             none
		}
	}
	core_request := request.to_core() or { panic('API paths should convert to native paths: ${err}') }
	assert granted_permission_profile_from_request(core_request) == api.GrantedPermissionProfile{
		network:     api.AdditionalNetworkPermissions{ enabled: true }
		file_system: api.AdditionalFileSystemPermissions{
			read:                [codex_utils_path_uri.LegacyAppPathString.from_absolute(absolute_path(&read_path))]
			write:               [codex_utils_path_uri.LegacyAppPathString.from_absolute(absolute_path(&write_path))]
			glob_scan_max_depth: none
			entries:             [
				api.FileSystemSandboxEntry{
					path:   api.FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_absolute(absolute_path(&read_path)) }
					access: .read
				},
				api.FileSystemSandboxEntry{
					path:   api.FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_absolute(absolute_path(&write_path)) }
					access: .write
				},
			]
		}
	}
}

fn test_converts_request_permissions_into_canonical_granted_permissions() {
	request := api.RequestPermissionProfile{
		network:     none
		file_system: api.AdditionalFileSystemPermissions{
			read:                none
			write:               none
			glob_scan_max_depth: none
			entries:             [api.FileSystemSandboxEntry{
				path:   api.FileSystemPath{ kind: .special, value: api.FileSystemSpecialPath{ kind: .root } }
				access: .write
			}]
		}
	}
	core_request := request.to_core() or { panic('API paths should convert to native paths: ${err}') }
	assert granted_permission_profile_from_request(core_request) == api.GrantedPermissionProfile{
		network:     none
		file_system: api.AdditionalFileSystemPermissions{
			read:                none
			write:               none
			glob_scan_max_depth: none
			entries:             [api.FileSystemSandboxEntry{
				path:   api.FileSystemPath{ kind: .special, value: api.FileSystemSpecialPath{ kind: .root } }
				access: .write
			}]
		}
	}
}

fn test_all_patch_variants_and_duplicate_component_paths_keep_the_last_value() {
	changes := file_update_changes_to_display([
		api.FileUpdateChange{ path: 'a//./b/'.clone(), kind: api.PatchChangeKind{ kind: .add }, diff: 'first'.clone() },
		api.FileUpdateChange{ path: 'removed'.clone(), kind: api.PatchChangeKind{ kind: .delete }, diff: 'old\n'.clone() },
		api.FileUpdateChange{ path: 'a/b'.clone(), kind: api.PatchChangeKind{ kind: .update, move_path: std_path.PathBuf.from('next/file'.clone()) }, diff: '@@\n-old\n+new\n'.clone() },
		api.FileUpdateChange{ path: 'unchanged'.clone(), kind: api.PatchChangeKind{ kind: .update, move_path: none }, diff: 'other diff'.clone() },
	])
	mut expected := std_collections.HashMap[std_path.PathBuf, diff_model.FileChange]{}
	expected.insert(std_path.PathBuf.from('a/b'.clone()), diff_model.FileChange(diff_model.Update{ unified_diff: '@@\n-old\n+new\n'.clone(), move_path: std_path.PathBuf.from('next/file'.clone()) }))
	expected.insert(std_path.PathBuf.from('removed'.clone()), diff_model.FileChange(diff_model.Delete{ content: 'old\n'.clone() }))
	expected.insert(std_path.PathBuf.from('unchanged'.clone()), diff_model.FileChange(diff_model.Update{ unified_diff: 'other diff'.clone(), move_path: none }))
	assert changes.len() == 3
	assert changes.equals(&expected)
	expected_key := std_path.PathBuf.from('a/b'.clone())
	mut retained_first_key := false
	for key in changes.keys() {
		if key.equals(&expected_key) {
			view := key.as_path()
			assert view.to_path_buf() == 'a//./b/'
			retained_first_key = true
		}
	}
	assert retained_first_key
}

fn test_display_path_keys_keep_parent_components_and_leading_dot_distinct() {
	changes := file_update_changes_to_display([
		api.FileUpdateChange{ path: 'a/../b'.clone(), kind: api.PatchChangeKind{ kind: .add }, diff: 'parent'.clone() },
		api.FileUpdateChange{ path: 'b'.clone(), kind: api.PatchChangeKind{ kind: .add }, diff: 'plain'.clone() },
		api.FileUpdateChange{ path: './b'.clone(), kind: api.PatchChangeKind{ kind: .add }, diff: 'leading-dot'.clone() },
	])
	assert changes.len() == 3
	for name in ['a/../b', 'b', './b'] {
		key := std_path.PathBuf.from(name.clone())
		assert changes.get(&key).has_value
	}
	assert file_update_changes_to_display([]).len() == 0
}

fn test_native_legacy_projection_groups_read_before_write() {
	read_path := '/tmp/read-only'
	write_path := '/tmp/write'
	request := api.RequestPermissionProfile{
		file_system: api.AdditionalFileSystemPermissions{
			entries: [
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_absolute(absolute_path(&write_path)) }, access: .write },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_absolute(absolute_path(&read_path)) }, access: .read },
			]
		}
	}
	core := request.to_core() or { panic(err) }
	granted := granted_permission_profile_from_request(core)
	file_system := granted.file_system or { panic('missing file system') }
	assert file_system == api.AdditionalFileSystemPermissions{
		read:    [codex_utils_path_uri.LegacyAppPathString.from_absolute(absolute_path(&read_path))]
		write:   [codex_utils_path_uri.LegacyAppPathString.from_absolute(absolute_path(&write_path))]
		entries: [
			api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_absolute(absolute_path(&read_path)) }, access: .read },
			api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_absolute(absolute_path(&write_path)) }, access: .write },
		]
	}
}

fn test_canonical_depth_suppresses_legacy_fields_without_reordering_entries() {
	request := api.RequestPermissionProfile{
		file_system: api.AdditionalFileSystemPermissions{
			glob_scan_max_depth: usize(3)
			entries:             [
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_string('/tmp/write'.clone()) }, access: .write },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_string('/tmp/read'.clone()) }, access: .read },
			]
		}
	}
	core := request.to_core() or { panic(err) }
	assert granted_permission_profile_from_request(core) == api.GrantedPermissionProfile{
		file_system: api.AdditionalFileSystemPermissions{
			glob_scan_max_depth: usize(3)
			entries:             [
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_string('/tmp/write'.clone()) }, access: .write },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_string('/tmp/read'.clone()) }, access: .read },
			]
		}
	}
}

fn test_canonical_entries_take_precedence_over_invalid_legacy_roots() {
	request := api.RequestPermissionProfile{
		file_system: api.AdditionalFileSystemPermissions{
			read:    [codex_utils_path_uri.LegacyAppPathString.from_string('relative/read'.clone())]
			write:   [codex_utils_path_uri.LegacyAppPathString.from_string('relative/write'.clone())]
			entries: []api.FileSystemSandboxEntry{}
		}
	}
	core := request.to_core() or { panic(err) }
	assert granted_permission_profile_from_request(core) == api.GrantedPermissionProfile{
		file_system: api.AdditionalFileSystemPermissions{ entries: []api.FileSystemSandboxEntry{} }
	}
}

fn test_invalid_legacy_paths_report_read_error_before_write_error() {
	request := api.RequestPermissionProfile{
		file_system: api.AdditionalFileSystemPermissions{
			read:  [codex_utils_path_uri.LegacyAppPathString.from_string('relative/read'.clone())]
			write: [codex_utils_path_uri.LegacyAppPathString.from_string('relative/write'.clone())]
		}
	}
	if _ := request.to_core() {
		assert false
	} else {
		assert err.msg() == 'path `relative/read` is not absolute'
		if err is std_io.Error {
			assert err.kind() == .invalid_input
		} else {
			assert false
		}
	}
}

fn test_canonical_symbol_glob_and_deny_payloads_survive_conversion() {
	request := api.RequestPermissionProfile{
		file_system: api.AdditionalFileSystemPermissions{
			entries: [
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .special, value: api.FileSystemSpecialPath{ kind: .minimal } }, access: .read },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .special, value: api.FileSystemSpecialPath{ kind: .project_roots, subpath: codex_utils_path_uri.LegacyAppPathString.from_string('nested/project'.clone()) } }, access: .write },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .special, value: api.FileSystemSpecialPath{ kind: .tmpdir } }, access: .write },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .special, value: api.FileSystemSpecialPath{ kind: .slash_tmp } }, access: .write },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .special, value: api.FileSystemSpecialPath{ kind: .unknown, path: ':future_root'.clone(), subpath: codex_utils_path_uri.LegacyAppPathString.from_string('nested/future'.clone()) } }, access: .deny },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .glob_pattern, pattern: '**/secret'.clone() }, access: .deny },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_string('/tmp/private'.clone()) }, access: .deny },
			]
		}
	}
	core := request.to_core() or { panic(err) }
	assert granted_permission_profile_from_request(core) == api.GrantedPermissionProfile{
		file_system: api.AdditionalFileSystemPermissions{
			entries: [
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .special, value: api.FileSystemSpecialPath{ kind: .minimal } }, access: .read },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .special, value: api.FileSystemSpecialPath{ kind: .project_roots, subpath: codex_utils_path_uri.LegacyAppPathString.from_string('nested/project'.clone()) } }, access: .write },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .special, value: api.FileSystemSpecialPath{ kind: .tmpdir } }, access: .write },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .special, value: api.FileSystemSpecialPath{ kind: .slash_tmp } }, access: .write },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .special, value: api.FileSystemSpecialPath{ kind: .unknown, path: ':future_root'.clone(), subpath: codex_utils_path_uri.LegacyAppPathString.from_string('nested/future'.clone()) } }, access: .deny },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .glob_pattern, pattern: '**/secret'.clone() }, access: .deny },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_string('/tmp/private'.clone()) }, access: .deny },
			]
		}
	}
}

fn test_foreign_windows_permission_paths_keep_legacy_projection() {
	$if windows {
		return
	}
	request := api.RequestPermissionProfile{
		file_system: api.AdditionalFileSystemPermissions{
			read:  [codex_utils_path_uri.LegacyAppPathString.from_string('C:\\src\\read'.clone())]
			write: [codex_utils_path_uri.LegacyAppPathString.from_string('\\\\server\\share\\write'.clone())]
		}
	}
	core := request.to_core() or { panic(err) }
	assert granted_permission_profile_from_request(core) == api.GrantedPermissionProfile{
		file_system: api.AdditionalFileSystemPermissions{
			read:    [codex_utils_path_uri.LegacyAppPathString.from_string('C:\\src\\read'.clone())]
			write:   [codex_utils_path_uri.LegacyAppPathString.from_string('\\\\server\\share\\write'.clone())]
			entries: [
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_string('C:\\src\\read'.clone()) }, access: .read },
				api.FileSystemSandboxEntry{ path: api.FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_string('\\\\server\\share\\write'.clone()) }, access: .write },
			]
		}
	}
}

fn test_absent_and_tristate_network_overlays_remain_distinct() {
	assert granted_permission_profile_from_request(request_permissions.RequestPermissionProfile{}) == api.GrantedPermissionProfile{}
	assert granted_permission_profile_from_request(request_permissions.RequestPermissionProfile{ network: models.NetworkPermissions{ enabled: none } }) == api.GrantedPermissionProfile{ network: api.AdditionalNetworkPermissions{ enabled: none } }
	assert granted_permission_profile_from_request(request_permissions.RequestPermissionProfile{ network: models.NetworkPermissions{ enabled: false } }) == api.GrantedPermissionProfile{ network: api.AdditionalNetworkPermissions{ enabled: false } }
}

fn test_borrowed_helpers_and_map_lookups_keep_heap_owners_reusable() {
	mut path_text := '/tmp/borrowed'
	mut key_text := 'heap/file'
	mut diff := 'heap diff'
	$if ownership ? {
		path_text = path_text.to_owned()
		key_text = key_text.to_owned()
		diff = diff.to_owned()
	}
	first_path := absolute_path(&path_text)
	second_path := absolute_path(&path_text)
	assert first_path == second_path
	assert path_text == '/tmp/borrowed'
	key := std_path.PathBuf.from(key_text)
	changes := file_update_changes_to_display([api.FileUpdateChange{ path: 'heap/file'.clone(), kind: api.PatchChangeKind{ kind: .add }, diff: diff }])
	first := changes.get(&key)
	second := changes.get(&key)
	assert first.has_value && second.has_value
	assert first.value.equals(second.value)
	assert changes.equals(&changes)
	assert changes.len() == 1
	view := key.as_path()
	assert view.to_path_buf() == 'heap/file'
	if first.value is diff_model.Add {
		assert first.value.content == 'heap diff'
	} else {
		assert false
	}
}

fn test_core_permission_clone_retains_canonical_uri_and_selector_payloads() {
	mut uri_text := 'file:///tmp/owned'
	mut pattern := '**/owned'
	mut unknown := ':owned_future'
	mut subpath := 'owned/subpath'
	$if ownership ? {
		uri_text = uri_text.to_owned()
		pattern = pattern.to_owned()
		unknown = unknown.to_owned()
		subpath = subpath.to_owned()
	}
	uri := codex_utils_path_uri.PathUri{ path: uri_text }
	uri_payload := permissions.FileSystemPathUri.some(uri)
	selector := permissions.FileSystemPath{
		kind:         'path'.clone()
		uri:          uri_payload
		pattern:      pattern
		unknown_path: unknown
		subpath:      subpath
	}
	entry := permissions.FileSystemSandboxEntry{ path: selector, access: .write }
	entries := [entry]
	file_system := permissions.FileSystemSandboxPolicy{ entries: entries }
	profile := models.PermissionProfile{ file_system: file_system }
	first := profile.clone()
	second := profile.clone()
	assert first == profile
	assert second == profile
	assert profile.file_system.entries[0].path.uri.has_value
	assert first.file_system.entries[0].path.uri.has_value
	assert profile.file_system.entries[0].path.uri.value.path.str != first.file_system.entries[0].path.uri.value.path.str
	assert profile.file_system.entries[0].path.pattern == '**/owned'
	assert profile.file_system.entries[0].path.unknown_path == ':owned_future'
	assert profile.file_system.entries[0].path.subpath == ?string('owned/subpath')
}
