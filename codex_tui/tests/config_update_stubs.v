module tests

import codex_app_server_client
import codex_core

// STUB: tui/src/tests.rs::start_test_embedded_app_server uses the untranslated
// embedded transport fixture, with actual local config reads/writes for this test.
pub fn start_test_embedded_app_server(config codex_core.Config) !codex_app_server_client.AppServerRequestHandle {
	return codex_app_server_client.AppServerRequestHandle.config_update_embedded_fixture(&config)
}
