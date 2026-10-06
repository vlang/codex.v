module codex_app_server_protocol

import codex_protocol.models
import codex_protocol.permissions
import codex_protocol.request_permissions
import codex_utils_absolute_path
import codex_utils_path_uri
import std_path
import std_io

// STUB: app-server-protocol/protocol/v2/item.rs::PatchChangeKind variant tags.
pub enum PatchChangeKindTag {
	add
	delete
	update
}

// STUB: PatchChangeKind retains Update's owned optional native PathBuf payload.
pub struct PatchChangeKind {
pub:
	kind      PatchChangeKindTag
	move_path ?std_path.PathBuf
}

// STUB: app-server-protocol/protocol/v2/item.rs::FileUpdateChange.
pub struct FileUpdateChange {
pub:
	path string
	kind PatchChangeKind
	diff string
}

// STUB: app-server-protocol/protocol/v2/permissions.rs::AdditionalNetworkPermissions.
pub struct AdditionalNetworkPermissions {
pub:
	enabled ?bool
}

// STUB: API and core FileSystemAccessMode share the same Copy variant identities.
pub type FileSystemAccessMode = permissions.FileSystemAccessMode

// STUB: FileSystemSpecialPath variant tags; payloads remain typed below.
pub enum FileSystemSpecialPathTag {
	root
	minimal
	project_roots
	tmpdir
	slash_tmp
	unknown
}

// STUB: FileSystemSpecialPath's public source-shaped alias. V3's json2 generic
// expansion confuses a same-named struct with the core enum, so the backing
// struct has an unambiguous name while callers retain the eventual API name.
pub type FileSystemSpecialPath = AppServerFileSystemSpecialPath

// STUB: FileSystemSpecialPath preserves all source payloads and future unknown tokens.
pub struct AppServerFileSystemSpecialPath {
pub:
	kind    FileSystemSpecialPathTag
	path    string
	subpath ?codex_utils_path_uri.LegacyAppPathString
}

// STUB: FileSystemPath variant tags for the app-server's legacy API path seam.
pub enum FileSystemPathTag {
	path
	glob_pattern
	special
}

// STUB: FileSystemPath retains its legacy path, glob pattern or special selector.
pub struct FileSystemPath {
pub:
	kind    FileSystemPathTag
	path    codex_utils_path_uri.LegacyAppPathString
	pattern string
	value   FileSystemSpecialPath
}

// STUB: app-server-protocol/protocol/v2/permissions.rs::FileSystemSandboxEntry.
pub struct FileSystemSandboxEntry {
pub:
	path   FileSystemPath
	access FileSystemAccessMode
}

// STUB: AdditionalFileSystemPermissions keeps legacy roots and canonical entries;
// transport serialization and NonZeroUsize deserialization belong to its source owner.
pub struct AdditionalFileSystemPermissions {
pub:
	read                ?[]codex_utils_path_uri.LegacyAppPathString
	write               ?[]codex_utils_path_uri.LegacyAppPathString
	glob_scan_max_depth ?usize
	entries             ?[]FileSystemSandboxEntry
}

// STUB: RequestPermissionProfile's typed permission overlays.
pub struct RequestPermissionProfile {
pub:
	network     ?AdditionalNetworkPermissions
	file_system ?AdditionalFileSystemPermissions
}

// STUB: GrantedPermissionProfile defaults both permission overlays to None.
pub struct GrantedPermissionProfile {
pub:
	network     ?AdditionalNetworkPermissions
	file_system ?AdditionalFileSystemPermissions
}

// STUB: permission_path_uri prefers native AbsolutePathBuf normalization before
// trying foreign-platform LegacyAppPathString -> PathUri. Existing URI/parser
// limitations remain owned by codex_utils_path_uri's target-specific shims.
fn approval_permission_path_uri(path codex_utils_path_uri.LegacyAppPathString) !codex_utils_path_uri.PathUri {
	text := path.as_str()
	if absolute := codex_utils_absolute_path.from_absolute_path(&text) {
		return codex_utils_path_uri.PathUri.from_abs_path(&absolute)
	}
	if uri := path.to_inferred_path_uri() {
		return uri
	}
	if convention := path.infer_absolute_path_convention() {
		name := if convention == .posix { 'POSIX' } else { 'Windows' }
		return std_io.Error.new(.invalid_input, 'path `${text}` is not absolute using ${name} path syntax')
	}
	return std_io.Error.new(.invalid_input, 'path `${text}` is not absolute')
}

// STUB: Borrowed core literal selector -> owned canonical URI. The existing
// native-text selector representation remains accepted alongside the new typed
// URI payload. V has no borrowed return spanning these two representations.
fn approval_core_path_uri(path &permissions.FileSystemPath) ?codex_utils_path_uri.PathUri {
	if path.uri.has_value {
		return codex_utils_path_uri.PathUri{ path: path.uri.value.path.clone() }
	}
	if path.kind != 'path' {
		return none
	}
	absolute := codex_utils_absolute_path.from_absolute_path(&path.path) or { return none }
	return codex_utils_path_uri.PathUri.from_abs_path(&absolute)
}

// STUB: From<CoreFileSystemPermissions>, preserving both legacy projections and
// canonical entries. Read roots precede write roots in the native legacy branch;
// incompatible selectors suppress legacy fields without dropping canonical data.
pub fn AdditionalFileSystemPermissions.from_core(value models.FileSystemPermissions) AdditionalFileSystemPermissions {
	mut native_read := []codex_utils_absolute_path.AbsolutePathBuf{}
	mut native_write := []codex_utils_absolute_path.AbsolutePathBuf{}
	mut native_compatible := value.glob_scan_max_depth == none
	if native_compatible {
		for index in 0 .. value.entries.len {
			entry := &value.entries[index]
			if entry.path.kind != 'path' || entry.access == .deny {
				native_compatible = false
				break
			}
			uri := approval_core_path_uri(&entry.path) or {
				native_compatible = false
				break
			}
			absolute := uri.to_abs_path() or {
				native_compatible = false
				break
			}
			match entry.access {
				.read { native_read << absolute }
				.write { native_write << absolute }
				.deny {}
			}
		}
	}
	if native_compatible {
		read_roots := native_read
		write_roots := native_write
		mut read := []codex_utils_path_uri.LegacyAppPathString{}
		mut write := []codex_utils_path_uri.LegacyAppPathString{}
		mut entries := []FileSystemSandboxEntry{cap: read_roots.len + write_roots.len}
		for index in 0 .. read_roots.len {
			path := &read_roots[index]
			read << codex_utils_path_uri.LegacyAppPathString.from_abs_path(path)
			entries << FileSystemSandboxEntry{
				path:   FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_abs_path(path) }
				access: .read
			}
		}
		for index in 0 .. write_roots.len {
			path := &write_roots[index]
			write << codex_utils_path_uri.LegacyAppPathString.from_abs_path(path)
			entries << FileSystemSandboxEntry{
				path:   FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_abs_path(path) }
				access: .write
			}
		}
		return AdditionalFileSystemPermissions{
			read:                if read.len > 0 { read } else { none }
			write:               if write.len > 0 { write } else { none }
			glob_scan_max_depth: none
			entries:             entries
		}
	}
	mut read := []codex_utils_path_uri.LegacyAppPathString{}
	mut write := []codex_utils_path_uri.LegacyAppPathString{}
	mut legacy_compatible := value.glob_scan_max_depth == none
	if legacy_compatible {
		for index in 0 .. value.entries.len {
			entry := &value.entries[index]
			if entry.path.kind != 'path' || entry.access == .deny {
				legacy_compatible = false
				break
			}
			uri := approval_core_path_uri(&entry.path) or {
				legacy_compatible = false
				break
			}
			legacy_path := codex_utils_path_uri.LegacyAppPathString.from_string(uri.inferred_native_path_string())
			inferred := legacy_path.to_inferred_path_uri() or {
				legacy_compatible = false
				break
			}
			if inferred.path != uri.path {
				legacy_compatible = false
				break
			}
			match entry.access {
				.read { read << legacy_path }
				.write { write << legacy_path }
				.deny {}
			}
		}
	}
	mut entries := []FileSystemSandboxEntry{cap: value.entries.len}
	for entry in value.entries {
		entries << FileSystemSandboxEntry.from_core(entry)
	}
	return AdditionalFileSystemPermissions{
		read:                if legacy_compatible && read.len > 0 { read } else { none }
		write:               if legacy_compatible && write.len > 0 { write } else { none }
		glob_scan_max_depth: value.glob_scan_max_depth
		entries:             entries
	}
}

// STUB: TryFrom<AdditionalFileSystemPermissions> for CoreFileSystemPermissions.
// Canonical entries take precedence over legacy read/write fields, including
// Some(empty entries); validation errors propagate in source iteration order.
pub fn (value AdditionalFileSystemPermissions) to_core() !models.FileSystemPermissions {
	mut entries := []permissions.FileSystemSandboxEntry{}
	if canonical := value.entries {
		for entry in canonical {
			entries << entry.to_core()!
		}
	} else {
		if read := value.read {
			for path in read {
				entries << permissions.FileSystemSandboxEntry{
					path:   permissions.FileSystemPath{ kind: 'path', uri: permissions.FileSystemPathUri.some(approval_permission_path_uri(path)!) }
					access: .read
				}
			}
		}
		if write := value.write {
			for path in write {
				entries << permissions.FileSystemSandboxEntry{
					path:   permissions.FileSystemPath{ kind: 'path', uri: permissions.FileSystemPathUri.some(approval_permission_path_uri(path)!) }
					access: .write
				}
			}
		}
	}
	return models.FileSystemPermissions{ entries: entries, glob_scan_max_depth: value.glob_scan_max_depth }
}

// STUB: TryFrom<RequestPermissionProfile> for CoreRequestPermissionProfile.
// V names the consuming conversion on the API owner to avoid an import cycle.
pub fn (value RequestPermissionProfile) to_core() !request_permissions.RequestPermissionProfile {
	return request_permissions.RequestPermissionProfile{
		network:     if network := value.network {
			models.NetworkPermissions{ enabled: network.enabled }
		} else {
			none
		}
		file_system: if file_system := value.file_system { file_system.to_core()! } else { none }
	}
}

// STUB: From<CoreFileSystemPath> at the API legacy-path conversion seam.
pub fn FileSystemPath.from_core(value permissions.FileSystemPath) FileSystemPath {
	match value.kind {
		'path' {
			uri := approval_core_path_uri(&value) or {
				// Existing partial native selectors cannot express an invalid PathUri.
				// Preserve their raw spelling for the untranslated runtime boundary.
				return FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_string(value.path) }
			}
			return FileSystemPath{ kind: .path, path: codex_utils_path_uri.LegacyAppPathString.from_string(uri.inferred_native_path_string()) }
		}
		'glob_pattern' { return FileSystemPath{ kind: .glob_pattern, pattern: value.pattern } }
		'special' {
			kind := match value.special {
				.root { FileSystemSpecialPathTag.root }
				.minimal { FileSystemSpecialPathTag.minimal }
				.project_roots, .workspace_roots { FileSystemSpecialPathTag.project_roots }
				.tmpdir { FileSystemSpecialPathTag.tmpdir }
				.slash_tmp { FileSystemSpecialPathTag.slash_tmp }
				.unknown { FileSystemSpecialPathTag.unknown }
			}
			return FileSystemPath{
				kind:  .special
				value: FileSystemSpecialPath{
					kind:    kind
					path:    value.unknown_path
					subpath: if subpath := value.subpath {
						codex_utils_path_uri.LegacyAppPathString.from_string(subpath)
					} else {
						none
					}
				}
			}
		}
		else { panic('untranslated core filesystem selector: ${value.kind}') }
	}
}

// STUB: TryFrom<FileSystemPath> for CoreFileSystemPath preserves owned payloads.
pub fn (value FileSystemPath) to_core() !permissions.FileSystemPath {
	match value.kind {
		.path {
			return permissions.FileSystemPath{ kind: 'path', uri: permissions.FileSystemPathUri.some(approval_permission_path_uri(value.path)!) }
		}
		.glob_pattern {
			return permissions.FileSystemPath{ kind: 'glob_pattern', pattern: value.pattern }
		}
		.special {
			special := match value.value.kind {
				.root { permissions.FileSystemSpecialPath.root }
				.minimal { permissions.FileSystemSpecialPath.minimal }
				.project_roots { permissions.FileSystemSpecialPath.project_roots }
				.tmpdir { permissions.FileSystemSpecialPath.tmpdir }
				.slash_tmp { permissions.FileSystemSpecialPath.slash_tmp }
				.unknown { permissions.FileSystemSpecialPath.unknown }
			}
			return permissions.FileSystemPath{
				kind:         'special'
				special:      special
				unknown_path: value.value.path
				subpath:      if subpath := value.value.subpath {
					subpath.into_string()
				} else {
					none
				}
			}
		}
	}
}

// STUB: From<CoreFileSystemSandboxEntry>, dropping only source-unobserved
// missing_path_behavior because the app-server entry has no such field.
pub fn FileSystemSandboxEntry.from_core(value permissions.FileSystemSandboxEntry) FileSystemSandboxEntry {
	return FileSystemSandboxEntry{ path: FileSystemPath.from_core(value.path), access: value.access }
}

// STUB: TryFrom<FileSystemSandboxEntry> sets core missing_path_behavior to None.
pub fn (value FileSystemSandboxEntry) to_core() !permissions.FileSystemSandboxEntry {
	return permissions.FileSystemSandboxEntry{ path: value.path.to_core()!, access: value.access, missing_path_behavior: none }
}
