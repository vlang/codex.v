module crossterm

import crossterm.cursor
import crossterm.style

// STUB: crossterm::queue!(writer, MoveTo) preserves ANSI output and writer I/O errors.
// V cannot translate Rust macros, so each command has a typed queue entry point.
pub fn queue_move_to[W](mut writer W, command cursor.MoveTo) ! {
	data := '\x1b[${u32(command.y) + 1};${u32(command.x) + 1}H'.bytes()
	writer.write(&data)!
}

// STUB: crossterm::queue!(writer, Print<&str>) preserves the borrowed text and I/O errors.
pub fn queue_print[W](mut writer W, command &style.Print) ! {
	data := command.text.bytes()
	writer.write(&data)!
}
