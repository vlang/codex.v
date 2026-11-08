module keys

import crossterm.event
import codex_tui.key_hint

fn test_navigation_accepts_arrow_and_vi_keys_without_stealing_other_actions() {
	up := move_up[..]
	down := move_down[..]
	for code in [event.key_code_up, event.KeyCode.char_key(`k`)] {
		input := event.KeyEvent.new(code, event.key_modifiers_none)
		assert key_hint.bindings_are_pressed(&up, input)
		assert !key_hint.bindings_are_pressed(&down, input)
	}
	for code in [event.key_code_down, event.KeyCode.char_key(`j`)] {
		input := event.KeyEvent.new(code, event.key_modifiers_none)
		assert key_hint.bindings_are_pressed(&down, input)
		assert !key_hint.bindings_are_pressed(&up, input)
	}
	assert !key_hint.bindings_are_pressed(&up, event.KeyEvent.new(event.KeyCode.char_key(`k`),
		event.key_modifiers_control))
	assert !key_hint.bindings_are_pressed(&down, event.KeyEvent.new(event.KeyCode.char_key(`j`),
		event.key_modifiers_alt))
}

fn test_numbered_choices_and_yes_no_aliases_dispatch_to_their_own_selection() {
	first := select_first[..]
	second := select_second[..]
	third := select_third[..]
	fourth := select_fourth[..]
	for ch in [`1`, `y`] {
		input := event.KeyEvent.new(event.KeyCode.char_key(ch), event.key_modifiers_none)
		assert key_hint.bindings_are_pressed(&first, input)
		assert !key_hint.bindings_are_pressed(&second, input)
		assert !key_hint.bindings_are_pressed(&third, input)
		assert !key_hint.bindings_are_pressed(&fourth, input)
	}
	for ch in [`2`, `n`] {
		input := event.KeyEvent.new(event.KeyCode.char_key(ch), event.key_modifiers_none)
		assert key_hint.bindings_are_pressed(&second, input)
		assert !key_hint.bindings_are_pressed(&first, input)
		assert !key_hint.bindings_are_pressed(&third, input)
		assert !key_hint.bindings_are_pressed(&fourth, input)
	}
	third_input := event.KeyEvent.new(event.KeyCode.char_key(`3`), event.key_modifiers_none)
	fourth_input := event.KeyEvent.new(event.KeyCode.char_key(`4`), event.key_modifiers_none)
	assert key_hint.bindings_are_pressed(&third, third_input)
	assert !key_hint.bindings_are_pressed(&fourth, third_input)
	assert key_hint.bindings_are_pressed(&fourth, fourth_input)
	assert !key_hint.bindings_are_pressed(&third, fourth_input)
	assert !key_hint.bindings_are_pressed(&first, event.KeyEvent.new(event.KeyCode.char_key(`Y`),
		event.key_modifiers_none))
	assert !key_hint.bindings_are_pressed(&second, event.KeyEvent.new(event.KeyCode.char_key(`n`),
		event.key_modifiers_control))
}

fn test_confirm_and_cancel_distinguish_key_codes_from_literal_control_characters() {
	confirm_bindings := confirm[..]
	cancel_bindings := cancel[..]
	enter := event.KeyEvent.new(event.key_code_enter, event.key_modifiers_none)
	escape := event.KeyEvent.new(event.key_code_esc, event.key_modifiers_none)
	assert key_hint.bindings_are_pressed(&confirm_bindings, enter)
	assert !key_hint.bindings_are_pressed(&cancel_bindings, enter)
	assert key_hint.bindings_are_pressed(&cancel_bindings, escape)
	assert !key_hint.bindings_are_pressed(&confirm_bindings, escape)
	assert !key_hint.bindings_are_pressed(&confirm_bindings, event.KeyEvent.new(event.KeyCode.char_key(`\n`),
		event.key_modifiers_none))
	assert !key_hint.bindings_are_pressed(&cancel_bindings, event.KeyEvent.new(event.KeyCode.char_key(rune(0x1b)),
		event.key_modifiers_none))
	assert !key_hint.bindings_are_pressed(&confirm_bindings, event.KeyEvent.new(event.key_code_enter,
		event.key_modifiers_control))
}

fn test_quit_accepts_plain_q_control_chords_and_terminal_c0_reports() {
	bindings := quit[..]
	assert key_hint.bindings_are_pressed(&bindings, event.KeyEvent.new(event.KeyCode.char_key(`q`),
		event.key_modifiers_none))
	for ch in [`c`, `d`] {
		assert key_hint.bindings_are_pressed(&bindings, event.KeyEvent.new(event.KeyCode.char_key(ch),
			event.key_modifiers_control))
		assert !key_hint.bindings_are_pressed(&bindings, event.KeyEvent.new(event.KeyCode.char_key(ch),
			event.key_modifiers_none))
	}
	for ch in [rune(0x03), rune(0x04)] {
		assert key_hint.bindings_are_pressed(&bindings, event.KeyEvent.new(event.KeyCode.char_key(ch),
			event.key_modifiers_none))
		assert !key_hint.bindings_are_pressed(&bindings, event.KeyEvent.new(event.KeyCode.char_key(ch),
			event.key_modifiers_alt))
	}
	assert !key_hint.bindings_are_pressed(&bindings, event.KeyEvent.new(event.KeyCode.char_key(`q`),
		event.key_modifiers_control))
}

fn test_animation_toggle_accepts_control_period_with_or_without_shift_only() {
	bindings := toggle_animation[..]
	for modifiers in [event.key_modifiers_control,
		event.key_modifiers_control.union(event.key_modifiers_shift)] {
		assert key_hint.bindings_are_pressed(&bindings, event.KeyEvent.new(event.KeyCode.char_key(`.`),
			modifiers))
	}
	for modifiers in [event.key_modifiers_none, event.key_modifiers_shift,
		event.key_modifiers_control.union(event.key_modifiers_alt)] {
		assert !key_hint.bindings_are_pressed(&bindings, event.KeyEvent.new(event.KeyCode.char_key(`.`),
			modifiers))
	}
	assert !key_hint.bindings_are_pressed(&bindings, event.KeyEvent.new(event.KeyCode.char_key(`>`),
		event.key_modifiers_control.union(event.key_modifiers_shift)))
}

fn test_copy_bindings_remain_reusable_across_press_repeat_and_release_matching() {
	// All source bindings are Copy values. Reusing them exercises the exported fixed arrays
	// under ownership analysis without introducing a clone boundary for a binding.
	for bindings in [move_up[..], move_down[..], select_first[..], select_second[..], select_third[..],
		select_fourth[..], confirm[..], cancel[..], quit[..], toggle_animation[..]] {
		for binding in bindings {
			copied := binding
			press := event.KeyEvent.new(binding.code, binding.modifiers)
			repeat := event.KeyEvent{
				...press
				kind: .repeat
			}
			release := event.KeyEvent{
				...press
				kind: .release
			}
			assert binding.is_press(press)
			assert copied.is_press(repeat)
			assert !binding.is_press(release)
			assert binding.is_press(press)
			assert copied.is_press(press)
		}
	}
}
