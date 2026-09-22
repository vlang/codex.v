module keymap

import codex_config.types
import codex_tui.key_hint
import crossterm.event

fn one(spec string) types.KeybindingsSpec {
	return types.KeybindingsSpec.from_one(types.KeybindingSpec{
		value: spec
	})
}

// Rust writes `KeybindingsSpec::Many(vec![KeybindingSpec("a".to_string()), ...])` inline; the
// helper keeps the translated tests readable without changing what is constructed.
fn many(specs []string) types.KeybindingsSpec {
	mut entries := []types.KeybindingSpec{}
	for spec in specs {
		entries << types.KeybindingSpec{
			value: spec
		}
	}
	return types.KeybindingsSpec.from_many(entries)
}

// Stands in for `RuntimeKeymap::from_config(..).expect_err(..)`.
fn expect_config_error(resolved_keymap &types.TuiKeymap, expectation string) string {
	RuntimeKeymap.from_config(resolved_keymap) or { return err.msg() }
	panic(expectation)
}

// Stands in for `RuntimeKeymap::from_config(..).expect(..)`.
fn expect_runtime(resolved_keymap &types.TuiKeymap, expectation string) RuntimeKeymap {
	return RuntimeKeymap.from_config(resolved_keymap) or { panic('${expectation}: ${err.msg()}') }
}

fn config_is_ok(resolved_keymap &types.TuiKeymap) bool {
	RuntimeKeymap.from_config(resolved_keymap) or { return false }
	return true
}

fn expect_conflict(resolved_keymap &types.TuiKeymap, first string, second string) {
	err_msg := expect_config_error(resolved_keymap, 'expected conflict')
	assert err_msg.contains(first)
	assert err_msg.contains(second)
}

// Rust builds several fixtures with `serde_json::from_value(json!({context: {action: spec}}))`.
// The V config stub has no deserializer yet, so the same assignment is applied through a named
// setter covering exactly the context/action pairs those tests use.
fn set_configured_binding(mut resolved_keymap types.TuiKeymap, context string, action string, spec types.KeybindingsSpec) {
	match context {
		'global' {
			match action {
				'submit' {
					resolved_keymap.global.submit = spec
				}
				'queue' {
					resolved_keymap.global.queue = spec
				}
				'toggle_shortcuts' {
					resolved_keymap.global.toggle_shortcuts = spec
				}
				else { panic('unsupported global action `${action}`') }
			}
		}
		'composer' {
			match action {
				'submit' {
					resolved_keymap.composer.submit = spec
				}
				else { panic('unsupported composer action `${action}`') }
			}
		}
		'editor' {
			match action {
				'insert_newline' {
					resolved_keymap.editor.insert_newline = spec
				}
				'yank' {
					resolved_keymap.editor.yank = spec
				}
				else { panic('unsupported editor action `${action}`') }
			}
		}
		'vim_normal' {
			match action {
				'enter_insert' {
					resolved_keymap.vim_normal.enter_insert = spec
				}
				'move_left' {
					resolved_keymap.vim_normal.move_left = spec
				}
				'cancel_operator' {
					resolved_keymap.vim_normal.cancel_operator = spec
				}
				else { panic('unsupported vim_normal action `${action}`') }
			}
		}
		'vim_operator' {
			match action {
				'delete_line' {
					resolved_keymap.vim_operator.delete_line = spec
				}
				'cancel' {
					resolved_keymap.vim_operator.cancel = spec
				}
				else { panic('unsupported vim_operator action `${action}`') }
			}
		}
		'vim_search' {
			match action {
				'forward' {
					resolved_keymap.vim_search.forward = spec
				}
				else { panic('unsupported vim_search action `${action}`') }
			}
		}
		'vim_text_object' {
			match action {
				'word' {
					resolved_keymap.vim_text_object.word = spec
				}
				'cancel' {
					resolved_keymap.vim_text_object.cancel = spec
				}
				else { panic('unsupported vim_text_object action `${action}`') }
			}
		}
		'pager' {
			match action {
				'scroll_up' {
					resolved_keymap.pager.scroll_up = spec
				}
				'close_transcript' {
					resolved_keymap.pager.close_transcript = spec
				}
				else { panic('unsupported pager action `${action}`') }
			}
		}
		'list' {
			match action {
				'move_up' {
					resolved_keymap.list.move_up = spec
				}
				'cancel' {
					resolved_keymap.list.cancel = spec
				}
				else { panic('unsupported list action `${action}`') }
			}
		}
		'agents' {
			match action {
				'search' {
					resolved_keymap.agents.search = spec
				}
				'toggle_grouping' {
					resolved_keymap.agents.toggle_grouping = spec
				}
				else { panic('unsupported agents action `${action}`') }
			}
		}
		'approval' {
			match action {
				'open_fullscreen' {
					resolved_keymap.approval.open_fullscreen = spec
				}
				'cancel' {
					resolved_keymap.approval.cancel = spec
				}
				else { panic('unsupported approval action `${action}`') }
			}
		}
		else {
			panic('unsupported keymap context `${context}`')
		}
	}
}

fn test_parses_canonical_binding() {
	binding := parse_keybinding('ctrl-alt-shift-a') or { panic('binding should parse') }
	assert binding.parts().code == event.KeyCode.char_key(`a`)
	assert binding.parts().modifiers == event.key_modifiers_control.union(event.key_modifiers_alt).union(event.key_modifiers_shift)
}

fn test_rejects_shadowing_composer_binding_in_app_scope() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.open_transcript = one('ctrl-t')
	resolved_keymap.composer.submit = one('ctrl-t')

	err_msg := expect_config_error(&resolved_keymap, 'expected shadowing conflict')
	assert err_msg.contains('composer.submit')
	assert err_msg.contains('open_transcript')
}

fn test_rejects_shadowing_composer_queue_in_app_scope() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.open_external_editor = one('ctrl-g')
	resolved_keymap.composer.queue = one('ctrl-g')

	err_msg := expect_config_error(&resolved_keymap, 'expected shadowing conflict')
	assert err_msg.contains('composer.queue')
	assert err_msg.contains('open_external_editor')
}

fn test_rejects_shadowing_composer_toggle_shortcuts_in_app_scope() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.open_transcript = one('ctrl-k')
	resolved_keymap.composer.toggle_shortcuts = one('ctrl-k')

	err_msg := expect_config_error(&resolved_keymap, 'expected shadowing conflict')
	assert err_msg.contains('composer.toggle_shortcuts')
	assert err_msg.contains('open_transcript')
}

fn test_rejects_shadowing_editor_binding_in_main_scope() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.composer.submit = one('ctrl-j')
	resolved_keymap.editor.insert_newline = one('ctrl-j')

	err_msg := expect_config_error(&resolved_keymap, 'expected shadowing conflict')
	assert err_msg.contains('composer.submit')
	assert err_msg.contains('editor.insert_newline')
}

fn test_rejects_shadowing_editor_binding_from_outer_main_handler() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.copy = one('ctrl-y')
	resolved_keymap.editor.yank = one('ctrl-y')

	err_msg := expect_config_error(&resolved_keymap, 'expected shadowing conflict')
	assert err_msg.contains('copy')
	assert err_msg.contains('editor.yank')
}

fn test_rejects_shadowing_approval_binding_in_app_scope() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.open_transcript = one('y')

	err_msg := expect_config_error(&resolved_keymap, 'expected shadowing conflict')
	assert err_msg.contains('approval.approve')
	assert err_msg.contains('open_transcript')
}

fn test_rejects_shadowing_list_binding_in_app_scope() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.copy = one('down')

	err_msg := expect_config_error(&resolved_keymap, 'expected shadowing conflict')
	assert err_msg.contains('list.move_down')
	assert err_msg.contains('copy')
}

fn test_supports_string_or_array_bindings() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.composer.submit = many(['ctrl-enter', 'meta-enter'])

	err_msg := expect_config_error(&resolved_keymap, 'meta is not a valid modifier')
	assert err_msg.contains('tui.keymap.composer.submit')

	resolved_keymap.composer.submit = many(['ctrl-enter', 'ctrl-shift-enter'])

	runtime := expect_runtime(&resolved_keymap, 'valid multi-binding')
	assert runtime.composer.submit.len == 2
}

fn test_deduplicates_repeated_bindings_while_preserving_first_seen_order() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.composer.submit = many(['ctrl-enter', 'ctrl-enter', 'ctrl-shift-enter'])

	runtime := expect_runtime(&resolved_keymap, 'valid multi-binding')
	assert runtime.composer.submit == [
		key_hint.ctrl(event.key_code_enter),
		key_hint.KeyBinding.new(event.key_code_enter, event.key_modifiers_control.union(event.key_modifiers_shift)),
	]
}

fn test_falls_back_to_global_binding_when_context_override_is_not_set() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.queue = one('ctrl-q')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')
	assert runtime.composer.queue == [key_hint.ctrl(event.KeyCode.char_key(`q`))]
}

fn test_invalid_global_open_transcript_binding_reports_global_path() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.open_transcript = one('meta-t')

	err_msg := expect_config_error(&resolved_keymap, 'expected parse error')
	assert err_msg.contains('tui.keymap.global.open_transcript')
}

fn test_invalid_global_open_external_editor_binding_reports_global_path() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.open_external_editor = one('meta-g')

	err_msg := expect_config_error(&resolved_keymap, 'expected parse error')
	assert err_msg.contains('tui.keymap.global.open_external_editor')
}

fn test_default_copy_binding_is_ctrl_o() {
	runtime := RuntimeKeymap.defaults()
	assert runtime.app.copy == [key_hint.ctrl(event.KeyCode.char_key(`o`))]
}

fn test_permission_shortcuts_reserve_plain_text() {
	for binding in ['a', 'shift-a', '2', 'space'] {
		mut resolved_keymap := types.TuiKeymap{}
		resolved_keymap.chat.previous_permission_mode = one(binding)
		assert expect_config_error(&resolved_keymap, 'permission shortcuts must not intercept typing').contains('printable keys')
		resolved_keymap.chat.previous_permission_mode = none
		resolved_keymap.chat.next_permission_mode = one(binding)
		assert !config_is_ok(&resolved_keymap)
		resolved_keymap.chat.next_permission_mode = none
		resolved_keymap.chat.skip_question = one(binding)
		assert !config_is_ok(&resolved_keymap)
		resolved_keymap.chat.skip_question = none
		resolved_keymap.chat.prompt_stack_back = one(binding)
		assert !config_is_ok(&resolved_keymap)
	}
	// The Rust test also asserts the AltGr (`ctrl-alt-q`) rejections behind `#[cfg(windows)]`.
	// `key_hint.is_altgr` ports only the non-Windows definition, so that block has no V counterpart
	// yet.
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.chat.previous_permission_mode = one('f7')
	resolved_keymap.chat.next_permission_mode = one('ctrl-x enter')
	assert config_is_ok(&resolved_keymap)
}

fn test_defaults_include_reassignable_main_surface_actions() {
	runtime := RuntimeKeymap.defaults()

	assert runtime.app.clear_terminal == [key_hint.ctrl(event.KeyCode.char_key(`l`))]
	assert runtime.app.toggle_fast_mode == []key_hint.KeyBinding{}
	assert runtime.chat.interrupt_turn == [key_hint.plain(event.key_code_esc)]
	assert runtime.chat.decrease_reasoning_effort == [
		key_hint.alt(event.KeyCode.char_key(`,`)),
		key_hint.shift(event.key_code_down),
	]
	assert runtime.chat.increase_reasoning_effort == [
		key_hint.alt(event.KeyCode.char_key(`.`)),
		key_hint.shift(event.key_code_up),
	]
	assert runtime.chat.edit_queued_message == [
		key_hint.alt(event.key_code_up),
		key_hint.shift(event.key_code_left),
	]
	assert runtime.composer.history_search_previous == [
		key_hint.ctrl(event.KeyCode.char_key(`r`)),
	]
	assert runtime.composer.history_search_next == [
		key_hint.ctrl(event.KeyCode.char_key(`s`)),
	]
	assert runtime.editor.kill_whole_line == []key_hint.KeyBinding{}
}

fn test_defaults_include_list_page_and_jump_actions() {
	runtime := RuntimeKeymap.defaults()

	assert runtime.list.move_up == [
		key_hint.plain(event.key_code_up),
		key_hint.ctrl(event.KeyCode.char_key(`p`)),
		key_hint.ctrl(event.KeyCode.char_key(`k`)),
		key_hint.plain(event.KeyCode.char_key(`k`)),
	]
	assert runtime.list.move_down == [
		key_hint.plain(event.key_code_down),
		key_hint.ctrl(event.KeyCode.char_key(`n`)),
		key_hint.ctrl(event.KeyCode.char_key(`j`)),
		key_hint.plain(event.KeyCode.char_key(`j`)),
	]
	assert runtime.list.move_left == [
		key_hint.plain(event.key_code_left),
		key_hint.ctrl(event.KeyCode.char_key(`h`)),
	]
	assert runtime.list.move_right == [
		key_hint.plain(event.key_code_right),
		key_hint.ctrl(event.KeyCode.char_key(`l`)),
	]
	assert runtime.list.page_up == [
		key_hint.plain(event.key_code_page_up),
		key_hint.ctrl(event.KeyCode.char_key(`b`)),
	]
	assert runtime.list.page_down == [
		key_hint.plain(event.key_code_page_down),
		key_hint.ctrl(event.KeyCode.char_key(`f`)),
	]
	assert runtime.list.jump_top == [key_hint.plain(event.key_code_home)]
	assert runtime.list.jump_bottom == [key_hint.plain(event.key_code_end)]
}

fn test_configured_main_surface_bindings_prune_reasoning_fallback_aliases() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.editor.move_up = one('shift-up')
	resolved_keymap.vim_text_object.word = one('shift-down')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.editor.move_up == [key_hint.shift(event.key_code_up)]
	assert runtime.vim_text_object.word == [key_hint.shift(event.key_code_down)]
	assert runtime.chat.decrease_reasoning_effort == [
		key_hint.alt(event.KeyCode.char_key(`,`)),
	]
	assert runtime.chat.increase_reasoning_effort == [
		key_hint.alt(event.KeyCode.char_key(`.`)),
	]
}

fn test_explicit_reasoning_binding_still_conflicts_with_editor_binding() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.editor.move_up = one('shift-up')
	resolved_keymap.chat.increase_reasoning_effort = one('shift-up')

	expect_conflict(&resolved_keymap, 'chat.increase_reasoning_effort', 'editor.move_up')
}

fn test_configured_legacy_list_bindings_prune_new_default_overlaps() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.list.move_up = one('page-up')
	resolved_keymap.list.move_down = one('page-down')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.list.move_up == [key_hint.plain(event.key_code_page_up)]
	assert runtime.list.move_down == [key_hint.plain(event.key_code_page_down)]
	assert runtime.list.page_up == [key_hint.ctrl(event.KeyCode.char_key(`b`))]
	assert runtime.list.page_down == [key_hint.ctrl(event.KeyCode.char_key(`f`))]
}

fn test_configured_legacy_list_bindings_can_prune_all_new_default_keys() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.list.move_up = many(['page-up', 'ctrl-b'])

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.list.move_up == [
		key_hint.plain(event.key_code_page_up),
		key_hint.ctrl(event.KeyCode.char_key(`b`)),
	]
	assert runtime.list.page_up == []key_hint.KeyBinding{}
}

fn test_explicit_new_list_bindings_still_conflict_with_legacy_bindings() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.list.move_up = one('page-up')
	resolved_keymap.list.page_up = one('page-up')

	expect_conflict(&resolved_keymap, 'move_up', 'page_up')
}

fn test_configured_app_bindings_prune_new_list_default_overlaps() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.copy = one('page-down')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.app.copy == [key_hint.plain(event.key_code_page_down)]
	assert runtime.list.page_down == [key_hint.ctrl(event.KeyCode.char_key(`f`))]
}

fn test_configured_approval_bindings_prune_new_list_default_overlaps() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.approval.approve = one('home')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.approval.approve == [key_hint.plain(event.key_code_home)]
	assert runtime.list.jump_top == []key_hint.KeyBinding{}
}

fn test_explicit_new_list_bindings_still_conflict_with_configured_approval_bindings() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.approval.approve = one('home')
	resolved_keymap.list.jump_top = one('home')

	expect_conflict(&resolved_keymap, 'list.jump_top', 'approval.approve')
}

fn test_configured_legacy_vim_normal_bindings_prune_new_change_operator_default() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_normal.move_left = one('c')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.vim_normal.move_left == [
		key_hint.plain(event.KeyCode.char_key(`c`)),
	]
	assert runtime.vim_normal.start_change_operator == []key_hint.KeyBinding{}
}

fn test_explicit_new_vim_normal_binding_still_conflicts_with_legacy_binding() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_normal.move_left = one('c')
	resolved_keymap.vim_normal.start_change_operator = one('c')

	expect_conflict(&resolved_keymap, 'move_left', 'start_change_operator')
}

fn test_explicit_replace_mode_binding_conflicts_with_legacy_binding() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_normal.move_left = one('shift-r')
	resolved_keymap.vim_normal.enter_replace_mode = one('shift-r')

	expect_conflict(&resolved_keymap, 'move_left', 'enter_replace_mode')
}

fn test_configured_legacy_vim_normal_bindings_prune_new_substitute_default() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_normal.move_left = one('s')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.vim_normal.move_left == [
		key_hint.plain(event.KeyCode.char_key(`s`)),
	]
	assert runtime.vim_normal.substitute_char == []key_hint.KeyBinding{}
}

fn test_explicit_new_vim_normal_substitute_binding_still_conflicts_with_legacy_binding() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_normal.move_left = one('s')
	resolved_keymap.vim_normal.substitute_char = one('s')

	expect_conflict(&resolved_keymap, 'move_left', 'substitute_char')
}

fn test_configured_legacy_vim_normal_bindings_prune_new_replace_default() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_normal.move_left = one('r')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.vim_normal.move_left == [
		key_hint.plain(event.KeyCode.char_key(`r`)),
	]
	assert runtime.vim_normal.replace_char == []key_hint.KeyBinding{}
}

fn test_configured_substitute_binding_prunes_new_replace_default() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_normal.substitute_char = one('r')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.vim_normal.substitute_char == [
		key_hint.plain(event.KeyCode.char_key(`r`)),
	]
	assert runtime.vim_normal.replace_char.len == 0
}

fn test_configured_vim_normal_chord_prefix_prunes_new_replace_default() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_normal.move_line_start = one('r g')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.vim_normal.replace_char.len == 0
	mut has_chord := false
	for binding in runtime.chords.bindings {
		if binding.action.context == .vim_normal
			&& binding.chord.prefix == key_hint.plain(event.KeyCode.char_key(`r`)) {
			has_chord = true
			break
		}
	}
	assert has_chord
}

fn test_explicit_new_vim_normal_replace_binding_still_conflicts_with_legacy_binding() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_normal.move_left = one('r')
	resolved_keymap.vim_normal.replace_char = one('r')

	expect_conflict(&resolved_keymap, 'move_left', 'replace_char')
}

fn test_configured_legacy_vim_normal_bindings_prune_new_repeat_default() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_normal.move_left = one('.')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.vim_normal.repeat_last_change == []key_hint.KeyBinding{}
}

fn test_configured_legacy_vim_bindings_prune_new_navigation_defaults() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_normal.move_left = one('f')
	resolved_keymap.vim_operator.motion_left = one('g')
	resolved_keymap.vim_normal.move_right = one('t')
	resolved_keymap.vim_normal.move_up = one('shift-f')
	resolved_keymap.vim_operator.motion_right = one('shift-t')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.vim_normal.find_forward == []key_hint.KeyBinding{}
	assert runtime.vim_normal.find_backward == []key_hint.KeyBinding{}
	assert runtime.vim_operator.motion_jump_top == []key_hint.KeyBinding{}
	assert runtime.vim_normal.till_forward == []key_hint.KeyBinding{}
	assert runtime.vim_operator.motion_till_backward == []key_hint.KeyBinding{}
}

fn test_explicit_vim_navigation_binding_still_conflicts_with_legacy_binding() {
	for key in ['f', 't'] {
		mut resolved_keymap := types.TuiKeymap{}
		resolved_keymap.vim_normal.move_left = one(key)
		mut action := ''
		if key == 'f' {
			resolved_keymap.vim_normal.find_forward = one(key)
			action = 'find_forward'
		} else {
			resolved_keymap.vim_normal.till_forward = one(key)
			action = 'till_forward'
		}
		expect_conflict(&resolved_keymap, 'move_left', action)
	}
}

fn test_vim_search_preserves_custom_motion_bindings() {
	for operator in [false, true] {
		mut config := types.TuiKeymap{}
		if operator {
			config.vim_operator.motion_left = one('n')
		} else {
			config.vim_normal.move_left = one('n')
		}
		runtime := expect_runtime(&config, 'custom motion keymap should resolve')
		assert runtime.vim_search.next.len == 0
		config.vim_search.next = one('n')
		assert !config_is_ok(&config)
	}
}

fn test_configured_vim_normal_chord_prefix_prunes_new_repeat_default() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_normal.move_line_start = one('. g')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.vim_normal.repeat_last_change.len == 0
	mut has_chord := false
	for binding in runtime.chords.bindings {
		if binding.action.context == .vim_normal
			&& binding.chord.prefix == key_hint.plain(event.KeyCode.char_key(`.`)) {
			has_chord = true
			break
		}
	}
	assert has_chord
}

fn test_configured_legacy_bindings_prune_new_vim_defaults() {
	for key_and_action in [['u', 'undo'], ['ctrl-r', 'redo'], ['shift-r', 'enter_replace_mode']] {
		key := key_and_action[0]
		new_action := key_and_action[1]
		for entry in [['vim_normal', 'move_left', ''], ['vim_normal', 'move_left', ' g'],
			['vim_search', 'forward', ''], ['vim_search', 'forward', ' g'], ['composer', 'submit',
				''], ['global', 'submit', ''], ['global', 'queue', ''],
			['global', 'toggle_shortcuts', '']] {
			context := entry[0]
			action := entry[1]
			suffix := entry[2]
			mut resolved_keymap := types.TuiKeymap{}
			set_configured_binding(mut resolved_keymap, context, action, one('${key}${suffix}'))
			if key == 'ctrl-r' && (suffix.len > 0 || context == 'composer' || context == 'global') {
				// Ctrl+R chords and main-surface actions must unbind the older history key.
				resolved_keymap.composer.history_search_previous = many([])
			}
			runtime := expect_runtime(&resolved_keymap, 'config should parse')
			resolved := bindings_for_action(runtime, 'vim_normal', new_action) or {
				panic('${context}.${action} = ${key}${suffix}')
			}
			assert resolved == []key_hint.KeyBinding{}, '${context}.${action} = ${key}${suffix}'
		}
	}
}

fn test_explicit_vim_history_bindings_still_conflict_with_legacy_bindings() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_normal.move_left = one('u')
	resolved_keymap.vim_normal.undo = one('u')
	expect_conflict(&resolved_keymap, 'move_left', 'undo')

	resolved_keymap.vim_normal.move_left = one('ctrl-r')
	resolved_keymap.vim_normal.undo = none
	resolved_keymap.vim_normal.redo = one('ctrl-r')
	expect_conflict(&resolved_keymap, 'move_left', 'redo')
}

fn test_explicit_empty_arrays_unbind_vim_history_actions() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_normal.undo = many([])
	resolved_keymap.vim_normal.redo = many([])

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.vim_normal.undo.len == 0
	assert runtime.vim_normal.redo.len == 0
}

fn test_configured_legacy_vim_operator_bindings_prune_new_text_object_defaults() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_operator.motion_left = one('i')
	resolved_keymap.vim_operator.motion_right = one('a')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.vim_operator.motion_left == [
		key_hint.plain(event.KeyCode.char_key(`i`)),
	]
	assert runtime.vim_operator.motion_right == [
		key_hint.plain(event.KeyCode.char_key(`a`)),
	]
	assert runtime.vim_operator.select_inner_text_object == []key_hint.KeyBinding{}
	assert runtime.vim_operator.select_around_text_object == []key_hint.KeyBinding{}
}

fn test_explicit_new_vim_operator_binding_still_conflicts_with_legacy_binding() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.vim_operator.motion_left = one('i')
	resolved_keymap.vim_operator.select_inner_text_object = one('i')

	expect_conflict(&resolved_keymap, 'motion_left', 'select_inner_text_object')
}

fn test_vim_normal_defaults_include_insert_and_arrow_aliases() {
	runtime := RuntimeKeymap.defaults()

	assert runtime.vim_normal.enter_insert == [
		key_hint.plain(event.KeyCode.char_key(`i`)),
		key_hint.plain(event.key_code_insert),
	]
	assert runtime.vim_normal.move_left == [
		key_hint.plain(event.KeyCode.char_key(`h`)),
		key_hint.plain(event.key_code_left),
	]
	assert runtime.vim_normal.move_right == [
		key_hint.plain(event.KeyCode.char_key(`l`)),
		key_hint.plain(event.key_code_right),
	]
	assert runtime.vim_normal.move_up == [
		key_hint.plain(event.KeyCode.char_key(`k`)),
		key_hint.plain(event.key_code_up),
	]
	assert runtime.vim_normal.move_down == [
		key_hint.plain(event.KeyCode.char_key(`j`)),
		key_hint.plain(event.key_code_down),
	]
}

fn test_invalid_global_copy_binding_reports_global_path() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.copy = one('meta-o')

	err_msg := expect_config_error(&resolved_keymap, 'expected parse error')
	assert err_msg.contains('tui.keymap.global.copy')
}

fn test_rejects_conflicting_editor_bindings() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.editor.move_left = one('ctrl-h')
	resolved_keymap.editor.move_right = one('ctrl-h')

	expect_conflict(&resolved_keymap, 'move_left', 'move_right')
}

fn test_rejects_conflicting_pager_bindings() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.pager.scroll_up = one('ctrl-u')
	resolved_keymap.pager.scroll_down = one('ctrl-u')

	expect_conflict(&resolved_keymap, 'scroll_up', 'scroll_down')
}

fn test_rejects_conflicting_list_bindings() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.list.move_up = one('up')
	resolved_keymap.list.move_down = one('up')

	expect_conflict(&resolved_keymap, 'move_up', 'move_down')

	mut horizontal_keymap := types.TuiKeymap{}
	horizontal_keymap.list.move_left = one('left')
	horizontal_keymap.list.move_right = one('left')

	expect_conflict(&horizontal_keymap, 'move_left', 'move_right')
}

fn test_rejects_conflicting_list_page_and_jump_bindings() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.list.page_up = one('home')
	resolved_keymap.list.jump_top = one('home')

	expect_conflict(&resolved_keymap, 'page_up', 'jump_top')
}

fn test_rejects_conflicting_approval_bindings() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.approval.approve = one('y')
	resolved_keymap.approval.decline = one('y')

	expect_conflict(&resolved_keymap, 'approve', 'decline')
}

fn test_rejects_conflicting_approval_deny_binding() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.approval.approve = one('y')
	resolved_keymap.approval.deny = one('y')

	expect_conflict(&resolved_keymap, 'approve', 'deny')
}

fn test_rejects_conflicting_approval_overlay_accept_binding() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.list.accept = one('y')

	expect_conflict(&resolved_keymap, 'list.accept', 'approval.approve')
}

fn test_rejects_conflicting_approval_overlay_cancel_binding() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.list.cancel = one('c')

	expect_conflict(&resolved_keymap, 'list.cancel', 'approval.cancel')
}

fn test_reassignable_fixed_shortcuts_conflict_until_original_action_is_unbound() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.copy = one('alt-.')

	expect_conflict(&resolved_keymap, 'copy', 'chat.increase_reasoning_effort')

	resolved_keymap.chat.increase_reasoning_effort = many([])
	runtime := expect_runtime(&resolved_keymap, 'remapped key should be free')
	assert runtime.app.copy == [key_hint.alt(event.KeyCode.char_key(`.`))]
}

fn test_kill_whole_line_can_be_assigned_without_default_binding() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.editor.kill_whole_line = one('ctrl-shift-u')

	runtime := expect_runtime(&resolved_keymap, 'runtime keymap')

	assert runtime.editor.kill_whole_line == [
		key_hint.KeyBinding.new(event.KeyCode.char_key(`u`), event.key_modifiers_control.union(event.key_modifiers_shift)),
	]
}

fn test_kill_whole_line_conflicts_until_kill_line_start_is_unbound() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.editor.kill_whole_line = one('ctrl-u')

	expect_conflict(&resolved_keymap, 'kill_line_start', 'kill_whole_line')

	resolved_keymap.editor.kill_line_start = many([])
	runtime := expect_runtime(&resolved_keymap, 'remapped key should be free')
	assert runtime.editor.kill_whole_line == [
		key_hint.ctrl(event.KeyCode.char_key(`u`)),
	]
}

fn test_toggle_fast_mode_can_be_assigned_without_default_binding() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.toggle_fast_mode = one('ctrl-shift-f')

	runtime := expect_runtime(&resolved_keymap, 'runtime keymap')

	assert runtime.app.toggle_fast_mode == [
		key_hint.KeyBinding.new(event.KeyCode.char_key(`f`), event.key_modifiers_control.union(event.key_modifiers_shift)),
	]
}

fn test_toggle_fast_mode_conflicts_with_existing_main_surface_bindings() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.toggle_fast_mode = one('ctrl-l')

	expect_conflict(&resolved_keymap, 'clear_terminal', 'toggle_fast_mode')
}

fn test_agents_overview_can_be_remapped_and_rejects_conflicts() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.open_agents = one('f12')
	resolved_keymap.agents.search = one('f6')
	resolved_keymap.agents.new_task = one('f7')
	resolved_keymap.agents.resume = one('f5')
	resolved_keymap.agents.rename = one('f9')
	resolved_keymap.agents.stop = one('f10')
	resolved_keymap.agents.toggle_grouping = one('f8')

	remapped := expect_runtime(&resolved_keymap, 'runtime keymap')
	assert remapped.app.open_agents == [
		key_hint.plain(event.KeyCode.function_key(12)),
	]
	assert remapped.agents.search == [key_hint.plain(event.KeyCode.function_key(6))]
	assert remapped.agents.new_task == [key_hint.plain(event.KeyCode.function_key(7))]
	assert remapped.agents.resume == [key_hint.plain(event.KeyCode.function_key(5))]
	assert remapped.agents.rename == [key_hint.plain(event.KeyCode.function_key(9))]
	assert remapped.agents.stop == [key_hint.plain(event.KeyCode.function_key(10))]
	assert remapped.agents.toggle_grouping == [
		key_hint.plain(event.KeyCode.function_key(8)),
	]

	resolved_keymap.agents.resume = one('f6')
	expect_conflict(&resolved_keymap, 'resume', 'search')
	resolved_keymap.agents.resume = one('f5')

	resolved_keymap.agents.toggle_grouping = one('right')
	with_right_grouping := expect_runtime(&resolved_keymap, 'runtime keymap')
	assert key_hint.plain(event.key_code_right) in with_right_grouping.list.move_right
	resolved_keymap.agents.toggle_grouping = one('f8')

	resolved_keymap.agents.stop = one('f9')
	expect_conflict(&resolved_keymap, 'rename', 'stop')

	resolved_keymap.agents.stop = one('f10')
	resolved_keymap.global.open_agents = one('ctrl-t')
	expect_conflict(&resolved_keymap, 'open_agents', 'open_transcript')

	resolved_keymap.global.open_agents = one('f12')
	resolved_keymap.agents.stop = one('ctrl-c')
	expect_conflict(&resolved_keymap, 'stop', 'fixed.interrupt_or_quit')

	// Rust guards this block with `#[cfg(unix)]`; the V tree only targets Unix hosts today.
	resolved_keymap.agents.stop = one('ctrl-z')
	assert expect_config_error(&resolved_keymap, 'ctrl-z must be rejected').contains('suspend')
	resolved_keymap.agents.stop = one('f10')
	resolved_keymap.global.open_agents = one('ctrl-z')
	assert expect_config_error(&resolved_keymap, 'ctrl-z must be rejected').contains('suspend')
	resolved_keymap.global.open_agents = one('f12')

	resolved_keymap.agents.stop = one('f10')
	resolved_keymap.agents.search = one('right')
	dashboard_priority := expect_runtime(&resolved_keymap, 'dashboard shortcuts take priority')
	assert dashboard_priority.agents.search == [key_hint.plain(event.key_code_right)]
	assert dashboard_priority.list.move_right == RuntimeKeymap.defaults().list.move_right

	resolved_keymap.agents.search = none
	resolved_keymap.agents.rename = none
	resolved_keymap.list.move_right = one('ctrl-r')
	list_shortcut := expect_runtime(&resolved_keymap, 'list shortcut remains usable')
	assert list_shortcut.agents.rename == [key_hint.ctrl(event.KeyCode.char_key(`r`))]

	resolved_keymap.agents.search = one('s')
	assert expect_config_error(&resolved_keymap, 'printable shortcut is reserved for input').contains('printable keys')

	resolved_keymap.agents.search = none
	resolved_keymap.agents.stop = one('backspace')
	assert expect_config_error(&resolved_keymap, 'backspace is reserved for task input').contains('backspace')

	// The Rust test also asserts the `ctrl-alt-@` AltGr rejections behind `#[cfg(windows)]`; the V
	// port of `key_hint.is_altgr` only covers the non-Windows definition so far.
	resolved_keymap.agents.stop = one('backspace f10')
	assert expect_config_error(&resolved_keymap, 'backspace is reserved for task input').contains('backspace')
}

fn test_agents_resume_default_yields_to_existing_custom_shortcuts() {
	for binding in ['ctrl-o', 'ctrl-o f6'] {
		mut resolved_keymap := types.TuiKeymap{}
		resolved_keymap.agents.search = one(binding)
		runtime := expect_runtime(&resolved_keymap, 'existing keymap remains valid')
		assert runtime.agents.resume.len == 0

		resolved_keymap.agents.resume = one('ctrl-o')
		assert !config_is_ok(&resolved_keymap)
	}
}

fn test_toggle_side_conversation_can_be_remapped_and_rejects_conflicts() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.toggle_side_conversation = one('f12')

	runtime := expect_runtime(&resolved_keymap, 'runtime keymap')
	assert runtime.app.toggle_side_conversation == [
		key_hint.plain(event.KeyCode.function_key(12)),
	]

	resolved_keymap.global.toggle_side_conversation = one('ctrl-l')
	expect_conflict(&resolved_keymap, 'clear_terminal', 'toggle_side_conversation')
}

fn test_toggle_side_conversation_default_yields_to_existing_configured_bindings() {
	for binding in ['ctrl-/', 'ctrl-7'] {
		mut resolved_keymap := types.TuiKeymap{}
		resolved_keymap.global.open_transcript = one(binding)

		runtime := expect_runtime(&resolved_keymap, 'existing keymap remains valid')

		assert runtime.app.open_transcript == [
			parse_keybinding(binding) or { panic('configured binding') },
		]
		assert runtime.app.toggle_side_conversation.len == 0
	}

	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.open_transcript = one('ctrl-/')
	resolved_keymap.global.copy = one('ctrl-7')

	runtime := expect_runtime(&resolved_keymap, 'distinct legacy bindings remain valid')
	assert runtime.app.toggle_side_conversation.len == 0
}

fn test_explicit_side_toggle_rejects_legacy_ctrl_slash_alias_conflicts() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.open_transcript = one('ctrl-7')
	resolved_keymap.global.toggle_side_conversation = one('ctrl-/')

	expect_conflict(&resolved_keymap, 'open_transcript', 'toggle_side_conversation')
}

fn test_rejects_main_bindings_that_collide_with_remaining_fixed_shortcuts() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.composer.submit = one('ctrl-v')

	expect_conflict(&resolved_keymap, 'composer.submit', 'fixed.paste_image')
}

fn test_interrupt_turn_allows_backtrack_escape_and_can_be_remapped_or_unbound() {
	mut resolved_keymap := types.TuiKeymap{}
	default_runtime := expect_runtime(&resolved_keymap, 'default keymap should parse')
	assert default_runtime.chat.interrupt_turn == [key_hint.plain(event.key_code_esc)]

	resolved_keymap.chat.interrupt_turn = one('f12')
	remapped := expect_runtime(&resolved_keymap, 'remapped keymap should parse')
	assert remapped.chat.interrupt_turn == [
		key_hint.plain(event.KeyCode.function_key(12)),
	]

	resolved_keymap.chat.interrupt_turn = many([])
	unbound := expect_runtime(&resolved_keymap, 'unbound keymap should parse')
	assert unbound.chat.interrupt_turn.len == 0
}

fn test_interrupt_turn_rejects_other_fixed_shortcuts() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.chat.interrupt_turn = one('ctrl-v')

	expect_conflict(&resolved_keymap, 'chat.interrupt_turn', 'fixed.paste_image')
}

fn test_interrupt_turn_rejects_request_user_input_question_navigation_bindings() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.chat.interrupt_turn = one('f12')
	resolved_keymap.list.move_right = one('f12')

	expect_conflict(&resolved_keymap, 'chat.interrupt_turn', 'list.move_right')
}

fn test_interrupt_turn_rejects_question_back_and_skip_bindings() {
	for entry in [['alt-down', 'chat.prompt_stack_back'], ['ctrl-]', 'chat.skip_question'],
		['ctrl-5', 'chat.skip_question'], ['ctrl-] x', 'chat.skip_question'],
		['ctrl-5 x', 'chat.skip_question']] {
		key := entry[0]
		action := entry[1]
		mut resolved_keymap := types.TuiKeymap{}
		resolved_keymap.chat.interrupt_turn = one(key)
		if key == 'alt-down' {
			resolved_keymap.chat.prompt_stack_back = one(key)
		} else {
			runtime := expect_runtime(&resolved_keymap, 'interrupt remap should resolve')
			assert runtime.chat.skip_question.len == 0
			resolved_keymap.chat.skip_question = one('ctrl-]')
		}
		expect_conflict(&resolved_keymap, 'chat.interrupt_turn', action)
	}
}

fn test_rejects_pager_bindings_that_collide_with_transcript_backtrack_keys() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.pager.close = one('left')

	expect_conflict(&resolved_keymap, 'close', 'fixed.transcript_edit_previous')
}

fn test_parses_function_keys_and_rejects_out_of_range_function_keys() {
	first := parse_keybinding('f1') or { panic('f1 should parse') }
	assert first.parts() == key_hint.KeyParts{
		code:      event.KeyCode.function_key(1)
		modifiers: event.key_modifiers_none
	}
	last := parse_keybinding('f24') or { panic('f24 should parse') }
	assert last.parts() == key_hint.KeyParts{
		code:      event.KeyCode.function_key(24)
		modifiers: event.key_modifiers_none
	}
	assert parse_keybinding('f25') == none
}

fn test_parses_all_named_non_character_keys() {
	cases := {
		'tab':       event.key_code_tab
		'backspace': event.key_code_backspace
		'esc':       event.key_code_esc
		'delete':    event.key_code_delete
		'up':        event.key_code_up
		'down':      event.key_code_down
		'left':      event.key_code_left
		'right':     event.key_code_right
		'home':      event.key_code_home
		'end':       event.key_code_end
		'page-up':   event.key_code_page_up
		'page-down': event.key_code_page_down
		'space':     event.KeyCode.char_key(` `)
		'minus':     event.KeyCode.char_key(`-`)
	}

	for spec, expected_key in cases {
		binding := parse_keybinding(spec) or { panic('failed to parse ${spec}') }
		assert binding.parts() == key_hint.KeyParts{
			code:      expected_key
			modifiers: event.key_modifiers_none
		}, 'failed to parse ${spec}'
	}
}

fn test_rejects_modifier_only_and_nonnumeric_function_key_specs() {
	assert parse_keybinding('ctrl') == none
	assert parse_keybinding('ff') == none
}

fn test_parses_minus_alias_and_legacy_literal_minus() {
	alias := parse_keybinding('alt-minus') or { panic('alt-minus should parse') }
	assert alias.parts() == key_hint.KeyParts{
		code:      event.KeyCode.char_key(`-`)
		modifiers: event.key_modifiers_alt
	}
	legacy := parse_keybinding('alt--') or { panic('alt-- should parse') }
	assert legacy.parts() == key_hint.KeyParts{
		code:      event.KeyCode.char_key(`-`)
		modifiers: event.key_modifiers_alt
	}
	bare := parse_keybinding('-') or { panic('- should parse') }
	assert bare.parts() == key_hint.KeyParts{
		code:      event.KeyCode.char_key(`-`)
		modifiers: event.key_modifiers_none
	}
}

fn test_explicit_empty_array_unbinds_action() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.composer.toggle_shortcuts = many([])
	runtime := expect_runtime(&resolved_keymap, 'config should parse')
	assert runtime.composer.toggle_shortcuts.len == 0
}

fn test_raw_output_toggle_defaults_to_alt_r() {
	runtime := RuntimeKeymap.defaults()
	assert runtime.app.toggle_raw_output == [
		key_hint.alt(event.KeyCode.char_key(`r`)),
	]
}

fn test_raw_output_toggle_can_be_remapped() {
	mut resolved_keymap := types.TuiKeymap{}
	resolved_keymap.global.toggle_raw_output = one('f12')

	runtime := expect_runtime(&resolved_keymap, 'config should parse')

	assert runtime.app.toggle_raw_output == [
		key_hint.plain(event.KeyCode.function_key(12)),
	]
}

fn test_default_editor_insert_newline_includes_current_aliases() {
	runtime := RuntimeKeymap.defaults()
	assert runtime.editor.insert_newline == [
		key_hint.ctrl(event.KeyCode.char_key(`j`)),
		key_hint.ctrl(event.KeyCode.char_key(`m`)),
		key_hint.plain(event.key_code_enter),
		key_hint.shift(event.key_code_enter),
		key_hint.alt(event.key_code_enter),
	]
}

fn test_default_editor_delete_forward_word_includes_alt_d() {
	runtime := RuntimeKeymap.defaults()
	assert key_hint.alt(event.KeyCode.char_key(`d`)) in runtime.editor.delete_forward_word
}

fn test_default_editor_deletion_includes_modified_backspace_delete_aliases() {
	runtime := RuntimeKeymap.defaults()

	assert key_hint.shift(event.key_code_backspace) in runtime.editor.delete_backward
	assert key_hint.shift(event.key_code_delete) in runtime.editor.delete_forward
	assert key_hint.ctrl(event.key_code_backspace) in runtime.editor.delete_backward_word
	assert key_hint.KeyBinding.new(event.key_code_backspace, event.key_modifiers_control.union(event.key_modifiers_shift)) in runtime.editor.delete_backward_word
	assert key_hint.ctrl(event.key_code_delete) in runtime.editor.delete_forward_word
	assert key_hint.KeyBinding.new(event.key_code_delete, event.key_modifiers_control.union(event.key_modifiers_shift)) in runtime.editor.delete_forward_word
}

fn test_default_composer_toggle_shortcuts_includes_shift_question_mark() {
	runtime := RuntimeKeymap.defaults()
	assert key_hint.shift(event.KeyCode.char_key(`?`)) in runtime.composer.toggle_shortcuts
}

fn test_default_approval_open_fullscreen_includes_ctrl_shift_a() {
	runtime := RuntimeKeymap.defaults()
	assert key_hint.KeyBinding.new(event.KeyCode.char_key(`a`), event.key_modifiers_control.union(event.key_modifiers_shift)) in runtime.approval.open_fullscreen
}

fn test_primary_binding_returns_first_or_none() {
	bindings := [
		key_hint.ctrl(event.KeyCode.char_key(`a`)),
		key_hint.shift(event.KeyCode.char_key(`b`)),
	]
	assert primary_binding(&bindings) or { panic('first binding') } == key_hint.ctrl(event.KeyCode.char_key(`a`))
	empty := []key_hint.KeyBinding{}
	assert primary_binding(&empty) == none
}

fn test_defaults_pass_conflict_validation() {
	defaults := RuntimeKeymap.defaults()
	defaults.validate_conflicts() or { panic('default keymap should be conflict free') }
}

// Exercises `keymap_ownership_harness`, which AGENTS.md requires for the `-ownership` build. Running
// it here as well keeps the borrowed-call sequence covered by the ordinary `v test` run.
fn test_keymap_ownership_harness_reuses_borrowed_owners() {
	assert keymap_ownership_harness() == 3
}

// Regression coverage for conflict diagnostics and validation pass ordering.
//
// Translated from `tui/src/keymap/conflict_tests.rs`, which Rust attaches to `keymap.rs` with
// `#[cfg(test)] #[path = "keymap/conflict_tests.rs"]`. V compiles each `_test.v` file on its own,
// so the attached module lives here rather than in a sibling file that could not reach these
// shared helpers.

// One `(context, first, second)` row of the conflicting-context table.
struct ConflictingContext {
	context string
	first   string
	second  string
}

fn test_conflicting_contexts_report_the_first_conflict_in_validation_order() {
	contexts := [
		ConflictingContext{
			context: 'editor'
			first:   'insert_newline'
			second:  'yank'
		},
		ConflictingContext{
			context: 'vim_normal'
			first:   'enter_insert'
			second:  'cancel_operator'
		},
		ConflictingContext{
			context: 'vim_operator'
			first:   'delete_line'
			second:  'cancel'
		},
		ConflictingContext{
			context: 'vim_text_object'
			first:   'word'
			second:  'cancel'
		},
		ConflictingContext{
			context: 'pager'
			first:   'scroll_up'
			second:  'close_transcript'
		},
		ConflictingContext{
			context: 'list'
			first:   'move_up'
			second:  'cancel'
		},
		ConflictingContext{
			context: 'agents'
			first:   'search'
			second:  'toggle_grouping'
		},
		ConflictingContext{
			context: 'approval'
			first:   'open_fullscreen'
			second:  'cancel'
		},
	]
	// Rust accumulates a `serde_json::Map` of every context and removes one entry per iteration.
	// The V config stub has no deserializer, so the same shrinking fixture is rebuilt from the
	// still-present rows through `set_configured_binding`.
	mut remaining := contexts.clone()

	for row in contexts {
		mut resolved_keymap := types.TuiKeymap{}
		for present in remaining {
			set_configured_binding(mut resolved_keymap, present.context, present.first, one('f12'))
			set_configured_binding(mut resolved_keymap, present.context, present.second, one('f12'))
		}
		err_msg := expect_config_error(&resolved_keymap, 'expected binding conflict')
		assert err_msg == 'Ambiguous `tui.keymap.${row.context}` bindings: `${row.first}` and `${row.second}` use the same key. Set unique keys in `~/.codex/config.toml` and retry. See the Codex keymap documentation for supported actions and examples.'
		remaining = remaining.filter(it.context != row.context)
	}
}
