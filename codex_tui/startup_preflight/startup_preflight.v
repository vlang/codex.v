// Conservative authentication checks that run before the provisional composer appears.
//
// Existing configuration, daemon, or authentication state keeps the composer visible.
module startup_preflight

import codex_app_server_client
import codex_login
import codex_protocol.shell_environment
import codex_utils_absolute_path
import std_ffi
import std_fs
import std_io
import std_path
import toml

// V has no tuples; this owned pair preserves Rust (String, toml::Value).
// V's existing TOML Any sum retains the original value's type and payload.
pub struct ConfigOverride {
pub:
	key   string
	value toml.Any
}

// V cannot take !T as a parameter. This owned tagged result preserves both
// io::Result branches without changing when the path is consumed.
pub type SystemConfigPathResult = codex_utils_absolute_path.AbsolutePathBuf | std_io.Error

// Recognize the single configuration override synthesized by the legacy `--search` flag.
pub fn has_only_search_config_override(cli_kv_overrides &[]ConfigOverride) bool {
	if cli_kv_overrides.len != 1 {
		return false
	}
	pair := &(*cli_kv_overrides)[0]
	if pair.value is string {
		return pair.key == 'web_search' && pair.value == 'live'
	}
	return false
}

// Rust str::trim uses Unicode White_Space. V's temporary owned trim result is
// the unavoidable allocation adaptation for the source's borrowed string slice.
const unicode_whitespace = '\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000'

// Hide the composer when the default file-backed account cannot already be authenticated.
pub fn should_delay_startup_composer_for_first_login(codex_home &std_path.Path, system_config_path_result SystemConfigPathResult, managed_configuration fn () !bool, environment_variable fn (&string) ?std_ffi.OsString) bool {
	if credential := environment_variable(&codex_login.codex_access_token_env_var) {
		value := credential.to_str()
		if value.present && value.value.trim(unicode_whitespace).len > 0 {
			return false
		}
	}
	if _ := environment_variable(&shell_environment.openai_federation_rule_id_env_var) {
		return false
	}
	if _ := environment_variable(&shell_environment.openai_identity_token_file_env_var) {
		return false
	}
	if system_config_path_result is std_io.Error {
		return false
	}
	system_config_path := system_config_path_result as codex_utils_absolute_path.AbsolutePathBuf
	if system_config_path.as_path().try_exists() or { return false } {
		return false
	}
	if metadata := std_fs.metadata(codex_home) {
		if !metadata.is_dir() {
			return false
		}
		for state_file in ['auth.json', 'config.toml', 'environments.toml'] {
			state := codex_home.join(&state_file)
			state_path := std_path.Path.new(&state)
			if state_path.try_exists() or { return false } {
				return false
			}
		}
		daemon_socket := codex_app_server_client.app_server_control_socket_path(codex_home) or { return false }
		if daemon_socket.as_path().try_exists() or { return false } {
			return false
		}
	} else {
		if err is std_io.Error {
			if err.kind() != .not_found || (codex_home.try_exists() or { return false }) {
				return false
			}
		} else {
			return false
		}
	}
	return !(managed_configuration() or { return false })
}
