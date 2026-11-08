module keyboard_modes

import codex_terminal_detection
import crossterm
import crossterm.event
import std_io
import strings

fn ansi_for(command crossterm.Command) string {
	mut out := strings.new_builder(32)
	command.write_ansi(mut out) or { panic(err) }
	return out.str()
}

fn test_keyboard_enhancement_suppresses_release_reporting_for_iterm() {
	assert ansi_for(event.PushKeyboardEnhancementFlags{
		flags: keyboard_enhancement_flags(.iterm2, /*running_in_tmux_session*/
			false, /*tmux_extended_keys_format*/
			BorrowedString{})
	}) == '\x1b[>5u'
}

fn test_keyboard_enhancement_suppresses_release_reporting_for_ghostty() {
	assert ansi_for(event.PushKeyboardEnhancementFlags{
		flags: keyboard_enhancement_flags(.ghostty, /*running_in_tmux_session*/
			false, /*tmux_extended_keys_format*/
			BorrowedString{})
	}) == '\x1b[>5u'
}

fn test_keyboard_enhancement_preserves_repeat_reporting_for_kitty() {
	assert ansi_for(event.PushKeyboardEnhancementFlags{
		flags: keyboard_enhancement_flags(.kitty, /*running_in_tmux_session*/
			false, /*tmux_extended_keys_format*/
			BorrowedString{})
	}) == '\x1b[>7u'
}

fn test_keyboard_enhancement_preserves_repeat_reporting_for_csi_u_tmux() {
	csi_u := 'csi-u'
	assert ansi_for(event.PushKeyboardEnhancementFlags{
		flags: keyboard_enhancement_flags(.kitty, /*running_in_tmux_session*/
			true, BorrowedString.some(&csi_u))
	}) == '\x1b[>7u'
}

fn test_keyboard_enhancement_preserves_shift_enter_for_xterm_tmux() {
	xterm := 'xterm'
	assert ansi_for(event.PushKeyboardEnhancementFlags{
		flags: keyboard_enhancement_flags(.kitty, /*running_in_tmux_session*/
			true, BorrowedString.some(&xterm))
	}) == '\x1b[>5u'
}

fn test_keyboard_enhancement_preserves_repeat_reporting_for_unknown_terminals() {
	assert ansi_for(event.PushKeyboardEnhancementFlags{
		flags: keyboard_enhancement_flags(.unknown, /*running_in_tmux_session*/
			false, /*tmux_extended_keys_format*/
			BorrowedString{})
	}) == '\x1b[>7u'
}

fn test_keyboard_enhancement_uses_conservative_flags_when_tmux_format_is_unknown() {
	assert ansi_for(event.PushKeyboardEnhancementFlags{
		flags: keyboard_enhancement_flags(.unknown, /*running_in_tmux_session*/
			true, /*tmux_extended_keys_format*/
			BorrowedString{})
	}) == '\x1b[>5u'
}

fn test_keyboard_enhancement_env_flag_parses_common_values() {
	one := '1'
	true_value := 'true'
	yes := 'YES'
	zero := '0'
	false_value := 'false'
	no := 'NO'
	unexpected := 'unexpected'
	assert parse_bool_env(BorrowedString.some(&one)) == ?bool(true)
	assert parse_bool_env(BorrowedString.some(&true_value)) == ?bool(true)
	assert parse_bool_env(BorrowedString.some(&yes)) == ?bool(true)
	assert parse_bool_env(BorrowedString.some(&zero)) == ?bool(false)
	assert parse_bool_env(BorrowedString.some(&false_value)) == ?bool(false)
	assert parse_bool_env(BorrowedString.some(&no)) == ?bool(false)
	assert parse_bool_env(BorrowedString.some(&unexpected)) == none
	assert parse_bool_env( /*value*/
	BorrowedString{}) == none
}

fn test_keyboard_enhancement_auto_disables_for_vscode_in_wsl() {
	assert keyboard_enhancement_disabled_for( /*disable_env*/
	BorrowedString{}, /*is_wsl*/
		true,
		/*is_vscode_terminal*/
		true)
}

fn test_keyboard_enhancement_auto_disable_requires_wsl_and_vscode() {
	assert !keyboard_enhancement_disabled_for( /*disable_env*/
	BorrowedString{}, /*is_wsl*/
		true,
		/*is_vscode_terminal*/
		false)
	assert !keyboard_enhancement_disabled_for( /*disable_env*/
	BorrowedString{}, /*is_wsl*/
		false,
		/*is_vscode_terminal*/
		true)
}

fn test_keyboard_enhancement_env_flag_overrides_auto_detection() {
	zero := '0'
	one := '1'
	assert !keyboard_enhancement_disabled_for(BorrowedString.some(&zero), /*is_wsl*/
		true,
		/*is_vscode_terminal*/
		true)
	assert keyboard_enhancement_disabled_for(BorrowedString.some(&one), /*is_wsl*/
		false,
		/*is_vscode_terminal*/
		false)
}

fn test_vscode_terminal_detection_uses_linux_and_windows_term_program() {
	vscode := 'vscode'
	windows_terminal := 'WindowsTerminal'
	assert vscode_terminal_detected(BorrowedString.some(&vscode), /*windows_term_program*/
		BorrowedString{})
	assert vscode_terminal_detected( /*linux_term_program*/
	BorrowedString{}, BorrowedString.some(&vscode))
	assert !vscode_terminal_detected( /*linux_term_program*/
	BorrowedString{}, BorrowedString.some(&windows_terminal))
	assert !vscode_terminal_detected( /*linux_term_program*/
	BorrowedString{}, /*windows_term_program*/
		BorrowedString{})
}

fn test_tmux_session_detection_accepts_tmux_or_tmux_pane() {
	tmux := '/tmp/tmux-501/default,1,0'
	pane := '%0'
	assert tmux_session_detected(BorrowedString.some(&tmux), /*tmux_pane*/
		BorrowedString{})
	assert tmux_session_detected( /*tmux*/
	BorrowedString{}, BorrowedString.some(&pane))
	assert !tmux_session_detected( /*tmux*/
	BorrowedString{}, /*tmux_pane*/
		BorrowedString{})
}

fn test_tmux_modify_other_keys_only_requests_confirmed_csi_u_format() {
	csi_u := 'csi-u'
	xterm := 'xterm'
	empty := ''
	assert tmux_should_enable_modify_other_keys_for( /*running_in_tmux_session*/
	true,
		BorrowedString.some(&csi_u))
	assert !tmux_should_enable_modify_other_keys_for( /*running_in_tmux_session*/
	true,
		/*extended_keys_format*/
		BorrowedString{})
	assert !tmux_should_enable_modify_other_keys_for( /*running_in_tmux_session*/
	true,
		BorrowedString.some(&xterm))
	assert !tmux_should_enable_modify_other_keys_for( /*running_in_tmux_session*/
	true,
		BorrowedString.some(&empty))
	assert !tmux_should_enable_modify_other_keys_for( /*running_in_tmux_session*/
	false,
		BorrowedString.some(&csi_u))
}

fn test_reset_keyboard_enhancement_flags_clears_all_pushed_levels() {
	assert ansi_for(ResetKeyboardEnhancementFlags{}) == '\x1b[<u'
}

fn test_enable_modify_other_keys_requests_xterm_keyboard_reporting() {
	assert ansi_for(EnableModifyOtherKeys{}) == '\x1b[>4;2m'
}

fn test_disable_modify_other_keys_resets_xterm_keyboard_reporting() {
	assert ansi_for(DisableModifyOtherKeys{}) == '\x1b[>4;0m'
}

fn test_borrowed_helpers_reuse_heap_string_owners() {
	mut bool_text := '\u2003YeS\u3000'
	mut vscode_text := 'VsCoDe'
	mut format_text := 'csi-u'
	mut tmux_text := ''
	$if ownership ? {
		bool_text = bool_text.to_owned()
		vscode_text = vscode_text.to_owned()
		format_text = format_text.to_owned()
		tmux_text = tmux_text.to_owned()
	}
	bool_value := BorrowedString.some(&bool_text)
	vscode_value := BorrowedString.some(&vscode_text)
	format_value := BorrowedString.some(&format_text)
	tmux_value := BorrowedString.some(&tmux_text)
	for _ in 0 .. 2 {
		assert parse_bool_env(bool_value) == ?bool(true)
		assert keyboard_enhancement_disabled_for(bool_value, false, false)
		assert term_program_is_vscode(vscode_value)
		assert vscode_terminal_detected(BorrowedString{}, vscode_value)
		assert tmux_session_detected(tmux_value, BorrowedString{})
		assert tmux_should_enable_modify_other_keys_for(true, format_value)
		assert keyboard_enhancement_flags(codex_terminal_detection.TerminalName.kitty,
			true, format_value) == event.KeyboardEnhancementFlags(7)
	}
	assert bool_text == '\u2003YeS\u3000'
	assert vscode_text == 'VsCoDe'
	assert format_text == 'csi-u'
	assert tmux_text == ''
	mut owner_text := 'vscode'
	$if ownership ? {
		owner_text = owner_text.to_owned()
	}
	owner := EnvironmentValue.from_option(owner_text)
	assert term_program_is_vscode(owner.as_deref())
	assert term_program_is_vscode(owner.as_deref())
	assert owner.value == 'vscode'
}

fn test_windows_stdout_parser_preserves_first_match_and_lossy_utf8() {
	mut output := 'ignored=other\r\nTERM_PROGRAM=vscode\r\nTERM_PROGRAM=second\r\n'
	$if ownership ? {
		output = output.to_owned()
	}
	assert windows_term_program_from_stdout(&output) == ?string('vscode')
	assert windows_term_program_from_stdout(&output) == ?string('vscode')
	assert output == 'ignored=other\r\nTERM_PROGRAM=vscode\r\nTERM_PROGRAM=second\r\n'
	empty_first := 'TERM_PROGRAM= \u2003\r\nTERM_PROGRAM=vscode\r\n'
	assert windows_term_program_from_stdout(&empty_first) == none
	case_sensitive := 'term_program=vscode\r\n'
	assert windows_term_program_from_stdout(&case_sensitive) == none
	bare_cr := 'TERM_PROGRAM=vs\rcode\n'
	assert windows_term_program_from_stdout(&bare_cr) == ?string('vs\rcode')
	invalid := [u8(`T`), `E`, `R`, `M`, `_`, `P`, `R`, `O`, `G`, `R`, `A`, `M`, `=`, 0xe2, 0x82].bytestr()
	assert windows_term_program_from_stdout(&invalid) == ?string('\ufffd')
	assert invalid.bytes().last() == u8(0x82)
}

fn test_windows_command_methods_retain_unsupported_errors() {
	commands := [crossterm.Command(ResetKeyboardEnhancementFlags{}),
		crossterm.Command(EnableModifyOtherKeys{}), crossterm.Command(DisableModifyOtherKeys{})]
	expected := [
		'keyboard enhancement reset is not implemented for the legacy Windows API',
		'modifyOtherKeys enable is not implemented for the legacy Windows API',
		'modifyOtherKeys reset is not implemented for the legacy Windows API',
	]
	for index in 0 .. commands.len {
		command := &commands[index]
		assert !command.is_ansi_code_supported()
		command.execute_winapi() or {
			assert err is std_io.Error
			if err is std_io.Error {
				assert err.kind() == .unsupported
			}
			assert err.msg() == expected[index]
			continue
		}
		assert false, 'legacy WinAPI unexpectedly succeeded'
	}
}
