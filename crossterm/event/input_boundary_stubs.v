module event

import std_io
import std_time

// STUB: crossterm::event::InputDiscardStatus. The decoder and quarantine buffers are not ported.
pub enum InputDiscardStatus {
	complete
	bracketed_paste_in_progress
	control_sequence_in_progress
}

// STUB: crossterm::event::Event's discriminator for the event consumed and discarded here.
pub enum EventKind {
	key
	mouse
	paste
	resize
	focus_gained
	focus_lost
}

// STUB: crossterm::event::MouseEvent's typed payload, needed to retain Event's real shape.
pub struct MouseEvent {
pub:
	kind      MouseEventKind
	button    MouseButton
	column    u16
	row       u16
	modifiers KeyModifiers
}

// STUB: crossterm::event::MouseEventKind; payload-bearing down/up/drag retain their button above.
pub enum MouseEventKind {
	down
	up
	drag
	moved
	scroll_down
	scroll_up
	scroll_left
	scroll_right
}

// STUB: crossterm::event::MouseButton.
pub enum MouseButton {
	left
	right
	middle
}

// STUB: crossterm::event::Event. No native reader or event decoding is provided by this shim.
pub struct Event {
pub:
	kind   EventKind
	key    KeyEvent
	mouse  MouseEvent
	paste  string
	width  u16
	height u16
}

// STUB: crossterm::event::discard_buffered_input. Fail explicitly until the shared decoder's
// discard/quarantine implementation is translated; clearing an absent buffer would be unsafe.
pub fn discard_buffered_input() !InputDiscardStatus {
	return std_io.Error.new(.unsupported, 'crossterm buffered input decoder is not translated')
}

// STUB: crossterm::event::poll. Preserve the Copy timeout and io::Result<bool> signature.
pub fn poll(timeout std_time.Duration) !bool {
	return std_io.Error.new(.unsupported, 'crossterm terminal event polling is not translated')
}

// STUB: crossterm::event::read. Preserve the owned payload and io::Result<Event> signature.
pub fn read() !Event {
	return std_io.Error.new(.unsupported, 'crossterm terminal event reading is not translated')
}
