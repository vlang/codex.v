module permissions

// STUB: evaluates whether the effective filesystem policy permits writing `path` from `cwd`.
pub fn (policy &FileSystemSandboxPolicy) can_write_local_path_with_cwd(path &string, cwd &string) bool {
	_ = path
	_ = cwd
	return policy.kind == 'danger_full_access' || policy.kind == 'workspace_write'
}
