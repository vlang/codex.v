module std_path

// STUB: std::path::Path::is_absolute using the borrowed path view shared with
// git_action_directives. Unix needs a root; Windows needs a prefix and root.
pub fn (path &Path) is_absolute() bool {
	$if windows {
		prefix_end, implicit_root, verbatim := windows_prefix(path)
		return prefix_end > 0 && (implicit_root || (prefix_end < path.end - path.start
			&& path_is_separator((*path.source)[path.start + prefix_end], verbatim)))
	} $else {
		return path.end > path.start && (*path.source)[path.start] == `/`
	}
}

// STUB: std::path::Path::to_path_buf clones the borrowed native-path bytes into
// an owned V string, matching the Rust PathBuf allocation boundary.
pub fn (path &Path) to_path_buf() string {
	return (*path.source)[path.start..path.end].clone()
}
