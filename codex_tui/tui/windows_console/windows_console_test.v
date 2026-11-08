module windows_console

import std_io
import windows_sys.win32.foundation
import windows_sys.win32.system.console

fn reset_console() &console.ConsoleFixture {
	mut original_modes := unsafe { original_vt_input }
	original_modes.mutex.lock()
	original_modes.modes.clear()
	original_modes.mutex.unlock()
	return console.reset_test_fixture()
}

fn saved_modes() []VirtualTerminalInput {
	mut original_modes := unsafe { original_vt_input }
	original_modes.mutex.lock()
	defer { original_modes.mutex.unlock() }
	return original_modes.modes.clone()
}

// The parent tui.rs tests these exact values; retain its original setup/assertions.
fn test_windows_console_input_modes_preserve_original_vt_input_state() {
	record_mode := input_record_mode( /*mode*/
	u32(0x398))
	assert record_mode == 0x198
	assert restored_input_mode(record_mode, .enabled) == 0x398
	assert restored_input_mode( /*mode*/
	u32(0x198), .disabled) == 0x198
}

fn test_mode_changes_preserve_every_unrelated_bit() {
	for mode in [u32(0), 0x0200, 0x0398, 0xffff_ffff, 0xa5a5_5a5a] {
		record_mode := input_record_mode(mode)
		assert record_mode == mode & ~u32(0x0200)
		assert restored_input_mode(mode, .enabled) == mode | u32(0x0200)
		assert restored_input_mode(mode, .disabled) == record_mode
	}
}

fn test_invalid_and_null_handles_do_not_query_or_save_a_mode() {
	for handle in [foundation.invalid_handle_value, foundation.Handle(0)] {
		mut fixture := reset_console()
		fixture.handle = handle
		if _, _ := current_input_mode() {
			assert false
		}
		set_input_record_mode() or { panic(err.msg()) }
		ensure_input_record_mode() or { panic(err.msg()) }
		assert saved_modes() == []VirtualTerminalInput{}
		assert fixture.std_handle_requests == [console.std_input_handle, console.std_input_handle,
			console.std_input_handle]
		assert fixture.mode_queries == []foundation.Handle{}
		assert fixture.mode_changes == []console.ModeChange{}
		assert foundation.test_last_error_reads() == 0
	}
}

fn test_failed_mode_query_is_unavailable_and_does_not_return_an_error() {
	mut fixture := reset_console()
	fixture.mode = 0x398
	fixture.query_fails = true
	if _, _ := current_input_mode() {
		assert false
	}
	set_input_record_mode() or { panic(err.msg()) }
	ensure_input_record_mode() or { panic(err.msg()) }
	assert saved_modes() == []VirtualTerminalInput{}
	assert fixture.mode_queries == [foundation.Handle(7), foundation.Handle(7), foundation.Handle(7)]
	assert fixture.mode_changes == []console.ModeChange{}
	assert fixture.mode == 0x398
	assert foundation.test_last_error_reads() == 0
}

fn test_set_changes_mode_and_saves_the_original_enabled_state() {
	mut fixture := reset_console()
	fixture.mode = 0x398
	set_input_record_mode() or { panic(err.msg()) }
	assert fixture.mode == 0x198
	assert fixture.std_handle_requests == [console.std_input_handle]
	assert fixture.mode_queries == [foundation.Handle(7)]
	assert fixture.mode_changes == [console.ModeChange{ handle: foundation.Handle(7), mode: 0x198 }]
	assert saved_modes() == [VirtualTerminalInput.enabled]
	assert foundation.test_last_error_reads() == 0
}

fn test_set_already_disabled_still_pushes_without_calling_set_console_mode() {
	mut fixture := reset_console()
	fixture.mode = 0x198
	set_input_record_mode() or { panic(err.msg()) }
	assert fixture.mode == 0x198
	assert fixture.mode_changes == []console.ModeChange{}
	assert saved_modes() == [VirtualTerminalInput.disabled]
}

fn test_failed_set_preserves_mode_and_stack_and_returns_the_native_error() {
	mut fixture := reset_console()
	fixture.mode = 0x198
	set_input_record_mode() or { panic(err.msg()) }
	fixture.mode = 0x398
	fixture.set_fails = true
	fixture.error_code = 0xf123_4567
	mut failed := false
	set_input_record_mode() or {
		failed = true
		assert err is std_io.Error
		if err is std_io.Error {
			assert err.kind() == .other
			assert err.code() == int(i32(u32(0xf123_4567)))
			assert err.msg() == 'fixture Windows error 4045620583 (os error -249346713)'
		}
	}
	assert failed
	assert fixture.mode == 0x398
	assert fixture.mode_changes == [console.ModeChange{ handle: foundation.Handle(7), mode: 0x198 }]
	assert saved_modes() == [VirtualTerminalInput.disabled]
	assert foundation.test_last_error_reads() == 1
}

fn test_ensure_changes_mode_without_pushing_and_skips_an_unchanged_mode() {
	mut fixture := reset_console()
	fixture.mode = 0x398
	ensure_input_record_mode() or { panic(err.msg()) }
	assert fixture.mode == 0x198
	assert saved_modes() == []VirtualTerminalInput{}
	ensure_input_record_mode() or { panic(err.msg()) }
	assert fixture.mode_changes == [console.ModeChange{ handle: foundation.Handle(7), mode: 0x198 }]
	assert fixture.mode_queries == [foundation.Handle(7), foundation.Handle(7)]
	assert saved_modes() == []VirtualTerminalInput{}
}

fn test_failed_ensure_preserves_the_existing_saved_mode() {
	mut fixture := reset_console()
	fixture.mode = 0x398
	set_input_record_mode() or { panic(err.msg()) }
	fixture.mode = 0x698
	fixture.set_fails = true
	mut failed := false
	ensure_input_record_mode() or {
		failed = true
		assert err is std_io.Error
		if err is std_io.Error {
			assert err.kind() == .permission_denied
			assert err.code() == 5
		}
	}
	assert failed
	assert fixture.mode == 0x698
	assert saved_modes() == [VirtualTerminalInput.enabled]
	assert fixture.mode_changes == [
		console.ModeChange{ handle: foundation.Handle(7), mode: 0x198 },
		console.ModeChange{ handle: foundation.Handle(7), mode: 0x498 },
	]
}

fn test_restore_empty_stack_does_not_call_any_console_api() {
	fixture := reset_console()
	restore_input_mode() or { panic(err.msg()) }
	assert fixture.std_handle_requests == []u32{}
	assert fixture.mode_queries == []foundation.Handle{}
	assert fixture.mode_changes == []console.ModeChange{}
	assert saved_modes() == []VirtualTerminalInput{}
}

fn test_nested_restores_are_lifo_and_preserve_the_current_unrelated_bits() {
	mut fixture := reset_console()
	fixture.mode = 0x398
	set_input_record_mode() or { panic(err.msg()) }
	set_input_record_mode() or { panic(err.msg()) }
	assert saved_modes() == [VirtualTerminalInput.enabled, VirtualTerminalInput.disabled]
	fixture.mode = 0xffff_ffff
	restore_input_mode() or { panic(err.msg()) }
	assert fixture.mode == 0xffff_fdff
	assert saved_modes() == [VirtualTerminalInput.enabled]
	fixture.mode = 0xa5a5_58a5
	restore_input_mode() or { panic(err.msg()) }
	assert fixture.mode == 0xa5a5_5aa5
	assert saved_modes() == []VirtualTerminalInput{}
	assert fixture.mode_changes == [
		console.ModeChange{ handle: foundation.Handle(7), mode: 0x198 },
		console.ModeChange{ handle: foundation.Handle(7), mode: 0xffff_fdff },
		console.ModeChange{ handle: foundation.Handle(7), mode: 0xa5a5_5aa5 },
	]
}

fn test_restore_unavailable_handles_pop_only_the_latest_saved_mode() {
	for handle in [foundation.invalid_handle_value, foundation.Handle(0)] {
		mut fixture := reset_console()
		fixture.mode = 0x398
		set_input_record_mode() or { panic(err.msg()) }
		set_input_record_mode() or { panic(err.msg()) }
		fixture.handle = handle
		restore_input_mode() or { panic(err.msg()) }
		assert saved_modes() == [VirtualTerminalInput.enabled]
		assert fixture.mode_queries == [foundation.Handle(7), foundation.Handle(7)]
		assert fixture.mode_changes == [console.ModeChange{ handle: foundation.Handle(7), mode: 0x198 }]
		fixture.handle = foundation.Handle(7)
		restore_input_mode() or { panic(err.msg()) }
		assert fixture.mode == 0x398
		assert saved_modes() == []VirtualTerminalInput{}
	}
}

fn test_restore_unavailable_mode_query_pops_without_reading_the_native_error() {
	mut fixture := reset_console()
	fixture.mode = 0x398
	set_input_record_mode() or { panic(err.msg()) }
	fixture.query_fails = true
	restore_input_mode() or { panic(err.msg()) }
	assert saved_modes() == []VirtualTerminalInput{}
	assert fixture.mode == 0x198
	assert fixture.mode_changes == [console.ModeChange{ handle: foundation.Handle(7), mode: 0x198 }]
	assert foundation.test_last_error_reads() == 0
}

fn test_restore_failure_leaves_the_stack_available_for_retry() {
	mut fixture := reset_console()
	fixture.mode = 0x398
	set_input_record_mode() or { panic(err.msg()) }
	fixture.mode = 0x498
	fixture.set_fails = true
	fixture.error_code = 87
	mut failed := false
	restore_input_mode() or {
		failed = true
		assert err is std_io.Error
		if err is std_io.Error {
			assert err.kind() == .invalid_input
			assert err.code() == 87
		}
	}
	assert failed
	assert fixture.mode == 0x498
	assert saved_modes() == [VirtualTerminalInput.enabled]
	fixture.set_fails = false
	fixture.mode = 0x1198
	restore_input_mode() or { panic(err.msg()) }
	assert fixture.mode == 0x1398
	assert saved_modes() == []VirtualTerminalInput{}
	assert fixture.mode_changes == [
		console.ModeChange{ handle: foundation.Handle(7), mode: 0x198 },
		console.ModeChange{ handle: foundation.Handle(7), mode: 0x698 },
		console.ModeChange{ handle: foundation.Handle(7), mode: 0x1398 },
	]
	assert foundation.test_last_error_reads() == 1
}

fn test_restore_already_matching_mode_pops_without_set_console_mode() {
	for original_mode in [u32(0x398), u32(0x198)] {
		mut fixture := reset_console()
		fixture.mode = original_mode
		set_input_record_mode() or { panic(err.msg()) }
		fixture.mode = original_mode
		fixture.mode_changes.clear()
		restore_input_mode() or { panic(err.msg()) }
		assert fixture.mode == original_mode
		assert fixture.mode_changes == []console.ModeChange{}
		assert saved_modes() == []VirtualTerminalInput{}
	}
}

fn test_heap_error_owner_remains_reusable_after_repeated_borrowed_accessors() {
	mut owner := 'heap-owned error message'
	$if ownership ? {
		owner = owner.to_owned()
	}
	owned_error := std_io.Error.from_native(.permission_denied, 5, owner.clone())
	assert owned_error.msg() == 'heap-owned error message (os error 5)'
	assert owned_error.msg() == 'heap-owned error message (os error 5)'
	assert owned_error.kind() == .permission_denied
	assert owned_error.kind() == .permission_denied
	assert owned_error.code() == 5
	assert owner == 'heap-owned error message'
}
