module models

import codex_protocol.permissions

// STUB: protocol/src/models.rs::NetworkPermissions, including its tri-state enabled setting.
pub struct NetworkPermissions {
pub:
	enabled ?bool
}

// STUB: protocol/src/models.rs::FileSystemPermissions. Existing typed sandbox entries
// retain their owner; validation of nonzero glob_scan_max_depth awaits the models port.
pub struct FileSystemPermissions {
pub:
	entries             []permissions.FileSystemSandboxEntry
	glob_scan_max_depth ?usize
}
