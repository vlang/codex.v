// Prompt rendering for IDE context injected into TUI user turns.
module prompt

import codex_app_server_protocol as api
import codex_tui.ide_context.model
import encoding.utf8
import strings

const max_active_selection_chars = 40_000
const max_open_tabs = 100
const max_open_tabs_chars = 20_000
// Match the desktop app and IDE extension delimiter exactly. IDE context is serialized into the
// raw prompt before this marker, then transcript rendering strips back to the request after the last
// marker. Keeping the same marker and stripping semantics lets threads created with IDE context in
// one surface replay cleanly in the others.
const prompt_request_begin = '## My request for Codex:'

pub fn apply_ide_context_to_user_input(context &model.IdeContext, mut items []api.UserInput) bool {
	context_text := render_prompt_context(context) or { return false }
	prefix := '${context_text}\n${prompt_request_begin}\n'
	mut text_index := -1
	for index in 0 .. items.len {
		if items[index] is api.UserInputText {
			text_index = index
			break
		}
	}
	if text_index >= 0 {
		// Prefix the existing text item in place so image and text items keep
		// the same relative order they had in the user's original submission.
		item := items[text_index]
		items[text_index] = api.UserInputText{}
		if item is api.UserInputText {
			items[text_index] = prefixed_text_input(prefix, item.text, item.text_elements)
		} else {
			panic('position matched a text item')
		}
	} else {
		items.insert(0, api.UserInputText{ text: prefix, text_elements: []api.TextElement{} })
	}
	return true
}

pub fn has_prompt_context(context &model.IdeContext) bool {
	if _ := render_prompt_context(context) {
		return true
	}
	return false
}

// V cannot return Rust's borrowed &str substring. The input remains borrowed,
// and the returned request is explicitly copied into an owned V string.
pub fn extract_prompt_request_with_offset(message &string) (string, usize) {
	marker_start := (*message).last_index(prompt_request_begin) or { return message.clone(), usize(0) }
	request_start := marker_start + prompt_request_begin.len
	mut leading_trimmed_len := 0
	mut trimmed_end := request_start
	mut found_content := false
	mut byte_index := request_start
	for byte_index < message.len {
		value := utf8.get_rune(*message, byte_index)
		width := utf8_char_len((*message)[byte_index])
		// Rust trim uses Unicode White_Space. V's utf8.is_space currently misses
		// U+3000 in this compiler, so keep the source's complete scalar set here.
		is_whitespace := value in [` `, `\t`, `\n`, `\r`, `\v`, `\f`, `\u0085`, `\u00a0`, `\u1680`,
			`\u2000`, `\u2001`, `\u2002`, `\u2003`, `\u2004`, `\u2005`, `\u2006`, `\u2007`, `\u2008`,
			`\u2009`, `\u200a`, `\u2028`, `\u2029`, `\u202f`, `\u205f`, `\u3000`]
		if !found_content && is_whitespace {
			leading_trimmed_len += width
		} else {
			found_content = true
			if !is_whitespace {
				trimmed_end = byte_index + width
			}
		}
		byte_index += width
	}
	trimmed_start := request_start + leading_trimmed_len
	if !found_content {
		return '', usize(trimmed_start)
	}
	return (*message)[trimmed_start..trimmed_end].clone(), usize(trimmed_start)
}

fn prefixed_text_input(prefix string, text string, text_elements []api.TextElement) api.UserInput {
	prefix_len := prefix.len
	mut shifted_elements := []api.TextElement{cap: text_elements.len}
	for index in 0 .. text_elements.len {
		element := &text_elements[index]
		// ByteRange.clone copies its two scalar endpoints at the source clone boundary.
		range := api.ByteRange{ start: element.byte_range.start, end: element.byte_range.end }
		shifted_elements << api.TextElement.new(api.ByteRange{
			start: range.start + prefix_len
			end:   range.end + prefix_len
		}, element.placeholder().to_owned())
	}
	return api.UserInputText{ text: '${prefix}${text}', text_elements: shifted_elements }
}

fn render_prompt_context(context &model.IdeContext) ?string {
	mut ide_context_section := strings.new_builder(256)
	if active_file := context.active_file {
		ide_context_section.write_string('\n## Active file: ${active_file.descriptor.path}\n')
	}
	if active_file := context.active_file {
		mut selected_ranges := []&model.Range{}
		if active_file.selections.len == 0 {
			if active_file.selection.start != active_file.selection.end {
				selected_ranges << &active_file.selection
			}
		} else {
			for index in 0 .. active_file.selections.len {
				range := &active_file.selections[index]
				if range.start != range.end {
					selected_ranges << range
				}
			}
		}
		if selected_ranges.len > 0 && (active_file.active_selection_content.len == 0 || selected_ranges.len > 1) {
			if selected_ranges.len == 1 {
				ide_context_section.write_string('\n## Active selection range:\n')
			} else {
				ide_context_section.write_string('\n## Active selection ranges:\n')
			}
			for range in selected_ranges {
				// Render ranges as 1-based positions for the prompt.
				start_line := range.start.line + 1
				start_column := range.start.character + 1
				end_line := range.end.line + 1
				end_column := range.end.character + 1
				ide_context_section.write_string('- ${active_file.descriptor.path}: line ${start_line}, column ${start_column} to line ${end_line}, column ${end_column}\n')
			}
		}
	}
	if active_file := context.active_file {
		if active_file.active_selection_content.len > 0 {
			ide_context_section.write_string('\n## Active selection of the file:\n')
			selection := &active_file.active_selection_content
			mut truncate_at := 0
			mut chars := 0
			for truncate_at < selection.len && chars < max_active_selection_chars {
				truncate_at += utf8_char_len((*selection)[truncate_at])
				chars++
			}
			if truncate_at < selection.len {
				ide_context_section.write_string((*selection)[..truncate_at])
				ide_context_section.write_string('\n[Selection truncated to ${max_active_selection_chars} characters.]\n')
			} else {
				ide_context_section.write_string(*selection)
			}
		}
	}
	if context.open_tabs.len > 0 {
		ide_context_section.write_string('\n## Open tabs:\n')
		mut rendered_tabs := 0
		mut rendered_tab_chars := 0
		for index in 0 .. context.open_tabs.len {
			if rendered_tabs >= max_open_tabs {
				break
			}
			tab := &context.open_tabs[index]
			tab_line := '- ${tab.label}: ${tab.path}\n'
			if rendered_tab_chars + tab_line.len > max_open_tabs_chars {
				break
			}
			ide_context_section.write_string(tab_line)
			rendered_tabs++
			rendered_tab_chars += tab_line.len
		}
		omitted_tabs := context.open_tabs.len - rendered_tabs
		if omitted_tabs > 0 {
			ide_context_section.write_string('[${omitted_tabs} open tabs omitted.]\n')
		}
	}
	if ide_context_section.len == 0 {
		return none
	}
	return '# Context from my IDE setup:\n${ide_context_section.str()}'
}
