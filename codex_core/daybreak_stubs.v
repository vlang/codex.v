module codex_core

import codex_login

// STUB: core/config/auth_keyring.rs::Config::auth_config assembles owned local
// credential-loading settings. Untranslated policy/keyring fields are retained
// behind the resolved AuthConfig seam rather than made into successful defaults.
pub fn (config &Config) auth_config() codex_login.AuthConfig {
	return config.resolved_auth_config.with_paths(config.codex_home.clone(), config.chatgpt_base_url.clone())
}
