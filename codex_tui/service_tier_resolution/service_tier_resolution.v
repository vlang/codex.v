module service_tier_resolution

import codex_config.types
import codex_core
import codex_protocol
import codex_protocol.config_types
import codex_protocol.openai_models

// V has no pub(crate) visibility, so cross-module functions are public.
pub fn configured_service_tier(config &codex_core.Config, notices &types.Notice) ?string {
	if tier := config.service_tier {
		return tier.clone()
	}
	if opted_out := notices.fast_default_opt_out {
		if opted_out {
			return config_types.service_tier_default_request_value.clone()
		}
	}
	return none
}

pub fn effective_service_tier(config &codex_core.Config, notices &types.Notice, model &string,
	models &[]openai_models.ModelPreset) ?string {
	if !config.features.enabled(.fast_mode) {
		return none
	}

	configured := configured_service_tier(config, notices)
	mut matching_index := ?int(none)
	for index in 0 .. models.len {
		if (*models)[index].model == *model {
			matching_index = index
			break
		}
	}
	index := matching_index or { return configured }
	preset := &(*models)[index]

	if tier := configured {
		if tier == config_types.service_tier_default_request_value {
			return tier
		}
		if model_supports_service_tier(preset, &tier) {
			return tier
		}
		return none
	}
	if tier := preset.default_service_tier {
		// The source clones the catalog default before filtering it.
		owned_tier := tier.clone()
		if model_supports_service_tier(preset, &owned_tier) {
			return owned_tier
		}
	}
	return none
}

// OptionalString preserves Rust Option<Option<String>>: is_set=false preserves,
// is_set=true/value=none clears, and is_set=true/value=string sets a tier.
// The current source emits preserve or set; the clear state remains representable.
pub fn service_tier_update_for_core(config &codex_core.Config, notices &types.Notice, model &string,
	models &[]openai_models.ModelPreset) codex_protocol.OptionalString {
	if !config.features.enabled(.fast_mode) {
		return codex_protocol.OptionalString{}
	}

	if tier := effective_service_tier(config, notices, model, models) {
		return codex_protocol.OptionalString{
			is_set: true
			value:  tier
		}
	}

	mut found := false
	for index in 0 .. models.len {
		if (*models)[index].model == *model {
			found = true
			break
		}
	}
	if !found {
		return codex_protocol.OptionalString{}
	}
	return codex_protocol.OptionalString{
		is_set: true
		value:  config_types.service_tier_default_request_value.clone()
	}
}

pub fn model_supports_service_tier(model &openai_models.ModelPreset, service_tier &string) bool {
	for index in 0 .. model.service_tiers.len {
		if model.service_tiers[index].id == *service_tier {
			return true
		}
	}
	return false
}
