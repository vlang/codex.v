module keymap

import codex_config.types
import codex_tui.key_hint
import crossterm.event
import tokio.time as tokio_time

fn chord_binding(spec string) types.KeybindingsSpec {
	return types.KeybindingsSpec.from_one(types.KeybindingSpec{
		value: spec
	})
}

fn chord_bindings(specs []string) types.KeybindingsSpec {
	mut entries := []types.KeybindingSpec{cap: specs.len}
	for spec in specs {
		entries << types.KeybindingSpec{
			value: spec
		}
	}
	return types.KeybindingsSpec.from_many(entries)
}

fn expect_chord_runtime(config &types.TuiKeymap, expectation string) RuntimeKeymap {
	return RuntimeKeymap.from_config(config) or { panic('${expectation}: ${err.msg()}') }
}

fn expect_chord_error(config &types.TuiKeymap, expectation string) string {
	RuntimeKeymap.from_config(config) or { return err.msg() }
	panic(expectation)
}

fn chord_key_event(binding key_hint.KeyBinding) event.KeyEvent {
	parts := binding.parts()
	return event.KeyEvent.new(parts.code, parts.modifiers)
}

struct ChordSpecExpectation {
	context  string
	action   string
	expected []string
}

fn test_rejects_fixed_resume_picker_keys_inside_list_chords() {
	for entry in [
		['ctrl-c home', 'cancel'],
		['ctrl-t home', 'resume_picker.toggle_transcript'],
		['ctrl-e home', 'resume_picker.toggle_expansion'],
		['ctrl-o home', 'resume_picker.toggle_density'],
	] {
		mut config := types.TuiKeymap{}
		config.list.jump_top = chord_binding(entry[0])

		error_message := expect_chord_error(&config, 'fixed picker actions must remain available')

		assert error_message.contains(entry[1]), error_message
	}
}

fn test_rejects_ctrl_c_inside_approval_chords() {
	mut config := types.TuiKeymap{}
	config.approval.approve = chord_binding('ctrl-x ctrl-c')

	error_message := expect_chord_error(&config, 'Ctrl+C must continue cancelling approvals')

	assert error_message.contains('cancel'), error_message
}

fn test_resolves_chords_for_actions_in_different_contexts() {
	mut config := types.TuiKeymap{}
	config.global.open_transcript = chord_bindings(['ctrl-t', 'ctrl-x ctrl-t'])
	config.composer.submit = chord_binding('ctrl-x enter')
	config.list.jump_top = chord_binding('ctrl-x home')

	actual := expect_chord_runtime(&config, 'valid chord keymap')

	assert user_bindings(actual.app.open_transcript.clone()) == [key_hint.ctrl(event.KeyCode.char_key(`t`))]
	for expectation in [
		ChordSpecExpectation{
			context:  'global'
			action:   'open_transcript'
			expected: ['ctrl-t', 'ctrl-x ctrl-t']
		},
		ChordSpecExpectation{
			context:  'composer'
			action:   'submit'
			expected: ['ctrl-x enter']
		},
		ChordSpecExpectation{
			context:  'list'
			action:   'jump_top'
			expected: ['ctrl-x home']
		},
	] {
		action := keymap_action_id(expectation.context, expectation.action) or {
			panic('known action')
		}
		configured := actual.chords.configured_specs(&action) or {
			panic('configured specs')
		}
		assert configured == expectation.expected
	}
}

fn assert_default_vim_jump(runtime &RuntimeKeymap, context KeymapContext, action string, target &[]key_hint.KeyBinding) {
	action_id := keymap_action_id(context.config_name(), action.clone()) or {
		panic('known Vim action')
	}
	mut found := false
	for configured in runtime.chords.bindings {
		if configured.action == action_id
			&& configured.chord.prefix == key_hint.plain(event.KeyCode.char_key(`g`))
			&& configured.chord.completion == key_hint.plain(event.KeyCode.char_key(`g`)) {
			found = true
			break
		}
	}
	assert found
	hint := runtime.primary_hint(context, action) or { panic('Vim jump hint') }
	assert hint.kind == .chord

	g := chord_key_event(key_hint.plain(event.KeyCode.char_key(`g`)))
	mut matcher := KeyChordMatcher{}
	contexts := KeymapContextSet.new(context)
	now := tokio_time.Instant.from_nanos(1_000_000)
	assert matcher.advance(g, &runtime.chords, contexts, now).kind == .pending
	completed := matcher.advance(g, &runtime.chords, contexts, now)
	assert completed.kind == .completed
	assert key_hint.bindings_are_pressed(target, completed.completed)
}

fn test_default_vim_jump_top_uses_contextual_gg_chords() {
	runtime := RuntimeKeymap.defaults()

	assert_default_vim_jump(&runtime, .vim_normal, 'jump_top', &runtime.vim_normal.jump_top)
	assert_default_vim_jump(&runtime, .vim_operator, 'motion_jump_top', &runtime.vim_operator.motion_jump_top)
}

fn test_default_vim_jump_chords_yield_to_configured_singles_and_chords() {
	mut config := types.TuiKeymap{}
	config.vim_normal.move_line_start = chord_binding('g g')
	config.vim_operator.motion_line_start = chord_binding('g')

	runtime := expect_chord_runtime(&config, 'configured legacy bindings win')

	assert runtime.vim_normal.jump_top.len == 0
	assert runtime.vim_operator.motion_jump_top.len == 0
	assert key_hint.bindings_are_pressed(&runtime.vim_operator.motion_line_start, chord_key_event(key_hint.plain(event.KeyCode.char_key(`g`))))
}

fn test_vim_jump_top_supports_single_and_custom_chord_remaps() {
	mut config := types.TuiKeymap{}
	config.vim_normal.jump_top = chord_binding('home')
	config.vim_operator.motion_jump_top = chord_binding('ctrl-x g')

	runtime := expect_chord_runtime(&config, 'custom Vim jumps are valid')

	assert key_hint.bindings_are_pressed(&runtime.vim_normal.jump_top, event.KeyEvent.new(event.key_code_home,
		event.key_modifiers_none))
	action := keymap_action_id('vim_operator', 'motion_jump_top') or { panic('known Vim action') }
	mut found := false
	for configured in runtime.chords.bindings {
		if configured.action == action
			&& configured.chord.prefix == key_hint.ctrl(event.KeyCode.char_key(`x`))
			&& configured.chord.completion == key_hint.plain(event.KeyCode.char_key(`g`)) {
			found = true
			break
		}
	}
	assert found
}

fn test_composer_chord_inherits_global_fallback() {
	mut config := types.TuiKeymap{}
	config.global.submit = chord_binding('ctrl-x enter')

	actual := expect_chord_runtime(&config, 'valid global fallback chord')
	action := keymap_action_id('composer', 'submit') or { panic('known action') }

	configured := actual.chords.configured_specs(&action) or { panic('configured specs') }
	assert configured == ['ctrl-x enter']
}

fn test_allows_shared_prefixes_with_distinct_completions() {
	mut config := types.TuiKeymap{}
	config.global.open_transcript = chord_binding('ctrl-x ctrl-t')
	config.global.copy = chord_binding('ctrl-x ctrl-o')

	expect_chord_runtime(&config, 'prefix trie can branch on the second stroke')
}

fn test_allows_plain_prefixes_in_vim_and_repeated_chords_in_all_contexts() {
	mut config := types.TuiKeymap{}
	config.vim_normal.move_line_start = chord_binding('g g')
	config.vim_operator.motion_line_start = chord_binding('g g')
	config.global.open_transcript = chord_binding('ctrl-t ctrl-t')

	expect_chord_runtime(&config, 'Vim owns printable prefixes and all contexts support repeated chords')
}

fn test_rejects_plain_printable_prefixes_outside_vim() {
	mut config := types.TuiKeymap{}
	config.composer.submit = chord_binding('x enter')

	error_message := expect_chord_error(&config, 'typing must not start a chord')

	assert error_message.contains('outside Vim'), error_message
	assert error_message.contains('ordinary text input'), error_message
}

fn test_rejects_prefixes_that_shadow_overlapping_single_bindings() {
	mut config := types.TuiKeymap{}
	config.global.open_transcript = chord_binding('ctrl-k ctrl-t')

	error_message := expect_chord_error(&config, 'ctrl-k already edits text')

	assert error_message.contains('editor.kill_line_end'), error_message
	assert error_message.contains('ctrl-k ctrl-t'), error_message
}

fn test_permits_the_same_chord_in_non_overlapping_contexts() {
	mut config := types.TuiKeymap{}
	config.editor.move_line_start = chord_binding('ctrl-x home')
	config.list.jump_top = chord_binding('ctrl-x home')

	expect_chord_runtime(&config, 'editor and list contexts are never active together')
}

fn test_rejects_duplicate_chords_in_overlapping_contexts() {
	mut config := types.TuiKeymap{}
	config.global.open_transcript = chord_binding('ctrl-x ctrl-t')
	config.composer.submit = chord_binding('ctrl-x ctrl-t')

	error_message := expect_chord_error(&config, 'one active chord must identify one action')

	assert error_message.contains('global.open_transcript'), error_message
	assert error_message.contains('composer.submit'), error_message
}

fn test_rejects_duplicate_chat_and_list_chords_used_by_request_user_input() {
	mut config := types.TuiKeymap{}
	config.chat.interrupt_turn = chord_binding('ctrl-x home')
	config.list.jump_top = chord_binding('ctrl-x home')

	error_message := expect_chord_error(&config, 'request input activates both contexts')

	assert error_message.contains('chat.interrupt_turn'), error_message
	assert error_message.contains('list.jump_top'), error_message
}

fn test_normalizes_ctrl_slash_terminal_aliases() {
	mut config := types.TuiKeymap{}
	config.global.open_transcript = chord_binding('ctrl-7 ctrl-t')

	error_message := expect_chord_error(&config, 'Ctrl-7 must remain the Ctrl-/ side-conversation alias')

	assert error_message.contains('global.toggle_side_conversation'), error_message
}

fn test_rejects_alias_equivalent_duplicate_chords() {
	mut config := types.TuiKeymap{}
	config.global.open_transcript = chord_binding('ctrl-x ctrl-/')
	config.global.copy = chord_binding('ctrl-x ctrl-7')
	config.global.toggle_side_conversation = types.KeybindingsSpec.from_many([]types.KeybindingSpec{})

	error_message := expect_chord_error(&config, 'aliases must identify one action')

	assert error_message.contains('global.open_transcript'), error_message
	assert error_message.contains('global.copy'), error_message
}

fn test_rejects_plain_escape_inside_a_chord() {
	mut config := types.TuiKeymap{}
	config.list.cancel = chord_binding('ctrl-x esc')

	error_message := expect_chord_error(&config, 'Esc cancels pending chords')

	assert error_message.contains('reserved for cancelling'), error_message
}

fn test_rejects_reserved_interrupt_keys_inside_a_main_chord() {
	mut config := types.TuiKeymap{}
	config.global.open_transcript = chord_binding('ctrl-x ctrl-c')

	error_message := expect_chord_error(&config, 'ctrl-c must remain available')

	assert error_message.contains('fixed.interrupt_or_quit'), error_message
}

fn test_rejects_unix_suspend_key_in_any_chord_stroke() {
	$if !windows {
		for chord in ['ctrl-z ctrl-t', 'ctrl-x ctrl-z'] {
			mut config := types.TuiKeymap{}
			config.list.jump_top = chord_binding(chord)

			error_message := expect_chord_error(&config, 'the Unix suspend key must not be consumed')

			assert error_message.contains('suspending'), error_message
		}
	}
}

fn test_rejects_windows_altgr_prefixes_outside_vim() {
	$if windows {
		mut config := types.TuiKeymap{}
		config.composer.submit = chord_binding('ctrl-alt-x enter')

		error_message := expect_chord_error(&config, 'AltGr may be ordinary Windows text input')

		assert error_message.contains('AltGr'), error_message
	}
}

fn test_dispatch_tokens_are_unique_and_cover_the_action_inventory() {
	mut tokens := []key_hint.KeyBinding{}
	actions := keymap_action_ids()

	for action in actions {
		token := dispatch_binding(&action) or { panic('action inventory must fit token band') }
		assert token !in tokens, 'duplicate token for ${action.config_path()}'
		tokens << token
	}

	assert tokens.len == actions.len
}

fn test_physical_dispatch_tokens_do_not_clear_pending_chords() {
	mut config := types.TuiKeymap{}
	config.global.open_transcript = chord_binding('ctrl-x ctrl-t')
	resolved_keymap := expect_chord_runtime(&config, 'valid chord keymap')
	contexts := KeymapContextSet.new(.global)
	now := tokio_time.Instant.from_nanos(1_000_000)
	mut matcher := KeyChordMatcher{}

	assert matcher.advance(chord_key_event(key_hint.ctrl(event.KeyCode.char_key(`x`))), &resolved_keymap.chords,
		contexts, now).kind == .pending

	action := keymap_action_id('global', 'open_transcript') or { panic('known keymap action') }
	token := dispatch_binding(&action) or { panic('internal dispatch token') }
	assert matcher.advance(chord_key_event(token), &resolved_keymap.chords, contexts, now).kind == .ignored
	assert matcher.is_pending()
	assert matcher.advance(chord_key_event(key_hint.ctrl(event.KeyCode.char_key(`t`))), &resolved_keymap.chords,
		contexts, now).kind == .completed
}

fn assert_matching_chord(runtime &RuntimeKeymap, context KeymapContext, prefix event.KeyEvent, completion event.KeyEvent, target &[]key_hint.KeyBinding, other &[]key_hint.KeyBinding, now tokio_time.Instant) {
	mut matcher := KeyChordMatcher{}
	contexts := KeymapContextSet.new(context)
	assert matcher.advance(prefix, &runtime.chords, contexts, now).kind == .pending
	completed := matcher.advance(completion, &runtime.chords, contexts, now)
	assert completed.kind == .completed
	assert key_hint.bindings_are_pressed(target, completed.completed)
	assert !key_hint.bindings_are_pressed(other, completed.completed)
}

fn test_matching_chords_dispatches_the_active_context_action() {
	mut config := types.TuiKeymap{}
	config.global.open_transcript = chord_binding('ctrl-t ctrl-t')
	config.editor.move_line_start = chord_binding('ctrl-x home')
	config.list.jump_top = chord_binding('ctrl-x home')
	runtime := expect_chord_runtime(&config, 'non-overlapping chord contexts')
	now := tokio_time.Instant.from_nanos(1_000_000)

	assert_matching_chord(&runtime, .global, chord_key_event(key_hint.ctrl(event.KeyCode.char_key(`t`))),
		chord_key_event(key_hint.ctrl(event.KeyCode.char_key(`t`))), &runtime.app.open_transcript,
		&runtime.app.copy, now)
	assert_matching_chord(&runtime, .editor, chord_key_event(key_hint.ctrl(event.KeyCode.char_key(`x`))),
		event.KeyEvent.new(event.key_code_home, event.key_modifiers_none), &runtime.editor.move_line_start,
		&runtime.list.jump_top, now)
	assert_matching_chord(&runtime, .list, chord_key_event(key_hint.ctrl(event.KeyCode.char_key(`x`))),
		event.KeyEvent.new(event.key_code_home, event.key_modifiers_none), &runtime.list.jump_top,
		&runtime.editor.move_line_start, now)
}

fn test_matcher_cancels_on_escape_context_change_and_timeout() {
	mut config := types.TuiKeymap{}
	config.list.jump_top = chord_binding('ctrl-x ctrl-t')
	runtime := expect_chord_runtime(&config, 'valid list chord')
	list := KeymapContextSet.new(.list)
	pager := KeymapContextSet.new(.pager)
	prefix := chord_key_event(key_hint.ctrl(event.KeyCode.char_key(`x`)))
	now := tokio_time.Instant.from_nanos(1_000_000)

	mut matcher := KeyChordMatcher{}
	assert matcher.advance(prefix, &runtime.chords, list, now).kind == .pending
	assert matcher.advance(event.KeyEvent.new(event.key_code_esc, event.key_modifiers_none), &runtime.chords,
		list, now).kind == .cancelled

	assert matcher.advance(prefix, &runtime.chords, list, now).kind == .pending
	assert matcher.expire(pager, now)

	assert matcher.advance(prefix, &runtime.chords, list, now).kind == .pending
	assert matcher.expire(list, tokio_time.Instant.from_nanos(now.nanos + key_chord_timeout))
}
