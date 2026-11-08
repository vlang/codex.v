module codex_app_server_protocol

import codex_protocol
import codex_protocol.config_types

// STUB: app-server-protocol/src/protocol/v2/collaboration_mode.rs list params.
pub struct CollaborationModeListParams {}

// STUB: CollaborationModeListParams' derived Default operation.
pub fn CollaborationModeListParams.default() CollaborationModeListParams {
	return CollaborationModeListParams{}
}

// STUB: app-server-protocol/src/protocol/v2/collaboration_mode.rs metadata.
// The wire field reasoning_effort retains its explicit snake_case name. Its
// three states use the existing core wrapper for Rust Option<Option<ReasoningEffort>>.
pub struct CollaborationModeMask {
pub:
	name             string
	mode             ?config_types.ModeKind
	model            ?string
	reasoning_effort codex_protocol.OptionalReasoningEffort
}

// STUB: the wire metadata's derived Clone operation at fixture response ownership boundaries.
pub fn (mask &CollaborationModeMask) clone() CollaborationModeMask {
	model := if value := mask.model { ?string(value.clone()) } else { ?string(none) }
	return CollaborationModeMask{
		name:             mask.name.clone()
		mode:             mask.mode
		model:            model
		reasoning_effort: mask.reasoning_effort
	}
}

// STUB: app-server-protocol/src/protocol/v2/collaboration_mode.rs list response.
pub struct CollaborationModeListResponse {
pub:
	data []CollaborationModeMask
}

// STUB: protocol/common.rs::ClientRequest::CollaborationModeList payload.
pub struct ClientRequestCollaborationModeList {
pub:
	request_id RequestId
	params     CollaborationModeListParams
}
