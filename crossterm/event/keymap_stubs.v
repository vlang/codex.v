module event

// STUB: crossterm::event::KeyModifiers::NONE.
pub const key_modifiers_none = KeyModifiers{}

// STUB: crossterm::event::KeyModifiers::CONTROL.
pub const key_modifiers_control = KeyModifiers{
	control: true
}

// STUB: crossterm::event::KeyModifiers::ALT.
pub const key_modifiers_alt = KeyModifiers{
	alt: true
}

// STUB: crossterm::event::KeyModifiers::SHIFT.
pub const key_modifiers_shift = KeyModifiers{
	shift: true
}

// STUB: crossterm::event::KeyModifiers::is_empty. The real bitflags value is empty when no
// modifier bit is set; the V stub stores one bool per modifier.
pub fn (modifiers KeyModifiers) is_empty() bool {
	return !modifiers.shift && !modifiers.control && !modifiers.alt && !modifiers.super
		&& !modifiers.hyper && !modifiers.meta
}

// STUB: crossterm::event::KeyModifiers::contains.
pub fn (modifiers KeyModifiers) contains(other KeyModifiers) bool {
	return (!other.shift || modifiers.shift) && (!other.control || modifiers.control)
		&& (!other.alt || modifiers.alt) && (!other.super || modifiers.super)
		&& (!other.hyper || modifiers.hyper) && (!other.meta || modifiers.meta)
}

// STUB: crossterm::event::KeyModifiers::union, spelled `|` in Rust.
pub fn (modifiers KeyModifiers) union(other KeyModifiers) KeyModifiers {
	return KeyModifiers{
		shift:   modifiers.shift || other.shift
		control: modifiers.control || other.control
		alt:     modifiers.alt || other.alt
		super:   modifiers.super || other.super
		hyper:   modifiers.hyper || other.hyper
		meta:    modifiers.meta || other.meta
	}
}

// STUB: crossterm::event::KeyModifiers::insert, spelled `modifiers.insert(BIT)` in Rust.
pub fn (mut modifiers KeyModifiers) insert(other KeyModifiers) {
	modifiers = modifiers.union(other)
}

// STUB: crossterm::event::KeyCode::Char.
pub fn KeyCode.char_key(ch rune) KeyCode {
	return KeyCode{
		kind: .char_key
		ch:   ch
	}
}

// STUB: crossterm::event::KeyCode::F.
pub fn KeyCode.function_key(number u8) KeyCode {
	return KeyCode{
		kind: .function
		f:    int(number)
	}
}

// STUB: crossterm::event::KeyCode::Enter.
pub const key_code_enter = KeyCode{
	kind: .enter
}

// STUB: crossterm::event::KeyCode::Tab.
pub const key_code_tab = KeyCode{
	kind: .tab
}

// STUB: crossterm::event::KeyCode::Backspace.
pub const key_code_backspace = KeyCode{
	kind: .backspace
}

// STUB: crossterm::event::KeyCode::Esc.
pub const key_code_esc = KeyCode{
	kind: .escape
}

// STUB: crossterm::event::KeyCode::Delete.
pub const key_code_delete = KeyCode{
	kind: .delete
}

// STUB: crossterm::event::KeyCode::Insert.
pub const key_code_insert = KeyCode{
	kind: .insert
}

// STUB: crossterm::event::KeyCode::Up.
pub const key_code_up = KeyCode{
	kind: .up
}

// STUB: crossterm::event::KeyCode::Down.
pub const key_code_down = KeyCode{
	kind: .down
}

// STUB: crossterm::event::KeyCode::Left.
pub const key_code_left = KeyCode{
	kind: .left
}

// STUB: crossterm::event::KeyCode::Right.
pub const key_code_right = KeyCode{
	kind: .right
}

// STUB: crossterm::event::KeyCode::Home.
pub const key_code_home = KeyCode{
	kind: .home
}

// STUB: crossterm::event::KeyCode::End.
pub const key_code_end = KeyCode{
	kind: .end
}

// STUB: crossterm::event::KeyCode::PageUp.
pub const key_code_page_up = KeyCode{
	kind: .page_up
}

// STUB: crossterm::event::KeyCode::PageDown.
pub const key_code_page_down = KeyCode{
	kind: .page_down
}
