module app_info

import codex_app_server_protocol as api
import codex_connectors

fn owned_app_text(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_owned_app_conversion_preserves_every_field_and_screenshot_order() {
	app := api.AppInfo{
		id:                   owned_app_text('app-id')
		name:                 owned_app_text('Application')
		description:          owned_app_text('Description')
		logo_url:             owned_app_text('light-logo')
		logo_url_dark:        owned_app_text('dark-logo')
		icon_assets:          {
			owned_app_text('light-svg'): owned_app_text('light-asset')
			owned_app_text('light-png'): owned_app_text('light-fallback')
		}
		icon_dark_assets:     {
			owned_app_text('dark-svg'): owned_app_text('dark-asset')
		}
		distribution_channel: owned_app_text('directory')
		branding:             api.AppBranding{
			category:            owned_app_text('Productivity')
			developer:           owned_app_text('Brand developer')
			website:             owned_app_text('Website')
			privacy_policy:      owned_app_text('Privacy policy')
			terms_of_service:    owned_app_text('Terms of service')
			is_discoverable_app: true
		}
		app_metadata:         api.AppMetadata{
			review:                         api.AppReview{ status: owned_app_text('approved') }
			categories:                     [owned_app_text('Primary'), owned_app_text('Secondary')]
			sub_categories:                 [owned_app_text('Subcategory')]
			seo_description:                owned_app_text('Search description')
			screenshots:                    [
				api.AppScreenshot{
					url:         owned_app_text('first-url')
					file_id:     owned_app_text('first-file')
					user_prompt: owned_app_text('First prompt')
				},
				api.AppScreenshot{
					file_id:     owned_app_text('second-file')
					user_prompt: owned_app_text('Second prompt')
				},
				api.AppScreenshot{
					url:         owned_app_text('third-url')
					user_prompt: owned_app_text('Third prompt')
				},
			]
			developer:                      owned_app_text('Metadata developer')
			version:                        owned_app_text('1.2.3')
			version_id:                     owned_app_text('version-id')
			version_notes:                  owned_app_text('Version notes')
			first_party_requires_install:   true
			show_in_composer_when_unlinked: false
		}
		labels:               {
			owned_app_text('label-key'): owned_app_text('label-value')
		}
		install_url:          owned_app_text('Install URL')
		is_accessible:        true
		is_enabled:           false
		plugin_display_names: [owned_app_text('First plugin'), owned_app_text('Second plugin')]
	}
	converted := app_info_from_api(app)
	assert converted == codex_connectors.AppInfo{
		id:                   owned_app_text('app-id')
		name:                 owned_app_text('Application')
		description:          owned_app_text('Description')
		logo_url:             owned_app_text('light-logo')
		logo_url_dark:        owned_app_text('dark-logo')
		icon_assets:          {
			owned_app_text('light-svg'): owned_app_text('light-asset')
			owned_app_text('light-png'): owned_app_text('light-fallback')
		}
		icon_dark_assets:     {
			owned_app_text('dark-svg'): owned_app_text('dark-asset')
		}
		distribution_channel: owned_app_text('directory')
		branding:             codex_connectors.AppBranding{
			category:            owned_app_text('Productivity')
			developer:           owned_app_text('Brand developer')
			website:             owned_app_text('Website')
			privacy_policy:      owned_app_text('Privacy policy')
			terms_of_service:    owned_app_text('Terms of service')
			is_discoverable_app: true
		}
		app_metadata:         codex_connectors.AppMetadata{
			review:                         codex_connectors.AppReview{ status: owned_app_text('approved') }
			categories:                     [owned_app_text('Primary'), owned_app_text('Secondary')]
			sub_categories:                 [owned_app_text('Subcategory')]
			seo_description:                owned_app_text('Search description')
			screenshots:                    [
				codex_connectors.AppScreenshot{
					url:         owned_app_text('first-url')
					file_id:     owned_app_text('first-file')
					user_prompt: owned_app_text('First prompt')
				},
				codex_connectors.AppScreenshot{
					file_id:     owned_app_text('second-file')
					user_prompt: owned_app_text('Second prompt')
				},
				codex_connectors.AppScreenshot{
					url:         owned_app_text('third-url')
					user_prompt: owned_app_text('Third prompt')
				},
			]
			developer:                      owned_app_text('Metadata developer')
			version:                        owned_app_text('1.2.3')
			version_id:                     owned_app_text('version-id')
			version_notes:                  owned_app_text('Version notes')
			first_party_requires_install:   true
			show_in_composer_when_unlinked: false
		}
		labels:               {
			owned_app_text('label-key'): owned_app_text('label-value')
		}
		install_url:          owned_app_text('Install URL')
		is_accessible:        true
		is_enabled:           false
		plugin_display_names: [owned_app_text('First plugin'), owned_app_text('Second plugin')]
	}
}

fn test_absent_app_options_remain_absent() {
	app := api.AppInfo{
		id:         owned_app_text('minimal')
		name:       owned_app_text('Minimal application')
		is_enabled: true
	}
	assert app_info_from_api(app) == codex_connectors.AppInfo{
		id:         owned_app_text('minimal')
		name:       owned_app_text('Minimal application')
		is_enabled: true
	}
}

fn test_present_empty_nested_metadata_stays_distinct_from_absence() {
	app := api.AppInfo{
		id:                   owned_app_text('empty')
		name:                 owned_app_text('Empty metadata')
		description:          owned_app_text('')
		logo_url:             owned_app_text('')
		logo_url_dark:        owned_app_text('')
		icon_assets:          map[string]string{}
		icon_dark_assets:     map[string]string{}
		distribution_channel: owned_app_text('')
		branding:             api.AppBranding{}
		app_metadata:         api.AppMetadata{
			review:                         api.AppReview{ status: owned_app_text('') }
			categories:                     []string{}
			sub_categories:                 []string{}
			seo_description:                owned_app_text('')
			screenshots:                    []api.AppScreenshot{}
			developer:                      owned_app_text('')
			version:                        owned_app_text('')
			version_id:                     owned_app_text('')
			version_notes:                  owned_app_text('')
			first_party_requires_install:   false
			show_in_composer_when_unlinked: true
		}
		labels:               map[string]string{}
		install_url:          owned_app_text('')
		is_accessible:        false
		is_enabled:           true
	}
	assert app_info_from_api(app) == codex_connectors.AppInfo{
		id:                   owned_app_text('empty')
		name:                 owned_app_text('Empty metadata')
		description:          owned_app_text('')
		logo_url:             owned_app_text('')
		logo_url_dark:        owned_app_text('')
		icon_assets:          map[string]string{}
		icon_dark_assets:     map[string]string{}
		distribution_channel: owned_app_text('')
		branding:             codex_connectors.AppBranding{}
		app_metadata:         codex_connectors.AppMetadata{
			review:                         codex_connectors.AppReview{ status: owned_app_text('') }
			categories:                     []string{}
			sub_categories:                 []string{}
			seo_description:                owned_app_text('')
			screenshots:                    []codex_connectors.AppScreenshot{}
			developer:                      owned_app_text('')
			version:                        owned_app_text('')
			version_id:                     owned_app_text('')
			version_notes:                  owned_app_text('')
			first_party_requires_install:   false
			show_in_composer_when_unlinked: true
		}
		labels:               map[string]string{}
		install_url:          owned_app_text('')
		is_accessible:        false
		is_enabled:           true
	}
}

fn test_present_parent_options_preserve_absent_children() {
	app := api.AppInfo{
		id:           owned_app_text('nested')
		name:         owned_app_text('Nested absence')
		branding:     api.AppBranding{
			developer: owned_app_text('Brand only')
		}
		app_metadata: api.AppMetadata{
			screenshots: [api.AppScreenshot{ user_prompt: owned_app_text('Prompt without image') }]
		}
		is_enabled:   false
	}
	assert app_info_from_api(app) == codex_connectors.AppInfo{
		id:           owned_app_text('nested')
		name:         owned_app_text('Nested absence')
		branding:     codex_connectors.AppBranding{
			developer: owned_app_text('Brand only')
		}
		app_metadata: codex_connectors.AppMetadata{
			screenshots: [codex_connectors.AppScreenshot{ user_prompt: owned_app_text('Prompt without image') }]
		}
		is_enabled:   false
	}
}
