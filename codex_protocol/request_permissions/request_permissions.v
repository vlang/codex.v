module request_permissions

// STUB: Permission request event.
pub struct RequestPermissionsEvent {
pub:
	id string
}

// STUB: Permission response payload.
pub struct RequestPermissionsResponse {
pub:
	granted bool
}

// STUB: Permission request arguments.
pub struct RequestPermissionsArgs {
pub:
	reason string
}
