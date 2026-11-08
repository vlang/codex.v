module console

import windows_sys.win32.foundation

// STUB: windows_sys::Win32::System::Console::STD_INPUT_HANDLE, a DWORD encoding -10.
pub const std_input_handle = u32(4294967286)

// STUB: Win32 GetConsoleMode's mutable DWORD output. V forbids mut scalar
// parameters, so this value wrapper preserves the borrowed output direction.
pub struct ConsoleMode {
pub mut:
	value u32
}

// STUB: windows_sys::Win32::System::Console::GetStdHandle. The fixture records the
// actual DWORD argument; normal Windows calls use V's existing WINAPI declaration.
pub fn get_std_handle(nstdhandle u32) foundation.Handle {
	$if test {
		mut fixture := unsafe { console_fixture }
		fixture.std_handle_requests << nstdhandle
		return fixture.handle
	} $else $if windows {
		return foundation.Handle(isize(C.GetStdHandle(nstdhandle)))
	} $else {
		return foundation.Handle(0)
	}
}

// STUB: windows_sys::Win32::System::Console::GetConsoleMode, preserving the BOOL
// result and mutable output parameter. Console handles remain borrowed Copy values.
pub fn get_console_mode(handle foundation.Handle, mut mode ConsoleMode) i32 {
	$if test {
		mut fixture := unsafe { console_fixture }
		fixture.mode_queries << handle
		if fixture.query_fails {
			foundation.set_test_last_error(fixture.error_code)
			return 0
		}
		mode.value = fixture.mode
		return 1
	} $else $if windows {
		return if C.GetConsoleMode(unsafe { voidptr(isize(handle)) }, &mode.value) { 1 } else { 0 }
	} $else {
		return 0
	}
}

// STUB: windows_sys::Win32::System::Console::SetConsoleMode, replacing the complete
// console mode only on success. Each fixture attempt retains its handle and DWORD.
pub fn set_console_mode(handle foundation.Handle, mode u32) i32 {
	$if test {
		mut fixture := unsafe { console_fixture }
		fixture.mode_changes << ModeChange{ handle: handle, mode: mode }
		if fixture.set_fails {
			foundation.set_test_last_error(fixture.error_code)
			return 0
		}
		fixture.mode = mode
		return 1
	} $else $if windows {
		return if C.SetConsoleMode(unsafe { voidptr(isize(handle)) }, mode) { 1 } else { 0 }
	} $else {
		return 0
	}
}

$if test {
	// STUB: typed observation of one SetConsoleMode(handle, mode) invocation.
	pub struct ModeChange {
	pub:
		handle foundation.Handle
		mode   u32
	}

	// STUB: individual Win32 console API fixture. Only tests configure or inspect it;
	// translated console logic continues to call the source-shaped functions above.
	@[heap]
	pub struct ConsoleFixture {
	pub mut:
		handle              foundation.Handle = foundation.Handle(7)
		mode                u32
		query_fails         bool
		set_fails           bool
		error_code          u32 = 5
		std_handle_requests []u32
		mode_queries        []foundation.Handle
		mode_changes        []ModeChange
	}

	// STUB: the fixture's single owner exists only in a V test build.
	const console_fixture = &ConsoleFixture{}

	// STUB: reset the typed fixture between tests without changing a native console.
	pub fn reset_test_fixture() &ConsoleFixture {
		mut fixture := unsafe { console_fixture }
		fixture.handle = foundation.Handle(7)
		fixture.mode = 0
		fixture.query_fails = false
		fixture.set_fails = false
		fixture.error_code = 5
		fixture.std_handle_requests.clear()
		fixture.mode_queries.clear()
		fixture.mode_changes.clear()
		foundation.reset_test_last_error()
		return fixture
	}
}
