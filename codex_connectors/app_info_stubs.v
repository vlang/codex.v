module codex_connectors

// STUB: AppBranding fields from connectors/src/app_info.rs.
// Branding supplied by the connector directory for an app.
pub struct AppBranding {
pub:
	category            ?string @[json_null]
	developer           ?string @[json_null]
	website             ?string @[json_null]
	privacy_policy      ?string @[json: 'privacyPolicy'; json_null]
	terms_of_service    ?string @[json: 'termsOfService'; json_null]
	is_discoverable_app bool    @[json: 'isDiscoverableApp']
}

// STUB: AppReview fields from connectors/src/app_info.rs.
// Review state supplied by the connector directory for an app.
pub struct AppReview {
pub:
	status string
}

// STUB: AppScreenshot fields from connectors/src/app_info.rs.
// Screenshot metadata supplied by the connector directory for an app.
// Serde's alternate input aliases file_id/user_prompt await the connector module translation.
pub struct AppScreenshot {
pub:
	url         ?string @[json_null]
	file_id     ?string @[json: 'fileId'; json_null]
	user_prompt string  @[json: 'userPrompt']
}

// STUB: AppMetadata fields from connectors/src/app_info.rs.
// Extended metadata supplied by the connector directory for an app.
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
