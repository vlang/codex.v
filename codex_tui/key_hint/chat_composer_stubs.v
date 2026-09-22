module key_hint

import crossterm.event

// STUB: crate::key_hint::KeyBinding.
pub struct KeyBinding {
pub:
	code      event.KeyCode
	modifiers event.KeyModifiers
}

// STUB: crate::key_hint::ShortcutHint payload discriminants.
pub enum ShortcutHintKind {
	single
	chord
}

// STUB: crate::key_hint::ShortcutHint. Rust uses a payload enum; this explicit tagged value keeps
// the Single and Chord payloads disjoint without relying on compiler-fragile optional sum types.
pub struct ShortcutHint {
pub:
	kind       ShortcutHintKind
	single     KeyBinding
	prefix     KeyBinding
	completion KeyBinding
}

// STUB: crate::key_hint::ShortcutHint::Single.
pub fn ShortcutHint.single(binding KeyBinding) ShortcutHint {
	return ShortcutHint{ kind: .single, single: binding }
}

// STUB: crate::key_hint::ShortcutHint::Chord.
pub fn ShortcutHint.chord(prefix KeyBinding, completion KeyBinding) ShortcutHint {
	return ShortcutHint{ kind: .chord, prefix: prefix, completion: completion }
}

// STUB: crate::key_hint::ShortcutHint::display_label.
pub fn (hint ShortcutHint) display_label() string {
	return if hint.kind == .single {
		hint.single.display_label()
	} else {
		'${hint.prefix.display_label()} ${hint.completion.display_label()}'
	}
}

// STUB: crate::key_hint::ShortcutHint::is_press.
pub fn (hint ShortcutHint) is_press(input event.KeyEvent) bool {
	return hint.kind == .single && hint.single.is_press(input)
}

// STUB: crate::key_hint::plain.
pub fn plain(code event.KeyCode) KeyBinding {
	return KeyBinding{ code: code }
}

// STUB: crate::key_hint::shift.
pub fn shift(code event.KeyCode) KeyBinding {
	return KeyBinding{ code: code, modifiers: event.KeyModifiers{ shift: true } }
}

// STUB: crate::key_hint::ctrl.
pub fn ctrl(code event.KeyCode) KeyBinding {
	return KeyBinding{ code: code, modifiers: event.KeyModifiers{ control: true } }
}

// STUB: crate::key_hint::alt.
pub fn alt(code event.KeyCode) KeyBinding {
	return KeyBinding{ code: code, modifiers: event.KeyModifiers{ alt: true } }
}

// STUB: crate::key_hint::KeyBinding::is_press.
pub fn (binding &KeyBinding) is_press(input event.KeyEvent) bool {
	return normalize_key_parts(binding.code, binding.modifiers) == normalize_key_parts(input.code, input.modifiers) && (input.kind == .press || input.kind == .repeat)
}

// STUB: crate::key_hint::KeyBinding::display_label.
pub fn (binding KeyBinding) display_label() string {
	mut prefix := ''
	if binding.modifiers.control {
		prefix += 'ctrl + '
	}
	if binding.modifiers.alt {
		prefix += '⌥ + '
	}
	if binding.modifiers.shift {
		prefix += 'shift + '
	}
	key := match binding.code.kind {
		.enter { 'enter' }
		.tab { 'tab' }
		.up { '↑' }
		.down { '↓' }
		.left { '←' }
		.right { '→' }
		.char_key { binding.code.ch.str().to_lower() }
		else { binding.code.kind.str() }
	}
	return prefix + key
}

// STUB: crate::key_hint::KeyBindingListExt::is_pressed.
pub fn bindings_are_pressed(bindings &[]KeyBinding, input event.KeyEvent) bool {
	for binding in *bindings {
		if binding.is_press(input) {
			return true
		}
	}
	return false
}
