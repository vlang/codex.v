module codex_plugin

// STUB: codex_plugin::PluginCapabilitySummary from plugin/src/lib.rs.
pub struct PluginCapabilitySummary {
pub:
	config_name       string
	display_name      string
	plugin_namespace  ?string
	description       ?string
	has_skills        bool
	mcp_server_names  []string
	app_connector_ids []string
}
