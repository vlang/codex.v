module keys

import crossterm.event
import codex_tui.key_hint

// Fixed shortcuts used before users have had a chance to configure Codex.

// V currently drops definitions for constructor calls nested in fixed-array constant
// literals. These helpers keep those constructors reachable through function bodies.
pub const move_up = [key_hint.plain(event.key_code_up), plain_character(`k`)]!

pub const move_down = [key_hint.plain(event.key_code_down), plain_character(`j`)]!

pub const select_first = [plain_character(`1`), plain_character(`y`)]!

pub const select_second = [plain_character(`2`), plain_character(`n`)]!

pub const select_third = [plain_character(`3`)]!

pub const select_fourth = [plain_character(`4`)]!

pub const confirm = [key_hint.plain(event.key_code_enter)]!

pub const cancel = [key_hint.plain(event.key_code_esc)]!

pub const quit = [plain_character(`q`), control_character(`c`), control_character(`d`)]!

pub const toggle_animation = [control_character(`.`), control_shift_character(`.`)]!

fn plain_character(ch rune) key_hint.KeyBinding {
	return key_hint.plain(event.KeyCode.char_key(ch))
}

fn control_character(ch rune) key_hint.KeyBinding {
	return key_hint.ctrl(event.KeyCode.char_key(ch))
}

fn control_shift_character(ch rune) key_hint.KeyBinding {
	return key_hint.KeyBinding.new(event.KeyCode.char_key(ch), event.key_modifiers_control.union(event.key_modifiers_shift))
}
