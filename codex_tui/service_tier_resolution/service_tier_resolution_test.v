module service_tier_resolution

import codex_config.types
import codex_core
import codex_features
import codex_protocol
import codex_protocol.openai_models

fn fixture_owned_string(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn fixture_config(fast_mode bool, tier ?string) codex_core.Config {
	return codex_core.Config{
		service_tier: tier
		features:     codex_features.Features{
			enabled_features: if fast_mode { [.fast_mode] } else { []codex_features.Feature{} }
		}
	}
}

fn fixture_model(tier_ids []string, default_tier ?string) openai_models.ModelPreset {
	mut tiers := []openai_models.ModelServiceTier{cap: tier_ids.len}
	for id in tier_ids {
		tiers << openai_models.ModelServiceTier{
			id: id
		}
	}
	return openai_models.ModelPreset{
		model:                fixture_owned_string('model-a')
		service_tiers:        tiers
		default_service_tier: default_tier
	}
}

fn test_configured_tier_precedes_opt_out() {
	config := fixture_config(true, fixture_owned_string('priority'))
	notices := types.Notice{ fast_default_opt_out: true }
	assert configured_service_tier(&config, &notices) == ?string('priority')
	assert configured_service_tier(&config, &notices) == ?string('priority')
	assert config.service_tier == ?string('priority')
}

fn test_notice_only_explicit_true_selects_standard_routing() {
	config := fixture_config(false, none)
	for opt_out in [?bool(none), ?bool(false), ?bool(true)] {
		notices := types.Notice{ fast_default_opt_out: opt_out }
		expected := if opt_out == ?bool(true) { ?string('default') } else { ?string(none) }
		assert configured_service_tier(&config, &notices) == expected
	}
	assert config.service_tier == none
}

fn test_disabled_feature_preserves_core_despite_explicit_tier_and_catalog_defaults() {
	config := fixture_config(false, fixture_owned_string('priority'))
	notices := types.Notice{ fast_default_opt_out: true }
	model := fixture_owned_string('model-a')
	models := [fixture_model([fixture_owned_string('priority')], fixture_owned_string('priority'))]
	assert effective_service_tier(&config, &notices, &model, &models) == none
	assert service_tier_update_for_core(&config, &notices, &model, &models) == codex_protocol.OptionalString{}
	assert configured_service_tier(&config, &notices) == ?string('priority')
	assert config.service_tier == ?string('priority')
	assert model == 'model-a'
	assert models[0].default_service_tier == ?string('priority')
}

fn test_unknown_model_retains_configured_tier_without_validation() {
	config := fixture_config(true, fixture_owned_string('unlisted-tier'))
	notices := types.Notice{}
	model := fixture_owned_string('unknown-model')
	models := [fixture_model([], none)]
	assert effective_service_tier(&config, &notices, &model, &models) == ?string('unlisted-tier')
	assert service_tier_update_for_core(&config, &notices, &model, &models) == codex_protocol.OptionalString{
		is_set: true
		value:  'unlisted-tier'
	}
	assert config.service_tier == ?string('unlisted-tier')
	assert models[0].model == 'model-a'
	assert model == 'unknown-model'
}

fn test_unknown_model_without_configuration_preserves_core() {
	config := fixture_config(true, none)
	notices := types.Notice{}
	model := fixture_owned_string('unknown-model')
	models := [fixture_model([fixture_owned_string('priority')], fixture_owned_string('priority'))]
	assert effective_service_tier(&config, &notices, &model, &models) == none
	assert service_tier_update_for_core(&config, &notices, &model, &models) == codex_protocol.OptionalString{}
	assert model == 'unknown-model'
	assert models[0].service_tiers[0].id == 'priority'
}

fn test_explicit_standard_routing_bypasses_catalog_support_and_defaults() {
	config := fixture_config(true, fixture_owned_string('default'))
	notices := types.Notice{}
	model := fixture_owned_string('model-a')
	models := [fixture_model([fixture_owned_string('priority')], fixture_owned_string('priority'))]
	assert effective_service_tier(&config, &notices, &model, &models) == ?string('default')
	assert service_tier_update_for_core(&config, &notices, &model, &models) == codex_protocol.OptionalString{
		is_set: true
		value:  'default'
	}
	assert config.service_tier == ?string('default')
	assert models[0].default_service_tier == ?string('priority')
}

fn test_opt_out_selects_standard_for_known_and_unknown_models() {
	config := fixture_config(true, none)
	notices := types.Notice{ fast_default_opt_out: true }
	models := [fixture_model([fixture_owned_string('priority')], fixture_owned_string('priority'))]
	for model in [fixture_owned_string('model-a'), fixture_owned_string('missing')] {
		assert effective_service_tier(&config, &notices, &model, &models) == ?string('default')
		assert service_tier_update_for_core(&config, &notices, &model, &models) == codex_protocol.OptionalString{
			is_set: true
			value:  'default'
		}
		assert model.len > 0
	}
	assert config.service_tier == none
	assert models[0].default_service_tier == ?string('priority')
}

fn test_explicit_supported_tier_wins_over_catalog_default() {
	config := fixture_config(true, fixture_owned_string('flex'))
	notices := types.Notice{}
	model := fixture_owned_string('model-a')
	models := [fixture_model([fixture_owned_string('priority'), fixture_owned_string('flex')], fixture_owned_string('priority'))]
	assert effective_service_tier(&config, &notices, &model, &models) == ?string('flex')
	assert service_tier_update_for_core(&config, &notices, &model, &models) == codex_protocol.OptionalString{
		is_set: true
		value:  'flex'
	}
	assert config.service_tier == ?string('flex')
	assert models[0].service_tiers[1].id == 'flex'
}

fn test_explicit_unsupported_tier_does_not_fall_back_to_catalog_default() {
	config := fixture_config(true, fixture_owned_string('unsupported'))
	notices := types.Notice{}
	model := fixture_owned_string('model-a')
	models := [fixture_model([fixture_owned_string('priority')], fixture_owned_string('priority'))]
	assert effective_service_tier(&config, &notices, &model, &models) == none
	assert service_tier_update_for_core(&config, &notices, &model, &models) == codex_protocol.OptionalString{
		is_set: true
		value:  'default'
	}
	assert config.service_tier == ?string('unsupported')
	assert models[0].default_service_tier == ?string('priority')
}

fn test_catalog_default_requires_supported_tier() {
	config := fixture_config(true, none)
	notices := types.Notice{}
	model := fixture_owned_string('model-a')
	supported := [fixture_model([fixture_owned_string('priority')], fixture_owned_string('priority'))]
	unsupported := [fixture_model([fixture_owned_string('flex')], fixture_owned_string('priority'))]
	missing := [fixture_model([fixture_owned_string('priority')], none)]
	assert effective_service_tier(&config, &notices, &model, &supported) == ?string('priority')
	assert effective_service_tier(&config, &notices, &model, &unsupported) == none
	assert effective_service_tier(&config, &notices, &model, &missing) == none
	assert service_tier_update_for_core(&config, &notices, &model, &supported) == codex_protocol.OptionalString{
		is_set: true
		value:  'priority'
	}
	assert service_tier_update_for_core(&config, &notices, &model, &unsupported) == codex_protocol.OptionalString{
		is_set: true
		value:  'default'
	}
	assert service_tier_update_for_core(&config, &notices, &model, &missing) == codex_protocol.OptionalString{
		is_set: true
		value:  'default'
	}
	assert supported[0].default_service_tier == ?string('priority')
	assert unsupported[0].default_service_tier == ?string('priority')
	assert missing[0].default_service_tier == none
}

fn test_catalog_standard_sentinel_is_validated_when_it_is_a_default() {
	config := fixture_config(true, none)
	notices := types.Notice{}
	model := fixture_owned_string('model-a')
	unsupported := [fixture_model([], fixture_owned_string('default'))]
	supported := [fixture_model([fixture_owned_string('default')], fixture_owned_string('default'))]
	assert effective_service_tier(&config, &notices, &model, &unsupported) == none
	assert effective_service_tier(&config, &notices, &model, &supported) == ?string('default')
	assert unsupported[0].default_service_tier == ?string('default')
	assert supported[0].service_tiers[0].id == 'default'
}

fn test_first_matching_catalog_preset_controls_resolution() {
	config := fixture_config(true, fixture_owned_string('priority'))
	notices := types.Notice{}
	model := fixture_owned_string('model-a')
	models := [fixture_model([], none),
		fixture_model([fixture_owned_string('priority')], fixture_owned_string('priority'))]
	assert effective_service_tier(&config, &notices, &model, &models) == none
	assert service_tier_update_for_core(&config, &notices, &model, &models) == codex_protocol.OptionalString{
		is_set: true
		value:  'default'
	}
	assert models[0].service_tiers.len == 0
	assert models[1].service_tiers[0].id == 'priority'
}

fn test_matching_model_and_tier_are_case_sensitive_and_do_not_trim() {
	config := fixture_config(true, fixture_owned_string('Priority'))
	notices := types.Notice{}
	model := fixture_owned_string('model-a')
	models := [fixture_model([fixture_owned_string('priority')], fixture_owned_string('priority'))]
	assert effective_service_tier(&config, &notices, &model, &models) == none
	upper_model := fixture_owned_string('MODEL-A')
	assert effective_service_tier(&config, &notices, &upper_model, &models) == ?string('Priority')
	spaced := fixture_owned_string(' priority ')
	assert !model_supports_service_tier(&models[0], &spaced)
	assert config.service_tier == ?string('Priority')
	assert upper_model == 'MODEL-A'
	assert spaced == ' priority '
}

fn test_empty_tier_is_an_explicit_value_and_can_be_supported() {
	config := fixture_config(true, fixture_owned_string(''))
	notices := types.Notice{ fast_default_opt_out: true }
	model := fixture_owned_string('model-a')
	unsupported := [fixture_model([fixture_owned_string('priority')], fixture_owned_string('priority'))]
	supported := [fixture_model([fixture_owned_string('')], none)]
	assert configured_service_tier(&config, &notices) == ?string('')
	assert effective_service_tier(&config, &notices, &model, &unsupported) == none
	assert effective_service_tier(&config, &notices, &model, &supported) == ?string('')
	assert service_tier_update_for_core(&config, &notices, &model, &supported) == codex_protocol.OptionalString{
		is_set: true
		value:  ''
	}
	assert config.service_tier == ?string('')
	assert supported[0].service_tiers[0].id == ''
}

fn test_borrowed_tier_query_and_catalog_remain_reusable() {
	model := fixture_model([fixture_owned_string('priority'), fixture_owned_string('flex')], fixture_owned_string('priority'))
	query := fixture_owned_string('flex')
	missing := fixture_owned_string('other')
	assert model_supports_service_tier(&model, &query)
	assert model_supports_service_tier(&model, &query)
	assert !model_supports_service_tier(&model, &missing)
	assert query == 'flex'
	assert missing == 'other'
	assert model.model == 'model-a'
	assert model.service_tiers[1].id == 'flex'
	assert model.default_service_tier == ?string('priority')
}

fn test_config_clone_boundaries_retain_independent_service_tier() {
	config := fixture_config(true, fixture_owned_string('priority'))
	mut changed_cwd := codex_core.clone_config_with_cwd(&config, fixture_owned_string('/new-cwd'))
	assert changed_cwd.service_tier == ?string('priority')
	changed_cwd.service_tier = fixture_owned_string('flex')
	assert config.service_tier == ?string('priority')
	assert changed_cwd.service_tier == ?string('flex')
	live_thread := codex_core.CodexThread{ config: config }
	mut first := live_thread.config()
	mut second := live_thread.config()
	assert first.service_tier == ?string('priority')
	assert second.service_tier == ?string('priority')
	first.service_tier = fixture_owned_string('flex')
	second.service_tier = none
	assert live_thread.config.service_tier == ?string('priority')
	assert first.service_tier == ?string('flex')
	assert second.service_tier == none
	assert changed_cwd.cwd == '/new-cwd'
}

fn test_nested_optional_representation_distinguishes_preserve_clear_and_set() {
	preserve := codex_protocol.OptionalString{}
	clear := codex_protocol.OptionalString{ is_set: true }
	set := codex_protocol.OptionalString{ is_set: true, value: fixture_owned_string('priority') }
	assert preserve != clear
	assert preserve != set
	assert clear != set
	assert !preserve.is_set
	assert preserve.value == none
	assert clear.is_set
	assert clear.value == none
	assert set.value == ?string('priority')
}
