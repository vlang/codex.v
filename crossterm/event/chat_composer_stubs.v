module event

// STUB: crossterm::event::KeyCode.
pub enum KeyCodeKind {
	char_key
	enter
	tab
	escape
	up
	down
	left
	right
	backspace
	delete
	function
	home
	end
	page_up
	page_down
	insert
	unknown
}

// STUB: payload-bearing crossterm::event::KeyCode.
pub struct KeyCode {
pub:
	kind KeyCodeKind
	ch   rune
	f    int
}

// STUB: crossterm::event::KeyModifiers.
pub struct KeyModifiers {
pub:
	shift   bool
	control bool
	alt     bool
	super   bool
	hyper   bool
	meta    bool
}

// STUB: crossterm::event::KeyEventKind.
pub enum KeyEventKind {
	press
	repeat
	release
}

// STUB: crossterm::event::KeyEvent.
pub struct KeyEvent {
pub:
	code      KeyCode
	modifiers KeyModifiers
	kind      KeyEventKind = .press
}

// STUB: crossterm::event::KeyEvent::new.
pub fn KeyEvent.new(code KeyCode, modifiers KeyModifiers) KeyEvent {
	return KeyEvent{ code: code, modifiers: modifiers }
}
