module config_toml

import codex_protocol.config_types
import toml

// STUB: config/src/config_toml.rs::ProjectConfig's observed user-config trust
// field. Full ConfigToml deserialization and active-project lookup await its port.
pub struct ProjectConfig {
pub:
	trust_level ?config_types.TrustLevel
}

// STUB: ProjectConfig's serde Deserialize boundary accepts a table or a
// one-field sequence. A table's missing trust_level defaults to None, and unknown
// fields are ignored (the Rust annotation denies them only in the JSON schema).
pub fn ProjectConfig.from_toml(value toml.Any) !ProjectConfig {
	if value is []toml.Any {
		if value.len == 0 { return error('project sequence is missing its trust_level field') }
		level := config_update_trust_level(value[0])!
		if value.len != 1 { return error('project sequence must contain exactly one field') }
		return ProjectConfig{ trust_level: level }
	} else if value is map[string]toml.Any {
		level := value['trust_level'] or { return ProjectConfig{} }
		return ProjectConfig{ trust_level: config_update_trust_level(level)! }
	}
	return error('project must be a table or a one-field sequence')
}

// STUB: TrustLevel's serde unit-enum boundary accepts a lowercase string or
// exactly one variant key whose unit payload is an empty table or empty array.
// TOML's deserialize_option always visits Some for a present value: no explicit
// Null or empty sequence represents an absent trust decision.
fn config_update_trust_level(value toml.Any) !config_types.TrustLevel {
	if value is string {
		return match value {
			'trusted' { config_types.TrustLevel.trusted }
			'untrusted' { config_types.TrustLevel.untrusted }
			else { return error('invalid project trust_level: ${value}') }
		}
	} else if value is map[string]toml.Any {
		if value.len != 1 {
			return error('project trust_level enum table must contain exactly one variant')
		}
		for variant, payload in value {
			level := match variant {
				'trusted' { config_types.TrustLevel.trusted }
				'untrusted' { config_types.TrustLevel.untrusted }
				else { return error('invalid project trust_level: ${variant}') }
			}
			is_unit := match payload {
				map[string]toml.Any { payload.len == 0 }
				[]toml.Any { payload.len == 0 }
				else { false }
			}
			if !is_unit {
				return error('project trust_level enum variant must have a unit payload')
			}
			return level
		}
	}
	return error('project trust_level must be a string or an externally tagged enum table')
}

// STUB: ProjectConfig::is_trusted observes its optional Copy-equivalent enum.
pub fn (project &ProjectConfig) is_trusted() bool {
	return project.trust_level == ?config_types.TrustLevel(.trusted)
}

// STUB: ProjectConfig::is_untrusted observes its optional Copy-equivalent enum.
pub fn (project &ProjectConfig) is_untrusted() bool {
	return project.trust_level == ?config_types.TrustLevel(.untrusted)
}
