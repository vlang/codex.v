module path_utils

import os

// STUB: normalize_for_native_workdir is owned by codex-utils-absolute-path/path_utils.rs.
pub fn normalize_for_native_workdir(path string) string {
	return os.norm_path(path)
}

// STUB: paths_match_after_normalization is owned by codex-utils-absolute-path/path_utils.rs.
pub fn paths_match_after_normalization(left &string, right &string) bool {
	return os.norm_path(*left) == os.norm_path(*right)
}
