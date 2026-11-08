module app_event

import codex_tui.permission_discovery.types
import uuid

// STUB: crate::app_event::AppEvent::PermissionProfilesLoaded typed payload.
pub struct PermissionProfilesLoaded {
pub:
	request_id uuid.Uuid
	result     types.PermissionDiscoveryResult
}

// STUB: the permission-discovery AppEvent constructor moves its owned result.
pub fn permission_profiles_loaded(request_id uuid.Uuid, result types.PermissionDiscoveryResult) AppEvent {
	return AppEvent{ kind: .permission_profiles_loaded, permission_profiles: PermissionProfilesLoaded{ request_id: request_id, result: result } }
}
