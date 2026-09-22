module codex_app_server

import codex_app_server_protocol
import codex_core

// STUB: exec_policy_config_warning is owned by app-server/lib.rs.
pub fn exec_policy_config_warning(error_value &codex_core.ExecPolicyError) codex_app_server_protocol.ConfigWarningNotification {
	return codex_app_server_protocol.ConfigWarningNotification{
		summary: 'Error parsing rules; custom rules not applied.'
		details: error_value.message.clone()
	}
}
