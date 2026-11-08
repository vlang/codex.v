module local_settings

import os
import time
import toml
import codex_core
import codex_core.config as core_config
import codex_core.config.edit
import codex_config
import codex_config.types
import codex_protocol.config_types
import codex_utils_absolute_path

fn local_settings_owned(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn local_settings_temp_home(label &string) !string {
	directory := os.join_path(os.temp_dir(), 'codex-v-local-settings-${*label}-${os.getpid()}-${time.now().unix_nano()}')
	os.mkdir_all(directory.clone())!
	return directory
}

// The Rust async ConfigBuilder boundary is synchronous in its local-loading stub.
fn test_local_load_preserves_defaults_and_resolved_overrides() {
	for config_text in [
		'',
		'
[tui]
animations = false
whimsy = false
show_tooltips = false
auto_recap = false
vim_mode_default = true
terminal_resize_reflow_max_rows = 0
session_picker_view = "comfortable"
[history]
persistence = "none"
max_bytes = 4096
[notice]
fast_default_opt_out = true
',
	] {
		label := 'load'
		home := local_settings_temp_home(&label) or { panic(err) }
		defer { os.rmdir_all(home.clone()) or { panic(err) } }
		os.write_file(os.join_path(home.clone(), 'config.toml'), config_text.clone()) or { panic(err) }
		mut overrides := codex_config.LoaderOverrides.without_managed_config_for_tests()
		overrides.ignore_project_config = true
		initial_builder := codex_core.ConfigBuilder.default()
		home_builder := initial_builder.codex_home(home.clone())
		loader_builder := home_builder.loader_overrides(overrides)
		configured_builder := loader_builder.cli_overrides([codex_core.PermissionCliOverride{ key: local_settings_owned('tui.disable_paste_burst'), value: toml.Any(true) }])
		config := configured_builder.build() or { panic(err) }
		local := LocalSettings.from(&config)
		empty_toml := ''
		mut expected := types.Tui.from_toml(&empty_toml) or { panic(err) }
		expected.disable_paste_burst = true
		expected.session_picker_view = .dense
		if config_text.len != 0 {
			expected.animations = false
			expected.whimsy = false
			expected.show_tooltips = false
			expected.auto_recap = false
			expected.vim_mode_default = true
			expected.terminal_resize_reflow_max_rows = usize(0)
			expected.session_picker_view = .comfortable
		}
		assert local.tui == expected
		assert local.terminal_resize_reflow() == config.terminal_resize_reflow
		assert local.history == config.history
		assert local.notices == config.notices
	}
}

// Source destinations and both independent config writes remain executable on disk.
fn test_local_writes_preserve_selected_user_file_and_home_destinations() {
	label := 'write'
	home := local_settings_temp_home(&label) or { panic(err) }
	defer { os.rmdir_all(home.clone()) or { panic(err) } }
	selected_path := os.join_path(home.clone(), 'work.config.toml')
	selected := codex_utils_absolute_path.from_absolute_path(&selected_path) or { panic(err) }
	os.write_file(selected.path.clone(), '[tui]\ntheme = "dracula"\n') or { panic(err) }
	work := 'work'
	mut overrides := codex_config.LoaderOverrides.without_managed_config_for_tests()
	overrides.user_config_path = selected.clone()
	overrides.user_config_profile = config_types.ProfileV2Name.parse(&work) or { panic(err) }
	overrides.ignore_project_config = true
	initial_builder := codex_core.ConfigBuilder.default()
	home_builder := initial_builder.codex_home(home.clone())
	configured_builder := home_builder.loader_overrides(overrides.clone())
	config := configured_builder.build() or { panic(err) }
	local := LocalSettings.from(&config)
	assert local.user_config_path == selected
	selected_view := local.user_config_path.as_path()
	nord := 'nord'
	edit.ConfigEditsBuilder.for_config_path(&selected_view)
		.with_edits([edit.syntax_theme_edit(&nord)])
		.apply() or { panic(err) }
	home_view := local.codex_home.as_path()
	edit.ConfigEditsBuilder.new(&home_view)
		.set_session_picker_view(.comfortable)
		.apply() or { panic(err) }
	reload_initial := codex_core.ConfigBuilder.default()
	reload_home := reload_initial.codex_home(home.clone())
	reload_configured := reload_home.loader_overrides(overrides)
	reloaded := reload_configured.build() or { panic(err) }
	assert LocalSettings.from(&reloaded).tui.theme == ?string('nord')
	home_config := toml.parse_text(os.read_file(os.join_path(home.clone(), 'config.toml')) or { panic(err) }) or { panic(err) }
	assert home_config.value('tui.session_picker_view').string() == 'comfortable'
	assert home_config.value('tui.theme') == toml.Any(toml.Null{})
}

fn test_terminal_resize_reflow_round_trips_auto_disabled_and_explicit_limits() {
	for resize in [
		core_config.TerminalResizeReflowMaxRows{ kind: .auto },
		core_config.TerminalResizeReflowMaxRows{ kind: .disabled },
		core_config.TerminalResizeReflowMaxRows{ kind: .limit, limit: 42 },
		core_config.TerminalResizeReflowMaxRows{ kind: .limit, limit: 1000 },
	] {
		config := codex_core.Config{ terminal_resize_reflow: core_config.TerminalResizeReflowConfig{ max_rows: resize } }
		local := LocalSettings.from(&config)
		assert local.terminal_resize_reflow() == config.terminal_resize_reflow
		assert local.tui.terminal_resize_reflow_max_rows == match resize.kind {
			.auto { ?usize(none) }
			.disabled { ?usize(0) }
			.limit { ?usize(resize.limit) }
		}
	}
}

fn test_repeated_borrows_clone_all_preferences_and_independent_nested_state() {
	owner := codex_core.Config{
		codex_home:                    local_settings_owned('/tmp/preferences-home')
		tui_notifications:             types.TuiNotificationSettings{ notifications: types.Notifications{ kind: .custom, custom: [local_settings_owned('agent-turn-complete')] }, method: .osc9, condition: .always }
		animations:                    false
		tui_whimsy:                    false
		show_tooltips:                 false
		tui_auto_recap:                false
		disable_paste_burst:           true
		tui_vim_mode_default:          true
		tui_question_esc_back:         false
		tui_raw_output_mode:           true
		tui_alternate_screen:          .never
		tui_status_line:               [local_settings_owned('thread-name')]
		tui_status_line_use_colors:    false
		tui_terminal_title:            [local_settings_owned('activity')]
		tui_theme:                     local_settings_owned('dracula')
		tui_pet:                       local_settings_owned('codex-pet')
		tui_pet_anchor:                .screen_bottom
		tui_session_picker_view:       .comfortable
		tui_resume_cwd:                .session
		tui_keymap:                    types.TuiKeymap{ composer: types.TuiComposerKeymap{ submit: types.KeybindingsSpec.from_many([types.KeybindingSpec{ value: local_settings_owned('ctrl-enter') }]) } }
		model_availability_nux:        types.ModelAvailabilityNuxConfig{
			shown_count: {
				local_settings_owned('model-a'): u32(2)
			}
		}
		terminal_resize_reflow:        core_config.TerminalResizeReflowConfig{ max_rows: core_config.TerminalResizeReflowMaxRows{ kind: .limit, limit: 87 } }
		history:                       types.History{ persistence: .none_, max_bytes: usize(4096) }
		notices:                       types.Notice{
			model_migrations:                  {
				local_settings_owned('old'): local_settings_owned('new')
			}
			external_config_migration_prompts: types.ExternalConfigMigrationPrompts{
				home:                     true
				home_last_prompted_at:    i64(8)
				projects:                 {
					local_settings_owned('/project'): true
				}
				project_last_prompted_at: {
					local_settings_owned('/project'): i64(42)
				}
			}
		}
		permission_config_layer_stack: codex_config.ConfigLayerStack{ layers: [codex_config.ConfigLayerEntry{ name: .user, user_file: codex_utils_absolute_path.AbsolutePathBuf{ path: local_settings_owned('/tmp/work.config.toml') } }] }
	}
	mut first := LocalSettings.from(&owner)
	second := LocalSettings.from(&owner)
	assert first == second
	assert first == second.clone()
	assert first.codex_home.path == '/tmp/preferences-home'
	assert first.user_config_path.path == '/tmp/work.config.toml'
	assert first.tui.notification_settings == owner.tui_notifications
	assert !first.tui.animations && !first.tui.whimsy && !first.tui.show_tooltips && !first.tui.auto_recap
	assert first.tui.disable_paste_burst == ?bool(true) && first.tui.vim_mode_default
	assert !first.tui.question_esc_back && first.tui.raw_output_mode && first.tui.alternate_screen == .never
	assert first.tui.status_line == owner.tui_status_line && !first.tui.status_line_use_colors
	assert first.tui.terminal_title == owner.tui_terminal_title && first.tui.theme == owner.tui_theme
	assert first.tui.pet == owner.tui_pet && first.tui.pet_anchor == .screen_bottom
	assert first.tui.session_picker_view == ?types.SessionPickerViewMode(.comfortable)
	assert first.tui.resume_cwd == ?types.ResumeCwdMode(.session)
	assert first.tui.keymap == owner.tui_keymap && first.tui.model_availability_nux == owner.model_availability_nux
	assert first.history == owner.history && first.notices == owner.notices
	assert first.terminal_resize_reflow() == owner.terminal_resize_reflow
	first.tui.notification_settings.notifications.custom[0] = local_settings_owned('changed-event')
	first.tui.model_availability_nux.shown_count['model-a'] = 99
	first.notices.model_migrations['old'] = local_settings_owned('changed-model')
	first.notices.external_config_migration_prompts.projects['/project'] = false
	mut cloned_config := owner.clone()
	assert LocalSettings.from(&cloned_config) == second
	cloned_config.tui_notifications.notifications.custom[0] = local_settings_owned('config-event')
	cloned_config.model_availability_nux.shown_count['model-a'] = 55
	cloned_config.notices.model_migrations['old'] = local_settings_owned('config-model')
	mut bindings := cloned_config.tui_keymap.composer.submit or { panic('missing submit') }
	bindings.many[0].value = local_settings_owned('alt-enter')
	cloned_config.tui_keymap.composer.submit = bindings
	retargeted := codex_core.clone_config_with_cwd(&owner, local_settings_owned('/tmp/new-cwd'))
	assert LocalSettings.from(&retargeted) == second
	assert LocalSettings.from(&owner) == second
	assert owner.tui_notifications.notifications.custom[0] == 'agent-turn-complete'
	assert owner.model_availability_nux.shown_count['model-a'] == 2
	assert owner.notices.model_migrations['old'] == 'new'
	assert owner.notices.external_config_migration_prompts.projects['/project']
	source_bindings := owner.tui_keymap.composer.submit or { panic('source keymap consumed') }
	assert source_bindings.many[0].value == 'ctrl-enter'
	assert owner.tui_theme or { panic('theme consumed') } == 'dracula'
	assert owner.codex_home == '/tmp/preferences-home'
}
