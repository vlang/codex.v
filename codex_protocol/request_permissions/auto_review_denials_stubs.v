module request_permissions

import codex_protocol.models

// STUB: protocol/src/request_permissions.rs::RequestPermissionProfile's typed network
// and filesystem overlays. serde's deny_unknown_fields validation awaits its module port.
pub struct RequestPermissionProfile {
pub:
	network     ?models.NetworkPermissions
	file_system ?models.FileSystemPermissions
}
