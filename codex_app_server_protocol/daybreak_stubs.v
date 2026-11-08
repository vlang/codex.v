module codex_app_server_protocol

// STUB: protocol/common.rs::AuthMode, preserving every authentication variant.
pub enum AuthMode {
	api_key
	chatgpt
	chatgpt_auth_tokens
	headers
	agent_identity
	personal_access_token
	bedrock_api_key
	bedrock_access_keys
}

// STUB: protocol/v1.rs::GetAuthStatusParams uses camelCase JSON field names.
pub struct GetAuthStatusParams {
pub:
	include_token ?bool @[json: 'includeToken']
	refresh_token ?bool @[json: 'refreshToken']
}

// STUB: protocol/v1.rs::GetAuthStatusResponse preserves the optional token/mode.
pub struct GetAuthStatusResponse {
pub:
	auth_method          ?AuthMode @[json: 'authMethod']
	auth_token           ?string   @[json: 'authToken']
	requires_openai_auth ?bool     @[json: 'requiresOpenaiAuth']
}

// STUB: protocol/common.rs::ClientRequest::GetAuthStatus typed request payload.
pub struct ClientRequestGetAuthStatus {
pub:
	request_id RequestId
	params     GetAuthStatusParams
}
