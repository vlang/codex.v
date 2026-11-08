module app_info

import codex_app_server_protocol as api
import codex_connectors

// Converts the app-server wire type owned by `codex-app-server-protocol` into connector-domain
// app metadata owned by `codex-connectors`.
//
// The types stay separate so app-server protocol ownership does not leak into the connector
// domain crate. Because this crate owns neither type, Rust's orphan rules require an explicit
// conversion function instead of a `From` implementation.
pub fn app_info_from_api(app api.AppInfo) codex_connectors.AppInfo {
	return codex_connectors.AppInfo{
		id:                   app.id
		name:                 app.name
		description:          app.description
		logo_url:             app.logo_url
		logo_url_dark:        app.logo_url_dark
		icon_assets:          app.icon_assets
		icon_dark_assets:     app.icon_dark_assets
		distribution_channel: app.distribution_channel
		branding:             if branding := app.branding {
			app_branding_from_api(branding)
		} else {
			none
		}
		app_metadata:         if metadata := app.app_metadata {
			app_metadata_from_api(metadata)
		} else {
			none
		}
		labels:               app.labels
		install_url:          app.install_url
		is_accessible:        app.is_accessible
		is_enabled:           app.is_enabled
		plugin_display_names: app.plugin_display_names
	}
}

fn app_branding_from_api(branding api.AppBranding) codex_connectors.AppBranding {
	return codex_connectors.AppBranding{
		category:            branding.category
		developer:           branding.developer
		website:             branding.website
		privacy_policy:      branding.privacy_policy
		terms_of_service:    branding.terms_of_service
		is_discoverable_app: branding.is_discoverable_app
	}
}

fn app_review_from_api(review api.AppReview) codex_connectors.AppReview {
	return codex_connectors.AppReview{
		status: review.status
	}
}

fn app_screenshot_from_api(screenshot api.AppScreenshot) codex_connectors.AppScreenshot {
	return codex_connectors.AppScreenshot{
		url:         screenshot.url
		file_id:     screenshot.file_id
		user_prompt: screenshot.user_prompt
	}
}

fn app_metadata_from_api(metadata api.AppMetadata) codex_connectors.AppMetadata {
	return codex_connectors.AppMetadata{
		review:                         if review := metadata.review {
			app_review_from_api(review)
		} else {
			none
		}
		categories:                     metadata.categories
		sub_categories:                 metadata.sub_categories
		seo_description:                metadata.seo_description
		screenshots:                    if screenshots := metadata.screenshots {
			mut converted := []codex_connectors.AppScreenshot{cap: screenshots.len}
			for screenshot in screenshots {
				converted << app_screenshot_from_api(screenshot)
			}
			converted
		} else {
			none
		}
		developer:                      metadata.developer
		version:                        metadata.version
		version_id:                     metadata.version_id
		version_notes:                  metadata.version_notes
		first_party_requires_install:   metadata.first_party_requires_install
		show_in_composer_when_unlinked: metadata.show_in_composer_when_unlinked
	}
}
