module codex_core

import codex_config
import codex_protocol
import toml

// STUB: ConfigBuilder::cli_overrides's owned Rust (String, TomlValue) tuple.
pub struct PermissionCliOverride {
pub:
	key   string
	value toml.Any
}

// STUB: preserve typed TOML CLI overrides across the owned builder chain.
pub fn (builder ConfigBuilder) cli_overrides(overrides []PermissionCliOverride) ConfigBuilder {
	return ConfigBuilder{ home: builder.home, cwd: builder.cwd, permission_overrides: overrides, loader_overrides_value: builder.loader_overrides_value }
}

// STUB: smallest config-loader boundary for source session-only profile tests.
// Full arbitrary profile compilation, managed validation and layer merging are
// untranslated. Unsupported CLI keys fail instead of pretending to load them.
fn apply_permission_builder_overrides(mut config Config, overrides []PermissionCliOverride) ! {
	if overrides.len == 0 {
		return
	}
	mut permission_tables := map[string]toml.Any{}
	mut profiles := []PermissionProfileCatalogEntry{}
	mut active := ?string(none)
	for entry in overrides {
		if entry.key == 'tui.disable_paste_burst' {
			if entry.value !is bool {
				return error('tui.disable_paste_burst must be a boolean')
			}
			config.disable_paste_burst = entry.value
		} else if entry.key == 'default_permissions' {
			if entry.value !is string {
				return error('default_permissions must be a string')
			}
			active = entry.value.clone()
		} else if entry.key.starts_with('permissions.') && entry.key.ends_with('.extends') {
			if entry.value !is string {
				return error('profile extends must be a string')
			}
			id := entry.key['permissions.'.len..entry.key.len - '.extends'.len].clone()
			permission_tables[id.clone()] = toml.Any({
				'extends': toml.Any(entry.value.clone())
			})
			profiles << PermissionProfileCatalogEntry{ id: id, allowed: true }
		} else {
			return error('untranslated CLI config override: ${entry.key}')
		}
	}
	mut table := map[string]toml.Any{}
	if permission_tables.len > 0 {
		table['permissions'] = toml.Any(permission_tables)
	}
	if selected := active {
		table['default_permissions'] = toml.Any(selected.clone())
		config.permissions = ConfigPermissions{ effective_profile: clone_permission_profile(&config.permissions.effective_profile), windows_sandbox_level: config.permissions.windows_sandbox_level, active_profile: codex_protocol.ActivePermissionProfile{ id: selected } }
	}
	config.custom_permission_profiles = profiles
	mut layers := config.permission_config_layer_stack.layers.clone()
	layers << codex_config.ConfigLayerEntry{ name: .session_flags, config: table }
	config.permission_config_layer_stack = codex_config.ConfigLayerStack{ layers: layers }
}
