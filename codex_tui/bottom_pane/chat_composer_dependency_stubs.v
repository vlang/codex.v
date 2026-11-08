module bottom_pane

import codex_tui.slash_command
import codex_tui.bottom_pane.prompt_args
import time
import codex_app_server_protocol.skill_metadata
import codex_file_search
import codex_plugin
import codex_protocol.thread_id as protocol_thread_id
import codex_protocol.user_input
import codex_tui.app_event
import codex_tui.app_event_sender
import codex_tui.key_hint
import codex_tui.keymap as tui_keymap
import codex_tui.mention_codec
import codex_tui.task_mentions
import crossterm.event as terminal_event
import ratatui.buffer as rat_buffer
import ratatui.layout as rat_layout
import ratatui.style as rat_style
import ratatui.text as rat_text

// STUB: super::textarea::LIVE_PREFIX_COLS.
const live_prefix_cols = u16(2)

// STUB: crate::tui::FrameRequester.
pub struct FrameRequester {}

// STUB: crate::tui::FrameRequester::schedule_frame.
pub fn (requester &FrameRequester) schedule_frame() {}

// STUB: crate::tui::FrameRequester::schedule_frame_in.
pub fn (requester &FrameRequester) schedule_frame_in(_duration_ms i64) {}

// STUB: crate::bottom_pane::MentionBinding.
pub struct MentionBinding {
pub:
	sigil   rune
	mention string
	path    string
}

// STUB: crate::bottom_pane::LocalImageAttachment.
pub struct LocalImageAttachment {
pub:
	path        string
	placeholder string
}

// STUB: crate::bottom_pane::textarea::TextElementSnapshot.
pub struct TextElementSnapshot {
pub:
	id    u64
	start int
	end   int
	text  string
}

// STUB: crate::bottom_pane::textarea::TextAreaState. Ratatui keeps viewport state separately from
// the text model so cursor queries and rendering share the same scroll origin.
pub struct TextAreaState {
mut:
	vertical_scroll int
}

// STUB: crate::bottom_pane::textarea::TextArea. The future textarea port owns full Vim/rendering behavior.
pub struct TextArea {
mut:
	buffer               string
	cursor_position      int
	next_element_id      u64 = 1
	elements             map[u64]user_input.TextElement
	kill_buffer          string
	vim_enabled          bool
	vim_search_enabled   bool
	vim_mode             string
	vim_query_open       bool
	vim_query_text       string
	vim_operator_pending bool
	vim_last_insert      string
}

// STUB: crate::bottom_pane::textarea::TextArea::new.
pub fn TextArea.new() TextArea {
	return TextArea{ vim_mode: 'normal' }
}

// STUB: crate::bottom_pane::textarea::TextArea::set_keymap_bindings.
pub fn (mut textarea TextArea) set_keymap_bindings(_keymap &tui_keymap.RuntimeKeymap) {}

// STUB: crate::bottom_pane::textarea::TextArea::keymap_contexts.
pub fn (textarea &TextArea) keymap_contexts() tui_keymap.KeymapContextSet {
	return tui_keymap.KeymapContextSet.new(.editor)
}

// STUB: crate::bottom_pane::textarea::TextArea::vim_query.
pub fn (textarea &TextArea) vim_query_active() bool {
	return textarea.vim_query_open
}

// STUB: crate::bottom_pane::textarea::TextArea::vim_query read boundary.
pub fn (textarea &TextArea) vim_query_text() ?string {
	if !textarea.vim_query_open {
		return none
	}
	return textarea.vim_query_text.clone()
}

// STUB: crate::bottom_pane::textarea::TextArea::wants_vim_search_key. The eventual textarea
// keymap supplies remapped next/previous bindings; this preserves active-query ownership and the
// built-in forward/backward search starters observed by ChatComposer.
pub fn (textarea &TextArea) wants_vim_search_key(event terminal_event.KeyEvent) bool {
	if textarea.vim_query_open {
		return true
	}
	return textarea.vim_search_enabled && textarea.is_vim_normal_mode() && !textarea.vim_operator_pending
		&& event.code.kind == .char_key && event.code.ch in [`/`, `?`]
		&& !event.modifiers.control && !event.modifiers.alt
}

// STUB: crate::bottom_pane::textarea::TextArea::vim_query_mut insertion boundary.
pub fn (mut textarea TextArea) insert_into_vim_query(text &string) bool {
	if !textarea.vim_query_open {
		return false
	}
	textarea.vim_query_text += *text
	return true
}

// STUB: crate::bottom_pane::textarea::TextArea::text.
pub fn (textarea &TextArea) text() string {
	return textarea.buffer.clone()
}

// STUB: crate::bottom_pane::textarea::TextArea::cursor.
pub fn (textarea &TextArea) cursor() int {
	return textarea.cursor_position
}

// STUB: crate::bottom_pane::textarea::TextArea::cursor_pos_with_state.
pub fn (textarea &TextArea) cursor_pos_with_state(area rat_layout.Rect,
	state TextAreaState) ?CursorPosition {
	if area.width == 0 || area.height == 0 {
		return none
	}
	text := textarea.text()
	cursor := clamp_int(textarea.cursor_position, 0, text.len)
	mut row := 0
	mut column := 0
	for value in text[..cursor].runes() {
		if value == `\n` {
			row++
			column = 0
			continue
		}
		width := rune_display_width(value)
		if column + width > int(area.width) {
			row++
			column = 0
		}
		column += width
		if column >= int(area.width) {
			row += column / int(area.width)
			column %= int(area.width)
		}
	}
	visible_row := row - state.vertical_scroll
	if visible_row < 0 || visible_row >= int(area.height) {
		return none
	}
	return CursorPosition{ x: area.x + u16(column), y: area.y + u16(visible_row) }
}

// STUB: private super::textarea display-cell width helper.
fn rune_display_width(value rune) int {
	// Combining marks occupy no cell; the common East Asian/full-width ranges occupy two.
	if (value >= 0x0300 && value <= 0x036f) || (value >= 0x1ab0 && value <= 0x1aff)
		|| (value >= 0x1dc0 && value <= 0x1dff) || (value >= 0x20d0 && value <= 0x20ff)
		|| (value >= 0xfe20 && value <= 0xfe2f) {
		return 0
	}
	if value >= 0x1100 && (value <= 0x115f || value == 0x2329 || value == 0x232a
		|| (value >= 0x2e80 && value <= 0xa4cf) || (value >= 0xac00 && value <= 0xd7a3)
		|| (value >= 0xf900 && value <= 0xfaff) || (value >= 0xfe10 && value <= 0xfe19)
		|| (value >= 0xfe30 && value <= 0xfe6f) || (value >= 0xff00 && value <= 0xff60)
		|| (value >= 0xffe0 && value <= 0xffe6) || (value >= 0x1f300 && value <= 0x1faff)) {
		return 2
	}
	return 1
}

// STUB: crate::bottom_pane::textarea::TextArea::is_empty.
pub fn (textarea &TextArea) is_empty() bool {
	return textarea.buffer.len == 0
}

// STUB: crate::bottom_pane::textarea::TextArea::set_cursor.
pub fn (mut textarea TextArea) set_cursor(position int) {
	textarea.cursor_position = clamp_int(position, 0, textarea.buffer.len)
}

// STUB: crate::bottom_pane::textarea::TextArea::insert_str.
pub fn (mut textarea TextArea) insert_str(text &string) {
	textarea.insert_str_at(textarea.cursor_position, text)
}

// STUB: crate::bottom_pane::textarea::TextArea::insert_str_at.
pub fn (mut textarea TextArea) insert_str_at(position int, text &string) {
	pos := clamp_int(position, 0, textarea.buffer.len)
	textarea.shift_elements(pos, text.len)
	// V's C backend can over-dereference a borrowed string inside a three-way concatenation; the
	// explicit owned fragment is the smallest compiler adaptation at this dependency boundary.
	fragment := text.clone()
	textarea.buffer = textarea.buffer[..pos] + fragment + textarea.buffer[pos..]
	textarea.cursor_position = pos + text.len
}

// STUB: crate::bottom_pane::textarea::TextArea element range maintenance.
fn (mut textarea TextArea) shift_elements(position int, delta int) {
	for id, element in textarea.elements {
		if element.byte_range.start >= position {
			textarea.elements[id] = user_input.TextElement.new(user_input.ByteRange{
				start: element.byte_range.start + delta
				end:   element.byte_range.end + delta
			}, element.not_hidden_placeholder_for_conversion_only())
		}
	}
}

// STUB: crate::bottom_pane::textarea::TextArea::insert_element.
pub fn (mut textarea TextArea) insert_element(text &string) u64 {
	id := textarea.next_element_id
	textarea.next_element_id++
	start := textarea.cursor_position
	textarea.insert_str_at(start, text)
	textarea.elements[id] = user_input.TextElement.new(user_input.ByteRange{
		start: start
		end:   start + text.len
	}, text.clone())
	return id
}

// STUB: crate::bottom_pane::textarea::TextArea::set_text_clearing_elements.
pub fn (mut textarea TextArea) set_text_clearing_elements(text &string) {
	textarea.buffer = text.clone()
	textarea.cursor_position = 0
	textarea.elements.clear()
}

// STUB: crate::bottom_pane::textarea::TextArea::set_text_with_elements.
pub fn (mut textarea TextArea) set_text_with_elements(text &string, elements &[]user_input.TextElement) {
	textarea.buffer = text.clone()
	textarea.cursor_position = 0
	textarea.elements.clear()
	for element in *elements {
		id := textarea.next_element_id
		textarea.next_element_id++
		textarea.elements[id] = user_input.TextElement.new(element.byte_range, element.not_hidden_placeholder_for_conversion_only())
	}
}

// STUB: crate::bottom_pane::textarea::TextArea::replace_range.
pub fn (mut textarea TextArea) replace_range(start int, end int, replacement &string) {
	left := clamp_int(start, 0, textarea.buffer.len)
	right := clamp_int(end, left, textarea.buffer.len)
	delta := replacement.len - (right - left)
	mut kept := map[u64]user_input.TextElement{}
	for id, element in textarea.elements {
		if element.byte_range.end <= left {
			kept[id] = element
		} else if element.byte_range.start >= right {
			kept[id] = user_input.TextElement.new(user_input.ByteRange{
				start: element.byte_range.start + delta
				end:   element.byte_range.end + delta
			}, element.not_hidden_placeholder_for_conversion_only())
		}
	}
	textarea.elements = kept.clone()
	// See insert_str_at for the borrowed-string concatenation backend adaptation.
	fragment := replacement.clone()
	textarea.buffer = textarea.buffer[..left] + fragment + textarea.buffer[right..]
	textarea.cursor_position = left + replacement.len
}

// STUB: crate::bottom_pane::textarea::TextArea::retract_paste_burst. Replace-mode restoration is
// owned by the future Vim textarea port; ordinary insertion removes the grabbed byte range.
pub fn (mut textarea TextArea) retract_paste_burst(start int) bool {
	if start < 0 || start > textarea.cursor_position || textarea.cursor_position > textarea.buffer.len {
		return false
	}
	empty := ''
	textarea.replace_range(start, textarea.cursor_position, &empty)
	return true
}

// STUB: crate::bottom_pane::textarea::TextArea::text_elements.
pub fn (textarea &TextArea) text_elements() []user_input.TextElement {
	mut result := []user_input.TextElement{}
	for _, element in textarea.elements {
		result << user_input.TextElement.new(element.byte_range, element.not_hidden_placeholder_for_conversion_only())
	}
	result.sort(a.byte_range.start < b.byte_range.start)
	return result
}

// STUB: crate::bottom_pane::textarea::TextArea::element_payloads.
pub fn (textarea &TextArea) element_payloads() []string {
	text := textarea.text()
	return textarea.text_elements().map(it.placeholder_text(&text) or { '' })
}

// STUB: crate::bottom_pane::textarea::TextArea::text_element_snapshots.
pub fn (textarea &TextArea) text_element_snapshots() []TextElementSnapshot {
	mut result := []TextElementSnapshot{}
	for id, element in textarea.elements {
		payload := element.placeholder_text(&textarea.buffer) or { '' }
		result << TextElementSnapshot{ id: id, start: element.byte_range.start, end: element.byte_range.end, text: payload }
	}
	result.sort(a.start < b.start)
	return result
}

// STUB: crate::bottom_pane::textarea::TextArea::add_element_range.
pub fn (mut textarea TextArea) add_element_range(start int, end int) ?u64 {
	if start < 0 || end <= start || end > textarea.buffer.len {
		return none
	}
	for _, element in textarea.elements {
		if start < element.byte_range.end && element.byte_range.start < end {
			return none
		}
	}
	id := textarea.next_element_id
	textarea.next_element_id++
	textarea.elements[id] = user_input.TextElement.new(user_input.ByteRange{ start: start, end: end }, textarea.buffer[start..end].clone())
	return id
}

// STUB: crate::bottom_pane::textarea::TextArea::element_id_for_exact_range.
pub fn (textarea &TextArea) element_id_for_exact_range(start int, end int) ?u64 {
	for id, element in textarea.elements {
		if element.byte_range.start == start && element.byte_range.end == end {
			return id
		}
	}
	return none
}

// STUB: crate::bottom_pane::textarea::TextArea::remove_element_range.
pub fn (mut textarea TextArea) remove_element_range(start int, end int) {
	for id, element in textarea.elements {
		if element.byte_range.start == start && element.byte_range.end == end {
			textarea.elements.delete(id)
		}
	}
}

// STUB: crate::bottom_pane::textarea::TextArea::input; supports composer-observed editing keys.
pub fn (mut textarea TextArea) input(key_event terminal_event.KeyEvent) {
	if textarea.vim_query_open {
		match key_event.code.kind {
			.char_key {
				textarea.vim_query_text += key_event.code.ch.str()
			}
			.backspace {
				if textarea.vim_query_text.len == 0 {
					textarea.vim_query_open = false
				} else {
					end := previous_char_boundary(&textarea.vim_query_text, textarea.vim_query_text.len)
					textarea.vim_query_text = textarea.vim_query_text[..end].clone()
				}
			}
			.enter, .escape {
				textarea.vim_query_open = false
			}
			else {}
		}
		return
	}
	if textarea.is_vim_normal_mode() && key_event.code.kind == .char_key
		&& key_event.code.ch in [`/`, `?`] && !key_event.modifiers.control && !key_event.modifiers.alt {
		textarea.vim_query_open = true
		textarea.vim_query_text = ''
		return
	}
	match key_event.code.kind {
		.escape {
			if textarea.vim_enabled && textarea.vim_mode in ['insert', 'replace'] {
				textarea.vim_mode = 'normal'
				textarea.cursor_position = previous_char_boundary(&textarea.buffer, textarea.cursor_position)
				textarea.vim_operator_pending = false
			}
		}
		.char_key {
			if textarea.is_vim_normal_mode() && !key_event.modifiers.control
				&& !key_event.modifiers.alt {
				match key_event.code.ch {
					`i` {
						textarea.vim_mode = 'insert'
						textarea.vim_operator_pending = false
					}
					`R` {
						textarea.vim_mode = 'replace'
						textarea.vim_operator_pending = false
					}
					`d` {
						textarea.vim_operator_pending = true
					}
					`.` {
						if textarea.vim_last_insert.len > 0 {
							last := textarea.vim_last_insert.clone()
							textarea.insert_str(&last)
						}
						textarea.vim_operator_pending = false
					}
					else {
						textarea.vim_operator_pending = false
					}
				}
			} else if key_event.modifiers.control && key_event.code.ch == `k` {
				textarea.kill_buffer = textarea.buffer[textarea.cursor_position..].clone()
				empty := ''
				textarea.replace_range(textarea.cursor_position, textarea.buffer.len, &empty)
			} else if key_event.modifiers.control && key_event.code.ch == `y` {
				killed := textarea.kill_buffer.clone()
				textarea.insert_str(&killed)
			} else if !key_event.modifiers.control && !key_event.modifiers.alt && !key_event.modifiers.super
				&& !key_event.modifiers.hyper && !key_event.modifiers.meta {
				value := key_event.code.ch.str()
				textarea.insert_str(&value)
				if textarea.vim_enabled && textarea.vim_mode in ['insert', 'replace'] {
					textarea.vim_last_insert = value
				}
			}
		}
		.enter {
			if textarea.is_vim_normal_mode() && textarea.vim_operator_pending {
				textarea.vim_operator_pending = false
			} else {
				newline := '\n'
				textarea.insert_str(&newline)
			}
		}
		.left {
			for _, element in textarea.elements {
				if textarea.cursor_position == element.byte_range.end {
					textarea.set_cursor(element.byte_range.start)
					return
				}
			}
			textarea.set_cursor(previous_char_boundary(&textarea.buffer, textarea.cursor_position))
		}
		.right {
			for _, element in textarea.elements {
				if textarea.cursor_position == element.byte_range.start {
					textarea.set_cursor(element.byte_range.end)
					return
				}
			}
			textarea.set_cursor(next_char_boundary(&textarea.buffer, textarea.cursor_position))
		}
		.backspace {
			for _, element in textarea.elements {
				if textarea.cursor_position > element.byte_range.start && textarea.cursor_position <= element.byte_range.end {
					empty := ''
					textarea.replace_range(element.byte_range.start, element.byte_range.end, &empty)
					return
				}
			}
			start := previous_char_boundary(&textarea.buffer, textarea.cursor_position)
			if start < textarea.cursor_position {
				empty := ''
				textarea.replace_range(start, textarea.cursor_position, &empty)
			}
		}
		.delete {
			for _, element in textarea.elements {
				if textarea.cursor_position >= element.byte_range.start && textarea.cursor_position < element.byte_range.end {
					empty := ''
					textarea.replace_range(element.byte_range.start, element.byte_range.end, &empty)
					return
				}
			}
			end := next_char_boundary(&textarea.buffer, textarea.cursor_position)
			if end > textarea.cursor_position {
				empty := ''
				textarea.replace_range(textarea.cursor_position, end, &empty)
			}
		}
		else {}
	}
}

// STUB: crate::bottom_pane::textarea::TextArea StatefulWidgetRef rendering boundary.
pub fn (textarea &TextArea) render_ref(area rat_layout.Rect, mut buffer rat_buffer.Buffer,
	mut _state TextAreaState) {
	text := textarea.text()
	write_wrapped_render_text(mut buffer, area, &text, rat_style.Style{}, textarea.element_highlights(rat_style.Style.default().cyan()))
}

// STUB: crate::bottom_pane::textarea::TextArea::render_ref_masked.
pub fn (textarea &TextArea) render_ref_masked(area rat_layout.Rect, mut buffer rat_buffer.Buffer,
	mut _state TextAreaState, mask rune) {
	masked := mask.str().repeat(textarea.text().runes().len)
	write_wrapped_render_text(mut buffer, area, &masked, rat_style.Style{}, [])
}

// STUB: crate::bottom_pane::textarea::TextArea::render_ref_styled_with_highlights.
pub fn (textarea &TextArea) render_ref_styled_with_highlights(area rat_layout.Rect,
	mut buffer rat_buffer.Buffer, mut _state TextAreaState, base_style rat_style.Style,
	highlights []Highlight) {
	text := textarea.text()
	mut combined := highlights.clone()
	combined << textarea.element_highlights(base_style.cyan())
	write_wrapped_render_text(mut buffer, area, &text, base_style, combined)
}

// STUB: crate::bottom_pane::textarea::TextArea element styling used by `render_lines`; atomic
// composer elements are cyan unless an explicit render-only highlight precedes them.
fn (textarea &TextArea) element_highlights(element_style rat_style.Style) []Highlight {
	mut highlights := []Highlight{}
	for _, element in textarea.elements {
		highlights << Highlight{
			start: element.byte_range.start
			end:   element.byte_range.end
			style: element_style
		}
	}
	return highlights
}

// STUB: UTF-8 boundary helper needed by the textarea boundary.
fn previous_char_boundary(text &string, position int) int {
	if position <= 0 {
		return 0
	}
	mut candidate := position - 1
	for candidate > 0 && is_utf8_continuation((*text)[candidate]) {
		candidate--
	}
	return candidate
}

// STUB: UTF-8 boundary helper needed by the textarea boundary.
fn next_char_boundary(text &string, position int) int {
	if position >= text.len {
		return text.len
	}
	mut candidate := position + 1
	for candidate < text.len && is_utf8_continuation((*text)[candidate]) {
		candidate++
	}
	return candidate
}

// STUB: crate::bottom_pane::textarea Vim feature boundary.
pub fn (mut textarea TextArea) set_vim_enabled(enabled bool) {
	textarea.vim_enabled = enabled
	textarea.vim_mode = if enabled { 'normal' } else { 'disabled' }
}

// STUB: crate::bottom_pane::textarea::TextArea::enable_vim_search.
pub fn (mut textarea TextArea) enable_vim_search() {
	textarea.vim_search_enabled = true
}

// STUB: crate::bottom_pane::textarea::TextArea::desired_height. The future textarea port owns
// Unicode display-width and wrapping; this boundary retains the composer's typed height call.
pub fn (textarea &TextArea) desired_height(width u16) u16 {
	text_width := max_int(int(width), 1)
	mut lines := 0
	for line in textarea.buffer.split('\n') {
		lines += max_int((line.runes().len + text_width - 1) / text_width, 1)
	}
	return u16(lines)
}

// STUB: crate::bottom_pane::textarea Vim feature boundary.
pub fn (textarea &TextArea) is_vim_enabled() bool {
	return textarea.vim_enabled
}

// STUB: crate::bottom_pane::textarea Vim feature boundary.
pub fn (mut textarea TextArea) enter_vim_insert_mode() {
	if textarea.vim_enabled {
		textarea.vim_mode = 'insert'
	}
}

// STUB: crate::bottom_pane::textarea::TextArea::enter_vim_normal_mode.
pub fn (mut textarea TextArea) enter_vim_normal_mode() {
	if textarea.vim_enabled {
		textarea.vim_mode = 'normal'
	}
}

// STUB: crate::bottom_pane::textarea Vim feature boundary.
pub fn (textarea &TextArea) is_vim_normal_mode() bool {
	return textarea.vim_enabled && textarea.vim_mode == 'normal'
}

// STUB: crate::bottom_pane::textarea::TextArea::vim_normal_end_cursor.
pub fn (textarea &TextArea) vim_normal_end_cursor() int {
	if textarea.buffer.len == 0 {
		return 0
	}
	return previous_char_boundary(&textarea.buffer, textarea.buffer.len)
}

// STUB: crate::bottom_pane::textarea::TextArea::uses_vim_insert_cursor.
pub fn (textarea &TextArea) uses_vim_insert_cursor() bool {
	return textarea.vim_enabled && textarea.vim_mode == 'insert'
}

// STUB: crate::bottom_pane::textarea Vim feature boundary.
pub fn (textarea &TextArea) is_vim_operator_pending() bool {
	return textarea.vim_operator_pending
}

// STUB: crate::bottom_pane::textarea Vim feature boundary.
pub fn (textarea &TextArea) allows_paste_burst() bool {
	return !textarea.is_vim_normal_mode()
}

// STUB: super::chat_composer_history::HistoryEntry.
pub struct HistoryEntry {
pub:
	text              string
	text_elements     []user_input.TextElement
	local_image_paths []string
	remote_image_urls []string
	mention_bindings  []MentionBinding
	pending_pastes    []PendingPaste
}

// STUB: super::chat_composer_history::HistoryEntry::new.
pub fn HistoryEntry.new(text string) HistoryEntry {
	return HistoryEntry.new_with_at_mentions(text, true)
}

// STUB: super::chat_composer_history::HistoryEntry::new_with_at_mentions.
pub fn HistoryEntry.new_with_at_mentions(text string, at_mentions_enabled bool) HistoryEntry {
	decoded := mention_codec.decode_history_mentions_with_at_mentions(&text, at_mentions_enabled)
	mut elements := []user_input.TextElement{}
	for value in decoded.task_mention_ranges {
		elements << user_input.TextElement.new(user_input.ByteRange{
			start: value.start
			end:   value.end
		}, none)
	}
	bindings := decoded.mentions.map(MentionBinding{
		sigil:   it.sigil
		mention: it.mention.clone()
		path:    it.path.clone()
	})
	return HistoryEntry{
		text:             decoded.text
		text_elements:    elements
		mention_bindings: bindings
	}
}

// STUB: codex_message_history::HistoryBatchCursor.
pub struct HistoryBatchCursor {
pub:
	offset int
}

// STUB: super::chat_composer_history::HistorySearchResult.
pub enum HistorySearchResultKind {
	pending
	at_boundary
	not_found
	unavailable
	found
}

// STUB: payload-bearing super::chat_composer_history::HistorySearchResult.
pub struct HistorySearchResult {
pub:
	kind  HistorySearchResultKind
	entry HistoryEntry
}

// STUB: super::chat_composer_history::HistoryEntryResponse.
pub enum HistoryEntryResponseKind {
	found
	search
	ignored
}

// STUB: payload-bearing super::chat_composer_history::HistoryEntryResponse.
pub struct HistoryEntryResponse {
pub:
	kind   HistoryEntryResponseKind
	entry  HistoryEntry
	search HistorySearchResult
}

// STUB: super::chat_composer_history::ChatComposerHistory.
pub struct ChatComposerHistory {
mut:
	entries                    []HistoryEntry
	navigation_index           int = -1
	thread_id                  protocol_thread_id.ThreadId
	has_thread_id              bool
	log_id                     u64
	entry_count                int
	at_mention_restore_enabled bool
}

// STUB: super::chat_composer_history::ChatComposerHistory::new.
pub fn ChatComposerHistory.new() ChatComposerHistory {
	return ChatComposerHistory{}
}

// STUB: super::chat_composer_history::ChatComposerHistory::set_metadata.
pub fn (mut history ChatComposerHistory) set_metadata(thread_id protocol_thread_id.ThreadId, log_id u64,
	entry_count int) {
	had_configured_thread := history.has_thread_id
	history.thread_id = thread_id
	history.has_thread_id = true
	history.log_id = log_id
	history.entry_count = entry_count
	history.navigation_index = -1
	if had_configured_thread {
		history.entries.clear()
	}
}

// STUB: super::chat_composer_history::ChatComposerHistory::set_at_mention_restore_enabled.
// Changing decoding policy invalidates persistent traversal state just like the Rust owner.
pub fn (mut history ChatComposerHistory) set_at_mention_restore_enabled(enabled bool) {
	if history.at_mention_restore_enabled == enabled {
		return
	}
	history.at_mention_restore_enabled = enabled
	history.navigation_index = -1
}

// STUB: super::chat_composer_history::ChatComposerHistory::on_entry_response.
// This shim preserves stale-log rejection and the response union. Search resumption remains owned
// by the eventual history module translation.
pub fn (mut history ChatComposerHistory) on_entry_response(log_id u64, _offset int, entry ?string,
	_sender &app_event_sender.AppEventSender) HistoryEntryResponse {
	if history.log_id != log_id {
		return HistoryEntryResponse{ kind: .ignored }
	}
	if text := entry {
		return HistoryEntryResponse{
			kind:  .found
			entry: HistoryEntry.new_with_at_mentions(text, history.at_mention_restore_enabled)
		}
	}
	return HistoryEntryResponse{ kind: .ignored }
}

// STUB: super::chat_composer_history::ChatComposerHistory::on_batch_response.
// Absolute row offsets and malformed gaps are accepted without collapsing the response vector.
pub fn (mut history ChatComposerHistory) on_batch_response(log_id u64, _cursor HistoryBatchCursor,
	entries []app_event.HistoryBatchEntryResponse, _next_older_cursor ?HistoryBatchCursor,
	_sender &app_event_sender.AppEventSender) ?HistorySearchResult {
	if history.log_id != log_id {
		return none
	}
	for response in entries {
		if text := response.entry {
			return HistorySearchResult{
				kind:  .found
				entry: HistoryEntry.new_with_at_mentions(text, history.at_mention_restore_enabled)
			}
		}
	}
	return HistorySearchResult{ kind: .not_found }
}

// STUB: super::chat_composer_history::ChatComposerHistory::on_batch_error.
// Retry scheduling belongs to the future history module; the result remains distinct from
// exhaustion so the composer does not manufacture a match.
pub fn (mut history ChatComposerHistory) on_batch_error(log_id u64, _cursor HistoryBatchCursor,
	_sender &app_event_sender.AppEventSender) ?HistorySearchResult {
	if history.log_id != log_id {
		return none
	}
	return HistorySearchResult{ kind: .unavailable }
}

// STUB: super::chat_composer_history::ChatComposerHistory::record_local_submission.
pub fn (mut history ChatComposerHistory) record_local_submission(entry HistoryEntry) {
	history.entries << entry
	history.navigation_index = -1
}

// STUB: super::chat_composer_history::ChatComposerHistory::record_replayed_submission.
pub fn (mut history ChatComposerHistory) record_replayed_submission(entry HistoryEntry) {
	history.record_local_submission(entry)
}

// STUB: super::chat_composer_history::ChatComposerHistory::record_recalled_text.
pub fn (mut history ChatComposerHistory) record_recalled_text(_text string) {}

// STUB: super::chat_composer_history::ChatComposerHistory::reset_navigation.
pub fn (mut history ChatComposerHistory) reset_navigation() {
	history.navigation_index = -1
}

// STUB: super::chat_composer_history::ChatComposerHistory::navigate_up.
pub fn (mut history ChatComposerHistory) navigate_up(sender &app_event_sender.AppEventSender) ?HistoryEntry {
	total_entries := history.entry_count + history.entries.len
	if total_entries == 0 {
		return none
	}
	if history.navigation_index < 0 {
		history.navigation_index = total_entries - 1
	} else if history.navigation_index > 0 {
		history.navigation_index--
	}
	if history.navigation_index >= history.entry_count {
		return clone_history_entry(&history.entries[history.navigation_index - history.entry_count])
	}
	id := protocol_thread_id.ThreadId{ value: history.thread_id.value.clone() }
	sender.send(app_event.lookup_message_history_entry(id, history.navigation_index, history.log_id))
	return none
}

// STUB: super::chat_composer_history::ChatComposerHistory::navigate_down.
pub fn (mut history ChatComposerHistory) navigate_down(sender &app_event_sender.AppEventSender) ?HistoryEntry {
	if history.navigation_index < 0 {
		return none
	}
	if history.navigation_index + 1 >= history.entry_count + history.entries.len {
		history.navigation_index = -1
		return HistoryEntry{}
	}
	history.navigation_index++
	if history.navigation_index >= history.entry_count {
		return clone_history_entry(&history.entries[history.navigation_index - history.entry_count])
	}
	id := protocol_thread_id.ThreadId{ value: history.thread_id.value.clone() }
	sender.send(app_event.lookup_message_history_entry(id, history.navigation_index, history.log_id))
	return none
}

// STUB: cloning boundary supplied by the untranslated history module.
fn clone_history_entry(entry &HistoryEntry) HistoryEntry {
	return HistoryEntry{
		text:              entry.text.clone()
		text_elements:     entry.text_elements.clone()
		local_image_paths: entry.local_image_paths.clone()
		remote_image_urls: entry.remote_image_urls.clone()
		mention_bindings:  entry.mention_bindings.clone()
		pending_pastes:    entry.pending_pastes.clone()
	}
}

// STUB: super::chat_composer_history::ChatComposerHistory read methods.
pub fn (history &ChatComposerHistory) startup_local_history() []HistoryEntry {
	if history.has_thread_id {
		return []
	}
	return history.entries.map(clone_history_entry(&it))
}

// STUB: super::chat_composer_history::ChatComposerHistory navigation predicate.
pub fn (history &ChatComposerHistory) should_handle_navigation(_text &string, _cursor int) bool {
	return history.entries.len > 0 || history.navigation_index >= 0
}

// STUB: super::attachment_state::local_image_label_text.
pub fn local_image_label_text(label_number int) string {
	return '[Image #${label_number}]'
}

// STUB: super::attachment_state::AttachmentState.
pub struct AttachmentState {
mut:
	local_images                []LocalImageAttachment
	remote_urls                 []string
	recent_submission_images    []LocalImageAttachment
	selected_remote_image_index ?int
}

// STUB: super::attachment_state::AttachmentState::is_empty.
pub fn (attachments &AttachmentState) is_empty() bool {
	return attachments.local_images.len == 0 && attachments.remote_urls.len == 0
}

// STUB: super::attachment_state::AttachmentState::attach_image.
pub fn (mut attachments AttachmentState) attach_image(mut textarea TextArea, path string) {
	placeholder := '[Image #${attachments.remote_urls.len + attachments.local_images.len + 1}]'
	textarea.insert_element(&placeholder)
	attachments.local_images << LocalImageAttachment{ path: path, placeholder: placeholder }
}

// STUB: super::attachment_state::AttachmentState local path projection.
pub fn (attachments &AttachmentState) local_image_paths() []string {
	return attachments.local_images.map(it.path.clone())
}

// STUB: super::attachment_state::AttachmentState local image projection.
pub fn (attachments &AttachmentState) local_images_copy() []LocalImageAttachment {
	return attachments.local_images.map(LocalImageAttachment{ path: it.path.clone(), placeholder: it.placeholder.clone() })
}

// STUB: super::attachment_state::AttachmentState remote URL projection.
pub fn (attachments &AttachmentState) remote_image_urls() []string {
	return attachments.remote_urls.clone()
}

// STUB: super::attachment_state::AttachmentState::remote_image_lines.
pub fn (attachments &AttachmentState) remote_image_lines() []rat_text.Line {
	selected := attachments.selected_remote_image_index or { -1 }
	mut lines := []rat_text.Line{cap: attachments.remote_urls.len}
	for index, _ in attachments.remote_urls {
		lines << rat_text.Line{
			spans: [rat_text.Span{
				text:  local_image_label_text(index + 1)
				style: if selected == index {
					rat_style.Style.default().reversed()
				} else {
					rat_style.Style.default()
				}
			}]
		}
	}
	// V's ownership checker currently treats repeated array append as consuming the local. The
	// attachment owner returns an independently owned vector, so materialize that result explicitly.
	return lines.clone()
}

// STUB: super::attachment_state::AttachmentState::handle_remote_image_selection_key.
pub fn (mut attachments AttachmentState) handle_remote_image_selection_key(key_event &terminal_event.KeyEvent,
	mut textarea TextArea) ?(InputResult, bool) {
	if attachments.remote_urls.len == 0 {
		return none
	}
	if selected := attachments.selected_remote_image_index {
		match key_event.code.kind {
			.up {
				attachments.selected_remote_image_index = max_int(selected - 1, 0)
			}
			.down {
				if selected + 1 >= attachments.remote_urls.len {
					attachments.selected_remote_image_index = none
				} else {
					attachments.selected_remote_image_index = selected + 1
				}
			}
			.delete, .backspace {
				attachments.remote_urls.delete(selected)
				attachments.selected_remote_image_index = none
				attachments.relabel_local_images(mut textarea)
			}
			else {
				return none
			}
		}
		return input_result_none(), true
	}
	if key_event.code.kind == .up && textarea.cursor() == 0 {
		attachments.selected_remote_image_index = attachments.remote_urls.len - 1
		return input_result_none(), true
	}
	return none
}

// STUB: super::attachment_state::AttachmentState::clear_remote_image_selection.
pub fn (mut attachments AttachmentState) clear_remote_image_selection() {
	attachments.selected_remote_image_index = none
}

// STUB: super::attachment_state::AttachmentState remote URL setter.
pub fn (mut attachments AttachmentState) set_remote_image_urls(urls []string, mut textarea TextArea) {
	attachments.remote_urls = urls
	attachments.relabel_local_images(mut textarea)
}

// STUB: super::attachment_state::AttachmentState remote URL drain.
pub fn (mut attachments AttachmentState) take_remote_image_urls(mut textarea TextArea) []string {
	urls := attachments.remote_urls.clone()
	attachments.remote_urls.clear()
	attachments.relabel_local_images(mut textarea)
	return urls
}

// STUB: super::attachment_state::AttachmentState remote URL clear.
pub fn (mut attachments AttachmentState) clear_remote_image_urls() {
	attachments.remote_urls.clear()
}

// STUB: super::attachment_state::AttachmentState local reset.
pub fn (mut attachments AttachmentState) reset_local_images(paths []string, mut textarea TextArea) {
	attachments.local_images.clear()
	image_elements := textarea.text_element_snapshots().filter(it.text.starts_with('[Image #'))
	for index, path in paths {
		expected := '[Image #${attachments.remote_urls.len + index + 1}]'
		mut matched := ?TextElementSnapshot(none)
		for element in image_elements {
			if element.text == expected {
				matched = element
				break
			}
		}
		if element := matched {
			attachments.local_images << LocalImageAttachment{
				path:        path
				placeholder: element.text.clone()
			}
		} else if index < image_elements.len {
			// Older history can lack placeholder payloads. Preserve source attachment ordering as the
			// compatibility fallback when a numbered label cannot be recovered.
			attachments.local_images << LocalImageAttachment{
				path:        path
				placeholder: image_elements[index].text.clone()
			}
		} else {
			attachments.attach_image(mut textarea, path)
		}
	}
}

// STUB: super::attachment_state::AttachmentState placeholder reconciliation.
pub fn (mut attachments AttachmentState) remove_deleted_local_placeholders(removed &[]string, mut textarea TextArea) {
	attachments.local_images = attachments.local_images.filter(it.placeholder !in *removed)
	attachments.relabel_local_images(mut textarea)
}

// STUB: super::attachment_state::AttachmentState relabeling.
pub fn (mut attachments AttachmentState) relabel_local_images(mut textarea TextArea) {
	mut saved_cursor := textarea.cursor()
	for index, image in attachments.local_images {
		old := image.placeholder.clone()
		new_label := '[Image #${attachments.remote_urls.len + index + 1}]'
		if old != new_label {
			old_len := old.len
			if start := textarea.buffer.index(old) {
				textarea.replace_range(start, start + old_len, &new_label)
				textarea.add_element_range(start, start + new_label.len)
				if start < saved_cursor {
					saved_cursor += new_label.len - old_len
				}
			}
			attachments.local_images[index] = LocalImageAttachment{
				path:        image.path.clone()
				placeholder: new_label
			}
		}
	}
	textarea.set_cursor(saved_cursor)
}

// STUB: super::attachment_state::AttachmentState submission pruning.
pub fn (mut attachments AttachmentState) prune_local_images_for_submission(text &string, _elements &[]user_input.TextElement) {
	attachments.local_images = attachments.local_images.filter((*text).contains(it.placeholder))
	attachments.recent_submission_images = attachments.local_images_copy()
}

// STUB: super::attachment_state::AttachmentState recent submission drain.
pub fn (mut attachments AttachmentState) take_recent_submission_images() []string {
	paths := attachments.local_images.map(it.path.clone())
	attachments.recent_submission_images.clear()
	attachments.local_images.clear()
	return paths
}

// STUB: super::attachment_state::AttachmentState recent submission drain with placeholders.
pub fn (mut attachments AttachmentState) take_recent_submission_images_with_placeholders() []LocalImageAttachment {
	images := attachments.local_images.map(LocalImageAttachment{ path: it.path.clone(), placeholder: it.placeholder.clone() })
	attachments.recent_submission_images.clear()
	attachments.local_images.clear()
	return images
}

// STUB: super::draft_state::ComposerMentionBinding.
pub struct ComposerMentionBinding {
pub:
	sigil   rune
	mention string
	path    string
}

// STUB: super::draft_state::DraftState.
pub struct DraftState {
mut:
	textarea                           TextArea
	textarea_state                     TextAreaState
	is_bash_mode                       bool
	pending_pastes                     []PendingPaste
	mention_bindings                   map[u64]ComposerMentionBinding
	recent_submission_mention_bindings []MentionBinding
	paste_burst                        PasteBurst
	disable_paste_burst                bool
	input_enabled                      bool = true
	input_disabled_placeholder         ?string
}

// STUB: super::draft_state::DraftState::new.
pub fn DraftState.new() DraftState {
	return DraftState{ textarea: TextArea.new(), input_enabled: true }
}

// STUB: super::popup_state::ActivePopup variant tags. V uses an explicit tagged payload struct
// below because option-bearing enum variants are not ownership-safe in the current compiler.
pub enum ActivePopupKind {
	none
	command
	file
	skill
	mention_v2
}

// STUB: super::command_popup::CommandPopup payload retained by ActivePopup::Command.
pub struct CommandPopup {
mut:
	commands       []SlashCommandItem
	items          []SlashCommandItem
	filter         string
	selected_index int
}

// STUB: super::file_search_popup::FileSearchPopup payload retained by ActivePopup::File.
pub struct FileSearchPopup {
mut:
	display_query  string
	pending_query  string
	waiting        bool
	matches        []codex_file_search.FileMatch
	selected_index int
}

// STUB: super::skill_popup::SkillPopup payload retained by ActivePopup::Skill.
pub struct SkillPopup {
mut:
	items          []MentionItem
	query          string
	selected_index int
}

// STUB: super::mentions_v2::MentionV2Popup payload retained by ActivePopup::MentionV2.
pub struct MentionV2Popup {
mut:
	candidates     []MentionItem
	items          []MentionItem
	query          string
	selected_index int
	search_mode    int
}

// STUB: super::file_search_popup::FileSearchPopup::new.
pub fn FileSearchPopup.new() FileSearchPopup {
	return FileSearchPopup{ waiting: true }
}

// STUB: super::file_search_popup::FileSearchPopup::set_query.
pub fn (mut popup FileSearchPopup) set_query(query &string) {
	if popup.pending_query == *query {
		return
	}
	popup.pending_query = query.clone()
	popup.waiting = true
}

// STUB: super::file_search_popup::FileSearchPopup::set_empty_prompt.
pub fn (mut popup FileSearchPopup) set_empty_prompt() {
	popup.display_query = ''
	popup.pending_query = ''
	popup.waiting = false
	popup.matches.clear()
	popup.selected_index = 0
}

// STUB: super::file_search_popup::FileSearchPopup::set_matches.
pub fn (mut popup FileSearchPopup) set_matches(query &string,
	matches []codex_file_search.FileMatch) {
	if *query != popup.pending_query {
		return
	}
	popup.display_query = query.clone()
	popup.matches = matches[..min_int(matches.len, 8)].clone()
	popup.waiting = false
	popup.selected_index = clamp_int(popup.selected_index, 0, max_int(0, popup.matches.len - 1))
}

// STUB: super::skill_popup::SkillPopup::new.
pub fn SkillPopup.new(mentions []MentionItem) SkillPopup {
	return SkillPopup{ items: mentions }
}

// STUB: super::skill_popup::SkillPopup::set_mentions.
pub fn (mut popup SkillPopup) set_mentions(mentions []MentionItem) {
	popup.items = mentions
	popup.selected_index = clamp_int(popup.selected_index, 0, max_int(0, popup.items.len - 1))
}

// STUB: super::skill_popup::SkillPopup::set_query.
pub fn (mut popup SkillPopup) set_query(query &string) {
	popup.query = query.clone()
	popup.selected_index = clamp_int(popup.selected_index, 0, max_int(0, popup.items.len - 1))
}

// STUB: super::mentions_v2::MentionV2Popup::new.
pub fn MentionV2Popup.new(candidates []MentionItem, query &string) MentionV2Popup {
	return MentionV2Popup{
		candidates: candidates.clone()
		items:      candidates
		query:      query.clone()
	}
}

// STUB: super::mentions_v2::MentionV2Popup::set_query.
pub fn (mut popup MentionV2Popup) set_query(query &string) {
	popup.query = query.clone()
	popup.selected_index = clamp_int(popup.selected_index, 0, max_int(0, popup.items.len - 1))
}

// STUB: super::mentions_v2::MentionV2Popup::set_candidates.
pub fn (mut popup MentionV2Popup) set_candidates(candidates []MentionItem) {
	files := popup.items.filter((it.category_tag or { '' }) == '[File]')
	popup.candidates = candidates.clone()
	popup.items = files
	popup.items << candidates
	popup.selected_index = clamp_int(popup.selected_index, 0, max_int(0, popup.items.len - 1))
}

// STUB: super::mentions_v2::MentionV2Popup::set_file_matches.
pub fn (mut popup MentionV2Popup) set_file_matches(query &string,
	matches []codex_file_search.FileMatch) {
	if popup.query != *query {
		return
	}
	mut file_items := matches[..min_int(matches.len, 8)].map(MentionItem{
		display_name: it.path.clone()
		insert_text:  it.path.clone()
		search_terms: [it.path.clone()]
		category_tag: '[File]'
	})
	file_items << popup.candidates.clone()
	popup.items = file_items
	popup.selected_index = clamp_int(popup.selected_index, 0, max_int(0, popup.items.len - 1))
}

// STUB: super::popup_state::ActivePopup. This explicit tagged representation preserves each
// Rust variant's distinct payload without a universal string/array payload.
pub struct ActivePopup {
pub mut:
	kind       ActivePopupKind
	command    CommandPopup
	file       FileSearchPopup
	skill      SkillPopup
	mention_v2 MentionV2Popup
}

// STUB: chat_composer/popup_state.rs::DismissedToken. This preserves stable token identity while
// that nested Rust module remains flattened to avoid a V module cycle with TextArea.
pub struct DismissedToken {
pub:
	query      string
	token      string
	occurrence int
}

// STUB: chat_composer/popup_state.rs::DismissedToken::new.
pub fn DismissedToken.new(textarea &TextArea, start int, end int, query string) DismissedToken {
	text := textarea.text()
	safe_start := clamp_int(start, 0, text.len)
	safe_end := clamp_int(end, safe_start, text.len)
	token := text[safe_start..safe_end].clone()
	return DismissedToken{
		query:      query
		token:      token.clone()
		occurrence: complete_token_occurrences_before(textarea, &token, safe_start)
	}
}

// STUB: chat_composer/popup_state.rs::DismissedToken::matches.
pub fn (dismissed &DismissedToken) matches(textarea &TextArea, start int, end int,
	query &string) bool {
	text := textarea.text()
	if dismissed.query != *query || start < 0 || end < start || end > text.len
		|| text[start..end] != dismissed.token {
		return false
	}
	return complete_token_occurrences_before(textarea, &dismissed.token, start) == dismissed.occurrence
}

// STUB: chat_composer/popup_state.rs::complete_token_occurrences_before.
fn complete_token_occurrences_before(textarea &TextArea, token &string, before int) int {
	text := textarea.text()
	limit := clamp_int(before, 0, text.len)
	elements := textarea.text_elements()
	mut count := 0
	prefix := text[..limit]
	for start in substring_occurrences(&prefix, token) {
		end := start + token.len
		mut starts_at_boundary := start == 0 || rune_is_space(text[..start].runes().last())
		mut ends_at_boundary := end == text.len
			|| (end < text.len && rune_is_space(text[end..].runes()[0]))
		for element in elements {
			if element.byte_range.end == start {
				starts_at_boundary = true
			}
			if element.byte_range.start == end {
				ends_at_boundary = true
			}
		}
		if starts_at_boundary && ends_at_boundary {
			count++
		}
	}
	return count
}

// STUB: super::popup_state::PopupState.
pub struct PopupState {
mut:
	active                  ActivePopup
	current_file_query      OwnedStringSlot
	dismissed_command_token ?string
	dismissed_file_token    ?DismissedToken
	dismissed_mention_token ?DismissedToken
}

// STUB: V ownership-safe representation of popup_state's borrowed Option<String> query cache.
struct OwnedStringSlot {
mut:
	present bool
	value   string
}

// STUB: private popup selection wrap helper shared by untranslated popup owners.
fn previous_popup_index(selected int, item_count int) int {
	if item_count <= 0 {
		return 0
	}
	return if selected <= 0 { item_count - 1 } else { selected - 1 }
}

// STUB: private popup selection wrap helper shared by untranslated popup owners.
fn next_popup_index(selected int, item_count int) int {
	if item_count <= 0 {
		return 0
	}
	return (selected + 1) % item_count
}

// STUB: super::command_popup::CommandPopup::move_up.
pub fn (mut popup CommandPopup) move_up() {
	popup.selected_index = previous_popup_index(popup.selected_index, popup.items.len)
}

// STUB: super::command_popup::CommandPopup::move_down.
pub fn (mut popup CommandPopup) move_down() {
	popup.selected_index = next_popup_index(popup.selected_index, popup.items.len)
}

// STUB: super::file_search_popup::FileSearchPopup::move_up.
pub fn (mut popup FileSearchPopup) move_up() {
	popup.selected_index = previous_popup_index(popup.selected_index, popup.matches.len)
}

// STUB: super::file_search_popup::FileSearchPopup::move_down.
pub fn (mut popup FileSearchPopup) move_down() {
	popup.selected_index = next_popup_index(popup.selected_index, popup.matches.len)
}

// STUB: super::skill_popup::SkillPopup::move_up.
pub fn (mut popup SkillPopup) move_up() {
	popup.selected_index = previous_popup_index(popup.selected_index, popup.items.len)
}

// STUB: super::skill_popup::SkillPopup::move_down.
pub fn (mut popup SkillPopup) move_down() {
	popup.selected_index = next_popup_index(popup.selected_index, popup.items.len)
}

// STUB: super::mentions_v2::Popup::move_up.
pub fn (mut popup MentionV2Popup) move_up() {
	popup.selected_index = previous_popup_index(popup.selected_index, popup.items.len)
}

// STUB: super::mentions_v2::Popup::move_down.
pub fn (mut popup MentionV2Popup) move_down() {
	popup.selected_index = next_popup_index(popup.selected_index, popup.items.len)
}

// STUB: super::mentions_v2::Popup::previous_search_mode.
pub fn (mut popup MentionV2Popup) previous_search_mode() {
	popup.search_mode = if popup.search_mode <= 0 {
		2
	} else {
		popup.search_mode - 1
	}
}

// STUB: super::mentions_v2::Popup::next_search_mode.
pub fn (mut popup MentionV2Popup) next_search_mode() {
	popup.search_mode = (popup.search_mode + 1) % 3
}

// STUB: shared row painter used by the untranslated concrete popup widgets.
fn render_typed_popup_rows(rows []string, selected_index int, area rat_layout.Rect,
	mut buffer rat_buffer.Buffer) {
	for row in 0 .. area.height {
		index := int(row)
		if index >= rows.len {
			break
		}
		style := if index == selected_index {
			rat_style.Style.default().reversed()
		} else {
			rat_style.Style.default()
		}
		write_render_text(mut buffer, area.x, area.y + row, area.width, rows[index], style, [])
		buffer.lines << rows[index]
	}
}

// STUB: super::command_popup::CommandPopup::render_ref.
pub fn (popup &CommandPopup) render_ref(area rat_layout.Rect, mut buffer rat_buffer.Buffer) {
	mut rows := []string{}
	for command in popup.items {
		name := command.command()
		description := command.description()
		rows << if description.len > 0 { '  /${name}  ${description}' } else { '  /${name}' }
	}
	render_typed_popup_rows(rows, popup.selected_index, area, mut buffer)
}

// STUB: super::file_search_popup::FileSearchPopup::render_ref.
pub fn (popup &FileSearchPopup) render_ref(area rat_layout.Rect, mut buffer rat_buffer.Buffer) {
	rows := if popup.matches.len > 0 {
		popup.matches.map('  ${it.path}')
	} else {
		[
			'  loading...',
		]
	}
	render_typed_popup_rows(rows, popup.selected_index, area, mut buffer)
}

// STUB: super::skill_popup::SkillPopup::render_ref.
pub fn (popup &SkillPopup) render_ref(area rat_layout.Rect, mut buffer rat_buffer.Buffer) {
	mut rows := []string{}
	for item in popup.items {
		category := item.category_tag or { '' }
		description := item.description or { '' }
		label := if item.display_name.contains(':') {
			'${item.display_name.all_after(':')} (${item.display_name.all_before(':')})'
		} else {
			item.display_name
		}
		rows << '  ${label}  ${category} ${description}'.trim_right(' ')
	}
	rows << ''
	rows << '  Press enter to insert or esc to close'
	render_typed_popup_rows(rows, popup.selected_index, area, mut buffer)
}

// STUB: super::mentions_v2::Popup::render_ref.
pub fn (popup &MentionV2Popup) render_ref(area rat_layout.Rect, mut buffer rat_buffer.Buffer) {
	mut rows := []string{}
	mut name_width := 0
	for item in popup.items {
		name_width = max_int(name_width, item.display_name.runes().len)
	}
	for item in popup.items {
		description := item.description or { '' }
		category_value := (item.category_tag or { '' }).trim('[]')
		category := category_value + ' '.repeat(max_int(0, 6 - category_value.runes().len))
		prefix := if rows.len == popup.selected_index { '>' } else { ' ' }
		padded_name := item.display_name + ' '.repeat(max_int(0, name_width - item.display_name.runes().len))
		left := '${prefix} ${padded_name}  ${description}'.trim_right(' ')
		gap := max_int(2, int(area.width) - left.runes().len - category.runes().len)
		rows << left + ' '.repeat(gap) + category
	}
	rows << ''
	rows << '  enter insert · esc close · ←/→ switch search modes     [All Results]   Filesystem Only    Plugins'
	render_typed_popup_rows(rows, popup.selected_index, area, mut buffer)
}

// STUB: super::command_popup::CommandPopup::calculate_required_height.
pub fn (popup &CommandPopup) calculate_required_height(_width u16) u16 {
	return u16(min_int(popup.items.len, 8))
}

// STUB: super::file_search_popup::FileSearchPopup::calculate_required_height.
pub fn (popup &FileSearchPopup) calculate_required_height() u16 {
	return u16(min_int(max_int(popup.matches.len, 1), 8))
}

// STUB: super::skill_popup::SkillPopup::calculate_required_height.
pub fn (popup &SkillPopup) calculate_required_height(_width u16) u16 {
	return u16(min_int(max_int(popup.items.len, 1), 8) + 2)
}

// STUB: super::mentions_v2::Popup::calculate_required_height.
pub fn (popup &MentionV2Popup) calculate_required_height(_width u16) u16 {
	return u16(min_int(max_int(popup.items.len, 1), 8) + 2)
}

// STUB: super::popup_state::ActivePopup::required_height.
pub fn (popup &ActivePopup) required_height(width u16, footer_height u16) u16 {
	return match popup.kind {
		.none { footer_height }
		.command { popup.command.calculate_required_height(width) }
		.file { popup.file.calculate_required_height() }
		.skill { popup.skill.calculate_required_height(width) }
		.mention_v2 { popup.mention_v2.calculate_required_height(width) }
	}
}

// STUB: super::popup_state::PopupState::active.
pub fn (state &PopupState) is_active() bool {
	return state.active.kind != .none
}

// STUB: super::footer::FooterMode.
pub enum FooterMode {
	composer_empty
	composer_has_draft
	history_search
	esc_hint
	shortcut_overlay
	quit_shortcut_reminder
}

// STUB: `bottom_pane::QUIT_SHORTCUT_TIMEOUT`; represented in milliseconds because the translated
// footer stores wall-clock millisecond deadlines rather than Rust `Instant` values.
pub const quit_shortcut_timeout_ms = i64(1_000)

// STUB: super::footer::toggle_shortcut_mode.
pub fn toggle_shortcut_mode(current FooterMode, ctrl_c_hint bool, is_empty bool) FooterMode {
	if ctrl_c_hint && current == .quit_shortcut_reminder {
		return current
	}
	base_mode := if is_empty { FooterMode.composer_empty } else { FooterMode.composer_has_draft }
	return match current {
		.shortcut_overlay, .quit_shortcut_reminder { base_mode }
		else { .shortcut_overlay }
	}
}

// STUB: super::footer::esc_hint_mode.
pub fn esc_hint_mode(current FooterMode, is_task_running bool) FooterMode {
	return if is_task_running { current } else { .esc_hint }
}

// STUB: super::footer::reset_mode_after_activity.
pub fn reset_mode_after_activity(current FooterMode) FooterMode {
	return match current {
		.esc_hint, .shortcut_overlay, .quit_shortcut_reminder, .history_search,
		.composer_has_draft {
			.composer_empty
		}
		else { current }
	}
}

// STUB: super::footer::footer_height. ShortcutOverlay is the only multi-line instructional mode;
// the remaining modes each reserve one footer row.
pub fn footer_height(props &FooterProps) u16 {
	return if props.mode == .shortcut_overlay { u16(9) } else { u16(1) }
}

// STUB: super::footer::footer_from_props_lines for ShortcutOverlay. The untranslated footer owner
// chooses the same ordered descriptors and two fixed-width columns as the Rust widget.
fn shortcut_overlay_lines(props &FooterProps) []rat_text.Line {
	hint_label := fn (hint ?key_hint.ShortcutHint, fallback string) string {
		if value := hint {
			return value.display_label()
		}
		return fallback
	}
	queue_label := if props.queue_submissions { 'to queue message' } else { 'to submit message' }
	lefts := ['/ for commands', '${hint_label(props.key_hints.insert_newline, 'enter')} for newline',
		'@ for file paths',
		'${hint_label(props.key_hints.external_editor, 'ctrl + g')} to edit in external editor',
		'${hint_label(props.key_hints.history_search, 'ctrl + r')} search history',
		'${hint_label(props.key_hints.reasoning_down, '⌥ + ,')} reasoning down']
	rights := ['! for shell commands', '${hint_label(props.key_hints.queue, 'tab')} ${queue_label}',
		'ctrl + v to paste images', if props.esc_backtrack_hint {
			'esc again to edit previous message'
		} else {
			'esc esc to edit previous message'
		}, 'ctrl + c to exit', '${hint_label(props.key_hints.reasoning_up, '⌥ + .')} reasoning up']
	mut column_width := 0
	for left in lefts {
		column_width = max_int(column_width, left.runes().len + 8)
	}
	mut lines := []rat_text.Line{}
	for index, left in lefts {
		lines << rat_text.Line{
			spans: [rat_text.Span{
				text: left + ' '.repeat(max_int(1, column_width - left.runes().len)) + rights[index]
			}]
		}
	}
	lines << rat_text.Line{
		spans: [rat_text.Span{
			text: '${hint_label(props.key_hints.show_transcript, 'ctrl + t')} to view transcript'
		}]
	}
	lines << rat_text.Line{}
	lines << rat_text.Line{
		spans: [
			rat_text.Span{ text: 'customize shortcuts with /keymap' },
		]
	}
	// V's ownership checker currently treats repeated array append as consuming the local. The
	// footer owner returns an independently owned vector, so materialize that result explicitly.
	return lines.clone()
}

// STUB: super::footer::render_footer_from_props. The target invokes the eventual footer API; this
// target-specific boundary currently renders the exact ShortcutOverlay rows used by ChatComposer.
pub fn render_footer_from_props(area rat_layout.Rect, mut buffer rat_buffer.Buffer,
	props &FooterProps, _collaboration ?CollaborationModeIndicator, _show_cycle_hint bool,
	_show_shortcuts_hint bool, _show_queue_hint bool) {
	if props.mode != .shortcut_overlay {
		return
	}
	lines := shortcut_overlay_lines(props)
	for row in 0 .. min_int(lines.len, int(area.height)) {
		text := lines[row].spans.map(it.text).join('')
		write_render_text(mut buffer, area.x + min_u16(area.width, live_prefix_cols), area.y + u16(row), area.width - min_u16(area.width, live_prefix_cols), text, rat_style.Style.default().dim(), [])
		buffer.lines << text
	}
}

// STUB: super::footer::CollaborationModeIndicator.
pub enum CollaborationModeIndicator {
	plan
}

// STUB: super::footer::GoalStatusIndicator payload discriminants.
pub enum GoalStatusIndicatorKind {
	active
	paused
	blocked
	usage_limited
	budget_limited
	complete
}

// STUB: super::footer::GoalStatusIndicator. Rust carries optional usage only for Active,
// BudgetLimited, and Complete; the explicit tag prevents payload leakage into other variants.
pub struct GoalStatusIndicator {
pub:
	kind  GoalStatusIndicatorKind
	usage ?string
}

// STUB: super::footer::goal_status_indicator_line.
pub fn goal_status_indicator_line(indicator &GoalStatusIndicator) rat_text.Line {
	label := match indicator.kind {
		.active {
			if usage := indicator.usage { 'Pursuing goal (${usage})' } else { 'Pursuing goal' }
		}
		.paused { 'Goal paused (/goal resume)' }
		.blocked { 'Goal stalled (/goal resume)' }
		.usage_limited { 'Goal hit usage limits (/goal resume)' }
		.budget_limited {
			if usage := indicator.usage { 'Goal unmet (${usage})' } else { 'Goal abandoned' }
		}
		.complete {
			if usage := indicator.usage { 'Goal achieved (${usage})' } else { 'Goal achieved' }
		}
	}
	return rat_text.Line{
		spans: [
			rat_text.Span{ text: label, style: rat_style.Style.default().magenta() },
		]
	}
}

// STUB: super::footer::status_line_right_indicator_line.
pub fn status_line_right_indicator_line(collaboration ?CollaborationModeIndicator,
	goal ?GoalStatusIndicator, ide_context_active bool, show_cycle_hint bool) ?rat_text.Line {
	mut spans := []rat_text.Span{}
	if mode := collaboration {
		label := match mode {
			.plan {
				if show_cycle_hint { 'Plan mode (shift+tab to cycle)' } else { 'Plan mode' }
			}
		}
		spans << rat_text.Span{ text: label, style: rat_style.Style.default().magenta() }
	} else if goal_status := goal {
		spans << goal_status_indicator_line(&goal_status).spans
	}
	if ide_context_active {
		if spans.len > 0 {
			spans << rat_text.Span{ text: ' · ', style: rat_style.Style.default().dim() }
		}
		spans << rat_text.Span{
			text:  'IDE context'
			style: rat_style.Style.default().cyan()
		}
	}
	return if spans.len > 0 { rat_text.Line{ spans: spans } } else { none }
}

// STUB: super::footer::context_window_line.
pub fn context_window_line(percent ?i64, used_tokens ?i64) rat_text.Line {
	text := if value := percent {
		'${clamp_i64(value, 0, 100)}% context left'
	} else if tokens := used_tokens {
		'${format_tokens_compact(tokens)} used'
	} else {
		'100% context left'
	}
	return rat_text.Line{
		spans: [
			rat_text.Span{ text: text, style: rat_style.Style.default().dim() },
		]
	}
}

// STUB: private super::footer integer clamp used by the footer renderer.
fn clamp_i64(value i64, low i64, high i64) i64 {
	return if value < low {
		low
	} else if value > high {
		high
	} else {
		value
	}
}

// STUB: private super::footer token-count formatter.
fn format_tokens_compact(tokens i64) string {
	abs_tokens := if tokens < 0 { -tokens } else { tokens }
	if abs_tokens < 1_000 {
		return '${tokens}'
	}
	if abs_tokens < 1_000_000 {
		whole := tokens / 1_000
		tenths := (abs_tokens % 1_000) / 100
		return if tenths == 0 { '${whole}k' } else { '${whole}.${tenths}k' }
	}
	whole := tokens / 1_000_000
	tenths := (abs_tokens % 1_000_000) / 100_000
	return if tenths == 0 { '${whole}m' } else { '${whole}.${tenths}m' }
}

// STUB: super::footer_state::FooterState.
pub struct FooterState {
mut:
	flash                           ?FooterFlash
	quit_shortcut_expires_at        i64
	quit_shortcut_key               key_hint.KeyBinding
	esc_backtrack_hint              bool
	use_shift_enter_hint            bool
	mode                            FooterMode
	hint_override                   ?[][]string
	context_window_percent          ?i64
	context_window_used_tokens      ?i64
	context_window_pending          bool
	collaboration_mode_indicator    ?CollaborationModeIndicator
	goal_status_indicator           ?GoalStatusIndicator
	ide_context_active              bool
	status_line_value               ?rat_text.Line
	status_line_hyperlink_url       ?string
	status_line_enabled             bool
	side_conversation_context_label ?string
	active_agent_label              ?string
	external_editor_key             ?key_hint.ShortcutHint
	show_transcript_key             ?key_hint.ShortcutHint
	insert_newline_key              ?key_hint.ShortcutHint
	queue_key                       ?key_hint.ShortcutHint
	toggle_shortcuts_key            ?key_hint.ShortcutHint
	history_search_key              ?key_hint.ShortcutHint
	reasoning_down_key              ?key_hint.ShortcutHint
	reasoning_up_key                ?key_hint.ShortcutHint
}

// STUB: super::footer_state::FooterFlash stores transient footer content until its deadline.
pub struct FooterFlash {
pub:
	line       rat_text.Line
	expires_at i64
}

// STUB: super::footer_state::ChatComposer::show_footer_flash.
pub fn (mut composer ChatComposer) show_footer_flash(line rat_text.Line, duration_ms i64) {
	composer.footer.flash = FooterFlash{
		line:       line
		expires_at: time.now().unix_milli() + duration_ms
	}
}

// STUB: super::footer_state::FooterState::flash_visible.
pub fn (footer &FooterState) flash_visible() bool {
	if flash := footer.flash {
		return flash.expires_at > time.now().unix_milli()
	}
	return false
}

// STUB: super::effort_ignition::EffortTier.
pub enum EffortTier {
	max
	ultra
}

// STUB: super::effort_ignition::IgnitionStyle.
pub enum IgnitionStyle {
	wave
	aurora
	pulse
}

// STUB: super::effort_ignition::IgnitionStyle::random. The eventual animation module supplies
// entropy; this boundary still guarantees that consecutive one-shot styles do not repeat.
pub fn IgnitionStyle.random(previous ?IgnitionStyle) IgnitionStyle {
	for candidate in [IgnitionStyle.wave, .aurora, .pulse] {
		if old := previous {
			if candidate == old {
				continue
			}
		}
		return candidate
	}
	return .wave
}

// STUB: super::effort_ignition::EffortIgnition.
pub struct EffortIgnition {
pub:
	tier          EffortTier
	style         IgnitionStyle
	started_at_ms i64
	cancelled     bool
}

// STUB: super::effort_ignition::EffortIgnition::new. Rust's Cell starts the clock on first render;
// immutable V render receivers cannot mutate an embedded value, so the V boundary starts it at
// construction, immediately before the composer requests its first frame.
pub fn EffortIgnition.new(tier EffortTier, style IgnitionStyle) EffortIgnition {
	return EffortIgnition{ tier: tier, style: style, started_at_ms: time.now().unix_milli() }
}

// STUB: super::effort_ignition::EffortIgnition::is_finished animation boundary.
pub fn (ignition &EffortIgnition) is_finished() bool {
	if ignition.cancelled {
		return true
	}
	elapsed := time.now().unix_milli() - ignition.started_at_ms
	max_ms := match ignition.style {
		.wave {
			if ignition.tier == .max { i64(1_000) } else { i64(1_300) }
		}
		.aurora {
			if ignition.tier == .max { i64(1_300) } else { i64(1_600) }
		}
		.pulse {
			if ignition.tier == .max { i64(900) } else { i64(1_250) }
		}
	}
	return elapsed >= max_ms
}

// STUB: super::effort_ignition::EffortIgnition::render. The eventual animation module owns its
// time-varying cell pattern; this boundary preserves the single protected content rectangle.
pub fn (ignition &EffortIgnition) render(composer_rect rat_layout.Rect,
	protected_rect rat_layout.Rect, mut buffer rat_buffer.Buffer) bool {
	_ = ignition
	_ = composer_rect
	_ = protected_rect
	_ = buffer
	return true
}

// STUB: super::effort_ignition::EffortIgnition::charge_alpha.
pub fn (ignition &EffortIgnition) charge_alpha() f32 {
	elapsed := time.now().unix_milli() - ignition.started_at_ms
	return f32(clamp_i64(elapsed, 0, 150)) / 150.0
}

// STUB: super::effort_ignition::EffortTier::prompt. The eventual animation module supplies charge
// interpolation; the stable tier colors and owned prompt glyph are preserved here.
pub fn (tier EffortTier) prompt(charge f32) (rat_style.Style, string) {
	style, glyph := match tier {
		.max { rat_style.Style.default().yellow(), '›' }
		.ultra { rat_style.Style.default().magenta(), '»' }
	}
	return if charge > 0.0 { style.bold() } else { style }, glyph
}

// STUB: super::chat_composer::sparkle::Sparkle animation state.
pub struct Sparkle {}

// STUB: chat_composer/sparkle.rs::ChatComposer::render_sparkle. The future animation module owns
// sparkle trajectories; this call boundary keeps the cursor exclusion and buffer ownership exact.
pub fn (composer &ChatComposer) render_sparkle(area rat_layout.Rect, cursor ?CursorPosition,
	mut buffer rat_buffer.Buffer) {
	_ = composer
	_ = area
	_ = cursor
	_ = buffer
}

// STUB: super::effort_status_line::EffortStatusLineTransition.
pub struct EffortStatusLineTransition {
pub:
	tier     EffortTier
	previous rat_text.Line
	finished bool
}

// STUB: super::effort_status_line::EffortStatusLineTransition::is_finished.
pub fn (transition &EffortStatusLineTransition) is_finished() bool {
	return transition.finished
}

// STUB: super::effort_status_line::EffortStatusLineTransition::render_line. Animation interpolation
// remains owned by the sibling module; the prior passive status line remains the stable frame.
pub fn (transition &EffortStatusLineTransition) render_line(_current ?rat_text.Line,
	_width u16) rat_text.Line {
	return transition.previous
}

// STUB: super::footer::passive_footer_status_line.
pub fn passive_footer_status_line(props &FooterProps) ?rat_text.Line {
	shows_passive := props.mode == .composer_empty
		|| (props.mode == .composer_has_draft && !props.is_task_running)
	if !shows_passive {
		return none
	}
	mut spans := []rat_text.Span{}
	if props.status_line_enabled {
		if line := props.status_line_value {
			spans << line.spans
		}
	}
	if label := props.active_agent_label {
		if spans.len > 0 {
			spans << rat_text.Span{ text: ' · ', style: rat_style.Style.default().dim() }
		}
		spans << rat_text.Span{ text: label, style: rat_style.Style.default().dim() }
	}
	if spans.len > 0 {
		return rat_text.Line{ spans: spans }
	}
	return none
}

// STUB: super::footer::uses_passive_footer_status_layout.
pub fn uses_passive_footer_status_layout(props &FooterProps) bool {
	return props.status_line_enabled
		&& (props.mode == .composer_empty
			|| (props.mode == .composer_has_draft && !props.is_task_running))
}

// STUB: super::footer::max_left_width_for_right.
pub fn max_left_width_for_right(area rat_layout.Rect, right_width u16) ?u16 {
	if right_width == 0 || area.width <= live_prefix_cols + right_width {
		return if right_width == 0 {
			area.width - min_u16(area.width, live_prefix_cols)
		} else {
			u16(0)
		}
	}
	return area.width - live_prefix_cols - right_width - 1
}

// STUB: super::footer::can_show_left_with_context.
pub fn can_show_left_with_context(area rat_layout.Rect, left_width u16,
	context_width u16) bool {
	if context_width == 0 || left_width == 0 {
		return true
	}
	return live_prefix_cols + left_width + 1 + context_width + live_prefix_cols <= area.width
}

// STUB: super::footer::render_footer_line.
pub fn render_footer_line(area rat_layout.Rect, mut buffer rat_buffer.Buffer,
	line rat_text.Line) {
	text := line.spans.map(it.text).join('')
	style := if line.spans.len > 0 { line.spans[0].style } else { rat_style.Style{} }
	write_render_text(mut buffer, area.x + min_u16(area.width, live_prefix_cols), area.y, area.width - min_u16(area.width, live_prefix_cols), text, style, [])
}

// STUB: super::footer::render_context_right.
pub fn render_context_right(area rat_layout.Rect, mut buffer rat_buffer.Buffer,
	line rat_text.Line) {
	text := line.spans.map(it.text).join('')
	width := min_int(text.runes().len, int(area.width))
	x := area.x + area.width - u16(width) - min_u16(area.width - u16(width), live_prefix_cols)
	style := if line.spans.len > 0 { line.spans[0].style } else { rat_style.Style.default().dim() }
	write_render_text(mut buffer, x, area.y, u16(width), text, style, [])
}

// STUB: crate::line_utils::truncate_line_with_ellipsis_if_overflow.
pub fn truncate_line_with_ellipsis_if_overflow(line rat_text.Line, max_width int) rat_text.Line {
	text := line.spans.map(it.text).join('')
	if text.runes().len <= max_width {
		return line
	}
	if max_width <= 0 {
		return rat_text.Line{}
	}
	if max_width == 1 {
		return rat_text.Line{ spans: [rat_text.Span{ text: '…' }] }
	}
	return rat_text.Line{
		spans: [
			rat_text.Span{ text: text.runes()[..max_width - 1].string() + '…' },
		]
	}
}

// STUB: self::history_search::HistorySearchStatus.
pub enum HistorySearchStatus {
	idle
	searching
	match_found
	no_match
}

// STUB: self::history_search::HistorySearchSession fields observed by ChatComposer rendering.
pub struct HistorySearchSession {
mut:
	query  string
	status HistorySearchStatus
}

// STUB: self::vim_history::VimHistory retains complete composer-owned drafts at edit boundaries.
pub struct VimHistory {
mut:
	undo    []ComposerDraft
	redo    []ComposerDraft
	pending ?ComposerDraft
}

// STUB: super::skill_popup::MentionItem.
pub struct MentionItem {
pub:
	display_name string
	description  ?string
	insert_text  string
	search_terms []string
	path         ?string
	category_tag ?string
	sort_rank    int
}

// STUB: super::mentions_v2::build_search_catalog. This preserves candidate ordering, hides skills
// owned by a listed plugin, and normalizes task titles before the mentions-v2 module is ported.
pub fn build_mentions_v2_catalog(skills ?[]skill_metadata.SkillMetadata, plugins ?[]codex_plugin.PluginCapabilitySummary,
	tasks &[]task_mentions.TaskMention) []MentionItem {
	mut plugin_ids := []string{}
	if plugin_values := plugins {
		plugin_ids = plugin_values.map(it.config_name.clone())
	}
	mut skill_candidates := []MentionItem{}
	if skill_values := skills {
		for skill in skill_values {
			if plugin_id := skill.plugin_id {
				if plugin_id in plugin_ids {
					continue
				}
			}
			display_name := if skill_interface := skill.interface {
				skill_interface.display_name or { skill.name.clone() }
			} else {
				skill.name.clone()
			}
			mut search_terms := [skill.name.clone()]
			if display_name != skill.name {
				search_terms << display_name.clone()
			}
			qualified_display := if skill.name.contains(':') {
				'${skill.name.all_after(':')} (${skill.name.all_before(':')})'
			} else {
				display_name
			}
			skill_candidates.prepend(MentionItem{
				display_name: qualified_display.clone()
				description:  skill_description(&skill)
				insert_text:  '\$${skill.name}'
				search_terms: search_terms.clone()
				path:         skill.path.clone()
				category_tag: '[Skill]'
				sort_rank:    1
			})
		}
	}
	mut candidates := []MentionItem{}
	if plugin_values := plugins {
		for plugin in plugin_values {
			name := plugin.config_name.all_before('@')
			candidates << MentionItem{
				display_name: plugin.display_name.clone()
				description:  plugin.description
				insert_text:  '@${name}'
				search_terms: [name, plugin.config_name.clone()]
				path:         'plugin://${plugin.config_name}'
				category_tag: '[Plugin]'
			}
		}
	}
	for task in *tasks {
		title := task.title.fields().join(' ').runes()[..min_int(task.title.fields().join(' ').runes().len, 160)].string()
		candidates << MentionItem{
			display_name: title.clone()
			description:  if task.cwd.len > 0 { task.cwd.clone() } else { none }
			insert_text:  '@${title}'
			search_terms: [title.clone(), task.cwd, task.snippet]
			path:         'thread://${task.thread_id}'
			category_tag: '[Task]'
			sort_rank:    1
		}
	}
	candidates << skill_candidates
	return candidates
}

// STUB: super::mentions_v2::MentionV2Selection.
pub struct MentionV2Selection {
pub:
	insert_text string
	path        string
}

// STUB: super::footer::FooterProps.
pub struct FooterProps {
pub:
	mode                        FooterMode
	esc_backtrack_hint          bool
	use_shift_enter_hint        bool
	is_task_running             bool
	queue_submissions           bool
	quit_shortcut_key           key_hint.KeyBinding
	collaboration_modes_enabled bool
	is_wsl                      bool
	status_line_value           ?rat_text.Line
	status_line_enabled         bool
	key_hints                   FooterKeyHints
	active_agent_label          ?string
}

// STUB: super::footer::FooterKeyHints.
pub struct FooterKeyHints {
pub:
	agents           ?key_hint.ShortcutHint
	toggle_shortcuts ?key_hint.ShortcutHint
	queue            ?key_hint.ShortcutHint
	insert_newline   ?key_hint.ShortcutHint
	external_editor  ?key_hint.ShortcutHint
	edit_previous    ?key_hint.ShortcutHint
	show_transcript  ?key_hint.ShortcutHint
	history_search   ?key_hint.ShortcutHint
	reasoning_down   ?key_hint.ShortcutHint
	reasoning_up     ?key_hint.ShortcutHint
}

// STUB: super::slash_commands::SlashCommandItem::description. Service-tier rows retain their
// catalog description rather than sharing a universal command payload.
pub fn (item &SlashCommandItem) description() string {
	return if item.kind == .builtin {
		item.builtin.description()
	} else {
		item.service_tier.description.clone()
	}
}

// STUB: self::slash_input::SubmissionValidation discriminants.
pub enum SubmissionValidationKind {
	valid
	unknown_command
}

// STUB: self::slash_input::SlashValidation.
pub enum SlashValidation {
	immediate
	deferred
}

// STUB: cfg(test) path module `chat_composer/agents_navigation_tests.rs`. Its test bodies belong
// to that separate source file and are outside the requested chat_composer.rs translation.
const agents_navigation_tests_module_stub = true

// STUB: cfg(test) path module `chat_composer_effort_tests.rs`. Its test bodies belong to that
// separate source file and are outside the requested chat_composer.rs translation.
const effort_tests_module_stub = true

// STUB: cfg(test) path module `chat_composer/embedded_input_tests.rs`. Its test bodies belong to
// that separate source file and are outside the requested chat_composer.rs translation.
const embedded_input_tests_module_stub = true

// STUB: self::slash_input::SubmissionValidation payload.
pub struct SubmissionValidation {
pub:
	kind SubmissionValidationKind
	name string
}

// STUB: self::slash_input::InlineCommand. Rust borrows `rest` from input; V returns an owned
// string while retaining the exact byte offset for TextElement rebasing.
pub struct InlineCommand {
pub:
	command     SlashCommandItem
	rest        string
	rest_offset int
}

// STUB: self::slash_input::SlashInput.
pub struct SlashInput {
pub:
	enabled               bool
	bash_mode             bool
	command_flags         BuiltinCommandFlags
	service_tier_commands []ServiceTierCommand
}

// STUB: self::slash_input::SlashInput::new.
pub fn SlashInput.new(enabled bool, bash_mode bool, flags BuiltinCommandFlags,
	service_tier_commands &[]ServiceTierCommand) SlashInput {
	return SlashInput{
		enabled:               enabled
		bash_mode:             bash_mode
		command_flags:         flags
		service_tier_commands: service_tier_commands.clone()
	}
}

// STUB: super::slash_commands::find_slash_command. Feature-gated built-ins and enabled service
// tiers share one typed lookup result, matching the Rust payload enum.
pub fn (input &SlashInput) command(name &string) ?SlashCommandItem {
	return find_slash_command(name, input.command_flags, &input.service_tier_commands)
}

// STUB: self::slash_input::SlashInput::validate_submission.
pub fn (input &SlashInput) validate_submission(text &string,
	starts_with_space bool) SubmissionValidation {
	if !input.enabled || input.bash_mode || starts_with_space || !text.starts_with('/') {
		return SubmissionValidation{ kind: .valid }
	}
	name, _, _ := prompt_args.parse_slash_name(text) or { return SubmissionValidation{ kind: .valid } }
	if name.contains('/') || input.command(&name) != none {
		return SubmissionValidation{ kind: .valid }
	}
	return SubmissionValidation{ kind: .unknown_command, name: name }
}

// STUB: self::slash_input::SlashInput::bare_command.
pub fn (input &SlashInput) bare_command(text &string) ?SlashCommandItem {
	if !input.enabled || input.bash_mode {
		return none
	}
	first_line := text.all_before('\n')
	name, rest, _ := prompt_args.parse_slash_name(&first_line) or { return none }
	if rest.len > 0 {
		return none
	}
	command := input.command(&name) or { return none }
	if command.supports_inline_args() {
		_, full_rest, _ := prompt_args.parse_slash_name(text) or { return none }
		if full_rest.len > 0 {
			return none
		}
	}
	return command
}

// STUB: self::slash_input::SlashInput::inline_command. Rust borrows the remainder from `text`; V
// returns an owned string while retaining its exact byte offset for TextElement rebasing.
pub fn (input &SlashInput) inline_command(text &string) ?InlineCommand {
	if !input.enabled || input.bash_mode || text.starts_with(' ') {
		return none
	}
	name, rest, rest_offset := prompt_args.parse_slash_name(text) or { return none }
	if rest.len == 0 || name.contains('/') {
		return none
	}
	command := input.command(&name) or { return none }
	if !command.supports_inline_args() {
		return none
	}
	return InlineCommand{
		command:     command
		rest:        rest
		// Existing TextElement ranges use V's signed string indices.
		rest_offset: int(rest_offset)
	}
}

// STUB: self::slash_input::command_popup_filter_text. V returns an owned string because it cannot
// borrow the command prefix from `first_line`.
pub fn command_popup_filter_text(first_line &string, cursor int) ?string {
	if !first_line.starts_with('/') || cursor < 0 || cursor > first_line.len {
		return none
	}
	mut name_end := first_line.len
	for index in 1 .. first_line.len {
		if (*first_line)[index] in [` `, `\t`, `\n`, `\r`] {
			name_end = index
			break
		}
	}
	effective_cursor := if cursor <= 1 { name_end } else { cursor }
	if effective_cursor > name_end {
		return none
	}
	return '/' + (*first_line)[1..effective_cursor]
}

// STUB: self::slash_input::SlashInput::is_editing_command_name.
pub fn (input &SlashInput) is_editing_command_name(first_line &string, cursor int) bool {
	filter := command_popup_filter_text(first_line, cursor) or { return false }
	if !input.enabled {
		return false
	}
	name := filter.trim_left('/')
	if name.len == 0 {
		return first_line.len == 1
	}
	for command in slash_command_catalog() {
		command_name := command.command()
		if input.command(&command_name) != none && fuzzy_match(&command_name, &name) {
			return true
		}
	}
	if input.command_flags.service_tier_commands_enabled {
		for service in input.service_tier_commands {
			if fuzzy_match(&service.name, &name) {
				return true
			}
		}
	}
	return false
}

// STUB: self::slash_input::SlashInput::should_parse_on_dequeue.
pub fn (input &SlashInput) should_parse_on_dequeue(text &string) bool {
	return input.enabled && !text.starts_with(' ') && text.trim_space().starts_with('/')
}

// STUB: self::slash_input::queued_input_action.
pub fn queued_input_action(prepared_text &string, defer_slash_validation bool) QueuedInputAction {
	if defer_slash_validation && prepared_text.starts_with('/') {
		return .parse_slash
	}
	if prepared_text.starts_with('!') {
		return .run_shell
	}
	return .plain
}

// STUB: self::slash_input feature flags assembled by its untranslated source owner.
pub fn (composer &ChatComposer) builtin_command_flags() BuiltinCommandFlags {
	return BuiltinCommandFlags{
		collaboration_modes_enabled:    composer.collaboration_modes_enabled
		connectors_enabled:             composer.connectors_enabled
		plugins_command_enabled:        composer.plugins_command_enabled
		token_activity_command_enabled: composer.token_activity_command_enabled
		service_tier_commands_enabled:  composer.service_tier_commands_enabled
		goal_command_enabled:           composer.goal_command_enabled
		personality_command_enabled:    composer.personality_command_enabled
		voice_command_enabled:          composer.voice_command_enabled
		worktrees_enabled:              composer.worktrees_enabled
		allow_elevate_sandbox:          composer.windows_degraded_sandbox_active
		side_conversation_active:       composer.side_conversation_active
	}
}

// STUB: self::vim_history::begin_direct_vim_edit.
pub fn (mut composer ChatComposer) begin_direct_vim_edit() bool {
	if !composer.draft.textarea.is_vim_enabled() || composer.vim_history.pending != none
		|| composer.history_search != none {
		return false
	}
	composer.vim_history.pending = composer.snapshot_draft()
	return true
}

// STUB: self::vim_history::finish_vim_edit.
pub fn (mut composer ChatComposer) finish_vim_edit() {
	if !composer.draft.textarea.is_vim_normal_mode() {
		return
	}
	snapshot := composer.vim_history.pending or { return }
	composer.vim_history.pending = none
	if snapshot.text == composer.current_text()
		&& snapshot.text_elements == composer.current_text_elements()
		&& snapshot.pending_pastes == composer.draft.pending_pastes
		&& snapshot.local_image_paths == composer.attachments.local_image_paths()
		&& snapshot.remote_image_urls == composer.attachments.remote_image_urls()
		&& snapshot.mention_bindings == composer.snapshot_mention_bindings() {
		return
	}
	composer.vim_history.redo.clear()
	composer.vim_history.undo << snapshot
}

// STUB: self::vim_history::begin_vim_edit.
pub fn (mut composer ChatComposer) begin_vim_edit(_input terminal_event.KeyEvent) {
	if !composer.draft.textarea.is_vim_enabled() || composer.vim_history.pending != none {
		return
	}
	composer.vim_history.pending = composer.snapshot_draft()
}

// STUB: self::vim_history::reset_vim_mode.
pub fn (mut composer ChatComposer) reset_vim_mode() {
	composer.draft.textarea.enter_vim_insert_mode()
}

// STUB: self::vim_history::handle_vim_history_key.
pub fn (mut composer ChatComposer) handle_vim_history_key(event terminal_event.KeyEvent) bool {
	if !composer.draft.textarea.is_vim_normal_mode() || composer.popups.is_active()
		|| event.code.kind != .char_key || event.modifiers != terminal_event.KeyModifiers{} {
		return false
	}
	redo := event.code.ch == `r`
	undo := event.code.ch == `u`
	if !undo && !redo {
		return false
	}
	mut history := VimHistory{
		undo: composer.vim_history.undo.clone()
		redo: composer.vim_history.redo.clone()
	}
	snapshot := if redo {
		if history.redo.len == 0 {
			return true
		}
		history.redo.pop()
	} else {
		if history.undo.len == 0 {
			return true
		}
		history.undo.pop()
	}
	current := composer.snapshot_draft()
	if redo {
		history.undo << current
	} else {
		history.redo << current
	}
	composer.restore_draft(snapshot)
	composer.vim_history = history
	composer.draft.textarea.enter_vim_normal_mode()
	return true
}

// STUB: self::history_search::handle_history_search_key.
pub fn (mut composer ChatComposer) handle_history_search_key(event terminal_event.KeyEvent) (InputResult, bool) {
	if event.kind in [.press, .repeat] && event.code.kind == .char_key
		&& !event.modifiers.control && !event.modifiers.alt {
		if mut search := composer.history_search {
			search.query += event.code.ch.str()
			search.status = .idle
			for index := composer.history.entries.len - 1; index >= 0; index-- {
				entry := composer.history.entries[index]
				if entry.text.contains(search.query) {
					search.status = .match_found
					composer.history_search = search
					composer.apply_history_entry(entry)
					return input_result_none(), true
				}
			}
			composer.history_search = search
		}
	}
	return input_result_none(), true
}

// STUB: self::history_search::begin_history_search. The session marker preserves key-routing
// ownership while the richer query/preview state remains with the untranslated sibling module.
pub fn (mut composer ChatComposer) begin_history_search() (InputResult, bool) {
	composer.history_search = HistorySearchSession{}
	return input_result_none(), true
}

// STUB: self::history_search test accessor.
pub fn (composer &ChatComposer) history_search_active() bool {
	return composer.history_search != none
}

// STUB: `chat_composer/vim_search.rs::vim_search_cursor_pos`; positions the cursor at the end of
// the textarea-owned footer query and clamps it inside the allocated footer row.
pub fn (composer &ChatComposer) vim_search_cursor_pos(area rat_layout.Rect) ?CursorPosition {
	query := composer.draft.textarea.vim_query_text() or { return none }
	areas := composer.layout_areas(area)
	footer := areas[3]
	if footer.width == 0 || footer.height == 0 {
		return none
	}
	indent := min_u16(u16(2), footer.width - 1)
	query_width := u16(query.runes().len + 'search: '.len)
	return CursorPosition{
		x: footer.x + min_u16(indent + query_width, footer.width - 1)
		y: footer.y + footer.height - 1
	}
}

// STUB: `chat_composer/history_search.rs::history_search_footer_line`; preserves query and status
// content while the child module's styled ratatui widgets remain untranslated.
pub fn (composer &ChatComposer) history_search_footer_line() ?rat_text.Line {
	search := composer.history_search or { return none }
	status := match search.status {
		.searching { '  searching' }
		.match_found { '  enter accept · esc cancel' }
		.no_match { '  no match' }
		.idle { '' }
	}
	return rat_text.Line{
		spans: [rat_text.Span{ text: 'reverse-i-search: ' }, rat_text.Span{
			text:  search.query.clone()
			style: rat_style.Style.default().cyan()
		}, rat_text.Span{ text: status }]
	}
}

// STUB: `chat_composer/history_search.rs::history_search_cursor_pos`; follows the end of the
// reverse-search query rather than the textarea preview.
pub fn (composer &ChatComposer) history_search_cursor_pos(area rat_layout.Rect) ?CursorPosition {
	search := composer.history_search or { return none }
	areas := composer.layout_areas(area)
	footer := areas[3]
	if footer.width == 0 || footer.height == 0 {
		return none
	}
	indent := min_u16(u16(2), footer.width - 1)
	query_width := u16('reverse-i-search: '.len + search.query.runes().len)
	return CursorPosition{
		x: footer.x + min_u16(indent + query_width, footer.width - 1)
		y: footer.y + footer.height - 1
	}
}

// STUB: `chat_composer/reconnect.rs::handle_paste_enter`. The untranslated reconnect module owns
// the timing-window half; active buffers are preserved exactly and slash commands still dispatch.
pub fn (mut composer ChatComposer) handle_paste_enter(now_ms i64) bool {
	first_line := composer.draft.textarea.text().all_before('\n')
	in_slash_context := composer.slash_commands_enabled() && !composer.draft.is_bash_mode
		&& (composer.popups.active.kind == .command || first_line.starts_with('/'))
	if !composer.draft.disable_paste_burst && composer.draft.paste_burst.is_active()
		&& !in_slash_context && composer.draft.paste_burst.append_newline_if_active(now_ms) {
		return true
	}
	return false
}

// STUB: self::inline_input::sync_slash_command_elements. This preserves the sibling module's
// observable range-marking behavior until inline_input itself is translated.
pub fn (mut composer ChatComposer) sync_slash_command_elements() {
	if !composer.slash_commands_enabled() || composer.draft.is_bash_mode {
		return
	}
	text := composer.draft.textarea.text()
	first_line := text.all_before('\n')
	mut desired_end := 0
	if first_line.starts_with('/') && !first_line.starts_with('//') {
		without := first_line[1..]
		mut token_end := without.len
		for index, byte in without.bytes() {
			if byte in [` `, `\t`, `\r`, `\n`] {
				token_end = index
				break
			}
		}
		name := without[..token_end]
		element_end := 1 + name.len
		has_space_after := element_end < first_line.len
		cursor := composer.draft.textarea.cursor()
		cursor_inside_name := cursor > 0 && cursor < element_end
		if name.len > 0 && !name.contains('/') && has_space_after && !cursor_inside_name
			&& slash_command_from_name(&name) != none {
			desired_end = element_end
		}
	}
	composer_text := composer.draft.textarea.text()
	for element in composer.draft.textarea.text_elements() {
		placeholder := element.placeholder_text(&composer_text) or { '' }
		if placeholder.starts_with('/')
			&& (element.byte_range.start != 0 || element.byte_range.end != desired_end) {
			composer.draft.textarea.remove_element_range(element.byte_range.start, element.byte_range.end)
		}
	}
	if desired_end > 0
		&& composer.draft.textarea.element_id_for_exact_range(0, desired_end) == none {
		composer.draft.textarea.add_element_range(0, desired_end)
	}
}

// STUB: self::inline_input::handle_key_event_with_slash_popup.
pub fn (mut composer ChatComposer) handle_key_event_with_slash_popup(key_event terminal_event.KeyEvent) (InputResult, bool) {
	if key_event.code.kind == .escape {
		first_line := composer.draft.textarea.text().all_before('\n')
		composer.popups.dismissed_command_token = command_popup_filter_text(&first_line,
			/* cursor */
			0)
		composer.popups.active = ActivePopup{}
		return input_result_none(), true
	}
	if key_event.code.kind == .enter {
		if command := composer.popups.active.command.selected_item() {
			if composer.reject_slash_command_if_unavailable(&command) {
				composer.stage_selected_slash_command_history(&command)
				composer.record_pending_slash_command_history()
				return input_result_none(), true
			}
			composer.stage_selected_slash_command_history(&command)
			empty := ''
			composer.draft.textarea.set_text_clearing_elements(&empty)
			if command.kind == .service_tier {
				return InputResult{ kind: .service_tier_command, service_tier: command.service_tier }, true
			}
			return InputResult{ kind: .command, command: command.builtin }, true
		}
	}
	if key_event.code.kind == .tab || (key_event.code.kind == .char_key && key_event.code.ch == `/`) {
		if command := composer.popups.active.command.selected_item() {
			command_name := command.command()
			completed := '/${command_name} '
			composer.draft.textarea.set_text_clearing_elements(&completed)
			composer.draft.textarea.set_cursor(completed.len)
			composer.popups.active = ActivePopup{}
			return input_result_none(), true
		}
	}
	return composer.handle_input_basic(key_event)
}

// STUB: self::command_popup ranking. Exact source ranking is owned by CommandPopup; this ordered
// catalog preserves its observable prefix choices used by composer completion and dispatch.
fn popup_ranked_slash_commands() []slash_command.SlashCommand {
	return slash_command_catalog()
}

// STUB: super::command_popup::CommandPopup::new plus on-composer-text filtering. The resulting
// payload retains the typed command items selected by the active variant.
pub fn CommandPopup.new(input &SlashInput, filter_text &string) CommandPopup {
	mut commands := []SlashCommandItem{}
	for item in commands_for_input(input.command_flags, &input.service_tier_commands) {
		if item.kind == .builtin && (item.builtin == .apps || item.builtin.command().starts_with('debug')) {
			continue
		}
		commands << item
	}
	mut popup := CommandPopup{ commands: commands }
	popup.on_composer_text_change(filter_text.clone())
	return popup
}

// STUB: self::slash_input::SlashInput::command_popup.
pub fn (input &SlashInput) command_popup(filter_text &string) CommandPopup {
	return CommandPopup.new(input, filter_text)
}

// STUB: super::command_popup::CommandPopup::on_composer_text_change.
pub fn (mut popup CommandPopup) on_composer_text_change(text string) {
	first_line := text.all_before('\n')
	stripped := if first_line.starts_with('/') { first_line[1..].trim_left(' \t') } else { '' }
	filter := stripped.fields()[0] or { '' }
	previous := popup.filter
	popup.filter = filter.clone()
	popup.items = popup.commands.filter((filter.len > 0 || it.kind == .service_tier
		|| it.builtin !in [.quit, .btw]) && (filter.len == 0 || it.command().starts_with(filter)))
	if popup.filter != previous {
		popup.selected_index = 0
	}
	if popup.items.len == 0 {
		popup.selected_index = 0
	} else {
		popup.selected_index = clamp_int(popup.selected_index, 0, popup.items.len - 1)
	}
}

// STUB: super::command_popup::CommandPopup::selected_item.
pub fn (popup &CommandPopup) selected_item() ?SlashCommandItem {
	if popup.items.len == 0 {
		return none
	}
	return popup.items[clamp_int(popup.selected_index, 0, popup.items.len - 1)]
}

// STUB: super::file_search_popup::FileSearchPopup::selected_match. Rust returns a borrowed Path;
// V returns an owned path string because it cannot express that slice lifetime.
pub fn (popup &FileSearchPopup) selected_match() ?string {
	if popup.matches.len == 0 {
		return none
	}
	index := clamp_int(popup.selected_index, 0, popup.matches.len - 1)
	return popup.matches[index].path.clone()
}

// STUB: super::skill_popup::SkillPopup::selected_mention. The eventual owner returns a shared
// borrow; V's optional-reference C generation is unreliable, so this explicit result is owned.
pub fn (popup &SkillPopup) selected_mention() ?MentionItem {
	if popup.items.len == 0 {
		return none
	}
	return popup.items[clamp_int(popup.selected_index, 0, popup.items.len - 1)]
}

// STUB: super::mentions_v2::Popup::selected.
pub fn (popup &MentionV2Popup) selected() ?MentionV2Selection {
	if popup.items.len == 0 {
		return none
	}
	item := popup.items[clamp_int(popup.selected_index, 0, popup.items.len - 1)]
	return MentionV2Selection{
		insert_text: item.insert_text.clone()
		path:        item.path or { '' }
	}
}

// STUB: self::command_popup selected-item lookup. Prefix candidates outrank fuzzy-only matches.
fn selected_popup_command(filter string) ?SlashCommandItem {
	commands := popup_ranked_slash_commands()
	for command in commands {
		if command.command().starts_with(filter) {
			return SlashCommandItem{ kind: .builtin, builtin: command }
		}
	}
	for command in commands {
		name := command.command()
		if fuzzy_match(&name, &filter) {
			return SlashCommandItem{ kind: .builtin, builtin: command }
		}
	}
	return none
}

// STUB: self::history_search::apply_history_search_result.
pub fn (mut composer ChatComposer) apply_history_search_result(result HistorySearchResult) {
	if result.kind == .found {
		composer.apply_history_entry(result.entry)
	}
}

// STUB: self::agents_navigation::agents_navigation_available.
pub fn (composer &ChatComposer) agents_navigation_available() bool {
	return composer.agents_navigation_enabled && composer.is_empty() && composer.input_enabled()
}
