module std_io

$if windows || test {
	import windows_sys.win32.foundation
}

$if windows {
	// STUB: Rust std's Windows error formatter borrows the loaded ntdll module.
	fn C.GetModuleHandleW(&u16) voidptr
}

// STUB: std::io::Error::last_os_error. Capture GetLastError before formatting so
// later Win32 calls cannot overwrite the failure; retain its full signed raw code.
pub fn Error.last_os_error() Error {
	$if windows || test {
		code := foundation.get_last_error()
		message := windows_console_error_message(code)
		return Error.from_native(windows_console_error_kind(code), int(i32(code)), message)
	} $else {
		return Error.new(.unsupported, 'Windows console last_os_error boundary is unavailable on this platform')
	}
}

// STUB: Windows native error formatting at std::io's external dependency boundary.
// Match Rust 1.95 std/sys/io/error/windows.rs, including HRESULT-encoded NTSTATUS,
// strict UTF-16 validation, fallback errors, and trailing ASCII whitespace removal.
fn windows_console_error_message(code u32) string {
	$if test {
		return 'fixture Windows error ${code}'
	} $else $if windows {
		mut error_number := code
		mut module := unsafe { voidptr(nil) }
		mut flags := u32(0x1000 | 0x0200)
		if error_number & u32(0x1000_0000) != 0 {
			ntdll := [u16(`N`), u16(`T`), u16(`D`), u16(`L`), u16(`L`), u16(`.`), u16(`D`), u16(`L`),
				u16(`L`), u16(0)]!
			module = C.GetModuleHandleW(&ntdll[0])
			if module != unsafe { nil } {
				error_number ^= u32(0x1000_0000)
				flags |= u32(0x0800)
			}
		}
		mut buffer := [2048]u16{}
		length := C.FormatMessageW(flags, module, error_number, 0, &buffer[0], u32(buffer.len), unsafe { nil })
		if length == 0 {
			format_error := int(i32(C.GetLastError()))
			return 'OS Error ${int(i32(error_number))} (FormatMessageW() returned error ${format_error})'
		}
		if !windows_console_valid_utf16(&buffer, int(length)) {
			return 'OS Error ${int(i32(error_number))} (FormatMessageW() returned invalid UTF-16)'
		}
		message := unsafe { string_from_wide2(&buffer[0], int(length)) }
		return message.trim_right(' \t\n\r\x0b\x0c')
	} $else {
		return 'Windows console API is unavailable on this platform'
	}
}

// STUB: String::from_utf16 rejects unpaired surrogates; V's Windows conversion
// accepts WTF-8, so validate the native buffer before producing an owned message.
fn windows_console_valid_utf16(buffer &[2048]u16, length int) bool {
	mut index := 0
	for index < length {
		unit := buffer[index]
		if unit >= 0xd800 && unit <= 0xdbff {
			if index + 1 == length || buffer[index + 1] < 0xdc00 || buffer[index + 1] > 0xdfff {
				return false
			}
			index += 2
		} else if unit >= 0xdc00 && unit <= 0xdfff {
			return false
		} else {
			index++
		}
	}
	return true
}

// STUB: std::io::ErrorKind cases available in this port for Win32 failures.
// Untranslated ErrorKind cases remain other while retaining their native code.
fn windows_console_error_kind(code u32) ErrorKind {
	return match code {
		2, 3, 15, 53, 67 { .not_found }
		5, 10013 { .permission_denied }
		80, 183 { .already_exists }
		87, 10022 { .invalid_input }
		109, 232 { .broken_pipe }
		120 { .unsupported }
		10035 { .would_block }
		121, 258, 594, 995, 1053, 1121, 1460, 5910, 7012, 7040, 8014, 8226, 9705, 13805, 15402,
		15403, 10060 {
			.timed_out
		}
		else { .other }
	}
}
