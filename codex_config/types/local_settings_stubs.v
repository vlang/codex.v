module types

import codex_protocol.config_types
import toml

// STUB: config/src/types.rs::SessionPickerViewMode, with Dense as the resolved default.
pub enum SessionPickerViewMode {
	dense
	comfortable
}

// STUB: SessionPickerViewMode::as_str preserves kebab-case persistence names.
pub fn (mode SessionPickerViewMode) as_str() string {
	return match mode {
		.comfortable { 'comfortable' }
		.dense { 'dense' }
	}
}

// STUB: config/src/types.rs::ResumeCwdMode's Copy directory preference.
pub enum ResumeCwdMode {
	current
	session
}

// STUB: config/src/types.rs::HistoryPersistence, whose default saves all entries.
pub enum HistoryPersistence {
	save_all
	none_
}

// STUB: config/src/types.rs::History includes every observed persistence field.
pub struct History {
pub mut:
	persistence HistoryPersistence = .save_all
	max_bytes   ?usize
}

// STUB: History's derived Clone is allocation-free.
pub fn (history &History) clone() History {
	return *history
}

// STUB: discriminant for the payload-bearing Notifications persistence enum.
pub enum NotificationsKind {
	enabled
	custom
}

// STUB: config/src/types.rs::Notifications keeps Enabled(bool) and Custom(Vec<String>) typed.
pub struct Notifications {
pub mut:
	kind    NotificationsKind
	enabled bool = true
	custom  []string
}

// STUB: config/src/types.rs::NotificationCondition's default is Unfocused.
pub enum NotificationCondition {
	unfocused
	always
}

// STUB: config/src/types.rs::TuiPetAnchor's default is Composer.
pub enum TuiPetAnchor {
	composer
	screen_bottom
}

// STUB: config/src/types.rs::TuiNotificationSettings includes all flattened settings.
pub struct TuiNotificationSettings {
pub mut:
	notifications Notifications
	method        NotificationMethod
	condition     NotificationCondition
}

// STUB: TuiNotificationSettings's derived Clone owns independent notification event names.
pub fn (settings &TuiNotificationSettings) clone() TuiNotificationSettings {
	return TuiNotificationSettings{ notifications: Notifications{ kind: settings.notifications.kind, enabled: settings.notifications.enabled, custom: settings.notifications.custom.clone() }, method: settings.method, condition: settings.condition }
}

// STUB: config/src/types.rs::ModelAvailabilityNuxConfig's flattened model counts.
pub struct ModelAvailabilityNuxConfig {
pub mut:
	shown_count map[string]u32
}

// STUB: ModelAvailabilityNuxConfig's derived Clone preserves independent model-count storage.
pub fn (nux &ModelAvailabilityNuxConfig) clone() ModelAvailabilityNuxConfig {
	mut counts := map[string]u32{}
	for key, value in nux.shown_count {
		counts[key.clone()] = value
	}
	return ModelAvailabilityNuxConfig{ shown_count: counts }
}

// STUB: config/src/types.rs::Tui has all 21 preference fields observed by LocalSettings.
// Boolean defaults are serde's empty-TOML defaults rather than Rust's derived Tui::default().
pub struct Tui {
pub mut:
	notification_settings           TuiNotificationSettings
	animations                      bool = true
	whimsy                          bool = true
	show_tooltips                   bool = true
	auto_recap                      bool = true
	disable_paste_burst             ?bool
	vim_mode_default                bool
	question_esc_back               bool = true
	raw_output_mode                 bool
	alternate_screen                config_types.AltScreenMode
	status_line                     ?[]string
	status_line_use_colors          bool = true
	terminal_title                  ?[]string
	theme                           ?string
	pet                             ?string
	pet_anchor                      TuiPetAnchor
	session_picker_view             ?SessionPickerViewMode
	resume_cwd                      ?ResumeCwdMode
	keymap                          TuiKeymap
	model_availability_nux          ModelAvailabilityNuxConfig
	terminal_resize_reflow_max_rows ?usize
}

// STUB: Tui's derived Default differs from serde's empty-TOML boolean defaults.
// Rust's derive initializes every plain bool to false; decoded omitted fields use true below.
pub fn Tui.default() Tui {
	return Tui{ animations: false, whimsy: false, show_tooltips: false, auto_recap: false, question_esc_back: false, status_line_use_colors: false }
}

// STUB: config/src/types.rs::ExternalConfigMigrationPrompts preserves nested notice state.
pub struct ExternalConfigMigrationPrompts {
pub mut:
	home                     ?bool
	home_last_prompted_at    ?i64
	projects                 map[string]bool
	project_last_prompted_at map[string]i64
}

// STUB: Notice's derived Clone owns independent nested migration keys and values.
pub fn (notice &Notice) clone() Notice {
	mut migrations := map[string]string{}
	for key, value in notice.model_migrations {
		migrations[key.clone()] = value.clone()
	}
	mut projects := map[string]bool{}
	for key, value in notice.external_config_migration_prompts.projects {
		projects[key.clone()] = value
	}
	mut times := map[string]i64{}
	for key, value in notice.external_config_migration_prompts.project_last_prompted_at {
		times[key.clone()] = value
	}
	return Notice{
		hide_full_access_warning:                notice.hide_full_access_warning
		hide_world_writable_warning:             notice.hide_world_writable_warning
		fast_default_opt_out:                    notice.fast_default_opt_out
		hide_rate_limit_model_nudge:             notice.hide_rate_limit_model_nudge
		hide_gpt5_1_migration_prompt:            notice.hide_gpt5_1_migration_prompt
		hide_gpt_5_1_codex_max_migration_prompt: notice.hide_gpt_5_1_codex_max_migration_prompt
		model_migrations:                        migrations
		external_config_migration_prompts:       ExternalConfigMigrationPrompts{
			home:                     notice.external_config_migration_prompts.home
			home_last_prompted_at:    notice.external_config_migration_prompts.home_last_prompted_at
			projects:                 projects
			project_last_prompted_at: times
		}
	}
}

// STUB: Tui's derived Clone owns independent strings, arrays, keymaps and NUX counts.
pub fn (tui &Tui) clone() Tui {
	return Tui{
		notification_settings:           tui.notification_settings.clone()
		animations:                      tui.animations
		whimsy:                          tui.whimsy
		show_tooltips:                   tui.show_tooltips
		auto_recap:                      tui.auto_recap
		disable_paste_burst:             tui.disable_paste_burst
		vim_mode_default:                tui.vim_mode_default
		question_esc_back:               tui.question_esc_back
		raw_output_mode:                 tui.raw_output_mode
		alternate_screen:                tui.alternate_screen
		status_line:                     if value := tui.status_line { value.clone() } else { none }
		status_line_use_colors:          tui.status_line_use_colors
		terminal_title:                  if value := tui.terminal_title {
			value.clone()
		} else {
			none
		}
		theme:                           if value := tui.theme { value.clone() } else { none }
		pet:                             if value := tui.pet { value.clone() } else { none }
		pet_anchor:                      tui.pet_anchor
		session_picker_view:             tui.session_picker_view
		resume_cwd:                      tui.resume_cwd
		keymap:                          tui.keymap.clone()
		model_availability_nux:          tui.model_availability_nux.clone()
		terminal_resize_reflow_max_rows: tui.terminal_resize_reflow_max_rows
	}
}

// STUB: serde's TOML deserialization boundary used by the empty-document expected fixture.
// V's generic TOML decoder cannot type-check optional enums. Only the source test's
// empty Tui document is supported here; nonempty documents fail explicitly.
pub fn Tui.from_toml(source &string) !Tui {
	doc := toml.parse_text(source.clone())!
	if doc.to_any().as_map().len != 0 {
		return error('nonempty Tui deserialization requires the config types port')
	}
	return Tui{}
}
