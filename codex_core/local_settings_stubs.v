module codex_core

import os
import toml
import codex_config
import codex_config.types
import codex_core.config as core_config
import codex_utils_absolute_path
import std_io

// STUB: ConfigBuilder::loader_overrides's owned source-shaped loader customization.
pub fn (builder ConfigBuilder) loader_overrides(overrides codex_config.LoaderOverrides) ConfigBuilder {
	return ConfigBuilder{ home: builder.home, cwd: builder.cwd, permission_overrides: builder.permission_overrides, loader_overrides_value: overrides }
}

// STUB: ConfigBuilder local disk-loading boundary for local_settings/config_update
// fixtures. Their fields and typed project trust tables are validated here;
// unsupported disk sections/keys fail. Managed requirements, project-layer
// selection and cloud loading await the real config loader.
fn apply_local_settings_builder_config(mut config Config, overrides &codex_config.LoaderOverrides) ! {
	if overrides.ignore_user_config {
		return
	}
	selected := if path := overrides.user_config_path {
		path.clone()
	} else {
		home := codex_utils_absolute_path.AbsolutePathBuf{ path: config.codex_home.clone() }
		child := 'config.toml'
		home.join(&child)
	}
	// A missing user file still has a selected writable destination in the real loader.
	text := if os.exists(selected.path.clone()) {
		os.read_file(selected.path.clone())!
	} else {
		''.clone()
	}
	doc := toml.parse_text(text)!
	for section, value in doc.to_any().as_map() {
		if section == 'projects' {
			validate_config_update_projects(value) or {
				return std_io.Error.new(.invalid_data, err.msg())
			}
			continue
		}
		if section !in ['tui', 'history', 'notice'] {
			return error('untranslated local config section: ${section}')
		}
		if value !is map[string]toml.Any {
			return error('local config section must be a table: ${section}')
		}
	}
	tui := local_settings_table(doc.value('tui'))!
	for key, value in tui {
		match key {
			'animations', 'whimsy', 'show_tooltips', 'auto_recap', 'vim_mode_default',
			'disable_paste_burst' {
				if value !is bool {
					return error('tui.${key} must be a boolean')
				}
				match key {
					'animations' { config.animations = value }
					'whimsy' { config.tui_whimsy = value }
					'show_tooltips' { config.show_tooltips = value }
					'auto_recap' { config.tui_auto_recap = value }
					'vim_mode_default' { config.tui_vim_mode_default = value }
					'disable_paste_burst' { config.disable_paste_burst = value }
					else {}
				}
			}
			'terminal_resize_reflow_max_rows' {
				if value !is i64 {
					return error('tui.terminal_resize_reflow_max_rows must be a nonnegative integer')
				}
				if value < 0 {
					return error('tui.terminal_resize_reflow_max_rows must be nonnegative')
				}
				config.terminal_resize_reflow = core_config.TerminalResizeReflowConfig{
					max_rows: if value == 0 {
						core_config.TerminalResizeReflowMaxRows{ kind: .disabled }
					} else {
						core_config.TerminalResizeReflowMaxRows{ kind: .limit, limit: usize(value) }
					}
				}
			}
			'session_picker_view' {
				if value !is string {
					return error('tui.session_picker_view must be a string')
				}
				config.tui_session_picker_view = match value {
					'dense' { types.SessionPickerViewMode.dense }
					'comfortable' { types.SessionPickerViewMode.comfortable }
					else { return error('invalid session picker view: ${value}') }
				}
			}
			'theme' {
				if value !is string {
					return error('tui.theme must be a string')
				}
				config.tui_theme = value.clone()
			}
			else { return error('untranslated local TUI config key: ${key}') }
		}
	}
	for key, value in local_settings_table(doc.value('history'))! {
		match key {
			'persistence' {
				if value !is string {
					return error('history.persistence must be a string')
				}
				config.history.persistence = match value {
					'none' { types.HistoryPersistence.none_ }
					'save-all' { types.HistoryPersistence.save_all }
					else { return error('invalid history persistence: ${value}') }
				}
			}
			'max_bytes' {
				if value !is i64 {
					return error('history.max_bytes must be a nonnegative integer')
				}
				if value < 0 {
					return error('history.max_bytes must be nonnegative')
				}
				config.history.max_bytes = usize(value)
			}
			else { return error('untranslated local history key: ${key}') }
		}
	}
	for key, value in local_settings_table(doc.value('notice'))! {
		if key != 'fast_default_opt_out' {
			return error('untranslated local notice key: ${key}')
		}
		if value !is bool {
			return error('notice.fast_default_opt_out must be a boolean')
		}
		config.notices.fast_default_opt_out = value
	}
	config.permission_config_layer_stack = codex_config.ConfigLayerStack{ layers: [codex_config.ConfigLayerEntry{ name: .user, user_file: selected, config: doc.to_any().as_map() }] }
}

// STUB: absent optional TOML tables deserialize to source defaults, rather than
// V's Any.as_map() conversion of Null into a table containing the synthetic key "0".
fn local_settings_table(value toml.Any) !map[string]toml.Any {
	return match value {
		map[string]toml.Any { value }
		toml.Null { map[string]toml.Any{} }
		else { return error('local config section must be a table') }
	}
}
