module std_path

import encoding.utf8
import serde_json

// STUB: std::path::PathBuf owns native path bytes. The existing Path view supplies
// platform-aware lexical behavior; Windows currently uses UTF-8 rather than WTF-16.
pub struct PathBuf {
	bytes string
}

// STUB: std::path::PathBuf::from(String) consumes its owned native-path storage.
pub fn PathBuf.from(bytes string) PathBuf {
	return PathBuf{ bytes: bytes }
}

// STUB: std::path::PathBuf::as_path borrows the owned storage without copying it.
pub fn (path &PathBuf) as_path() Path {
	return Path.new(&path.bytes)
}

// STUB: std::path::PathBuf's Clone allocates independent native-path storage.
pub fn (path &PathBuf) clone() PathBuf {
	return PathBuf{ bytes: path.bytes.clone() }
}

// STUB: std::path::PathBuf's PartialEq uses Path's lexical component equality.
pub fn (path &PathBuf) equals(other &PathBuf) bool {
	left := path.as_path()
	right := other.as_path()
	return left.equals(&right)
}

// STUB: serde's Serialize for PathBuf delegates to Path::to_str, rejecting invalid
// native UTF-8 instead of performing a lossy conversion.
pub fn (path &PathBuf) serialize_json() !string {
	if !utf8.validate(path.bytes.str, path.bytes.len) {
		return error('path contains invalid UTF-8 characters')
	}
	return serde_json.quote_string(&path.bytes)
}
