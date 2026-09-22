module loader

import os

// STUB: project_trust_key is owned by codex-config/loader and normalizes a project path for the
// `[projects]` trust table.
pub fn project_trust_key(path &string) string {
	return os.norm_path(*path)
}
