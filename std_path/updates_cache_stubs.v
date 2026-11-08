module std_path

import os

// STUB: Path::join's owned PathBuf boundary for updates_cache's relative filename.
// Config's untranslated AbsolutePathBuf currently stores its owned bytes in string.
pub fn (path &Path) join(component &string) string {
	return os.join_path_single(path.to_path_buf(), component.clone())
}
