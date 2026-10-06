module pathdiff

import std_path

// STUB: pathdiff::diff_paths computes the lexical relative path used by the
// source fixture. Native Windows drive/prefix mismatches remain unsupported.
pub fn diff_paths(path &std_path.Path, base &std_path.Path) ?std_path.PathBuf {
	path_text := path.to_string_lossy()
	base_text := base.to_string_lossy()
	if !path.is_absolute() || !base.is_absolute() { return none }
	separator := $if windows { '\\' } $else { '/' }
	parts := path_text.split(separator)
	bases := base_text.split(separator)
	$if windows {
		if parts.len == 0 || bases.len == 0 || parts[0] != bases[0] { return none }
	}
	mut common := 0
	for common < parts.len && common < bases.len && parts[common] == bases[common] { common++ }
	mut result := []string{}
	for index in common .. bases.len { if bases[index].len > 0 { result << '..' } }
	for index in common .. parts.len { if parts[index].len > 0 { result << parts[index].clone() } }
	return std_path.PathBuf.from(result.join(separator))
}
