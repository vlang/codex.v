module metadata

import codex_connectors

// STUB: codex_connectors::metadata::connector_display_label returns the connector's user-facing
// name.
pub fn connector_display_label(connector &codex_connectors.AppInfo) string {
	return connector.name.clone()
}

// STUB: codex_connectors::metadata::connector_mention_slug derives the stable mention spelling.
pub fn connector_mention_slug(connector &codex_connectors.AppInfo) string {
	display_name := connector_display_label(connector)
	mut normalized := ''
	for character in display_name.runes() {
		if character >= `A` && character <= `Z` {
			normalized += (character + 32).str()
		} else if (character >= `a` && character <= `z`) || (character >= `0` && character <= `9`) {
			normalized += character.str()
		} else {
			normalized += '-'
		}
	}
	normalized = normalized.trim('-')
	return if normalized.len == 0 { 'app' } else { normalized }
}
