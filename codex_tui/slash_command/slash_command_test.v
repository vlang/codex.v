module slash_command

import strum

fn test_stop_command_is_canonical_name() {
	assert SlashCommand.stop.command() == 'stop'
}

fn test_clean_alias_parses_to_stop_command() {
	name := 'clean'
	assert (SlashCommand.from_str(&name) or { panic(err) }) == .stop
}

fn test_pet_alias_parses_to_pets_command() {
	assert SlashCommand.pets.command() == 'pets'
	name := 'pet'
	assert (SlashCommand.from_str(&name) or { panic(err) }) == .pets
}

fn test_certain_commands_are_available_during_task() {
	assert SlashCommand.goal.available_during_task()
	assert SlashCommand.ide.available_during_task()
	assert SlashCommand.title.available_during_task()
	assert SlashCommand.statusline.available_during_task()
	assert SlashCommand.raw.available_during_task()
	assert SlashCommand.raw.available_in_side_conversation()
	assert SlashCommand.raw.supports_inline_args()
	assert SlashCommand.app.available_during_task()
}

fn test_auto_review_command_is_approve() {
	assert SlashCommand.auto_review.command() == 'approve'
	name := 'approve'
	assert (SlashCommand.from_str(&name) or { panic(err) }) == .auto_review
}

fn test_borrowed_parser_keeps_owned_input_reusable() {
	name := $if ownership ? { 'cwd'.to_owned() } $else { 'cwd' }
	first := SlashCommand.from_str(&name) or { panic(err) }
	second := SlashCommand.from_str(&name) or { panic(err) }
	third := SlashCommand.try_from(&name) or { panic(err) }
	assert first == .pwd
	assert second == first
	assert third == first
	assert name == 'cwd'
	assert first.command() == 'pwd'
	assert first.as_ref() == 'pwd'
	assert first.into_static_str() == 'pwd'
}

fn test_parser_rejects_unknown_spelling_with_typed_error() {
	for name in ['', '/goal', 'Goal', ' goal', 'auto-review', 'memory-drop', 'unknown'] {
		if command := SlashCommand.from_str(&name) {
			assert false, 'unexpectedly parsed ${name} as ${command}'
		} else {
			assert err is strum.ParseError
			assert err.kind == .variant_not_found
			assert err.msg() == 'Matching variant not found'
		}
	}
}

fn test_enum_string_conversions_round_trip_in_declaration_order() {
	commands := SlashCommand.iter()
	for command in commands {
		name := command.command()
		assert (SlashCommand.from_str(&name) or { panic(err) }) == command
		assert (SlashCommand.try_from(&name) or { panic(err) }) == command
		assert command.as_ref() == name
		assert command.into_static_str() == name
	}
	mut names := []string{}
	mut previous_position := -1
	for item in built_in_slash_commands() {
		position := commands.index(item.command)
		assert position > previous_position
		previous_position = position
		names << item.name
	}
	$if windows {
		assert 'sandbox-add-read-dir' in names
	} $else {
		assert 'sandbox-add-read-dir' !in names
	}
	$if android {
		assert 'copy' !in names
	} $else {
		assert 'copy' in names
	}
	$if macos || windows {
		assert 'app' in names
	} $else {
		assert 'app' !in names
	}
	$if prod {
		assert 'rollout' !in names
		assert 'test-approval' !in names
	} $else {
		assert 'rollout' in names
		assert 'test-approval' in names
	}
}
