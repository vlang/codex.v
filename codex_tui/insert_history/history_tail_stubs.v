module insert_history

import codex_tui.custom_terminal
import codex_tui.terminal_hyperlinks
import codex_tui.wrapping
import codex_tui.test_backend
import ratatui.layout
import ratatui.text

// STUB: insert_history.rs::HistoryLineWrapPolicy preserves its Copy-equivalent variants.
pub enum HistoryLineWrapPolicy {
	pre_wrap
	terminal
}

// STUB: insert_history.rs::InsertHistoryMode preserves its native escape strategies.
pub enum InsertHistoryMode {
	standard
	full_screen
}

// STUB: insert_history::insert_history_lines consumes plain lines through the source-shaped
// hyperlink insertion API; default policy is PreWrap and mode is Standard.
pub fn insert_history_lines(mut terminal custom_terminal.Terminal, lines []text.Line) ! {
	plain := terminal_hyperlinks.plain_hyperlink_lines(lines)
	insert_history_hyperlink_lines_with_mode_and_wrap_policy(mut terminal, &plain, .standard, .pre_wrap, terminal.last_known_screen_size)!
}

// STUB: insert_history::wrap_history_hyperlink_lines returns source physical row counts.
// Terminal-managed lines retain their owned text and link annotations at the source clone
// boundary. Plain PreWrap fixture lines use the existing FirstFit wrapping dependency;
// mixed URL adaptation/semantic-link remapping await the full insert_history translation.
pub fn wrap_history_hyperlink_lines(lines &[]terminal_hyperlinks.HyperlinkLine, wrap_width usize, wrap_policy HistoryLineWrapPolicy) ([]terminal_hyperlinks.HyperlinkLine, usize) {
	mut wrapped := []terminal_hyperlinks.HyperlinkLine{}
	mut wrapped_rows := usize(0)
	for index in 0 .. lines.len {
		line := unsafe { &lines[index] }
		if wrap_policy == .terminal || line.hyperlinks.len > 0 {
			wrapped << line.clone()
			columns := line.width()
			wrapped_rows += ((if columns > 0 { columns } else { usize(1) }) + wrap_width - 1) / wrap_width
		} else {
			line_wrapped := wrapping.word_wrap_lines([line.line.clone()], wrapping.RtOptions.new(wrap_width))
			mut owned_lines := HistoryTailOwnedLines{ values: terminal_hyperlinks.plain_hyperlink_lines(line_wrapped) }
			owned_lines.values.reverse_in_place()
			count := owned_lines.values.len
			for _ in 0 .. count {
				wrapped_line := owned_lines.values.pop()
				columns := wrapped_line.width()
				wrapped_rows += ((if columns > 0 { columns } else { usize(1) }) + wrap_width - 1) / wrap_width
				wrapped << wrapped_line
			}
		}
	}
	return wrapped, wrapped_rows
}

// STUB: source-shaped insertion executes ANSI through the terminal's typed backend writer.
// This reproduces native region movement, history row counting and cursor neutrality for
// the in-memory fixture; styled/OSC 8 output remains the untranslated insertion runtime.
pub fn insert_history_hyperlink_lines_with_mode_and_wrap_policy(mut terminal custom_terminal.Terminal, lines &[]terminal_hyperlinks.HyperlinkLine, mode InsertHistoryMode, wrap_policy HistoryLineWrapPolicy, screen_size layout.Size) ! {
	mut area := terminal.viewport_area
	mut should_update_area := false
	last_cursor_pos := terminal.last_known_cursor_pos
	wrap_width := usize(if area.width > 0 { area.width } else { u16(1) })
	wrapped, wrapped_rows := wrap_history_hyperlink_lines(lines, wrap_width, wrap_policy)
	wrapped_lines := u16(wrapped_rows)
	match mode {
		.full_screen {
			terminal.clear_after_position(layout.Position{ x: area.x, y: area.y })!
			mut writer := terminal.backend_mut()
			writer.set_cursor_position(layout.Position{ x: 0, y: area.y })!
			for index in 0 .. wrapped.len {
				if index > 0 {
					data := '\r\n'.bytes()
					writer.write(&data)!
				}
				write_history_line(mut writer, &wrapped[index], wrap_width)!
			}
			for _ in 0 .. area.height {
				data := '\r\n\x1b[K'.bytes()
				writer.write(&data)!
			}
			writer.set_cursor_position(last_cursor_pos)!
			maximum := if screen_size.height >= area.height {
				screen_size.height - area.height
			} else {
				u16(0)
			}
			advanced := u32(area.y) + u32(wrapped_lines)
			viewport_top := u16(if advanced < u32(maximum) { advanced } else { u32(maximum) })
			if area.y != viewport_top {
				area = layout.Rect{ ...area, y: viewport_top }
				should_update_area = true
			}
		}
		.standard {
			mut writer := terminal.backend_mut()
			cursor_top := if area.bottom() < screen_size.height {
				available := screen_size.height - area.bottom()
				scroll_amount := if wrapped_lines < available { wrapped_lines } else { available }
				region := '\x1b[${area.y + 1};${screen_size.height}r'.bytes()
				writer.write(&region)!
				writer.set_cursor_position(layout.Position{ x: 0, y: area.y })!
				for _ in 0 .. scroll_amount {
					data := '\x1bM'.bytes()
					writer.write(&data)!
				}
				reset := '\x1b[r'.bytes()
				writer.write(&reset)!
				top := if area.y > 0 { area.y - 1 } else { u16(0) }
				area = layout.Rect{ ...area, y: area.y + scroll_amount }
				should_update_area = true
				top
			} else {
				if area.y > 0 { area.y - 1 } else { u16(0) }
			}
			region := '\x1b[1;${area.y}r'.bytes()
			writer.write(&region)!
			writer.set_cursor_position(layout.Position{ x: 0, y: cursor_top })!
			for index in 0 .. wrapped.len {
				data := '\r\n'.bytes()
				writer.write(&data)!
				write_history_line(mut writer, &wrapped[index], wrap_width)!
			}
			reset := '\x1b[r'.bytes()
			writer.write(&reset)!
			writer.set_cursor_position(last_cursor_pos)!
		}
	}
	if should_update_area { terminal.set_viewport_area(area) }
	if wrapped_lines > 0 { terminal.note_history_rows_inserted(wrapped_lines) }
}

// STUB: owned iterator storage for the source dependency's wrapped-line collection.
struct HistoryTailOwnedLines {
mut:
	values []terminal_hyperlinks.HyperlinkLine
}

// STUB: insert_history::write_history_line's visible text and continuation-row clearing.
// Full span styling and validated OSC 8 metadata are outside this fixture boundary.
fn write_history_line(mut writer test_backend.VT100Backend, line &terminal_hyperlinks.HyperlinkLine, wrap_width usize) ! {
	columns := line.width()
	physical_rows := u16(((if columns > 0 { columns } else { usize(1) }) + wrap_width - 1) / wrap_width)
	if physical_rows > 1 {
		save := '\x1b7'.bytes()
		writer.write(&save)!
		for _ in 1 .. physical_rows {
			data := '\x1b[1B\x1b[1G\x1b[K'.bytes()
			writer.write(&data)!
		}
		restore := '\x1b8'.bytes()
		writer.write(&restore)!
	}
	clear := '\x1b[K'.bytes()
	writer.write(&clear)!
	for index in 0 .. line.line.spans.len {
		data := line.line.spans[index].text.bytes()
		writer.write(&data)!
	}
}
