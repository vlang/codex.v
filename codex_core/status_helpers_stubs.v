module codex_core

import os
import codex_config

// STUB: core/src/config/mod.rs::ConfigBuilder observed test setup fields.
// Full layered configuration, cloud loading, and validation are untranslated.
pub struct ConfigBuilder {
	home                   ?string
	cwd                    ?string
	permission_overrides   []PermissionCliOverride
	loader_overrides_value codex_config.LoaderOverrides
}

// STUB: ConfigBuilder::default leaves optional test overrides unset.
pub fn ConfigBuilder.default() ConfigBuilder {
	return ConfigBuilder{}
}

// STUB: ConfigBuilder::codex_home consumes the owned PathBuf and builder.
pub fn (builder ConfigBuilder) codex_home(home string) ConfigBuilder {
	return ConfigBuilder{ home: home, cwd: builder.cwd, permission_overrides: builder.permission_overrides, loader_overrides_value: builder.loader_overrides_value }
}

// STUB: ConfigBuilder::fallback_cwd consumes the optional owned PathBuf and builder.
pub fn (builder ConfigBuilder) fallback_cwd(cwd ?string) ConfigBuilder {
	return ConfigBuilder{ home: builder.home, cwd: cwd, permission_overrides: builder.permission_overrides, loader_overrides_value: builder.loader_overrides_value }
}

// STUB: ConfigBuilder::build provides the faithful in-memory boundary needed
// by status pure-path tests. Rust's async runtime and disk config loader are absent.
pub fn (builder ConfigBuilder) build() !Config {
	home := builder.home or { return error('untranslated default codex home discovery') }
	// Rust's absent fallback is AbsolutePathBuf::current_dir(), an owned path.
	cwd := builder.cwd or { os.getwd() }
	if !os.is_abs_path(home.clone()) || !os.is_abs_path(cwd.clone()) {
		return error('status config builder requires absolute override paths')
	}
	mut config := Config{ codex_home: home, cwd: cwd, model_provider_id: 'openai' }
	apply_local_settings_builder_config(mut config, &builder.loader_overrides_value)!
	apply_permission_builder_overrides(mut config, builder.permission_overrides)!
	return config
}
