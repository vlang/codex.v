module osc9

import codex_terminal_detection
import crossterm
import os
import strings

pub struct Osc9Backend {
	dcs_passthrough bool
}

pub fn Osc9Backend.default() Osc9Backend {
	return Osc9Backend.new()
}

pub fn Osc9Backend.new() Osc9Backend {
	terminal := codex_terminal_detection.terminal_info()
	return Osc9Backend{
		dcs_passthrough: if multiplexer := terminal.multiplexer {
			multiplexer.kind == .tmux
		} else {
			false
		}
	}
}

pub fn (mut backend Osc9Backend) notify(message &string) ! {
	command := PostNotification{
		message:         message.clone()
		dcs_passthrough: backend.dcs_passthrough
	}
	mut output := os.stdout()
	crossterm.execute(mut output, &command)!
}

// Command that emits an OSC 9 desktop notification with a message.
pub struct PostNotification {
pub:
	message         string
	dcs_passthrough bool
}

// Rust derives Clone; copy the owned message at that explicit boundary.
pub fn (command &PostNotification) clone() PostNotification {
	return PostNotification{
		message:         command.message.clone()
		dcs_passthrough: command.dcs_passthrough
	}
}

pub fn (command &PostNotification) write_ansi(mut output strings.Builder) ! {
	if command.dcs_passthrough {
		escaped_message := escape_tmux_dcs_passthrough_payload(&command.message)
		output.write_string('\x1bPtmux;\x1b\x1b]9;${escaped_message}\a\x1b\\')
	} else {
		output.write_string('\x1b]9;${command.message}\a')
	}
}

// The shared V Command interface includes Windows methods on every platform.
// Their implementations retain the source's Windows behavior.
pub fn (command &PostNotification) execute_winapi() ! {
	return error('tried to execute PostNotification using WinAPI; use ANSI instead')
}

pub fn (command &PostNotification) is_ansi_code_supported() bool {
	return true
}

fn escape_tmux_dcs_passthrough_payload(message &string) string {
	return message.replace('\x1b', '\x1b\x1b')
}
