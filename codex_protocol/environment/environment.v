module environment

import codex_protocol.models

// STUB: Runtime environment configuration.
pub struct EnvironmentConfig {
pub:
	values map[string]string
}

// STUB: Runtime environment configuration state.
pub struct EnvironmentConfigState {
pub:
	values map[string]string
}

// STUB: Full-access evaluation belongs to the environment module.
pub fn has_full_access[T](no_approvals bool, thread_profile &models.PermissionProfile, environments &[]T) bool {
	_ = no_approvals
	_ = thread_profile
	_ = environments
	return false
}
