module terminal_title

import os
import strings

fn test_sanitizes_terminal_title() {
	input := '  Project\t|\nWorking\x1b\x07\u009D\u009C |  Thread  '
	sanitized := sanitize_terminal_title(&input)
	assert sanitized == 'Project | Working | Thread'
}

fn test_strips_invisible_format_chars_from_terminal_title() {
	input := 'Pro\u202Ej\u2066e\u200Fc\u061Ct\u200B \uFEFFT\u2060itle'
	sanitized := sanitize_terminal_title(&input)
	assert sanitized == 'Project Title'
}

fn test_truncates_terminal_title() {
	input := 'a'.repeat(max_terminal_title_chars + 10)
	sanitized := sanitize_terminal_title(&input)
	assert sanitized.len == max_terminal_title_chars
}

fn test_truncation_prefers_visible_char_over_pending_space() {
	input := '${'a'.repeat(max_terminal_title_chars - 1)} b'
	sanitized := sanitize_terminal_title(&input)
	assert sanitized.len == max_terminal_title_chars
	assert sanitized.runes().last() == `b`
}

fn test_writes_osc_title_with_bel_terminator() {
	mut output := strings.new_builder(32)
	command := SetWindowTitle{ title: 'hello'.clone() }
	command.write_ansi(mut output) or { panic('encode terminal title: ${err}') }
	assert output.str() == '\x1b]0;hello\x07'
}

fn test_unicode_title_limit_counts_scalars() {
	input := '${'界'.repeat(max_terminal_title_chars - 1)} 🐈 trailing'
	sanitized := sanitize_terminal_title(&input)
	assert sanitized.runes().len == max_terminal_title_chars
	assert sanitized.runes().last() == `🐈`
	whitespace := '\u00a0one\u2003\u3000two\u202f'
	invisible := '\x1b\x07\u202e\u200b'
	assert sanitize_terminal_title(&whitespace) == 'one two'
	assert sanitize_terminal_title(&invisible) == ''
}

fn test_borrowed_title_and_command_preserve_owners() {
	mut input := '  Project\t|\nWorking  '
	mut payload := 'hello'
	$if ownership ? {
		input = input.to_owned()
		payload = payload.to_owned()
	}
	assert sanitize_terminal_title(&input) == 'Project | Working'
	assert sanitize_terminal_title(&input) == 'Project | Working'
	assert input == '  Project\t|\nWorking  '
	command := SetWindowTitle{ title: payload }
	mut first := strings.new_builder(32)
	command.write_ansi(mut first) or { panic(err) }
	mut second := strings.new_builder(32)
	command.write_ansi(mut second) or { panic(err) }
	assert first.str() == '\x1b]0;hello\x07'
	assert second.str() == '\x1b]0;hello\x07'
	assert command.title == 'hello'
	cloned := command.clone()
	mut cloned_output := strings.new_builder(32)
	cloned.write_ansi(mut cloned_output) or { panic(err) }
	assert cloned_output.str() == '\x1b]0;hello\x07'
	assert command.title == 'hello'
	// Tests run with captured stdout; preserve the source's early return before
	// sanitization when output is redirected, including for an empty title.
	if os.is_atty(1) == 0 {
		assert set_terminal_title(&input) or { panic(err) } == .applied
		empty := ''
		assert set_terminal_title(&empty) or { panic(err) } == .applied
		clear_terminal_title() or { panic(err) }
	}
	assert input == '  Project\t|\nWorking  '
}
