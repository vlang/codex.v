// Client-owned preferences and persistence paths, independent of active server settings.
//
// The resolved core config is a temporary input at local load/reload boundaries. Server thread
// responses must never refresh these values; live preference changes belong here. The remaining
// Config-based lifecycle adapters also use this conversion until their interfaces are migrated.
module local_settings

import codex_core
import codex_core.config as core_config
import codex_config.types
import codex_utils_absolute_path

pub struct LocalSettings {
pub mut:
	tui              types.Tui
	history          types.History
	notices          types.Notice
	codex_home       codex_utils_absolute_path.AbsolutePathBuf
	user_config_path codex_utils_absolute_path.AbsolutePathBuf
}

pub fn LocalSettings.from(config &codex_core.Config) LocalSettings {
	// The existing Config dependency stores its validated AbsolutePathBuf as a string.
	// Restore the typed owned path at the source's explicit clone boundary.
	home := codex_utils_absolute_path.AbsolutePathBuf{ path: config.codex_home.clone() }
	config_file := 'config.toml'
	user_config_path := if selected := config.permission_config_layer_stack.get_user_config_file() {
		selected.value.clone()
	} else {
		home.join(&config_file)
	}
	return LocalSettings{
		tui:              types.Tui{
			notification_settings:           config.tui_notifications.clone()
			animations:                      config.animations
			whimsy:                          config.tui_whimsy
			show_tooltips:                   config.show_tooltips
			auto_recap:                      config.tui_auto_recap
			disable_paste_burst:             config.disable_paste_burst
			vim_mode_default:                config.tui_vim_mode_default
			question_esc_back:               config.tui_question_esc_back
			raw_output_mode:                 config.tui_raw_output_mode
			alternate_screen:                config.tui_alternate_screen
			status_line:                     if value := config.tui_status_line {
				value.clone()
			} else {
				none
			}
			status_line_use_colors:          config.tui_status_line_use_colors
			terminal_title:                  if value := config.tui_terminal_title {
				value.clone()
			} else {
				none
			}
			theme:                           if value := config.tui_theme {
				value.clone()
			} else {
				none
			}
			pet:                             if value := config.tui_pet {
				value.clone()
			} else {
				none
			}
			pet_anchor:                      config.tui_pet_anchor
			session_picker_view:             config.tui_session_picker_view
			resume_cwd:                      config.tui_resume_cwd
			keymap:                          config.tui_keymap.clone()
			model_availability_nux:          config.model_availability_nux.clone()
			terminal_resize_reflow_max_rows: match config.terminal_resize_reflow.max_rows.kind {
				.auto { none }
				.disabled { usize(0) }
				.limit { config.terminal_resize_reflow.max_rows.limit }
			}
		}
		history:          config.history.clone()
		notices:          config.notices.clone()
		codex_home:       home
		user_config_path: user_config_path
	}
}

pub fn (local &LocalSettings) terminal_resize_reflow() core_config.TerminalResizeReflowConfig {
	return core_config.TerminalResizeReflowConfig{
		max_rows: if rows := local.tui.terminal_resize_reflow_max_rows {
			if rows == 0 {
				core_config.TerminalResizeReflowMaxRows{ kind: .disabled }
			} else {
				core_config.TerminalResizeReflowMaxRows{ kind: .limit, limit: rows }
			}
		} else {
			core_config.TerminalResizeReflowMaxRows{ kind: .auto }
		}
	}
}

// Rust derives Clone; V explicitly clones each owned preference and persistence path.
pub fn (local &LocalSettings) clone() LocalSettings {
	return LocalSettings{ tui: local.tui.clone(), history: local.history.clone(), notices: local.notices.clone(), codex_home: local.codex_home.clone(), user_config_path: local.user_config_path.clone() }
}
