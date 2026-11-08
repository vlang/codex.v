module bottom_pane

import codex_tui.slash_command

fn all_enabled_flags() BuiltinCommandFlags {
	return BuiltinCommandFlags{
		collaboration_modes_enabled:    true
		connectors_enabled:             true
		plugins_command_enabled:        true
		token_activity_command_enabled: true
		service_tier_commands_enabled:  true
		goal_command_enabled:           true
		personality_command_enabled:    true
		voice_command_enabled:          true
		worktrees_enabled:              true
		allow_elevate_sandbox:          true
		side_conversation_active:       false
	}
}

// The Rust fixtures call to_string on each literal. Keep these allocations visible to ownership.
fn owned_slash_command_test_string(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_worktree_command_lookup_requires_feature() {
	name := 'worktree'
	assert find_builtin_command(&name, BuiltinCommandFlags.default()) == none
	assert (find_builtin_command(&name, all_enabled_flags()) or { panic('expected a worktree command') }) == .worktree
}

fn test_debug_command_still_resolves_for_dispatch() {
	name := 'debug-config'
	cmd := find_builtin_command(&name, all_enabled_flags())
	assert (cmd or { panic('expected a debug-config command') }) == .debug_config
}

fn test_clear_command_resolves_for_dispatch() {
	name := 'clear'
	assert (find_builtin_command(&name, all_enabled_flags()) or { panic('expected a clear command') }) == .clear
}

fn test_goal_command_allows_extra_os_for_dispatch() {
	name := 'goooooooooooal'
	assert (find_builtin_command(&name, all_enabled_flags()) or { panic('expected a goal command') }) == .goal
}

fn test_stop_command_resolves_for_dispatch() {
	name := 'stop'
	assert (find_builtin_command(&name, all_enabled_flags()) or { panic('expected a stop command') }) == .stop
}

fn test_clean_command_alias_resolves_for_dispatch() {
	name := 'clean'
	assert (find_builtin_command(&name, all_enabled_flags()) or { panic('expected a stop command') }) == .stop
}

fn test_service_tier_commands_are_hidden_when_disabled() {
	mut flags := all_enabled_flags()
	flags.service_tier_commands_enabled = false
	commands := [ServiceTierCommand{
		id:          owned_slash_command_test_string('priority')
		name:        owned_slash_command_test_string('fast')
		description: owned_slash_command_test_string('fastest inference')
	}]
	name := 'fast'
	assert find_slash_command(&name, flags, &commands) == none
}

fn test_all_service_tiers_are_exposed_as_commands_after_model() {
	commands := [
		ServiceTierCommand{
			id:          owned_slash_command_test_string('priority')
			name:        owned_slash_command_test_string('fast')
			description: owned_slash_command_test_string('fastest inference')
		},
		ServiceTierCommand{
			id:          owned_slash_command_test_string('batch')
			name:        owned_slash_command_test_string('slow')
			description: owned_slash_command_test_string('slower inference with lower priority')
		},
	]
	items := commands_for_input(all_enabled_flags(), &commands)
	mut model_idx := -1
	for index, item in items {
		if item.kind == .builtin && item.builtin == .model {
			model_idx = index
			break
		}
	}
	assert model_idx >= 0, 'model command should be visible'
	mut inserted := []SlashCommandItem{}
	for item in items[model_idx + 1..model_idx + 1 + commands.len] {
		inserted << item.clone()
	}
	mut expected := []SlashCommandItem{}
	for command in commands {
		expected << SlashCommandItem{ kind: .service_tier, service_tier: command }
	}
	assert inserted == expected
}

fn test_goal_command_is_hidden_when_disabled() {
	mut flags := all_enabled_flags()
	flags.goal_command_enabled = false
	name := 'goal'
	assert find_builtin_command(&name, flags) == none
}

fn test_voice_command_is_hidden_when_disabled() {
	mut flags := all_enabled_flags()
	flags.voice_command_enabled = false
	name := 'voice'
	assert find_builtin_command(&name, flags) == none
}

fn test_usage_command_is_hidden_from_input_when_account_token_activity_is_disabled() {
	mut flags := all_enabled_flags()
	flags.token_activity_command_enabled = false
	mut found := ?slash_command.BuiltInSlashCommand(none)
	for item in builtins_for_input(flags) {
		if item.command == .usage {
			found = item
			break
		}
	}
	assert found == none
}

fn test_usage_command_exact_lookup_still_resolves_when_account_token_activity_is_disabled() {
	mut flags := all_enabled_flags()
	flags.token_activity_command_enabled = false
	name := 'usage'
	assert (find_builtin_command(&name, flags) or { panic('expected a usage command') }) == .usage
}

fn test_side_conversation_hides_commands_without_side_flag() {
	mut commands := []slash_command.SlashCommand{}
	for item in builtins_for_input(BuiltinCommandFlags{
		...all_enabled_flags()
		side_conversation_active: true
	}) {
		commands << item.command
	}
	assert commands == [slash_command.SlashCommand.ide, .agents, .copy, .export_cmd, .raw, .diff,
		.mention, .status, .pwd, .usage]
}

fn test_side_conversation_exact_lookup_still_resolves_hidden_commands_for_dispatch_error() {
	name := 'review'
	assert (find_builtin_command(&name, BuiltinCommandFlags{
		...all_enabled_flags()
		side_conversation_active: true
	}) or { panic('expected a review command') }) == .review
}

fn test_side_conversation_exact_lookup_still_resolves_service_tier_commands_for_dispatch_error() {
	command := ServiceTierCommand{
		id:          owned_slash_command_test_string('priority')
		name:        owned_slash_command_test_string('fast')
		description: owned_slash_command_test_string('fastest inference')
	}
	flags := BuiltinCommandFlags{
		...all_enabled_flags()
		side_conversation_active: true
	}
	name := 'fast'
	// std::slice::from_ref borrows one command. V has no borrowed single-element array view, so
	// construct a temporary owned array with a clone while keeping the original fixture reusable.
	commands := [command.clone()]
	assert (find_slash_command(&name, flags, &commands) or { panic('expected a service-tier command') }) == SlashCommandItem{
		kind:         .service_tier
		service_tier: command
	}
}

fn test_slash_command_helpers_keep_borrowed_owners_reusable() {
	name := owned_slash_command_test_string('fast')
	command := ServiceTierCommand{
		id:          owned_slash_command_test_string('priority')
		name:        owned_slash_command_test_string('fast')
		description: owned_slash_command_test_string('fastest inference')
	}
	commands := [command.clone()]
	flags := all_enabled_flags()
	first := find_slash_command(&name, flags, &commands) or { panic('expected a service tier') }
	second := find_slash_command(&name, flags, &commands) or { panic('expected a service tier') }
	first_name := first.command()
	second_name := first.command()
	assert first_name == name
	assert second_name == name
	assert first == second
	assert commands[0] == command
	assert command.id == 'priority'
	assert name == 'fast'
	assert !first.supports_inline_args()
	assert !first.available_in_side_conversation()
	assert first.available_during_task()
	first_items := commands_for_input(flags, &commands)
	second_items := commands_for_input(flags, &commands)
	assert first_items == second_items
	assert commands[0].name == name
	assert has_slash_command_prefix(&name, flags, &commands)
	assert has_slash_command_prefix(&name, flags, &commands)
	assert commands[0].description == 'fastest inference'
	assert name == 'fast'
}
