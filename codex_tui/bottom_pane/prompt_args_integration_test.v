module bottom_pane

import codex_protocol.user_input
import codex_tui.app_event_sender
import crossterm.event

fn owned_prompt_integration_string(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

// The canonical prompt parser must feed byte offsets into actual composer dispatch.
// Both separators are three-byte Unicode whitespace characters. Keeping the image
// element checks that parsing trims the separator and rebases its full-text range.
fn test_composer_plan_preserves_element_ranges_after_unicode_command_separator() {
	mut composer := ChatComposer.new(true, app_event_sender.AppEventSender{}, false,
		owned_prompt_integration_string('Ask Codex to do anything'), false)
	composer.set_collaboration_modes_enabled(true)
	full_text := owned_prompt_integration_string('/plan\u2003\u3000[Image #1]')
	placeholder := owned_prompt_integration_string('[Image #1]')
	start := full_text.len - placeholder.len
	composer.set_text_content(full_text.clone(), [user_input.TextElement.new(user_input.ByteRange{
		start: start
		end:   full_text.len
	}, placeholder.clone())], [])

	result, _ := composer.handle_key_event(event.KeyEvent.new(event.key_code_enter,
		event.key_modifiers_none))
	assert result.kind == .command_with_args
	assert result.command.command() == 'plan'
	assert result.text == placeholder
	assert result.text_elements.len == 1
	assert result.text_elements[0].byte_range == user_input.ByteRange{
		start: 0
		end:   placeholder.len
	}
	assert full_text[start..] == placeholder
	// Rust dispatch keeps the draft until the command requests prepared arguments.
	assert composer.current_text() == full_text
	prepared := composer.prepare_inline_args_submission(false) or { panic('missing inline arguments') }
	assert prepared.text == placeholder
	assert prepared.elements.len == 1
	assert prepared.elements[0].byte_range == user_input.ByteRange{
		start: 0
		end:   placeholder.len
	}
	assert composer.current_text() == ''
}
