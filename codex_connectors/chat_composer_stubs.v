module codex_connectors

// STUB: codex_connectors::AppInfo from connectors/src/app_info.rs.
pub struct AppInfo {
pub:
	id                   string
	name                 string
	description          ?string            @[json_null]
	logo_url             ?string            @[json: 'logoUrl'; json_null]
	logo_url_dark        ?string            @[json: 'logoUrlDark'; json_null]
	icon_assets          ?map[string]string @[json: 'iconAssets'; json_null]
	icon_dark_assets     ?map[string]string @[json: 'iconDarkAssets'; json_null]
	distribution_channel ?string            @[json: 'distributionChannel'; json_null]
	branding             ?AppBranding       @[json_null]
	app_metadata         ?AppMetadata       @[json: 'appMetadata'; json_null]
	labels               ?map[string]string @[json_null]
	install_url          ?string            @[json: 'installUrl'; json_null]
	is_accessible        bool               @[json: 'isAccessible']
	is_enabled           bool = true        @[json: 'isEnabled']
	plugin_display_names []string           @[json: 'pluginDisplayNames']
}
