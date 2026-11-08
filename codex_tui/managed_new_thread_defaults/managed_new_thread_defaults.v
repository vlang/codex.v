module managed_new_thread_defaults

import codex_app_server_protocol as api
import codex_core
import codex_protocol.config_types

// The optional wrapper contains only a shared reference, preserving Rust
// Option<&NewThreadModelDefaults> without V's unreliable ?&T C lowering.
pub struct BorrowedNewThreadModelDefaults {
pub:
	value &api.NewThreadModelDefaults
}

// V has no pub(crate) visibility, so this cross-module function is public.
pub fn apply_managed_new_thread_defaults(mut config codex_core.Config,
	defaults ?BorrowedNewThreadModelDefaults, cli_kv_overrides &[]codex_core.PermissionCliOverride,
	harness_overrides &codex_core.ConfigOverrides) {
	borrowed := defaults or { return }
	managed := borrowed.value
	// Managed values are defaults rather than enforcement. Preserve explicit launch choices from
	// dedicated flags such as `-m` (`harness_overrides`) and generic `-c key=value` settings
	// (`cli_kv_overrides`), then fill only the fields that were not selected for this invocation.
	// Model and reasoning effort are a compatibility-sensitive pair, so an explicit override of
	// either opts out of both managed values. For example, `codex -m gpt-5.4` keeps that model and
	// its existing/default effort, while `-c model_reasoning_effort=low` does not switch to the
	// managed model. Service tier remains independent and is resolved against the selected model
	// before the thread starts.
	model_key := 'model'
	effort_key := 'model_reasoning_effort'
	tier_key := 'service_tier'
	has_explicit_model_settings := harness_overrides.model != none
		|| has_cli_override(cli_kv_overrides, &model_key)
		|| has_cli_override(cli_kv_overrides, &effort_key)

	if !has_explicit_model_settings {
		if model := managed.model {
			config.model = model.clone()
		}
	}
	if !has_explicit_model_settings {
		if reasoning_effort := managed.model_reasoning_effort {
			// The canonical translated effort is a Copy-equivalent V enum.
			config.model_reasoning_effort = reasoning_effort
		}
	}
	if !harness_overrides.service_tier.has_value
		&& !has_cli_override(cli_kv_overrides, &tier_key) {
		if service_tier := managed.service_tier {
			if tier := config_types.ServiceTier.from_request_value(&service_tier) {
				config.service_tier = tier.request_value().clone()
			} else {
				config.service_tier = service_tier.clone()
			}
		}
	}
}

// Rust's local has_cli_override closure is lifted to a helper with the same borrows.
fn has_cli_override(cli_kv_overrides &[]codex_core.PermissionCliOverride, key &string) bool {
	for index in 0 .. cli_kv_overrides.len {
		if (*cli_kv_overrides)[index].key == *key {
			return true
		}
	}
	return false
}
