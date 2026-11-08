module codex_config

import os
import codex_protocol.config_types
import codex_utils_absolute_path

// STUB: state.rs::LoaderOverrides's fields observed by LocalSettings's test loader.
// Managed/cloud/project configuration remains outside this local test boundary.
pub struct LoaderOverrides {
pub mut:
	packaged_defaults_path                    ?codex_utils_absolute_path.AbsolutePathBuf
	user_config_path                          ?codex_utils_absolute_path.AbsolutePathBuf
	user_config_profile                       ?config_types.ProfileV2Name
	managed_config_path                       ?string
	system_config_path                        ?string
	system_requirements_path                  ?string
	ignore_managed_requirements               bool
	ignore_login_requirements                 bool
	ignore_user_config                        bool
	ignore_project_config                     bool
	ignore_user_and_project_exec_policy_rules bool
	managed_preferences_base64                ?string
	macos_managed_config_requirements_base64  ?string
}

// STUB: LoaderOverrides::without_managed_config_for_tests selects the source fixture destinations.
pub fn LoaderOverrides.without_managed_config_for_tests() LoaderOverrides {
	base := os.join_path(os.temp_dir(), 'codex-config-tests')
	return LoaderOverrides{
		managed_config_path:                      os.join_path(base, 'managed_config.toml')
		system_config_path:                       os.join_path(base, 'config.toml')
		system_requirements_path:                 os.join_path(base, 'requirements.toml')
		managed_preferences_base64:               ''.clone()
		macos_managed_config_requirements_base64: ''.clone()
	}
}

// STUB: LoaderOverrides's derived Clone retains independent selected profile and file bytes.
pub fn (overrides &LoaderOverrides) clone() LoaderOverrides {
	return LoaderOverrides{
		packaged_defaults_path:                    if path := overrides.packaged_defaults_path {
			path.clone()
		} else {
			none
		}
		user_config_path:                          if path := overrides.user_config_path {
			path.clone()
		} else {
			none
		}
		user_config_profile:                       if profile := overrides.user_config_profile {
			profile.clone()
		} else {
			none
		}
		managed_config_path:                       if path := overrides.managed_config_path {
			path.clone()
		} else {
			none
		}
		system_config_path:                        if path := overrides.system_config_path {
			path.clone()
		} else {
			none
		}
		system_requirements_path:                  if path := overrides.system_requirements_path {
			path.clone()
		} else {
			none
		}
		ignore_managed_requirements:               overrides.ignore_managed_requirements
		ignore_login_requirements:                 overrides.ignore_login_requirements
		ignore_user_config:                        overrides.ignore_user_config
		ignore_project_config:                     overrides.ignore_project_config
		ignore_user_and_project_exec_policy_rules: overrides.ignore_user_and_project_exec_policy_rules
		managed_preferences_base64:                if value := overrides.managed_preferences_base64 {
			value.clone()
		} else {
			none
		}
		macos_managed_config_requirements_base64:  if value := overrides.macos_managed_config_requirements_base64 {
			value.clone()
		} else {
			none
		}
	}
}

// STUB: Option<&AbsolutePathBuf> returned by ConfigLayerStack::get_user_config_file.
// An optional allocation-free pointer wrapper avoids V's unsupported &?T/?&T resource shapes.
pub struct UserConfigFileRef {
pub:
	value &codex_utils_absolute_path.AbsolutePathBuf
}

// STUB: state.rs::get_user_config_file returns the highest-precedence user layer's file.
// Disabled layers remain writable targets, matching get_active_user_layer's source search.
pub fn (stack &ConfigLayerStack) get_user_config_file() ?UserConfigFileRef {
	for index := stack.layers.len - 1; index >= 0; index-- {
		if stack.layers[index].name == .user {
			return UserConfigFileRef{ value: &stack.layers[index].user_file }
		}
	}
	return none
}
