module types

// STUB: config/src/types.rs::Notice includes every notice field, including nested migration maps.
pub struct Notice {
pub mut:
	hide_full_access_warning                ?bool
	hide_world_writable_warning             ?bool
	fast_default_opt_out                    ?bool
	hide_rate_limit_model_nudge             ?bool
	hide_gpt5_1_migration_prompt            ?bool
	hide_gpt_5_1_codex_max_migration_prompt ?bool @[json: 'hide_gpt-5.1-codex-max_migration_prompt']
	model_migrations                        map[string]string
	external_config_migration_prompts       ExternalConfigMigrationPrompts
}
