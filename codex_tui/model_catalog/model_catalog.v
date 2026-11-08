// TUI model and collaboration inventories; refreshing models preserves the server mode catalog.
module model_catalog

import codex_protocol.config_types
import codex_protocol.openai_models

// V exports cross-module names because it has no Rust pub(crate) visibility.
pub const luna_reserve_model = 'gpt-reserve'
pub const luna_model = 'gpt-5.6-luna'

// V cannot return a borrowed string slice, so both branches construct an owned result.
// Only ASCII letters are case-insensitive, matching Rust eq_ignore_ascii_case.
pub fn model_display_name(model &string) string {
	if model.len == luna_reserve_model.len {
		mut matches := true
		for index in 0 .. model.len {
			character := (*model)[index]
			folded := if character >= `A` && character <= `Z` { character + 32 } else { character }
			if folded != luna_reserve_model[index] {
				matches = false
				break
			}
		}
		if matches {
			return 'Luna Reserve'.clone()
		}
	}
	return model.clone()
}

// Rust's Clone is implemented explicitly below; V supplies structural debug formatting.
pub struct ModelCatalog {
pub mut:
	models              []openai_models.ModelPreset
	collaboration_modes []config_types.CollaborationModeMask
}

pub fn ModelCatalog.new(models []openai_models.ModelPreset) ModelCatalog {
	return ModelCatalog{
		models:              models
		collaboration_modes: []config_types.CollaborationModeMask{}
	}
}

// Both the receiver and modes are owned, matching Rust's consuming builder.
pub fn (catalog ModelCatalog) with_collaboration_modes(modes []config_types.CollaborationModeMask) ModelCatalog {
	return ModelCatalog{
		models:              catalog.models
		collaboration_modes: modes
	}
}

// V's result syntax retains the fallible call shape of Result<_, Infallible>.
// No error can be constructed by this implementation, as in the Rust source.
pub fn (catalog &ModelCatalog) try_list_models() ![]openai_models.ModelPreset {
	mut models := []openai_models.ModelPreset{cap: catalog.models.len}
	for index in 0 .. catalog.models.len {
		models << (&catalog.models[index]).clone()
	}
	return models
}

pub fn (catalog &ModelCatalog) clone() ModelCatalog {
	mut models := []openai_models.ModelPreset{cap: catalog.models.len}
	for index in 0 .. catalog.models.len {
		models << (&catalog.models[index]).clone()
	}
	mut modes := []config_types.CollaborationModeMask{cap: catalog.collaboration_modes.len}
	for index in 0 .. catalog.collaboration_modes.len {
		modes << (&catalog.collaboration_modes[index]).clone()
	}
	return ModelCatalog{
		models:              models
		collaboration_modes: modes
	}
}
