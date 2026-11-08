module status

import codex_app_server_client
import codex_tui
import codex_utils_absolute_path

fn remote_connection_owned(value &string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_remote_connection_status_value_formats_display_value() {
	version := '1.2.3'
	embedded := codex_tui.AppServerTarget(codex_tui.AppServerEmbedded{})
	assert remote_connection_status_value(&embedded, BorrowedServerVersion{ has_value: true, value: &version }) == none

	websocket_target := codex_tui.AppServerTarget(codex_tui.AppServerRemote{
		endpoint: codex_app_server_client.RemoteAppServerWebSocket{
			websocket_url: 'ws://user:secret@127.0.0.1:4500/?token=abc#frag'
			auth_token:    'abc'
		}
	})
	websocket_status := remote_connection_status_value(&websocket_target, BorrowedServerVersion{ has_value: true, value: &version }) or { panic('remote status absent') }
	assert websocket_status == RemoteConnectionStatus{
		address: 'ws://127.0.0.1:4500/'
		version: 'v1.2.3'
	}

	socket_path := codex_utils_absolute_path.AbsolutePathBuf.relative_to_current_dir('codex.sock') or { panic(err) }
	daemon_target := codex_tui.AppServerTarget(codex_tui.AppServerLocalDaemon{
		endpoint: codex_app_server_client.RemoteAppServerUnixSocket{ socket_path: socket_path.clone() }
	})
	daemon_status := remote_connection_status_value(&daemon_target, /* server_version */
		BorrowedServerVersion{}) or { panic('daemon status absent') }
	assert daemon_status == RemoteConnectionStatus{
		address: 'unix://${socket_path.display()}'
		version: 'unknown'
	}
}

fn test_remote_connection_status_preserves_borrowed_owners() {
	raw_literal := 'wss://name:password@EXAMPLE.com:443/rpc?auth=secret#private'
	version_literal := '2.3.4'
	token_literal := 'secret'
	raw := remote_connection_owned(&raw_literal)
	version := remote_connection_owned(&version_literal)
	token := remote_connection_owned(&token_literal)
	target := codex_tui.AppServerTarget(codex_tui.AppServerRemote{
		endpoint: codex_app_server_client.RemoteAppServerWebSocket{
			websocket_url: remote_connection_owned(&raw)
			auth_token:    remote_connection_owned(&token)
		}
	})
	for _ in 0 .. 2 {
		remote_status := remote_connection_status_value(&target, BorrowedServerVersion{ has_value: true, value: &version }) or { panic('remote status absent') }
		assert remote_status == RemoteConnectionStatus{
			address: 'wss://example.com/rpc'
			version: 'v2.3.4'
		}
	}
	assert raw == raw_literal
	assert version == version_literal
	assert token == token_literal
	match target {
		codex_tui.AppServerRemote {
			match target.endpoint {
				codex_app_server_client.RemoteAppServerWebSocket {
					assert target.endpoint.websocket_url == raw
					assert target.endpoint.auth_token or { panic('auth token moved') } == token
				}
				else {
					assert false
				}
			}
		}
		else {
			assert false
		}
	}
}

fn test_sanitized_websocket_url_preserves_path_and_nondefault_port() {
	raw_literal := 'wss://user:secret@example.com:9443/a%2Fb/c%20d?token=x#fragment'
	raw := remote_connection_owned(&raw_literal)
	for _ in 0 .. 2 {
		parsed := sanitized_websocket_url(&raw) or { panic('valid URL rejected') }
		assert parsed.to_string() == 'wss://example.com:9443/a%2Fb/c%20d'
	}
	assert raw == raw_literal
}

fn test_sanitized_websocket_url_normalizes_scheme_host_port_and_dot_segments() {
	raw := ' \tWS:\\user:password@EXAMPLE.com:00080/a/../b/%2e/c?x#y\r\n '
	parsed := sanitized_websocket_url(&raw) or { panic('valid URL rejected') }
	assert parsed.to_string() == 'ws://example.com/b/c'
	unicode_path := 'ws://localhost:4500/界 é?token=x#fragment'
	unescaped := sanitized_websocket_url(&unicode_path) or { panic('valid Unicode path rejected') }
	assert unescaped.to_string() == 'ws://localhost:4500/%E7%95%8C%20e%CC%81'
}

fn test_sanitized_websocket_url_keeps_ipv6_and_numeric_ipv4_hosts() {
	ipv6 := 'ws://name:password@[2001:0DB8:0:0:0:0:0:1]:4500/rpc?x#y'
	parsed_ipv6 := sanitized_websocket_url(&ipv6) or { panic('valid IPv6 URL rejected') }
	assert parsed_ipv6.to_string() == 'ws://[2001:db8::1]:4500/rpc'
	mapped := 'ws://[::ffff:192.0.2.1]:4500/'
	parsed_mapped := sanitized_websocket_url(&mapped) or { panic('valid IPv4-mapped URL rejected') }
	assert parsed_mapped.to_string() == 'ws://[::ffff:c000:201]:4500/'
	ipv4 := 'ws://0x7f.1:80'
	parsed_ipv4 := sanitized_websocket_url(&ipv4) or { panic('valid numeric IPv4 URL rejected') }
	assert parsed_ipv4.to_string() == 'ws://127.0.0.1/'
	nonnumeric := 'ws://0xz:4500/'
	parsed_nonnumeric := sanitized_websocket_url(&nonnumeric) or { panic('valid domain URL rejected') }
	assert parsed_nonnumeric.to_string() == 'ws://0xz:4500/'
	double_dot := 'ws://127.0.0.1..:4500/'
	parsed_double_dot := sanitized_websocket_url(&double_dot) or { panic('valid dotted domain URL rejected') }
	assert parsed_double_dot.to_string() == 'ws://127.0.0.1..:4500/'
}

fn test_sanitized_websocket_url_rejects_invalid_urls() {
	cases := ['relative/path', 'ws://', 'ws://host:65536/', 'ws://host:not-a-port/', 'ws://[not-ipv6]/',
		'ws://host name/', 'ws://256.1.1.1/']
	for index in 0 .. cases.len {
		assert sanitized_websocket_url(&cases[index]) == none
	}
	target := codex_tui.AppServerTarget(codex_tui.AppServerRemote{
		endpoint: codex_app_server_client.RemoteAppServerWebSocket{ websocket_url: 'not an absolute URL' }
	})
	remote_status := remote_connection_status_value(&target, BorrowedServerVersion{}) or { panic('remote status absent') }
	assert remote_status == RemoteConnectionStatus{
		address: '<invalid websocket URL>'
		version: 'unknown'
	}
}

fn test_sanitized_websocket_url_retains_nonwebsocket_absolute_url_behavior() {
	// The Rust helper calls Url::parse without restricting the scheme. Failed
	// credential setters on an opaque URL must not prevent query/fragment removal.
	opaque := 'mailto:user@example.com?subject=secret#fragment'
	parsed_opaque := sanitized_websocket_url(&opaque) or { panic('valid opaque URL rejected') }
	assert parsed_opaque.to_string() == 'mailto:user@example.com'
	file := 'file:///tmp/codex.sock?private#fragment'
	parsed_file := sanitized_websocket_url(&file) or { panic('valid file URL rejected') }
	assert parsed_file.to_string() == 'file:///tmp/codex.sock'
}

fn test_remote_connection_status_clone_preserves_owned_strings() {
	address_literal := 'ws://localhost:4500/rpc'
	version_literal := 'v1.2.3'
	connection_status := RemoteConnectionStatus{
		address: remote_connection_owned(&address_literal)
		version: remote_connection_owned(&version_literal)
	}
	first := connection_status.clone()
	second := connection_status.clone()
	assert first == second
	assert connection_status == first
	assert connection_status.address == address_literal
	assert connection_status.version == version_literal
}
