module key_hint

import crossterm.event
import ratatui.text as rat_text

// Key binding primitives and input matching for the TUI.
//
// This module provides `KeyBinding`, the runtime representation of a single
// keybinding (key code + modifier set), along with matching logic that handles
// cross-terminal inconsistencies in how shifted letters and raw C0 control
// characters are reported.
//
// List and picker code should match navigation through these helpers instead
// of comparing `KeyEvent` values directly. The matcher owns compatibility for
// terminals that report control chords as C0 characters, while
// `is_plain_text_key_event` gives searchable pickers a shared boundary between
// text input and navigation commands.
//
// It also supplies rendering helpers that convert bindings into styled
// `ratatui.text.Span` values for UI hint display.

const ctrl_prefix = 'ctrl + '
const shift_prefix = 'shift + '

// One concrete key event that can trigger a TUI action.
//
// Matching via `is_press` handles exact equality plus compatibility fallbacks
// for terminals that report uppercase letters without SHIFT and Ctrl keys as
// raw C0 control characters. This means a binding defined as `shift-a` will
// match either `Shift+a` or plain `A`, and `ctrl-j` will match raw LF.
//
// This does not model multi-key chords or partial matches; callers that need
// sequences must keep that state outside this type.
pub struct KeyBinding {
pub:
	code      event.KeyCode
	modifiers event.KeyModifiers
}

// V has no comparable anonymous tuple type for Rust's `(KeyCode, KeyModifiers)`, so the pair is
// named to keep comparisons and destructuring explicit at call sites.
pub struct KeyParts {
pub:
	code      event.KeyCode
	modifiers event.KeyModifiers
}

// A user-visible shortcut made from one key or a two-key chord.
// Rust uses a payload enum; this explicit tagged representation keeps the payloads disjoint in V.
pub enum ShortcutHintKind {
	single
	chord
}

pub struct ShortcutHint {
pub:
	kind       ShortcutHintKind
	single     KeyBinding
	prefix     KeyBinding
	completion KeyBinding
}

pub fn ShortcutHint.single(binding KeyBinding) ShortcutHint {
	return ShortcutHint{
		kind:   .single
		single: binding
	}
}

pub fn ShortcutHint.chord(prefix KeyBinding, completion KeyBinding) ShortcutHint {
	return ShortcutHint{
		kind:       .chord
		prefix:     prefix
		completion: completion
	}
}

pub fn (hint ShortcutHint) display_label() string {
	return match hint.kind {
		.single { hint.single.display_label() }
		.chord { '${hint.prefix.display_label()} ${hint.completion.display_label()}' }
	}
}

pub fn (hint ShortcutHint) is_press(input event.KeyEvent) bool {
	return hint.kind == .single && hint.single.is_press(input)
}

// Equivalent to Rust's `From<KeyBinding> for ShortcutHint` implementation.
pub fn ShortcutHint.from_binding(binding KeyBinding) ShortcutHint {
	return ShortcutHint.single(binding)
}

pub fn KeyBinding.new(key event.KeyCode, modifiers event.KeyModifiers) KeyBinding {
	return KeyBinding{
		code:      key
		modifiers: modifiers
	}
}

pub fn KeyBinding.from_event(input event.KeyEvent) KeyBinding {
	parts := normalize_key_parts(input.code, input.modifiers)
	return KeyBinding{
		code:      parts.code
		modifiers: parts.modifiers
	}
}

pub fn (binding &KeyBinding) is_press(input event.KeyEvent) bool {
	return normalize_key_parts(binding.code, binding.modifiers) == normalize_key_parts(input.code,
		input.modifiers) && input.kind in [.press, .repeat]
}

pub fn (binding &KeyBinding) parts() KeyParts {
	return KeyParts{
		code:      binding.code
		modifiers: binding.modifiers
	}
}

// Legacy Ctrl+] is reported as Ctrl+5; keep matching and conflicts consistent.
pub fn (binding &KeyBinding) normalized_parts() KeyParts {
	parts := binding.parts()
	if parts.code.kind == .char_key && parts.code.ch == `5`
		&& parts.modifiers == event.key_modifiers_control {
		return ctrl(event.KeyCode.char_key(`]`)).parts()
	}
	return parts
}

pub fn (binding &KeyBinding) display_label() string {
	modifiers := modifiers_to_string(binding.modifiers)
	key := match binding.code.kind {
		.enter { 'enter' }
		.char_key {
			if binding.code.ch == ` ` {
				'space'
			} else {
				ascii_lowercase_rune(binding.code.ch).str()
			}
		}
		.up { '↑' }
		.down { '↓' }
		.left { '←' }
		.right { '→' }
		.page_up { 'pgup' }
		.page_down { 'pgdn' }
		else { key_code_string(binding.code) }
	}
	return '${modifiers}${key}'
}

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
			code:      event.KeyCode.char_key(ascii_lowercase_rune(ch))
			modifiers: with_shift
		}
	}
	return KeyBinding.new(key, modifiers).normalized_parts()
}

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

// Matching helpers for one action's keybinding set.
//
// Rust expresses this as `KeyBindingListExt` for `[KeyBinding]`. V uses a free function because
// methods cannot be added to arrays from another module. The slice is a set of alternatives for
// one action; order is reserved for UI hint selection via `primary_binding`, not dispatch priority.
// True when any binding in this set matches `input`.
pub fn bindings_are_pressed(bindings &[]KeyBinding, input event.KeyEvent) bool {
	for binding in *bindings {
		if binding.is_press(input) {
			return true
		}
	}
	return false
}

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

pub fn plain(key event.KeyCode) KeyBinding {
	return KeyBinding.new(key, event.key_modifiers_none)
}

pub fn alt(key event.KeyCode) KeyBinding {
	return KeyBinding.new(key, event.key_modifiers_alt)
}

pub fn shift(key event.KeyCode) KeyBinding {
	return KeyBinding.new(key, event.key_modifiers_shift)
}

pub fn ctrl(key event.KeyCode) KeyBinding {
	return KeyBinding.new(key, event.key_modifiers_control)
}

pub fn ctrl_alt(key event.KeyCode) KeyBinding {
	return KeyBinding.new(key, event.key_modifiers_control.union(event.key_modifiers_alt))
}

fn modifiers_to_string(modifiers event.KeyModifiers) string {
	mut result := ''
	if modifiers.contains(event.key_modifiers_control) {
		result += ctrl_prefix
	}
	if modifiers.contains(event.key_modifiers_shift) {
		result += shift_prefix
	}
	if modifiers.contains(event.key_modifiers_alt) {
		result += alt_prefix()
	}
	return result
}

// Equivalent to Rust's owned `From<KeyBinding> for Span<'static>` implementation.
pub fn span_from_binding(binding KeyBinding) rat_text.Span {
	return span_from_borrowed_binding(&binding)
}

// Equivalent to Rust's borrowed `From<&KeyBinding> for Span<'static>` implementation.
pub fn span_from_borrowed_binding(binding &KeyBinding) rat_text.Span {
	return rat_text.Span{
		text:  binding.display_label()
		style: key_hint_style()
	}
}

// Equivalent to Rust's `From<ShortcutHint> for Span<'static>` implementation.
pub fn span_from_shortcut_hint(hint ShortcutHint) rat_text.Span {
	return rat_text.Span{
		text:  hint.display_label()
		style: key_hint_style()
	}
}

fn key_hint_style() rat_text.SpanStyle {
	return rat_text.SpanStyle{ dim: true }
}

pub fn has_ctrl_or_alt(mods event.KeyModifiers) bool {
	return (mods.contains(event.key_modifiers_control) || mods.contains(event.key_modifiers_alt))
		&& !is_altgr(mods)
}

// The Rust source treats ALT and CONTROL together as AltGr only on Windows.
pub fn is_altgr(mods event.KeyModifiers) bool {
	$if windows {
		return mods.contains(event.key_modifiers_alt)
			&& mods.contains(event.key_modifiers_control)
	}
	return false
}

fn alt_prefix() string {
	$if test {
		return '⌥ + '
	}
	$if macos {
		return '⌥ + '
	}
	return 'alt + '
}

fn ascii_lowercase_rune(ch rune) rune {
	if ch >= `A` && ch <= `Z` {
		return rune(int(ch) - int(`A`) + int(`a`))
	}
	return ch
}

// Mirrors the lowercase result of crossterm's `KeyCode::to_string()` for the variants represented
// by the local dependency shim. Key codes with custom compact labels are handled above.
fn key_code_string(code event.KeyCode) string {
	return match code.kind {
		.char_key { ascii_lowercase_rune(code.ch).str() }
		.enter { 'enter' }
		.tab { 'tab' }
		.escape { 'esc' }
		.up { 'up' }
		.down { 'down' }
		.left { 'left' }
		.right { 'right' }
		.backspace { backspace_label() }
		.delete { delete_label() }
		.function { 'f${code.f}' }
		.home { 'home' }
		.end { 'end' }
		.page_up { 'page up' }
		.page_down { 'page down' }
		.insert { 'insert' }
		.unknown { 'unknown' }
	}
}

fn backspace_label() string {
	$if macos {
		return 'delete'
	}
	return 'backspace'
}

fn delete_label() string {
	$if macos {
		return 'fwd del'
	}
	return 'del'
}
