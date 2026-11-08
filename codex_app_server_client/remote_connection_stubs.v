module codex_app_server_client

import codex_utils_absolute_path

// STUB: app-server-client/src/remote.rs owns RemoteAppServerEndpoint. These
// payloads preserve its two transports and owned URL, auth token, and socket path.
pub type RemoteAppServerEndpoint = RemoteAppServerUnixSocket | RemoteAppServerWebSocket

// STUB: RemoteAppServerEndpoint::WebSocket from app-server-client/src/remote.rs.
pub struct RemoteAppServerWebSocket {
pub:
	websocket_url string
	auth_token    ?string
}

// STUB: RemoteAppServerEndpoint::UnixSocket from app-server-client/src/remote.rs.
pub struct RemoteAppServerUnixSocket {
pub:
	socket_path codex_utils_absolute_path.AbsolutePathBuf
}
