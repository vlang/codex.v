module task_mentions

import codex_app_server_protocol as api
import codex_protocol.thread_id as protocol_thread_id
import codex_protocol.user_input
import codex_tui.bottom_pane
import codex_tui.mention_codec

fn test_task_mention_history_round_trips_multiword_and_escaped_titles() {
	title := 'Fix ]( parser \\ safely'
	text := 'Inspect x@${title} next'
	mention := mention_codec.LinkedMention{
		sigil:   `@`
		mention: title
		path:    'thread://task-123'
	}

	mentions := [mention]
	elements := [
		user_input.TextElement.new(user_input.ByteRange{
			start: 'Inspect x'.len
			end:   'Inspect x@'.len + title.len
		}, none),
	]
	encoded := mention_codec.encode_history_mentions_at_elements(&text, &mentions, &elements)
	assert encoded == 'Inspect x[@Fix \\]\\( parser \\\\ safely](thread://task-123) next'
	at_mentions_enabled := true
	decoded := mention_codec.decode_history_mentions_with_at_mentions(&encoded, at_mentions_enabled)
	assert decoded.text == text
	assert decoded.mentions == mentions
	too_long := '[@${'x'.repeat(max_task_title_chars + 1)}](thread://task-123)'
	start := 0
	assert parse_task_link(&too_long, start) == none
	for path in ['thread://', 'thread://../settings', 'thread://task?target'] {
		assert valid_thread_path(&path) == none, path
	}
	long_id := 'thread://${'x'.repeat(65)}'
	assert valid_thread_path(&long_id) == none
	malformed := '[@é](thread://task-123)'
	for end in [3, malformed.len + 1] {
		decoded_text, decoded_elements := decode_task_links(&malformed, [
			user_input.TextElement.new(user_input.ByteRange{ start: 0, end: end }, none),
		])
		assert decoded_text == malformed
		assert decoded_elements.len == 0
	}
	literal := '[@actual](thread://task-456)'
	pair := '${literal} ${literal}'
	pair_text, _ := decode_task_links(&pair, [
		user_input.TextElement.new(user_input.ByteRange{ start: 0, end: literal.len }, none),
		user_input.TextElement.new(user_input.ByteRange{
			start: literal.len + 1
			end:   literal.len * 2 + 1
		}, '@actual'),
	])
	assert pair_text == '${literal} @actual'
}

fn test_task_reference_context_deduplicates_and_merges_with_ide_context() {
	title := 'Review the migration'
	visible := 'Compare plain @${title} with plugin @${title} and selected @${title}x'
	binding := bottom_pane.MentionBinding{
		sigil:   `@`
		mention: title
		path:    'thread://task-123'
	}
	text := '# IDE: @${title}\n## My request for Codex:\n${visible}'
	plugin_start := (text.index('plugin @') or { panic('plugin mention') }) + 'plugin '.len
	selected_start := text.last_index('@${title}') or { panic('selected task') }
	mut text_elements := []api.TextElement{}
	for element_start in [plugin_start, selected_start] {
		text_elements << api.TextElement.new(api.ByteRange{
			start: element_start
			end:   element_start + title.len + 1
		}, '@${title}')
	}
	mut items := [
		api.UserInput(api.UserInputText{
			text:          text
			text_elements: text_elements
		}),
	]

	current_thread_id := ?protocol_thread_id.ThreadId(none)
	referenced_bindings := [
		bottom_pane.MentionBinding{
			sigil:   `@`
			mention: title
			path:    'plugin://sample@test'
		},
		// Rust passes `binding.clone(), binding`.
		bottom_pane.MentionBinding{
			sigil:   binding.sigil
			mention: binding.mention.clone()
			path:    binding.path.clone()
		},
		binding,
	]
	apply_task_references(mut items, &referenced_bindings, current_thread_id)

	assert items.len == 1, 'expected text with deduplicated task references'
	updated := items[0] as api.UserInputText
	assert updated.text.starts_with('# IDE: @Review the migration\n## Referenced chats')
	assert updated.text.count('## My request for Codex:') == 1
	assert updated.text.count('"threadId":"task-123"') == 1
	assert updated.text.contains('MUST call `read_thread`')
	assert updated.text.ends_with('Compare plain @Review the migration with plugin @Review the migration and selected [@Review the migration](thread://task-123)x')

	for id_len in [36, 64] {
		mut bindings := []bottom_pane.MentionBinding{}
		for index in 0 .. max_referenced_tasks {
			// Rust formats `thread://{index:0id_len$}`: the index zero-padded to `id_len` digits.
			digits := index.str()
			bindings << bottom_pane.MentionBinding{
				sigil:   `@`
				mention: 'task'
				path:    'thread://${'0'.repeat(id_len - digits.len)}${digits}'
			}
		}
		mut empty_items := [
			api.UserInput(api.UserInputText{
				text:          ''
				text_elements: []api.TextElement{}
			}),
		]
		apply_task_references(mut empty_items, &bindings, current_thread_id)
		empty_text := (empty_items[0] as api.UserInputText).text
		expected := if max_referenced_tasks < max_referenced_thread_id_bytes / id_len {
			max_referenced_tasks
		} else {
			max_referenced_thread_id_bytes / id_len
		}
		assert empty_text.count('"threadId":') == expected
	}
}

fn test_task_reference_heading_inside_selected_title_is_not_a_context_boundary() {
	title := 'Review ${request_heading} carefully'
	mut items := [
		api.UserInput(api.UserInputText{
			text:          '@${title}'
			text_elements: [
				api.TextElement.new(api.ByteRange{ start: 0, end: title.len + 1 }, none),
			]
		}),
	]

	current_thread_id := ?protocol_thread_id.ThreadId(none)
	bindings := [
		bottom_pane.MentionBinding{
			sigil:   `@`
			mention: title
			path:    'thread://task-123'
		},
	]
	apply_task_references(mut items, &bindings, current_thread_id)

	assert items.len == 1, 'expected text with a task reference'
	updated := items[0] as api.UserInputText
	assert updated.text.starts_with('## Referenced chats with Codex:')
	assert updated.text.ends_with('[@${title}](thread://task-123)')
}
