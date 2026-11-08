module input_boundary

import codex_tui.tui
import crossterm.event
import std_io
import std_time
import time

enum Action {
	discard
	clock
	poll
	read
	readable
}

struct FixtureFailure {
	failed  bool
	kind    std_io.ErrorKind
	message string
}

fn (failure &FixtureFailure) check() ! {
	if failure.failed {
		return std_io.Error.new(failure.kind, failure.message.clone())
	}
}

struct PollStep {
	value bool
	error FixtureFailure
}

struct DiscardStep {
	value event.InputDiscardStatus
	error FixtureFailure
}

struct ReadableStep {
	value bool
	error FixtureFailure
}

struct ReadStep {
	text  string
	error FixtureFailure
}

struct ScriptedInput {
	base      std_time.Instant = std_time.Instant.now()
	times     []std_time.Duration
	polls     []PollStep
	discards  []DiscardStep
	reads     []ReadStep
	readables []ReadableStep
mut:
	clock_index    int
	poll_index     int
	discard_index  int
	read_index     int
	readable_index int
	actions        []Action
	timeouts       []std_time.Duration
}

fn (mut input ScriptedInput) now() std_time.Instant {
	input.actions << .clock
	assert input.clock_index < input.times.len
	value := input.times[input.clock_index]
	input.clock_index++
	return input.base.add(value)
}

fn (mut input ScriptedInput) discard_buffered_input() !event.InputDiscardStatus {
	input.actions << .discard
	assert input.discard_index < input.discards.len
	step := &input.discards[input.discard_index]
	input.discard_index++
	step.error.check()!
	return match step.value {
		.complete { event.InputDiscardStatus.complete }
		.bracketed_paste_in_progress { event.InputDiscardStatus.bracketed_paste_in_progress }
		.control_sequence_in_progress { event.InputDiscardStatus.control_sequence_in_progress }
	}
}

fn (mut input ScriptedInput) poll(timeout std_time.Duration) !bool {
	input.actions << .poll
	input.timeouts << timeout
	assert input.poll_index < input.polls.len
	step := &input.polls[input.poll_index]
	input.poll_index++
	step.error.check()!
	return step.value == true
}

fn (mut input ScriptedInput) read() !event.Event {
	input.actions << .read
	assert input.read_index < input.reads.len
	step := &input.reads[input.read_index]
	input.read_index++
	step.error.check()!
	return event.Event{ kind: .paste, paste: step.text.clone() }
}

fn (mut input ScriptedInput) terminal_input_is_readable() !bool {
	input.actions << .readable
	assert input.readable_index < input.readables.len
	step := &input.readables[input.readable_index]
	input.readable_index++
	step.error.check()!
	return step.value == true
}

fn execute_script(mut script ScriptedInput) ! {
	mut input := BoundaryInput(&script)
	discard_pending_terminal_input_with(mut input)!
}

fn source_actions(unix_actions []Action, windows_actions []Action) []Action {
	$if unix && !plan9 {
		return unix_actions
	} $else $if windows {
		return windows_actions
	} $else {
		return windows_actions.filter(it != .readable)
	}
}

fn test_decoded_event_is_read_before_deciding_the_boundary_is_clear() {
	mut owner := 'buffered paste'
	$if ownership ? {
		owner = owner.to_owned()
	}
	mut script := ScriptedInput{
		times:     [std_time.duration_zero, std_time.duration_zero, std_time.Duration.from_millis(2)]
		polls:     [PollStep{ value: true }, PollStep{}]
		discards:  [DiscardStep{}, DiscardStep{}]
		reads:     [ReadStep{ text: owner.clone() }]
		readables: [ReadableStep{}]
	}
	execute_script(mut script) or { panic(err) }
	assert script.actions == source_actions([.discard, .clock, .clock, .poll, .read, .clock, .poll,
		.discard, .readable], [.clock, .clock, .poll, .read, .clock, .poll, .readable])
	assert script.timeouts == [std_time.Duration.from_millis(10), std_time.Duration.from_millis(10)]
	assert owner == 'buffered paste'
}

fn test_unread_native_bytes_trigger_another_decoding_pass() {
	$if plan9 {
		return
	}
	mut script := ScriptedInput{
		times:     [std_time.duration_zero, std_time.duration_zero, std_time.Duration.from_millis(10)]
		polls:     [PollStep{}, PollStep{}]
		discards:  [DiscardStep{}, DiscardStep{}, DiscardStep{}]
		readables: [ReadableStep{ value: true }, ReadableStep{}]
	}
	execute_script(mut script) or { panic(err) }
	assert script.actions == source_actions([.discard, .clock, .clock, .poll, .discard, .readable,
		.clock, .poll, .discard, .readable], [.clock, .clock, .poll, .readable, .clock, .poll,
		.readable])
}

fn test_incomplete_control_sequences_and_bracketed_pastes_stay_quarantined() {
	$if unix && !plan9 {
		for status in [event.InputDiscardStatus.control_sequence_in_progress,
			event.InputDiscardStatus.bracketed_paste_in_progress] {
			mut script := ScriptedInput{
				times:     [std_time.duration_zero, std_time.duration_zero,
					std_time.Duration.from_millis(10)]
				polls:     [PollStep{}, PollStep{}]
				discards:  [DiscardStep{ value: status }, DiscardStep{ value: status }, DiscardStep{}]
				readables: [ReadableStep{}]
			}
			execute_script(mut script) or { panic(err) }
			assert script.actions == [.discard, .clock, .clock, .poll, .discard, .clock, .poll,
				.discard, .readable]
		}
	}
}

fn test_poll_is_clamped_to_the_remaining_one_millisecond() {
	mut script := ScriptedInput{
		times:     [std_time.duration_zero, std_time.Duration.from_millis(999)]
		polls:     [PollStep{}]
		discards:  [DiscardStep{}, DiscardStep{}]
		readables: [ReadableStep{}]
	}
	execute_script(mut script) or { panic(err) }
	assert script.timeouts == [std_time.Duration.from_millis(1)]
}

fn test_expired_boundary_does_not_poll_or_read_after_the_deadline() {
	mut script := ScriptedInput{
		times:    [std_time.duration_zero, std_time.Duration.from_secs(1)]
		discards: [DiscardStep{}]
	}
	execute_script(mut script) or {
		assert err is std_io.Error
		if err is std_io.Error {
			assert err.kind() == .timed_out
			assert err.msg() == 'timed out discarding buffered terminal input'
		}
		assert script.actions == source_actions([.discard, .clock, .clock], [.clock, .clock])
		return
	}
	assert false
}

fn test_clock_past_deadline_saturates_to_timeout() {
	mut script := ScriptedInput{
		times:    [std_time.duration_zero, std_time.Duration.from_secs(2)]
		discards: [DiscardStep{}]
	}
	execute_script(mut script) or {
		assert err is std_io.Error
		if err is std_io.Error {
			assert err.kind() == .timed_out
		}
		assert script.poll_index == 0
		return
	}
	assert false
}

fn test_native_interrupted_error_retries_without_losing_the_boundary() {
	$if plan9 {
		return
	}
	mut script := ScriptedInput{
		times:     [std_time.duration_zero, std_time.duration_zero, std_time.Duration.from_millis(10)]
		polls:     [PollStep{}, PollStep{}]
		discards:  [DiscardStep{}, DiscardStep{}, DiscardStep{}]
		readables: [
			ReadableStep{ error: FixtureFailure{ failed: true, kind: .interrupted, message: 'interrupted' } },
			ReadableStep{},
		]
	}
	execute_script(mut script) or { panic(err) }
	assert script.readable_index == 2
	assert script.poll_index == 2
}

fn failure_at(point int, expected int, message &string) FixtureFailure {
	if point == expected {
		return FixtureFailure{ failed: true, kind: .permission_denied, message: message.clone() }
	}
	return FixtureFailure{}
}

fn test_each_error_boundary_propagates_the_original_owned_message() {
	mut owner := 'input error with dynamic storage'
	$if ownership ? {
		owner = owner.to_owned()
	}
	for point in 0 .. 5 {
		$if windows || plan9 {
			if point == 0 || point == 3 {
				continue
			}
		}
		$if plan9 {
			if point == 4 {
				continue
			}
		}
		mut script := ScriptedInput{
			times:     [std_time.duration_zero, std_time.duration_zero]
			polls:     [PollStep{ value: point == 2, error: failure_at(point, 1, &owner) }]
			reads:     [ReadStep{ error: failure_at(point, 2, &owner) }]
			discards:  [
				DiscardStep{ error: failure_at(point, 0, &owner) },
				DiscardStep{ error: failure_at(point, 3, &owner) },
			]
			readables: [ReadableStep{ error: failure_at(point, 4, &owner) }]
		}
		execute_script(mut script) or {
			assert err.msg() == owner
			assert err is std_io.Error
			if err is std_io.Error {
				assert err.kind() == .permission_denied
			}
			continue
		}
		assert false
	}
	assert owner == 'input error with dynamic storage'
}

// A real monotonic clock and real sleeps verify the one-second deadline independently of the
// deterministic policy cases, without touching a terminal or changing process input modes.
struct SleepingIncompleteInput {
mut:
	polls int
}

fn (mut input SleepingIncompleteInput) now() std_time.Instant {
	return std_time.Instant.now()
}

fn (mut input SleepingIncompleteInput) discard_buffered_input() !event.InputDiscardStatus {
	return .control_sequence_in_progress
}

fn (mut input SleepingIncompleteInput) poll(timeout std_time.Duration) !bool {
	input.polls++
	time.sleep(time.Duration(timeout.as_nanos().lo))
	return false
}

fn (mut input SleepingIncompleteInput) read() !event.Event {
	panic('incomplete input must not produce an event')
}

fn (mut input SleepingIncompleteInput) terminal_input_is_readable() !bool {
	return true
}

fn test_actual_elapsed_timeout_is_at_least_one_second() {
	$if plan9 {
		return
	}
	mut fixture := SleepingIncompleteInput{}
	mut input := BoundaryInput(&fixture)
	start := std_time.Instant.now()
	discard_pending_terminal_input_with(mut input) or {
		assert err is std_io.Error
		if err is std_io.Error {
			assert err.kind() == .timed_out
		}
		assert start.elapsed() >= std_time.Duration.from_secs(1)
		assert fixture.polls > 0
		return
	}
	assert false
}

fn initialization_scope(disarm bool, fail bool) ! {
	mut guard := TerminalInitializationGuard{ active: true }
	defer {
		// Normal builds need explicit cleanup. Disarm after the source-shaped Drop call so
		// automatic ownership cleanup has no second effect, independent of custom defines.
		guard.drop()
		guard.active = false
	}
	if disarm {
		guard.active = false
	}
	if fail {
		return error('initialization failed')
	}
}

fn automatic_initialization_scope(disarm bool, fail bool) ! {
	mut guard := TerminalInitializationGuard{ active: true }
	if disarm {
		guard.active = false
	}
	if fail {
		return error('initialization failed')
	}
}

fn test_ownership_guard_restores_automatically_without_manual_cleanup() {
	// The explicit custom define enables this ownership-only proof. Plain -ownership still
	// validates the general guard cases above; normal builds do not insert automatic Drop.
	$if ownership ? {
		tui.install_input_boundary_restore_fixture('')
		defer { tui.clear_input_boundary_restore_fixture() }
		automatic_initialization_scope(false, false) or { panic(err) }
		assert tui.input_boundary_restore_fixture_calls() == 1
		automatic_initialization_scope(true, false) or { panic(err) }
		assert tui.input_boundary_restore_fixture_calls() == 1
		automatic_initialization_scope(false, true) or {
			assert err.msg() == 'initialization failed'
			assert tui.input_boundary_restore_fixture_calls() == 2
			return
		}
		assert false
	}
}

fn test_active_guard_restores_on_initialization_error() {
	tui.install_input_boundary_restore_fixture('')
	defer { tui.clear_input_boundary_restore_fixture() }
	initialization_scope(false, true) or {
		assert err.msg() == 'initialization failed'
		assert tui.input_boundary_restore_fixture_calls() == 1
		return
	}
	assert false
}

fn test_active_guard_restores_when_the_scope_ends() {
	tui.install_input_boundary_restore_fixture('')
	defer { tui.clear_input_boundary_restore_fixture() }
	initialization_scope(false, false) or { panic(err) }
	assert tui.input_boundary_restore_fixture_calls() == 1
}

fn test_disarmed_guard_transfers_ownership_without_restoring() {
	tui.install_input_boundary_restore_fixture('')
	defer { tui.clear_input_boundary_restore_fixture() }
	initialization_scope(true, false) or { panic(err) }
	assert tui.input_boundary_restore_fixture_calls() == 0
}

fn test_guard_ignores_restoration_errors() {
	mut owner := 'restoration failed'
	$if ownership ? {
		owner = owner.to_owned()
	}
	tui.install_input_boundary_restore_fixture(owner.clone())
	defer { tui.clear_input_boundary_restore_fixture() }
	initialization_scope(false, false) or { panic(err) }
	assert tui.input_boundary_restore_fixture_calls() == 1
	assert owner == 'restoration failed'
}

fn test_untranslated_decoder_fails_explicitly_before_native_reads() {
	discard_pending_terminal_input() or {
		assert err is std_io.Error
		if err is std_io.Error {
			assert err.kind() == .unsupported
		}
		return
	}
	assert false
}

// POSIX pipe writes C int elements. V's int is 64-bit in this compiler.
fn C.pipe(&i32) int
fn C.close(int) int
fn C.write(int, voidptr, usize) isize
fn C.read(int, voidptr, usize) isize
fn C.fcntl(int, int, ...int) int

fn test_native_poll_observes_pipe_bytes_without_consuming_or_changing_flags() {
	$if unix && !plan9 {
		mut descriptors := [2]i32{}
		assert C.pipe(&descriptors[0]) == 0
		defer {
			C.close(descriptors[0])
			C.close(descriptors[1])
		}
		flags := C.fcntl(descriptors[0], C.F_GETFL)
		assert !native_readability_result(C.codex_input_boundary_poll_descriptor(descriptors[0]))!
		byte := u8(`x`)
		assert C.write(descriptors[1], &byte, 1) == 1
		assert native_readability_result(C.codex_input_boundary_poll_descriptor(descriptors[0]))!
		assert C.fcntl(descriptors[0], C.F_GETFL) == flags
		mut observed := u8(0)
		assert C.read(descriptors[0], &observed, 1) == 1
		assert observed == byte
		assert !native_readability_result(C.codex_input_boundary_poll_descriptor(descriptors[0]))!
	}
}

fn assert_poll_error(reading C.CodexInputBoundaryReading, expected_flags u16) {
	assert reading.events & expected_flags != 0
	native_readability_result(reading) or {
		assert err is std_io.Error
		if err is std_io.Error {
			assert err.kind() == .other
		}
		assert err.msg() == 'terminal input poll failed with events 0x${reading.events:x}'
		return
	}
	assert false
}

fn test_native_poll_rejects_hangup_even_when_unread_bytes_remain() {
	$if unix && !plan9 {
		mut descriptors := [2]i32{}
		assert C.pipe(&descriptors[0]) == 0
		defer { C.close(descriptors[0]) }
		byte := u8(`x`)
		assert C.write(descriptors[1], &byte, 1) == 1
		assert C.close(descriptors[1]) == 0
		reading := C.codex_input_boundary_poll_descriptor(descriptors[0])
		assert reading.events & u16(C.POLLIN) != 0
		assert_poll_error(reading, u16(C.POLLHUP))
	}
}

fn test_native_poll_rejects_invalid_descriptor() {
	$if unix && !plan9 {
		mut descriptors := [2]i32{}
		assert C.pipe(&descriptors[0]) == 0
		assert C.close(descriptors[0]) == 0
		defer { C.close(descriptors[1]) }
		assert_poll_error(C.codex_input_boundary_poll_descriptor(descriptors[0]), u16(C.POLLNVAL))
	}
}

fn test_native_poll_rejects_pipe_error() {
	// Linux reports POLLERR for this pipe end. macOS reports no event when only POLLIN
	// was requested; the platform-independent event-classification case below covers it.
	$if linux {
		mut descriptors := [2]i32{}
		assert C.pipe(&descriptors[0]) == 0
		assert C.close(descriptors[0]) == 0
		defer { C.close(descriptors[1]) }
		assert_poll_error(C.codex_input_boundary_poll_descriptor(descriptors[1]), u16(C.POLLERR))
	}
}

fn test_native_poll_errors_override_readable_input_for_every_error_flag() {
	$if unix && !plan9 {
		for flag in [u16(C.POLLERR), u16(C.POLLHUP), u16(C.POLLNVAL)] {
			assert_poll_error(C.codex_input_boundary_read_poll_events(1, u16(C.POLLIN) | flag), flag)
		}
	}
}

fn test_unavailable_windows_handle_keeps_the_exact_error_message() {
	native_readability_result(C.CodexInputBoundaryReading{ error_type: 2 }) or {
		assert err.msg() == 'terminal input handle is unavailable'
		assert err is std_io.Error
		if err is std_io.Error {
			assert err.kind() == .other
		}
		return
	}
	assert false
}

fn test_io_error_message_access_borrows_the_owner() {
	mut owner := 'dynamic IO error'
	$if ownership ? {
		owner = owner.to_owned()
	}
	err := std_io.Error.new(.interrupted, owner.clone())
	assert err.msg() == owner
	assert err.msg() == owner
	assert err.kind() == .interrupted
	assert err.code() == 0
	assert owner == 'dynamic IO error'
}

fn formatted_native_error(message &string) string {
	err := std_io.Error.from_native(.permission_denied, 13, message.clone())
	return err.msg()
}

fn test_native_error_display_retains_code_and_owner_after_repeated_borrows() {
	mut owner := 'dynamic native IO error'
	$if ownership ? {
		owner = owner.to_owned()
	}
	err := std_io.Error.from_native(.permission_denied, 13, owner.clone())
	formatted := err.msg()
	assert formatted == 'dynamic native IO error (os error 13)'
	assert err.msg() == formatted
	assert err.kind() == .permission_denied
	assert err.code() == 13
	assert formatted_native_error(&owner) == formatted
	assert owner == 'dynamic native IO error'
	assert formatted == 'dynamic native IO error (os error 13)'
}

fn test_native_zero_code_is_distinct_from_a_custom_error() {
	native_error := std_io.Error.from_native(.other, 0, 'native success message')
	custom_error := std_io.Error.new(.other, 'native success message')
	assert native_error.msg() == 'native success message (os error 0)'
	assert custom_error.msg() == 'native success message'
	assert native_error.code() == 0
	assert custom_error.code() == 0
}

fn test_native_high_bit_os_error_retains_rust_signed_i32_code() {
	native_readability_result(C.CodexInputBoundaryReading{ error_type: 3, error_code: u32(0x80000000) }) or {
		assert err is std_io.Error
		if err is std_io.Error {
			assert err.code() == -2147483648
			assert err.kind() == .other
		}
		assert err.msg() == ' (os error -2147483648)'
		assert err.msg() == ' (os error -2147483648)'
		return
	}
	assert false
}

fn test_new_native_descriptor_is_read_only_and_close_on_exec_without_changing_stdin() {
	$if unix && !plan9 {
		stdin_flags := C.fcntl(0, C.F_GETFL)
		stdin_descriptor_flags := C.fcntl(0, C.F_GETFD)
		descriptor := C.codex_input_boundary_open_readonly(c'/dev/null')
		assert descriptor >= 0
		defer { C.close(descriptor) }
		assert C.fcntl(descriptor, C.F_GETFL) & int(C.O_ACCMODE) == int(C.O_RDONLY)
		assert C.fcntl(descriptor, C.F_GETFD) & int(C.FD_CLOEXEC) != 0
		assert C.fcntl(0, C.F_GETFL) == stdin_flags
		assert C.fcntl(0, C.F_GETFD) == stdin_descriptor_flags
	}
}

fn test_native_open_error_preserves_kind_code_and_owned_display() {
	$if unix && !plan9 {
		assert C.codex_input_boundary_open_readonly(c'/dev/codex-input-boundary-does-not-exist') == -1
		reading := C.codex_input_boundary_last_os_error()
		assert reading.error_code == u32(C.ENOENT)
		native_readability_result(reading) or {
			assert err is std_io.Error
			if err is std_io.Error {
				assert err.kind() == .not_found
				assert err.code() == int(C.ENOENT)
			}
			message := err.msg()
			assert message.ends_with(' (os error ${reading.error_code})')
			assert err.msg() == message
			assert message.len > ' (os error ${reading.error_code})'.len
			return
		}
		assert false
	}
}
