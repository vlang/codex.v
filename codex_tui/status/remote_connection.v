module status

import codex_tui
import codex_app_server_client
import url

pub struct RemoteConnectionStatus {
pub:
	address string
	version string
}

// Rust's derived Clone duplicates the two owned display strings. V supplies
// structural equality and debug formatting for the corresponding struct.
pub fn (value &RemoteConnectionStatus) clone() RemoteConnectionStatus {
	return RemoteConnectionStatus{
		address: value.address.clone()
		version: value.version.clone()
	}
}

// Option<&str> is represented by a Copy-equivalent borrowed wrapper because
// V's ?&string cannot reliably pass through ownership-mode C generation.
pub struct BorrowedServerVersion {
pub:
	has_value bool
	value     &string = unsafe { nil }
}

pub fn remote_connection_status_value(app_server_target &codex_tui.AppServerTarget, server_version BorrowedServerVersion) ?RemoteConnectionStatus {
	// V's C generator cannot reliably return a reference from this match.
	// Passing each endpoint directly to the shared formatter preserves Rust's borrow.
	address := match app_server_target {
		codex_tui.AppServerEmbedded { return none }
		codex_tui.AppServerLocalDaemon {
			remote_connection_address(&app_server_target.endpoint)
		}
		codex_tui.AppServerRemote {
			remote_connection_address(&app_server_target.endpoint)
		}
	}
	version := if server_version.has_value {
		'v${*server_version.value}'
	} else {
		'unknown'.clone()
	}
	return RemoteConnectionStatus{ address: address, version: version }
}

// The source address-formatting match is extracted only to keep its shared
// endpoint reference out of V's faulty match-reference temporary lowering.
fn remote_connection_address(endpoint &codex_app_server_client.RemoteAppServerEndpoint) string {
	return match endpoint {
		codex_app_server_client.RemoteAppServerWebSocket {
			if parsed := sanitized_websocket_url(&endpoint.websocket_url) {
				parsed.to_string()
			} else {
				'<invalid websocket URL>'.clone()
			}
		}
		codex_app_server_client.RemoteAppServerUnixSocket {
			'unix://${endpoint.socket_path.display()}'
		}
	}
}

pub fn sanitized_websocket_url(raw &string) ?url.Url {
	mut parsed := url.Url.parse(raw) or { return none }
	empty := ''
	parsed.set_username(&empty) or {}
	parsed.set_password(url.BorrowedString{}) or {}
	parsed.set_query(url.BorrowedString{})
	parsed.set_fragment(url.BorrowedString{})
	return parsed
}
