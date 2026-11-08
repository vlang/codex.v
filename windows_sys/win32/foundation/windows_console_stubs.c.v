module foundation

// STUB: windows_sys 0.52 Win32::Foundation::HANDLE is a pointer-sized Copy integer.
pub type Handle = isize

// STUB: windows_sys::Win32::Foundation::INVALID_HANDLE_VALUE.
pub const invalid_handle_value = Handle(-1)

// STUB: windows_sys::Win32::Foundation::GetLastError, using the real thread-local
// Win32 value on Windows and a typed fixture in terminal-console tests elsewhere.
pub fn get_last_error() u32 {
	$if test {
		mut state := unsafe { test_last_error }
		state.reads++
		return state.code
	} $else $if windows {
		return C.GetLastError()
	} $else {
		return 0
	}
}

$if test {
	// STUB: GetLastError's thread-local value at the single-threaded fixture boundary.
	@[heap]
	struct LastErrorFixture {
	mut:
		code  u32
		reads int
	}

	// STUB: a fixture owns the last-error value; no non-Windows native API is invoked.
	const test_last_error = &LastErrorFixture{}

	// STUB: SetLastError supplies the numeric fixture result for an individual API failure.
	pub fn set_test_last_error(code u32) {
		mut state := unsafe { test_last_error }
		state.code = code
	}

	// STUB: observation of GetLastError calls at the typed fixture boundary.
	pub fn test_last_error_reads() int {
		return test_last_error.reads
	}

	// STUB: reset GetLastError's value and observations between console fixtures.
	pub fn reset_test_last_error() {
		mut state := unsafe { test_last_error }
		state.code = 0
		state.reads = 0
	}
}
