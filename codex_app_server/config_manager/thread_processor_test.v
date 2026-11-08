module config_manager

import codex_app_server_protocol as api
import codex_core
import codex_features
import codex_config
import codex_protocol
import toml
import serde_json

fn fixture_owned_tier(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_service_tier_override_preserves_clears_or_sets_base_preference() {
	manager := ConfigManager{
		base_config: codex_core.Config{ service_tier: fixture_owned_tier('organization-tier') }
	}
	preserved := manager.load_with_overrides(?map[string]serde_json.Value(none), codex_core.ConfigOverrides{}) or { panic(err) }
	cleared := manager.load_with_overrides(?map[string]serde_json.Value(none), codex_core.ConfigOverrides{
		service_tier: api.ClearableString{ has_value: true, clear: true }
	}) or { panic(err) }
	replaced := manager.load_with_overrides(?map[string]serde_json.Value(none), codex_core.ConfigOverrides{
		service_tier: api.ClearableString{ has_value: true, value: fixture_owned_tier('flex') }
	}) or { panic(err) }
	assert preserved.service_tier == ?string('organization-tier')
	// ConfigBuilder maps an explicit clear to its standard-routing sentinel.
	assert cleared.service_tier == ?string('default')
	assert replaced.service_tier == ?string('flex')
	assert manager.base_config.service_tier == ?string('organization-tier')
}

fn test_service_tier_reload_normalizes_fast_alias_and_applies_feature_gate() {
	for fast_mode in [false, true] {
		manager := ConfigManager{
			base_config: codex_core.Config{
				service_tier: fixture_owned_tier('fast')
				features:     codex_features.Features{
					enabled_features: if fast_mode {
						[.fast_mode]
					} else {
						[]codex_features.Feature{}
					}
				}
			}
		}
		expected_fast := if fast_mode { ?string('priority') } else { ?string(none) }
		inherited := manager.load_with_overrides(?map[string]serde_json.Value(none), codex_core.ConfigOverrides{}) or { panic(err) }
		assert inherited.service_tier == expected_fast
		for request in ['fast', 'priority', 'flex', 'default', '', ' priority '] {
			loaded := manager.load_with_overrides(?map[string]serde_json.Value(none), codex_core.ConfigOverrides{
				service_tier: api.ClearableString{ has_value: true, value: fixture_owned_tier(request.clone()) }
			}) or { panic(err) }
			expected := if request in ['fast', 'priority'] {
				expected_fast
			} else {
				?string(request)
			}
			assert loaded.service_tier == expected
		}
		assert manager.base_config.service_tier == ?string('fast')
	}
}

fn test_service_tier_reloads_return_independent_owned_values() {
	manager := ConfigManager{
		base_config: codex_core.Config{ service_tier: fixture_owned_tier('flex') }
	}
	mut first := manager.load_with_overrides(?map[string]serde_json.Value(none), codex_core.ConfigOverrides{}) or { panic(err) }
	mut second := manager.load_with_overrides(?map[string]serde_json.Value(none), codex_core.ConfigOverrides{}) or { panic(err) }
	first.service_tier = fixture_owned_tier('default')
	second.service_tier = none
	assert manager.base_config.service_tier == ?string('flex')
	assert first.service_tier == ?string('default')
	assert second.service_tier == none
}

fn test_permission_and_model_settings_survive_repeated_reload_and_cwd_retarget() {
	manager := ConfigManager{
		base_config: codex_core.Config{
			model:                         fixture_owned_tier('managed-model')
			model_reasoning_effort:        .high
			cwd:                           fixture_owned_tier('/original')
			permissions:                   codex_core.ConfigPermissions{
				active_profile: codex_protocol.ActivePermissionProfile{
					id:      fixture_owned_tier('session-only')
					extends: fixture_owned_tier(':workspace')
				}
			}
			custom_permission_profiles:    [codex_core.PermissionProfileCatalogEntry{
				id:          fixture_owned_tier('session-only')
				description: fixture_owned_tier('Permissions selected for this invocation')
				allowed:     true
			}]
			permission_config_layer_stack: codex_config.ConfigLayerStack{
				layers: [codex_config.ConfigLayerEntry{
					name:   .session_flags
					config: {
						'permissions': toml.Any({
							'session-only': toml.Any({
								'extends': toml.Any(fixture_owned_tier(':workspace'))
							})
						})
					}
				}]
			}
		}
	}
	first := manager.load_with_overrides(?map[string]serde_json.Value(none), codex_core.ConfigOverrides{}) or { panic(err) }
	second := manager.load_for_cwd(?map[string]serde_json.Value(none), codex_core.ConfigOverrides{}, fixture_owned_tier('/retargeted')) or { panic(err) }
	assert first.model == manager.base_config.model
	assert second.model == manager.base_config.model
	assert first.model_reasoning_effort == ?codex_protocol.ReasoningEffortConfig(.high)
	assert second.model_reasoning_effort == first.model_reasoning_effort
	assert first.custom_permission_profiles == manager.base_config.custom_permission_profiles
	assert second.custom_permission_profiles == first.custom_permission_profiles
	assert first.permissions.active_profile == manager.base_config.permissions.active_profile
	assert second.permissions.active_profile == first.permissions.active_profile
	assert first.permission_config_layer_stack.layers[0].name == .session_flags
	assert second.permission_config_layer_stack.layers[0].config == first.permission_config_layer_stack.layers[0].config
	assert second.cwd == '/retargeted'
	assert manager.base_config.cwd == '/original'
	assert manager.base_config.model or { panic('model was moved') } == 'managed-model'
	assert manager.base_config.custom_permission_profiles[0].description or { panic('description was moved') } == 'Permissions selected for this invocation'
	explicit := manager.load_with_overrides(?map[string]serde_json.Value(none), codex_core.ConfigOverrides{
		model: fixture_owned_tier('launch-model')
	}) or { panic(err) }
	assert explicit.model == ?string('launch-model')
	assert manager.base_config.model == ?string('managed-model')
}
