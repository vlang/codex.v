// Shared helpers for filtering and matching built-in and model service-tier slash commands.
//
// The same sandbox- and feature-gating rules are used by both the composer
// and the command popup. Centralizing them here keeps those call sites small
// and ensures they stay in sync.
module bottom_pane

import codex_tui.slash_command
import codex_utils_fuzzy_match

pub struct ServiceTierCommand {
pub:
	id          string
	name        string
	description string
}

// The Rust payload enum is represented by an explicit tag and its two typed payloads.
pub enum SlashCommandItemKind {
	builtin
	service_tier
}

pub struct SlashCommandItem {
pub:
	kind         SlashCommandItemKind
	builtin      slash_command.SlashCommand
	service_tier ServiceTierCommand
}

// Rust returns a borrowed string slice. V returns an owned string, allocating for service-tier
// names because their lifetime is tied to the borrowed item; built-in names are static literals.
pub fn (item &SlashCommandItem) command() string {
	return match item.kind {
		.builtin { item.builtin.command() }
		.service_tier { item.service_tier.name.clone() }
	}
}

pub fn (item &SlashCommandItem) supports_inline_args() bool {
	return match item.kind {
		.builtin { item.builtin.supports_inline_args() }
		.service_tier { false }
	}
}

pub fn (item &SlashCommandItem) available_in_side_conversation() bool {
	return match item.kind {
		.builtin { item.builtin.available_in_side_conversation() }
		.service_tier { false }
	}
}

pub fn (item &SlashCommandItem) available_during_task() bool {
	return match item.kind {
		.builtin { item.builtin.available_during_task() }
		.service_tier { true }
	}
}

pub struct BuiltinCommandFlags {
pub mut:
	collaboration_modes_enabled    bool
	connectors_enabled             bool
	plugins_command_enabled        bool
	token_activity_command_enabled bool
	service_tier_commands_enabled  bool
	goal_command_enabled           bool
	personality_command_enabled    bool
	voice_command_enabled          bool
	worktrees_enabled              bool
	allow_elevate_sandbox          bool
	side_conversation_active       bool
}

// Return the built-ins that should be visible/usable for the current input.
pub fn builtins_for_input(flags BuiltinCommandFlags) []slash_command.BuiltInSlashCommand {
	mut commands := []slash_command.BuiltInSlashCommand{}
	for item in slash_command.built_in_slash_commands() {
		if !flags.allow_elevate_sandbox && item.command == .elevate_sandbox {
			continue
		}
		if !flags.collaboration_modes_enabled && item.command == .plan {
			continue
		}
		if !flags.connectors_enabled && item.command == .apps {
			continue
		}
		if !flags.plugins_command_enabled && item.command == .plugins {
			continue
		}
		if !flags.token_activity_command_enabled && item.command == .usage {
			continue
		}
		if !flags.goal_command_enabled && item.command == .goal {
			continue
		}
		if !flags.worktrees_enabled && item.command == .worktree {
			continue
		}
		if !flags.personality_command_enabled && item.command == .personality {
			continue
		}
		if !flags.voice_command_enabled && item.command == .voice {
			continue
		}
		if flags.side_conversation_active && !item.command.available_in_side_conversation() {
			continue
		}
		commands << item
	}
	return commands
}

pub fn commands_for_input(flags BuiltinCommandFlags,
	service_tier_commands &[]ServiceTierCommand) []SlashCommandItem {
	mut commands := []SlashCommandItem{}
	tiers_enabled := flags.service_tier_commands_enabled
	for item in builtins_for_input(flags) {
		cmd := item.command
		commands << SlashCommandItem{ kind: .builtin, builtin: cmd }
		if cmd == .model && tiers_enabled {
			for service_tier in *service_tier_commands {
				commands << SlashCommandItem{ kind: .service_tier, service_tier: service_tier.clone() }
			}
		}
	}
	mut visible := []SlashCommandItem{}
	for command in commands {
		if !flags.side_conversation_active || command.available_in_side_conversation() {
			visible << command
		}
	}
	return visible
}

// Find a single built-in command by a recognized name or alias, after applying feature gating.
//
// Side-conversation and token-activity gating are intentionally enforced by dispatch rather than
// command lookup so a typed command can produce a specific unavailable message while the popup
// still hides it.
pub fn find_builtin_command(name &string, flags BuiltinCommandFlags) ?slash_command.SlashCommand {
	cmd := slash_command.SlashCommand.from_str(name) or {
		if name.len <= 3 || !name.starts_with('g') || !name.ends_with('al') {
			return none
		}
		// Examine the borrowed bytes directly instead of allocating the Rust strip_prefix/suffix
		// string slice. The slice must contain at least one byte, and every byte must be 'o'.
		for index in 1 .. name.len - 2 {
			if (*name)[index] != `o` {
				return none
			}
		}
		slash_command.SlashCommand.goal
	}
	for visible in builtins_for_input(BuiltinCommandFlags{
		...flags
		token_activity_command_enabled: true
		side_conversation_active:       false
	}) {
		if visible.command == cmd {
			return cmd
		}
	}
	return none
}

pub fn find_slash_command(name &string, flags BuiltinCommandFlags,
	service_tier_commands &[]ServiceTierCommand) ?SlashCommandItem {
	if cmd := find_builtin_command(name, flags) {
		return SlashCommandItem{ kind: .builtin, builtin: cmd }
	}
	tiers_enabled := flags.service_tier_commands_enabled
	if tiers_enabled {
		for command in *service_tier_commands {
			if command.name == *name {
				return SlashCommandItem{ kind: .service_tier, service_tier: command.clone() }
			}
		}
	}
	return none
}

pub fn has_slash_command_prefix(name &string, flags BuiltinCommandFlags,
	service_tier_commands &[]ServiceTierCommand) bool {
	for command in commands_for_input(flags, service_tier_commands) {
		command_name := command.command()
		if codex_utils_fuzzy_match.fuzzy_match(&command_name, name) != none {
			return true
		}
	}
	return false
}

// Rust derives Clone for the owned service-tier payload.
pub fn (command &ServiceTierCommand) clone() ServiceTierCommand {
	return ServiceTierCommand{
		id:          command.id.clone()
		name:        command.name.clone()
		description: command.description.clone()
	}
}

// Rust derives Clone for the payload enum; only the service-tier case owns strings.
pub fn (item &SlashCommandItem) clone() SlashCommandItem {
	return match item.kind {
		.builtin { SlashCommandItem{ kind: .builtin, builtin: item.builtin } }
		.service_tier {
			SlashCommandItem{ kind: .service_tier, service_tier: item.service_tier.clone() }
		}
	}
}

// Rust derives Default; every feature flag defaults to false.
pub fn BuiltinCommandFlags.default() BuiltinCommandFlags {
	return BuiltinCommandFlags{}
}
