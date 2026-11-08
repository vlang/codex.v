module windows_console

$if windows || test {
	import std_io
	import sync
	import windows_sys.win32.foundation
	import windows_sys.win32.system.console
}

const enable_virtual_terminal_input = u32(0x0200)

// V has no pub(super); this Copy enum is exported to the parent TUI module.
pub enum VirtualTerminalInput {
	enabled
	disabled
}

pub fn input_record_mode(mode u32) u32 {
	return mode & ~enable_virtual_terminal_input
}

pub fn restored_input_mode(mode u32, original VirtualTerminalInput) u32 {
	return match original {
		.enabled { mode | enable_virtual_terminal_input }
		.disabled { input_record_mode(mode) }
	}
}

$if windows || test {
	const original_vt_input = &OriginalVtInput{}

	// A heap owner and scoped defer adapt Mutex<Vec<VirtualTerminalInput>> and MutexGuard.
	// V mutexes have no poison state: a panic aborts rather than unwinding, so locking
	// directly is equivalent to Rust's recovery through PoisonError::into_inner.
	@[heap]
	struct OriginalVtInput {
	mut:
		mutex &sync.Mutex = sync.new_mutex()
		modes []VirtualTerminalInput
	}

	fn current_input_mode() ?(foundation.Handle, u32) {
		handle := console.get_std_handle(console.std_input_handle)
		if handle == foundation.invalid_handle_value || handle == foundation.Handle(0) {
			return none
		}

		mut mode := console.ConsoleMode{}
		if console.get_console_mode(handle, mut mode) == 0 {
			return none
		}

		return handle, mode.value
	}
}

// Windows-only source bodies also compile in tests to exercise the same API calls
// through typed fixtures. Normal non-Windows builds have no console side effects.
pub fn set_input_record_mode() ! {
	$if windows || test {
		handle, mode := current_input_mode() or { return }
		requested_mode := input_record_mode(mode)
		if requested_mode != mode && console.set_console_mode(handle, requested_mode) == 0 {
			return std_io.Error.last_os_error()
		}

		original := if mode & enable_virtual_terminal_input != 0 {
			VirtualTerminalInput.enabled
		} else {
			VirtualTerminalInput.disabled
		}
		mut original_modes := unsafe { original_vt_input }
		original_modes.mutex.lock()
		defer { original_modes.mutex.unlock() }
		original_modes.modes << original
	}
}

pub fn ensure_input_record_mode() ! {
	$if windows || test {
		handle, mode := current_input_mode() or { return }
		requested_mode := input_record_mode(mode)
		if requested_mode != mode && console.set_console_mode(handle, requested_mode) == 0 {
			return std_io.Error.last_os_error()
		}
	}
}

pub fn restore_input_mode() ! {
	$if windows || test {
		mut original_modes := unsafe { original_vt_input }
		original_modes.mutex.lock()
		defer { original_modes.mutex.unlock() }
		if original_modes.modes.len == 0 {
			return
		}
		original := original_modes.modes.last()
		handle, mode := current_input_mode() or {
			original_modes.modes.pop()
			return
		}
		requested_mode := restored_input_mode(mode, original)
		if requested_mode != mode && console.set_console_mode(handle, requested_mode) == 0 {
			return std_io.Error.last_os_error()
		}

		original_modes.modes.pop()
	}
}
