module codex_core

import codex_config.config_toml
import toml

// STUB: core/src/config/mod.rs::ConfigBuilder::harness_overrides keeps the
// source test's cwd setting on its consumed builder. Other fields are unused by
// config_update; complete harness override loading awaits ConfigBuilder's port.
pub fn (builder ConfigBuilder) harness_overrides(overrides ConfigOverrides) ConfigBuilder {
	return ConfigBuilder{ home: builder.home, cwd: overrides.cwd, permission_overrides: builder.permission_overrides, loader_overrides_value: builder.loader_overrides_value }
}

// STUB: ConfigToml's projects map deserialization validates each typed project.
// The existing builder retains the original TOML in its user config layer;
// native active-project selection and project-layer loading remain untranslated.
fn validate_config_update_projects(value toml.Any) ! {
	if value !is map[string]toml.Any {
		return error('projects must be a table')
	}
	for _, project in value {
		_ := config_toml.ProjectConfig.from_toml(project)!
	}
}
