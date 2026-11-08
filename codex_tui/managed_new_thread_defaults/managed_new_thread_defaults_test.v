module managed_new_thread_defaults

import codex_app_server_protocol as api
import codex_core
import codex_protocol.config_types
import codex_protocol.openai_models
import os
import toml
import uuid

fn owned(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn make_test_config() codex_core.Config {
	codex_home := os.join_path(os.temp_dir(), 'codex-managed-new-thread-defaults-${uuid.Uuid.new_v4()}')
	os.mkdir(codex_home) or { panic('tempdir: ${err}') }
	initial_builder := codex_core.ConfigBuilder.default()
	home_builder := initial_builder.codex_home(codex_home)
	return home_builder.build() or { panic('config: ${err}') }
}

fn defaults() api.NewThreadModelDefaults {
	return api.NewThreadModelDefaults{
		model:                  owned('managed-model')
		model_reasoning_effort: openai_models.ReasoningEffort.high
		service_tier:           owned('fast')
	}
}

fn test_applies_managed_defaults_to_a_new_thread_config() {
	mut actual := make_test_config()
	defer { os.rmdir_all(actual.codex_home) or {} }
	actual.model = owned('configured-model')
	actual.model_reasoning_effort = openai_models.ReasoningEffort.low
	actual.service_tier = owned('flex')
	mut expected := actual.clone()
	expected.model = owned('managed-model')
	expected.model_reasoning_effort = openai_models.ReasoningEffort.high
	expected.service_tier = config_types.ServiceTier.fast.request_value().clone()
	managed := defaults()
	cli_kv_overrides := []codex_core.PermissionCliOverride{}
	harness_overrides := codex_core.ConfigOverrides{}

	apply_managed_new_thread_defaults(mut actual, BorrowedNewThreadModelDefaults{ value: &managed }, &cli_kv_overrides, &harness_overrides)

	assert actual == expected
}

fn test_explicit_model_skips_managed_model_and_reasoning_effort() {
	mut actual := make_test_config()
	defer { os.rmdir_all(actual.codex_home) or {} }
	actual.model = owned('explicit-model')
	actual.model_reasoning_effort = none
	actual.service_tier = owned('flex')
	mut expected := actual.clone()
	expected.service_tier = config_types.ServiceTier.fast.request_value().clone()
	harness_overrides := codex_core.ConfigOverrides{
		model: owned('explicit-model')
	}
	managed := defaults()
	cli_kv_overrides := []codex_core.PermissionCliOverride{}

	apply_managed_new_thread_defaults(mut actual, BorrowedNewThreadModelDefaults{ value: &managed }, &cli_kv_overrides, &harness_overrides)

	assert actual == expected
}

fn test_explicit_reasoning_effort_skips_managed_model_and_reasoning_effort() {
	mut actual := make_test_config()
	defer { os.rmdir_all(actual.codex_home) or {} }
	actual.model = owned('configured-model')
	actual.model_reasoning_effort = openai_models.ReasoningEffort.low
	actual.service_tier = owned('flex')
	mut expected := actual.clone()
	expected.service_tier = config_types.ServiceTier.fast.request_value().clone()
	cli_kv_overrides := [codex_core.PermissionCliOverride{
		key:   owned('model_reasoning_effort')
		value: toml.Any(owned('low'))
	}]
	managed := defaults()
	harness_overrides := codex_core.ConfigOverrides{}

	apply_managed_new_thread_defaults(mut actual, BorrowedNewThreadModelDefaults{ value: &managed }, &cli_kv_overrides, &harness_overrides)

	assert actual == expected
}

fn test_explicit_launch_overrides_take_precedence() {
	mut actual := make_test_config()
	defer { os.rmdir_all(actual.codex_home) or {} }
	actual.model = owned('explicit-model')
	actual.model_reasoning_effort = openai_models.ReasoningEffort.low
	actual.service_tier = owned('flex')
	expected := actual.clone()
	cli_kv_overrides := [codex_core.PermissionCliOverride{
		key:   owned('model_reasoning_effort')
		value: toml.Any(owned('low'))
	}]
	harness_overrides := codex_core.ConfigOverrides{
		model:        owned('explicit-model')
		service_tier: api.ClearableString{ has_value: true, value: owned('flex') }
	}
	managed := defaults()

	apply_managed_new_thread_defaults(mut actual, BorrowedNewThreadModelDefaults{ value: &managed }, &cli_kv_overrides, &harness_overrides)

	assert actual == expected
}

fn test_borrowed_defaults_and_overrides_remain_reusable() {
	managed := defaults()
	cli_kv_overrides := [codex_core.PermissionCliOverride{
		key:   owned('unrelated_setting')
		value: toml.Any(owned('kept'))
	}]
	harness_overrides := codex_core.ConfigOverrides{
		model_provider: owned('provider')
	}
	borrowed := BorrowedNewThreadModelDefaults{ value: &managed }
	mut first := codex_core.Config{}
	mut second := codex_core.Config{}
	apply_managed_new_thread_defaults(mut first, borrowed, &cli_kv_overrides, &harness_overrides)
	apply_managed_new_thread_defaults(mut second, borrowed, &cli_kv_overrides, &harness_overrides)
	assert first == second
	assert first.model or { panic('model') } == 'managed-model'
	assert first.service_tier or { panic('tier') } == 'priority'
	assert managed.model or { panic('managed model') } == 'managed-model'
	assert managed.model_reasoning_effort or { panic('managed effort') } == .high
	assert managed.service_tier or { panic('managed tier') } == 'fast'
	assert cli_kv_overrides[0].key == 'unrelated_setting'
	assert cli_kv_overrides[0].value as string == 'kept'
	assert harness_overrides.model_provider or { panic('provider') } == 'provider'
}

fn test_absent_managed_defaults_and_absent_fields_preserve_config() {
	mut actual := codex_core.Config{
		model:                  owned('configured-model')
		model_reasoning_effort: openai_models.ReasoningEffort.low
		service_tier:           owned('flex')
	}
	expected := actual.clone()
	cli_kv_overrides := []codex_core.PermissionCliOverride{}
	harness_overrides := codex_core.ConfigOverrides{}
	apply_managed_new_thread_defaults(mut actual, none, &cli_kv_overrides, &harness_overrides)
	assert actual == expected
	managed := api.NewThreadModelDefaults{}
	apply_managed_new_thread_defaults(mut actual, BorrowedNewThreadModelDefaults{ value: &managed }, &cli_kv_overrides, &harness_overrides)
	assert actual == expected
}

fn test_generic_model_and_service_tier_overrides_preserve_explicit_choices() {
	mut actual := codex_core.Config{
		model:                  owned('explicit-model')
		model_reasoning_effort: openai_models.ReasoningEffort.low
		service_tier:           owned('flex')
	}
	expected := actual.clone()
	managed := defaults()
	cli_kv_overrides := [codex_core.PermissionCliOverride{
		key:   owned('model')
		value: toml.Any(owned('explicit-model'))
	}, codex_core.PermissionCliOverride{
		key:   owned('service_tier')
		value: toml.Any(owned('flex'))
	}]
	harness_overrides := codex_core.ConfigOverrides{}
	borrowed := BorrowedNewThreadModelDefaults{ value: &managed }
	apply_managed_new_thread_defaults(mut actual, borrowed, &cli_kv_overrides, &harness_overrides)
	apply_managed_new_thread_defaults(mut actual, borrowed, &cli_kv_overrides, &harness_overrides)
	assert actual == expected
	assert cli_kv_overrides[0].key == 'model'
	assert cli_kv_overrides[1].key == 'service_tier'
	assert managed.model or { panic('managed model') } == 'managed-model'
}

fn test_explicit_service_tier_clear_is_preserved_independently() {
	mut actual := codex_core.Config{
		model:        owned('configured-model')
		service_tier: none
	}
	managed := defaults()
	cli_kv_overrides := []codex_core.PermissionCliOverride{}
	harness_overrides := codex_core.ConfigOverrides{
		service_tier: api.ClearableString{ has_value: true, clear: true }
	}
	apply_managed_new_thread_defaults(mut actual, BorrowedNewThreadModelDefaults{ value: &managed }, &cli_kv_overrides, &harness_overrides)
	assert actual.model or { panic('model') } == 'managed-model'
	assert actual.model_reasoning_effort or { panic('effort') } == .high
	assert actual.service_tier == none
}

fn test_managed_tier_normalizes_known_values_and_preserves_unknown_values() {
	for value in ['fast', 'priority', 'flex', 'default', 'future-tier', 'FAST', ''] {
		managed := api.NewThreadModelDefaults{ service_tier: owned(value.clone()) }
		mut actual := codex_core.Config{}
		cli_kv_overrides := []codex_core.PermissionCliOverride{}
		harness_overrides := codex_core.ConfigOverrides{}
		borrowed := BorrowedNewThreadModelDefaults{ value: &managed }
		apply_managed_new_thread_defaults(mut actual, borrowed, &cli_kv_overrides, &harness_overrides)
		apply_managed_new_thread_defaults(mut actual, borrowed, &cli_kv_overrides, &harness_overrides)
		expected := if value == 'fast' { 'priority' } else { value.clone() }
		assert actual.service_tier or { panic('tier') } == expected
		assert managed.service_tier or { panic('managed tier') } == value
	}
}
