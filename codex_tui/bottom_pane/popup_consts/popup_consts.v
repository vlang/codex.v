// Shared popup-related constants for bottom pane widgets.
module popup_consts

import codex_tui.key_hint
import codex_tui.keymap
import crossterm.event
import ratatui.text

// Maximum number of rows any popup should attempt to display.
// Keep this consistent across all popups for a uniform feel.
pub const max_popup_rows = usize(8)

// Standard footer hint text used by popups.
pub fn standard_popup_hint_line() text.Line {
	return text.line_from_spans([
		text.Span{ text: 'Press ' },
		key_hint.span_from_binding(key_hint.plain(event.key_code_enter)),
		text.Span{ text: ' to confirm or ' },
		key_hint.span_from_binding(key_hint.plain(event.key_code_esc)),
		text.Span{ text: ' to go back' },
	])
}

pub fn standard_popup_hint_line_for_keymap(list_keymap &keymap.ListKeymap) text.Line {
	accept_label := 'to confirm'
	cancel_label := 'to go back'
	return accept_cancel_hint_line(list_keymap.primary_hint(.accept), &accept_label,
		list_keymap.primary_hint(.cancel), &cancel_label)
}

// ShortcutHint is allocation-free and Copy-equivalent, so optional hints remain value parameters.
// Rust's static string labels are borrowed; interpolated spans own their formatted text.
pub fn accept_cancel_hint_line(accept ?key_hint.ShortcutHint, accept_label &string, cancel ?key_hint.ShortcutHint, cancel_label &string) text.Line {
	if accept_hint := accept {
		if cancel_hint := cancel {
			return text.line_from_spans([
				text.Span{ text: 'Press ' },
				key_hint.span_from_shortcut_hint(accept_hint),
				text.Span{ text: ' ${*accept_label} or ' },
				key_hint.span_from_shortcut_hint(cancel_hint),
				text.Span{ text: ' ${*cancel_label}' },
			])
		}
		return text.line_from_spans([
			text.Span{ text: 'Press ' },
			key_hint.span_from_shortcut_hint(accept_hint),
			text.Span{ text: ' ${*accept_label}' },
		])
	}
	if cancel_hint := cancel {
		return text.line_from_spans([
			text.Span{ text: 'Press ' },
			key_hint.span_from_shortcut_hint(cancel_hint),
			text.Span{ text: ' ${*cancel_label}' },
		])
	}
	return text.line_from('')
}
