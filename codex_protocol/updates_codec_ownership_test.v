module codex_protocol

fn updates_codec_owned(literal &string) string {
	$if ownership ? {
		return literal.to_owned()
	} $else {
		return literal.clone()
	}
}

// V's production C generator removes assert statements, so this check must
// execute in the release build that selects the new encoder.
fn updates_codec_require(condition bool) {
	if !condition {
		panic('borrowed communication changed during response serialization')
	}
}

fn test_response_serialization_repeatedly_borrows_heap_communication() {
	author := '/root'
	recipient := '/root/reviewer'
	other := '/root/worker'
	content := 'review the existing changes'
	encrypted := 'owned ciphertext'
	communication := InterAgentCommunication{
		author:            AgentPath{ value: updates_codec_owned(&author) }
		recipient:         AgentPath{ value: updates_codec_owned(&recipient) }
		other_recipients:  [AgentPath{ value: updates_codec_owned(&other) }]
		content:           updates_codec_owned(&content)
		encrypted_content: updates_codec_owned(&encrypted)
		trigger_turn:      true
	}
	first := communication.to_response_input_item()
	second := communication.to_response_input_item()
	updates_codec_require(first.content[0].text == second.content[0].text)
	updates_codec_require(first.content[0].text.contains(content))
	updates_codec_require(communication.author.value == author)
	updates_codec_require(communication.recipient.value == recipient)
	updates_codec_require(communication.other_recipients[0].value == other)
	updates_codec_require(communication.content == content)
	updates_codec_require((communication.encrypted_content or { panic('ciphertext moved') }) == encrypted)
}
