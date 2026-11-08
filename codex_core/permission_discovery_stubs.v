module codex_core

import codex_protocol

// STUB: core/config.rs::Config's derived Clone. Keep all observed fields at the
// canonical clone boundary so request processors cannot drop newly ported state.
pub fn (config &Config) clone() Config {
	return clone_core_config(config)
}

// STUB: core/src/config/permission_profile_catalog.rs::PermissionProfileCatalogEntry.
pub struct PermissionProfileCatalogEntry {
pub:
	id          string
	description ?string
	allowed     bool
}

// STUB: preserve profile ownership at Config's existing Clone boundary.
pub fn clone_custom_permission_profiles(profiles &[]PermissionProfileCatalogEntry) []PermissionProfileCatalogEntry {
	mut result := []PermissionProfileCatalogEntry{cap: profiles.len}
	for index in 0 .. profiles.len {
		profile := unsafe { &profiles[index] }
		result << PermissionProfileCatalogEntry{
			id:          profile.id.clone()
			description: if text := profile.description {
				text.clone()
			} else {
				none
			}
			allowed:     profile.allowed
		}
	}
	return result
}

// STUB: ConfigPermissions::active_permission_profile returns owned metadata,
// matching resolved_permission_profile.rs's cloned source value.
pub fn (permissions &ConfigPermissions) active_permission_profile() ?codex_protocol.ActivePermissionProfile {
	if profile := permissions.active_profile {
		return codex_protocol.ActivePermissionProfile{
			id:      profile.id.clone()
			extends: if parent := profile.extends {
				parent.clone()
			} else {
				none
			}
		}
	}
	return none
}
