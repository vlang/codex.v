module codex_connectors

// STUB: codex_connectors::AppInfo from connectors/src/app_info.rs.
pub struct AppInfo {
pub:
	id                   string
	name                 string
	description          ?string
	is_accessible        bool
	is_enabled           bool
	plugin_display_names []string
}
