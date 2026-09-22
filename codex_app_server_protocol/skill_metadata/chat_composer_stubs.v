module skill_metadata

// STUB: codex_app_server_protocol::SkillInterface from protocol/v2/plugin.rs.
pub struct SkillInterface {
pub:
	display_name      ?string
	short_description ?string
}

// STUB: codex_app_server_protocol::SkillScope from protocol/v2/plugin.rs.
pub enum SkillScope {
	user
	repo
	system
	admin
}

// STUB: codex_app_server_protocol::SkillToolDependency from protocol/v2/plugin.rs.
pub struct SkillToolDependency {
pub:
	type_name   string
	value       string
	description ?string
	transport   ?string
	command     ?string
	url         ?string
}

// STUB: codex_app_server_protocol::SkillDependencies from protocol/v2/plugin.rs.
pub struct SkillDependencies {
pub:
	tools []SkillToolDependency
}

// STUB: codex_app_server_protocol::SkillMetadata from protocol/v2/plugin.rs. This leaf module
// keeps consumers of the generated plugin schema independent from unrelated app-server payloads.
pub struct SkillMetadata {
pub:
	name              string
	description       string
	short_description ?string
	interface         ?SkillInterface
	dependencies      ?SkillDependencies
	path              string
	scope             SkillScope
	enabled           bool = true
	plugin_id         ?string
}
