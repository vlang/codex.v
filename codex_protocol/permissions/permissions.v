module permissions

import codex_utils_absolute_path
import codex_utils_path_uri
import os

pub type AbsolutePathBuf = codex_utils_absolute_path.AbsolutePathBuf

// STUB: Filesystem access modes.
pub enum FileSystemAccessMode {
	read
	write
	deny
}

// STUB: Filesystem sandbox policy kind.
pub enum FileSystemSandboxKind {
	unrestricted
	restricted
}

// STUB: Symbolic filesystem paths.
pub enum FileSystemSpecialPath {
	root
	minimal
	project_roots
	workspace_roots
	tmpdir
	slash_tmp
	unknown
}

// STUB: Filesystem path selector.
pub struct FileSystemPath {
pub:
	kind    string
	path    string
	special FileSystemSpecialPath
	subpath ?string
	// STUB: Typed canonical PathUri retains identity at app-server conversion seams.
	// Existing native `path` callers remain supported until the permissions port.
	uri FileSystemPathUri
	// STUB: Payloads of the untranslated GlobPattern and Unknown selector variants.
	pattern      string
	unknown_path string
}

// STUB: Optional canonical PathUri payload alongside the existing native-path
// representation. A tagged wrapper lets borrowed selectors remain reusable in
// V's ownership checker, which moves composite ?PathUri during if-let matching.
pub struct FileSystemPathUri {
pub:
	has_value bool
	value     codex_utils_path_uri.PathUri
}

// STUB: Owned canonical URI construction for the untranslated selector owner.
pub fn FileSystemPathUri.some(value codex_utils_path_uri.PathUri) FileSystemPathUri {
	return FileSystemPathUri{ has_value: true, value: value }
}

// STUB: A filesystem sandbox rule.
pub struct FileSystemSandboxEntry {
pub:
	path                  FileSystemPath
	access                FileSystemAccessMode
	missing_path_behavior ?string
}

// STUB: Canonical filesystem sandbox policy.
pub struct FileSystemSandboxPolicy {
pub:
	kind              string
	entries           []FileSystemSandboxEntry
	platform_defaults bool
	// STUB: models.rs/permissions.rs retain the managed filesystem scan limit.
	glob_scan_max_depth ?usize
}

// STUB: Canonical network sandbox policy.
pub struct NetworkSandboxPolicy {
pub:
	kind string
}

// STUB: Raw serialized filesystem policy.
pub struct RawFileSystemSandboxPolicy {
pub:
	kind    string
	entries []FileSystemSandboxEntry
}

// STUB: Parse and validate a raw filesystem sandbox policy later.
pub fn file_system_sandbox_policy_from_str(value &string) !FileSystemSandboxPolicy {
	return FileSystemSandboxPolicy{ kind: value }
}

// STUB: Parse and validate a network sandbox policy later.
pub fn network_sandbox_policy_from_str(value &string) !NetworkSandboxPolicy {
	return NetworkSandboxPolicy{ kind: value }
}

// STUB: Restricted policy constructor.
pub fn restricted(entries []FileSystemSandboxEntry) FileSystemSandboxPolicy {
	return FileSystemSandboxPolicy{ kind: 'restricted', entries: entries }
}

// STUB: Legacy policy projection. The caller supplies the already translated legacy kind.
pub fn from_legacy_sandbox_policy_for_cwd(kind string, cwd string) FileSystemSandboxPolicy {
	_ = cwd
	return FileSystemSandboxPolicy{ kind: kind }
}

// STUB: Raw-to-canonical policy projection.
pub fn from_raw(raw RawFileSystemSandboxPolicy) !FileSystemSandboxPolicy {
	return FileSystemSandboxPolicy{ kind: raw.kind, entries: raw.entries }
}

// STUB: Network policy projection from a legacy sandbox policy.
pub fn network_from_legacy(kind string, enabled bool) NetworkSandboxPolicy {
	return NetworkSandboxPolicy{ kind: if enabled { 'enabled' } else { kind } }
}

// STUB: Protected workspace metadata discovery belongs to permissions.rs.
pub fn default_read_only_subpaths_for_writable_root(root &AbsolutePathBuf, protect_missing_dot_codex bool) []AbsolutePathBuf {
	mut paths := []AbsolutePathBuf{}
	for name in ['.git', '.agents'] {
		candidate := '${root.path}/${name}'
		if os.exists(candidate) {
			paths << AbsolutePathBuf{ path: candidate }
		}
	}
	dot_codex := '${root.path}/.codex'
	if protect_missing_dot_codex || os.exists(dot_codex) {
		paths << AbsolutePathBuf{ path: dot_codex }
	}
	return paths
}

// STUB: Full disk read evaluation belongs to permissions.rs.
pub fn (policy &FileSystemSandboxPolicy) has_full_disk_read_access() bool {
	return policy.kind == 'danger_full_access'
}

// STUB: Full disk write evaluation belongs to permissions.rs.
pub fn (policy &FileSystemSandboxPolicy) has_full_disk_write_access() bool {
	return policy.additional_dirs_full_disk_write_access()
}

// STUB: Platform-default inclusion belongs to permissions.rs.
pub fn (policy &FileSystemSandboxPolicy) include_platform_defaults() bool {
	return policy.platform_defaults
}
