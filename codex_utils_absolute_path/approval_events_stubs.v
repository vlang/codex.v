module codex_utils_absolute_path

import encoding.utf8
import serde_json
import os

// STUB: AbsolutePathBuf's serde newtype serialization delegates to native Path.
pub fn (path &AbsolutePathBuf) serialize_json() !string {
	if !utf8.validate(path.path.str, path.path.len) {
		return error('path contains invalid UTF-8 characters')
	}
	return serde_json.quote_string(&path.path)
}

// STUB: AbsolutePathBuf's serde Deserialize without a thread-local base guard.
// Relative input fails as in Rust; guard/home expansion and foreign-platform
// normalization remain owned by the untranslated absolute-path runtime.
pub fn AbsolutePathBuf.deserialize_json(text &string) !AbsolutePathBuf {
	value := serde_json.raw_json_value(text)!
	bytes := value.string_owned()!
	if !os.is_abs_path(bytes) { return error('AbsolutePathBuf deserialized without a base path') }
	return from_absolute_path(&bytes)
}
