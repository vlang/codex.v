module models

import codex_protocol.permissions

// STUB: Canonical active permission-profile metadata.
pub struct ActivePermissionProfile {
pub:
	id      string
	extends ?string
}

// STUB: Agent message input content; encrypted_content is used for encrypted variants.
pub struct AgentMessageInputContent {
pub:
	kind              string
	text              string
	encrypted_content string
}

// STUB: Base instruction payload.
pub struct BaseInstructions {
pub:
	text string
}

// STUB: Responses API content item.
pub struct ContentItem {
pub:
	kind string
	text string
}

// STUB: Image detail preference.
pub enum ImageDetail {
	auto
	low
	high
	original
}

// STUB: Internal metadata passed through agent chat messages.
pub struct InternalChatMessageMetadataPassthrough {
pub:
	turn_id string
}

// STUB: Message phase on the Responses API.
pub enum MessagePhase {
	analysis
	commentary
	final
}

// STUB: Canonical permission profile.
pub struct PermissionProfile {
pub:
	enforcement SandboxEnforcement
	file_system permissions.FileSystemSandboxPolicy
	network     permissions.NetworkSandboxPolicy
}

// STUB: Model input item.
pub struct ResponseInputItem {
pub:
	kind    string
	role    string
	content []ContentItem
	phase   ?MessagePhase
}

// STUB: Stored response item.
pub struct ResponseItem {
pub:
	kind                                       string
	id                                         ?string
	author                                     string
	recipient                                  string
	content                                    []AgentMessageInputContent
	internal_chat_message_metadata_passthrough ?InternalChatMessageMetadataPassthrough
}

// STUB: Sandbox enforcement projection.
pub enum SandboxEnforcement {
	none
	legacy
	external
}

// STUB: Web-search action payload.
pub struct WebSearchAction {
pub:
	kind string
}

// STUB: Metadata initialization belongs to models.rs.
pub fn set_turn_id_if_missing(metadata ?InternalChatMessageMetadataPassthrough, turn_id &string) InternalChatMessageMetadataPassthrough {
	if existing := metadata {
		if existing.turn_id.len > 0 {
			return existing
		}
	}
	return InternalChatMessageMetadataPassthrough{ turn_id: *turn_id }
}

// STUB: Legacy sandbox conversion belongs to models.rs.
pub fn sandbox_enforcement_from_legacy(kind string) SandboxEnforcement {
	return if kind == 'external_sandbox' { .external } else { .legacy }
}

// STUB: Permission-profile construction belongs to models.rs.
pub fn permission_profile_from_runtime_permissions(enforcement SandboxEnforcement, file_system permissions.FileSystemSandboxPolicy, network permissions.NetworkSandboxPolicy) PermissionProfile {
	return PermissionProfile{ enforcement: enforcement, file_system: file_system, network: network }
}
