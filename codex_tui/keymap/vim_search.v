module keymap

import codex_config.types
import codex_tui.key_hint
import crossterm.event

// Search bindings shared by normal and operator-pending input. Existing explicit Vim
// bindings win over new defaults; explicit search conflicts remain configuration errors.
pub struct VimSearchKeymap {
pub mut:
	forward  []key_hint.KeyBinding
	backward []key_hint.KeyBinding
	next     []key_hint.KeyBinding
	previous []key_hint.KeyBinding
}

pub fn VimSearchKeymap.default() VimSearchKeymap {
	return VimSearchKeymap{
		forward:  [key_hint.plain(event.KeyCode.char_key(`/`))]
		backward: [
			key_hint.plain(event.KeyCode.char_key(`?`)),
			key_hint.shift(event.KeyCode.char_key(`?`)),
		]
		next:     [key_hint.plain(event.KeyCode.char_key(`n`))]
		previous: [
			key_hint.plain(event.KeyCode.char_key(`N`)),
			key_hint.shift(event.KeyCode.char_key(`n`)),
		]
	}
}

// Rust iterates a `[(action, &Option<KeybindingsSpec>, &mut Vec<KeyBinding>); 4]` array so each
// slot can be mutated in place. V has no array of mutable field references, so the same four slots
// are walked by index and written back to `search` in the identical order.
pub fn (mut resolved_keymap RuntimeKeymap) configure_vim_search(config &types.TuiKeymap) ! {
	mut others := []RuntimeActionBinding{}
	for binding in runtime_action_bindings(resolved_keymap) {
		if binding.id.context == .vim_normal || binding.id.context == .vim_operator {
			others << binding
		}
	}
	mut search := resolved_keymap.vim_search
	config_search := config.vim_search
	action_names := ['forward', 'backward', 'next', 'previous']
	configured_slots := [
		config_search.forward,
		config_search.backward,
		config_search.next,
		config_search.previous,
	]
	for index, action in action_names {
		path := 'tui.keymap.vim_search.${action}'
		mut bindings := match index {
			0 { search.forward.clone() }
			1 { search.backward.clone() }
			2 { search.next.clone() }
			else { search.previous.clone() }
		}
		if configured_slots[index] == none {
			mut retained := []key_hint.KeyBinding{}
			for key in bindings {
				mut shadowed_by_other := false
				for other in others {
					if key in other.bindings {
						if slot := configured_binding_for_action(config, other.id) {
							if slot.spec != none {
								shadowed_by_other = true
								break
							}
						}
					}
				}
				mut shadowed_by_chord := false
				for chord in resolved_keymap.chords.bindings {
					if chord.action.context.overlaps(.vim_search)
						&& chord.chord.prefix.parts() == key.parts() {
						shadowed_by_chord = true
						break
					}
				}
				if !shadowed_by_other && !shadowed_by_chord {
					retained << key
				}
			}
			bindings = retained.clone()
		}
		for other in others {
			mut conflicts := false
			for key in other.bindings {
				if key in bindings {
					conflicts = true
					break
				}
			}
			if conflicts {
				return error('Conflicting `${path}` and `${other.id.config_path()}` bindings')
			}
		}
		match index {
			0 {
				search.forward = bindings
			}
			1 {
				search.backward = bindings
			}
			2 {
				search.next = bindings
			}
			else {
				search.previous = bindings
			}
		}
	}
	validate_unique('vim_search', [
		ActionBindings{
			action:   'forward'
			bindings: search.forward.clone()
		},
		ActionBindings{
			action:   'backward'
			bindings: search.backward.clone()
		},
		ActionBindings{
			action:   'next'
			bindings: search.next.clone()
		},
		ActionBindings{
			action:   'previous'
			bindings: search.previous.clone()
		},
	])!
	resolved_keymap.vim_search = search
}
