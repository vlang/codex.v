module codex_core

import codex_state.sqlite

fn terminal_helpers_owned(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value
	}
}

fn test_terminal_settings_survive_shared_config_cloning() {
	config := Config{
		sqlite:                      sqlite.SqliteConfig.new_for_testing(terminal_helpers_owned('/tmp/sqlite-home'))
		codex_home:                  terminal_helpers_owned('/tmp/codex-home')
		cwd:                         terminal_helpers_owned('/tmp/current-workspace')
		respect_system_proxy:        true
		check_for_update_on_startup: false
		developer_instructions:      terminal_helpers_owned('Use the existing project conventions.')
	}
	first := clone_core_config(&config)
	second := clone_core_config(&config)
	assert first == second
	assert config == first
	reloaded := clone_config_with_cwd(&config, terminal_helpers_owned('/tmp/new-workspace'))
	assert reloaded.respect_system_proxy
	assert !reloaded.check_for_update_on_startup
	assert reloaded.developer_instructions == config.developer_instructions
	assert reloaded.cwd == '/tmp/new-workspace'
	assert config.cwd == '/tmp/current-workspace'
	assert config.developer_instructions or { panic('instructions were moved') } == 'Use the existing project conventions.'
}
