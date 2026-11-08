module startup_preflight

import codex_login
import codex_protocol.shell_environment
import codex_utils_absolute_path
import os
import rand
import std_ffi
import std_io
import std_path
import toml

// TempDir's scoped cleanup is explicit in V's normal GC builds.
fn temporary_directory() string {
	path := os.join_path(os.temp_dir(), 'codex-startup-preflight-${rand.uuid_v4()}')
	os.mkdir(path) or { panic(err.msg()) }
	return path
}

fn join_path(parent &string, child &string) string {
	path := std_path.Path.new(parent)
	return path.join(child)
}

fn absolute_path(path &string) codex_utils_absolute_path.AbsolutePathBuf {
	return codex_utils_absolute_path.from_absolute_path(path) or { panic(err.msg()) }
}

fn delay(home &string, system_path SystemConfigPathResult, managed fn () !bool, environment fn (&string) ?std_ffi.OsString) bool {
	path := std_path.Path.new(home)
	return should_delay_startup_composer_for_first_login(&path, system_path, managed, environment)
}

fn no_managed_configuration() !bool {
	return false
}

fn no_environment_variable(_ &string) ?std_ffi.OsString {
	return none
}

fn owned_os_string(value &string) std_ffi.OsString {
	$if ownership ? {
		return std_ffi.OsString.from(value.to_owned())
	} $else {
		return std_ffi.OsString.from(value.clone())
	}
}

fn test_startup_delays_composer_for_homes_without_authentication_state() {
	temporary_directory := temporary_directory()
	defer { os.rmdir_all(temporary_directory) or { panic(err.msg()) } }
	codex_home := join_path(&temporary_directory, &codex_home_name)
	system_path := join_path(&temporary_directory, &system_config_name)
	system_config_path := absolute_path(&system_path)
	assert delay(&codex_home, system_config_path.clone(), no_managed_configuration, no_environment_variable)
	assert delay(&codex_home, system_config_path.clone(), no_managed_configuration, fn (name &string) ?std_ffi.OsString {
		if *name == codex_login.codex_access_token_env_var {
			return owned_os_string(&blank_credential)
		}
		return none
	})
	tmp := join_path(&codex_home, &tmp_name)
	arg0 := join_path(&tmp, &arg0_name)
	os.mkdir_all(arg0) or { panic(err.msg()) }
	assert delay(&codex_home, system_config_path.clone(), no_managed_configuration, no_environment_variable)
	helper_directory := join_path(&arg0, &arg0_session_name)
	os.mkdir(helper_directory) or { panic(err.msg()) }
	os.write_file(join_path(&helper_directory, &apply_patch_name), '') or { panic(err.msg()) }
	assert delay(&codex_home, system_config_path.clone(), no_managed_configuration, no_environment_variable)
	assert delay(&codex_home, system_config_path.clone(), no_managed_configuration, fn (name &string) ?std_ffi.OsString {
		if *name == 'CODEX_HOME' {
			return owned_os_string(&custom_home_value)
		}
		return none
	})
	assert !delay(&codex_home, system_config_path.clone(), no_managed_configuration, fn (name &string) ?std_ffi.OsString {
		if *name == codex_login.codex_access_token_env_var {
			return owned_os_string(&access_token_value)
		}
		return none
	})
	for disabled_credential in [codex_login.openai_api_key_env_var, codex_login.codex_api_key_env_var] {
		assert delay(&codex_home, system_config_path.clone(), no_managed_configuration, fn [disabled_credential] (name &string) ?std_ffi.OsString {
			if *name == disabled_credential {
				return owned_os_string(&disabled_key_value)
			}
			return none
		})
	}
	for existing_state in ['history.jsonl', 'log', 'sessions'] {
		state_path := join_path(&codex_home, &existing_state)
		if existing_state == 'history.jsonl' {
			os.write_file(state_path, '') or { panic(err.msg()) }
		} else {
			os.mkdir(state_path) or { panic(err.msg()) }
		}
		assert delay(&codex_home, system_config_path.clone(), no_managed_configuration, no_environment_variable)
	}
	assert delay(&codex_home, system_config_path.clone(), no_managed_configuration, fn (name &string) ?std_ffi.OsString {
		if *name == 'CODEX_HOME' {
			return owned_os_string(&custom_home_value)
		}
		return none
	})
	assert !delay(&codex_home, system_config_path.clone(), fn () !bool {
		panic('process credentials should not probe managed configuration')
	}, fn (name &string) ?std_ffi.OsString {
		if *name == 'CODEX_HOME' {
			return owned_os_string(&custom_home_value)
		}
		if *name == codex_login.codex_access_token_env_var {
			return owned_os_string(&access_token_value)
		}
		return none
	})
	for existing_state in ['auth.json', 'config.toml', 'environments.toml'] {
		state_path := join_path(&codex_home, &existing_state)
		os.write_file(state_path, '') or { panic(err.msg()) }
		assert !delay(&codex_home, system_config_path.clone(), fn () !bool {
			panic('configured homes should not probe managed configuration')
		}, no_environment_variable)
		os.rm(state_path) or { panic(err.msg()) }
	}
	daemon_directory := join_path(&codex_home, &daemon_directory_name)
	os.mkdir(daemon_directory) or { panic(err.msg()) }
	assert delay(&codex_home, system_config_path.clone(), no_managed_configuration, no_environment_variable)
	socket_path := join_path(&daemon_directory, &daemon_socket_name)
	os.write_file(socket_path, '') or { panic(err.msg()) }
	assert !delay(&codex_home, system_config_path.clone(), fn () !bool {
		panic('daemon-owned homes should not probe managed configuration')
	}, no_environment_variable)
	os.rm(socket_path) or { panic(err.msg()) }
	os.rmdir(daemon_directory) or { panic(err.msg()) }
	additional_temporary_state := join_path(&tmp, &additional_tmp_name)
	os.write_file(additional_temporary_state, '') or { panic(err.msg()) }
	assert delay(&codex_home, system_config_path.clone(), no_managed_configuration, no_environment_variable)
	invalid_home := join_path(&temporary_directory, &invalid_home_name)
	os.write_file(invalid_home, 'not a directory') or { panic(err.msg()) }
	assert !delay(&invalid_home, system_config_path, no_managed_configuration, no_environment_variable)
}

fn test_startup_keeps_composer_when_home_state_cannot_be_confirmed() {
	temporary_directory := temporary_directory()
	defer { os.rmdir_all(temporary_directory) or { panic(err.msg()) } }
	codex_home := join_path(&temporary_directory, &codex_home_name)
	system_path := join_path(&temporary_directory, &system_config_name)
	system_config_path := absolute_path(&system_path)
	os.mkdir(codex_home) or { panic(err.msg()) }
	assert delay(&codex_home, system_config_path, no_managed_configuration, no_environment_variable)
	$if !windows {
		unix_system_config_path := absolute_path(&system_path)
		daemon_directory := join_path(&codex_home, &daemon_directory_name)
		os.write_file(daemon_directory, 'not a directory') or { panic(err.msg()) }
		assert !delay(&codex_home, unix_system_config_path.clone(), fn () !bool {
			panic('ambiguous daemon state should not probe managed configuration')
		}, no_environment_variable)
		os.rm(daemon_directory) or { panic(err.msg()) }
		blocking_parent := join_path(&temporary_directory, &blocking_home_parent_name)
		os.write_file(blocking_parent, 'not a directory') or { panic(err.msg()) }
		blocked_home := join_path(&blocking_parent, &codex_home_name)
		assert !delay(&blocked_home, unix_system_config_path, fn () !bool {
			panic('ambiguous home state should not probe managed configuration')
		}, no_environment_variable)
	}
}

fn test_startup_keeps_composer_for_workload_identity_markers() {
	temporary_directory := temporary_directory()
	defer { os.rmdir_all(temporary_directory) or { panic(err.msg()) } }
	codex_home := join_path(&temporary_directory, &codex_home_name)
	system_path := join_path(&temporary_directory, &system_config_name)
	system_config_path := absolute_path(&system_path)
	for marker in [shell_environment.openai_federation_rule_id_env_var,
		shell_environment.openai_identity_token_file_env_var] {
		for value in ['', 'configured'] {
			assert !delay(&codex_home, system_config_path.clone(), fn () !bool {
				panic('workload identity should not probe managed configuration')
			}, fn [marker, value] (name &string) ?std_ffi.OsString {
				if *name == marker {
					return owned_os_string(&value)
				}
				return none
			})
		}
	}
	$if !windows {
		assert !delay(&codex_home, system_config_path, fn () !bool {
			panic('workload identity should not probe managed configuration')
		}, fn (name &string) ?std_ffi.OsString {
			if *name == shell_environment.openai_identity_token_file_env_var {
				return std_ffi.OsString.from_vec([u8(`/`), 0xff])
			}
			return none
		})
	}
}

fn test_startup_only_accepts_the_synthetic_search_override() {
	// V has no std::slice::from_ref; keeping the original pair in one owned
	// array permits the same borrow before moving it into the two-entry fixture.
	mut search := [ConfigOverride{ key: 'web_search'.clone(), value: toml.Any('live'.clone()) }]
	assert !has_only_search_config_override(&[]ConfigOverride{})
	assert has_only_search_config_override(&search)
	assert !has_only_search_config_override(&[ConfigOverride{ key: 'web_search'.clone(), value: toml.Any('cached'.clone()) }])
	assert !has_only_search_config_override(&[ConfigOverride{ key: 'model_provider'.clone(), value: toml.Any('live'.clone()) }])
	search << ConfigOverride{ key: 'model'.clone(), value: toml.Any('custom'.clone()) }
	assert !has_only_search_config_override(&search)
}

fn test_startup_keeps_composer_when_system_configuration_is_possible() {
	temporary_directory := temporary_directory()
	defer { os.rmdir_all(temporary_directory) or { panic(err.msg()) } }
	codex_home := join_path(&temporary_directory, &codex_home_name)
	system_path := join_path(&temporary_directory, &system_config_name)
	system_config_path := absolute_path(&system_path)
	assert !delay(&codex_home, std_io.Error.new(.other, 'system configuration path is unavailable'), no_managed_configuration, no_environment_variable)
	$if !windows {
		blocking_parent := join_path(&temporary_directory, &blocking_parent_name)
		os.write_file(blocking_parent, 'not a directory') or { panic(err.msg()) }
		blocked_system_path := join_path(&blocking_parent, &system_config_name)
		assert !delay(&codex_home, absolute_path(&blocked_system_path), no_managed_configuration, no_environment_variable)
	}
	os.write_file(system_path, "model_provider = 'local'") or { panic(err.msg()) }
	assert !delay(&codex_home, system_config_path, no_managed_configuration, no_environment_variable)
}

fn test_startup_keeps_composer_when_managed_configuration_is_possible() {
	temporary_directory := temporary_directory()
	defer { os.rmdir_all(temporary_directory) or { panic(err.msg()) } }
	codex_home := join_path(&temporary_directory, &codex_home_name)
	system_path := join_path(&temporary_directory, &system_config_name)
	system_config_path := absolute_path(&system_path)
	assert !delay(&codex_home, system_config_path.clone(), fn () !bool {
		return true
	}, no_environment_variable)
	assert !delay(&codex_home, system_config_path, fn () !bool {
		return std_io.Error.new(.other, 'managed configuration is inaccessible')
	}, no_environment_variable)
}

fn test_repeated_borrowed_owned_overrides_and_native_path_keep_owners() {
	mut key := 'web_search'
	mut value := 'live'
	$if ownership ? {
		key = key.to_owned()
		value = value.to_owned()
	}
	overrides := [ConfigOverride{ key: key, value: toml.Any(value) }]
	assert has_only_search_config_override(&overrides)
	assert has_only_search_config_override(&overrides)
	assert overrides[0].key == 'web_search'
	assert overrides[0].value is string
	assert !has_only_search_config_override(&[ConfigOverride{ key: 'web_search'.clone(), value: toml.Any(true) }])
	temporary_directory := temporary_directory()
	defer { os.rmdir_all(temporary_directory) or { panic(err.msg()) } }
	home := join_path(&temporary_directory, &codex_home_name)
	system_path := join_path(&temporary_directory, &system_config_name)
	system := absolute_path(&system_path)
	assert delay(&home, system.clone(), no_managed_configuration, no_environment_variable)
	assert delay(&home, system.clone(), no_managed_configuration, no_environment_variable)
	assert home.ends_with(codex_home_name)
	assert system.path == system_path
}

fn test_credentials_reject_invalid_utf8_and_trim_unicode_only() {
	temporary_directory := temporary_directory()
	defer { os.rmdir_all(temporary_directory) or { panic(err.msg()) } }
	home := join_path(&temporary_directory, &codex_home_name)
	system_path := join_path(&temporary_directory, &system_config_name)
	system := absolute_path(&system_path)
	assert delay(&home, system.clone(), no_managed_configuration, fn (name &string) ?std_ffi.OsString {
		if *name == codex_login.codex_access_token_env_var {
			return std_ffi.OsString.from_vec([u8(0xff)])
		}
		return none
	})
	assert delay(&home, system.clone(), no_managed_configuration, fn (name &string) ?std_ffi.OsString {
		if *name == codex_login.codex_access_token_env_var {
			return owned_os_string(&unicode_blank_credential)
		}
		return none
	})
	assert !delay(&home, system, fn () !bool {
		panic('nonblank credentials must short circuit')
	}, fn (name &string) ?std_ffi.OsString {
		if *name == codex_login.codex_access_token_env_var {
			return owned_os_string(&zero_width_space_credential)
		}
		return none
	})
	owner := std_ffi.OsString.from_vec([u8(`/`), 0xff])
	assert !owner.to_str().present
	assert !owner.to_str().present
	assert owner.bytes.bytes() == [u8(`/`), 0xff]
}

fn test_dangling_symlinks_are_missing_and_invalid_native_path_is_ambiguous() {
	$if !windows {
		temporary_directory := temporary_directory()
		defer { os.rmdir_all(temporary_directory) or { panic(err.msg()) } }
		home := join_path(&temporary_directory, &codex_home_name)
		system_path := join_path(&temporary_directory, &system_config_name)
		missing_target := join_path(&temporary_directory, &missing_target_name)
		os.symlink(missing_target, system_path) or { panic(err.msg()) }
		os.symlink(missing_target, home) or { panic(err.msg()) }
		system := absolute_path(&system_path)
		assert delay(&home, system, no_managed_configuration, no_environment_variable)
		invalid_home := home + '\x00extra'
		assert !delay(&invalid_home, absolute_path(&system_path), fn () !bool {
			panic('ambiguous native paths must short circuit')
		}, no_environment_variable)
	}
}

const codex_home_name = 'codex-home'
const system_config_name = 'system.toml'
const blank_credential = '  '
const tmp_name = 'tmp'
const arg0_name = 'arg0'
const arg0_session_name = 'codex-arg0-session'
const apply_patch_name = 'apply_patch'
const custom_home_value = '/custom/home'
const access_token_value = 'access-token'
const disabled_key_value = 'disabled-key'
const daemon_directory_name = 'app-server-control'
const daemon_socket_name = 'app-server-control.sock'
const additional_tmp_name = 'other'
const invalid_home_name = 'invalid-home'
const blocking_home_parent_name = 'blocking-home-parent'
const blocking_parent_name = 'blocking-parent'
const unicode_blank_credential = '\u0085\u2003\u3000'
const zero_width_space_credential = '\u200b'
const missing_target_name = 'nonexistent'
