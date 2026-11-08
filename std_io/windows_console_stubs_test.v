module std_io

import windows_sys.win32.foundation

fn test_windows_console_error_decoder_validates_complete_utf16_sequences() {
	mut buffer := [2048]u16{}
	assert windows_console_valid_utf16(&buffer, 0)
	buffer[0] = u16(`A`)
	buffer[1] = 0xd83d
	buffer[2] = 0xde80
	buffer[3] = u16(`B`)
	assert windows_console_valid_utf16(&buffer, 4)
	assert windows_console_valid_utf16(&buffer, 4)
	assert buffer[1] == 0xd83d
	assert buffer[2] == 0xde80
	assert !windows_console_valid_utf16(&buffer, 2)
	buffer[2] = u16(`C`)
	assert !windows_console_valid_utf16(&buffer, 4)
	buffer[1] = 0xde80
	assert !windows_console_valid_utf16(&buffer, 4)
	buffer[1] = u16(`D`)
	buffer[2046] = 0xd83d
	buffer[2047] = 0xde80
	assert windows_console_valid_utf16(&buffer, 2048)
	assert !windows_console_valid_utf16(&buffer, 2047)
}

fn test_windows_console_last_os_error_retains_native_kind_code_and_message() {
	foundation.reset_test_last_error()
	foundation.set_test_last_error(5)
	native_error := Error.last_os_error()
	foundation.set_test_last_error(87)
	assert native_error.kind() == .permission_denied
	assert native_error.code() == 5
	assert native_error.msg() == 'fixture Windows error 5 (os error 5)'
	assert native_error.msg() == 'fixture Windows error 5 (os error 5)'
	assert foundation.test_last_error_reads() == 1
	new_error := Error.last_os_error()
	assert new_error.kind() == .invalid_input
	assert new_error.code() == 87
	assert new_error.msg() == 'fixture Windows error 87 (os error 87)'
	assert foundation.test_last_error_reads() == 2
}

fn test_windows_console_last_os_error_keeps_unknown_high_codes_and_zero_native() {
	foundation.reset_test_last_error()
	foundation.set_test_last_error(0xf123_4567)
	high_error := Error.last_os_error()
	assert high_error.kind() == .other
	assert high_error.code() == -249346713
	assert high_error.msg() == 'fixture Windows error 4045620583 (os error -249346713)'
	foundation.set_test_last_error(0)
	zero_error := Error.last_os_error()
	assert zero_error.kind() == .other
	assert zero_error.code() == 0
	assert zero_error.msg() == 'fixture Windows error 0 (os error 0)'
}
