module codex_tui

import codex_app_server_client

// STUB: tui/src/lib.rs reexports the app-server-client endpoint; keep its
// declaration in its eventual owner instead of duplicating the transport type.
pub type RemoteAppServerEndpoint = codex_app_server_client.RemoteAppServerEndpoint

// STUB: tui/src/lib.rs owns AppServerTarget and its three distinct variants.
pub type AppServerTarget = AppServerEmbedded | AppServerLocalDaemon | AppServerRemote

// STUB: AppServerTarget::Embedded from tui/src/lib.rs.
pub struct AppServerEmbedded {}

// STUB: AppServerTarget::LocalDaemon from tui/src/lib.rs.
pub struct AppServerLocalDaemon {
pub:
	endpoint RemoteAppServerEndpoint
}

// STUB: AppServerTarget::Remote from tui/src/lib.rs.
pub struct AppServerRemote {
pub:
	endpoint RemoteAppServerEndpoint
}
