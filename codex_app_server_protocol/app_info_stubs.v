module codex_app_server_protocol

// STUB: AppBranding fields from app-server-protocol/src/protocol/v2/apps.rs.
// EXPERIMENTAL - app metadata returned by app-list APIs.
pub struct AppBranding {
pub:
	category            ?string @[json_null]
	developer           ?string @[json_null]
	website             ?string @[json_null]
	privacy_policy      ?string @[json: 'privacyPolicy'; json_null]
	terms_of_service    ?string @[json: 'termsOfService'; json_null]
	is_discoverable_app bool    @[json: 'isDiscoverableApp']
}

// STUB: AppReview fields from app-server-protocol/src/protocol/v2/apps.rs.
pub struct AppReview {
pub:
	status string
}

// STUB: AppScreenshot fields from app-server-protocol/src/protocol/v2/apps.rs.
// Serde's alternate input aliases file_id/user_prompt await the protocol module translation.
pub struct AppScreenshot {
pub:
	url         ?string @[json_null]
	file_id     ?string @[json: 'fileId'; json_null]
	user_prompt string  @[json: 'userPrompt']
}

// STUB: AppMetadata fields from app-server-protocol/src/protocol/v2/apps.rs.
pub struct AppMetadata {
pub:
	review                         ?AppReview       @[json_null]
	categories                     ?[]string        @[json_null]
	sub_categories                 ?[]string        @[json: 'subCategories'; json_null]
	seo_description                ?string          @[json: 'seoDescription'; json_null]
	screenshots                    ?[]AppScreenshot @[json_null]
	developer                      ?string          @[json_null]
	version                        ?string          @[json_null]
	version_id                     ?string          @[json: 'versionId'; json_null]
	version_notes                  ?string          @[json: 'versionNotes'; json_null]
	first_party_requires_install   ?bool            @[json: 'firstPartyRequiresInstall'; json_null]
	show_in_composer_when_unlinked ?bool            @[json: 'showInComposerWhenUnlinked'; json_null]
}

// STUB: AppInfo fields/defaults from app-server-protocol/src/protocol/v2/apps.rs.
// EXPERIMENTAL - app metadata returned by app-list APIs.
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
	// Whether this app is enabled in config.toml.
	// Example:
	// ```toml
	// [apps.bad_app]
	// enabled = false
	// ```
	is_enabled           bool = true @[json: 'isEnabled']
	plugin_display_names []string    @[json: 'pluginDisplayNames']
}
