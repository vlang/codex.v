module keymap

import codex_config.types
import codex_tui.key_hint
import crossterm.event

// Ownership harness for `v -ownership`.
//
// AGENTS.md requires a focused check that owned values survive repeated borrowed calls. The Rust
// source resolves one `&TuiKeymap` into an owned `RuntimeKeymap` and then reads borrowed binding
// slices many times, so this harness creates owned spec strings, borrows the config repeatedly, and
// keeps using both owners afterwards.
pub fn keymap_ownership_harness() int {
	mut configured := types.TuiKeymap{}
	$if ownership ? {
		submit_spec := 'ctrl-enter'.to_owned()
		toggle_spec := 'f12'.to_owned()
		// Name each owned aggregate before passing it onward. The pinned ownership checker
		// otherwise counts the nested field construction and function argument as two moves.
		submit_binding := types.KeybindingSpec{
			value: submit_spec
		}
		toggle_binding := types.KeybindingSpec{
			value: toggle_spec
		}
		configured.composer.submit = types.KeybindingsSpec.from_one(submit_binding)
		configured.global.toggle_raw_output = types.KeybindingsSpec.from_one(toggle_binding)
	} $else {
		configured.composer.submit = types.KeybindingsSpec.from_one(types.KeybindingSpec{
			value: 'ctrl-enter'
		})
		configured.global.toggle_raw_output = types.KeybindingsSpec.from_one(types.KeybindingSpec{
			value: 'f12'
		})
	}

	// Borrow the same owned config more than once.
	first := RuntimeKeymap.from_config(&configured) or { return -1 }
	second := RuntimeKeymap.from_config(&configured) or { return -2 }
	// The owner remains usable after both borrowed calls.
	alias_used := configured_main_surface_alias_is_used(&configured, 'ctrl-enter')
	if !alias_used {
		return -3
	}

	// Borrow the resolved binding lists more than once, then keep using the owners.
	submit := first.composer.submit.clone()
	if primary_binding(&submit) == none {
		return -4
	}
	if primary_binding(&submit) == none {
		return -5
	}
	pressed_twice := key_hint.bindings_are_pressed(&submit, event.KeyEvent.new(event.key_code_enter, event.key_modifiers_control))
		&& key_hint.bindings_are_pressed(&submit, event.KeyEvent.new(event.key_code_enter, event.key_modifiers_control))
	if !pressed_twice {
		return -6
	}

	hint := first.primary_hint(.composer, 'submit') or { return -7 }
	if hint.display_label().len == 0 {
		return -8
	}
	list_hint := first.list.primary_hint(.move_up) or { return -9 }
	if list_hint.display_label().len == 0 {
		return -10
	}
	approval_hint := first.approval.hint_for_bindings(&first.approval.approve) or { return -11 }
	if approval_hint.display_label().len == 0 {
		return -12
	}

	return first.app.toggle_raw_output.len + second.app.toggle_raw_output.len + submit.len
}
