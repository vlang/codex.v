module codex_utils_path_uri

import serde_json

// STUB: LegacyAppPathString's derived Clone owns independent UTF-8 storage.
pub fn (path &LegacyAppPathString) clone() LegacyAppPathString {
	return LegacyAppPathString{ path: path.path.clone() }
}

// STUB: LegacyAppPathString's serde-transparent String serialization borrows the
// private path bytes, avoiding an allocation solely to expose the string view.
pub fn (path &LegacyAppPathString) serialize_json() string {
	return serde_json.quote_string(&path.path)
}
