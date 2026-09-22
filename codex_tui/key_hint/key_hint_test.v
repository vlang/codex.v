module key_hint

import crossterm.event

struct C0Case {
	ctrl_char rune
	c0_char   rune
}

fn test_is_press_accepts_press_and_repeat_but_rejects_release() {
	binding := ctrl(event.KeyCode.char_key(`k`))
	press := event.KeyEvent.new(event.KeyCode.char_key(`k`), event.key_modifiers_control)
	repeat := event.KeyEvent{
		...press
		kind: .repeat
	}
	release := event.KeyEvent{
		...press
		kind: .release
	}
	wrong_modifiers := event.KeyEvent.new(event.KeyCode.char_key(`k`), event.key_modifiers_none)

	assert binding.is_press(press)
	assert binding.is_press(repeat)
	assert !binding.is_press(release)
	assert !binding.is_press(wrong_modifiers)
}

fn test_keybinding_list_ext_matches_any_binding() {
	bindings := [plain(event.KeyCode.char_key(`a`)), ctrl(event.KeyCode.char_key(`b`))]

	assert bindings_are_pressed(&bindings, event.KeyEvent.new(event.KeyCode.char_key(`a`),
		event.key_modifiers_none))
	assert bindings_are_pressed(&bindings, event.KeyEvent.new(event.KeyCode.char_key(`b`),
		event.key_modifiers_control))
	assert !bindings_are_pressed(&bindings, event.KeyEvent.new(event.KeyCode.char_key(`c`),
		event.key_modifiers_none))
}

fn test_shifted_letter_binding_matches_uppercase_char_events() {
	binding := shift(event.KeyCode.char_key(`a`))

	assert binding.is_press(event.KeyEvent.new(event.KeyCode.char_key(`a`), event.key_modifiers_shift))
	assert binding.is_press(event.KeyEvent.new(event.KeyCode.char_key(`A`), event.key_modifiers_none))
	assert binding.is_press(event.KeyEvent.new(event.KeyCode.char_key(`A`), event.key_modifiers_shift))
}

fn test_shift_letter_binding_preserves_other_modifiers_with_uppercase_compat() {
	binding := KeyBinding.new(event.KeyCode.char_key(`i`), event.key_modifiers_control.union(event.key_modifiers_shift))

	assert binding.is_press(event.KeyEvent.new(event.KeyCode.char_key(`I`), event.key_modifiers_control))
}

fn test_shift_letter_binding_does_not_match_plain_lowercase_or_other_uppercase() {
	binding := shift(event.KeyCode.char_key(`o`))

	assert !binding.is_press(event.KeyEvent.new(event.KeyCode.char_key(`o`), event.key_modifiers_none))
	assert !binding.is_press(event.KeyEvent.new(event.KeyCode.char_key(`P`), event.key_modifiers_none))
}

fn test_ctrl_letter_binding_matches_c0_control_char_events() {
	binding := ctrl(event.KeyCode.char_key(`p`))

	assert binding.is_press(event.KeyEvent.new(event.KeyCode.char_key(rune(0x10)), event.key_modifiers_none))
	assert !binding.is_press(event.KeyEvent.new(event.KeyCode.char_key(rune(0x10)), event.key_modifiers_alt))
}

fn test_ctrl_bindings_match_all_supported_c0_control_char_events() {
	cases := [
		C0Case{ ctrl_char: ` `, c0_char: rune(0x00) },
		C0Case{ ctrl_char: `a`, c0_char: rune(0x01) },
		C0Case{ ctrl_char: `b`, c0_char: rune(0x02) },
		C0Case{ ctrl_char: `c`, c0_char: rune(0x03) },
		C0Case{ ctrl_char: `d`, c0_char: rune(0x04) },
		C0Case{ ctrl_char: `e`, c0_char: rune(0x05) },
		C0Case{ ctrl_char: `f`, c0_char: rune(0x06) },
		C0Case{ ctrl_char: `g`, c0_char: rune(0x07) },
		C0Case{ ctrl_char: `h`, c0_char: rune(0x08) },
		C0Case{ ctrl_char: `i`, c0_char: rune(0x09) },
		C0Case{ ctrl_char: `j`, c0_char: rune(0x0a) },
		C0Case{ ctrl_char: `k`, c0_char: rune(0x0b) },
		C0Case{ ctrl_char: `l`, c0_char: rune(0x0c) },
		C0Case{ ctrl_char: `m`, c0_char: rune(0x0d) },
		C0Case{ ctrl_char: `n`, c0_char: rune(0x0e) },
		C0Case{ ctrl_char: `o`, c0_char: rune(0x0f) },
		C0Case{ ctrl_char: `p`, c0_char: rune(0x10) },
		C0Case{ ctrl_char: `q`, c0_char: rune(0x11) },
		C0Case{ ctrl_char: `r`, c0_char: rune(0x12) },
		C0Case{ ctrl_char: `s`, c0_char: rune(0x13) },
		C0Case{ ctrl_char: `t`, c0_char: rune(0x14) },
		C0Case{ ctrl_char: `u`, c0_char: rune(0x15) },
		C0Case{ ctrl_char: `v`, c0_char: rune(0x16) },
		C0Case{ ctrl_char: `w`, c0_char: rune(0x17) },
		C0Case{ ctrl_char: `x`, c0_char: rune(0x18) },
		C0Case{ ctrl_char: `y`, c0_char: rune(0x19) },
		C0Case{ ctrl_char: `z`, c0_char: rune(0x1a) },
		C0Case{ ctrl_char: `4`, c0_char: rune(0x1c) },
		C0Case{ ctrl_char: `5`, c0_char: rune(0x1d) },
		C0Case{ ctrl_char: `]`, c0_char: rune(0x1d) },
		C0Case{ ctrl_char: `6`, c0_char: rune(0x1e) },
		C0Case{ ctrl_char: `7`, c0_char: rune(0x1f) },
	]

	for item in cases {
		assert ctrl(event.KeyCode.char_key(item.ctrl_char)).is_press(event.KeyEvent.new(event.KeyCode.char_key(item.c0_char),
			event.key_modifiers_none)), 'expected raw C0 ${item.c0_char} to match ctrl-${item.ctrl_char}'
		assert !ctrl(event.KeyCode.char_key(item.ctrl_char)).is_press(event.KeyEvent.new(event.KeyCode.char_key(item.c0_char),
			event.key_modifiers_alt)), 'expected modified raw C0 ${item.c0_char} not to match ctrl-${item.ctrl_char}'
	}
}

fn test_ctrl_binding_does_not_match_ambiguous_c0_escape_or_delete() {
	assert !ctrl(event.KeyCode.char_key(`[`)).is_press(event.KeyEvent.new(event.KeyCode.char_key(rune(0x1b)),
		event.key_modifiers_none))
	assert !ctrl(event.KeyCode.char_key(`?`)).is_press(event.KeyEvent.new(event.KeyCode.char_key(rune(0x7f)),
		event.key_modifiers_none))
}

fn test_history_search_ctrl_bindings_match_c0_control_char_events() {
	assert ctrl(event.KeyCode.char_key(`r`)).is_press(event.KeyEvent.new(event.KeyCode.char_key(rune(0x12)),
		event.key_modifiers_none))
	assert ctrl(event.KeyCode.char_key(`s`)).is_press(event.KeyEvent.new(event.KeyCode.char_key(rune(0x13)),
		event.key_modifiers_none))
}

fn test_ctrl_alt_sets_both_modifiers() {
	assert ctrl_alt(event.KeyCode.char_key(`v`)).parts() == KeyParts{
		code:      event.KeyCode.char_key(`v`)
		modifiers: event.key_modifiers_control.union(event.key_modifiers_alt)
	}
}

fn test_has_ctrl_or_alt_checks_supported_modifier_combinations() {
	assert !has_ctrl_or_alt(event.key_modifiers_none)
	assert has_ctrl_or_alt(event.key_modifiers_control)
	assert has_ctrl_or_alt(event.key_modifiers_alt)

	control_alt := event.key_modifiers_control.union(event.key_modifiers_alt)
	$if windows {
		assert !has_ctrl_or_alt(control_alt)
	} $else {
		assert has_ctrl_or_alt(control_alt)
	}
}

// V-specific coverage for the three Rust `From<...> for Span` implementations and display paths
// that the source module's tests do not exercise directly.
fn test_display_labels_and_span_conversions_preserve_rendering() {
	all_modifiers := event.key_modifiers_control.union(event.key_modifiers_shift).union(event.key_modifiers_alt)
	binding := KeyBinding.new(event.KeyCode.char_key(`A`), all_modifiers)
	assert binding.display_label() == 'ctrl + shift + ⌥ + a'
	assert plain(event.KeyCode.char_key(` `)).display_label() == 'space'
	assert plain(event.key_code_page_up).display_label() == 'pgup'
	assert plain(event.key_code_page_down).display_label() == 'pgdn'

	owned_span := span_from_binding(binding)
	assert owned_span.text == 'ctrl + shift + ⌥ + a'
	assert owned_span.style.dim
	borrowed_span := span_from_borrowed_binding(&binding)
	assert borrowed_span == owned_span

	hint := ShortcutHint.chord(ctrl(event.KeyCode.char_key(`x`)), plain(event.key_code_enter))
	assert hint.display_label() == 'ctrl + x enter'
	assert !hint.is_press(event.KeyEvent.new(event.KeyCode.char_key(`x`), event.key_modifiers_control))
	hint_span := span_from_shortcut_hint(hint)
	assert hint_span.text == 'ctrl + x enter'
	assert hint_span.style.dim
}
