module bel

import crossterm
import os
import strings

pub struct BelBackend {}

pub fn BelBackend.default() BelBackend {
	return BelBackend{}
}

pub fn (mut backend BelBackend) notify(_message &string) ! {
	command := PostNotification{}
	mut output := os.stdout()
	crossterm.execute(mut output, &command)!
}

// Command that emits a BEL desktop notification.
pub struct PostNotification {}

// Rust derives Clone; the unit command has no owned data to duplicate.
pub fn (command &PostNotification) clone() PostNotification {
	return PostNotification{}
}

pub fn (command &PostNotification) write_ansi(mut output strings.Builder) ! {
	output.write_string('\x07')
}

// The shared V Command interface includes Windows methods on every platform.
// Their implementations retain the source's Windows behavior.
pub fn (command &PostNotification) execute_winapi() ! {
	return error('tried to execute PostNotification using WinAPI; use ANSI instead')
}

pub fn (command &PostNotification) is_ansi_code_supported() bool {
	return true
}
