module event

import std_io
import strings

// STUB: crossterm::event::KeyboardEnhancementFlags stores Copy u8 protocol bits.
pub type KeyboardEnhancementFlags = u8

// STUB: KeyboardEnhancementFlags::DISAMBIGUATE_ESCAPE_CODES.
pub const keyboard_disambiguate_escape_codes = KeyboardEnhancementFlags(1)
// STUB: KeyboardEnhancementFlags::REPORT_EVENT_TYPES.
pub const keyboard_report_event_types = KeyboardEnhancementFlags(2)
// STUB: KeyboardEnhancementFlags::REPORT_ALTERNATE_KEYS.
pub const keyboard_report_alternate_keys = KeyboardEnhancementFlags(4)
// STUB: KeyboardEnhancementFlags::REPORT_ALL_KEYS_AS_ESCAPE_CODES.
pub const keyboard_report_all_keys_as_escape_codes = KeyboardEnhancementFlags(8)

// STUB: crossterm::event::PushKeyboardEnhancementFlags owns Copy flag bits.
pub struct PushKeyboardEnhancementFlags {
pub:
	flags KeyboardEnhancementFlags
}

// STUB: PushKeyboardEnhancementFlags::write_ansi emits the source CSI > bits u.
pub fn (command &PushKeyboardEnhancementFlags) write_ansi(mut output strings.Builder) ! {
	output.write_string('\x1b[>${u8(command.flags)}u')
}

// STUB: PushKeyboardEnhancementFlags::execute_winapi rejects the legacy API.
pub fn (command &PushKeyboardEnhancementFlags) execute_winapi() ! {
	return std_io.Error.new(.unsupported, 'Keyboard progressive enhancement not implemented for the legacy Windows API.')
}

// STUB: PushKeyboardEnhancementFlags::is_ansi_code_supported is false on Windows.
pub fn (command &PushKeyboardEnhancementFlags) is_ansi_code_supported() bool {
	return false
}

// STUB: crossterm::event::PopKeyboardEnhancementFlags pops exactly one stack level.
pub struct PopKeyboardEnhancementFlags {}

// STUB: PopKeyboardEnhancementFlags::write_ansi emits the source CSI <1u.
pub fn (command &PopKeyboardEnhancementFlags) write_ansi(mut output strings.Builder) ! {
	output.write_string('\x1b[<1u')
}

// STUB: PopKeyboardEnhancementFlags::execute_winapi rejects the legacy API.
pub fn (command &PopKeyboardEnhancementFlags) execute_winapi() ! {
	return std_io.Error.new(.unsupported, 'Keyboard progressive enhancement not implemented for the legacy Windows API.')
}

// STUB: PopKeyboardEnhancementFlags::is_ansi_code_supported is false on Windows.
pub fn (command &PopKeyboardEnhancementFlags) is_ansi_code_supported() bool {
	return false
}
