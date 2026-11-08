module codex_app_server_client

import codex_utils_absolute_path
import std_path

// STUB: Reexport of codex-app-server-transport::app_server_control_socket_path.
// Construct only the path: this API does not create or inspect a daemon socket.
pub fn app_server_control_socket_path(codex_home &std_path.Path) !codex_utils_absolute_path.AbsolutePathBuf {
	directory := codex_home.join(&preflight_daemon_directory_name)
	directory_path := std_path.Path.new(&directory)
	socket := directory_path.join(&preflight_daemon_socket_name)
	return codex_utils_absolute_path.from_absolute_path(&socket)
}

// STUB: Native path component borrowed by app-server transport.
const preflight_daemon_directory_name = 'app-server-control'
// STUB: Native path component borrowed by app-server transport.
const preflight_daemon_socket_name = 'app-server-control.sock'
