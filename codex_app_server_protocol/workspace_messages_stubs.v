module codex_app_server_protocol

// STUB: app-server-protocol/src/protocol/v2/account.rs API response declaration;
// the protocol owner still supplies its serde/TS/schema derives.
pub struct GetWorkspaceMessagesResponse {
pub:
	// Whether the workspace-message backend route is available for this client.
	feature_enabled bool @[json: 'featureEnabled']
	// Active workspace messages returned by the backend.
	messages []WorkspaceMessage
}

// STUB: app-server-protocol/src/protocol/v2/account.rs API message declaration;
// retain camelCase wire names and nullable Unix-second timestamps.
pub struct WorkspaceMessage {
pub:
	message_id   string               @[json: 'messageId']
	message_type WorkspaceMessageType @[json: 'messageType']
	message_body string               @[json: 'messageBody']
	// Unix timestamp (in seconds) when the message was created.
	created_at ?i64 @[json: 'createdAt'; json_null]
	// Unix timestamp (in seconds) when the message was archived.
	archived_at ?i64 @[json: 'archivedAt'; json_null]
}

// STUB: app-server-protocol/src/protocol/v2/account.rs snake_case wire enum.
// Rust serde(other) decodes unrecognized names as Unknown; that deserializer
// remains the protocol owner's responsibility. These Copy-equivalent variants
// preserve the typed API rather than representing the message type as a string.
pub enum WorkspaceMessageType {
	headline
	announcement
	unknown
}
