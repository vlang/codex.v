module history_cell

// STUB: crate::history_cell::HistoryCellKind models the cell kinds created by ChatComposer.
pub enum HistoryCellKind {
	info
	error
}

// STUB: crate::history_cell::HistoryCell preserves the owned transcript-cell payload passed
// through AppEvent::InsertHistoryCell.
pub struct HistoryCell {
pub:
	kind    HistoryCellKind
	message string
	hint    ?string
}

// STUB: crate::history_cell::new_info_event.
pub fn new_info_event(message string, hint ?string) HistoryCell {
	return HistoryCell{
		kind:    .info
		message: message
		hint:    hint
	}
}

// STUB: crate::history_cell::new_error_event.
pub fn new_error_event(message string) HistoryCell {
	return HistoryCell{
		kind:    .error
		message: message
	}
}

// STUB: crate::history_cell::sanitize_user_text. This keeps printable text/newlines while removing
// control bytes and complete ANSI CSI sequences at the external history-cell boundary.
pub fn sanitize_user_text(input string) string {
	mut output := []u8{cap: input.len}
	mut index := 0
	for index < input.len {
		byte := input[index]
		if byte == 0x1b {
			index++
			if index < input.len && input[index] == `[` {
				index++
				for index < input.len {
					final_byte := input[index]
					index++
					if final_byte >= 0x40 && final_byte <= 0x7e {
						break
					}
				}
			}
			continue
		}
		if byte != 0 && byte != 0x7f {
			output << byte
		}
		index++
	}
	return output.bytestr()
}
