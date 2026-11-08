module codex_app_server_protocol

import codex_protocol.openai_models

// STUB: app-server-protocol/src/protocol/v2/config.rs::NewThreadModelDefaults.
// Keep the managed defaults typed and retain their camelCase wire field names.
pub struct NewThreadModelDefaults {
pub:
	model                  ?string                        @[json_null]
	model_reasoning_effort ?openai_models.ReasoningEffort @[json: 'modelReasoningEffort'; json_null]
	service_tier           ?string                        @[json: 'serviceTier'; json_null]
}
