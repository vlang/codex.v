module popup_consts

import codex_config.types
import codex_tui.key_hint
import codex_tui.keymap
import crossterm.event
import ratatui.style
import ratatui.text

fn test_standard_popup_hint_line_preserves_styled_shortcuts() {
	assert max_popup_rows == usize(8)
	assert standard_popup_hint_line() == text.Line{
		spans: [
			text.Span{ text: 'Press ' },
			text.Span{ text: 'enter', style: style.Style.default().dim() },
			text.Span{ text: ' to confirm or ' },
			text.Span{ text: 'esc', style: style.Style.default().dim() },
			text.Span{ text: ' to go back' },
		]
	}
}

fn test_accept_and_cancel_hints_preserve_custom_labels() {
	accept := key_hint.ShortcutHint.single(key_hint.ctrl(event.KeyCode.char_key(`y`)))
	cancel := key_hint.ShortcutHint.single(key_hint.plain(event.key_code_esc))
	accept_label := 'to save'
	cancel_label := 'to abandon changes'
	assert accept_cancel_hint_line(accept, &accept_label, cancel, &cancel_label) == text.Line{
		spans: [
			text.Span{ text: 'Press ' },
			text.Span{ text: 'ctrl + y', style: style.Style.default().dim() },
			text.Span{ text: ' to save or ' },
			text.Span{ text: 'esc', style: style.Style.default().dim() },
			text.Span{ text: ' to abandon changes' },
		]
	}
}

fn test_accept_only_hint_omits_cancel_label() {
	accept := key_hint.ShortcutHint.single(key_hint.plain(event.key_code_enter))
	accept_label := 'to select'
	cancel_label := 'unused'
	assert accept_cancel_hint_line(accept, &accept_label, none, &cancel_label) == text.Line{
		spans: [
			text.Span{ text: 'Press ' },
			text.Span{ text: 'enter', style: style.Style.default().dim() },
			text.Span{ text: ' to select' },
		]
	}
}

fn test_cancel_only_hint_omits_accept_label() {
	cancel := key_hint.ShortcutHint.single(key_hint.plain(event.key_code_esc))
	accept_label := 'unused'
	cancel_label := 'to dismiss'
	assert accept_cancel_hint_line(none, &accept_label, cancel, &cancel_label) == text.Line{
		spans: [
			text.Span{ text: 'Press ' },
			text.Span{ text: 'esc', style: style.Style.default().dim() },
			text.Span{ text: ' to dismiss' },
		]
	}
}

fn test_absent_hints_produce_empty_line() {
	accept_label := 'unused accept'
	cancel_label := 'unused cancel'
	assert accept_cancel_hint_line(none, &accept_label, none, &cancel_label) == text.Line{
		spans: [text.Span{ text: '' }]
	}
}

fn test_standard_popup_hint_line_uses_primary_bindings_and_borrows_keymap() {
	list_keymap := keymap.ListKeymap{
		accept: [key_hint.ctrl(event.KeyCode.char_key(`y`)), key_hint.plain(event.key_code_enter)]
		cancel: [key_hint.ctrl(event.KeyCode.char_key(`q`))]
	}
	assert standard_popup_hint_line_for_keymap(&list_keymap) == text.Line{
		spans: [
			text.Span{ text: 'Press ' },
			text.Span{ text: 'ctrl + y', style: style.Style.default().dim() },
			text.Span{ text: ' to confirm or ' },
			text.Span{ text: 'ctrl + q', style: style.Style.default().dim() },
			text.Span{ text: ' to go back' },
		]
	}
	assert standard_popup_hint_line_for_keymap(&list_keymap).spans.len == 5
	assert list_keymap.accept.len == 2
	assert list_keymap.cancel[0].is_press(event.KeyEvent.new(event.KeyCode.char_key(`q`),
		event.key_modifiers_control))
}

fn test_standard_popup_hint_line_uses_configured_chords_and_explicit_unbinding() {
	configuration := types.TuiKeymap{
		list: types.TuiListKeymap{
			accept: types.KeybindingsSpec.from_one(types.KeybindingSpec{ value: 'ctrl-x ctrl-y' })
			cancel: types.KeybindingsSpec.from_many([]types.KeybindingSpec{})
		}
	}
	runtime := keymap.RuntimeKeymap.from_config(&configuration) or { panic(err) }
	assert standard_popup_hint_line_for_keymap(&runtime.list) == text.Line{
		spans: [
			text.Span{ text: 'Press ' },
			text.Span{ text: 'ctrl + x ctrl + y', style: style.Style.default().dim() },
			text.Span{ text: ' to confirm' },
		]
	}
	assert runtime.list.primary_hint(.cancel) == none
}

fn test_borrowed_labels_and_copy_hints_remain_reusable() {
	mut accept_label := 'to retain 日本語'
	mut cancel_label := 'to return 🐈'
	$if ownership ? {
		accept_label = 'to retain 日本語'.to_owned()
		cancel_label = 'to return 🐈'.to_owned()
	}
	accept := key_hint.ShortcutHint.chord(key_hint.ctrl(event.KeyCode.char_key(`x`)),
		key_hint.plain(event.key_code_enter))
	cancel := key_hint.ShortcutHint.single(key_hint.plain(event.key_code_esc))
	first := accept_cancel_hint_line(accept, &accept_label, cancel, &cancel_label)
	second := accept_cancel_hint_line(accept, &accept_label, cancel, &cancel_label)
	assert first == second
	assert first.spans[1].text == 'ctrl + x enter'
	assert first.spans[2].text == ' to retain 日本語 or '
	assert first.spans[4].text == ' to return 🐈'
	assert accept_label == 'to retain 日本語'
	assert cancel_label == 'to return 🐈'
	assert accept.display_label() == 'ctrl + x enter'
	assert cancel.display_label() == 'esc'
}
