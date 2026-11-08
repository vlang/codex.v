module openai_models

import chrono
import codex_protocol

// STUB: protocol/src/openai_models.rs::InputModality, used by ModelPreset metadata.
pub enum InputModality {
	text
	image
	audio
}

// STUB: protocol/src/openai_models.rs::ReasoningEffortPreset.
// The existing ReasoningEffort dependency stub cannot retain Custom(String) payloads yet.
pub struct ReasoningEffortPreset {
pub mut:
	effort      ReasoningEffort
	description string
}

// STUB: protocol/src/openai_models.rs::ModelUpgrade; timestamp operations remain in chrono.
pub struct ModelUpgrade {
pub mut:
	id                   string
	migration_config_key string
	model_link           ?string
	upgrade_copy         ?string
	migration_markdown   ?string
	retirement_at        ?chrono.DateTimeUtc
}

// STUB: protocol/src/openai_models.rs::ModelAvailabilityNux.
pub struct ModelAvailabilityNux {
pub mut:
	message string
}

// STUB: protocol/src/openai_models.rs::ModelServiceTier.
pub struct ModelServiceTier {
pub mut:
	id          string
	name        string
	description string
}

// STUB: protocol/src/openai_models.rs::ModelPreset, preserving every metadata field.
// The existing ReasoningEffort dependency stub drops custom effort payloads; protocol
// metadata conversion and serialization are still owned by the untranslated external file.
pub struct ModelPreset {
pub mut:
	id                          string
	model                       string
	display_name                string
	description                 string
	model_specialty             ?string
	default_reasoning_effort    ReasoningEffort = .medium
	supported_reasoning_efforts []ReasoningEffortPreset
	supports_personality        bool
	additional_speed_tiers      []string
	service_tiers               []ModelServiceTier
	default_service_tier        ?string
	is_default                  bool
	upgrade                     ?ModelUpgrade
	show_in_picker              bool
	multi_agent_version         ?codex_protocol.MultiAgentVersion
	availability_nux            ?ModelAvailabilityNux
	supported_in_api            bool
	input_modalities            []InputModality = [.text, .image]
}

// STUB: Derived Clone for protocol/src/openai_models.rs::ModelPreset.
// Explicit construction retains every owned clone boundary under V's ownership checker.
pub fn (preset &ModelPreset) clone() ModelPreset {
	mut efforts := []ReasoningEffortPreset{cap: preset.supported_reasoning_efforts.len}
	for index in 0 .. preset.supported_reasoning_efforts.len {
		effort := &preset.supported_reasoning_efforts[index]
		efforts << ReasoningEffortPreset{
			effort:      effort.effort
			description: effort.description.clone()
		}
	}
	mut speed_tiers := []string{cap: preset.additional_speed_tiers.len}
	for index in 0 .. preset.additional_speed_tiers.len {
		speed_tiers << preset.additional_speed_tiers[index].clone()
	}
	mut tiers := []ModelServiceTier{cap: preset.service_tiers.len}
	for index in 0 .. preset.service_tiers.len {
		tier := &preset.service_tiers[index]
		tiers << ModelServiceTier{
			id:          tier.id.clone()
			name:        tier.name.clone()
			description: tier.description.clone()
		}
	}
	model_specialty := if value := preset.model_specialty {
		?string(value.clone())
	} else {
		?string(none)
	}
	default_service_tier := if value := preset.default_service_tier {
		?string(value.clone())
	} else {
		?string(none)
	}
	upgrade := if value := preset.upgrade {
		?ModelUpgrade(value.clone())
	} else {
		?ModelUpgrade(none)
	}
	availability_nux := if value := preset.availability_nux {
		?ModelAvailabilityNux(ModelAvailabilityNux{ message: value.message.clone() })
	} else {
		?ModelAvailabilityNux(none)
	}
	return ModelPreset{
		id:                          preset.id.clone()
		model:                       preset.model.clone()
		display_name:                preset.display_name.clone()
		description:                 preset.description.clone()
		model_specialty:             model_specialty
		default_reasoning_effort:    preset.default_reasoning_effort
		supported_reasoning_efforts: efforts
		supports_personality:        preset.supports_personality
		additional_speed_tiers:      speed_tiers
		service_tiers:               tiers
		default_service_tier:        default_service_tier
		is_default:                  preset.is_default
		upgrade:                     upgrade
		show_in_picker:              preset.show_in_picker
		multi_agent_version:         preset.multi_agent_version
		availability_nux:            availability_nux
		supported_in_api:            preset.supported_in_api
		input_modalities:            preset.input_modalities.clone()
	}
}

// STUB: Derived Clone for protocol/src/openai_models.rs::ModelUpgrade.
pub fn (upgrade &ModelUpgrade) clone() ModelUpgrade {
	model_link := if value := upgrade.model_link { ?string(value.clone()) } else { ?string(none) }
	upgrade_copy := if value := upgrade.upgrade_copy {
		?string(value.clone())
	} else {
		?string(none)
	}
	markdown := if value := upgrade.migration_markdown {
		?string(value.clone())
	} else {
		?string(none)
	}
	return ModelUpgrade{
		id:                   upgrade.id.clone()
		migration_config_key: upgrade.migration_config_key.clone()
		model_link:           model_link
		upgrade_copy:         upgrade_copy
		migration_markdown:   markdown
		retirement_at:        upgrade.retirement_at
	}
}
