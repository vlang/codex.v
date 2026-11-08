module std_ffi

import encoding.utf8

// STUB: std::ffi::OsString stores arbitrary native Unix bytes. As with the
// existing Path adapter, Windows storage currently uses UTF-8 rather than WTF-16.
pub struct OsString {
pub:
	bytes string
}

// STUB: OsString::from(String) consumes the owned native string storage.
pub fn OsString.from(bytes string) OsString {
	return OsString{ bytes: bytes }
}

// STUB: Unix OsStringExt::from_vec consumes the original arbitrary byte vector.
pub fn OsString.from_vec(bytes []u8) OsString {
	return OsString{ bytes: bytes.bytestr() }
}

// STUB: Safe Copy view of Option<&str>; avoids V's unsupported &?string/ ?&string.
pub struct BorrowedUtf8 {
pub:
	present bool
	value   &string = unsafe { nil }
}

// STUB: OsStr::to_str borrows valid UTF-8 and rejects invalid native bytes.
pub fn (value &OsString) to_str() BorrowedUtf8 {
	return BorrowedUtf8{ present: utf8.validate(value.bytes.str, value.bytes.len), value: &value.bytes }
}
