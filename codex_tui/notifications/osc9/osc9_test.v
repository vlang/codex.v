module osc9

import crossterm
import strings

fn test_post_notification_writes_plain_osc9_sequence() {
	mut ansi := strings.new_builder(0)
	command := PostNotification{
		message:         'hello'.clone()
		dcs_passthrough: false
	}

	command.write_ansi(mut ansi) or { panic('OSC 9 command should format: ${err}') }

	assert ansi.str() == '\x1b]9;hello\x07'
}

fn test_post_notification_writes_tmux_dcs_wrapped_osc9_sequence() {
	mut ansi := strings.new_builder(0)
	command := PostNotification{
		message:         'done'.clone()
		dcs_passthrough: true
	}

	command.write_ansi(mut ansi) or { panic('OSC 9 command should format: ${err}') }

	assert ansi.str() == '\x1bPtmux;\x1b\x1b]9;done\x07\x1b\\'
}

fn test_post_notification_escapes_escape_bytes_inside_tmux_payload() {
	mut ansi := strings.new_builder(0)
	command := PostNotification{
		message:         'danger\x1b[31m'.clone()
		dcs_passthrough: true
	}

	command.write_ansi(mut ansi) or { panic('OSC 9 command should format: ${err}') }

	assert ansi.str() == '\x1bPtmux;\x1b\x1b]9;danger\x1b\x1b[31m\x07\x1b\\'
}

fn test_borrowed_tmux_payload_and_command_preserve_owners() {
	mut message := 'danger\x1b[31m'
	$if ownership ? {
		message = message.to_owned()
	}
	assert escape_tmux_dcs_passthrough_payload(&message) == 'danger\x1b\x1b[31m'
	assert escape_tmux_dcs_passthrough_payload(&message) == 'danger\x1b\x1b[31m'
	assert message == 'danger\x1b[31m'
	command := PostNotification{
		message:         message
		dcs_passthrough: true
	}
	mut first := strings.new_builder(0)
	command.write_ansi(mut first) or { panic(err) }
	mut second := strings.new_builder(0)
	command.write_ansi(mut second) or { panic(err) }
	assert first.str() == '\x1bPtmux;\x1b\x1b]9;danger\x1b\x1b[31m\x07\x1b\\'
	assert second.str() == '\x1bPtmux;\x1b\x1b]9;danger\x1b\x1b[31m\x07\x1b\\'
	assert command.message == 'danger\x1b[31m'
	cloned := command.clone()
	mut cloned_output := strings.new_builder(0)
	cloned.write_ansi(mut cloned_output) or { panic(err) }
	assert cloned_output.str() == '\x1bPtmux;\x1b\x1b]9;danger\x1b\x1b[31m\x07\x1b\\'
	assert command.message == 'danger\x1b[31m'
	assert command.dcs_passthrough
}

fn test_command_interface_preserves_borrowed_owner_and_windows_behavior() {
	mut interface_payload := 'hello'
	$if ownership ? {
		interface_payload = interface_payload.to_owned()
	}
	command := PostNotification{
		message:         interface_payload
		dcs_passthrough: false
	}
	borrowed := crossterm.Command(&command)
	mut first := strings.new_builder(0)
	borrowed.write_ansi(mut first) or { panic(err) }
	mut second := strings.new_builder(0)
	borrowed.write_ansi(mut second) or { panic(err) }
	assert first.str() == '\x1b]9;hello\x07'
	assert second.str() == '\x1b]9;hello\x07'
	assert borrowed.is_ansi_code_supported()
	mut failed := false
	borrowed.execute_winapi() or {
		assert err.msg() == 'tried to execute PostNotification using WinAPI; use ANSI instead'
		failed = true
	}
	assert failed
	assert command.message == 'hello'
}
