module codex_utils_path_uri

// STUB: utils/path-uri/src/api_path_string.rs::LegacyAppPathString::into_string
// transfers its owned String payload without allocating a borrowed text copy.
pub fn (path LegacyAppPathString) into_string() string {
	return path.path
}
