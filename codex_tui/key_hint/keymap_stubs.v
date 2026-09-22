module key_hint

import crossterm.event

// STUB: the `(KeyCode, KeyModifiers)` tuple returned by crate::key_hint::KeyBinding::parts and
// ::normalized_parts. V has no comparable anonymous tuple type, so the pair is named here to keep
// the `a.parts() == b.parts()` comparisons and `(KeyCode::Char(_), modifiers)` matches of the Rust
// source expressible at the original call sites.
pub struct KeyParts {
pub:
	code      event.KeyCode
	modifiers event.KeyModifiers
}

// STUB: crate::key_hint::KeyBinding::new.
pub fn KeyBinding.new(key event.KeyCode, modifiers event.KeyModifiers) KeyBinding {
	return KeyBinding{
		code:      key
		modifiers: modifiers
	}
}

// STUB: crate::key_hint::KeyBinding::from_event.
pub fn KeyBinding.from_event(input event.KeyEvent) KeyBinding {
	parts := normalize_key_parts(input.code, input.modifiers)
	return KeyBinding{
		code:      parts.code
		modifiers: parts.modifiers
	}
}

// STUB: crate::key_hint::KeyBinding::parts.
pub fn (binding &KeyBinding) parts() KeyParts {
	return KeyParts{
		code:      binding.code
		modifiers: binding.modifiers
	}
}

// STUB: crate::key_hint::KeyBinding::normalized_parts.
// Legacy Ctrl+] is reported as Ctrl+5; keep matching and conflicts consistent.
pub fn (binding &KeyBinding) normalized_parts() KeyParts {
	parts := binding.parts()
	if parts.code.kind == .char_key && parts.code.ch == `5`
		&& parts.modifiers == event.key_modifiers_control {
		return ctrl(event.KeyCode.char_key(`]`)).parts()
	}
	return parts
}

// STUB: crate::key_hint::normalize_key_parts.
pub fn normalize_key_parts(key event.KeyCode, modifiers event.KeyModifiers) KeyParts {
	if key.kind != .char_key {
		return KeyParts{
			code:      key
			modifiers: modifiers
		}
	}
	ch := key.ch
	if modifiers.is_empty() {
		if ctrl_char := c0_control_char_to_ctrl_char(ch) {
			return normalize_key_parts(event.KeyCode.char_key(ctrl_char), event.key_modifiers_control)
		}
	}
	if ch >= `A` && ch <= `Z` {
		mut with_shift := modifiers
		with_shift.insert(event.key_modifiers_shift)
		return KeyParts{
			code:      event.KeyCode.char_key(rune(int(ch) - int(`A`) + int(`a`)))
			modifiers: with_shift
		}
	}
	return KeyBinding.new(key, modifiers).normalized_parts()
}

// STUB: crate::key_hint::c0_control_char_to_ctrl_char.
fn c0_control_char_to_ctrl_char(ch rune) ?rune {
	code := u32(ch)
	if code == 0x00 {
		return ` `
	}
	if code >= 0x01 && code <= 0x1a {
		return rune(code - 0x01 + u32(`a`))
	}
	if code >= 0x1c && code <= 0x1f {
		return rune(code - 0x1c + u32(`4`))
	}
	return none
}

// STUB: crate::key_hint::ctrl_alt.
pub fn ctrl_alt(key event.KeyCode) KeyBinding {
	return KeyBinding.new(key, event.key_modifiers_control.union(event.key_modifiers_alt))
}

// STUB: crate::key_hint::is_plain_text_key_event.
//
// Returns whether an event should be treated as literal text input.
//
// Searchable pickers use this to avoid stealing plain printable characters for
// navigation when the same character might be a valid query. For example, a
// list may bind `j` and `k` for movement, but a searchable list must let
// plain `j` update the query while still allowing `Ctrl+J` to move. Calling
// this after normalizing keybindings would blur that distinction and cause
// printable search input to disappear.
pub fn is_plain_text_key_event(input event.KeyEvent) bool {
	if input.code.kind != .char_key {
		return false
	}
	ch := input.code.ch
	is_ascii_control := u32(ch) < 0x20 || u32(ch) == 0x7f
	return !is_ascii_control && !input.modifiers.contains(event.key_modifiers_control)
		&& !input.modifiers.contains(event.key_modifiers_alt)
}

// STUB: crate::key_hint::has_ctrl_or_alt.
pub fn has_ctrl_or_alt(mods event.KeyModifiers) bool {
	return (mods.contains(event.key_modifiers_control) || mods.contains(event.key_modifiers_alt))
		&& !is_altgr(mods)
}

// STUB: crate::key_hint::is_altgr. The Rust source treats ALT and CONTROL together as AltGr only
// on Windows and returns false everywhere else.
pub fn is_altgr(mods event.KeyModifiers) bool {
	$if windows {
		return mods.contains(event.key_modifiers_control)
			&& mods.contains(event.key_modifiers_alt)
	}
	return false
}

// STUB: crate::key_hint::ShortcutHint::from(KeyBinding).
pub fn ShortcutHint.from_binding(binding KeyBinding) ShortcutHint {
	return ShortcutHint.single(binding)
}
