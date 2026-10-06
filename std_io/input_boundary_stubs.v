module std_io

// STUB: std::io::ErrorKind cases observed at the terminal-input boundary. Unclassified OS
// errors retain their original numeric code and message rather than claiming another kind.
pub enum ErrorKind {
	other
	interrupted
	timed_out
	unsupported
	not_found
	permission_denied
	would_block
	invalid_input
	// STUB: std::io::ErrorKind::InvalidData is used for typed config deserialization.
	invalid_data
	broken_pipe
	// STUB: std::io::ErrorKind::AlreadyExists, also used by terminal stderr suppression.
	already_exists
}

// STUB: std::io::Error. V's result error interface carries the owned message, kind, and native
// code together; its borrowed msg() accessor must allocate because V has no borrowed &str return.
pub struct Error {
	error_kind ErrorKind
	message    string
	os_code    int
	native     bool
}

// STUB: std::io::Error::new, preserving the owned message supplied by the caller.
pub fn Error.new(kind ErrorKind, message string) Error {
	return Error{ error_kind: kind, message: message }
}

// STUB: std::io::Error::from_raw_os_error with the native message/kind resolved by the caller.
pub fn Error.from_native(kind ErrorKind, os_code int, message string) Error {
	return Error{ error_kind: kind, message: message, os_code: os_code, native: true }
}

// STUB: std::io::Error::kind.
pub fn (err &Error) kind() ErrorKind {
	return err.error_kind
}

// STUB: std::io::Error's Display adapter; returns an owned V string from the borrowed error.
pub fn (err &Error) msg() string {
	if err.native {
		return '${err.message} (os error ${err.os_code})'
	}
	return err.message.clone()
}

// STUB: std::io::Error::raw_os_error as V's IError numeric code (zero for non-native errors).
pub fn (err &Error) code() int {
	return err.os_code
}
