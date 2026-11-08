module model_catalog

import chrono
import codex_protocol
import codex_protocol.config_types
import codex_protocol.openai_models

fn fixture_owned_string(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn fixture_model() openai_models.ModelPreset {
	return openai_models.ModelPreset{
		id:                          fixture_owned_string('primary-preset')
		model:                       fixture_owned_string('gpt-catalog-test')
		display_name:                fixture_owned_string('Catalog Test')
		description:                 fixture_owned_string('A model for exercising owned metadata.')
		model_specialty:             fixture_owned_string('cyber')
		default_reasoning_effort:    .high
		supported_reasoning_efforts: [openai_models.ReasoningEffortPreset{
			effort:      .high
			description: fixture_owned_string('More reasoning')
		}]
		supports_personality:        true
		additional_speed_tiers:      [fixture_owned_string('fast')]
		service_tiers:               [openai_models.ModelServiceTier{
			id:          fixture_owned_string('priority')
			name:        fixture_owned_string('Fast')
			description: fixture_owned_string('Priority processing')
		}]
		default_service_tier:        fixture_owned_string('priority')
		is_default:                  true
		upgrade:                     openai_models.ModelUpgrade{
			id:                   fixture_owned_string('replacement')
			migration_config_key: fixture_owned_string('upgrade_notice')
			model_link:           fixture_owned_string('https://example.invalid/model')
			upgrade_copy:         fixture_owned_string('Try the replacement')
			migration_markdown:   fixture_owned_string('Choose **replacement**.')
			retirement_at:        chrono.DateTimeUtc{
				seconds:     1893456000
				nanoseconds: 123456789
			}
		}
		show_in_picker:              true
		multi_agent_version:         .v2
		availability_nux:            openai_models.ModelAvailabilityNux{
			message: fixture_owned_string('Now available')
		}
		supported_in_api:            true
		input_modalities:            [.text, .image, .audio]
	}
}

fn fixture_mode() config_types.CollaborationModeMask {
	return config_types.CollaborationModeMask{
		name:                   fixture_owned_string('Planning')
		mode:                   .plan
		model:                  fixture_owned_string('gpt-mode-specific')
		reasoning_effort:       codex_protocol.OptionalReasoningEffort{
			is_set: true
			value:  codex_protocol.ReasoningEffortConfig.high
		}
		developer_instructions: codex_protocol.OptionalString{
			is_set: true
			value:  fixture_owned_string('Explain the plan before implementation.')
		}
	}
}

fn test_new_catalog_preserves_models_and_starts_without_modes() {
	mut second := fixture_model()
	second.id = fixture_owned_string('secondary-preset')
	second.model = fixture_owned_string('gpt-other')
	second.service_tiers = []openai_models.ModelServiceTier{}
	second.default_service_tier = none
	second.upgrade = none
	second.availability_nux = none
	models := [fixture_model(), second]
	catalog := ModelCatalog.new(models)
	assert catalog.models.len == 2
	assert catalog.models[0] == fixture_model()
	assert catalog.models[1].id == 'secondary-preset'
	assert catalog.models[1].model == 'gpt-other'
	assert catalog.models[1].service_tiers == []openai_models.ModelServiceTier{}
	assert catalog.models[1].default_service_tier == none
	assert catalog.models[1].upgrade == none
	assert catalog.models[1].availability_nux == none
	assert catalog.collaboration_modes == []config_types.CollaborationModeMask{}
}

fn test_consuming_builder_replaces_modes_and_preserves_models() {
	catalog := ModelCatalog.new([fixture_model()]).with_collaboration_modes([fixture_mode()])
	assert catalog.models == [fixture_model()]
	assert catalog.collaboration_modes == [fixture_mode()]
	replacement := config_types.CollaborationModeMask{
		name:                   fixture_owned_string('Clear custom settings')
		mode:                   .default_mode
		reasoning_effort:       codex_protocol.OptionalReasoningEffort{ is_set: true }
		developer_instructions: codex_protocol.OptionalString{ is_set: true }
	}
	modes := [replacement]
	updated := catalog.with_collaboration_modes(modes)
	assert updated.models == [fixture_model()]
	assert updated.collaboration_modes.len == 1
	assert updated.collaboration_modes[0].name == 'Clear custom settings'
	assert updated.collaboration_modes[0].reasoning_effort.is_set
	assert updated.collaboration_modes[0].reasoning_effort.value == none
	assert updated.collaboration_modes[0].developer_instructions.is_set
	assert updated.collaboration_modes[0].developer_instructions.value == none
}

fn test_list_models_returns_independent_owned_metadata_and_preserves_modes() {
	catalog := ModelCatalog.new([fixture_model()]).with_collaboration_modes([fixture_mode()])
	mut listed := catalog.try_list_models() or { panic(err) }
	assert listed == [fixture_model()]
	listed[0].id = fixture_owned_string('edited-id')
	listed[0].model = fixture_owned_string('edited-model')
	listed[0].display_name = fixture_owned_string('Edited Name')
	listed[0].description = fixture_owned_string('Edited description')
	listed[0].model_specialty = fixture_owned_string('edited-specialty')
	listed[0].supported_reasoning_efforts[0].description = fixture_owned_string('Edited effort')
	listed[0].additional_speed_tiers[0] = fixture_owned_string('edited-speed')
	listed[0].service_tiers[0].id = fixture_owned_string('edited-tier')
	listed[0].service_tiers[0].name = fixture_owned_string('Edited Tier')
	listed[0].service_tiers[0].description = fixture_owned_string('Edited tier description')
	listed[0].default_service_tier = fixture_owned_string('edited-tier')
	mut upgrade := listed[0].upgrade or { panic('fixture must have an upgrade') }
	upgrade.id = fixture_owned_string('edited-upgrade')
	upgrade.migration_config_key = fixture_owned_string('edited-key')
	upgrade.model_link = fixture_owned_string('https://example.invalid/edited')
	upgrade.upgrade_copy = fixture_owned_string('Edited copy')
	upgrade.migration_markdown = fixture_owned_string('Edited markdown')
	listed[0].upgrade = upgrade
	listed[0].availability_nux = openai_models.ModelAvailabilityNux{
		message: fixture_owned_string('Edited notice')
	}
	listed[0].input_modalities[0] = .audio
	assert catalog.try_list_models() or { panic(err) } == [fixture_model()]
	assert catalog.try_list_models() or { panic(err) } == [fixture_model()]
	assert catalog.models == [fixture_model()]
	assert catalog.collaboration_modes == [fixture_mode()]
}

fn test_catalog_clone_preserves_independent_model_and_mode_owners() {
	catalog := ModelCatalog.new([fixture_model()]).with_collaboration_modes([fixture_mode()])
	mut copied := catalog.clone()
	assert copied == catalog
	copied.models[0].service_tiers[0].description = fixture_owned_string('Changed clone')
	copied.collaboration_modes[0].name = fixture_owned_string('Changed mode')
	copied.collaboration_modes[0].model = fixture_owned_string('changed-mode-model')
	copied.collaboration_modes[0].developer_instructions = codex_protocol.OptionalString{
		is_set: true
		value:  fixture_owned_string('Changed instructions')
	}
	assert catalog.models == [fixture_model()]
	assert catalog.collaboration_modes == [fixture_mode()]
	assert catalog.clone() == catalog
}

fn test_catalog_clone_retains_all_nested_optional_mask_states() {
	modes := [config_types.CollaborationModeMask{
		name: fixture_owned_string('Preserve')
	}, config_types.CollaborationModeMask{
		name:                   fixture_owned_string('Clear')
		reasoning_effort:       codex_protocol.OptionalReasoningEffort{ is_set: true }
		developer_instructions: codex_protocol.OptionalString{ is_set: true }
	}, fixture_mode()]
	catalog := ModelCatalog.new([]openai_models.ModelPreset{}).with_collaboration_modes(modes)
	copied := catalog.clone()
	assert copied == catalog
	assert !copied.collaboration_modes[0].reasoning_effort.is_set
	assert !copied.collaboration_modes[0].developer_instructions.is_set
	assert copied.collaboration_modes[1].reasoning_effort.is_set
	assert copied.collaboration_modes[1].reasoning_effort.value == none
	assert copied.collaboration_modes[1].developer_instructions.is_set
	assert copied.collaboration_modes[1].developer_instructions.value == none
	assert copied.collaboration_modes[2] == fixture_mode()
	assert catalog.try_list_models() or { panic(err) } == []openai_models.ModelPreset{}
}

fn test_display_name_uses_only_ascii_case_folding() {
	for input in ['gpt-reserve', 'GPT-RESERVE', 'GpT-ReSeRvE'] {
		assert model_display_name(&input) == 'Luna Reserve'
	}
	for input in ['', 'gpt-5.6-luna', 'gpt-reserve ', ' gpt-reserve', 'gpt-reſerve', 'GPT-REŚERVE'] {
		assert model_display_name(&input) == input
	}
}

fn test_borrowed_display_names_preserve_owned_strings() {
	mut reserve := 'GpT-ReSeRvE'
	mut regular := 'gpt-owned-测试'
	$if ownership ? {
		reserve = reserve.to_owned()
		regular = regular.to_owned()
	}
	mut first := model_display_name(&reserve)
	assert model_display_name(&reserve) == 'Luna Reserve'
	first = first + '!'
	assert first == 'Luna Reserve!'
	assert reserve == 'GpT-ReSeRvE'
	mut displayed := model_display_name(&regular)
	assert model_display_name(&regular) == 'gpt-owned-测试'
	displayed = displayed + '!'
	assert displayed == 'gpt-owned-测试!'
	assert regular == 'gpt-owned-测试'
}
