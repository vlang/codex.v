module permissions

import os
import std_path

// STUB: permissions.rs::has_full_disk_write_access for the existing native
// symbolic/literal rule representation. Executor URIs and glob policies remain
// unported; unsupported narrowing selectors conservatively prevent a full grant.
fn (policy &FileSystemSandboxPolicy) additional_dirs_full_disk_write_access() bool {
	if policy.kind in ['unrestricted', 'external_sandbox', 'danger_full_access'] {
		return true
	}
	mut root_write := false
	for index in 0 .. policy.entries.len {
		entry := &policy.entries[index]
		if entry.path.kind == 'special' && entry.path.special == .root && entry.access == .write {
			root_write = true
		}
	}
	if !root_write {
		return false
	}
	for index in 0 .. policy.entries.len {
		entry := &policy.entries[index]
		if entry.access == .write {
			continue
		}
		if entry.path.kind == 'special' {
			if entry.path.special == .minimal {
				continue
			}
			if entry.path.special == .root {
				if entry.access == .deny {
					return false
				}
				continue
			}
		}
		mut overridden := false
		for candidate_index in 0 .. policy.entries.len {
			candidate := &policy.entries[candidate_index]
			if candidate.access != .write || int(candidate.access) <= int(entry.access) {
				continue
			}
			if additional_dirs_selectors_share_target(&candidate.path, &entry.path) {
				overridden = true
				break
			}
		}
		if !overridden {
			return false
		}
	}
	return true
}

// STUB: file_system_paths_share_target for the native selectors represented here.
// Native literals use their normalized spelling; :root and the literal native
// root name the same cwd-independent target, as the source policy evaluator does.
fn additional_dirs_selectors_share_target(left &FileSystemPath, right &FileSystemPath) bool {
	if left == right {
		return true
	}
	if left.kind == 'path' && right.kind == 'path' {
		return additional_dirs_normalize(&left.path) == additional_dirs_normalize(&right.path)
	}
	if left.kind == 'special' && left.special == .root && right.kind == 'path' {
		return additional_dirs_literal_is_native_root(&right.path)
	}
	if right.kind == 'special' && right.special == .root && left.kind == 'path' {
		return additional_dirs_literal_is_native_root(&left.path)
	}
	return false
}

// STUB: the native root subset of special_path_matches_path_uri.
fn additional_dirs_literal_is_native_root(path &string) bool {
	view := std_path.Path.new(path)
	if !view.is_absolute() {
		return false
	}
	normalized := additional_dirs_normalize(path)
	root := additional_dirs_native_root(&normalized)
	return normalized == additional_dirs_normalize(&root)
}

// STUB: permissions.rs::can_write_local_path_with_cwd's native-path adapter.
// This boundary resolves root/workspace/project symbolic selectors and literal
// native paths, applying longest-root then access-order precedence. Selected
// executor URI/glob expansion and ambient minimal grants are still untranslated;
// unsupported non-minimal selectors fail closed rather than inventing a grant.
pub fn (policy &FileSystemSandboxPolicy) can_write_local_path_with_cwd(path &std_path.Path, cwd &std_path.Path) bool {
	if policy.kind in ['unrestricted', 'external_sandbox', 'danger_full_access'] {
		return true
	}
	// Keep native path bytes for permission matching. Lossy text is appropriate
	// for the warning display, but can collapse distinct non-Unicode paths here.
	cwd_text := cwd.to_path_buf()
	if !cwd.is_absolute() {
		return false
	}
	resolved_cwd := additional_dirs_normalize(&cwd_text)
	path_text := path.to_path_buf()
	resolved_path := if path.is_absolute() {
		additional_dirs_normalize(&path_text)
	} else {
		joined := os.join_path(resolved_cwd, path_text)
		additional_dirs_normalize(&joined)
	}
	mut roots := []NativePermissionRoot{cap: policy.entries.len}
	if policy.kind == 'workspace_write' {
		roots << NativePermissionRoot{ path: resolved_cwd.clone(), access: .write }
	}
	for index in 0 .. policy.entries.len {
		entry := &policy.entries[index]
		if entry.path.kind == 'special' && entry.path.special == .minimal {
			continue
		}
		root := additional_dirs_resolve_selector(&entry.path, &resolved_cwd) or { return false }
		roots << NativePermissionRoot{ path: root, access: entry.access }
	}
	mut depth := -1
	mut access := FileSystemAccessMode.deny
	for index in 0 .. roots.len {
		root := unsafe { &roots[index] }
		if !additional_dirs_path_under(&resolved_path, &root.path) {
			continue
		}
		root_depth := additional_dirs_path_depth(&root.path)
		if root_depth > depth || (root_depth == depth && int(root.access) > int(access)) {
			depth = root_depth
			access = root.access
		}
	}
	if access != .write {
		return false
	}
	if policy.has_full_disk_write_access() {
		return true
	}
	// Preserve protected metadata denial, unless an explicit write root at or
	// below the metadata directory grants it back, as permissions.rs does.
	for index in 0 .. roots.len {
		root := unsafe { &roots[index] }
		if root.access != .write {
			continue
		}
		for name in ['.git', '.agents', '.codex'] {
			joined := os.join_path(root.path, name)
			protected := additional_dirs_normalize(&joined)
			if !additional_dirs_path_under(&resolved_path, &protected) {
				continue
			}
			mut explicit_write := false
			for candidate_index in 0 .. roots.len {
				candidate := unsafe { &roots[candidate_index] }
				if candidate.access == .write && additional_dirs_path_under(&resolved_path, &candidate.path)
					&& additional_dirs_path_under(&candidate.path, &protected) {
					explicit_write = true
					break
				}
			}
			// Source metadata_write_denial uses the first matching protected
			// directory, then checks every explicit write root against that one.
			return explicit_write
		}
	}
	return true
}

// STUB: resolved native rule from permissions.rs's selected-executor evaluator.
struct NativePermissionRoot {
	path   string
	access FileSystemAccessMode
}

// STUB: the representable symbolic/native selector subset of resolved_entries.
fn additional_dirs_resolve_selector(selector &FileSystemPath, cwd &string) ?string {
	if selector.kind == 'path' {
		view := std_path.Path.new(&selector.path)
		if !view.is_absolute() {
			return none
		}
		return additional_dirs_normalize(&selector.path)
	}
	if selector.kind != 'special' {
		return none
	}
	mut root := match selector.special {
		.root { additional_dirs_native_root(cwd) }
		.project_roots, .workspace_roots { cwd.clone() }
		.minimal, .tmpdir, .slash_tmp, .unknown { return none }
	}
	if subpath := selector.subpath {
		joined := os.join_path(root, subpath)
		root = joined
	}
	return additional_dirs_normalize(&root)
}

// STUB: borrowed native path normalization constructs the owned query result.
fn additional_dirs_normalize(path &string) string {
	mut normalized := os.norm_path(*path)
	$if windows {
		normalized = normalized.replace('\\', '/')
		mut bytes := normalized.bytes()
		for index in 0 .. bytes.len {
			if bytes[index] >= `A` && bytes[index] <= `Z` {
				bytes[index] += 32
			}
		}
		return bytes.bytestr()
	}
	return normalized
}

// STUB: lexical native component ancestry, with the root separator kept intact.
fn additional_dirs_path_under(path &string, root &string) bool {
	if *path == *root {
		return true
	}
	prefix := if root.ends_with('/') { root.clone() } else { '${*root}/' }
	return path.starts_with(prefix)
}

// STUB: ordinary native path depth used by resolve_access precedence.
fn additional_dirs_path_depth(path &string) int {
	mut count := 0
	for part in path.split('/') {
		if part.len > 0 { count++ }
	}
	return count
}

// STUB: the selected native filesystem root for root-symbol resolution.
fn additional_dirs_native_root(cwd &string) string {
	$if windows {
		if cwd.len >= 3 && (*cwd)[1] == `:` {
			return (*cwd)[..3].clone()
		}
		if cwd.starts_with('//') {
			parts := cwd.split('/')
			if parts.len >= 4 {
				return '//${parts[2]}/${parts[3]}'
			}
		}
	}
	return '/'.clone()
}
