module codex_app_server_protocol

import codex_protocol.models

// STUB: codex_app_server_protocol::RequestId variant tags. Rust's payload enum is represented by
// an explicit tag with variant-specific storage.
pub enum RequestIdKind {
	string_id
	integer
}

// STUB: codex_app_server_protocol::RequestId, the JSON-RPC request id.
pub struct RequestId {
pub:
	kind         RequestIdKind
	string_value string
	integer      i64
}

// STUB: codex_app_server_protocol::RequestId::String.
pub fn RequestId.string(value string) RequestId {
	return RequestId{
		kind:         .string_id
		string_value: value
	}
}

// STUB: codex_app_server_protocol::ClientRequest::ThreadSearch payload.
pub struct ClientRequestThreadSearch {
pub:
	request_id RequestId
	params     ThreadSearchParams
}

// STUB: codex_app_server_protocol::ClientRequest::ThreadList payload.
pub struct ClientRequestThreadList {
pub:
	request_id RequestId
	params     ThreadListParams
}

// STUB: codex_app_server_protocol::ClientRequest variants issued by task-mention search
// and optional collaboration-mode discovery.
pub type ClientRequest = ClientRequestConfigRead
	| ClientRequestConfigBatchWrite
	| ClientRequestEnvironmentInfo
	| ClientRequestSkillsConfigWrite
	| ClientRequestOneOffCommandExec
	| ClientRequestGetAuthStatus
	| ClientRequestConfigRequirementsRead
	| ClientRequestPermissionProfileList
	| ClientRequestThreadStart
	| ClientRequestTurnStart
	| ClientRequestThreadUnsubscribe
	| ClientRequestCollaborationModeList
	| ClientRequestThreadList
	| ClientRequestThreadRead
	| ClientRequestThreadQueueAdd
	| ClientRequestThreadSearch

// STUB: codex_app_server_protocol::ByteRange (v2 turn input), a byte range within UTF-8 text.
pub struct ByteRange {
pub mut:
	start int
	end   int
}

// STUB: codex_app_server_protocol::TextElement (v2 turn input).
pub struct TextElement {
pub mut:
	// Byte range in the parent `text` buffer that this element occupies.
	byte_range ByteRange
mut:
	// Optional human-readable placeholder for the element, displayed in the UI.
	placeholder ?string
}

// STUB: codex_app_server_protocol::TextElement::new.
pub fn TextElement.new(byte_range ByteRange, placeholder ?string) TextElement {
	return TextElement{
		byte_range:  byte_range
		placeholder: placeholder
	}
}

// STUB: codex_app_server_protocol::UserInput::Text.
pub struct UserInputText {
pub mut:
	text string
	// UI-defined spans within `text` used to render or persist special elements.
	text_elements []TextElement
}

// STUB: codex_app_server_protocol::UserInput::Image, including optional image detail.
pub struct UserInputImage {
pub:
	detail ?models.ImageDetail
	url    string
}

// STUB: codex_app_server_protocol::UserInput::LocalImage, including optional image detail.
pub struct UserInputLocalImage {
pub:
	detail ?models.ImageDetail
	path   string
}

// STUB: codex_app_server_protocol::UserInput::Audio.
pub struct UserInputAudio {
pub:
	url string
}

// STUB: codex_app_server_protocol::UserInput::LocalAudio.
pub struct UserInputLocalAudio {
pub:
	path string
}

// STUB: codex_app_server_protocol::UserInput::Skill.
pub struct UserInputSkill {
pub:
	name string
	path string
}

// STUB: codex_app_server_protocol::UserInput::Mention.
pub struct UserInputMention {
pub:
	name string
	path string
}

// STUB: codex_app_server_protocol::UserInput (v2 turn input).
pub type UserInput = UserInputAudio
	| UserInputImage
	| UserInputLocalAudio
	| UserInputLocalImage
	| UserInputMention
	| UserInputSkill
	| UserInputText
