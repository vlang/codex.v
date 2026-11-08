module codex_config

import toml
import codex_utils_absolute_path

// STUB: config/src/config_layer_source.rs::ConfigLayerSource variant identities.
// Discovery observes only provenance; unobserved source payloads await that owner.
pub enum ConfigLayerSource {
	packaged_defaults
	mdm
	system
	enterprise_managed
	user
	project
	session_flags
	legacy_managed_config_toml_from_file
	legacy_managed_config_toml_from_mdm
}

// STUB: config/src/state.rs::ConfigLayerEntry's observed provenance, TOML table,
// and disabled state; loader/version/raw-TOML metadata are untranslated.
pub struct ConfigLayerEntry {
pub:
	name ConfigLayerSource
	// STUB: User { file, .. } payload observed by LocalSettings.
	user_file       codex_utils_absolute_path.AbsolutePathBuf
	config          map[string]toml.Any
	disabled_reason ?string
}

// STUB: typed permission-layer companion to the pre-existing []string config
// stack stub. It preserves real layer APIs while other callers await migration.
pub struct ConfigLayerStack {
pub:
	layers []ConfigLayerEntry
}

// STUB: Returns enabled config layers from lowest precedence to highest.
// Requirement sources are tracked separately and are not included here.
pub fn (stack &ConfigLayerStack) layers_low_to_high() []&ConfigLayerEntry {
	mut layers := []&ConfigLayerEntry{}
	for index in 0 .. stack.layers.len {
		if stack.layers[index].disabled_reason == none {
			layers << &stack.layers[index]
		}
	}
	return layers
}

// STUB: deep Clone at Config's existing owned reload boundary.
pub fn (stack &ConfigLayerStack) clone() ConfigLayerStack {
	mut layers := []ConfigLayerEntry{cap: stack.layers.len}
	for index in 0 .. stack.layers.len {
		layer := &stack.layers[index]
		mut config := map[string]toml.Any{}
		for key, value in layer.config {
			config[key.clone()] = clone_permission_toml(&value)
		}
		layers << ConfigLayerEntry{
			name:            layer.name
			user_file:       layer.user_file.clone()
			config:          config
			disabled_reason: if reason := layer.disabled_reason {
				reason.clone()
			} else {
				none
			}
		}
	}
	return ConfigLayerStack{ layers: layers }
}

// STUB: recursive TOML Clone used by the source configuration clone boundary.
fn clone_permission_toml(value &toml.Any) toml.Any {
	match value {
		string { return toml.Any(value.clone()) }
		[]toml.Any {
			mut values := []toml.Any{cap: value.len}
			for index in 0 .. value.len {
				values << clone_permission_toml(&value[index])
			}
			return toml.Any(values)
		}
		map[string]toml.Any {
			mut values := map[string]toml.Any{}
			for key, item in value {
				values[key.clone()] = clone_permission_toml(&item)
			}
			return toml.Any(values)
		}
		else { return *value }
	}
}
